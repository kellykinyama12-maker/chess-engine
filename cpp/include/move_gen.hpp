#pragma once

#include "types.hpp"
#include "position.hpp"
#include <vector>
#include <cstdint>

class MoveGenerator {
public:
    // Generate pseudo-legal moves (may leave king in check)
    static std::vector<Move> generate_pseudolegal(const Position& pos);
    
    // Generate legal moves (filtered to not leave king in check)
    static std::vector<Move> generate_legal(const Position& pos);
    
    // Check if a move is legal
    static bool is_legal(const Position& pos, const Move& move);
    
    // Check if position is under attack
    static bool is_attacked_by(const Position& pos, Square sq, Color attacker);
    
    // Check if king is in check
    static bool is_in_check(const Position& pos, Color king_color);

private:
    // Helper methods for pawn moves
    static void generate_pawn_moves(
        const Position& pos,
        std::vector<Move>& moves,
        Color color
    );
    
    // Helper for knight moves
    static void generate_knight_moves(
        const Position& pos,
        std::vector<Move>& moves,
        Color color
    );
    
    // Helper for sliding piece moves (bishop, rook, queen)
    static void generate_sliding_moves(
        const Position& pos,
        std::vector<Move>& moves,
        Square sq,
        Color color,
        bool diagonal,
        bool straight
    );
    
    // Helper for king moves
    static void generate_king_moves(
        const Position& pos,
        std::vector<Move>& moves,
        Color color
    );
    
    // Direction tables
    static constexpr int pawn_dirs[2] = {8, -8};  // WHITE forward, BLACK backward
    static constexpr int knight_moves[8][2] = {
        {-2, -1}, {-2, 1}, {-1, -2}, {-1, 2},
        {1, -2}, {1, 2}, {2, -1}, {2, 1}
    };
    static constexpr int king_moves[8][2] = {
        {-1, -1}, {-1, 0}, {-1, 1}, {0, -1},
        {0, 1}, {1, -1}, {1, 0}, {1, 1}
    };
    static constexpr int bishop_dirs[4][2] = {{-1, -1}, {-1, 1}, {1, -1}, {1, 1}};
    static constexpr int rook_dirs[4][2] = {{-1, 0}, {0, -1}, {0, 1}, {1, 0}};
};
