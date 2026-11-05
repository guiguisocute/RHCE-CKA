# RHCSA-01 基础工具：Shell、文本处理、SSH、归档、链接与权限

> **轨道**：[RHCSA](README.md) ｜ **考纲**：EX200「Understand and use essential tools」 ｜ **建议用时**：8 h ｜ **难度**：★☆☆
>
> **前置**：[F1 Ubuntu → RHEL 对照](../00-foundations/01-ubuntu-to-rhel.md) · [F7 vim / tmux / 考场效率](../00-foundations/07-vim-tmux-exam-efficiency.md)
> **后续**：[S2 Shell 脚本](02-shell-scripting.md) · [S3 运行中的系统](03-operate-running-systems.md) · [S4 本地存储与 LVM](04-local-storage-lvm.md) · [S7 网络配置](07-networking-nmcli.md) · [S8 用户与 sudo](08-users-groups-sudo.md)
> **关联**（跨轨道）：[RHCE-03 Ad-hoc、模块与 ansible-doc](../rhce/03-adhoc-modules-docs.md)（同样是「考场只能查本地文档」） · [CKA-02 kubectl 高效操作](../cka/02-kubectl-efficiency.md)

## 1. 这个知识点在网络中的位置

这是所有节点的根。你在 Ubuntu 上已经会用 bash、ssh、tar，这里的重点不是「会不会」，而是**在没有搜索引擎的情况下，能不能靠 `man` 和 `/usr/share/doc` 自己查到答案**——这个能力会直接迁移到 RHCE 的 `ansible-doc` 和 CKA 的 `kubectl explain`。

Ubuntu 对照：命令几乎完全一样（都是 GNU coreutils + bash）。差异主要在默认安装的软件包和配置文件位置，见 [F1](../00-foundations/01-ubuntu-to-rhel.md)。

## 2. 核心概念

| 主题 | 要点 |
|---|---|
| 重定向 | `>` 覆盖、`>>` 追加、`2>` 错误输出、`&>` 标准输出+错误、`2>&1`、`|` 管道、`tee` 同时写文件和屏幕 |
| grep / 正则 | 基础正则 `^ $ . * [ ]`；`grep -E` 扩展正则 `+ ? | ()`；`-i -v -n -r -c -o -w` |
| SSH | 密钥登录、`ssh user@host 'cmd'` 远程执行；`scp`、`sftp`、`rsync -av` 安全传文件 |
| 切换用户 | `su -`（登录 shell，加载目标用户环境）vs `su`（不加载）；`sudo -i` 以 root 登录 shell |
| 归档压缩 | `tar` + `-z`(gzip) `-j`(bzip2) `-J`(xz)；`c` 创建 `x` 解压 `t` 列出 `f` 文件名 `v` 详细 `-C` 指定目录 |
| 链接 | 硬链接 `ln a b`：同一 inode，不能跨文件系统、不能链目录；软链接 `ln -s 目标 链接名`：独立 inode，可跨文件系统 |
| 权限 | `u g o` × `r w x`；数字 r=4 w=2 x=1；目录的 `x` = 能进入，`r` = 能列出，`w` = 能增删文件 |
| 特殊权限 | SUID `4`（`u+s`）、SGID `2`（`g+s`，目录上=新文件继承组）、Sticky `1`（`o+t`，/tmp 只能删自己的文件） |
| 文档 | `man`、`man -k`（= `apropos`）、`man 5 文件名`、`info`、`--help`、`/usr/share/doc/<包名>/` |

man 手册章节号（考场查配置文件格式时必用）：

| 章节 | 内容 | 例子 |
|---|---|---|
| 1 | 用户命令 | `man 1 passwd` |
| 5 | 配置文件格式 | `man 5 passwd`、`man 5 fstab`、`man 5 crontab` |
| 8 | 管理员命令 | `man 8 lvcreate`、`man 8 semanage` |

## 3. 必会操作

