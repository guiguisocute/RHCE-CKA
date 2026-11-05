# Go-07 并发：goroutine、channel 与 context

> **轨道**：[Go](README.md) ｜ **运维场景**：同时探测 500 台机器的端口、并发备份、批量 SSH——要快，又不能把对端或自己压垮，还要能超时和中途取消 ｜ **建议用时**：4 h（第 9 周） ｜ **难度**：★★★
>
> **前置**：[Go-04 方法、接口与泛型](04-methods-interfaces-generics.md)
> **后续**：[Go-08 网络、HTTP 与 TLS](08-net-http-tls.md) · [Go-10 SSH 远程执行](10-ssh-parallel-exec.md) · [Go-12 client-go](12-client-go.md)
> **关联**（跨轨道）：[E1 Ansible 架构](../rhce/01-ansible-architecture.md)（`forks` 就是并发上限）· [S7 网络 nmcli](../rhcsa/07-networking-nmcli.md) · [S9 防火墙](../rhcsa/09-security-firewalld-selinux.md)（端口探测的对象）

## 1. 这个知识点在网络中的位置

Shell 里并发靠 `&` 和 `wait`，很难控制并发数和超时。Go 的 goroutine 非常轻（一个只占几 KB），用 channel 传数据、用 `context` 统一超时和取消，写批量运维工具非常顺手。
学 RHCE 时你会配置 Ansible 的 `forks: 5`：同一时间最多对 5 台机器执行。本节的 worker pool 就是它的 Go 实现；到 G10 你会用它写一个迷你版 Ansible。

| Ansible | Go |
|---|---|
| `forks: 5` | 5 个 worker goroutine，或容量为 5 的信号量 channel |
| `timeout: 10` | `context.WithTimeout(ctx, 10*time.Second)` |
| `serial: 2`（分批滚动） | 每批开 2 个 goroutine，`wg.Wait()` 之后再开下一批 |
| 某台失败就停（`any_errors_fatal`） | `errgroup.WithContext`：一个返回错误，其余被取消 |

## 2. 核心概念

| 概念 | 说明 |
|---|---|
| goroutine | `go f()` 启动；`main` 返回时所有 goroutine 直接结束 |
| channel | `ch := make(chan T)` 无缓冲（收发双方同步）；`make(chan T, n)` 有缓冲 |
| `close(ch)` | 由发送方关闭，表示「没有更多数据」；接收方 `for v := range ch` 自动结束 |
| `select` | 同时等待多个 channel，常和 `ctx.Done()`、`time.After` 搭配做超时 |
| `sync.WaitGroup` | 等一组 goroutine 结束；Go 1.25 起可以直接 `wg.Go(func(){...})` |
| `sync.Mutex` | 保护共享数据（比如多个 goroutine 往同一个 map 写结果） |
| `context.Context` | 在调用链里传递「截止时间」和「取消信号」，第一个参数惯例叫 `ctx` |
| `errgroup`（`golang.org/x/sync`） | WaitGroup + 错误收集 + 出错时取消 + `SetLimit` 限并发 |
| 竞态 | 多个 goroutine 同时读写同一变量且没加锁。`go run -race` / `go test -race` 能抓到 |

## 3. 必会操作

**运维场景示例：worker pool 并发探测端口，整体 5 秒超时，Ctrl-C 可中断**

