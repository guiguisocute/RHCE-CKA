# RHCSA-03 运行中的系统：引导、target、root 密码重置、进程、tuned、日志

> **轨道**：[RHCSA](README.md) ｜ **考纲**：EX200「Operate running systems」 ｜ **建议用时**：8 h ｜ **难度**：★★☆
>
> **前置**：[S1 基础工具](01-essential-tools.md) · [F2 systemd 与 journald](../00-foundations/02-systemd-journald.md)
> **后续**：[S6 软件、计划任务、时间、引导](06-software-scheduling-boot.md)
> **关联**（跨轨道）：[CKA-15 排错](../cka/15-troubleshooting.md)（`systemctl status kubelet`、`journalctl -u kubelet` 是节点排错第一步） · [RHCE-11 自动化 RHCSA 任务](../rhce/11-automate-rhcsa-tasks.md)

## 1. 这个知识点在网络中的位置

这一节决定你**能不能进考场的机器**：EX200 常见的开场题就是「这台机器 root 密码未知，请重置」。做不出来，后面的题全部没法做。

此外，进程管理、日志查看、持久化 journal 是所有排错的基础；CKA 30% 的排错题里，节点层面的问题（kubelet 挂了、证书过期、磁盘满）全靠这里的技能。

Ubuntu 对照：Ubuntu 也是 systemd + GRUB2，`systemctl`/`journalctl` 用法完全一样；差异在 GRUB 菜单默认隐藏（Ubuntu）vs 默认显示（RHEL），以及 RHEL 默认启用 SELinux（重置密码后要 relabel）。

## 2. 核心概念

| 主题 | 要点 |
|---|---|
| systemd target | `multi-user.target`（字符界面，≈ 老的 runlevel 3）、`graphical.target`（图形，≈ 5）、`rescue.target`（单用户，需要 root 密码）、`emergency.target`（最小化，只读根） |
| 引导链 | 固件(BIOS/UEFI) → GRUB2 → kernel + initramfs → systemd(PID 1) → default.target |
| 中断引导 | 在 GRUB 菜单按 `e` 编辑内核参数行（以 `linux` 开头），`Ctrl+x` 用修改后的参数启动一次（不持久） |
| 进程 | `ps aux`、`top`（`P` 按 CPU 排序，`M` 按内存，`k` 杀进程，`r` renice）、信号 15(TERM)/9(KILL)/1(HUP) |
| nice 值 | -20（最高优先级）~ 19（最低）；普通用户只能调高（降优先级），root 才能调低 |
| tuned | 系统调优守护进程，按场景切换 profile：`virtual-guest`、`throughput-performance`、`balanced`、`powersave` 等 |
| journald | 默认 `Storage=auto`：存在 `/var/log/journal/` 才持久化，否则只在内存（`/run/log/journal/`），重启就丢 |
| rsyslog | 传统文本日志 `/var/log/messages`、`/var/log/secure`（≈ Ubuntu 的 `/var/log/syslog`、`/var/log/auth.log`） |

## 3. 必会操作

### 3.1 开关机与 target

```bash
systemctl reboot / systemctl poweroff         # 正常重启/关机
systemctl get-default                         # 查看默认 target
systemctl set-default multi-user.target       # 设置默认 target（持久）
systemctl isolate rescue.target               # 立即切换（当前会话）
# GRUB 里临时进入某 target：在 linux 行末尾加 systemd.unit=rescue.target
```

### 3.2 中断引导重置 root 密码（必须练到 3 分钟内）

**方法 A：`rd.break`**（RHEL 8/9 官方文档的经典流程；RHEL 10 请对照官方文档确认）

```text
1. 重启，在 GRUB 菜单停住（按方向键），选中默认内核，按 e
2. 找到以 linux 开头的行，移动到行尾，追加：rd.break
   （如果是虚拟机串口控制台，可能还需删掉 console=ttyS0 之类参数才能在图形控制台看到 shell）
3. Ctrl+x 启动，进入 switch_root:/# 提示符
4. mount -o remount,rw /sysroot
5. chroot /sysroot
6. passwd root                      # 输入两次新密码
7. touch /.autorelabel              # 让 SELinux 下次启动时重打标签（很重要！）
8. exit                             # 退出 chroot
9. exit                             # 继续启动（relabel 后会自动再重启一次，耐心等待）
```

**方法 B：`init=/bin/bash`**（`rd.break` 提示需要 root 密码、或 initramfs 不配合时的备选）

```text
1. GRUB 按 e，在 linux 行末尾追加：init=/bin/bash（可同时删掉 rhgb quiet 方便看输出）
2. Ctrl+x 启动，直接得到 root shell（根目录只读）
3. mount -o remount,rw /
4. passwd root
5. touch /.autorelabel
6. exec /usr/lib/systemd/systemd    # 或 /usr/sbin/reboot -f
```

