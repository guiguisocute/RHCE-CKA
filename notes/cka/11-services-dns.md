# CKA-11 Service 与 CoreDNS

> **轨道**：[CKA](README.md) ｜ **考纲**：CKA「Services and Networking (20%)」——Pod 间连通、ClusterIP/NodePort/LoadBalancer 与 endpoints、CoreDNS ｜ **建议用时**：6 h ｜ **难度**：★★☆
>
> **前置**：[CKA-09 工作负载](09-workloads.md) · [F3 网络基础](../00-foundations/03-networking-basics.md) · [RHCSA-07 网络配置 nmcli](../rhcsa/07-networking-nmcli.md)
> **后续**：[CKA-12 NetworkPolicy](12-network-policy.md) · [CKA-13 Ingress 与 Gateway API](13-ingress-gateway-api.md) · [CKA-15 排错](15-troubleshooting.md)
> **关联**（跨轨道）：[RHCSA-09 防火墙与 SELinux](../rhcsa/09-security-firewalld-selinux.md)（NodePort 端口要放行） · [CKA-08 扩展接口（CNI）](08-extension-interfaces-crd.md)

## 1. 这个知识点在网络中的位置

Pod 的 IP 随时会变（重建就换），Service 给一组 Pod 提供**稳定的虚拟 IP + DNS 名字**，并做负载均衡。
它向下依赖 CNI（K8）提供的「Pod 平坦网络」，向上是 Ingress/Gateway（K13）的后端、NetworkPolicy（K12）的作用对象，也是排错（K15）中「服务访问不通」的主战场。
docker compose 里服务之间直接用服务名互访（compose 内置 DNS），`ports: "8080:80"` 把端口映射到宿主机——在 K8s 里前者对应 **ClusterIP + CoreDNS**，后者对应 **NodePort / LoadBalancer**。

## 2. 核心概念

**K8s 网络模型**（CNI 插件必须满足）：每个 Pod 有独立 IP；所有 Pod 之间、节点与 Pod 之间无需 NAT 即可互通。所以「Pod 间连通」默认就是通的，除非 NetworkPolicy 限制或 CNI 坏了。

| Service 类型 | 访问方式 | 典型用途 |
|---|---|---|
| `ClusterIP`（默认） | 集群内 `svc-ip:port` 或 DNS 名 | 内部服务互访 |
| `NodePort` | 任意节点 `nodeIP:nodePort`（默认范围 30000–32767） | 实验环境对外暴露 |
| `LoadBalancer` | 云厂商/MetalLB 分配的外部 IP | 生产对外 |
| `ExternalName` | DNS CNAME 到外部域名，无代理 | 把外部服务纳入集群 DNS |
| Headless（`clusterIP: None`） | DNS 直接返回各 Pod IP | StatefulSet、客户端自己负载均衡 |

- **三个端口别搞混**：`port`（Service 自己的端口）、`targetPort`（容器端口，可写名字）、`nodePort`（节点端口）。
- **selector → EndpointSlice**：Service 按标签选择 **Ready** 的 Pod，控制器把它们的 IP 写进 EndpointSlice（标签 `kubernetes.io/service-name=<svc>`）。旧的 `Endpoints` API 自 v1.33 起已**废弃**（`kubectl get endpoints` 仍可用但会提示），排错时两者都能看。
- 没有 selector 的 Service：需要手工创建 EndpointSlice（对接集群外的数据库等）。
- **kube-proxy** 在每个节点上把 Service VIP 翻译成 Pod IP：模式有 `iptables`（默认）、`nftables`、`ipvs`（v1.35 起标记为废弃）。某些 CNI（如 Cilium）可以完全替代 kube-proxy。
- **CoreDNS**：
  - 以 Deployment `coredns` 运行在 `kube-system`，对外的 Service 名叫 **`kube-dns`**（历史原因），配置在 ConfigMap `coredns` 的 `Corefile` 里。
  - Service 记录：`<svc>.<ns>.svc.cluster.local`；同命名空间可直接用 `<svc>`，跨命名空间用 `<svc>.<ns>`。
  - Headless Service 的 Pod 记录：`<pod-hostname>.<svc>.<ns>.svc.cluster.local`（StatefulSet 常用）。
  - Pod 的 `/etc/resolv.conf` 由 kubelet 生成（`nameserver` = kube-dns 的 ClusterIP，`search` 域 + `ndots:5`）；`dnsPolicy` 默认 `ClusterFirst`。
