# RHCSA 原创模拟考（EX200 风格）

> ⚠️ **声明**：本卷为本仓库**原创练习**，仅模仿 EX200 的题型、难度和「按最终状态评分」的方式，**不是考试真题**，也不代表真实考试的题目分布。
> 考纲请以红帽官方页面为准：<https://www.redhat.com/en/services/training/ex200-red-hat-certified-system-administrator-rhcsa-exam>

## 考试规则（请严格模拟）

- **计时 180 分钟**，中途不看笔记、不用搜索引擎；只允许 `man`、`--help`、`/usr/share/doc`。
- 开考前两台机器都回滚到 [实验环境](00-lab-setup.md) 的 `01-lab-ready` 快照，然后**额外做以下「出题人准备」**（让考生之外的人或自己提前完成）：
  - 在 servera 上把 root 密码改成一个随机值并忘掉它：`echo "root:$(openssl rand -hex 8)" | chpasswd`
  - 把 servera 的网络连接改回 DHCP：`nmcli con mod "<连接名>" ipv4.method auto ipv4.addresses '' ipv4.gateway '' ipv4.dns '' && nmcli con up "<连接名>"`
  - 删除 servera 上所有 `/etc/yum.repos.d/*.repo`（备份到 `/root/repo-bak/`）
  - serverb 按实验环境第 5、6 节提供 HTTP 仓库（`http://serverb/repo/BaseOS`、`/AppStream`）和 NFS 导出
- 题目给出的名称、路径、数值必须**完全一致**。
- **全部完成后重启两台机器**，再按文末自查表评分。重启后不生效的题记 0 分。

## 环境

| 主机 | IP | 说明 |
|---|---|---|
| servera.lab.example.com | 192.168.122.10/24，网关/DNS 192.168.122.1 | 主要答题机（第 1~16 题） |
| serverb.lab.example.com | 192.168.122.11/24 | 第 17~20 题；同时提供仓库与 NFS |

---

## 第一部分：servera

**1. 重置 root 密码（必做，否则无法继续）**
将 servera 的 root 密码设置为 `trootent`。

**2. 配置网络**
在 servera 上配置静态网络：IP `192.168.122.10/24`、网关 `192.168.122.1`、DNS `192.168.122.1`；主机名 `servera.lab.example.com`。

**3. 配置软件仓库**
配置 servera 使用 `http://serverb/repo/BaseOS` 和 `http://serverb/repo/AppStream` 作为默认仓库。

**4. 调试 SELinux**
在 servera 上安装 httpd，使其在 **非标准端口 82** 上提供服务，网站文件位于 `/var/www/html`（放一个 `file1` 文件，内容为 `EX200 mock`）。要求：
- 从 serverb 执行 `curl http://servera:82/file1` 能看到内容
- 开机自启；SELinux 保持 enforcing

**5. 用户与组**
- 创建组 `sysmgrs`
- 用户 `natasha`：附加组 sysmgrs
- 用户 `harry`：附加组 sysmgrs
- 用户 `sarah`：没有交互式 shell，不属于 sysmgrs
- 所有用户密码 `flectrag`

**6. 协作目录**
创建 `/common/admin`：属组 sysmgrs；sysmgrs 成员可读写和访问，其他用户无任何权限；在其中创建的文件自动属于 sysmgrs 组。

**7. 计划任务**
用户 `natasha` 每天 14:23 执行 `/bin/echo hiya`。

**8. sudo**
sysmgrs 组的成员可以**无需密码**以 sudo 执行任何命令。

**9. 时间同步**
servera 与 `serverb.lab.example.com` 同步时间（需要时在 serverb 上把 chronyd 配置为允许 192.168.122.0/24 的 NTP 服务器，并放行防火墙 `ntp` 服务）。

**10. autofs**
serverb 导出了 `/exports/home`。配置 autofs：`remoteuser1`（UID 3001，在 servera 上创建，家目录 `/home/remote/remoteuser1`）登录 servera 时，家目录自动挂载自 `serverb:/exports/home/remoteuser1`，可读写。

**11. 查找文件**
找出用户 `student` 拥有的所有文件，将它们复制到 `/root/findfiles/`（保持属性）。

**12. 文本查找**
将 `/usr/share/dict/words`（若不存在，用 `/etc/services`）中包含 `ich` 的所有行，按原始顺序写入 `/root/wordlist`，文件中不能有空行。

**13. 归档**
创建 `/root/backup.tar.bz2`，包含 `/usr/local` 的内容，使用 bzip2 压缩。

