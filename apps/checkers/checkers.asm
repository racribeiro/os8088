; =============================================================================
; CHECKERS -- local two-player draughts on an 8 x 8 board.
; Click a piece, then a legal destination. White moves up; black down.
; Men promote at the far rank. Captures are supported (including kings).
; =============================================================================

%include "os88api.inc"

    OS88_HEADER 'CHECKERS', ck_entry, 1

; The board itself, 8x8 cells at 2x2 pixels each: black squares are data,
; white squares are the opaque mask's underlay.
    OS88_ICON16
    dw 0xFFFF,0xFFFF,0xFFFF,0xFFFF,0xFFFF,0xFFFF,0xFFFF,0xFFFF
    dw 0xFFFF,0xFFFF,0xFFFF,0xFFFF,0xFFFF,0xFFFF,0xFFFF,0xFFFF
    dw 0xCCCC,0xCCCC,0x3333,0x3333,0xCCCC,0xCCCC,0x3333,0x3333
    dw 0xCCCC,0xCCCC,0x3333,0x3333,0xCCCC,0xCCCC,0x3333,0x3333
    OS88_ICON16_END

CK_W equ 550
CK_H equ 350
CK_X equ 12
CK_Y equ 38                    ; leave a clear capture band above the board
CK_SQ equ 32
CK_SEL equ 0FFh
CK_EMPTY equ 0
CK_RED equ 1
CK_BLACK equ 2
CK_RKING equ 3
CK_BKING equ 4
CK_MODE_HUMAN equ 0
CK_MODE_ROBOT equ 1
CK_MODE_AUTO equ 2
CK_MODE_WHITE_ROBOT equ 3

ck_entry:
    push ax
    push cx
    push si
    mov si, ck_tpl
    call OSAPI_WM_CREATE
    jc .out
    mov si, ck_menus
    call OSAPI_MENU_SET
    mov si, ck_about
    call OSAPI_ABOUT_SET
    mov byte [ck_robot], CK_MODE_HUMAN
    mov ax, ck_ontimer
    call OSAPI_WM_ONTIMER
    mov byte [ck_selected], CK_SEL
    call ck_reset
.out:
    pop si
    pop cx
    pop ax
    ret

; W_PAINT: the manager has white-filled the content and holds gfx lock.
ck_paint:
    push ax
    push bx
    push cx
    push dx
    push si
    push di
    mov bx, si
    call OSAPI_WM_CLIP_SET
    jc .out
    mov bx, si
    call OSAPI_WM_CONTENT
    add ax, CK_X
    mov [ck_ox], ax
    add dx, CK_Y
    mov [ck_oy], dx
    call ck_board
    call ck_captures
    call ck_status
    mov bx, si
    mov ax, 4                     ; ~0.22 s between robot turns
    call OSAPI_WM_TIMER             ; one-second clock; W_PAINT re-arms it
.out:
    pop di
    pop si
    pop dx
    pop cx
    pop bx
    pop ax
    ret

; Draw all 64 squares then their pieces.  Square colour is derived from the
; index parity: in a row, it alternates; the next row starts reversed.
ck_board:
    mov byte [ck_preview_active], 0
    mov byte [ck_preview_force], 0
    call ck_any_capture
    jnc .cache
    mov byte [ck_preview_force], 1
.cache:
    mov byte [ck_preview_active], 1
.start:
    mov al, 70h                     ; repaint: capture rule is now cached
    call ck_trace
    mov byte [ck_i], 0
.square:
    mov al, [ck_i]
    cmp al, 64
    jae .out
    call ck_cell_xy
    mov [ck_px], ax
    mov [ck_py], bx
    mov al, [ck_i]
    mov ah, al
    and al, 7
    mov cl, 3
    shr ah, cl
    xor al, ah
    test al, 1
    jz .light
    mov al, CDGRAY
    jmp short .fill
.light:
    mov al, CLGRAY
.fill:
    call OSAPI_SET_COLOR
    mov ax, [ck_px]
    mov bx, [ck_py]
    mov cx, ax
    add cx, CK_SQ-1
    mov dx, bx
    add dx, CK_SQ-1
    call OSAPI_GFX_FILL
    mov al, [ck_i]
    cmp al, [ck_selected]
    jne .piece
    mov al, CYELLOW
    call OSAPI_SET_COLOR
    mov ax, [ck_px]
    mov bx, [ck_py]
    mov cx, ax
    add cx, CK_SQ-1
    mov dx, bx
    add dx, CK_SQ-1
    call OSAPI_GFX_FRAME
.piece:
    mov al, [ck_i]
    cmp byte [ck_selected], CK_SEL
    jne .one_piece
    call ck_any_piece_target
    jmp short .marker
.one_piece:
    call ck_target_legal
.marker:
    jnc .draw_piece
    mov al, 6                       ; CGA brown/orange: global legal move
    call OSAPI_SET_COLOR
    mov ax, [ck_px]
    add ax, 12
    mov bx, [ck_py]
    add bx, 12
    mov cx, ax
    add cx, 7
    mov dx, bx
    add dx, 7
    call OSAPI_GFX_FILL             ; legal-destination marker
.draw_piece:
    xor bx, bx
    mov bl, [ck_i]
    mov al, [ck_board_data+bx]
    or al, al
    jz .next
    mov [ck_piece_v], al
    mov ax, [ck_px]
    mov bx, [ck_py]
    call ck_piece
.next:
    inc byte [ck_i]
    jmp .square
.out:
    mov byte [ck_preview_active], 0
    mov al, 71h                     ; repaint completed
    call ck_trace
    ret

