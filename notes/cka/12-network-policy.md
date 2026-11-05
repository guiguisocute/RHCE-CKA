# CKA-12 NetworkPolicy

> **轨道**：[CKA](README.md) ｜ **考纲**：CKA「Services and Networking (20%)」——Define and enforce Network Policies ｜ **建议用时**：4 h ｜ **难度**：★★★
>
> **前置**：[CKA-11 Service 与 CoreDNS](11-services-dns.md)
> **后续**：[CKA-15 排错](15-troubleshooting.md) · [CKA-13 Ingress 与 Gateway API](13-ingress-gateway-api.md)
> **关联**（跨轨道）：[RHCSA-09 防火墙与 SELinux](../rhcsa/09-security-firewalld-selinux.md)（firewalld zone ↔ NetworkPolicy） · [F3 网络基础](../00-foundations/03-networking-basics.md) · [CKA-08 扩展接口（CNI）](08-extension-interfaces-crd.md)

## 1. 这个知识点在网络中的位置

K8s 默认「所有 Pod 互通」，NetworkPolicy 是 Pod 级的**白名单防火墙**。
它的思维方式和 RHCSA 的 firewalld 很像（默认拒绝 + 按来源/端口放行），只不过「来源」用**标签**而不是 IP 来描述。
NetworkPolicy 只是一个 API 对象，**真正执行的是 CNI 插件**（Calico、Cilium 支持；Flannel 单独使用时**不支持**）——这是它和 K8（CNI）的连接点。docker compose 里最接近的是自定义 `networks:` 隔离，但那是网络级的，粒度粗得多。

## 2. 核心概念

- **被选中才受约束**：`spec.podSelector` 选中的 Pod 才受此策略影响；`podSelector: {}` = 本命名空间所有 Pod。
- **policyTypes**：`Ingress`（进入 Pod 的流量）、`Egress`（Pod 发出的流量）。一旦某方向被任意策略选中，该方向变为「**默认拒绝，只放行规则里列出的**」。
- **多条策略是并集（OR）**，没有「拒绝规则」，也没有优先级。
- **from / to 的四种来源**：
  | 写法 | 含义 |
  |---|---|
  | `podSelector` | **同命名空间**内带某标签的 Pod |
  | `namespaceSelector` | 带某标签的**命名空间**里的所有 Pod |
  | `namespaceSelector` + `podSelector`（同一个 `-` 元素里） | 指定命名空间里的指定 Pod（**AND**） |
  | `ipBlock` | CIDR（可带 `except`），一般用于集群外地址 |
- **YAML 里最致命的细节**——列表元素的划分决定 AND / OR：

```yaml
  ingress:
  - from:
    - namespaceSelector: {matchLabels: {team: a}}
      podSelector: {matchLabels: {role: client}}     # 同一个元素：team=a 命名空间里的 role=client（AND）
  - from:
    - namespaceSelector: {matchLabels: {team: a}}
    - podSelector: {matchLabels: {role: client}}     # 两个元素：team=a 的所有 Pod，或本命名空间的 role=client（OR）
```

- 每个命名空间都有自动标签 `kubernetes.io/metadata.name=<ns>`，用它选择命名空间最省事，不用另外打标签。
- **Egress 默认拒绝时别忘了 DNS**：要放行到 `kube-system` 的 CoreDNS 的 UDP/TCP 53，否则 Pod 连域名都解析不了。
- 端口：`ports` 可写 `port` + `protocol`，或端口范围 `port` + `endPort`。

## 3. 必会操作

```bash
kubectl get networkpolicy -A                    # 简写 netpol
kubectl describe netpol <name> -n <ns>          # describe 会把规则翻译成人话，检查 AND/OR 最方便
kubectl label ns prod team=prod                 # 给命名空间打标签
kubectl get ns --show-labels

# 验证：从不同命名空间/不同标签的 Pod 发请求
kubectl run t1 -n dev --rm -it --image=busybox:1.36 --restart=Never -- wget -qO- -T 2 http://api.prod
kubectl run t2 -n prod --rm -it --labels=role=frontend --image=busybox:1.36 --restart=Never -- wget -qO- -T 2 http://api
```

模板 1：命名空间默认拒绝所有入站（最常用的起点）：

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-deny-ingress
  namespace: prod
spec:
  podSelector: {}
  policyTypes: [Ingress]
