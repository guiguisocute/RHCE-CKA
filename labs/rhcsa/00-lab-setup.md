# RHCSA 实验环境搭建

> 对应笔记：[RHCSA 轨道索引](../../notes/rhcsa/README.md) ｜ 后续：[练习题集](practice-set-1.md) · [模拟考](mock-exam.md)
>
> 这套环境也会被 RHCE 复用（servera 当 Ansible 控制节点，serverb 等当被控节点），所以值得花一个周末认真搭好。

## 1. 目标拓扑

| 主机 | 角色 | vCPU / 内存 | 系统盘 | 额外磁盘 | IP（示例，NAT 网段 192.168.122.0/24） |
|---|---|---|---|---|---|
| `servera.lab.example.com` | 主要练习机 | 2 / 2 GiB | 20 GiB | `vdb` 5 GiB、`vdc` 5 GiB（LVM/分区/swap 练习） | 192.168.122.10 |
| `serverb.lab.example.com` | NFS 服务器、SSH 目标、第二台练习机 | 2 / 2 GiB | 20 GiB | `vdb` 5 GiB | 192.168.122.11 |

> 内存紧张时 1.5 GiB 也能跑最小安装（Minimal Install / Server without GUI）。练 Flatpak 图形应用时才需要装 GUI。
> 磁盘设备名：KVM/virtio 下是 `vda vdb vdc`；VMware/VirtualBox/Hyper-V 下通常是 `sda sdb sdc` 或 `nvme0n1`，练习时替换即可。

## 2. 获取系统镜像

### 方案 A（推荐）：免费正版 RHEL 10

1. 注册 Red Hat 账号，加入 **Red Hat Developer Subscription for Individuals**（免费，个人可用最多 16 台）：<https://developers.redhat.com/products/rhel/download>
2. 下载 **RHEL 10 Binary DVD ISO**（x86_64；Apple Silicon 选 **aarch64**）。
3. 安装完成后注册系统（Simple Content Access 模式下注册即可使用仓库，无需 attach）：

```bash
subscription-manager register --username <你的红帽账号>     # 按提示输入密码
subscription-manager status
dnf repolist                                              # 应看到 rhel-10-for-x86_64-baseos-rpms 和 appstream-rpms
```

### 方案 B：AlmaLinux 10 / Rocky Linux 10

二进制兼容 RHEL，无需注册，适合多开机器。差异：仓库名不同、没有 `subscription-manager`、红帽 Flatpak 仓库不可用（用 flathub 练习）。**考前最后两周建议换回正版 RHEL 10 练一遍**。

## 3. 三种宿主方案

### Windows：VMware Workstation（个人免费）/ VirtualBox / Hyper-V

- VMware Workstation：新建虚拟机 → 选 ISO → 客户机类型 "Red Hat Enterprise Linux 9 64 位"（列表里没有 10 时选 9）→ 自定义硬件里「添加 → 硬盘」两次。网络用 NAT。
- VirtualBox：类型 Linux / Red Hat (64-bit)；控制器里添加两块 VDI；开启 EFI 可选。
- Hyper-V：**第 2 代**虚拟机；安全启动模板选 **Microsoft UEFI Certificate Authority**（否则 RHEL 无法引导）；使用 Default Switch。

### macOS（Apple Silicon）：UTM

- 必须用 **aarch64** ISO（x86_64 ISO 只能走「模拟」模式，极慢）。
- UTM → Create → **Virtualize** → Linux → 选 ISO；在 Drives 里新增两块 VirtIO 磁盘。
- 网络默认 Shared Network 即可；需要固定 IP 时在系统里用 nmcli 配静态地址。

### Linux：KVM / libvirt（最接近考试环境）

```bash
sudo apt install -y qemu-kvm libvirt-daemon-system virtinst     # Ubuntu 宿主机
osinfo-query os | grep -i rhel                                  # 查看可用的 --os-variant（没有 rhel10 就用 rhel9.0 或 detect=on）
sudo virt-install --name servera --memory 2048 --vcpus 2 \
  --disk size=20 --disk size=5 --disk size=5 \
  --cdrom /var/lib/libvirt/images/rhel-10.0-x86_64-dvd.iso \
  --os-variant detect=on,require=off \
  --network network=default --graphics vnc
# serverb 同理（--disk size=20 --disk size=5）
sudo virsh list --all; sudo virsh domifaddr servera
```

## 4. 系统安装要点

- 软件选择：**Server**（无 GUI）或 **Minimal Install**；分区用自动（会建 LVM：`rhel-root`、`rhel-swap`）。
- **只在系统盘上安装**，不要勾选额外的 `vdb/vdc`，留给练习。
- 设置 root 密码，并创建普通用户 `student`（勾选「设为管理员」= 加入 `wheel`）。
- 装好后：

