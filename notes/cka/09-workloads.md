# CKA-09 工作负载：Deployment、ConfigMap/Secret 与 HPA

> **轨道**：[CKA](README.md) ｜ **考纲**：CKA「Workloads and Scheduling (15%)」 ｜ **建议用时**：8 h ｜ **难度**：★★☆
>
> **前置**：[CKA-02 kubectl 高效操作](02-kubectl-efficiency.md) · [F4 YAML 语法](../00-foundations/04-yaml.md) · [F5 Docker → Podman → K8s](../00-foundations/05-containers-docker-to-k8s.md)
> **后续**：[CKA-10 调度](10-scheduling.md) · [CKA-07 Helm 与 Kustomize](07-helm-kustomize.md) · [CKA-11 Service 与 CoreDNS](11-services-dns.md) · [CKA-14 存储](14-storage.md)
> **关联**（跨轨道）：[RHCSA-10 Podman 容器](../rhcsa/10-containers-podman.md) · [RHCE-10 Ansible Vault](../rhce/10-vault.md)

## 1. 这个知识点在网络中的位置

考纲这一块（15%）考的是「把应用跑起来并且跑得稳」：Deployment 滚动更新/回滚、ConfigMap/Secret 注入配置、HPA 自动扩缩、探针等自愈原语。
它是 Service（K11）、存储（K14）、调度（K10）的共同起点——几乎每道题都要先有一个 Pod/Deployment。
你熟悉的 `docker compose up` 在 K8s 里被拆成了好几个对象，先把对应关系建立起来：

| docker-compose.yml | Kubernetes 对象/字段 | 说明 |
|---|---|---|
| `services.web.image` | `Deployment.spec.template.spec.containers[].image` | Pod 模板里的容器 |
| `deploy.replicas` / `--scale` | `Deployment.spec.replicas`、`kubectl scale` | ReplicaSet 负责维持副本数 |
| `restart: always` | Pod `restartPolicy: Always`（Deployment 只能是 Always）+ 控制器重建 | 自愈：容器崩了 kubelet 重启，Pod 没了控制器重建 |
| `environment:` / `env_file:` | `env` / `envFrom` + ConfigMap、Secret | 配置与镜像分离 |
| `ports:` | `containerPort`（仅声明）+ **Service**（真正暴露，见 K11） | compose 的端口映射 ≈ NodePort/LoadBalancer |
| `volumes:`（命名卷） | PVC + PV（见 K14） | |
| `healthcheck:` | `livenessProbe` / `readinessProbe` / `startupProbe` | readiness 失败会把 Pod 从 Service 摘掉 |
| `depends_on:` | **没有直接等价物**：用 initContainers 等待依赖 + readinessProbe | K8s 假设依赖随时可能不可用 |
| `docker compose up -d` 改镜像 | `kubectl set image` → 滚动更新 | 可 `rollout undo` 回滚 |

## 2. 核心概念

- **Deployment → ReplicaSet → Pod**：改 Pod 模板（镜像、环境变量、资源……）会生成新 ReplicaSet 并滚动替换；只改 `replicas` 不会产生新版本。
- **滚动更新策略** `spec.strategy`：
  - `RollingUpdate`（默认）：`maxSurge`（最多多出几个，默认 25%）、`maxUnavailable`（最多少几个，默认 25%）。
  - `Recreate`：先全部删掉再创建，会中断服务。
- **修订历史**：`revisionHistoryLimit`（默认 10）；`kubectl rollout history` 的 CHANGE-CAUSE 来自注解 `kubernetes.io/change-cause`（`--record` 已废弃）。
- **其他控制器**（知道用途、会写最小 YAML）：DaemonSet（每节点一个，如日志/网络插件）、StatefulSet（稳定名称+独立 PVC）、Job/CronJob（一次性/定时任务）。
- **ConfigMap / Secret** 三种用法：`env.valueFrom`（单个键）、`envFrom`（全部键）、挂载为卷（每个键一个文件，**卷方式会热更新**，env 方式需重启 Pod）。Secret 默认只是 base64 编码，不是加密。
- **自愈原语**：
  - `livenessProbe` 失败 → 重启容器；`readinessProbe` 失败 → 从 Service Endpoints 中摘除；`startupProbe` 成功前不跑另外两个探针（慢启动应用）。
  - initContainers：按顺序跑完才启动主容器；`restartPolicy: Always` 的 initContainer 就是原生 **sidecar**（v1.33 GA）。
  - PodDisruptionBudget：限制主动驱逐（drain）时最多同时不可用的 Pod 数。
