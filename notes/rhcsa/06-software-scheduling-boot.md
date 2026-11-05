# RHCSA-06 部署与维护：软件仓库、Flatpak、计划任务、时间同步、引导配置

> **轨道**：[RHCSA](README.md) ｜ **考纲**：EX200「Deploy, configure, and maintain systems」+ RHEL 10 新增「Manage software（Flatpak）」 ｜ **建议用时**：7 h ｜ **难度**：★★☆
>
> **前置**：[S3 运行中的系统](03-operate-running-systems.md)
> **后续**：[RHCE-11 用 Ansible 自动化 RHCSA 任务](../rhce/11-automate-rhcsa-tasks.md)（`dnf`/`yum_repository`/`cron`/`systemd_service` 模块）
> **关联**（跨轨道）：[CKA-03 用 kubeadm 搭建集群](../cka/03-kubeadm-install.md)（加 Kubernetes 软件仓库、时间同步、内核参数都是装集群的前置） · [S7 网络配置](07-networking-nmcli.md)

## 1. 这个知识点在网络中的位置

这一节是「让一台机器长期稳定运行」的日常维护：装软件、定时任务、时间同步、开机自启、改内核参数。几乎每道 EX200 大题都会顺带考到其中一项（比如「安装 httpd 并开机自启」）。

在网络中：RHCE 用 `ansible.builtin.dnf`、`ansible.builtin.yum_repository`、`ansible.builtin.cron`、`ansible.builtin.systemd_service` 做同样的事；CKA 装集群时要先添加 Kubernetes 的软件仓库、确保节点时间一致（证书校验依赖时间）。

Ubuntu 对照：

| Ubuntu | RHEL |
|---|---|
| `apt install/remove/update/upgrade` | `dnf install/remove/check-update/upgrade` |
| `/etc/apt/sources.list.d/*.list` | `/etc/yum.repos.d/*.repo` |
| `dpkg -i x.deb` / `dpkg -L` / `dpkg -S` | `dnf install ./x.rpm` / `rpm -ql` / `rpm -qf` |
| `systemd-timesyncd`（默认） | `chronyd` |
| `update-grub` | `grubby` 或 `grub2-mkconfig -o /boot/grub2/grub.cfg` |
| Snap | Flatpak（RHEL 10 版考纲新增） |

## 2. 核心概念

| 主题 | 要点 |
|---|---|
| 软件仓库 | RHEL 分 **BaseOS**（核心系统）和 **AppStream**（应用、语言运行时）两个仓库；订阅后由 `subscription-manager` 管理，也可手写 `.repo` 文件 |
| `.repo` 文件 | 至少包含 `[id]`、`name=`、`baseurl=`、`enabled=1`、`gpgcheck=`；有 GPG key 时写 `gpgkey=` |
| 模块化（module stream） | RHEL 8/9 的 AppStream 有 `dnf module`；据 RHEL 10 资料已不再提供模块流（以官方为准），考试遇到按题意操作 |
| Flatpak | 桌面应用的沙箱化分发格式。需要先配置 **remote（仓库）**，再 `flatpak install`。红帽提供 RHEL Flatpak 仓库（需订阅认证） |
| cron | `crontab -e`（用户级）、`/etc/crontab`、`/etc/cron.d/`（系统级，需写用户名字段）；格式「分 时 日 月 周 命令」 |
| at | 一次性任务：`at now + 5 minutes`、`atq`、`atrm`；服务 `atd` |
| systemd timer | `.timer` 单元驱动同名 `.service`；`OnCalendar=` 类似 cron |
| chrony | `/etc/chrony.conf` 里的 `server`/`pool` 行；`chronyc sources -v` 验证 |
| 引导参数 | `grubby --update-kernel=ALL --args="..."` 修改所有内核条目的参数（持久） |

## 3. 必会操作

### 3.1 软件包与仓库

