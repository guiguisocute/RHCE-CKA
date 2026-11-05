# RHCE-04 Playbook 基础

> **轨道**：[RHCE](README.md) ｜ **考纲**：EX294「Create Ansible plays and playbooks」「Understand core components → Plays / Playbooks」 ｜ **建议用时**：4 h ｜ **难度**：★★☆
>
> **前置**：[RHCE-03 Ad-hoc、模块与 ansible-doc](03-adhoc-modules-docs.md) · [YAML 语法](../00-foundations/04-yaml.md)
> **后续**：[RHCE-05 变量与 facts](05-variables-facts.md) · [RHCE-10 Ansible Vault](10-vault.md)
> **关联**（跨轨道）：[CKA-09 工作负载](../cka/09-workloads.md)（Deployment YAML 同样是「期望状态」） · [YAML 语法](../00-foundations/04-yaml.md)

## 1. 这个知识点在网络中的位置

Playbook 是 EX294 的**交付物**：几乎每道题都是「写一个 playbook 放在指定路径，并运行它」。
如果你写过 docker-compose.yml，会觉得很熟悉：都是 YAML 描述期望状态；不同的是 playbook 的 task 是**按顺序执行**的。

## 2. 核心概念

### 结构

```yaml
---                                   # 文档开始（可选）
- name: Configure web servers         # Play 1
  hosts: webservers                   # 目标主机/组/pattern
  become: true                        # 本 play 提权（覆盖 ansible.cfg）
  gather_facts: true                  # 默认 true
  vars:
    pkg: httpd
  tasks:
    - name: Install {{ pkg }}         # Task：name + 一个模块
      ansible.builtin.dnf:
        name: "{{ pkg }}"             # 值以 {{ 开头必须加引号
        state: present

    - name: Start and enable service
      ansible.builtin.service:
        name: "{{ pkg }}"
        state: started
        enabled: true
      notify: Restart httpd           # 触发 handler（仅在 changed 时）

  handlers:
    - name: Restart httpd
      ansible.builtin.service:
        name: httpd
        state: restarted

- name: Configure database servers    # Play 2
  hosts: dbservers
  tasks:
    - name: Install mariadb
      ansible.builtin.dnf:
        name: mariadb-server
        state: present
```

### 常用 play 关键字

| 关键字 | 作用 |
|---|---|
| `hosts` | 目标，支持 pattern（`'webservers:&prod'`） |
| `become` / `become_user` | 提权 / 切换到某用户 |
| `remote_user` | 登录用户 |
| `gather_facts` | 是否收集 facts |
| `vars` / `vars_files` | 变量 / 变量文件 |
| `pre_tasks` / `roles` / `tasks` / `post_tasks` / `handlers` | 执行顺序就是这个顺序 |
| `serial` | 滚动执行，一次处理 N 台 |
| `ignore_errors` / `any_errors_fatal` | 错误处理，见 [E6](06-loops-conditions-errors.md) |

### 结果状态

| 状态 | 含义 |
|---|---|
| `ok` | 已是期望状态，没改动 |
| `changed` | 做了改动 |
| `failed` | 失败（默认该主机后续 task 停止） |
| `skipped` | `when` 不满足 |
| `unreachable` | SSH 连不上 |
| `rescued` / `ignored` | 被 `rescue` 接住 / 被 `ignore_errors` 忽略 |

## 3. 必会操作

```bash
ansible-playbook site.yml --syntax-check     # 1. 语法
ansible-playbook site.yml -C -D              # 2. dry-run + diff（有些模块不支持 check 模式）
ansible-playbook site.yml                    # 3. 正式执行
ansible-playbook site.yml                    # 4. 再执行一次：应该 changed=0（幂等）

ansible-playbook site.yml -l node1           # 只对 node1（limit）
ansible-playbook site.yml --start-at-task 'Start and enable service'
ansible-playbook site.yml --step             # 每个 task 前询问
ansible-playbook site.yml -t config          # 只执行打了 tags: config 的 task
ansible-playbook site.yml -e 'pkg=nginx'     # 额外变量（优先级最高）

# navigator 版本（考纲要求会用）
ansible-navigator run site.yml -m stdout
```

