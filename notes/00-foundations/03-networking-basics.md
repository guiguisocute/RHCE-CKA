# F3 网络基础：IP、路由、DNS、端口

> **轨道**：[公共基础](README.md) ｜ **考纲**：EX200「Manage basic networking」的前提；CKA「Services & Networking」(20%) 的前提 ｜ **建议用时**：4 h ｜ **难度**：★★☆
>
> **前置**：[F1 Ubuntu → RHEL 对照](01-ubuntu-to-rhel.md)
> **后续**：[RHCSA-07 网络配置 nmcli](../rhcsa/07-networking-nmcli.md)
> **关联**（跨轨道）：[F6 TLS / PKI 基础](06-tls-pki-basics.md) · [RHCSA-09 防火墙与 SELinux](../rhcsa/09-security-firewalld-selinux.md) · [CKA-08 CNI](../cka/08-extension-interfaces-crd.md) · [CKA-11 Service 与 CoreDNS](../cka/11-services-dns.md) · [CKA-12 NetworkPolicy](../cka/12-network-policy.md)

## 1. 这个知识点在网络中的位置

RHCSA 要你用 `nmcli` 配静态 IP/网关/DNS；CKA 要你理解 Pod IP、Service 虚拟 IP、CoreDNS、NetworkPolicy。
如果不清楚「子网掩码、默认网关、DNS 解析顺序、端口监听」这些底层概念，两边都只能死记命令。
你在 docker 里遇到过的 `-p 8080:80`、bridge 网络、容器之间用服务名互相访问，本质都是这里的知识。

## 2. 核心概念

### 2.1 IPv4 / CIDR 速查

| CIDR | 掩码 | 可用主机数 | 场景 |
|---|---|---|---|
| /32 | 255.255.255.255 | 1（单个地址） | NetworkPolicy 里放行某一台主机 |
| /24 | 255.255.255.0 | 254 | 最常见的局域网 |
| /16 | 255.255.0.0 | 65534 | Calico 默认 Pod 网段 `192.168.0.0/16` |
| /12 | 255.240.0.0 | 约 100 万 | kubeadm 默认 Service 网段 `10.96.0.0/12` |

- 私有地址段：`10.0.0.0/8`、`172.16.0.0/12`、`192.168.0.0/16`（docker 默认 bridge 用 `172.17.0.0/16`）。
- 同一子网内直接通信（ARP 找 MAC）；跨子网要走**网关**（路由表里的 `default via`）。

### 2.2 IPv6 只需掌握这些（RHCSA 会考配置）

- 地址 128 位，写成 8 组十六进制：`2001:db8::10/64`，`::` 表示连续的 0。
- `fe80::/10` 是链路本地地址，每块网卡自动生成；`::1` 是回环。
- nmcli 配置方式和 IPv4 几乎一样，只是字段名是 `ipv6.addresses`、`ipv6.method manual`。

### 2.3 一次 `curl http://web.example.com:8080` 发生了什么

1. **名称解析**：按 `/etc/nsswitch.conf` 的 `hosts:` 行顺序，一般先查 `/etc/hosts`，再查 `/etc/resolv.conf` 里的 DNS 服务器。
2. **选路由**：查路由表，目标在本子网就直接发，否则发给默认网关。
3. **建立 TCP 连接**：目标主机上必须有进程**监听**该端口（`ss -tlnp` 能看到），且**防火墙放行**。
4. **应用层**：HTTP 请求/响应；若是 HTTPS 还要先做 TLS 握手（见 [F6](06-tls-pki-basics.md)）。

排错时就按这 4 步逐层检查：解析 → 路由 → 端口/防火墙 → 应用。CKA 里 Service 不通也是同一套思路，只是第 1 步换成 CoreDNS、第 2/3 步换成 kube-proxy/CNI。

### 2.4 要记住的端口

| 端口 | 服务 | 出现在 |
|---|---|---|
| 22/tcp | SSH | 全部 |
| 53/udp+tcp | DNS | RHCSA 解析、CKA CoreDNS |
| 80, 443/tcp | HTTP/HTTPS | RHCSA 防火墙 + SELinux 端口题 |
| 2049/tcp | NFS | RHCSA autofs / NFS 挂载 |
| 6443/tcp | kube-apiserver | CKA |
| 2379-2380/tcp | etcd | CKA 备份恢复 |
| 10250/tcp | kubelet API | CKA |
| 30000-32767 | NodePort | CKA Service |

### 2.5 和 Ubuntu / Docker 的对照

| 你熟悉的 | RHEL / Kubernetes 中 |
|---|---|
| netplan YAML + `netplan apply` | `nmcli connection modify ...` + `nmcli connection up ...` |
| `/etc/resolv.conf` 指向 `127.0.0.53`（systemd-resolved） | NetworkManager 直接写入真实 DNS 地址 |
| `ifconfig` / `netstat`（net-tools） | `ip` / `ss`（iproute2，RHEL 默认没有 net-tools） |
| docker bridge + veth pair | CNI 插件为每个 Pod 建 veth、分配 Pod IP |
| compose 里用服务名互访（内置 DNS） | CoreDNS：`<svc>.<ns>.svc.cluster.local` |
| `docker run -p 8080:80` | Service 的 `port` / `targetPort` / `nodePort` |