```

模板 2：只允许 `frontend` 命名空间里 `role=web` 的 Pod 访问 `app=api` 的 8080 端口：

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: api-allow-frontend
  namespace: prod
spec:
  podSelector:
    matchLabels: {app: api}
  policyTypes: [Ingress]
  ingress:
  - from:
    - namespaceSelector:
        matchLabels: {kubernetes.io/metadata.name: frontend}
      podSelector:
        matchLabels: {role: web}
    ports:
    - {protocol: TCP, port: 8080}
```

模板 3：限制出站，只允许访问 DB 和 DNS：

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: api-egress
  namespace: prod
spec:
  podSelector:
    matchLabels: {app: api}
  policyTypes: [Egress]
  egress:
  - to:
    - podSelector:
        matchLabels: {app: db}
    ports:
    - {protocol: TCP, port: 5432}
  - to:
    - namespaceSelector:
        matchLabels: {kubernetes.io/metadata.name: kube-system}
      podSelector:
        matchLabels: {k8s-app: kube-dns}
    ports:
    - {protocol: UDP, port: 53}
    - {protocol: TCP, port: 53}
```

## 4. 考试坑点

- 先读清楚题目要的是 **Ingress、Egress 还是两者**，`policyTypes` 写全。只写 `egress:` 规则不写 `policyTypes` 时，API 会根据规则推断，但显式写出最稳。
- `namespaceSelector` 与 `podSelector` 前面多一个 `-` 就从 AND 变成 OR——提交后一定 `kubectl describe netpol` 看翻译结果。
- `ingress: [{}]`（一个空规则）= 允许所有入站；`ingress: []` 或不写 = 拒绝所有入站（在 policyTypes 含 Ingress 时）。
- 策略对 Service 端口无效，**`ports` 要写 Pod 的容器端口**（targetPort），不是 Service 的 port。
- `ipBlock` 对 Pod IP 无意义（Pod IP 会变，且经 SNAT 后可能不匹配），选 Pod 用标签。
- 题目给了现成的多个 NetworkPolicy 让你「选出正确的那个并应用」时，逐一 `describe` 对比，最小权限的那个往往是答案。
- 实验环境用 Flannel 的话策略不会生效——自己练习要装 Calico 或 Cilium（见 [CKA 实验环境](../../labs/cka/00-lab-setup.md)）。

## 5. 动手练习

- [CKA 练习题集 · K12 NetworkPolicy](../../labs/cka/practice-set-1.md#k12-networkpolicy)（默认拒绝、跨命名空间放行、Egress + DNS、AND/OR 辨析）
- [CKA 模拟考](../../labs/cka/mock-exam.md) 第 11 题

## 6. 官方文档（本仓库离线版 + 考场可用的查法）

- 离线：
  - [Network Policies 概念](../../references/cka/kubernetes-docs/concepts/services-networking/network-policies.md)（含 default deny / allow all 全套模板）
  - [声明网络策略（任务）](../../references/cka/kubernetes-docs/tasks/administer-cluster/declare-network-policy.md)
  - 示例 YAML：[`networkpolicy.yaml`](../../references/cka/kubernetes-docs/examples/service/networking/networkpolicy.yaml) · [`network-policy-default-deny-all.yaml`](../../references/cka/kubernetes-docs/examples/service/networking/network-policy-default-deny-all.yaml) · [`network-policy-default-deny-egress.yaml`](../../references/cka/kubernetes-docs/examples/service/networking/network-policy-default-deny-egress.yaml) · [`networkpolicy-multiport-egress.yaml`](../../references/cka/kubernetes-docs/examples/service/networking/networkpolicy-multiport-egress.yaml)
- 考场（kubernetes.io）：
  - `/docs/concepts/services-networking/network-policies/`——页面里的第一个完整示例同时包含 ipBlock、namespaceSelector、podSelector、ingress、egress，复制后删减最快
  - 命令行：`kubectl explain networkpolicy.spec.ingress.from --recursive`

## 7. 自测清单

- [ ] 能不查文档写出 default-deny（入站/出站/全部）三种策略
- [ ] 能讲清 `namespaceSelector` 和 `podSelector` 放在同一元素与不同元素的区别
- [ ] 能写出允许指定命名空间 + 指定标签 + 指定端口的入站策略，并用临时 Pod 验证「该通的通、不该通的不通」
- [ ] 做 Egress 限制时记得放行 DNS
- [ ] 能解释为什么 NetworkPolicy 在 Flannel 集群上「写了没用」
