# RHCE-01 Ansible 架构与安装

> **轨道**：[RHCE](README.md) ｜ **考纲**：EX294「Understand core components of Ansible」「Install and configure an Ansible control node」 ｜ **建议用时**：3 h ｜ **难度**：★☆☆
>
> **前置**：[YAML 语法](../00-foundations/04-yaml.md) · [Ubuntu → RHEL 对照](../00-foundations/01-ubuntu-to-rhel.md) · [RHCSA-01 基础工具](../rhcsa/01-essential-tools.md) · [RHCSA-08 用户、组与 sudo](../rhcsa/08-users-groups-sudo.md)
> **后续**：[RHCE-02 Inventory 与 ansible.cfg](02-inventory-and-config.md)
> **关联**（跨轨道）：[Docker → Podman → K8s](../00-foundations/05-containers-docker-to-k8s.md)（执行环境 EE 就是容器镜像） · [CKA-01 集群架构](../cka/01-architecture.md)（同样是「控制端 + 被管理节点」）

## 1. 这个知识点在网络中的位置

Ansible 是 RHCE 的全部内容。先搞清楚「谁在哪台机器上执行什么」，后面所有 playbook 排错都会轻松很多。
你在 Ubuntu 上可能用 SSH 手动一台台配置过实验室机器——Ansible 做的就是把这件事写成**可重复执行的声明式配置**，通过 SSH 批量推下去。

## 2. 核心概念

| 概念 | 说明 |
|---|---|
| **控制节点 (control node)** | 安装 Ansible、写 playbook、执行命令的机器。只要有 Python 和 SSH 客户端，Linux 即可 |
| **受管节点 (managed node)** | 被配置的机器。**不需要装 Ansible agent**，只需要 `sshd` + Python（模块会被临时传过去执行） |
| **Inventory** | 受管节点清单，可分组，见 [E2](02-inventory-and-config.md) |
| **Module** | 一个具体的「动作单元」，如 `ansible.builtin.dnf`、`ansible.posix.firewalld` |
| **Task** | 调用一次模块 + 参数 |
| **Play** | 把一组 task 应用到一组主机（`hosts:`） |
| **Playbook** | 一个 YAML 文件，包含一个或多个 play |
| **Role** | 可复用的 task/handler/template/变量打包结构，见 [E8](08-roles.md) |
| **Collection** | 分发单位：打包了 modules、roles、plugins，名字形如 `namespace.collection`，见 [E9](09-collections-navigator.md) |
| **FQCN** | Fully Qualified Collection Name，例如 `ansible.builtin.copy`。考试和工作中都推荐写全名 |
| **幂等 (idempotent)** | 同一个 playbook 执行第二次应该全部是 `ok`、没有 `changed`——这是判断 playbook 写得好不好的第一标准 |
| **ansible-core** | 引擎 + `ansible.builtin` 模块。RHEL AppStream 自带 |
| **Ansible Automation Platform (AAP)** | 红帽商业产品，包含 ansible-navigator、执行环境、自动化控制器等 |
| **执行环境 (Execution Environment, EE)** | 一个装好了 ansible-core + collections + Python 依赖的**容器镜像**，`ansible-navigator` 默认用 podman 在其中运行 playbook |

### 执行流程（一个 task 发生了什么）

```text
控制节点                                   受管节点
ansible-playbook site.yml
  ├─ 读 ansible.cfg、inventory、变量
  ├─ 渲染 task 参数（Jinja2）
  ├─ 通过 SSH 把模块代码(Python)拷贝到 ~/.ansible/tmp/ ──→ python3 执行模块
  │                                                      └─ 返回 JSON：changed / failed / 输出
  └─ 汇总结果：ok / changed / failed / skipped / unreachable
```

- 默认 `forks = 5`：同时并发 5 台主机。
- 默认 `strategy = linear`：所有主机执行完 task 1，再一起执行 task 2。
- 默认第一个 task 前会执行 **Gathering Facts**（`setup` 模块），见 [E5](05-variables-facts.md)。

### 两种运行方式（考试都会涉及）

| 方式 | 命令 | Ansible 在哪运行 |
|---|---|---|
| 传统 | `ansible-playbook site.yml` | 控制节点本机的 ansible-core |
| Automation content navigator | `ansible-navigator run site.yml -m stdout` | 默认在 EE 容器里（podman），也可 `--ee false` 用本机 ansible-core |