**14. 新增 swap**
在 servera 上新增一个 **512 MiB** 的 swap 分区（使用 `/dev/vdb`），开机自动启用；原有 swap 不受影响。

**15. 逻辑卷**
- 创建卷组 `datastore`，PE 大小 **16 MiB**
- 创建逻辑卷 `database`，大小为 **50 个 extent**，ext4 文件系统，开机自动挂载到 `/mnt/database`

**16. 调整逻辑卷大小**
新建逻辑卷 `vo`（在 `datastore` 中，初始 200 MiB，xfs，挂载到 `/reports`），然后将其扩展到 **300 MiB**（允许 270~330 MiB），文件系统同步扩容，数据不丢失。

---

## 第二部分：serverb

**17. tuned**
将 serverb 的 tuned profile 设置为推荐的 profile。

**18. 持久化日志**
配置 serverb 的 systemd journal 持久化保存。

**19. 默认文件权限**
用户 `student`（serverb 上）新建的文件默认权限为 `-r--r-----`（目录为 `dr-xr-x---`）。

**20. 容器（仅当你报考的版本包含容器目标）**
在 serverb 上以用户 `student`：
- 使用 `registry.access.redhat.com/ubi10/ubi` 构建镜像 `localhost/logger:1`，容器启动后每 60 秒向 stdout 打印一次 `date`
- 以该镜像运行容器 `logger`，并将宿主目录 `/home/student/container-logs` 挂载到容器内 `/var/log/app`
- 将该容器配置为 student 的 systemd 用户服务，**系统重启后无需登录**即自动运行

---

## 评分自查表（重启两台机器后逐项检查）

| 题 | 分值 | 检查命令（全部通过才得分） | 得分 |
|---|---|---|---|
| 1 | 必做 | 控制台以 `root / trootent` 登录成功；`getenforce` = Enforcing | |
| 2 | 15 | `ip -br a`、`ip route`、`cat /etc/resolv.conf`、`hostnamectl` | |
| 3 | 15 | `dnf repolist` 显示两个仓库；`dnf install -y tmux` 成功 | |
| 4 | 20 | serverb 上 `curl http://servera:82/file1`；`systemctl is-enabled httpd`；`getenforce` | |
| 5 | 15 | `id natasha harry sarah`；`getent passwd sarah`；`su - harry` 密码登录 | |
| 6 | 15 | `ls -ld /common/admin` = `drwxrws---` + `sysmgrs`；natasha 新建文件属组为 sysmgrs | |
| 7 | 10 | `crontab -l -u natasha` = `23 14 * * * /bin/echo hiya` | |
| 8 | 10 | `su - natasha -c 'sudo -n true' && echo OK` | |
| 9 | 10 | `chronyc sources` 中 serverb 为 `^*` | |
| 10 | 20 | `su - remoteuser1` → `pwd`、`touch t`、`findmnt /home/remote/remoteuser1` | |
| 11 | 10 | `ls -l /root/findfiles` 中属主为 student | |
| 12 | 10 | `diff <(grep ich 源文件) /root/wordlist` 无输出；`grep -c '^$' /root/wordlist` = 0 | |
| 13 | 10 | `tar -tjf /root/backup.tar.bz2 \| head` | |
| 14 | 15 | `swapon --show` 显示原 swap + 约 512 MiB 新 swap | |
| 15 | 20 | `vgdisplay datastore \| grep 'PE Size'` = 16 MiB；`lvdisplay datastore/database` LE = 50；`findmnt /mnt/database` 类型 ext4 | |
| 16 | 15 | `lvs datastore/vo` 在 270~330 MiB；`df -h /reports` 同步变大；扩容前写入的文件仍在 | |
| 17 | 10 | `tuned-adm active` = `tuned-adm recommend` | |
| 18 | 10 | `journalctl --list-boots` ≥ 2 条 | |
| 19 | 10 | `su - student -c 'umask'` = `0227`；新建文件权限 `-r--r-----` | |
| 20 | 20 | `curl`/`podman ps` 检查：重启后 `ssh student@serverb podman ps` 显示 logger 运行中；宿主目录挂载正确 | |
| **合计** | **300** | 参考：EX200 据公开资料 210/300 通过；本卷请以 **≥ 240** 为目标 | |

> 第 20 题不考时，总分按 280 计，目标 ≥ 225。

## 复盘

- 每道失分题写进 [`journal/`](../../journal/) 错题本，标注对应知识节点（S1~S10），回到 [笔记](../../notes/rhcsa/README.md) 补漏。
- 第一次完成时间超过 180 分钟很正常；目标是第三次模拟时 **150 分钟内完成并留出 30 分钟检查和重启验证**。
