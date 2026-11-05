# RHCE-11 用 Ansible 自动化 RHCSA 任务（枢纽节点）

> **轨道**：[RHCE](README.md) ｜ **考纲**：EX294「Automate standard RHCSA tasks using Ansible modules」「Configure managed nodes」 ｜ **建议用时**：10 h ｜ **难度**：★★★
>
> **前置**：[RHCE-08 Roles](08-roles.md) · [RHCE-10 Ansible Vault](10-vault.md) · 以及下表中所有 RHCSA 笔记
> **后续**：[RHCE-12 RHEL System Roles](12-rhel-system-roles.md) · [原创模拟考](../../labs/rhce/mock-exam.md)
> **关联**（跨轨道）：[RHCSA 轨道全部 10 个节点](../rhcsa/README.md) · [CKA-03 用 kubeadm 搭建集群](../cka/03-kubeadm-install.md)（装 K8s 前的节点准备——关 swap、加载内核模块、sysctl——正适合用 Ansible 批量做）

## 1. 这个知识点在网络中的位置

这是整个 RHCE 轨道的**枢纽**：EX294 的大部分分数来自「把 RHCSA 的操作用模块实现」。
学习方法：对下表每一行，先回到对应 RHCSA 笔记确认**手工命令**会做，再用 `ansible-doc` 查模块，写成 task，最后用 ad-hoc 命令验证结果。

## 2. 核心概念：RHCSA 任务 → Ansible 模块对照表

