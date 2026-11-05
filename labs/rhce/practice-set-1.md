# RHCE 分节练习（36 题）

> **环境**：[00-lab-setup.md](00-lab-setup.md)（control + node1~node4，项目目录 `~/ansible`）
> **笔记**：[RHCE 轨道](../../notes/rhce/README.md)
> **说明**：全部为**原创练习题**，按知识节点 E1~E12 分节。先独立完成，再展开参考答案。每题做完都要**再运行一次确认 `changed=0`**。
> 做完一节后回滚快照或手工清理，避免互相影响。

---

<a id="e1"></a>
## E1 Ansible 架构与安装 → [笔记](../../notes/rhce/01-ansible-architecture.md)

### E1-1 确认运行环境
**任务**：在 control 上找出：当前 ansible-core 版本、生效的配置文件路径、collection 搜索路径、Python 版本。
**验证**：能口述四项结果。

<details><summary>参考答案</summary>

```bash
cd ~/ansible && ansible --version
```
</details>

### E1-2 dry-run 与幂等
**任务**：写 `~/ansible/motd.yml`，把 `/etc/motd` 内容设为 `Managed by Ansible`。先用 check+diff 模式运行，再正式运行两次，观察 `changed` 的变化。
**验证**：第二次正式运行 `changed=0`。

<details><summary>参考答案</summary>

```yaml
---
- name: Manage motd
  hosts: all
  tasks:
    - name: Set motd
      ansible.builtin.copy:
        content: "Managed by Ansible\n"
        dest: /etc/motd
        mode: "0644"
```

```bash
ansible-playbook motd.yml -C -D
ansible-playbook motd.yml && ansible-playbook motd.yml
```
</details>

---

<a id="e2"></a>
## E2 Inventory 与 ansible.cfg → [笔记](../../notes/rhce/02-inventory-and-config.md)

### E2-1 从零写 inventory
**任务**：删除 `~/ansible/inventory` 后重写：`dev`=node1，`test`=node2，`prod`=node3、node4；组 `webservers` 包含 `prod` 组；组 `lab` 包含 `dev` 和 `test`。
**验证**：`ansible-inventory --graph` 显示正确树形；`ansible webservers --list-hosts` 输出 2 台。

<details><summary>参考答案</summary>

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

[lab:children]
dev
test
```
</details>

### E2-2 ansible.cfg 自检
**任务**：故意在 `/tmp` 下执行 `ansible all -m ping`，观察失败原因；然后用一条命令列出 `~/ansible/ansible.cfg` 中所有与默认值不同的设置。
**验证**：输出包含 `DEFAULT_HOST_LIST`、`DEFAULT_REMOTE_USER`、`DEFAULT_BECOME`。

<details><summary>参考答案</summary>

```bash
cd /tmp && ansible all -m ansible.builtin.ping       # 读到 /etc/ansible/ansible.cfg 或无 inventory
cd ~/ansible && ansible-config dump --only-changed
```
</details>

### E2-3 group_vars 与 host_vars
**任务**：为 `prod` 组定义变量 `http_port: 8080`，为 node1 定义 `http_port: 9090`，用 ad-hoc 的 `debug` 模块打印所有主机的 `http_port`（未定义的显示 `unset`）。
**验证**：node1 显示 9090，node3/node4 显示 8080，node2 显示 unset。

<details><summary>参考答案</summary>

```bash
mkdir -p group_vars host_vars
echo 'http_port: 8080' > group_vars/prod.yml
echo 'http_port: 9090' > host_vars/node1.lab.example.com.yml
ansible all -m ansible.builtin.debug -a "msg={{ http_port | default('unset') }}"
```
</details>

---

<a id="e3"></a>
## E3 Ad-hoc、模块与 ansible-doc → [笔记](../../notes/rhce/03-adhoc-modules-docs.md)

### E3-1 用 ad-hoc 配置 yum 仓库
**任务**：写一个 shell 脚本 `~/ansible/adhoc-repo.sh`，里面用 **ad-hoc 命令**（不是 playbook）在所有节点配置两个仓库：`BaseOS` → `http://control.lab.example.com/rhel/BaseOS`，`AppStream` → `http://control.lab.example.com/rhel/AppStream`，启用 gpgcheck，gpgkey 为 `file:///etc/pki/rpm-gpg/RPM-GPG-KEY-redhat-release`。
**验证**：`ansible all -a 'dnf repolist'` 看到两个仓库。

