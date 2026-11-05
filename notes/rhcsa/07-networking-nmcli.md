# RHCSA-07 网络配置：nmcli、IPv4/IPv6、主机名解析

> **轨道**：[RHCSA](README.md) ｜ **考纲**：EX200「Manage basic networking」 ｜ **建议用时**：5 h ｜ **难度**：★★☆
>
> **前置**：[S1 基础工具](01-essential-tools.md) · [F3 网络基础](../00-foundations/03-networking-basics.md)
> **后续**：[S9 防火墙与 SELinux](09-security-firewalld-selinux.md)
> **关联**（跨轨道）：[CKA-11 Service 与 CoreDNS](../cka/11-services-dns.md)（`/etc/resolv.conf`、DNS 解析顺序同样适用于 Pod） · [RHCE-12 RHEL System Roles](../rhce/12-rhel-system-roles.md)（network 角色） · [S5 NFS / autofs](05-file-systems-nfs-autofs.md)

## 1. 这个知识点在网络中的位置

EX200 的网络题通常是第一批题：**给某台机器配置静态 IP、网关、DNS、主机名**——配错了，后面需要访问仓库/NFS 的题全部失败。所以要求「一次配对、重启不丢」。

Ubuntu 对照（这是你最需要转换思路的地方）：

| Ubuntu（Server） | RHEL |
|---|---|
| netplan（`/etc/netplan/*.yaml`）+ systemd-networkd | **NetworkManager**，命令行工具 `nmcli`，文本界面 `nmtui` |
| `netplan apply` | `nmcli connection up <连接名>` |
| `/etc/netplan/` | `/etc/NetworkManager/system-connections/*.nmconnection`（keyfile 格式） |
| — | 老的 `/etc/sysconfig/network-scripts/ifcfg-*` 在 RHEL 9 已不是默认格式；RHEL 10 不再支持 ifcfg（据发行说明，以官方为准） |

## 2. 核心概念

| 概念 | 说明 |
|---|---|
| device（设备） | 网卡，如 `enp1s0`、`eth0`；`nmcli device status` 查看 |
| connection（连接） | 一份配置（IP、网关、DNS…），绑定到某个设备。**一个设备可以有多个连接，但同一时间只激活一个** |
| `ipv4.method` | `auto`（DHCP）、`manual`（静态）、`disabled` |
| `ipv6.method` | `auto`（SLAAC/DHCPv6）、`manual`、`ignore`/`disabled` |
| `connection.autoconnect` | `yes` = 开机自动激活（考纲：Configure network services to start automatically at boot） |
| 主机名 | `hostnamectl set-hostname`，写入 `/etc/hostname` |
| 解析顺序 | `/etc/nsswitch.conf` 的 `hosts:` 行（默认先 `files` 即 `/etc/hosts`，再 `dns`）；DNS 服务器由 NM 写入 `/etc/resolv.conf` |

## 3. 必会操作

```bash
# ---------- 查看 ----------
nmcli device status                           # 设备与连接对应关系
nmcli connection show                         # 所有连接（NAME 一列就是后面命令用的连接名）
nmcli connection show "Wired connection 1" | grep -E 'ipv4|ipv6|autoconnect'
ip -br addr; ip route; cat /etc/resolv.conf

# ---------- 修改已有连接为静态 IPv4 + IPv6 ----------
CON="Wired connection 1"                      # 以实际连接名为准，可能叫 enp1s0 / eth0
nmcli connection modify "$CON" \
  ipv4.method manual \
  ipv4.addresses 192.168.122.10/24 \
  ipv4.gateway 192.168.122.1 \
  ipv4.dns "192.168.122.1 8.8.8.8" \
  ipv6.method manual \
  ipv6.addresses fd00:122::10/64 \
  connection.autoconnect yes
nmcli connection up "$CON"                    # 让配置生效（远程 ssh 时会短暂断开，IP 变了要用新 IP 重连）

# ---------- 新建连接 ----------
nmcli connection add type ethernet con-name static-eth1 ifname eth1 \
  ipv4.method manual ipv4.addresses 10.0.0.5/24 ipv4.gateway 10.0.0.1 ipv4.dns 10.0.0.1
nmcli connection up static-eth1

# 追加第二个 IP（用 + 号，不覆盖原有）
nmcli connection modify "$CON" +ipv4.addresses 192.168.122.110/24

# ---------- 主机名与解析 ----------
hostnamectl set-hostname servera.lab.example.com
hostnamectl                                   # 验证（/etc/hostname 已被写入）
echo '192.168.122.11  serverb.lab.example.com  serverb' >> /etc/hosts
getent hosts serverb                          # 按 nsswitch 顺序解析（比 ping 更能说明问题）
dig serverb.lab.example.com                   # 只查 DNS（包 bind-utils）

# ---------- 文本界面（不熟悉参数时的保底方案） ----------
nmtui                                         # 图形化菜单编辑连接，改完记得在菜单里 Activate

# ---------- 配置文件位置 ----------
ls /etc/NetworkManager/system-connections/
cat "/etc/NetworkManager/system-connections/$CON.nmconnection"   # 只读查看；直接改文件后需 nmcli connection reload
```

## 4. 考试坑点

- **`nmcli connection modify` 只改配置，不会立即生效**，必须 `nmcli connection up`（或重启）。
- **连接名 ≠ 设备名**：先 `nmcli con show` 确认 NAME 列，带空格的名字要加引号。
- 同一设备上有多个连接时，确认 `autoconnect` 只在你要的那个上为 `yes`，否则重启后可能激活了别的连接。
- `ipv4.addresses` 必须带前缀长度（`/24`）；漏写会被当成 `/32`。
- 考试通常通过控制台（console）操作网络题，**不要在 ssh 会话里随手 `down` 掉唯一的连接**。
- 改主机名后，提示符要重新登录才会变；评分看的是 `hostnamectl`/`/etc/hostname`。
- 配置 IPv6 后用 `ping -6` / `ip -6 addr` 验证。

## 5. 动手练习

- [练习题集 · S7 网络配置](../../labs/rhcsa/practice-set-1.md#s7)
- 实验网段与主机规划见 [实验环境搭建](../../labs/rhcsa/00-lab-setup.md)

## 6. 官方文档（本仓库离线版 + 考场可用的查法）

- RHEL 10《Configuring and managing networking》：<https://docs.redhat.com/en/documentation/red_hat_enterprise_linux/10/html-single/configuring_and_managing_networking/index>
- 离线 PDF：运行 [`scripts/fetch-rhel-docs.sh`](../../scripts/fetch-rhel-docs.sh)
- **考场查法**（nmcli 的参数名很长，记不住就查）：
  - `man nmcli-examples`：**最重要**，静态 IP、新建连接、bond、VLAN 的完整示例
  - `man nm-settings`（或 `man nm-settings-nmcli`）→ `/ipv4.method`：所有属性的取值
  - `nmcli connection modify "$CON" ipv4.<Tab><Tab>`：bash 补全直接列出可用属性
  - `man hostnamectl`、`man 5 hosts`、`man 5 nsswitch.conf`、`man 5 resolv.conf`

## 7. 自测清单

- [ ] 能在 2 分钟内把一台 DHCP 的机器改成指定的静态 IPv4（含网关/DNS）并验证
- [ ] 能同时配置一个静态 IPv6 地址
- [ ] 能给同一连接追加第二个 IP
- [ ] 能设置 FQDN 主机名并在 `/etc/hosts` 中添加解析
- [ ] 能解释 device 与 connection 的区别
- [ ] 重启后检查 IP、网关、DNS、主机名全部保持
