# RHCSA-04 本地存储：分区、LVM 与 swap

> **轨道**：[RHCSA](README.md) ｜ **考纲**：EX200「Configure local storage」 ｜ **建议用时**：8 h ｜ **难度**：★★★
>
> **前置**：[S1 基础工具](01-essential-tools.md)
> **后续**：[S5 文件系统 / NFS / autofs](05-file-systems-nfs-autofs.md)
> **关联**（跨轨道）：[RHCE-11 用 Ansible 自动化 RHCSA 任务](../rhce/11-automate-rhcsa-tasks.md)（`parted`/`lvg`/`lvol`/`filesystem`/`mount` 模块） · [RHCE-12 RHEL System Roles](../rhce/12-rhel-system-roles.md)（storage 角色） · [CKA-14 存储](../cka/14-storage.md)（PV/PVC 的底层就是这些块设备和文件系统）

## 1. 这个知识点在网络中的位置

存储题在 EX200 里分值高、而且**一旦弄坏 /etc/fstab，机器可能起不来**，整场考试崩盘。这里要练到「非破坏性」——在已有数据的磁盘上新增分区/LV/swap，不影响现有挂载。

在网络中：RHCE 里你会用 `community.general.parted`、`community.general.lvg`、`community.general.lvol` 模块做同样的事；CKA 的 PersistentVolume 也最终落在某个节点的块设备或 NFS 上。

Ubuntu 对照：工具完全相同（parted、fdisk、lvm2）；Ubuntu 安装时默认也可选 LVM。RHEL 的默认文件系统是 **XFS**（Ubuntu 是 ext4），XFS **只能扩容不能缩容**。

## 2. 核心概念

```text
物理磁盘 /dev/vdb
 ├─ 分区 /dev/vdb1 ──┐
 └─ 分区 /dev/vdb2 ──┤  pvcreate → PV（物理卷）
物理磁盘 /dev/vdc ───┘
                     ↓ vgcreate
              VG（卷组）vg_data，按 PE（物理区块，默认 4 MiB）切分
                     ↓ lvcreate
        LV（逻辑卷）/dev/vg_data/lv_web  →  mkfs  →  mount
```

| 主题 | 要点 |
|---|---|
| MBR vs GPT | MBR：最多 4 个主分区（或 3 主 + 1 扩展），单盘 ≤ 2 TiB；GPT：默认 128 个分区，现代系统首选 |
| 工具 | `parted`（MBR/GPT 都行，可脚本化）、`fdisk`（MBR/GPT）、`gdisk`（GPT） |
| 分区类型 | 给 LVM 用的分区可设 `lvm` 标志；swap 分区设 `linux-swap` 类型 |
| PE 大小 | `vgcreate -s 8M` 指定；题目常要求「PE 大小为 X」或「LV 大小为 N 个 extent」（`lvcreate -l N`） |
| 持久挂载 | 写入 `/etc/fstab`，推荐用 `UUID=` 或 `LABEL=`（考纲原文：mount by UUID or label） |
| swap | `mkswap` → `swapon` → fstab 中写 `UUID=... none swap defaults 0 0` |

## 3. 必会操作

```bash
# ---------- 查看 ----------
lsblk -f                                      # 树状显示磁盘/分区/文件系统/UUID/挂载点
blkid /dev/vdb1                               # UUID 与类型
parted /dev/vdb print                         # 分区表
pvs; vgs; lvs                                 # LVM 三件套简表
pvdisplay; vgdisplay vg_data; lvdisplay       # 详细信息（vgdisplay 里能看到 PE Size / Free PE）

# ---------- 分区（parted 非交互写法） ----------
parted -s /dev/vdb mklabel gpt                # ⚠️ 新盘才做！已有分区表的盘不要再 mklabel
parted -s /dev/vdb mkpart data 1MiB 1025MiB   # 1 GiB 分区
parted -s /dev/vdb set 1 lvm on               # 设 LVM 标志
parted -s /dev/vdb mkpart swap1 linux-swap 1025MiB 1537MiB
udevadm settle; lsblk /dev/vdb                # 等内核识别新分区（必要时 partprobe）

# fdisk 交互写法：fdisk /dev/vdb → n 新建 → p/e → 起止 → t 改类型(8e LVM / 82 swap，GPT 下用别名 lvm / swap) → w 写入

# ---------- LVM ----------
pvcreate /dev/vdb1
vgcreate -s 8M vg_data /dev/vdb1              # PE = 8 MiB
lvcreate -n lv_web -L 500M vg_data            # 按大小
lvcreate -n lv_db  -l 50 vg_data              # 按 extent 数（50 × 8 MiB = 400 MiB）
mkfs.xfs /dev/vg_data/lv_web
mkdir -p /srv/web

# ---------- 持久挂载（UUID） ----------
blkid /dev/vg_data/lv_web                     # 复制 UUID
echo 'UUID=<上一步的UUID>  /srv/web  xfs  defaults  0 0' >> /etc/fstab
# LV 也可以直接写设备路径 /dev/vg_data/lv_web（LVM 名字是稳定的），但题目要求 UUID 就写 UUID
systemctl daemon-reload                       # 让 systemd 重新读取 fstab
mount -a                                      # 无输出 = 语法 OK
findmnt --verify                              # 额外检查 fstab
df -hT /srv/web

# ---------- 扩容（非破坏性） ----------
vgextend vg_data /dev/vdc1                    # VG 空间不够时先加 PV
lvextend -r -L +300M /dev/vg_data/lv_web      # -r 同时扩文件系统（xfs_growfs / resize2fs）
# 不带 -r 时：xfs_growfs /srv/web（XFS 用挂载点）或 resize2fs /dev/vg_data/lv_x（ext4 用设备）

# ---------- swap ----------
mkswap /dev/vdb2
echo "UUID=$(blkid -s UUID -o value /dev/vdb2)  none  swap  defaults  0 0" >> /etc/fstab
systemctl daemon-reload
swapon -a                                     # 启用 fstab 里的所有 swap
swapon --show; free -h                        # 验证

# LV 做 swap 也一样：lvcreate -n lv_swap -L 512M vg_data && mkswap /dev/vg_data/lv_swap

# ---------- 删除（倒序） ----------
umount /srv/web && sed -i '/\/srv\/web/d' /etc/fstab
lvremove /dev/vg_data/lv_web; vgremove vg_data; pvremove /dev/vdb1
```

