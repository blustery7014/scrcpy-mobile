# ADB Latency Tester CLI

A command-line tool for measuring latency to ADB (Android Debug Bridge) devices.

## Overview

This tool can test the latency of connections to ADB devices by directly using the ADB protocol. It performs a complete ADB handshake and measures the round-trip time to provide accurate measurements.

## Features

- Direct ADB protocol connection testing (no ADB binary required)
- Average latency calculation over multiple tests
- Command line arguments for customization
- Works on macOS (can be adapted for other platforms)

## Building

To build the tool, run:

```bash
make
```

This will create an executable called `adb-latency-tester` in the current directory.

## Usage

```
./adb-latency-tester [options]
```

### Options

- `-h, --host HOST`: Host to connect to (default: 127.0.0.1)
- `-p, --port PORT`: Port to connect to (default: 5555)
- `-c, --count COUNT`: Number of tests to run for average (default: 5)
- `-v, --verbose`: Enable verbose output
- `--help`: Show help message

### Examples

Test latency to the default local ADB server:
```bash
./adb-latency-tester
```

Test latency to a specific device with verbose output:
```bash
./adb-latency-tester -h 192.168.1.100 -p 5555 -v
```

Run 10 tests for a more accurate average:
```bash
./adb-latency-tester -c 10
```

## Makefile Targets

- `make`: Build the tool
- `make debug`: Build with debug symbols
- `make clean`: Remove build artifacts
- `make run`: Build and run with default settings
- `make test`: Build and run with verbose output
- `make help`: Show Makefile help

## Implementation Details

The tool uses direct socket connections to communicate with the ADB server using the ADB protocol. It performs the following steps:

1. Connect to the ADB server socket
2. Send an ADB CNXN (connection) message
3. Read and parse the response
4. Measure the round-trip time

This provides a more accurate measurement of the actual ADB protocol latency compared to using the `adb` command-line tool. 