#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <time.h>

// Include the generated header file
#include "../build/libtsnet-forwarder.h"

// Color codes for better output
#define COLOR_RESET   "\033[0m"
#define COLOR_RED     "\033[31m"
#define COLOR_GREEN   "\033[32m"
#define COLOR_YELLOW  "\033[33m"
#define COLOR_BLUE    "\033[34m"
#define COLOR_MAGENTA "\033[35m"
#define COLOR_CYAN    "\033[36m"

void print_header() {
    printf(COLOR_CYAN "========================================\n");
    printf("  libtsnet-forwarder C Test Program\n");
    printf("========================================\n" COLOR_RESET);
}

void print_step(const char* step) {
    printf(COLOR_BLUE "[STEP] %s\n" COLOR_RESET, step);
}

void print_success(const char* message) {
    printf(COLOR_GREEN "[SUCCESS] %s\n" COLOR_RESET, message);
}

void print_error(const char* message) {
    printf(COLOR_RED "[ERROR] %s\n" COLOR_RESET, message);
}

void print_info(const char* message) {
    printf(COLOR_YELLOW "[INFO] %s\n" COLOR_RESET, message);
}

void print_connection_info() {
    char* hostname = tsnet_get_last_hostname();
    char* magic_dns = tsnet_get_last_magic_dns();
    char* ipv4 = tsnet_get_last_ipv4();
    char* ipv6 = tsnet_get_last_ipv6();
    
    printf(COLOR_MAGENTA "\n🎉 Connection Information:\n");
    printf("   📍 Hostname:  %s\n", hostname ? hostname : "N/A");
    printf("   🌐 MagicDNS:  %s\n", magic_dns ? magic_dns : "N/A");
    printf("   🔗 IPv4:      %s\n", ipv4 ? ipv4 : "N/A");
    printf("   🔗 IPv6:      %s\n", ipv6 ? ipv6 : "N/A");
    printf(COLOR_RESET "\n");
    
    // Free allocated strings
    if (hostname) free(hostname);
    if (magic_dns) free(magic_dns);
    if (ipv4) free(ipv4);
    if (ipv6) free(ipv6);
}

void wait_for_connection(int timeout_seconds) {
    print_step("Waiting for connection to complete...");
    
    int elapsed = 0;
    while (elapsed < timeout_seconds) {
        int status = tsnet_get_connect_status();
        
        if (status == 1) {
            print_success("Connected to Tailscale network!");
            print_connection_info();
            return;
        } else if (status == -1) {
            char* error = tsnet_get_last_error();
            printf(COLOR_RED "[ERROR] Connection failed: %s\n" COLOR_RESET, 
                   error ? error : "Unknown error");
            if (error) free(error);
            return;
        }
        
        printf(".");
        fflush(stdout);
        sleep(1);
        elapsed++;
    }
    
    print_error("Connection timeout!");
}

int main(int argc, char* argv[]) {
    print_header();
    
    // Check for auth key argument
    if (argc < 2) {
        print_error("Usage: ./main <tailscale-auth-key> [hostname] [state-dir]");
        printf(COLOR_YELLOW "Example: ./main tskey-auth-xxxxxx my-device /tmp/tsnet-test\n" COLOR_RESET);
        return 1;
    }
    
    const char* auth_key = argv[1];
    const char* hostname = argc > 2 ? argv[2] : "tsnet-c-test";
    const char* state_dir = argc > 3 ? argv[3] : "/tmp/tsnet-c-test";
    
    print_info("Starting Tailscale connection test...");
    printf("   Auth Key: %s...%s\n", 
           strncmp(auth_key, "tskey-", 6) == 0 ? "tskey-" : "****", 
           strlen(auth_key) > 10 ? &auth_key[strlen(auth_key)-4] : "****");
    printf("   Hostname: %s\n", hostname);
    printf("   State Dir: %s\n", state_dir);
    printf("\n");
    
    // Step 1: Set authentication key
    print_step("Setting Tailscale authentication key...");
    if (update_tsnet_auth_key((char*)auth_key) != 0) {
        print_error("Failed to set authentication key");
        return 1;
    }
    print_success("Authentication key set successfully");
    
    // Step 2: Set hostname
    print_step("Setting hostname...");
    if (tsnet_update_hostname((char*)hostname) != 0) {
        print_error("Failed to set hostname");
        return 1;
    }
    print_success("Hostname set successfully");
    
    // Step 3: Set state directory
    print_step("Setting state directory...");
    if (tsnet_update_state_dir((char*)state_dir) != 0) {
        print_error("Failed to set state directory");
        return 1;
    }
    print_success("State directory set successfully");
    
    // Step 4: Show current configuration
    print_step("Current configuration:");
    char* current_hostname = tsnet_get_hostname();
    char* current_state_dir = tsnet_get_state_dir();
    printf("   Hostname: %s\n", current_hostname ? current_hostname : "N/A");
    printf("   State Dir: %s\n", current_state_dir ? current_state_dir : "N/A");
    if (current_hostname) free(current_hostname);
    if (current_state_dir) free(current_state_dir);
    
    // Step 5: Connect to Tailscale (asynchronous)
    print_step("Connecting to Tailscale network...");
    tsnet_connect_async();
    
    // Step 6: Wait for connection
    wait_for_connection(60); // 60 seconds timeout
    
    // Step 7: Check if server is started
    if (tsnet_is_started()) {
        print_success("TSNet server is running");
        
        // Get and display additional IP information
        char* current_ip = tsnet_get_tailscale_ips();
        if (current_ip && strlen(current_ip) > 0) {
            printf(COLOR_CYAN "Current Tailscale IP: %s\n" COLOR_RESET, current_ip);
        }
        if (current_ip) free(current_ip);
        
    } else {
        print_error("TSNet server is not running");
    }
    
    // Step 8: Cleanup
    print_step("Cleaning up...");
    int cleaned_count = tsnet_cleanup();
    printf(COLOR_GREEN "[SUCCESS] Cleaned up %d connections\n" COLOR_RESET, cleaned_count);
    
    printf(COLOR_CYAN "\n========================================\n");
    printf("  Test completed successfully!\n");
    printf("========================================\n" COLOR_RESET);
    
    return 0;
} 