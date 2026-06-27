//go:build windows

package main

import (
	"fmt"
	"io"
	"os"
	"time"
)

// shutdownSignals: Windows reliably delivers only os.Interrupt (Ctrl-C).
var shutdownSignals = []os.Signal{os.Interrupt}

// ipcPath returns the named-pipe path mpv exposes via --input-ipc-server on Windows.
func ipcPath(tag string) string {
	return fmt.Sprintf(`\\.\pipe\mpv-%s-%d`, tag, os.Getpid())
}

// dialIPC opens mpv's IPC named pipe. mpv creates a byte-mode pipe that can be
// driven as a regular file handle, so no third-party named-pipe library is
// needed. The timeout is advisory: opening returns immediately if the pipe is
// not yet available, and the caller retries.
func dialIPC(ipc string, _ time.Duration) (io.ReadWriteCloser, error) {
	return os.OpenFile(ipc, os.O_RDWR, 0)
}
