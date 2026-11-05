# Go-02 基础语法与错误处理

> **轨道**：[Go](README.md) ｜ **运维场景**：把 Bash 脚本里的 `if [[ -f ]]`、`$?`、`set -e` 换成可靠的、有明确错误信息的 Go 代码 ｜ **建议用时**：3.5 h（第 2 周） ｜ **难度**：★☆☆
>
> **前置**：[Go-01 环境、模块与工具链](01-toolchain-modules.md)
> **后续**：[Go-03 slice、map、struct 与指针](03-composite-types.md)
> **关联**（跨轨道）：[S2 Shell 脚本](../rhcsa/02-shell-scripting.md)（同样的逻辑用两种语言各写一遍）

## 1. 这个知识点在网络中的位置

RHCSA 的 Shell 脚本里，错误处理靠 `$?` 和 `set -e`，很容易漏掉。Go 没有异常，**每个可能失败的函数都把 `error` 作为最后一个返回值**，调用方必须显式处理。代码会多几行 `if err != nil`，但运维工具出问题时，你能拿到一句完整的错误链，比如 `load config "/etc/app.yaml": open /etc/app.yaml: permission denied`。

## 2. 核心概念

**Shell 和 Go 对照**

| Bash | Go |
|---|---|
| `name="web"` | `name := "web"`（函数内）或 `var name = "web"` |
| `$1`、`$#` | `os.Args[1]`、`len(os.Args)-1`（更推荐用 `flag` 包，见 G5） |
| `if [[ -f "$f" ]]` | `if _, err := os.Stat(f); err == nil { ... }` |
| `for i in 1 2 3` | `for _, i := range []int{1, 2, 3}`；Go 1.22+ 还能写 `for i := range 3` |
| `while read line` | `for scanner.Scan() { ... }`（G5） |
| `case "$x" in ...` | `switch x { case "a", "b": ... }`，不用写 `break` |
| `$?`、`exit 1` | 函数返回 `error`；`os.Exit(1)` |
| `set -e` | 没有自动机制，每个 `err` 都要检查 |
| `trap cleanup EXIT` | `defer cleanup()`（函数返回时执行） |

**语法要点**

- 类型写在变量名后面：`var port int = 22`；`:=` 自动推断类型，只能在函数里用。
- 只有 `for` 一种循环；`if`、`switch` 可以带一个初始化语句：`if err := f(); err != nil {}`。
- 函数可以返回多个值，惯例是 `(结果, error)`。
- 首字母大写的标识符可以被别的 package 使用（导出），小写是包内私有。
- `const` + `iota` 定义枚举。

**错误处理的四件套**

| 写法 | 作用 |
|---|---|
| `errors.New("磁盘已满")` | 创建一个简单错误 |
| `fmt.Errorf("load %q: %w", path, err)` | 加上下文并**包装**原错误（`%w`），错误链不丢 |
| `errors.Is(err, fs.ErrNotExist)` | 判断错误链里有没有某个特定错误（文件不存在、权限不足……） |
| `errors.As(err, &pathErr)` | 从错误链里取出某种类型的错误，读它的字段；Go 1.26 起还有泛型版 `errors.AsType` |

其他：`errors.Join(e1, e2)`（Go 1.20+）把多个错误合成一个，适合「检查 10 项，最后一起报错」的巡检工具。

## 3. 必会操作

```go
// checkcfg：读取配置文件，按错误类型给出不同提示和退出码
package main

import (
	"errors"
	"fmt"
	"io/fs"
	"os"
)

// ServiceState 用 iota 定义一组枚举常量
type ServiceState int

const (
	Unknown ServiceState = iota // 0
	Active                      // 1
	Inactive                    // 2
	Failed                      // 3
)

// loadConfig 读文件；出错时用 %w 包装，保留原始错误供调用方判断
func loadConfig(path string) ([]byte, error) {
	data, err := os.ReadFile(path)
	if err != nil {
		return nil, fmt.Errorf("load config %q: %w", path, err)
	}
	return data, nil
}

func main() {
	if len(os.Args) != 2 {
		fmt.Fprintln(os.Stderr, "usage: checkcfg <file>")
		os.Exit(2) // 参数错误，和 shell 的惯例一样用 2
	}
	data, err := loadConfig(os.Args[1])
	switch {
	case errors.Is(err, fs.ErrNotExist):
		fmt.Fprintln(os.Stderr, "文件不存在:", err)
		os.Exit(1)
	case errors.Is(err, fs.ErrPermission):
		fmt.Fprintln(os.Stderr, "没有权限，试试 sudo:", err)
		os.Exit(1)
	case err != nil:
		var pe *fs.PathError
		if errors.As(err, &pe) {
			fmt.Fprintf(os.Stderr, "操作 %s 失败，路径 %s: %v\n", pe.Op, pe.Path, pe.Err)
		}
		os.Exit(1)
	}
	fmt.Printf("读取 %d 字节，状态枚举示例：Active=%d Failed=%d\n", len(data), Active, Failed)
}
```

