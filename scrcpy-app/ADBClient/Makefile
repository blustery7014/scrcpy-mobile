# Makefile for ADB Latency Tester CLI
# For macOS

# Compiler and flags
CC = clang
CFLAGS = -x objective-c -fobjc-arc -Wall
LDFLAGS = -framework Foundation

# Define target
TARGET = adb-latency-tester

# Source files
SOURCES = ADBLatencyTester.m

# Use our mock ADBClient header
DEFINES = -DLATENCY_TESTER_CLI

# Include paths
INCLUDES = -I.

# Build for macOS
all: $(TARGET)

$(TARGET): $(SOURCES)
	$(CC) $(CFLAGS) $(DEFINES) $(INCLUDES) $^ -o $@ $(LDFLAGS)

debug: CFLAGS += -g -DDEBUG
debug: all

clean:
	rm -f $(TARGET)

run: all
	./$(TARGET)

# Default test with arguments
test: all
	./$(TARGET) -v

# Help
help:
	@echo "ADB Latency Tester CLI Makefile"
	@echo ""
	@echo "Targets:"
	@echo "  all     - Build the CLI tool (default)"
	@echo "  debug   - Build with debug symbols"
	@echo "  clean   - Remove build artifacts"
	@echo "  run     - Build and run the CLI tool"
	@echo "  test    - Build and run with verbose flag"
	@echo "  help    - Show this help message"
	@echo ""
	@echo "Usage examples:"
	@echo "  make                    - Build the CLI tool"
	@echo "  make run                - Build and run with default settings"
	@echo "  make test               - Build and run with verbose output"
	@echo "  ./$(TARGET) --help      - Show CLI usage information"
	@echo "  ./$(TARGET) -h 10.0.0.1 -p 5555   - Test specific host/port"

.PHONY: all debug clean run test help 