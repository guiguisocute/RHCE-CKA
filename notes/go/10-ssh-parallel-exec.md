# Go-10 SSH 远程执行与并行任务：写一个迷你 Ansible

> **轨道**：[Go](README.md) ｜ **运维场景**：对 50 台机器同时执行 `uptime`、批量收集 `df -h`、分批滚动重启服务——要限制并发、要有超时、单台失败不能拖垮整批 ｜ **建议用时**：4 h（第 13 周） ｜ **难度**：★★★
>
> **前置**：[Go-07 并发：goroutine、channel、context](07-concurrency-context.md) · [Go-09 配置、模板与 CLI](09-config-template-cli.md)
> **后续**：做完本节，可以接着学 [Go-11 容器化与部署](11-containerize-deploy.md)，把工具搬上 Kubernetes
> **关联**（跨轨道）：[RHCE-01 Ansible 架构](../rhce/01-ansible-architecture.md)（控制节点推送、forks）· [RHCE-02 Inventory 与 ansible.cfg](../rhce/02-inventory-and-config.md) · [RHCE-03 Ad-hoc 与模块](../rhce/03-adhoc-modules-docs.md) · [RHCSA-09 SSH 密钥](../rhcsa/09-security-firewalld-selinux.md)

## 1. 这个知识点在网络中的位置

学 RHCE 时你已经知道：Ansible 在控制节点上通过 SSH 连到受管节点执行任务，`forks` 决定同时连几台。这一节用 Go 把这个模型亲手实现一遍：

| Ansible | 本节的 Go 实现 |
|---|---|
| inventory 里的主机列表 | 命令行参数 `node1,node2,node3`（项目里改成读 INI / YAML，复用 [G9](09-config-template-cli.md)） |
| `remote_user`、`private_key_file` | `ssh.ClientConfig{User: ..., Auth: ssh.PublicKeys(signer)}` |
| `host_key_checking = True` | `knownhosts.New("~/.ssh/known_hosts")` |
| `forks = 5` | `errgroup.Group.SetLimit(5)` |
| `timeout`、单台失败继续跑其他主机 | `context.WithTimeout` + 每台主机单独记录错误 |
| `node1 \| CHANGED \| rc=0 >>` | 按输入顺序打印 `SUCCESS` / `FAILED` |

写完以后再看 Ansible，你会清楚它慢在哪里（每个任务都要传 Python 模块并执行），也会明白为什么 Ansible 强调幂等：远程执行本身没有「状态」概念，幂等全靠模块自己检查。

## 2. 核心概念

- **`golang.org/x/crypto/ssh`**：Go 官方维护的 SSH 实现（`x/` 是官方扩展库，不在标准库里，但由 Go 团队维护）。一条 TCP 连接上可以开多个 `Session`，每个 Session 执行一条命令。
- **主机密钥校验**：`ssh.InsecureIgnoreHostKey()` 相当于 `StrictHostKeyChecking=no`，网上很多示例这么写，但它会让中间人攻击变得可能。正确做法是用 `knownhosts` 包读 `~/.ssh/known_hosts`。
- **`errgroup`**（`golang.org/x/sync/errgroup`）：在 `sync.WaitGroup` 的基础上加了「收集第一个错误」和 `SetLimit` 限并发。这里我们**故意不返回错误**，因为一台机器连不上不应该取消其他机器，这和 Ansible 默认的行为一致。
- **超时**：`net.Dialer.DialContext` 控制连接阶段；命令执行阶段用 `select` 同时等结果和 `ctx.Done()`，超时就关闭连接。

## 3. 必会操作

```bash
go mod init example.com/gossh
go get golang.org/x/crypto@v0.58.0 golang.org/x/sync@v0.24.0   # 写作时实际拉到的版本
```

