#include "move_gen.hpp"
#include <algorithm>

// Define static direction tables (outside class)
constexpr int MoveGenerator::pawn_dirs[2];
constexpr int MoveGenerator::knight_moves[8][2];
constexpr int MoveGenerator::king_moves[8][2];
constexpr int MoveGenerator::bishop_dirs[4][2];
constexpr int MoveGenerator::rook_dirs[4][2];

std::vector<Move> MoveGenerator::generate_pseudolegal(const Position& pos) {
    std::vector<Move> moves;
    Color side = pos.side_to_move();
    
    // Generate pawn, knight, king moves once per color (not per piece)
    generate_pawn_moves(pos, moves, side);
    generate_knight_moves(pos, moves, side);
    generate_king_moves(pos, moves, side);
    
    // Generate sliding piece moves per piece (bishops/rooks/queens)
    for (Square sq(0); sq.index < 64; sq.index++) {
        Piece p = pos.piece_at(sq);
        if (p.type == PieceType::NONE || p.color != side) continue;
        
        switch (p.type) {
            case PieceType::BISHOP:
                generate_sliding_moves(pos, moves, sq, side, true, false);
                break;
            case PieceType::ROOK:
                generate_sliding_moves(pos, moves, sq, side, false, true);
                break;
            case PieceType::QUEEN:
                generate_sliding_moves(pos, moves, sq, side, true, true);
                break;
            default:
                break;
        }
    }
    
    return moves;
}

std::vector<Move> MoveGenerator::generate_legal(const Position& pos) {
    std::vector<Move> pseudolegal = generate_pseudolegal(pos);
    std::vector<Move> legal;
    
    for (const auto& move : pseudolegal) {
        if (is_legal(pos, move)) {
            legal.push_back(move);
        }
    }
    
    return legal;
}

bool MoveGenerator::is_legal(const Position& pos, const Move& move) {
    // Make a temporary position to check
    Position temp = pos;
    if (!temp.make_move(move)) return false;
    
    // Check if our king is in check
    return !is_in_check(temp, pos.side_to_move());
}

bool MoveGenerator::is_attacked_by(const Position& pos, Square sq, Color attacker) {
    int file = sq.index % 8;
    int rank = sq.index / 8;
    
    // Check pawn attacks
    if (attacker == Color::WHITE) {
        // White pawns attack diagonally upward
        if (rank > 0) {  // Not on rank 1
            // Left pawn (file - 1, rank - 1)
            if (file > 0) {
                Piece pawn_left = pos.piece_at(Square(sq.index - 9));
                if (pawn_left.type == PieceType::PAWN && pawn_left.color == Color::WHITE) return true;
            }
            // Right pawn (file + 1, rank - 1)
            if (file < 7) {
                Piece pawn_right = pos.piece_at(Square(sq.index - 7));
                if (pawn_right.type == PieceType::PAWN && pawn_right.color == Color::WHITE) return true;
            }
        }
    } else {
        // Black pawns attack diagonally downward
        if (rank < 7) {  // Not on rank 8
            // Left pawn (file - 1, rank + 1)
            if (file > 0) {
                Piece pawn_left = pos.piece_at(Square(sq.index + 7));
                if (pawn_left.type == PieceType::PAWN && pawn_left.color == Color::BLACK) return true;
            }
            // Right pawn (file + 1, rank + 1)
            if (file < 7) {
                Piece pawn_right = pos.piece_at(Square(sq.index + 9));
                if (pawn_right.type == PieceType::PAWN && pawn_right.color == Color::BLACK) return true;
            }
        }
    }
    
    // Check knight attacks
    for (const auto& offset : knight_moves) {
        int new_idx = sq.index + offset[0] + offset[1] * 8;
        if (new_idx < 0 || new_idx >= 64) continue;
        if ((sq.index % 8) + offset[0] < 0 || (sq.index % 8) + offset[0] >= 8) continue;
        
        Piece knight = pos.piece_at(Square(new_idx));
        if (knight.type == PieceType::KNIGHT && knight.color == attacker) return true;
    }
    
    // Check king attacks
    for (const auto& offset : king_moves) {
        int new_idx = sq.index + offset[0] + offset[1] * 8;
        if (new_idx < 0 || new_idx >= 64) continue;
        if ((sq.index % 8) + offset[0] < 0 || (sq.index % 8) + offset[0] >= 8) continue;
        
        Piece king = pos.piece_at(Square(new_idx));
        if (king.type == PieceType::KING && king.color == attacker) return true;
    }
    
    // Check sliding piece attacks (bishops, rooks, queens)
    // Bishop and Queen diagonals
    for (const auto& dir : bishop_dirs) {
        int new_idx = sq.index + dir[0] + dir[1] * 8;
        while (new_idx >= 0 && new_idx < 64 &&
               (sq.index % 8) + dir[0] >= 0 && (sq.index % 8) + dir[0] < 8) {
            Piece p = pos.piece_at(Square(new_idx));
            if (p.type != PieceType::NONE) {
                if (p.color == attacker && 
                    (p.type == PieceType::BISHOP || p.type == PieceType::QUEEN)) {
                    return true;
                }
                break;
            }
            new_idx += dir[0] + dir[1] * 8;
        }
    }
    
    // Rook and Queen straights
    for (const auto& dir : rook_dirs) {
        int new_idx = sq.index + dir[0] + dir[1] * 8;
        while (new_idx >= 0 && new_idx < 64) {
            Piece p = pos.piece_at(Square(new_idx));
            if (p.type != PieceType::NONE) {
                if (p.color == attacker && 
                    (p.type == PieceType::ROOK || p.type == PieceType::QUEEN)) {
                    return true;
                }
                break;
            }
            new_idx += dir[0] + dir[1] * 8;
        }
    }
    
    return false;
}

