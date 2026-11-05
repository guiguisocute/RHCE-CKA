# template：运维小工具骨架

所有 P1~P11 项目都从这里复制起步。只用标准库，`go vet`、`go test -race` 和静态编译都已验证通过。

## 它演示了什么

| 写法 | 在哪 | 为什么 |
|---|---|---|
| `run(ctx, args, stdout, stderr) error` | `main.go` | `main` 只接线；逻辑可以在测试里直接调用，不用起子进程 |
| `flag.NewFlagSet(..., flag.ContinueOnError)` | `parseFlags` | 参数错误返回 error，而不是直接 `os.Exit`，测试能覆盖 |
| `signal.NotifyContext` | `realMain` | Ctrl+C / `systemctl stop` 发的 SIGTERM 会取消 ctx，长任务能优雅退出 |
| `log/slog` 写 stderr，结果写 stdout | `run` | `tool --json \| jq` 不会被日志污染 |
| 统一退出码 0/1/2/3 | `exitCode` | shell 脚本、Ansible 的 `failed_when`、CI 都能直接判断 |
| 表驱动测试 | `main_test.go` | 加用例只要加一行 |

退出码约定：`0` 成功；`1` 运行出错；`2` 参数用错；`3` 检查类工具发现了问题（比如 `fstab-lint` 查出错误）。

## 复制成新项目

以 P1 logstat 为例（在 `go/` 目录下执行）：

```bash
cp -r tools/template tools/logstat
```

```bash
sed -i 's/const toolName = "template"/const toolName = "logstat"/' tools/logstat/main.go
```

然后：

1. 改 `main.go` 顶部的包注释，写清这个工具做什么。
2. 改 `config` 和 `parseFlags`，换成你的参数。
3. 把 `greet` 换成你的业务逻辑，**输入用 `io.Reader`**（测试时传 `strings.NewReader`，运行时传文件），别在逻辑里直接 `os.Open`。
4. 改 `main_test.go`，先写测试用例再写实现。
5. 把这个 README 改成你项目的说明：用法、示例输出、退出码。

## 运行、测试、编译

```bash
go run ./tools/template -name ops -json
```

```bash
go test -race ./tools/template
```

```bash
CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build -trimpath -ldflags="-s -w" -o bin/template ./tools/template
```

最后一条编译出来的是**静态链接**的单个二进制（`file bin/template` 会显示 `statically linked`），可以直接 `scp` 到实验室里的 RHEL 虚拟机上运行，不需要装 Go。`bin/` 不要提交到仓库。

> 目录名不能以 `_` 或 `.` 开头：Go 工具链匹配 `./...` 时会跳过这类目录，`go test ./...` 就测不到它了。
