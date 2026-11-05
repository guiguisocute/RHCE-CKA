# RHCE-12 RHEL System Roles

> **轨道**：[RHCE](README.md) ｜ **考纲**：EX294「Use roles and Ansible Content Collections → Obtain a set of related roles, supplementary modules, and other content from content collections, and use them in a playbook」（RHEL 9 版考纲有「Install and use RHEL system roles」；RHEL 10 版是否保留以官方为准） ｜ **建议用时**：4 h ｜ **难度**：★★☆
>
> **前置**：[RHCE-09 Collections 与 ansible-navigator](09-collections-navigator.md) · [RHCE-11 用 Ansible 自动化 RHCSA 任务](11-automate-rhcsa-tasks.md)
> **后续**：[原创模拟考](../../labs/rhce/mock-exam.md) → [CKA 轨道](../cka/README.md)
> **关联**（跨轨道）：[RHCSA-06 软件、计划任务、时间](../rhcsa/06-software-scheduling-boot.md)（timesync） · [RHCSA-09 防火墙与 SELinux](../rhcsa/09-security-firewalld-selinux.md)（selinux / firewall） · [RHCSA-04 本地存储与 LVM](../rhcsa/04-local-storage-lvm.md)（storage） · [RHCSA-07 网络配置](../rhcsa/07-networking-nmcli.md)（network）

## 1. 这个知识点在网络中的位置

RHEL System Roles 是红帽官方维护的一套 roles（上游项目叫 **linux-system-roles**），用**统一的变量接口**管理时间同步、SELinux、防火墙、存储、网络等——不用关心底层是 chrony 还是 ntpd。
它也是「collection 里打包 role」的最好范例：`redhat.rhel_system_roles` collection。考试中你只需**读懂示例、改变量**。

## 2. 核心概念

| 项 | 说明 |
|---|---|
| 软件包 | `rhel-system-roles`（RHEL AppStream） |
| role 形式 | `/usr/share/ansible/roles/rhel-system-roles.<名字>`（例如 `rhel-system-roles.timesync`） |
| collection 形式 | `/usr/share/ansible/collections/ansible_collections/redhat/rhel_system_roles/`，引用名 `redhat.rhel_system_roles.<名字>` |
| 示例和文档 | `/usr/share/doc/rhel-system-roles/<名字>/`（README 和 `example-*-playbook.yml`） |
| 上游 | `linux-system-roles.<名字>`，变量与 RHEL 版一致 |

常用 role：`timesync`、`selinux`、`firewall`、`storage`、`network`、`crypto_policies`、`kernel_settings`、`sshd`、`journald`、`logging`、`podman`、`systemd`、`kdump` 等（以 `ls /usr/share/ansible/roles/` 实际输出为准）。

## 3. 必会操作

```bash
sudo dnf install -y rhel-system-roles
ls /usr/share/ansible/roles/                                     # role 形式
ls /usr/share/ansible/collections/ansible_collections/redhat/rhel_system_roles/roles/   # collection 形式
ls /usr/share/doc/rhel-system-roles/timesync/                    # 示例 playbook
cp /usr/share/doc/rhel-system-roles/timesync/example-timesync-playbook.yml ~/ansible/timesync.yml
```

> 如果用 role 形式，`ansible.cfg` 的 `roles_path` 要包含 `/usr/share/ansible/roles`。用 collection 形式则需要 `collections_path` 包含 `/usr/share/ansible/collections`（默认已包含）。

### timesync：配置 NTP

```yaml
---
- name: Configure time synchronization
  hosts: all
  vars:
    timesync_ntp_servers:
      - hostname: classroom.example.com
        iburst: true
  roles:
    - redhat.rhel_system_roles.timesync      # 或 rhel-system-roles.timesync
```

### selinux：模式、布尔值、文件上下文、端口

```yaml
---
- name: Manage SELinux with the system role
  hosts: webservers
  vars:
    selinux_policy: targeted
    selinux_state: enforcing
    selinux_booleans:
      - name: httpd_can_network_connect
        state: true
        persistent: true
    selinux_fcontexts:
      - target: '/srv/web(/.*)?'
        setype: httpd_sys_content_t
        state: present
    selinux_restore_dirs:
      - /srv/web
    selinux_ports:
      - ports: 8888
        proto: tcp
        setype: http_port_t
        state: present
  tasks:
    - name: Apply selinux role, reboot if required
      block:
        - name: Run selinux role
          ansible.builtin.include_role:
            name: redhat.rhel_system_roles.selinux
      rescue:
        - name: Fail if the failure was not caused by a needed reboot
          ansible.builtin.fail:
            msg: SELinux role failed for another reason
          when: not selinux_reboot_required | default(false)

        - name: Reboot the host
          ansible.builtin.reboot:

        - name: Re-run selinux role after reboot
          ansible.builtin.include_role:
            name: redhat.rhel_system_roles.selinux
```

