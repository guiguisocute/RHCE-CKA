# RHCSA-05 文件系统：vfat/ext4/xfs、NFS、autofs、SGID 协作目录与权限排错

> **轨道**：[RHCSA](README.md) ｜ **考纲**：EX200「Create and configure file systems」 ｜ **建议用时**：6 h ｜ **难度**：★★☆
>
> **前置**：[S4 本地存储与 LVM](04-local-storage-lvm.md) · [S8 用户、组与 sudo](08-users-groups-sudo.md)（SGID 目录需要组）
> **后续**：[S9 防火墙与 SELinux](09-security-firewalld-selinux.md)（NFS 要放行防火墙、文件要有正确的 SELinux 上下文）
> **关联**（跨轨道）：[CKA-14 存储](../cka/14-storage.md)（NFS 是 K8s PV 最常见的练习后端） · [RHCE-11 自动化 RHCSA 任务](../rhce/11-automate-rhcsa-tasks.md)（`ansible.posix.mount`、`community.general.filesystem`）

## 1. 这个知识点在网络中的位置

S4 解决「块设备从哪来」，S5 解决「在块设备上建什么文件系统、怎么挂载、多人怎么协作」。其中 **autofs** 是 EX200 的经典题：「用户 remoteuserX 登录时，自动把 NFS 上的家目录挂到 /home/remote/remoteuserX」。

Ubuntu 对照：Ubuntu 也有 `autofs` 包和 `nfs-common`；RHEL 的 NFS 客户端包叫 `nfs-utils`。RHEL 默认 XFS，Ubuntu 默认 ext4。

## 2. 核心概念

| 文件系统 | 创建 | 改标签 | 扩容 | 备注 |
|---|---|---|---|---|
| XFS | `mkfs.xfs` | `xfs_admin -L lbl`（需卸载） | `xfs_growfs 挂载点` | RHEL 默认；不能缩小 |
| ext4 | `mkfs.ext4` | `e2label dev lbl` | `resize2fs dev` | 可缩小（需卸载） |
| vfat | `mkfs.vfat`（包 `dosfstools`） | `fatlabel` | — | U 盘/EFI 分区；不支持 Linux 权限，用挂载选项 `uid= gid= umask=` 控制 |

| 主题 | 要点 |
|---|---|
| NFS 挂载 | `mount -t nfs server:/export /mnt/x`；fstab 选项建议加 `_netdev`（网络就绪后再挂） |
| autofs | 按需挂载：访问目录时才挂，空闲后自动卸载。主配置 `/etc/auto.master` + `/etc/auto.master.d/*.autofs`，映射文件如 `/etc/auto.xxx` |
| 直接映射 vs 间接映射 | 间接：`/home/remote  /etc/auto.remote`（挂到 `/home/remote/<key>`）；直接：`/-  /etc/auto.direct`（映射文件里写绝对路径） |
| 通配符 | 映射文件中 `*  -rw  server:/home/&`，`&` 会被替换为访问的 key（用户名） |
| SGID 目录 | `chmod g+s dir`：目录里新建的文件自动继承目录的属组，团队协作必备 |
| 权限排错 | 依次检查：ugo 权限 → 每层父目录的 `x` → ACL（`getfacl`） → SELinux 上下文（`ls -Z`） |

## 3. 必会操作

