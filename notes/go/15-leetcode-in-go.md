# Go-15 用 Go 刷 LeetCode：常用写法与模板

> **轨道**：[Go](README.md) ｜ **运维场景**：日志 Top K、依赖排序、限流、容量规划、网络连通性——LeetCode 里的这些题型，写运维工具时都会遇到；用 Go 刷，顺便把标准库的容器包练熟 ｜ **建议用时**：3 h（第 14 周整理一遍，之后每周查阅） ｜ **难度**：★★☆
>
> **前置**：[Go-03 slice、map、struct 与指针](03-composite-types.md)
> **后续**：贯穿全程的工具笔记，没有固定的后续节点
> **关联**：[LeetCode 刷题计划](../../labs/go/leetcode-plan.md) · [本地题解目录 go/leetcode/](../../go/leetcode/README.md) · [P7 depsort](../../labs/go/projects.md#p7)（拓扑排序的实战版）

## 1. 这个知识点在网络中的位置

LeetCode 在这条轨道里的作用是练**数据结构手感**和**Go 语法速度**。Go 标准库没有现成的栈、队列、优先队列、有序集合，很多东西要自己用 slice、map、`container/heap`、`container/list` 组合出来。下面的模板全部在本机 `go test -race` 验证过（Go 1.24，`go.mod` 写 `go 1.22`）。

题型和运维场景的对应：哈希计数 / Top K = 统计 SSH 失败 IP（§3.1、§3.4）；栈 = 校验配置括号（§3.2）；BFS / 并查集 = 故障扩散、网络分区、找环路（§3.3、§3.6）；堆 = 合并 K 台机器的有序日志（§3.4）；LRU = 缓存（§3.5）；拓扑排序 = 服务启动顺序（§3.7）；二分答案 = 容量规划（§3.8）；DP = `diff`（§3.9）。

## 2. 核心概念

- **提交方式**：网页上只粘贴函数和你自定义的类型，不要带 `package`、`main`。常用标准库一般已预先导入；需要额外 import 时以编辑器能否通过为准。
- **Go 版本**：以 LeetCode 编辑器里显示的版本为准。低于 1.21 时不能用内置 `min` / `max` 和 `slices`、`maps` 包，要自己写小函数。
- **`int` 是 64 位**（LeetCode 的运行环境是 64 位），一般不用担心溢出；题目要求取模时用 `const mod = 1_000_000_007`。
- **并发题**（如 [1114. 按序打印](https://leetcode.cn/problems/print-in-order/)）不一定提供 Go 选项，以题目页为准。不支持时在本地用 channel 实现，并用 `-race` 测试（§3.10）。
- **本地流程**：`./scripts/new-leetcode.sh 146` 生成 `go/leetcode/0146-lru-cache/`，写表驱动测试，`go test` 通过再提交（见 [go/leetcode/README.md](../../go/leetcode/README.md)）。

## 3. 必会操作（模板）

### 3.1 map 当 set / 计数表，排序

```go
seen := make(map[int]int)       // 值 -> 下标（1. 两数之和）
set := map[int]struct{}{}       // set：value 用空 struct，不占空间
set[x] = struct{}{}
if _, ok := set[x]; ok { /* 存在 */ }
cnt := map[string]int{}
for _, w := range words { cnt[w]++ } // 不存在的 key 读出来是零值，可以直接 ++
slices.Sort(nums)                    // Go 1.21+；老版本：sort.Ints(nums)
sort.Slice(ps, func(i, j int) bool { // 自定义：次数降序，相同按字典序
	if ps[i].cnt != ps[j].cnt { return ps[i].cnt > ps[j].cnt }
	return ps[i].word < ps[j].word
})
b := []byte(s); slices.Sort(b); key := string(b) // 49. 字母异位词分组的 key
```

### 3.2 栈、字符串、rune（20. 有效的括号、1108. IP 地址无效化）

```go
func isValid(s string) bool {
	pair := map[rune]rune{')': '(', ']': '[', '}': '{'}
	stack := []rune{}
	for _, ch := range s { // range 字符串得到 rune（Unicode 码点）；s[i] 得到 byte
		switch ch {
		case '(', '[', '{':
			stack = append(stack, ch) // 入栈
		default:
			if len(stack) == 0 || stack[len(stack)-1] != pair[ch] { // 看栈顶
				return false
			}
			stack = stack[:len(stack)-1] // 出栈
		}
	}
	return len(stack) == 0
}
var sb strings.Builder // 拼字符串别用 +=（每次都会复制整个字符串）
sb.WriteString("1[.]")
sb.WriteByte('1')
fmt.Println(sb.String())
n, _ := strconv.Atoi("42")                   // 字符串 → 整数；反过来用 strconv.Itoa(n)
fmt.Println(n, strings.Split("1.2.10", ".")) // 165. 比较版本号：先按 . 切开
```

### 3.3 队列与 BFS（200. 岛屿数量）

```go
dirs := [4][2]int{{1, 0}, {-1, 0}, {0, 1}, {0, -1}}
queue := [][2]int{{i, j}}
grid[i][j] = '0' // 入队时就标记，避免重复入队
for len(queue) > 0 {
	cur := queue[0]
	queue = queue[1:] // slice 当队列：出队
	for _, d := range dirs {
		x, y := cur[0]+d[0], cur[1]+d[1]
		if x >= 0 && x < m && y >= 0 && y < n && grid[x][y] == '1' {
			grid[x][y] = '0'
			queue = append(queue, [2]int{x, y})
		}
	}
}
```

按层处理（102. 层序遍历、994. 腐烂的橘子）：外层循环先记下 `size := len(queue)`，内层只处理这 `size` 个。

### 3.4 堆：container/heap（347. 前 K 个高频元素、23. 合并 K 个升序链表）

```go
type pair struct{ val, cnt int }
type minHeap []pair
func (h minHeap) Len() int           { return len(h) }
func (h minHeap) Less(i, j int) bool { return h[i].cnt < h[j].cnt } // < 小顶堆，> 大顶堆
func (h minHeap) Swap(i, j int)      { h[i], h[j] = h[j], h[i] }
func (h *minHeap) Push(x any)        { *h = append(*h, x.(pair)) }
func (h *minHeap) Pop() any {
	old := *h
	x := old[len(old)-1]
	*h = old[:len(old)-1]
	return x
}
// 用法：一定要用包函数 heap.Push / heap.Pop，不要直接调 h.Push
h := &minHeap{}
for v, c := range cnt {
	heap.Push(h, pair{v, c})
	if h.Len() > k {
		heap.Pop(h) // 堆里始终保留 k 个最大的
	}
}
top := (*h)[0] // 堆顶（最小值），不弹出
```

### 3.5 LRU：container/list + map（146. LRU 缓存）

```go
type entry struct{ key, val int }
type LRUCache struct {
	cap   int
	ll    *list.List            // 前面 = 最近使用
	items map[int]*list.Element
}
func Constructor(capacity int) LRUCache {
	return LRUCache{cap: capacity, ll: list.New(), items: map[int]*list.Element{}}
}
func (c *LRUCache) Get(key int) int {
	if e, ok := c.items[key]; ok {
		c.ll.MoveToFront(e)
		return e.Value.(*entry).val
	}
	return -1
}
func (c *LRUCache) Put(key, value int) {
	if e, ok := c.items[key]; ok {
		e.Value.(*entry).val = value
		c.ll.MoveToFront(e)
		return
	}
	c.items[key] = c.ll.PushFront(&entry{key, value})
	if c.ll.Len() > c.cap {
		last := c.ll.Back()
		c.ll.Remove(last)
		delete(c.items, last.Value.(*entry).key)
	}
}
```

### 3.6 并查集（547. 省份数量、684. 冗余连接）

```go
type UnionFind struct{ parent, rank []int }
func NewUnionFind(n int) *UnionFind {
	uf := &UnionFind{parent: make([]int, n), rank: make([]int, n)}
	for i := range uf.parent { uf.parent[i] = i }
	return uf
}
func (uf *UnionFind) Find(x int) int {
	for uf.parent[x] != x {
		uf.parent[x] = uf.parent[uf.parent[x]] // 路径压缩
		x = uf.parent[x]
	}
	return x
}
// Union 返回 false 表示两点早已连通：再连这条边就成环了（684 的答案）
func (uf *UnionFind) Union(a, b int) bool {
	ra, rb := uf.Find(a), uf.Find(b)
	if ra == rb { return false }
	if uf.rank[ra] < uf.rank[rb] { ra, rb = rb, ra }
	uf.parent[rb] = ra
	if uf.rank[ra] == uf.rank[rb] { uf.rank[ra]++ }
	return true
}
```

### 3.7 拓扑排序 Kahn（207 / 210. 课程表 = 服务启动顺序）

```go
indeg, next := make([]int, n), make([][]int, n)
for _, p := range prerequisites { // [a, b]：b 先于 a
	next[p[1]] = append(next[p[1]], p[0])
	indeg[p[0]]++
}
queue, order := []int{}, []int{}
for i, d := range indeg { if d == 0 { queue = append(queue, i) } }
for len(queue) > 0 {
	u := queue[0]; queue = queue[1:]
	order = append(order, u)
	for _, v := range next[u] {
		if indeg[v]--; indeg[v] == 0 { queue = append(queue, v) }
	}
}
hasCycle := len(order) < n // 有环 = 依赖死锁，systemd 也会报 ordering cycle
```

### 3.8 二分：查找与「在答案上二分」（704、875、1011）

```go
lo, hi := 0, len(nums) // 左闭右开：返回第一个 >= target 的位置
for lo < hi {
	mid := lo + (hi-lo)/2
	if nums[mid] < target { lo = mid + 1 } else { hi = mid }
}
lo, hi = 1, slices.Max(piles) // 875：找「能完成」的最小速度
for lo < hi {
	mid := lo + (hi-lo)/2
	if canFinish(mid) { hi = mid } else { lo = mid + 1 }
}
```

### 3.9 记忆化递归（1143. 最长公共子序列：`diff` 的核心）

```go
memo := make([][]int, len(a)) // 每格初始化为 -1，表示还没算过
var dfs func(i, j int) int    // 递归闭包：先声明，再赋值
dfs = func(i, j int) int {
	if i == len(a) || j == len(b) { return 0 }
	if memo[i][j] >= 0 { return memo[i][j] }
	r := max(dfs(i+1, j), dfs(i, j+1)) // Go 1.21+ 内置 max
	if a[i] == b[j] { r = 1 + dfs(i+1, j+1) }
	memo[i][j] = r
	return r
}
```

### 3.10 并发题本地版（1114. 按序打印）

两个 `chan struct{}`：`First` 打印后 `close(firstDone)`，`Second` 先 `<-firstDone` 再打印并 `close(secondDone)`，`Third` 等 `secondDone`。`close` 会唤醒所有等待者，而且只能关一次。测试里乱序启动三个 goroutine 跑 100 轮，加 `-race`。channel 的用法见 [G7](07-concurrency-context.md)。

## 4. 考试坑点

- `heap.Push(h, x)` 和 `h.Push(x)` 不一样：后者只是 append，不会调整堆。
- `queue = queue[1:]` 出队不会释放底层数组，超大 BFS 可以改用环形队列或定期复制；刷题一般无所谓。
- `for i, v := range slice` 里的 `v` 是副本，改 `v` 不会改原切片；要改就用 `slice[i]`。
- `map` 遍历顺序是随机的，需要稳定输出就先把 key 排序。
- 递归闭包必须先 `var dfs func(...)` 再赋值，否则闭包里引用不到自己。
- 二维切片 `make([][]int, m)` 只建了外层，每一行还要再 `make`。

## 5. 动手练习

- 把本节每个模板在 `go/leetcode/` 下对应的题目里实现一遍，并写表驱动测试。
- 项目：[P7 depsort](../../labs/go/projects.md#p7)（第 14 周）把 §3.7 用在真实的服务依赖文件上，环要报出具体路径。

**配套 LeetCode（第 14 周，[刷题计划](../../labs/go/leetcode-plan.md#w14)）**

- [207. 课程表](https://leetcode.cn/problems/course-schedule/)：判断依赖图有没有环
- [210. 课程表 II](https://leetcode.cn/problems/course-schedule-ii/)：给出一个合法的启动顺序
- [621. 任务调度器](https://leetcode.cn/problems/task-scheduler/)：同类任务之间要冷却时间，≈ 同一台机器两次重启之间要间隔

## 6. 官方文档（本仓库离线版 + 本机查法）

- 本机：`go doc container/heap`（包文档里就有一个完整的优先队列示例）、`go doc container/list`、`go doc slices`、`go doc sort.Slice`、`go doc strings.Builder`
- Go by Example：[sorting-by-functions.go](../../references/go/gobyexample/examples/sorting-by-functions/sorting-by-functions.go)
- 泛型（写通用的 `Set[T]`、`Max[T]`）：[generics.md](../../references/go/go-docs/tutorial/generics.md)
- 语言规范里关于 range 和切片的部分：[go_spec.html](../../references/go/spec/go_spec.html)
- 题目信息（题号、中英文名、slug、难度、是否会员题）：[leetcode-problems.tsv](../../labs/go/leetcode-problems.tsv)

## 7. 自测清单

- [ ] 不看资料写出 `container/heap` 的五个方法，并说出 `Less` 里用 `<` 还是 `>` 决定大小顶堆
- [ ] 不看资料写出 LRU 缓存，并说出为什么要在链表节点里同时存 key
- [ ] 能写出并查集，并用它判断「加上这条链路会不会成环」
- [ ] 能用 Kahn 算法输出依赖顺序，并检测出环
- [ ] 能用「在答案上二分」解 875 和 1011，并说出单调性在哪里
- [ ] 每道题都先在本地 `go test` 通过再提交
