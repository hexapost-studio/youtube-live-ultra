//go:build !windows

package main

import (
	"fmt"
	"io"
	"net"
	"os"
	"path/filepath"
	"syscall"
	"time"
)

// shutdownSignals are the OS signals that trigger a graceful shutdown.
var shutdownSignals = []os.Signal{os.Interrupt, syscall.SIGTERM}

// ipcPath returns the Unix-socket path mpv exposes via --input-ipc-server.
func ipcPath(tag string) string {
	return filepath.Join(os.TempDir(), fmt.Sprintf("mpv-%s-%d.sock", tag, os.Getpid()))
}

// dialIPC connects to mpv's IPC Unix socket. A zero timeout blocks.
func dialIPC(ipc string, timeout time.Duration) (io.ReadWriteCloser, error) {
	if timeout > 0 {
		return net.DialTimeout("unix", ipc, timeout)
	}
	return net.Dial("unix", ipc)
}
