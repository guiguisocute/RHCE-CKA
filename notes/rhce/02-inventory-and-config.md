# RHCE-02 Inventory 与 ansible.cfg

> **轨道**：[RHCE](README.md) ｜ **考纲**：EX294「Install and configure an Ansible control node」「Configure Ansible managed nodes」 ｜ **建议用时**：4 h ｜ **难度**：★☆☆
>
> **前置**：[RHCE-01 Ansible 架构与安装](01-ansible-architecture.md)
> **后续**：[RHCE-03 Ad-hoc、模块与 ansible-doc](03-adhoc-modules-docs.md)
> **关联**（跨轨道）：[RHCSA-08 用户、组与 sudo](../rhcsa/08-users-groups-sudo.md)（提权的底层就是 sudo） · [RHCSA-01 基础工具](../rhcsa/01-essential-tools.md)（ssh-keygen / ssh-copy-id） · [CKA-02 kubectl 高效操作](../cka/02-kubectl-efficiency.md)（kubeconfig context ≈ inventory + 连接配置）

## 1. 这个知识点在网络中的位置

考试第一题通常就是「在控制节点上创建 inventory 和 ansible.cfg」。这一题错了，后面所有题都跑不起来。
它也是「受管节点」那一侧的配置入口：用哪个用户登录、怎么提权、用哪个 Python。

## 2. 核心概念

### Inventory（INI 格式，考试最常用）

```ini
# inventory
[dev]
node1.example.com

[test]
node2.example.com

[prod]
node3.example.com
node4.example.com

[balancers]
node5.example.com

# 组的组：用 :children
[webservers:children]
prod

# 组变量（更推荐放进 group_vars/ 目录）
[prod:vars]
http_port=8080
```

- 隐含组：`all`（所有主机）、`ungrouped`（不属于任何组的主机）。
- 范围写法：`node[1:4].example.com`。
- 主机级连接变量：`node1 ansible_host=192.168.122.11 ansible_user=automation ansible_port=22`。

同样内容的 YAML 格式：

```yaml
all:
  children:
    dev:
      hosts:
        node1.example.com:
    prod:
      hosts:
        node3.example.com:
        node4.example.com:
    webservers:
      children:
        prod:
```

### host_vars / group_vars 目录

```text
~/ansible/
├── ansible.cfg
├── inventory
├── group_vars/
│   ├── all.yml          # 所有主机
│   └── prod.yml         # prod 组
└── host_vars/
    └── node1.example.com.yml
```

`group_vars/`、`host_vars/` 放在 **inventory 文件同级目录**或 **playbook 同级目录**都会被自动加载。

### ansible.cfg 查找顺序（第一个找到的生效，不合并）

1. 环境变量 `ANSIBLE_CONFIG` 指定的文件
2. **当前目录**下的 `ansible.cfg`
3. 用户家目录 `~/.ansible.cfg`
4. `/etc/ansible/ansible.cfg`

> 安全限制：如果当前目录是 world-writable，ansible 会忽略其中的 ansible.cfg。

### 考试级 ansible.cfg 模板

```ini
[defaults]
inventory       = /home/student/ansible/inventory
remote_user     = automation
roles_path      = /home/student/ansible/roles:/usr/share/ansible/roles
collections_path = /home/student/ansible/collections:/usr/share/ansible/collections
host_key_checking = False
forks           = 10
# vault_password_file = /home/student/ansible/vault-pass.txt

[privilege_escalation]
become          = True
become_method   = sudo
become_user     = root
become_ask_pass = False
```

> 老资料里常见复数写法 `collections_paths`；新版本推荐单数 `collections_path`，复数仍兼容（较新的 ansible-core 会提示弃用）。拿不准就以考场里 `ansible-config list` 的输出为准。

## 3. 必会操作

