# CKA-13 Ingress 与 Gateway API

> **轨道**：[CKA](README.md) ｜ **考纲**：CKA「Services and Networking (20%)」——Use the Gateway API to manage Ingress traffic；Know how to use Ingress controllers and Ingress resources ｜ **建议用时**：6 h ｜ **难度**：★★★
>
> **前置**：[CKA-11 Service 与 CoreDNS](11-services-dns.md)
> **后续**：[CKA-15 排错](15-troubleshooting.md)
> **关联**（跨轨道）：[CKA-08 扩展接口与 CRD](08-extension-interfaces-crd.md)（Gateway API 本身就是一组 CRD） · [CKA-07 Helm 与 Kustomize](07-helm-kustomize.md)（控制器通常用 Helm 安装） · [F6 TLS / PKI 基础](../00-foundations/06-tls-pki-basics.md) · [F3 网络基础](../00-foundations/03-networking-basics.md)

## 1. 这个知识点在网络中的位置

Service（K11）是四层的；HTTP 层面「按域名/路径把流量分给不同服务、终止 TLS」需要七层入口：

- **Ingress**：老牌 API（`networking.k8s.io/v1`），官方已宣布 **Ingress API 冻结**（不删除，但不再增加功能），并推荐新项目使用 Gateway API。
- **Gateway API**：2025 年新版 CKA 考纲加入，按角色拆分成 GatewayClass / Gateway / HTTPRoute 等多个对象，功能（流量拆分、重定向、头部改写、跨命名空间）是原生字段而不是各家控制器的注解。

两者都**只是 API**：必须有控制器（Ingress Controller / Gateway 实现，如 Envoy Gateway、Cilium、Istio、NGINX Gateway Fabric、Traefik 等）才会真正生效。
用 docker 时你可能在 compose 里放一个 nginx/traefik 反向代理并挂上 `nginx.conf`——Ingress/Gateway 就是把那份配置文件变成了 K8s 对象，由控制器自动生成代理配置。

## 2. 核心概念

**Ingress**

- `ingressClassName` 指定哪个控制器处理；集群可以有一个默认 IngressClass（注解 `ingressclass.kubernetes.io/is-default-class: "true"`）。
- `rules[].host` + `http.paths[]`，每个 path **必须**写 `pathType`：`Prefix`（按 `/` 分段前缀匹配）、`Exact`、`ImplementationSpecific`。
- `tls[]`：`hosts` + `secretName`（`kubernetes.io/tls` 类型 Secret，与 Ingress **同命名空间**）。
- `defaultBackend`：都不匹配时的去处。

**Gateway API**（`gateway.networking.k8s.io/v1`）

| 对象 | 谁负责 | 作用 | 类比 |
|---|---|---|---|
| GatewayClass | 基础设施提供方 | 声明用哪个控制器（`controllerName`），集群级 | IngressClass |
| Gateway | 集群运维 | 监听器：协议、端口、主机名、TLS 证书、允许哪些命名空间的路由挂上来 | 「一台负载均衡器」 |
| HTTPRoute / GRPCRoute | 应用开发 | 匹配规则（主机名、路径、头部、查询参数、方法）→ 后端 Service，可带 filters 和权重 | Ingress 的 rules |
| ReferenceGrant | 被引用方命名空间 | 允许其他命名空间的 Route 引用本命名空间的 Service/Secret | 跨命名空间授权 |

- Route 通过 `parentRefs`（可带 `sectionName` 选择特定监听器）挂到 Gateway；Gateway 默认只接受**同命名空间**的 Route，跨命名空间要配 `allowedRoutes.namespaces.from: All | Selector`。
- 常用 filters：`RequestRedirect`（如 HTTP→HTTPS）、`URLRewrite`、`RequestHeaderModifier`、`RequestMirror`。
- 流量拆分：同一 rule 的多个 `backendRefs` 设 `weight`（金丝雀发布）。
- 状态排查看 conditions：Gateway `Accepted` / `Programmed`，Route `Accepted` / `ResolvedRefs`。
- CRD 需要单独安装（standard channel）：`kubectl apply --server-side -f https://github.com/kubernetes-sigs/gateway-api/releases/download/<版本>/standard-install.yaml`。考试环境一般已装好 CRD 和控制器。

**Ingress → Gateway API 字段对照**（考纲有「迁移」类题目的可能）：

