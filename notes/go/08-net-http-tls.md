# Go-08 网络、HTTP 与 TLS

> **轨道**：[Go](README.md) ｜ **运维场景**：给服务加 `/healthz`、写健康检查探针、调内部 API、批量检查证书还剩几天过期 ｜ **建议用时**：4 h（第 15 周） ｜ **难度**：★★★
>
> **前置**：[Go-07 并发](07-concurrency-context.md)
> **后续**：[Go-11 容器化与在 K8s 上运行](11-containerize-deploy.md) · [Go-14 可观测性与 exporter](14-observability-exporter.md)
> **关联**（跨轨道）：[S7 网络 nmcli](../rhcsa/07-networking-nmcli.md) · [F3 网络基础](../00-foundations/03-networking-basics.md) · [F6 TLS / PKI 基础](../00-foundations/06-tls-pki-basics.md) · [K9 工作负载与探针](../cka/09-workloads.md) · [K4 证书与集群维护](../cka/04-cluster-lifecycle.md)

## 1. 这个知识点在网络中的位置

Go 的 `net/http` 不用任何框架就能写出生产可用的 HTTP 服务，Kubernetes 的 apiserver、kubelet、Prometheus 都建立在它之上。
这一节把三门考试里的网络知识串起来：RHCSA 的端口和防火墙、CKA 的 liveness/readiness 探针和 SIGTERM 优雅退出、kubeadm 集群证书一年过期（`kubeadm certs check-expiration`）。本周的项目 P8 certcheck，就是一个能检查任意 TLS 端口或 PEM 文件的「证书到期巡检」工具。

## 2. 核心概念

| 包 | 用途 | 常用 API |
|---|---|---|
| `net` | TCP/UDP、DNS | `Dial`、`Dialer{Timeout}.DialContext`、`Listen`、`LookupHost`、`SplitHostPort` |
| `net/netip` | IP 和网段（比 `net.IP` 更好用） | `ParseAddr`、`ParsePrefix`、`Prefix.Contains` |
| `net/http` 服务端 | HTTP 服务 | `NewServeMux`、`HandleFunc("GET /healthz", ...)`（Go 1.22+ 路由支持方法和 `{id}` 通配）、`Server{ReadHeaderTimeout}`、`Shutdown` |
| `net/http` 客户端 | 调 API | `Client{Timeout}`、`NewRequestWithContext`、`resp.Body.Close()` |
| `net/http/httptest` | 测试 | `NewRecorder`、`NewRequest`、`NewServer`、`NewTLSServer` |
| `crypto/tls` | TLS 连接 | `Dial`、`Config{ServerName, MinVersion}`、`ConnectionState().PeerCertificates` |
| `crypto/x509` + `encoding/pem` | 解析证书 | `pem.Decode`、`x509.ParseCertificate`、`cert.NotAfter`、`cert.DNSNames` |

**优雅退出**：kubelet 停止 Pod 时先发 SIGTERM，等 `terminationGracePeriodSeconds`（默认 30 秒）后再发 SIGKILL。程序应该在收到 SIGTERM 后先让 `/readyz` 返回失败、停止接新请求，处理完手上的请求再退出。

## 3. 必会操作

**运维场景示例 1：带 `/healthz`、`/readyz` 的服务，收到 SIGTERM 时优雅退出**

