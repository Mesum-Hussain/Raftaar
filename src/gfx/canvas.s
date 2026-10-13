# software canvas: 32-bit XRGB target, clip stack, rects, rounded rects, alpha masks
.include "raftaar.inc"

.equ CLIP_DEPTH, 32

.bss
.p2align 4
.globl g_cv
g_cv: .zero CV_SIZE
clip_stack: .zero 16 * CLIP_DEPTH
clip_sp: .quad 0

.text

# gfx_set_target(pixels, w, h, stride_px)
FN gfx_set_target
    mov [rip + g_cv + CV_pixels], rdi
    mov [rip + g_cv + CV_w], esi
    mov [rip + g_cv + CV_h], edx
    mov [rip + g_cv + CV_stride], ecx
    mov dword ptr [rip + g_cv + CV_cx0], 0
    mov dword ptr [rip + g_cv + CV_cy0], 0
    mov [rip + g_cv + CV_cx1], esi
    mov [rip + g_cv + CV_cy1], edx
    mov qword ptr [rip + clip_sp], 0
    ret

# gfx_clip_push(x, y, w, h): intersect clip with rect
FN gfx_clip_push
    mov rax, [rip + clip_sp]
    cmp rax, CLIP_DEPTH
    jae 1f
    lea r8, [rip + clip_stack]
    shl rax, 4
    mov r9, [rip + g_cv + CV_cx0]
    mov [r8 + rax], r9
    mov r9, [rip + g_cv + CV_cx1]
    mov [r8 + rax + 8], r9
    inc qword ptr [rip + clip_sp]
1:  lea edx, [rdx + rdi]        # x1
    lea ecx, [rcx + rsi]        # y1
    mov eax, [rip + g_cv + CV_cx0]
    cmp edi, eax
    cmovl edi, eax
    mov eax, [rip + g_cv + CV_cy0]
    cmp esi, eax
    cmovl esi, eax
    mov eax, [rip + g_cv + CV_cx1]
    cmp edx, eax
    cmovg edx, eax
    mov eax, [rip + g_cv + CV_cy1]
    cmp ecx, eax
    cmovg ecx, eax
    cmp edx, edi
    cmovl edx, edi
    cmp ecx, esi
    cmovl ecx, esi
    mov [rip + g_cv + CV_cx0], edi
    mov [rip + g_cv + CV_cy0], esi
    mov [rip + g_cv + CV_cx1], edx
    mov [rip + g_cv + CV_cy1], ecx
    ret

FN gfx_clip_pop
    mov rax, [rip + clip_sp]
    test rax, rax
    jz 1f
    dec rax
    mov [rip + clip_sp], rax
    lea r8, [rip + clip_stack]
    shl rax, 4
    mov r9, [r8 + rax]
    mov [rip + g_cv + CV_cx0], r9
    mov r9, [r8 + rax + 8]
    mov [rip + g_cv + CV_cx1], r9
1:  ret

# blend(dst eax, src ecx, alpha edx 0..255) -> eax ; clobbers r8-r11
.macro BLEND
    mov r8d, edx
    shr r8d, 7
    add r8d, edx                # a' in 0..256
    mov r9d, 256
    sub r9d, r8d                # 256 - a'
    mov r10d, ecx
    and r10d, 0xff00ff
    imul r10d, r8d
    mov r11d, eax
    and r11d, 0xff00ff
    imul r11d, r9d
    add r10d, r11d
    shr r10d, 8
    and r10d, 0xff00ff
    and ecx, 0x00ff00
    imul ecx, r8d
    and eax, 0x00ff00
    imul eax, r9d
    add eax, ecx
    shr eax, 8
    and eax, 0x00ff00
    or eax, r10d
    or eax, 0xff000000
.endm

