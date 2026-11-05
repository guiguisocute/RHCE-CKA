# RHCE-09 Collections 与 ansible-navigator

> **轨道**：[RHCE](README.md) ｜ **考纲**：EX294「Use roles and Ansible Content Collections → Install Content Collections and use them」「Run playbooks with Automation content navigator」 ｜ **建议用时**：5 h ｜ **难度**：★★★
>
> **前置**：[RHCE-08 Roles](08-roles.md)
> **后续**：[RHCE-12 RHEL System Roles](12-rhel-system-roles.md)
> **关联**（跨轨道）：[RHCSA-10 Podman 容器](../rhcsa/10-containers-podman.md)（navigator 默认用 podman 跑执行环境） · [Docker → Podman → K8s](../00-foundations/05-containers-docker-to-k8s.md) · [CKA-07 Helm 与 Kustomize](../cka/07-helm-kustomize.md)（collection 仓库 ≈ Helm repo）

## 1. 这个知识点在网络中的位置

ansible-core 只自带 `ansible.builtin`。防火墙、SELinux、LVM 等模块都在 **collection** 里（`ansible.posix`、`community.general`、`redhat.rhel_system_roles`）。
**ansible-navigator** 是红帽 AAP 的新一代命令行：把 ansible-core + collections + Python 依赖装进一个**容器镜像（执行环境 EE）**里运行，解决「我这能跑你那不能跑」的问题——和你用 Docker 打包应用的思路一样。

## 2. 核心概念

### Collection

| 概念 | 说明 |
|---|---|
| 命名 | `namespace.collection`，模块 FQCN = `namespace.collection.module` |
| 来源 | Ansible Galaxy（社区）、Automation Hub（红帽认证）、私有 Galaxy、tar 包、git |
| 安装位置 | `collections_path`（默认 `~/.ansible/collections:/usr/share/ansible/collections`），实际目录是 `<path>/ansible_collections/<ns>/<coll>/` |
| 内容 | `plugins/modules/`、`roles/`、`playbooks/`、`docs/` |

### 执行环境 (EE)

```text
ansible-navigator run site.yml
  └─ podman run <EE 镜像>                    ← 镜像里有 ansible-core + collections + Python 库
       └─ 挂载当前项目目录 → 在容器内执行 ansible-playbook
            └─ SSH → 受管节点（受管节点不需要容器）
```

- 红帽 EE 镜像示例：`registry.redhat.io/ansible-automation-platform-2x/ee-supported-rhel9`（具体名称和 tag 以考场/订阅为准，需要 `podman login registry.redhat.io`）。
- **项目目录**里的 `collections/`、`roles/`、`ansible.cfg`、inventory 会被挂进容器；放在项目外的文件容器里看不到。
- `--ee false`（`--execution-environment false`）：不用容器，直接用本机 ansible-core。

### ansible-navigator 设置文件

查找顺序：环境变量 `ANSIBLE_NAVIGATOR_CONFIG` → 项目目录 `./ansible-navigator.yml`（**无点**） → `~/.ansible-navigator.yml`（**有点**）。

```yaml
---
ansible-navigator:
  execution-environment:
    image: registry.redhat.io/ansible-automation-platform-2x/ee-supported-rhel9:latest   # 以考场提供为准
    pull:
      policy: missing          # 本地有就不拉
  mode: stdout                 # 默认 interactive（TUI）；考试里 stdout 更直观
  playbook-artifact:
    enable: false              # 不生成 artifact json；需要交互输入密码时必须关闭
```

## 3. 必会操作

### 安装 collection

```yaml
# collections/requirements.yml
---
collections:
  - name: ansible.posix
  - name: community.general
    version: ">=8.0.0"
  - name: http://materials.example.com/collections/redhat-rhel_system_roles-1.0.0.tar.gz
    type: url
  - name: /home/student/downloads/community-general-9.0.0.tar.gz
    type: file
```

```bash
ansible-galaxy collection install -r collections/requirements.yml -p collections/
ansible-galaxy collection install ansible.posix -p collections/
ansible-galaxy collection list                 # 列出所有路径下已安装的 collection
ansible-doc -l ansible.posix                   # 确认模块可被找到
```

> `-p collections/` 会装到 `collections/ansible_collections/...`。确保 `ansible.cfg` 的 `collections_path` 包含 `./collections`（或绝对路径）。

### ansible-navigator 常用命令

