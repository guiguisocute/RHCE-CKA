# RHCE 原创模拟考（18 题 · 240 分钟 · 300 分）

> ⚠️ **声明**：本套题为本仓库**原创**，仿照 EX294 的题型和难度编写，**不是真题，也不包含任何真题内容**。
> 红帽考试规则禁止泄露考题，请勿在本仓库中添加回忆版真题。
>
> **环境**：[00-lab-setup.md](00-lab-setup.md)，考前回滚到 `rhce-base` 快照。
> **规则**：计时 240 分钟；只允许使用本机文档（`ansible-doc`、`ansible-navigator doc`、`man`、`/usr/share/doc`）；**不许上网、不许看本仓库笔记**。
> **及格线**：参考 EX294 常见标准 210/300（70%），以官方为准。

## 考试环境说明（题面）

- 你以 `student` 用户登录 `control.lab.example.com`，所有工作放在 `/home/student/ansible/`。
- 受管节点：`node1` ~ `node4`（域名 `lab.example.com`），用户 `automation` 已配置 SSH 免密与 sudo 免密。
- 软件仓库：`http://control.lab.example.com/rhel/BaseOS`、`http://control.lab.example.com/rhel/AppStream`。
- 素材：`http://control.lab.example.com/materials/`（含 collection 与 role 的 tar 包）。
- 除非另有说明，所有 playbook 都必须能用 `ansible-navigator run -m stdout`（或 `ansible-playbook`）在 `/home/student/ansible/` 下运行，且**可重复运行**。

---

### 第 1 题 · 控制节点（15 分）
在 control 上安装 ansible-core 与 ansible-navigator（如未安装），然后：
- 创建静态 inventory `/home/student/ansible/inventory`：node1 属于 `dev`；node2 属于 `test`；node3、node4 属于 `prod`；`prod` 是 `webservers` 的成员。
- 创建 `/home/student/ansible/ansible.cfg`：使用上述 inventory；角色路径为 `/home/student/ansible/roles`；collection 路径为 `/home/student/ansible/collections`；以 `automation` 登录，默认通过 sudo 提权为 root。

### 第 2 题 · Ad-hoc 配置仓库（15 分）
创建可执行脚本 `/home/student/ansible/repos.sh`，使用 **ad-hoc 命令**在所有受管节点配置 `BaseOS` 和 `AppStream` 两个仓库（描述分别为 `Lab BaseOS`、`Lab AppStream`），启用 GPG 校验，密钥为 `file:///etc/pki/rpm-gpg/RPM-GPG-KEY-redhat-release`。

### 第 3 题 · 安装 collection（10 分）
从素材服务器安装 `ansible.posix` 与 `community.general` 到 `/home/student/ansible/collections`，安装清单保存为 `/home/student/ansible/collections/requirements.yml`。

### 第 4 题 · 安装 role（10 分）
创建 `/home/student/ansible/roles/requirements.yml`，从素材服务器的 `webinfo.tar.gz` 安装 role，命名为 `infopage`，安装到 `/home/student/ansible/roles`。

### 第 5 题 · 安装软件包（15 分）
创建 `/home/student/ansible/packages.yml`：
- `dev` 与 `test` 组安装 `php`、`mariadb`；
- `prod` 组安装 `RPM Development Tools` 包组；
- `dev` 组所有软件包更新到最新。

### 第 6 题 · 编写 role（20 分）
在 `/home/student/ansible/roles` 中创建 role `portal`：
- 安装并开机启动 `httpd`、`firewalld`，防火墙永久且立即放行 http；
- 用模板生成 `/var/www/html/index.html`，内容为一行：`Portal on <FQDN> at <默认IPv4>`；
- 模板变化时重启 httpd。

创建 `/home/student/ansible/portal.yml`，在 `webservers` 组使用该 role。

### 第 7 题 · 使用安装的 role（10 分）
创建 `/home/student/ansible/info.yml`：对 `test` 组使用第 4 题安装的 `infopage` role。

### 第 8 题 · System Role：时间同步（15 分）
安装 `rhel-system-roles`，创建 `/home/student/ansible/timesync.yml`，在所有节点用 timesync role 以 `control.lab.example.com` 为 NTP 服务器并启用 iburst。

### 第 9 题 · System Role：SELinux（15 分）
创建 `/home/student/ansible/selinux.yml`：在 `prod` 组保持 SELinux 为 enforcing（targeted），持久开启布尔值 `httpd_can_network_connect`，并允许 httpd 监听 TCP 8090（SELinux 端口类型 `http_port_t`）。

### 第 10 题 · LVM 与错误处理（20 分）
创建 `/home/student/ansible/lv.yml`，在所有节点：
- 如果卷组 `vg_exam` 不存在，输出 `vg_exam not found` 并继续处理其他主机；
- 如果存在，创建 LV `lv_app`，大小 1000 MiB；空间不足时输出 `insufficient space` 并改为 500 MiB；
- LV 格式化为 xfs（不需要挂载）。