# gfx_fill(x, y, w, h, argb)
FN gfx_fill
    push rbx
    push r12
    push r13
    push r14
    push r15
    lea edx, [rdx + rdi]        # x1
    lea ecx, [rcx + rsi]        # y1
    mov eax, [rip + g_cv + CV_cx0]
    cmp edi, eax
    cmovl edi, eax
    mov eax, [rip + g_cv + CV_cy0]
    cmp esi, eax
    cmovl esi, eax
    mov eax, [rip + g_cv + CV_cx1]
    cmp edx, eax
    cmovg edx, eax
    mov eax, [rip + g_cv + CV_cy1]
    cmp ecx, eax
    cmovg ecx, eax
    sub edx, edi                # w
    jle .Lfill_ret
    sub ecx, esi                # h
    jle .Lfill_ret
    mov r12d, edx
    mov r13d, ecx
    mov ebx, r8d                # color
    movsxd rdi, edi
    movsxd rsi, esi
    mov eax, [rip + g_cv + CV_stride]
    mov r14, rax
    imul rsi, rax
    add rsi, rdi
    mov r15, [rip + g_cv + CV_pixels]
    lea r15, [r15 + rsi*4]      # row ptr
    mov eax, ebx
    shr eax, 24
    cmp eax, 255
    jne .Lfill_blend
    or ebx, 0xff000000
.Lfill_row:
    mov rdi, r15
    mov eax, ebx
    mov ecx, r12d
    rep stosd
    lea r15, [r15 + r14*4]
    dec r13d
    jnz .Lfill_row
    jmp .Lfill_ret
.Lfill_blend:
    test eax, eax
    jz .Lfill_ret
    mov esi, eax                # alpha
    cmp r12d, 4
    jae .Lfill_wide
.Lfill_brow:
    xor edi, edi
.Lfill_bpx:
    mov eax, [r15 + rdi*4]
    mov ecx, ebx
    mov edx, esi
    BLEND
    mov [r15 + rdi*4], eax
    inc edi
    cmp edi, r12d
    jb .Lfill_bpx
    lea r15, [r15 + r14*4]
    dec r13d
    jnz .Lfill_brow
.Lfill_ret:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret
# four pixels at a time, as BLEND has each channel: (color * a' + pixel * (256 - a')) >> 8, opaque;
# the color's share is the same for every pixel. A modal's shade over the whole window took most of
# its frame one pixel at a time. The xmm registers it takes are given back.
.Lfill_wide:
    sub rsp, 96
    movdqu [rsp], xmm0
    movdqu [rsp + 16], xmm1
    movdqu [rsp + 32], xmm4
    movdqu [rsp + 48], xmm5
    movdqu [rsp + 64], xmm6
    movdqu [rsp + 80], xmm7
    mov eax, esi
    shr eax, 7
    add eax, esi                # a' 0..256
    mov ecx, 256
    sub ecx, eax
    movd xmm4, ecx
    pshuflw xmm4, xmm4, 0
    punpcklqdq xmm4, xmm4       # 256 - a' in every word
    movd xmm0, eax
    pshuflw xmm0, xmm0, 0       # a' in the low four
    pxor xmm6, xmm6
    movd xmm5, ebx
    punpcklbw xmm5, xmm6        # the color's channels as words
    pmullw xmm5, xmm0
    punpcklqdq xmm5, xmm5       # times a', for two pixels
    mov eax, 0xff000000
    movd xmm7, eax
    pshufd xmm7, xmm7, 0
.Lfill_wrow:
    xor edi, edi
.Lfill_w4:
    lea eax, [rdi + 4]
    cmp eax, r12d
    ja .Lfill_wtail
    movdqu xmm0, [r15 + rdi*4]
    movdqu xmm1, xmm0
    psrldq xmm1, 8
    punpcklbw xmm0, xmm6
    punpcklbw xmm1, xmm6
    pmullw xmm0, xmm4
    pmullw xmm1, xmm4
    paddw xmm0, xmm5
    paddw xmm1, xmm5
    psrlw xmm0, 8
    psrlw xmm1, 8
    packuswb xmm0, xmm1
    por xmm0, xmm7
    movdqu [r15 + rdi*4], xmm0
    add edi, 4
    jmp .Lfill_w4
.Lfill_wtail:
    cmp edi, r12d
    jae .Lfill_wnext
    mov eax, [r15 + rdi*4]
    mov ecx, ebx
    mov edx, esi
    BLEND
    mov [r15 + rdi*4], eax
    inc edi
    jmp .Lfill_wtail
