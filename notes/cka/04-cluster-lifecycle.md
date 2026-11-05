# CKA-04 集群生命周期：升级、节点维护、证书与 etcd 备份恢复

> **轨道**：[CKA](README.md) ｜ **考纲**：CKA「Manage the lifecycle of Kubernetes clusters」 ｜ **建议用时**：8 h ｜ **难度**：★★★
>
> **前置**：[CKA-03 用 kubeadm 搭建集群](03-kubeadm-install.md) · [F6 TLS/PKI 基础](../00-foundations/06-tls-pki-basics.md)
> **后续**：[CKA-05 高可用控制平面](05-ha-control-plane.md) · [CKA-15 排错](15-troubleshooting.md)
> **关联**（跨轨道）：[RHCSA-06 软件、计划任务、时间、引导](../rhcsa/06-software-scheduling-boot.md)（版本锁定、计划备份） · [RHCSA-02 Shell 脚本](../rhcsa/02-shell-scripting.md)（写备份脚本） · [RHCE-11 自动化 RHCSA 任务](../rhce/11-automate-rhcsa-tasks.md)（用 Ansible 滚动升级节点）

## 1. 这个知识点在网络中的位置

集群装好只是开始。考纲里的「生命周期」包括：**小版本升级、节点维护（cordon/drain）、证书续期、etcd 备份与恢复**。
这几类题几乎每次考试都会出现，而且步骤固定——练熟了就是送分题，没练过就是大坑。
etcd 备份恢复 = 「整个集群的数据库备份」；升级 = 「按顺序替换软件包 + 静态 Pod 清单」。两者都离不开 RHCSA 的软件包管理和 systemd。

## 2. 核心概念

### 2.1 升级规则

- **一次只能升一个小版本**：1.36 → 1.37 可以，1.35 → 1.37 必须先到 1.36。
- **顺序**：先控制平面（第一个节点 `kubeadm upgrade apply`，其余控制平面节点 `kubeadm upgrade node`），再逐个 worker（`kubeadm upgrade node`）。
- **版本偏差**：kubelet 不能比 apiserver 新；可以比 apiserver 旧若干个小版本（当前策略见官方 Version Skew Policy）。kubectl 与 apiserver 相差 ±1 个小版本内。
- 每个节点的通用流程：升级 kubeadm 包 → `kubeadm upgrade ...` → `drain` → 升级 kubelet/kubectl 包 → `systemctl daemon-reload && systemctl restart kubelet` → `uncordon`。
- pkgs.k8s.io 每个小版本一个仓库：**升级前要先改软件源里的版本号**（见 [K3](03-kubeadm-install.md)）。

### 2.2 节点维护

| 命令 | 效果 |
|---|---|
| `kubectl cordon node1` | 标记不可调度，已有 Pod 不动 |
| `kubectl drain node1 --ignore-daemonsets --delete-emptydir-data` | cordon + 驱逐 Pod（遵守 PodDisruptionBudget） |
| `kubectl uncordon node1` | 恢复调度 |

### 2.3 证书

kubeadm 生成的组件证书默认 1 年有效，CA 10 年。`kubeadm upgrade` 会自动续期；也可以手动 `kubeadm certs renew`。续期后要**重启控制平面静态 Pod**（移出再移回清单，或重启 kubelet）才会加载新证书。

### 2.4 etcd 备份恢复的工具

| 工具 | 用途 |
|---|---|
| `etcdctl` | 客户端，连**正在运行的** etcd：`snapshot save`、`member list`、`endpoint health` |
| `etcdutl` | 离线管理工具，直接操作数据文件：`snapshot status`、**`snapshot restore`** |

官方文档说明：`etcdctl snapshot restore/status` 自 etcd v3.5 起已废弃，并计划在 v3.6 移除——新版本请用 `etcdutl`。考场机器上有哪个就用哪个，命令参数几乎一样。
连接 kubeadm 的 etcd 必须带 TLS 证书（都在 `/etc/kubernetes/pki/etcd/`），具体路径**以 `etcd.yaml` 静态 Pod 清单里的参数为准**。

## 3. 必会操作

### 3.1 升级控制平面（以 Ubuntu 为例，1.36.x → 1.37.x）

