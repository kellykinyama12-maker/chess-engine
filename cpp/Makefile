# Makefile for Chess Engine C++ port
# Using MinGW on Windows
# Usage: mingw32-make or mingw32-make build
# Note: -O0 is used instead of -O1/-O2/-O3 due to GCC 16 optimization issues with constexpr arrays

CXX = g++
CXXFLAGS = -std=c++17 -Wall -Wextra -O0 -Iinclude
LDFLAGS = -static-libgcc -static-libstdc++

# Directories
SRC_DIR = src
INC_DIR = include

# Source files (excluding main.cpp)
SOURCES = src/zobrist.cpp src/position.cpp src/move_gen.cpp

# Main executable
MAIN_EXE = build/bin/chess_engine.exe

# All targets
.PHONY: all build clean help

all: build

build: $(MAIN_EXE)

build/bin/chess_engine.exe: $(SOURCES) $(SRC_DIR)/main.cpp
	@if not exist build\bin mkdir build\bin
	$(CXX) $(CXXFLAGS) $(SOURCES) $(SRC_DIR)/main.cpp -o $@ $(LDFLAGS)
	@echo Built executable: $@

clean:
	@if exist build rmdir /s /q build
	@echo Cleaned build artifacts

help:
	@echo Chess Engine C++ Build System
	@echo.
	@echo make           - Build everything
	@echo make clean     - Clean build artifacts
	@echo make help      - Show this help
