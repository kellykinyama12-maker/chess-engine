#include "position.hpp"
#include "zobrist.hpp"
#include "move_gen.hpp"
#include <sstream>
#include <cctype>
#include <algorithm>
#include <cstring>

Position::Position() {
    clear();
    // Start position
    set_from_fen("rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1");
}

Position::Position(const std::string& fen) {
    clear();
    set_from_fen(fen);
}

void Position::clear() {
    std::fill(board.begin(), board.end(), Piece());
    side = Color::WHITE;
    zobrist = 0;
    in_check = false;
    halfmoves = 0;
    fullmoves = 0;
    castling[0] = castling[1] = castling[2] = castling[3] = false;
    en_passant_square = Square(255);
    history.clear();
}

Piece Position::piece_at(Square sq) const {
    if (sq.index >= 64) return Piece();
    return board[sq.index];
}

void Position::put_piece(Piece p, Square sq) {
    if (sq.index >= 64) return;
    board[sq.index] = p;
    update_zobrist_piece(p, sq);
}

void Position::remove_piece(Square sq) {
    if (sq.index >= 64) return;
    Piece p = board[sq.index];
    board[sq.index] = Piece();
    update_zobrist_piece(p, sq);
}

void Position::update_zobrist_piece(Piece p, Square sq) {
    if (p.type != PieceType::NONE) {
        zobrist ^= Zobrist::piece(p, sq);
    }
}

void Position::update_zobrist_side() {
    zobrist ^= Zobrist::side();
}

void Position::set_from_fen(const std::string& fen) {
    clear();
    
    std::istringstream iss(fen);
    std::string piece_placement, active_color, castling_rights, ep_square, halfmove, fullmove;
    
    if (!(iss >> piece_placement >> active_color >> castling_rights >> ep_square >> halfmove >> fullmove)) {
        // Invalid FEN, use starting position
        set_from_fen("rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1");
        return;
    }
    
    // Parse piece placement
    int sq_index = 56;  // Start from a8
    for (char c : piece_placement) {
        if (c == '/') {
            sq_index -= 16;  // Move to next rank
        } else if (std::isdigit(c)) {
            sq_index += (c - '0');  // Skip empty squares
        } else {
            Piece p;
            p.color = std::isupper(c) ? Color::WHITE : Color::BLACK;
            char piece_char = std::toupper(c);
            
            switch (piece_char) {
                case 'P': p.type = PieceType::PAWN; break;
                case 'N': p.type = PieceType::KNIGHT; break;
                case 'B': p.type = PieceType::BISHOP; break;
                case 'R': p.type = PieceType::ROOK; break;
                case 'Q': p.type = PieceType::QUEEN; break;
                case 'K': p.type = PieceType::KING; break;
                default: continue;
            }
            
            put_piece(p, Square(sq_index));
            sq_index++;
        }
    }
    
    // Parse side to move
    side = (active_color == "w") ? Color::WHITE : Color::BLACK;
    if (side == Color::BLACK) update_zobrist_side();
    
    // Parse castling rights
    castling[0] = castling[1] = castling[2] = castling[3] = false;
    for (char c : castling_rights) {
        switch (c) {
            case 'K': castling[0] = true; break;
            case 'Q': castling[1] = true; break;
            case 'k': castling[2] = true; break;
            case 'q': castling[3] = true; break;
        }
    }
    zobrist ^= Zobrist::castling_rights(castling[0], castling[1], castling[2], castling[3]);
    
    // Parse en passant square
    if (ep_square != "-") {
        en_passant_square = Square(
            static_cast<File>(ep_square[0] - 'a'),
            static_cast<Rank>(ep_square[1] - '1')
        );
        zobrist ^= Zobrist::en_passant(en_passant_square);
    }
    
    // Parse halfmove clock
    halfmoves = std::stoi(halfmove);
    
    // Parse fullmove number
    fullmoves = (std::stoi(fullmove) - 1) * 2;
    if (side == Color::BLACK) fullmoves++;
    
    // Check detection
    in_check = MoveGenerator::is_in_check(*this, side);
}

