package p0001

import (
	"slices"
	"testing"
)

// 表驱动测试：每一行是一个用例，新增用例只需加一行。
// 运行：cd go && go test ./leetcode/0001-two-sum/ -v
func TestTwoSum(t *testing.T) {
	tests := []struct {
		name   string
		nums   []int
		target int
		want   []int
	}{
		{name: "示例 1", nums: []int{2, 7, 11, 15}, target: 9, want: []int{0, 1}},
		{name: "示例 2", nums: []int{3, 2, 4}, target: 6, want: []int{1, 2}},
		{name: "示例 3：两个相同的值", nums: []int{3, 3}, target: 6, want: []int{0, 1}},
		{name: "不能把同一个元素用两次", nums: []int{3, 5, 1}, target: 6, want: []int{1, 2}},
		{name: "负数", nums: []int{-3, 4, 3, 90}, target: 0, want: []int{0, 2}},
		{name: "值为 0", nums: []int{0, 4, 3, 0}, target: 0, want: []int{0, 3}},
		{name: "答案在末尾", nums: []int{1, 2, 3, 4, 5}, target: 9, want: []int{3, 4}},
		{name: "无解", nums: []int{1, 2}, target: 7, want: nil},
		{name: "空输入", nums: nil, target: 1, want: nil},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got := twoSum(tt.nums, tt.target)
			if !slices.Equal(got, tt.want) {
				t.Errorf("twoSum(%v, %d) = %v, want %v", tt.nums, tt.target, got, tt.want)
			}
		})
	}
}

// 基准测试：go test -bench=. -benchmem ./leetcode/0001-two-sum/
func BenchmarkTwoSum(b *testing.B) {
	nums := make([]int, 10000)
	for i := range nums {
		nums[i] = i
	}
	target := nums[len(nums)-2] + nums[len(nums)-1] // 最坏情况：答案在最后
	for b.Loop() {                                  // Go 1.24 起的写法；更早的版本用 for i := 0; i < b.N; i++
		twoSum(nums, target)
	}
}
