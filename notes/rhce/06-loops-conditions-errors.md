# RHCE-06 循环、条件、handler 与错误处理

> **轨道**：[RHCE](README.md) ｜ **考纲**：EX294「Understand core components → Loops / Conditional tasks / Handling task failure」「Create plays → Use conditionals / Configure error handling」「Configure managed nodes → Convert simple shell scripts to playbooks」 ｜ **建议用时**：6 h ｜ **难度**：★★★
>
> **前置**：[RHCE-05 变量与 facts](05-variables-facts.md)
> **后续**：[RHCE-07 Jinja2 模板](07-jinja2-templates.md) · [RHCE-08 Roles](08-roles.md)
> **关联**（跨轨道）：[RHCSA-02 Shell 脚本](../rhcsa/02-shell-scripting.md)（`for`/`if`/`$?` → `loop`/`when`/`failed_when`） · [CKA-09 工作负载](../cka/09-workloads.md)（探针失败后的自愈 ≈ `rescue`）

## 1. 这个知识点在网络中的位置

这是 EX294 最容易丢分的一节：几乎每道综合题都有「对列表里的每个用户…」「只在 dev 组的主机上…」「如果磁盘不存在就输出错误信息」。
它也是把 [RHCSA-02 Shell 脚本](../rhcsa/02-shell-scripting.md) 翻译成 playbook 的核心：`for` → `loop`，`if` → `when`，`|| echo` → `block/rescue`。

## 2. 核心概念

### 循环 loop

```yaml
- name: Create several users
  ansible.builtin.user:
    name: "{{ item.name }}"
    groups: "{{ item.groups }}"
    append: true
  loop:
    - { name: alice, groups: wheel }
    - { name: bob,   groups: devops }
  loop_control:
    label: "{{ item.name }}"     # 输出时只显示用户名，不刷屏
```

| 场景 | 写法 |
|---|---|
| 简单列表 | `loop: [a, b, c]` 或 `loop: "{{ my_list }}"` |
| 字典 | `loop: "{{ my_dict \| dict2items }}"` → `item.key` / `item.value` |
| 嵌套 | `loop: "{{ list1 \| product(list2) \| list }}"` → `item.0` / `item.1` |
| 带序号 | `loop_control: { index_var: idx }` |
| 旧语法 | `with_items`、`with_dict` 仍可用，等价但不推荐 |

> 很多模块的 `name` 参数接受列表，**不用 loop** 更快：`ansible.builtin.dnf: name: [httpd, mod_ssl]`。

### 条件 when

```yaml
when: ansible_facts['distribution'] == "RedHat"
when: inventory_hostname in groups['dev']
when: "'dev' in group_names"
when: ansible_facts['memtotal_mb'] | int >= 1024
when: my_var is defined
when: result.rc != 0
when: "'vdb' in ansible_facts['devices']"
when:                          # 列表 = and
  - ansible_facts['distribution_major_version'] == "10"
  - "'webservers' in group_names"
when: a == 1 or b == 2         # or 要写在一行
```

`when` 里**直接写变量名，不加 `{{ }}`**。

### Handler 进阶

- `notify` 可以通知多个 handler；handler 可以 `listen: "restart web stack"` 订阅一个主题。
- `ansible.builtin.meta: flush_handlers` 立即执行已触发的 handler。
- `force_handlers: true`（play 级）：即使后续 task 失败也执行已通知的 handler。

### 错误处理

| 手段 | 作用 |
|---|---|
| `ignore_errors: true` | 本 task 失败也继续 |
| `failed_when: <条件>` | 自定义「什么算失败」 |
| `changed_when: <条件>` / `false` | 自定义「什么算改动」，查询类 command 必加 `false` |
| `block` / `rescue` / `always` | try / catch / finally |
| `any_errors_fatal: true` | 任何主机失败即全部停止 |
| `max_fail_percentage` | 失败比例阈值 |
| `ansible.builtin.fail` / `assert` | 主动失败 / 断言 |

```yaml
- name: Try to create LV, fall back to smaller size
  block:
    - name: Create 1500M LV
      community.general.lvol:
        vg: vg_lab
        lv: data
        size: 1500m
  rescue:
    - name: Report not enough space
      ansible.builtin.debug:
        msg: Not enough free space in VG for the requested LV
    - name: Create 800M LV instead
      community.general.lvol:
        vg: vg_lab
        lv: data
        size: 800m
  always:
    - name: Always runs
      ansible.builtin.debug:
        msg: LV task finished
```