```go
// portcheck：用固定数量的 worker 并发探测一批 host:port，整体有超时
package main

import (
	"cmp"
	"context"
	"fmt"
	"net"
	"os"
	"os/signal"
	"slices"
	"sync"
	"time"
)

type result struct {
	Target string
	Open   bool
	Took   time.Duration
	Err    error
}

func probe(ctx context.Context, target string) result {
	start := time.Now()
	d := net.Dialer{Timeout: 2 * time.Second} // 单个连接最多等 2 秒
	conn, err := d.DialContext(ctx, "tcp", target)
	if err != nil {
		return result{Target: target, Took: time.Since(start), Err: err}
	}
	conn.Close()
	return result{Target: target, Open: true, Took: time.Since(start)}
}

func main() {
	targets := os.Args[1:]
	if len(targets) == 0 {
		targets = []string{"127.0.0.1:22", "127.0.0.1:80", "127.0.0.1:8080", "127.0.0.1:6443"}
	}

	// 整体最多跑 5 秒；按 Ctrl-C 也会取消所有探测
	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt)
	defer stop()
	ctx, cancel := context.WithTimeout(ctx, 5*time.Second)
	defer cancel()

	jobs := make(chan string)
	results := make(chan result)
	const workers = 3 // 相当于 Ansible 的 forks

	var wg sync.WaitGroup
	for range workers { // Go 1.22+：range 一个整数
		wg.Add(1)
		go func() {
			defer wg.Done()
			for t := range jobs {
				results <- probe(ctx, t)
			}
		}()
	}
	go func() { // 发任务
		defer close(jobs)
		for _, t := range targets {
			select {
			case jobs <- t:
			case <-ctx.Done():
				return
			}
		}
	}()
	go func() { wg.Wait(); close(results) }() // 所有 worker 结束后关闭结果通道

	var all []result
	for r := range results {
		all = append(all, r)
	}
	slices.SortFunc(all, func(a, b result) int { return cmp.Compare(a.Target, b.Target) })
	for _, r := range all {
		state := "open"
		if !r.Open {
			state = "closed: " + r.Err.Error()
		}
		fmt.Printf("%-18s %-6s %s\n", r.Target, r.Took.Round(time.Millisecond), state)
	}
}
```

```bash
go run . 10.0.0.11:22 10.0.0.11:80 10.0.0.12:22 10.0.0.12:6443
go run -race . 127.0.0.1:22        # 开着竞态检测跑一遍
```

**errgroup：限并发 + 任意一个失败就取消其余**

```go
// go get golang.org/x/sync
func backup(ctx context.Context, host string) error {
	select {
	case <-time.After(100 * time.Millisecond): // 假装在备份
		if host == "db2" {
			return fmt.Errorf("%s: 磁盘已满", host)
		}
		fmt.Println("done", host)
		return nil
	case <-ctx.Done():
		return ctx.Err()
	}
}

func main() {
	hosts := []string{"db1", "db2", "db3", "db4", "db5"}
	g, ctx := errgroup.WithContext(context.Background())
	g.SetLimit(2) // 最多同时跑 2 个
	for _, h := range hosts {
		g.Go(func() error { return backup(ctx, h) }) // Go 1.22+ 循环变量每轮都是新的，可以直接用 h
	}
	if err := g.Wait(); err != nil {
		fmt.Println("失败：", err) // 失败： db2: 磁盘已满（后面的任务拿到已取消的 ctx，直接返回）
	}
}
```

**用 Mutex 保护共享 map**

```go
var mu sync.Mutex
stats := map[string]int{}
// 在多个 goroutine 里：
mu.Lock()
stats[host]++
mu.Unlock()
```

## 4. 考试坑点

- **goroutine 泄漏**：worker 在往一个没人读的 channel 发数据，会永远卡住。每个 goroutine 都要想清楚「它什么时候退出」，并让它监听 `ctx.Done()`。Go 1.26 起有实验性的 goroutine 泄漏 profile 可以帮忙排查（以官方文档为准）。
- **谁关闭 channel**：只由发送方关闭；关闭两次、往已关闭的 channel 发送都会 panic。多个发送方时，用 WaitGroup 等它们全部结束后再关闭（上面例子里的第三个 goroutine）。
- **`wg.Add` 写在 goroutine 里面**：可能 `Wait` 先执行完。`Add` 要在 `go` 之前调用（Go 1.25 的 `wg.Go` 自动处理了这一点，`go vet` 也会检查）。
- **并发写 map 直接崩溃**：`fatal error: concurrent map writes`，加锁或者只在一个 goroutine 里写（让 worker 把结果发回 channel，由 main 汇总，像上面那样）。
- **忘了传 ctx**：外层超时了，底层的 `Dial`、HTTP 请求还在继续。所有可能阻塞的调用都用带 ctx 的版本（`DialContext`、`NewRequestWithContext`、`CommandContext`）。
- **无限并发**：对 2000 台机器同时开 2000 个 SSH 连接，可能被对端的 `MaxStartups` 拒绝，或者触发防火墙限速。永远设并发上限。
- **Go 1.22 之前的循环变量**：旧版本里 goroutine 闭包捕获的是同一个循环变量，要写 `h := h`。`go.mod` 里 `go` 版本 ≥ 1.22 时不用。

