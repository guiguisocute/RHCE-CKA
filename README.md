# RHCE + CKA 备考知识库

一个把 **官方资料 → 知识网络 → 动手实验 → 复盘记录** 串起来的备考仓库。

- 目标：RHCSA（EX200）→ RHCE（EX294）→ CKA
- 起点：用过 Ubuntu、Docker / Docker Compose；没用过 RHEL，高阶知识较少
- 节奏：约 24 周，每周 12~15 小时（工作日 1.5 h + 周末两个半天）

## 从这里开始

1. **先看 [`tour.html`](tour.html) 考试导览**（下载仓库后用浏览器打开）：25 步动画讲解，一步一步介绍 RHCSA、RHCE、CKA 分别考什么，可以打开「朗读」听讲解。
2. **再打开 [`index.html`](index.html)**：可视化学习路线、逐周计划、可勾选的进度、知识网络浏览器。
3. 按路线进入 [`notes/`](notes/README.md) 学知识点，每篇笔记都标明了前置、后续、跨考试关联和官方文档位置。
4. 学完一个知识点就去 [`labs/`](labs/README.md) 动手，错题和心得写进 [`journal/`](journal/README.md)。
5. 查原始官方文档：[`references/`](references/README.md)。

## 仓库结构

```text
.
├── tour.html                  # 考试导览：25 步动画讲解 + 语音朗读
├── index.html                 # 学习路线总览（逐周计划 + 进度勾选 + 知识网络浏览器）
├── notes/                     # 知识网络：每篇笔记是一个节点，互相链接
│   ├── README.md              #   全局知识地图（Mermaid）+ 节点清单
│   ├── _template.md           #   新笔记模板
│   ├── 00-foundations/        #   公共基础：Ubuntu→RHEL、systemd、网络、YAML、容器、TLS、vim
│   ├── rhcsa/                 #   EX200：10 个节点
│   ├── rhce/                  #   EX294：12 个节点（11 号是连接 RHCSA 的枢纽）
│   └── cka/                   #   CKA：15 个节点，按考纲 5 大领域组织
├── labs/                      # 实验环境搭建 + 原创练习题 + 模拟考
│   ├── rhcsa/  rhce/  cka/
├── journal/                   # 学习日志、错题本（你自己写）
├── references/                # 官方原始资料（只读）
│   ├── cka/                   #   CKA 考纲 PDF、kubernetes.io 文档、Helm、Gateway API
│   ├── rhce/                  #   Ansible 文档、ansible-navigator、RHEL System Roles
│   └── rhel/                  #   RHEL 10 PDF 手册（运行脚本下载）
└── scripts/
    ├── fetch-rhel-docs.sh     # 下载 RHEL 官方 PDF 手册
    ├── update-references.sh   # 从官方 GitHub 仓库更新 references/
    └── check-links.py         # 检查笔记之间的相对链接有没有断
```

## 三门考试速览

| | RHCSA · EX200 | RHCE · EX294 | CKA |
|---|---|---|---|
| 主办 | Red Hat | Red Hat | Linux Foundation / CNCF |
| 形式 | 上机实操 | 上机实操（Ansible） | 上机实操（在线监考） |
| 版本 | RHEL 10 | 以 RHEL 10 / ansible-core 2.16 为基线的课程配套 | 考纲 v1.37 |
| 考场文档 | 本地 `man` / `/usr/share/doc` | 本地文档 + `ansible-doc` | kubernetes.io/docs 等官方站点 |
| 关系 | RHCE 的前置 | 需持有有效 RHCSA | 独立 |

> 红帽在 2026 年 5 月调整了认证体系（分方向、分等级），EX294 的页面标题也有变化；CKA 考纲会随 Kubernetes 版本更新。
> **报名前务必核对官方页面**：[EX200](https://www.redhat.com/en/services/training/ex200-red-hat-certified-system-administrator-rhcsa-exam) ·
> [EX294](https://www.redhat.com/en/services/training/ex294-red-hat-certified-engineer-rhce-exam-red-hat-enterprise-linux) ·
> [CKA](https://training.linuxfoundation.org/certification/certified-kubernetes-administrator-cka/) ·
> [CNCF 考纲仓库](https://github.com/cncf/curriculum)

## 为什么是 RHCSA → RHCE → CKA

- **RHCE 必须先有 RHCSA**，而且 EX294 本质上是「用 Ansible 自动化 RHCSA 的操作」，两门连着考，知识最热。
- **CKA 30% 是排错**，排错靠的是 Linux 基本功：systemd/journalctl、网络、证书、磁盘。前两门打下的底子在这里全部用得上。
- 你已有 Docker 经验，CKA 放最后不会卡在容器概念上，反而能把精力放在集群运维。

## 推荐工具

- 笔记阅读：[Obsidian](https://obsidian.md/)（打开整个仓库即可看到知识关系图谱）或 VS Code
- 实验：VMware Workstation / VirtualBox / UTM / KVM，见 [`labs/rhcsa/00-lab-setup.md`](labs/rhcsa/00-lab-setup.md)
- 免费正版 RHEL：[Red Hat Developer Subscription for Individuals](https://developers.redhat.com/products/rhel/download)

## 维护

```bash
./scripts/update-references.sh
```

```bash
python3 scripts/check-links.py
```

资料版权归各自官方所有，许可证见 [`references/README.md`](references/README.md)。