| Ingress | Gateway API |
|---|---|
| `ingressClassName` | Gateway 的 `gatewayClassName` |
| `tls[].secretName` | Gateway listener 的 `tls.certificateRefs` |
| `rules[].host` | HTTPRoute 的 `hostnames`（也可在 listener 上限制 `hostname`） |
| `paths[].path` + `pathType: Prefix/Exact` | `matches[].path.type: PathPrefix/Exact` + `value` |
| `backend.service.name/port.number` | `backendRefs[].name/port` |
| 控制器专有注解（rewrite、canary…） | 原生 `filters`、`weight` |

## 3. 必会操作

```bash
# Ingress
kubectl get ingressclass
kubectl create ingress shop -n shop --class=nginx \
  --rule="shop.example.com/api*=api:8080,tls=shop-tls" \
  --rule="shop.example.com/*=frontend:80" --dry-run=client -o yaml
#   path 末尾带 * → pathType=Prefix；不带 * → Exact（见 kubectl create ingress -h 的示例）
kubectl describe ingress shop                    # 看 Rules/Backends 是否解析到 Endpoints
kubectl create secret tls shop-tls --cert=shop.crt --key=shop.key

# Gateway API
kubectl get gatewayclass,gateway,httproute -A
kubectl describe gateway web-gw -n infra         # Listeners 的 Attached Routes、Conditions
kubectl describe httproute shop -n shop          # Parents 下的 Accepted / ResolvedRefs
kubectl explain httproute.spec.rules --recursive | less
kubectl api-resources | grep gateway.networking

# 测试：-H 指定 Host 头，或 --resolve 把域名指到入口 IP
curl -H "Host: shop.example.com" http://<gateway-或-ingress-IP>/api
curl -k --resolve shop.example.com:443:<IP> https://shop.example.com/
```

Ingress（带 TLS 和两个路径）：

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: shop
  namespace: shop
spec:
  ingressClassName: nginx
  tls:
  - hosts: [shop.example.com]
    secretName: shop-tls
  rules:
  - host: shop.example.com
    http:
      paths:
      - path: /api
        pathType: Prefix
        backend:
          service: {name: api, port: {number: 8080}}
      - path: /
        pathType: Prefix
        backend:
          service: {name: frontend, port: {number: 80}}
```

Gateway（HTTP + HTTPS 两个监听器，允许带标签的命名空间挂路由）：

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: web-gw
  namespace: infra
spec:
  gatewayClassName: example-class        # kubectl get gatewayclass 查实际名字
  listeners:
  - name: http
    protocol: HTTP
    port: 80
    allowedRoutes:
      namespaces: {from: All}
  - name: https
    protocol: HTTPS
    port: 443
    hostname: shop.example.com
    tls:
      mode: Terminate
      certificateRefs:
      - {kind: Secret, name: shop-tls}    # Secret 在 Gateway 所在命名空间（infra）
    allowedRoutes:
      namespaces:
        from: Selector
        selector:
          matchLabels: {kubernetes.io/metadata.name: shop}
```

HTTPRoute（路径路由 + 90/10 金丝雀），以及 HTTP→HTTPS 跳转：

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: shop
  namespace: shop
spec:
  parentRefs:
  - {name: web-gw, namespace: infra, sectionName: https}
  hostnames: [shop.example.com]
  rules:
  - matches:
    - path: {type: PathPrefix, value: /api}
    backendRefs:
    - {name: api-v1, port: 8080, weight: 90}
    - {name: api-v2, port: 8080, weight: 10}
  - matches:
    - path: {type: PathPrefix, value: /}
    backendRefs:
    - {name: frontend, port: 80}
---
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: shop-redirect
  namespace: shop
spec:
  parentRefs:
  - {name: web-gw, namespace: infra, sectionName: http}
  hostnames: [shop.example.com]
  rules:
  - filters:
    - type: RequestRedirect
      requestRedirect: {scheme: https, statusCode: 301}
