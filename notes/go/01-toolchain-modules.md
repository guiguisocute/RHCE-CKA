# Go-01 环境、模块与工具链

> **轨道**：[Go](README.md) ｜ **运维场景**：把工具编译成一个静态二进制，`scp` 到任何一台 Linux 上直接跑 ｜ **建议用时**：3 h（第 1 周） ｜ **难度**：★☆☆
>
> **前置**：无（会用 Linux 命令行即可）
> **后续**：[Go-02 基础语法与错误处理](02-basics-errors.md)
> **关联**（跨轨道）：[F1 Ubuntu → RHEL 对照](../00-foundations/01-ubuntu-to-rhel.md)（dnf 装包、PATH 配置）

## 1. 这个知识点在网络中的位置

这一节只解决一件事：在你的 RHEL 10 / Ubuntu 实验机上装好 Go，能 `go run`、`go build`、`go test`。
你熟悉的 Python 脚本要在目标机器上装解释器和依赖；Go 编出来是**一个文件**，没有运行时依赖。运维工具最看重这一点：拷到哪台机器都能跑，容器镜像可以小到几 MB。
`go.mod` 的角色 ≈ Python 的 `requirements.txt` + 项目名，`go.sum` ≈ 依赖的校验和锁文件。

## 2. 核心概念

| 概念 | 说明 |
|---|---|
| module | 一个项目 = 一个 module，根目录有 `go.mod`，第一行 `module github.com/你/项目名` |
| package | 一个目录 = 一个 package；`package main` + `func main()` 才能编出可执行文件 |
| `GOPATH` | 默认 `~/go`，放下载的依赖缓存（`~/go/pkg/mod`）和 `go install` 装的工具（`~/go/bin`） |
| `GOPROXY` | 下载模块用的代理，默认 `https://proxy.golang.org,direct`；国内可设成 `https://goproxy.cn,direct` |
| `GOTOOLCHAIN` | Go 1.21 起，`go.mod` 里要求更高版本时，go 命令会自动下载对应工具链 |
| 交叉编译 | 设 `GOOS`/`GOARCH` 就能在 x86 笔记本上编出 ARM 服务器用的二进制，不需要额外工具链 |
| `CGO_ENABLED=0` | 不链接 C 库，得到完全静态的二进制，可以放进 `scratch`/distroless 镜像 |

**装哪个版本**：写作时最新稳定版是 Go 1.27（2026 年 8 月发布），本仓库的示例按 Go 1.24 起能编译来写。实际装的版本以你机器上 `go version` 为准。

## 3. 必会操作

**安装（二选一）**

```bash
# 方式 A：发行版仓库，最省事，但版本可能比官网旧几个小版本
sudo dnf install golang        # RHEL 10；Ubuntu 用 sudo apt install golang-go
go version
```

```bash
# 方式 B：官方 tarball，版本最新。文件名里的版本号以 https://go.dev/dl/ 实际为准（国内可用 https://golang.google.cn/dl/）
curl -LO https://go.dev/dl/go1.27.0.linux-amd64.tar.gz
sudo rm -rf /usr/local/go && sudo tar -C /usr/local -xzf go1.27.0.linux-amd64.tar.gz
echo 'export PATH=$PATH:/usr/local/go/bin:$HOME/go/bin' >> ~/.bashrc && source ~/.bashrc
```

> 两种方式不要混装，否则 `which go` 指向哪个容易搞混。学习用推荐方式 B，版本和官方文档一致。

**环境变量**

```bash
go env GOPATH GOPROXY GOMODCACHE GOOS GOARCH   # 查看当前配置
go env -w GOPROXY=https://goproxy.cn,direct    # 国内网络建议设置，写进 ~/.config/go/env
go env -w GOPRIVATE=git.example.com            # 公司内部仓库不走代理（按需）
```

**第一个项目**

```bash
mkdir hostinfo && cd hostinfo
go mod init github.com/yourname/hostinfo   # 生成 go.mod
vim main.go                                # 写下面的代码
go run .                                   # 编译并运行（不留二进制）
go build -o hostinfo .                     # 编译出二进制
go vet ./...                               # 静态检查常见错误
gofmt -l .                                 # 列出格式不规范的文件；go fmt ./... 直接改
go mod tidy                                # 增删依赖后整理 go.mod / go.sum
```

`main.go`：打印主机名、内核版本和开机时长（在 RHEL/Ubuntu 上都能跑）。

```go
// hostinfo：打印主机名、内核版本和开机时长
package main

import (
	"fmt"
	"os"
	"strconv"
	"strings"
	"time"
)

func readTrim(path string) (string, error) {
	b, err := os.ReadFile(path)
	if err != nil {
		return "", err
	}
	return strings.TrimSpace(string(b)), nil
}

func main() {
	host, err := os.Hostname()
	if err != nil {
		fmt.Fprintln(os.Stderr, "hostname:", err)
		os.Exit(1)
	}
	kernel, err := readTrim("/proc/sys/kernel/osrelease")
	if err != nil {
		fmt.Fprintln(os.Stderr, "kernel:", err)
		os.Exit(1)
	}
	raw, err := readTrim("/proc/uptime") // 内容形如 "12345.67 23456.78"
	if err != nil {
		fmt.Fprintln(os.Stderr, "uptime:", err)
		os.Exit(1)
	}
	sec, err := strconv.ParseFloat(strings.Fields(raw)[0], 64)
	if err != nil {
		fmt.Fprintln(os.Stderr, "parse uptime:", err)
		os.Exit(1)
	}
	up := time.Duration(sec * float64(time.Second)).Round(time.Minute)
	fmt.Printf("host=%s kernel=%s uptime=%s\n", host, kernel, up)
}
```

