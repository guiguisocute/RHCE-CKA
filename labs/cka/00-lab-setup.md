# CKA 实验环境搭建

> **对应笔记**：[K1 架构](../../notes/cka/01-architecture.md) · [K3 kubeadm 装集群](../../notes/cka/03-kubeadm-install.md) · [K4 升级/etcd](../../notes/cka/04-cluster-lifecycle.md) · [K8 CNI/CRI](../../notes/cka/08-extension-interfaces-crd.md)
> **下一步**：[practice-set-1](practice-set-1.md) → [mock-exam](mock-exam.md)

三种环境按需选择，**最终一定要用方案 B 亲手搭过至少两次**——考纲里 25% 的「集群架构/安装/生命周期」和 30% 的「排错」都依赖这套真实环境。

| 方案 | 适合练什么 | 成本 | 局限 |
|---|---|---|---|
| A. kind / minikube（本机容器里的集群） | kubectl、YAML、工作负载、Service、RBAC、Helm | 几分钟、8 GB 内存的笔记本即可 | 不能练 kubeadm 安装/升级、节点 systemd 排错 |
| **B. 3 台虚拟机 + kubeadm** | **全部考纲**：安装、升级、etcd 备份、NetworkPolicy、排错 | 约 8～12 GB 内存、60 GB 磁盘 | 搭建要 1～2 小时 |
| C. killercoda 在线场景 | 碎片时间刷题 | 免费、浏览器即可 | 会话有时长限制、环境不可保存 |

> 下文版本号以 Kubernetes **v1.37** 为例（与考纲 v1.37 一致）。所有 `<版本>` 占位符请到对应项目的 Releases 页面确认最新版本。

---

## 方案 A：kind 或 minikube（10 分钟上手）

你用过 Docker，这一步零门槛。kind = 「Kubernetes in Docker」，每个节点就是一个容器。

```bash
# 安装 kubectl（官方方式，见 references/cka/kubernetes-docs/tasks/tools/install-kubectl-linux.md）
curl -LO "https://dl.k8s.io/release/$(curl -Ls https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
sudo install -m 0755 kubectl /usr/local/bin/kubectl

# 安装 kind（版本见 https://github.com/kubernetes-sigs/kind/releases）
curl -Lo ./kind https://kind.sigs.k8s.io/dl/<版本>/kind-linux-amd64 && chmod +x kind && sudo mv kind /usr/local/bin/

# 1 控制平面 + 2 worker
cat > kind-3node.yaml <<'EOF'
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
nodes:
- role: control-plane
- role: worker
- role: worker
networking:
  disableDefaultCNI: false      # 想练 NetworkPolicy 时改为 true，再自行安装 Calico
  podSubnet: "10.244.0.0/16"
EOF
kind create cluster --name cka --config kind-3node.yaml
kubectl get nodes
docker exec -it cka-control-plane bash      # 「ssh」进节点：能看到 /etc/kubernetes/manifests、crictl
kind delete cluster --name cka
```

minikube 等价写法：`minikube start --nodes 3 --cni calico`（minikube 的 `--cni calico` 支持 NetworkPolicy）。

---

## 方案 B：3 台虚拟机 + kubeadm（正式环境）

### B.0 规划

| 主机名 | IP（示例：VirtualBox host-only 网段） | 角色 | 建议配置 |
|---|---|---|---|
| cp1 | 192.168.56.10 | control-plane | 2 vCPU / 4 GB / 20 GB |
| worker1 | 192.168.56.11 | worker | 2 vCPU / 2～4 GB / 20 GB |
| worker2 | 192.168.56.12 | worker | 2 vCPU / 2～4 GB / 20 GB |