```bash
# 1) 改软件源到新小版本
sudo sed -i 's#/v1.36/#/v1.37/#' /etc/apt/sources.list.d/kubernetes.list
sudo apt-get update && apt-cache madison kubeadm | head -3        # 找到具体补丁版本

# 2) 升级 kubeadm
sudo apt-mark unhold kubeadm && sudo apt-get install -y kubeadm='1.37.x-*' && sudo apt-mark hold kubeadm
kubeadm version

# 3) 计划并执行
sudo kubeadm upgrade plan
sudo kubeadm upgrade apply v1.37.x          # 其余控制平面节点用：sudo kubeadm upgrade node

# 4) 腾空节点 → 升级 kubelet/kubectl → 重启 → 恢复
kubectl drain cp1 --ignore-daemonsets
sudo apt-mark unhold kubelet kubectl && sudo apt-get install -y kubelet='1.37.x-*' kubectl='1.37.x-*' && sudo apt-mark hold kubelet kubectl
sudo systemctl daemon-reload && sudo systemctl restart kubelet
kubectl uncordon cp1
```

RHEL 系把第 1、2、4 步换成：改 `/etc/yum.repos.d/kubernetes.repo` 中的版本号，`sudo dnf install -y kubeadm-'1.37.x-*' --disableexcludes=kubernetes`。

### 3.2 升级 worker（在控制平面上 drain，在 worker 上执行其余步骤）

```bash
# worker 上：改源 + 升级 kubeadm（同上）
sudo kubeadm upgrade node                   # 更新本节点 kubelet 配置
# 控制平面上：
kubectl drain worker1 --ignore-daemonsets --delete-emptydir-data
# worker 上：升级 kubelet kubectl，重启 kubelet（同上）
# 控制平面上：
kubectl uncordon worker1 && kubectl get nodes   # VERSION 列显示新版本
```

### 3.3 etcd 备份与恢复

```bash
# 先从清单里确认证书路径和数据目录
sudo grep -E 'cert-file|key-file|trusted-ca-file|listen-client-urls|data-dir' /etc/kubernetes/manifests/etcd.yaml

# 备份（连运行中的 etcd）
sudo ETCDCTL_API=3 etcdctl --endpoints=https://127.0.0.1:2379 \
  --cacert=/etc/kubernetes/pki/etcd/ca.crt \
  --cert=/etc/kubernetes/pki/etcd/server.crt \
  --key=/etc/kubernetes/pki/etcd/server.key \
  snapshot save /opt/backup/etcd-snap.db

sudo etcdutl --write-out=table snapshot status /opt/backup/etcd-snap.db   # 校验

# 恢复到一个新目录（不要覆盖正在用的 /var/lib/etcd）
sudo etcdutl --data-dir /var/lib/etcd-restore snapshot restore /opt/backup/etcd-snap.db

# 让 etcd 使用新目录：编辑静态 Pod 清单中 name: etcd-data 的 hostPath.path
sudo vim /etc/kubernetes/manifests/etcd.yaml      # /var/lib/etcd → /var/lib/etcd-restore
# kubelet 会自动重建 etcd Pod；等待 1~2 分钟后验证
watch sudo crictl ps                               # etcd、kube-apiserver 重新 Running
kubectl get pods -A
```

官方建议：恢复前停掉所有 apiserver，恢复后重启 kube-scheduler、kube-controller-manager、kubelet，避免它们使用陈旧数据；kubeadm 集群还应同步修改 `kubeadm-config` ConfigMap 里的 `etcd.local.dataDir`，否则下次 `kubeadm upgrade` 会写回旧目录。

### 3.4 证书

```bash
sudo kubeadm certs check-expiration         # 各证书到期时间
sudo kubeadm certs renew all                # 全部续期 → 然后重启控制平面组件
sudo openssl x509 -in /etc/kubernetes/pki/apiserver.crt -noout -dates -subject -ext subjectAltName
```

## 4. 考试坑点

- 升级题**只升到题目要求的版本**，而且通常只要求升级控制平面或某个节点，看清楚。
- 忘记 `apt-mark unhold`/`--disableexcludes` → 包管理器说「没有可升级的包」。
- 升级 kubelet 后忘记 `daemon-reload` + `restart kubelet` → `kubectl get nodes` 版本不变。
- `drain` 报错：DaemonSet Pod 需要 `--ignore-daemonsets`；用 emptyDir 的 Pod 需要 `--delete-emptydir-data`；裸 Pod（没有控制器）需要 `--force`。
- etcd 备份：`--endpoints` 要用 https；三个证书参数缺一不可；题目指定的备份路径要一字不差。
- etcd 恢复后 apiserver 会短暂不可用，耐心等；如果一直起不来，用 `crictl ps -a` + `crictl logs` 查 etcd 容器日志，多半是 hostPath 改错。
- 改 `etcd.yaml` 时 `volumes` 和 `--data-dir` 参数是两处不同的东西：最简单的做法是只改 `volumes.hostPath.path`，容器内路径保持 `/var/lib/etcd` 不变。