```

## 4. 考试坑点

- Ingress 的 `pathType` 必填；`Prefix` 的 `/api` 匹配 `/api`、`/api/x`，**不匹配** `/apix`。
- TLS Secret 必须和 Ingress 同命名空间；Gateway 的证书 Secret 默认必须和 Gateway 同命名空间（跨命名空间需要 ReferenceGrant）。
- HTTPRoute 引用**其他命名空间的 Service** 时，要在 Service 所在命名空间创建 ReferenceGrant，否则 `ResolvedRefs=False`。
- Route 挂不上 Gateway：检查 `parentRefs` 的名字/命名空间/`sectionName`，以及 Gateway listener 的 `allowedRoutes` 与 `hostname` 是否兼容。
- 题目给的 GatewayClass/IngressClass 名字以集群里实际存在的为准（`kubectl get gatewayclass`、`kubectl get ingressclass`）。
- 考场文档：kubernetes.io 的 Gateway 概念页有 GatewayClass/Gateway/HTTPRoute 模板；能否打开 gateway-api.sigs.k8s.io 以 LF 最新考生手册为准——所以本页的 YAML 要能**默写**。
- 写完用 `kubectl describe` 看 conditions，再用 `curl -H Host:` 实测，别只看 `created`。

## 5. 动手练习

- [CKA 练习题集 · K13 Ingress 与 Gateway API](../../labs/cka/practice-set-1.md#k13-ingress-与-gateway-api)（Ingress 路径与 TLS、Gateway + HTTPRoute、流量拆分、跳转、Ingress 迁移到 Gateway）
- [CKA 模拟考](../../labs/cka/mock-exam.md) 第 12、13 题

## 6. 官方文档（本仓库离线版 + 考场可用的查法）

- 离线：
  - [Ingress](../../references/cka/kubernetes-docs/concepts/services-networking/ingress.md) · [Ingress 控制器](../../references/cka/kubernetes-docs/concepts/services-networking/ingress-controllers.md) · [Gateway API（kubernetes.io 概念页）](../../references/cka/kubernetes-docs/concepts/services-networking/gateway.md)
  - Ingress 示例：[`minimal-ingress.yaml`](../../references/cka/kubernetes-docs/examples/service/networking/minimal-ingress.yaml) · [`name-virtual-host-ingress.yaml`](../../references/cka/kubernetes-docs/examples/service/networking/name-virtual-host-ingress.yaml) · [`default-ingressclass.yaml`](../../references/cka/kubernetes-docs/examples/service/networking/default-ingressclass.yaml)
  - Gateway API 官方站：[入门](../../references/cka/gateway-api-docs/guides/getting-started/introduction.md) · [简单 Gateway](../../references/cka/gateway-api-docs/guides/getting-started/simple-gateway.md) · [从 Ingress 迁移](../../references/cka/gateway-api-docs/guides/getting-started/migrating-from-ingress.md)
  - 用户指南：[HTTP 路由](../../references/cka/gateway-api-docs/guides/user-guides/http-routing.md) · [重定向与改写](../../references/cka/gateway-api-docs/guides/user-guides/http-redirect-rewrite.md) · [流量拆分](../../references/cka/gateway-api-docs/guides/user-guides/traffic-splitting.md) · [TLS](../../references/cka/gateway-api-docs/guides/user-guides/tls.md) · [跨命名空间](../../references/cka/gateway-api-docs/guides/user-guides/multiple-ns.md) · [头部修改](../../references/cka/gateway-api-docs/guides/user-guides/http-header-modifier.md)
  - API 参考：[Gateway](../../references/cka/gateway-api-docs/reference/api-types/gateway.md) · [GatewayClass](../../references/cka/gateway-api-docs/reference/api-types/gatewayclass.md) · [HTTPRoute](../../references/cka/gateway-api-docs/reference/api-types/httproute.md) · [ReferenceGrant](../../references/cka/gateway-api-docs/reference/api-types/referencegrant.md) · [排错（conditions 含义）](../../references/cka/gateway-api-docs/docs/concepts/troubleshooting.md)
  - 注：Gateway API 指南里的 `{{< readfile file="/examples/..." >}}` 引用的是 gateway-api 仓库的 `examples/` 目录，未随本仓库下载，可在 [GitHub](https://github.com/kubernetes-sigs/gateway-api/tree/main/examples/standard) 查看。
- 考场（kubernetes.io）：
  - `/docs/concepts/services-networking/ingress/`（Ingress YAML、pathType 规则表）
  - `/docs/concepts/services-networking/gateway/`（GatewayClass / Gateway / HTTPRoute 模板）
  - 命令行：`kubectl create ingress -h`、`kubectl explain gateway.spec.listeners --recursive`、`kubectl explain httproute.spec --recursive`

## 7. 自测清单

- [ ] 能用 `kubectl create ingress` 和 YAML 两种方式创建带 TLS、两条路径的 Ingress
- [ ] 能默写 Gateway（HTTP/HTTPS 监听器）+ HTTPRoute（路径匹配 + backendRefs）
- [ ] 能实现 90/10 流量拆分和 HTTP→HTTPS 301 跳转
- [ ] 能把一个现有 Ingress 等价改写成 Gateway + HTTPRoute
- [ ] 能根据 `Accepted`/`ResolvedRefs`/`Programmed` 条件判断问题出在哪一层
- [ ] 能解释为什么创建了 Ingress/Gateway 却没有任何效果（缺控制器 / class 名字不对）
