# RHCE 轨道（EX294）：用 Ansible 自动化 RHEL

> **上一站**：[RHCSA 轨道](../rhcsa/README.md) ｜ **下一站**：[CKA 轨道](../cka/README.md) ｜ **总地图**：[知识网络](../README.md)
>
> **练习**：[实验环境搭建](../../labs/rhce/00-lab-setup.md) · [分节练习 30+ 题](../../labs/rhce/practice-set-1.md) · [原创模拟考](../../labs/rhce/mock-exam.md)

## 1. 考试速览

| 项目 | 说明 |
|---|---|
| 考试代号 | **EX294**（上机实操，没有选择题） |
| 时长 | 约 4 小时（以报名页为准） |
| 证书构成 | **RHCE = 有效期内的 RHCSA（EX200）+ 通过 EX294**。所以必须先考 RHCSA |
| 考什么 | 在一台控制节点上写 inventory / ansible.cfg / playbook / role，把一批受管节点配置到题目要求的状态——本质是「**用 Ansible 完成 RHCSA 的活**」 |
| 判分方式 | 考后由脚本检查受管节点的**最终状态**（以及你留下的 playbook 文件是否存在、能否运行）。过程不看，结果才算数 |
| 考场文档 | **只有本机文档**：`ansible-doc`、`ansible-navigator doc`、`man`、`/usr/share/doc`、`/usr/share/ansible/collections` 下的内容。**不能上网** |

### 2026 年的版本变化（⚠️ 以官方页面为准）

以下信息来自 2026-11 的搜索摘要，**生成本仓库的环境无法直接访问 redhat.com 核实**，报名前务必打开官方页面确认：

- 2026-05 红帽认证体系改版（按 Enterprise Linux / Ansible / OpenShift 等方向划分等级），EX294 页面标题变为
  「**Red Hat Certified Advanced System Administrator in Ansible Exam**」。
- 配套课程 **AU294** 基于 **RHEL 10 + ansible-core 2.16 + Ansible Automation Platform 2.6**。
- 官方页面：<https://www.redhat.com/en/services/training/ex294-red-hat-certified-engineer-rhce-exam-red-hat-enterprise-linux>
- 红帽同一门考试往往同时开放多个版本（如 RHEL 9 版、RHEL 10 版），**报名时选的版本决定你的考纲**，以报名确认邮件为准。

## 2. 考纲领域 → 笔记映射

下表按 RHEL 9 版 EX294 考纲的结构整理（RHEL 10 版大方向一致，细项以官方页面为准）：

| 考纲领域（英文原名） | 要点 | 对应笔记 |
|---|---|---|
| Understand core components of Ansible | inventory、modules、variables、facts、loops、conditionals、plays、handlers、task failure、playbooks、configuration files、roles；**会用自带文档查模块** | [E1](01-ansible-architecture.md) · [E3](03-adhoc-modules-docs.md) · [E5](05-variables-facts.md) · [E6](06-loops-conditions-errors.md) |
| Use roles and Ansible Content Collections | 创建/安装 role；安装 collection 并在 playbook 中使用 | [E8](08-roles.md) · [E9](09-collections-navigator.md) · [E12](12-rhel-system-roles.md) |
| Install and configure an Ansible control node | 安装软件包、静态 inventory、`ansible.cfg`、主机组 | [E1](01-ansible-architecture.md) · [E2](02-inventory-and-config.md) |
| Configure Ansible managed nodes | 分发 SSH key、配置提权（sudo）、部署文件、把简单 shell 脚本改写成 playbook | [E2](02-inventory-and-config.md) · [E6](06-loops-conditions-errors.md) · [E11](11-automate-rhcsa-tasks.md) |
| Run playbooks with Automation content navigator | `ansible-navigator run`、用 navigator 查 collection 里的新模块、用 navigator 查看 inventory / 配置 | [E9](09-collections-navigator.md) |
| Create Ansible plays and playbooks | 常用模块、`register` 取命令结果、条件控制、错误处理、把系统配置到指定状态 | [E4](04-playbooks.md) · [E5](05-variables-facts.md) · [E6](06-loops-conditions-errors.md) |
| Automate standard RHCSA tasks | 软件包与仓库、服务、防火墙、文件系统、存储设备、文件内容、归档、计划任务、安全（SELinux）、用户和组 | [E11](11-automate-rhcsa-tasks.md)（枢纽，逐项链接 RHCSA 笔记） |
| Manage content | 用模板生成定制化配置文件 | [E7](07-jinja2-templates.md) |
| Use Ansible Vault | 加密变量文件、在 playbook 中使用 | [E10](10-vault.md) |

## 3. 学习顺序与建议用时（合计约 60 h，按每周 12 h 约 5 周）

