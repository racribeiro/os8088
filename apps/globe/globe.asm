; =============================================================================
; GLOBE 1.0 -- interactive terrestrial wireframe globe.
; Cursor keys rotate it. View offers Auto Rotate, Perspective and Isometric.
; Only continent outlines are drawn inside the globe rim.
; =============================================================================

%include "os88api.inc"

    OS88_HEADER 'GLOBE', gl_entry, 1

; A round Earth: solid Americas at left, a compact Europe above Africa at
; right.  At 16px the land masses are intentionally bold rather than literal
; coastlines, so the geographic split reads on the desktop at a glance.
    OS88_ICON16
    dw 0x0000,0x07E0,0x1FF8,0x3FFC,0x7FFE,0x7FFE,0xFFFF,0xFFFF
    dw 0xFFFF,0xFFFF,0x7FFE,0x7FFE,0x3FFC,0x1FF8,0x07E0,0x0000
    dw 0x0000,0x07E0,0x1818,0x2104,0x4C72,0x4C7E,0x8C70,0x8C38
    dw 0x8C38,0x8C70,0x4C68,0x4C78,0x2104,0x1818,0x07E0,0x0000
    OS88_ICON16_END

GL_W equ 292
GL_H equ 272
GL_CX equ (GL_W - 2) / 2
GL_CY equ 122
GL_STEP equ 8
GL_TICK equ 2
GL_BUF_ST equ 91                 ; 728 pixels: 720-wide content plus alignment
GL_BUF_H equ 480
GL_BUF_SIZE equ GL_BUF_ST * GL_BUF_H

gl_entry:
    push ax
    push si
    mov si, gl_tpl
    call OSAPI_WM_CREATE
    jc .out
    mov byte [gl_persp], 0          ; Isometric keeps every coastline in the rim.
    mov byte [gl_color], 1
    mov al, 1
    call OSAPI_WM_SIZABLE
    mov ax, gl_onsize
    call OSAPI_WM_ONSIZE
    mov si, gl_menus
    call OSAPI_MENU_SET
    mov si, gl_about
    call OSAPI_ABOUT_SET             ; kernel adds “About Globe” above Close
    mov ax, gl_ontimer
    call OSAPI_WM_ONTIMER           ; absent on kern_small: arrows still work
.out:
    pop si
    pop ax
    ret

; W_PAINT, called with the graphics lock held.
gl_paint:
    push ax
    push bx
    push cx
    push dx
    push si
    ; Graphics primitives only know the physical screen.  Arm the window
    ; manager's visible-content region for every paint so rotation can never
    ; write into the title bar, desktop, or another window.
    mov bx, si
    call OSAPI_WM_CLIP_SET
    jc gl_paint_done
    mov bx, si
    call OSAPI_WM_CONTENT
    mov [gl_cx], ax
    mov [gl_cy], dx
    mov [gl_ox], ax
    mov [gl_oy], dx
    mov bx, si
    call OSAPI_WM_GEOM
    mov [gl_cw], cx
    mov [gl_ch], dx
    cmp byte [gl_about_on], 0
    jne gl_about_paint
    mov ax, cx
    cmp ax, dx
    jbe .short
    mov ax, dx
.short:
    mov bx, 2
    mul bx
    mov bx, 5
    div bx                          ; radius = 40% of the shorter content axis
    mov [gl_radius], ax
    mov bx, 128
    mul bx
    mov bx, 104
    div bx
    mov [gl_scale], ax              ; Q7 model scale, 80% diameter overall
    ; Centre from the globe's *actual* diameter: top margin + radius.  This
    ; is equivalent to content-height/2 but remains explicit when its 80%
    ; size changes with a resize.
    mov ax, [gl_radius]
    add ax, ax
    mov bx, [gl_cw]
    sub bx, ax
    shr bx, 1
    add bx, [gl_ox]
    add bx, [gl_radius]
    mov [gl_cx], bx
    mov bx, [gl_ch]
    sub bx, ax
    shr bx, 1
    add bx, [gl_oy]
    add bx, [gl_radius]
    mov [gl_cy], bx
    call gl_angles
    mov byte [gl_buffer], 0
    cmp byte [gl_color], 0
    jne .scene
    cmp byte [gl_buffer_bad], 0
    jne .scene
    call gl_mask_begin
    mov byte [gl_buffer], 1