.Lfill_wnext:
    lea r15, [r15 + r14*4]
    dec r13d
    jnz .Lfill_wrow
    movdqu xmm0, [rsp]
    movdqu xmm1, [rsp + 16]
    movdqu xmm4, [rsp + 32]
    movdqu xmm5, [rsp + 48]
    movdqu xmm6, [rsp + 64]
    movdqu xmm7, [rsp + 80]
    add rsp, 96
    jmp .Lfill_ret

# gfx_blend_px(x, y, argb, alpha 0..255): alpha is multiplied with color alpha
FN gfx_blend_px
    cmp edi, [rip + g_cv + CV_cx0]
    jl 1f
    cmp edi, [rip + g_cv + CV_cx1]
    jge 1f
    cmp esi, [rip + g_cv + CV_cy0]
    jl 1f
    cmp esi, [rip + g_cv + CV_cy1]
    jge 1f
    mov eax, edx
    shr eax, 24
    imul ecx, eax
    lea eax, [rcx + 128]
    shr eax, 8
    add ecx, eax
    shr ecx, 8                  # alpha * a / 255
    test ecx, ecx
    jz 1f
    push rbx
    mov ebx, edx
    mov edx, ecx
    mov ecx, ebx
    movsxd rsi, esi
    movsxd rdi, edi
    mov eax, [rip + g_cv + CV_stride]
    imul rsi, rax
    add rsi, rdi
    mov rdi, [rip + g_cv + CV_pixels]
    lea rdi, [rdi + rsi*4]
    mov eax, [rdi]
    BLEND
    mov [rdi], eax
    pop rbx
1:  ret

# gfx_round_rect(x, y, w, h, r, argb)
FN gfx_round_rect
    PROLOGUE 48
    mov r12d, edi               # x
    mov r13d, esi               # y
    mov r14d, edx               # w
    mov r15d, ecx               # h
    mov [rsp + 36], r9d         # color
    # clamp radius to min(w,h)/2
    mov eax, edx
    cmp eax, ecx
    cmovg eax, ecx
    sar eax, 1
    cmp r8d, eax
    cmovg r8d, eax
    mov ebx, r8d                # r
    test ebx, ebx
    jle .Lrr_plain
    # middle band
    mov edi, r12d
    lea esi, [r13 + rbx]
    mov edx, r14d
    mov ecx, r15d
    sub ecx, ebx
    sub ecx, ebx
    mov r8d, r9d
    call gfx_fill
    # center spans of corner rows
    mov dword ptr [rsp], 0      # i
.Lrr_rows:
    mov eax, [rsp]
    cmp eax, ebx
    jge .Lrr_done
    lea edi, [r12 + rbx]
    lea esi, [r13 + rax]
    mov edx, r14d
    sub edx, ebx
    sub edx, ebx
    mov ecx, 1
    mov r8d, [rsp + 36]
    call gfx_fill
    mov eax, [rsp]
    lea edi, [r12 + rbx]
    lea esi, [r13 + r15 - 1]
    sub esi, eax
    mov edx, r14d
    sub edx, ebx
    sub edx, ebx
    mov ecx, 1
    mov r8d, [rsp + 36]
    call gfx_fill
    # corner pixels of this row
    mov dword ptr [rsp + 4], 0  # j
