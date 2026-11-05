# CKA-05 高可用控制平面

> **轨道**：[CKA](README.md) ｜ **考纲**：CKA「Implement and configure a highly-available control plane」 ｜ **建议用时**：6 h ｜ **难度**：★★★
>
> **前置**：[CKA-04 集群生命周期](04-cluster-lifecycle.md) · [CKA-03 用 kubeadm 搭建集群](03-kubeadm-install.md)
> **后续**：[CKA-15 排错](15-troubleshooting.md) · [CKA-08 扩展接口](08-extension-interfaces-crd.md)
> **关联**（跨轨道）：[F3 网络基础](../00-foundations/03-networking-basics.md)（VIP、负载均衡、TCP 健康检查） · [F6 TLS/PKI 基础](../00-foundations/06-tls-pki-basics.md)（证书分发） · [RHCSA-09 防火墙与 SELinux](../rhcsa/09-security-firewalld-selinux.md)

## 1. 这个知识点在网络中的位置

单控制平面集群里，那台机器一挂，整个集群就不能再做任何变更。HA 的思路很朴素：**多台控制平面 + 前面一个负载均衡 + etcd 多数派**。
它把 K3 的 `kubeadm init/join` 和 K4 的 etcd 知识组合起来，再加一点网络（VIP/LB）知识。
考试中这一块更多考「理解和配置」：知道两种拓扑、知道 `--control-plane-endpoint`、会把新控制平面节点加进去、会检查 etcd 成员和 leader 选举。

## 2. 核心概念

### 2.1 两种拓扑

| 拓扑 | 结构 | 优点 | 缺点 |
|---|---|---|---|
| **堆叠 etcd（stacked）** | 每个控制平面节点上同时跑 apiserver/scheduler/controller-manager **和** etcd | 机器少、kubeadm 默认支持、配置简单 | 一台机器挂 = 同时少一个控制平面和一个 etcd 成员 |
| **外部 etcd（external）** | etcd 单独一组机器 | 故障域隔离 | 机器翻倍，证书要手动分发 |

### 2.2 为什么是 3、5 台

etcd 用 Raft 协议，需要**多数派（quorum）**存活才能写入：`quorum = n/2 + 1`（向下取整）。

| etcd 成员数 | 允许故障数 |
|---|---|
| 1 | 0 |
| 2 | 0（比 1 台还脆弱：任何一台挂都失去多数派） |
| 3 | 1 |
| 5 | 2 |

### 2.3 各组件如何实现「高可用」

| 组件 | 方式 |
|---|---|
| kube-apiserver | 无状态，多实例同时工作，前面放 **TCP 负载均衡**（HAProxy+Keepalived、kube-vip、云 LB） |
| etcd | Raft 集群，多数派 |
| kube-scheduler / kube-controller-manager | 多实例但**同一时刻只有一个 leader 干活**，通过 `kube-system` 下的 `Lease` 对象选主 |
| kubelet / 客户端 | 都连接 `controlPlaneEndpoint`（LB 地址），而不是某台机器 |

### 2.4 关键参数

- `kubeadm init --control-plane-endpoint "LB_DNS:6443" --upload-certs`
  - `--control-plane-endpoint`：**必须在第一次 init 时就指定**，之后改很麻烦。单机实验也建议用一个 DNS 名/VIP，以便将来扩展。
  - `--upload-certs`：把控制平面共享证书加密后存到 `kube-system/kubeadm-certs` Secret，供其他控制平面节点 join 时下载。该 Secret 和解密 key **2 小时后过期**。
- `kubeadm join ... --control-plane --certificate-key <key>`：以控制平面身份加入。

## 3. 必会操作

```bash
# —— 第一台控制平面 ——
sudo kubeadm init --control-plane-endpoint "k8s-api.lab.local:6443" --upload-certs --pod-network-cidr=192.168.0.0/16
# 输出里有两条 join：带 --control-plane --certificate-key 的给控制平面，另一条给 worker

# —— 其他控制平面节点 ——
sudo kubeadm join k8s-api.lab.local:6443 --token <t> --discovery-token-ca-cert-hash sha256:<h> \
  --control-plane --certificate-key <key>

# —— 超过 2 小时后再加控制平面：重新上传证书并拿到新 key ——
sudo kubeadm init phase upload-certs --upload-certs       # 打印新的 certificate key
kubeadm token create --print-join-command                 # 再拼上 --control-plane --certificate-key <新key>

# —— 验证 ——
kubectl get nodes -l node-role.kubernetes.io/control-plane
kubectl -n kube-system get pods -l tier=control-plane -o wide
kubectl -n kube-system get lease kube-scheduler kube-controller-manager -o custom-columns=NAME:.metadata.name,HOLDER:.spec.holderIdentity
kubectl get --raw='/readyz?verbose' | tail -3

# —— etcd 成员与健康（在控制平面节点上，证书参数同 K4）——
E="--endpoints=https://127.0.0.1:2379 --cacert=/etc/kubernetes/pki/etcd/ca.crt --cert=/etc/kubernetes/pki/etcd/server.crt --key=/etc/kubernetes/pki/etcd/server.key"
sudo etcdctl $E member list -w table
sudo etcdctl $E endpoint status --cluster -w table      # 谁是 leader、DB 大小、raft index
sudo etcdctl $E endpoint health --cluster
```