.scene:
    cmp byte [gl_color], 0
    je .mono
    mov al, CLCYAN
    call OSAPI_SET_COLOR
    mov si, gl_disc_spans
    mov cl, 15
    call gl_disc
    call gl_fill_contours
    mov al, CBLACK                  ; keep the ocean rim distinct from cyan water
    jmp short .rim
.mono:
    mov al, CBLACK
.rim:
    call OSAPI_SET_COLOR
    mov si, gl_outline
    mov cl, 17
    call gl_path                   ; only the rim is unrotated
    call gl_contours
    cmp byte [gl_grid], 0
    je gl_paint_done
    mov al, CLGRAY
    cmp byte [gl_color], 0
    jne .gridpen
    mov al, CBLACK
.gridpen:
    call OSAPI_SET_COLOR
    call gl_graticule
gl_paint_done:
    cmp byte [gl_buffer], 0
    je .unbuffered
    mov byte [gl_buffer], 0
    call gl_mask_put
.unbuffered:
    pop si
    pop dx
    pop cx
    pop bx
    pop ax
    ret

; W_ONKEY: arrows rotate by 8/256 of a turn.
gl_onkey:
    cmp byte [gl_about_on], 0
    je .live
    mov byte [gl_about_on], 0
    call gl_repaint                  ; any key closes the native About panel
    ret
.live:
    cmp ah, KSC_ESC
    jne .notesc
    cmp byte [gl_full], 0
    je .out
    jmp gl_restore
.notesc:
    cmp al, 'f'
    je gl_fulltoggle
    cmp al, 'F'
    je gl_fulltoggle
    cmp ah, KSC_LEFT
    je .left
    cmp ah, KSC_RIGHT
    je .right
    cmp ah, KSC_UP
    je .up
    cmp ah, KSC_DOWN
    jne .out
    sub byte [gl_pitch], GL_STEP
    jmp short .draw
.up:    add byte [gl_pitch], GL_STEP
        jmp short .draw
.left:  sub byte [gl_yaw], GL_STEP
        jmp short .draw
.right: add byte [gl_yaw], GL_STEP
.draw:  call gl_repaint
.out:   ret

; View: Auto Rotate, Perspective, Isometric, Maximize, Restore, Color, Grid.
gl_oncmd:
    or ah, ah
    jnz .out
    cmp al, 0
    je .auto
    cmp al, 1
    je .perspective
    cmp al, 2
    je .isometric
    cmp al, 3
    je gl_maximize
    cmp al, 4
    je gl_restore
    cmp al, 5
    je .color
    cmp al, 6
    je .grid
    jmp short .out
.isometric:
    mov byte [gl_persp], 0
    jmp short .draw
.color:
    xor byte [gl_color], 1
    jmp short .draw
.grid:
    xor byte [gl_grid], 1
    jmp short .draw
.perspective:
    mov byte [gl_persp], 1
    jmp short .draw
.auto:
    xor byte [gl_auto], 1
    mov bx, si
    cmp byte [gl_auto], 0
    je .cancel
    mov ax, GL_TICK
    call OSAPI_WM_TIMER
    jmp short .draw
.cancel:
    xor ax, ax
    call OSAPI_WM_TIMER
.draw:
    call gl_repaint
.out:
    ret

; The timer is one-shot, therefore an enabled Auto Rotate re-arms itself.
gl_ontimer:
    cmp byte [gl_auto], 0
    je .out
    add byte [gl_yaw], 2
    call gl_repaint
    mov bx, si
    mov ax, GL_TICK
    call OSAPI_WM_TIMER
.out:
    ret

; W_ONSIZE accepts every grow-box size; gl_paint derives its centre afresh.
gl_onsize:
    ret

; Fullscreen is the system's maximized window. F toggles it after the menu
; bar has disappeared, while the two explicit View commands are useful before.
gl_fulltoggle:
    cmp byte [gl_full], 0
    je gl_maximize
    jmp short gl_restore
gl_maximize:
    mov bx, si
    mov al, 1
    call OSAPI_FULLSCREEN
    jc gl_fullout
    mov byte [gl_full], 1
gl_fullout:
    ret
gl_restore:
    mov bx, si
    xor al, al
    call OSAPI_FULLSCREEN
    jc gl_fullout
    mov byte [gl_full], 0
    ret

