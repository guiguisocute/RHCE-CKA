# go/：Go 轨道的代码

这里是一个 Go module，放你自己写的 LeetCode 题解和运维小工具。学习路线和知识点见 [`notes/go/`](../notes/go/README.md)。

- module 路径：`github.com/guiguisocute/RHCE-CKA/go`（见 [`go.mod`](go.mod)）
- `go` 指令写的是 `go 1.24`，表示最低版本。用更新的 Go（例如 1.27）编译也没问题。等你在 `tools/` 里引入 client-go、controller-runtime 这类新版依赖时，`go get` 会自动把这一行抬到 `go 1.26`，这是正常现象；本机 Go 低于 1.26 时会按 `GOTOOLCHAIN` 设置自动下载新工具链，所以建议直接装最新稳定版。

## 目录

```text
go/
├── go.mod
├── leetcode/          # LeetCode 题解：每题一个目录，solution.go + solution_test.go
│   └── README.md      #   命名规则、生成脚本、刷题计划入口
└── tools/             # 运维小项目 P1~P11
    ├── README.md      #   进度清单
    └── template/      #   可复制的 CLI 骨架（只用标准库，带测试）
```

- `leetcode/`：配合 [LeetCode 刷题计划](../labs/go/leetcode-plan.md)。目录命名和新建题目的方法见 [`leetcode/README.md`](leetcode/README.md)。
- `tools/`：配合 [11 个运维小项目](../labs/go/projects.md)。每个项目一个子目录，从 [`tools/template/`](tools/template/) 复制起步。

## 常用命令

都在 `go/` 目录下执行：

```bash
cd go
```

```bash
go test ./...
```

```bash
go vet ./...
```

```bash
gofmt -l .
```

```bash
go test -race ./tools/...
```

```bash
go test -run TestTwoSum -v ./leetcode/...
```

- `gofmt -l .` 没有输出才算格式正确；`gofmt -w .` 直接改写。
- `go test ./...` 会跳过以 `_` 或 `.` 开头的目录，也会跳过带自己 `go.mod` 的子目录（比如 P11 用 kubebuilder 生成的 operator 项目）。这类项目要进对应目录里单独测试。

## 国内网络：设置模块代理

`go get` 默认访问 `proxy.golang.org` 和 `sum.golang.org`，国内经常连不上。设置一次即可（写入 `go env` 配置文件，永久生效）：

```bash
go env -w GOPROXY=https://goproxy.cn,direct
```

```bash
go env -w GOSUMDB=sum.golang.google.cn
```

备选代理：`https://mirrors.aliyun.com/goproxy/`。查看当前设置：`go env GOPROXY GOSUMDB`。

## 第三方依赖（用到时再加）

前 4 个项目只用标准库。之后需要的依赖如下，在 `go/` 目录下 `go get` 即可，`go.mod` 和 `go.sum` 会自动更新：

| 项目 | 依赖 | 命令 |
|---|---|---|
| P5 tmplgen、P7 depsort | YAML 解析 | `go get go.yaml.in/yaml/v3@latest`（或 `sigs.k8s.io/yaml`） |
| P4、P6 | 限并发的 errgroup（可选） | `go get golang.org/x/sync@latest` |
| P6 gossh | SSH 客户端 | `go get golang.org/x/crypto@latest` |
| P9 kpods | Kubernetes 客户端 | `go get k8s.io/client-go@v0.37.2 k8s.io/apimachinery@v0.37.2` |
| P10 cert-exporter | Prometheus 客户端 | `go get github.com/prometheus/client_golang@latest` |
| P11 operator | kubebuilder 生成独立项目 | 见 [P11](../labs/go/projects.md#p11) |

`gopkg.in/yaml.v3` 已经停止维护，新代码建议用 YAML 组织维护的 `go.yaml.in/yaml/v3`。`k8s.io/client-go` 的 `v0.X.Y` 对应 Kubernetes `1.X.Y`，版本尽量和集群一致。上表的版本号是 2026-11 查到的，以 `go list -m -versions <模块>` 的结果为准。