```text
第 1 周  E1 架构 → E2 inventory/配置 → E3 ad-hoc/ansible-doc          （约 10 h）
第 2 周  E4 playbook → E5 变量与 facts → E6 循环/条件/错误处理          （约 14 h）
第 3 周  E7 Jinja2 → E8 roles → E10 vault                             （约 12 h）
第 4 周  E9 collections/navigator → E12 System Roles → E11 自动化 RHCSA （约 14 h）
第 5 周  练习题全刷一遍 → 模拟考 2 次（限时 4 h）→ 查漏补缺              （约 10 h）
```

| 笔记 | 用时 | 难度 |
|---|---|---|
| [E1 Ansible 架构与安装](01-ansible-architecture.md) | 3 h | ★☆☆ |
| [E2 Inventory 与 ansible.cfg](02-inventory-and-config.md) | 4 h | ★☆☆ |
| [E3 Ad-hoc、模块与 ansible-doc](03-adhoc-modules-docs.md) | 3 h | ★☆☆ |
| [E4 Playbook 基础](04-playbooks.md) | 4 h | ★★☆ |
| [E5 变量与 facts](05-variables-facts.md) | 5 h | ★★☆ |
| [E6 循环、条件、handler 与错误处理](06-loops-conditions-errors.md) | 6 h | ★★★ |
| [E7 Jinja2 模板](07-jinja2-templates.md) | 5 h | ★★☆ |
| [E8 Roles](08-roles.md) | 5 h | ★★☆ |
| [E9 Collections 与 ansible-navigator](09-collections-navigator.md) | 5 h | ★★★ |
| [E10 Ansible Vault](10-vault.md) | 2 h | ★☆☆ |
| [E11 用 Ansible 自动化 RHCSA 任务](11-automate-rhcsa-tasks.md) | 10 h | ★★★ |
| [E12 RHEL System Roles](12-rhel-system-roles.md) | 4 h | ★★☆ |

## 4. 与 RHCSA 的依赖关系

RHCE 不是「另一门课」，而是**把 RHCSA 的每个操作换成幂等的 Ansible 任务**。如果某个 RHCSA 操作你手工都不会做，用 Ansible 也写不出来。对照关系：

| 如果你在 RHCE 卡在… | 回去复习 |
|---|---|
| SSH 免密、sudo 免密、`become` | [RHCSA-08 用户、组与 sudo](../rhcsa/08-users-groups-sudo.md) · [RHCSA-01 基础工具](../rhcsa/01-essential-tools.md) |
| 分区/LVM/文件系统模块参数看不懂 | [RHCSA-04 本地存储与 LVM](../rhcsa/04-local-storage-lvm.md) · [RHCSA-05 文件系统](../rhcsa/05-file-systems-nfs-autofs.md) |
| firewalld / SELinux 模块 | [RHCSA-09 防火墙与 SELinux](../rhcsa/09-security-firewalld-selinux.md) |
| dnf 仓库、cron、chrony、启动 target | [RHCSA-06 软件、计划任务、时间、引导](../rhcsa/06-software-scheduling-boot.md) · [RHCSA-03 运行中的系统](../rhcsa/03-operate-running-systems.md) |
| nmcli / 主机名 / 网络 | [RHCSA-07 网络配置](../rhcsa/07-networking-nmcli.md) |
| 把 shell 脚本改写成 playbook | [RHCSA-02 Shell 脚本](../rhcsa/02-shell-scripting.md) |
| 执行环境（EE）是什么 | [RHCSA-10 Podman](../rhcsa/10-containers-podman.md) · [Docker → Podman → K8s](../00-foundations/05-containers-docker-to-k8s.md) |

**建议节奏**：RHCSA 考完后 1~2 个月内考 RHCE，RHCSA 的手感还在。

## 5. 通往 CKA 的桥

- **声明式思维**：playbook 描述「期望状态」，Kubernetes 的 YAML 也是；`changed`/`ok` ≈ `kubectl apply` 的 `configured`/`unchanged`。
- **模板与打包**：[E7 Jinja2](07-jinja2-templates.md) / [E8 Roles](08-roles.md) ↔ [CKA-07 Helm 与 Kustomize](../cka/07-helm-kustomize.md)。
- **文档查法**：`ansible-doc` ↔ `kubectl explain`，见 [CKA-02 kubectl 高效操作](../cka/02-kubectl-efficiency.md)。

## 6. 离线官方文档入口

- Ansible 用户文档：[`references/rhce/ansible-docs/`](../../references/rhce/ansible-docs/)（从 [playbook_guide/index.rst](../../references/rhce/ansible-docs/playbook_guide/index.rst) 开始）
- ansible-navigator：[`references/rhce/ansible-navigator-docs/`](../../references/rhce/ansible-navigator-docs/)
- RHEL System Roles 上游 README：[`references/rhce/rhel-system-roles-upstream/`](../../references/rhce/rhel-system-roles-upstream/)
- RHEL 10 System Roles 手册（PDF，需本机运行 [`scripts/fetch-rhel-docs.sh`](../../scripts/fetch-rhel-docs.sh) 下载）