- 系统：**Ubuntu 24.04 LTS**（你熟悉）和 **RHEL 10 / Rocky Linux 10 / AlmaLinux 10**（顺便复习 RHCSA）各搭一遍。RHEL 可用免费的 [Red Hat Developer Subscription](https://developers.redhat.com/products/rhel/download)。
- 虚拟化：VirtualBox、VMware、KVM/libvirt 均可；每台 VM 一块 NAT 网卡（上网）+ 一块 host-only 网卡（集群通信）。
- 网段规划：Pod CIDR 用 `10.244.0.0/16`，Service CIDR 用默认 `10.96.0.0/12`，**都不能和 VM 网段重叠**。
- 想练升级（[K4](../../notes/cka/04-cluster-lifecycle.md)）：第一次搭建时故意装上一个小版本（如 v1.36），之后再升到 v1.37。

### B.1 所有节点：主机名、hosts、时间

```bash
sudo hostnamectl set-hostname cp1            # 每台分别设置
cat <<'EOF' | sudo tee -a /etc/hosts
192.168.56.10 cp1
192.168.56.11 worker1
192.168.56.12 worker2
EOF
timedatectl                                   # 确认 NTP 同步（证书校验依赖时间）
```

### B.2 所有节点：关闭 swap（持久化）

```bash
sudo swapoff -a
sudo sed -ri '/\sswap\s/s/^#?/#/' /etc/fstab   # 注释掉 fstab 中的 swap 行
# RHEL 10 / Fedora 系若使用 zram：sudo dnf remove -y zram-generator-defaults（视系统而定）
free -h                                        # Swap 一行应为 0
```

### B.3 所有节点：内核模块与 sysctl（持久化）

```bash
cat <<'EOF' | sudo tee /etc/modules-load.d/k8s.conf
overlay
br_netfilter
EOF
sudo modprobe overlay && sudo modprobe br_netfilter

cat <<'EOF' | sudo tee /etc/sysctl.d/k8s.conf
net.ipv4.ip_forward                 = 1
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
EOF
sudo sysctl --system
sysctl net.ipv4.ip_forward net.bridge.bridge-nf-call-iptables
```

> 官方文档只强制要求 `net.ipv4.ip_forward=1`；`br_netfilter` 与 bridge-nf-call 是多数 CNI（如 Flannel）仍需要的设置，具体以所选 CNI 文档为准。

### B.4 所有节点：安装 containerd 并启用 systemd cgroup 驱动

**Ubuntu 24.04**

```bash
sudo apt-get update && sudo apt-get install -y containerd
```

**RHEL 10 / Rocky / Alma 10**（RHEL 官方仓库不提供 containerd，常用 Docker 官方仓库的 `containerd.io` 包；支持的系统版本以 Docker 文档为准）

```bash
sudo dnf install -y dnf-plugins-core
sudo dnf config-manager --add-repo https://download.docker.com/linux/rhel/docker-ce.repo    # Rocky/Alma 用 .../linux/centos/docker-ce.repo
sudo dnf install -y containerd.io
```

**两种系统通用：生成默认配置并改 cgroup 驱动**

```bash
sudo mkdir -p /etc/containerd
containerd config default | sudo tee /etc/containerd/config.toml >/dev/null   # 覆盖包自带的（可能禁用了 cri 插件）
sudo sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml
grep -n 'SystemdCgroup' /etc/containerd/config.toml    # 必须看到 = true；若没有该行，按 container-runtimes.md 手动加到 runc.options 段
sudo systemctl enable --now containerd && sudo systemctl restart containerd
```

### B.5 所有节点：安装 kubelet / kubeadm / kubectl（pkgs.k8s.io，每个小版本一个仓库）

**Ubuntu 24.04**

```bash
K8S=v1.37                                        # 想练升级就先写 v1.36
sudo apt-get install -y apt-transport-https ca-certificates curl gpg
sudo mkdir -p -m 755 /etc/apt/keyrings
curl -fsSL https://pkgs.k8s.io/core:/stable:/${K8S}/deb/Release.key | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/${K8S}/deb/ /" | sudo tee /etc/apt/sources.list.d/kubernetes.list
sudo apt-get update && sudo apt-get install -y kubelet kubeadm kubectl
sudo apt-mark hold kubelet kubeadm kubectl
sudo systemctl enable --now kubelet              # 在 kubeadm init 前会反复重启，属正常
```

**RHEL 10 / Rocky / Alma 10**

```bash
K8S=v1.37
cat <<EOF | sudo tee /etc/yum.repos.d/kubernetes.repo
[kubernetes]
name=Kubernetes
baseurl=https://pkgs.k8s.io/core:/stable:/${K8S}/rpm/
enabled=1
gpgcheck=1
gpgkey=https://pkgs.k8s.io/core:/stable:/${K8S}/rpm/repodata/repomd.xml.key
exclude=kubelet kubeadm kubectl cri-tools kubernetes-cni
EOF
sudo dnf install -y kubelet kubeadm kubectl --disableexcludes=kubernetes
# 若系统是 DNF5，上面的参数改为：--setopt=disable_excludes=kubernetes
sudo systemctl enable --now kubelet
```

### B.6 仅 RHEL 系：SELinux 与 firewalld

官方安装文档要求将 SELinux 设为 permissive（复习：[RHCSA-09 防火墙与 SELinux](../../notes/rhcsa/09-security-firewalld-selinux.md)）：

```bash
sudo setenforce 0
sudo sed -i 's/^SELINUX=enforcing$/SELINUX=permissive/' /etc/selinux/config
getenforce
```

firewalld 二选一：

```bash
# 选项 1（顺便练 RHCSA）：按官方端口表放行
# 控制平面：
sudo firewall-cmd --permanent --add-port={6443,2379-2380,10250,10257,10259}/tcp
# worker：
sudo firewall-cmd --permanent --add-port={10250,10256}/tcp --add-port=30000-32767/{tcp,udp}
# CNI 端口另加（例：Calico BGP 179/tcp、VXLAN 4789/udp；Flannel VXLAN 8472/udp —— 以 CNI 文档为准）
sudo firewall-cmd --reload && sudo firewall-cmd --list-all

# 选项 2（纯实验、排除干扰）：
sudo systemctl disable --now firewalld
```

### B.7 控制平面：kubeadm init

```bash
sudo kubeadm init \
  --apiserver-advertise-address=192.168.56.10 \
  --pod-network-cidr=10.244.0.0/16
# 想以后练 HA：再加 --control-plane-endpoint=<DNS 或 VIP>:6443 --upload-certs（见 notes/cka/05-ha-control-plane.md）

mkdir -p $HOME/.kube
sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config
kubectl get nodes        # NotReady：还没装 CNI，正常
```

**把输出最后的 `kubeadm join ...` 命令保存下来。**

### B.8 控制平面：安装 CNI（二选一）

```bash
# 推荐 Calico：支持 NetworkPolicy（练 K12 必需）。版本见 https://github.com/projectcalico/calico/releases
kubectl apply -f https://raw.githubusercontent.com/projectcalico/calico/<版本>/manifests/calico.yaml
# Calico 清单方式通常会识别 kubeadm 的 --pod-network-cidr；若 Pod IP 不在 10.244.0.0/16，
# 下载清单后修改 CALICO_IPV4POOL_CIDR 再 apply（以 Calico 官方文档为准）

# 或 Flannel：最简单，但 **不执行 NetworkPolicy**；默认网段正好是 10.244.0.0/16
kubectl apply -f https://github.com/flannel-io/flannel/releases/latest/download/kube-flannel.yml
# 多网卡 VM 上 Flannel 可能选错网卡，需要在 DaemonSet 参数里加 --iface=<host-only 网卡名>

kubectl get pods -A -w   # 等 CNI 和 CoreDNS 都 Running
```

### B.9 worker：加入集群

```bash
sudo kubeadm join 192.168.56.10:6443 --token <token> --discovery-token-ca-cert-hash sha256:<hash>
# token 过期（默认 24h）：在 cp1 上 kubeadm token create --print-join-command
```

### B.10 验证与常用附加组件

```bash
kubectl get nodes -o wide                             # 3 个节点 Ready
kubectl create deploy web --image=nginx --replicas=3 && kubectl get pods -o wide   # 分布在两个 worker
kubectl expose deploy web --port=80 --type=NodePort && kubectl get svc web
curl http://192.168.56.11:<NodePort>                  # 返回 nginx 欢迎页

# Helm（官方脚本，见 references/cka/helm-docs/intro/install.mdx）
curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-4 | bash

# metrics-server（kubectl top 需要；实验环境 kubelet 是自签证书，需加 --kubelet-insecure-tls）
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml
kubectl -n kube-system patch deploy metrics-server --type=json \
  -p '[{"op":"add","path":"/spec/template/spec/containers/0/args/-","value":"--kubelet-insecure-tls"}]'
kubectl top nodes

# 动态存储（练 K14 的 StorageClass）：rancher local-path-provisioner，版本见其 GitHub Releases
kubectl apply -f https://raw.githubusercontent.com/rancher/local-path-provisioner/<版本>/deploy/local-path-storage.yaml

# etcdctl / etcdutl（kubeadm 不自带；版本与集群 etcd 一致）
kubectl -n kube-system get pod etcd-cp1 -o jsonpath='{.spec.containers[0].image}'; echo   # 查 etcd 版本
ETCD_VER=v3.6.x   # 替换为上面查到的版本
curl -fsSL https://github.com/etcd-io/etcd/releases/download/${ETCD_VER}/etcd-${ETCD_VER}-linux-amd64.tar.gz | tar xz
sudo mv etcd-${ETCD_VER}-linux-amd64/{etcdctl,etcdutl} /usr/local/bin/

# Gateway API CRD（standard channel；版本号以 Gateway API 入门文档为准）
kubectl apply --server-side -f https://github.com/kubernetes-sigs/gateway-api/releases/download/<版本>/standard-install.yaml
kubectl get crd | grep gateway.networking.k8s.io
```

Ingress 控制器和 Gateway API 实现（练 K13 用）：CRD 只是 API 定义，还要装一个真正处理流量的控制器。
安装思路和可选实现见 [practice-set-1 的 K13 小节开头](practice-set-1.md#k13-ingress-与-gateway-api)，
CRD 安装命令见 [Gateway API 入门](../../references/cka/gateway-api-docs/guides/getting-started/introduction.md)。

### B.11 快照策略（非常重要）

| 快照名 | 时间点 | 用途 |
|---|---|---|
| `00-os-base` | 刚装完系统、配好网络 | 重新练「准备基础设施 + kubeadm init」 |
| `01-prereq-done` | 做完 B.1～B.6 | 只练 init/join/CNI |
| `02-cluster-ready` | B.10 完成 | 日常练习起点；练排错、练升级前都回到这里 |

练「搞坏再修好」之前先打快照；修不好就回滚，然后对照 [K15 排错](../../notes/cka/15-troubleshooting.md) 复盘。

### B.12 搭建常见问题

| 现象 | 排查方向 |
|---|---|
| `kubeadm init` preflight 报 swap | B.2 没做或没持久化 |
| preflight 报 `ip_forward` | B.3 的 sysctl 没生效 |
| 卡在 `waiting for the kubelet to boot up the control plane` | `journalctl -u kubelet -f`；多半是 cgroup 驱动不一致或 containerd 的 cri 插件被禁用 |
| 节点一直 NotReady | CNI 没装好：`kubectl -n kube-system get pods`、`ls /etc/cni/net.d/` |
| worker join 超时 | 6443 不通（firewalld）、时间不同步、用错 IP |
| CoreDNS 一直 Pending | 还没有 Ready 的节点（先装 CNI） |
| 重来一遍 | `sudo kubeadm reset -f && sudo rm -rf /etc/cni/net.d $HOME/.kube`，再清理 iptables 或直接回滚快照 |

---

## 方案 C：killercoda 免费在线环境

- [killercoda.com/killer-shell-cka](https://killercoda.com/killer-shell-cka)：killer.sh 团队维护的 CKA 场景，浏览器里直接得到一个小集群。
- [killercoda.com/playgrounds](https://killercoda.com/playgrounds)：空白 Kubernetes playground，临时验证命令用。
- 正式的 killer.sh 模拟考（购买 CKA 考试附赠，以官网为准）留到最后两周再用，难度高于真实考试。

## 官方文档（本仓库离线版）

- [install-kubeadm.md](../../references/cka/kubernetes-docs/setup/production-environment/tools/kubeadm/install-kubeadm.md) · [create-cluster-kubeadm.md](../../references/cka/kubernetes-docs/setup/production-environment/tools/kubeadm/create-cluster-kubeadm.md) · [container-runtimes.md](../../references/cka/kubernetes-docs/setup/production-environment/container-runtimes.md)
- [ports-and-protocols.md](../../references/cka/kubernetes-docs/reference/networking/ports-and-protocols.md) · [troubleshooting-kubeadm.md](../../references/cka/kubernetes-docs/setup/production-environment/tools/kubeadm/troubleshooting-kubeadm.md)
- [install-kubectl-linux.md](../../references/cka/kubernetes-docs/tasks/tools/install-kubectl-linux.md) · [Helm 安装](../../references/cka/helm-docs/intro/install.mdx)
