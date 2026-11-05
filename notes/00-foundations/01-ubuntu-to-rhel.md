# F1 Ubuntu → RHEL 对照：把你的 Ubuntu 经验平移过来

> **轨道**：[公共基础](README.md) ｜ **考纲**：EX200 全部领域的前提（考纲本身不单列） ｜ **建议用时**：3 h ｜ **难度**：★☆☆
>
> **前置**：无（整张网络的起点）
> **后续**：[RHCSA-01 基础工具](../rhcsa/01-essential-tools.md)
> **关联**（跨轨道）：[RHCSA-06 软件与引导](../rhcsa/06-software-scheduling-boot.md) · [RHCSA-07 网络 nmcli](../rhcsa/07-networking-nmcli.md) · [RHCSA-09 防火墙与 SELinux](../rhcsa/09-security-firewalld-selinux.md) · [CKA-03 kubeadm 装集群](../cka/03-kubeadm-install.md)

## 1. 这个知识点在网络中的位置

你已经会用 Ubuntu，Linux 的 80% 是相通的：同样是 systemd、bash、ssh、coreutils。
RHEL 的差异集中在**包管理、网络配置、防火墙、强制访问控制（SELinux）**这四块——恰好也是 RHCSA 的高频考点。
先把「Ubuntu 上我会怎么做 → RHEL 上对应怎么做」建立起来，后面每个 RHCSA 节点就只是在这张对照表上加深。
CKA 的实验/考试节点用什么发行版并不固定（以考生手册为准），所以 Ubuntu 和 RHEL 两套习惯都要保留。

## 2. 核心概念

### 2.1 一张对照表（最重要）

| 领域 | Ubuntu（你熟悉的） | RHEL 9/10（要学的） | 详见 |
|---|---|---|---|
| 包格式 / 底层工具 | `.deb` / `dpkg` | `.rpm` / `rpm` | [RHCSA-06](../rhcsa/06-software-scheduling-boot.md) |
| 高层包管理 | `apt` | `dnf`（`yum` 是指向 dnf 的兼容命令） | 同上 |
| 软件源配置 | `/etc/apt/sources.list(.d)`、PPA | `/etc/yum.repos.d/*.repo`；官方源 = **BaseOS + AppStream** | 同上 |
| 查文件属于哪个包 | `dpkg -S /path` | `rpm -qf /path`；查「哪个包提供某命令」用 `dnf provides '*/cmd'` | 同上 |
| 包组 | `tasksel` | `dnf group list / install` | 同上 |
| 桌面软件补充 | snap / flatpak | **Flatpak**（RHEL 10 版 RHCSA 考纲新增，以官方为准） | 同上 |
| 网络配置 | netplan → systemd-networkd 或 NM | **NetworkManager**：`nmcli` / `nmtui`，配置文件 `/etc/NetworkManager/system-connections/*.nmconnection` | [RHCSA-07](../rhcsa/07-networking-nmcli.md) |
| DNS 解析 | systemd-resolved（`127.0.0.53`） | NetworkManager 直接写 `/etc/resolv.conf` | [F3](03-networking-basics.md) |
| 防火墙 | `ufw` | **firewalld**：`firewall-cmd`（后端 nftables），zone 概念 | [RHCSA-09](../rhcsa/09-security-firewalld-selinux.md) |
| 强制访问控制 | AppArmor | **SELinux**，默认 `Enforcing`，考试里**绝不能关** | [RHCSA-09](../rhcsa/09-security-firewalld-selinux.md) |
| 管理员组 | `sudo` 组 | `wheel` 组 | [RHCSA-08](../rhcsa/08-users-groups-sudo.md) |
| 默认文件系统 | ext4 | **XFS**（不能缩小！），ext4 仍可用 | [RHCSA-05](../rhcsa/05-file-systems-nfs-autofs.md) |
| 系统日志文件 | `/var/log/syslog`、`/var/log/auth.log` | `/var/log/messages`、`/var/log/secure`（rsyslog 写入）+ journald | [F2](02-systemd-journald.md) |
| 时间同步 | systemd-timesyncd | **chronyd**（`/etc/chrony.conf`、`chronyc sources`） | [RHCSA-06](../rhcsa/06-software-scheduling-boot.md) |
| Web 服务包名 | `apache2`，配置在 `/etc/apache2` | `httpd`，配置在 `/etc/httpd` | — |
| SSH 服务名 | `ssh.service` | `sshd.service` | — |
| 引导配置 | `update-grub` | `grubby`（推荐）或 `grub2-mkconfig -o ...` | [RHCSA-06](../rhcsa/06-software-scheduling-boot.md) |
| 容器 | docker（守护进程） | **podman**（无守护进程，可 rootless） | [F5](05-containers-docker-to-k8s.md) |
| Web 管理界面 | 无 | Cockpit（`https://主机:9090`） | — |

### 2.2 RHEL 特有的「订阅」概念

- RHEL 的软件仓库需要**注册订阅**才能用：`subscription-manager register`。
- 个人学习用 **Red Hat Developer Subscription for Individuals**（免费，最多 16 台），在 developers.redhat.com 注册即可。
- 替代方案：Rocky Linux / AlmaLinux（与 RHEL 二进制兼容，不需要订阅），但考试环境是正版 RHEL，细节以 RHEL 为准。
- **考试环境没有外网、不需要注册订阅**：题目会给你一个内网的 BaseOS/AppStream 仓库 URL，让你自己写 `.repo` 文件。

### 2.3 RHEL 10 需要注意的硬件要求