; Self redraw for keyboard, menu and timer callbacks (all have the lock).
gl_repaint:
    push ax
    push bx
    push cx
    push dx
    cmp byte [gl_color], 0
    je .paint                       ; the composed band carries its own paper
    mov al, CWHITE
    call OSAPI_SET_COLOR
    mov bx, si
    call OSAPI_WM_CONTENT
    mov [gl_x1], ax
    mov [gl_y1], dx
    mov bx, si
    call OSAPI_WM_GEOM
    dec cx
    dec dx
    add cx, [gl_x1]
    add dx, [gl_y1]
    mov ax, [gl_x1]
    mov bx, [gl_y1]
    call OSAPI_GFX_FILL
.paint:
    call gl_paint
    pop dx
    pop cx
    pop bx
    pop ax
    ret

; The kernel owns the About menu item and calls this under the graphics lock.
; It is a small modal-in-content card: any key returns to the globe.
gl_about:
    mov byte [gl_about_on], 1
    call gl_repaint
    ret

gl_about_paint:
    mov al, CWHITE
    call OSAPI_SET_COLOR
    mov ax, [gl_ox]
    mov bx, [gl_oy]
    mov cx, ax
    add cx, [gl_cw]
    dec cx
    mov dx, bx
    add dx, [gl_ch]
    dec dx
    call OSAPI_GFX_FILL
    mov si, gl_about_1
    mov dx, [gl_oy]
    add dx, 44
    call gl_about_line
    mov si, gl_about_2
    add dx, 20
    call gl_about_line
    mov si, gl_about_3
    add dx, 20
    call gl_about_line
    jmp gl_paint_done

; in SI=NUL string, DX=baseline; uses the live content width.
gl_about_line:
    push ax
    push cx
    call OSAPI_FONT_WIDTH
    mov cx, [gl_cw]
    sub cx, ax
    shr cx, 1
    add cx, [gl_ox]
    mov ax, (CWHITE << 8) | CBLACK
    call OSAPI_FONT_RUN
    pop cx
    pop ax
    ret

; Fetch the four Q7 trig values needed for this frame.
gl_angles:
    mov al, [gl_yaw]
    xor ah, ah
    mov bx, ax
    mov al, [gl_sintab + bx]
    mov [gl_siny], al
    add bl, 64
    adc bh, 0
    and bx, 255
    mov al, [gl_sintab + bx]
    mov [gl_cosy], al
    mov al, [gl_pitch]
    xor ah, ah
    mov bx, ax
    mov al, [gl_sintab + bx]
    mov [gl_sinp], al
    add bl, 64
    adc bh, 0
    and bx, 255
    mov al, [gl_sintab + bx]
    mov [gl_cosp], al
    ret

; Pointer + count entries, each a closed or open coastline in x,y,z triples.
gl_contours:
    mov di, gl_shapes
.next:
    mov si, [di]
    or si, si
    jz .out
    mov cl, [di+2]
    mov al, [di+3]
    cmp byte [gl_color], 0
    jne .colour
    mov al, CBLACK
.colour:
    call OSAPI_SET_COLOR
    add di, 4
    push di
    call gl_contour
    pop di
    jmp short .next
.out:
    ret

; Paint front-facing continental rings before drawing their coastline.  Each
; source contour has at most 16 points; scan conversion finds its intersections
; per row and sends one clipped horizontal run to the kernel.
gl_fill_contours:
    mov di, gl_shapes
.next:
    mov si, [di]
    or si, si
    jz .out
    mov cl, [di+2]
    mov al, [di+3]
    call OSAPI_SET_COLOR
    add di, 4
    push di
    call gl_fill_contour
    pop di
    jmp short .next
.out:
    ret

; in DS:SI=Q7 points, CL=count.  Edges that cross the rear hemisphere are
; clipped at the limb, so a partly-visible continent still receives paint.
gl_fill_contour:
    mov [gl_fill_left], cl
    mov byte [gl_fill_n], 0
    call gl_vertex
    mov [gl_firstx], cx
    mov [gl_firsty], dx
    mov al, [gl_depth]
    mov [gl_firstd], al
    mov [gl_prevx], cx
    mov [gl_prevy], dx
    mov [gl_prevd], al
    dec byte [gl_fill_left]