| RHCSA 任务 | 手工命令 | Ansible 模块 | 复习 RHCSA 笔记 |
|---|---|---|---|
| 创建/修改文件内容 | `vim`、`echo >>`、`sed -i` | `ansible.builtin.copy`、`lineinfile`、`blockinfile`、`replace`、`template` | [RHCSA-01](../rhcsa/01-essential-tools.md) |
| 文件/目录、权限、属主、链接 | `mkdir`、`chmod`、`chown`、`ln -s` | `ansible.builtin.file`（`state: directory/link/hard/touch/absent`） | [RHCSA-01](../rhcsa/01-essential-tools.md) |
| ACL | `setfacl` | `ansible.posix.acl` | [RHCSA-01](../rhcsa/01-essential-tools.md) |
| 归档与压缩 | `tar czf`、`tar xf` | `community.general.archive`、`ansible.builtin.unarchive` | [RHCSA-01](../rhcsa/01-essential-tools.md) |
| 执行脚本 | `bash script.sh` | `ansible.builtin.script`、`command`（配合 `creates`） | [RHCSA-02](../rhcsa/02-shell-scripting.md) |
| 默认启动 target | `systemctl set-default` | `ansible.builtin.command` + `changed_when`（或 `file` 管理 `default.target` 软链接） | [RHCSA-03](../rhcsa/03-operate-running-systems.md) |
| 服务启停/开机自启 | `systemctl enable --now` | `ansible.builtin.service`、`ansible.builtin.systemd_service` | [RHCSA-03](../rhcsa/03-operate-running-systems.md) |
| 重启 | `reboot` | `ansible.builtin.reboot` | [RHCSA-03](../rhcsa/03-operate-running-systems.md) |
| tuned 性能配置 | `tuned-adm profile` | `ansible.builtin.command` + 判断（无专用内置模块）或 System Role `kernel_settings` | [RHCSA-03](../rhcsa/03-operate-running-systems.md) |
| 日志持久化 | `/etc/systemd/journald.conf` | `ansible.builtin.lineinfile` / `ini_file` + handler 重启 `systemd-journald` | [RHCSA-03](../rhcsa/03-operate-running-systems.md) |
| 分区 | `parted`/`fdisk` | `community.general.parted` | [RHCSA-04](../rhcsa/04-local-storage-lvm.md) |
| PV / VG | `pvcreate`、`vgcreate` | `community.general.lvg` | [RHCSA-04](../rhcsa/04-local-storage-lvm.md) |
| LV 创建/扩容 | `lvcreate`、`lvextend -r` | `community.general.lvol`（`resizefs: true`） | [RHCSA-04](../rhcsa/04-local-storage-lvm.md) |
| swap | `mkswap`、`swapon`、fstab | `community.general.filesystem`（`fstype: swap`）+ `ansible.posix.mount`（`fstype: swap`）/ `command: swapon -a` | [RHCSA-04](../rhcsa/04-local-storage-lvm.md) |
| 创建文件系统 | `mkfs.xfs`、`mkfs.ext4` | `community.general.filesystem` | [RHCSA-05](../rhcsa/05-file-systems-nfs-autofs.md) |
| 持久挂载 | `/etc/fstab`、`mount -a` | `ansible.posix.mount`（`state: mounted`） | [RHCSA-05](../rhcsa/05-file-systems-nfs-autofs.md) |
| NFS 挂载 | fstab `_netdev` | `ansible.posix.mount`（`fstype: nfs`） | [RHCSA-05](../rhcsa/05-file-systems-nfs-autofs.md) |
| autofs | `/etc/auto.master.d/*.autofs` | `copy`/`template` + `service`（autofs） | [RHCSA-05](../rhcsa/05-file-systems-nfs-autofs.md) |
| 软件仓库 | `/etc/yum.repos.d/*.repo` | `ansible.builtin.yum_repository`、`ansible.builtin.rpm_key` | [RHCSA-06](../rhcsa/06-software-scheduling-boot.md) |
| 安装/删除/更新软件包、组 | `dnf install`、`dnf group install` | `ansible.builtin.dnf`（组写 `'@Development Tools'`）、`ansible.builtin.package` | [RHCSA-06](../rhcsa/06-software-scheduling-boot.md) |
| Flatpak 仓库与应用 | `flatpak remote-add`、`flatpak install` | `community.general.flatpak_remote`、`community.general.flatpak` | [RHCSA-06](../rhcsa/06-software-scheduling-boot.md) |
| cron 计划任务 | `crontab -e -u` | `ansible.builtin.cron` | [RHCSA-06](../rhcsa/06-software-scheduling-boot.md) |
| at 一次性任务 | `at` | `ansible.posix.at` | [RHCSA-06](../rhcsa/06-software-scheduling-boot.md) |
| 时间同步 chrony | `/etc/chrony.conf` | `lineinfile` + `service`，或 System Role `timesync`（[E12](12-rhel-system-roles.md)） | [RHCSA-06](../rhcsa/06-software-scheduling-boot.md) |
| 时区 | `timedatectl set-timezone` | `community.general.timezone` | [RHCSA-06](../rhcsa/06-software-scheduling-boot.md) |
| 内核参数 | `sysctl -w` + `/etc/sysctl.d/` | `ansible.posix.sysctl` | [RHCSA-06](../rhcsa/06-software-scheduling-boot.md) |
| 主机名 | `hostnamectl set-hostname` | `ansible.builtin.hostname` | [RHCSA-07](../rhcsa/07-networking-nmcli.md) |
| 网卡 IP / DNS | `nmcli con mod` | `community.general.nmcli`，或 System Role `network` | [RHCSA-07](../rhcsa/07-networking-nmcli.md) |
| /etc/hosts | 编辑文件 | `ansible.builtin.lineinfile` / `template` | [RHCSA-07](../rhcsa/07-networking-nmcli.md) |
| 用户 / 组 | `useradd`、`groupadd`、`usermod -aG` | `ansible.builtin.user`、`ansible.builtin.group` | [RHCSA-08](../rhcsa/08-users-groups-sudo.md) |
| 密码与密码策略 | `passwd`、`chage` | `user`（`password`、`password_expire_max`）、`lineinfile` 改 `/etc/login.defs` | [RHCSA-08](../rhcsa/08-users-groups-sudo.md) |
| sudo 规则 | `/etc/sudoers.d/` | `ansible.builtin.copy`/`lineinfile`（`validate: /usr/sbin/visudo -cf %s`）、`community.general.sudoers` | [RHCSA-08](../rhcsa/08-users-groups-sudo.md) |
| SSH 公钥 | `ssh-copy-id` | `ansible.posix.authorized_key` | [RHCSA-08](../rhcsa/08-users-groups-sudo.md) |
| 防火墙 | `firewall-cmd --permanent` | `ansible.posix.firewalld`（`permanent` + `immediate`） | [RHCSA-09](../rhcsa/09-security-firewalld-selinux.md) |
| SELinux 模式 | `setenforce`、`/etc/selinux/config` | `ansible.posix.selinux` | [RHCSA-09](../rhcsa/09-security-firewalld-selinux.md) |
| SELinux 布尔值 | `setsebool -P` | `ansible.posix.seboolean`（`persistent: true`） | [RHCSA-09](../rhcsa/09-security-firewalld-selinux.md) |
| SELinux 文件上下文 | `semanage fcontext` + `restorecon` | `community.general.sefcontext` + `command: restorecon -Rv` | [RHCSA-09](../rhcsa/09-security-firewalld-selinux.md) |
| SELinux 端口 | `semanage port -a` | `community.general.seport` | [RHCSA-09](../rhcsa/09-security-firewalld-selinux.md) |
| 容器 | `podman run`、systemd 单元 | `containers.podman.podman_container`、`podman_image`（需 `containers.podman` collection） | [RHCSA-10](../rhcsa/10-containers-podman.md) |

## 3. 必会操作：一份「全家桶」示例

