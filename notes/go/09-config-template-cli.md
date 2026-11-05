# Go-09 配置、模板与 CLI：YAML、text/template、cobra

> **轨道**：[Go](README.md) ｜ **运维场景**：读 YAML 变量文件、按模板批量生成配置、做一个带子命令和 `--help` 的运维工具 ｜ **建议用时**：4 h（第 11 周，第 12 周做项目） ｜ **难度**：★★☆
>
> **前置**：[Go-05 运维常用标准库](05-stdlib-files-text-exec.md)
> **后续**：[Go-10 SSH 远程执行与并行任务](10-ssh-parallel-exec.md)
> **关联**（跨轨道）：[RHCE-07 Jinja2 模板](../rhce/07-jinja2-templates.md) · [RHCE-05 变量与 facts](../rhce/05-variables-facts.md) · [CKA-07 Helm 与 Kustomize](../cka/07-helm-kustomize.md)（**Helm 模板就是 Go 模板**）· [F4 YAML](../00-foundations/04-yaml.md)

## 1. 这个知识点在网络中的位置

这一周正好在学 RHCE 的变量和 Jinja2 模板。Ansible 的 `template` 模块做三件事：读变量、渲染模板、写文件。用 Go 实现一遍，就是 `yaml.v3` + `text/template` + `os.WriteFile`。
更重要的是：到了 CKA，Helm chart 里的 `{{ .Values.replicaCount }}` 用的正是 Go 的 `text/template`，外加 Sprig 函数库。这一节学的语法，Helm 里原样能用。

| 你学过的 | Go 里对应的 |
|---|---|
| Ansible `vars.yml` / `group_vars/` | 一个 struct + `yaml.Unmarshal` |
| Jinja2 `{{ var }}`、`{% for %}`、`{% if %}` | `{{ .Var }}`、`{{ range }}`、`{{ if }}`，统一用 `{{ end }}` 结束 |
| Jinja2 过滤器 `{{ name \| upper }}` | 管道 + 自定义函数 `{{ .Name \| upper }}`（`template.FuncMap`） |
| Helm `{{ .Values.x \| default 3 }}` | 同一种语法；`default`、`quote` 这些函数来自 Sprig，标准库没有 |
| `ansible-playbook --help`、子命令 | cobra：`hostsgen render --vars x.yml` |

## 2. 核心概念

- **struct tag**：`yaml:"domain"` 告诉 yaml.v3 字段对应哪个 key。JSON 用 `json:"..."`（标准库 `encoding/json`）。
- **模板上下文**：`{{ . }}` 是传进来的数据；`range` 里 `.` 变成当前元素，要访问外层用 `$`（如 `{{ $.Domain }}`）。
- **空白控制**：`{{-` 吃掉左边的空白和换行，`-}}` 吃掉右边的。生成配置文件时多数格式问题都出在这里。Jinja2 用的是 `{%-`，Helm 和 Go 一样。
- **`text/template` vs `html/template`**：生成配置文件用 `text/template`；`html/template` 会做 HTML 转义，用在配置文件上会把 `<`、`&` 转坏。
- **cobra**：kubectl、helm、hugo 的命令行都是 cobra 写的。`Command` 组成树，每个命令带自己的 flags，自动生成 `--help` 和 shell 补全。

## 3. 必会操作

```bash
mkdir hostsgen && cd hostsgen && go mod init example.com/hostsgen
go get gopkg.in/yaml.v3@v3.0.1 github.com/spf13/cobra@v1.10.2   # 写作时实际拉到的版本，以 pkg.go.dev 最新为准
```

`vars.yml` 和 `hosts.tmpl`：

```yaml
domain: lab.local
hosts:
  - name: node1
    ip: 192.168.56.11
    tags: [web]
  - name: node2
    ip: 192.168.56.12
    tags: [web, db]
```

```text
# 由 hostsgen 生成，请勿手改
127.0.0.1   localhost
{{- range .Hosts }}
{{ printf "%-15s" .IP }} {{ .Name }}.{{ $.Domain }} {{ .Name }}  # {{ join .Tags "," | upper }}
{{- end }}
```

`main.go`（已在 Go 1.24 上编译运行）：

```go
package main

import (
	"bytes"
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"text/template"

	"github.com/spf13/cobra"
	"gopkg.in/yaml.v3"
)

type Vars struct {
	Domain string `yaml:"domain"`
	Hosts  []struct {
		Name string   `yaml:"name"`
		IP   string   `yaml:"ip"`
		Tags []string `yaml:"tags"`
	} `yaml:"hosts"`
}

func render(varsFile, tmplFile string) ([]byte, error) {
	raw, err := os.ReadFile(varsFile)
	if err != nil {
		return nil, fmt.Errorf("读取变量文件: %w", err)
	}
	var v Vars
	if err := yaml.Unmarshal(raw, &v); err != nil {
		return nil, fmt.Errorf("解析 YAML: %w", err)
	}
	funcs := template.FuncMap{"upper": strings.ToUpper, "join": strings.Join} // 自定义「过滤器」
	t, err := template.New("main").Funcs(funcs).Option("missingkey=error").ParseFiles(tmplFile)
	if err != nil {
		return nil, fmt.Errorf("解析模板: %w", err)
	}
	var buf bytes.Buffer
	if err := t.ExecuteTemplate(&buf, filepath.Base(tmplFile), v); err != nil {
		return nil, fmt.Errorf("渲染模板: %w", err)
	}
	return buf.Bytes(), nil
}

func main() {
	var varsFile, tmplFile, out string
	root := &cobra.Command{Use: "hostsgen", Short: "用 YAML 变量渲染配置文件", SilenceUsage: true}
	renderCmd := &cobra.Command{
		Use:   "render",
		Short: "渲染模板并写到 --out（不给则打印到标准输出）",
		RunE: func(cmd *cobra.Command, args []string) error {
			data, err := render(varsFile, tmplFile)
			if err != nil {
				return err
			}
			if out == "" {
				_, err = cmd.OutOrStdout().Write(data)
				return err
			}
			return os.WriteFile(out, data, 0o644)
		},
	}
	renderCmd.Flags().StringVar(&varsFile, "vars", "vars.yml", "变量文件")
	renderCmd.Flags().StringVar(&tmplFile, "tmpl", "hosts.tmpl", "模板文件")
	renderCmd.Flags().StringVarP(&out, "out", "o", "", "输出文件")
	root.AddCommand(renderCmd)
	if err := root.Execute(); err != nil {
		os.Exit(1)
	}
}
```