<details><summary>参考答案</summary>

```bash
#!/bin/bash
for r in BaseOS AppStream; do
  ansible all -m ansible.builtin.yum_repository -a \
    "name=$r description='Local $r' baseurl=http://control.lab.example.com/rhel/$r gpgcheck=yes gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-redhat-release enabled=yes"
done
```
</details>

### E3-2 文档检索竞速
**任务**：只用 `ansible-doc`，在 3 分钟内分别找到：①设置 SELinux 端口类型的模块；②管理 at 任务的模块；③它们的必填参数。
**验证**：写出模块 FQCN 和必填参数。

<details><summary>参考答案</summary>

```bash
ansible-doc -l | grep -i -E 'seport|\bat\b'
ansible-doc -s community.general.seport     # 必填：ports、proto、setype（以实际输出为准）
ansible-doc -s ansible.posix.at              # 需要 command 或 script_file 之一，以及 count/units
```
</details>

### E3-3 ad-hoc 验证技巧
**任务**：用 ad-hoc 命令一次性列出所有节点的：内核版本、默认 IPv4 地址、SELinux 状态。
**验证**：每台主机三项信息。

<details><summary>参考答案</summary>

```bash
ansible all -a 'uname -r'
ansible all -m ansible.builtin.setup -a 'filter=ansible_default_ipv4'
ansible all -a 'getenforce'
```
</details>

---

<a id="e4"></a>
## E4 Playbook 基础 → [笔记](../../notes/rhce/04-playbooks.md)

### E4-1 两个 play
**任务**：`~/ansible/packages.yml`：在 `dev` 和 `test` 上安装 `php` 和 `mariadb`；在 `prod` 上安装包组 `RPM Development Tools`，并把所有包更新到最新。
**验证**：`ansible dev -a 'rpm -q php mariadb'`。

<details><summary>参考答案</summary>

```yaml
---
- name: Packages for dev and test
  hosts: dev,test
  tasks:
    - name: Install php and mariadb
      ansible.builtin.dnf:
        name: [php, mariadb]
        state: present

- name: Packages for prod
  hosts: prod
  tasks:
    - name: Install development group
      ansible.builtin.dnf:
        name: "@RPM Development Tools"
        state: present
    - name: Update all packages
      ansible.builtin.dnf:
        name: "*"
        state: latest
```
</details>

### E4-2 handler
**任务**：在 `test` 上安装 httpd，设置 `/etc/httpd/conf.d/lab.conf` 内容为 `ServerName node2.lab.example.com`；只有该文件变化时才重启 httpd；httpd 开机自启。
**验证**：修改文件内容再运行，观察 handler 被触发；不改时 handler 不触发。

<details><summary>参考答案</summary>

```yaml
---
- name: httpd with handler
  hosts: test
  tasks:
    - name: Install httpd
      ansible.builtin.dnf:
        name: httpd
        state: present
    - name: Deploy lab.conf
      ansible.builtin.copy:
        content: "ServerName node2.lab.example.com\n"
        dest: /etc/httpd/conf.d/lab.conf
        mode: "0644"
      notify: Restart httpd
    - name: Enable httpd
      ansible.builtin.service:
        name: httpd
        state: started
        enabled: true
  handlers:
    - name: Restart httpd
      ansible.builtin.service:
        name: httpd
        state: restarted
```
</details>

### E4-3 lineinfile + validate
**任务**：在所有节点的 `/etc/ssh/sshd_config` 中确保 `MaxAuthTries 3`，修改前用 `sshd -t` 校验，修改后 reload sshd。
**验证**：`ansible all -a 'grep ^MaxAuthTries /etc/ssh/sshd_config'`。

<details><summary>参考答案</summary>

