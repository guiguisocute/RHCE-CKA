# Go-11 容器化与在 K8s 上运行 Go 服务

> **轨道**：[Go](README.md) ｜ **运维场景**：把自己写的运维工具做成 15 MB 的镜像，部署到集群里，配好探针、资源限制和优雅退出，滚动更新时不丢请求 ｜ **建议用时**：4 h（第 17 周） ｜ **难度**：★★☆
>
> **前置**：[Go-08 网络、HTTP 与 TLS](08-net-http-tls.md)
> **后续**：[Go-14 可观测性：日志、指标与 exporter](14-observability-exporter.md)
> **关联**（跨轨道）：[F5 Docker → Podman → K8s](../00-foundations/05-containers-docker-to-k8s.md) · [CKA-09 工作负载与探针](../cka/09-workloads.md) · [CKA-10 资源与调度](../cka/10-scheduling.md) · [CKA-11 Service](../cka/11-services-dns.md) · [F2 systemd（SIGTERM 的来历）](../00-foundations/02-systemd-journald.md)

## 1. 这个知识点在网络中的位置

你已经会用 docker compose 跑别人的镜像。这一节反过来：给自己的 Go 程序做镜像，并让它在 Kubernetes 里「表现良好」。CKA 考的探针、资源限制、滚动更新，在这里都要从**程序这一侧**落实：

| CKA 里的配置 | Go 程序要配合做的事 |
|---|---|
| `livenessProbe: httpGet /healthz` | 提供一个永远很快返回 200 的 `/healthz` |
| `readinessProbe: httpGet /readyz` | 准备好（配置加载完、依赖连上）才返回 200；退出前先返回 503 |
| `kubectl delete pod`、滚动更新 | kubelet 发 SIGTERM → 程序要 `srv.Shutdown()` 等请求处理完 |
| `terminationGracePeriodSeconds: 30` | 优雅退出必须在 30 秒内完成，否则被 SIGKILL |
| ConfigMap 注入 env | 从 `os.Getenv` 读配置 |
| `securityContext.runAsNonRoot` | 镜像以数字 UID 的非 root 用户运行 |

Go 编译出的静态二进制不依赖 glibc，所以运行镜像可以用 distroless 甚至 scratch，体积比带 Python 运行时的镜像小一两个数量级。

## 2. 核心概念

- **多阶段构建**：第一阶段 `FROM golang` 编译，第二阶段只 `COPY` 二进制。最终镜像里没有编译器、没有 shell。
- **`CGO_ENABLED=0`**：关掉 cgo，得到完全静态链接的二进制（`ldd` 显示 `not a dynamic executable`），才能放进 scratch / distroless/static。
- **distroless vs scratch**：scratch 是空镜像；`gcr.io/distroless/static-debian12` 多了 CA 证书、`/etc/passwd`、时区数据，访问 HTTPS 和做时区转换不用自己处理，推荐用它。
- **`signal.NotifyContext`**：把 SIGTERM / SIGINT 变成 `ctx.Done()`，和 [G7](07-concurrency-context.md) 的 context 用法统一。
- **liveness ≠ readiness**：liveness 失败会**重启容器**，所以不要在 liveness 里检查数据库这类外部依赖，否则数据库一抖，所有 Pod 被一起重启。外部依赖放进 readiness。

## 3. 必会操作

`main.go`（已编译运行，并在容器里验证过 SIGTERM 优雅退出）：