```bash
go run . render                    # 打印渲染结果
go run . render -o /tmp/hosts      # 写文件
go run . render --help             # cobra 自动生成的帮助
```

输出：

```text
# 由 hostsgen 生成，请勿手改
127.0.0.1   localhost
192.168.56.11   node1.lab.local node1  # WEB
192.168.56.12   node2.lab.local node2  # WEB,DB
```

### 3.1 运维场景示例：把它变成「幂等的 template 模块」

Ansible 的 `template` 模块在内容没变时报 `ok`，变了才报 `changed` 并触发 handler。给上面的工具加三步就是同样的行为，这正是 [P5 tmplgen](../../labs/go/projects.md#p5) 的要求：

1. 渲染到内存（上面的 `render` 已经做到）。
2. 读出目标文件的旧内容，`bytes.Equal` 比较；相同就输出 `ok` 并退出。
3. 不同就先写到同目录的临时文件，再 `os.Rename` 原子替换，输出 `changed`；可选地执行 `--notify "systemctl reload nginx"`（≈ handler）。

## 4. 考试坑点

- 模板里访问不存在的**结构体字段**，执行时直接报错（`can't evaluate field Nope`）；`missingkey=error` 只影响 **map** 里缺失的 key。用 map 存变量时一定要加这个选项，否则缺的变量会被渲染成 `<no value>`。
- `range` 里忘了用 `$.Domain` 访问外层变量，是新手最常见的错误。
- 不加 `SilenceUsage: true` 时，cobra 每次 `RunE` 返回错误都会把整段用法打印出来，日志会很乱。
- yaml.v3 对缩进和类型很严格：`port: "8080"` 是字符串，`port: 8080` 是整数，struct 字段类型要对上（和 [F4 YAML](../00-foundations/04-yaml.md) 讲的一样）。
- 写配置文件别直接覆盖：先写临时文件再 `os.Rename`，避免写到一半进程退出，留下半个文件。

## 5. 动手练习

- 项目：[P5 tmplgen：模板生成配置，幂等写入](../../labs/go/projects.md#p5)（第 12 周）
- 小练习：用同一份 `vars.yml` 再写一个模板，生成 Ansible 的 INI inventory（`[web]` 组下列出带 `web` 标签的主机）。

**配套 LeetCode（第 11~12 周，[刷题计划](../../labs/go/leetcode-plan.md#w11)）**

- [394. 字符串解码](https://leetcode.cn/problems/decode-string/)：`3[a2[c]]` 的展开，和模板引擎处理嵌套 `{{ range }}` 是一个思路，用栈
- [150. 逆波兰表达式求值](https://leetcode.cn/problems/evaluate-reverse-polish-notation/)：栈的基本功
- [224. 基本计算器](https://leetcode.cn/problems/basic-calculator/)（困难，可选）：带括号的表达式求值
- 第 12 周（[计划](../../labs/go/leetcode-plan.md#w12)）：[146. LRU 缓存](https://leetcode.cn/problems/lru-cache/)（Ansible 的 fact 缓存）、[981. 基于时间的键值存储](https://leetcode.cn/problems/time-based-key-value-store/)（≈ etcd 按 revision 读历史值）

## 6. 官方文档（本仓库离线版 + 本机查法）

- Go by Example：[text-templates.go](../../references/go/gobyexample/examples/text-templates/text-templates.go)、[json.go](../../references/go/gobyexample/examples/json/json.go)
- cobra：[user_guide.md](../../references/go/cobra-docs/user_guide.md)
- 官方教程：[JSON 与 Go](../../references/go/go-docs/tutorial/json.md)
- Helm 模板（同一套语法）：[functions_and_pipelines.mdx](../../references/cka/helm-docs/chart_template_guide/functions_and_pipelines.mdx)、[control_structures.md](../../references/cka/helm-docs/chart_template_guide/control_structures.md)、[function_list.mdx](../../references/cka/helm-docs/chart_template_guide/function_list.mdx)
- 本机：`go doc text/template`（包文档开头就是完整的语法说明）、`go doc gopkg.in/yaml.v3 Unmarshal`

## 7. 自测清单

- [ ] 不看资料写出读 YAML → 渲染模板 → 写文件的完整流程
- [ ] 能说出 `{{- ... -}}` 两边的减号各自吃掉什么
- [ ] 能解释 `range` 里 `.` 和 `$` 的区别
- [ ] 能把一段 Jinja2 模板（`for`、`if`、过滤器）翻译成 Go 模板
- [ ] 用 cobra 写一个带两个子命令（`render`、`diff`）的工具，`--help` 输出正常
- [ ] 能读懂 Helm chart 里 `templates/deployment.yaml` 的每一个 `{{ }}`
