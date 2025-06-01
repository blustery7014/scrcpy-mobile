package main

/*
#include <stdlib.h>
*/
import "C"

import (
	"log"
	"time"

	forwarder "me.wsen.scrcpy-tsnet/lib"
)

var tsnetForwarder *forwarder.TSNetForwarder

// Global variables to store connection info for C callbacks
var (
	lastHostname  string
	lastMagicDNS  string
	lastIPv4      string
	lastIPv6      string
	lastError     string
	connectStatus int // 0: none, 1: success, -1: error

	// Test variables to track IP changes
	firstConnectionIPs  []string
	secondConnectionIPs []string
)

func init() {
	tsnetForwarder = forwarder.GetInstance()

	// Register connect callback
	connectCallback := &forwarder.ConnectCallback{
		OnConnectSuccess: func(hostname, magicDNS, ipv4, ipv6 string) {
			log.Printf("Connect Success: hostname=%s, magicDNS=%s, ipv4=%s, ipv6=%s", hostname, magicDNS, ipv4, ipv6)
			lastHostname = hostname
			lastMagicDNS = magicDNS
			lastIPv4 = ipv4
			lastIPv6 = ipv6
			connectStatus = 1
		},
		OnConnectError: func(hostname string, err error) {
			log.Printf("Connect Error: hostname=%s, error=%v", hostname, err)
			lastHostname = hostname
			lastError = err.Error()
			connectStatus = -1
		},
	}
	tsnetForwarder.TsnetRegisterConnectCallback(connectCallback)
}

// update_tsnet_auth_key sets the tsnet authentication key
//
//export update_tsnet_auth_key
func update_tsnet_auth_key(authKey *C.char) C.int {
	key := C.GoString(authKey)
	if err := tsnetForwarder.UpdateTsnetAuthKey(key); err != nil {
		return -1
	}
	return 0
}

// tsnet_update_hostname sets the tsnet client hostname
//
//export tsnet_update_hostname
func tsnet_update_hostname(hostname *C.char) C.int {
	host := C.GoString(hostname)
	if err := tsnetForwarder.TsnetUpdateHostname(host); err != nil {
		return -1
	}
	return 0
}

// tsnet_update_state_dir sets the tsnet state directory
//
//export tsnet_update_state_dir
func tsnet_update_state_dir(stateDir *C.char) C.int {
	dir := C.GoString(stateDir)
	if err := tsnetForwarder.TsnetUpdateStateDir(dir); err != nil {
		return -1
	}
	return 0
}

// tsnet_connect connects to Tailscale network
//
//export tsnet_connect
func tsnet_connect() C.int {
	connectStatus = 0
	if err := tsnetForwarder.TsnetConnect(); err != nil {
		return -1
	}
	return 0
}

// tsnet_connect_async connects to Tailscale network asynchronously
//
//export tsnet_connect_async
func tsnet_connect_async() {
	connectStatus = 0
	tsnetForwarder.TsnetConnectAsync()
}

// tsnet_get_connect_status gets the connection status
//
//export tsnet_get_connect_status
func tsnet_get_connect_status() C.int {
	return C.int(connectStatus)
}

// tsnet_get_last_hostname gets the last connected hostname
//
//export tsnet_get_last_hostname
func tsnet_get_last_hostname() *C.char {
	return C.CString(lastHostname)
}

// tsnet_get_last_magic_dns gets the last connected MagicDNS
//
//export tsnet_get_last_magic_dns
func tsnet_get_last_magic_dns() *C.char {
	return C.CString(lastMagicDNS)
}

// tsnet_get_last_ipv4 gets the last connected IPv4
//
//export tsnet_get_last_ipv4
func tsnet_get_last_ipv4() *C.char {
	return C.CString(lastIPv4)
}

// tsnet_get_last_ipv6 gets the last connected IPv6
//
//export tsnet_get_last_ipv6
func tsnet_get_last_ipv6() *C.char {
	return C.CString(lastIPv6)
}

// tsnet_get_last_error gets the last connection error
//
//export tsnet_get_last_error
func tsnet_get_last_error() *C.char {
	return C.CString(lastError)
}

// tsnet_start_forward starts port forwarding
//
//export tsnet_start_forward
func tsnet_start_forward(remoteAddr *C.char, remotePort C.int, localPort C.int) C.int {
	addr := C.GoString(remoteAddr)
	rPort := int(remotePort)
	lPort := int(localPort)

	if err := tsnetForwarder.TsnetStartForward(addr, rPort, lPort); err != nil {
		return -1
	}
	return 0
}

// tsnet_stop_forward stops port forwarding
//
//export tsnet_stop_forward
func tsnet_stop_forward(remoteAddr *C.char, remotePort C.int, localPort C.int) C.int {
	addr := C.GoString(remoteAddr)
	rPort := int(remotePort)
	lPort := int(localPort)

	count := tsnetForwarder.TsnetStopForward(addr, rPort, lPort)
	return C.int(count)
}

// tsnet_stop_all_forwards stops all port forwarding
//
//export tsnet_stop_all_forwards
func tsnet_stop_all_forwards() C.int {
	count := tsnetForwarder.TsnetStopAllForwards()
	return C.int(count)
}

// tsnet_cleanup cleans up resources
//
//export tsnet_cleanup
func tsnet_cleanup() C.int {
	count := tsnetForwarder.Cleanup()
	return C.int(count)
}