### 一个「部署文件到受管节点」的完整示例

```yaml
---
- name: Deploy message of the day
  hosts: all
  tasks:
    - name: Create /etc/motd with host-specific content
      ansible.builtin.copy:
        content: "Welcome to {{ inventory_hostname }}\n"
        dest: /etc/motd
        owner: root
        group: root
        mode: "0644"

    - name: Ensure /opt/app exists
      ansible.builtin.file:
        path: /opt/app
        state: directory
        mode: "0755"

    - name: Ensure a line exists in sshd_config
      ansible.builtin.lineinfile:
        path: /etc/ssh/sshd_config
        regexp: '^#?PermitRootLogin'
        line: PermitRootLogin no
        validate: /usr/sbin/sshd -t -f %s
      notify: Reload sshd

  handlers:
    - name: Reload sshd
      ansible.builtin.service:
        name: sshd
        state: reloaded
```

## 4. 考试坑点

- **缩进用空格，2 个一级**。在 vim 里先配好（见 [vim/tmux 考场效率](../00-foundations/07-vim-tmux-exam-efficiency.md)）：`autocmd FileType yaml setlocal ts=2 sw=2 et ai`。
- **`{{ var }}` 开头必须加引号**：`name: {{ pkg }}` 会被 YAML 当成字典导致语法错误。
- **`mode` 写成字符串 `"0644"`**：写 `644` 会被当成十进制数 → 权限错乱。
- **handler 只在 changed 时触发，并且在 play 末尾统一执行**。前面 task 失败了 handler 就不跑（可用 `--force-handlers` 或 `force_handlers: true`）。
- **handler 名字要和 notify 完全一致**（区分大小写）。
- **一个 task 只能有一个模块**。两个模块写在同一个 `- name:` 下会报 `conflicting action statements`。
- **最后一定要跑第二遍**确认幂等；判分脚本可能会重新运行你的 playbook。

## 5. 动手练习

- [practice-set-1 · E4 节](../../labs/rhce/practice-set-1.md#e4)

## 6. 官方文档（本仓库离线版 + 考场可用的查法）

- 离线：
  - [playbook_guide/playbooks_intro.rst](../../references/rhce/ansible-docs/playbook_guide/playbooks_intro.rst)
  - [playbook_guide/playbooks_handlers.rst](../../references/rhce/ansible-docs/playbook_guide/playbooks_handlers.rst)
  - [playbook_guide/playbooks_checkmode.rst](../../references/rhce/ansible-docs/playbook_guide/playbooks_checkmode.rst)
  - [playbook_guide/playbooks_tags.rst](../../references/rhce/ansible-docs/playbook_guide/playbooks_tags.rst)
  - [playbook_guide/playbooks_startnstep.rst](../../references/rhce/ansible-docs/playbook_guide/playbooks_startnstep.rst)
  - [getting_started/get_started_playbook.rst](../../references/rhce/ansible-docs/getting_started/get_started_playbook.rst)
  - [reference_appendices/YAMLSyntax.rst](../../references/rhce/ansible-docs/reference_appendices/YAMLSyntax.rst)
- 考场：
  - `ansible-doc -t keyword -l` 看 play/task 层可用的所有关键字
  - `ansible-doc -t keyword serial`、`ansible-doc -t keyword force_handlers`
  - `ansible-playbook --help | less` 查 `--limit`、`--start-at-task`、`--tags`

## 7. 自测清单

- [ ] 能不查资料写出含 2 个 play、vars、tasks、handlers 的 playbook
- [ ] 能解释 `ok`、`changed`、`skipped`、`unreachable` 的含义
- [ ] 知道 handler 何时、以什么顺序执行
- [ ] 能说出为什么 `mode: 644` 是错的
- [ ] 会用 `--syntax-check`、`-C -D`、`-l`、`--start-at-task` 排错
- [ ] 能保证写出的 playbook 第二次执行 `changed=0`