```bash
dnf repolist all                              # 所有仓库及启用状态
dnf search nginx; dnf info nginx              # 搜索/详情
dnf provides '*/semanage'                     # 哪个包提供这个文件（考场救命：找不到命令时用）
dnf install -y httpd; dnf remove -y httpd
dnf upgrade -y                                # 更新全部（≈ apt update && apt upgrade）
dnf history; dnf history undo <ID>            # 事务历史与回滚
dnf group list; dnf group install -y "Development Tools"
dnf install -y ./local-package.rpm            # 安装本地 rpm 并自动解决依赖
rpm -qa | grep kernel; rpm -qi httpd; rpm -ql httpd; rpm -qf /etc/httpd/conf/httpd.conf
rpm -qc httpd                                 # 只列配置文件

# 手写 repo 文件（考试最常见：「配置 http://.../BaseOS 和 .../AppStream 作为软件源」）
cat > /etc/yum.repos.d/exam.repo <<'EOF'
[BaseOS]
name=BaseOS
baseurl=http://repo.example.com/rhel10/BaseOS
enabled=1
gpgcheck=0

[AppStream]
name=AppStream
baseurl=http://repo.example.com/rhel10/AppStream
enabled=1
gpgcheck=0
EOF
dnf clean all && dnf repolist                 # 验证
# 或：dnf config-manager --add-repo http://repo.example.com/rhel10/BaseOS
#     （会自动生成 .repo，但 gpgcheck 可能需要手工调整；dnf-plugins-core 提供该子命令）
```

### 3.2 Flatpak（RHEL 10 版考纲新增，命令以官方文档为准）

```bash
dnf install -y flatpak
flatpak remotes                               # 已配置的仓库
# 添加仓库（考试会给出 URL；以下为两个常见示例）
flatpak remote-add --if-not-exists rhel https://flatpaks.redhat.io/rhel.flatpakrepo     # 红帽官方（需订阅认证）
flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo  # 社区仓库，练习用
flatpak remote-ls rhel | head                 # 列出仓库里的应用
flatpak search gedit
flatpak install -y rhel org.gnome.gedit       # 系统级安装（默认 --system）
flatpak list --app                            # 已安装应用
flatpak run org.gnome.gedit                   # 运行（需要图形会话）
flatpak uninstall -y org.gnome.gedit
flatpak remote-delete flathub
```

### 3.3 计划任务

```bash
# cron：分 时 日 月 周
crontab -e -u alice                           # 编辑 alice 的计划任务
#   */5 * * * *  /usr/bin/logger "alice cron"        每 5 分钟
#   30 14 * * 1-5 /usr/local/bin/backup.sh            工作日 14:30
crontab -l -u alice
echo '0 2 * * * root /usr/local/bin/cleanup.sh' > /etc/cron.d/cleanup   # 系统级多一列用户名
# 限制谁能用 cron：/etc/cron.allow、/etc/cron.deny

# at：一次性
systemctl enable --now atd
echo 'date > /tmp/at-test' | at now + 2 minutes
atq; atrm 1

# systemd timer（现代写法）
cat > /etc/systemd/system/backup.service <<'EOF'
[Unit]
Description=Backup /etc
[Service]
Type=oneshot
ExecStart=/usr/bin/tar czf /root/etc-%H.tar.gz /etc
EOF
cat > /etc/systemd/system/backup.timer <<'EOF'
[Unit]
Description=Daily backup
[Timer]
OnCalendar=*-*-* 02:00:00
Persistent=true
[Install]
WantedBy=timers.target
EOF
systemctl daemon-reload && systemctl enable --now backup.timer
systemctl list-timers
```

### 3.4 服务与默认 target

```bash
systemctl enable --now httpd                  # 开机自启 + 立即启动（考试标准答案）
systemctl is-enabled httpd; systemctl is-active httpd
systemctl set-default multi-user.target       # 默认 target（详见 S3）
```

### 3.5 时间同步

```bash
timedatectl                                   # 时区、NTP 状态
timedatectl set-timezone Asia/Shanghai
timedatectl list-timezones | grep -i shanghai
vim /etc/chrony.conf                          # 注释掉默认 pool 行，加：server classroom.example.com iburst
systemctl enable --now chronyd && systemctl restart chronyd
chronyc sources -v                            # 行首 ^* 表示已同步到该源
timedatectl set-ntp true
```