```yaml
---
- name: Harden sshd
  hosts: all
  tasks:
    - name: Set MaxAuthTries
      ansible.builtin.lineinfile:
        path: /etc/ssh/sshd_config
        regexp: '^#?MaxAuthTries'
        line: MaxAuthTries 3
        validate: /usr/sbin/sshd -t -f %s
      notify: Reload sshd
  handlers:
    - name: Reload sshd
      ansible.builtin.service:
        name: sshd
        state: reloaded
```
</details>

---

<a id="e5"></a>
## E5 变量与 facts → [笔记](../../notes/rhce/05-variables-facts.md)

### E5-1 register
**任务**：在所有节点运行 `uptime -p`，把结果存入变量并用 debug 打印 `<主机名>: <uptime>`；这个 task 不能报 changed。
**验证**：输出 4 行且 `changed=0`。

<details><summary>参考答案</summary>

```yaml
---
- name: Uptime
  hosts: all
  gather_facts: false
  tasks:
    - name: Run uptime
      ansible.builtin.command: uptime -p
      register: up
      changed_when: false
    - name: Show
      ansible.builtin.debug:
        msg: "{{ inventory_hostname }}: {{ up.stdout }}"
```
</details>

### E5-2 local facts
**任务**：在 `dev` 节点创建自定义 fact 文件，使 `ansible_local.lab.info.owner` 的值为 `student`，`role` 为 `devbox`；随后在同一 playbook 中打印它（提示：写完 fact 后需要重新收集）。
**验证**：debug 输出 `student devbox`。

<details><summary>参考答案</summary>

```yaml
---
- name: Local facts
  hosts: dev
  tasks:
    - name: Ensure facts.d exists
      ansible.builtin.file:
        path: /etc/ansible/facts.d
        state: directory
        mode: "0755"
    - name: Write fact file
      ansible.builtin.copy:
        dest: /etc/ansible/facts.d/lab.fact
        content: |
          [info]
          owner=student
          role=devbox
        mode: "0644"
    - name: Re-gather local facts
      ansible.builtin.setup:
        filter: ansible_local
    - name: Show
      ansible.builtin.debug:
        msg: "{{ ansible_local['lab']['info']['owner'] }} {{ ansible_local['lab']['info']['role'] }}"
```
</details>

### E5-3 读取其他主机的 facts
**任务**：在 node1 上生成 `/root/prod-ips.txt`，每行是一台 prod 主机的默认 IPv4 地址。
**验证**：`ansible dev -a 'cat /root/prod-ips.txt'` 显示 node3、node4 的 IP。

<details><summary>参考答案</summary>

```yaml
---
- name: Gather prod facts
  hosts: prod
  tasks: []

- name: Write prod IPs on dev
  hosts: dev
  tasks:
    - name: Write file
      ansible.builtin.copy:
        dest: /root/prod-ips.txt
        content: |
          {% for h in groups['prod'] %}
          {{ hostvars[h]['ansible_facts']['default_ipv4']['address'] }}
          {% endfor %}
        mode: "0644"
```
</details>

---

<a id="e6"></a>
## E6 循环、条件、handler 与错误处理 → [笔记](../../notes/rhce/06-loops-conditions-errors.md)

### E6-1 字典列表 loop
**任务**：变量文件 `~/ansible/vars/staff.yml` 中有：

```yaml
staff:
  - { name: amy,  dept: dev, uid: 3001 }
  - { name: ben,  dept: ops, uid: 3002 }
  - { name: cara, dept: dev, uid: 3003 }
```

在所有节点创建这些用户，附加组为各自 `dept`（组需先创建）。
**验证**：`ansible all -a 'id cara'` 显示 uid 3003 且在 dev 组。

<details><summary>参考答案</summary>

```yaml
---
- name: Staff users
  hosts: all
  vars_files:
    - vars/staff.yml
  tasks:
    - name: Create groups
      ansible.builtin.group:
        name: "{{ item }}"
        state: present
      loop: "{{ staff | map(attribute='dept') | unique | list }}"
    - name: Create users
      ansible.builtin.user:
        name: "{{ item.name }}"
        uid: "{{ item.uid }}"
        groups: "{{ item.dept }}"
        append: true
      loop: "{{ staff }}"
      loop_control:
        label: "{{ item.name }}"
```
</details>