```bash
go run . /etc/hostname     # 读取 N 字节……
go run . /nonexist         # 文件不存在: load config "/nonexist": open /nonexist: no such file or directory
go run . /etc/shadow       # 普通用户运行：没有权限，试试 sudo: ...
```

**defer：函数返回前一定执行**

```go
f, err := os.Open(path)
if err != nil {
	return err
}
defer f.Close() // 不管后面从哪个 return 离开，文件都会被关闭
```

## 4. 考试坑点

- **`err` 被忽略**：`data, _ := os.ReadFile(p)` 把错误丢了，出问题时只看到「空配置」。只有确实不关心时才用 `_`。
- **`:=` 遮蔽**：在 `if` 块里写 `x, err := ...` 会新建一个同名变量，外面的 `err` 没被赋值。`go vet` 默认不检查变量遮蔽（shadow 检查器要单独安装），主要靠习惯：块里只想赋值就用 `=`。
- **用 `%v` 包装会丢失错误链**：`fmt.Errorf("...: %v", err)` 之后 `errors.Is` 就判断不出来了，要用 `%w`。
- **`os.Exit` 不执行 defer**：在 `main` 里 `defer f.Close()` 后又 `os.Exit(1)`，defer 不会运行。复杂程序把逻辑放进 `run() error`，`main` 只负责打印错误和退出（G6 会讲）。
- **`panic` 不是错误处理**：工具里遇到坏输入应返回 `error`；`panic` 只用于程序员错误（比如不可能出现的分支）。
- **字符串比较错误**：别写 `if err.Error() == "file not found"`，错误文案随版本会变，用 `errors.Is`。

## 5. 动手练习

- 把你 RHCSA 练习里写过的一个 Shell 脚本（例如「检查 /etc/fstab 里的挂载点是否都存在」）用 Go 重写，要求每个错误都带上下文、退出码和原脚本一致。
- 给 `checkcfg` 加 `-all` 参数：检查多个文件，用 `errors.Join` 汇总所有错误后统一退出。
- 后续项目从第 5 周开始：[运维小项目](../../labs/go/projects.md)。

**配套 LeetCode（第 2 周，[刷题计划](../../labs/go/leetcode-plan.md#w2)）**

- [20. 有效的括号](https://leetcode.cn/problems/valid-parentheses/)：用切片当栈；想想怎么检查配置文件里的括号是否配对
- [14. 最长公共前缀](https://leetcode.cn/problems/longest-common-prefix/)：练 `for` 循环和字符串下标（注意 byte 和 rune 的区别）
- [929. 独特的电子邮件地址](https://leetcode.cn/problems/unique-email-addresses/)：`strings.Cut`、`strings.ReplaceAll`，以及用 map 去重

## 6. 官方文档（本仓库离线版 + 本机查法）

- 离线：
  - Tour of Go：[基础](../../references/go/tour/basics.article)、[流程控制](../../references/go/tour/flowcontrol.article)
  - [官方教程：返回和处理错误](../../references/go/go-docs/tutorial/handle-errors.html)
  - [Effective Go](../../references/go/go-docs/effective_go.html)（读 Errors、Defer、Panic 三节）
  - Go by Example：[errors](../../references/go/gobyexample/examples/errors/errors.go)、[custom-errors](../../references/go/gobyexample/examples/custom-errors/custom-errors.go)、[defer](../../references/go/gobyexample/examples/defer/defer.go)、[switch](../../references/go/gobyexample/examples/switch/switch.go)、[enums](../../references/go/gobyexample/examples/enums/enums.go)、[exit](../../references/go/gobyexample/examples/exit/exit.go)
  - [语言规范](../../references/go/spec/go_spec.html)（遇到语法疑问时查）
- 本机：`go doc errors`、`go doc errors.Is`、`go doc fmt.Errorf`、`go doc io/fs.ErrNotExist`
- 在线：https://pkg.go.dev/errors 、https://go.dev/blog/go1.13-errors

## 7. 自测清单

- [ ] 能解释 `%w` 和 `%v` 包装错误的区别
- [ ] 能用 `errors.Is` 区分「文件不存在」和「没有权限」
- [ ] 会用 `iota` 定义一组状态常量
- [ ] 知道 `os.Exit` 为什么会跳过 `defer`
- [ ] 把一个 30 行以内的 Shell 脚本改写成 Go，行为一致
