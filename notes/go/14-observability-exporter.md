# Go-14 可观测性：结构化日志、指标与 Prometheus exporter

> **轨道**：[Go](README.md) ｜ **运维场景**：kubeadm 集群的证书一年到期，到期那天 apiserver 直接不可用——写一个 exporter 把「证书还剩几天」变成指标，让 Prometheus 提前告警 ｜ **建议用时**：4 h（第 20 周） ｜ **难度**：★★★
>
> **前置**：[Go-08 网络、HTTP 与 TLS](08-net-http-tls.md) · [Go-11 容器化与部署](11-containerize-deploy.md)
> **后续**：Go 轨道的终点之一。之后可以给 P9 kpods、P11 operator 也加上指标
> **关联**（跨轨道）：[CKA-15 排错](../cka/15-troubleshooting.md)（`kubectl top`、日志）· [CKA-04 集群生命周期](../cka/04-cluster-lifecycle.md)（`kubeadm certs check-expiration`）· [F6 TLS / PKI](../00-foundations/06-tls-pki-basics.md) · [F2 journald](../00-foundations/02-systemd-journald.md)

## 1. 这个知识点在网络中的位置

CKA 排错时你靠 `kubectl logs`、`journalctl`、`kubectl top`。这些是「出了事再去看」。可观测性要做的是「出事之前就知道」：

| 信号 | 你在考试里见过的 | 本节 Go 里怎么做 |
|---|---|---|
| 日志 | `journalctl -u kubelet`、`kubectl logs` | 标准库 `log/slog` 输出 `key=value` 或 JSON，方便检索 |
| 指标 | `kubectl top`（metrics-server）、kubelet 的 `/metrics` | `prometheus/client_golang` 暴露 `/metrics` |
| 健康检查 | 探针 `/healthz` | 见 [G11](11-containerize-deploy.md) |

kube-apiserver、kubelet、etcd、CoreDNS 都暴露 Prometheus 格式的 `/metrics`，用的正是同一个 client_golang 库。写一个自己的 exporter，以后看这些组件的指标就不陌生了。

## 2. 核心概念

- **Prometheus 拉模型**：Prometheus 定期（如每 30 秒）请求你的 `/metrics`，你返回纯文本格式的指标。
- **四种指标类型**：Counter（只增，如请求总数）、Gauge（可增可减，如剩余秒数、队列长度）、Histogram（分桶统计，如请求延迟）、Summary。证书剩余时间是 Gauge。
- **标签（labels）**：`cert_expiry_seconds{target="/etc/kubernetes/pki/apiserver.crt"}`。标签组合不能无限增长（不要把用户 ID、请求 URL 当标签），否则 Prometheus 内存爆掉。
- **自定义 Collector**：每次被抓取时现算现报（实现 `Describe` 和 `Collect`），适合「状态来自外部」的 exporter；而在业务代码里埋点用 `promauto.NewCounter` 之类的直接 `Inc()`。
- **命名约定**：单位写在名字里，用基本单位（秒、字节）：`_seconds`、`_bytes`；Counter 以 `_total` 结尾。
- **`log/slog`**（Go 1.21+ 标准库）：`slog.Info("msg", "key", value)`；`slog.New(slog.NewJSONHandler(os.Stdout, nil))` 输出 JSON，日志平台可以直接按字段检索。

## 3. 必会操作

```bash
go mod init example.com/certexporter
go get github.com/prometheus/client_golang@v1.25.0   # 写作时实际拉到的版本；需要 go 1.26
```