```bash
# 验证 inventory
ansible-inventory -i inventory --graph          # 树状显示组关系
ansible-inventory -i inventory --list -y        # YAML 格式输出全部主机和变量
ansible-inventory --host node1.example.com      # 某台主机最终合并后的变量
ansible prod --list-hosts                       # 测试主机模式（pattern）

# 主机模式 pattern
ansible 'webservers:&prod' --list-hosts         # 交集
ansible 'all:!dev' --list-hosts                 # 排除
ansible 'node[1:3]*' --list-hosts               # 通配

# 配置相关
ansible-config dump --only-changed              # ★ 只显示和默认值不同的配置，确认 ansible.cfg 生效
ansible-config list | less                      # 所有可配置项及说明（考场查键名）
ansible-config init --disabled > ansible.cfg.example   # 生成带注释的完整模板（全部注释掉）

# 受管节点准备：SSH key + sudo（手工版；考试可能要求用 playbook 完成）
ssh-keygen -t ed25519 -N '' -f ~/.ssh/id_ed25519
ssh-copy-id automation@node1.example.com
echo 'automation ALL=(ALL) NOPASSWD: ALL' | sudo tee /etc/sudoers.d/automation
sudo visudo -cf /etc/sudoers.d/automation        # 语法检查
```

## 4. 考试坑点

- **路径用绝对路径**：题目通常指定 `/home/<user>/ansible/inventory`，写相对路径在别的目录执行会失效。
- **`ansible-config dump --only-changed` 是最好的自检**：输出里看不到你设置的 inventory/remote_user，说明 ansible.cfg 没生效。
- **组名不要有 `-`**：ansible 会警告非法字符，推荐用下划线。
- **`[group:children]` 写错成 `[group-children]`** 是常见拼写错误。
- **变量优先级**：host_vars > group_vars/具体组 > group_vars/all，详见 [E5](05-variables-facts.md)。
- 题目要求「用 automation 用户登录、以 root 执行」→ `remote_user = automation` + `become = True`，两者缺一不可。

## 5. 动手练习

- [practice-set-1 · E2 节](../../labs/rhce/practice-set-1.md#e2)
- 起步模板：[labs/rhce/00-lab-setup.md](../../labs/rhce/00-lab-setup.md)

## 6. 官方文档（本仓库离线版 + 考场可用的查法）

- 离线：
  - [inventory_guide/intro_inventory.rst](../../references/rhce/ansible-docs/inventory_guide/intro_inventory.rst)（INI/YAML 两种格式、组变量、`children`）
  - [inventory_guide/intro_patterns.rst](../../references/rhce/ansible-docs/inventory_guide/intro_patterns.rst)（`&`、`!`、通配）
  - [inventory_guide/connection_details.rst](../../references/rhce/ansible-docs/inventory_guide/connection_details.rst)
  - [installation_guide/intro_configuration.rst](../../references/rhce/ansible-docs/installation_guide/intro_configuration.rst)（配置文件查找顺序）
  - [playbook_guide/playbooks_privilege_escalation.rst](../../references/rhce/ansible-docs/playbook_guide/playbooks_privilege_escalation.rst)
  - [tips_tricks/sample_setup.rst](../../references/rhce/ansible-docs/tips_tricks/sample_setup.rst)（目录结构范例）
- 考场：
  - `ansible-config list` → 搜 `DEFAULT_ROLES_PATH`、`COLLECTIONS_PATHS` 查键名和 ini 节名
  - `ansible-config init --disabled | grep -A3 become` 快速找到 `[privilege_escalation]` 写法
  - `ansible-doc -t connection ssh` 查 `ansible_user`、`ansible_port` 等连接变量
  - `ansible-doc -t become sudo` 查提权参数
  - `ansible-doc -t inventory ini` / `ansible-doc -t inventory yaml` 查 inventory 格式说明和示例

## 7. 自测清单

- [ ] 5 分钟内从零写出题目要求的 inventory（含组的组）和 ansible.cfg
- [ ] 能背出 ansible.cfg 的 4 级查找顺序
- [ ] 会用 `ansible-inventory --graph` 和 `ansible-config dump --only-changed` 自检
- [ ] 知道 `group_vars/` 应该放在哪个目录才会被加载
- [ ] 能写出交集、排除两种 host pattern
- [ ] 能独立完成受管节点的 SSH 免密 + sudo 免密配置