- **HPA**（`autoscaling/v2`）：依赖 **metrics-server** 提供 CPU/内存指标；目标是 Deployment/StatefulSet 的 `scale` 子资源；按 `requests` 计算利用率——**容器没设 requests，CPU 百分比 HPA 就算不出来**（TARGETS 显示 `<unknown>`）。

## 3. 必会操作

```bash
# 生成 Deployment 骨架（考场最快路径：命令生成 YAML，再 vim 补字段）
kubectl create deployment web --image=nginx:1.27 --replicas=3 --port=80 --dry-run=client -o yaml > web.yaml

# 滚动更新：改镜像（web 是容器名，不是 Deployment 名，可用 kubectl get deploy web -o yaml 查）
kubectl set image deployment/web nginx=nginx:1.28
kubectl annotate deployment/web kubernetes.io/change-cause="upgrade to 1.28"   # 记录变更原因
kubectl rollout status deployment/web          # 等待完成
kubectl rollout history deployment/web         # 查看历史
kubectl rollout history deployment/web --revision=2
kubectl rollout undo deployment/web            # 回到上一版
kubectl rollout undo deployment/web --to-revision=1
kubectl rollout pause|resume deployment/web     # 暂停后可连续修改，再一次性发布
kubectl rollout restart deployment/web          # 重建所有 Pod（例如 ConfigMap 以 env 注入后需要）

# 扩缩容
kubectl scale deployment/web --replicas=5

# ConfigMap / Secret
kubectl create configmap app-cfg --from-literal=MODE=prod --from-file=app.conf
kubectl create secret generic db-cred --from-literal=user=admin --from-literal=password='S3cr3t!'
kubectl create secret tls web-tls --cert=tls.crt --key=tls.key
kubectl get secret db-cred -o jsonpath='{.data.password}' | base64 -d; echo
kubectl set env deployment/web --from=configmap/app-cfg        # 全部键注入为环境变量

# HPA（kubectl 新版用 --cpu，旧参数 --cpu-percent 已移除/废弃，以 kubectl autoscale --help 为准）
kubectl autoscale deployment web --min=2 --max=10 --cpu=50%
kubectl get hpa -w
kubectl top pods                                 # 先确认 metrics-server 工作
```

一个包含配置注入、探针、资源请求的 Deployment（HPA 能工作的最低要求就是有 `resources.requests`）：

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: web
spec:
  replicas: 3
  selector:
    matchLabels: {app: web}          # 必须与 template.labels 匹配，创建后不可改
  strategy:
    type: RollingUpdate
    rollingUpdate: {maxSurge: 1, maxUnavailable: 0}
  template:
    metadata:
      labels: {app: web}
    spec:
      containers:
      - name: nginx
        image: nginx:1.27
        ports: [{containerPort: 80}]
        envFrom:
        - configMapRef: {name: app-cfg}
        env:
        - name: DB_PASSWORD
          valueFrom:
            secretKeyRef: {name: db-cred, key: password}
        resources:
          requests: {cpu: 100m, memory: 128Mi}
          limits:   {memory: 256Mi}
        readinessProbe:
          httpGet: {path: /, port: 80}
          periodSeconds: 5
        livenessProbe:
          tcpSocket: {port: 80}
          initialDelaySeconds: 10
        volumeMounts:
        - {name: cfg, mountPath: /etc/app, readOnly: true}
      volumes:
      - name: cfg
        configMap: {name: app-cfg}
```

HPA 的 v2 写法（需要按内存扩缩、或自定义扩缩行为时用 YAML）：

```yaml
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: web
spec:
  scaleTargetRef: {apiVersion: apps/v1, kind: Deployment, name: web}
  minReplicas: 2
  maxReplicas: 10
  metrics:
  - type: Resource
    resource:
      name: cpu
      target: {type: Utilization, averageUtilization: 50}
  behavior:
    scaleDown:
      stabilizationWindowSeconds: 300   # 缩容冷却
