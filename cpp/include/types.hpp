#pragma once

#include <cstdint>
#include <string>
#include <array>
#include <vector>

// === Core Types ===

enum class Color : uint8_t {
    WHITE = 0,
    BLACK = 1
};

enum class PieceType : uint8_t {
    PAWN = 0,
    KNIGHT = 1,
    BISHOP = 2,
    ROOK = 3,
    QUEEN = 4,
    KING = 5,
    NONE = 6
};

enum class Rank : uint8_t {
    RANK_1 = 0, RANK_2 = 1, RANK_3 = 2, RANK_4 = 3,
    RANK_5 = 4, RANK_6 = 5, RANK_7 = 6, RANK_8 = 7
};

enum class File : uint8_t {
    FILE_A = 0, FILE_B = 1, FILE_C = 2, FILE_D = 3,
    FILE_E = 4, FILE_F = 5, FILE_G = 6, FILE_H = 7
};

struct Square {
    uint8_t index;  // 0-63 (a1=0, h1=7, a8=56, h8=63)
    
    constexpr Square() : index(0) {}
    constexpr Square(uint8_t idx) : index(idx) {}
    constexpr Square(File f, Rank r) : index(static_cast<uint8_t>(f) + static_cast<uint8_t>(r) * 8) {}
    
    constexpr File file() const { return static_cast<File>(index % 8); }
    constexpr Rank rank() const { return static_cast<Rank>(index / 8); }
    
    bool operator==(const Square& other) const { return index == other.index; }
    bool operator!=(const Square& other) const { return index != other.index; }
    
    std::string to_string() const {
        char file_char = 'a' + (index % 8);
        char rank_char = '1' + (index / 8);
        return std::string(1, file_char) + rank_char;
    }
};

struct Move {
    uint16_t from;
    uint16_t to;
    PieceType promotion = PieceType::NONE;
    
    Move() : from(0), to(0) {}
    Move(Square f, Square t) : from(f.index), to(t.index) {}
    Move(Square f, Square t, PieceType promo) : from(f.index), to(t.index), promotion(promo) {}
    
    bool operator==(const Move& other) const {
        return from == other.from && to == other.to && promotion == other.promotion;
    }
    
    std::string to_string() const {
        std::string s = Square(from).to_string() + Square(to).to_string();
        if (promotion != PieceType::NONE) {
            const char* promo_chars = "nbrq";
            if (promotion < PieceType::NONE) {
                s += promo_chars[static_cast<int>(promotion)];
            }
        }
        return s;
    }
};

struct RootMove {
    Move move;
    std::string san;  // Standard Algebraic Notation
    int score;        // centipawns
    
    RootMove(Move m, const std::string& s, int sc) 
        : move(m), san(s), score(sc) {}
};

struct Piece {
    PieceType type;
    Color color;
    
    Piece() : type(PieceType::NONE), color(Color::WHITE) {}
    Piece(PieceType t, Color c) : type(t), color(c) {}
    
    bool is_empty() const { return type == PieceType::NONE; }
};

// === MCTS Types ===

using Reward = double;

enum class EdgeStatistic {
    UCB,
    VISITS,
    MEAN,
    PRIOR
};

// === Constants ===

constexpr int MAX_PLY = 128;
constexpr int MATE_SCORE = 40000;
constexpr int CENTIPAWN_SCALE = 100;

constexpr uint64_t RANK_1 = 0x00000000000000FFULL;
constexpr uint64_t RANK_8 = 0xFF00000000000000ULL;
constexpr uint64_t FILE_A = 0x0101010101010101ULL;
constexpr uint64_t FILE_H = 0x8080808080808080ULL;

// Direction constants for move generation
constexpr int NORTH = 8;
constexpr int SOUTH = -8;
constexpr int EAST = 1;
constexpr int WEST = -1;
