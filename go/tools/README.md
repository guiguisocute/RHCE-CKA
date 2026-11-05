# tools/：运维小项目

每个项目一个子目录，目录名就是工具名，都属于同一个 module `github.com/guiguisocute/RHCE-CKA/go`。需求和验收标准见 [labs/go/projects.md](../../labs/go/projects.md)。

## 目录约定

```text
tools/
├── template/        # 骨架，复制它起步
├── logstat/         # P1
│   ├── main.go      #   接线：flag、信号、退出码
│   ├── parse.go     #   业务逻辑（输入用 io.Reader，便于测试）
│   ├── parse_test.go
│   ├── testdata/    #   测试用的样例文件（go 工具会自动忽略这个目录名）
│   └── README.md    #   用法、示例输出、退出码
└── ...
```

- 新建项目：`cp -r tools/template tools/<名字>`，步骤见 [template/README.md](template/README.md)。
- 测试样例放 `testdata/`，比如截取一段脱敏后的 `/var/log/secure`、一份写错的 `fstab`。
- 编译产物放 `go/bin/`，不提交（已在 `go/.gitignore` 里忽略）。
- P11 operator 由 kubebuilder 生成，有自己的 `go.mod`，是独立的 module。

## 进度

- [ ] P1 [logstat：统计 SSH 登录失败](../../labs/go/projects.md#p1)（W5）
- [ ] P2 [fstab-lint：检查 /etc/fstab](../../labs/go/projects.md#p2)（W6）
- [ ] P3 [svcwatch：批量检查 systemd 服务](../../labs/go/projects.md#p3)（W7）
- [ ] P4 [portcheck：并发端口探测](../../labs/go/projects.md#p4)（W9）
- [ ] P5 [tmplgen：模板生成配置，幂等写入](../../labs/go/projects.md#p5)（W12）
- [ ] P6 [gossh：并行 SSH 执行器](../../labs/go/projects.md#p6)（W13）
- [ ] P7 [depsort：服务依赖拓扑排序](../../labs/go/projects.md#p7)（W14）
- [ ] P8 [certcheck：证书过期检查](../../labs/go/projects.md#p8)（W15）
- [ ] P9 [kpods：找出不健康的 Pod](../../labs/go/projects.md#p9)（W18~W19）
- [ ] P10 [cert-exporter：证书过期 exporter](../../labs/go/projects.md#p10)（W20）
- [ ] P11 [operator：StaticSite CRD + controller](../../labs/go/projects.md#p11)（W22）