; AL=destination.  CF=1 if any active-side piece can legally reach it.
; Used only for the orange turn preview; ck_target_legal remains the sole
; move rule implementation.
ck_any_piece_target:
    push bx
    push cx
    push dx
    push si
    mov [ck_preview_dst], al
    mov byte [ck_preview_src], 0
.scan:
    mov al, [ck_preview_src]
    cmp al, 64
    jae .no
    xor bx, bx
    mov bl, al
    mov al, [ck_board_data+bx]
    call ck_is_own
    jnc .next
    mov al, [ck_preview_src]
    mov [ck_selected], al
    mov al, [ck_preview_dst]
    call ck_target_legal
    jc .yes
.next:
    inc byte [ck_preview_src]
    jmp short .scan
.yes:
    stc
    jmp short .out
.no:
    clc
.out:
    mov byte [ck_selected], CK_SEL
    pop si
    pop dx
    pop cx
    pop bx
    ret

; in AL=index; out AX=x, BX=y (top-left of its square).
ck_cell_xy:
    xor ah, ah
    mov bx, ax
    and ax, 7
    mov cl, 5
    shl ax, cl
    add ax, [ck_ox]
    mov cl, 3
    shr bx, cl
    mov cl, 5
    shl bx, cl
    add bx, [ck_oy]
    ret

; AX/BX=square origin, [ck_piece_v]=piece.  A single masked 16px sprite gives
; each man a stable two-colour disc: its mask is the rim and its data is the
; centre.  This avoids every scanline sharing the board's working coordinates.
ck_piece:
    mov cx, ax
    add cx, 8
    mov dx, bx
    add dx, 8
    mov al, [ck_piece_v]
    cmp al, CK_RED
    je .white
    cmp al, CK_RKING
    je .white
    mov ax, (CBLACK << 8) | CWHITE ; black centre, white rim
    jmp short .draw
.white:
    mov ax, (CWHITE << 8) | CBLACK ; white centre, black rim
.draw:
    call OSAPI_ICON_PEN
    mov si, ck_piece_sprite
    call OSAPI_ICON_DRAW
.king:
    mov al, [ck_piece_v]
    cmp al, CK_RKING
    je .crown
    cmp al, CK_BKING
    jne .out
.crown:
    mov al, CYELLOW
    call OSAPI_SET_COLOR
    mov ax, cx
    add ax, 4
    mov bx, dx
    add bx, 4
    mov cx, ax
    add cx, 7
    mov dx, bx
    add dx, 7
    call OSAPI_GFX_FRAME
.out:
    ret

ck_status:
    ; The board is completely opaque and redraws itself.  Only this small text
    ; area needs erasing before a turn label changes length; never white-fill
    ; the entire window just to repaint a move.
    mov al, CWHITE
    call OSAPI_SET_COLOR
    mov ax, [ck_ox]
    add ax, 272
    mov bx, [ck_oy]
    add bx, 8
    mov cx, ax
    add cx, 260                    ; includes the replay button's right edge
    mov dx, bx
    add dx, 240                    ; erase a prior game-over panel on reset
    call OSAPI_GFX_FILL
    mov si, ck_s_red
    cmp byte [ck_game_over], 0
    je .turn
    mov si, ck_s_white_wins
    cmp byte [ck_winner], CK_RED
    je .draw
    mov si, ck_s_black_wins
    jmp short .draw
.turn:
    cmp byte [ck_turn], CK_RED
    je .draw
    mov si, ck_s_black
.draw:
    mov cx, [ck_ox]
    add cx, 280
    mov dx, [ck_oy]
    add dx, 18
    mov ax, (CWHITE << 8) | CBLACK
    call OSAPI_FONT_RUN
    cmp byte [ck_game_over], 0
    je .after_win
    ; Bold bitmap heading and a clearly framed replay control.
    inc cx
    mov ax, (CWHITE << 8) | CBLACK
    call OSAPI_FONT_RUN
    mov al, CWHITE
    call OSAPI_SET_COLOR
    mov ax, [ck_ox]
    add ax, 400
    mov bx, [ck_oy]
    add bx, 210
    mov cx, ax
    add cx, 119
    mov dx, bx
    add dx, 20
    call OSAPI_GFX_FILL
    mov al, CBLACK
    call OSAPI_SET_COLOR
    mov ax, [ck_ox]
    add ax, 400
    mov bx, [ck_oy]
    add bx, 210
    mov cx, ax
    add cx, 119
    mov dx, bx
    add dx, 20
    call OSAPI_GFX_FRAME
    mov cx, [ck_ox]
    add cx, 420
    mov dx, [ck_oy]
    add dx, 216
    mov si, ck_s_play_again
    mov ax, (CWHITE << 8) | CBLACK
    call OSAPI_FONT_RUN
.after_win:
    cmp byte [ck_game_over], 0
    jne .no_hint
    cmp byte [ck_robot], CK_MODE_AUTO
    je .no_hint
    cmp byte [ck_robot], CK_MODE_ROBOT
    jne .hint
    cmp byte [ck_turn], CK_BLACK
    je .no_hint
.hint:
    mov si, ck_s_hint
    add dx, 18
    mov ax, (CWHITE << 8) | CBLACK
    call OSAPI_FONT_RUN
.no_hint:
    call ck_debug_draw
    call ck_clock_draw
    ret

; Diagnostic breadcrumb: D <sequence> <stage>, hexadecimal so it costs no
; division on an 8088.  Report this value if the UI stops responding.
ck_debug_draw:
    mov ax, [ck_trace_seq]
    mov di, ck_trace_buf+2
    call ck_hex_word
    mov al, [ck_trace_stage]
    mov di, ck_trace_buf+7
    call ck_hex_byte
    mov cx, [ck_ox]
    add cx, 280
    mov dx, [ck_oy]
    add dx, 270
    mov si, ck_trace_buf
    mov ax, (CWHITE << 8) | CBLACK
    call OSAPI_FONT_RUN
    ret