> 新版 `x/crypto` 要求较新的 Go（v0.58.0 要求 go 1.26）。`go get` 会自动把 `go.mod` 里的 `go` 版本抬高；`GOTOOLCHAIN=auto`（默认）时会自动下载对应工具链。用旧版 Go 的话，`go get golang.org/x/crypto@<旧版本>`，以 pkg.go.dev 上的版本说明为准。

核心代码（完整版 119 行，已用 `go test -race` 对着进程内的测试 SSH 服务端验证，包括超时分支）：

```go
// run 在一台主机上执行命令；addr 形如 "node1:22"
func run(ctx context.Context, cfg *ssh.ClientConfig, addr, cmd string) result {
	d := net.Dialer{Timeout: cfg.Timeout}
	conn, err := d.DialContext(ctx, "tcp", addr)
	if err != nil {
		return result{Host: addr, Err: err}
	}
	c, chans, reqs, err := ssh.NewClientConn(conn, addr, cfg)
	if err != nil {
		conn.Close()
		return result{Host: addr, Err: err}
	}
	client := ssh.NewClient(c, chans, reqs)
	defer client.Close()
	sess, err := client.NewSession()
	if err != nil {
		return result{Host: addr, Err: err}
	}
	defer sess.Close()

	type out struct {
		b   []byte
		err error
	}
	done := make(chan out, 1)
	go func() { b, err := sess.CombinedOutput(cmd); done <- out{b, err} }()
	select {
	case o := <-done:
		return result{Host: addr, Output: strings.TrimSpace(string(o.b)), Err: o.err}
	case <-ctx.Done(): // 超时：关掉连接，让卡住的远程命令立即返回
		client.Close()
		return result{Host: addr, Err: ctx.Err()}
	}
}
```

```go
// main 里的并发部分
results := make([]result, len(hosts)) // 每个 goroutine 只写自己的下标，不用加锁，输出顺序和输入一致
var g errgroup.Group
g.SetLimit(*forks)
for i, h := range hosts { // Go 1.22+：每轮循环的 i、h 都是新变量
	g.Go(func() error {
		results[i] = run(ctx, cfg, net.JoinHostPort(h, "22"), cmd)
		return nil // 单台失败不影响其他主机
	})
}
g.Wait()
```

```go
func clientConfig(user, keyPath string) (*ssh.ClientConfig, error) {
	key, err := os.ReadFile(keyPath)
	if err != nil {
		return nil, err
	}
	signer, err := ssh.ParsePrivateKey(key) // 有密码的私钥用 ssh.ParsePrivateKeyWithPassphrase
	if err != nil {
		return nil, fmt.Errorf("解析私钥: %w", err)
	}
	home, _ := os.UserHomeDir()
	hostKeyCB, err := knownhosts.New(filepath.Join(home, ".ssh", "known_hosts")) // 校验主机指纹
	if err != nil {
		return nil, fmt.Errorf("读取 known_hosts: %w", err)
	}
	return &ssh.ClientConfig{User: user, Auth: []ssh.AuthMethod{ssh.PublicKeys(signer)},
		HostKeyCallback: hostKeyCB, Timeout: 5 * time.Second}, nil
}
```