### E6-2 按组条件执行
**任务**：同上题，但 `dept: dev` 的用户只在 `dev` 和 `test` 组主机上创建，`dept: ops` 的用户只在 `prod` 上创建。
**验证**：node3 上没有 amy，有 ben。

<details><summary>参考答案</summary>

```yaml
    - name: Create dev users on dev/test
      ansible.builtin.user:
        name: "{{ item.name }}"
        uid: "{{ item.uid }}"
        groups: "{{ item.dept }}"
        append: true
      loop: "{{ staff }}"
      when:
        - item.dept == 'dev'
        - "'dev' in group_names or 'test' in group_names"

    - name: Create ops users on prod
      ansible.builtin.user:
        name: "{{ item.name }}"
        uid: "{{ item.uid }}"
        groups: "{{ item.dept }}"
        append: true
      loop: "{{ staff }}"
      when:
        - item.dept == 'ops'
        - "'prod' in group_names"
```
（组的创建 task 保持在前面）
</details>

### E6-3 block/rescue 降级
**任务**：在所有节点的 vdb 上：若 vdb 不存在，打印 `vdb missing` 并继续；若存在，创建 VG `vg_lab` 和 1200 MiB 的 LV `lv_try`；空间不够时打印 `not enough space` 并改建 600 MiB。
**验证**：node3 打印 missing；node4（vdb 1G）打印 not enough space 且 LV 为 600M；node1/node2 为 1.17g 左右。

<details><summary>参考答案</summary>

```yaml
---
- name: LV with fallback
  hosts: all
  tasks:
    - name: Report missing disk
      ansible.builtin.debug:
        msg: vdb missing
      when: "'vdb' not in ansible_facts['devices']"

    - name: Build LVM when disk exists
      when: "'vdb' in ansible_facts['devices']"
      block:
        - name: Create VG
          community.general.lvg:
            vg: vg_lab
            pvs: /dev/vdb
        - name: Try 1200M
          block:
            - name: Create 1200M LV
              community.general.lvol:
                vg: vg_lab
                lv: lv_try
                size: 1200m
          rescue:
            - name: Report
              ansible.builtin.debug:
                msg: not enough space
            - name: Create 600M LV
              community.general.lvol:
                vg: vg_lab
                lv: lv_try
                size: 600m
```
</details>

### E6-4 shell 脚本改写
**任务**：把下面脚本改写为幂等的 playbook `~/ansible/convert.yml`，作用于 `test` 组：

```bash
#!/bin/bash
mkdir -p /opt/reports
grep -q '^report:' /etc/group || groupadd report
chgrp report /opt/reports && chmod 2775 /opt/reports
echo "0 2 * * * root /usr/bin/du -sh /home > /opt/reports/home.txt" > /etc/cron.d/home-report
systemctl is-active crond || systemctl start crond
```
**验证**：再次运行 `changed=0`；`ls -ld /opt/reports` 为 `drwxrwsr-x root report`。

<details><summary>参考答案</summary>

```yaml
---
- name: Converted script
  hosts: test
  tasks:
    - name: Group report
      ansible.builtin.group:
        name: report
    - name: Reports dir with setgid
      ansible.builtin.file:
        path: /opt/reports
        state: directory
        group: report
        mode: "2775"
    - name: Cron file
      ansible.builtin.cron:
        name: home report
        cron_file: home-report
        user: root
        minute: "0"
        hour: "2"
        job: /usr/bin/du -sh /home > /opt/reports/home.txt
    - name: crond running
      ansible.builtin.service:
        name: crond
        state: started
        enabled: true
```
</details>

---

<a id="e7"></a>
## E7 Jinja2 模板 → [笔记](../../notes/rhce/07-jinja2-templates.md)

### E7-1 全量 hosts 文件
**任务**：用模板在 `dev` 组主机生成 `/etc/lab-hosts`，格式与 `/etc/hosts` 相同，包含 inventory 中**所有主机**的 `IP FQDN 短名`。
**验证**：`ansible dev -a 'cat /etc/lab-hosts'` 有 4 行主机记录。