> 为什么要 `touch /.autorelabel`：`passwd` 在没有加载 SELinux 策略的环境下重写了 `/etc/shadow`，文件丢失正确的 SELinux 标签，不 relabel 的话**重启后谁都登录不了**。

### 3.3 进程与调度

```bash
ps aux --sort=-%cpu | head -5                 # CPU 占用前 5
ps -eo pid,user,ni,%cpu,%mem,cmd --sort=-%mem | head
top                                           # 交互：P/M 排序，k 杀，r 改 nice，q 退出
kill -15 1234; kill -9 1234                   # 先礼后兵
pkill -u alice; killall dd                    # 按用户/按名字
nice -n 10 tar czf /tmp/big.tgz /usr          # 以 nice 10 启动
renice -n 5 -p 1234                           # 修改运行中进程
```

### 3.4 tuned

```bash
dnf install -y tuned && systemctl enable --now tuned
tuned-adm list                                # 所有 profile
tuned-adm recommend                           # 系统推荐的 profile（题目常问「设置为推荐的 profile」）
tuned-adm profile virtual-guest               # 切换（持久）
tuned-adm active                              # 验证
```

### 3.5 日志与持久化 journal

```bash
journalctl -u sshd --since today              # 某服务今天的日志
journalctl -p err -b                          # 本次启动以来的错误级别日志
journalctl -f                                 # 跟踪（≈ tail -f）
journalctl --list-boots                       # 持久化后才能看到多次启动

# 持久化 journal（二选一，推荐第 2 种写法更明确）
mkdir -p /var/log/journal && systemctl restart systemd-journald
# 或：在 /etc/systemd/journald.conf 的 [Journal] 段设置 Storage=persistent
#     （也可以写成 drop-in：/etc/systemd/journald.conf.d/persistent.conf）
systemctl restart systemd-journald
ls /var/log/journal/                          # 出现以 machine-id 命名的目录即成功

tail -f /var/log/secure                       # 认证日志（Ubuntu：/var/log/auth.log）
logger -p user.notice "test from alice"       # 写一条日志测试 rsyslog
```

### 3.6 网络服务状态与安全传输文件

```bash
systemctl status sshd; systemctl is-enabled sshd; systemctl is-active sshd
ss -tlnp                                      # 监听端口（替代 netstat）
scp -r /data student@serverb:/tmp/ ; rsync -avz /data/ serverb:/data/
```

## 4. 考试坑点

- **重置密码忘了 `touch /.autorelabel`**：考试最常见的「做完了但全盘皆输」。
- `rd.break` 后**要等 relabel 完成并自动重启**，不要在 relabel 过程中强制断电。
- GRUB 编辑是**一次性**的，不要试图把 `rd.break` 写进 `/etc/default/grub`。
- `systemctl isolate` 只影响当前，`set-default` 才是开机默认。
- 题目要求「journal 持久化」后，**重启验证** `journalctl --list-boots` 有多条记录。
- `tuned-adm profile` 前先确认 `tuned` 服务已 `enable --now`，否则重启后不生效。
- 普通用户不能把 nice 调成负数；题目要求负数时用 root。

## 5. 动手练习

- [练习题集 · S3 运行中的系统](../../labs/rhcsa/practice-set-1.md#s3)（含 root 密码重置）
- 建议先打快照再练重置密码，见 [实验环境搭建](../../labs/rhcsa/00-lab-setup.md)

## 6. 官方文档（本仓库离线版 + 考场可用的查法）

- RHEL 10 内核与引导参数：<https://docs.redhat.com/en/documentation/red_hat_enterprise_linux/10/html-single/managing_monitoring_and_updating_the_kernel/index>
- RHEL 10 文档首页（root 密码重置、systemd、日志等章节请在此搜索）：<https://docs.redhat.com/en/documentation/red_hat_enterprise_linux/10>
- 离线 PDF：运行 [`scripts/fetch-rhel-docs.sh`](../../scripts/fetch-rhel-docs.sh)
- **考场查法**：
  - `man dracut.cmdline` → `/rd.break`（initramfs 阶段的调试参数说明）
  - `man bootup`（引导流程图）、`man systemd.special`（各种 target 含义）
  - `man journald.conf` → `/Storage=`
  - `man tuned-adm`、`ls /usr/lib/tuned/`（所有 profile 目录）
  - `man 7 signal`（信号编号）、`man ps` → `/STANDARD FORMAT SPECIFIERS`

## 7. 自测清单

- [ ] 能在 3 分钟内（不看笔记）用 `rd.break` 或 `init=/bin/bash` 重置 root 密码，并能重新登录
- [ ] 能说明为什么需要 `/.autorelabel`
- [ ] 能把默认启动目标改为 `multi-user.target` 并重启验证
- [ ] 能找出 CPU 占用最高的进程，调整其 nice 值或终止它
- [ ] 能把 tuned 设为推荐 profile 并验证
- [ ] 能配置持久化 journal，并在重启后用 `journalctl -b -1` 查看上一次启动的日志
