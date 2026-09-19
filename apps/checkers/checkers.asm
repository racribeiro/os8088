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
CK_H equ 310
CK_X equ 12
CK_Y equ 18
CK_SQ equ 32
CK_SEL equ 0FFh
CK_EMPTY equ 0
CK_RED equ 1
CK_BLACK equ 2
CK_RKING equ 3
CK_BKING equ 4

ck_entry:
    push ax
    push cx
    push si
    mov si, ck_tpl
    call OSAPI_WM_CREATE
    jc .out
    mov si, ck_menus
    call OSAPI_MENU_SET
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
    call ck_status
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
    call ck_target_legal
    jnc .draw_piece
    mov al, CWHITE
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
    mov si, ck_s_red
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
    mov si, ck_s_hint
    add dx, 18
    mov ax, (CWHITE << 8) | CBLACK
    call OSAPI_FONT_RUN
    ret

; W_ONCLICK. CX/DX are absolute screen coordinates.
ck_onclick:
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
    mov ax, dx
    mov cl, 5
    shr ax, cl
    mov bx, ax
    mov ax, cx
    mov cl, 5
    shr ax, cl
    add bx, bx
    add bx, bx
    add bx, bx
    add bx, ax
    mov [ck_target], bl
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
    call ck_piece_has_move
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
    xor bx, bx
    mov bl, [ck_selected]
    mov al, [ck_board_data+bx]
    mov [ck_piece_v], al
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
    mov byte [ck_board_data+bx], CK_EMPTY
.apply:
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
    mov byte [ck_selected], CK_SEL
    xor byte [ck_turn], 3           ; 1 <-> 2
.out:
    ret

; AL=index -> AL=column, AH=row.
ck_rowcol:
    mov ah, al
    and al, 7
    mov cl, 3
    shr ah, cl
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
    call ck_any_capture
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
    stc
    jmp short .out
.no:
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
    pop cx
    pop di
    pop si
    ret

ck_oncmd:
    or ah, ah
    jnz .out
    or al, al
    jnz .out
    call ck_reset
    call ck_repaint
.out:
    ret

ck_repaint:
    push ax
    push bx
    push cx
    push dx
    mov al, CWHITE
    call OSAPI_SET_COLOR
    mov bx, si
    call OSAPI_WM_CONTENT
    mov bx, dx
    mov cx, ax
    add cx, CK_W-3
    add dx, CK_H-TITLE_H-2
    call OSAPI_GFX_FILL
    call ck_paint
    pop dx
    pop cx
    pop bx
    pop ax
    ret

ck_tpl:
    dw 45, 75, CK_W, CK_H
    dw ck_title, ck_paint, 0, ck_onclick
    OS88_MENUSET ck_menus, ck_name, ck_oncmd
        OS88_MENU ck_m_game, ck_i_game, 1
    OS88_MENUSET_END ck_menus
ck_name: db 'Checkers',0
ck_m_game: db 'Game',0
ck_i_game: dw ck_i_new
ck_i_new: db 'New Game',0
ck_title: db 'Checkers',0
ck_s_red: db 'White to move',0
ck_s_black: db 'Black to move',0
ck_s_hint: db 'Select a piece, then move.',0

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

    OS88_BSS 95
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
