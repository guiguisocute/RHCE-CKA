#!/usr/bin/env bash
# 生成一道 LeetCode 题的 Go 刷题骨架：go/leetcode/NNNN-slug/{solution.go,solution_test.go}
#
# 用法：
#   ./scripts/new-leetcode.sh 146
#   ./scripts/new-leetcode.sh 2000 --slug reverse-prefix-of-word --title "Reverse Prefix of Word" \
#       [--title-zh "反转单词前缀"] [--difficulty Easy|Medium|Hard]
#
# 题号会先在 labs/go/leetcode-problems.tsv 里查（已核对的题目元数据）；
# 不在表里的题，用 --slug 和 --title 手动指定。目录已存在时不会覆盖。
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TSV="${ROOT}/labs/go/leetcode-problems.tsv"

usage() {
  sed -n '2,10p' "$0" | sed 's/^# \{0,1\}//'
  exit "${1:-0}"
}

[ $# -ge 1 ] || usage 1
case "$1" in -h|--help) usage 0 ;; esac

id_raw="$1"; shift
if ! [[ "$id_raw" =~ ^[0-9]+$ ]]; then
  echo "题号必须是数字：${id_raw}" >&2
  exit 1
fi
id=$((10#$id_raw))

slug="" title="" title_zh="" difficulty="" premium="F"
while [ $# -gt 0 ]; do
  case "$1" in
    --slug) slug="${2:?--slug 需要一个值}"; shift 2 ;;
    --title) title="${2:?--title 需要一个值}"; shift 2 ;;
    --title-zh) title_zh="${2:?--title-zh 需要一个值}"; shift 2 ;;
    --difficulty) difficulty="${2:?--difficulty 需要一个值}"; shift 2 ;;
    -h|--help) usage 0 ;;
    *) echo "未知参数：$1" >&2; usage 1 ;;
  esac
done

if [ -z "$slug" ]; then
  line="$(awk -F'\t' -v id="$id" 'NR > 1 && $1 == id { print; exit }' "$TSV")"
  if [ -z "$line" ]; then
    echo "题号 ${id} 不在 ${TSV#"${ROOT}/"} 里。请手动指定，例如：" >&2
    echo "  $0 ${id} --slug two-sum --title \"Two Sum\" --title-zh \"两数之和\" --difficulty Easy" >&2
    exit 1
  fi
  IFS=$'\t' read -r _ title title_zh slug difficulty premium <<<"$line"
fi

if ! [[ "$slug" =~ ^[a-z0-9]+(-[a-z0-9]+)*$ ]]; then
  echo "slug 只能包含小写字母、数字和连字符：${slug}" >&2
  exit 1
fi
[ -n "$title" ] || title="$slug"

case "$difficulty" in
  Easy) diff_zh="简单（Easy）" ;;
  Medium) diff_zh="中等（Medium）" ;;
  Hard) diff_zh="困难（Hard）" ;;
  "") diff_zh="未填写" ;;
  *) echo "--difficulty 只能是 Easy、Medium 或 Hard：${difficulty}" >&2; exit 1 ;;
esac
[ "$premium" = "P" ] && diff_zh="${diff_zh} · 会员题"

num4="$(printf '%04d' "$id")"
pkg="p${num4}"
rel="go/leetcode/${num4}-${slug}"
dir="${ROOT}/${rel}"
name="${id}. ${title_zh:+${title_zh}（}${title}${title_zh:+）}"

if [ -e "$dir" ]; then
  echo "已存在：${rel}（不会覆盖）" >&2
  exit 1
fi
mkdir -p "$dir"

cat > "${dir}/solution.go" <<EOF
// Package ${pkg}：LeetCode ${name}
//
// 难度：${diff_zh}
// 链接：https://leetcode.cn/problems/${slug}/
//
//	https://leetcode.com/problems/${slug}/
//
// 提交时只复制函数（设计题复制类型和方法），不要复制 package 这一行。
// 链表 / 二叉树题：LeetCode 已经定义了 ListNode / TreeNode，本地需要自己在 types.go 里定义，但不要提交它。
package ${pkg}

// TODO：把 LeetCode 上的函数签名粘贴到这里，再写出解法。
//
// 思路：
//
// 复杂度：时间 O(?)，空间 O(?)
EOF

cat > "${dir}/solution_test.go" <<EOF
package ${pkg}

import "testing"

// 运行：cd go && go test ./leetcode/${num4}-${slug}/ -v
func TestSolution(t *testing.T) {
	t.Skip("TODO：写完 solution.go 后删掉这一行，并补全下面的用例")

	tests := []struct {
		name string
		// 输入字段，例如：nums []int
		// 期望输出，例如：want int
	}{
		{name: "示例 1"},
		{name: "示例 2"},
		{name: "边界：空输入 / 单个元素"},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			// got := 函数名(tt.输入)
			// if got != tt.want {
			// 	t.Errorf("got %v, want %v", got, tt.want)
			// }
		})
	}
}
EOF

echo "已生成 ${rel}/"
echo "  solution.go       写解法"
echo "  solution_test.go  写表驱动测试（先删掉 t.Skip）"
echo "运行测试：cd go && go test ./leetcode/${num4}-${slug}/ -v"