// tsnet_is_started checks if the server is already started
//
//export tsnet_is_started
func tsnet_is_started() C.int {
	if tsnetForwarder.IsStarted() {
		return 1
	}
	return 0
}

// tsnet_get_tailscale_ips gets Tailscale IP addresses (returns the first IP)
//
//export tsnet_get_tailscale_ips
func tsnet_get_tailscale_ips() *C.char {
	ips := tsnetForwarder.GetTailscaleIPs()
	if len(ips) > 0 {
		return C.CString(ips[0])
	}
	return C.CString("")
}

// tsnet_get_hostname gets the currently used hostname
//
//export tsnet_get_hostname
func tsnet_get_hostname() *C.char {
	hostname := tsnetForwarder.GetHostname()
	return C.CString(hostname)
}

// tsnet_get_state_dir gets the currently used state directory
//
//export tsnet_get_state_dir
func tsnet_get_state_dir() *C.char {
	stateDir := tsnetForwarder.GetStateDir()
	return C.CString(stateDir)
}

// tsnet_test_ip_reuse_consistency tests if IP addresses remain consistent when reusing state
//
//export tsnet_test_ip_reuse_consistency
func tsnet_test_ip_reuse_consistency(authKey *C.char, hostname *C.char, stateDir *C.char) C.int {
	log.Printf("=== Starting IP Reuse Consistency Test ===")

	// Setup configuration
	key := C.GoString(authKey)
	host := C.GoString(hostname)
	dir := C.GoString(stateDir)

	if err := tsnetForwarder.UpdateTsnetAuthKey(key); err != nil {
		log.Printf("Failed to set auth key: %v", err)
		return -1
	}

	if err := tsnetForwarder.TsnetUpdateHostname(host); err != nil {
		log.Printf("Failed to set hostname: %v", err)
		return -1
	}

	if err := tsnetForwarder.TsnetUpdateStateDir(dir); err != nil {
		log.Printf("Failed to set state dir: %v", err)
		return -1
	}

	// First connection
	log.Printf("--- First Connection ---")
	connectStatus = 0
	if err := tsnetForwarder.TsnetConnect(); err != nil {
		log.Printf("First connection failed: %v", err)
		return -1
	}

	// Wait for connection to complete
	for i := 0; i < 30; i++ {
		if connectStatus != 0 {
			break
		}
		time.Sleep(1 * time.Second)
	}

	if connectStatus != 1 {
		log.Printf("First connection did not succeed within timeout")
		return -1
	}

	// Record first connection IPs
	firstConnectionIPs = tsnetForwarder.GetTailscaleIPs()
	log.Printf("First connection IPs: %v", firstConnectionIPs)

	// Cleanup (this should preserve state directory)
	log.Printf("--- Cleaning up for reconnection test ---")
	cleanupCount := tsnetForwarder.Cleanup()
	log.Printf("Cleanup stopped %d forwards", cleanupCount)

	// Wait a moment before reconnecting
	time.Sleep(2 * time.Second)

	// Second connection (should reuse state)
	log.Printf("--- Second Connection (State Reuse Test) ---")
	connectStatus = 0
	if err := tsnetForwarder.TsnetConnect(); err != nil {
		log.Printf("Second connection failed: %v", err)
		return -1
	}

	// Wait for second connection to complete
	for i := 0; i < 30; i++ {
		if connectStatus != 0 {
			break
		}
		time.Sleep(1 * time.Second)
	}

	if connectStatus != 1 {
		log.Printf("Second connection did not succeed within timeout")
		return -1
	}

	// Record second connection IPs
	secondConnectionIPs = tsnetForwarder.GetTailscaleIPs()
	log.Printf("Second connection IPs: %v", secondConnectionIPs)

	// Compare IPs
	log.Printf("--- IP Comparison Results ---")
	if len(firstConnectionIPs) != len(secondConnectionIPs) {
		log.Printf("❌ DIFFERENT: IP count changed from %d to %d", len(firstConnectionIPs), len(secondConnectionIPs))
		return -1
	}

	identical := true
	for i, ip1 := range firstConnectionIPs {
		if i < len(secondConnectionIPs) {
			ip2 := secondConnectionIPs[i]
			if ip1 == ip2 {
				log.Printf("✅ SAME: IP[%d] = %s", i, ip1)
			} else {
				log.Printf("❌ DIFFERENT: IP[%d] changed from %s to %s", i, ip1, ip2)
				identical = false
			}
		}
	}

	if identical {
		log.Printf("🎉 SUCCESS: All IP addresses remained consistent after state reuse!")
		return 1
	} else {
		log.Printf("⚠️  WARNING: IP addresses changed after reconnection")
		return 0
	}
}

// tsnet_get_first_connection_ips gets the first connection IP addresses for comparison
//
//export tsnet_get_first_connection_ips
func tsnet_get_first_connection_ips() *C.char {
	if len(firstConnectionIPs) > 0 {
		return C.CString(firstConnectionIPs[0])
	}
	return C.CString("")
}

// tsnet_get_second_connection_ips gets the second connection IP addresses for comparison
//
//export tsnet_get_second_connection_ips
func tsnet_get_second_connection_ips() *C.char {
	if len(secondConnectionIPs) > 0 {
		return C.CString(secondConnectionIPs[0])
	}
	return C.CString("")
}

// main function is required
func main() {}
