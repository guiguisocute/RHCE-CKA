# F6 TLS / PKI 基础：证书、CA 与 kubeconfig

> **轨道**：[公共基础](README.md) ｜ **考纲**：CKA「Cluster Architecture」(25%) 中证书、RBAC、etcd 备份的前提 ｜ **建议用时**：3 h ｜ **难度**：★★☆
>
> **前置**：[F3 网络基础](03-networking-basics.md)
> **后续**：[CKA-04 集群生命周期：升级与 etcd 备份恢复](../cka/04-cluster-lifecycle.md) · [CKA-06 RBAC 与 ServiceAccount](../cka/06-rbac.md)
> **关联**（跨轨道）：[CKA-01 集群架构与组件](../cka/01-architecture.md) · [CKA-03 kubeadm 装集群](../cka/03-kubeadm-install.md) · [CKA-13 Ingress 与 Gateway API（TLS 终止）](../cka/13-ingress-gateway-api.md) · [RHCSA-09 SSH 密钥认证](../rhcsa/09-security-firewalld-selinux.md) · [RHCE-02 向受管节点分发 SSH 密钥](../rhce/02-inventory-and-config.md)

## 1. 这个知识点在网络中的位置

Kubernetes 集群内部**所有组件之间都用 TLS 双向认证**：apiserver ↔ etcd、apiserver ↔ kubelet、你的 kubectl ↔ apiserver。
CKA 里「证书过期排查」「etcd 备份要带三个证书参数」「用证书创建一个新用户再给它绑 RBAC」都建立在这里。
RHCSA/RHCE 里的 **SSH 密钥认证**是同一类非对称加密思想，只是没有 CA 这一层——可以对照着理解。

## 2. 核心概念

| 概念 | 一句话 | 在 K8s 里的例子 |
|---|---|---|
| 非对称密钥对 | 私钥自己保管，公钥可以公开；私钥签名、公钥验证 | `apiserver.key` / `apiserver.crt` |
| 证书（X.509） | 「公钥 + 身份信息 + 有效期」，由 CA 用私钥签名 | `/etc/kubernetes/pki/*.crt` |
| CA | 签发证书的权威；谁信任 CA，谁就信任它签的证书 | `/etc/kubernetes/pki/ca.crt`（集群 CA）、`pki/etcd/ca.crt`（etcd 独立 CA） |
| Subject CN / O | 证书里的「名字」和「组织」 | **K8s 把客户端证书的 CN 当用户名、O 当用户组** |
| SAN | 证书对哪些域名/IP 有效 | apiserver 证书必须包含访问它所用的 IP/域名，否则报 x509 错误 |
| CSR | 证书签名请求：拿着公钥和身份信息请 CA 签名 | K8s 有 `CertificateSigningRequest` API |
| mTLS | 双方都出示证书互相验证 | etcd 要求客户端证书，所以 etcdctl 要带 `--cert/--key/--cacert` |
| kubeconfig | 记录「连哪个集群（CA + 地址）、用什么身份（证书或 token）」的 YAML | `~/.kube/config`、`/etc/kubernetes/admin.conf` |

### kubeconfig 的结构（三段 + 一个当前值）

```yaml
apiVersion: v1
kind: Config
clusters:                          # 连哪个集群
  - name: kubernetes
    cluster:
      server: https://192.168.122.10:6443
      certificate-authority-data: <base64 的 ca.crt>
users:                             # 用什么身份
  - name: kubernetes-admin
    user:
      client-certificate-data: <base64 的客户端证书>
      client-key-data: <base64 的私钥>
contexts:                          # 集群 + 用户（+ 默认命名空间）的组合
  - name: kubernetes-admin@kubernetes
    context: {cluster: kubernetes, user: kubernetes-admin, namespace: default}
current-context: kubernetes-admin@kubernetes
```

类比：SSH 的 `~/.ssh/config` 里写主机地址和用哪把密钥；kubeconfig 就是 kubectl 的 `~/.ssh/config`。

### kubeadm 集群的证书布局

- 目录：`/etc/kubernetes/pki/`（集群 CA、apiserver、front-proxy、sa 密钥），`/etc/kubernetes/pki/etcd/`（etcd 自己的 CA 和证书）。
- 默认有效期：叶子证书 **1 年**，CA **10 年**；`kubeadm upgrade` 时会自动续期叶子证书。
- 控制面组件的 kubeconfig：`/etc/kubernetes/{admin,super-admin,controller-manager,scheduler,kubelet}.conf`（`super-admin.conf` 自 v1.29 起出现）。

## 3. 必会操作