```bash
hostnamectl set-hostname servera.lab.example.com
cat >> /etc/hosts <<'EOF'
192.168.122.10  servera.lab.example.com  servera
192.168.122.11  serverb.lab.example.com  serverb
EOF
dnf install -y vim-enhanced bash-completion man-pages tar bzip2 policycoreutils-python-utils
mandb                                         # 建好 man 索引，man -k 才能用
```

## 5. 本地 dnf 仓库（离线练习 + 模拟考题中的「配置仓库」）

把 DVD ISO 挂到虚拟机光驱（或拷进系统），做成本地仓库：

```bash
mkdir -p /mnt/iso
# 光驱方式：
echo '/dev/sr0  /mnt/iso  iso9660  ro,nofail  0 0' >> /etc/fstab
# ISO 文件方式：
# echo '/root/rhel-10.0-x86_64-dvd.iso  /mnt/iso  iso9660  loop,ro,nofail  0 0' >> /etc/fstab
systemctl daemon-reload && mount -a && ls /mnt/iso       # 应看到 BaseOS/ 和 AppStream/

cat > /etc/yum.repos.d/local-iso.repo <<'EOF'
[local-BaseOS]
name=Local BaseOS
baseurl=file:///mnt/iso/BaseOS
enabled=1
gpgcheck=1
gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-redhat-release

[local-AppStream]
name=Local AppStream
baseurl=file:///mnt/iso/AppStream
enabled=1
gpgcheck=1
gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-redhat-release
EOF
dnf clean all && dnf repolist
```

> AlmaLinux/Rocky 的 GPG key 文件名不同（`ls /etc/pki/rpm-gpg/` 查看），或练习时直接 `gpgcheck=0`。

**模拟「考场 HTTP 仓库」**：在 serverb 上把 ISO 内容通过 httpd 发布，servera 用 `baseurl=http://serverb/BaseOS` 访问：

```bash
# serverb 上执行
dnf install -y httpd && mkdir -p /var/www/html/repo
# ISO 是只读文件系统，restorecon 改不了标签，挂载时直接用 context= 指定 httpd 可读的 SELinux 类型
mount -o loop,ro,context=system_u:object_r:httpd_sys_content_t:s0 /root/rhel-10.0-x86_64-dvd.iso /var/www/html/repo
# （想持久就写进 fstab，选项同上；或者把 BaseOS/、AppStream/ 复制到 /var/www/html/repo 后 restorecon -Rv，需要约 10 GiB 空间）
systemctl enable --now httpd
firewall-cmd --permanent --add-service=http && firewall-cmd --reload
# servera 上：baseurl=http://serverb/repo/BaseOS 和 http://serverb/repo/AppStream
```

## 6. serverb 上准备 NFS（S5 autofs 练习用）

```bash
dnf install -y nfs-utils
mkdir -p /exports/share /exports/home/remoteuser{1,2}
echo 'shared file' > /exports/share/readme.txt
cat >> /etc/exports <<'EOF'
/exports/share  192.168.122.0/24(rw,sync)
/exports/home   192.168.122.0/24(rw,sync)
EOF
useradd -u 3001 remoteuser1; useradd -u 3002 remoteuser2           # UID 与 servera 上保持一致
chown remoteuser1: /exports/home/remoteuser1; chown remoteuser2: /exports/home/remoteuser2
systemctl enable --now nfs-server && exportfs -rav
firewall-cmd --permanent --add-service={nfs,mountd,rpc-bind} && firewall-cmd --reload
```

## 7. 快照习惯（非常重要）

| 快照名 | 时机 |
|---|---|
| `00-clean-install` | 刚装完、注册完 |
| `01-lab-ready` | 完成本页第 4~6 节 |
| `pre-<练习名>` | 每次练危险操作（root 密码重置、fstab、分区）前 |

```bash
# KVM
sudo virsh snapshot-create-as servera 01-lab-ready
sudo virsh snapshot-list servera
sudo virsh snapshot-revert servera 01-lab-ready
```

VMware/VirtualBox/UTM/Hyper-V 在图形界面里都有「快照 / 检查点」。**每做完一轮练习就回滚到 `01-lab-ready`**，下一轮从干净状态开始——这才接近考场。

## 8. 自检

- [ ] 两台机器能互相 `ping` 主机名、`ssh student@serverb` 成功
- [ ] `dnf repolist` 能看到 BaseOS 和 AppStream（订阅或本地仓库）
- [ ] servera 上 `lsblk` 能看到两块未使用的空盘
- [ ] `showmount -e serverb` 能看到 `/exports/share` 和 `/exports/home`
- [ ] `man -k fstab` 有结果
- [ ] 已创建 `01-lab-ready` 快照
