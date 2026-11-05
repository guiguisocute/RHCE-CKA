# Go-05 运维常用标准库：文件、文本与命令

> **轨道**：[Go](README.md) ｜ **运维场景**：解析日志、遍历目录、安全地改配置文件、调用 `systemctl` 等外部命令——就是把你平时用 `grep`/`awk`/`find` 写的脚本换成 Go ｜ **建议用时**：4 h（第 5 周，第 7 周复习） ｜ **难度**：★★☆
>
> **前置**：[Go-04 方法、接口与泛型](04-methods-interfaces-generics.md) · [S2 Shell 脚本](../rhcsa/02-shell-scripting.md)（把脚本重写成 Go）
> **后续**：[Go-06 测试与工程化](06-testing-tooling.md) · [Go-09 配置、模板与 CLI](09-config-template-cli.md)
> **关联**（跨轨道）：[S1 基础工具](../rhcsa/01-essential-tools.md)（grep/find/重定向）· [F2 systemd 与 journald](../00-foundations/02-systemd-journald.md) · [S3 运行中的系统](../rhcsa/03-operate-running-systems.md)（日志位置）

## 1. 这个知识点在网络中的位置

这是 Go 运维开发里**最常用**的一节，标准库本身就够写大部分运维工具。学 RHCSA 时你会用 `grep 'Failed password' /var/log/secure | awk ... | sort | uniq -c`，这周就用 Go 写一个功能相同、但能处理各种边界情况、能写测试、能编成二进制分发的版本。这就是项目 P1。

## 2. 核心概念

| 包 | 对应的 Shell 习惯 | 常用 API |
|---|---|---|
| `os` | `cat`、`echo >`、`mkdir -p`、`test -f` | `ReadFile`、`WriteFile`、`Open`、`MkdirAll`、`Stat`、`Getenv`、`Hostname` |
| `bufio` | `while read line` | `NewScanner(r)` + `Scan()` + `Text()`；`NewWriter` 批量写 |
| `regexp` | `grep -E`、`sed` | `MustCompile`、`FindStringSubmatch`、`ReplaceAllString`（RE2 语法，不支持反向引用） |
| `strings` / `strconv` | `cut`、`tr`、`awk '{print $2}'` | `Fields`、`Split`、`Cut`、`HasPrefix`、`TrimSpace`；`Atoi`、`ParseFloat` |
| `path/filepath` | `find`、`basename`、`dirname` | `Join`、`WalkDir`、`Glob`、`Base`、`Dir`、`Rel` |
| `os/exec` | 在脚本里调用命令 | `CommandContext(ctx, name, args...)`、`Output`、`CombinedOutput`、`*exec.ExitError` |
| `encoding/json` | `jq` | `Marshal`、`Unmarshal`、`NewDecoder`；struct tag：`json:"name,omitempty"` |
| `flag` | `getopts` | `String`、`Int`、`Bool`、`Duration`、`Parse`、`Args` |
| `time` | `date`、`sleep`、`timeout` | `Now`、`Since`、`Parse`（参考时间 `2006-01-02 15:04:05`）、`time.Stamp` |

## 3. 必会操作

**运维场景示例：统计 SSH 登录失败最多的 IP，并检查 sshd 服务状态**