; AL is a stage code; every important state transition calls this.
ck_trace:
    inc word [ck_trace_seq]
    mov [ck_trace_stage], al
    ret

ck_hex_word:
    push cx
    mov cl, 12
.n:
    mov bx, ax
    shr bx, cl
    and bx, 15                     ; the table index must not retain BH
    mov bl, [ck_hex+bx]
    mov [di], bl
    inc di
    sub cl, 4
    jns .n
    pop cx
    ret
ck_hex_byte:
    push bx
    push ax
    push cx
    mov bx, ck_hex
    mov ah, al
    mov cl, 4
    shr al, cl
    and al, 15
    xlatb
    mov [di], al
    inc di
    mov al, ah
    and al, 15
    xlatb
    mov [di], al
    pop cx
    pop ax
    pop bx
    ret

; W_ONCLICK. CX/DX are absolute screen coordinates.
ck_onclick:
    mov al, 10h
    call ck_trace
    call ck_clock_sync
    cmp byte [ck_game_over], 0
    je .board
    push ax
    push bx
    push cx
    push dx
    push si
    mov bx, si
    call OSAPI_WM_CONTENT
    add ax, CK_X
    mov [ck_ox], ax
    add dx, CK_Y
    mov [ck_oy], dx
    pop si
    pop dx
    pop cx
    pop bx
    pop ax
    cmp byte [ck_game_over], 0
    je .board
    ; Native-looking app button, handled by its screen rectangle.
    cmp cx, [ck_ox]
    jl .out
    cmp dx, [ck_oy]
    jl .out
    sub cx, [ck_ox]
    sub dx, [ck_oy]
    cmp cx, 400
    jl .out
    cmp cx, 520
    jae .out
    cmp dx, 210
    jl .out
    cmp dx, 231
    jae .out
    call ck_start_game
    ret
.board:
    cmp cx, [ck_ox]
    jl .out
    cmp dx, [ck_oy]
    jl .out
    sub cx, [ck_ox]
    sub dx, [ck_oy]
    cmp cx, 256
    jae .out
    cmp dx, 256
    jae .out
    ; Board storage is always index = row * 8 + column.  Keep this conversion
    ; in one helper: swapping the two here transposes clicks while drawing and
    ; move validation still use the normal row-major board.
    call ck_point_index
    mov [ck_target], al
    mov al, 11h
    call ck_trace
    cmp byte [ck_selected], CK_SEL
    jne .move
    call ck_select
    jmp short .redraw
.move:
    mov al, [ck_target]
    cmp al, [ck_selected]
    jne .try
    mov byte [ck_selected], CK_SEL
    jmp short .redraw
.try:
    call ck_try_move
.redraw:
    call ck_repaint
.out:
    ret

; Select only a piece belonging to the player whose turn it is.
ck_select:
    mov al, 20h
    call ck_trace
    xor bx, bx
    mov bl, [ck_target]
    mov al, [ck_board_data+bx]
    cmp al, [ck_turn]
    je .yes
    cmp byte [ck_turn], CK_RED
    jne .black
    cmp al, CK_RKING
    jne .clear
    jmp short .yes
.black:
    cmp al, CK_BKING
    jne .clear
.yes:
    mov al, [ck_target]
    mov al, 21h
    call ck_trace
    mov al, [ck_target]
    call ck_piece_has_move
    mov al, 22h
    call ck_trace
    jc .select
.clear:
    mov byte [ck_selected], CK_SEL
    ret
.select:
    mov al, [ck_target]
    mov [ck_selected], al
.out:
    ret

; Validate a diagonal single-step or capture. Men move toward the opponent;
; kings move both ways. A successful capture removes the jumped enemy.
ck_try_move:
    mov al, 30h
    call ck_trace
    xor bx, bx
    mov bl, [ck_selected]
    mov al, [ck_board_data+bx]
    mov [ck_piece_v], al
    cmp byte [ck_preview_active], 0
    je .live_force
    mov al, [ck_preview_force]
    mov [ck_force], al
    jmp short .force_done
.live_force:
    call ck_any_capture
    mov byte [ck_force], 0
    jnc .force_done
    mov byte [ck_force], 1
.force_done:
    xor bx, bx
    mov bl, [ck_target]
    cmp byte [ck_board_data+bx], CK_EMPTY
    jne .out
    mov al, [ck_target]
    call ck_dark_square
    jz .out                         ; pieces never occupy a light square
    mov al, [ck_selected]
    call ck_rowcol
    mov [ck_sr], ah
    mov [ck_sc], al
    mov al, [ck_target]
    call ck_rowcol
    mov [ck_dr], ah
    mov [ck_dc], al
    ; signed row and col deltas in bytes
    mov al, [ck_dr]
    sub al, [ck_sr]
    mov [ck_drow], al
    mov al, [ck_dc]
    sub al, [ck_sc]
    mov [ck_dcol], al
    mov al, [ck_drow]
    call ck_abs
    cmp al, 1
    je .step
    cmp al, 2
    jne .out
    mov byte [ck_jump], 1
    jmp short .rdir
.step:
    mov byte [ck_jump], 0
    mov al, [ck_dcol]
    call ck_abs
    cmp al, 1
    jne .out
    jmp short .direction
.rdir:
    mov al, [ck_dcol]
    call ck_abs
    cmp al, 2
    jne .out
.direction:
    cmp byte [ck_jump], 0
    jne .legal                       ; men may capture in either direction
    ; A man may only move forward; a king may use either row direction.
    mov al, [ck_piece_v]
    cmp al, CK_RKING
    je .legal
    cmp al, CK_BKING
    je .legal
    cmp al, CK_RED
    jne .blackdir
    cmp byte [ck_drow], 0
    jge .out
    jmp short .legal
