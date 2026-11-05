# RHCE-03 Ad-hoc 命令、模块与 ansible-doc

> **轨道**：[RHCE](README.md) ｜ **考纲**：EX294「Understand core components of Ansible → Use provided documentation to look up specific information about Ansible modules and commands」 ｜ **建议用时**：3 h ｜ **难度**：★☆☆
>
> **前置**：[RHCE-02 Inventory 与 ansible.cfg](02-inventory-and-config.md)
> **后续**：[RHCE-04 Playbook 基础](04-playbooks.md)
> **关联**（跨轨道）：[CKA-02 kubectl 高效操作](../cka/02-kubectl-efficiency.md)（`ansible-doc` ≈ `kubectl explain`；ad-hoc ≈ 命令式 kubectl） · [RHCSA-01 基础工具](../rhcsa/01-essential-tools.md)（`man` 的查法同样适用）

## 1. 这个知识点在网络中的位置

考场**不能上网**，模块参数记不住是常态——**会查文档比会背更重要**。
`ansible-doc` 是你在考场唯一的「搜索引擎」，它的 `EXAMPLES` 段几乎可以直接复制进 playbook。
Ad-hoc 命令则是验证想法、检查结果最快的方式（比如 playbook 跑完后，用一条 ad-hoc 确认用户真的建好了）。

## 2. 核心概念

### Ad-hoc 语法

```text
ansible <host-pattern> [-i inventory] -m <module> -a '<参数>' [-b] [-u user] [-v]
```

- `-m` 不写默认是 `ansible.builtin.command`。
- `-b` = become（提权），ansible.cfg 已设 `become=True` 时可省略。
- 参数格式：`key=value key2=value2`，或 JSON 字符串。

### 高频模块速查（全部是 FQCN）

| 类别 | 模块 |
|---|---|
| 连通 / 信息 | `ansible.builtin.ping`、`ansible.builtin.setup`、`ansible.builtin.debug` |
| 命令 | `ansible.builtin.command`、`ansible.builtin.shell`、`ansible.builtin.script`、`ansible.builtin.raw` |
| 软件 | `ansible.builtin.dnf`、`ansible.builtin.package`、`ansible.builtin.yum_repository`、`ansible.builtin.rpm_key` |
| 服务 | `ansible.builtin.service`、`ansible.builtin.systemd_service`（别名 `systemd`） |
| 文件 | `ansible.builtin.copy`、`ansible.builtin.file`、`ansible.builtin.template`、`ansible.builtin.lineinfile`、`ansible.builtin.blockinfile`、`ansible.builtin.replace`、`ansible.builtin.fetch`、`ansible.builtin.stat`、`ansible.builtin.get_url`、`ansible.builtin.unarchive` |
| 用户 | `ansible.builtin.user`、`ansible.builtin.group`、`ansible.posix.authorized_key` |
| 计划任务 | `ansible.builtin.cron`、`ansible.posix.at` |
| 安全 | `ansible.posix.firewalld`、`ansible.posix.selinux`、`ansible.posix.seboolean`、`community.general.sefcontext`、`community.general.seport` |
| 存储 | `community.general.parted`、`community.general.lvg`、`community.general.lvol`、`community.general.filesystem`、`ansible.posix.mount` |
| 其他 | `ansible.builtin.reboot`、`ansible.builtin.hostname`、`ansible.posix.sysctl`、`community.general.archive` |

> `ansible.posix` 和 `community.general` 不在 ansible-core 里，需要单独安装 collection（见 [E9](09-collections-navigator.md)）。考场通常会提供，但要先 `ansible-galaxy collection list` 确认。

### command vs shell vs raw

| 模块 | 走 shell 吗 | 支持管道/重定向/变量 | 用途 |
|---|---|---|---|
| `command` | 否 | 否 | 默认，最安全 |
| `shell` | 是（`/bin/sh`） | 是 | 需要 `|`、`>`、`&&` 时 |
| `raw` | 直接 SSH 执行 | 是 | 受管节点没 Python 时引导安装 |

三者都**不幂等**，需要配合 `creates:`/`removes:` 或 `changed_when:`（见 [E6](06-loops-conditions-errors.md)）。

## 3. 必会操作