<details><summary>参考答案</summary>

见 [E7 笔记](../../notes/rhce/07-jinja2-templates.md) 「生成所有主机的 hosts 文件」一节。关键点：先对 `all` 收集 facts，再对 `dev` 渲染模板。
</details>

### E7-2 硬件报告
**任务**：在所有节点生成 `/root/hw.txt`：

```text
HOST=<inventory_hostname>
MEM_MB=<总内存>
VDB=<vdb 大小，没有则 NONE>
DISTRO=<发行版 + 版本>
```
**验证**：node3 的 VDB 为 NONE。

<details><summary>参考答案</summary>

`templates/hw.j2`：

```jinja
HOST={{ inventory_hostname }}
MEM_MB={{ ansible_facts['memtotal_mb'] }}
VDB={{ ansible_facts['devices']['vdb']['size'] if 'vdb' in ansible_facts['devices'] else 'NONE' }}
DISTRO={{ ansible_facts['distribution'] }} {{ ansible_facts['distribution_version'] }}
```

```yaml
---
- name: Hardware report
  hosts: all
  tasks:
    - name: Render
      ansible.builtin.template:
        src: templates/hw.j2
        dest: /root/hw.txt
        mode: "0644"
```
</details>

### E7-3 按组输出不同内容
**任务**：在所有节点生成 `/etc/issue`：dev 组写 `Development box`，test 写 `Test box`，其余写 `Production - authorized use only`。要求一个模板完成。
**验证**：三类主机内容不同。

<details><summary>参考答案</summary>

```jinja
{% if 'dev' in group_names %}
Development box
{% elif 'test' in group_names %}
Test box
{% else %}
Production - authorized use only
{% endif %}
```
</details>

---

<a id="e8"></a>
## E8 Roles → [笔记](../../notes/rhce/08-roles.md)

### E8-1 写一个 web role
**任务**：在 `~/ansible/roles` 下创建 role `webpage`：安装并启动 httpd、firewalld 放行 http、用模板生成 `/var/www/html/index.html`，内容为 `Hello from <FQDN> (<IP>)`。写 `~/ansible/webpage.yml` 对 `webservers` 使用此 role。
**验证**：`curl http://node3.lab.example.com` 返回正确内容。

<details><summary>参考答案</summary>

参考 [E8 笔记](../../notes/rhce/08-roles.md) 的 apache 示例，把 role 名换成 `webpage`；`roles/webpage/templates/index.html.j2`：

```jinja
Hello from {{ ansible_facts['fqdn'] }} ({{ ansible_facts['default_ipv4']['address'] }})
```
</details>

### E8-2 从素材服务器安装 role
**任务**：使用 `~/ansible/roles/requirements.yml`，从 `http://control.lab.example.com/materials/webinfo.tar.gz` 安装 role，命名为 `infopage`，装到 `~/ansible/roles`。
**验证**：`ansible-galaxy role list -p ~/ansible/roles` 中有 `infopage`。

<details><summary>参考答案</summary>

```yaml
---
- src: http://control.lab.example.com/materials/webinfo.tar.gz
  name: infopage
```

```bash
ansible-galaxy role install -r roles/requirements.yml -p roles/
```
</details>

### E8-3 带默认值的 role
**任务**：给 `webpage` role 增加变量 `web_message`，默认值 `Hello`（放在 defaults），模板使用它；在 playbook 中为 node4 覆盖为 `Hi from node4`（用 host_vars）。
**验证**：node3 与 node4 首页内容不同。

<details><summary>参考答案</summary>

```bash
echo 'web_message: Hello' > roles/webpage/defaults/main.yml
echo 'web_message: Hi from node4' > host_vars/node4.lab.example.com.yml
# 模板改为：{{ web_message }} from {{ ansible_facts['fqdn'] }}
```
（host_vars 优先级高于 role defaults）
</details>

---

<a id="e9"></a>
## E9 Collections 与 ansible-navigator → [笔记](../../notes/rhce/09-collections-navigator.md)