```yaml
---
- name: RHCSA tasks automated
  hosts: dev
  become: true
  tasks:
    - name: Configure BaseOS repository
      ansible.builtin.yum_repository:
        name: BaseOS
        description: Local BaseOS
        baseurl: http://repo.example.com/BaseOS
        gpgcheck: true
        gpgkey: http://repo.example.com/RPM-GPG-KEY-redhat-release
        enabled: true

    - name: Install packages and a package group
      ansible.builtin.dnf:
        name:
          - httpd
          - "@RPM Development Tools"
        state: present

    - name: Create partition 1 on /dev/vdb (1 GiB)
      community.general.parted:
        device: /dev/vdb
        number: 1
        state: present
        part_end: 1GiB
        flags: [lvm]

    - name: Create volume group
      community.general.lvg:
        vg: vg_data
        pvs: /dev/vdb1

    - name: Create logical volume
      community.general.lvol:
        vg: vg_data
        lv: lv_web
        size: 500m

    - name: Make XFS file system
      community.general.filesystem:
        dev: /dev/vg_data/lv_web
        fstype: xfs

    - name: Mount persistently
      ansible.posix.mount:
        path: /srv/web
        src: /dev/vg_data/lv_web
        fstype: xfs
        state: mounted          # 写 fstab 并立即挂载

    - name: SELinux file context for /srv/web
      community.general.sefcontext:
        target: '/srv/web(/.*)?'
        setype: httpd_sys_content_t
        state: present

    - name: Apply context
      ansible.builtin.command: restorecon -Rv /srv/web
      register: rc_out
      changed_when: rc_out.stdout | length > 0

    - name: Open http permanently and now
      ansible.posix.firewalld:
        service: http
        permanent: true
        immediate: true
        state: enabled

    - name: Cron job for user bob every 2 minutes
      ansible.builtin.cron:
        name: log heartbeat
        user: bob
        minute: "*/2"
        job: logger "heartbeat from bob"

    - name: Set default target to multi-user
      ansible.builtin.command: systemctl set-default multi-user.target
      register: tgt
      changed_when: "'Created symlink' in tgt.stderr"
```

## 4. 考试坑点

- **`ansible.posix.mount` 的 state**：`mounted` = 写 fstab + 挂载；`present` = 只写 fstab；`unmounted`；`absent` = 卸载并删除条目。题目说「持久挂载」用 `mounted`。
- **firewalld 的 `permanent` 与 `immediate`**：只写 `permanent: true` 不会立即生效；只写 `immediate` 重启后丢失。两个都写。
- **sefcontext 只改策略不改文件**，必须再 `restorecon`。
- **parted 单位**：`part_end: 1GiB`；多个分区时第二个用 `part_start`。磁盘不存在时先用 `when` 判断（见 [E6](06-loops-conditions-errors.md)）。
- **lvol 的 `size`**：`500m`、`1g`、`100%FREE`；扩容时加 `resizefs: true`；缩小需要 `force`（别轻易做）。
- **dnf 组名**写成 `"@组名"`，用 `dnf group list` 查准确名字（注意 RHEL 10 上组名可能有变化）。
- **重启类操作**：改 SELinux disabled/enabled、某些内核参数需要 `ansible.builtin.reboot`，题目没要求就别乱重启。
- **验证**：每做完一类，用 ad-hoc 验证——`ansible dev -a 'lsblk'`、`-a 'findmnt /srv/web'`、`-a 'firewall-cmd --list-services'`、`-a 'ls -Zd /srv/web'`。

## 5. 动手练习

- [practice-set-1 · E11 节](../../labs/rhce/practice-set-1.md#e11)
- 综合：[原创模拟考](../../labs/rhce/mock-exam.md)
- 反向训练：把 [RHCSA 练习](../../labs/rhcsa/practice-set-1.md) 的每道题都改写成 playbook

## 6. 官方文档（本仓库离线版 + 考场可用的查法）

- 离线：
  - [playbook_guide/playbooks_privilege_escalation.rst](../../references/rhce/ansible-docs/playbook_guide/playbooks_privilege_escalation.rst)
  - [playbook_guide/playbooks_reuse.rst](../../references/rhce/ansible-docs/playbook_guide/playbooks_reuse.rst)
  - [tips_tricks/ansible_tips_tricks.rst](../../references/rhce/ansible-docs/tips_tricks/ansible_tips_tricks.rst)
  - 模块完整参数文档不在离线包内（由各 collection 自带），**以 `ansible-doc` 为准**
- 考场：
  - `ansible-doc -l | grep -E 'lvol|lvg|parted|filesystem|mount|sefcontext|seport|firewalld|cron|at$'`
  - `ansible-doc -s community.general.lvol` 等，直接复制 snippet
  - `ansible-galaxy collection list` 确认 `ansible.posix`、`community.general` 已安装

## 7. 自测清单

- [ ] 对照表每一行，都能不看资料写出 task（参数可查 `ansible-doc`）
- [ ] 能用一个 playbook 完成：分区 → VG → LV → 文件系统 → 持久挂载 → SELinux 上下文
- [ ] 知道 mount 模块 4 种 state 的区别
- [ ] 能写出 firewalld 永久 + 立即生效的 task
- [ ] 所有示例 playbook 第二次运行 `changed=0`
