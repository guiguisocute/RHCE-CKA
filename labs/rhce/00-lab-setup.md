# RHCE 实验环境搭建：1 台控制节点 + 4 台受管节点

> **配套笔记**：[RHCE 轨道](../../notes/rhce/README.md) · [E1 架构](../../notes/rhce/01-ansible-architecture.md) · [E2 Inventory](../../notes/rhce/02-inventory-and-config.md) · [E9 navigator](../../notes/rhce/09-collections-navigator.md)
> **虚拟机创建方法**：复用 [RHCSA 实验环境](../rhcsa/00-lab-setup.md)（KVM/libvirt 或 VirtualBox、RHEL 开发者订阅、快照）

## 1. 拓扑

```text
                        192.168.122.0/24（libvirt 默认 NAT 网络，可自行调整）
 ┌──────────────────────┐
 │ control  .10         │  ansible-core、ansible-navigator、podman、本地软件仓库(httpd)
 └─────────┬────────────┘
           │ SSH（automation 用户，密钥登录，sudo 免密）
   ┌───────┼──────────────┬──────────────┬──────────────┐
 node1 .11        node2 .12        node3 .13        node4 .14
 dev              test             prod             prod
 vdb 2G           vdb 2G           (无额外磁盘)      vdb 1G
```

- 资源建议：control 2 vCPU / 4 GB（要跑 EE 容器），node 1 vCPU / 1.5~2 GB，系统盘 20 GB。
- **故意让 node3 没有 vdb、node4 的 vdb 较小**：用来练「磁盘不存在/空间不足时的条件判断与错误处理」。
- ⚠️ **RHEL 10 要求 x86-64-v3 CPU**（大约 Intel Haswell / AMD Zen 及以后）。KVM 里把 CPU 模式设为 `host-passthrough`（virt-manager →「CPU → 复制主机 CPU 配置」）；老 CPU 跑不了时改用 RHEL 9，并在报名时选 RHEL 9 版考试（若仍开放）。

## 2. 所有节点的基础配置

在**每台**机器上（安装时或安装后）：

```bash
sudo hostnamectl set-hostname node1.lab.example.com      # 各自的名字
sudo subscription-manager register                       # 使用开发者订阅账号
```

在 **control** 上写 `/etc/hosts`，再分发到所有节点（等会儿用 Ansible 分发也是一道好练习）：

```text
192.168.122.10  control.lab.example.com  control
192.168.122.11  node1.lab.example.com    node1
192.168.122.12  node2.lab.example.com    node2
192.168.122.13  node3.lab.example.com    node3
192.168.122.14  node4.lab.example.com    node4
```

## 3. 创建 automation 用户、SSH 免密、sudo 免密

考试环境一般已经准备好登录用户；自己搭环境时需要先做这一步（这本身也是考纲「Configure Ansible managed nodes」的内容）。

### 方法 A：手工（先用 root 密码登录一次）

```bash
# 在 control 上，以普通用户（例如 student）执行
ssh-keygen -t ed25519 -N '' -f ~/.ssh/id_ed25519

for h in node1 node2 node3 node4; do
  ssh root@$h "useradd -m automation 2>/dev/null; echo 'automation ALL=(ALL) NOPASSWD: ALL' > /etc/sudoers.d/automation; chmod 440 /etc/sudoers.d/automation"
  ssh-copy-id -i ~/.ssh/id_ed25519.pub automation@$h
done
```

> RHEL 9/10 默认禁止 root 用密码 SSH 登录（`PermitRootLogin prohibit-password`）。如果上面的 `ssh root@...` 失败：安装时勾选「允许 root 密码 SSH 登录」，或先在每台节点控制台上手工创建 automation 用户并设置密码，再用 `ssh-copy-id automation@...`。

### 方法 B：用 Ansible 引导（练习用）

需要控制节点有 `sshpass`（RHEL 默认仓库可能没有，需 EPEL，以实际为准），并且节点允许某个账号用密码登录：

```yaml
# bootstrap.yml —— 运行：ansible-playbook -i inventory bootstrap.yml -u root -k
---
- name: Bootstrap automation user
  hosts: all
  become: false
  tasks:
    - name: Create automation user
      ansible.builtin.user:
        name: automation
        state: present

    - name: Allow passwordless sudo
      ansible.builtin.copy:
        content: "automation ALL=(ALL) NOPASSWD: ALL\n"
        dest: /etc/sudoers.d/automation
        mode: "0440"
        validate: /usr/sbin/visudo -cf %s

    - name: Install SSH public key
      ansible.posix.authorized_key:
        user: automation
        key: "{{ lookup('ansible.builtin.file', '~/.ssh/id_ed25519.pub') }}"
        state: present
```

验证：`ssh automation@node1 sudo -n true && echo OK`。

## 4. 控制节点安装软件

```bash
# ansible-core：RHEL 9/10 AppStream 自带
sudo dnf install -y ansible-core python3-pip podman rhel-system-roles

# collections：ansible-core 只带 ansible.builtin，考纲要用的 ansible.posix / community.general 需额外安装
ansible-galaxy collection install ansible.posix community.general containers.podman
ansible-galaxy collection list
```

