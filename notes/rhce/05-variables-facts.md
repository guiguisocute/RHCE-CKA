# RHCE-05 变量与 facts

> **轨道**：[RHCE](README.md) ｜ **考纲**：EX294「Understand core components → Variables / Facts」「Create plays → Use variables to retrieve the results of running a command」 ｜ **建议用时**：5 h ｜ **难度**：★★☆
>
> **前置**：[RHCE-04 Playbook 基础](04-playbooks.md)
> **后续**：[RHCE-06 循环、条件、handler 与错误处理](06-loops-conditions-errors.md)
> **关联**（跨轨道）：[CKA-07 Helm 与 Kustomize](../cka/07-helm-kustomize.md)（`values.yaml` 的覆盖顺序和 Ansible 变量优先级思路一样） · [RHCSA-04 本地存储与 LVM](../rhcsa/04-local-storage-lvm.md)（`ansible_devices` / `ansible_lvm` facts 对应 `lsblk` / `vgs`）

## 1. 这个知识点在网络中的位置

变量让同一个 playbook 能用在不同主机上；facts 让 playbook 能「看到」受管节点当前的状态（IP、内存、磁盘、发行版）。
考试里常见题型：「根据主机的内存/磁盘/所在组生成不同内容」「把命令输出保存下来再判断」——都靠这一节。

## 2. 核心概念

### 变量来源（常用的，从低到高）

| 优先级 | 来源 | 典型用途 |
|---|---|---|
| 低 | role `defaults/main.yml` | role 的可覆盖默认值 |
| ↓ | inventory 中的组变量 / `group_vars/all` | 全局默认 |
| ↓ | `group_vars/<组>` | 组级配置 |
| ↓ | `host_vars/<主机>` | 主机级配置 |
| ↓ | facts（`ansible_facts`） | 自动收集 |
| ↓ | play `vars:` / `vars_files:` | playbook 内定义 |
| ↓ | role `vars/main.yml` | role 内部常量 |
| ↓ | `set_fact` / `register` | 运行时产生 |
| 高 | `-e` / `--extra-vars` | 命令行，**永远最高** |

完整的 22 级列表见离线文档 [playbooks_variables.rst](../../references/rhce/ansible-docs/playbook_guide/playbooks_variables.rst) 的 *Variable precedence* 小节，记住上表即可。

### Facts

```jinja
{# 两种写法等价，推荐第一种 #}
{{ ansible_facts['hostname'] }}           {# ansible_facts 字典 #}
{{ ansible_hostname }}                    {# 注入的顶层变量（受 inject_facts_as_vars 控制） #}
```

| 常用 fact | 含义 |
|---|---|
| `ansible_facts['hostname']` / `['fqdn']` | 主机名 |
| `ansible_facts['default_ipv4']['address']` | 默认网卡 IPv4 |
| `ansible_facts['distribution']` / `['distribution_major_version']` | `RedHat` / `10` |
| `ansible_facts['memtotal_mb']` | 内存 MB |
| `ansible_facts['devices']['vdb']['size']` | 磁盘大小（字符串，如 `"10.00 GB"`） |
| `ansible_facts['lvm']['vgs']` | 卷组信息（需要 lvm2） |
| `ansible_facts['mounts']` | 挂载列表 |
| `ansible_facts['bios_version']` | BIOS 版本 |

### 魔法变量（不是 facts，Ansible 自带）

| 变量 | 含义 |
|---|---|
| `inventory_hostname` | inventory 里写的名字 |
| `groups['webservers']` | 某组的主机列表 |
| `group_names` | 当前主机所属的组列表 |
| `hostvars['node1']['ansible_facts']['default_ipv4']['address']` | **读别的主机的变量/facts**（那台主机必须已收集 facts） |
| `play_hosts` / `ansible_play_hosts` | 当前 play 的主机 |

### register：取命令结果

```yaml
- name: Check whether httpd is installed
  ansible.builtin.command: rpm -q httpd
  register: rpm_result
  changed_when: false        # 查询类命令不应该报 changed
  failed_when: false         # 没装时 rc=1，不当作失败

- name: Show result
  ansible.builtin.debug:
    msg: "rc={{ rpm_result.rc }}, stdout={{ rpm_result.stdout }}"
```

