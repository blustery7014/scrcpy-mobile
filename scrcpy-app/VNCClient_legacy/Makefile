# Compiler
CC = clang

# Compiler flags
CFLAGS = -fmodules -framework Foundation

# Target executable
TARGET = TestCursorPos

# Source files
SOURCES = CursorPosManager.m TestCursorPos.m

# Default target
all: $(TARGET)

$(TARGET): $(SOURCES)
	$(CC) $(CFLAGS) -o $(TARGET) $(SOURCES)

# Clean up build artifacts
clean:
	rm -f $(TARGET)

.PHONY: all clean