```go
package main

import (
	"context"
	"errors"
	"log/slog"
	"net/http"
	"os"
	"os/signal"
	"sync/atomic"
	"syscall"
	"time"
)

func main() {
	addr := ":8080"
	if v := os.Getenv("LISTEN_ADDR"); v != "" { // 配置从环境变量读（≈ ConfigMap 注入的 env）
		addr = v
	}
	var ready atomic.Bool

	mux := http.NewServeMux()
	mux.HandleFunc("GET /healthz", func(w http.ResponseWriter, r *http.Request) { w.Write([]byte("ok\n")) })
	mux.HandleFunc("GET /readyz", func(w http.ResponseWriter, r *http.Request) {
		if !ready.Load() {
			http.Error(w, "not ready", http.StatusServiceUnavailable)
			return
		}
		w.Write([]byte("ready\n"))
	})
	mux.HandleFunc("GET /", func(w http.ResponseWriter, r *http.Request) {
		host, _ := os.Hostname() // 在 Pod 里就是 Pod 名
		w.Write([]byte("hello from " + host + "\n"))
	})
	srv := &http.Server{Addr: addr, Handler: mux, ReadHeaderTimeout: 5 * time.Second}

	// kubelet 停容器时发 SIGTERM；本地按 Ctrl+C 是 SIGINT
	ctx, stop := signal.NotifyContext(context.Background(), syscall.SIGINT, syscall.SIGTERM)
	defer stop()
	go func() {
		slog.Info("listening", "addr", addr)
		if err := srv.ListenAndServe(); err != nil && !errors.Is(err, http.ErrServerClosed) {
			slog.Error("server failed", "err", err)
			os.Exit(1)
		}
	}()
	ready.Store(true) // 真实服务里：配置加载完、依赖连上之后再置 true

	<-ctx.Done()
	slog.Info("shutting down")
	ready.Store(false) // 先让 readiness 失败，摘掉流量
	shutdownCtx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()
	if err := srv.Shutdown(shutdownCtx); err != nil { // 不再接新连接，等进行中的请求完成
		slog.Error("shutdown", "err", err)
	}
	slog.Info("bye")
}
```

`Dockerfile`（已实际构建，最终镜像 14.9 MB；镜像标签以 Docker Hub 和 distroless 仓库为准）：

```dockerfile
# ---- 构建阶段 ----
FROM golang:1.26 AS build
WORKDIR /src
COPY go.mod go.sum ./
RUN go mod download                 # 依赖单独一层，代码改动时不用重新下载
COPY . .
RUN CGO_ENABLED=0 GOOS=linux go build -trimpath -ldflags="-s -w" -o /out/healthsvc .

# ---- 运行阶段：只放一个静态二进制 ----
FROM gcr.io/distroless/static-debian12:nonroot
COPY --from=build /out/healthsvc /healthsvc
EXPOSE 8080
USER 65532:65532                    # 用数字 UID，K8s 的 runAsNonRoot 才能校验
ENTRYPOINT ["/healthsvc"]
```

> 没有第三方依赖时没有 `go.sum`，把 `COPY go.mod go.sum ./` 改成 `COPY go.mod ./` 并删掉 `go mod download` 那行。

```bash
docker build -t healthsvc:v1 .          # RHEL 上：podman build -t healthsvc:v1 .
docker run --rm -p 8080:8080 healthsvc:v1
kind load docker-image healthsvc:v1     # 把本地镜像放进 kind 集群
kubectl apply -f healthsvc.yaml
```

`healthsvc.yaml`（Deployment + Service）：

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: healthsvc
spec:
  replicas: 2
  selector:
    matchLabels: {app: healthsvc}
  template:
    metadata:
      labels: {app: healthsvc}
    spec:
      terminationGracePeriodSeconds: 30
      containers:
        - name: healthsvc
          image: healthsvc:v1
          imagePullPolicy: IfNotPresent
          ports: [{name: http, containerPort: 8080}]
          livenessProbe:  {httpGet: {path: /healthz, port: http}, initialDelaySeconds: 3, periodSeconds: 10}
          readinessProbe: {httpGet: {path: /readyz, port: http}, periodSeconds: 5}
          resources:
            requests: {cpu: 50m, memory: 32Mi}
            limits: {memory: 64Mi}
          securityContext: {runAsNonRoot: true, readOnlyRootFilesystem: true, allowPrivilegeEscalation: false}
---
apiVersion: v1
kind: Service
metadata:
  name: healthsvc
spec:
  selector: {app: healthsvc}
  ports: [{name: http, port: 80, targetPort: http}]
