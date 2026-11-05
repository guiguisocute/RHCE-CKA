# RHCSA-09 安全：firewalld、SELinux、umask 与 SSH 密钥认证

> **轨道**：[RHCSA](README.md) ｜ **考纲**：EX200「Manage security」（+「Manage basic networking」中的防火墙部分） ｜ **建议用时**：10 h ｜ **难度**：★★★
>
> **前置**：[S7 网络配置 nmcli](07-networking-nmcli.md) · [S8 用户、组与 sudo](08-users-groups-sudo.md)
> **后续**：[S10 Podman 容器](10-containers-podman.md)（容器卷的 `:Z` 就是 SELinux 上下文） · [RHCE-11 用 Ansible 自动化 RHCSA 任务](../rhce/11-automate-rhcsa-tasks.md)
> **关联**（跨轨道）：[RHCE-12 RHEL System Roles](../rhce/12-rhel-system-roles.md)（selinux / firewall 角色） · [CKA-03 用 kubeadm 搭建集群](../cka/03-kubeadm-install.md)（控制平面端口 6443/2379-2380/10250 要放行） · [CKA-12 NetworkPolicy](../cka/12-network-policy.md)（Pod 级别的「防火墙」）

## 1. 这个知识点在网络中的位置

**SELinux 是从 Ubuntu 转过来最大的门槛**，也是 EX200 里最容易「做了但不得分」的部分：服务明明起来了，网页却 403；换了端口，服务直接起不来。规律只有一条：**ugo 权限、firewalld、SELinux 三道门都要过**。

Ubuntu 对照：

| Ubuntu | RHEL |
|---|---|
| ufw（默认未启用） | **firewalld**（默认启用，只放行 ssh、cockpit、dhcpv6-client 等少数服务） |
| AppArmor（按程序路径限制） | **SELinux**（按标签/上下文限制，默认 `enforcing`） |
| `ufw allow 80/tcp` | `firewall-cmd --permanent --add-port=80/tcp && firewall-cmd --reload` |

## 2. 核心概念

### firewalld

| 概念 | 说明 |
|---|---|
| zone | 一组规则；网卡/源地址归属某个 zone。默认 zone 通常是 `public` |
| service | 预定义的端口集合（`/usr/lib/firewalld/services/*.xml`），如 `http`、`nfs` |
| runtime vs permanent | 不加 `--permanent` 只改运行时（重启丢失）；加了只改永久配置（需 `--reload` 才生效）。**考试标准写法：`--permanent` + `--reload`** |
| rich rule | 更复杂的规则，如「只允许某网段访问某端口」 |

### SELinux

| 概念 | 说明 |
|---|---|
| 模式 | `enforcing`（强制）、`permissive`（只记录不拦截）、`disabled`。`getenforce`/`setenforce 0|1` 改运行时；`/etc/selinux/config` 改持久 |
| 上下文（context） | `user:role:type:level`，考试只关心 **type**，如 `httpd_sys_content_t`。`ls -Z` 看文件，`ps -eZ` 看进程 |
| 类型强制 | 进程（如 `httpd_t`）只能访问策略允许的文件类型 |
| 文件上下文规则 | `semanage fcontext` 定义「某路径应该是什么类型」（持久）；`restorecon` 按规则**应用**到文件 |
| 端口标签 | `semanage port` 定义某端口属于哪个类型（如 `http_port_t`），服务改非标准端口时必须加 |
| 布尔值 | 策略开关，如 `httpd_enable_homedirs`；`setsebool -P` 持久 |
| 排错 | 拒绝记录在 `/var/log/audit/audit.log`（AVC）；`sealert` 会给出修复建议 |

> `chcon` 也能改上下文，但**不持久**（`restorecon` 或 relabel 后会被覆盖）。考试一律用 `semanage fcontext` + `restorecon`。

## 3. 必会操作

### 3.1 firewalld

```bash
systemctl enable --now firewalld
firewall-cmd --get-default-zone; firewall-cmd --get-active-zones
firewall-cmd --list-all                       # 当前默认 zone 的所有规则
firewall-cmd --get-services | tr ' ' '\n' | grep -i http
firewall-cmd --permanent --add-service=http --add-service=https
firewall-cmd --permanent --add-port=8080/tcp
firewall-cmd --permanent --remove-service=cockpit
firewall-cmd --permanent --add-rich-rule='rule family="ipv4" source address="192.168.122.0/24" port port="5432" protocol="tcp" accept'
firewall-cmd --permanent --zone=trusted --add-source=10.0.0.0/8
firewall-cmd --reload                         # 让 permanent 配置生效
firewall-cmd --list-all                       # 验证
```

### 3.2 SELinux 模式

```bash
getenforce; sestatus
setenforce 0                                  # 临时 permissive（排错用）
vim /etc/selinux/config                       # SELINUX=enforcing|permissive —— 持久
# 注意：RHEL 9 起在配置文件里写 SELINUX=disabled 不能完全禁用，需要内核参数：
#   grubby --update-kernel=ALL --args="selinux=0"（考试几乎不会要求禁用）
```

### 3.3 文件上下文（最常考：Web 根目录换位置）

```bash
dnf install -y policycoreutils-python-utils   # 提供 semanage（考场若缺命令：dnf provides '*/semanage'）
ls -Zd /var/www/html                          # 参考：标准目录的类型
mkdir -p /web && echo hello > /web/index.html
semanage fcontext -a -t httpd_sys_content_t '/web(/.*)?'   # 定义规则（持久）
restorecon -Rv /web                           # 应用规则
ls -Z /web
semanage fcontext -l | grep '^/web'           # 查看自定义规则
# 文件被 mv 进来后上下文不对？ restorecon -Rv <目录> 即可恢复默认
```