## 3. 必会操作

### 把 shell 脚本翻译成 playbook

```bash
#!/bin/bash
# 原始脚本
for u in alice bob; do
  id "$u" &>/dev/null || useradd "$u"
done
if ! rpm -q httpd &>/dev/null; then dnf -y install httpd; fi
systemctl enable --now httpd
[ -d /srv/www ] || mkdir -p /srv/www
```

```yaml
---
- name: Translated from shell script
  hosts: webservers
  tasks:
    - name: Ensure users exist            # for + useradd → loop + user（天然幂等）
      ansible.builtin.user:
        name: "{{ item }}"
        state: present
      loop: [alice, bob]

    - name: Ensure httpd installed        # if ! rpm -q → dnf state=present
      ansible.builtin.dnf:
        name: httpd
        state: present

    - name: Enable and start httpd
      ansible.builtin.service:
        name: httpd
        state: started
        enabled: true

    - name: Ensure /srv/www exists        # [ -d ] || mkdir → file state=directory
      ansible.builtin.file:
        path: /srv/www
        state: directory
```

### 非幂等命令的正确写法

```yaml
- name: Initialize something only once
  ansible.builtin.command: /usr/local/bin/init-db.sh
  args:
    creates: /var/lib/app/.initialized    # 文件存在就跳过

- name: Query only
  ansible.builtin.command: getenforce
  register: se
  changed_when: false

- name: Fail on purpose with a message
  ansible.builtin.fail:
    msg: "Disk vdb not found on {{ inventory_hostname }}"
  when: "'vdb' not in ansible_facts['devices']"
```

## 4. 考试坑点

- **`when` 加了 `{{ }}`** 会有警告甚至逻辑错误；直接写表达式。
- **`when` 以引号字符开头**（如 `'dev' in group_names`）时整行要再包一层双引号，否则 YAML 解析失败。
- **`loop` + `register`**：结果在 `result.results` 列表里，每项有自己的 `item`、`rc`。
- **`ignore_errors` 不能挽救 unreachable**、也不能挽救语法错误。
- **`rescue` 执行后该主机状态为 `rescued`，整体不算失败**——题目「如果失败则输出 X」就用它。
- **handler 在 block 失败后不会执行**，除非 `force_handlers`。
- 题目说「如果磁盘不存在则输出信息并继续」时，**不要让 playbook 整体失败**——用 `when` + `debug`，或 `block/rescue`。

## 5. 动手练习

- [practice-set-1 · E6 节](../../labs/rhce/practice-set-1.md#e6)

## 6. 官方文档（本仓库离线版 + 考场可用的查法）

- 离线：
  - [playbook_guide/playbooks_loops.rst](../../references/rhce/ansible-docs/playbook_guide/playbooks_loops.rst)（含 `with_*` → `loop` 迁移对照表）
  - [playbook_guide/playbooks_conditionals.rst](../../references/rhce/ansible-docs/playbook_guide/playbooks_conditionals.rst)
  - [playbook_guide/playbooks_error_handling.rst](../../references/rhce/ansible-docs/playbook_guide/playbooks_error_handling.rst)
  - [playbook_guide/playbooks_blocks.rst](../../references/rhce/ansible-docs/playbook_guide/playbooks_blocks.rst)
  - [playbook_guide/playbooks_handlers.rst](../../references/rhce/ansible-docs/playbook_guide/playbooks_handlers.rst)
  - [playbook_guide/playbooks_tests.rst](../../references/rhce/ansible-docs/playbook_guide/playbooks_tests.rst)（`is defined`、`is failed`、`is version`…）
- 考场：
  - `ansible-doc -t keyword loop_control`、`ansible-doc -t keyword failed_when`、`ansible-doc -t keyword rescue`
  - `ansible-doc ansible.builtin.fail`、`ansible-doc ansible.builtin.assert`
  - `ansible-doc -t test -l` 列出可用的 test（`defined`、`match`、`search`…）

## 7. 自测清单

- [ ] 能用 `loop` 遍历列表、字典（`dict2items`）、字典列表
- [ ] 能写出「只在 dev 组且内存 ≥ 1 GB 的主机执行」的 `when`
- [ ] 会用 `block/rescue/always` 实现「失败则降级并输出信息」
- [ ] 能给 `command` 加上 `creates` / `changed_when` 使其幂等
- [ ] 能把一个 15 行左右的 shell 脚本改写成等价 playbook
- [ ] 知道 handler 何时不会执行、如何强制执行