**编出能发到任何 Linux 上的静态二进制**

```bash
CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build -trimpath -ldflags="-s -w" -o hostinfo .
file hostinfo                  # ... statically linked
ldd hostinfo                   # not a dynamic executable
go version -m ./hostinfo       # 查看二进制里记录的 Go 版本、模块和编译参数（排查线上版本很有用）
GOARCH=arm64 go build -o hostinfo-arm64 .   # 给 ARM 机器编
scp hostinfo serverb:/usr/local/bin/        # 拷过去就能跑
```

- `-ldflags="-s -w"`：去掉符号表和调试信息，体积小 30% 左右。
- `-trimpath`：去掉编译机上的绝对路径，产物可复现。

**编辑器**：VS Code 装官方 Go 扩展（会自动安装 `gopls`）；vim/neovim 用 LSP 接 `gopls`：

```bash
go install golang.org/x/tools/gopls@latest   # 装到 ~/go/bin
```

## 4. 考试坑点

> 这里的「考试」指写运维工具时最常踩的坑。

- **`go: command not found`**：tarball 安装后没把 `/usr/local/go/bin` 加进 PATH，或者只改了 `~/.bashrc` 没 `source`。
- **`go get` 卡住或超时**：没设 `GOPROXY`。国内网络设 `goproxy.cn` 后通常就好了。
- **在 `~` 目录直接 `go run main.go` 报错 `go.mod file not found`**：Go 1.16 起默认要求在 module 里，先 `go mod init`。
- **`CGO_ENABLED=0` 下的 `os/user`**：纯 Go 实现只读 `/etc/passwd` 和 `/etc/group`，查不到 SSSD/LDAP 里的用户。公司用 FreeIPA/AD 登录时要注意。
- **dnf 装的版本太旧**：别的项目 `go.mod` 写了 `go 1.26`，旧工具链会尝试自动下载新版（`GOTOOLCHAIN=auto`）；内网环境下载不到就会报错，这时换 tarball 安装。
- **`go install` 和 `go build` 的区别**：`install` 把二进制放进 `~/go/bin`，`build` 放在当前目录。

## 5. 动手练习

- 环境搭建：[labs/go/00-setup.md](../../labs/go/00-setup.md)
- 第 1 周小任务：照着上面的代码写出 `hostinfo`，加一个 `-json` 参数用 JSON 输出（预习 G5），交叉编译后拷到 RHCSA 实验机 serverb 上运行。详见 [运维小项目](../../labs/go/projects.md)。

**配套 LeetCode（第 1 周，[刷题计划](../../labs/go/leetcode-plan.md#w1)）**

- [1. 两数之和](https://leetcode.cn/problems/two-sum/)：第一次用 `map`，熟悉 LeetCode 的 Go 函数签名
- [1108. IP 地址无效化](https://leetcode.cn/problems/defanging-an-ip-address/)：`strings.ReplaceAll` 一行搞定，再试试用 `strings.Builder` 手写

## 6. 官方文档（本仓库离线版 + 本机查法）

- 离线：
  - [官方入门教程 Getting started](../../references/go/go-docs/tutorial/getting-started.html)、[创建 module](../../references/go/go-docs/tutorial/create-module.html)、[编译和安装](../../references/go/go-docs/tutorial/compile-install.html)
  - [How to Write Go Code](../../references/go/go-docs/code.html)（module、package、`go install` 的标准讲法）
  - [管理依赖](../../references/go/go-docs/modules/managing-dependencies.md)、[go.mod 参考](../../references/go/go-docs/modules/gomod-ref.md)、[模块目录布局](../../references/go/go-docs/modules/layout.md)
  - [Tour of Go 欢迎页](../../references/go/tour/welcome.article)（本机运行：`go install golang.org/x/website/tour@latest && tour`）
  - [Go by Example: Hello World](../../references/go/gobyexample/examples/hello-world/hello-world.go)
- 本机：`go help build`、`go help modules`、`go help environment`、`go env`、`go doc os.Hostname`
- 在线：https://go.dev/doc/ 、https://pkg.go.dev/cmd/go

## 7. 自测清单

- [ ] 能说出 `go.mod` 和 `go.sum` 各管什么
- [ ] 不查资料写出交叉编译 ARM64 静态二进制的完整命令
- [ ] 用 `go version -m` 看出一个二进制是用哪个 Go 版本编译的
- [ ] 知道 `GOPROXY`、`GOPRIVATE` 分别在什么时候要改
- [ ] `hostinfo` 能在没装 Go 的 RHEL 实验机上跑起来
