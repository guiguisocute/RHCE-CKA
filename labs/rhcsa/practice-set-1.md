# RHCSA 练习题集 1（按知识点分节）

> **原创练习题**，按 [RHCSA 知识网络](../../notes/rhcsa/README.md) 的 S1~S10 节点分节，不是考试真题。
> 环境：[实验环境搭建](00-lab-setup.md) 中的 servera / serverb。除非特别说明，都在 **servera** 上以 root 完成。
> 做法：先只看「任务」动手 → 用「验证」自查 → 实在卡住再展开「提示」。每节做完**重启一次**再验证全部题目。
> 做错的题记到 [`journal/`](../../journal/) 错题本。

目录：[S1](#s1) · [S2](#s2) · [S3](#s3) · [S4](#s4) · [S5](#s5) · [S6](#s6) · [S7](#s7) · [S8](#s8) · [S9](#s9) · [S10](#s10)

---

<a id="s1"></a>
## S1 基础工具（笔记：[S1](../../notes/rhcsa/01-essential-tools.md)）

**1.1** 找出系统中属于用户 `student` 的所有普通文件，将它们**保持属性**复制到 `/root/student-files/`（目录不存在则创建）。
- 验证：`ls -l /root/student-files/` 中属主仍为 student。
<details><summary>提示</summary>

`mkdir -p /root/student-files && find / -user student -type f -exec cp -a {} /root/student-files/ \; 2>/dev/null`
</details>

**1.2** 把 `/usr/share/dict/words`（不存在则用 `/etc/services`）中所有包含字符串 `ion` 且以 `s` 结尾的行，按原顺序写入 `/root/ion-lines.txt`。
- 验证：`grep -c . /root/ion-lines.txt` 与 `grep -E 'ion.*s$' 源文件 | wc -l` 一致。
<details><summary>提示</summary>

`grep -E 'ion.*s$' /etc/services > /root/ion-lines.txt`
</details>

**1.3** 创建 `/root/etc.tar.bz2`，内容为整个 `/etc` 目录的 bzip2 压缩归档；再把其中的 `etc/hosts` 单独解压到 `/tmp/restore/`。
- 验证：`tar -tjf /root/etc.tar.bz2 | head`；`cat /tmp/restore/etc/hosts`。
<details><summary>提示</summary>

`tar -cjf /root/etc.tar.bz2 /etc`；`mkdir -p /tmp/restore && tar -xjf /root/etc.tar.bz2 -C /tmp/restore etc/hosts`。缺 bzip2 就 `dnf install -y bzip2`。
</details>

**1.4** 创建 `/root/hosts.hard`（`/etc/hosts` 的硬链接）和 `/root/hosts.soft`（软链接）。然后说明：删除 `/etc/hosts` 后哪个还能读到内容？（只在快照里试！）
- 验证：`ls -li /etc/hosts /root/hosts.*` 中硬链接 inode 相同。
<details><summary>提示</summary>

`ln /etc/hosts /root/hosts.hard; ln -s /etc/hosts /root/hosts.soft`。硬链接仍可读，软链接变成悬空链接。
</details>

**1.5** 创建目录 `/data/report`，属主 `root`、属组 `student`，权限要求：属主读写执行、属组只读可进入、其他人无任何权限。
- 验证：`ls -ld /data/report` 显示 `drwxr-x---. root student`。
<details><summary>提示</summary>

`mkdir -p /data/report && chown root:student /data/report && chmod 750 /data/report`
</details>

**1.6** 不用搜索引擎，只用本地文档，找出：`/etc/fstab` 第 5、6 列的含义；`tar` 中哪个选项表示 xz 压缩。把答案写进 `/root/doc-answers.txt`。
<details><summary>提示</summary>

`man 5 fstab`（搜 `/fifth`）；`man tar` 搜 `/xz`。`man -k` 无结果先执行 `mandb`。
</details>

---

<a id="s2"></a>
## S2 Shell 脚本（笔记：[S2](../../notes/rhcsa/02-shell-scripting.md)）

**2.1** 编写 `/usr/local/bin/sysinfo`：无参数时输出主机名、内核版本、内存总量（MiB）三行；任何用户都能直接执行 `sysinfo`。
- 验证：`su - student -c sysinfo`。
<details><summary>提示</summary>

用 `hostname`、`uname -r`、`free -m | awk '/Mem:/{print $2}'`；别忘了 `chmod 755`。
</details>

**2.2** 编写 `/root/bin/checkfile.sh`：接收 1 个参数；参数个数不对时向 stderr 输出 `Usage: checkfile.sh <path>` 并以退出码 1 退出；参数是文件输出 `file`，是目录输出 `directory`，都不是输出 `none` 并以退出码 2 退出。
- 验证：分别用 `/etc/hosts`、`/etc`、`/nope`、无参数测试，并 `echo $?`。

**2.3** 编写 `/root/bin/mkusers.sh`：读取 `/root/userlist.txt`（每行一个用户名），为每个不存在的用户创建账号并设置密码 `Passw0rd`；已存在的用户输出 `<name> exists` 并跳过。
- 验证：准备一个含已存在用户的列表运行两次，第二次全部输出 exists。
<details><summary>提示</summary>

`while read -r u; do id "$u" &>/dev/null && { echo "$u exists"; continue; }; useradd "$u"; echo Passw0rd | passwd --stdin "$u"; done < /root/userlist.txt`
</details>

**2.4** 编写 `/root/bin/bigfiles.sh`：找出 `/usr` 下大于 5 MiB 的文件，输出「大小(MiB) 路径」，按大小降序，只取前 10 行，结果写入 `/root/bigfiles.txt`。

---

<a id="s3"></a>
## S3 运行中的系统（笔记：[S3](../../notes/rhcsa/03-operate-running-systems.md)）

**3.1** 【先打快照】假设你不知道 serverb 的 root 密码。通过中断引导将其重置为 `redhat123`，重启后能用新密码登录，SELinux 仍为 enforcing。
- 验证：控制台用新密码登录；`getenforce` 为 Enforcing。
<details><summary>提示</summary>

GRUB 按 `e` → linux 行末尾加 `rd.break` → `Ctrl+x` → `mount -o remount,rw /sysroot` → `chroot /sysroot` → `passwd root` → `touch /.autorelabel` → `exit` → `exit`。`rd.break` 不行就用 `init=/bin/bash` 方法（见笔记 S3）。
</details>

**3.2** 将 servera 默认启动到 `multi-user.target`；然后在**不改默认值**的情况下，通过 GRUB 让本次启动进入 `rescue.target`。
- 验证：`systemctl get-default`；rescue 模式提示输入 root 密码。

**3.3** 启动一个后台任务 `dd if=/dev/zero of=/dev/null &`，找出 CPU 占用最高的进程，把它的 nice 值调到 15，然后终止它。
- 验证：`ps -o pid,ni,cmd -p <PID>` 显示 NI 15；之后 `pgrep dd` 无输出。

**3.4** 安装并启用 tuned，把 profile 设置为系统推荐值。
- 验证：`tuned-adm active` 与 `tuned-adm recommend` 输出一致，重启后仍一致。

**3.5** 配置 systemd journal 持久化，重启后能看到上一次启动的日志。
- 验证：`journalctl --list-boots` 至少 2 条；`journalctl -b -1 | head`。
<details><summary>提示</summary>

`mkdir -p /var/log/journal` 或在 `/etc/systemd/journald.conf` 设置 `Storage=persistent`，然后 `systemctl restart systemd-journald`。
</details>

**3.6** 把 servera 上 `/var/log/messages` 中所有包含 `error`（不区分大小写）的行，通过 scp 传到 serverb 的 `/tmp/servera-errors.log`。

---

<a id="s4"></a>
## S4 本地存储与 LVM（笔记：[S4](../../notes/rhcsa/04-local-storage-lvm.md)）

**4.1** 在 `/dev/vdb` 上创建 GPT 分区表，新建一个 2 GiB 分区，用作 LVM 物理卷。
- 验证：`parted /dev/vdb print` 显示 lvm 标志；`pvs` 中出现 `/dev/vdb1`。

**4.2** 创建卷组 `vg_exam`，PE 大小 16 MiB；在其中创建逻辑卷 `lv_data`，大小为 **40 个 extent**，格式化为 xfs，按 **UUID** 持久挂载到 `/exam/data`。
- 验证：`lvdisplay vg_exam/lv_data` 显示 Current LE 40（= 640 MiB）；`findmnt /exam/data`；重启后仍挂载。
<details><summary>提示</summary>

`vgcreate -s 16M vg_exam /dev/vdb1`；`lvcreate -n lv_data -l 40 vg_exam`；`mkfs.xfs`；`blkid` 取 UUID 写 fstab；`systemctl daemon-reload; mount -a`。
</details>

**4.3** 在**不卸载、不丢数据**的前提下，把 `lv_data` 扩容到约 900 MiB（允许 870~930 MiB）。
- 验证：先在 `/exam/data` 写入测试文件，扩容后文件仍在；`df -h /exam/data`。
<details><summary>提示</summary>

`lvextend -r -L 900M /dev/vg_exam/lv_data`（640 MiB + 若干 PE；16 MiB 粒度会自动取整）。
</details>

**4.4** 在 `/dev/vdb` 的剩余空间中新增一个 512 MiB 的 swap 分区，持久启用，且**不影响系统原有的 swap**。
- 验证：`swapon --show` 显示两个 swap；重启后仍然两个。

**4.5** VG `vg_exam` 空间不足：把 `/dev/vdc` 整盘加入 `vg_exam`，然后新建 LV `lv_logs`（1 GiB，ext4），按 **LABEL=LOGS** 挂载到 `/exam/logs`。
- 验证：`vgs vg_exam` 显示 2 个 PV；`blkid` 中 LABEL 为 LOGS；`findmnt /exam/logs`。

---

<a id="s5"></a>
## S5 文件系统 / NFS / autofs（笔记：[S5](../../notes/rhcsa/05-file-systems-nfs-autofs.md)）

**5.1** 将 serverb 的 `/exports/share` 以 NFS 方式持久挂载到 servera 的 `/mnt/share`（只读）。
- 验证：`findmnt /mnt/share` 显示 `ro` 和 `nfs`；重启后仍在。
<details><summary>提示</summary>

fstab：`serverb:/exports/share  /mnt/share  nfs  ro,_netdev  0 0`
</details>

**5.2** 配置 autofs：servera 上用户 `remoteuser1`（UID 3001，家目录 `/home/remote/remoteuser1`）登录时，自动挂载 `serverb:/exports/home/remoteuser1` 作为家目录，可读写。要求使用**通配符**映射，以便 remoteuser2 也自动生效。
- 验证：`su - remoteuser1` 后 `pwd` 为 `/home/remote/remoteuser1`，`touch test` 成功；`mount | grep remote`。
<details><summary>提示</summary>

`useradd -u 3001 -d /home/remote/remoteuser1 -M remoteuser1`；`/etc/auto.master.d/remote.autofs` 写 `/home/remote /etc/auto.remote`；`/etc/auto.remote` 写 `* -rw,sync serverb:/exports/home/&`；`systemctl enable --now autofs`。
</details>

**5.3** 用 autofs **直接映射**把 `serverb:/exports/share` 按需挂载到 `/mnt/docs`。

**5.4** 创建协作目录 `/srv/projects`：属组 `projects`，组成员可读写，其他人无权限，组成员在其中新建的文件**自动属于 projects 组**。把 `student` 加入 projects 组。
- 验证：`su - student -c 'touch /srv/projects/a'`；`ls -l /srv/projects/a` 属组为 projects。

**5.5** 在 `/dev/vdb` 剩余空间（或新 LV）上创建 vfat 文件系统，挂载到 `/mnt/usb`，使 `student` 拥有其中文件。

**5.6** 用户 `student` 报告无法读取 `/srv/secret/plan.txt`（文件权限 644）。找出原因并修复（可能存在多层原因：父目录权限、ACL）。
- 准备：`mkdir -p /srv/secret && echo plan > /srv/secret/plan.txt && chmod 700 /srv/secret && setfacl -m u:student:--- /srv/secret/plan.txt`

---

<a id="s6"></a>
## S6 软件、计划任务、时间、引导（笔记：[S6](../../notes/rhcsa/06-software-scheduling-boot.md)）

**6.1** 删除（或备份移走）`/etc/yum.repos.d/` 下所有 repo 文件，手写一个 repo 文件，使用 serverb 上 HTTP 发布的 BaseOS 和 AppStream 仓库（见实验环境第 5 节），然后安装 `httpd` 和 `tmux`。
- 验证：`dnf repolist` 只显示你的两个仓库；`rpm -q httpd tmux`。

**6.2** 找出提供 `/usr/bin/dig` 命令的软件包并安装它。

**6.3** 用户 `student` 每天 14:23 执行 `/usr/bin/echo "hello"`；同时配置 root 在工作日每 10 分钟执行 `logger "rhcsa-check"`。
- 验证：`crontab -l -u student`；`crontab -l`；稍后 `journalctl -t root | grep rhcsa-check` 或 `grep rhcsa-check /var/log/messages`。

**6.4** 用 systemd timer 实现：每天 03:00 把 `/etc` 打包到 `/root/backup/etc-$(date +%F).tar.gz`（提示：在 service 里调用脚本），timer 开机自启。
- 验证：`systemctl list-timers | grep` 你的 timer；手动 `systemctl start` 对应 service 一次，检查生成的文件。

**6.5** 把时区设为 `Asia/Shanghai`；配置 chrony 只使用 `serverb` 作为时间源（练习时可先在 serverb 上 `allow 192.168.122.0/24` 并启用 chronyd 作为服务器）。
- 验证：`timedatectl`；`chronyc sources` 中 serverb 一行行首出现 `^*`（或 `^?` 时检查 serverb 防火墙 `ntp` 服务）。

**6.6** 为所有内核条目添加内核参数 `audit=1`，并删除 `rhgb quiet`。
- 验证：重启后 `cat /proc/cmdline`。
<details><summary>提示</summary>

`grubby --update-kernel=ALL --args="audit=1" --remove-args="rhgb quiet"`
</details>

**6.7** 【RHEL 10 新增目标】安装 flatpak，添加一个 Flatpak 仓库（正版 RHEL 用 `rhel` 仓库；Alma/Rocky 用 flathub），安装一个小应用（如计算器 `org.gnome.Calculator`），确认 `flatpak list` 中可见，然后卸载并删除该仓库。
- 验证：每一步用 `flatpak remotes` / `flatpak list --app` 检查。

---

<a id="s7"></a>
## S7 网络配置 nmcli（笔记：[S7](../../notes/rhcsa/07-networking-nmcli.md)）

**7.1** 【在 VM 控制台操作】把 serverb 当前连接改为静态：IP `192.168.122.11/24`、网关 `192.168.122.1`、DNS `192.168.122.1`，开机自动连接。
- 验证：重启后 `ip -br a`、`ip route`、`cat /etc/resolv.conf`。

**7.2** 为同一连接再追加 IPv4 地址 `192.168.122.111/24` 和 IPv6 地址 `fd00:122::11/64`。
- 验证：`ip -br a` 同时显示三个地址；从 servera `ping 192.168.122.111`。

**7.3** 将 serverb 主机名设为 `serverb.lab.example.com`，在 servera 和 serverb 的 `/etc/hosts` 中添加 `192.168.122.200 repo.lab.example.com repo` 的解析。
- 验证：`hostnamectl`；`getent hosts repo`。

**7.4** 新建一个名为 `backup-net` 的连接（绑定到同一网卡，静态 IP `10.10.10.5/24`，**不自动连接**）。确认重启后激活的仍是原连接。
- 验证：`nmcli -f NAME,AUTOCONNECT,DEVICE con show`。

---

<a id="s8"></a>
## S8 用户、组与 sudo（笔记：[S8](../../notes/rhcsa/08-users-groups-sudo.md)）

**8.1** 创建组 `sysadmins`（GID 4000）；创建用户 `natasha`、`harry`，附加组为 sysadmins；创建用户 `sarah`，不能交互登录，不属于 sysadmins。三人密码均为 `flectrag`。
- 验证：`id natasha`；`getent passwd sarah` 的 shell 为 `/sbin/nologin`；`su - harry` 用密码登录成功。

**8.2** 创建用户 `alex`，UID 为 3456，密码 `flectrag`；把 `alex` 追加到 `wheel` 组，**不能丢失**它原有的附加组。

**8.3** 新建用户的密码默认 30 天后过期；`natasha` 的密码立即改为 60 天过期、提前 7 天警告，且下次登录必须修改密码。
- 验证：`grep ^PASS /etc/login.defs`；`chage -l natasha`。

**8.4** 让 `sysadmins` 组成员可以免密码执行任何 sudo 命令；让 `harry` 只能以 sudo 执行 `/usr/bin/systemctl restart httpd`。
- 验证：`su - natasha -c 'sudo -n id'` 成功；`sudo -l -U harry`。
<details><summary>提示</summary>

`visudo -f /etc/sudoers.d/sysadmins`：`%sysadmins ALL=(ALL) NOPASSWD: ALL`；`harry ALL=(root) /usr/bin/systemctl restart httpd`。
</details>

**8.5** 账号 `harry` 在 2026-12-31 之后不可用。

---

<a id="s9"></a>
## S9 防火墙与 SELinux（笔记：[S9](../../notes/rhcsa/09-security-firewalld-selinux.md)）

**9.1** 在 servera 安装 httpd，网站根目录改为 `/webroot`（放一个 `index.html` 内容为 `Hello RHCSA`），httpd 监听 **82** 端口；SELinux 保持 enforcing；从 serverb 能 `curl http://servera:82` 看到内容；开机自启。
- 验证：serverb 上 `curl servera:82`；`getenforce`；重启后再 curl。
<details><summary>提示</summary>

改 `/etc/httpd/conf/httpd.conf` 中 `Listen 82`、`DocumentRoot "/webroot"` 和对应 `<Directory "/webroot">`；`semanage fcontext -a -t httpd_sys_content_t '/webroot(/.*)?' && restorecon -Rv /webroot`；`semanage port -a -t http_port_t -p tcp 82`；`firewall-cmd --permanent --add-port=82/tcp && firewall-cmd --reload`；`systemctl enable --now httpd`。
</details>

**9.2** 故障排查：执行以下准备后网页返回 403，**不允许关闭 SELinux**，找出并修复原因。
- 准备：`echo moved > /root/moved.html && mv /root/moved.html /var/www/html/`
- 验证：`curl localhost/moved.html` 返回 `moved`。
<details><summary>提示</summary>

`ls -Z /var/www/html/moved.html` 显示 `admin_home_t`；`restorecon -v /var/www/html/moved.html`。
</details>

**9.3** 让 Apache 可以访问用户家目录中的 `public_html`（找出并持久开启相应 SELinux 布尔值）。
- 验证：`getsebool httpd_enable_homedirs` 为 on，重启后仍为 on。

**9.4** 防火墙：允许 `192.168.122.0/24` 访问 servera 的 5432/tcp，其他来源不允许；永久删除 `cockpit` 服务；所有修改重启后有效。
- 验证：`firewall-cmd --list-all`。

**9.5** 配置 `student` 从 servera 免密登录 serverb；并在 serverb 上禁止所有用户使用密码登录 SSH（用 drop-in 文件实现）。**注意：先确认密钥登录成功再禁用密码！**
- 验证：`ssh student@serverb hostname` 不询问密码；从别的用户尝试密码登录被拒。

**9.6** 用户 `natasha` 新建的文件默认权限为 `-rw-r-----`，目录为 `drwxr-x---`。
- 验证：`su - natasha -c 'touch f; mkdir d; ls -ld f d'`。

---

<a id="s10"></a>
## S10 Podman 容器（笔记：[S10](../../notes/rhcsa/10-containers-podman.md)；先确认你报考版本是否包含此目标）

**10.1** 以 `student` 身份：用 skopeo 查看 `registry.access.redhat.com/ubi10/ubi` 的可用标签和架构（不拉取镜像）。

**10.2** 以 `student` 身份编写 Containerfile，基于 UBI 10 安装 httpd，构建镜像 `localhost/webapp:v1`。
- 验证：`podman images` 中出现该镜像。

**10.3** 以 `student` 身份运行容器 `webapp`：宿主 8080 → 容器 80，宿主目录 `~/web-content` 挂载为容器的网站根目录，内容为 `container works`。
- 验证：`curl localhost:8080`。
<details><summary>提示</summary>

`podman run -d --name webapp -p 8080:80 -v ~/web-content:/var/www/html:Z localhost/webapp:v1`
</details>

**10.4** 把 `webapp` 配置为 `student` 的 systemd 用户服务（Quadlet），系统重启后**无需 student 登录**容器即自动运行。
- 验证：`reboot` 后不登录 student，从 root 执行 `curl localhost:8080`；`ssh student@localhost systemctl --user status webapp`。
<details><summary>提示</summary>

用 `ssh student@localhost` 登录（不要 `su`）；`loginctl enable-linger student`；写 `~/.config/containers/systemd/webapp.container`（含 `[Install] WantedBy=default.target`）；`systemctl --user daemon-reload && systemctl --user start webapp`。
</details>

**10.5** 用 `podman pod` 创建一个包含 web 和 sidecar（`ubi10/ubi` 运行 `sleep infinity`）两个容器的 Pod，验证两个容器共享网络（在 sidecar 里 `curl localhost:80`）。思考它和 Kubernetes Pod 的对应关系（预习 [CKA-09](../../notes/cka/09-workloads.md)）。

---

## 完成后

- [ ] 回滚快照，**不看提示**把每节最难的一题再做一遍
- [ ] 计时完成一次 [模拟考](mock-exam.md)