```bash
# —— 看懂一张证书 ——
openssl x509 -in /etc/kubernetes/pki/apiserver.crt -noout -subject -issuer -dates
openssl x509 -in /etc/kubernetes/pki/apiserver.crt -noout -text | grep -A1 "Subject Alternative Name"

# —— kubeadm 证书管理（CKA）——
sudo kubeadm certs check-expiration      # 所有证书的过期时间
sudo kubeadm certs renew all             # 续期全部（之后要重启控制面静态 Pod 才生效）

# —— 从 kubeconfig 里取出证书看 ——
kubectl config view --raw -o jsonpath='{.users[0].user.client-certificate-data}' \
  | base64 -d | openssl x509 -noout -subject     # 看当前用户的 CN/O

# —— 为新用户签发证书（CKA 常见：建用户 → 绑 RBAC，见 CKA-06）——
openssl genrsa -out alice.key 2048
openssl req -new -key alice.key -out alice.csr -subj "/CN=alice/O=dev"
cat <<EOF | kubectl apply -f -
apiVersion: certificates.k8s.io/v1
kind: CertificateSigningRequest
metadata:
  name: alice
spec:
  request: $(base64 -w0 < alice.csr)
  signerName: kubernetes.io/kube-apiserver-client
  expirationSeconds: 86400
  usages: ["client auth"]
EOF
kubectl certificate approve alice
kubectl get csr alice -o jsonpath='{.status.certificate}' | base64 -d > alice.crt

# —— 把新用户写进 kubeconfig ——
kubectl config set-credentials alice --client-certificate=alice.crt --client-key=alice.key --embed-certs=true
kubectl config set-context alice@kubernetes --cluster=kubernetes --user=alice
kubectl --context alice@kubernetes get pods      # 还没绑 RBAC，应该返回 Forbidden
kubectl config get-contexts                       # 列出所有 context
kubectl config use-context kubernetes-admin@kubernetes

# —— etcd 是 mTLS：三个证书参数缺一不可（详见 CKA-04）——
sudo etcdctl --endpoints=https://127.0.0.1:2379 \
  --cacert=/etc/kubernetes/pki/etcd/ca.crt \
  --cert=/etc/kubernetes/pki/etcd/server.crt \
  --key=/etc/kubernetes/pki/etcd/server.key \
  endpoint health

# —— 对照：SSH 密钥认证（RHCSA/RHCE）——
ssh-keygen -t ed25519 -N '' -f ~/.ssh/id_ed25519   # 生成密钥对（无口令）
ssh-copy-id user@server1                           # 把公钥追加到对方 ~/.ssh/authorized_keys
```

## 4. 考试坑点

- **`base64` 换行**：Linux 的 `base64` 默认每 76 字符换行，塞进 YAML 会出错；用 `base64 -w0`。
- **CSR 的 `usages` / `signerName` 写错**：客户端证书要 `client auth` + `kubernetes.io/kube-apiserver-client`。
- **etcdctl 证书路径**：别猜，去 `/etc/kubernetes/manifests/etcd.yaml` 里抄 `--cert-file`、`--key-file`、`--trusted-ca-file` 的路径（以题目环境为准）。
- **x509: certificate is valid for X, not Y**：访问地址不在证书 SAN 里。
- **x509: certificate has expired**：`kubeadm certs check-expiration` 定位，`renew` 后要让控制面静态 Pod 重启（例如把 manifest 临时移出 `/etc/kubernetes/manifests/` 再移回），以官方文档步骤为准。
- **`kubectl config set-context` 之后忘了切换**：CKA 每题都要先确认当前 context / 所在主机是否正确。

## 5. 动手练习

- [`labs/cka/practice-set-1.md`](../../labs/cka/practice-set-1.md)：创建用户证书 + RBAC 绑定、检查证书过期、etcd 备份题
- [`labs/rhce/00-lab-setup.md`](../../labs/rhce/00-lab-setup.md)：给受管节点分发 SSH 密钥
- 自测：用 `openssl x509 -text` 读出你集群 apiserver 证书的所有 SAN，解释每一项为什么存在。

## 6. 官方文档（本仓库离线版 + 考场可用的查法）

- 离线：[`references/cka/kubernetes-docs/setup/best-practices/certificates.md`](../../references/cka/kubernetes-docs/setup/best-practices/certificates.md)（集群需要哪些证书、各自用途）
- 离线：[`references/cka/kubernetes-docs/tasks/administer-cluster/kubeadm/kubeadm-certs.md`](../../references/cka/kubernetes-docs/tasks/administer-cluster/kubeadm/kubeadm-certs.md)（kubeadm 证书检查与续期）
- 离线：[`references/cka/kubernetes-docs/reference/access-authn-authz/certificate-signing-requests.md`](../../references/cka/kubernetes-docs/reference/access-authn-authz/certificate-signing-requests.md)（CSR API，含为普通用户签发证书的完整步骤）
- 离线：[`references/cka/kubernetes-docs/reference/access-authn-authz/authentication.md`](../../references/cka/kubernetes-docs/reference/access-authn-authz/authentication.md)（CN=用户名、O=组 的规则）
- 离线：[`references/cka/kubernetes-docs/concepts/configuration/organize-cluster-access-kubeconfig.md`](../../references/cka/kubernetes-docs/concepts/configuration/organize-cluster-access-kubeconfig.md)（kubeconfig 概念）
- 离线：[`references/cka/kubernetes-docs/tasks/access-application-cluster/configure-access-multiple-clusters.md`](../../references/cka/kubernetes-docs/tasks/access-application-cluster/configure-access-multiple-clusters.md)（多集群 / 多 context 配置）
- 离线：[`references/cka/kubernetes-docs/tasks/administer-cluster/certificates.md`](../../references/cka/kubernetes-docs/tasks/administer-cluster/certificates.md)（用 openssl / cfssl 手工生成证书）

考场查法：kubernetes.io 搜索 "Certificate Signing Requests"、"kubeadm certs"；本地 `kubectl config --help`、`kubeadm certs --help`、`man openssl-x509`、`man ssh-keygen`。

## 7. 自测清单

- [ ] 能说清楚 CA、证书、私钥、CSR 四者的关系
- [ ] 能解释 kubeconfig 的 clusters / users / contexts 三段分别存了什么
- [ ] 5 分钟内为用户 `alice`（组 `dev`）签发证书并配置好 context
- [ ] 能找到并说出 kubeadm 集群中 etcd 的 CA、证书、私钥路径
- [ ] 能用 `kubeadm certs check-expiration` 判断哪张证书快过期，并完成续期
