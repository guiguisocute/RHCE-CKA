# Go-06 测试与工程化

> **轨道**：[Go](README.md) ｜ **运维场景**：运维工具一旦出 bug 就可能改坏一批机器的配置，必须有测试；还要能稳定地构建、打版本号、扫漏洞 ｜ **建议用时**：4 h（第 6 周） ｜ **难度**：★★☆
>
> **前置**：[Go-05 运维常用标准库](05-stdlib-files-text-exec.md)
> **后续**：之后每个节点、每个项目、每道 LeetCode 都要求带测试
> **关联**（跨轨道）：[S5 文件系统与 fstab](../rhcsa/05-file-systems-nfs-autofs.md)（本节示例解析的就是 /etc/fstab）· [E4 Playbook](../rhce/04-playbooks.md)（`--check` 模式和测试是同一种「先验证再动手」的习惯）

## 1. 这个知识点在网络中的位置

RHCSA 里你知道 `/etc/fstab` 写错一个字段，机器重启就进 emergency 模式。写一个「fstab 检查器」时，你必须保证它对各种奇怪的输入都给出正确判断——这就是测试的价值。Go 自带测试框架，不需要装 pytest 之类的东西：文件名以 `_test.go` 结尾，函数以 `Test` 开头，`go test` 就能跑。

## 2. 核心概念

| 概念 | 说明 |
|---|---|
| 单元测试 | `func TestXxx(t *testing.T)`，用 `t.Errorf`（继续）/ `t.Fatalf`（立即停止）报告失败 |
| 表驱动测试 | 把输入和期望输出写成一张表，用 `t.Run` 逐行跑子测试。Go 社区的标准写法 |
| `t.TempDir()` | 自动创建并在测试后删除的临时目录，测试读写文件的工具必备 |
| `testdata/` | 放测试输入文件的目录，`go build` 会忽略它 |
| 覆盖率 | `go test -cover`；`-coverprofile=c.out` + `go tool cover -html=c.out` 看哪些行没测到 |
| 竞态检测 | `go test -race` 找并发读写 bug（G7 必用） |
| 基准测试 | `func BenchmarkXxx(b *testing.B)`；Go 1.24+ 推荐 `for b.Loop() {}` |
| 模糊测试 | `func FuzzXxx(f *testing.F)`（Go 1.18+），自动生成随机输入找 panic 和边界 bug |
| 示例测试 | `func ExampleXxx()` + `// Output:` 注释，既是文档也是测试 |

**项目布局（够用的版本）**

```text
fstab-lint/
├── go.mod
├── main.go            # 只负责解析参数、调用 run()、打印错误、退出
├── internal/fstab/    # 业务逻辑放这里，可测试；internal 下的包不能被别的 module 导入
│   ├── fstab.go
│   ├── fstab_test.go
│   └── testdata/bad-fstab
└── Makefile
```

## 3. 必会操作

`internal/fstab/fstab.go`：

```go
// Package fstab 解析 /etc/fstab 的一行
package fstab

import (
	"fmt"
	"strconv"
	"strings"
)

type Entry struct {
	Spec    string // UUID=... 或 /dev/...
	File    string // 挂载点
	VFSType string // xfs、ext4、swap、nfs……
	Options []string
	Freq    int
	PassNo  int
}

// ParseLine 解析一行；空行和注释返回 ok=false
func ParseLine(line string) (e Entry, ok bool, err error) {
	line = strings.TrimSpace(line)
	if line == "" || strings.HasPrefix(line, "#") {
		return Entry{}, false, nil
	}
	f := strings.Fields(line)
	if len(f) < 4 || len(f) > 6 {
		return Entry{}, false, fmt.Errorf("需要 4~6 个字段，实际 %d 个", len(f))
	}
	e = Entry{Spec: f[0], File: f[1], VFSType: f[2], Options: strings.Split(f[3], ",")}
	if len(f) >= 5 {
		if e.Freq, err = strconv.Atoi(f[4]); err != nil {
			return Entry{}, false, fmt.Errorf("第 5 列 dump 不是数字: %w", err)
		}
	}
	if len(f) == 6 {
		if e.PassNo, err = strconv.Atoi(f[5]); err != nil {
			return Entry{}, false, fmt.Errorf("第 6 列 pass 不是数字: %w", err)
		}
	}
	if e.VFSType != "swap" && !strings.HasPrefix(e.File, "/") {
		return Entry{}, false, fmt.Errorf("挂载点 %q 必须是绝对路径", e.File)
	}
	return e, true, nil
}
```

`internal/fstab/fstab_test.go`（节选：表驱动测试、基准测试、模糊测试）：

```go
func TestParseLine(t *testing.T) {
	tests := []struct {
		name    string
		line    string
		wantOK  bool
		wantErr bool
	}{
		{name: "注释", line: "# /etc/fstab"},
		{name: "空行", line: "   "},
		{name: "xfs 用 UUID", line: "UUID=1b2c /data xfs defaults 0 0", wantOK: true},
		{name: "swap", line: "/dev/vg0/swap none swap defaults 0 0", wantOK: true},
		{name: "字段太少", line: "/dev/vdb1 /data", wantErr: true},
		{name: "pass 不是数字", line: "/dev/vdb1 /data xfs defaults 0 x", wantErr: true},
		{name: "相对路径挂载点", line: "/dev/vdb1 data xfs defaults 0 0", wantErr: true},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			_, ok, err := ParseLine(tt.line)
			if (err != nil) != tt.wantErr {
				t.Fatalf("err = %v, wantErr %v", err, tt.wantErr)
			}
			if ok != tt.wantOK {
				t.Fatalf("ok = %v, want %v", ok, tt.wantOK)
			}
		})
	}
}

func BenchmarkParseLine(b *testing.B) {
	for b.Loop() { // Go 1.24+；旧版本写 for i := 0; i < b.N; i++
		_, _, _ = ParseLine("UUID=1b2c /data xfs defaults,noatime 0 2")
	}
}

func FuzzParseLine(f *testing.F) {
	f.Add("UUID=1b2c /data xfs defaults 0 0")
	f.Fuzz(func(t *testing.T, line string) {
		e, ok, err := ParseLine(line) // 不管输入什么都不能 panic
		if ok && err == nil && e.VFSType != "swap" && !strings.HasPrefix(e.File, "/") {
			t.Errorf("接受了非法挂载点 %q", e.File)
		}
	})
}
```