```

## 4. 考试坑点

- **容器名 ≠ Deployment 名**：`kubectl create deployment web --image=nginx` 生成的容器名是 `nginx`（取自镜像名）。`set image` 写错容器名会报错。
- 题目要求「记录变更原因」时用 `kubernetes.io/change-cause` 注解，别再用 `--record`。
- `selector` 创建后不可修改；改标签只能删了重建。
- Secret 的 YAML 里 `data:` 要 base64；不想手动编码就用 `stringData:`。
- ConfigMap 用 `subPath` 挂载的文件**不会**热更新。
- HPA `TARGETS` 一直 `<unknown>`：没有 metrics-server、或者容器没设 `requests`。
- 「回滚到上一个版本」后，`rollout history` 的 revision 编号会**往后加**而不是回到旧号，看清题意要的是哪个镜像。
- 做完题用 `kubectl rollout status` 和 `kubectl get pods -o wide` 确认真正 Running/Ready，而不是只看 `created`。

## 5. 动手练习

- [CKA 练习题集 · K9 工作负载](../../labs/cka/practice-set-1.md#k9-工作负载)（滚动更新与回滚、ConfigMap/Secret、HPA、sidecar、PDB）
- [CKA 模拟考](../../labs/cka/mock-exam.md) 第 6、7 题

## 6. 官方文档（本仓库离线版 + 考场可用的查法）

- 离线：
  - [Deployments](../../references/cka/kubernetes-docs/concepts/workloads/controllers/deployment.md) · [执行滚动更新教程](../../references/cka/kubernetes-docs/tasks/run-application/update-deployment-rolling.md)
  - [DaemonSet](../../references/cka/kubernetes-docs/concepts/workloads/controllers/daemonset.md) · [StatefulSet](../../references/cka/kubernetes-docs/concepts/workloads/controllers/statefulset.md) · [Job](../../references/cka/kubernetes-docs/concepts/workloads/controllers/job.md) · [CronJob](../../references/cka/kubernetes-docs/concepts/workloads/controllers/cron-jobs.md)
  - [ConfigMap](../../references/cka/kubernetes-docs/concepts/configuration/configmap.md) · [Secret](../../references/cka/kubernetes-docs/concepts/configuration/secret.md) · [用 ConfigMap 配置 Pod](../../references/cka/kubernetes-docs/tasks/configure-pod-container/configure-pod-configmap.md) · [用 Secret 分发凭据](../../references/cka/kubernetes-docs/tasks/inject-data-application/distribute-credentials-secure.md)
  - [探针配置](../../references/cka/kubernetes-docs/tasks/configure-pod-container/configure-liveness-readiness-startup-probes.md) · [Pod 生命周期](../../references/cka/kubernetes-docs/concepts/workloads/pods/pod-lifecycle.md) · [Init 容器](../../references/cka/kubernetes-docs/concepts/workloads/pods/init-containers.md) · [Sidecar 容器](../../references/cka/kubernetes-docs/concepts/workloads/pods/sidecar-containers.md)
  - [HPA 概念](../../references/cka/kubernetes-docs/concepts/workloads/autoscaling/horizontal-pod-autoscale.md) · [HPA 演练](../../references/cka/kubernetes-docs/tasks/run-application/horizontal-pod-autoscale-walkthrough.md) · [PDB](../../references/cka/kubernetes-docs/tasks/run-application/configure-pdb.md)
  - 示例 YAML：[`examples/controllers/`](../../references/cka/kubernetes-docs/examples/controllers/)、[`examples/application/`](../../references/cka/kubernetes-docs/examples/application/)
- 考场（kubernetes.io）：
  - `/docs/concepts/workloads/controllers/deployment/`（搜索框搜 "deployment" 第一条）
  - `/docs/tasks/configure-pod-container/configure-liveness-readiness-startup-probes/`
  - `/docs/tasks/run-application/horizontal-pod-autoscale-walkthrough/`
  - 命令行：`kubectl explain deployment.spec.strategy --recursive`、`kubectl create deployment -h`、`kubectl autoscale -h`

## 7. 自测清单

- [ ] 2 分钟内用命令生成并改好一个带 3 副本、资源请求、readinessProbe 的 Deployment
- [ ] 能完成「升级镜像 → 发现问题 → 回滚到指定 revision」并用 `rollout history` 验证
- [ ] 能用 env、envFrom、卷三种方式使用 ConfigMap/Secret，并说出哪种会热更新
- [ ] 能创建 CPU 50% 的 HPA，并解释 TARGETS 为 `<unknown>` 的两种原因
- [ ] 能说出 liveness / readiness / startup 三种探针失败后的不同后果
- [ ] 能把一个 docker-compose 服务翻译成 Deployment + Service + ConfigMap