.blackdir:
    cmp byte [ck_drow], 0
    jle .out
.legal:
    cmp byte [ck_jump], 0
    jne .capture_check
    cmp byte [ck_force], 0
    jne .out                         ; capture is mandatory
    jmp short .apply
.capture_check:
    ; midpoint must contain the other colour
    mov al, [ck_sr]
    add al, [ck_dr]
    shr al, 1
    mov ah, al
    mov al, [ck_sc]
    add al, [ck_dc]
    shr al, 1
    mov cl, 3
    shl ah, cl
    add al, ah
    xor bx, bx
    mov bl, al
    mov al, [ck_board_data+bx]
    or al, al
    jz .out
    cmp byte [ck_turn], CK_RED
    jne .mustred
    cmp al, CK_RED
    je .out
    cmp al, CK_RKING
    je .out
    jmp short .capture
.mustred:
    cmp al, CK_BLACK
    je .out
    cmp al, CK_BKING
    je .out
.capture:
    mov al, 40h
    call ck_trace
    cmp byte [ck_turn], CK_RED
    jne .black_took
    inc byte [ck_cap_white]
    jmp short .counted
.black_took:
    inc byte [ck_cap_black]
.counted:
    mov byte [ck_board_data+bx], CK_EMPTY
.apply:
    mov al, 50h
    call ck_trace
    xor bx, bx
    mov bl, [ck_selected]
    mov byte [ck_board_data+bx], CK_EMPTY
    xor bx, bx
    mov bl, [ck_target]
    mov al, [ck_piece_v]
    mov byte [ck_promoted], 0
    ; promotion when a man reaches its far edge
    cmp al, CK_RED
    jne .blackprom
    cmp byte [ck_dr], 0
    jne .store
    mov al, CK_RKING
    mov byte [ck_promoted], 1
    jmp short .store
.blackprom:
    cmp al, CK_BLACK
    jne .store
    cmp byte [ck_dr], 7
    jne .store
    mov al, CK_BKING
    mov byte [ck_promoted], 1
.store:
    mov [ck_board_data+bx], al
    ; A capture can end the game before a multi-jump is considered.
    cmp byte [ck_jump], 0
    je .after_store
    mov al, [ck_turn]
    xor al, 3
    call ck_side_has_piece
    jc .after_store
    mov al, [ck_turn]
    call ck_end_game
    ret
.after_store:
    cmp byte [ck_jump], 0
    je .finish
    cmp byte [ck_promoted], 0
    jne .finish                      ; crowning ends a capture sequence
    mov al, [ck_target]
    call ck_piece_has_capture
    jnc .finish
    mov al, [ck_target]
    mov [ck_selected], al            ; same piece must continue capturing
    ret
.finish:
    mov al, 60h
    call ck_trace
    mov byte [ck_selected], CK_SEL
    xor byte [ck_turn], 3           ; 1 <-> 2
    mov al, [ck_turn]
    call ck_side_has_piece
    jc .have_piece
    mov al, [ck_turn]
    xor al, 3
    call ck_end_game
    ret
.have_piece:
    call ck_side_has_move
    jc .can_move
    xor byte [ck_turn], 3           ; no legal destination: pass the turn
.can_move:
    cmp byte [ck_robot], CK_MODE_HUMAN
    je .out
    cmp byte [ck_ai_busy], 0
    jne .out
    cmp byte [ck_robot], CK_MODE_ROBOT
    je .black_robot
    cmp byte [ck_robot], CK_MODE_WHITE_ROBOT
    je .white_robot
    jmp short .robot
.black_robot:
    cmp byte [ck_turn], CK_BLACK
    jne .out
.robot:
    call ck_robot_play
    jmp short .out
.white_robot:
    cmp byte [ck_turn], CK_RED
    jne .out
    call ck_robot_play
.out:
    ret

; AL=CK_RED/CK_BLACK. CF=1 when that side still has a man or king.
ck_side_has_piece:
    push bx
    push cx
    mov cl, al
    xor bx, bx
.scan:
    cmp bx, 64
    jae .no
    mov al, [ck_board_data+bx]
    cmp al, cl
    je .yes
    cmp cl, CK_RED
    jne .black
    cmp al, CK_RKING
    je .yes
    jmp short .next
.black:
    cmp al, CK_BKING
    je .yes
.next:
    inc bx
    jmp short .scan
.yes:
    stc
    jmp short .out
.no:
    clc
.out:
    pop cx
    pop bx
    ret

; CF=1 if the side currently in [ck_turn] owns any legal move.
ck_side_has_move:
    push ax
    push bx
    push si
    xor si, si
.scan:
    cmp si, 64
    jae .no
    mov al, [ck_board_data+si]
    call ck_is_own
    jnc .next
    mov ax, si
    call ck_piece_has_move
    jc .yes
.next:
    inc si
    jmp short .scan
.yes:
    stc
    jmp short .out
.no:
    clc
.out:
    pop si
    pop bx
    pop ax
    ret

; AL is the winner side.  It freezes further clicks and the clock.
ck_end_game:
    mov [ck_winner], al
    mov byte [ck_game_over], 1
    mov byte [ck_selected], CK_SEL
    ret

; AL=index -> AL=column, AH=row.
ck_rowcol:
    mov ah, al
    and al, 7
    mov cl, 3
    shr ah, cl
    ret