bool MoveGenerator::is_in_check(const Position& pos, Color king_color) {
    // Find king
    for (Square sq(0); sq.index < 64; sq.index++) {
        Piece p = pos.piece_at(sq);
        if (p.type == PieceType::KING && p.color == king_color) {
            Color enemy = (king_color == Color::WHITE) ? Color::BLACK : Color::WHITE;
            return is_attacked_by(pos, sq, enemy);
        }
    }
    return false;
}

void MoveGenerator::generate_pawn_moves(
    const Position& pos,
    std::vector<Move>& moves,
    Color color) {
    
    for (Square sq(0); sq.index < 64; sq.index++) {
        Piece p = pos.piece_at(sq);
        if (p.type != PieceType::PAWN || p.color != color) continue;
        
        int forward = (color == Color::WHITE) ? 8 : -8;
        int start_rank = (color == Color::WHITE) ? 1 : 6;
        int promotion_rank = (color == Color::WHITE) ? 7 : 0;
        
        // Single square forward
        Square forward_sq(sq.index + forward);
        if (forward_sq.index < 64 && !pos.is_occupied(forward_sq)) {
            if (static_cast<int>(forward_sq.rank()) == promotion_rank) {
                // Promotion moves
                moves.push_back(Move(sq, forward_sq, PieceType::KNIGHT));
                moves.push_back(Move(sq, forward_sq, PieceType::BISHOP));
                moves.push_back(Move(sq, forward_sq, PieceType::ROOK));
                moves.push_back(Move(sq, forward_sq, PieceType::QUEEN));
            } else {
                moves.push_back(Move(sq, forward_sq));
                
                // Double square from start
                if (static_cast<int>(sq.rank()) == start_rank) {
                    Square double_sq(sq.index + 2 * forward);
                    if (!pos.is_occupied(double_sq)) {
                        moves.push_back(Move(sq, double_sq));
                    }
                }
            }
        }
        
        // Captures (diagonal)
        int left = forward - 1;
        int right = forward + 1;
        
        // Left capture
        if (sq.index % 8 > 0) {  // Not on A-file
            Square cap_sq(sq.index + left);
            if (cap_sq.index < 64 && pos.is_occupied(cap_sq) && pos.piece_at(cap_sq).color != color) {
                if (static_cast<int>(cap_sq.rank()) == promotion_rank) {
                    moves.push_back(Move(sq, cap_sq, PieceType::KNIGHT));
                    moves.push_back(Move(sq, cap_sq, PieceType::BISHOP));
                    moves.push_back(Move(sq, cap_sq, PieceType::ROOK));
                    moves.push_back(Move(sq, cap_sq, PieceType::QUEEN));
                } else {
                    moves.push_back(Move(sq, cap_sq));
                }
            }
        }
        
        // Right capture
        if (sq.index % 8 < 7) {  // Not on H-file
            Square cap_sq(sq.index + right);
            if (cap_sq.index < 64 && pos.is_occupied(cap_sq) && pos.piece_at(cap_sq).color != color) {
                if (static_cast<int>(cap_sq.rank()) == promotion_rank) {
                    moves.push_back(Move(sq, cap_sq, PieceType::KNIGHT));
                    moves.push_back(Move(sq, cap_sq, PieceType::BISHOP));
                    moves.push_back(Move(sq, cap_sq, PieceType::ROOK));
                    moves.push_back(Move(sq, cap_sq, PieceType::QUEEN));
                } else {
                    moves.push_back(Move(sq, cap_sq));
                }
            }
        }
    }
}

void MoveGenerator::generate_knight_moves(
    const Position& pos,
    std::vector<Move>& moves,
    Color color) {
    
    for (Square sq(0); sq.index < 64; sq.index++) {
        Piece p = pos.piece_at(sq);
        if (p.type != PieceType::KNIGHT || p.color != color) continue;
        
        int file = sq.index % 8;
        int rank = sq.index / 8;
        
        for (const auto& offset : knight_moves) {
            int new_file = file + offset[1];
            int new_rank = rank + offset[0];
            
            // Check bounds
            if (new_file < 0 || new_file >= 8 || new_rank < 0 || new_rank >= 8) continue;
            
            Square dest(new_rank * 8 + new_file);
            Piece target = pos.piece_at(dest);
            
            // Can move if empty or enemy piece
            if (target.type == PieceType::NONE || target.color != color) {
                moves.push_back(Move(sq, dest));
            }
        }
    }
}

