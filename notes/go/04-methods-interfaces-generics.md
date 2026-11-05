# Go-04 方法、接口与泛型

> **轨道**：[Go](README.md) ｜ **运维场景**：写可插拔的巡检/告警框架；读懂 client-go、controller-runtime 里到处出现的接口 ｜ **建议用时**：4 h（第 4 周） ｜ **难度**：★★☆
>
> **前置**：[Go-03 slice、map、struct 与指针](03-composite-types.md)
> **后续**：[Go-05 运维常用标准库](05-stdlib-files-text-exec.md) · [Go-07 并发](07-concurrency-context.md) · [Go-12 client-go](12-client-go.md)
> **关联**（跨轨道）：[K1 集群架构](../cka/01-architecture.md)（kubelet 通过 CRI 接口对接不同容器运行时，和 Go 接口是同一个思想）

## 1. 这个知识点在网络中的位置

接口是 Go 最重要的抽象工具。标准库里最常见的两个接口 `io.Reader` 和 `io.Writer`，把「文件、标准输入、网络连接、HTTP 响应体、SSH 会话输出」统一成一种东西：写一个函数接收 `io.Reader`，它就能处理以上所有来源，测试时传一个 `strings.Reader` 就行。
到 CKA 阶段写 client-go 时，`kubernetes.Interface` 也是接口，测试时可以换成假的 clientset（fake client）。

## 2. 核心概念

| 概念 | 说明 |
|---|---|
| 方法 | 绑定在类型上的函数：`func (d DiskChecker) Check() Result` |
| 值接收者 / 指针接收者 | 需要修改接收者、或结构体较大时用 `func (d *T)`；同一类型的方法尽量统一用一种 |
| 接口 | 一组方法签名。**隐式实现**：类型只要有这些方法就自动满足接口，不用写 `implements` |
| 小接口 | Go 惯例是 1~2 个方法的小接口：`io.Reader`、`io.Writer`、`fmt.Stringer`、`error` |
| 类型断言 | `s, ok := v.(fmt.Stringer)`；类型 switch：`switch x := v.(type) {}` |
| 嵌入 | 在 struct 里嵌入另一个类型，就「继承」了它的方法（组合优于继承） |
| 泛型（Go 1.18+） | `func Filter[T any](xs []T, keep func(T) bool) []T`；约束常用 `any`、`comparable`、`cmp.Ordered` |

常见建议：**接收接口，返回具体类型**；接口由使用方定义，不要先写一堆接口再找实现。

版本提示：Go 1.27 起，方法也可以声明自己的类型参数（泛型方法）。本仓库示例按 Go 1.24 写，不使用这个特性。

## 3. 必会操作

```go
// 一个可扩展的巡检框架：所有检查项实现同一个 Checker 接口
package main

import (
	"bufio"
	"fmt"
	"io"
	"os"
	"strings"
	"syscall"
)

type Result struct {
	Name string
	OK   bool
	Msg  string
}

// String 让 Result 实现 fmt.Stringer，Println 时自动调用
func (r Result) String() string {
	mark := "OK  "
	if !r.OK {
		mark = "FAIL"
	}
	return fmt.Sprintf("[%s] %-18s %s", mark, r.Name, r.Msg)
}

// Checker 是一个只有两个方法的小接口；任何类型实现了这两个方法就自动满足它
type Checker interface {
	Name() string
	Check() Result
}

// DiskChecker 检查挂载点剩余空间（只适用于 Linux）
type DiskChecker struct {
	Path       string
	MinFreePct float64
}

func (d DiskChecker) Name() string { return "disk " + d.Path }

func (d DiskChecker) Check() Result {
	var st syscall.Statfs_t
	if err := syscall.Statfs(d.Path, &st); err != nil {
		return Result{d.Name(), false, err.Error()}
	}
	free := float64(st.Bavail) / float64(st.Blocks) * 100
	return Result{d.Name(), free >= d.MinFreePct, fmt.Sprintf("free %.1f%%", free)}
}

// FileChecker 检查关键文件是否存在
type FileChecker struct{ Path string }

func (f FileChecker) Name() string { return "file " + f.Path }

func (f FileChecker) Check() Result {
	if _, err := os.Stat(f.Path); err != nil {
		return Result{f.Name(), false, err.Error()}
	}
	return Result{f.Name(), true, "exists"}
}

// countLines 接收 io.Reader：文件、标准输入、网络连接、测试用的 strings.Reader 都能传进来
func countLines(r io.Reader) (int, error) {
	sc := bufio.NewScanner(r)
	n := 0
	for sc.Scan() {
		n++
	}
	return n, sc.Err()
}

// Filter 是一个泛型函数：对任何元素类型的切片都能用
func Filter[T any](xs []T, keep func(T) bool) []T {
	var out []T
	for _, x := range xs {
		if keep(x) {
			out = append(out, x)
		}
	}
	return out
}

func main() {
	checks := []Checker{
		DiskChecker{Path: "/", MinFreePct: 10},
		FileChecker{Path: "/etc/hostname"},
		FileChecker{Path: "/etc/not-here.conf"},
	}
	var results []Result
	for _, c := range checks {
		results = append(results, c.Check())
	}
	for _, r := range results {
		fmt.Println(r)
	}
	failed := Filter(results, func(r Result) bool { return !r.OK })
	fmt.Printf("%d/%d 项失败\n", len(failed), len(results))

	n, _ := countLines(strings.NewReader("a\nb\nc\n"))
	fmt.Println("lines:", n)
}
```

