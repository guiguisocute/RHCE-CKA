# RHCE-08 Roles

> **轨道**：[RHCE](README.md) ｜ **考纲**：EX294「Use roles and Ansible Content Collections → Create and work with roles / Install roles and use them in playbooks」 ｜ **建议用时**：5 h ｜ **难度**：★★☆
>
> **前置**：[RHCE-06 循环、条件、handler 与错误处理](06-loops-conditions-errors.md) · [RHCE-07 Jinja2 模板](07-jinja2-templates.md)
> **后续**：[RHCE-09 Collections 与 ansible-navigator](09-collections-navigator.md) · [RHCE-11 用 Ansible 自动化 RHCSA 任务](11-automate-rhcsa-tasks.md)
> **关联**（跨轨道）：[CKA-07 Helm 与 Kustomize](../cka/07-helm-kustomize.md)（role ≈ Helm chart：目录约定 + 默认值 + 模板） · [RHCE-12 RHEL System Roles](12-rhel-system-roles.md)

## 1. 这个知识点在网络中的位置

Role 把「一类配置」（比如 Apache、时间同步）的 task、handler、模板、默认变量打包成固定目录结构，可以被多个 playbook 复用、可以分享。
考试常见三种题：**自己写一个 role**、**从给定 URL/文件安装 role（ansible-galaxy）**、**使用 RHEL System Roles**（见 [E12](12-rhel-system-roles.md)）。

### 和 Helm chart 的类比

| Ansible role | Helm chart |
|---|---|
| `defaults/main.yml`（可被覆盖的默认值） | `values.yaml` |
| `templates/*.j2` | `templates/*.yaml` |
| `meta/main.yml`（依赖、元数据） | `Chart.yaml`（`dependencies`） |
| `ansible-galaxy role init` | `helm create` |
| `ansible-galaxy role install -r requirements.yml` | `helm repo add` + `helm install` |
| playbook 里 `roles:` + `vars:` 覆盖 | `helm install -f my-values.yaml` / `--set` |

## 2. 核心概念

### 目录结构（`ansible-galaxy role init apache` 生成）

```text
roles/apache/
├── defaults/main.yml    # 默认变量（优先级最低，供使用者覆盖）
├── vars/main.yml        # role 内部变量（优先级高）
├── tasks/main.yml       # ★ 入口
├── handlers/main.yml    # handler
├── templates/           # template 模块默认从这里找 src
├── files/               # copy 模块默认从这里找 src
├── meta/main.yml        # 作者、平台、依赖 dependencies
├── tests/               # 测试 inventory + playbook
└── README.md
```

只有需要的目录才必须存在，最小 role 只要 `tasks/main.yml`。

### 在 playbook 中使用 role 的三种方式

```yaml
# 1) roles: 关键字（最常见；在 tasks 之前执行）
- hosts: webservers
  roles:
    - apache
    - role: apache
      vars:
        apache_port: 8080

# 2) include_role：动态，可以配合 when/loop
- hosts: webservers
  tasks:
    - name: Use apache role conditionally
      ansible.builtin.include_role:
        name: apache
      when: "'prod' in group_names"

# 3) import_role：静态，解析时就展开
- hosts: webservers
  tasks:
    - name: Import apache role
      ansible.builtin.import_role:
        name: apache
```

### role 的搜索路径

1. playbook 同级的 `roles/` 目录
2. `ansible.cfg` 里 `roles_path`（冒号分隔多个）
3. 默认 `~/.ansible/roles:/usr/share/ansible/roles:/etc/ansible/roles`

## 3. 必会操作

### 写一个 role（考试经典：apache + 定制首页）

```bash
cd /home/student/ansible/roles
ansible-galaxy role init apache
```

`roles/apache/tasks/main.yml`：

```yaml
---
- name: Install httpd and firewalld
  ansible.builtin.dnf:
    name:
      - httpd
      - firewalld
    state: present

- name: Start and enable services
  ansible.builtin.service:
    name: "{{ item }}"
    state: started
    enabled: true
  loop:
    - httpd
    - firewalld

- name: Open http in firewall
  ansible.posix.firewalld:
    service: http
    permanent: true
    immediate: true
    state: enabled

- name: Deploy index.html from template
  ansible.builtin.template:
    src: index.html.j2
    dest: /var/www/html/index.html
    mode: "0644"
  notify: Restart httpd
```

