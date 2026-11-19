cmake_minimum_required(VERSION 3.20)
project(chess_engine_cpp VERSION 1.0.0 LANGUAGES CXX)

# C++ Standard
set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

# Build type configuration
if(NOT CMAKE_BUILD_TYPE)
    set(CMAKE_BUILD_TYPE Release CACHE STRING "Build type" FORCE)
endif()

message(STATUS "Build type: ${CMAKE_BUILD_TYPE}")
message(STATUS "C++ Standard: ${CMAKE_CXX_STANDARD}")

# Platform-specific settings
if(WIN32)
    if(MINGW)
        message(STATUS "Configuring for MinGW on Windows")
        
        # Compiler flags for MinGW
        set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -Wall -Wextra -Wpedantic")
        set(CMAKE_CXX_FLAGS_DEBUG "-g -O0")
        set(CMAKE_CXX_FLAGS_RELEASE "-O3 -march=native -flto")
        
        # Static linking
        set(CMAKE_EXE_LINKER_FLAGS "${CMAKE_EXE_LINKER_FLAGS} -static-libgcc -static-libstdc++")
    else()
        message(STATUS "Configuring for MSVC on Windows")
        set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} /W4 /permissive-")
        set(CMAKE_CXX_FLAGS_RELEASE "${CMAKE_CXX_FLAGS_RELEASE} /O2 /GL")
    endif()
elseif(UNIX AND NOT APPLE)
    message(STATUS "Configuring for Linux")
    set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -Wall -Wextra -Wpedantic")
    set(CMAKE_CXX_FLAGS_DEBUG "-g -O0")
    set(CMAKE_CXX_FLAGS_RELEASE "-O3 -march=native -flto")
elseif(APPLE)
    message(STATUS "Configuring for macOS")
    set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -Wall -Wextra -Wpedantic")
    set(CMAKE_CXX_FLAGS_DEBUG "-g -O0")
    set(CMAKE_CXX_FLAGS_RELEASE "-O3 -flto")
endif()

# Source files
set(CHESS_SOURCES
    src/position.cpp
    src/move_gen.cpp
    src/zobrist.cpp
)

set(MCTS_SOURCES
    src/mcts_new.cpp
    src/thread_pool.cpp
    src/uci.cpp
)

set(ALL_SOURCES ${CHESS_SOURCES} ${MCTS_SOURCES})

# Library: chess_core
add_library(chess_core OBJECT ${CHESS_SOURCES})
target_include_directories(chess_core PUBLIC 
    ${CMAKE_CURRENT_SOURCE_DIR}/include
)
target_compile_features(chess_core PUBLIC cxx_std_17)

# Library: mcts_engine
add_library(mcts_engine OBJECT ${MCTS_SOURCES})
target_include_directories(mcts_engine PUBLIC 
    ${CMAKE_CURRENT_SOURCE_DIR}/include
)
target_compile_features(mcts_engine PUBLIC cxx_std_17)

# Main executable
add_executable(chess_engine src/main.cpp)
target_include_directories(chess_engine PRIVATE 
    ${CMAKE_CURRENT_SOURCE_DIR}/include
)
target_link_libraries(chess_engine chess_core mcts_engine)
target_compile_features(chess_engine PRIVATE cxx_std_17)

# UCI executable for chess GUI compatibility
add_executable(chess_engine_uci src/uci_main.cpp)
target_include_directories(chess_engine_uci PRIVATE 
    ${CMAKE_CURRENT_SOURCE_DIR}/include
)
target_link_libraries(chess_engine_uci chess_core mcts_engine)
target_compile_features(chess_engine_uci PRIVATE cxx_std_17)

# Optional: Tests executable
option(BUILD_TESTS "Build test suite" ON)
if(BUILD_TESTS)
    add_executable(chess_engine_test src/main.cpp)
    target_include_directories(chess_engine_test PRIVATE 
        ${CMAKE_CURRENT_SOURCE_DIR}/include
    )
    target_link_libraries(chess_engine_test chess_core mcts_engine)
    target_compile_features(chess_engine_test PRIVATE cxx_std_17)
    
    # Register test
    enable_testing()
    add_test(NAME chess_engine_tests COMMAND chess_engine_test)
endif()

# Installation
install(TARGETS chess_engine chess_engine_uci
    RUNTIME DESTINATION bin
)

install(DIRECTORY include/
    DESTINATION include/chess_engine
    FILES_MATCHING PATTERN "*.hpp"
)

# Print configuration summary
message(STATUS "")
message(STATUS "Chess Engine C++ Configuration Summary")
message(STATUS "========================================")
message(STATUS "Build Type: ${CMAKE_BUILD_TYPE}")
message(STATUS "C++ Standard: ${CMAKE_CXX_STANDARD}")
message(STATUS "Compiler: ${CMAKE_CXX_COMPILER}")
message(STATUS "Build Tests: ${BUILD_TESTS}")
message(STATUS "")
message(STATUS "Source Files:")
message(STATUS "  Chess Core: ${CHESS_SOURCES}")
message(STATUS "  MCTS Engine: ${MCTS_SOURCES}")
message(STATUS "")
message(STATUS "Build Flags:")
if(MINGW)
    message(STATUS "  Debug: ${CMAKE_CXX_FLAGS_DEBUG}")
    message(STATUS "  Release: ${CMAKE_CXX_FLAGS_RELEASE}")
endif()
message(STATUS "")
message(STATUS "To build:")
message(STATUS "  mkdir build && cd build")
message(STATUS "  cmake ..")
message(STATUS "  cmake --build . --config ${CMAKE_BUILD_TYPE}")
message(STATUS "")
