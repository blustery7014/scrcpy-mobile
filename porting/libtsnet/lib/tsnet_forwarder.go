package libtsnet_forwarder

import (
	"context"
	"fmt"
	"io"
	"log"
	"net"
	"os"
	"sync"
	"time"

	"tailscale.com/tsnet"
)

// ForwardCallback defines the forwarding status callback interface
type ForwardCallback struct {
	OnForwardSuccess func(remoteAddr string, remotePort int, localPort int)
	OnForwardClosed  func(remoteAddr string, remotePort int, localPort int)
	OnForwardError   func(remoteAddr string, remotePort int, localPort int, err error)
}

// ForwardInfo stores forwarding information
type ForwardInfo struct {
	RemoteAddr string
	RemotePort int
	LocalPort  int
	Listener   net.Listener
	Cancel     context.CancelFunc
}

// TSNetForwarder tsnet forwarder
type TSNetForwarder struct {
	server    *tsnet.Server
	authKey   string
	hostname  string
	forwards  map[string]*ForwardInfo
	callback  *ForwardCallback
	mutex     sync.RWMutex
	isStarted bool
}

var globalForwarder *TSNetForwarder
var initOnce sync.Once

// GetInstance gets the global singleton
func GetInstance() *TSNetForwarder {
	initOnce.Do(func() {
		globalForwarder = &TSNetForwarder{
			forwards: make(map[string]*ForwardInfo),
		}
	})
	return globalForwarder
}

// UpdateTsnetAuthKey sets the tsnet authentication key
func (f *TSNetForwarder) UpdateTsnetAuthKey(authKey string) error {
	f.mutex.Lock()
	defer f.mutex.Unlock()

	f.authKey = authKey

	// If the server is already started, need to reinitialize
	if f.isStarted {
		f.stopServer()
		return f.startServer()
	}
	return nil
}

// TsnetUpdateHostname sets the tsnet client hostname
func (f *TSNetForwarder) TsnetUpdateHostname(hostname string) error {
	f.mutex.Lock()
	defer f.mutex.Unlock()

	f.hostname = hostname

	// If the server is already started, need to reinitialize to use the new hostname
	if f.isStarted {
		f.stopServer()
		return f.startServer()
	}
	return nil
}

// getHostname gets the hostname to use, if not set, use the local hostname
func (f *TSNetForwarder) getHostname() string {
	if f.hostname != "" {
		return f.hostname
	}

	// Try to get the local hostname
	if hostname, err := os.Hostname(); err == nil && hostname != "" {
		return hostname
	}

	// If failed to get, use default value
	return "scrcpy-tsnet-forwarder"
}

// startServer starts the tsnet server
func (f *TSNetForwarder) startServer() error {
	if f.isStarted {
		return nil
	}

	tsnetData := "/tmp/tsnet-forwarder"

	// Clean up old tsnet data
	if _, err := os.Stat(tsnetData); !os.IsNotExist(err) {
		_ = os.RemoveAll(tsnetData)
	}

	hostname := f.getHostname()
	f.server = &tsnet.Server{
		Dir:      tsnetData,
		Hostname: hostname,
		AuthKey:  f.authKey,
	}

	if err := f.server.Start(); err != nil {
		return fmt.Errorf("failed to start tsnet server: %v", err)
	}

	ctx, cancel := context.WithTimeout(context.Background(), 60*time.Second)
	defer cancel()

	_, err := f.server.Up(ctx)
	if err != nil {
		f.server.Close()
		return fmt.Errorf("failed to bring up tsnet server: %v", err)
	}

	f.isStarted = true
	ip4, ip6 := f.server.TailscaleIPs()
	log.Printf("TSNet server started with hostname '%s' and IPs: %v, %v", hostname, ip4, ip6)
	return nil
}

// stopServer stops the tsnet server
func (f *TSNetForwarder) stopServer() {
	if f.server != nil {
		f.server.Close()
		f.server = nil
	}
	f.isStarted = false
}

// TsnetStartForward starts port forwarding
func (f *TSNetForwarder) TsnetStartForward(remoteAddr string, remotePort int, localPort int) error {
	f.mutex.Lock()
	defer f.mutex.Unlock()

	// Ensure the server is started
	if err := f.startServer(); err != nil {
		log.Printf("Failed to start server: %v", err)
		if f.callback != nil && f.callback.OnForwardError != nil {
			f.callback.OnForwardError(remoteAddr, remotePort, localPort, err)
		}
		return err
	}

	// Generate unique key
	key := fmt.Sprintf("%s:%d->%d", remoteAddr, remotePort, localPort)

	// Check if already exists
	if _, exists := f.forwards[key]; exists {
		log.Printf("Forward already exists: %s", key)
		return nil
	}

	// Create local listener
	listener, err := net.Listen("tcp", fmt.Sprintf(":%d", localPort))
	if err != nil {
		log.Printf("Failed to create listener on port %d: %v", localPort, err)
		if f.callback != nil && f.callback.OnForwardError != nil {
			f.callback.OnForwardError(remoteAddr, remotePort, localPort, err)
		}
		return err
	}

	// Create context for cancellation
	ctx, cancel := context.WithCancel(context.Background())

	// Store forwarding information
	forwardInfo := &ForwardInfo{
		RemoteAddr: remoteAddr,
		RemotePort: remotePort,
		LocalPort:  localPort,
		Listener:   listener,
		Cancel:     cancel,
	}
	f.forwards[key] = forwardInfo

	// Start forwarding goroutine
	go f.handleForward(ctx, forwardInfo)

	log.Printf("Started forward: %s", key)
	if f.callback != nil && f.callback.OnForwardSuccess != nil {
		f.callback.OnForwardSuccess(remoteAddr, remotePort, localPort)
	}

	return nil
}