## 5. 动手练习

- 在自己的集群上完整做一次 1.(n-1) → 1.n 升级（搭建时故意装旧一个小版本，见 [labs/cka/00-lab-setup.md](../../labs/cka/00-lab-setup.md)）。
- 备份 etcd → 删除一个 Deployment → 恢复 → 确认 Deployment 回来了。
- drain 一个运行着裸 Pod 和 emptyDir Pod 的节点，读懂每个报错。
- [labs/cka/practice-set-1.md](../../labs/cka/practice-set-1.md)、[labs/cka/mock-exam.md](../../labs/cka/mock-exam.md) 中升级与 etcd 题。

## 6. 官方文档（本仓库离线版 + 考场可用的查法）

| 主题 | 离线文件 | 考场在线路径 |
|---|---|---|
| **升级 kubeadm 集群** | [tasks/administer-cluster/kubeadm/kubeadm-upgrade.md](../../references/cka/kubernetes-docs/tasks/administer-cluster/kubeadm/kubeadm-upgrade.md) | kubernetes.io/docs/tasks/administer-cluster/kubeadm/kubeadm-upgrade/ |
| 升级 Linux 工作节点 | [tasks/administer-cluster/kubeadm/upgrading-linux-nodes.md](../../references/cka/kubernetes-docs/tasks/administer-cluster/kubeadm/upgrading-linux-nodes.md) | kubernetes.io/docs/tasks/administer-cluster/kubeadm/upgrading-linux-nodes/ |
| 更换软件包仓库（换小版本） | [tasks/administer-cluster/kubeadm/change-package-repository.md](../../references/cka/kubernetes-docs/tasks/administer-cluster/kubeadm/change-package-repository.md) | kubernetes.io/docs/tasks/administer-cluster/kubeadm/change-package-repository/ |
| **etcd 运维（备份/恢复）** | [tasks/administer-cluster/configure-upgrade-etcd.md](../../references/cka/kubernetes-docs/tasks/administer-cluster/configure-upgrade-etcd.md) | kubernetes.io/docs/tasks/administer-cluster/configure-upgrade-etcd/ |
| 证书管理 | [tasks/administer-cluster/kubeadm/kubeadm-certs.md](../../references/cka/kubernetes-docs/tasks/administer-cluster/kubeadm/kubeadm-certs.md) | kubernetes.io/docs/tasks/administer-cluster/kubeadm/kubeadm-certs/ |
| 安全腾空节点 | [tasks/administer-cluster/safely-drain-node.md](../../references/cka/kubernetes-docs/tasks/administer-cluster/safely-drain-node.md) | kubernetes.io/docs/tasks/administer-cluster/safely-drain-node/ |
| 重新配置 kubeadm 集群 | [tasks/administer-cluster/kubeadm/kubeadm-reconfigure.md](../../references/cka/kubernetes-docs/tasks/administer-cluster/kubeadm/kubeadm-reconfigure.md) | kubernetes.io/docs/tasks/administer-cluster/kubeadm/kubeadm-reconfigure/ |
| kubeadm upgrade 参考 | [reference/setup-tools/kubeadm/kubeadm-upgrade.md](../../references/cka/kubernetes-docs/reference/setup-tools/kubeadm/kubeadm-upgrade.md) | kubernetes.io/docs/reference/setup-tools/kubeadm/kubeadm-upgrade/ |

考场技巧：搜 `upgrade kubeadm` 直接照着官方页面一步步执行；搜 `etcd backup` 找到备份命令模板，证书路径从 `etcd.yaml` 里抄。

## 7. 自测清单

- [ ] 能不看文档说出控制平面和 worker 的升级步骤顺序
- [ ] 15 分钟内完成一个控制平面节点 + 一个 worker 的小版本升级
- [ ] 知道 etcdctl 与 etcdutl 的区别，能写出带证书的 `snapshot save`
- [ ] 能完成一次 etcd 恢复并说明为什么要恢复到新目录
- [ ] 能查看证书到期时间并全部续期
- [ ] 知道 drain 的三种常见报错及对应参数