> 出题准备（考生开考前自行完成，不计时）：在 node1、node4 上用 vdb 创建 `vg_exam`（node4 的 vdb 只有 1G）；node2、node3 不创建。

### 第 11 题 · 分区（15 分）
创建 `/home/student/ansible/part.yml`，在 `test` 组：
- 如果存在磁盘 `vdb`，创建 600 MiB 主分区 1，格式化为 ext4，持久挂载到 `/exam-data`；
- 如果不存在，输出 `disk vdb does not exist`。

### 第 12 题 · 生成 hosts 文件（20 分）
下载或自行编写模板 `/home/student/ansible/hosts.j2`，创建 `/home/student/ansible/hosts.yml`，在 `dev` 组生成 `/etc/exam-hosts`：每行格式为 `IP FQDN 短主机名`，覆盖 inventory 中**全部**主机，文件属主 root、权限 0644。

### 第 13 题 · 按组修改文件内容（15 分）
创建 `/home/student/ansible/issue.yml`，在所有节点设置 `/etc/issue` 的内容：`dev` → `Dev`，`test` → `Test`，`prod` → `Prod`。

### 第 14 题 · Web 目录（20 分）
创建 `/home/student/ansible/webdir.yml`，在 `dev` 组：
- 创建组 `webdev`；创建目录 `/webdev`，属组 `webdev`，权限 `rwxrwsr-x`（含 setgid）；
- 创建软链接 `/var/www/html/webdev` → `/webdev`；
- `/webdev/index.html` 内容 `Development`；SELinux 上下文允许 httpd 读取；
- httpd 已安装、运行并开机自启，防火墙放行 http。

### 第 15 题 · 硬件报告（20 分）
创建 `/home/student/ansible/hwreport.yml`，在所有节点生成 `/root/hwreport.txt`：

```text
HOST=<inventory 主机名>
MEMORY=<总内存 MB>
BIOS=<BIOS 版本>
VDA=<vda 大小>
VDB=<vdb 大小；不存在写 NONE>
```

### 第 16 题 · Vault（15 分）
- 创建 `/home/student/ansible/vault.txt`，内容为 `ExamVault2026`；
- 创建 vault 加密文件 `/home/student/ansible/passwords.yml`，包含 `pw_ops: Ops!2026` 与 `pw_qa: Qa!2026`。

### 第 17 题 · 批量创建用户（25 分）
已知 `/home/student/ansible/user_list.yml`（自行创建）：

```yaml
users:
  - name: olivia
    job: ops
    uid: 4101
  - name: quinn
    job: qa
    uid: 4102
  - name: owen
    job: ops
    uid: 4103
```

创建 `/home/student/ansible/users.yml`：
- `job: ops` 的用户在 `dev`、`test` 组创建，附加组 `opsteam`，密码使用 `pw_ops`；
- `job: qa` 的用户在 `prod` 组创建，附加组 `qateam`，密码使用 `pw_qa`；
- 密码 SHA512 哈希；附加组不存在时需创建；不得修改已存在用户的密码；
- 运行时使用第 16 题的密码文件。

### 第 18 题 · Rekey 与计划任务（15 分）
- 把 `/home/student/ansible/passwords.yml` 的 vault 密码改为 `ExamVault2027`（同时更新 `vault.txt`）；
- 创建 `/home/student/ansible/cron.yml`：在所有节点为用户 `olivia`（不存在的主机跳过）添加 cron，每 5 分钟执行 `logger "exam heartbeat"`。

---

## 评分自查表

考完后先**重启所有受管节点**（检查持久化），再在 control 上逐项自查：