- `sessionAffinity: ClientIP`：同一客户端固定到同一 Pod。
- `externalTrafficPolicy: Local`：保留客户端源 IP，只转发到本节点上的 Pod。

## 3. 必会操作

```bash
# 暴露 Deployment（selector 自动从 Deployment 复制，最不容易出错）
kubectl expose deployment web --name=web-svc --port=80 --target-port=8080 --type=ClusterIP
kubectl expose deployment web --name=web-np --port=80 --target-port=8080 --type=NodePort
# 指定 nodePort：expose 没有该参数，生成 YAML 后补 nodePort 字段，或用 create service（注意它的 selector 是 app=<名字>）
kubectl create service nodeport web --tcp=80:8080 --node-port=30080 --dry-run=client -o yaml
kubectl run web2 --image=nginx --port=80 --expose          # 一步创建 Pod + 同名 ClusterIP Service

# 看 Service 背后到底有哪些 Pod
kubectl get svc web-svc -o wide                              # SELECTOR 列
kubectl get endpointslices -l kubernetes.io/service-name=web-svc
kubectl get pods -l app=web -o wide --show-labels            # 对比标签是否匹配

# 临时调试 Pod：测连通与 DNS（busybox 自带 nslookup/wget）
kubectl run tmp --rm -it --image=busybox:1.36 --restart=Never -- sh
#   nslookup web-svc                          # 同命名空间
#   nslookup web-svc.prod.svc.cluster.local   # 全限定名
#   wget -qO- -T 2 http://web-svc:80
#   cat /etc/resolv.conf

# CoreDNS
kubectl -n kube-system get deploy,svc,cm -l k8s-app=kube-dns
kubectl -n kube-system get cm coredns -o yaml
kubectl -n kube-system edit cm coredns              # 改完 CoreDNS 会自动 reload（Corefile 中有 reload 插件时）
kubectl -n kube-system rollout restart deploy coredns
kubectl -n kube-system logs -l k8s-app=kube-dns
```

一个完整的 NodePort Service：

```yaml
apiVersion: v1
kind: Service
metadata:
  name: web-np
spec:
  type: NodePort
  selector: {app: web}         # 必须与 Pod 标签一致（不是 Deployment 的标签）
  ports:
  - name: http
    port: 80                   # Service 端口
    targetPort: 8080           # 容器端口（也可以写 containerPort 的 name）
    nodePort: 30080            # 不写则自动分配
    protocol: TCP
```

Corefile 片段（给集群加一个自定义上游/存根域——题目里常见的「让 example.internal 走 10.0.0.53」）：

```text
example.internal:53 {
    errors
    cache 30
    forward . 10.0.0.53
}
.:53 {
    errors
    health
    ready
    kubernetes cluster.local in-addr.arpa ip6.arpa {
       pods insecure
       fallthrough in-addr.arpa ip6.arpa
    }
    forward . /etc/resolv.conf
    cache 30
    loop
    reload
    loadbalance
}
```

## 4. 考试坑点