### 最小实验用负载均衡（HAProxy，示意）

```text
# /etc/haproxy/haproxy.cfg 片段 —— 单独一台 LB 机器，TCP 模式转发 6443
frontend k8s-api
    bind *:6443
    mode tcp
    default_backend k8s-cp
backend k8s-cp
    mode tcp
    balance roundrobin
    option tcp-check
    server cp1 192.168.56.11:6443 check
    server cp2 192.168.56.12:6443 check
    server cp3 192.168.56.13:6443 check
```

生产中还会用 Keepalived 给多台 LB 提供浮动 VIP，或者用 kube-vip 以静态 Pod 形式直接在控制平面节点上提供 VIP。具体配置以 kubeadm 仓库的 HA 指南为准。
RHEL 上 HAProxy 监听非标准端口时还要处理 SELinux 布尔值/端口标签（见 [RHCSA-09](../rhcsa/09-security-firewalld-selinux.md)）。

## 4. 考试坑点

- 「2 台控制平面」不是高可用：堆叠 etcd 下 2 个成员没有容错能力。
- 加入控制平面节点报 `certificate key` 相关错误 → 多半是超过 2 小时，用 `kubeadm init phase upload-certs --upload-certs` 重新生成。
- `--control-plane-endpoint` 指向的地址必须能解析、能连通 6443；LB 上 6443 不通时 `kubeadm init` 会卡在等待控制平面。
- 控制平面节点默认带 `node-role.kubernetes.io/control-plane:NoSchedule` 污点，普通 Pod 不会调度上去——这是设计，不是故障（见 [K10](10-scheduling.md)）。
- 控制平面节点同样要升级（K4），HA 集群升级时第一台用 `upgrade apply`，其余用 `upgrade node`。

## 5. 动手练习

- 资源允许时：4 台 VM（1 LB + 3 控制平面）搭一个堆叠 etcd 的 HA 集群（参考 [labs/cka/00-lab-setup.md](../../labs/cka/00-lab-setup.md) 的准备步骤）。
- 关掉一台控制平面，验证 `kubectl` 仍可用、etcd 仍有 leader；再关一台，观察失去多数派后的表现。
- 观察 `Lease` 的 `holderIdentity`：杀掉当前 leader 所在节点的 scheduler 静态 Pod，看 leader 迁移。
- 资源不够时：用 kind 的多控制平面配置体验（kind 自带一个 LB 容器）。

## 6. 官方文档（本仓库离线版 + 考场可用的查法）

| 主题 | 离线文件 | 考场在线路径 |
|---|---|---|
| **用 kubeadm 创建 HA 集群** | [setup/.../kubeadm/high-availability.md](../../references/cka/kubernetes-docs/setup/production-environment/tools/kubeadm/high-availability.md) | kubernetes.io/docs/setup/production-environment/tools/kubeadm/high-availability/ |
| HA 拓扑选择 | [setup/.../kubeadm/ha-topology.md](../../references/cka/kubernetes-docs/setup/production-environment/tools/kubeadm/ha-topology.md) | kubernetes.io/docs/setup/production-environment/tools/kubeadm/ha-topology/ |
| 用 kubeadm 搭建 HA etcd | [setup/.../kubeadm/setup-ha-etcd-with-kubeadm.md](../../references/cka/kubernetes-docs/setup/production-environment/tools/kubeadm/setup-ha-etcd-with-kubeadm.md) | kubernetes.io/docs/setup/production-environment/tools/kubeadm/setup-ha-etcd-with-kubeadm/ |
| etcd 运维 | [tasks/administer-cluster/configure-upgrade-etcd.md](../../references/cka/kubernetes-docs/tasks/administer-cluster/configure-upgrade-etcd.md) | kubernetes.io/docs/tasks/administer-cluster/configure-upgrade-etcd/ |
| Lease 与选主 | [concepts/architecture/leases.md](../../references/cka/kubernetes-docs/concepts/architecture/leases.md) | kubernetes.io/docs/concepts/architecture/leases/ |
| kubeadm init 阶段 | [reference/setup-tools/kubeadm/kubeadm-init-phase.md](../../references/cka/kubernetes-docs/reference/setup-tools/kubeadm/kubeadm-init-phase.md) | kubernetes.io/docs/reference/setup-tools/kubeadm/kubeadm-init-phase/ |

考场技巧：搜 `highly available kubeadm`，`--upload-certs`、`--certificate-key` 的用法都在这一页。

## 7. 自测清单

- [ ] 能画出堆叠 etcd 与外部 etcd 两种拓扑，并说出各自优缺点
- [ ] 能解释为什么 etcd 用奇数个成员，3 台允许坏几台
- [ ] 能说出 apiserver、etcd、scheduler/controller-manager 三类组件各自如何实现 HA
- [ ] 能把一个新节点以控制平面身份加入集群（含证书 key 过期的处理）
- [ ] 能用 etcdctl 查看成员列表和 leader，用 Lease 查看当前 scheduler leader