```go
// logstat：统计 sshd 登录失败最多的 IP（RHEL：/var/log/secure，Ubuntu：/var/log/auth.log）
package main

import (
	"bufio"
	"cmp"
	"context"
	"errors"
	"flag"
	"fmt"
	"io"
	"os"
	"os/exec"
	"regexp"
	"slices"
	"strings"
	"time"
)

var failedRe = regexp.MustCompile(`Failed password for (?:invalid user )?(\S+) from (\S+) port \d+`)

func countFailed(r io.Reader) (map[string]int, error) {
	counts := map[string]int{}
	sc := bufio.NewScanner(r)
	sc.Buffer(make([]byte, 0, 64*1024), 1024*1024) // 默认单行上限 64 KiB，这里放宽到 1 MiB
	for sc.Scan() {
		if m := failedRe.FindStringSubmatch(sc.Text()); m != nil {
			counts[m[2]]++ // m[1] 是用户名，m[2] 是 IP
		}
	}
	return counts, sc.Err()
}

// unitState 调用 systemctl is-active，并给命令加 3 秒超时
func unitState(unit string) (string, error) {
	ctx, cancel := context.WithTimeout(context.Background(), 3*time.Second)
	defer cancel()
	out, err := exec.CommandContext(ctx, "systemctl", "is-active", unit).Output()
	if ctx.Err() == context.DeadlineExceeded {
		return "", fmt.Errorf("systemctl is-active %s: 超时", unit)
	}
	state := strings.TrimSpace(string(out))
	var ee *exec.ExitError
	if errors.As(err, &ee) {
		if state == "" { // 连状态都没输出，说明是真出错了（比如容器里没有 systemd）
			return "", fmt.Errorf("systemctl is-active %s: %s", unit, strings.TrimSpace(string(ee.Stderr)))
		}
		return state, nil // inactive/failed 时退出码非 0，这不算执行失败
	}
	return state, err
}

func main() {
	path := flag.String("f", "/var/log/secure", "日志文件；- 表示标准输入")
	top := flag.Int("n", 5, "显示前 N 个 IP")
	unit := flag.String("unit", "", "顺便检查一个 systemd 服务的状态")
	flag.Parse()

	var r io.Reader = os.Stdin
	if *path != "-" {
		f, err := os.Open(*path)
		if err != nil {
			fmt.Fprintln(os.Stderr, err)
			os.Exit(1)
		}
		defer f.Close()
		r = f
	}
	counts, err := countFailed(r)
	if err != nil {
		fmt.Fprintln(os.Stderr, "read:", err)
		os.Exit(1)
	}

	type entry struct {
		IP string
		N  int
	}
	var list []entry
	for ip, n := range counts {
		list = append(list, entry{ip, n})
	}
	slices.SortFunc(list, func(a, b entry) int {
		if c := cmp.Compare(b.N, a.N); c != 0 { // 次数降序
			return c
		}
		return cmp.Compare(a.IP, b.IP) // 次数相同按 IP 升序，保证输出稳定
	})
	for i, e := range list {
		if i == *top {
			break
		}
		fmt.Printf("%-16s %d\n", e.IP, e.N)
	}

	if *unit != "" {
		state, err := unitState(*unit)
		if err != nil {
			fmt.Fprintln(os.Stderr, "unit:", err)
			os.Exit(1)
		}
		fmt.Printf("%s: %s\n", *unit, state)
	}
}
```

运行：`sudo go run . -n 3 -unit sshd`（读 /var/log/secure 需要 root）；没有这个文件的系统用 `journalctl -u sshd --no-pager | go run . -f -`。

**遍历目录、原子写文件、解析 journald**

```go
// bigFiles 找出超过 limit 字节的文件，相当于 find /var/log -size +100M
func bigFiles(root string, limit int64) ([]string, error) {
	var out []string
	err := filepath.WalkDir(root, func(path string, d fs.DirEntry, err error) error {
		if err != nil {
			return nil // 没权限的目录跳过，不中断整个遍历
		}
		if d.Type().IsRegular() {
			if info, err := d.Info(); err == nil && info.Size() > limit {
				out = append(out, fmt.Sprintf("%s %dMiB", path, info.Size()>>20))
			}
		}
		return nil
	})
	return out, err
}

// writeFileAtomic 先写临时文件再 rename，进程中途被杀也不会留下写了一半的配置
func writeFileAtomic(path string, data []byte, perm os.FileMode) error {
	tmp, err := os.CreateTemp(filepath.Dir(path), ".tmp-*") // 必须和目标在同一文件系统
	if err != nil {
		return err
	}
	defer os.Remove(tmp.Name())
	if _, err := tmp.Write(data); err != nil {
		tmp.Close()
		return err
	}
	if err := tmp.Close(); err != nil {
		return err
	}
	if err := os.Chmod(tmp.Name(), perm); err != nil {
		return err
	}
	return os.Rename(tmp.Name(), path)
}
```

解析 `journalctl -u sshd -o json`：每行是一个 JSON 对象，定义 ``struct{ Message string `json:"MESSAGE"` }`` 这样的字段映射后逐行 `json.Unmarshal` 即可。

## 4. 考试坑点