## 5. 动手练习

- 第 9 周项目：[P4 portcheck](../../labs/go/projects.md#p4)：从文件读「主机 端口列表」，`-c` 控制并发数，`-t` 控制超时，输出 open/closed/timeout 三种状态，结果可选 JSON。用它验证你在 RHCSA 实验机上用 firewalld 放行的端口。
- 给巡检框架（G4）加并发：所有 Checker 并行执行，总超时 10 秒。

**配套 LeetCode（第 9 周，[刷题计划](../../labs/go/leetcode-plan.md#w9)）**

- [1114. 按序打印](https://leetcode.cn/problems/print-in-order/)：用 channel 控制三个 goroutine 的执行顺序。LeetCode 的多线程题不一定提供 Go 语言选项，没有的话就在本地实现并用 `-race` 测试
- [622. 设计循环队列](https://leetcode.cn/problems/design-circular-queue/)：环形缓冲区，日志采集 agent 里很常见；写完想想有缓冲 channel 内部是不是也是这个结构
- [239. 滑动窗口最大值](https://leetcode.cn/problems/sliding-window-maximum/)：「最近 5 分钟内的最大延迟」就是这道题

## 6. 官方文档（本仓库离线版 + 本机查法）

- 离线：
  - Tour of Go：[并发](../../references/go/tour/concurrency.article)
  - [Go 内存模型](../../references/go/spec/go_mem.html)（想搞懂「为什么要加锁」时读）
  - [竞态检测器](../../references/go/go-docs/articles/race_detector.html)
  - Go by Example：[goroutines](../../references/go/gobyexample/examples/goroutines/goroutines.go)、[channels](../../references/go/gobyexample/examples/channels/channels.go)、[select](../../references/go/gobyexample/examples/select/select.go)、[timeouts](../../references/go/gobyexample/examples/timeouts/timeouts.go)、[closing-channels](../../references/go/gobyexample/examples/closing-channels/closing-channels.go)、[worker-pools](../../references/go/gobyexample/examples/worker-pools/worker-pools.go)、[waitgroups](../../references/go/gobyexample/examples/waitgroups/waitgroups.go)、[mutexes](../../references/go/gobyexample/examples/mutexes/mutexes.go)、[rate-limiting](../../references/go/gobyexample/examples/rate-limiting/rate-limiting.go)、[context](../../references/go/gobyexample/examples/context/context.go)、[signals](../../references/go/gobyexample/examples/signals/signals.go)
- 本机：`go doc context`、`go doc sync.WaitGroup`、`go doc os/signal.NotifyContext`
- 在线：https://pkg.go.dev/context 、https://pkg.go.dev/golang.org/x/sync/errgroup 、https://go.dev/blog/pipelines

## 7. 自测清单

- [ ] 能不看资料写出「N 个 worker + jobs/results 两个 channel」的 worker pool
- [ ] 能解释为什么 `close(results)` 要放在一个单独的 goroutine 里等 `wg.Wait()`
- [ ] 会用 `context.WithTimeout` 给一批操作设总超时
- [ ] 会用 errgroup 的 `SetLimit` 限制并发数
- [ ] 用 `-race` 抓到过一次自己写的竞态 bug