## 3. 必会操作

```bash
# —— 看地址和路由 ——
ip -br addr                    # 简洁列出所有网卡和 IP（-br = brief）
ip addr show dev ens160        # 某块网卡详情（网卡名以 ip link 输出为准）
ip route                       # 路由表；default via X 就是网关
ip -6 addr                     # IPv6 地址

# —— 名称解析 ——
cat /etc/hosts /etc/resolv.conf
grep ^hosts /etc/nsswitch.conf # 解析顺序
getent hosts server1           # 按 nsswitch 顺序解析（会查 /etc/hosts），最接近程序实际行为
dig +short example.com         # 只查 DNS（需 bind-utils 包）；dig 不看 /etc/hosts
host example.com               # 同样来自 bind-utils

# —— 连通性 ——
ping -c 3 192.168.122.1        # ICMP
tracepath 8.8.8.8              # 路由跟踪（RHEL 自带；traceroute 需另装）
curl -v http://server1:8080/   # 应用层测试，-v 看握手细节
nc -zv server1 2049            # 测端口是否可连（nmap-ncat 包）

# —— 端口监听 ——
sudo ss -tlnp                  # TCP 监听端口 + 进程（t=TCP l=listen n=数字 p=进程）
sudo ss -ulnp                  # UDP

# —— 主机名 ——
hostnamectl                    # 查看
sudo hostnamectl set-hostname server1.lab.example.com   # 永久修改
```

## 4. 考试坑点

- **`dig` 能解析但程序访问不了**：程序走 nsswitch，`dig` 不看 `/etc/hosts`；验证考题里的主机名解析请用 `getent hosts`。
- **服务起了但外面访问不到**：先 `ss -tlnp` 看监听的是 `127.0.0.1` 还是 `0.0.0.0`，再看 firewalld，最后看 SELinux 端口标签（见 [RHCSA-09](../rhcsa/09-security-firewalld-selinux.md)）。
- **网关/掩码写错**：`192.168.1.10/24` 的网关必须在 `192.168.1.0/24` 内；掩码写成 `/16` 可能导致和别的网段冲突。
- **改了网络没重新激活连接**：`nmcli con mod` 只改配置，需要 `nmcli con up <名字>` 才生效（远程操作时小心把自己断开）。
- **CKA：Pod 网段和节点网段重叠**：kubeadm init 时 `--pod-network-cidr` 不能和宿主机网段冲突，否则路由混乱。

## 5. 动手练习

- [`labs/rhcsa/practice-set-1.md`](../../labs/rhcsa/practice-set-1.md)：静态 IP、主机名、解析相关题
- [`labs/cka/practice-set-1.md`](../../labs/cka/practice-set-1.md)：Service / DNS 不通的排查题
- 自测题：`10.20.30.40/27` 的网络地址、广播地址、可用范围分别是什么？（答案：网络 `10.20.30.32`，广播 `10.20.30.63`，可用 `.33`~`.62`）

## 6. 官方文档（本仓库离线版 + 考场可用的查法）

- RHEL 在线：[Configuring and managing networking](https://docs.redhat.com/en/documentation/red_hat_enterprise_linux/10/html-single/configuring_and_managing_networking/index)
- 离线：[`references/cka/kubernetes-docs/reference/networking/ports-and-protocols.md`](../../references/cka/kubernetes-docs/reference/networking/ports-and-protocols.md)（K8s 各组件端口表）
- 离线：[`references/cka/kubernetes-docs/concepts/cluster-administration/networking.md`](../../references/cka/kubernetes-docs/concepts/cluster-administration/networking.md)（K8s 网络模型：每个 Pod 一个 IP）
- 离线：[`references/cka/kubernetes-docs/concepts/services-networking/dns-pod-service.md`](../../references/cka/kubernetes-docs/concepts/services-networking/dns-pod-service.md)（Service / Pod 的 DNS 命名规则）
- 离线：[`references/cka/kubernetes-docs/reference/networking/virtual-ips.md`](../../references/cka/kubernetes-docs/reference/networking/virtual-ips.md)（Service 虚拟 IP 与 kube-proxy）

考场查法：

```bash
man ip-address ip-route        # ip 子命令的手册（man ip 只是总览）
man ss
man nsswitch.conf              # 解析顺序
man 5 resolv.conf
man nmcli-examples             # 下一步 RHCSA-07 的救命手册
```

## 7. 自测清单

- [ ] 能手算任意 `/24`~`/30` 子网的网络地址、广播地址和可用范围
- [ ] 能按「解析 → 路由 → 端口/防火墙 → 应用」四步排查一个访问不通的服务
- [ ] 能解释 `getent hosts` 和 `dig` 结果不一致的原因
- [ ] 能说出 6443、2379、10250、30000-32767 分别是什么
- [ ] 能把 `docker run -p 8080:80` 对应到 K8s Service 的 `port`/`targetPort`/`nodePort`