### E9-1 从 tar 包安装 collection 到项目
**任务**：用 `~/ansible/collections/requirements.yml`，从素材服务器的 tar 包安装 `ansible.posix` 和 `community.general` 到 `~/ansible/collections`。
**验证**：`ansible-doc -l ansible.posix | head` 有输出；`ls ~/ansible/collections/ansible_collections/`。

<details><summary>参考答案</summary>

```yaml
---
collections:
  - name: http://control.lab.example.com/materials/ansible-posix-<版本>.tar.gz
    type: url
  - name: http://control.lab.example.com/materials/community-general-<版本>.tar.gz
    type: url
```

```bash
ansible-galaxy collection install -r collections/requirements.yml -p collections/
```
</details>

### E9-2 用 navigator 运行和查文档
**任务**：用 ansible-navigator（stdout 模式）运行 E8-1 的 `webpage.yml`；再用 navigator 查 `ansible.posix.firewalld` 的 EXAMPLES。
**验证**：运行结果与 ansible-playbook 一致。

<details><summary>参考答案</summary>

```bash
ansible-navigator run webpage.yml -m stdout          # 没有 EE 镜像时加 --ee false
ansible-navigator doc ansible.posix.firewalld -m stdout | less
```
</details>

### E9-3 navigator 查看 inventory 与配置
**任务**：用 navigator 输出 inventory 的全部主机变量；用 navigator 的交互模式查看当前生效的 ansible 配置。
**验证**：能找到 `DEFAULT_REMOTE_USER`。

<details><summary>参考答案</summary>

```bash
ansible-navigator inventory --list -m stdout
ansible-navigator config        # TUI 中输入 :f REMOTE_USER 过滤（或翻页查找）
```
</details>

---

<a id="e10"></a>
## E10 Ansible Vault → [笔记](../../notes/rhce/10-vault.md)

### E10-1 加密变量文件
**任务**：创建 `~/ansible/vault-pass.txt`（内容 `LabVault!`，权限 600）；创建加密文件 `~/ansible/creds.yml`，含 `dev_pass: Dev#2026` 和 `ops_pass: Ops#2026`。
**验证**：`head -1 creds.yml` 为 `$ANSIBLE_VAULT;1.1;AES256`；`ansible-vault view` 能看到明文。

<details><summary>参考答案</summary>

```bash
echo 'LabVault!' > vault-pass.txt && chmod 600 vault-pass.txt
ansible-vault create creds.yml --vault-password-file vault-pass.txt
ansible-vault view creds.yml --vault-password-file vault-pass.txt
```
</details>

### E10-2 用 vault 变量创建用户
**任务**：`~/ansible/vault-users.yml`：在 dev 上创建用户 `devuser`（密码 `dev_pass`），在 prod 上创建 `opsuser`（密码 `ops_pass`），密码 SHA512 哈希，重复运行不修改密码。再把 vault 密码改为 `NewVault!`。
**验证**：`ssh devuser@node1` 能用 `Dev#2026` 登录；rekey 后旧密码文件不能再解密。

<details><summary>参考答案</summary>

```yaml
---
- name: Dev user
  hosts: dev
  vars_files: [creds.yml]
  tasks:
    - name: devuser
      ansible.builtin.user:
        name: devuser
        password: "{{ dev_pass | password_hash('sha512') }}"
        update_password: on_create
- name: Ops user
  hosts: prod
  vars_files: [creds.yml]
  tasks:
    - name: opsuser
      ansible.builtin.user:
        name: opsuser
        password: "{{ ops_pass | password_hash('sha512') }}"
        update_password: on_create
```

```bash
ansible-playbook vault-users.yml --vault-password-file vault-pass.txt
echo 'NewVault!' > new-pass.txt
ansible-vault rekey creds.yml --vault-password-file vault-pass.txt --new-vault-password-file new-pass.txt
```
</details>

---

<a id="e11"></a>
## E11 用 Ansible 自动化 RHCSA 任务 → [笔记](../../notes/rhce/11-automate-rhcsa-tasks.md)

### E11-1 分区 + 文件系统 + 挂载
**任务**：在 dev、test 的 vdb 上创建 800 MiB 的分区 1，格式化为 ext4，持久挂载到 `/data`；没有 vdb 的主机输出提示。
**验证**：`findmnt /data`；`/etc/fstab` 有记录；重启后仍挂载。