```go
package main

import (
	"context"
	"errors"
	"io"
	"log"
	"net/http"
	"os"
	"os/signal"
	"sync/atomic"
	"syscall"
	"time"
)

func main() {
	var ready atomic.Bool

	mux := http.NewServeMux()
	mux.HandleFunc("GET /healthz", func(w http.ResponseWriter, r *http.Request) { // Go 1.22+ 支持在路由里写方法
		io.WriteString(w, "ok\n")
	})
	mux.HandleFunc("GET /readyz", func(w http.ResponseWriter, r *http.Request) {
		if !ready.Load() {
			http.Error(w, "not ready", http.StatusServiceUnavailable)
			return
		}
		io.WriteString(w, "ready\n")
	})

	srv := &http.Server{Addr: ":8080", Handler: mux, ReadHeaderTimeout: 5 * time.Second}

	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer stop()

	go func() {
		log.Println("listening on", srv.Addr)
		if err := srv.ListenAndServe(); err != nil && !errors.Is(err, http.ErrServerClosed) {
			log.Fatal(err)
		}
	}()
	time.Sleep(500 * time.Millisecond) // 假装在加载配置、预热缓存
	ready.Store(true)

	<-ctx.Done() // 等 SIGTERM（kubelet 停止 Pod 时发的就是它）
	ready.Store(false)
	log.Println("shutting down")
	shutdownCtx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()
	if err := srv.Shutdown(shutdownCtx); err != nil { // 不再接新请求，等进行中的请求处理完
		log.Println("shutdown:", err)
	}
}
```

```bash
go build -o health . && ./health &                  # 用编译好的二进制测，go run 不会把 SIGTERM 转给子进程
curl -s localhost:8080/healthz                       # ok
curl -s -o /dev/null -w '%{http_code}\n' -X POST localhost:8080/healthz   # 405：方法不匹配
kill -TERM %1                                        # 日志里出现 shutting down
```

用 `httptest` 测试 handler，不需要真的监听端口：

```go
rec := httptest.NewRecorder()
mux.ServeHTTP(rec, httptest.NewRequest(http.MethodGet, "/healthz", nil))
if rec.Code != http.StatusOK { t.Fatalf("got %d", rec.Code) }
```

**运维场景示例 2：证书还剩多少天过期（远端端口或本地 PEM 文件）**

```go
// remoteCert 连上 host:port 做 TLS 握手，取对端出示的叶子证书
func remoteCert(addr string, timeout time.Duration) (*x509.Certificate, error) {
	host, _, err := net.SplitHostPort(addr)
	if err != nil {
		return nil, err
	}
	d := &net.Dialer{Timeout: timeout}
	// 只读证书信息，不做信任校验，这样自签名或已过期的证书也能读出来
	conn, err := tls.DialWithDialer(d, "tcp", addr, &tls.Config{ServerName: host, InsecureSkipVerify: true})
	if err != nil {
		return nil, err
	}
	defer conn.Close()
	certs := conn.ConnectionState().PeerCertificates
	if len(certs) == 0 {
		return nil, errors.New("对端没有出示证书")
	}
	return certs[0], nil
}

// fileCert 读取 PEM 文件里的第一张证书，例如 /etc/kubernetes/pki/apiserver.crt
func fileCert(path string) (*x509.Certificate, error) {
	data, err := os.ReadFile(path)
	if err != nil {
		return nil, err
	}
	block, _ := pem.Decode(data)
	if block == nil || block.Type != "CERTIFICATE" {
		return nil, fmt.Errorf("%s 里没有 PEM 证书", path)
	}
	return x509.ParseCertificate(block.Bytes)
}

// 用法：days := int(time.Until(cert.NotAfter).Hours() / 24)
```

```bash
go build -o certcheck . && ./certcheck -warn 30 10.0.0.10:6443 /etc/kubernetes/pki/apiserver.crt
# 10.0.0.10:6443                   OK    361 天  CN=kube-apiserver  到期 2027-11-01
echo $?   # 0 正常、1 有证书快过期、2 出错：方便被 cron 或监控调用
```

**HTTP 客户端：永远设超时**

```go
client := &http.Client{Timeout: 5 * time.Second} // http.DefaultClient 没有超时，对端卡住时会一直等
req, _ := http.NewRequestWithContext(ctx, http.MethodGet, "http://10.0.0.11:8080/healthz", nil)
resp, err := client.Do(req)
if err != nil {
	return err
}
defer resp.Body.Close()
if resp.StatusCode != http.StatusOK {
	return fmt.Errorf("unhealthy: %s", resp.Status)
}
```

## 4. 考试坑点