> 只有在 `disabled` ↔ `enabled` 切换时 role 才会因需要重启而失败（设置 `selinux_reboot_required` fact）。这种 `block/rescue` 结构在 `/usr/share/doc/rhel-system-roles/selinux/` 的示例里有，**考场直接复制改**。

### firewall

```yaml
---
- name: Firewall via system role
  hosts: webservers
  vars:
    firewall:
      - service: http
        state: enabled
      - port: 8080/tcp
        state: enabled
  roles:
    - redhat.rhel_system_roles.firewall
```

### storage：LVM + 文件系统 + 挂载一次完成

```yaml
---
- name: Storage via system role
  hosts: dev
  vars:
    storage_pools:
      - name: vg_app
        type: lvm
        disks:
          - vdb
        volumes:
          - name: lv_data
            size: 500 MiB
            fs_type: xfs
            mount_point: /data
            state: present
  roles:
    - redhat.rhel_system_roles.storage
```

## 4. 考试坑点

- **role 名字两种写法别混**：`rhel-system-roles.timesync`（role 路径）vs `redhat.rhel_system_roles.timesync`（collection FQCN）。哪个能用取决于你配置的路径；先 `ls` 确认。
- **示例在 `/usr/share/doc/rhel-system-roles/`**：考场上最快的做法是 `cp` 示例再改变量，而不是凭记忆写。
- **变量名必须完全一致**（`timesync_ntp_servers` 不是 `ntp_servers`）；拼错不会报错，只是不生效。
- **navigator + EE**：EE 镜像里不一定带 `redhat.rhel_system_roles`；如果题目要求用 navigator 跑，确认 EE 里有该 collection（`ansible-navigator collections`），或把 collection 装进项目目录的 `collections/`。
- **storage role 很「强势」**：会按变量描述重建卷，`disks` 写错会毁掉数据，实验时先做快照。
- 运行时间较长（尤其第一次会安装依赖包），耐心等待，不要中途 Ctrl+C。

## 5. 动手练习

- [practice-set-1 · E12 节](../../labs/rhce/practice-set-1.md#e12)

## 6. 官方文档（本仓库离线版 + 考场可用的查法）

- 离线（上游 README，变量与 RHEL 版一致）：
  - [timesync-README.md](../../references/rhce/rhel-system-roles-upstream/timesync-README.md)
  - [selinux-README.md](../../references/rhce/rhel-system-roles-upstream/selinux-README.md)（`selinux_reboot_required` 说明）
  - [firewall-README.md](../../references/rhce/rhel-system-roles-upstream/firewall-README.md)
  - [storage-README.md](../../references/rhce/rhel-system-roles-upstream/storage-README.md)
  - [network-README.md](../../references/rhce/rhel-system-roles-upstream/network-README.md)
  - [crypto_policies-README.md](../../references/rhce/rhel-system-roles-upstream/crypto_policies-README.md)
  - RHEL 10 官方手册《Automating system administration by using RHEL system roles》：本机运行 [`scripts/fetch-rhel-docs.sh`](../../scripts/fetch-rhel-docs.sh) 下载到 `references/rhel/10/`
- 考场：
  - `ls /usr/share/doc/rhel-system-roles/`，`less /usr/share/doc/rhel-system-roles/selinux/README.md`
  - `ansible-doc -t role -l`（列出可见的 role，较新 ansible-core 支持）、`ansible-doc -t role redhat.rhel_system_roles.timesync`（以实际版本为准）
  - `rpm -ql rhel-system-roles | grep example`

## 7. 自测清单

- [ ] 能说出 role 形式与 collection 形式的路径与引用名
- [ ] 能在 5 分钟内用 timesync role 配置 NTP 服务器
- [ ] 能用 selinux role 设置布尔值、文件上下文、端口，并理解 reboot 的 `block/rescue`
- [ ] 能用 storage role 一次完成 VG/LV/文件系统/挂载
- [ ] 知道去 `/usr/share/doc/rhel-system-roles/` 找示例