.Lrr_cols:
    mov eax, [rsp + 4]
    cmp eax, ebx
    jge .Lrr_nextrow
    # dx = r - j - 0.5 ; dy = r - i - 0.5
    cvtsi2ss xmm0, ebx
    cvtsi2ss xmm1, eax
    subss xmm0, xmm1
    subss xmm0, [rip + f_half]
    cvtsi2ss xmm2, ebx
    cvtsi2ss xmm1, dword ptr [rsp]
    subss xmm2, xmm1
    subss xmm2, [rip + f_half]
    mulss xmm0, xmm0
    mulss xmm2, xmm2
    addss xmm0, xmm2
    sqrtss xmm0, xmm0
    cvtsi2ss xmm1, ebx
    addss xmm1, [rip + f_half]
    subss xmm1, xmm0            # coverage
    maxss xmm1, [rip + f_zero]
    minss xmm1, [rip + f_one]
    mulss xmm1, [rip + f_255]
    cvtss2si eax, xmm1
    test eax, eax
    jz .Lrr_nextcol
    mov [rsp + 8], eax
    # top-left
    mov ecx, [rsp + 4]
    lea edi, [r12 + rcx]
    mov ecx, [rsp]
    lea esi, [r13 + rcx]
    mov edx, [rsp + 36]
    mov ecx, [rsp + 8]
    call gfx_blend_px
    # top-right
    mov ecx, [rsp + 4]
    lea edi, [r12 + r14 - 1]
    sub edi, ecx
    mov ecx, [rsp]
    lea esi, [r13 + rcx]
    mov edx, [rsp + 36]
    mov ecx, [rsp + 8]
    call gfx_blend_px
    # bottom-left
    mov ecx, [rsp + 4]
    lea edi, [r12 + rcx]
    mov ecx, [rsp]
    lea esi, [r13 + r15 - 1]
    sub esi, ecx
    mov edx, [rsp + 36]
    mov ecx, [rsp + 8]
    call gfx_blend_px
    # bottom-right
    mov ecx, [rsp + 4]
    lea edi, [r12 + r14 - 1]
    sub edi, ecx
    mov ecx, [rsp]
    lea esi, [r13 + r15 - 1]
    sub esi, ecx
    mov edx, [rsp + 36]
    mov ecx, [rsp + 8]
    call gfx_blend_px
.Lrr_nextcol:
    inc dword ptr [rsp + 4]
    jmp .Lrr_cols
.Lrr_nextrow:
    inc dword ptr [rsp]
    jmp .Lrr_rows
.Lrr_plain:
    mov edi, r12d
    mov esi, r13d
    mov edx, r14d
    mov ecx, r15d
    mov r8d, [rsp + 36]
    call gfx_fill
.Lrr_done:
    EPILOGUE

# gfx_px_fade(x, y, alpha 0..255): the pixel toward transparent black, all four channels
gfx_px_fade:
    cmp edi, [rip + g_cv + CV_cx0]
    jl 1f
    cmp edi, [rip + g_cv + CV_cx1]
    jge 1f
    cmp esi, [rip + g_cv + CV_cy0]
    jl 1f
    cmp esi, [rip + g_cv + CV_cy1]
    jge 1f
    movsxd rsi, esi
    movsxd rdi, edi
    mov eax, [rip + g_cv + CV_stride]
    imul rsi, rax
    add rsi, rdi
    mov rdi, [rip + g_cv + CV_pixels]
    lea rdi, [rdi + rsi*4]
    mov r8d, 255
    sub r8d, edx                # what stays
    mov eax, [rdi]
    xor r9d, r9d                # the result
    mov ecx, 4
2:  rol eax, 8
    movzx edx, al
    imul edx, r8d
    add edx, 127
    imul edx, edx, 0x8081       # / 255
    shr edx, 23
    shl r9d, 8
    or r9d, edx
    dec ecx
    jnz 2b
    mov [rdi], r9d
1:  ret

# gfx_card_edge(x, y, w, h, r, border, outside): what makes a rectangle already drawn a rounded card:
#   its corners outside the radius take the color around it and a 1px border (g_border) follows the
#   outline. An outside of 0 fades the corners to transparent instead (the window's own corners);
#   a border of 0 draws no line.
FN gfx_card_edge
    PROLOGUE 64
    mov r12d, edi               # x
    mov r13d, esi               # y
    mov r14d, edx               # w
    mov r15d, ecx               # h
    mov ebx, r8d                # r
    mov [rsp + 36], r9d         # border
    mov eax, [rbp + 16]
    mov [rsp + 40], eax         # outside
    mov eax, r14d
    cmp eax, r15d
    cmovg eax, r15d
    sar eax, 1
    cmp ebx, eax
    cmovg ebx, eax
    test ebx, ebx
    jg 1f
    xor ebx, ebx
1:  mov dword ptr [rsp], 0      # i
.Lce_rows:
    mov eax, [rsp]
    cmp eax, ebx
    jge .Lce_lines
    mov dword ptr [rsp + 4], 0  # j