```

### 3.1 运维场景示例：验证滚动更新不丢请求

1. 一个终端里循环请求：`kubectl run curl --image=curlimages/curl -it --rm -- sh -c 'while true; do curl -s healthsvc/; sleep 0.2; done'`
2. 另一个终端：`kubectl rollout restart deploy/healthsvc`，同时 `kubectl get pods -w`。
3. 观察日志 `kubectl logs -f deploy/healthsvc`：能看到 `shutting down` → `bye`，请求没有报错。
4. 对照实验：把 `srv.Shutdown` 换成 `os.Exit(0)` 重新部署，再滚动一次，看看会不会出现连接被拒。

## 4. 考试坑点

- **`USER nonroot:nonroot`（名字）配上 `runAsNonRoot: true` 会导致 Pod 起不来**：kubelet 无法从用户名判断是不是 root，报 `CreateContainerConfigError`。Dockerfile 里写数字 UID（distroless 的 nonroot 用户是 65532）。
- 国内网络下，构建阶段的 `go mod download` 可能很慢甚至超时：在构建阶段加一行 `ENV GOPROXY=https://goproxy.cn,direct`（和本机 `go env -w GOPROXY=...` 是同一个设置）。
- 忘了 `CGO_ENABLED=0`：用到 `net`、`os/user` 的程序默认可能动态链接 glibc，放进 distroless/static 或 scratch 后启动失败。
- 镜像标签用 `latest` 时 `imagePullPolicy` 默认是 `Always`，kind 里刚 `kind load` 的镜像会被忽略，节点去远程拉，拉不到就 `ErrImagePull`。用具体标签。
- 进程收到 SIGTERM 后立刻退出 → 正在处理的请求失败。PID 1 的进程默认没有信号处理，必须像上面那样自己处理。
- 在 liveness 里检查外部依赖，会导致级联重启（见第 2 节）。

## 5. 动手练习

- 第 17 周任务：把 [P8 certcheck](../../labs/go/projects.md#p8) 改成 HTTP 服务，按本节方式打镜像、部署到 kind，配上两种探针；第 20 周它会变成 [P10 cert-exporter](../../labs/go/projects.md#p10)。
- 动手体会：故意让 `/healthz` 返回 500，观察 `kubectl get pods` 里的 RESTARTS 和 `kubectl describe pod` 里的事件。

**配套 LeetCode（第 17 周，[刷题计划](../../labs/go/leetcode-plan.md#w17)）**

- [200. 岛屿数量](https://leetcode.cn/problems/number-of-islands/)：BFS / DFS 基本功，统计「互相连通的一组节点」
- [994. 腐烂的橘子](https://leetcode.cn/problems/rotting-oranges/)：多源 BFS，≈ 故障从几个节点向外扩散需要几轮
- [102. 二叉树的层序遍历](https://leetcode.cn/problems/binary-tree-level-order-traversal/)：按层处理，≈ 分批滚动发布

## 6. 官方文档（本仓库离线版 + 本机查法）

- 探针：[configure-liveness-readiness-startup-probes.md](../../references/cka/kubernetes-docs/tasks/configure-pod-container/configure-liveness-readiness-startup-probes.md)
- Pod 终止流程（SIGTERM、宽限期）：[pod-lifecycle.md](../../references/cka/kubernetes-docs/concepts/workloads/pods/pod-lifecycle.md)
- 资源请求与限制：[manage-resources-containers.md](../../references/cka/kubernetes-docs/concepts/configuration/manage-resources-containers.md)
- Go by Example：[signals.go](../../references/go/gobyexample/examples/signals/signals.go)、[http-server.go](../../references/go/gobyexample/examples/http-server/http-server.go)
- client-go 官方示例里的 [Dockerfile](../../references/go/k8s/client-go-examples/in-cluster-client-configuration/Dockerfile)（对比一下写法）
- 本机：`go doc os/signal.NotifyContext`、`go doc net/http.Server.Shutdown`

## 7. 自测清单

- [ ] 能写出多阶段 Dockerfile，并解释每一行
- [ ] 能说出 `CGO_ENABLED=0`、`-trimpath`、`-ldflags="-s -w"` 各自的作用
- [ ] 能解释 liveness 和 readiness 失败后分别会发生什么
- [ ] 程序收到 SIGTERM 后先摘流量、再等请求完成、最后退出
- [ ] 能把本地镜像放进 kind 集群并跑起来，`kubectl rollout restart` 时请求不报错
- [ ] 能排查 `CreateContainerConfigError`（runAsNonRoot + 非数字 UID）
