#pragma once

#include "types.hpp"
#include <array>
#include <cstdint>

class Zobrist {
public:
    // Initialize Zobrist tables (must be called once at startup)
    static void init();
    
    // Get hash for a piece at a square
    static uint64_t piece(Piece p, Square sq);
    
    // Get hash for side to move
    static uint64_t side();
    
    // Get hash for castling rights (index 0-15 for all combinations)
    static uint64_t castling_rights(bool wk, bool wq, bool bk, bool bq);
    
    // Get hash for en passant square (or 0 if none)
    static uint64_t en_passant(Square sq);

private:
    // Zobrist lookup tables
    // piece_keys[12][64] - 12 piece types (6 piece types * 2 colors) * 64 squares
    static std::array<std::array<uint64_t, 64>, 12> piece_keys;
    
    // side_key - for side to move
    static uint64_t side_key;
    
    // castling_keys[16] - 2^4 castling right combinations
    static std::array<uint64_t, 16> castling_keys;
    
    // en_passant_keys[64] - for each file (en passant only on 4th/5th rank)
    static std::array<uint64_t, 64> en_passant_keys;
    
    // For initialization
    static uint64_t random_u64();
    static bool initialized;
};