`roles/apache/templates/index.html.j2`：

```jinja
Welcome to {{ ansible_facts['fqdn'] }} on {{ ansible_facts['default_ipv4']['address'] }}
```

`roles/apache/handlers/main.yml`：

```yaml
---
- name: Restart httpd
  ansible.builtin.service:
    name: httpd
    state: restarted
```

使用它的 `apache.yml`：

```yaml
---
- name: Deploy apache role
  hosts: webservers
  roles:
    - apache
```

### 用 ansible-galaxy 安装 role

`roles/requirements.yml`：

```yaml
---
- src: http://materials.example.com/roles/loadbalancer.tar.gz
  name: lb_role
- src: http://materials.example.com/roles/webinfo.tar.gz
  name: webinfo
# 也可以从 Galaxy 或 git 安装：
# - name: geerlingguy.nginx
# - src: https://github.com/user/repo.git
#   scm: git
#   version: main
#   name: myrole
```

```bash
ansible-galaxy role install -r roles/requirements.yml -p roles/   # -p 指定安装目录
ansible-galaxy role list                                          # 确认已安装
ansible-galaxy role remove lb_role -p roles/
```

## 4. 考试坑点

- **`-p` 不能忘**：不指定会装到 `~/.ansible/roles`，题目要求装到 `/home/student/ansible/roles` 时判分失败（或者确保 `roles_path` 第一个目录就是它）。
- **requirements.yml 里 `name:` 决定 role 目录名**，playbook 里要用这个名字引用。
- **role 内引用模板/文件不要写路径**：`src: index.html.j2` 即可，role 会自动去自己的 `templates/` 找。
- **`roles:` 先于 `tasks:` 执行**；要在 role 之前做准备工作用 `pre_tasks:`。
- **defaults vs vars**：给用户覆盖的放 `defaults/`；放在 `vars/` 的变量连 play `vars:` 都覆盖不了（除了 `-e`）。
- **role 的 handler 名字全局可见**，多个 role 的 handler 同名会冲突。
- `ansible-galaxy role init` 生成的 `meta/main.yml` 里 `galaxy_info` 可以不改，不影响运行。

## 5. 动手练习

- [practice-set-1 · E8 节](../../labs/rhce/practice-set-1.md#e8)

## 6. 官方文档（本仓库离线版 + 考场可用的查法）

- 离线：
  - [playbook_guide/playbooks_reuse_roles.rst](../../references/rhce/ansible-docs/playbook_guide/playbooks_reuse_roles.rst)（目录结构、搜索路径、`include_role` vs `import_role`）
  - [playbook_guide/playbooks_reuse.rst](../../references/rhce/ansible-docs/playbook_guide/playbooks_reuse.rst)
  - [galaxy/user_guide.rst](../../references/rhce/ansible-docs/galaxy/user_guide.rst)（requirements.yml 格式、`ansible-galaxy role install`）
  - [tips_tricks/sample_setup.rst](../../references/rhce/ansible-docs/tips_tricks/sample_setup.rst)
- 考场：
  - `ansible-galaxy role init --help`、`ansible-galaxy role install --help`
  - `ansible-doc ansible.builtin.include_role`、`ansible-doc ansible.builtin.import_role`
  - 参考现成的 role：`ls /usr/share/ansible/roles/`（装了 rhel-system-roles 时有大量范例）

## 7. 自测清单

- [ ] 能在 15 分钟内从 `ansible-galaxy role init` 开始写出一个带模板和 handler 的 role
- [ ] 能写出从 URL tar 包安装 role 的 requirements.yml，并指定名字
- [ ] 能说出 `defaults/` 与 `vars/` 的区别
- [ ] 知道 `roles:`、`include_role`、`import_role` 的区别和执行时机
- [ ] 能说出 role 与 Helm chart 的 3 个对应点