// handleForward handles port forwarding
func (f *TSNetForwarder) handleForward(ctx context.Context, info *ForwardInfo) {
	defer func() {
		info.Listener.Close()
		f.mutex.Lock()
		key := fmt.Sprintf("%s:%d->%d", info.RemoteAddr, info.RemotePort, info.LocalPort)
		delete(f.forwards, key)
		f.mutex.Unlock()

		if f.callback != nil && f.callback.OnForwardClosed != nil {
			f.callback.OnForwardClosed(info.RemoteAddr, info.RemotePort, info.LocalPort)
		}
	}()

	for {
		select {
		case <-ctx.Done():
			return
		default:
			// Accept local connection
			localConn, err := info.Listener.Accept()
			if err != nil {
				if f.callback != nil && f.callback.OnForwardError != nil {
					f.callback.OnForwardError(info.RemoteAddr, info.RemotePort, info.LocalPort, err)
				}
				return
			}

			// Handle connection
			go f.handleConnection(ctx, localConn, info)
		}
	}
}

// handleConnection handles a single connection
func (f *TSNetForwarder) handleConnection(ctx context.Context, localConn net.Conn, info *ForwardInfo) {
	defer localConn.Close()

	// Connect to remote address through tsnet
	remoteAddr := fmt.Sprintf("%s:%d", info.RemoteAddr, info.RemotePort)
	remoteConn, err := f.server.Dial(ctx, "tcp", remoteAddr)
	if err != nil {
		log.Printf("Failed to connect to remote %s: %v", remoteAddr, err)
		if f.callback != nil && f.callback.OnForwardError != nil {
			f.callback.OnForwardError(info.RemoteAddr, info.RemotePort, info.LocalPort, err)
		}
		return
	}
	defer remoteConn.Close()

	// Bidirectional data forwarding
	done := make(chan struct{}, 2)

	// Local to remote
	go func() {
		defer func() { done <- struct{}{} }()
		io.Copy(remoteConn, localConn)
	}()

	// Remote to local
	go func() {
		defer func() { done <- struct{}{} }()
		io.Copy(localConn, remoteConn)
	}()

	// Wait for either direction to complete or context cancellation
	select {
	case <-done:
	case <-ctx.Done():
	}
}

// TsnetStopForward stops port forwarding
func (f *TSNetForwarder) TsnetStopForward(remoteAddr string, remotePort int, localPort int) int {
	f.mutex.Lock()
	defer f.mutex.Unlock()

	// Find and stop matching forwards
	var toRemove []string
	for key, info := range f.forwards {
		if (remoteAddr == "" || info.RemoteAddr == remoteAddr) &&
			(remotePort == 0 || info.RemotePort == remotePort) &&
			(localPort == 0 || info.LocalPort == localPort) {
			toRemove = append(toRemove, key)
		}
	}

	for _, key := range toRemove {
		if info, exists := f.forwards[key]; exists {
			info.Cancel()
			log.Printf("Stopped forward: %s", key)
		}
	}

	return len(toRemove)
}

// TsnetStopAllForwards stops all port forwarding
func (f *TSNetForwarder) TsnetStopAllForwards() int {
	f.mutex.Lock()
	defer f.mutex.Unlock()

	count := len(f.forwards)
	for key, info := range f.forwards {
		info.Cancel()
		log.Printf("Stopped forward: %s", key)
	}

	return count
}

// TsnetRegisterCallback registers callback functions
func (f *TSNetForwarder) TsnetRegisterCallback(callback *ForwardCallback) {
	f.mutex.Lock()
	defer f.mutex.Unlock()

	f.callback = callback
}

// GetForwards gets all current forwarding information
func (f *TSNetForwarder) GetForwards() map[string]*ForwardInfo {
	f.mutex.RLock()
	defer f.mutex.RUnlock()

	result := make(map[string]*ForwardInfo)
	for k, v := range f.forwards {
		result[k] = v
	}
	return result
}

// IsStarted checks if the server is already started
func (f *TSNetForwarder) IsStarted() bool {
	f.mutex.RLock()
	defer f.mutex.RUnlock()
	return f.isStarted
}

// GetTailscaleIPs gets Tailscale IP addresses
func (f *TSNetForwarder) GetTailscaleIPs() []string {
	f.mutex.RLock()
	defer f.mutex.RUnlock()

	if f.server == nil {
		return nil
	}

	ip4, ip6 := f.server.TailscaleIPs()
	var result []string
	if ip4.IsValid() {
		result = append(result, ip4.String())
	}
	if ip6.IsValid() {
		result = append(result, ip6.String())
	}
	return result
}

// GetHostname gets the currently used hostname
func (f *TSNetForwarder) GetHostname() string {
	f.mutex.RLock()
	defer f.mutex.RUnlock()

	return f.getHostname()
}

// Cleanup cleans up resources
func (f *TSNetForwarder) Cleanup() int {
	f.mutex.Lock()
	defer f.mutex.Unlock()

	count := len(f.forwards)

	// Stop all forwards
	for _, info := range f.forwards {
		info.Cancel()
	}
	f.forwards = make(map[string]*ForwardInfo)

	// Stop server
	f.stopServer()

	return count
}