- **`bufio.Scanner` 单行超过 64 KiB 会停止**，`sc.Err()` 返回 `token too long`。处理日志一定要 `sc.Buffer(...)` 放宽，并且**检查 `sc.Err()`**。
- **`exec.Command("sh", "-c", "systemctl status " + name)` 有命令注入风险**：参数要分开传，`exec.Command("systemctl", "status", name)`。
- **超时被杀也是 `*exec.ExitError`**：判断退出码之前先看 `ctx.Err()`，否则会把「超时」当成「服务 inactive」。
- **时间格式要用参考时间**：`2006-01-02 15:04:05`，不是 `YYYY-MM-DD`。syslog 的 `Nov  5 08:01:02` 没有年份，`time.Parse(time.Stamp, ...)` 解析出来是 0 年，要自己补年份。
- **SELinux**：Go 程序以服务身份写 `/var/log`、`/etc` 时，被 SELinux 拒绝和被文件权限拒绝的报错都是 `permission denied`，要去 `ausearch -m avc` 里确认（见 [S9](../rhcsa/09-security-firewalld-selinux.md)）。

## 5. 动手练习

- 第 5 周项目：[P1 logstat](../../labs/go/projects.md#p1)（加 `-since` 时间过滤和 JSON 输出）；第 7 周项目：[P3 svcwatch](../../labs/go/projects.md#p3)（批量检查 systemd 服务，非 active 的打印 `systemctl status` 最后 5 行）。

**配套 LeetCode**

- 第 5 周（[刷题计划](../../labs/go/leetcode-plan.md#w5)）：
  - [71. 简化路径](https://leetcode.cn/problems/simplify-path/)：自己实现 `filepath.Clean` 的核心逻辑
  - [609. 在系统中查找重复文件](https://leetcode.cn/problems/find-duplicate-file-in-system/)：按内容分组，和 `fdupes` 找重复文件一个思路
  - [692. 前K个高频单词](https://leetcode.cn/problems/top-k-frequent-words/)：计数 + 自定义排序，几乎就是 logstat 的排序部分
- 第 7 周复习（[刷题计划](../../labs/go/leetcode-plan.md#w7)）：
  - [56. 合并区间](https://leetcode.cn/problems/merge-intervals/)：合并多段维护窗口
  - [57. 插入区间](https://leetcode.cn/problems/insert-interval/)
  - [435. 无重叠区间](https://leetcode.cn/problems/non-overlapping-intervals/)

## 6. 官方文档（本仓库离线版 + 本机查法）

- 离线（Go by Example 每个都是可运行的最小示例）：
  [reading-files](../../references/go/gobyexample/examples/reading-files/reading-files.go)、[writing-files](../../references/go/gobyexample/examples/writing-files/writing-files.go)、[line-filters](../../references/go/gobyexample/examples/line-filters/line-filters.go)、[regular-expressions](../../references/go/gobyexample/examples/regular-expressions/regular-expressions.go)、[file-paths](../../references/go/gobyexample/examples/file-paths/file-paths.go)、[directories](../../references/go/gobyexample/examples/directories/directories.go)、[spawning-processes](../../references/go/gobyexample/examples/spawning-processes/spawning-processes.go)、[json](../../references/go/gobyexample/examples/json/json.go)、[command-line-flags](../../references/go/gobyexample/examples/command-line-flags/command-line-flags.go)、[time-formatting-parsing](../../references/go/gobyexample/examples/time-formatting-parsing/time-formatting-parsing.go)、[environment-variables](../../references/go/gobyexample/examples/environment-variables/environment-variables.go)、[temporary-files-and-directories](../../references/go/gobyexample/examples/temporary-files-and-directories/temporary-files-and-directories.go)
- 官方文档：[Effective Go](../../references/go/go-docs/effective_go.html)、[JSON 教程](../../references/go/go-docs/tutorial/json.md)
- 本机：`go doc bufio.Scanner`、`go doc os/exec.CommandContext`、`go doc -all regexp/syntax | less`（RE2 语法）、`go doc time.Layout`
- 在线：https://pkg.go.dev/std

## 7. 自测清单

- [ ] 不查资料写出「逐行读文件 + 正则提取 + 计数」的完整代码
- [ ] 知道 `bufio.Scanner` 的 64 KiB 限制以及怎么放宽
- [ ] 能调用外部命令并区分「命令执行失败」「非 0 退出码」「超时」三种情况
- [ ] 会写原子替换配置文件的函数
- [ ] 能用 `filepath.WalkDir` 实现 `find -size +100M`
