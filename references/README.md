# 官方资料库（references/）

这里只放**官方来源**的原始资料，不做修改，方便离线查阅、全文搜索（`grep -r`）。
学习笔记请写在 [`../notes/`](../notes/)，那边会反向链接到这里的具体文件。

> 抓取时间：2026-11-05。资料会过时，用 [`../scripts/update-references.sh`](../scripts/update-references.sh) 一键更新。

## 目录总览

| 路径 | 内容 | 官方来源 | 版本 / commit | 许可证 |
|---|---|---|---|---|
| [`cka/CKA_Curriculum_v1.37.pdf`](cka/CKA_Curriculum_v1.37.pdf) | **CKA 官方考纲**（v1.37，5 大领域及权重） | [cncf/curriculum](https://github.com/cncf/curriculum) | `0a8cc08` (2026-11-03) | CC BY 4.0 |
| [`cka/CNCF-CKA-curriculum-README.md`](cka/CNCF-CKA-curriculum-README.md) | 考纲说明与权重表 | 同上 | 同上 | CC BY 4.0 |
| [`cka/kubernetes-docs/`](cka/kubernetes-docs/) | **kubernetes.io/docs 原文**（concepts / tasks / setup / tutorials / reference / examples）。CKA 考试时唯一允许打开的就是这套文档的在线版 | [kubernetes/website](https://github.com/kubernetes/website) `content/en/docs` | `2fb3b0d` (2026-11-05) | CC BY 4.0 |
| [`cka/helm-docs/`](cka/helm-docs/) | Helm 官方文档（intro / howto / 命令参考 / chart 模板指南） | [helm/helm-www](https://github.com/helm/helm-www) `docs/` | `a876ef3` (2026-11-04) | MIT |
| [`cka/gateway-api-docs/`](cka/gateway-api-docs/) | Gateway API 官方文档（概念、入门、用户指南、API 参考） | [kubernetes-sigs/gateway-api](https://github.com/kubernetes-sigs/gateway-api) `site/content/en` | `69601c4` (2026-11-04) | Apache-2.0 |
| [`rhce/ansible-docs/`](rhce/ansible-docs/) | Ansible 官方用户文档（入门、inventory、playbook、vault、collections、命令行工具） | [ansible/ansible-documentation](https://github.com/ansible/ansible-documentation) `docs/docsite/rst` | `70d42b1` (2026-11-04) | GPL-3.0 |
| [`rhce/ansible-navigator-docs/`](rhce/ansible-navigator-docs/) | ansible-navigator（Automation content navigator）官方文档 | [ansible/ansible-navigator](https://github.com/ansible/ansible-navigator) `docs/` | `b412709` (2026-10-13) | Apache-2.0 |
| [`rhce/rhel-system-roles-upstream/`](rhce/rhel-system-roles-upstream/) | RHEL System Roles 上游 README（firewall / selinux / storage / timesync / network / crypto_policies） | [linux-system-roles](https://github.com/linux-system-roles) | 见下方 | MIT |
| [`rhel/`](rhel/) | **RHEL 10 官方 PDF 手册**——需在你自己电脑上运行脚本下载（见下文） | docs.redhat.com | — | CC BY-SA 3.0 |
| [`go/go-docs/`](go/go-docs/) | **Go 官方文档**（go.dev/doc：入门教程、How to Write Go Code、Effective Go、FAQ、模块、竞态检测、Go 1.26/1.27 发布说明） | [golang/website](https://github.com/golang/website) `_content/doc` | `6ac127a` (2026-11-04) | CC BY 4.0 / BSD |
| [`go/tour/`](go/tour/) | **Tour of Go** 官方交互教程原文（`.article` + 示例代码） | golang/website `_content/tour` | 同上 | BSD |
| [`go/spec/`](go/spec/) | Go 语言规范、内存模型 | [golang/go](https://github.com/golang/go) `doc/` | `35455b8` | BSD |
| [`go/gobyexample/`](go/gobyexample/) | Go by Example 全部示例（社区经典，非官方） | [mmcgrana/gobyexample](https://github.com/mmcgrana/gobyexample) | `5d9b1f1` (2026-10-31) | CC BY 3.0 |
| [`go/cobra-docs/`](go/cobra-docs/) | cobra 命令行框架文档（kubectl、helm 都用它） | [spf13/cobra](https://github.com/spf13/cobra) `site/content` | `adbc881` (2026-07-10) | Apache-2.0 |
| [`go/k8s/client-go-examples/`](go/k8s/client-go-examples/) | client-go 官方示例 | [kubernetes/client-go](https://github.com/kubernetes/client-go) `examples` | `675830c` (2026-11-05) | Apache-2.0 |
| [`go/k8s/sample-controller/`](go/k8s/sample-controller/) | 官方示例控制器（CRD + informer + workqueue） | [kubernetes/sample-controller](https://github.com/kubernetes/sample-controller) | `0c40c89` (2026-11-02) | Apache-2.0 |
| [`go/k8s/kubebuilder-book/`](go/k8s/kubebuilder-book/) | Kubebuilder Book（快速开始、CronJob 教程、参考） | [kubernetes-sigs/kubebuilder](https://github.com/kubernetes-sigs/kubebuilder) `docs/book/src` | `a537b6b` (2026-11-04) | Apache-2.0 |
| [`go/prometheus-client-golang-examples/`](go/prometheus-client-golang-examples/) | Prometheus Go 客户端官方示例（写 exporter 用） | [prometheus/client_golang](https://github.com/prometheus/client_golang) `examples` | `7c6a403` (2026-11-04) | Apache-2.0 |

linux-system-roles 各仓库 commit：firewall `4a74f21`、selinux `4e8b470`、storage `919b193`、timesync `5523983`、network `cd35767`、crypto_policies `36146a6`。

## 为什么红帽的 PDF 不在仓库里？

生成这个仓库的云端环境网络策略只放行了 GitHub，`docs.redhat.com`、`redhat.com`、`kubernetes.io` 都被拦截了。
Kubernetes / Ansible 的文档源码本身就托管在 GitHub 上，所以能直接拿到；而 RHEL 手册只在 docs.redhat.com 发布。

在你自己的电脑上执行（需要 `curl`）：

```bash
./scripts/fetch-rhel-docs.sh
```

脚本会把 RHCSA/RHCE 相关的 RHEL 10 手册（存储、文件系统、SELinux、防火墙、网络、DNF、System Roles 等）下载到 `references/rhel/`。
红帽文档采用 CC BY-SA 3.0 许可，可以提交到仓库里（PDF 体积较大，也可以只留在本地，`.gitignore` 默认忽略它们）。

## 考试时能用什么文档？（决定了你平时该怎么练）

| 考试 | 考场里可用的文档 | 平时练习建议 |
|---|---|---|
| **RHCSA EX200** | 只有考试机器上**本地安装的文档**：`man`、`--help`、`/usr/share/doc` | 练习 `man -k`、`man 5 fstab`、`/usr/share/doc/*/` 里找示例；不要依赖搜索引擎 |
| **RHCE EX294** | 同上，外加 `ansible-doc`、`ansible-navigator doc` | 熟练用 `ansible-doc -l`、`ansible-doc -s 模块名`、`ansible-navigator collections` 查模块参数和 EXAMPLES |
| **CKA** | 浏览器里只能开 kubernetes.io/docs、kubernetes.io/blog 等官方站点（以 LF 官网最新说明为准） | 平时就在 kubernetes.io 上找 YAML 模板，熟悉文档目录结构；本目录的 Markdown 原文可以 `grep` 快速定位页面 |

> 以上考场规则请以报名前的官方页面为准：
> [Red Hat EX200](https://www.redhat.com/en/services/training/ex200-red-hat-certified-system-administrator-rhcsa-exam)、
> [Red Hat EX294](https://www.redhat.com/en/services/training/ex294-red-hat-certified-engineer-rhce-exam-red-hat-enterprise-linux)、
> [LF CKA](https://training.linuxfoundation.org/certification/certified-kubernetes-administrator-cka/)、
> [CKA/CKAD/CKS 考生手册](https://docs.linuxfoundation.org/tc-docs/certification/tips-cka-and-ckad)。

## 怎么阅读这些 Markdown / RST 原文

- **Kubernetes / Helm / Gateway API**：Hugo/Docusaurus 格式的 Markdown，里面会有 `{{< glossary_tooltip ... >}}`、`{{% code_sample file="..." %}}` 之类的短代码，忽略即可；
  `code_sample file="pods/simple-pod.yaml"` 对应的文件在 [`cka/kubernetes-docs/examples/`](cka/kubernetes-docs/examples/) 下。
- **Ansible**：reStructuredText（`.rst`），GitHub 网页上可以直接渲染阅读。
- 快速搜索示例：

```bash
grep -rl "kind: NetworkPolicy" references/cka/kubernetes-docs | head
```

```bash
grep -rn "become_user" references/rhce/ansible-docs/playbook_guide | head
```

## Go 资料怎么读

Go 是本仓库的第四条学习线（运维开发方向），学习顺序见 [`../notes/go/README.md`](../notes/go/README.md)。

- `tour/*.article` 是 Tour of Go 的原文，直接读就行；想要可交互的版本，在本机运行 `go install golang.org/x/website/tour@latest` 后执行 `tour`。
- `go-docs/` 下的 `.html` 文件是 go.dev 网站的页面模板，浏览器可以直接打开（样式会缺失，内容完整）。
- 写代码时最常用的是本机命令：`go doc strings.Split`、`go doc -all os/exec`、`go help modules`。

## 官方但无法离线保存的资源（只给链接）

| 资源 | 说明 |
|---|---|
| [Red Hat Developer Subscription for Individuals](https://developers.redhat.com/products/rhel/download) | **免费**获取正版 RHEL（最多 16 台），做实验首选 |
| [RH024 Red Hat Enterprise Linux Technical Overview](https://www.redhat.com/en/services/training/rh024-red-hat-linux-technical-overview) | 红帽官方免费入门课 |
| [DO007 Ansible Basics: Automation Technical Overview](https://www.redhat.com/en/services/training/do007-ansible-essentials-simplicity-automation-technical-overview) | 红帽官方免费 Ansible 入门课 |
| [Red Hat Learning Community](https://learn.redhat.com/) | 官方学习社区，考试经验帖、考纲变更公告 |
| [pkg.go.dev](https://pkg.go.dev/) | Go 标准库和第三方包的在线文档 |
| [Go Playground](https://go.dev/play/) | 在线运行 Go 代码片段 |
| [Go 语言之旅（中文）](https://tour.go-zh.org/) | Go 中文社区翻译的 Tour of Go（社区维护） |
| [LeetCode 中国站](https://leetcode.cn/) / [LeetCode](https://leetcode.com/) | 刷题，两个站点题号一致；本仓库的刷题计划见 [`../labs/go/leetcode-plan.md`](../labs/go/leetcode-plan.md) |
| [LFS158 Introduction to Kubernetes](https://training.linuxfoundation.org/training/introduction-to-kubernetes/) | Linux Foundation 官方免费 Kubernetes 入门课 |
| [killer.sh](https://killer.sh/) | 购买 CKA 考试后附赠 2 次官方模拟考环境（比真题难，用于最后冲刺） |
| [Kubernetes 中文文档](https://kubernetes.io/zh-cn/docs/) | 官方中文翻译（考试时只能看英文版更稳妥，练习时可对照） |
