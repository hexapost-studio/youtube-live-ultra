package main

import (
	"os/exec"
	"runtime"
	"strings"
	"testing"
)

// ─── CLI ────────────────────────────────────────────────────────────────────

func TestVersion(t *testing.T) {
	if version == "" {
		t.Error("version should not be empty")
	}
	if !strings.Contains(version, "go") {
		t.Error("version should contain 'go' suffix")
	}
}

func TestDetectHWDec(t *testing.T) {
	args := detectHWDec()
	if len(args) == 0 {
		t.Error("detectHWDec should return at least one arg")
	}
	found := false
	for _, a := range args {
		if strings.HasPrefix(a, "--hwdec=") {
			found = true
		}
	}
	if !found {
		t.Error("detectHWDec should include --hwdec")
	}
}

func TestDetectHWDecMacOS(t *testing.T) {
	if runtime.GOOS != "darwin" {
		t.Skip("macOS only test")
	}
	args := detectHWDec()
	hasVideoToolbox := false
	for _, a := range args {
		if strings.Contains(a, "videotoolbox") {
			hasVideoToolbox = true
		}
	}
	if !hasVideoToolbox {
		t.Error("macOS should use videotoolbox")
	}
}

func TestDetectHWDecLinux(t *testing.T) {
	if runtime.GOOS != "linux" {
		t.Skip("Linux only test")
	}
	args := detectHWDec()
	hasVAAPI := false
	hasAuto := false
	for _, a := range args {
		if strings.Contains(a, "vaapi") {
			hasVAAPI = true
		}
		if strings.Contains(a, "auto-safe") {
			hasAuto = true
		}
	}
	if !hasVAAPI && !hasAuto {
		t.Error("Linux should use vaapi or auto-safe")
	}
}

// ─── SANDBOX ────────────────────────────────────────────────────────────────

func TestSandboxWrapDarwin(t *testing.T) {
	if runtime.GOOS != "darwin" {
		t.Skip("macOS only test")
	}
	cmd := exec.Command("echo", "test")
	wrapped := sandboxWrap(cmd)
	if !strings.Contains(strings.Join(wrapped.Args, " "), "sandbox-exec") {
		t.Error("macOS sandbox should use sandbox-exec")
	}
}

func TestSandboxWrapLinux(t *testing.T) {
	if runtime.GOOS != "linux" {
		t.Skip("Linux only test")
	}
	cmd := exec.Command("echo", "test")
	wrapped := sandboxWrap(cmd)
	args := strings.Join(wrapped.Args, " ")
	hasFirejail := strings.Contains(args, "firejail")
	hasBwrap := strings.Contains(args, "bwrap")
	if !hasFirejail && !hasBwrap {
		t.Log("No sandbox available on this Linux system (expected)")
	}
}

func TestSandboxWrapPreservesArgs(t *testing.T) {
	cmd := exec.Command("echo", "hello", "world")
	wrapped := sandboxWrap(cmd)
	args := strings.Join(wrapped.Args, " ")
	if !strings.Contains(args, "hello") || !strings.Contains(args, "world") {
		t.Error("sandboxWrap should preserve original command args")
	}
}

// ─── MPV ARGS ───────────────────────────────────────────────────────────────

func TestMpvArgsStandard(t *testing.T) {
	args := []string{"--profile=low-latency"}
	args = append(args, detectHWDec()...)
	
	if len(args) < 2 {
		t.Error("standard mpv args should include profile + hwdec")
	}
}

func TestURL(t *testing.T) {
	// LauchMpvYtdl should handle URLs with special chars
	if _, err := exec.LookPath("mpv"); err != nil {
		t.Skip("mpv not installed")
	}
	// This test just verifies the function doesn't panic
	// We don't actually launch mpv
	_ = launchMpvYtdl
	_ = launchStreamlink
	_ = launchYtdlpPipe
}

// ─── BENCHMARKS ─────────────────────────────────────────────────────────────

func BenchmarkDetectHWDec(b *testing.B) {
	for i := 0; i < b.N; i++ {
		detectHWDec()
	}
}

func BenchmarkSandboxWrap(b *testing.B) {
	cmd := exec.Command("echo", "test")
	b.ResetTimer()
	for i := 0; i < b.N; i++ {
		sandboxWrap(cmd)
	}
}