; CX/DX are board-relative pixels (both already known to be below 256).
; Return AL = row * 8 + column.  This is the sole pixel-to-board conversion;
; ck_cell_xy is its inverse and ck_rowcol is the index-level decomposition.
ck_point_index:
    mov bx, cx                      ; column before CL is used as a shift count
    mov ax, dx                      ; row
    mov cl, 5
    shr ax, cl
    add ax, ax
    add ax, ax
    add ax, ax                      ; row * 8
    shr bx, cl                      ; column
    add ax, bx
    ret
ck_abs:
    test al, al
    jns .out
    neg al
.out:
    ret

; AL=index -> ZF=0 for a dark (playable) square, ZF=1 for a light one.
ck_dark_square:
    mov ah, al
    and al, 7
    mov cl, 3
    shr ah, cl
    xor al, ah
    test al, 1
    ret

; AL=destination index.  CF=1 means the currently selected man may be shown
; as moving there under the active mandatory-capture rule.  This is a pure
; preview: it never changes the board or the selected piece.
ck_target_legal:
    push bx
    push cx
    push dx
    push si
    mov ah, [ck_target]
    mov [ck_saved_target], ah       ; painting must not change click state
    cmp byte [ck_selected], CK_SEL
    je .no
    mov [ck_target], al
    xor bx, bx
    mov bl, al
    cmp byte [ck_board_data+bx], CK_EMPTY
    jne .no
    call ck_dark_square
    jz .no
    xor bx, bx
    mov bl, [ck_selected]
    mov al, [ck_board_data+bx]
    mov [ck_piece_v], al
    ; Board painting calls this once per square.  Reuse the mandatory-capture
    ; result computed by ck_board instead of scanning all 64 squares 64 times.
    cmp byte [ck_preview_active], 0
    je .live_force
    mov al, [ck_preview_force]
    mov [ck_force], al
    jmp short .force_done
.live_force:
    call ck_any_capture
    mov byte [ck_force], 0
    jnc .force_done
    mov byte [ck_force], 1
.force_done:
    mov al, [ck_selected]
    call ck_rowcol
    mov [ck_sr], ah
    mov [ck_sc], al
    mov al, [ck_target]
    call ck_rowcol
    mov [ck_dr], ah
    mov [ck_dc], al
    mov al, [ck_dr]
    sub al, [ck_sr]
    mov [ck_drow], al
    mov al, [ck_dc]
    sub al, [ck_sc]
    mov [ck_dcol], al
    mov al, [ck_drow]
    call ck_abs
    cmp al, 1
    je .step
    cmp al, 2
    jne .no
    mov al, [ck_dcol]
    call ck_abs
    cmp al, 2
    jne .no
    mov al, [ck_sr]
    add al, [ck_dr]
    shr al, 1
    mov ah, al
    mov al, [ck_sc]
    add al, [ck_dc]
    shr al, 1
    mov cl, 3
    shl ah, cl
    add al, ah
    xor ah, ah
    mov bx, ax
    mov al, [ck_board_data+bx]
    call ck_is_enemy
    jc .yes
    jmp short .no
.step:
    cmp byte [ck_force], 0
    jne .no
    mov al, [ck_dcol]
    call ck_abs
    cmp al, 1
    jne .no
    mov al, [ck_piece_v]
    cmp al, CK_RKING
    je .yes
    cmp al, CK_BKING
    je .yes
    cmp al, CK_RED
    jne .black
    cmp byte [ck_drow], 0
    jl .yes
    jmp short .no
.black:
    cmp byte [ck_drow], 0
    jg .yes
.no:
    clc
    jmp short .out
.yes:
    stc
.out:
    mov al, [ck_saved_target]
    mov [ck_target], al
    pop si
    pop dx
    pop cx
    pop bx
    ret

; AL=source index, CF=1 when that piece has at least one legal move.  If a
; capture exists anywhere, the source must itself be able to capture.
ck_piece_has_move:
    push bx
    push cx
    push dx
    push si
    mov [ck_move_src], al
    mov al, 23h
    call ck_trace
    call ck_any_capture
    mov al, 24h
    call ck_trace
    jnc .quiet
    mov al, [ck_move_src]
    call ck_piece_has_capture
    jmp short .out
.quiet:
    mov al, [ck_move_src]
    call ck_rowcol
    mov [ck_pr], ah
    mov [ck_pc], al
    xor bx, bx
    mov bl, [ck_move_src]
    mov al, [ck_board_data+bx]
    cmp al, CK_RKING
    je .king
    cmp al, CK_BKING
    je .king
    cmp al, CK_RED
    jne .black
    mov bl, -1
    call ck_forward_empty
    jmp short .out
.black:
    mov bl, 1
    call ck_forward_empty
    jmp short .out
.king:
    mov bl, -1
    call ck_forward_empty
    jc .out
    mov bl, 1
    call ck_forward_empty
.out:
    pop si
    pop dx
    pop cx
    pop bx
    ret

; BL is a one-row direction. CF=1 if either adjacent diagonal is empty.
ck_forward_empty:
    mov al, [ck_pr]
    add al, bl
    cmp al, 7
    ja .no
    mov [ck_lr], al
    mov al, [ck_pc]
    dec al
    cmp al, 7
    ja .right
    mov [ck_lc], al
    call ck_landing_empty
    jc .yes
.right:
    mov al, [ck_pc]
    inc al
    cmp al, 7
    ja .no
    mov [ck_lc], al
    call ck_landing_empty
    jc .yes
.no:
    clc
    ret
.yes:
    stc
    ret

; [ck_lr],[ck_lc] is on-board. CF=1 only when that square is empty.
ck_landing_empty:
    mov al, [ck_lr]
    shl al, 1
    shl al, 1
    shl al, 1
    add al, [ck_lc]
    xor ah, ah
    mov si, ax
    cmp byte [ck_board_data+si], CK_EMPTY
    jne .no
    stc
    ret