.Lce_cols:
    mov eax, [rsp + 4]
    cmp eax, ebx
    jge .Lce_nextrow
    # distance of the pixel's middle from the corner's center
    cvtsi2ss xmm0, ebx
    cvtsi2ss xmm1, eax
    subss xmm0, xmm1
    subss xmm0, [rip + f_half]
    cvtsi2ss xmm2, ebx
    cvtsi2ss xmm1, dword ptr [rsp]
    subss xmm2, xmm1
    subss xmm2, [rip + f_half]
    mulss xmm0, xmm0
    mulss xmm2, xmm2
    addss xmm0, xmm2
    sqrtss xmm0, xmm0           # d
    # outside = clamp(d - r + 0.5)
    cvtsi2ss xmm1, ebx
    movss xmm3, xmm0
    subss xmm3, xmm1
    addss xmm3, [rip + f_half]
    maxss xmm3, [rip + f_zero]
    minss xmm3, [rip + f_one]
    # line = clamp(d - (r - border) + 0.5) - outside
    cvtsi2ss xmm2, dword ptr [rip + g_border]
    subss xmm1, xmm2
    movss xmm4, xmm0
    subss xmm4, xmm1
    addss xmm4, [rip + f_half]
    maxss xmm4, [rip + f_zero]
    minss xmm4, [rip + f_one]
    mulss xmm3, [rip + f_255]
    mulss xmm4, [rip + f_255]
    cvtss2si eax, xmm3
    mov [rsp + 8], eax          # outside 0..255
    cvtss2si eax, xmm4
    mov [rsp + 12], eax         # line and outside 0..255
    test eax, eax
    jz .Lce_nextcol
    mov dword ptr [rsp + 16], 0 # corner 0..3
.Lce_corner:
    mov ecx, [rsp + 4]
    lea edi, [r12 + rcx]
    test dword ptr [rsp + 16], 1
    jz 2f
    lea edi, [r12 + r14 - 1]
    sub edi, ecx
2:  mov ecx, [rsp]
    lea esi, [r13 + rcx]
    test dword ptr [rsp + 16], 2
    jz 3f
    lea esi, [r13 + r15 - 1]
    sub esi, ecx
3:  mov [rsp + 20], edi
    mov [rsp + 24], esi
    cmp dword ptr [rsp + 36], 0
    je 4f
    mov edx, [rsp + 36]
    mov ecx, [rsp + 12]
    call gfx_blend_px
4:  cmp dword ptr [rsp + 8], 0
    je 6f
    mov edi, [rsp + 20]
    mov esi, [rsp + 24]
    mov edx, [rsp + 40]
    test edx, edx
    jz 5f
    mov ecx, [rsp + 8]
    call gfx_blend_px
    jmp 6f
5:  mov edx, [rsp + 8]
    call gfx_px_fade
6:  inc dword ptr [rsp + 16]
    cmp dword ptr [rsp + 16], 4
    jb .Lce_corner
.Lce_nextcol:
    inc dword ptr [rsp + 4]
    jmp .Lce_cols
.Lce_nextrow:
    inc dword ptr [rsp]
    jmp .Lce_rows
.Lce_lines:
    cmp dword ptr [rsp + 36], 0
    je .Lce_done
    lea edi, [r12 + rbx]        # top
    mov esi, r13d
    mov edx, r14d
    sub edx, ebx
    sub edx, ebx
    mov ecx, [rip + g_border]
    mov r8d, [rsp + 36]
    call gfx_fill
    lea edi, [r12 + rbx]        # bottom
    lea esi, [r13 + r15]
    sub esi, [rip + g_border]
    mov edx, r14d
    sub edx, ebx
    sub edx, ebx
    mov ecx, [rip + g_border]
    mov r8d, [rsp + 36]
    call gfx_fill
    mov edi, r12d               # left
    lea esi, [r13 + rbx]
    mov edx, [rip + g_border]
    mov ecx, r15d
    sub ecx, ebx
    sub ecx, ebx
    mov r8d, [rsp + 36]
    call gfx_fill
    lea edi, [r12 + r14]        # right
    sub edi, [rip + g_border]
    lea esi, [r13 + rbx]
    mov edx, [rip + g_border]
    mov ecx, r15d
    sub ecx, ebx
    sub ecx, ebx
    mov r8d, [rsp + 36]
    call gfx_fill
