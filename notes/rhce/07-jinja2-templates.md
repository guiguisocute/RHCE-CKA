# RHCE-07 Jinja2 模板

> **轨道**：[RHCE](README.md) ｜ **考纲**：EX294「Manage content → Create and use templates to create customized configuration files」 ｜ **建议用时**：5 h ｜ **难度**：★★☆
>
> **前置**：[RHCE-06 循环、条件、handler 与错误处理](06-loops-conditions-errors.md)
> **后续**：[RHCE-08 Roles](08-roles.md)
> **关联**（跨轨道）：[CKA-07 Helm 与 Kustomize](../cka/07-helm-kustomize.md)（Helm 用 Go template，思路完全一样） · [RHCE-05 变量与 facts](05-variables-facts.md)

## 1. 这个知识点在网络中的位置

`copy` 只能发「死」文件，`template` 能根据每台主机的 facts/变量生成不同内容——比如每台机器的 `/etc/hosts`、带主机名的欢迎页、按组生成的配置文件。
考试几乎必有一道「用模板生成 `/etc/lab-hosts`（或类似文件），包含所有主机的 IP 和名字」的题。

### 和 Helm 的类比（为 CKA 铺路）

| 概念 | Ansible (Jinja2) | Helm (Go template) |
|---|---|---|
| 模板文件 | `templates/xxx.j2` | `templates/deployment.yaml` |
| 变量来源 | inventory / vars / facts | `values.yaml` + `--set` |
| 取值 | `{{ http_port }}` | `{{ .Values.httpPort }}` |
| 条件 | `{% if x %}...{% endif %}` | `{{ if .Values.x }}...{{ end }}` |
| 循环 | `{% for h in groups['all'] %}` | `{{ range .Values.hosts }}` |
| 过滤器/函数 | `{{ name \| upper }}`、`default('x')` | `{{ .Values.name \| upper }}`、`default "x"` |
| 渲染预览 | `ansible-playbook -C -D` | `helm template` |

## 2. 核心概念

| 语法 | 用途 |
|---|---|
| `{{ expr }}` | 输出表达式 |
| `{% stmt %}` | 控制语句：`if`/`for`/`set` |
| `{# comment #}` | 注释，不输出 |
| `{%- ... -%}` | 去掉两侧空白/换行 |
| `{{ var \| filter }}` | 过滤器 |

### 常用过滤器

| 过滤器 | 示例 | 结果 |
|---|---|---|
| `default` | `{{ port \| default(80) }}` | 未定义时用默认值 |
| `upper`/`lower` | `{{ 'a' \| upper }}` | `A` |
| `join` | `{{ list \| join(',') }}` | `a,b,c` |
| `int` / `string` / `bool` | `{{ '3' \| int + 1 }}` | `4` |
| `length` | `{{ groups['all'] \| length }}` | 主机数 |
| `password_hash` | `{{ 'redhat' \| password_hash('sha512') }}` | `$6$...`，给 user 模块用 |
| `regex_replace` | `{{ 'a-b' \| regex_replace('-', '_') }}` | `a_b` |
| `to_nice_yaml` / `to_json` | 数据结构序列化 | |
| `dict2items` / `items2dict` | 字典 ↔ 列表 | |
| `ipaddr` 系列 | 需 `ansible.utils` collection | |

## 3. 必会操作

### 生成所有主机的 hosts 文件（考试经典题）

`templates/lab-hosts.j2`：

```jinja
# {{ ansible_managed }}
127.0.0.1   localhost localhost.localdomain
::1         localhost localhost.localdomain
{% for host in groups['all'] %}
{{ hostvars[host]['ansible_facts']['default_ipv4']['address'] }}  {{ hostvars[host]['ansible_facts']['fqdn'] }}  {{ hostvars[host]['ansible_facts']['hostname'] }}
{% endfor %}
```

`hosts.yml`：

```yaml
---
- name: Gather facts from every host first
  hosts: all
  gather_facts: true
  tasks: []

- name: Deploy /etc/lab-hosts to dev group
  hosts: dev
  tasks:
    - name: Render template
      ansible.builtin.template:
        src: templates/lab-hosts.j2
        dest: /etc/lab-hosts
        owner: root
        group: root
        mode: "0644"
```