最小版本（只读本地 PEM 文件；[P10](../../labs/go/projects.md#p10) 会扩展到检查远程 TLS 端口）。已编译运行，并用 client_golang 的 `testutil` 写了测试：

```go
type certCollector struct {
	glob    string
	expiry  *prometheus.Desc
	success *prometheus.Desc
	now     func() time.Time // 测试时可以替换成固定时间
}

func newCertCollector(glob string) *certCollector {
	return &certCollector{
		glob:    glob,
		expiry:  prometheus.NewDesc("cert_expiry_seconds", "证书剩余有效期（秒），负数表示已过期", []string{"target"}, nil),
		success: prometheus.NewDesc("cert_check_success", "本次检查是否成功（1 成功，0 失败）", []string{"target"}, nil),
		now:     time.Now,
	}
}

func (c *certCollector) Describe(ch chan<- *prometheus.Desc) { ch <- c.expiry; ch <- c.success }

// Collect 在每次被抓取时调用：现读文件、现算剩余时间
func (c *certCollector) Collect(ch chan<- prometheus.Metric) {
	files, _ := filepath.Glob(c.glob)
	for _, f := range files {
		cert, err := readCert(f) // os.ReadFile → pem.Decode → x509.ParseCertificate
		if err != nil {
			slog.Warn("check failed", "target", f, "err", err) // 结构化日志
			ch <- prometheus.MustNewConstMetric(c.success, prometheus.GaugeValue, 0, f)
			continue
		}
		left := cert.NotAfter.Sub(c.now()).Seconds()
		ch <- prometheus.MustNewConstMetric(c.expiry, prometheus.GaugeValue, left, f)
		ch <- prometheus.MustNewConstMetric(c.success, prometheus.GaugeValue, 1, f)
	}
}

func main() {
	glob := flag.String("certs", "/etc/kubernetes/pki/*.crt", "证书文件 glob")
	addr := flag.String("listen", ":9101", "监听地址")
	flag.Parse()
	reg := prometheus.NewRegistry() // 独立 registry：只暴露自己的指标
	reg.MustRegister(newCertCollector(*glob))
	mux := http.NewServeMux()
	mux.Handle("GET /metrics", promhttp.HandlerFor(reg, promhttp.HandlerOpts{}))
	mux.HandleFunc("GET /healthz", func(w http.ResponseWriter, r *http.Request) { w.Write([]byte("ok\n")) })
	srv := &http.Server{Addr: *addr, Handler: mux, ReadHeaderTimeout: 5 * time.Second}
	slog.Info("listening", "addr", *addr, "certs", *glob)
	if err := srv.ListenAndServe(); err != nil {
		slog.Error("server stopped", "err", err)
		os.Exit(1)
	}
}
```

运行效果（用 openssl 生成一张 30 天的自签证书测试）：

```bash
./certexporter -certs 'pki/*.crt' -listen 127.0.0.1:9101 &
curl -s 127.0.0.1:9101/metrics
```

```text
# HELP cert_check_success 本次检查是否成功（1 成功，0 失败）
# TYPE cert_check_success gauge
cert_check_success{target="pki/ca.crt"} 1
# HELP cert_expiry_seconds 证书剩余有效期（秒），负数表示已过期
# TYPE cert_expiry_seconds gauge
cert_expiry_seconds{target="pki/ca.crt"} 2.591998175844096e+06
```

测试的关键：用 `crypto/x509` 现场生成一张「48 小时后过期」的证书，把 `now` 换成固定时间，然后 `testutil.CollectAndCompare(c, strings.NewReader(want))` 断言输出里正好是 `172800`。

### 3.1 运维场景示例：给 kubeadm 集群的证书加告警

1. 按 [G11](11-containerize-deploy.md) 打镜像；Deployment 用 `nodeSelector` + 容忍 `node-role.kubernetes.io/control-plane:NoSchedule` 调度到控制平面节点，`hostPath`（只读）挂载 `/etc/kubernetes/pki`（[CKA-10](../cka/10-scheduling.md)、[CKA-14](../cka/14-storage.md)）。
2. Prometheus 告警规则：`cert_expiry_seconds < 7 * 24 * 3600`，或者 `cert_check_success == 0`。
3. 告警响了以后的处理流程就是 [CKA-04](../cka/04-cluster-lifecycle.md) 里的 `kubeadm certs check-expiration` 和 `kubeadm certs renew all`。

## 4. 考试坑点

- 在 `Collect` 里做很慢的操作（比如串行连 100 个远程端口），Prometheus 抓取会超时。远程检查要并发做（[G7](07-concurrency-context.md)），或者后台定时检查、抓取时读缓存。
- 用默认的全局 registry（`prometheus.MustRegister`）会顺带暴露 Go 运行时指标。想要就加上，不想要就用 `prometheus.NewRegistry()`。
- 时间相关的代码直接调 `time.Now()` 没法测。像上面一样把 `now` 做成可替换的字段。
- 标签值来自外部输入时要控制取值范围，见第 2 节的「标签组合不能无限增长」。
- 日志里不要打证书私钥、token、密码，`slog` 的结构化字段一样会被日志平台收走。

## 5. 动手练习

- 项目：[P10 cert-exporter：证书过期 exporter](../../labs/go/projects.md#p10)（第 20 周）：在本节基础上支持远程 `host:port`、配置文件、部署到集群
- 小练习：给 [G11](11-containerize-deploy.md) 的 healthsvc 加一个 `http_requests_total{code="200"}` Counter 和一个延迟 Histogram，用 `promhttp.InstrumentHandlerCounter` 包住 handler

**配套 LeetCode（第 20 周，[刷题计划](../../labs/go/leetcode-plan.md#w20)）**

- [1192. 查找集群内的关键连接](https://leetcode.cn/problems/critical-connections-in-a-network/)（困难）：找出断掉就会让集群分裂的链路，也就是单点故障（Tarjan 求桥）
- [1584. 连接所有点的最小费用](https://leetcode.cn/problems/min-cost-to-connect-all-points/)：最小生成树，≈ 用最少的布线把所有机房连起来

## 6. 官方文档（本仓库离线版 + 本机查法）

- client_golang 官方示例：[simple](../../references/go/prometheus-client-golang-examples/simple/main.go)、[customlabels](../../references/go/prometheus-client-golang-examples/customlabels/main.go)、[middleware](../../references/go/prometheus-client-golang-examples/middleware/)
- Kubernetes 组件自身的指标：[system-metrics.md](../../references/cka/kubernetes-docs/concepts/cluster-administration/system-metrics.md)、[resource-metrics-pipeline.md](../../references/cka/kubernetes-docs/tasks/debug/debug-cluster/resource-metrics-pipeline.md)
- 日志：[logging.md](../../references/cka/kubernetes-docs/concepts/cluster-administration/logging.md)
- kubeadm 证书管理：[kubeadm-certs.md](../../references/cka/kubernetes-docs/tasks/administer-cluster/kubeadm/kubeadm-certs.md)
- kubebuilder 项目里的指标：[metrics.md](../../references/go/k8s/kubebuilder-book/reference/metrics.md)
- 本机：`go doc log/slog`、`go doc crypto/x509.Certificate`、`openssl x509 -in apiserver.crt -noout -enddate`（对照验证）

## 7. 自测清单

- [ ] 能说出 Counter、Gauge、Histogram 各适合什么场景
- [ ] 能写一个自定义 Collector，并用 `testutil.CollectAndCompare` 测试
- [ ] 能解释为什么要控制标签的取值范围
- [ ] 会用 `slog` 输出 JSON 日志，并知道哪些字段不能打
- [ ] 能把 exporter 部署到控制平面节点上读 `/etc/kubernetes/pki`
- [ ] 能写出「证书 7 天内过期」的 PromQL 表达式
