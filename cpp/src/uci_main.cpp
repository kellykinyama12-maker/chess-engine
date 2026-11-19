#include "uci.hpp"
#include "zobrist.hpp"
#include <iostream>
#include <string>

// UCI Engine Entry Point
// Runs the chess engine in UCI protocol mode for compatibility with chess GUIs

int main(int argc, char* argv[]) {
    // Initialize zobrist hashing
    Zobrist::init();
    
    // Create UCI handler and run
    UciHandler engine("ChessEngine", "Copilot");
    
    // Run UCI protocol loop
    engine.run();
    
    return 0;
}