.Lce_done:
    EPILOGUE

# gfx_frame(x, y, w, h, r, border, fill): rounded rect with 1px border (scaled by g_border)
FN gfx_frame
    PROLOGUE 16
    mov r12d, edi
    mov r13d, esi
    mov r14d, edx
    mov r15d, ecx
    mov ebx, r8d
    mov eax, [rbp + 16]         # fill (7th arg on stack)
    mov [rsp], eax
    mov r8d, ebx
    call gfx_round_rect
    mov eax, [rip + g_border]
    lea edi, [r12 + rax]
    lea esi, [r13 + rax]
    mov edx, r14d
    sub edx, eax
    sub edx, eax
    mov ecx, r15d
    sub ecx, eax
    sub ecx, eax
    mov r8d, ebx
    sub r8d, eax
    mov r9d, [rsp]
    call gfx_round_rect
    EPILOGUE

# gfx_mask(x, y, bits, w, h, argb): blend an 8-bit alpha mask
FN gfx_mask
    PROLOGUE 32
    mov [rsp], edi              # x
    mov [rsp + 4], esi          # y
    mov r12, rdx                # bits
    mov [rsp + 8], ecx          # w (mask stride)
    mov [rsp + 12], r8d         # h
    mov ebx, r9d                # color
    mov eax, ebx
    shr eax, 24
    mov [rsp + 16], eax         # color alpha
    # clipped span
    mov r13d, edi               # x0
    lea r14d, [rdi + rcx]       # x1
    mov eax, [rip + g_cv + CV_cx0]
    cmp r13d, eax
    cmovl r13d, eax
    mov eax, [rip + g_cv + CV_cx1]
    cmp r14d, eax
    cmovg r14d, eax
    cmp r14d, r13d
    jle .Lmk_ret
    mov r15d, esi               # y0
    lea eax, [rsi + r8]
    mov [rsp + 20], eax         # y1
    mov eax, [rip + g_cv + CV_cy0]
    cmp r15d, eax
    cmovl r15d, eax
    mov eax, [rip + g_cv + CV_cy1]
    cmp [rsp + 20], eax
    jle 1f
    mov [rsp + 20], eax
1:
.Lmk_row:
    cmp r15d, [rsp + 20]
    jge .Lmk_ret
    # src row = bits + (y - y0)*w
    mov eax, r15d
    sub eax, [rsp + 4]
    imul eax, [rsp + 8]
    movsxd rax, eax
    lea rsi, [r12 + rax]
    movsxd rax, dword ptr [rsp]
    sub rsi, rax                # so that rsi[x] is the mask byte for canvas x
    mov eax, r15d
    imul eax, [rip + g_cv + CV_stride]
    movsxd rax, eax
    mov rdi, [rip + g_cv + CV_pixels]
    lea rdi, [rdi + rax*4]
    movsxd r10, r13d
.Lmk_px:
    movzx edx, byte ptr [rsi + r10]
    test edx, edx
    jz .Lmk_next
    imul edx, [rsp + 16]
    lea eax, [rdx + 128]
    shr eax, 8
    add edx, eax
    shr edx, 8
    mov eax, [rdi + r10*4]
    mov ecx, ebx
    push r10
    BLEND
    pop r10
    mov [rdi + r10*4], eax
.Lmk_next:
    inc r10
    cmp r10d, r14d
    jl .Lmk_px
    inc r15d
    jmp .Lmk_row
.Lmk_ret:
    EPILOGUE

# color_mix(a, b, t 0..255) -> a*(1-t) + b*t, opaque
FN color_mix
    mov eax, edi
    mov ecx, esi
    push rbx
    BLEND
    pop rbx
    ret

# color_alpha(argb, alpha) -> color with alpha replaced
FN color_alpha
    mov eax, edi
    and eax, 0x00ffffff
    shl esi, 24
    or eax, esi
    ret

.section .rodata
.p2align 2
.globl f_half, f_zero, f_one, f_255, f_64
f_half: .float 0.5
f_zero: .float 0.0
f_one: .float 1.0
f_255: .float 255.0
f_64: .float 64.0

.data
.globl g_border
g_border: .long 1