```bash
# ---------- ansible-doc：考场救命 ----------
ansible-doc -l                          # 列出所有模块（很长，配合 grep）
ansible-doc -l | grep -i firewall       # 按关键字找模块
ansible-doc -l ansible.posix            # 只列出某个 collection 的模块
ansible-doc ansible.posix.firewalld     # 完整文档：参数、默认值、EXAMPLES、RETURN
ansible-doc -s ansible.builtin.user     # 精简 snippet，直接是 task 模板
ansible-doc -t keyword become           # 查 playbook 关键字（become、loop、when、notify…）
ansible-doc -t keyword -l               # 列出所有关键字
ansible-doc -t lookup -l                # 列出 lookup 插件（file、env、password…）
ansible-doc -t filter -l                # 列出 filter 插件（较新的 ansible-core 支持）
ansible-doc -t become sudo              # 提权插件参数
# 在 less 里：输入 /EXAMPLES 回车 直接跳到示例

# ---------- ad-hoc 常用 ----------
ansible all -m ansible.builtin.ping
ansible all -m ansible.builtin.command -a 'uptime'
ansible all -m ansible.builtin.shell -a 'df -h | grep /data'
ansible dev -m ansible.builtin.dnf -a 'name=httpd state=present'
ansible dev -m ansible.builtin.service -a 'name=httpd state=started enabled=true'
ansible all -m ansible.builtin.copy -a 'content="hello\n" dest=/etc/motd'
ansible all -m ansible.builtin.user -a 'name=bob state=present'
ansible all -m ansible.builtin.setup -a 'filter=ansible_default_ipv4'
ansible all -m ansible.builtin.setup -a 'gather_subset=hardware'

# 验证类（playbook 跑完后自查）
ansible all -a 'id bob'
ansible all -a 'systemctl is-enabled httpd'
ansible all -a 'firewall-cmd --list-all'
ansible all -a 'cat /etc/fstab'
```

### 从 ad-hoc 到 playbook 的一一对应

```bash
ansible dev -m ansible.builtin.dnf -a 'name=httpd state=latest'
```

等价于：

```yaml
- name: Install httpd
  hosts: dev
  tasks:
    - name: Ensure httpd is latest
      ansible.builtin.dnf:
        name: httpd
        state: latest
```

## 4. 考试坑点

- **记关键字而不是记参数**：只要记得「SELinux 文件上下文的模块叫 sefcontext」，参数让 `ansible-doc` 告诉你。
- **ansible-doc 查不到 `ansible.posix.*`**：说明 collection 没装或 `collections_path` 没配对 → 回到 [E9](09-collections-navigator.md)。
- **`-a` 里的引号**：外层单引号、内层双引号，避免本地 shell 把 `$`、`*` 展开。
- **ad-hoc 只用于验证，不是交付物**：题目要求「写一个 playbook 叫 /home/student/ansible/users.yml」，判分会检查文件存在并能运行。
- `ansible-doc` 输出里 `= ` 开头的参数是**必填**，`- ` 开头是可选。

## 5. 动手练习

- [practice-set-1 · E3 节](../../labs/rhce/practice-set-1.md#e3)
- 训练法：随便选 10 个模块名，限时 30 秒内用 `ansible-doc -s` 写出 task 骨架。

## 6. 官方文档（本仓库离线版 + 考场可用的查法）

- 离线：
  - [command_guide/intro_adhoc.rst](../../references/rhce/ansible-docs/command_guide/intro_adhoc.rst)
  - [command_guide/cheatsheet.rst](../../references/rhce/ansible-docs/command_guide/cheatsheet.rst)
  - [module_plugin_guide/modules_intro.rst](../../references/rhce/ansible-docs/module_plugin_guide/modules_intro.rst)
  - [module_plugin_guide/modules_support.rst](../../references/rhce/ansible-docs/module_plugin_guide/modules_support.rst)
  - [reference_appendices/common_return_values.rst](../../references/rhce/ansible-docs/reference_appendices/common_return_values.rst)
- 考场：
  - `ansible-doc -l | grep <关键字>` → `ansible-doc -s <模块>` → `ansible-doc <模块>` 里 `/EXAMPLES`
  - `ansible-navigator doc ansible.posix.firewalld -m stdout`（navigator 版，见 [E9](09-collections-navigator.md)）
  - 模块源码也是文档：`/usr/share/ansible/collections/ansible_collections/<ns>/<coll>/plugins/modules/*.py` 开头的 `DOCUMENTATION`/`EXAMPLES` 字符串

## 7. 自测清单

- [ ] 不看笔记，能用 `ansible-doc` 在 1 分钟内找到「设置 SELinux 端口标签」的模块和示例
- [ ] 能说出 `command`、`shell`、`raw` 的区别
- [ ] 会用 `ansible-doc -t keyword` 查 `ignore_errors`、`notify` 等关键字
- [ ] 能把任意一条 ad-hoc 命令改写成 playbook task
- [ ] 会用 `setup` 的 `filter` 参数快速查某个 fact