void MoveGenerator::generate_sliding_moves(
    const Position& pos,
    std::vector<Move>& moves,
    Square sq,
    Color color,
    bool diagonal,
    bool straight) {
    
    int file = sq.index % 8;
    int rank = sq.index / 8;
    
    // Direction arrays to try
    std::vector<std::pair<int, int>> directions;
    
    if (diagonal) {
        directions.push_back({-1, -1}); // up-left
        directions.push_back({-1, 1});  // up-right
        directions.push_back({1, -1});  // down-left
        directions.push_back({1, 1});   // down-right
    }
    
    if (straight) {
        directions.push_back({-1, 0});  // up
        directions.push_back({1, 0});   // down
        directions.push_back({0, -1});  // left
        directions.push_back({0, 1});   // right
    }
    
    for (const auto& dir : directions) {
        int new_rank = rank + dir.first;
        int new_file = file + dir.second;
        
        // Slide in this direction until blocked
        while (new_rank >= 0 && new_rank < 8 && new_file >= 0 && new_file < 8) {
            Square dest(new_rank * 8 + new_file);
            Piece target = pos.piece_at(dest);
            
            if (target.type == PieceType::NONE) {
                // Empty square, can move
                moves.push_back(Move(sq, dest));
            } else {
                // Occupied square
                if (target.color != color) {
                    // Enemy piece, can capture
                    moves.push_back(Move(sq, dest));
                }
                // Blocked, stop sliding in this direction
                break;
            }
            
            new_rank += dir.first;
            new_file += dir.second;
        }
    }
}

void MoveGenerator::generate_king_moves(
    const Position& pos,
    std::vector<Move>& moves,
    Color color) {
    
    // Find king position
    Square king_sq(255);  // Invalid
    for (Square sq(0); sq.index < 64; sq.index++) {
        Piece p = pos.piece_at(sq);
        if (p.type == PieceType::KING && p.color == color) {
            king_sq = sq;
            break;
        }
    }
    
    if (king_sq.index >= 64) return;  // No king found
    
    int file = king_sq.index % 8;
    int rank = king_sq.index / 8;
    
    // Normal king moves (8 adjacent squares)
    for (const auto& offset : king_moves) {
        int new_file = file + offset[1];
        int new_rank = rank + offset[0];
        
        if (new_file < 0 || new_file >= 8 || new_rank < 0 || new_rank >= 8) continue;
        
        Square dest(new_rank * 8 + new_file);
        Piece target = pos.piece_at(dest);
        
        if (target.type == PieceType::NONE || target.color != color) {
            moves.push_back(Move(king_sq, dest));
        }
    }
    
    // Castling (kingside and queenside)
    if (color == Color::WHITE) {
        // Kingside castling: e1 to g1
        if (king_sq.index == 4) {  // e1
            // Check castling rights and pieces
            bool can_castle = pos.piece_at(Square(5)).type == PieceType::NONE &&  // f1 empty
                             pos.piece_at(Square(6)).type == PieceType::NONE &&   // g1 empty
                             pos.piece_at(Square(7)).type == PieceType::ROOK &&   // h1 has rook
                             pos.piece_at(Square(7)).color == Color::WHITE;
            
            if (can_castle) {
                moves.push_back(Move(king_sq, Square(6)));  // e1 to g1
            }
            
            // Queenside castling: e1 to c1
            can_castle = pos.piece_at(Square(3)).type == PieceType::NONE &&   // d1 empty
                        pos.piece_at(Square(2)).type == PieceType::NONE &&    // c1 empty
                        pos.piece_at(Square(1)).type == PieceType::NONE &&    // b1 empty
                        pos.piece_at(Square(0)).type == PieceType::ROOK &&    // a1 has rook
                        pos.piece_at(Square(0)).color == Color::WHITE;
            
            if (can_castle) {
                moves.push_back(Move(king_sq, Square(2)));  // e1 to c1
            }
        }
    } else {
        // Black kingside castling: e8 to g8
        if (king_sq.index == 60) {  // e8
            bool can_castle = pos.piece_at(Square(61)).type == PieceType::NONE &&  // f8 empty
                             pos.piece_at(Square(62)).type == PieceType::NONE &&   // g8 empty
                             pos.piece_at(Square(63)).type == PieceType::ROOK &&   // h8 has rook
                             pos.piece_at(Square(63)).color == Color::BLACK;
            
            if (can_castle) {
                moves.push_back(Move(king_sq, Square(62)));  // e8 to g8
            }
            
            // Black queenside castling: e8 to c8
            can_castle = pos.piece_at(Square(59)).type == PieceType::NONE &&   // d8 empty
                        pos.piece_at(Square(58)).type == PieceType::NONE &&    // c8 empty
                        pos.piece_at(Square(57)).type == PieceType::NONE &&    // b8 empty
                        pos.piece_at(Square(56)).type == PieceType::ROOK &&    // a8 has rook
                        pos.piece_at(Square(56)).color == Color::BLACK;
            
            if (can_castle) {
                moves.push_back(Move(king_sq, Square(58)));  // e8 to c8
            }
        }
    }
}