> 第一个 play 的目的：让 `hostvars[...]` 里有**所有主机**的 facts。只对 dev 收集 facts 的话，其他主机的 IP 会 undefined。

### 条件 + 默认值

```jinja
Server: {{ ansible_facts['fqdn'] }}
Memory: {{ ansible_facts['memtotal_mb'] }} MB
{% if 'prod' in group_names %}
Environment: production
{% else %}
Environment: {{ env_name | default('development') }}
{% endif %}
Disk vdb: {{ ansible_facts['devices']['vdb']['size'] if 'vdb' in ansible_facts['devices'] else 'NONE' }}
```

### 硬件报告类题目

```yaml
- name: Hardware report
  hosts: all
  tasks:
    - name: Write report from template
      ansible.builtin.template:
        src: templates/hwreport.j2
        dest: /root/hwreport.txt
        mode: "0644"
```

```jinja
HOST={{ inventory_hostname }}
MEMORY={{ ansible_facts['memtotal_mb'] }}
BIOS={{ ansible_facts['bios_version'] }}
DISK_SIZE_VDA={{ ansible_facts['devices']['vda']['size'] | default('NONE') }}
DISK_SIZE_VDB={{ ansible_facts['devices']['vdb']['size'] if 'vdb' in ansible_facts['devices'] else 'NONE' }}
```

> 注意：`ansible_facts['devices']['vdb']` 不存在时，`['size'] | default(...)` 仍可能报错（父键不存在）；最稳的写法是先判断键是否存在，如上面的 `if ... else`。

## 4. 考试坑点

- **`template` 的 `src` 在控制节点，`dest` 在受管节点**；src 相对路径默认找 playbook 同级 `templates/` 目录（在 role 里找 role 的 `templates/`）。
- **for 循环多出空行**：用 `{%- for ... %}` 或在 `ansible.cfg`/task 中设 `trim_blocks`（template 模块默认 `trim_blocks: true`）。
- **`{{ ansible_managed }}`**：文件开头放上它是好习惯，提示文件由 Ansible 管理。
- **把 `.j2` 当 YAML 写**：模板文件里不需要 YAML 缩进规则，但模板里**生成的**如果是 YAML/INI，缩进要对。
- **hostvars 取不到**：见上面「先收集所有主机 facts」。
- `password_hash` 每次生成不同 salt → 每次 changed；需要幂等时用固定 salt：`password_hash('sha512', 'mysalt')`，或 `user` 模块加 `update_password: on_create`。

## 5. 动手练习

- [practice-set-1 · E7 节](../../labs/rhce/practice-set-1.md#e7)

## 6. 官方文档（本仓库离线版 + 考场可用的查法）

- 离线：
  - [playbook_guide/playbooks_templating.rst](../../references/rhce/ansible-docs/playbook_guide/playbooks_templating.rst)
  - [playbook_guide/playbooks_filters.rst](../../references/rhce/ansible-docs/playbook_guide/playbooks_filters.rst)（含 `password_hash`、`default`、`dict2items`）
  - [playbook_guide/playbooks_templating_undef.rst](../../references/rhce/ansible-docs/playbook_guide/playbooks_templating_undef.rst)
  - [playbook_guide/complex_data_manipulation.rst](../../references/rhce/ansible-docs/playbook_guide/complex_data_manipulation.rst)
  - [playbook_guide/playbooks_lookups.rst](../../references/rhce/ansible-docs/playbook_guide/playbooks_lookups.rst)
- 考场：
  - `ansible-doc ansible.builtin.template`（EXAMPLES 里有 `trim_blocks`、`validate` 用法）
  - `ansible-doc -t filter -l`、`ansible-doc -t filter ansible.builtin.password_hash`（较新 ansible-core 支持 filter 文档）
  - 用 `ansible.builtin.debug: msg="{{ ... }}"` 先试表达式，再写进模板

## 7. 自测清单

- [ ] 能在 10 分钟内写出「所有主机 IP + FQDN + 短名」的 hosts 模板并部署
- [ ] 知道为什么要先对 `all` 收集 facts
- [ ] 会写 `if/else`、`for`、`default`、`join`
- [ ] 能处理「某块磁盘可能不存在」的情况
- [ ] 能说出 Jinja2 和 Helm 模板的 3 个对应点
