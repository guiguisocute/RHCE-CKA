package main

import (
	"bytes"
	"context"
	"errors"
	"flag"
	"fmt"
	"strings"
	"testing"
)

// 表驱动测试：每一行是一个用例，循环里用 t.Run 跑子测试。
// 新增场景只需要在表里加一行。
func TestRun(t *testing.T) {
	tests := []struct {
		name       string
		args       []string
		wantOut    string
		wantErrOut string // stderr 里应包含的片段，空表示不检查
		wantCode   int
	}{
		{name: "默认参数", args: nil, wantOut: "hello, world\n", wantCode: exitOK},
		{name: "指定名字", args: []string{"-name", "ops"}, wantOut: "hello, ops\n", wantCode: exitOK},
		{name: "JSON 输出", args: []string{"-name", "ops", "-json"}, wantOut: `{"message":"hello, ops"}` + "\n", wantCode: exitOK},
		{name: "帮助", args: []string{"-h"}, wantErrOut: "用法", wantCode: exitOK},
		{name: "名字为空", args: []string{"-name", "  "}, wantErrOut: "不能为空", wantCode: exitUsage},
		{name: "未知参数", args: []string{"-nope"}, wantErrOut: "flag provided but not defined", wantCode: exitUsage},
		{name: "超时非法", args: []string{"-timeout", "0s"}, wantErrOut: "必须大于 0", wantCode: exitUsage},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			var stdout, stderr bytes.Buffer
			err := run(context.Background(), tt.args, &stdout, &stderr)
			if got := exitCode(err, &stderr); got != tt.wantCode {
				t.Fatalf("退出码 = %d，期望 %d（err=%v）", got, tt.wantCode, err)
			}
			if tt.wantOut != "" && stdout.String() != tt.wantOut {
				t.Errorf("stdout = %q，期望 %q", stdout.String(), tt.wantOut)
			}
			if tt.wantErrOut != "" && !strings.Contains(stderr.String(), tt.wantErrOut) {
				t.Errorf("stderr = %q，应包含 %q", stderr.String(), tt.wantErrOut)
			}
		})
	}
}

func TestExitCode(t *testing.T) {
	tests := []struct {
		name string
		err  error
		want int
	}{
		{"成功", nil, exitOK},
		{"帮助", flag.ErrHelp, exitOK},
		{"参数错误", usageError{errors.New("bad flag")}, exitUsage},
		{"发现问题（被包装过）", fmt.Errorf("fstab: %w", errFindings), exitFindings},
		{"运行错误", errors.New("disk on fire"), exitError},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			var stderr bytes.Buffer
			if got := exitCode(tt.err, &stderr); got != tt.want {
				t.Errorf("exitCode(%v) = %d，期望 %d", tt.err, got, tt.want)
			}
		})
	}
}

func TestGreetHonorsCancel(t *testing.T) {
	ctx, cancel := context.WithCancel(context.Background())
	cancel()
	if _, err := greet(ctx, "ops"); !errors.Is(err, context.Canceled) {
		t.Fatalf("取消后的 ctx 应返回 context.Canceled，实际 %v", err)
	}
}