.project:
    cmp byte [gl_fill_left], 0
    je .close
    call gl_vertex
    mov [gl_curx], cx
    mov [gl_cury], dx
    mov al, [gl_depth]
    mov [gl_curd], al
    call gl_fill_edge
    mov ax, [gl_curx]
    mov [gl_prevx], ax
    mov ax, [gl_cury]
    mov [gl_prevy], ax
    mov al, [gl_curd]
    mov [gl_prevd], al
    dec byte [gl_fill_left]
    jmp short .project
.close:
    mov ax, [gl_firstx]
    mov [gl_curx], ax
    mov ax, [gl_firsty]
    mov [gl_cury], ax
    mov al, [gl_firstd]
    mov [gl_curd], al
    call gl_fill_edge
    cmp byte [gl_fill_n], 3
    jb .out
.projected:
    mov word [gl_fill_min], 32767
    mov word [gl_fill_max], -32768
    xor bx, bx
    xor cx, cx
    mov cl, [gl_fill_n]
    add cx, cx
.bounds:
    cmp bx, cx
    jae .rows
    mov ax, [gl_py+bx]
    cmp ax, [gl_fill_min]
    jge .notmin
    mov [gl_fill_min], ax
.notmin:
    cmp ax, [gl_fill_max]
    jle .notmax
    mov [gl_fill_max], ax
.notmax:
    add bx, 2
    jmp short .bounds
.rows:
    mov ax, [gl_fill_min]
    mov [gl_scan], ax
.row:
    mov ax, [gl_scan]
    cmp ax, [gl_fill_max]
    jg .out
    call gl_fill_row
    inc word [gl_scan]
    jmp short .row
.out:
    ret

; Sutherland-Hodgman edge step against depth >= 0.
gl_fill_edge:
    mov al, [gl_prevd]
    test al, al
    js .prevout
    mov al, [gl_curd]
    test al, al
    js .outcross
    mov ax, [gl_curx]
    mov dx, [gl_cury]
    jmp short gl_fill_add
.outcross:
    call gl_fill_intersect
    jmp short gl_fill_add
.prevout:
    mov al, [gl_curd]
    test al, al
    js .out
    call gl_fill_intersect
    call gl_fill_add
    mov ax, [gl_curx]
    mov dx, [gl_cury]
    jmp short gl_fill_add
.out:
    ret

; Projected intersection of prev->cur where depth is zero.
; out AX=x, DX=y.
gl_fill_intersect:
    mov ax, [gl_curx]
    sub ax, [gl_prevx]
    mov bx, ax
    mov al, [gl_prevd]
    cbw
    imul bx
    mov bl, [gl_prevd]
    sub bl, [gl_curd]
    xor bh, bh
    test bl, bl
    jns .xdiv
    dec bh
.xdiv:
    idiv bx
    add ax, [gl_prevx]
    mov [gl_ix], ax
    mov ax, [gl_cury]
    sub ax, [gl_prevy]
    mov bx, ax
    mov al, [gl_prevd]
    cbw
    imul bx
    mov bl, [gl_prevd]
    sub bl, [gl_curd]
    xor bh, bh
    test bl, bl
    jns .ydiv
    dec bh
.ydiv:
    idiv bx
    add ax, [gl_prevy]
    mov dx, ax
    mov ax, [gl_ix]
    ret

; Append AX/DX to the clipped ring (maximum source budget is 30 points).
gl_fill_add:
    xor bx, bx
    mov bl, [gl_fill_n]
    add bx, bx
    mov [gl_px+bx], ax
    mov [gl_py+bx], dx
    inc byte [gl_fill_n]
    ret

; Find the leftmost and rightmost crossing of one polygon scan row.
gl_fill_row:
    mov byte [gl_fill_i], 0
    mov byte [gl_fill_have], 0
.edge:
    mov al, [gl_fill_i]
    cmp al, [gl_fill_n]
    jae .emit
    xor bx, bx
    mov bl, al
    add bx, bx
    mov [gl_fill_a], bx
    inc al
    cmp al, [gl_fill_n]
    jb .nextok
    xor al, al
.nextok:
    xor di, di
    xor dx, dx
    mov dl, al
    add di, dx
    add di, di
    mov [gl_fill_b], di
    mov ax, [gl_py+bx]
    mov dx, [gl_py+di]
    cmp ax, dx
    je .advance
    ; include the lower endpoint, exclude the upper: no double intersections
    cmp ax, dx
    jl .up
    xchg ax, dx