.no:
    clc
    ret

; CF=1 when AL is a piece belonging to [ck_turn].  Ghost/empty values are
; never accepted as a selectable piece.
ck_is_own:
    cmp byte [ck_turn], CK_RED
    jne .black
    cmp al, CK_RED
    je .yes
    cmp al, CK_RKING
    je .yes
    clc
    ret
.black:
    cmp al, CK_BLACK
    je .yes
    cmp al, CK_BKING
    jne .no
.yes:
    stc
    ret
.no:
    clc
    ret

; CF=1 when AL is an opponent piece of [ck_turn].
ck_is_enemy:
    or al, al
    jz .no
    cmp byte [ck_turn], CK_RED
    jne .black
    cmp al, CK_BLACK
    je .yes
    cmp al, CK_BKING
    je .yes
    jmp short .no
.black:
    cmp al, CK_RED
    je .yes
    cmp al, CK_RKING
    jne .no
.yes:
    stc
    ret
.no:
    clc
    ret

; CF=1 if any piece of the player to move has an adjacent jump.  It is used
; before selection and before a quiet move, so a player cannot evade a capture.
ck_any_capture:
    push ax
    push bx
    push si
    xor si, si
    mov al, 25h
    call ck_trace
.scan:
    cmp si, 64
    jae .no
    mov al, [ck_board_data+si]
    call ck_is_own
    jnc .next
    mov ax, si
    call ck_piece_has_capture
    jc .yes
.next:
    inc si
    jmp short .scan
.yes:
    mov al, 26h
    call ck_trace
    stc
    jmp short .out
.no:
    mov al, 27h
    call ck_trace
    clc
.out:
    pop si
    pop bx
    pop ax
    ret

; AL=source index, CF=1 if it has a legal two-square jump in one of the four
; diagonal directions.  Men intentionally use all four directions here: only
; their quiet move is forward-only.
ck_piece_has_capture:
    push ax
    push bx
    push cx
    push dx
    push si
    push di
    mov [ck_probe], al
    call ck_rowcol
    mov [ck_pr], ah
    mov [ck_pc], al
    mov si, ck_dirs
    mov cx, 4
.dir:
    mov bl, [si]                     ; row delta
    mov bh, [si+1]                   ; column delta
    mov al, [ck_pr]
    add al, bl
    add al, bl
    js .next
    cmp al, 7
    ja .next
    mov [ck_lr], al
    mov al, [ck_pc]
    add al, bh
    add al, bh
    js .next
    cmp al, 7
    ja .next
    mov [ck_lc], al
    mov al, [ck_lr]
    shl al, 1
    shl al, 1
    shl al, 1
    add al, [ck_lc]
    xor ah, ah
    mov di, ax
    mov al, [ck_board_data+di]
    or al, al
    jnz .next
    mov al, [ck_pr]
    add al, bl
    shl al, 1
    shl al, 1
    shl al, 1
    mov dl, [ck_pc]
    add dl, bh
    add al, dl
    xor ah, ah
    mov di, ax
    mov al, [ck_board_data+di]
    call ck_is_enemy
    jc .yes
.next:
    add si, 2
    loop .dir
    clc
    jmp short .out
.yes:
    stc
.out:
    pop di
    pop si
    pop dx
    pop cx
    pop bx
    pop ax
    ret

; New Game menu action and initial package state.
ck_reset:
    push si
    push di
    push cx
    push es
    push ds
    pop es
    mov si, ck_initial
    mov di, ck_board_data
    mov cx, 64
    cld                             ; string operations must always advance
    rep movsb
    pop es
    mov byte [ck_turn], CK_RED
    mov byte [ck_selected], CK_SEL
    mov byte [ck_cap_white], 0
    mov byte [ck_cap_black], 0
    mov byte [ck_game_over], 0
    mov byte [ck_winner], 0
    mov word [ck_time_total], 0
    mov word [ck_time_white], 0
    mov word [ck_time_black], 0
    call OSAPI_GET_TICKS
    mov [ck_time_last], ax
    pop cx
    pop di
    pop si
    ret

; The clock runs at the BIOS tick rate (about 18 ticks/second).  It is updated
; by a one-second window timer, so the active side owns all waiting time.
ck_clock_sync:
    call OSAPI_GET_TICKS
    mov bx, ax
    sub bx, [ck_time_last]
    mov [ck_time_last], ax
    add [ck_time_total], bx
    cmp byte [ck_game_over], 0
    jne .out
    cmp byte [ck_turn], CK_RED
    jne .black
    add [ck_time_white], bx
    ret
.black:
    add [ck_time_black], bx
.out:
    ret

ck_clock_draw:
    push ax
    push bx
    push cx
    push dx
    push si
    push di
    mov ax, [ck_time_total]
    mov bx, 18
    xor dx, dx
    div bx
    mov di, ck_clock_total+2
    call ck_hex_word
    mov ax, [ck_time_white]
    mov bx, 18
    xor dx, dx
    div bx
    mov di, ck_clock_white+2
    call ck_hex_word
    mov ax, [ck_time_black]
    mov bx, 18
    xor dx, dx
    div bx
    mov di, ck_clock_black+2
    call ck_hex_word
    mov cx, [ck_ox]
    add cx, 280                    ; align with the turn/winner label
    mov dx, [ck_oy]
    add dx, 72
    mov si, ck_clock_total
    mov ax, (CWHITE << 8) | CBLACK
    call OSAPI_FONT_RUN
    add dx, 18
    mov si, ck_clock_white
    call OSAPI_FONT_RUN
    add dx, 18
    mov si, ck_clock_black
    call OSAPI_FONT_RUN
    pop di
    pop si
    pop dx
    pop cx
    pop bx
    pop ax
    ret

