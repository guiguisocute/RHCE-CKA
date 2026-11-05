# Go-03 slice、map、struct 与指针

> **轨道**：[Go](README.md) ｜ **运维场景**：主机清单、按组归类、计数统计、去重——运维数据几乎都是这三种结构的组合 ｜ **建议用时**：3.5 h（第 3 周） ｜ **难度**：★★☆
>
> **前置**：[Go-02 基础语法与错误处理](02-basics-errors.md)
> **后续**：[Go-04 方法、接口与泛型](04-methods-interfaces-generics.md) · [Go-15 用 Go 刷 LeetCode](15-leetcode-in-go.md)
> **关联**（跨轨道）：[E2 Inventory](../rhce/02-inventory-and-config.md)（Ansible 的「组 → 主机」就是 `map[string][]Host`）

## 1. 这个知识点在网络中的位置

写运维工具时，你处理的数据通常长这样：一批主机（slice）、按组或按 IP 归类（map）、每台主机有名字/IP/标签（struct）。
这一节学会这三样，就能处理 90% 的日常数据。LeetCode 的哈希表、数组类题目也全靠它们，所以从这周开始刷题会顺手很多。

## 2. 核心概念

| 类型 | 写法 | 要点 |
|---|---|---|
| 数组 | `[3]string` | 长度是类型的一部分，很少直接用 |
| slice | `[]string`、`make([]Host, 0, 100)` | 指向底层数组的「窗口」：有 `len` 和 `cap`；`append` 可能换一块新内存 |
| map | `map[string]int`、`make(map[string][]Host)` | 遍历顺序**随机**；读不存在的 key 返回零值；用 `v, ok := m[k]` 判断是否存在 |
| 集合 | `map[string]struct{}` | Go 没有 set 类型，用空 struct 当值，不占内存 |
| struct | `type Host struct{ Name, IP string }` | 字段零值可用；可以带 tag：`json:"name"`（G5） |
| 指针 | `*Host`、`&h` | 需要修改原值，或者结构体很大时传指针；`nil` 指针解引用会 panic |

**Go 1.21+ 的 `slices` 和 `maps` 包**：`slices.Sort`、`slices.Contains`、`slices.Index`、`slices.SortFunc`；`maps.Keys` 返回迭代器（Go 1.23+），配合 `slices.Sorted(maps.Keys(m))` 得到排好序的 key。内置函数 `min`、`max`、`clear` 也是 1.21 加的。

## 3. 必会操作

```go
// 把「主机 组 IP」清单按组归类：slice + map + struct 的典型组合
package main

import (
	"fmt"
	"maps"
	"slices"
	"strings"
)

type Host struct {
	Name  string
	Group string
	IP    string
}

func main() {
	raw := `web1 web 10.0.0.11
web2 web 10.0.0.12
db1  db  10.0.0.21
web1 web 10.0.0.11`

	var hosts []Host
	seen := map[string]struct{}{} // 当集合用：struct{} 不占内存
	for _, line := range strings.Split(raw, "\n") {
		f := strings.Fields(line)
		if len(f) != 3 {
			continue
		}
		if _, dup := seen[f[0]]; dup { // comma-ok 写法判断 key 是否存在
			continue
		}
		seen[f[0]] = struct{}{}
		hosts = append(hosts, Host{Name: f[0], Group: f[1], IP: f[2]})
	}

	byGroup := map[string][]Host{}
	for _, h := range hosts {
		byGroup[h.Group] = append(byGroup[h.Group], h)
	}
	// map 的遍历顺序是随机的，输出前先排序 key（Go 1.23+ 写法）
	for _, g := range slices.Sorted(maps.Keys(byGroup)) {
		names := make([]string, 0, len(byGroup[g]))
		for _, h := range byGroup[g] {
			names = append(names, h.Name)
		}
		fmt.Printf("[%s] %s\n", g, strings.Join(names, ", "))
	}

	// 坑：切片共享底层数组
	a := []int{1, 2, 3, 4}
	b := a[:2]
	b = append(b, 99) // cap 还够，直接写进了 a[2]
	fmt.Println(a, b) // [1 2 99 4] [1 2 99]

	// 坑：range 拿到的是副本，要改原切片得用下标
	for i := range hosts {
		hosts[i].IP = strings.Replace(hosts[i].IP, "10.0.", "192.168.", 1)
	}
	fmt.Println(hosts[0].IP) // 192.168.0.11
}
```

输出：

