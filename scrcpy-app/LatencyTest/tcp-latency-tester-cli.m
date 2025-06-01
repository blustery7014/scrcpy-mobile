//
//  tcp-latency-tester-cli.m
//  Scrcpy Remote
//
//  Created by Claude on 12/27/24.
//  Command line interface for TCPLatencyTester
//

#import <Foundation/Foundation.h>
#import "TCPLatencyTester.h"

void printUsage(const char *programName) {
    printf("TCP Latency Tester - Tests TCP connection latency to any host:port\n\n");
    printf("Usage: %s [options] <host> <port>\n\n", programName);
    printf("Arguments:\n");
    printf("  host                 Target hostname or IP address\n");
    printf("  port                 Target port number\n\n");
    printf("Options:\n");
    printf("  -c, --count COUNT    Number of tests to run for average (default: 3)\n");
    printf("  -t, --timeout SEC    Connection timeout in seconds (default: 10)\n");
    printf("  -r, --read-timeout SEC  Read timeout in seconds (default: 5)\n");
    printf("  -d, --data STRING    Custom data to send (default: \"PING\\n\")\n");
    printf("  -v, --verbose        Enable verbose output\n");
    printf("  -h, --help           Show this help message\n\n");
    printf("Examples:\n");
    printf("  %s google.com 80                    # Test HTTP port\n", programName);
    printf("  %s 8.8.8.8 53 -c 5                 # Test DNS with 5 iterations\n", programName);
    printf("  %s 127.0.0.1 5037 -v               # Test local ADB with verbose output\n", programName);
    printf("  %s example.com 443 -t 5 -r 3       # Test HTTPS with custom timeouts\n", programName);
}

int main(int argc, const char * argv[]) {
    @autoreleasepool {
        // Default values
        NSString *host = nil;
        NSString *port = nil;
        int testCount = 3;
        double connectionTimeout = 10.0;
        double readTimeout = 5.0;
        NSString *customData = nil;
        BOOL verbose = NO;
        
        // Parse command line arguments
        for (int i = 1; i < argc; i++) {
            NSString *arg = [NSString stringWithUTF8String:argv[i]];
            
            if ([arg isEqualToString:@"-h"] || [arg isEqualToString:@"--help"]) {
                printUsage(argv[0]);
                return 0;
            } else if ([arg isEqualToString:@"-c"] || [arg isEqualToString:@"--count"]) {
                if (i + 1 < argc) {
                    testCount = atoi(argv[++i]);
                    if (testCount <= 0) testCount = 1;
                }
            } else if ([arg isEqualToString:@"-t"] || [arg isEqualToString:@"--timeout"]) {
                if (i + 1 < argc) {
                    connectionTimeout = atof(argv[++i]);
                    if (connectionTimeout <= 0) connectionTimeout = 10.0;
                }
            } else if ([arg isEqualToString:@"-r"] || [arg isEqualToString:@"--read-timeout"]) {
                if (i + 1 < argc) {
                    readTimeout = atof(argv[++i]);
                    if (readTimeout <= 0) readTimeout = 5.0;
                }
            } else if ([arg isEqualToString:@"-d"] || [arg isEqualToString:@"--data"]) {
                if (i + 1 < argc) {
                    customData = [NSString stringWithUTF8String:argv[++i]];
                }
            } else if ([arg isEqualToString:@"-v"] || [arg isEqualToString:@"--verbose"]) {
                verbose = YES;
            } else if (!host) {
                host = arg;
            } else if (!port) {
                port = arg;
            } else {
                printf("Error: Too many arguments\n\n");
                printUsage(argv[0]);
                return 1;
            }
        }
        
        // Validate required arguments
        if (!host || !port) {
            printf("Error: Host and port are required\n\n");
            printUsage(argv[0]);
            return 1;
        }
        
        // Validate port number
        int portNumber = [port intValue];
        if (portNumber <= 0 || portNumber > 65535) {
            printf("Error: Invalid port number: %s\n", [port UTF8String]);
            return 1;
        }
        
        // Print test configuration
        printf("TCP Latency Tester\n");
        printf("==================\n");
        printf("Target: %s:%s\n", [host UTF8String], [port UTF8String]);
        printf("Test count: %d\n", testCount);
        printf("Connection timeout: %.1f seconds\n", connectionTimeout);
        printf("Read timeout: %.1f seconds\n", readTimeout);
        if (customData) {
            printf("Custom data: \"%s\"\n", [customData UTF8String]);
        }
        if (verbose) {
            printf("Verbose output: enabled\n");
        }
        printf("\n");
        
        // Create TCPLatencyTester
        TCPLatencyTester *tester = [[TCPLatencyTester alloc] initWithHost:host port:port];
        tester.connectionTimeout = connectionTimeout;
        tester.readTimeout = readTimeout;
        
        // Prepare custom data if provided
        NSData *testData = nil;
        if (customData) {
            // Add newline if not present
            if (![customData hasSuffix:@"\n"]) {
                customData = [customData stringByAppendingString:@"\n"];
            }
            testData = [customData dataUsingEncoding:NSUTF8StringEncoding];
        }
        
        // Use semaphore to wait for async operations
        dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);
        
        printf("Running %d test(s)...\n", testCount);
        
        if (testCount == 1) {
            // Single test
            if (testData) {
                [tester testLatencyWithCustomData:testData completion:^(NSNumber * _Nullable latencyMs, NSError * _Nullable error) {
                    if (error) {
                        printf("Test failed: %s\n", [error.localizedDescription UTF8String]);
                    } else {
                        printf("Latency: %.2f ms\n", [latencyMs doubleValue]);
                    }
                    dispatch_semaphore_signal(semaphore);
                }];
            } else {
                [tester testLatency:^(NSNumber * _Nullable latencyMs, NSError * _Nullable error) {
                    if (error) {
                        printf("Test failed: %s\n", [error.localizedDescription UTF8String]);
                    } else {
                        printf("Latency: %.2f ms\n", [latencyMs doubleValue]);
                    }
                    dispatch_semaphore_signal(semaphore);
                }];
            }
        } else {
            // Multiple tests for average
            [tester testAverageLatencyWithCount:testCount completion:^(NSNumber * _Nullable latencyMs, NSError * _Nullable error) {
                if (error) {
                    printf("Average latency test failed: %s\n", [error.localizedDescription UTF8String]);
                } else {
                    printf("Average latency: %.2f ms\n", [latencyMs doubleValue]);
                    
                    // Provide quality assessment
                    double latency = [latencyMs doubleValue];
                    printf("Connection quality: ");
                    if (latency < 50) {
                        printf("Excellent\n");
                    } else if (latency < 100) {
                        printf("Good\n");
                    } else if (latency < 200) {
                        printf("Moderate\n");
                    } else {
                        printf("Poor\n");
                    }
                }
                dispatch_semaphore_signal(semaphore);
            }];
        }
        
        // Wait for completion
        dispatch_semaphore_wait(semaphore, DISPATCH_TIME_FOREVER);
        
        if (verbose) {
            printf("\nTest completed.\n");
        }
    }
    
    return 0;
} 