.up:
    cmp word [gl_scan], ax
    jl .advance
    cmp word [gl_scan], dx
    jge .advance
    ; x = x1 + (scan-y1) * (x2-x1) / (y2-y1)
    mov bx, [gl_fill_a]
    mov di, [gl_fill_b]
    mov ax, [gl_scan]
    sub ax, [gl_py+bx]
    mov cx, [gl_px+di]
    sub cx, [gl_px+bx]
    imul cx
    mov cx, [gl_py+di]
    sub cx, [gl_py+bx]
    idiv cx
    add ax, [gl_px+bx]
    cmp byte [gl_fill_have], 0
    jne .other
    mov [gl_fill_xlo], ax
    mov [gl_fill_xhi], ax
    mov byte [gl_fill_have], 1
    jmp short .advance
.other:
    cmp ax, [gl_fill_xlo]
    jge .nlo
    mov [gl_fill_xlo], ax
.nlo:
    cmp ax, [gl_fill_xhi]
    jle .advance
    mov [gl_fill_xhi], ax
.advance:
    inc byte [gl_fill_i]
    jmp .edge
.emit:
    cmp byte [gl_fill_have], 0
    je .out
    mov ax, [gl_fill_xlo]
    mov bx, [gl_fill_xhi]
    mov dx, [gl_scan]
    call OSAPI_GFX_HLINE
.out:
    ret

; The latitude/longitude paths share the same rotation and front-face test as
; coastlines.  Thus a meridian naturally disappears behind the sphere instead
; of being painted through it.
gl_graticule:
    mov di, gl_grid_shapes
.next:
    mov si, [di]
    or si, si
    jz .out
    mov cl, [di+2]
    add di, 3
    push di
    call gl_contour
    pop di
    jmp short .next
.out:
    ret

; Draw a coastline only where both endpoints face the viewer.
gl_contour:
    mov [gl_left], cl
    call gl_vertex
    mov [gl_x1], cx
    mov [gl_y1], dx
    mov al, [gl_depth]
    test al, al
    js .hidden
    mov byte [gl_visible], 1
    jmp short .seed
.hidden:
    mov byte [gl_visible], 0
.seed:
    dec byte [gl_left]
    jz .out
.point:
    call gl_vertex
    cmp byte [gl_visible], 0
    je .save
    mov al, [gl_depth]
    test al, al
    js .save
    mov ax, [gl_x1]
    mov bx, [gl_y1]
    call gl_line
.save:
    mov [gl_x1], cx
    mov [gl_y1], dx
    mov al, [gl_depth]
    test al, al
    js .hide
    mov byte [gl_visible], 1
    jmp short .more
.hide:
    mov byte [gl_visible], 0
.more:
    dec byte [gl_left]
    jnz .point
.out:
    ret

; Rotate a model point. Isometric is orthographic; Perspective adds depth/256.
; in DS:SI=x,y,z; out CX=x, DX=y; SI += 3.
gl_vertex:
    mov al, [si]
    imul byte [gl_cosy]
    mov di, ax
    mov al, [si+2]
    imul byte [gl_siny]
    sub di, ax
    call gl_sh7
    mov [gl_rx], al
    mov al, [si]
    imul byte [gl_siny]
    mov di, ax
    mov al, [si+2]
    imul byte [gl_cosy]
    add di, ax
    call gl_sh7
    mov [gl_rz], al
    mov al, [si+1]
    imul byte [gl_cosp]
    mov di, ax
    mov al, [gl_rz]
    imul byte [gl_sinp]
    sub di, ax
    call gl_sh7
    mov [gl_ry], al
    mov al, [si+1]
    imul byte [gl_sinp]
    mov di, ax
    mov al, [gl_rz]
    imul byte [gl_cosp]
    add di, ax
    call gl_sh7
    mov [gl_depth], al
    mov al, [gl_rx]
    cbw
    call gl_scaleax
    cmp byte [gl_persp], 0
    je .x
    push ax
    mov bl, al
    mov al, [gl_depth]
    imul byte bl
    mov di, ax
    call gl_sh8
    cbw
    pop bx
    add ax, bx                     ; x += x*depth/256