ck_ontimer:
    mov al, 80h
    call ck_trace
    call ck_clock_sync
    cmp byte [ck_robot], CK_MODE_AUTO
    jne .paint
    cmp byte [ck_game_over], 0
    jne .paint
    cmp byte [ck_ai_busy], 0
    jne .paint
    call ck_robot_play
.paint:
    mov al, 81h
    call ck_trace
    call ck_repaint
    ret

; Captured men are material on the edge nearest their former side: white men
; taken by Black sit above the board; black men taken by White sit below it.
; These two narrow bands are the only extra pixels a move needs to repaint.
ck_captures:
    push ax
    push bx
    push cx
    push dx
    push si
    mov al, CWHITE
    call OSAPI_SET_COLOR
    mov ax, [ck_ox]
    mov bx, [ck_oy]
    sub bx, 32
    mov cx, ax
    add cx, 255
    mov dx, bx
    add dx, 31                    ; ends at board top - 1
    call OSAPI_GFX_FILL
    mov ax, [ck_ox]
    mov bx, [ck_oy]
    add bx, 256                   ; begins immediately below board
    mov cx, ax
    add cx, 255
    mov dx, bx
    add dx, 31
    call OSAPI_GFX_FILL
    mov si, [ck_ox]
    mov bx, [ck_oy]
    sub bx, 31
    xor cx, cx
    mov cl, [ck_cap_black]
.white:
    jcxz .black_start
    mov ax, si
    mov byte [ck_piece_v], CK_RED
    push bx
    push cx
    push si
    call ck_piece
    pop si
    pop cx
    pop bx
    add si, 20
    dec cl
    jmp short .white
.black_start:
    mov si, [ck_ox]
    mov bx, [ck_oy]
    add bx, 256
    xor cx, cx
    mov cl, [ck_cap_white]
.black:
    jcxz .out
    mov ax, si
    mov byte [ck_piece_v], CK_BLACK
    push bx
    push cx
    push si
    call ck_piece
    pop si
    pop cx
    pop bx
    add si, 20
    dec cl
    jmp short .black
.out:
    pop si
    pop dx
    pop cx
    pop bx
    pop ax
    ret

ck_oncmd:
    or ah, ah
    jnz .out
    or al, al
    jnz .mode
    call ck_reset
    call ck_repaint
    jmp short .out
.mode:
    dec al
    jnz .not_human
    mov byte [ck_robot], 0
    jmp short .new
.not_human:
    dec al
    jnz .not_black
    mov byte [ck_robot], 1
    jmp short .new
.not_black:
    dec al
    jnz .auto
    mov byte [ck_robot], CK_MODE_WHITE_ROBOT
    jmp short .new
.auto:
    mov byte [ck_robot], 2
.new:
    call ck_start_game
 .out:
    ret

ck_start_game:
    call ck_reset
    call ck_repaint
    cmp byte [ck_robot], CK_MODE_AUTO
    je .go
    cmp byte [ck_robot], CK_MODE_WHITE_ROBOT
    jne .out
.go:
    call ck_robot_play              ; start White immediately, not at first tick
    call ck_repaint
.out:
    ret

; OSAPI_ABOUT_SET installs this as Checkers > About....
ck_about:
    push ax
    push bx
    push cx
    push dx
    push si
    mov al, OS88UI_AOK
    mov bx, si
    mov si, ck_s_about
    mov di, ck_about_done
    call os88ui_ask
    pop si
    pop dx
    pop cx
    pop bx
    pop ax
    ret

ck_about_done:
    ret

; Temporary robot policy: reservoir-sample one legal black move.  The same
; generator is retained for the depth-five minimax that replaces this policy.
ck_robot_play:
    mov byte [ck_ai_busy], 1
.restart:
    mov byte [ck_ai_n], 0
    cmp byte [ck_selected], CK_SEL
    je .all_sources
    mov al, [ck_selected]           ; same man must finish its jump chain
    mov [ck_ai_src], al
    mov byte [ck_ai_dst], 0
    jmp short .forced_src
.all_sources:
    mov byte [ck_ai_src], 0
.src:
    mov al, [ck_ai_src]
    cmp al, 64
    jae .play
    xor bx, bx
    mov bl, al
    mov al, [ck_board_data+bx]
    call ck_is_own
    jnc .nextsrc
    mov al, [ck_ai_src]
    mov [ck_selected], al
    mov byte [ck_ai_dst], 0
.forced_src:
.dst:
    mov al, [ck_ai_dst]
    cmp al, 64
    jae .nextsrc
    call ck_target_legal
    jnc .nextdst
    inc byte [ck_ai_n]
    call OSAPI_RAND
    xor dx, dx
    xor bx, bx
    mov bl, [ck_ai_n]
    div bx
    or dx, dx
    jnz .nextdst
    mov al, [ck_ai_src]
    mov [ck_ai_bestsrc], al
    mov al, [ck_ai_dst]
    mov [ck_ai_bestdst], al
.nextdst:
    inc byte [ck_ai_dst]
    jmp short .dst
.nextsrc:
    inc byte [ck_ai_src]
    jmp short .src
.play:
    cmp byte [ck_ai_n], 0
    je .out
    mov al, [ck_ai_bestsrc]
    mov [ck_selected], al
    mov al, [ck_ai_bestdst]
    mov [ck_target], al
    call ck_try_move
    cmp byte [ck_game_over], 0
    jne .out
    cmp byte [ck_robot], CK_MODE_AUTO
    je .same_side
    cmp byte [ck_turn], CK_BLACK
    jne .out