register 结果常用字段：`rc`、`stdout`、`stdout_lines`、`stderr`、`changed`、`failed`；用在 `loop` 上时是 `results` 列表。

## 3. 必会操作

```yaml
---
- name: Variables demo
  hosts: all
  vars:
    web_pkg: httpd
  vars_files:
    - vars/users.yml            # 外部变量文件
  tasks:
    - name: Print some facts
      ansible.builtin.debug:
        msg: >-
          {{ inventory_hostname }} runs {{ ansible_facts['distribution'] }}
          {{ ansible_facts['distribution_version'] }} with
          {{ ansible_facts['memtotal_mb'] }} MB RAM

    - name: Compute a fact at runtime
      ansible.builtin.set_fact:
        is_big: "{{ ansible_facts['memtotal_mb'] | int > 2048 }}"

    - name: Print a variable of another host
      ansible.builtin.debug:
        var: hostvars['node1.example.com']['ansible_facts']['default_ipv4']['address']
```

```bash
# 查 facts 的方法
ansible node1 -m ansible.builtin.setup -a 'filter=ansible_devices'
ansible node1 -m ansible.builtin.setup | grep -i mem
ansible-inventory --host node1.example.com      # 看 inventory 层的变量合并结果
```

### 自定义 facts（local facts）

```ini
# 受管节点上的 /etc/ansible/facts.d/custom.fact（INI 或 JSON）
[app]
env=prod
```

在 playbook 中读取：`{{ ansible_facts['ansible_local']['custom']['app']['env'] }}`。

## 4. 考试坑点

- **facts 未收集**：`gather_facts: false` 时访问 `ansible_facts[...]` 会报 undefined。读其他主机的 `hostvars[...]['ansible_facts']` 时，那台主机**也必须在本次运行中收集过 facts**——常用做法是先写一个 `hosts: all` 的 play 收集 facts。
- **`ansible_devices.vdb` 不存在**：判断前先 `when: "'vdb' in ansible_facts['devices']"`。
- **变量名不能含 `-`**，也别用 Python 保留字（`class`、`register` 等）。
- **数字比较要 `| int`**：facts 里有些值是字符串。
- **点号访问 vs 方括号**：`a.b` 和 `a['b']` 等价，但键名有 `-` 或与方法同名（如 `items`、`keys`）时必须用方括号。
- **`-e` 优先级最高**，调试时用它覆盖变量；但别在交付的 playbook 里依赖它。

## 5. 动手练习

- [practice-set-1 · E5 节](../../labs/rhce/practice-set-1.md#e5)

## 6. 官方文档（本仓库离线版 + 考场可用的查法）

- 离线：
  - [playbook_guide/playbooks_variables.rst](../../references/rhce/ansible-docs/playbook_guide/playbooks_variables.rst)（含 *Variable precedence*）
  - [playbook_guide/playbooks_vars_facts.rst](../../references/rhce/ansible-docs/playbook_guide/playbooks_vars_facts.rst)（facts、local facts、`hostvars`）
  - [reference_appendices/special_variables.rst](../../references/rhce/ansible-docs/reference_appendices/special_variables.rst)（魔法变量完整列表）
  - [reference_appendices/general_precedence.rst](../../references/rhce/ansible-docs/reference_appendices/general_precedence.rst)
  - [reference_appendices/common_return_values.rst](../../references/rhce/ansible-docs/reference_appendices/common_return_values.rst)（register 结果字段）
- 考场：
  - `ansible all -m ansible.builtin.setup -a 'filter=*mem*'` 直接搜 facts 名
  - `ansible-doc ansible.builtin.setup`、`ansible-doc ansible.builtin.set_fact`
  - `ansible-doc -t keyword vars_files`、`ansible-doc -t keyword register`

## 7. 自测清单

- [ ] 能说出 `-e`、`host_vars`、`group_vars`、role defaults 的优先级高低
- [ ] 能写出「读取另一台主机 IP」的表达式，并知道前提条件
- [ ] 会用 `register` + `changed_when: false` 写查询类 task
- [ ] 能从 `setup` 输出里快速找到磁盘、内存、发行版相关的 fact
- [ ] 会创建并读取一个 local fact