<details><summary>参考答案</summary>

```yaml
---
- name: Partition and mount
  hosts: dev,test
  tasks:
    - name: No disk
      ansible.builtin.debug:
        msg: "{{ inventory_hostname }} has no vdb"
      when: "'vdb' not in ansible_facts['devices']"
    - name: Disk work
      when: "'vdb' in ansible_facts['devices']"
      block:
        - name: Partition
          community.general.parted:
            device: /dev/vdb
            number: 1
            state: present
            part_end: 800MiB
        - name: ext4
          community.general.filesystem:
            dev: /dev/vdb1
            fstype: ext4
        - name: Mount
          ansible.posix.mount:
            path: /data
            src: /dev/vdb1
            fstype: ext4
            state: mounted
```
（与 E6-3 共用 vdb 会冲突，先回滚快照）
</details>

### E11-2 SELinux + 防火墙 + 非标准端口
**任务**：在 test 上让 httpd 在 **82 端口**提供 `/srv/site` 目录的内容（DocumentRoot 改为 `/srv/site`，首页内容 `site ok`），SELinux 保持 enforcing。
**验证**：`curl http://node2.lab.example.com:82` 返回 `site ok`。

<details><summary>参考答案</summary>

```yaml
---
- name: httpd on port 82
  hosts: test
  tasks:
    - name: Packages
      ansible.builtin.dnf:
        name: [httpd, firewalld, policycoreutils-python-utils]
        state: present
    - name: Content dir
      ansible.builtin.file:
        path: /srv/site
        state: directory
        mode: "0755"
    - name: Index
      ansible.builtin.copy:
        content: "site ok\n"
        dest: /srv/site/index.html
        mode: "0644"
    - name: fcontext
      community.general.sefcontext:
        target: '/srv/site(/.*)?'
        setype: httpd_sys_content_t
    - name: restorecon
      ansible.builtin.command: restorecon -Rv /srv/site
      register: rc
      changed_when: rc.stdout | length > 0
    - name: SELinux port 82
      community.general.seport:
        ports: 82
        proto: tcp
        setype: http_port_t
        state: present
    - name: Listen 82
      ansible.builtin.lineinfile:
        path: /etc/httpd/conf/httpd.conf
        regexp: '^Listen '
        line: Listen 82
      notify: Restart httpd
    - name: DocumentRoot
      ansible.builtin.copy:
        dest: /etc/httpd/conf.d/site.conf
        content: |
          DocumentRoot "/srv/site"
          <Directory "/srv/site">
              Require all granted
          </Directory>
        mode: "0644"
      notify: Restart httpd
    - name: Services
      ansible.builtin.service:
        name: "{{ item }}"
        state: started
        enabled: true
      loop: [httpd, firewalld]
    - name: Firewall 82
      ansible.posix.firewalld:
        port: 82/tcp
        permanent: true
        immediate: true
        state: enabled
  handlers:
    - name: Restart httpd
      ansible.builtin.service:
        name: httpd
        state: restarted
```
</details>

### E11-3 计划任务与 at
**任务**：在所有节点为用户 `amy`（E6-1 中创建）添加 cron：每周一 08:30 执行 `logger "weekly check"`；在 dev 上用 at 安排 10 分钟后执行 `touch /tmp/at-done`。
**验证**：`ansible all -a 'crontab -l -u amy'`；`ansible dev -a 'atq'`。

<details><summary>参考答案</summary>

```yaml
---
- name: Scheduling
  hosts: all
  tasks:
    - name: Weekly cron
      ansible.builtin.cron:
        name: weekly check
        user: amy
        weekday: "1"
        hour: "8"
        minute: "30"
        job: logger "weekly check"

- name: at job
  hosts: dev
  tasks:
    - name: Ensure atd
      ansible.builtin.service:
        name: atd
        state: started
        enabled: true
    - name: Schedule
      ansible.posix.at:
        command: touch /tmp/at-done
        count: 10
        units: minutes
        unique: true
```
</details>

