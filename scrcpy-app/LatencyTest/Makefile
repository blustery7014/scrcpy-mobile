# Makefile for TCPLatencyTester CLI
# Usage: make tcp-latency-tester

CC = clang
CFLAGS = -framework Foundation -fobjc-arc
TARGET = tcp-latency-tester
SOURCES = tcp-latency-tester-cli.m TCPLatencyTester.m

.PHONY: all clean test

all: $(TARGET)

$(TARGET): $(SOURCES)
	$(CC) $(CFLAGS) -o $(TARGET) $(SOURCES)

clean:
	rm -f $(TARGET)

install: $(TARGET)
	cp $(TARGET) /usr/local/bin/

uninstall:
	rm -f /usr/local/bin/$(TARGET)

# Test targets
test: $(TARGET)
	@echo "Testing Google DNS..."
	./$(TARGET) 8.8.8.8 53 -c 3

test-google: $(TARGET)
	@echo "Testing Google.com HTTP..."
	./$(TARGET) www.google.com 80 -c 3

test-cloudflare: $(TARGET)
	@echo "Testing Cloudflare DNS..."
	./$(TARGET) 1.1.1.1 53 -c 5

test-adb: $(TARGET)
	@echo "Testing local ADB server..."
	./$(TARGET) 127.0.0.1 5037 -c 1

test-all: test test-google test-cloudflare

help:
	@echo "Available targets:"
	@echo "  all           - Build the tcp-latency-tester binary"
	@echo "  clean         - Remove built files"
	@echo "  install       - Install to /usr/local/bin"
	@echo "  uninstall     - Remove from /usr/local/bin"
	@echo "  test          - Run basic test to Google DNS"
	@echo "  test-google   - Test Google.com HTTP"
	@echo "  test-cloudflare - Test Cloudflare DNS"
	@echo "  test-adb      - Test local ADB server"
	@echo "  test-all      - Run all tests"
	@echo "  help          - Show this help" 