### ansible-navigator 两种装法

| 方式 | 命令 | 说明 |
|---|---|---|
| RPM（官方） | `sudo subscription-manager repos --list \| grep -i ansible-automation` 找到 AAP 仓库后 `--enable <仓库名>`，再 `sudo dnf install ansible-navigator` | 需要订阅里包含 Ansible Automation Platform；仓库名随 AAP 版本和 RHEL 版本变化，**以 `--list` 输出为准** |
| pip（实验可用） | `python3 -m pip install --user ansible-navigator` | 装到 `~/.local/bin`，确认它在 `PATH` 里 |

### 执行环境（EE）镜像

ansible-navigator 默认会用 podman 拉取并运行一个 EE 镜像：

```bash
ansible-navigator --help | grep -A2 -- '--eei'      # 查看默认镜像
podman login registry.redhat.io                     # 使用红帽官方 EE 时需要（用红帽账号登录）
podman pull registry.redhat.io/ansible-automation-platform-2x/ee-supported-rhel9:latest   # 示意：把 2x 换成实际版本号，名称以红帽 Catalog 为准
podman images
```

- 不想折腾镜像时：`ansible-navigator run site.yml -m stdout --ee false`（用本机 ansible-core，collections 用本机安装的）。
- 社区镜像（无需红帽账号）也可以，例如 navigator 的默认社区开发镜像；名称以 `--help` 输出为准。
- **EE 与 podman 的关系**：EE 只是一个 OCI 镜像；navigator 相当于帮你执行 `podman run -v $PWD:/runner/project <EE> ansible-playbook ...`。所以 RHCSA 的 [Podman 笔记](../../notes/rhcsa/10-containers-podman.md) 在这里会用到。

## 5. （推荐）在 control 上搭本地软件仓库和「考试素材服务器」

模拟考试里「仓库地址是 `http://...`」「role/collection 的 tar 包在 `http://...`」的场景：

```bash
sudo dnf install -y httpd
sudo mkdir -p /var/www/html/rhel /var/www/html/materials
# 1) 软件仓库：挂载 RHEL 安装 ISO（先把 ISO 拷到 /root/）
sudo mount -o loop,ro /root/rhel-10-x86_64-dvd.iso /var/www/html/rhel     # 文件名按实际
#    仓库地址即为 http://control.lab.example.com/rhel/BaseOS 和 .../rhel/AppStream
# 2) 素材：下载 collection tar 包（control 需联网）
ansible-galaxy collection download ansible.posix community.general -p /tmp/coll
sudo cp /tmp/coll/*.tar.gz /var/www/html/materials/
sudo restorecon -Rv /var/www/html
sudo systemctl enable --now httpd
sudo firewall-cmd --permanent --add-service=http && sudo firewall-cmd --reload
```

自己做一个 role tar 包放到 materials，用来练 `ansible-galaxy role install`：

```bash
cd /tmp && ansible-galaxy role init webinfo
echo -e "---\n- name: Hello\n  ansible.builtin.debug:\n    msg: webinfo role works" > webinfo/tasks/main.yml
tar czf webinfo.tar.gz webinfo && sudo cp webinfo.tar.gz /var/www/html/materials/
```

## 6. 项目目录起步模板

```bash
mkdir -p ~/ansible/{roles,collections,group_vars,host_vars,templates}
cd ~/ansible
```

`~/ansible/ansible.cfg`：

```ini
[defaults]
inventory        = /home/student/ansible/inventory
remote_user      = automation
roles_path       = /home/student/ansible/roles:/usr/share/ansible/roles
collections_path = /home/student/ansible/collections:/usr/share/ansible/collections
host_key_checking = False

[privilege_escalation]
become          = True
become_method   = sudo
become_user     = root
become_ask_pass = False
```

`~/ansible/inventory`：

```ini
[dev]
node1.lab.example.com

[test]
node2.lab.example.com

[prod]
node3.lab.example.com
node4.lab.example.com

[webservers:children]
prod
```

`~/ansible/ansible-navigator.yml`（可选）：

```yaml
---
ansible-navigator:
  mode: stdout
  playbook-artifact:
    enable: false
  execution-environment:
    enabled: true          # 没有镜像时改成 false
    pull:
      policy: missing
```

## 7. 验收

```bash
cd ~/ansible
ansible --version | grep 'config file'          # 应指向 ~/ansible/ansible.cfg
ansible-config dump --only-changed
ansible-inventory --graph
ansible all -m ansible.builtin.ping
ansible all -m ansible.builtin.command -a 'id' # 应显示 uid=0(root)（become 生效）
ansible-navigator run --help >/dev/null && echo navigator OK
```

全部通过后，给所有虚拟机**打快照**（例如 `rhce-base`），每做完一轮练习就回滚，保证环境干净。

下一步：[分节练习](practice-set-1.md) → [模拟考](mock-exam.md)