```bash
# ---------- 三种文件系统 ----------
mkfs.xfs  -L DATA  /dev/vg_data/lv_data
mkfs.ext4 -L BACKUP /dev/vdb3
dnf install -y dosfstools && mkfs.vfat -n USB /dev/vdb4
# 按 LABEL 持久挂载（考纲：mount by UUID or label）
echo 'LABEL=BACKUP  /backup  ext4  defaults  0 0' >> /etc/fstab
echo 'UUID=xxxx-xxxx  /mnt/usb  vfat  defaults,uid=alice,umask=022  0 0' >> /etc/fstab
systemctl daemon-reload && mount -a && df -hT

# ---------- NFS 客户端 ----------
dnf install -y nfs-utils
showmount -e serverb                          # 列出服务器导出的目录（需服务器放行 mountd/rpc-bind）
mkdir -p /mnt/share
mount -t nfs serverb:/exports/share /mnt/share
echo 'serverb:/exports/share  /mnt/share  nfs  defaults,_netdev  0 0' >> /etc/fstab

# ---------- NFS 服务端（练习环境用，考试一般已提供） ----------
dnf install -y nfs-utils && mkdir -p /exports/share /exports/home
echo '/exports/share  *(rw,sync)' >> /etc/exports
echo '/exports/home   192.168.122.0/24(rw,sync)' >> /etc/exports
systemctl enable --now nfs-server && exportfs -rav
firewall-cmd --permanent --add-service={nfs,mountd,rpc-bind} && firewall-cmd --reload

# ---------- autofs：间接映射 + 通配符 ----------
dnf install -y autofs nfs-utils
cat > /etc/auto.master.d/remote.autofs <<'EOF'
/home/remote  /etc/auto.remote
EOF
cat > /etc/auto.remote <<'EOF'
*  -rw,sync  serverb:/exports/home/&
EOF
systemctl enable --now autofs                 # 改了配置用 systemctl restart autofs
ls /home/remote/remoteuser1                   # 访问即触发挂载（ls /home/remote 本身看不到子目录是正常的）
mount | grep remote

# ---------- autofs：直接映射 ----------
echo '/-  /etc/auto.direct' > /etc/auto.master.d/direct.autofs
echo '/mnt/docs  -ro  serverb:/exports/share' > /etc/auto.direct
systemctl restart autofs

# ---------- SGID 协作目录 ----------
groupadd devteam
mkdir -p /srv/devteam
chgrp devteam /srv/devteam
chmod 2770 /srv/devteam                       # rwxrws---：组成员可读写，其他人无权；新文件属组=devteam
ls -ld /srv/devteam

# ---------- ACL（权限排错时会遇到） ----------
setfacl -m u:alice:rw /srv/report.txt         # 给单个用户额外权限
setfacl -m d:g:devteam:rwx /srv/devteam       # 默认 ACL：目录下新文件自动继承
getfacl /srv/report.txt
setfacl -b /srv/report.txt                    # 清除所有 ACL
```

## 4. 考试坑点

- **autofs 题最常见的错误**：
  - 映射文件里服务器路径写错（先用 `showmount -e` 和手动 `mount` 验证一遍）；
  - 忘记 `systemctl enable autofs`，重启后失效；
  - 题目要求挂载点目录**不需要提前创建**，autofs 会自己创建（提前创建一般也无害）；
  - 用户的家目录在 autofs 下时，`useradd -d /home/remote/remoteuser1 -M` 指定家目录且不自动创建。
- **NFS 写进 fstab 却没有 `_netdev`**，在部分环境下引导时会卡住或挂载失败。
- **SGID 是 `2xxx` 不是 `4xxx`**（4 是 SUID）；题目说「新建文件自动属于 X 组」= SGID。
- **vfat 不吃 `chmod/chown`**，权限要用挂载选项。
- 排查「用户没有权限」：除了文件本身，**父目录每一层都要有 `x`**；ACL 存在时 `ls -l` 权限位末尾有 `+`。

## 5. 动手练习

- [练习题集 · S5 文件系统 / NFS / autofs](../../labs/rhcsa/practice-set-1.md#s5)
- 实验需要 serverb 充当 NFS 服务器，见 [实验环境搭建](../../labs/rhcsa/00-lab-setup.md)

## 6. 官方文档（本仓库离线版 + 考场可用的查法）

- RHEL 10《Managing file systems》：<https://docs.redhat.com/en/documentation/red_hat_enterprise_linux/10/html-single/managing_file_systems/index>
- RHEL 10《Configuring and using network file services》（NFS 服务端/客户端）：<https://docs.redhat.com/en/documentation/red_hat_enterprise_linux/10/html-single/configuring_and_using_network_file_services/index>
- 离线 PDF：运行 [`scripts/fetch-rhel-docs.sh`](../../scripts/fetch-rhel-docs.sh)
- **考场查法**：
  - `man 5 auto.master`、`man 5 autofs`（映射文件格式、`*` 与 `&` 的说明）
  - `cat /etc/auto.master`、`/etc/auto.misc`：**系统自带示例**，照着改最快
  - `man 5 nfs`（客户端挂载选项）、`man 5 exports`（服务端）
  - `man xfs_admin`、`man e2label`、`man mkfs.vfat`
  - `man setfacl` → `/EXAMPLES`

## 7. 自测清单

- [ ] 能分别创建 xfs/ext4/vfat 文件系统，并按 LABEL 或 UUID 持久挂载
- [ ] 能手动挂载 NFS 并写入 fstab（含 `_netdev`）
- [ ] 能用通配符配置 autofs，使 `/home/remote/<用户名>` 自动挂载对应 NFS 目录
- [ ] 能配置直接映射的 autofs
- [ ] 能建一个 SGID 协作目录，并验证组成员新建的文件属组正确
- [ ] 给出一个「alice 无法写入某文件」的场景，能按 ugo → 父目录 → ACL → SELinux 的顺序排查