```bash
ansible-navigator --version
ansible-navigator images                                  # 列出可用 EE 镜像（TUI）
ansible-navigator run site.yml -m stdout                  # ★ 运行 playbook，输出同 ansible-playbook
ansible-navigator run site.yml -m stdout -i inventory --pp missing
ansible-navigator run site.yml -m stdout --ee false       # 不使用容器
ansible-navigator run site.yml -m stdout --pae false --ask-vault-pass   # 交互输入 vault 密码
ansible-navigator collections                             # ★ 浏览 EE 里有哪些 collection（TUI，输入编号进入）
ansible-navigator collections -m stdout                   # 非交互输出（较新版本支持）
ansible-navigator doc ansible.posix.firewalld -m stdout   # ★ 查模块文档 = ansible-doc
ansible-navigator doc -l -m stdout                        # 列出 EE 内全部模块
ansible-navigator inventory -i inventory --list -m stdout # = ansible-inventory --list
ansible-navigator inventory -i inventory                  # TUI 浏览主机和组
ansible-navigator config                                  # = ansible-config，查看生效配置
ansible-navigator exec -- ansible-galaxy collection list  # 在 EE 里执行任意命令
```

TUI 操作：数字键选择条目、`Esc` 返回、`:q` 退出、`:help` 帮助、`:doc <模块>` 查文档、`:run <playbook>` 运行。

## 4. 考试坑点

- **装完 collection 用 `ansible-doc -l <ns>` 验证**，`ansible-galaxy collection list` 里出现了但 `ansible-doc` 查不到，就是 `collections_path` 没配对。
- **navigator 里能跑，ansible-playbook 不能跑（或反之）**：两者用的是不同的 collection 集合（EE 镜像里 vs 本机路径）。题目指定用哪个就用哪个。
- **TUI 卡住看不懂**：加 `-m stdout`。
- **需要输入密码（`--ask-vault-pass`、`-K`）时**：必须 `-m stdout` 且 `--pae false`，否则报错或无法交互。
- **EE 拉镜像失败**：考场一般预置了镜像，设置 `--pp never`/`missing` 避免联网拉取；`podman images` 确认镜像名。
- **requirements.yml 顶层结构**：collection 的要放在 `collections:` 键下；role 的 requirements 可以是纯列表（或 `roles:` 键）。两者别混。
- tar 包 URL 安装要写 `type: url`；本地文件写 `type: file`（或直接 `ansible-galaxy collection install ./xxx.tar.gz`）。

## 5. 动手练习

- [practice-set-1 · E9 节](../../labs/rhce/practice-set-1.md#e9)
- 环境：[labs/rhce/00-lab-setup.md](../../labs/rhce/00-lab-setup.md) 的「执行环境」一节

## 6. 官方文档（本仓库离线版 + 考场可用的查法）

- 离线：
  - [collections_guide/collections_installing.rst](../../references/rhce/ansible-docs/collections_guide/collections_installing.rst)（requirements.yml 的 `type: url/file/git`）
  - [collections_guide/collections_using_playbooks.rst](../../references/rhce/ansible-docs/collections_guide/collections_using_playbooks.rst)
  - [collections_guide/collections_listing.rst](../../references/rhce/ansible-docs/collections_guide/collections_listing.rst)
  - [collections_guide/collections_downloading.rst](../../references/rhce/ansible-docs/collections_guide/collections_downloading.rst)（离线下载 tar 包）
  - [getting_started_ee/introduction.rst](../../references/rhce/ansible-docs/getting_started_ee/introduction.rst)、[run_execution_environment.rst](../../references/rhce/ansible-docs/getting_started_ee/run_execution_environment.rst)
  - [ansible-navigator：subcommands.md](../../references/rhce/ansible-navigator-docs/subcommands.md)（与 ansible-* 命令对照）、[settings.md](../../references/rhce/ansible-navigator-docs/settings.md)（设置文件查找顺序）、[installation.md](../../references/rhce/ansible-navigator-docs/installation.md)、[faq.md](../../references/rhce/ansible-navigator-docs/faq.md)
- 考场：
  - `ansible-navigator --help`、`ansible-navigator run --help | less`（查 `--pp`、`--pae`、`--eei`）
  - `ansible-navigator settings --sample`（较新版本可输出示例设置文件，以 `--help` 为准）
  - `ansible-galaxy collection install --help`
  - `ls /usr/share/ansible/collections/ansible_collections/`：看系统预装了哪些 collection

## 7. 自测清单

- [ ] 能写出包含 Galaxy、URL tar 包、本地文件三种来源的 collections/requirements.yml
- [ ] 能把 collection 装进项目目录并让 `ansible-doc` 找到
- [ ] 会用 `ansible-navigator run -m stdout` 运行 playbook
- [ ] 会用 `ansible-navigator doc` / `collections` 找一个陌生模块并写出 task
- [ ] 能解释 EE 是什么、为什么受管节点不需要容器
- [ ] 知道交互输入密码时 navigator 需要哪两个选项
