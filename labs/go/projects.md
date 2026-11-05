# Go 运维小项目（P1~P11）

每个项目都是一个**真能在实验室里用上的运维工具**，难度随 Go 知识点递增，题材紧跟当周的考试内容。Go 知识点见 [notes/go/](../../notes/go/README.md)，代码放 [`go/tools/`](../../go/tools/README.md)。

> 先自己写，卡住了再展开「提示」。提示只给关键 API 和思路，不给完整答案。

## 总览

| # | 项目 | 周 | 主要 Go 知识 | 对应考试内容 |
|---|---|---|---|---|
| [P1](#p1) | logstat：统计 SSH 登录失败 | W5 | [G5](../../notes/go/05-stdlib-files-text-exec.md) bufio、regexp、map、排序 | [RHCSA-01](../../notes/rhcsa/01-essential-tools.md)、[RHCSA-03](../../notes/rhcsa/03-operate-running-systems.md) 日志 |
| [P2](#p2) | fstab-lint：检查 /etc/fstab | W6 | [G5](../../notes/go/05-stdlib-files-text-exec.md)、[G6](../../notes/go/06-testing-tooling.md) fs.FS、表驱动测试 | [RHCSA-05](../../notes/rhcsa/05-file-systems-nfs-autofs.md) 挂载 |
| [P3](#p3) | svcwatch：批量检查 systemd 服务 | W7 | [G5](../../notes/go/05-stdlib-files-text-exec.md) os/exec、context 超时 | [systemd](../../notes/00-foundations/02-systemd-journald.md) |
| [P4](#p4) | portcheck：并发端口探测 | W9 | [G7](../../notes/go/07-concurrency-context.md) goroutine、限并发、超时 | [RHCSA-09](../../notes/rhcsa/09-security-firewalld-selinux.md) firewalld |
| [P5](#p5) | tmplgen：模板生成配置，幂等写入 | W12 | [G9](../../notes/go/09-config-template-cli.md) YAML、text/template、原子写 | [RHCE-07](../../notes/rhce/07-jinja2-templates.md) template 模块 |
| [P6](#p6) | gossh：并行 SSH 执行器 | W13 | [G10](../../notes/go/10-ssh-parallel-exec.md) x/crypto/ssh、并发 | [RHCE-01](../../notes/rhce/01-ansible-architecture.md)、[RHCE-03](../../notes/rhce/03-adhoc-modules-docs.md) ad-hoc |
| [P7](#p7) | depsort：服务依赖拓扑排序 | W14 | [G15](../../notes/go/15-leetcode-in-go.md) 图、拓扑排序 | [RHCE-08](../../notes/rhce/08-roles.md) role 依赖 |
| [P8](#p8) | certcheck：证书过期检查 | W15 | [G8](../../notes/go/08-net-http-tls.md) crypto/tls、crypto/x509 | [TLS/PKI](../../notes/00-foundations/06-tls-pki-basics.md)、[CKA-04](../../notes/cka/04-cluster-lifecycle.md) 证书 |
| [P9](#p9) | kpods：找出不健康的 Pod | W18~W19 | [G12](../../notes/go/12-client-go.md) client-go、informer | [CKA-15](../../notes/cka/15-troubleshooting.md) 排错 |
| [P10](#p10) | cert-exporter：证书过期 exporter | W20 | [G14](../../notes/go/14-observability-exporter.md)、[G11](../../notes/go/11-containerize-deploy.md) | [CKA-09](../../notes/cka/09-workloads.md) 探针、[CKA-10](../../notes/cka/10-scheduling.md) 污点 |
| [P11](#p11) | operator：StaticSite CRD + controller | W22 | [G13](../../notes/go/13-controller-operator.md) controller-runtime、kubebuilder | [CKA-08](../../notes/cka/08-extension-interfaces-crd.md) CRD / Operator |

## 目录约定

- 所有项目都在同一个 module `github.com/guiguisocute/RHCE-CKA/go` 里（`go/go.mod` 已存在），每个项目一个目录：`go/tools/<项目名>/`。
- 从模板复制起步：`cd go && cp -r tools/template tools/logstat`，步骤见 [template/README.md](../../go/tools/template/README.md)。
- 测试样例放 `go/tools/<项目名>/testdata/`；编译产物放 `go/bin/`（已忽略）。
- 例外：P11 由 kubebuilder 生成，自带 `go.mod`，是独立 module。

## 通用工程规范

所有项目都遵守下面几条，它们也是每个项目验收清单里的固定项。

1. **`run(ctx, args, stdout, stderr) error` 模式**：`main` 只负责接线，逻辑全部可测。模板已经写好。
2. **参数**：P1~P8 用标准库 `flag`；P9 之后参数变多，可以换成 [cobra](../../references/go/cobra-docs/user_guide.md)（见 [G9](../../notes/go/09-config-template-cli.md)）。
3. **输出**：结果写 stdout，日志用 `log/slog` 写 stderr；凡是给人看的表格，都提供 `--json` 给机器读。
4. **退出码**：`0` 成功；`1` 运行出错；`2` 参数错误；`3` 检查完成但发现问题。这样 shell 脚本、Ansible 的 `failed_when`、CI 都能直接判断。
5. **输入用接口**：解析函数接收 `io.Reader` 或 `fs.FS`，而不是文件路径。测试时传 `strings.NewReader(...)` 或 `fstest.MapFS`，不用碰真实系统。
6. **固定检查**：`gofmt -l .` 无输出、`go vet ./...` 无告警、`go test -race ./...` 通过、`CGO_ENABLED=0 go build` 能编译出静态二进制。
7. **Makefile（可选）**：`make test`、`make build`、`make lint`。写一个就会了，后面项目复制即可。

---

<a id="p1"></a>

## P1 logstat：统计 SSH 登录失败（W5）

**场景**：一台暴露在公网的 RHEL 每天被扫上千次 SSH。你想知道是谁在扫、在试哪些用户名，好决定要不要加 firewalld 规则或 fail2ban。`grep | awk | sort | uniq -c` 能做，但每次都要现拼命令，换成 journald 的 JSON 格式还得重写。

**功能需求**

```text
logstat [-format secure|journal-json] [-top 10] [-json] [文件...]
```

- 没有文件参数时读 stdin，所以两种用法都要支持：
  - `sudo logstat /var/log/secure`
  - `journalctl -u sshd -o json --since today | logstat -format journal-json`
- 识别这几类行（IP 用文档保留地址举例）：
  - `Failed password for root from 192.0.2.10 port 52314 ssh2`
  - `Failed password for invalid user admin from 192.0.2.10 port 52316 ssh2`
  - `Invalid user test from 198.51.100.7 port 40022`
- 输出两张表：按 IP 统计、按用户名统计，次数从高到低，次数相同按 IP / 用户名字典序。

```text
TOP IP            COUNT  USERS
192.0.2.10          42  root,admin,oracle
198.51.100.7        17  test

TOP USER  COUNT
root         30
admin        12
```

- `-json` 时输出 `{"by_ip":[{"ip":"192.0.2.10","count":42,"users":["admin","oracle","root"]}],"by_user":[...]}`。

**验收标准**

- [ ] 两种输入格式都能解析，不认识的行直接跳过，不报错
- [ ] 有表驱动测试，覆盖：普通失败、invalid user、IPv6 地址、无关行、空输入
- [ ] 排序稳定：同样的输入，输出永远一样（测试里断言整个输出）
- [ ] 100 MB 的日志也不会爆内存（逐行处理，不 `ReadAll`）
- [ ] `gofmt`、`go vet` 无告警，`go test -race` 通过
- [ ] `CGO_ENABLED=0 go build` 能编译出静态二进制，`scp` 到 RHEL 虚拟机上直接运行

**用到的 Go 知识**：[G3 map 与 struct](../../notes/go/03-composite-types.md) · [G5 bufio、regexp、encoding/json](../../notes/go/05-stdlib-files-text-exec.md) · LeetCode [347、692、811](leetcode-plan.md)（都是「计数 + Top K」）

**和考试的关联**：RHCSA 要求会用 `journalctl` 和 `/var/log` 定位问题（[RHCSA-03](../../notes/rhcsa/03-operate-running-systems.md)），也要会 `grep`/正则（[RHCSA-01](../../notes/rhcsa/01-essential-tools.md)）。做完这个项目，你对 journald 的字段会熟很多。

<details>
<summary>提示</summary>

- 逐行读：`sc := bufio.NewScanner(r)`。journald 的 JSON 行可能很长，先 `sc.Buffer(make([]byte, 0, 64*1024), 1<<20)` 把上限调到 1 MiB，否则超长行会报 `bufio.Scanner: token too long`。
- 正则只编译一次，放在包级变量，然后用 `failedRe.FindStringSubmatch(line)` 取分组：

```go
var failedRe = regexp.MustCompile(`Failed password for (invalid user )?(\S+) from (\S+) port \d+`)
```

- journald JSON：每行一个对象，日志正文在 `MESSAGE` 字段。MESSAGE 含非 UTF-8 字节时，journald 会把它输出成数字数组而不是字符串，所以先用 `json.RawMessage` 接住，再判断是字符串还是数组：

```go
type journalEntry struct {
	Message json.RawMessage `json:"MESSAGE"`
}
```

- 计数：`map[string]*ipStat`。用户名集合可以用 `map[string]struct{}`。
- 排序（Go 1.21+）：`slices.SortFunc(list, func(a, b ipStat) int { return cmp.Or(cmp.Compare(b.Count, a.Count), cmp.Compare(a.IP, b.IP)) })`。
- 对齐输出：`text/tabwriter`。

</details>

**进阶挑战**

- 加 `-since 1h`：只统计最近一小时（`/var/log/secure` 的时间戳不带年份，想想怎么处理跨年）。
- 加 `-threshold 20`：输出超过阈值的 IP，并顺带打印对应的 `firewall-cmd --add-rich-rule='rule family="ipv4" source address="192.0.2.10" reject'` 命令（只打印，不执行）。

---

<a id="p2"></a>

## P2 fstab-lint：检查 /etc/fstab（W6）

**场景**：RHCSA 最可怕的事故之一：`/etc/fstab` 写错一个 UUID，重启直接进 emergency 模式。`mount -a` 只能发现部分问题。这个工具在你重启**之前**把常见错误全查出来。

**功能需求**

```text
fstab-lint [-root /] [-json] [fstab 路径，默认 /etc/fstab]
```

逐行检查，报告格式为 `文件:行号: 级别: 说明`：

```text
/etc/fstab:9: error: UUID=3f1c... 不存在（/dev/disk/by-uuid 下找不到）
/etc/fstab:10: error: 挂载点 /data 不存在
/etc/fstab:11: error: 字段数为 3，至少需要 4 个（设备 挂载点 类型 选项）
/etc/fstab:12: warn: 文件系统类型 "xfss" 不在 /proc/filesystems 中，可能拼错了
/etc/fstab:14: error: 挂载点 /data 与第 10 行重复
/etc/fstab:15: warn: NFS 挂载没有 _netdev 选项，网络未就绪时可能拖慢启动
```

- 跳过空行和 `#` 注释行；swap 行的挂载点是 `none` 或 `swap`，不检查目录。
- 设备可以写成 `UUID=`、`LABEL=`、`PARTUUID=`、`/dev/...`，或者 NFS 的 `host:/path`。
- 有 error 时退出码为 `3`；只有 warn 时退出码为 `0`，加 `-strict` 后 warn 也算失败。

**验收标准**

- [ ] 上面列出的 6 类问题都能查出来，每类至少一个测试用例
- [ ] 测试不依赖本机真实的 `/dev/disk`：用 `-root` 指向 `testdata/`，或者把文件系统抽象成 `fs.FS`
- [ ] 错误信息带行号，可以直接 `vim +行号 /etc/fstab`
- [ ] 在 RHEL 虚拟机上故意写坏 fstab，工具能查出来；改对后再运行，输出为空、退出码为 0
- [ ] `gofmt`、`go vet` 无告警，`go test -race` 通过；`CGO_ENABLED=0` 静态编译

**用到的 Go 知识**：[G5 os、io/fs、strings.Fields](../../notes/go/05-stdlib-files-text-exec.md) · [G6 表驱动测试、testdata 目录、testing/fstest](../../notes/go/06-testing-tooling.md)

**和考试的关联**：[RHCSA-05 文件系统与挂载](../../notes/rhcsa/05-file-systems-nfs-autofs.md)、[RHCSA-04 LVM](../../notes/rhcsa/04-local-storage-lvm.md)。字段含义见 `man 5 fstab`，系统自带的对照工具是 `findmnt --verify`，可以和你的输出对比。

<details>
<summary>提示</summary>

- `strings.Fields(line)` 按任意空白切分；`man 5 fstab` 规定第 5、6 列省略时按 0 处理，所以 4~6 列都合法。
- 把「根目录」抽象出来：`func lint(fsys fs.FS, fstab io.Reader) []Finding`。运行时传 `os.DirFS(root)`，测试时传 `fstest.MapFS{"dev/disk/by-uuid/abcd": {}, "data": {Mode: fs.ModeDir}}`。注意 `fs.FS` 的路径不带开头的 `/`。
- 设备是否存在：`UUID=xxx` 对应 `dev/disk/by-uuid/xxx`，`LABEL=` 对应 `dev/disk/by-label/`（标签里的空格在这里会写成 `\x20`）。`/dev/disk/by-uuid/` 下是软链接，用 `fs.Stat` 检查是否存在即可。
- 已知文件系统类型：解析 `/proc/filesystems`（格式是 `nodev\tproc` 或 `\txfs`），再补上 `swap`、`nfs`、`nfs4`、`cifs` 这些不一定已加载的类型。
- 重复挂载点：`map[string]int` 记录挂载点第一次出现的行号。

</details>

**进阶挑战**

- 检查 `x-systemd.automount`、`nofail` 等选项的拼写。
- 加 `-fix-suggest`：发现设备写的是 `/dev/vdb1` 时，提示改成对应的 `UUID=...`（读 `/dev/disk/by-uuid` 的软链接反查）。

---

<a id="p3"></a>

## P3 svcwatch：批量检查 systemd 服务（W7）

**场景**：一台机器上有十几个服务必须开机自启并保持运行（sshd、chronyd、firewalld、httpd……）。考试最后要逐个确认，平时巡检也一样。这个工具一次查完，输出一张表。

**功能需求**

```text
svcwatch [-f services.txt] [-timeout 3s] [-json] [-fix] [服务名...]
```

```text
UNIT        LOAD    ACTIVE    SUB      ENABLED   OK
sshd        loaded  active    running  enabled   ✓
chronyd     loaded  active    running  enabled   ✓
httpd       loaded  inactive  dead     disabled  ✗
nosuchsvc   not-found  inactive  dead  -         ✗
```

- 服务名可以来自参数，也可以来自文件（每行一个，`#` 开头为注释）。
- 「OK」的标准：已加载、active、enabled（`static` 的服务不要求 enabled）。
- 有不 OK 的服务时退出码为 `3`。
- `-fix`：对不 OK 的服务执行 `systemctl enable --now <unit>`。必须是 root，否则直接报错退出（退出码 `2`）。执行完要重新检查一遍再输出。

**验收标准**

- [ ] 每次调用 `systemctl` 都有超时（`exec.CommandContext`），卡住的命令不会拖死整个工具
- [ ] 测试不调用真实的 `systemctl`：把「执行命令」抽象成函数或接口，测试里注入假的输出
- [ ] 能正确处理不存在的服务（`LoadState=not-found`）
- [ ] `-fix` 在非 root 下拒绝执行
- [ ] `gofmt`、`go vet` 无告警，`go test -race` 通过；`CGO_ENABLED=0` 静态编译

**用到的 Go 知识**：[G5 os/exec、bufio](../../notes/go/05-stdlib-files-text-exec.md) · [G7 context 超时](../../notes/go/07-concurrency-context.md)（先用 `context.WithTimeout`，并发留到 P4）

**和考试的关联**：[systemd 与 journald](../../notes/00-foundations/02-systemd-journald.md)、[RHCSA-03](../../notes/rhcsa/03-operate-running-systems.md)。RHCSA 的每道题都隐含「服务要 enable」，这个工具就是你考前最后一遍检查的自动化版本。

<details>
<summary>提示</summary>

- `systemctl is-active` 和 `is-enabled` 遇到非 active / 非 enabled 会返回**非 0 退出码**。这时 `cmd.Output()` 会同时返回输出和 `*exec.ExitError`，不能一看到 err 就当失败处理。
- 更好解析的写法：`systemctl show <unit> --property=LoadState,ActiveState,SubState,UnitFileState`，输出是 `Key=Value` 行，退出码通常为 0。一次可以传多个 unit，结果之间用空行分隔。具体行为以 `man systemctl` 为准。
- 可注入的执行器：`type runner func(ctx context.Context, name string, args ...string) ([]byte, error)`。生产代码传 `func(ctx ...) { return exec.CommandContext(ctx, name, args...).Output() }`，测试传一个返回固定字符串的函数。
- 判断 root：`os.Geteuid() == 0`。

</details>

**进阶挑战**

- 不再调用 `systemctl`，改用 D-Bus 直接问 systemd（`github.com/coreos/go-systemd/v22/dbus`），比较两种做法的速度。
- 加 `-watch 10s`：每 10 秒检查一次，状态变化时打印一行日志。

---

<a id="p4"></a>

## P4 portcheck：并发端口探测（W9）

**场景**：配完 firewalld 和服务之后，你想从**另一台机器**确认端口真的通了。几十个 `host:port` 一个个 `nc -zv` 太慢；而且你还想知道「不通」到底是被防火墙拒了、被丢了，还是服务根本没监听。

**功能需求**

```text
portcheck [-c 20] [-timeout 2s] [-json] [-f targets.txt] [host:port...]
```

targets.txt 支持 inventory 风格的分组：

```ini
[web]
192.0.2.11:80
192.0.2.11:443

[db]
192.0.2.21:5432
```

```text
GROUP  TARGET            STATUS  LATENCY  DETAIL
web    192.0.2.11:80     open    0.8ms
web    192.0.2.11:443    closed  0.6ms    connection refused：主机可达，但端口没有服务在监听
db     192.0.2.21:5432   filtered 2.0s    timeout：可能被防火墙 DROP，或网络不通
web    192.0.2.12:80     filtered 0.5ms   no route to host：常见于 firewalld 默认的 reject 规则
```

- `-c` 限制同时进行的连接数，`-timeout` 是单个连接的超时。
- 输出顺序和输入顺序一致（并发不能把顺序打乱）。
- 有非 open 的目标时退出码为 `3`。

**验收标准**

- [ ] 同时进行的连接数永远不超过 `-c`（写一个测试，用假的 dialer 统计最大并发数）
- [ ] 1000 个目标、`-c 50`、全部超时时，总耗时约为 `1000/50 × timeout`，而不是 `1000 × timeout`
- [ ] Ctrl+C 能立刻停下（ctx 取消后不再发起新连接）
- [ ] `go test -race` 通过（并发写结果切片时没有数据竞争）
- [ ] `gofmt`、`go vet` 无告警；`CGO_ENABLED=0` 静态编译
- [ ] 在实验室验证三种结果：服务停掉（refused）、`firewall-cmd --remove-service` 后（reject）、`firewall-cmd --set-target=DROP` 后（timeout）。具体表现以你的 firewalld 配置为准

**用到的 Go 知识**：[G7 goroutine、sync.WaitGroup、限并发、context](../../notes/go/07-concurrency-context.md) · [G8 net.Dialer](../../notes/go/08-net-http-tls.md) · LeetCode [239、622](leetcode-plan.md)

**和考试的关联**：[RHCSA-09 防火墙](../../notes/rhcsa/09-security-firewalld-selinux.md)、[RHCSA-07 网络](../../notes/rhcsa/07-networking-nmcli.md)。CKA 里排查 Service / NetworkPolicy 时，同样要区分这三种「不通」（[CKA-15](../../notes/cka/15-troubleshooting.md)）。

<details>
<summary>提示</summary>

- 拨号：`d := net.Dialer{Timeout: timeout}`，`conn, err := d.DialContext(ctx, "tcp", target)`；拼地址用 `net.JoinHostPort(host, port)`，这样 IPv6 也能正确加上方括号。
- 区分错误：`errors.Is(err, syscall.ECONNREFUSED)`、`errors.Is(err, syscall.EHOSTUNREACH)`；超时用 `var ne net.Error; errors.As(err, &ne) && ne.Timeout()`。
- 限并发的两种写法：带缓冲的 channel 当信号量（`sem := make(chan struct{}, c)`），或者 `golang.org/x/sync/errgroup` 的 `g.SetLimit(c)`。
- 保持顺序：先建好 `results := make([]Result, len(targets))`，每个 goroutine 只写自己的下标 `results[i]`，这样不需要加锁。
- 可测试：把拨号抽象成 `type dialFunc func(ctx context.Context, network, addr string) (net.Conn, error)`。

</details>

**进阶挑战**

- 加 `-udp`，探测 UDP 端口（想想为什么 UDP 的「open」很难判断）。
- 加 `-http`：对 open 的端口再发一个 `HEAD /`，顺便拿到状态码。

---

<a id="p5"></a>

## P5 tmplgen：模板生成配置，幂等写入（W12）

**场景**：这就是 Ansible `template` 模块做的事：变量文件 + 模板 → 配置文件，内容没变就不动它（`ok`），变了才写（`changed`）。自己实现一遍，你会真正理解「幂等」和 `--check` / `--diff`。

**功能需求**

```text
tmplgen -vars vars.yaml -template nginx.conf.tmpl -dest /etc/nginx/conf.d/app.conf [-mode 0644] [-check] [-diff]
```

vars.yaml：

```yaml
server_name: web01.lab.local
http_port: 8080
upstreams:
  - 192.0.2.21:8080
  - 192.0.2.22:8080
```

nginx.conf.tmpl（Go 模板语法，和 Helm 的模板是同一套）：

```text
upstream app {
{{- range .upstreams }}
    server {{ . }};
{{- end }}
}
server {
    listen {{ .http_port }};
    server_name {{ .server_name }};
}
```

```text
changed: /etc/nginx/conf.d/app.conf
```

- 目标文件不存在或内容不同 → 写入，输出 `changed`；内容相同 → 不写，输出 `ok`。
- `-check`：只报告「会不会改」，不真的写（对应 `ansible-playbook --check`）。
- `-diff`：把新旧内容的差异以 `-`/`+` 行打印出来（对应 `--diff`）。
- 模板里引用了不存在的变量时直接报错，而不是渲染成 `<no value>`。

**验收标准**

- [ ] 连续运行两次，第二次一定是 `ok`，且目标文件的修改时间不变
- [ ] 写入是原子的：写到一半被 kill，目标文件要么是旧内容，要么是新内容，不会只有一半
- [ ] 保留指定的权限（`-mode`），默认 `0644`
- [ ] 缺变量时报错并指出变量名
- [ ] 有表驱动测试，覆盖：首次生成、内容不变、内容变化、`-check` 不写文件、缺变量
- [ ] `gofmt`、`go vet` 无告警，`go test -race` 通过；`CGO_ENABLED=0` 静态编译

**用到的 Go 知识**：[G9 YAML、text/template](../../notes/go/09-config-template-cli.md) · [G5 os.CreateTemp、os.Rename、crypto/sha256](../../notes/go/05-stdlib-files-text-exec.md) · LeetCode [1143 最长公共子序列](leetcode-plan.md)（`-diff` 的核心算法）

**和考试的关联**：[RHCE-07 Jinja2 模板](../../notes/rhce/07-jinja2-templates.md)、[RHCE-04 playbook 与幂等](../../notes/rhce/04-playbooks.md)、[RHCE-06 handler](../../notes/rhce/06-loops-conditions-errors.md)。到了 CKA，[Helm](../../notes/cka/07-helm-kustomize.md) 用的就是 Go 的 `text/template`。

<details>
<summary>提示</summary>

- YAML：`go get go.yaml.in/yaml/v3`，`yaml.Unmarshal(data, &vars)`，`vars` 用 `map[string]any`。
- 缺变量报错：`template.New(name).Option("missingkey=error").Parse(text)`。对 map 类型的数据，这个选项会让缺 key 变成执行错误。
- 先渲染到 `bytes.Buffer`，再和旧文件比较：`bytes.Equal(newContent, oldContent)` 就够了。`sha256.Sum256` 适合把哈希打印出来给人看。
- 原子写：在**目标目录**里 `os.CreateTemp(dir, ".tmplgen-*")` → 写入 → `f.Sync()` → `f.Chmod(mode)` → `f.Close()` → `os.Rename(tmp, dest)`。同一文件系统内 rename 是原子的。
- 为什么临时文件要建在目标目录：如果在 `/tmp` 生成再移动过去，文件会带着 `/tmp` 的 SELinux 标签（`tmp_t`），nginx/httpd 可能读不了。这正是 RHCSA 里要用 `restorecon` 修的问题（[RHCSA-09](../../notes/rhcsa/09-security-firewalld-selinux.md)）。
- `-diff`：按行切分后做最长公共子序列（LCS），不在 LCS 里的旧行打 `-`、新行打 `+`。先实现 O(n·m) 的 DP，够用了。

</details>

**进阶挑战**

- 加 `-notify "systemctl reload nginx"`：只有 `changed` 时才执行，相当于 Ansible 的 handler。
- 加 `-backup`：写入前把旧文件备份成 `app.conf.20261105T101500`（Ansible `backup: yes`）。
- 支持一次处理多个模板（读一个 YAML 清单），输出 `ok=3 changed=1` 汇总。

---

<a id="p6"></a>

## P6 gossh：并行 SSH 执行器（W13）

**场景**：`ansible web -m command -a uptime` 背后做的事：读 inventory → 并行 SSH 到每台主机 → 收集结果 → 按主机汇总。自己写一个，`forks`、`become`、`UNREACHABLE` 这些概念都会变得具体。

**功能需求**

```text
gossh -i inventory -l web [-u automation] [-k ~/.ssh/id_ed25519] [-f 5] [-t 30s] [-become] "命令"
```

inventory（Ansible INI 格式的子集）：

```ini
[web]
node1 ansible_host=192.0.2.11
node2

[db]
node3 ansible_user=dbadmin ansible_port=2222
```

```text
node1 | CHANGED | rc=0 >>
 10:15:01 up 3 days,  2:11,  1 user,  load average: 0.00, 0.01, 0.05
node2 | FAILED | rc=127 >>
bash: uptimee: command not found
node3 | UNREACHABLE! => dial tcp 192.0.2.23:2222: i/o timeout

ok=1 failed=1 unreachable=1
```

- `-l` 选组或主机名（`all` 表示全部）；`-f` 是并发数（Ansible 的 `forks` 默认就是 5）；`-t` 是每台主机的超时。
- `-become`：在命令前加 `sudo -n`（要求受管节点配了免密 sudo，和 [RHCE 实验环境](../rhce/00-lab-setup.md) 一致）。
- 全部成功时退出码为 `0`，有失败或不可达时为 `3`。

**验收标准**

- [ ] **默认校验主机密钥**：用 `~/.ssh/known_hosts`，遇到未知主机时报错并提示怎么处理。只有显式加 `-insecure-ignore-host-key` 才跳过，并打印醒目的警告
- [ ] 支持私钥文件和 ssh-agent 两种认证方式
- [ ] 同时连接数永远不超过 `-f`（用假的执行器写测试验证）
- [ ] 单台主机超时不会拖住其他主机；Ctrl+C 能中断所有连接
- [ ] 输出按 inventory 顺序排列，不受谁先完成影响
- [ ] `gofmt`、`go vet` 无告警，`go test -race` 通过；`CGO_ENABLED=0` 静态编译

**用到的 Go 知识**：[G10 x/crypto/ssh](../../notes/go/10-ssh-parallel-exec.md) · [G7 并发、context](../../notes/go/07-concurrency-context.md) · [G9 解析 inventory](../../notes/go/09-config-template-cli.md)

**和考试的关联**：[RHCE-01 Ansible 架构](../../notes/rhce/01-ansible-architecture.md)、[RHCE-02 inventory](../../notes/rhce/02-inventory-and-config.md)、[RHCE-03 ad-hoc](../../notes/rhce/03-adhoc-modules-docs.md)。inventory 语法见 [Ansible 官方文档](../../references/rhce/ansible-docs/inventory_guide/intro_inventory.rst)。

<details>
<summary>提示</summary>

- 依赖：`go get golang.org/x/crypto`，用 `golang.org/x/crypto/ssh`、`.../ssh/knownhosts`、`.../ssh/agent`。
- 主机密钥：`cb, err := knownhosts.New(filepath.Join(home, ".ssh", "known_hosts"))`，赋给 `ssh.ClientConfig.HostKeyCallback`。未知主机会返回 `*knownhosts.KeyError`，它的 `Want` 为空，表示 known_hosts 里没有这台主机。这时提示用户先手动 `ssh` 一次，或者用 `ssh-keyscan` 核对指纹后加入。
- 私钥：`signer, err := ssh.ParsePrivateKey(pemBytes)`，然后 `ssh.PublicKeys(signer)`。ssh-agent：连接 `SSH_AUTH_SOCK` 这个 unix socket，`agent.NewClient(conn)`，再用 `ssh.PublicKeysCallback(ag.Signers)`。
- `ssh.Dial` 不接受 ctx。想让 ctx 生效，就先用 `net.Dialer.DialContext` 建立 TCP 连接，再 `ssh.NewClientConn(conn, addr, cfg)` → `ssh.NewClient(c, chans, reqs)`。
- 执行：`sess, _ := client.NewSession()`，`sess.Stdout = &out`，`err := sess.Run(cmd)`。命令非 0 退出时，`var ee *ssh.ExitError; errors.As(err, &ee)` 后用 `ee.ExitStatus()` 取退出码。超时后关闭 session 和 client，比发信号可靠。
- 可测试：`type executor interface{ Run(ctx context.Context, h Host, cmd string) Result }`，并发控制和输出格式都能用假实现测。

</details>

**进阶挑战**

- 加 `-m copy -src a -dest b`：用 SFTP（`github.com/pkg/sftp`）把文件推到所有主机。
- 加 `-o json`，输出格式模仿 `ansible-playbook` 的 JSON callback。
- 读取 `ansible.cfg` 里的 `remote_user`、`forks`、`private_key_file`。

---

<a id="p7"></a>

## P7 depsort：服务依赖拓扑排序（W14）

**场景**：一套应用由 web、app、db、cache、mq 组成，启动必须先启依赖。你想知道「哪些可以并行启动、分几批」，还想在写错依赖（出现环）时立刻发现。systemd 的 `After=`/`Requires=`、Ansible role 的 `dependencies`、Helm chart 依赖、Kubernetes 的 initContainers，背后都是同一个问题。

**功能需求**

```text
depsort [-reverse] [-json] services.yaml
```

```yaml
web: [app, cache]
app: [db, mq]
db: []
cache: []
mq: []
```

```text
第 1 批（可并行）：cache db mq
第 2 批：app
第 3 批：web
```

- `-reverse` 输出停止顺序（倒过来）。
- 发现环：`错误：发现循环依赖 app -> db -> app`，退出码为 `3`。
- 依赖了一个没定义的服务：报错并指出是谁依赖了它。
- 同一批内按名字排序，保证输出稳定。

**验收标准**

- [ ] 拓扑排序正确，分批（同一层）输出
- [ ] 能检测环，并打印出**一条具体的环路径**，而不只是「有环」
- [ ] 有表驱动测试：无依赖、链式、菱形依赖、自环、长环、未定义依赖
- [ ] `gofmt`、`go vet` 无告警，`go test -race` 通过；`CGO_ENABLED=0` 静态编译

**用到的 Go 知识**：[G15 图与拓扑排序的 Go 写法](../../notes/go/15-leetcode-in-go.md) · [G3 map、slice](../../notes/go/03-composite-types.md) · [G9 YAML](../../notes/go/09-config-template-cli.md) · LeetCode [207、210](leetcode-plan.md)（本项目就是这两题的工程版）

**和考试的关联**：[RHCE-08 roles 依赖](../../notes/rhce/08-roles.md)、[systemd](../../notes/00-foundations/02-systemd-journald.md)（`systemctl list-dependencies`、`systemd-analyze critical-chain`）、[CKA-07 Helm](../../notes/cka/07-helm-kustomize.md)。

<details>
<summary>提示</summary>

- Kahn 算法：统计每个节点的入度（它依赖了几个服务）→ 入度为 0 的是第 1 批 → 「删掉」这一批，更新依赖它们的节点的入度 → 新的入度为 0 的就是下一批。
- 边的方向：`app 依赖 db` 画成 `db → app`，也就是「db 启动后才能启动 app」。需要一个反向邻接表 `dependents[db] = [app]`。
- 有环的判断：所有批次处理完后还有节点没输出，就说明有环。要找出具体路径，对剩下的节点做 DFS 三色标记（白/灰/黑），碰到灰色节点时沿着递归栈回溯即可。
- 稳定输出：每批 `slices.Sort(batch)`。

</details>

**进阶挑战**

- 直接读 systemd 的 unit 文件（`/usr/lib/systemd/system/*.service`）里的 `Requires=` 和 `After=`，画出真实的启动依赖，和 `systemd-analyze critical-chain` 对比。
- 输出 Graphviz 的 dot 格式：`depsort -dot services.yaml | dot -Tsvg > deps.svg`。

---

<a id="p8"></a>

## P8 certcheck：证书过期检查（W15）

**场景**：证书过期是最常见的「凌晨三点事故」之一。kubeadm 集群的证书默认一年过期，过期后 apiserver 直接不可用，CKA 也会考 `kubeadm certs check-expiration` 和证书续期。这个工具同时检查远程 TLS 服务和本地证书文件。

**功能需求**

```text
certcheck [-warn-days 30] [-crit-days 7] [-ca ca.crt] [-insecure] [-json] 目标...
```

目标可以是 `host:port`，也可以是本地 PEM 文件：

```bash
certcheck -ca /etc/kubernetes/pki/ca.crt 192.0.2.11:6443 /etc/kubernetes/pki/*.crt
```

```text
TARGET                                  SUBJECT                   NOT_AFTER    DAYS  STATUS
192.0.2.11:6443                         CN=kube-apiserver         2027-11-04    364  OK
/etc/kubernetes/pki/apiserver.crt       CN=kube-apiserver         2027-11-04    364  OK
/etc/kubernetes/pki/front-proxy-ca.crt  CN=front-proxy-ca         2036-11-02   3649  OK
web.lab.local:443                       CN=web.lab.local          2026-11-10      5  CRIT
```

- 有 WARN 或 CRIT 时退出码为 `3`；连接失败或证书解析失败记为 ERROR。
- 一个 PEM 文件里可能有多张证书（证书链），每张都要检查。
- 默认做完整的证书校验；校验失败（比如自签名）要单独报告。`-insecure` 只用来「看一眼过期时间」，并且要在输出里标明「未校验」。

**验收标准**

- [ ] 远程和本地两种目标都支持；IPv6 地址能正确处理
- [ ] 测试不访问网络：用 `httptest.NewTLSServer` 起一个本地 TLS 服务；本地证书用测试里现场生成的自签名证书（`crypto/x509.CreateCertificate`）
- [ ] 天数计算有测试（过期、今天到期、刚好在阈值上）
- [ ] 在 kubeadm 集群的控制平面节点上运行，结果和 `kubeadm certs check-expiration` 一致
- [ ] `gofmt`、`go vet` 无告警，`go test -race` 通过；`CGO_ENABLED=0` 静态编译

**用到的 Go 知识**：[G8 crypto/tls、crypto/x509、encoding/pem](../../notes/go/08-net-http-tls.md) · [G7 并发检查多个目标](../../notes/go/07-concurrency-context.md) · LeetCode [295、703](leetcode-plan.md)

**和考试的关联**：[TLS/PKI 基础](../../notes/00-foundations/06-tls-pki-basics.md)、[CKA-04 集群生命周期](../../notes/cka/04-cluster-lifecycle.md)。证书管理的官方文档：[kubeadm-certs](../../references/cka/kubernetes-docs/tasks/administer-cluster/kubeadm/kubeadm-certs.md)。

<details>
<summary>提示</summary>

- `time.ParseDuration` 不支持 `d`（天）这个单位，所以参数用 `-warn-days 30` 这种整数，而不是 `-warn 30d`。
- 远程：`d := tls.Dialer{NetDialer: &net.Dialer{Timeout: t}, Config: &tls.Config{ServerName: host, RootCAs: pool}}`，`conn, err := d.DialContext(ctx, "tcp", addr)`，然后 `conn.(*tls.Conn).ConnectionState().PeerCertificates[0]`。
- 自定义 CA：`pool := x509.NewCertPool(); pool.AppendCertsFromPEM(caPEM)`。kubeadm 的 apiserver 证书是集群 CA 签发的，不带 `-ca` 时校验失败是正常的。
- 本地文件：循环调用 `block, rest := pem.Decode(data)`，只处理 `block.Type == "CERTIFICATE"` 的块，再 `x509.ParseCertificate(block.Bytes)`。
- 剩余天数：`int(time.Until(cert.NotAfter).Hours() / 24)`。测试时把「现在」作为参数传进去，别在函数里直接调用 `time.Now()`。

</details>

**进阶挑战**

- 读取 kubeconfig（如 `/etc/kubernetes/admin.conf`），检查里面 `client-certificate-data` 内嵌的客户端证书。
- 检查证书的 SAN 是否包含你访问用的主机名或 IP。

---

<a id="p9"></a>

## P9 kpods：找出不健康的 Pod（W18~W19）

**场景**：CKA 的排错题一上来就是「集群里有东西坏了」。`kubectl get pods -A` 一屏几百行，你要的是：哪些 Pod 有问题、问题是什么。这个工具用 client-go 直接问 apiserver，把原因整理好给你。

**功能需求**

```text
kpods [--context ctx] [-n ns | -A] [--restarts 5] [--watch] [--json]
```

```text
NAMESPACE  NAME                    PHASE    PROBLEM                                                    RESTARTS  NODE
shop       api-7d9f8b6c5d-x2k8p    Pending  Unschedulable: 0/3 nodes are available: 3 Insufficient cpu  0         -
shop       web-5c6d7f8b9-qq2lm     Running  container web: CrashLoopBackOff (last: Error, exit 1)     12        worker1
default    tools                   Pending  container tools: ImagePullBackOff                          0         worker2
kube-system coredns-5d78c9869d-abcd Running container coredns: not ready（就绪探针失败）              0         cp1
```

- 「有问题」的定义：Phase 不是 Running/Succeeded；或者有容器处于 waiting 状态；或者有容器 not ready；或者重启次数 ≥ `--restarts`。
- 每个问题都要给出 reason，有 message 时也带上。init 容器也要检查。
- `--context`：切换 kubeconfig 里的 context（和 CKA 考试一样，每题都先切 context）。
- `--watch`：持续运行，Pod 状态变坏或恢复时各打印一行。

**验收标准**

- [ ] 支持 `KUBECONFIG` 环境变量、`~/.kube/config`、`--context`；在集群内运行时自动使用 ServiceAccount
- [ ] 核心判断函数 `diagnose(pod *corev1.Pod) []Problem` 是纯函数，用表驱动测试覆盖：Pending 不可调度、ImagePullBackOff、CrashLoopBackOff、OOMKilled、not ready、Evicted、init 容器失败
- [ ] 至少一个测试用 client-go 的 fake clientset 跑完整的 list 流程
- [ ] 用 [CKA practice-set](../cka/practice-set-1.md) 里的排错题制造故障，工具能把它们都列出来
- [ ] `gofmt`、`go vet` 无告警，`go test -race` 通过；`CGO_ENABLED=0` 静态编译

**用到的 Go 知识**：[G12 client-go](../../notes/go/12-client-go.md) · [G4 接口](../../notes/go/04-methods-interfaces-generics.md)（`kubernetes.Interface` 让 fake 客户端可以替换真客户端）· [G7 context](../../notes/go/07-concurrency-context.md)

**和考试的关联**：[CKA-15 排错](../../notes/cka/15-troubleshooting.md)、[CKA-02 kubectl](../../notes/cka/02-kubectl-efficiency.md)、[CKA-06 RBAC](../../notes/cka/06-rbac.md)（在集群里运行时，需要一个能 get/list/watch pods 的 ClusterRole）。

<details>
<summary>提示</summary>

- 依赖：`go get k8s.io/client-go@v0.37.2 k8s.io/apimachinery@v0.37.2`，版本尽量和集群一致。
- kubeconfig 加载（自动处理 `KUBECONFIG` 和默认路径）：
  `loader := clientcmd.NewNonInteractiveDeferredLoadingClientConfig(clientcmd.NewDefaultClientConfigLoadingRules(), &clientcmd.ConfigOverrides{CurrentContext: ctxName})`，然后 `cfg, err := loader.ClientConfig()`。集群内运行用 `rest.InClusterConfig()`。
- 列出 Pod：`cs.CoreV1().Pods(ns).List(ctx, metav1.ListOptions{})`，`ns` 传 `metav1.NamespaceAll`（空字符串）表示所有 namespace。Pod 很多时用 `Limit` 和 `Continue` 分页。
- 原因在哪：
  - 调度失败：`pod.Status.Conditions` 里 `Type == PodScheduled` 且 `Status == False` 的那一项，看它的 `Reason`（如 `Unschedulable`）和 `Message`。
  - 容器：`pod.Status.ContainerStatuses[i]` 的 `State.Waiting.Reason`（`CrashLoopBackOff`、`ImagePullBackOff`、`ErrImagePull`、`CreateContainerConfigError`）、`LastTerminationState.Terminated.Reason`/`ExitCode`（`OOMKilled`、`Error`）、`Ready`、`RestartCount`；init 容器在 `InitContainerStatuses`。
  - 被驱逐：`pod.Status.Phase == Failed` 且 `pod.Status.Reason == "Evicted"`。
- 测试：`fake.NewSimpleClientset(pod1, pod2)`（client-go 官方示例的写法，见 [fake-client](../../references/go/k8s/client-go-examples/fake-client/)；新版本还提供 `fake.NewClientset`，以你用的 client-go 版本为准）。
- `--watch`：用 informer，`informers.NewSharedInformerFactory(cs, 0)` → `f.Core().V1().Pods().Informer()` → `AddEventHandler(cache.ResourceEventHandlerFuncs{...})`（新版本返回 registration 和 error 两个值）→ `f.Start(ctx.Done())` → `cache.WaitForCacheSync(ctx.Done(), inf.HasSynced)`。写法参考 [sample-controller](../../references/go/k8s/sample-controller/controller.go)。

</details>

**进阶挑战**

- 对每个有问题的 Pod，顺手取最近的 Events（`cs.CoreV1().Events(ns).List`，按 `involvedObject.name` 过滤），效果相当于 `kubectl describe` 的最后几行。
- 加 `--nodes`：同时检查节点状态（NotReady、MemoryPressure、DiskPressure）。

---

<a id="p10"></a>

## P10 cert-exporter：证书过期 exporter（W20）

**场景**：P8 是你手动跑的工具。真实环境里，应该让 Prometheus 每分钟来抓一次，快过期时自动告警。这个项目把 P8 改造成 exporter，并完整走一遍「写服务 → 打镜像 → 部署到 K8s → 配探针 → 验证」的流程。

**功能需求**

```text
cert-exporter -listen :8080 -config /etc/cert-exporter/targets.yaml
```

```text
# HELP cert_expiry_seconds 证书剩余有效期（秒），负数表示已过期
# TYPE cert_expiry_seconds gauge
cert_expiry_seconds{target="192.0.2.11:6443"} 3.1449e+07
cert_expiry_seconds{target="/host/pki/apiserver.crt"} 3.1449e+07
# HELP cert_check_success 本次检查是否成功（1 成功，0 失败）
# TYPE cert_check_success gauge
cert_check_success{target="192.0.2.11:6443"} 1
```

- `/metrics`：Prometheus 格式的指标；`/healthz`：进程活着就返回 200。
- 每次被抓取时现场检查（或者后台定时检查、抓取时读缓存，二选一，在 README 里说明理由）。
- 收到 SIGTERM 时优雅退出：停止接受新请求，等进行中的请求完成。

**部署要求**

- 多阶段 Dockerfile，最终镜像基于 distroless 或 scratch，以非 root 运行。
- Kubernetes 清单：ConfigMap（targets.yaml）、Deployment、Service（端口命名为 `http-metrics`）。
- Deployment 要配 liveness 和 readiness 探针（`httpGet /healthz`）、resources requests/limits、`securityContext`（`runAsNonRoot: true`、`readOnlyRootFilesystem: true`）。
- 进阶部署：要检查控制平面上的 `/etc/kubernetes/pki/*.crt`，就得把 Pod 调度到控制平面节点：`nodeSelector` 加上对 `node-role.kubernetes.io/control-plane:NoSchedule` 污点的 toleration，再以只读 `hostPath` 挂载 pki 目录。

**验收标准**

- [ ] `curl localhost:8080/metrics` 能看到 `cert_expiry_seconds`
- [ ] 有测试：用 `httptest.NewRecorder` 调用 handler，断言输出里有对应的指标行（或者用 client_golang 的 `testutil` 包）
- [ ] 镜像体积小于 30 MB，`docker run`（或 `podman run`）能直接跑
- [ ] 在 kind 或 kubeadm 集群里运行，Pod Ready；`kubectl port-forward svc/cert-exporter 8080:8080` 后能抓到指标
- [ ] `kubectl delete pod` 后新 Pod 能自动起来；日志里能看到优雅退出
- [ ] `gofmt`、`go vet` 无告警，`go test -race` 通过

**用到的 Go 知识**：[G14 Prometheus client_golang](../../notes/go/14-observability-exporter.md) · [G11 容器化与部署](../../notes/go/11-containerize-deploy.md) · [G8 net/http](../../notes/go/08-net-http-tls.md)

**和考试的关联**：[CKA-09 工作负载与探针](../../notes/cka/09-workloads.md)、[CKA-10 污点与容忍](../../notes/cka/10-scheduling.md)、[CKA-11 Service](../../notes/cka/11-services-dns.md)、[CKA-14 hostPath 卷](../../notes/cka/14-storage.md)。一个项目把 CKA 的四个领域都串起来了。

<details>
<summary>提示</summary>

- 依赖：`go get github.com/prometheus/client_golang@latest`。官方示例见 [prometheus-client-golang-examples](../../references/go/prometheus-client-golang-examples/)。
- 「抓取时检查」适合写成自定义 Collector：实现 `Describe(ch chan<- *prometheus.Desc)` 和 `Collect(ch chan<- prometheus.Metric)`，在 Collect 里检查证书，再 `ch <- prometheus.MustNewConstMetric(desc, prometheus.GaugeValue, secs, target)`。描述符用 `prometheus.NewDesc("cert_expiry_seconds", "...", []string{"target"}, nil)` 创建。
- 用独立的 registry：`reg := prometheus.NewRegistry(); reg.MustRegister(c, collectors.NewGoCollector())`，然后 `mux.Handle("/metrics", promhttp.HandlerFor(reg, promhttp.HandlerOpts{}))`。
- 指标命名：Prometheus 约定时间用秒作单位。另一种常见做法是暴露过期的时间点 `cert_not_after_timestamp_seconds`，剩余时间交给 PromQL 计算（`cert_not_after_timestamp_seconds - time()`）。两种都可以，在 README 里说明你的选择。
- 优雅退出：`srv := &http.Server{Addr: addr, Handler: mux, ReadHeaderTimeout: 5 * time.Second}`；收到信号后调用 `srv.Shutdown(ctx)`。Pod 默认的 `terminationGracePeriodSeconds` 是 30 秒。
- Dockerfile 骨架（构建上下文是 `go/` 目录，镜像标签以 Docker Hub 和 distroless 仓库为准）：

```dockerfile
FROM golang:1.27 AS build
WORKDIR /src
COPY go.mod go.sum ./
RUN go mod download
COPY . .
RUN CGO_ENABLED=0 go build -trimpath -ldflags="-s -w" -o /out/cert-exporter ./tools/cert-exporter

FROM gcr.io/distroless/static-debian12:nonroot
COPY --from=build /out/cert-exporter /cert-exporter
EXPOSE 8080
ENTRYPOINT ["/cert-exporter"]
```

- 把镜像放进集群：kind 用 `kind load docker-image cert-exporter:dev`；在 RHEL 上用 podman 构建时，先 `podman save -o cert-exporter.tar cert-exporter:dev`，再 `kind load image-archive cert-exporter.tar`；kubeadm 集群可以在每个节点上 `sudo ctr -n k8s.io images import cert-exporter.tar`。镜像标签不是 `latest` 时，默认的 `imagePullPolicy` 是 `IfNotPresent`，不会去远程拉。

</details>

**进阶挑战**

- 写一条 Prometheus 告警规则：证书剩余不到 7 天时触发。
- 用 Helm 把清单打包成 chart，用 `values.yaml` 配置目标列表（复习 [CKA-07](../../notes/cka/07-helm-kustomize.md)）。

---

<a id="p11"></a>

## P11 operator：StaticSite CRD + controller（W22）

**场景**：CKA 考纲要求「理解 CRD，安装和配置 operator」。自己写一个 operator，CRD、控制循环、OwnerReference、RBAC 这些概念就全都通了。需求很简单：用户创建一个 `StaticSite` 对象，operator 自动帮他建好 ConfigMap、Deployment 和 Service。

**功能需求**

```yaml
apiVersion: web.lab.local/v1alpha1
kind: StaticSite
metadata:
  name: hello
spec:
  image: nginx:1.27
  replicas: 2
  content: |
    <h1>Hello from StaticSite</h1>
status:
  readyReplicas: 2
  conditions:
    - type: Available
      status: "True"
```

- controller 根据 spec 创建或更新：ConfigMap（`index.html` = `spec.content`）、Deployment（挂载这个 ConfigMap 到 `/usr/share/nginx/html`）、Service（ClusterIP，80 端口）。
- 修改 `spec.replicas`、`spec.content`，对应资源要跟着更新。
- 删除 StaticSite，三个子资源要被自动回收（垃圾回收，而不是你在代码里一个个删）。
- `status.readyReplicas` 和 `Available` 条件要如实反映 Deployment 的状态。
- `kubectl get staticsites` 要显示 READY 列。

**验收标准**

- [ ] `make manifests && make install && make run` 后，`kubectl apply -f config/samples/` 能看到三个子资源被创建
- [ ] reconcile 是**幂等**的：反复触发多少次，结果都一样，不会重复创建资源
- [ ] 手动 `kubectl delete deploy hello` 后，controller 会把它重新建出来（自愈）
- [ ] `kubectl delete staticsite hello` 后子资源被自动删除
- [ ] spec 有校验：`replicas` 最小为 1、`image` 必填（用 kubebuilder 的校验标记）
- [ ] RBAC 标记齐全，`make deploy` 部署到集群后，controller 不会因为权限不足报 forbidden
- [ ] `make test`（envtest）通过

**用到的 Go 知识**：[G13 controller-runtime 与 kubebuilder](../../notes/go/13-controller-operator.md) · [G12 client-go 的对象模型](../../notes/go/12-client-go.md)

**和考试的关联**：[CKA-08 扩展接口、CRD 与 Operator](../../notes/cka/08-extension-interfaces-crd.md)、[CKA-06 RBAC](../../notes/cka/06-rbac.md)、[CKA-01 控制器的工作方式](../../notes/cka/01-architecture.md)。「幂等」和 RHCE 里的 Ansible 是同一个思想（[RHCE-04](../../notes/rhce/04-playbooks.md)）。

<details>
<summary>提示</summary>

- 安装 kubebuilder 和创建项目（命令来自 [Kubebuilder Book 快速开始](../../references/go/k8s/kubebuilder-book/quick-start.md)，以书中最新写法为准）：

```bash
curl -L -o kubebuilder "https://go.kubebuilder.io/dl/latest/$(go env GOOS)/$(go env GOARCH)"
```

```bash
chmod +x kubebuilder && sudo mv kubebuilder /usr/local/bin/
```

```bash
mkdir -p go/tools/operator && cd go/tools/operator
```

```bash
kubebuilder init --domain lab.local --repo github.com/guiguisocute/RHCE-CKA/go/tools/operator
```

```bash
kubebuilder create api --group web --version v1alpha1 --kind StaticSite
```

- 在 `api/v1alpha1/staticsite_types.go` 里定义 spec/status，用标记加校验和打印列：`// +kubebuilder:validation:Minimum=1`、`// +kubebuilder:default=1`、`// +kubebuilder:printcolumn:name="Ready",type=integer,JSONPath=".status.readyReplicas"`。改完运行 `make manifests generate`。
- Reconcile 的骨架：
  1. `r.Get(ctx, req.NamespacedName, &site)`，取不到时 `return ctrl.Result{}, client.IgnoreNotFound(err)`。
  2. 对每个子资源，用 `controllerutil.CreateOrUpdate(ctx, r.Client, obj, func() error { /* 把期望状态写进 obj */ ; return controllerutil.SetControllerReference(&site, obj, r.Scheme) })`。
  3. 读 Deployment 的 `Status.ReadyReplicas`，写回 `site.Status`，再 `r.Status().Update(ctx, &site)`。
- 让子资源的变化也能触发 reconcile：`ctrl.NewControllerManagedBy(mgr).For(&webv1alpha1.StaticSite{}).Owns(&appsv1.Deployment{}).Owns(&corev1.Service{}).Owns(&corev1.ConfigMap{}).Complete(r)`。参考 [secondary-owned-resources](../../references/go/k8s/kubebuilder-book/reference/watching-resources/secondary-owned-resources.md)。
- RBAC 标记写在 Reconcile 函数上方，例如 `// +kubebuilder:rbac:groups=apps,resources=deployments,verbs=get;list;watch;create;update;patch;delete`，以及 `groups="",resources=services;configmaps`。`make manifests` 会据此生成 ClusterRole。
- 完整示例：[CronJob 教程](../../references/go/k8s/kubebuilder-book/cronjob-tutorial/cronjob-tutorial.md)。

</details>

**进阶挑战**

- 修改 `spec.content` 后，ConfigMap 变了，但 Pod 不会自动重启。给 Pod 模板加一个内容哈希注解，让 Deployment 滚动更新。这就是 Helm 里常见的 `checksum/config` 技巧（[CKA-07](../../notes/cka/07-helm-kustomize.md)）。
- 加一个 finalizer：删除 StaticSite 前先打印一行「站点下线」日志（参考书中的 finalizer 示例）。
- 加 webhook，拒绝 `image` 不带 tag 的 StaticSite。
