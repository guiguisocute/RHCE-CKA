# RHCSA-08 用户、组、密码策略与 sudo

> **轨道**：[RHCSA](README.md) ｜ **考纲**：EX200「Manage users and groups」 ｜ **建议用时**：4 h ｜ **难度**：★☆☆
>
> **前置**：[S1 基础工具](01-essential-tools.md)
> **后续**：[S9 防火墙与 SELinux](09-security-firewalld-selinux.md)（umask、SSH 密钥） · [S5 SGID 协作目录](05-file-systems-nfs-autofs.md)
> **关联**（跨轨道）：[RHCE-11 自动化 RHCSA 任务](../rhce/11-automate-rhcsa-tasks.md)（`ansible.builtin.user`/`group`、`password_hash` 过滤器） · [RHCE-02 Inventory 与 ansible.cfg](../rhce/02-inventory-and-config.md)（被控节点上的 sudo 免密配置） · [CKA-06 RBAC](../cka/06-rbac.md)（K8s 没有「用户对象」，权限模型和 Linux 组/sudo 对照理解）

## 1. 这个知识点在网络中的位置

用户管理是 EX200 里最「送分」的一块，但细节多：UID、附加组、nologin shell、密码过期策略、sudo 规则。RHCE 第一步就是在所有被控节点上建好 Ansible 用户并配置 **sudo 免密**——这里学的 sudoers 写法会被直接复用。

Ubuntu 对照：

| Ubuntu | RHEL |
|---|---|
| `adduser`（交互式 Perl 脚本）/ `useradd` | 只用 `useradd`（RHEL 的 `adduser` 是 `useradd` 的软链接，非交互） |
| 管理员组 `sudo` | 管理员组 **`wheel`** |
| `useradd` 默认不建家目录 | `useradd` 默认**创建**家目录（`/etc/login.defs` 中 `CREATE_HOME yes`） |
| 普通用户 UID 从 1000 起 | 同样 1000 起（`/etc/login.defs` 的 `UID_MIN`） |

## 2. 核心概念

| 文件 | 内容 |
|---|---|
| `/etc/passwd` | `用户名:x:UID:GID:注释:家目录:shell` |
| `/etc/shadow` | 密码哈希 + 密码策略（最后修改日、最短/最长有效期、警告天数、过期日） |
| `/etc/group` | `组名:x:GID:成员列表`（这里列的是**附加组**成员） |
| `/etc/login.defs` | 新用户默认值：`PASS_MAX_DAYS`、`PASS_MIN_DAYS`、`PASS_WARN_AGE`、`UID_MIN`、`UMASK` 等 |
| `/etc/skel/` | 新建家目录的模板文件 |
| `/etc/sudoers`、`/etc/sudoers.d/` | sudo 规则；**永远用 `visudo` 编辑**（会做语法检查） |

主组（primary group）vs 附加组（supplementary groups）：主组在 passwd 第 4 列，新建文件默认属于主组；附加组决定额外权限。

## 3. 必会操作

```bash
# ---------- 用户 ----------
useradd alice                                 # 默认：建家目录、主组 alice
useradd -u 2001 -G wheel,devteam -c "Bob Lee" bob      # 指定 UID、附加组、注释
useradd -s /sbin/nologin svcuser              # 不能登录 shell 的服务账号
useradd -d /home/remote/ruser1 -M ruser1      # 指定家目录且不创建（autofs 场景）
usermod -aG devteam alice                     # 追加附加组（-a 必须有！）
usermod -s /bin/bash svcuser; usermod -L alice / -U alice   # 改 shell；锁定/解锁
userdel -r bob                                # 连家目录一起删
id alice; groups alice

# ---------- 密码 ----------
passwd alice                                  # 交互设置
echo 'redhat' | passwd --stdin alice          # RHEL 特有的非交互写法
echo 'alice:redhat' | chpasswd                # 通用写法

# ---------- 密码策略 ----------
chage -l alice                                # 查看
chage -M 90 -m 7 -W 14 alice                  # 最长 90 天、最短 7 天、提前 14 天警告
chage -E 2026-12-31 alice                     # 账号过期日
chage -d 0 alice                              # 强制下次登录修改密码
vim /etc/login.defs                           # PASS_MAX_DAYS 60 ——只影响之后新建的用户！

# ---------- 组 ----------
groupadd -g 3000 devteam
groupmod -n developers devteam                # 改名
gpasswd -d alice developers                   # 从组里移除用户
groupdel developers

# ---------- sudo ----------
usermod -aG wheel alice                       # 加入 wheel = 完整 sudo 权限（需输入自己的密码）
visudo -f /etc/sudoers.d/devteam              # 推荐：独立文件，便于管理
#   %devteam  ALL=(ALL)  /usr/bin/systemctl restart httpd, /usr/bin/dnf
#   ansible   ALL=(ALL)  NOPASSWD: ALL               ← RHCE 被控节点的标准配置
visudo -c                                     # 检查所有 sudoers 文件语法
sudo -l -U alice                              # 列出 alice 能执行的 sudo 命令
```

## 4. 考试坑点

- **`usermod -G` 不加 `-a` 会覆盖**原有附加组——最经典的失分点。
- 改 `/etc/login.defs` 只影响**之后**创建的用户，已有用户要用 `chage` 单独改。题目可能同时要求两者。
- 题目给的 UID/GID 要精确，`id` 验证。
- `nologin` 用户：`/sbin/nologin`（RHEL 上 `/usr/sbin/nologin` 也存在，二者是同一文件）。
- sudoers 文件写错会导致**所有人**都用不了 sudo：只用 `visudo`；`/etc/sudoers.d/` 下的文件名不要带 `.` 或以 `~` 结尾（会被忽略）。
- 题目要求「alice 不需要密码就能 sudo」→ `NOPASSWD:`，注意冒号。
- 密码题通常会给定明文密码，设置完用 `su - alice` 试登录一次。

## 5. 动手练习

- [练习题集 · S8 用户、组与 sudo](../../labs/rhcsa/practice-set-1.md#s8)

## 6. 官方文档（本仓库离线版 + 考场可用的查法）

- 用户与组管理在 RHEL 9 属于《Configuring basic system settings》，RHEL 10 的章节位置请在文档首页搜索 "Managing users and groups"：<https://docs.redhat.com/en/documentation/red_hat_enterprise_linux/10>
- 离线 PDF：运行 [`scripts/fetch-rhel-docs.sh`](../../scripts/fetch-rhel-docs.sh)
- **考场查法**：
  - `man useradd`、`man usermod`（`/-a, --append`）、`man chage`
  - `man 5 login.defs`、`man 5 passwd`、`man 5 shadow`（每个字段含义）
  - `man 5 sudoers` → `/EXAMPLES`（规则写法，含 `NOPASSWD`、`%group`、命令别名）
  - `cat /etc/sudoers`：自带的注释里就有 `%wheel` 和 `NOPASSWD` 示例，照抄最快

## 7. 自测清单

- [ ] 能创建指定 UID、附加组、nologin shell 的用户
- [ ] 能在不丢失原有附加组的前提下给用户追加组
- [ ] 能设置密码最长有效期、账号过期日，并强制首次登录改密码
- [ ] 能让新建用户默认密码有效期为 60 天
- [ ] 能给某个组配置「只能执行某几条命令」的 sudo 规则，以及给某个用户配置免密 sudo
- [ ] 能读懂 `/etc/shadow` 中一行的每个字段