- Service 不通的第一检查：**EndpointSlice 为空 = selector 和 Pod 标签对不上，或 Pod 没 Ready**（readinessProbe 失败）。
- `targetPort` 写成了 Service 端口、或容器其实监听的是另一个端口——`kubectl exec` 进去 `ss -lntp`/`netstat` 看实际监听。
- 题目说「暴露为 NodePort 30xxx」，`kubectl expose` 生成的随机端口不算对，需要显式写 `nodePort`。
- 同一命名空间内用短名；跨命名空间必须带 `<ns>`。`nslookup` 失败时先确认 Pod 用的是哪个 namespace。
- busybox 的 `nslookup` 在某些版本对 search 域处理怪异，必要时用全限定名或换 `registry.k8s.io/e2e-test-images/agnhost` / `nicolaka/netshoot` 镜像（考场一般有 busybox）。
- `kube-dns` Service 的 ClusterIP 和 kubelet `clusterDNS` 配置不一致 → 所有 Pod DNS 失败（排错题常见）。
- 不要用 `ping` 测 Service IP：Service VIP 一般不响应 ICMP，用 `wget`/`curl`/`nc`。

## 5. 动手练习

- [CKA 练习题集 · K11 Service 与 CoreDNS](../../labs/cka/practice-set-1.md#k11-service-与-coredns)（ClusterIP/NodePort/Headless、EndpointSlice、DNS 解析、CoreDNS 存根域）
- [CKA 模拟考](../../labs/cka/mock-exam.md) 第 9、10 题

## 6. 官方文档（本仓库离线版 + 考场可用的查法）

- 离线：
  - [Service](../../references/cka/kubernetes-docs/concepts/services-networking/service.md) · [EndpointSlice](../../references/cka/kubernetes-docs/concepts/services-networking/endpoint-slices.md) · [虚拟 IP 与 kube-proxy 模式](../../references/cka/kubernetes-docs/reference/networking/virtual-ips.md) · [服务流量策略](../../references/cka/kubernetes-docs/concepts/services-networking/service-traffic-policy.md)
  - [Service 与 Pod 的 DNS](../../references/cka/kubernetes-docs/concepts/services-networking/dns-pod-service.md) · [使用 CoreDNS](../../references/cka/kubernetes-docs/tasks/administer-cluster/coredns.md) · [自定义 DNS 服务](../../references/cka/kubernetes-docs/tasks/administer-cluster/dns-custom-nameservers.md) · [调试 DNS 解析](../../references/cka/kubernetes-docs/tasks/administer-cluster/dns-debugging-resolution.md)
  - [集群网络模型](../../references/cka/kubernetes-docs/concepts/cluster-administration/networking.md) · [用 Service 连接前后端](../../references/cka/kubernetes-docs/tasks/access-application-cluster/connecting-frontend-backend.md) · [用 Service 访问集群中的应用](../../references/cka/kubernetes-docs/tasks/access-application-cluster/service-access-application-cluster.md)
  - 示例 YAML：[`examples/service/`](../../references/cka/kubernetes-docs/examples/service/)
- 考场（kubernetes.io）：
  - `/docs/concepts/services-networking/service/`（各类型 YAML）
  - `/docs/concepts/services-networking/dns-pod-service/`（DNS 记录格式）
  - `/docs/tasks/administer-cluster/dns-debugging-resolution/`（`dnsutils` 测试 Pod 和排查步骤）
  - 命令行：`kubectl expose -h`、`kubectl create service nodeport -h`、`kubectl explain service.spec.ports`

## 7. 自测清单

- [ ] 能分别用 `expose` 和 YAML 创建 ClusterIP、NodePort（指定端口）、Headless Service
- [ ] 能说出 `port` / `targetPort` / `nodePort` 的区别，并画出一个请求从节点端口到容器的路径
- [ ] Service 访问不通时，能在 3 分钟内定位是标签、端口、Ready 还是 DNS 问题
- [ ] 能写出 Service、跨命名空间 Service、Headless Pod 的 DNS 全名
- [ ] 能修改 CoreDNS Corefile 添加存根域并验证生效
- [ ] 能把 compose 的「服务名互访」和「端口映射」分别翻译成 K8s 对象
