package main

/*
#include <stdlib.h>
*/
import "C"

import (
	forwarder "me.wsen.scrcpy-tsnet/lib"
)

var tsnetForwarder *forwarder.TSNetForwarder

func init() {
	tsnetForwarder = forwarder.GetInstance()
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

// main function is required
func main() {}