ssh-agent、未知主机的处理见 [P6 的提示](../../labs/go/projects.md#p6)。使用：

```bash
go build -o gossh .
./gossh -u automation -f 5 node1,node2,node3 'uptime'
./gossh -t 10s node1,node2 'sudo systemctl is-active httpd'
```

### 3.1 运维场景示例：分批滚动重启

Ansible 的 `serial: 2` 表示每次只处理 2 台，一批成功后再处理下一批。用本节的工具实现：

1. 把主机列表按 2 台切片：`for i := 0; i < len(hosts); i += 2 { batch := hosts[i:min(i+2, len(hosts))] }`。
2. 每批内部并行执行 `sudo systemctl restart httpd && systemctl is-active httpd`。
3. 本批有任何一台失败就停止，不再处理后面的批次（≈ `max_fail_percentage: 0`）。

这就是滚动更新的基本逻辑，到 CKA 你会在 Deployment 的 `maxUnavailable` 里再见到它。

## 4. 考试坑点

- **`sess.Stdout` 和 `sess.Stderr` 不要指向同一个 `bytes.Buffer`**：x/crypto/ssh 用两个 goroutine 分别拷贝 stdout 和 stderr，会产生数据竞争（写本节示例时用 `go test -race` 实际抓到过）。要合并输出就用 `CombinedOutput`，它内部加了锁。
- 不要用 `ssh.InsecureIgnoreHostKey()`。首次连接新机器时先 `ssh-keyscan node1 >> ~/.ssh/known_hosts`，和 Ansible 一样。
- 每个 Session 只能执行一条命令；要执行多条，开多个 Session，或者把命令写成 `cmd1 && cmd2`。
- 闭包捕获循环变量：Go 1.22 之前，`for _, h := range hosts` 里的 `h` 是同一个变量，goroutine 里会读到错的值。`go.mod` 的 `go` 指令要 ≥ 1.22 才是新语义。
- 远程命令要用 sudo 时，受管节点要配置免密 sudo（和 RHCE 实验环境一样），否则 sudo 会卡在等待密码，最后超时。

## 5. 动手练习

- 项目：[P6 gossh：并行 SSH 执行器](../../labs/go/projects.md#p6)（第 13 周）：读 INI inventory、支持组名、输出格式模仿 Ansible
- 进阶：加一个 `-copy src:dst` 选项，用 SSH Session 的 stdin 传文件（`cat > dst`），对应 Ansible 的 `copy` 模块。

**配套 LeetCode（第 13 周，[刷题计划](../../labs/go/leetcode-plan.md#w13)）**

- [21. 合并两个有序链表](https://leetcode.cn/problems/merge-two-sorted-lists/)：两台机器各自按时间排好序的日志，合成一份
- [23. 合并 K 个升序链表](https://leetcode.cn/problems/merge-k-sorted-lists/)（困难）：gossh 从 K 台机器收集日志后合并，用 `container/heap`（模板见 [G15](15-leetcode-in-go.md)）
- [215. 数组中的第K个最大元素](https://leetcode.cn/problems/kth-largest-element-in-an-array/)：找出磁盘占用第 K 高的主机

## 6. 官方文档（本仓库离线版 + 本机查法）

- Go by Example：[worker-pools.go](../../references/go/gobyexample/examples/worker-pools/worker-pools.go)、[context.go](../../references/go/gobyexample/examples/context/context.go)、[waitgroups.go](../../references/go/gobyexample/examples/waitgroups/waitgroups.go)
- 竞态检测：[race_detector.html](../../references/go/go-docs/articles/race_detector.html)
- 依赖管理：[managing-dependencies.md](../../references/go/go-docs/modules/managing-dependencies.md)
- 对照阅读：[RHCE-01 Ansible 架构](../rhce/01-ansible-architecture.md) 里的 forks、连接方式
- 本机：`go doc golang.org/x/crypto/ssh.Session`、`go doc golang.org/x/sync/errgroup.Group.SetLimit`（先在模块里 `go get` 才能查）

## 7. 自测清单

- [ ] 能不看资料写出：读私钥 → 建 ClientConfig → 连接 → 开 Session → 执行命令
- [ ] 能解释为什么不用 `InsecureIgnoreHostKey`，以及 known_hosts 里没有某台机器时会怎样
- [ ] 能用 `errgroup.SetLimit` 把并发限制在 N，并说出它和 Ansible `forks` 的对应关系
- [ ] 一台主机卡死时，工具能在超时后返回，不会一直挂着
- [ ] 能说出 `Stdout`/`Stderr` 共用一个 Buffer 为什么是数据竞争，并用 `-race` 复现
- [ ] 能实现 `serial: 2` 式的分批执行