- RHEL 10（x86_64）要求 CPU 支持 **x86-64-v3** 指令集（大致相当于支持 AVX2 的 CPU）。
- 虚拟机里装不上或启动后崩溃，多半是虚拟 CPU 没把指令集透传：KVM/libvirt 用 `host-passthrough` CPU 模式；VirtualBox / VMware 请确认 CPU 特性透传（以官方说明为准）。
- 实验环境搭建见 [`labs/rhcsa/00-lab-setup.md`](../../labs/rhcsa/00-lab-setup.md)。

## 3. 必会操作

```bash
# —— 订阅与仓库（自己练习环境用；考场不需要）——
sudo subscription-manager register --username <你的账号>   # 注册到开发者订阅
sudo subscription-manager status                            # 查看订阅状态
dnf repolist                                                # 列出已启用仓库，应看到 baseos / appstream

# —— Ubuntu 习惯 → RHEL 写法 ——
sudo dnf install -y vim-enhanced bash-completion            # apt install
dnf search nginx                                            # apt search
dnf info httpd                                              # apt show
rpm -qa | grep kernel                                       # dpkg -l | grep kernel
rpm -ql chrony                                              # dpkg -L chrony
rpm -qf /etc/chrony.conf                                    # dpkg -S /etc/chrony.conf
dnf provides '*/semanage'                                   # 找不到命令时：查哪个包提供它
sudo dnf upgrade -y                                         # apt update && apt upgrade

# —— 系统信息 ——
cat /etc/redhat-release                                     # 看版本（Ubuntu 是 /etc/os-release / lsb_release）
hostnamectl                                                 # 主机名、内核、架构
uname -r                                                    # 内核版本

# —— 四大差异点的“健康检查” ——
getenforce                                                  # 应输出 Enforcing
sudo firewall-cmd --state && sudo firewall-cmd --list-all   # firewalld 是否运行、当前 zone 规则
nmcli connection show                                       # NetworkManager 管理的连接
systemctl is-active chronyd                                 # 时间同步服务
```

## 4. 考试坑点

- **把 Ubuntu 肌肉记忆带进考场**：`apt`、`ufw`、`netplan apply`、`update-grub` 在 RHEL 上都不存在，或者不是正确做法。
- **为了省事关掉 SELinux / firewalld**：考试的评分脚本会检查 SELinux 是否 Enforcing、服务是否能在防火墙开启时访问。关了就等于题目没做。
- **直接改 `/etc/resolv.conf` 或网卡配置文件**：NetworkManager 会覆盖。网络一律用 `nmcli` 改（见 [RHCSA-07](../rhcsa/07-networking-nmcli.md)）。
- **XFS 不能缩小**：题目要求「缩小逻辑卷」时，那一定是 ext4；XFS 只能扩容（`xfs_growfs`）。
- **管理员组写成 `sudo`**：RHEL 是 `wheel`。
- 所有配置都要**重启后仍然生效**——这是红帽考试的通用规则，每做完一题都要想「重启后还在吗？」。

## 5. 动手练习

- 搭建 RHEL 实验环境：[`labs/rhcsa/00-lab-setup.md`](../../labs/rhcsa/00-lab-setup.md)
- 装好后，把上面「必会操作」整块敲一遍，并用对照表里每一行在 RHEL 上各做一次。
- 第一套练习题：[`labs/rhcsa/practice-set-1.md`](../../labs/rhcsa/practice-set-1.md)

## 6. 官方文档（本仓库离线版 + 考场可用的查法）

RHEL 手册不在仓库里（生成仓库时 docs.redhat.com 无法访问），可在本机运行 [`scripts/fetch-rhel-docs.sh`](../../scripts/fetch-rhel-docs.sh) 下载 PDF，或在线阅读：

- [RHEL 10 文档首页](https://docs.redhat.com/en/documentation/red_hat_enterprise_linux/10)
- [Considerations in adopting RHEL 10](https://docs.redhat.com/en/documentation/red_hat_enterprise_linux/10/html-single/considerations_in_adopting_rhel_10/index)（RHEL 9 → 10 的变化汇总，链接以官网为准）
- [Managing software with the DNF tool](https://docs.redhat.com/en/documentation/red_hat_enterprise_linux/10/html-single/managing_software_with_the_dnf_tool/index)
- [Configuring and managing networking](https://docs.redhat.com/en/documentation/red_hat_enterprise_linux/10/html-single/configuring_and_managing_networking/index)
- [Using SELinux](https://docs.redhat.com/en/documentation/red_hat_enterprise_linux/10/html-single/using_selinux/index)

考场里只有本地文档，养成这些查法：

```bash
man -k firewall          # 按关键词搜索 man 页（等同 apropos）；搜不到先 sudo mandb
man dnf                  # dnf 全部子命令
man 5 dnf.conf           # .repo 文件 / dnf.conf 里的配置项（第 5 节 = 配置文件格式）
man nmcli-examples       # nmcli 的现成示例，考场救命用
ls /usr/share/doc/       # 各软件包自带的示例配置
```

## 7. 自测清单

- [ ] 不看笔记，能把对照表里「Ubuntu 列」的 10 个操作翻译成 RHEL 命令
- [ ] 能说出 BaseOS 和 AppStream 两个仓库的区别（系统核心包 vs 应用/语言运行时/模块）
- [ ] 能解释为什么考试中不能 `setenforce 0`、不能 `systemctl stop firewalld`
- [ ] 能在没有网络的情况下，用 `man -k` / `man 5` 找到一个配置文件的格式说明
- [ ] 已经有一台能 `dnf install` 的 RHEL 10（或 Rocky/Alma 10）虚拟机