### E11-4 swap 与 sysctl
**任务**：在 dev 上：用 vdb 的剩余空间建分区 2（256 MiB）作为 swap，持久启用；设置 `vm.swappiness=10` 持久生效。
**验证**：`swapon --show`；`sysctl vm.swappiness`。

<details><summary>参考答案</summary>

```yaml
---
- name: Swap and sysctl
  hosts: dev
  tasks:
    - name: Partition 2
      community.general.parted:
        device: /dev/vdb
        number: 2
        state: present
        part_start: 800MiB
        part_end: 1056MiB
    - name: mkswap
      community.general.filesystem:
        dev: /dev/vdb2
        fstype: swap
    - name: fstab entry
      ansible.posix.mount:
        path: none
        src: /dev/vdb2
        fstype: swap
        opts: defaults
        state: present
    - name: Activate swap
      ansible.builtin.command: swapon -a
      changed_when: false
    - name: swappiness
      ansible.posix.sysctl:
        name: vm.swappiness
        value: "10"
        sysctl_set: true
        state: present
```
</details>

### E11-5 时区、主机名、默认 target
**任务**：所有节点时区设为 `Asia/Shanghai`；node2 的主机名改为 `test-node2.lab.example.com`（做完记得改回）；prod 组默认启动到 `multi-user.target`。
**验证**：`timedatectl`、`hostnamectl`、`systemctl get-default`。

<details><summary>参考答案</summary>

```yaml
---
- name: Misc
  hosts: all
  tasks:
    - name: Timezone
      community.general.timezone:
        name: Asia/Shanghai
    - name: Hostname
      ansible.builtin.hostname:
        name: test-node2.lab.example.com
      when: inventory_hostname == 'node2.lab.example.com'
    - name: Check default target
      ansible.builtin.command: systemctl get-default
      register: tgt
      changed_when: false
      when: "'prod' in group_names"
    - name: Set default target
      ansible.builtin.command: systemctl set-default multi-user.target
      when:
        - "'prod' in group_names"
        - tgt.stdout != 'multi-user.target'
```
</details>

---

<a id="e12"></a>
## E12 RHEL System Roles → [笔记](../../notes/rhce/12-rhel-system-roles.md)

### E12-1 timesync
**任务**：安装 `rhel-system-roles`，写 `~/ansible/timesync.yml` 用 timesync role 让所有节点使用 `control.lab.example.com` 作为 NTP 服务器（iburst）。control 上先把 chronyd 配置为允许 192.168.122.0/24 同步（`allow` 指令）。
**验证**：`ansible all -a 'chronyc sources'` 显示 control。

<details><summary>参考答案</summary>

```yaml
---
- name: Time sync
  hosts: all
  vars:
    timesync_ntp_servers:
      - hostname: control.lab.example.com
        iburst: true
  roles:
    - redhat.rhel_system_roles.timesync
```
（如果用 role 形式则写 `rhel-system-roles.timesync`，并确认 `roles_path` 含 `/usr/share/ansible/roles`）
</details>

### E12-2 selinux role
**任务**：用 selinux role 在 prod 上：保持 enforcing；开启布尔值 `httpd_can_network_connect`（持久）；为 `/srv/app(/.*)?` 设置 `httpd_sys_content_t` 并 restorecon。
**验证**：`getsebool httpd_can_network_connect`；`ls -Zd /srv/app`（目录需先存在）。

<details><summary>参考答案</summary>

```yaml
---
- name: SELinux role
  hosts: prod
  vars:
    selinux_state: enforcing
    selinux_policy: targeted
    selinux_booleans:
      - name: httpd_can_network_connect
        state: true
        persistent: true
    selinux_fcontexts:
      - target: '/srv/app(/.*)?'
        setype: httpd_sys_content_t
        state: present
    selinux_restore_dirs:
      - /srv/app
  pre_tasks:
    - name: Ensure dir exists
      ansible.builtin.file:
        path: /srv/app
        state: directory
        mode: "0755"
  roles:
    - redhat.rhel_system_roles.selinux
```
</details>

---

全部完成后：回滚快照 → 限时 4 小时做 [模拟考](mock-exam.md)。