### 3.6 引导加载程序与内核

```bash
grubby --default-kernel                       # 当前默认内核
grubby --info=ALL | grep -E '^(index|kernel|args)'
grubby --update-kernel=ALL --args="console=ttyS0"      # 给所有内核加参数（持久）
grubby --update-kernel=ALL --remove-args="rhgb quiet"  # 删除参数
grubby --set-default /boot/vmlinuz-<版本>              # 设置默认内核
# 传统方式：改 /etc/default/grub 的 GRUB_TIMEOUT / GRUB_CMDLINE_LINUX，然后
grub2-mkconfig -o /boot/grub2/grub.cfg        # RHEL 9+ 在 UEFI 上也是这个路径
dnf upgrade -y kernel                         # 内核更新会新增条目，保留旧内核
```

## 4. 考试坑点

- **repo 的 `baseurl` 要精确到含 `repodata/` 的那一层目录**；写错会报 "Cannot download repomd.xml"。
- 题目没给 GPG key 时 `gpgcheck=0`；给了就 `gpgcheck=1` + `gpgkey=`。
- **服务要 `enable --now`**，只 `start` 重启后就没了。
- **系统级 cron（/etc/cron.d、/etc/crontab）要写用户名字段**，用户级 `crontab -e` 不写。
- cron 环境变量极少，脚本里命令用绝对路径。
- 改了 chrony 配置要 `systemctl restart chronyd`，并用 `chronyc sources` 确认 `^*`。
- Flatpak：`--system`（默认，所有用户可见）与 `--user` 的区别；题目说「为所有用户安装」用默认即可。
- `grubby` 改的是 BLS 条目（`/boot/loader/entries/*.conf`），重启后生效；用 `cat /proc/cmdline` 验证。

## 5. 动手练习

- [练习题集 · S6 软件、计划任务、时间、引导](../../labs/rhcsa/practice-set-1.md#s6)
- 本地 ISO 仓库的搭法见 [实验环境搭建 · 本地仓库](../../labs/rhcsa/00-lab-setup.md)

## 6. 官方文档（本仓库离线版 + 考场可用的查法）

- RHEL 10《Managing software with the DNF tool》：<https://docs.redhat.com/en/documentation/red_hat_enterprise_linux/10/html-single/managing_software_with_the_dnf_tool/index>
- RHEL 10《Managing, monitoring, and updating the kernel》（grubby、内核参数）：<https://docs.redhat.com/en/documentation/red_hat_enterprise_linux/10/html-single/managing_monitoring_and_updating_the_kernel/index>
- Flatpak、chrony、计划任务等章节请在 RHEL 10 文档首页搜索：<https://docs.redhat.com/en/documentation/red_hat_enterprise_linux/10>
- 离线 PDF：运行 [`scripts/fetch-rhel-docs.sh`](../../scripts/fetch-rhel-docs.sh)
- **考场查法**：
  - `man 5 yum.conf` 或 `man dnf.conf` → `/\[repository\] OPTIONS`（repo 文件各字段）
  - `man 5 crontab`（时间字段格式，含示例）、`cat /etc/crontab`（自带格式注释）
  - `man systemd.timer`、`man systemd.time` → `/CALENDAR EVENTS`
  - `man chrony.conf` → `/server`
  - `man grubby` → `/EXAMPLES`
  - `man flatpak-remote-add`、`man flatpak-install`

## 7. 自测清单

- [ ] 能手写 BaseOS + AppStream 两个 repo 并成功安装软件
- [ ] 能用 `dnf provides` 找到某个命令属于哪个包
- [ ] 能添加 Flatpak 仓库、安装并卸载一个应用
- [ ] 能写一条「每周一到周五 14:23 以 alice 身份执行」的 cron
- [ ] 能把 cron 任务改写成 systemd timer
- [ ] 能把 chrony 指向指定服务器并验证同步
- [ ] 能用 `grubby` 给所有内核添加/删除参数，并通过 `/proc/cmdline` 验证