## 4. 考试坑点

- **改 fstab 后必须 `mount -a` / `swapon -a` 验证**，再 `reboot` 验证。fstab 写错会让机器进入 emergency 模式。
  - 万一进了 emergency：输入 root 密码 → `mount -o remount,rw /` → 修 `/etc/fstab` → `systemctl daemon-reload` → `reboot`。
- **`mklabel` 会清空分区表**：考试给的磁盘上如果已有分区（比如已经有 swap 在用），只能在空闲空间新增，不能重建分区表。
- **分区对齐**：用 `1MiB` 起点，`parted` 才不会警告 "not properly aligned"。
- **题目里的大小有容差**：通常允许一定范围（如 470~530 MiB），但 VG 剩余空间不够时要先算清楚：`vgdisplay` 看 Free PE。
- **XFS 不能缩小**。题目要求缩小时，一般是 ext4。
- 用 `-l` 按 extent 数创建时，单位是 PE 而不是 MiB；`-l 100%FREE` 用光剩余空间。
- RHEL 9/10 挂载点配置由 systemd 根据 fstab 生成 `.mount` 单元，所以**改 fstab 后 `systemctl daemon-reload`**，否则 `mount` 会提示 fstab 已修改。

## 5. 动手练习

- [练习题集 · S4 本地存储与 LVM](../../labs/rhcsa/practice-set-1.md#s4)
- 实验需要额外磁盘，见 [实验环境搭建](../../labs/rhcsa/00-lab-setup.md)（每台 VM 加 2 块 5~10 GiB 虚拟盘）

## 6. 官方文档（本仓库离线版 + 考场可用的查法）

- RHEL 10《Managing storage devices》：<https://docs.redhat.com/en/documentation/red_hat_enterprise_linux/10/html-single/managing_storage_devices/index>
- RHEL 10《Managing file systems》：<https://docs.redhat.com/en/documentation/red_hat_enterprise_linux/10/html-single/managing_file_systems/index>
- LVM 专册（RHEL 9 叫《Configuring and managing logical volumes》，RHEL 10 名称以文档首页为准）：<https://docs.redhat.com/en/documentation/red_hat_enterprise_linux/10>
- 离线 PDF：运行 [`scripts/fetch-rhel-docs.sh`](../../scripts/fetch-rhel-docs.sh)
- **考场查法**：
  - `man 5 fstab`：六列含义（设备、挂载点、类型、选项、dump、fsck 顺序）
  - `man lvm`（总览）、`man lvcreate` → `/EXAMPLES`、`man lvextend` → `/-r`
  - `man vgcreate` → `/physicalextentsize`
  - `man parted`（`help mkpart` 在 parted 交互模式里也能用）
  - `man mkswap`、`man swapon`

## 7. 自测清单

- [ ] 能在 GPT 磁盘上用 `parted` 非交互地新建 1 GiB 分区并设 LVM 标志
- [ ] 能创建 PE=16 MiB 的 VG，并创建 20 个 extent 的 LV
- [ ] 能用 UUID 把 LV 持久挂载，并说出 fstab 六列含义
- [ ] 能在不卸载的前提下把 XFS 的 LV 扩容 300 MiB
- [ ] 能新增一个 512 MiB swap 分区并持久启用，不影响已有 swap
- [ ] fstab 写错导致进入 emergency 模式时，知道怎么修复
