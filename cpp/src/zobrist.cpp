#include "zobrist.hpp"
#include <random>
#include <chrono>

// Initialize static members
std::array<std::array<uint64_t, 64>, 12> Zobrist::piece_keys;
uint64_t Zobrist::side_key;
std::array<uint64_t, 16> Zobrist::castling_keys;
std::array<uint64_t, 64> Zobrist::en_passant_keys;
bool Zobrist::initialized = false;

uint64_t Zobrist::random_u64() {
    static std::random_device rd;
    static std::mt19937_64 generator(rd());
    return generator();
}

void Zobrist::init() {
    if (initialized) return;
    initialized = true;
    
    // Initialize piece keys
    for (int piece_idx = 0; piece_idx < 12; piece_idx++) {
        for (int sq = 0; sq < 64; sq++) {
            piece_keys[piece_idx][sq] = random_u64();
        }
    }
    
    // Initialize side key
    side_key = random_u64();
    
    // Initialize castling keys
    for (int i = 0; i < 16; i++) {
        castling_keys[i] = random_u64();
    }
    
    // Initialize en passant keys
    for (int sq = 0; sq < 64; sq++) {
        en_passant_keys[sq] = random_u64();
    }
}

uint64_t Zobrist::piece(Piece p, Square sq) {
    if (!initialized) init();
    if (p.type == PieceType::NONE) return 0;
    
    int piece_idx = static_cast<int>(p.type) + 
                    (p.color == Color::BLACK ? 6 : 0);
    return piece_keys[piece_idx][sq.index];
}

uint64_t Zobrist::side() {
    if (!initialized) init();
    return side_key;
}

uint64_t Zobrist::castling_rights(bool wk, bool wq, bool bk, bool bq) {
    if (!initialized) init();
    int index = (wk ? 1 : 0) + (wq ? 2 : 0) + (bk ? 4 : 0) + (bq ? 8 : 0);
    return castling_keys[index];
}

uint64_t Zobrist::en_passant(Square sq) {
    if (!initialized) init();
    if (sq.index >= 64) return 0;
    return en_passant_keys[sq.index];
}