.x:
    add ax, [gl_cx]
    mov cx, ax
    mov al, [gl_ry]
    cbw
    call gl_scaleax
    cmp byte [gl_persp], 0
    je .y
    push ax
    mov bl, al
    mov al, [gl_depth]
    imul byte bl
    mov di, ax
    call gl_sh8
    cbw
    pop bx
    add ax, bx                     ; y += y*depth/256
.y:
    mov dx, [gl_cy]
    sub dx, ax
    add si, 3
    ret

; Draw the globe rim, an unrotated signed-byte polyline.
gl_path:
    lodsb
    cbw
    call gl_scaleax
    add ax, [gl_cx]
    mov [gl_x1], ax
    lodsb
    cbw
    call gl_scaleax
    add ax, [gl_cy]
    mov [gl_y1], ax
    mov [gl_left], cl
    dec byte [gl_left]
.next:
    lodsb
    cbw
    call gl_scaleax
    add ax, [gl_cx]
    mov cx, ax
    lodsb
    cbw
    call gl_scaleax
    add ax, [gl_cy]
    mov dx, ax
    mov ax, [gl_x1]
    mov bx, [gl_y1]
    call gl_line
    mov [gl_x1], cx
    mov [gl_y1], dx
    dec byte [gl_left]
    jnz .next
    ret

; Horizontal spans approximate a solid Q7 sphere.  Their endpoints use the
; same live scale as the rim, so the cyan ocean is always 80% of the window.
gl_disc:
    mov [gl_left], cl
.row:
    lodsb                           ; model y, then its half-width
    cbw
    call gl_scaleax
    add ax, [gl_cy]
    mov dx, ax
    lodsb
    cbw
    call gl_scaleax
    mov bx, ax
    neg ax
    add ax, [gl_cx]
    add bx, [gl_cx]
    call OSAPI_GFX_HLINE
    dec byte [gl_left]
    jnz .row
    ret

; A monochrome frame is composed in a 1bpp RAM band and presented in one (or
; a few 200-row) blits.  Colour mode remains direct because a 1bpp band has
; only one ink colour.  The band covers the whole content rectangle, so its
; white paper also removes the previous frame without a visible erase pass.
gl_mask_begin:
    mov ax, [gl_ox]
    and ax, 0fff8h
    mov [gl_bx0], ax
    mov bx, [gl_ox]
    add bx, [gl_cw]
    sub bx, ax
    add bx, 7
    and bx, 0fff8h
    mov [gl_bw], bx
    mov ax, [gl_oy]
    mov [gl_by0], ax
    mov ax, [gl_ch]
    mov [gl_bh], ax
    ; Rows in RAM have the fixed GL_BUF_ST stride.  Clear that stride for
    ; every live row, not just the visible byte width: otherwise the lower
    ; rows retain pixels from an earlier frame after the globe moves.
    mov ax, GL_BUF_ST
    mul word [gl_bh]
    mov cx, ax
    mov di, gl_mask
    push es
    push ds
    pop es
    xor al, al
    rep stosb
    pop es
    ret

; Present the whole frame; BLIT1 accepts at most 255 rows at a time.
gl_mask_put:
    mov al, CBLACK
    mov ah, CWHITE
    call OSAPI_GFX_BLIT1_PEN
    push es
    push ds
    pop es
    mov si, gl_mask
    mov bp, GL_BUF_ST
    mov ax, [gl_bx0]
    mov bx, [gl_by0]
    mov cx, [gl_bw]
    mov dx, [gl_bh]
.rows:
    ; BLIT1 takes ES:SI and BP.  Re-arm both for *every* band: the first
    ; arrival is allowed to use its own ES/BP scratch, while the next one
    ; must still read our RAM mask rather than the kernel segment.
    push ds
    pop es
    mov bp, GL_BUF_ST
    mov ax, [gl_bx0]
    mov cx, [gl_bw]
    cmp dx, 200
    jbe .last
    push dx
    mov dx, 200
    call OSAPI_GFX_BLIT1
    jc .refused
    pop dx
    add si, GL_BUF_ST * 200
    add bx, 200
    sub dx, 200
    jmp short .rows
.last:
    call OSAPI_GFX_BLIT1
    jnc .done
.refused:
    mov byte [gl_buffer_bad], 1
    ; kern_small has no BLIT1 implementation.  A later input repaint falls
    ; back to the normal clipped line renderer instead of touching the band.
.done:
    pop es
    ret