.same_side:
    cmp byte [ck_selected], CK_SEL
    je .out
    jmp .restart                    ; perform every forced black jump
.out:
    mov byte [ck_ai_busy], 0
    cmp byte [ck_robot], CK_MODE_AUTO
    jne .done
    cmp byte [ck_game_over], 0
    jne .done
    mov bx, si
    mov ax, 4                     ; keep Robot-vs-Robot cadence armed
    call OSAPI_WM_TIMER             ; retain auto-play even after a robot turn
.done:
    ret

ck_repaint:
    push ax
    push bx
    push cx
    push dx
    push si                         ; callback ABI: SI remains the window
    ; ck_paint redraws the opaque board and ck_status clears just its own
    ; label band.  A full-content fill here made every move flash.
    call ck_paint
    mov al, 72h                     ; ck_paint has returned to the callback
    call ck_trace
    call ck_debug_draw
    pop si
    pop dx
    pop cx
    pop bx
    pop ax
    ret

ck_tpl:
    dw 45, 75, CK_W, CK_H
    dw ck_title, ck_paint, 0, ck_onclick
    OS88_MENUSET ck_menus, ck_name, ck_oncmd
    OS88_MENU ck_m_game, ck_i_game, 5
    OS88_MENUSET_END ck_menus
ck_name: db 'Checkers',0
ck_m_game: db 'Game',0
ck_i_game: dw ck_i_new, ck_i_human, ck_i_robot, ck_i_robot_white, ck_i_auto
ck_i_new: db 'New Game',0
ck_i_human: db 'Human vs Human',0
ck_i_robot: db 'Human vs Robot',0
ck_i_robot_white: db 'Robot vs Human',0
ck_i_auto: db 'Robot vs Robot',0
ck_title: db 'Checkers',0
ck_s_red: db 'White to move',0
ck_s_black: db 'Black to move',0
ck_s_white_wins: db 'White Wins!',0
ck_s_black_wins: db 'Black Wins!',0
ck_s_play_again: db 'Play Again',0
ck_s_hint: db 'Select a piece, then move.',0
ck_s_about: db 'Rui Ribeiro - 2026',0
ck_trace_buf: db 'D 0000 00',0
ck_hex: db '0123456789ABCDEF'
ck_clock_total: db 'T:0000',0
ck_clock_white: db 'W:0000',0
ck_clock_black: db 'B:0000',0

; 16px masked disc.  MASK lays the rim; DATA lays the centre over that rim.
ck_piece_sprite:
    db 1,16
    dw 0x0000,0x0FF0,0x1FF8,0x3FFC,0x7FFE,0x7FFE,0xFFFF,0xFFFF
    dw 0xFFFF,0xFFFF,0x7FFE,0x7FFE,0x3FFC,0x1FF8,0x0FF0,0x0000
    dw 0x0000,0x0000,0x0000,0x0FF0,0x1FF8,0x3FFC,0x3FFC,0x7FFE
    dw 0x7FFE,0x3FFC,0x3FFC,0x1FF8,0x0FF0,0x0000,0x0000,0x0000

; Four diagonal (row,column) directions for jump discovery.
ck_dirs: db -1,-1, -1,1, 1,-1, 1,1

; 0 empty; white starts at the bottom and moves upward; black moves downward.
ck_initial:
    db 0,2,0,2,0,2,0,2, 2,0,2,0,2,0,2,0, 0,2,0,2,0,2,0,2
    db 0,0,0,0,0,0,0,0, 0,0,0,0,0,0,0,0
    db 1,0,1,0,1,0,1,0, 0,1,0,1,0,1,0,1, 1,0,1,0,1,0,1,0

%define OS88UI_ALERT
%include "os88ui.inc"

    OS88_BSS 119
    OS88_IMAGE_END
ck_ox equ os88_image_end+0
ck_oy equ os88_image_end+2
ck_px equ os88_image_end+4
ck_py equ os88_image_end+6
ck_i equ os88_image_end+8
ck_turn equ os88_image_end+9
ck_selected equ os88_image_end+10
ck_target equ os88_image_end+11
ck_piece_v equ os88_image_end+12
ck_sr equ os88_image_end+13
ck_sc equ os88_image_end+14
ck_dr equ os88_image_end+15
ck_dc equ os88_image_end+16
ck_drow equ os88_image_end+17
ck_dcol equ os88_image_end+18
ck_jump equ os88_image_end+19
ck_board_data equ os88_image_end+20
ck_force equ os88_image_end+84
ck_promoted equ os88_image_end+85
ck_probe equ os88_image_end+86
ck_pr equ os88_image_end+87
ck_pc equ os88_image_end+88
ck_lr equ os88_image_end+89
ck_lc equ os88_image_end+90
ck_move_src equ os88_image_end+91
ck_saved_target equ os88_image_end+92
ck_cap_white equ os88_image_end+93
ck_cap_black equ os88_image_end+94
ck_robot equ os88_image_end+95
ck_ai_n equ os88_image_end+96
ck_ai_src equ os88_image_end+97
ck_ai_dst equ os88_image_end+98
ck_ai_bestsrc equ os88_image_end+99
ck_ai_bestdst equ os88_image_end+100
ck_ai_busy equ os88_image_end+101
ck_trace_seq equ os88_image_end+102
ck_trace_stage equ os88_image_end+104
ck_preview_active equ os88_image_end+105
ck_preview_force equ os88_image_end+106
ck_game_over equ os88_image_end+107
ck_winner equ os88_image_end+108
ck_time_last equ os88_image_end+109
ck_time_total equ os88_image_end+111
ck_time_white equ os88_image_end+113
ck_time_black equ os88_image_end+115
ck_preview_src equ os88_image_end+117
ck_preview_dst equ os88_image_end+118
