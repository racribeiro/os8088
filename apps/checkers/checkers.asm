; =============================================================================
; CHECKERS -- local two-player draughts on an 8 x 8 board.
; Click a piece, then a highlighted destination. Red moves down; black up.
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
CK_Y equ 30
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

; in AX/BX=square origin, [ck_piece_v]=piece.  Two bounded raster discs make
; a circular man: black with a white border, or white with a black border.
; Kings get a yellow inner frame.
ck_piece:
    push ax
    push bx
    mov al, [ck_piece_v]
    cmp al, CK_RED
    je .white
    cmp al, CK_RKING
    je .white
    mov al, CWHITE
    jmp short .outer
.white:
    mov al, CBLACK
.outer:
    call OSAPI_SET_COLOR
    pop bx                          ; restore the square origin after AL=colour
    pop ax
    push ax
    push bx
    add ax, 6
    add bx, 6
    mov si, ck_disc_outer
    call ck_disc_draw
    pop bx
    pop ax
    mov al, [ck_piece_v]
    cmp al, CK_RED
    je .inner_white
    cmp al, CK_RKING
    je .inner_white
    mov al, CBLACK
    jmp short .inner
.inner_white:
    mov al, CWHITE
.inner:
    call OSAPI_SET_COLOR
    add ax, 8
    add bx, 8
    mov si, ck_disc_inner
    call ck_disc_draw
.king:
    mov al, [ck_piece_v]
    cmp al, CK_RKING
    je .crown
    cmp al, CK_BKING
    jne .out
.crown:
    mov al, CYELLOW
    call OSAPI_SET_COLOR
    mov ax, [ck_px]
    add ax, 4                       ; inner-disc origin is square + 8
    mov bx, [ck_py]
    add bx, 4
    mov cx, ax
    add cx, 7
    mov dx, bx
    add dx, 7
    call OSAPI_GFX_FRAME
.out:
    ret

; AX/BX = raster origin; SI = pairs of x offset and inclusive width, ending
; in FFh.  The tables make each horizontal run finite and keep a piece inside
; its own 32px square.
ck_disc_draw:
    mov [ck_px], ax
    mov [ck_py], bx
    xor di, di
.row:
    mov al, [si]
    inc si
    cmp al, 0FFh
    je .out
    cbw
    add ax, [ck_px]
    mov bx, ax
    mov al, [si]
    inc si
    xor ah, ah
    add ax, bx
    dec ax
    xchg ax, bx                    ; AX=x1, BX=x2 for gfx_hline
    mov dx, [ck_py]
    add dx, di
    call OSAPI_GFX_HLINE
    inc di
    jmp short .row
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
    jne .out
    jmp short .yes
.black:
    cmp al, CK_BKING
    jne .out
.yes:
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
    xor bx, bx
    mov bl, [ck_target]
    cmp byte [ck_board_data+bx], CK_EMPTY
    jne .out
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
.rdir:
    mov al, [ck_dcol]
    call ck_abs
    cmp al, [ck_jump]
    jne .out
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
    je .apply
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
    ; promotion when a man reaches its far edge
    cmp al, CK_RED
    jne .blackprom
    cmp byte [ck_dr], 0
    jne .store
    mov al, CK_RKING
    jmp short .store
.blackprom:
    cmp al, CK_BLACK
    jne .store
    cmp byte [ck_dr], 7
    jne .store
    mov al, CK_BKING
.store:
    mov [ck_board_data+bx], al
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

; (x offset, inclusive run width) rows for 20px and 16px circles.
ck_disc_outer:
    db 8,4, 5,10, 3,14, 2,16, 1,18, 1,18
    db 0,20, 0,20, 0,20, 0,20, 0,20, 0,20, 0,20, 0,20
    db 1,18, 1,18, 2,16, 3,14, 5,10, 8,4, 0FFh
ck_disc_inner:
    db 6,4, 4,8, 2,12, 1,14
    db 0,16, 0,16, 0,16, 0,16, 0,16, 0,16, 0,16, 0,16
    db 1,14, 2,12, 4,8, 6,4, 0FFh

; 0 empty; red starts at the bottom and moves upward; black moves downward.
ck_initial:
    db 0,2,0,2,0,2,0,2, 2,0,2,0,2,0,2,0, 0,2,0,2,0,2,0,2
    db 0,0,0,0,0,0,0,0, 0,0,0,0,0,0,0,0
    db 1,0,1,0,1,0,1,0, 0,1,0,1,0,1,0,1, 1,0,1,0,1,0,1,0

    OS88_BSS 86
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