; Preserve the API line contract for gl_contour/gl_path.  In buffer mode the
; endpoints are changed into content-relative coordinates and rasterised in
; our 1bpp frame; otherwise this is the ordinary clipped kernel line.
gl_line:
    cmp byte [gl_buffer], 0
    je .screen
    push ax
    push bx
    push cx
    push dx
    push si
    push di
    push bp
    sub ax, [gl_bx0]
    sub cx, [gl_bx0]
    sub bx, [gl_by0]
    sub dx, [gl_by0]
    mov [gl_mx1], ax
    mov [gl_my1], bx
    mov [gl_mx2], cx
    mov [gl_my2], dx
    call gl_mask_line
    pop bp
    pop di
    pop si
    pop dx
    pop cx
    pop bx
    pop ax
    ret
.screen:
    push si
    xor si, si                      ; OSAPI_GFX_LINE: SI=0 is a one-pixel line
    call OSAPI_GFX_LINE
    pop si
    ret

; Bresenham into a set-bit buffer.  gl_mask_begin puts every projected point
; inside this content-sized band; WM_CLIP_SET remains the final guard at
; presentation time for a moved/covered window.
gl_mask_line:
    mov ax, [gl_mx1]
    mov cx, [gl_mx2]
    cmp ax, cx
    jle .ordered
    mov [gl_mx1], cx
    mov [gl_mx2], ax
    mov ax, [gl_my1]
    mov cx, [gl_my2]
    mov [gl_my1], cx
    mov [gl_my2], ax
.ordered:
    mov ax, [gl_mx2]
    sub ax, [gl_mx1]
    mov [gl_mdx], ax
    mov ax, [gl_my2]
    sub ax, [gl_my1]
    mov word [gl_msy], GL_BUF_ST
    jns .dy
    neg ax
    mov word [gl_msy], -GL_BUF_ST
.dy:
    mov [gl_mdy], ax
    mov ax, [gl_my1]
    mov bx, GL_BUF_ST
    mul bx
    mov di, ax
    mov ax, [gl_mx1]
    mov bx, ax
    mov cl, 3
    shr bx, cl
    add di, bx
    and al, 7
    mov cl, al
    mov bl, 80h
    ror bl, cl
    mov ax, [gl_mdx]
    cmp ax, [gl_mdy]
    jl .majy
    mov si, ax
    inc si
    mov bp, [gl_mdy]
    add bp, bp
    mov [gl_me1], bp
    sub bp, ax
    add ax, ax
    mov [gl_me2], ax
.mx:
    or [gl_mask + di], bl
    shr bl, 1
    jnz .mxbit
    mov bl, 80h
    inc di
.mxbit:
    add bp, [gl_me1]
    jle .mxnext
    sub bp, [gl_me2]
    add di, [gl_msy]
.mxnext:
    dec si
    jnz .mx
    ret
.majy:
    mov si, [gl_mdy]
    inc si
    mov bp, [gl_mdx]
    add bp, bp
    mov [gl_me1], bp
    sub bp, [gl_mdy]
    mov ax, [gl_mdy]
    add ax, ax
    mov [gl_me2], ax
.my:
    or [gl_mask + di], bl
    add di, [gl_msy]
    add bp, [gl_me1]
    jle .mynext
    sub bp, [gl_me2]
    shr bl, 1
    jnz .mynext
    mov bl, 80h
    inc di
.mynext:
    dec si
    jnz .my
    ret

; Signed Q7 / Q8 helpers.
gl_sh7: mov ax, di
        add ax, ax
        mov al, ah
        ret
gl_sh8: mov ax, di
        sar ax, 1
        mov al, ah
        ret
gl_scaleax:
    imul word [gl_scale]
    mov di, ax
    call gl_sh7
    cbw
    ret

gl_tpl:
    dw 174, 92, GL_W, GL_H
    dw gl_title, gl_paint, gl_onkey, 0
    OS88_MENUSET gl_menus, gl_name, gl_oncmd
        OS88_MENU gl_m_view, gl_i_view, 7
    OS88_MENUSET_END gl_menus