## 3. 必会操作

```bash
# 控制节点：安装 ansible-core（RHEL 9/10 的 AppStream 仓库里就有）
sudo dnf install -y ansible-core

# ansible-navigator 属于 AAP 仓库（需要订阅）；实验环境可用 pip 安装（见 labs/rhce/00-lab-setup.md）
python3 -m pip install --user ansible-navigator

# 查看版本、配置文件位置、Python 解释器、collection 搜索路径
ansible --version

# 测试连通性：ping 模块（不是 ICMP ping，而是 SSH 登录 + 执行 Python）
ansible all -i inventory -m ansible.builtin.ping

# 查看某台主机收集到的 facts
ansible node1 -m ansible.builtin.setup | less

# 执行 playbook 的常用选项
ansible-playbook site.yml --syntax-check   # 只检查语法
ansible-playbook site.yml -C               # check 模式（dry-run，不改动）
ansible-playbook site.yml -C -D            # dry-run 并显示文件 diff
ansible-playbook site.yml -v / -vvv        # 输出更详细，排错用
ansible-playbook site.yml --list-tasks --list-hosts
```

`ansible --version` 的输出要会读：

```text
ansible [core 2.16.x]
  config file = /home/student/ansible/ansible.cfg     ← 当前生效的配置文件，考试第一件事就是确认它
  configured module search path = [...]
  ansible python module location = ...
  ansible collection location = /home/student/.ansible/collections:/usr/share/ansible/collections
  executable location = /usr/bin/ansible
  python version = 3.12.x
```

## 4. 考试坑点

- **受管节点要有 Python 3**；RHEL 默认已装。报错 `/usr/bin/python: not found` 时检查 `interpreter_python`。
- **确认生效的 ansible.cfg**：在错误目录执行命令会读到 `/etc/ansible/ansible.cfg`，inventory、remote_user 全错。养成 `cd` 到项目目录再执行的习惯。
- **不要用 `command`/`shell` 偷懒**：判分看最终状态，但非幂等的 `shell` 很容易二次执行时报错（例如重复 `useradd`）。有专门模块就用模块。
- **FQCN**：`ansible.builtin.copy` 和 `copy` 在 ansible-core 里等价，但用 FQCN 能避免和 collection 里同名模块冲突，也方便 `ansible-doc` 查询。
- **ping 失败三板斧**：`ssh user@node` 能否免密 → `sudo -l` 是否免密 → inventory 主机名能否解析。

## 5. 动手练习

- 搭环境：[labs/rhce/00-lab-setup.md](../../labs/rhce/00-lab-setup.md)
- 练习：[practice-set-1 · E1 节](../../labs/rhce/practice-set-1.md#e1)

## 6. 官方文档（本仓库离线版 + 考场可用的查法）

- 离线：
  - [getting_started/introduction.rst](../../references/rhce/ansible-docs/getting_started/introduction.rst)、[basic_concepts.rst](../../references/rhce/ansible-docs/getting_started/basic_concepts.rst)
  - [installation_guide/intro_installation.rst](../../references/rhce/ansible-docs/installation_guide/intro_installation.rst)
  - [command_guide/command_line_tools.rst](../../references/rhce/ansible-docs/command_guide/command_line_tools.rst)
  - [reference_appendices/glossary.rst](../../references/rhce/ansible-docs/reference_appendices/glossary.rst)
  - [ansible-navigator 文档首页](../../references/rhce/ansible-navigator-docs/index.md)
- 考场：
  - `ansible --version`：确认配置文件、collection 路径
  - `ansible-doc -l | wc -l`：确认能查到哪些模块
  - `man ansible`、`man ansible-playbook`（如已安装）、`ansible-playbook --help | less`

## 7. 自测清单

- [ ] 能画出「控制节点 → SSH → 受管节点执行 Python 模块 → 返回 JSON」的流程
- [ ] 能说清 module / task / play / playbook / role / collection 的包含关系
- [ ] 能解释什么是幂等，以及为什么 `shell: useradd bob` 不幂等
- [ ] 能读懂 `ansible --version` 的每一行
- [ ] 知道 `ansible-playbook` 与 `ansible-navigator run` 的区别（本机 vs EE 容器）
- [ ] 会用 `--syntax-check`、`-C`、`-D`、`-v` 四个排错选项
