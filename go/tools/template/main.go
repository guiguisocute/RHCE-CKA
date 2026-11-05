// Command template 是运维小工具的可复制骨架。
//
// 它演示了本仓库所有 Go 工具共用的写法：
//   - main 只负责接线，逻辑都在 run(ctx, args, stdout, stderr) error 里，方便测试；
//   - 用 flag.NewFlagSet 解析参数，不碰全局 flag.CommandLine；
//   - 用 signal.NotifyContext 让 Ctrl+C / SIGTERM 取消正在进行的工作；
//   - 用 log/slog 往 stderr 打结构化日志，stdout 只放结果（方便管道和 --json）；
//   - 用统一的退出码约定。
//
// 复制成新项目的步骤见同目录 README.md。
package main

import (
	"context"
	"encoding/json"
	"errors"
	"flag"
	"fmt"
	"io"
	"log/slog"
	"os"
	"os/signal"
	"strings"
	"syscall"
	"time"
)

// 退出码约定（所有工具保持一致，方便在 shell 脚本和 CI 里判断）。
const (
	exitOK       = 0 // 成功
	exitError    = 1 // 运行时出错（文件读不了、网络失败……）
	exitUsage    = 2 // 参数用错
	exitFindings = 3 // 检查类工具：运行正常，但发现了问题（比如 fstab 有错）
)

// errFindings 由检查类工具返回，表示「检查完成，但有问题」。
var errFindings = errors.New("检查发现问题")

// usageError 表示参数错误，退出码为 exitUsage。
type usageError struct{ err error }

func (e usageError) Error() string { return e.err.Error() }
func (e usageError) Unwrap() error { return e.err }

const toolName = "template"

type config struct {
	name    string
	timeout time.Duration
	jsonOut bool
	verbose bool
	rest    []string // 位置参数
}

func parseFlags(args []string, stderr io.Writer) (config, error) {
	var c config
	fs := flag.NewFlagSet(toolName, flag.ContinueOnError)
	fs.SetOutput(stderr)
	fs.StringVar(&c.name, "name", "world", "要问候的名字")
	fs.DurationVar(&c.timeout, "timeout", 5*time.Second, "整条命令的超时时间，例如 500ms、10s")
	fs.BoolVar(&c.jsonOut, "json", false, "以 JSON 输出结果")
	fs.BoolVar(&c.verbose, "v", false, "输出调试日志")
	fs.Usage = func() {
		fmt.Fprintf(fs.Output(), "用法：%s [选项] [参数...]\n\n选项：\n", toolName)
		fs.PrintDefaults()
	}

	if err := fs.Parse(args); err != nil {
		if errors.Is(err, flag.ErrHelp) {
			return c, err // -h：打印帮助后正常退出
		}
		return c, usageError{err} // flag 包已经把错误和用法打印到 stderr
	}
	if strings.TrimSpace(c.name) == "" {
		fmt.Fprintln(stderr, "错误：--name 不能为空")
		fs.Usage()
		return c, usageError{errors.New("--name 不能为空")}
	}
	if c.timeout <= 0 {
		fmt.Fprintln(stderr, "错误：--timeout 必须大于 0")
		return c, usageError{errors.New("--timeout 必须大于 0")}
	}
	c.rest = fs.Args()
	return c, nil
}

// run 是真正的入口。它不调用 os.Exit、不直接读写 os.Stdout，因此可以在测试里直接调用。
func run(ctx context.Context, args []string, stdout, stderr io.Writer) error {
	cfg, err := parseFlags(args, stderr)
	if err != nil {
		return err
	}

	level := slog.LevelInfo
	if cfg.verbose {
		level = slog.LevelDebug
	}
	logger := slog.New(slog.NewTextHandler(stderr, &slog.HandlerOptions{Level: level}))

	ctx, cancel := context.WithTimeout(ctx, cfg.timeout)
	defer cancel()

	logger.Debug("开始执行", "name", cfg.name, "args", cfg.rest)
	msg, err := greet(ctx, cfg.name)
	if err != nil {
		return fmt.Errorf("生成问候语：%w", err)
	}

	if cfg.jsonOut {
		return json.NewEncoder(stdout).Encode(result{Message: msg})
	}
	_, err = fmt.Fprintln(stdout, msg)
	return err
}

type result struct {
	Message string `json:"message"`
}

// greet 是业务逻辑示例：输入明确、接受 ctx、返回 error，替换成你自己的逻辑即可。
func greet(ctx context.Context, name string) (string, error) {
	if err := ctx.Err(); err != nil {
		return "", err
	}
	return "hello, " + name, nil
}

// exitCode 把 run 返回的错误翻译成退出码，并在需要时把错误信息写到 stderr。
func exitCode(err error, stderr io.Writer) int {
	var ue usageError
	switch {
	case err == nil, errors.Is(err, flag.ErrHelp):
		return exitOK
	case errors.As(err, &ue):
		return exitUsage
	case errors.Is(err, errFindings):
		return exitFindings
	default:
		fmt.Fprintf(stderr, "%s: %v\n", toolName, err)
		return exitError
	}
}

func realMain() int {
	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer stop()
	return exitCode(run(ctx, os.Args[1:], os.Stdout, os.Stderr), os.Stderr)
}

func main() {
	// os.Exit 不会执行 defer，所以把 defer 都放进 realMain。
	os.Exit(realMain())
}