gl_name: db 'Globe', 0
gl_m_view: db 'View', 0
gl_i_view: dw gl_i_auto, gl_i_persp, gl_i_iso, gl_i_max, gl_i_restore, gl_i_color, gl_i_grid
gl_i_auto: db 'Auto Rotate', 0
gl_i_persp: db 'Perspective', 0
gl_i_iso: db 'Isometric', 0
gl_i_max: db 'Maximize', 0
gl_i_restore: db 'Restore', 0
gl_i_color: db 'Color', 0
gl_i_grid: db 'Graticule', 0
gl_title: db 'Globe 1.0', 0
gl_about_1: db 'Globe 1.0', 0
gl_about_2: db 'Interactive terrestrial wireframe', 0
gl_about_3: db 'Contributed by Rui Ribeiro', 0

; Globe rim only. All interior paths below are named continental coastlines.
gl_outline:
    db 0,-104,40,-96,74,-74,96,-40,104,0,96,40,74,74,40,96
    db 0,104,-40,96,-74,74,-96,40,-104,0,-96,-40,-74,-74,-40,-96,0,-104

; y, half-width pairs: a compact filled-disc stencil, symmetric about zero.
gl_disc_spans:
    db -104,0,-96,40,-87,57,-71,76,-50,91,-26,101,0,104
    db 26,101,50,91,71,76,87,57,96,40,104,0

; Simplified ESRI/Figshare continent polygons, generated with an explicit
; per-ring point budget.  See globe_contours.inc for CC BY 4.0 attribution.
%include "globe_contours.inc"

; The equator, both tropics, both polar circles and four meridians.  This is
; separate from the coastline dataset so the View toggle can be instant.
%include "globe_graticule.inc"

gl_sintab:
%include "wiresin.inc"

    OS88_BSS 43910
    OS88_IMAGE_END
gl_cx equ os88_image_end+0
gl_cy equ os88_image_end+2
gl_x1 equ os88_image_end+4
gl_y1 equ os88_image_end+6
gl_left equ os88_image_end+8
gl_yaw equ os88_image_end+9
gl_pitch equ os88_image_end+10
gl_auto equ os88_image_end+11
gl_siny equ os88_image_end+12
gl_cosy equ os88_image_end+13
gl_sinp equ os88_image_end+14
gl_cosp equ os88_image_end+15
gl_rx equ os88_image_end+16
gl_ry equ os88_image_end+17
gl_rz equ os88_image_end+18
gl_depth equ os88_image_end+19
gl_visible equ os88_image_end+20
gl_persp equ os88_image_end+21
gl_full equ os88_image_end+22
gl_color equ os88_image_end+23
gl_grid equ os88_image_end+24
gl_scale equ os88_image_end+25
gl_about_on equ os88_image_end+27
gl_buffer equ os88_image_end+28
gl_buffer_bad equ os88_image_end+29
gl_radius equ os88_image_end+30
gl_ox equ os88_image_end+32
gl_oy equ os88_image_end+34
gl_cw equ os88_image_end+36
gl_ch equ os88_image_end+38
gl_bx0 equ os88_image_end+40
gl_by0 equ os88_image_end+42
gl_bw equ os88_image_end+44
gl_bh equ os88_image_end+46
gl_mx1 equ os88_image_end+48
gl_my1 equ os88_image_end+50
gl_mx2 equ os88_image_end+52
gl_my2 equ os88_image_end+54
gl_mdx equ os88_image_end+56
gl_mdy equ os88_image_end+58
gl_msy equ os88_image_end+60
gl_me1 equ os88_image_end+62
gl_me2 equ os88_image_end+64
gl_fill_n equ os88_image_end+66
gl_fill_i equ os88_image_end+67
gl_fill_min equ os88_image_end+68
gl_fill_max equ os88_image_end+70
gl_scan equ os88_image_end+72
gl_fill_have equ os88_image_end+74
gl_fill_a equ os88_image_end+76
gl_fill_b equ os88_image_end+78
gl_fill_xlo equ os88_image_end+80
gl_fill_xhi equ os88_image_end+82
gl_fill_left equ os88_image_end+84
gl_firstd equ os88_image_end+85
gl_prevd equ os88_image_end+86
gl_curd equ os88_image_end+87
gl_firstx equ os88_image_end+88
gl_firsty equ os88_image_end+90
gl_prevx equ os88_image_end+92
gl_prevy equ os88_image_end+94
gl_curx equ os88_image_end+96
gl_cury equ os88_image_end+98
gl_ix equ os88_image_end+100
gl_px equ os88_image_end+102
gl_py equ os88_image_end+166
gl_mask equ os88_image_end+230