bool Position::make_move(const Move& move) {
    // Save current state
    PositionHistory hist;
    hist.move = move;
    hist.captured = piece_at(Square(move.to));
    std::copy(castling, castling + 4, hist.castling);
    hist.en_passant = en_passant_square;
    hist.halfmoves_before = halfmoves;
    hist.zobrist_before = zobrist;
    
    // Update en passant
    zobrist ^= Zobrist::en_passant(en_passant_square);
    en_passant_square = Square(255);
    
    // Move piece
    Piece p = piece_at(Square(move.from));
    if (p.type == PieceType::NONE) return false;
    
    remove_piece(Square(move.from));
    remove_piece(Square(move.to));  // Remove captured piece if any
    
    // Handle promotion
    if (move.promotion != PieceType::NONE) {
        p.type = move.promotion;
    }
    
    put_piece(p, Square(move.to));
    
    // Handle pawn moves for en passant and halfmove clock
    if (p.type == PieceType::PAWN) {
        halfmoves = 0;
        
        // Check for en passant pawn capture
        if (move.from % 8 != move.to % 8 && hist.captured.type == PieceType::NONE) {
            // En passant capture
            Square captured_sq(move.to + (side == Color::WHITE ? -8 : 8));
            remove_piece(captured_sq);
        }
        
        // Set en passant square for double push
        int from_rank = move.from / 8;
        int to_rank = move.to / 8;
        if ((p.color == Color::WHITE && from_rank == 1 && to_rank == 3) ||
            (p.color == Color::BLACK && from_rank == 6 && to_rank == 4)) {
            en_passant_square = Square((move.from + move.to) / 2);
            zobrist ^= Zobrist::en_passant(en_passant_square);
        }
    } else {
        halfmoves++;
    }
    
    // Handle captures for halfmove clock
    if (hist.captured.type != PieceType::NONE) {
        halfmoves = 0;
    }
    
    // Handle castling
    if (p.type == PieceType::KING) {
        if (p.color == Color::WHITE) {
            castling[0] = castling[1] = false;
        } else {
            castling[2] = castling[3] = false;
        }
    } else if (p.type == PieceType::ROOK) {
        if (p.color == Color::WHITE) {
            if (move.from == 0) castling[1] = false;
            if (move.from == 7) castling[0] = false;
        } else {
            if (move.from == 56) castling[3] = false;
            if (move.from == 63) castling[2] = false;
        }
    }
    
    // Update zobrist for castling
    zobrist ^= Zobrist::castling_rights(castling[0], castling[1], castling[2], castling[3]);
    
    // Switch sides
    side = (side == Color::WHITE) ? Color::BLACK : Color::WHITE;
    fullmoves++;
    update_zobrist_side();
    
    history.push_back(hist);
    
    // Check detection
    in_check = MoveGenerator::is_in_check(*this, side);
    
    return true;
}

void Position::unmake_move() {
    if (history.empty()) return;
    
    PositionHistory& hist = history.back();
    
    // Restore position state
    side = (side == Color::WHITE) ? Color::BLACK : Color::WHITE;
    fullmoves--;
    zobrist = hist.zobrist_before;
    halfmoves = hist.halfmoves_before;
    
    // Restore castling rights
    std::copy(hist.castling, hist.castling + 4, castling);
    
    // Restore en passant square
    en_passant_square = hist.en_passant;
    
    // Undo piece movement
    Piece p = piece_at(Square(hist.move.to));
    if (hist.move.promotion != PieceType::NONE) {
        p.type = PieceType::PAWN;
    }
    
    remove_piece(Square(hist.move.to));
    put_piece(p, Square(hist.move.from));
    
    // Restore captured piece
    if (hist.captured.type != PieceType::NONE) {
        put_piece(hist.captured, Square(hist.move.to));
    } else if (p.type == PieceType::PAWN && 
               hist.move.from % 8 != hist.move.to % 8) {
        // Restore en passant captured pawn
        Square captured_sq(hist.move.to + (side == Color::WHITE ? 8 : -8));
        put_piece(Piece(PieceType::PAWN, side == Color::WHITE ? Color::BLACK : Color::WHITE), captured_sq);
    }
    
    history.pop_back();
    
    // Check detection
    in_check = MoveGenerator::is_in_check(*this, side);
}

std::string Position::fen() const {
    std::ostringstream oss;
    
    // Piece placement
    for (int rank = 7; rank >= 0; rank--) {
        int empty_count = 0;
        for (int file = 0; file < 8; file++) {
            Piece p = board[rank * 8 + file];
            if (p.type == PieceType::NONE) {
                empty_count++;
            } else {
                if (empty_count > 0) {
                    oss << empty_count;
                    empty_count = 0;
                }
                const char* piece_chars = "pnbrqk";
                char c = piece_chars[static_cast<int>(p.type)];
                if (p.color == Color::WHITE) c = std::toupper(c);
                oss << c;
            }
        }
        if (empty_count > 0) oss << empty_count;
        if (rank > 0) oss << "/";
    }
    
    oss << (side == Color::WHITE ? " w " : " b ");
    
    // Castling rights
    if (!castling[0] && !castling[1] && !castling[2] && !castling[3]) {
        oss << "-";
    } else {
        if (castling[0]) oss << "K";
        if (castling[1]) oss << "Q";
        if (castling[2]) oss << "k";
        if (castling[3]) oss << "q";
    }
    oss << " ";
    
    // En passant
    if (en_passant_square.index < 64) {
        oss << en_passant_square.to_string();
    } else {
        oss << "-";
    }
    oss << " ";
    
    // Halfmove and fullmove
    oss << halfmoves << " " << (1 + fullmoves / 2);
    
    return oss.str();
}

std::vector<Move> Position::legal_moves() const {
    return MoveGenerator::generate_legal(*this);
}

std::string Position::ascii() const {
    std::ostringstream oss;
    oss << "\n  a b c d e f g h\n";
    for (int rank = 7; rank >= 0; rank--) {
        oss << (rank + 1) << " ";
        for (int file = 0; file < 8; file++) {
            Piece p = board[rank * 8 + file];
            char c = ' ';
            if (p.type != PieceType::NONE) {
                const char* piece_chars = "pnbrqk";
                c = piece_chars[static_cast<int>(p.type)];
                if (p.color == Color::WHITE) c = std::toupper(c);
            }
            oss << c << " ";
        }
        oss << (rank + 1) << "\n";
    }
    oss << "  a b c d e f g h\n";
    return oss.str();
}

bool Position::is_checkmate() const {
    return in_check && legal_moves().empty();
}

bool Position::is_stalemate() const {
    return !in_check && legal_moves().empty();
}

bool Position::is_drawn() const {
    // 50-move rule
    if (halfmoves >= 100) return true;
    
    // TODO: Threefold repetition (needs move history)
    
    return false;
}
