# CKA 练习题集 1（按知识点）

> **原创练习**：根据 [CKA 官方考纲 v1.37](../../references/cka/CKA_Curriculum_v1.37.pdf) 逐条设计，**不是真题**，难度和题量不代表真实考试。
> 配套笔记：[notes/cka/](../../notes/cka/README.md) ｜ 环境搭建：[00-lab-setup](00-lab-setup.md) ｜ 综合模拟：[mock-exam](mock-exam.md)

## 使用说明

- **环境假设**：kubeadm 搭建的集群，控制平面 `cp1`，工作节点 `worker1`、`worker2`（名字以你自己的环境为准）；已安装支持 NetworkPolicy 的 CNI（Calico/Cilium）。
- 答案文件统一写到 `/opt/answers/`（先 `sudo mkdir -p /opt/answers && sudo chown $USER /opt/answers`）。
- 每题流程：读题 → 自己做 → 跑「验证」→ 再展开「提示 / 参考」对照。会破坏集群的题（标 ⚠️）先给虚拟机**打快照**。
- 计时建议：普通题 ≤ 6 分钟，⚠️ 排错题 ≤ 10 分钟。做不出来的题记进错题本。
- 考纲覆盖对照见文末 [覆盖表](#考纲覆盖表)。

---

## K1 集群架构

笔记：[CKA-01 集群架构与组件](../../notes/cka/01-architecture.md)

**1.1** 找出 kubelet 的静态 Pod 目录，把该目录下的所有文件名写入 `/opt/answers/static-pods.txt`。

- 验证：`cat /opt/answers/static-pods.txt` 应包含 `etcd.yaml`、`kube-apiserver.yaml` 等 4 个文件。

<details><summary>提示 / 参考</summary>

```bash
ssh cp1
sudo grep staticPodPath /var/lib/kubelet/config.yaml      # 通常是 /etc/kubernetes/manifests
ls /etc/kubernetes/manifests > /opt/answers/static-pods.txt
```
</details>

**1.2** 从 kube-apiserver 的配置中找出 `--service-cluster-ip-range` 和 `--etcd-servers` 的值，分两行写入 `/opt/answers/apiserver.txt`。

<details><summary>提示 / 参考</summary>

```bash
sudo grep -E 'service-cluster-ip-range|etcd-servers' /etc/kubernetes/manifests/kube-apiserver.yaml \
  | sed 's/.*=//' > /opt/answers/apiserver.txt
# 也可以：kubectl -n kube-system get pod kube-apiserver-cp1 -o yaml | grep -E '...'
```
</details>

**1.3** 把每个节点的「节点名 kubelet版本 容器运行时版本」写入 `/opt/answers/nodes.txt`（每行一个节点）。

<details><summary>提示 / 参考</summary>

```bash
kubectl get nodes -o custom-columns=NAME:.metadata.name,KUBELET:.status.nodeInfo.kubeletVersion,CRI:.status.nodeInfo.containerRuntimeVersion --no-headers > /opt/answers/nodes.txt
```
</details>

## K2 kubectl 高效操作

笔记：[CKA-02 kubectl 高效操作](../../notes/cka/02-kubectl-efficiency.md)

**2.1** 用一条命令输出所有节点的名字和 InternalIP（格式 `name ip`，每行一个），写入 `/opt/answers/node-ips.txt`。

<details><summary>提示 / 参考</summary>

```bash
kubectl get nodes -o jsonpath='{range .items[*]}{.metadata.name}{" "}{.status.addresses[?(@.type=="InternalIP")].address}{"\n"}{end}' > /opt/answers/node-ips.txt
```
</details>

**2.2** 列出所有命名空间中的 Pod，按创建时间排序，只输出 `命名空间/名字`，写入 `/opt/answers/pods-by-age.txt`。

<details><summary>提示 / 参考</summary>

```bash
kubectl get pods -A --sort-by=.metadata.creationTimestamp \
  -o custom-columns=X:.metadata.namespace,Y:.metadata.name --no-headers | awk '{print $1"/"$2}' > /opt/answers/pods-by-age.txt
```
</details>

**2.3** 在命名空间 `drill`（不存在则创建）中创建 Pod `sleeper`：镜像 `busybox:1.36`，命令 `sleep 3600`，标签 `tier=tools`，并把生成的 YAML 保存到 `/opt/answers/sleeper.yaml`。

<details><summary>提示 / 参考</summary>

```bash
kubectl create ns drill
kubectl run sleeper -n drill --image=busybox:1.36 --labels=tier=tools --dry-run=client -o yaml -- sleep 3600 > /opt/answers/sleeper.yaml
kubectl apply -f /opt/answers/sleeper.yaml
```
`--` 之后的内容会成为容器的 `args`（加 `--command` 则成为 `command`）。
</details>

## K3 用 kubeadm 搭建集群

笔记：[CKA-03 用 kubeadm 搭建集群](../../notes/cka/03-kubeadm-install.md)

**3.1** 在一台新虚拟机 `worker3` 上完成「装集群前的准备」：关闭 swap 且重启后不恢复、加载 `overlay` 和 `br_netfilter` 模块并开机自动加载、开启 `net.ipv4.ip_forward=1` 并持久化、安装 containerd 并使用 systemd cgroup 驱动。

- 验证：`swapon --show` 无输出；`lsmod | grep br_netfilter`；`sysctl net.ipv4.ip_forward` 为 1；`grep SystemdCgroup /etc/containerd/config.toml` 为 true；以上在**重启后**依然成立。

<details><summary>提示 / 参考</summary>

```bash
sudo swapoff -a && sudo sed -i '/\sswap\s/ s/^/#/' /etc/fstab
printf 'overlay\nbr_netfilter\n' | sudo tee /etc/modules-load.d/k8s.conf
sudo modprobe overlay && sudo modprobe br_netfilter
echo 'net.ipv4.ip_forward = 1' | sudo tee /etc/sysctl.d/k8s.conf && sudo sysctl --system
containerd config default | sudo tee /etc/containerd/config.toml >/dev/null
sudo sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml
sudo systemctl restart containerd && sudo systemctl enable containerd
```
containerd 2.x 的配置结构有变化，`SystemdCgroup` 所在段落以官方「Container Runtimes」页面为准。
</details>

**3.2** 把 `worker3` 加入集群（原 join token 已过期）。

- 验证：`kubectl get nodes` 出现 `worker3` 且为 `Ready`。

<details><summary>提示 / 参考</summary>

```bash
# 在 cp1 上生成新的 join 命令
sudo kubeadm token create --print-join-command
# 在 worker3 上（已装好 kubeadm/kubelet/kubectl）执行打印出的命令
sudo kubeadm join <cp1-ip>:6443 --token ... --discovery-token-ca-cert-hash sha256:...
```
</details>

**3.3** 在一套全新的 3 节点虚拟机上从零完成：`kubeadm init`（指定 Pod 网段）→ 配置 kubectl → 安装 CNI → 加入两个 worker。限时 30 分钟。

<details><summary>提示 / 参考</summary>

完整步骤见 [CKA 实验环境](00-lab-setup.md) 和 [CKA-03](../../notes/cka/03-kubeadm-install.md)。关键点：`--pod-network-cidr` 要与 CNI 配置一致；装 CNI 之前节点是 `NotReady`，属正常现象。
</details>

## K4 集群生命周期：升级与 etcd

笔记：[CKA-04 集群生命周期](../../notes/cka/04-cluster-lifecycle.md)

**4.1** ⚠️ 把控制平面 `cp1` 从当前版本升级到下一个**小版本**的最新补丁版（例如 1.36.x → 1.37.y）：先驱逐 `cp1`，升级 kubeadm → 升级控制平面 → 升级 kubelet/kubectl → 恢复调度。

- 验证：`kubectl get nodes` 中 `cp1` 的 VERSION 为新版本且 `Ready`；`kubeadm version` 为新版本。

<details><summary>提示 / 参考</summary>

```bash
kubectl drain cp1 --ignore-daemonsets
# （pkgs.k8s.io 仓库按小版本区分，先把仓库地址改成新小版本）
sudo apt-mark unhold kubeadm && sudo apt-get update && sudo apt-get install -y kubeadm='1.37.*' && sudo apt-mark hold kubeadm
sudo kubeadm upgrade plan
sudo kubeadm upgrade apply v1.37.y
sudo apt-mark unhold kubelet kubectl && sudo apt-get install -y kubelet='1.37.*' kubectl='1.37.*' && sudo apt-mark hold kubelet kubectl
sudo systemctl daemon-reload && sudo systemctl restart kubelet
kubectl uncordon cp1
```
RHEL 系用 `dnf install kubeadm-'1.37.*' --disableexcludes=kubernetes`。
</details>

**4.2** ⚠️ 接着升级 `worker1`。

<details><summary>提示 / 参考</summary>

```bash
kubectl drain worker1 --ignore-daemonsets --delete-emptydir-data
ssh worker1
#   升级 kubeadm 包 → sudo kubeadm upgrade node → 升级 kubelet/kubectl 包 → daemon-reload → restart kubelet
exit
kubectl uncordon worker1
```
</details>

**4.3** 为 etcd 创建快照到 `/opt/backup/etcd-snap.db`，并输出快照状态表格到 `/opt/answers/etcd-status.txt`。

<details><summary>提示 / 参考</summary>

```bash
sudo mkdir -p /opt/backup
sudo ETCDCTL_API=3 etcdctl --endpoints=https://127.0.0.1:2379 \
  --cacert=/etc/kubernetes/pki/etcd/ca.crt \
  --cert=/etc/kubernetes/pki/etcd/server.crt \
  --key=/etc/kubernetes/pki/etcd/server.key \
  snapshot save /opt/backup/etcd-snap.db
sudo etcdutl --write-out=table snapshot status /opt/backup/etcd-snap.db | tee /opt/answers/etcd-status.txt
```
证书路径不确定时：`sudo grep -E 'cert|key|listen-client' /etc/kubernetes/manifests/etcd.yaml`。
</details>

**4.4** ⚠️ 先创建 Deployment `before-restore`，做快照，再删掉它；然后把 etcd 恢复到快照时刻，使 `before-restore` 重新出现。

<details><summary>提示 / 参考</summary>

```bash
sudo etcdutl --data-dir /var/lib/etcd-restore snapshot restore /opt/backup/etcd-snap.db
sudo vim /etc/kubernetes/manifests/etcd.yaml
#   把 volumes 里 etcd-data 的 hostPath.path 从 /var/lib/etcd 改成 /var/lib/etcd-restore
#   （或者改 --data-dir 并同步 volumeMounts；只改一处最不容易错）
# 等 etcd 和 apiserver 静态 Pod 重建（1~2 分钟），必要时 sudo systemctl restart kubelet
kubectl get deploy before-restore
```
</details>

## K5 高可用控制平面

笔记：[CKA-05 高可用控制平面](../../notes/cka/05-ha-control-plane.md)

**5.1** （需要 3 台控制平面虚拟机 + 1 个负载均衡）使用 `--control-plane-endpoint` 和 `--upload-certs` 初始化第一个控制平面，再把第二台以控制平面身份加入。

- 验证：`kubectl get nodes` 中有两个 `control-plane` 角色节点；`kubectl -n kube-system get pods -l component=etcd` 有两个。

<details><summary>提示 / 参考</summary>

```bash
sudo kubeadm init --control-plane-endpoint "k8s-api.lab.local:6443" --upload-certs --pod-network-cidr=192.168.0.0/16
# 输出中带 --control-plane --certificate-key 的 join 命令用于控制平面节点
# certificate-key 两小时后过期，重新上传：
sudo kubeadm init phase upload-certs --upload-certs
sudo kubeadm token create --print-join-command   # 再拼上 --control-plane --certificate-key <新 key>
```
</details>

**5.2** 列出 etcd 成员，写入 `/opt/answers/etcd-members.txt`；然后关掉一台控制平面虚拟机，确认 `kubectl` 仍可用（3 节点 etcd 允许坏 1 台）。

<details><summary>提示 / 参考</summary>

```bash
sudo ETCDCTL_API=3 etcdctl --endpoints=https://127.0.0.1:2379 --cacert=/etc/kubernetes/pki/etcd/ca.crt \
  --cert=/etc/kubernetes/pki/etcd/server.crt --key=/etc/kubernetes/pki/etcd/server.key \
  member list -w table | tee /opt/answers/etcd-members.txt
```
</details>

## K6 RBAC

笔记：[CKA-06 RBAC 与 ServiceAccount](../../notes/cka/06-rbac.md)

**6.1** 在命名空间 `team-a` 中创建 ServiceAccount `deployer`，让它只能对 Deployment 执行 `get,list,create,update`，对 Pod 只能 `get,list`。

- 验证：`kubectl auth can-i create deployments -n team-a --as=system:serviceaccount:team-a:deployer` → yes；`delete deployments` → no；`create pods` → no。

<details><summary>提示 / 参考</summary>

```bash
kubectl create ns team-a
kubectl create sa deployer -n team-a
kubectl create role deployer -n team-a --verb=get,list,create,update --resource=deployments.apps
kubectl create role pod-reader -n team-a --verb=get,list --resource=pods
kubectl create rolebinding deployer -n team-a --role=deployer --serviceaccount=team-a:deployer
kubectl create rolebinding deployer-pods -n team-a --role=pod-reader --serviceaccount=team-a:deployer
```
</details>

**6.2** 让用户 `jane` 可以在**所有命名空间**读取 Node 和 PersistentVolume（只读），但不能读 Secret。

<details><summary>提示 / 参考</summary>

```bash
kubectl create clusterrole infra-viewer --verb=get,list,watch --resource=nodes,persistentvolumes
kubectl create clusterrolebinding jane-infra-viewer --clusterrole=infra-viewer --user=jane
kubectl auth can-i list nodes --as=jane          # yes
kubectl auth can-i get secrets -A --as=jane      # no
```
</details>

**6.3** 为新用户 `dev-user`（组 `dev-team`）签发客户端证书：生成私钥和 CSR → 通过 `CertificateSigningRequest` 让集群签发 → 写入 kubeconfig 的新 context `dev-user@lab`（默认命名空间 `team-a`）。然后给 `dev-team` 组绑定 `team-a` 中的内置 `edit` ClusterRole。

- 验证：`kubectl --context=dev-user@lab get pods` 成功；`kubectl --context=dev-user@lab get nodes` 被拒绝。

<details><summary>提示 / 参考</summary>

```bash
openssl genrsa -out dev-user.key 2048
openssl req -new -key dev-user.key -out dev-user.csr -subj "/CN=dev-user/O=dev-team"
cat <<EOF | kubectl apply -f -
apiVersion: certificates.k8s.io/v1
kind: CertificateSigningRequest
metadata:
  name: dev-user
spec:
  request: $(base64 -w0 < dev-user.csr)
  signerName: kubernetes.io/kube-apiserver-client
  expirationSeconds: 86400
  usages: ["client auth"]
EOF
kubectl certificate approve dev-user
kubectl get csr dev-user -o jsonpath='{.status.certificate}' | base64 -d > dev-user.crt
kubectl config set-credentials dev-user --client-key=dev-user.key --client-certificate=dev-user.crt --embed-certs=true
kubectl config set-context dev-user@lab --cluster=kubernetes --user=dev-user --namespace=team-a
kubectl create rolebinding dev-team-edit -n team-a --clusterrole=edit --group=dev-team
```
集群名以 `kubectl config get-clusters` 为准。
</details>

**6.4** 命名空间 `team-b` 里的 ServiceAccount `monitor` 应该能 `list pods`，但现在不行。找出原因并修复（准备：先执行下面的命令制造故障）。

```bash
kubectl create ns team-b && kubectl create sa monitor -n team-b
kubectl create role pod-lister -n team-b --verb=list --resource=pods
kubectl create rolebinding monitor -n team-b --role=pod-lister --serviceaccount=team-b:monitr
```

<details><summary>提示 / 参考</summary>

`kubectl describe rolebinding monitor -n team-b` 会看到 subject 名字拼错（`monitr`）。RoleBinding 的 subjects 可以 `kubectl edit` 修改（roleRef 不可修改，改 roleRef 只能删了重建）。
验证：`kubectl auth can-i list pods -n team-b --as=system:serviceaccount:team-b:monitor`。
</details>

## K7 Helm 与 Kustomize

笔记：[CKA-07 Helm 与 Kustomize](../../notes/cka/07-helm-kustomize.md)

**7.1** 添加 Helm 仓库 `podinfo`（`https://stefanprodan.github.io/podinfo`），在命名空间 `web`（自动创建）中安装 release `frontend`，副本数 2。

- 验证：`helm list -n web` 显示 `frontend` 为 `deployed`；`kubectl get deploy -n web` 副本 2/2。

<details><summary>提示 / 参考</summary>

```bash
helm repo add podinfo https://stefanprodan.github.io/podinfo && helm repo update
helm search repo podinfo --versions | head
helm show values podinfo/podinfo | grep -n replicaCount
helm install frontend podinfo/podinfo -n web --create-namespace --set replicaCount=2
```
</details>

**7.2** 把 `frontend` 升级为 3 副本（用 values 文件），然后回滚到第 1 个 revision，最后把 release 渲染出的清单（不安装）保存到 `/opt/answers/frontend.yaml`。

<details><summary>提示 / 参考</summary>

```bash
printf 'replicaCount: 3\n' > values-prod.yaml
helm upgrade frontend podinfo/podinfo -n web -f values-prod.yaml
helm history frontend -n web
helm rollback frontend 1 -n web
helm get values frontend -n web
helm template frontend podinfo/podinfo -n web -f values-prod.yaml > /opt/answers/frontend.yaml
```
</details>

**7.3** 用 Kustomize 组织一个 `base`（Deployment `api` + Service `api`）和一个 `overlays/prod`：名字前缀 `prod-`、命名空间 `prod`、副本 4、镜像 tag 改为 `1.28`，并用 `configMapGenerator` 生成 `api-config`（`LOG_LEVEL=warn`）。

- 验证：`kubectl kustomize overlays/prod` 输出中名字为 `prod-api`，ConfigMap 名带哈希后缀；`kubectl apply -k overlays/prod` 成功。

<details><summary>提示 / 参考</summary>

```yaml
# base/kustomization.yaml
resources: [deployment.yaml, service.yaml]
---
# overlays/prod/kustomization.yaml
resources: [../../base]
namePrefix: prod-
namespace: prod
replicas:
- {name: api, count: 4}
images:
- {name: nginx, newTag: "1.28"}
configMapGenerator:
- name: api-config
  literals: [LOG_LEVEL=warn]
```
`kubectl create ns prod` 后再 `kubectl apply -k overlays/prod`。
</details>

**7.4** 用 Helm 把 metrics-server 安装到 `kube-system`（实验环境给它加 `--kubelet-insecure-tls` 参数），使 `kubectl top nodes` 可用。（如果已按 [00-lab-setup](00-lab-setup.md) 用清单装过，先 `kubectl delete -f` 那份清单再练这题。）

<details><summary>提示 / 参考</summary>

```bash
helm repo add metrics-server https://kubernetes-sigs.github.io/metrics-server/
helm show values metrics-server/metrics-server | grep -n -A3 '^args'
helm install metrics-server metrics-server/metrics-server -n kube-system --set 'args={--kubelet-insecure-tls}'
kubectl top nodes
```
</details>

## K8 扩展接口：CNI / CSI / CRI、CRD 与 Operator

笔记：[CKA-08 扩展接口与 CRD](../../notes/cka/08-extension-interfaces-crd.md)

**8.1** 找出集群使用的 CNI 插件名称及其配置文件路径，写入 `/opt/answers/cni.txt`。

<details><summary>提示 / 参考</summary>

```bash
ssh worker1 'ls /etc/cni/net.d/; ls /opt/cni/bin | head'
kubectl get pods -A | grep -Ei 'calico|cilium|flannel|weave'
```
</details>

**8.2** 找出 kubelet 连接的容器运行时 socket，以及运行时名称和版本，写入 `/opt/answers/cri.txt`。

<details><summary>提示 / 参考</summary>

```bash
sudo grep containerRuntimeEndpoint /var/lib/kubelet/config.yaml
sudo cat /var/lib/kubelet/kubeadm-flags.env
sudo crictl version
```
</details>

**8.3** 列出集群中注册的 CSI 驱动和所有 StorageClass 的 provisioner。

<details><summary>提示 / 参考</summary>

```bash
kubectl get csidrivers
kubectl get sc -o custom-columns=NAME:.metadata.name,PROVISIONER:.provisioner
```
</details>

**8.4** 创建 CRD `backups.ops.example.com`（组 `ops.example.com`，版本 `v1`，命名空间级，kind `Backup`，短名 `bk`，`spec` 含字符串字段 `schedule` 和整数字段 `retention`），然后创建一个 `Backup` 对象 `nightly`。

- 验证：`kubectl api-resources | grep backups`；`kubectl get bk nightly -o yaml`；`kubectl explain backup.spec` 能看到两个字段。

<details><summary>提示 / 参考</summary>

```yaml
apiVersion: apiextensions.k8s.io/v1
kind: CustomResourceDefinition
metadata:
  name: backups.ops.example.com
spec:
  group: ops.example.com
  scope: Namespaced
  names: {plural: backups, singular: backup, kind: Backup, shortNames: [bk]}
  versions:
  - name: v1
    served: true
    storage: true
    schema:
      openAPIV3Schema:
        type: object
        properties:
          spec:
            type: object
            properties:
              schedule: {type: string}
              retention: {type: integer}
---
apiVersion: ops.example.com/v1
kind: Backup
metadata:
  name: nightly
spec:
  schedule: "0 2 * * *"
  retention: 7
```
</details>

**8.5** 安装一个 Operator（推荐 cert-manager，按其官方文档用 Helm 或清单安装），列出它安装的所有 CRD 写入 `/opt/answers/operator-crds.txt`，并用 `kubectl explain` 查看其中一个 CR 的 `spec` 字段。

<details><summary>提示 / 参考</summary>

```bash
kubectl get crd -o name | grep cert-manager.io > /opt/answers/operator-crds.txt
kubectl explain certificate.spec | head -30
kubectl get pods -n cert-manager        # Operator 本身就是一个跑在集群里的控制器 Deployment
```
理解要点：CRD 只定义「数据结构」，Operator（控制器）负责 watch 这些对象并让现实状态趋近期望状态。
</details>

## K9 工作负载

笔记：[CKA-09 工作负载](../../notes/cka/09-workloads.md)

**9.1** 创建 Deployment `web`（`nginx:1.27`，3 副本）。把镜像升级到 `nginx:1.28` 并记录变更原因 `bump to 1.28`；再升级到一个**不存在**的镜像 `nginx:9.99`，观察滚动更新卡住；最后回滚到镜像为 `1.28` 的版本。

- 验证：`kubectl rollout history deploy/web` 有 CHANGE-CAUSE；`kubectl get deploy web -o jsonpath='{.spec.template.spec.containers[0].image}'` 为 `nginx:1.28`；3/3 Ready。

<details><summary>提示 / 参考</summary>

```bash
kubectl create deployment web --image=nginx:1.27 --replicas=3
kubectl set image deploy/web nginx=nginx:1.28 && kubectl annotate deploy/web kubernetes.io/change-cause="bump to 1.28"
kubectl set image deploy/web nginx=nginx:9.99
kubectl rollout status deploy/web --timeout=30s     # 超时：新 Pod ImagePullBackOff，旧 Pod 仍在服务
kubectl rollout undo deploy/web                      # 回到上一版（1.28）
```
</details>

**9.2** 修改 `web` 的滚动更新策略为 `maxSurge: 1`、`maxUnavailable: 0`，再触发一次重启（不改镜像），用 `-w` 观察 Pod 替换顺序。

<details><summary>提示 / 参考</summary>

```bash
kubectl patch deploy web -p '{"spec":{"strategy":{"rollingUpdate":{"maxSurge":1,"maxUnavailable":0}}}}'
kubectl rollout restart deploy/web && kubectl get pods -l app=web -w
```
</details>

**9.3** 创建 ConfigMap `nginx-conf`，内容为一个 nginx server 配置文件 `default.conf`（监听 8080），挂载到 `web` 的 `/etc/nginx/conf.d/`；创建 Secret `web-secret`（`API_KEY=abc123`）并以环境变量 `API_KEY` 注入。

- 验证：`kubectl exec deploy/web -- env | grep API_KEY`；`kubectl exec deploy/web -- curl -s localhost:8080` 有响应（nginx 镜像带 curl，若没有用 `wget`）。

<details><summary>提示 / 参考</summary>

```bash
cat > default.conf <<'EOF'
server { listen 8080; location / { return 200 "hello from configmap\n"; } }
EOF
kubectl create configmap nginx-conf --from-file=default.conf
kubectl create secret generic web-secret --from-literal=API_KEY=abc123
kubectl set env deploy/web --from=secret/web-secret
kubectl edit deploy web     # 添加 volumes.configMap 和 volumeMounts（mountPath: /etc/nginx/conf.d）
```
</details>

**9.4** 给 `web` 设置 CPU 请求 `100m`，再创建 HPA：CPU 利用率 50%，最少 2、最多 6 个副本。用一个循环请求的 Pod 制造负载，观察扩容。

<details><summary>提示 / 参考</summary>

```bash
kubectl set resources deploy web --requests=cpu=100m
kubectl autoscale deploy web --min=2 --max=6 --cpu=50%
kubectl expose deploy web --port=80 --target-port=8080
kubectl run load --image=busybox:1.36 --restart=Never -- sh -c 'while true; do wget -qO- http://web >/dev/null; done'
kubectl get hpa web -w
```
</details>

**9.5** 创建 Pod `app-with-sidecar`：主容器 `busybox:1.36` 每秒向 `/var/log/app.log` 追加一行时间；用**原生 sidecar**（`initContainers` + `restartPolicy: Always`）运行 `tail -F /var/log/app.log`，两者共享 `emptyDir`。

- 验证：`kubectl logs app-with-sidecar -c log-streamer` 能看到持续输出。

<details><summary>提示 / 参考</summary>

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: app-with-sidecar
spec:
  initContainers:
  - name: log-streamer
    image: busybox:1.36
    restartPolicy: Always
    command: ["sh", "-c", "touch /var/log/app.log; tail -F /var/log/app.log"]
    volumeMounts: [{name: logs, mountPath: /var/log}]
  containers:
  - name: app
    image: busybox:1.36
    command: ["sh", "-c", "while true; do date >> /var/log/app.log; sleep 1; done"]
    volumeMounts: [{name: logs, mountPath: /var/log}]
  volumes:
  - name: logs
    emptyDir: {}
```
</details>

**9.6** 自愈原语：创建 Pod `probe-demo`，启动后创建 `/tmp/healthy`，30 秒后删除；配置 `exec` 类型 livenessProbe 检查该文件。再为 `web` 创建 PDB（`minAvailable: 2`），然后 `drain` 一个节点观察 PDB 的作用。

<details><summary>提示 / 参考</summary>

```yaml
apiVersion: v1
kind: Pod
metadata: {name: probe-demo}
spec:
  containers:
  - name: app
    image: busybox:1.36
    args: ["sh", "-c", "touch /tmp/healthy; sleep 30; rm -f /tmp/healthy; sleep 600"]
    livenessProbe:
      exec: {command: ["cat", "/tmp/healthy"]}
      initialDelaySeconds: 5
      periodSeconds: 5
```
```bash
kubectl get pod probe-demo -w            # RESTARTS 逐渐增加
kubectl create pdb web-pdb --selector=app=web --min-available=2
kubectl drain worker1 --ignore-daemonsets --delete-emptydir-data   # 若违反 PDB 会等待重试
kubectl uncordon worker1
```
</details>

**9.7** 创建 DaemonSet `node-agent`（`busybox:1.36`，`sleep infinity`），要求**包括控制平面节点**在内每个节点一个；再创建 CronJob `cleanup`，每 5 分钟运行一次 `echo cleanup`，只保留 2 个成功 Job 记录。

<details><summary>提示 / 参考</summary>

```bash
kubectl create deploy node-agent --image=busybox:1.36 --dry-run=client -o yaml -- sleep infinity > ds.yaml
# 改 kind: DaemonSet，删掉 replicas、strategy、status；在 template.spec 加：
#   tolerations: [{key: node-role.kubernetes.io/control-plane, operator: Exists, effect: NoSchedule}]
kubectl apply -f ds.yaml && kubectl get ds node-agent -o wide
kubectl create cronjob cleanup --image=busybox:1.36 --schedule="*/5 * * * *" -- echo cleanup
kubectl patch cronjob cleanup -p '{"spec":{"successfulJobsHistoryLimit":2}}'
```
</details>

## K10 调度

笔记：[CKA-10 调度](../../notes/cka/10-scheduling.md)

**10.1** 给 `worker2` 打标签 `disktype=ssd`，创建 Pod `fast-io`（`nginx`）只调度到带该标签的节点（用 nodeSelector）。

<details><summary>提示 / 参考</summary>

```bash
kubectl label node worker2 disktype=ssd
kubectl run fast-io --image=nginx --dry-run=client -o yaml > fast-io.yaml   # 加 spec.nodeSelector: {disktype: ssd}
kubectl apply -f fast-io.yaml && kubectl get pod fast-io -o wide
```
</details>

**10.2** 创建 Deployment `analytics`（2 副本）：**必须**运行在 `disktype` 为 `ssd` 或 `nvme` 的节点上，**优先**运行在标签 `zone=zone-a` 的节点上。

<details><summary>提示 / 参考</summary>

参考 [CKA-10](../../notes/cka/10-scheduling.md) 的 nodeAffinity 模板：`required` 用 `operator: In, values: [ssd, nvme]`，`preferred` 带 `weight`。写在 `spec.template.spec.affinity` 下。
</details>

**10.3** 给 `worker1` 加污点 `maintenance=true:NoExecute`，观察上面普通 Pod 被驱逐；创建一个能容忍该污点 60 秒的 Pod `tolerant`，并调度到 `worker1`。完成后删除污点。

<details><summary>提示 / 参考</summary>

```yaml
spec:
  nodeName: worker1      # 或用 nodeSelector: {kubernetes.io/hostname: worker1}
  tolerations:
  - {key: maintenance, operator: Equal, value: "true", effect: NoExecute, tolerationSeconds: 60}
```
```bash
kubectl taint node worker1 maintenance=true:NoExecute
kubectl taint node worker1 maintenance=true:NoExecute-
```
</details>

**10.4** 在命名空间 `quota-lab` 中：用 LimitRange 给容器设置默认 requests `cpu=100m,memory=64Mi`、默认 limits `cpu=200m,memory=128Mi`；用 ResourceQuota 限制最多 3 个 Pod、`requests.memory` 总量 `256Mi`。然后尝试创建第 4 个 Pod 并记录报错。

<details><summary>提示 / 参考</summary>

```bash
kubectl create ns quota-lab
kubectl create quota q -n quota-lab --hard=pods=3,requests.memory=256Mi
# LimitRange 只能用 YAML（模板见 CKA-10），type: Container，default / defaultRequest
for i in 1 2 3 4; do kubectl run p$i -n quota-lab --image=nginx; done   # 第 4 个报 exceeded quota
kubectl describe quota q -n quota-lab
```
</details>

**10.5** 让 Deployment `spread`（3 副本）的 Pod 分布在 3 个不同节点（使用 podAntiAffinity）；再创建 PriorityClass `critical`（值 `1000000`），让 `spread` 使用它。

<details><summary>提示 / 参考</summary>

```bash
kubectl create priorityclass critical --value=1000000 --description="critical workloads"
# Deployment 模板中：priorityClassName: critical
#                  affinity.podAntiAffinity.requiredDuringSchedulingIgnoredDuringExecution（topologyKey: kubernetes.io/hostname）
```
只有 2 个 worker 时第 3 个副本会 Pending（控制平面有污点）——想一想如何验证这是「预期行为」。
</details>

## K11 Service 与 CoreDNS

笔记：[CKA-11 Service 与 CoreDNS](../../notes/cka/11-services-dns.md)

**11.1** 创建 Deployment `echo`（镜像 `registry.k8s.io/e2e-test-images/agnhost:2.53`，参数 `netexec --http-port=8080`，2 副本）；暴露为 ClusterIP Service `echo`（端口 80 → 8080），再暴露为 NodePort Service `echo-np`（nodePort `30080`）。

- 验证：临时 Pod 中 `wget -qO- http://echo/hostname` 返回 Pod 名；`curl http://<任一节点IP>:30080/hostname` 成功。

<details><summary>提示 / 参考</summary>

```bash
kubectl create deploy echo --image=registry.k8s.io/e2e-test-images/agnhost:2.53 --replicas=2 -- /agnhost netexec --http-port=8080
kubectl expose deploy echo --port=80 --target-port=8080
kubectl expose deploy echo --name=echo-np --type=NodePort --port=80 --target-port=8080 --dry-run=client -o yaml > np.yaml
# 在 ports[0] 下加 nodePort: 30080 后 apply
```
agnhost 版本号以 registry.k8s.io 上可用的为准；也可以换成 nginx（端口 80）。
</details>

**11.2** 创建 Headless Service `db` 和 StatefulSet `db`（3 副本，`busybox:1.36` 运行 `sleep 3600`，`serviceName: db`），在临时 Pod 中解析 `db-0.db`、`db.default.svc.cluster.local`，把解析结果写入 `/opt/answers/dns.txt`。

<details><summary>提示 / 参考</summary>

```bash
kubectl create service clusterip db --clusterip=None --dry-run=client -o yaml   # selector 为 app=db
kubectl run tmp --rm -it --image=busybox:1.36 --restart=Never -- nslookup db-0.db.default.svc.cluster.local
```
Headless Service 的 A 记录返回所有 Pod IP；`db-0.db` 返回单个 Pod IP。
</details>

**11.3** ⚠️ Service `shop` 访问不通。先执行下面的命令制造故障，然后找出全部问题并修复（共 2 处）。

```bash
kubectl create deploy shop --image=nginx --replicas=2
kubectl create service clusterip shop --tcp=80:8080
kubectl patch svc shop -p '{"spec":{"selector":{"app":"sh0p"}}}'
```

<details><summary>提示 / 参考</summary>

1. `kubectl get endpointslices -l kubernetes.io/service-name=shop` 为空 → selector 拼错，改回 `app: shop`。
2. 有地址后仍不通 → nginx 监听 80，而 `targetPort` 是 8080，改为 80。
</details>

**11.4** 让集群内 Pod 解析 `*.corp.internal` 时转发到 DNS 服务器 `10.96.0.200`（假设存在），其余不变；并找出集群域名（cluster domain）写入 `/opt/answers/cluster-domain.txt`。

<details><summary>提示 / 参考</summary>

```bash
kubectl -n kube-system edit cm coredns     # 增加 corp.internal:53 { forward . 10.96.0.200 } 段
kubectl -n kube-system rollout restart deploy coredns
sudo grep clusterDomain /var/lib/kubelet/config.yaml | awk '{print $2}' > /opt/answers/cluster-domain.txt
```
</details>

## K12 NetworkPolicy

笔记：[CKA-12 NetworkPolicy](../../notes/cka/12-network-policy.md)

> 准备：`kubectl create ns prod; kubectl create ns frontend; kubectl create ns dev`；在 `prod` 中创建 `api`（`app=api`，agnhost netexec 8080）和 `db`（`app=db`，nginx 80）及同名 Service。

**12.1** 在 `prod` 中创建默认拒绝所有**入站**流量的策略。

- 验证：从 `dev` 命名空间的临时 Pod 访问 `api.prod` 超时。

<details><summary>提示 / 参考</summary>

`podSelector: {}` + `policyTypes: [Ingress]`，无 ingress 规则（模板见 [CKA-12](../../notes/cka/12-network-policy.md)）。
</details>

**12.2** 允许 `frontend` 命名空间中标签 `role=web` 的 Pod 访问 `prod` 中 `app=api` 的 8080 端口；其他来源（包括 `frontend` 中不带该标签的 Pod）仍然拒绝。

- 验证：`kubectl run t -n frontend --labels=role=web --rm -it --image=busybox:1.36 --restart=Never -- wget -qO- -T 2 http://api.prod/hostname` 成功；去掉 `--labels` 失败。

<details><summary>提示 / 参考</summary>

`namespaceSelector`（`kubernetes.io/metadata.name: frontend`）与 `podSelector`（`role: web`）写在**同一个** `from` 元素里；`ports` 写 Pod 端口 8080（Service 的 80 不对）。
</details>

**12.3** 限制 `prod` 中 `app=api` 的**出站**流量：只能访问 `app=db` 的 80 端口，以及集群 DNS。

- 验证：`kubectl exec -n prod deploy/api -- ...` 访问 `db` 成功、访问外网或其他 Pod 失败、域名能解析。

<details><summary>提示 / 参考</summary>

参考 [CKA-12](../../notes/cka/12-network-policy.md) 模板 3：两条 egress 规则（db 80 + kube-dns UDP/TCP 53）。
</details>

**12.4** 下面两份策略中，哪一份实现了「只允许 `dev` 命名空间中 `role=tester` 的 Pod 访问」？把正确的文件名写入 `/opt/answers/netpol-choice.txt` 并说明另一份的效果。

```yaml
# A
ingress:
- from:
  - namespaceSelector: {matchLabels: {kubernetes.io/metadata.name: dev}}
  - podSelector: {matchLabels: {role: tester}}
# B
ingress:
- from:
  - namespaceSelector: {matchLabels: {kubernetes.io/metadata.name: dev}}
    podSelector: {matchLabels: {role: tester}}
```

<details><summary>提示 / 参考</summary>

B 正确（同一元素 = AND）。A 是 OR：允许 `dev` 中**所有** Pod，**或**本命名空间中 `role=tester` 的 Pod。
</details>

## K13 Ingress 与 Gateway API

笔记：[CKA-13 Ingress 与 Gateway API](../../notes/cka/13-ingress-gateway-api.md)

> 准备：集群中需要一个 Ingress 控制器和一个 Gateway API 实现（考试环境通常已装好）。自己练习时：
> 1. 安装 Gateway API CRD（standard channel，命令见 [Gateway API 入门](../../references/cka/gateway-api-docs/guides/getting-started/introduction.md)）；
> 2. 按其官方文档用 Helm 安装一个同时支持 Ingress 与 Gateway API 的实现（如 Traefik、Cilium），或分别安装一个 Ingress 控制器和一个 Gateway 实现（如 Envoy Gateway、NGINX Gateway Fabric）；
> 3. 实验环境没有云负载均衡时，入口 Service 用 NodePort 访问，或安装 MetalLB 提供 LoadBalancer IP。
>
> 命名空间 `shop` 中准备 Service `frontend:80`、`api:8080`、`api-v2:8080`（可用 agnhost netexec 或 nginx 快速起）。

**13.1** 用 openssl 生成 `shop.example.com` 的自签名证书，创建 TLS Secret `shop-tls`；创建 Ingress `shop`：`/api` → `api:8080`，`/` → `frontend:80`，启用 TLS。

- 验证：`curl -k --resolve shop.example.com:443:<入口IP> https://shop.example.com/api` 返回 api 的响应。

<details><summary>提示 / 参考</summary>

```bash
openssl req -x509 -nodes -newkey rsa:2048 -days 30 -keyout shop.key -out shop.crt -subj "/CN=shop.example.com"
kubectl create secret tls shop-tls -n shop --cert=shop.crt --key=shop.key
kubectl create ingress shop -n shop --class=<ingressclass> \
  --rule="shop.example.com/api*=api:8080,tls=shop-tls" --rule="shop.example.com/*=frontend:80"
```
</details>

**13.2** 在命名空间 `infra` 创建 Gateway `web-gw`（使用集群已有的 GatewayClass，HTTP 80 监听器，允许所有命名空间挂路由）；在 `shop` 中创建 HTTPRoute `shop`：主机名 `shop.example.com`，`/api` → `api:8080`，其余 → `frontend:80`。

- 验证：`kubectl get gateway -n infra` 中 `PROGRAMMED=True`；`kubectl describe httproute shop -n shop` 中 `Accepted=True`、`ResolvedRefs=True`；`curl -H 'Host: shop.example.com' http://<网关IP>/api` 成功。

<details><summary>提示 / 参考</summary>

模板见 [CKA-13](../../notes/cka/13-ingress-gateway-api.md)。`parentRefs` 要写 `namespace: infra`，因为 Route 和 Gateway 不在同一命名空间。
</details>

**13.3** 修改 HTTPRoute：`/api` 的流量 80% 到 `api`、20% 到 `api-v2`；再为 HTTP 监听器创建一条把所有请求 301 跳转到 HTTPS 的路由（需要先给 Gateway 增加 HTTPS 443 监听器并引用 `infra` 中的 TLS Secret）。

<details><summary>提示 / 参考</summary>

- 拆分：同一 rule 下两个 `backendRefs`，`weight: 80` / `weight: 20`；用 `for i in $(seq 20); do curl -s ...; done` 观察比例。
- 跳转：`filters: [{type: RequestRedirect, requestRedirect: {scheme: https, statusCode: 301}}]`，`parentRefs` 用 `sectionName: http` 只挂到 HTTP 监听器。
- 证书 Secret 默认要和 Gateway 在同一命名空间（`infra`）。
</details>

**13.4** 把 13.1 的 Ingress 等价迁移为 Gateway + HTTPRoute（含 TLS），验证新入口可用后删除 Ingress。

<details><summary>提示 / 参考</summary>

按 [CKA-13](../../notes/cka/13-ingress-gateway-api.md) 的「Ingress → Gateway API 字段对照」表逐项改写：`tls.secretName` → listener `tls.certificateRefs`，`host` → `hostnames`，`Prefix` → `PathPrefix`。
</details>

## K14 存储

笔记：[CKA-14 存储](../../notes/cka/14-storage.md)

**14.1** 创建 PV `pv-log`（1Gi，RWO，`Retain`，`storageClassName: manual`，hostPath `/mnt/data/log`）、PVC `log-claim`（500Mi），以及挂载该 PVC 到 `/var/log/app` 并持续写日志的 Pod `logger`。

- 验证：`kubectl get pv,pvc` 显示 `Bound`；在 Pod 所在节点上 `cat /mnt/data/log/out.log` 有内容。

<details><summary>提示 / 参考</summary>

三件套模板见 [CKA-14](../../notes/cka/14-storage.md)。hostPath 数据在节点上，`kubectl get pod logger -o wide` 看节点后 ssh 过去检查。
</details>

**14.2** 安装 local-path-provisioner（按其 GitHub README），把 `local-path` 设为**默认** StorageClass；创建一个不写 `storageClassName` 的 PVC `auto-claim`（1Gi），观察它在没有 Pod 使用前的状态，再创建使用它的 Pod。

<details><summary>提示 / 参考</summary>

```bash
kubectl patch sc local-path -p '{"metadata":{"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}'
kubectl get sc        # local-path (default)
kubectl get pvc auto-claim    # WaitForFirstConsumer：Pod 创建前一直 Pending，属正常
```
</details>

**14.3** 删除 14.1 中的 Pod 和 PVC，观察 `pv-log` 状态变为 `Released`；让一个新 PVC `log-claim-2` 重新绑定到 `pv-log`，并确认旧数据还在。

<details><summary>提示 / 参考</summary>

```bash
kubectl patch pv pv-log --type=json -p '[{"op":"remove","path":"/spec/claimRef"}]'   # Released → Available
# 新 PVC 写 storageClassName: manual，可加 volumeName: pv-log 精确绑定
```
</details>

**14.4** 创建 StorageClass `expandable`（`allowVolumeExpansion: true`，provisioner 同 local-path 或你环境中支持扩容的 CSI），用它创建 PVC 并扩容到 2Gi；最后把集群中所有 PV 按容量从小到大排序输出到 `/opt/answers/pv-sorted.txt`。

<details><summary>提示 / 参考</summary>

```bash
kubectl patch pvc data -p '{"spec":{"resources":{"requests":{"storage":"2Gi"}}}}'
kubectl get pv --sort-by=.spec.capacity.storage > /opt/answers/pv-sorted.txt
```
local-path 实际并不支持在线扩容（hostPath 无容量概念），想完整练习扩容需要支持扩容的 CSI 驱动；考试中以题目环境为准。
</details>

## K15 排错

笔记：[CKA-15 排错](../../notes/cka/15-troubleshooting.md)

**15.1** ⚠️ 故障：在 `worker1` 上执行 `sudo systemctl disable --now kubelet`。任务：让 `worker1` 恢复 `Ready`，且重启后保持。

<details><summary>提示 / 参考</summary>

`kubectl describe node worker1` 显示 `Kubelet stopped posting node status` → `ssh worker1` → `systemctl status kubelet` → `sudo systemctl enable --now kubelet`。
</details>

**15.2** ⚠️ 故障：在 `worker2` 上执行
`sudo sed -i 's#/etc/kubernetes/pki/ca.crt#/etc/kubernetes/pki/ca-bad.crt#' /var/lib/kubelet/config.yaml && sudo systemctl restart kubelet`。
任务：找出原因并修复。

<details><summary>提示 / 参考</summary>

`sudo journalctl -u kubelet -n 30 --no-pager` 会看到无法加载 client CA 文件的报错 → 改回 `clientCAFile` 路径 → `sudo systemctl restart kubelet`。
</details>

**15.3** ⚠️ 故障：在 `cp1` 上先备份 `kube-apiserver.yaml` 到 `/root/`，再执行
`sudo sed -i 's#--etcd-servers=https://127.0.0.1:2379#--etcd-servers=https://127.0.0.1:2380#' /etc/kubernetes/manifests/kube-apiserver.yaml`。
任务：在 `kubectl` 不可用的情况下定位并修复。

<details><summary>提示 / 参考</summary>

```bash
sudo crictl ps -a | grep kube-apiserver        # 反复 Exited
sudo crictl logs <id> 2>&1 | tail              # 连接 etcd 失败
sudo vim /etc/kubernetes/manifests/kube-apiserver.yaml   # 改回 2379（2380 是 etcd 的 peer 端口）
```
</details>

**15.4** ⚠️ 故障：`sudo mv /etc/kubernetes/manifests/kube-scheduler.yaml /root/`。然后创建一个 Deployment。任务：解释现象（Pending 且没有调度事件）并修复。

<details><summary>提示 / 参考</summary>

`kubectl -n kube-system get pods` 中没有 kube-scheduler → 把清单移回 `/etc/kubernetes/manifests/` → 等待静态 Pod 启动 → Pending 的 Pod 自动被调度。
</details>

**15.5** ⚠️ 依次创建下面 3 个有问题的工作负载，分别找出状态（ImagePullBackOff / CreateContainerConfigError / CrashLoopBackOff）的原因并修复。

```bash
kubectl create deploy bad-image --image=nginx:1.27-typo
kubectl create deploy bad-config --image=nginx && kubectl set env deploy/bad-config --from=configmap/does-not-exist
kubectl create deploy bad-cmd --image=busybox:1.36 -- sh -c 'echo starting; exit 1'
```

<details><summary>提示 / 参考</summary>

- `bad-image`：`describe` 中 `Failed to pull image` → `kubectl set image deploy/bad-image nginx=nginx:1.27`。
- `bad-config`：`describe` 中 `configmap "does-not-exist" not found` → 创建该 ConfigMap 或去掉 envFrom。
- `bad-cmd`：`kubectl logs deploy/bad-cmd --previous` → 修改命令为长驻进程。
</details>

**15.6** 创建 Pod `mem-hog`（参考官方示例 [`memory-request-limit-2.yaml`](../../references/cka/kubernetes-docs/examples/pods/resource/memory-request-limit-2.yaml)：申请 250M 内存但限制 100Mi）。找出它反复重启的原因，写入 `/opt/answers/oom.txt`，并修改限制使其正常运行。

<details><summary>提示 / 参考</summary>

`kubectl describe pod mem-hog` → `Last State: Terminated, Reason: OOMKilled, Exit Code: 137`。Pod 的 resources 不能直接修改（原地调整需走 resize 子资源），简单做法是导出 YAML、改 limits、`kubectl replace --force -f`。
</details>

**15.7** 找出命名空间 `kube-system` 中当前 **CPU 占用最高**的 Pod，把它的名字写入 `/opt/answers/top-cpu.txt`；再把各节点内存使用情况写入 `/opt/answers/node-mem.txt`。

<details><summary>提示 / 参考</summary>

```bash
kubectl top pods -n kube-system --sort-by=cpu --no-headers | head -1 | awk '{print $1}' > /opt/answers/top-cpu.txt
kubectl top nodes > /opt/answers/node-mem.txt
```
`Metrics API not available` → 先完成 7.4（安装 metrics-server）。
</details>

**15.8** 对 9.5 中的 `app-with-sidecar`：把 `log-streamer` 容器最近 20 行日志写入 `/opt/answers/sidecar.log`；再把 `kube-system` 中 kube-proxy 所有 Pod 日志中含 `error`（不区分大小写）的行写入 `/opt/answers/proxy-errors.txt`（可以为空）。

<details><summary>提示 / 参考</summary>

```bash
kubectl logs app-with-sidecar -c log-streamer --tail=20 > /opt/answers/sidecar.log
kubectl logs -n kube-system -l k8s-app=kube-proxy --tail=-1 | grep -i error > /opt/answers/proxy-errors.txt
```
</details>

**15.9** ⚠️ 故障：`kubectl -n kube-system scale deploy coredns --replicas=0`。任务：从一个普通 Pod 出发，证明「IP 能通但域名不通」，定位到 CoreDNS 并修复。

<details><summary>提示 / 参考</summary>

```bash
kubectl run tmp --rm -it --image=busybox:1.36 --restart=Never -- sh
#   wget -qO- -T 2 http://<echo 的 ClusterIP>/hostname   → 成功
#   nslookup echo                                       → 超时
kubectl -n kube-system get deploy coredns; kubectl get endpointslices -n kube-system -l kubernetes.io/service-name=kube-dns
kubectl -n kube-system scale deploy coredns --replicas=2
```
</details>

**15.10** 检查集群所有证书的到期时间，写入 `/opt/answers/certs.txt`；续期 apiserver 证书并让新证书生效。

<details><summary>提示 / 参考</summary>

```bash
sudo kubeadm certs check-expiration | tee /opt/answers/certs.txt
sudo kubeadm certs renew apiserver
# 重启 apiserver 静态 Pod：把清单临时移出 manifests 目录再移回，或按官方文档重启 kubelet 触发
sudo openssl x509 -in /etc/kubernetes/pki/apiserver.crt -noout -dates
```
</details>

---

## 考纲覆盖表

| CKA 考纲条目（v1.37） | 题号 |
|---|---|
| Manage role based access control (RBAC) | 6.1–6.4 |
| Prepare underlying infrastructure for installing a Kubernetes cluster | 3.1 |
| Create and manage Kubernetes clusters using kubeadm | 3.2, 3.3 |
| Manage the lifecycle of Kubernetes clusters | 4.1–4.4, 15.10 |
| Implement and configure a highly-available control plane | 5.1, 5.2 |
| Use Helm and Kustomize to install cluster components | 7.1–7.4 |
| Understand extension interfaces (CNI, CSI, CRI, etc.) | 8.1–8.3 |
| Understand CRDs, install and configure operators | 8.4, 8.5 |
| Understand application deployments and how to perform rolling update and rollbacks | 9.1, 9.2 |
| Use ConfigMaps and Secrets to configure applications | 9.3 |
| Configure workload autoscaling | 9.4 |
| Understand the primitives used to create robust, self-healing, application deployments | 9.5–9.7 |
| Configure Pod admission and scheduling (limits, node affinity, etc.) | 10.1–10.5 |
| Understand connectivity between Pods | 11.1, 12.1–12.3, 15.9 |
| Define and enforce Network Policies | 12.1–12.4 |
| Use ClusterIP, NodePort, LoadBalancer service types and endpoints | 11.1–11.3 |
| Use the Gateway API to manage Ingress traffic | 13.2–13.4 |
| Know how to use Ingress controllers and Ingress resources | 13.1, 13.4 |
| Understand and use CoreDNS | 11.2, 11.4, 15.9 |
| Implement storage classes and dynamic volume provisioning | 14.2, 14.4 |
| Configure volume types, access modes and reclaim policies | 14.1, 14.3 |
| Manage persistent volumes and persistent volume claims | 14.1–14.4 |
| Troubleshoot clusters and nodes | 15.1, 15.2 |
| Troubleshoot cluster components | 15.3, 15.4, 15.10 |
| Monitor cluster and application resource usage | 15.7, 7.4 |
| Manage and evaluate container output streams | 15.8, 9.5 |
| Troubleshoot services and networking | 11.3, 15.9 |

> 考纲中的 LoadBalancer 类型需要云环境或 MetalLB 才能拿到外部 IP，实验环境里能创建并理解其 `EXTERNAL-IP <pending>` 的含义即可。