```bash
go test ./...                          # 跑全部测试
go test -v -run 'TestParseLine/swap' ./internal/fstab   # 只跑一个子测试
go test -race -cover ./...             # 竞态检测 + 覆盖率
go test -run '^$' -bench . ./...       # 只跑基准测试
go test -run '^$' -fuzz FuzzParseLine -fuzztime 30s ./internal/fstab   # 模糊测试 30 秒
go test -count=1 ./...                 # 禁用测试缓存，强制重跑
```

**让 main 可测试：`run()` 模式**

```go
func main() {
	if err := run(os.Args[1:], os.Stdout); err != nil {
		fmt.Fprintln(os.Stderr, "fstab-lint:", err)
		os.Exit(1)
	}
}

func run(args []string, out io.Writer) error { /* 真正的逻辑，测试里传 bytes.Buffer 进来 */ return nil }
```

**版本号、工具和漏洞扫描**

```bash
go build -ldflags "-X main.version=$(git describe --tags --always)" -o fstab-lint .   # 需要 var version = "dev"
go get -tool golang.org/x/vuln/cmd/govulncheck   # Go 1.24+：把工具版本记进 go.mod
go tool govulncheck ./...                        # 扫描依赖里的已知漏洞（官方工具）
```

一个最小的 `Makefile`：

```makefile
.PHONY: test build lint
test:
	go test -race -cover ./...
lint:
	gofmt -l . && go vet ./...
build: lint test
	CGO_ENABLED=0 go build -trimpath -ldflags="-s -w" -o bin/fstab-lint .
```

## 4. 考试坑点

- **测试文件和代码放在同一个 package**：`package fstab`，这样能测未导出的函数；想只测公开 API 就写 `package fstab_test`。
- **测试结果被缓存**：输入文件变了但代码没变时，`go test` 可能直接显示 `(cached)`，加 `-count=1`。
- **测试依赖真实环境**：测试里别读真的 `/etc/fstab`、别调真的 `systemctl`。把输入抽象成 `io.Reader`（G4），用 `t.TempDir()` 造文件。
- **`t.Fatal` 在子 goroutine 里调用无效**：只能在运行测试的那个 goroutine 里调用。
- **只看覆盖率数字**：覆盖率 90% 不代表边界情况都测了，表驱动测试里专门加「坏输入」行。

## 5. 动手练习

- 第 6 周项目：[P2 fstab-lint](../../labs/go/projects.md#p2)：读整个 fstab，检查字段数、挂载点是否存在、UUID 是否能在 `/dev/disk/by-uuid/` 找到、是否有重复挂载点；`testdata/` 里放 5 个故意写错的 fstab。
- 回头给 P1 logstat 补上表驱动测试，覆盖率做到 80% 以上。

**配套 LeetCode（第 6 周，[刷题计划](../../labs/go/leetcode-plan.md#w6)）**

这三道都是「边界情况特别多」的题，很适合先写测试表再写代码：

- [165. 比较版本号](https://leetcode.cn/problems/compare-version-numbers/)：`dnf` 比较软件包版本时做的就是这件事
- [468. 验证IP地址](https://leetcode.cn/problems/validate-ip-address/)：先自己实现，再和 `net/netip.ParseAddr` 的结果对比
- [8. 字符串转换整数 (atoi)](https://leetcode.cn/problems/string-to-integer-atoi/)：和 `strconv.Atoi` 对比，体会标准库处理了多少细节

## 6. 官方文档（本仓库离线版 + 本机查法）

- 离线：
  - [官方教程：添加测试](../../references/go/go-docs/tutorial/add-a-test.html)、[模糊测试教程](../../references/go/go-docs/tutorial/fuzz.md)、[模糊测试说明](../../references/go/go-docs/fuzz.md)
  - [竞态检测器](../../references/go/go-docs/articles/race_detector.html)
  - [模块目录布局](../../references/go/go-docs/modules/layout.md)
  - [govulncheck 教程](../../references/go/go-docs/tutorial/govulncheck.md)
  - [Go by Example: testing-and-benchmarking](../../references/go/gobyexample/examples/testing-and-benchmarking/main_test.go)
- 本机：`go help test`、`go help testflag`、`go doc testing.T`、`go doc testing.B.Loop`
- 在线：https://pkg.go.dev/testing 、https://go.dev/wiki/TableDrivenTests

## 7. 自测清单

- [ ] 能不看资料写出一个带 `t.Run` 的表驱动测试
- [ ] 会用 `t.TempDir()` 测试读写文件的函数
- [ ] 知道 `-race`、`-cover`、`-count=1`、`-run` 各自的作用
- [ ] 会用 `-ldflags -X` 给二进制注入版本号
- [ ] 把 main 拆成 `main()` + `run()`，并给 `run()` 写了测试
