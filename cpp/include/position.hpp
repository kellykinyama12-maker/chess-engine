#pragma once

#include "types.hpp"
#include <array>
#include <vector>
#include <string>
#include <cstdint>

// Forward declaration
class MoveGenerator;

class Position {
public:
    // Constructors
    Position();
    Position(const std::string& fen);
    
    // Board access
    Piece piece_at(Square sq) const;
    bool is_occupied(Square sq) const { return piece_at(sq).type != PieceType::NONE; }
    bool is_white(Square sq) const { return is_occupied(sq) && piece_at(sq).color == Color::WHITE; }
    bool is_black(Square sq) const { return is_occupied(sq) && piece_at(sq).color == Color::BLACK; }
    
    // Move execution
    bool make_move(const Move& move);
    void unmake_move();
    
    // Position properties
    Color side_to_move() const { return side; }
    uint64_t get_zobrist() const { return zobrist; }
    std::string fen() const;
    
    // Game state
    bool is_check() const { return in_check; }
    bool is_checkmate() const;
    bool is_stalemate() const;
    bool is_drawn() const;
    bool is_game_over() const { return is_checkmate() || is_stalemate() || is_drawn(); }
    
    // Move generation
    std::vector<Move> legal_moves() const;
    
    // ASCII representation
    std::string ascii() const;
    
    // History
    int halfmove_clock() const { return halfmoves; }
    int fullmove_number() const { return 1 + (fullmoves / 2); }

private:
    // Board representation: 8x8 array
    std::array<Piece, 64> board;
    
    // Position state
    Color side = Color::WHITE;
    uint64_t zobrist = 0;
    bool in_check = false;
    
    // Game state
    int halfmoves = 0;      // For 50-move rule
    int fullmoves = 0;      // Move counter (increases for Black only)
    
    // Castling rights and en passant
    bool castling[4] = {};  // [0]=White kingside, [1]=White queenside, [2]=Black kingside, [3]=Black queenside
    Square en_passant_square = Square(255);  // 255 = none
    
    // Move history for undo
    struct PositionHistory {
        Move move;
        Piece captured;
        bool castling[4];
        Square en_passant;
        int halfmoves_before;
        uint64_t zobrist_before;
    };
    std::vector<PositionHistory> history;
    
    // Helper methods
    void set_from_fen(const std::string& fen);
    void clear();
    void put_piece(Piece p, Square sq);
    void remove_piece(Square sq);
    void update_zobrist_piece(Piece p, Square sq);
    void update_zobrist_side();
    
    friend class MoveGenerator;
};