- **`http.Get` 和 `http.DefaultClient` 没有超时**：工具里一律自己建 `http.Client{Timeout: ...}`。
- **忘了 `resp.Body.Close()`**：连接不能复用，批量请求时文件描述符会耗尽（`too many open files`）。
- **`InsecureSkipVerify: true` 只能用于「读取证书信息」**：用来发业务请求等于关掉了 TLS 的身份校验。正常调用 apiserver 时用 kubeconfig 里的 CA（G12）。
- **`http.Server` 不设 `ReadHeaderTimeout`**：慢速攻击可以占满连接，`gosec` 等扫描工具也会报警。
- **监听 `:8080` 在 RHEL 上访问不到**：先排查 firewalld，再排查 SELinux（非标准端口要 `semanage port`），就是 RHCSA 的「三道关」。
- **收到 SIGTERM 直接 `os.Exit`**：正在处理的请求会被打断，滚动更新时出现 502。用 `srv.Shutdown`。
- **证书天数取整**：`time.Until(...).Hours()/24` 向下取整，提前量要留够；证书链里第一张才是叶子证书。

## 5. 动手练习

- 第 15 周项目：[P8 certcheck](../../labs/go/projects.md#p8)：从文件读取目标列表（`host:port` 或 PEM 路径），用 G7 的 worker pool 并发检查，输出 CN、SAN、到期日和剩余天数，支持 `-json`。在 CKA 实验集群上检查 `/etc/kubernetes/pki/` 下的所有证书，和 `kubeadm certs check-expiration` 的结果对比。
- 第 17 周会把 certcheck 改成 HTTP 服务，容器化后部署到 kind 集群，用上面的 `/healthz`、`/readyz` 配置探针（G11）。

**配套 LeetCode（第 15 周，[刷题计划](../../labs/go/leetcode-plan.md#w15)）**

- [3. 无重复字符的最长子串](https://leetcode.cn/problems/longest-substring-without-repeating-characters/)：滑动窗口 + map，限流器的「窗口」思想
- [295. 数据流的中位数](https://leetcode.cn/problems/find-median-from-data-stream/)：用两个 `container/heap` 维护中位数，监控里的 P50 延迟就是它
- [703. 数据流中的第 K 大元素](https://leetcode.cn/problems/kth-largest-element-in-a-stream/)：最小堆，「最近请求里最慢的前 K 个」

## 6. 官方文档（本仓库离线版 + 本机查法）

- 离线：
  - Go by Example：[http-server](../../references/go/gobyexample/examples/http-server/http-server.go)、[http-client](../../references/go/gobyexample/examples/http-client/http-client.go)、[tcp-server](../../references/go/gobyexample/examples/tcp-server/tcp-server.go)、[url-parsing](../../references/go/gobyexample/examples/url-parsing/url-parsing.go)、[context](../../references/go/gobyexample/examples/context/context.go)、[signals](../../references/go/gobyexample/examples/signals/signals.go)
  - [官方教程：用 Gin 写 RESTful API](../../references/go/go-docs/tutorial/web-service-gin.md)（Gin 是第三方框架，看懂标准库后再看）
  - [Go 1.27 发布说明](../../references/go/go-docs/go1.27.md)（`crypto/tls`、`crypto/x509`、`net/http` 小节有最新变化）
  - 证书原理复习：[F6 TLS / PKI 基础](../00-foundations/06-tls-pki-basics.md)
- 本机：`go doc net/http.ServeMux`（路由规则写在这里）、`go doc crypto/tls.Config`、`go doc crypto/x509.Certificate`、`go doc net/netip`
- 在线：https://pkg.go.dev/net/http 、https://pkg.go.dev/crypto/tls

## 7. 自测清单

- [ ] 能写出带方法路由、`ReadHeaderTimeout` 和优雅退出的 HTTP 服务
- [ ] 能解释 liveness 和 readiness 探针为什么要分成两个接口
- [ ] 能用 `httptest` 给 handler 写测试
- [ ] 能从远端端口和本地 PEM 文件两种来源读出证书的到期时间
- [ ] 知道 `InsecureSkipVerify` 什么时候可以用、什么时候绝对不能用