```bash
# ---------- 重定向与文本处理 ----------
find / -user alice -type f 2>/dev/null > /root/alice-files   # 找 alice 的文件，丢掉报错，结果写文件
grep -E '^(root|alice):' /etc/passwd                          # 扩展正则
grep -v '^#' /etc/ssh/sshd_config | grep -v '^$'               # 去掉注释和空行看有效配置
grep -rn 'Listen' /etc/httpd/conf/                            # 递归搜索并显示行号
ls /nonexist /etc 2>&1 | tee /tmp/out.txt                      # 错误也进管道
find /etc -name '*.conf' -size +10k -mtime -30                # 按名字/大小/修改时间查找
find /usr/share -name '*.txt' -exec cp {} /tmp/txt/ \;        # 对结果执行命令

# ---------- SSH 与文件传输 ----------
ssh-keygen -t ed25519                         # 生成密钥（一路回车）
ssh-copy-id student@serverb                   # 推送公钥
ssh student@serverb 'hostname; uptime'        # 远程执行
scp /etc/hosts student@serverb:/tmp/          # 复制到远端
rsync -av /srv/data/ serverb:/backup/data/    # 增量同步（注意源目录结尾的 / 含义）
sftp student@serverb                          # 交互式传输

# ---------- 归档 ----------
tar -czvf /root/etc-backup.tar.gz /etc        # gzip
tar -cjvf /root/etc-backup.tar.bz2 /etc       # bzip2（RHEL 默认可能需 dnf install bzip2）
tar -tf /root/etc-backup.tar.gz | head        # 只看不解
tar -xzvf /root/etc-backup.tar.gz -C /tmp     # 解到 /tmp
gzip file; gunzip file.gz; bzip2 file; bunzip2 file.bz2

# ---------- 链接 ----------
ln /etc/hosts /root/hosts.hard                # 硬链接（同文件系统）
ln -s /etc/hosts /root/hosts.soft             # 软链接
ls -li /etc/hosts /root/hosts.*               # 对比 inode 号

# ---------- 权限 ----------
chmod 750 /data; chmod u+x,g-w,o= script.sh   # 数字与符号两种写法
chown alice:devs /data/report                 # 改属主属组
chmod 2770 /shared                            # SGID 协作目录（详见 S5）
chmod 1777 /pub                               # sticky
umask                                         # 当前 umask（详见 S9）

# ---------- 查文档（考场救命技能） ----------
man -k partition                              # 按关键字找手册；无结果先 mandb 更新索引
man 5 fstab                                   # 看 fstab 每列含义
man lvcreate   # 进入后输入 /EXAMPLES 跳到示例段，n 下一个匹配
ls /usr/share/doc/ | grep -i chrony           # 软件包自带文档与示例配置
lvcreate --help | less                        # 比 man 更短
```

## 4. 考试坑点

- **`man -k` 返回 "nothing appropriate"**：先以 root 执行 `mandb` 重建索引。
- **`su` 和 `su -` 不一样**：题目说「以 alice 身份执行」时用 `su - alice`，否则环境变量和当前目录是 root 的。
- **tar 绝对路径**：`tar -czf x.tar.gz /etc` 会去掉开头的 `/`（提示 "Removing leading `/'"），解压时注意 `-C` 目标目录。
- **硬链接跨文件系统会失败**：`/boot` 和 `/` 通常是不同文件系统。
- **重定向顺序**：`cmd > file 2>&1` 正确；`cmd 2>&1 > file` 错误输出仍然到屏幕。
- **find 结果写文件时，题目常要求「只要文件名」或「复制保持属性」**：留意 `cp -a` / `cp -p`。
- 题目给的路径、文件名、用户名**一字不差**，评分脚本是机器在检查。

## 5. 动手练习

- [练习题集 · S1 基础工具](../../labs/rhcsa/practice-set-1.md#s1)
- [实验环境搭建](../../labs/rhcsa/00-lab-setup.md)（先把环境搭好）

## 6. 官方文档（本仓库离线版 + 考场可用的查法）

- RHEL 10 文档首页：<https://docs.redhat.com/en/documentation/red_hat_enterprise_linux/10>（基础命令红帽文档写得不多，主要靠 man）
- 离线 PDF：在自己电脑上运行 [`scripts/fetch-rhel-docs.sh`](../../scripts/fetch-rhel-docs.sh)，下载到 `references/rhel/10/`
- **考场查法**：
  - `man bash` → `/REDIRECTION`、`/Pattern Matching`
  - `man 7 regex`（正则语法）、`man grep`、`man find`（`/EXAMPLES`）
  - `man tar`（`/EXAMPLES`）、`man ssh_config`、`man 5 sshd_config`
  - `man chmod`、`man 1 ln`
  - `info coreutils`（coreutils 完整文档，比 man 详细）

## 7. 自测清单

- [ ] 能解释 `2>&1` 放在 `>` 前后的区别
- [ ] 能用一条 `find` 找出某用户的所有文件并复制到目录且保持属性
- [ ] 能用 `grep -E` 写出匹配「以数字开头、以 .conf 结尾」的正则
- [ ] 能用 `tar` 创建 gzip/bzip2 归档、列出内容、解压到指定目录
- [ ] 能说清楚硬链接和软链接在 inode、跨文件系统、删除源文件后的表现差异
- [ ] 能把 `rwxr-s---` 换算成数字权限（2750）
- [ ] 遇到不会的命令，能 3 分钟内通过 `man -k` / `man` 的 EXAMPLES 段 / `/usr/share/doc` 找到用法