```text
[db] db1
[web] web1, web2
[1 2 99 4] [1 2 99]
192.168.0.11
```

**运维场景示例：统计 HTTP 状态码**

```go
counts := map[string]int{}
for _, line := range lines { // lines 来自 access.log
	f := strings.Fields(line)
	if len(f) > 8 {
		counts[f[8]]++ // 不存在的 key 读出来是 0，所以直接 ++ 就行
	}
}
```

**指针：什么时候用**

```go
func disable(h *Host) { h.IP = "" }   // 要修改调用方的数据：传指针
func show(h Host) string { return h.Name } // 只读：传值就好（小结构体复制成本很低）

h := Host{Name: "web1"}
disable(&h)          // & 取地址
p := &Host{Name: "db1"} // 直接拿到指针
fmt.Println(p.Name)  // 指针访问字段不用写 (*p).Name
```

## 4. 考试坑点

- **map 未初始化就写**：`var m map[string]int; m["a"] = 1` 会 panic，要 `m := map[string]int{}` 或 `make`。读 nil map 不会 panic。
- **依赖 map 遍历顺序**：每次运行顺序都可能不同。输出报告、写测试断言前先排序。
- **切片共享底层数组**：从大切片切出小切片再 `append`，可能悄悄改掉原数据。需要独立副本时用 `slices.Clone(s)`。
- **`range` 的值是副本**：`for _, h := range hosts { h.IP = "x" }` 改不动原切片，要用 `hosts[i]`。
- **并发读写 map 会直接崩溃**：报 `fatal error: concurrent map writes`。G7 会讲用 `sync.Mutex` 保护。
- **字符串按下标取到的是 byte**：中文主机名、带 emoji 的日志要用 `for _, r := range s` 按 rune 遍历。

## 5. 动手练习

- 读 `/etc/passwd`，按登录 shell 分组统计用户数（`map[string][]string`），按 shell 名字排序输出。
- 读 `ip -o addr` 的输出，整理成 `map[网卡][]IP`。
- 后续项目：[运维小项目](../../labs/go/projects.md)（P1 logstat 会用到这里的 map 计数和排序）。

**配套 LeetCode（第 3 周，[刷题计划](../../labs/go/leetcode-plan.md#w3)）**

- [49. 字母异位词分组](https://leetcode.cn/problems/group-anagrams/)：`map[key][]string`，key 用排好序的字符串或 `[26]int` 数组（数组可以当 map 的 key，切片不行）
- [347. 前 K 个高频元素](https://leetcode.cn/problems/top-k-frequent-elements/)：先 map 计数，再排序或桶排序，和「统计攻击最多的 IP」是同一个问题
- [811. 子域名访问计数](https://leetcode.cn/problems/subdomain-visit-count/)：解析「次数 域名」并把每级子域名累加，几乎就是在分析访问日志

## 6. 官方文档（本仓库离线版 + 本机查法）

- 离线：
  - Tour of Go：[更多类型：struct、slice、map](../../references/go/tour/moretypes.article)
  - [Effective Go](../../references/go/go-docs/effective_go.html)（读 Data、Slices、Maps 三节）
  - Go by Example：[slices](../../references/go/gobyexample/examples/slices/slices.go)、[maps](../../references/go/gobyexample/examples/maps/maps.go)、[structs](../../references/go/gobyexample/examples/structs/structs.go)、[pointers](../../references/go/gobyexample/examples/pointers/pointers.go)、[sorting](../../references/go/gobyexample/examples/sorting/sorting.go)、[sorting-by-functions](../../references/go/gobyexample/examples/sorting-by-functions/sorting-by-functions.go)、[strings-and-runes](../../references/go/gobyexample/examples/strings-and-runes/strings-and-runes.go)
  - [语言规范](../../references/go/spec/go_spec.html)：Slice types、Map types、Appending and copying slices
- 本机：`go doc slices`、`go doc maps.Keys`、`go doc builtin.append`
- 在线：https://pkg.go.dev/slices 、https://go.dev/blog/slices-intro

## 7. 自测清单

- [ ] 能画出 slice 的 `len`、`cap` 和底层数组的关系，解释上面 `[1 2 99 4]` 的结果
- [ ] 能写出「判断 key 是否存在」的 comma-ok 写法
- [ ] 知道为什么报告输出前要对 map 的 key 排序
- [ ] 会用 `map[string]struct{}` 做去重
- [ ] 知道什么时候函数参数该传指针