输出（磁盘剩余比例以你的机器为准）：

```text
[OK  ] disk /             free 11.3%
[OK  ] file /etc/hostname exists
[FAIL] file /etc/not-here.conf stat /etc/not-here.conf: no such file or directory
1/3 项失败
lines: 3
```

要加一种新检查（比如「端口在监听」「服务是 active」），只要写一个新类型实现 `Name()` 和 `Check()`，主流程一行都不用改。Nagios/Zabbix 插件、Prometheus collector 都是这个思路。

**io.Reader / io.Writer 组合**

```go
f, _ := os.Open("/var/log/messages")
defer f.Close()
io.Copy(os.Stdout, f)                         // 文件 → 标准输出，就是 cat
gz := gzip.NewWriter(out); io.Copy(gz, f)     // 文件 → gzip → 输出文件，就是 gzip -c（最后要 gz.Close()）
tee := io.MultiWriter(os.Stdout, logFile)     // 同时写两个地方，就是 tee
```

**编译期检查一个类型是否实现了接口**

```go
var _ Checker = DiskChecker{} // 少实现一个方法，编译就会报错
```

## 4. 考试坑点

- **指针接收者导致「没实现接口」**：方法写成 `func (d *DiskChecker) Check()` 时，只有 `*DiskChecker` 满足接口，`[]Checker{DiskChecker{}}` 会编译失败，要写 `&DiskChecker{}`。
- **nil 接口不等于 nil**：一个值为 `nil` 的 `*MyErr` 赋给 `error` 接口后，`err != nil` 为真。返回错误时直接 `return nil`，不要返回类型化的 nil 指针。
- **接口定义得太大**：一个接口十几个方法，写测试替身会非常痛苦。拆成小接口。
- **滥用泛型**：Go 社区的建议是先写具体代码，同样的逻辑重复三次以上再考虑泛型。
- **`syscall` 是平台相关的**：上面的 `Statfs` 只能在 Linux 上编译。正式项目推荐用 `golang.org/x/sys/unix`。

## 5. 动手练习

- 给巡检框架加两个检查：`PortChecker`（端口能否连通，预习 G7/G8）和 `UnitChecker`（systemd 服务是否 active，预习 G5）。
- 写一个 `type multiChecker []Checker`，让它本身也实现 `Checker`（组合模式）。
- 后续项目：[运维小项目](../../labs/go/projects.md)。

**配套 LeetCode（第 4 周，[刷题计划](../../labs/go/leetcode-plan.md#w4)）**

这周的三道设计题都要求你定义一个类型并实现方法，正好练本节内容：

- [155. 最小栈](https://leetcode.cn/problems/min-stack/)：struct + 指针接收者方法
- [232. 用栈实现队列](https://leetcode.cn/problems/implement-queue-using-stacks/)：两个 slice 组合出新行为
- [706. 设计哈希映射](https://leetcode.cn/problems/design-hashmap/)：不用内置 map，自己用 slice 实现分桶，理解 map 的原理

## 6. 官方文档（本仓库离线版 + 本机查法）

- 离线：
  - Tour of Go：[方法和接口](../../references/go/tour/methods.article)、[泛型](../../references/go/tour/generics.article)
  - [官方教程：泛型入门](../../references/go/go-docs/tutorial/generics.md)
  - [Effective Go](../../references/go/go-docs/effective_go.html)（读 Methods、Interfaces and other types、Embedding 三节）
  - Go by Example：[methods](../../references/go/gobyexample/examples/methods/methods.go)、[interfaces](../../references/go/gobyexample/examples/interfaces/interfaces.go)、[struct-embedding](../../references/go/gobyexample/examples/struct-embedding/struct-embedding.go)、[generics](../../references/go/gobyexample/examples/generics/generics.go)
- 本机：`go doc io.Reader`、`go doc fmt.Stringer`、`go doc cmp.Ordered`
- 在线：https://pkg.go.dev/io 、https://go.dev/blog/intro-generics

## 7. 自测清单

- [ ] 能解释「隐式实现」接口是什么意思，以及它带来的好处
- [ ] 写一个接收 `io.Reader` 的函数，并分别传入文件和 `strings.Reader` 调用
- [ ] 知道值接收者和指针接收者对「是否满足接口」的影响
- [ ] 能说出 nil 接口和「装着 nil 指针的接口」的区别
- [ ] 写一个泛型函数 `Map[T, U any]`
