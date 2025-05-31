#ifndef TSNET_FORWARDER_H
#define TSNET_FORWARDER_H

#ifdef __cplusplus
extern "C" {
#endif

// Callback function type definitions
typedef void (*forward_success_callback)(char* remote_addr, int remote_port, int local_port);
typedef void (*forward_closed_callback)(char* remote_addr, int remote_port, int local_port);
typedef void (*forward_error_callback)(char* remote_addr, int remote_port, int local_port, char* error_msg);

// API function declarations
extern int update_tsnet_auth_key(char* auth_key);
extern int tsnet_start_forward(char* remote_addr, int remote_port, int local_port);
extern int tsnet_stop_forward(char* remote_addr, int remote_port, int local_port);
extern int tsnet_stop_all_forwards(void);
extern void tsnet_register_callbacks(
    forward_success_callback on_success,
    forward_closed_callback on_closed,
    forward_error_callback on_error
);
extern int tsnet_cleanup(void);
extern int tsnet_is_started(void);
extern char* tsnet_get_tailscale_ips(void);

#ifdef __cplusplus
}
#endif

#endif // TSNET_FORWARDER_H 