| 题 | 分 | 自查命令（全部在 `/home/student/ansible` 下执行） | 得分 |
|---|---|---|---|
| 1 | 15 | `ansible-config dump --only-changed`；`ansible-inventory --graph`；`ansible all -a id` 显示 root | |
| 2 | 15 | `ansible all -a 'dnf repolist'` 显示两个仓库；`bash repos.sh` 可重复执行无报错 | |
| 3 | 10 | `ansible-doc -l ansible.posix \| head`；`ls collections/ansible_collections` | |
| 4 | 10 | `ansible-galaxy role list -p roles` 含 infopage | |
| 5 | 15 | `ansible dev -a 'rpm -q php mariadb'`；`ansible prod -a 'dnf group list --installed'` | |
| 6 | 20 | `curl node3.lab.example.com` 返回正确一行；第二次运行 `changed=0` | |
| 7 | 10 | `ansible-navigator run info.yml -m stdout` 成功 | |
| 8 | 15 | `ansible all -a 'chronyc sources'` 含 control | |
| 9 | 15 | `ansible prod -a 'getsebool httpd_can_network_connect'`；`ansible prod -a 'semanage port -l'` 中 http_port_t 含 8090 | |
| 10 | 20 | node2/3 输出 not found；node1 `lvs` 有 1000m；node4 有 500m；`blkid` 为 xfs | |
| 11 | 15 | `ansible test -a 'findmnt /exam-data'`；重启后仍挂载 | |
| 12 | 20 | `ansible dev -a 'cat /etc/exam-hosts'` 有 4 行且 IP 正确 | |
| 13 | 15 | `ansible all -a 'cat /etc/issue'` | |
| 14 | 20 | `ls -ld /webdev`；`ls -Zd /webdev`；`curl node1.lab.example.com/webdev/` 返回 Development | |
| 15 | 20 | `ansible all -a 'cat /root/hwreport.txt'`，node3 的 VDB=NONE | |
| 16 | 15 | `head -1 passwords.yml` 为 `$ANSIBLE_VAULT`；`ansible-vault view passwords.yml --vault-password-file vault.txt` | |
| 17 | 25 | `ansible dev,test -a 'id olivia'`；`ansible prod -a 'id quinn'`；用密码 SSH 登录测试；再次运行 `changed=0` | |
| 18 | 15 | 新密码可 view、旧密码不可；`ansible all -a 'crontab -l -u olivia'`（node3/4 无此用户应跳过而非报错） | |
| **合计** | **300** | | |

## 复盘方法

1. 丢分的题，回到对应笔记节点：第 1 题 → [E2](../../notes/rhce/02-inventory-and-config.md)；第 2 题 → [E3](../../notes/rhce/03-adhoc-modules-docs.md)；第 3、7 题 → [E9](../../notes/rhce/09-collections-navigator.md)；第 4、6 题 → [E8](../../notes/rhce/08-roles.md)；第 8、9 题 → [E12](../../notes/rhce/12-rhel-system-roles.md)；第 10、11 题 → [E6](../../notes/rhce/06-loops-conditions-errors.md) + [E11](../../notes/rhce/11-automate-rhcsa-tasks.md)；第 12、15 题 → [E7](../../notes/rhce/07-jinja2-templates.md)；第 16~18 题 → [E10](../../notes/rhce/10-vault.md)。
2. 把错误写进学习日志的错题本（见仓库根目录 `journal/`）。
3. 记录每题用时，超过 15 分钟的题型重点刷 [分节练习](practice-set-1.md)。
4. 两次模拟考都 ≥ 240 分再预约正式考试。

## 参考解答要点（考完再看）

<details><summary>展开</summary>

- **第 1 题**：见 [E2 笔记](../../notes/rhce/02-inventory-and-config.md) 的 ansible.cfg 模板；`[webservers:children]` 下写 `prod`。
- **第 2 题**：`ansible all -m ansible.builtin.yum_repository -a "name=BaseOS description='Lab BaseOS' baseurl=... gpgcheck=yes gpgkey=... enabled=yes"`，AppStream 同理；`chmod +x repos.sh`。
- **第 6 题**：见 [E8 笔记](../../notes/rhce/08-roles.md) 的 apache 示例。
- **第 9 题**：selinux role 的 `selinux_booleans` + `selinux_ports`，见 [E12 笔记](../../notes/rhce/12-rhel-system-roles.md)。
- **第 10 题**：先用 `when: "'vg_exam' in ansible_facts['lvm']['vgs']"`（受管节点需安装 lvm2 才有 `lvm` fact）判断，再 `block/rescue`，见 [E6 笔记](../../notes/rhce/06-loops-conditions-errors.md)。
- **第 12 题**：第一个 play `hosts: all` 收集 facts，第二个 play 对 dev 渲染模板，见 [E7 笔记](../../notes/rhce/07-jinja2-templates.md)。
- **第 14 题**：`file` 模块 `mode: "2775"`、`state: link`；`sefcontext` + `restorecon`；注意软链接本身不需要改上下文，目标目录需要。
- **第 17 题**：两个 play（或一个 play + `when` 组合 `item.job` 与 `group_names`）；`groups` + `append: true`；`password: "{{ pw_ops | password_hash('sha512') }}"` + `update_password: on_create`；`vars_files` 同时包含 `user_list.yml` 与 `passwords.yml`。
- **第 18 题**：`ansible-vault rekey passwords.yml --vault-password-file vault.txt --new-vault-password-file new.txt`，再把新密码写回 `vault.txt`；cron task 前先用 `ansible.builtin.command: id olivia` + `register` + `failed_when: false` + `changed_when: false` 判断用户是否存在（`rc == 0` 才添加）；也可以用 `ansible.builtin.getent`，参数以 `ansible-doc` 为准。

</details>