### 3.4 端口标签

```bash
semanage port -l | grep http_port_t           # 默认允许 httpd 监听的端口
semanage port -a -t http_port_t -p tcp 82     # 允许 httpd 使用 82 端口
semanage port -m -t http_port_t -p tcp 82     # 端口已被别的类型占用时用 -m 修改
# 别忘了防火墙：firewall-cmd --permanent --add-port=82/tcp && firewall-cmd --reload
```

### 3.5 布尔值

```bash
getsebool -a | grep httpd                     # 列出相关布尔值
semanage boolean -l | grep homedirs           # 带说明
setsebool -P httpd_enable_homedirs on         # -P 持久！
```

### 3.6 排错

```bash
ausearch -m AVC -ts recent                    # 最近的拒绝记录
grep AVC /var/log/audit/audit.log | tail
dnf install -y setroubleshoot-server && sealert -a /var/log/audit/audit.log   # 给出修复命令建议
journalctl -t setroubleshoot --since "10 min ago"
```

### 3.7 umask（默认文件权限）

```bash
umask                                         # 通常 0022 → 新文件 644、新目录 755
umask 027                                     # 当前 shell 生效
echo 'umask 027' >> /home/alice/.bashrc       # 只对 alice 持久
# 系统级默认值来自 /etc/login.defs 的 UMASK 以及 /etc/profile、/etc/bashrc；
# 全局自定义推荐放 /etc/profile.d/umask.sh（以 RHEL 10 实际文件为准）
```

### 3.8 SSH 密钥认证

```bash
ssh-keygen -t ed25519 -N '' -f ~/.ssh/id_ed25519   # 无密码短语生成
ssh-copy-id alice@serverb                     # 推送公钥 → ~/.ssh/authorized_keys
ssh alice@serverb                             # 不再询问密码即成功
# 权限要求：~/.ssh 700，authorized_keys 600，否则 sshd 拒绝使用
vim /etc/ssh/sshd_config.d/50-exam.conf       # 推荐用 drop-in 文件改 sshd 配置
#   PasswordAuthentication no
#   PermitRootLogin prohibit-password          ← RHEL 9 起默认就禁止 root 用密码登录
sshd -t && systemctl reload sshd              # 先检查语法再重载
```

## 4. 考试坑点

- **firewalld 只加 `--permanent` 不 `--reload`** → 当前不生效；**不加 `--permanent`** → 重启丢失。
- **`setsebool` 忘记 `-P`** → 重启丢失。
- **用 `chcon` 而不是 `semanage fcontext`** → relabel 后丢失。
- `semanage fcontext` 的路径正则要写 `'/web(/.*)?'`（带引号），否则只匹配目录本身。
- 服务改端口三件套：**服务配置 + `semanage port` + 防火墙**，缺一不可；`systemctl status` 报 "Permission denied" 绑定端口，几乎一定是 SELinux 端口标签。
- 题目说「SELinux 必须保持 enforcing」时，排错可以临时 `setenforce 0` 验证是不是 SELinux 的问题，**但最后一定要改回 1**。
- 重置 root 密码后忘了 relabel，也是 SELinux 问题（见 [S3](03-operate-running-systems.md)）。

## 5. 动手练习

- [练习题集 · S9 防火墙与 SELinux](../../labs/rhcsa/practice-set-1.md#s9)

## 6. 官方文档（本仓库离线版 + 考场可用的查法）

- RHEL 10《Using SELinux》：<https://docs.redhat.com/en/documentation/red_hat_enterprise_linux/10/html-single/using_selinux/index>
- RHEL 10《Configuring firewalls and packet filters》：<https://docs.redhat.com/en/documentation/red_hat_enterprise_linux/10/html-single/configuring_firewalls_and_packet_filters/index>
- SSH 加固等内容可在 RHEL 10 文档首页搜索：<https://docs.redhat.com/en/documentation/red_hat_enterprise_linux/10>
- 离线 PDF：运行 [`scripts/fetch-rhel-docs.sh`](../../scripts/fetch-rhel-docs.sh)
- **考场查法**：
  - `man semanage-fcontext` → `/EXAMPLES`：**直接给出 `'/web(/.*)?'` 这种写法**
  - `man semanage-port` → `/EXAMPLES`、`man semanage-boolean`
  - `man restorecon`、`man setsebool`、`man 8 httpd_selinux`（若安装了 `selinux-policy-doc`，每个服务都有对应的 `*_selinux` 手册，列出所需类型和布尔值）
  - `man firewall-cmd` → `/Examples`、`man firewalld.richlanguage`（rich rule 语法）
  - `man ssh-keygen`、`man 5 sshd_config`

## 7. 自测清单

- [ ] 能用 `--permanent` + `--reload` 放行服务/端口，并用 `--list-all` 验证
- [ ] 能写一条只允许某网段访问某端口的 rich rule
- [ ] 能把 Web 根目录换到 `/web` 并让 httpd 在 enforcing 下正常访问
- [ ] 能让 httpd 监听 82 端口（SELinux + 防火墙 + 服务配置）
- [ ] 能用 `ausearch`/`sealert` 找出一条 AVC 拒绝的原因并修复
- [ ] 能为某用户持久设置 umask 027 并验证新文件权限
- [ ] 能配置 SSH 密钥登录，并说出 `~/.ssh` 和 `authorized_keys` 的权限要求
