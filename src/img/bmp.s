# BMP and ICO / CUR: 1, 4, 8, 16, 24 and 32 bits per pixel, bit fields, top-down rows; icons by
# their largest entry, which may be a PNG or a bitmap with an AND mask
.include "raftaar.inc"

# channel from bit fields: ((px & mask) >> shift >> s2) * mult >> 16
STRUCT
F CH_mask, 4
F CH_shift, 4
F CH_s2, 4
F CH_mult, 4
ENDSTRUCT CH_SIZE

.bss
.p2align 3
img: .quad 0
pixels: .quad 0                 # first stored row
pend: .quad 0                   # end of the data
.p2align 2
pal: .zero 4 * 256
chans: .zero 4 * CH_SIZE        # red, green, blue, alpha
width: .long 0
height: .long 0
bpp: .long 0
topdown: .long 0
stride: .long 0
ico: .long 0

.text

# bmp_decode(ptr, len, IMG*) -> 0 or -1
FN bmp_decode
    push rbx
    mov [rip + img], rdx
    cmp rsi, 26
    jb 9f
    mov eax, [rdi + 10]         # pixel data offset
    cmp rax, rsi
    jae 9f
    lea rcx, [rdi + rax]
    mov [rip + pixels], rcx
    lea rcx, [rdi + rsi]
    mov [rip + pend], rcx
    add rdi, 14
    sub rsi, 14
    mov dword ptr [rip + ico], 0
    call dib
    pop rbx
    ret
9:  mov eax, -1
    pop rbx
    ret

# ico_decode(ptr, len, IMG*) -> 0 or -1: the entry with the most pixels, then the most bits
FN ico_decode
    PROLOGUE 16
    mov [rip + img], rdx
    mov r12, rdi
    mov r13, rsi
    movzx r14d, word ptr [r12 + 4]      # entries
    lea eax, [r14*8]
    lea eax, [rax*2 + 6]
    cmp rax, r13
    ja .Lico_fail
    xor ebx, ebx
    mov r15, -1                 # best entry
    mov qword ptr [rsp], -1     # its score
1:  cmp ebx, r14d
    jae 3f
    lea rdi, [rbx*8]
    lea rdi, [r12 + rdi*2 + 6]
    # data must lie in the file
    mov eax, [rdi + 8]
    mov ecx, [rdi + 12]
    add rax, rcx
    cmp rax, r13
    ja 2f
    cmp dword ptr [rdi + 8], 0
    je 2f
    movzx eax, byte ptr [rdi]
    dec al
    movzx eax, al
    inc eax                     # 0 means 256
    movzx ecx, byte ptr [rdi + 1]
    dec cl
    movzx ecx, cl
    inc ecx
    imul eax, ecx
    shl rax, 8
    movzx ecx, word ptr [rdi + 6]
    and ecx, 255
    or rax, rcx
    cmp rax, [rsp]
    jle 2f
    mov [rsp], rax
    mov r15, rdi
2:  inc ebx
    jmp 1b
3:  test r15, r15
    js .Lico_fail
    mov eax, [r15 + 12]
    lea rdi, [r12 + rax]
    mov esi, [r15 + 8]
    # PNG inside
    cmp rsi, 8
    jb 4f
    mov rax, 0x0a1a0a0d474e5089
    cmp [rdi], rax
    jne 4f
    mov rdx, [rip + img]
    call png_decode
    EPILOGUE
4:  lea rcx, [rdi + rsi]
    mov [rip + pend], rcx
    mov qword ptr [rip + pixels], 0
    mov dword ptr [rip + ico], 1
    call dib
    EPILOGUE
.Lico_fail:
    mov eax, -1
    EPILOGUE

# dib(header, bytes from it) -> 0 or -1: pixels at [pixels], or after the color table when that is 0
dib:
    PROLOGUE 32
    mov r12, rdi
    mov r13, rsi
    cmp r13, 12
    jb .Lfail
    mov ebx, [r12]              # header size
    cmp rbx, r13
    ja .Lfail
    xor r14d, r14d              # compression
    cmp ebx, 12
    jne 1f
    # OS/2: 16-bit sizes, 3-byte palette entries
    movzx eax, word ptr [r12 + 4]
    mov [rip + width], eax
    movzx ecx, word ptr [r12 + 6]
    movzx eax, word ptr [r12 + 10]
    mov [rip + bpp], eax
    mov r15d, 3                 # palette entry size
    mov dword ptr [rsp + 4], 0  # colors
    jmp 2f
1:  cmp ebx, 40
    jb .Lfail
    mov eax, [r12 + 4]
    mov [rip + width], eax
    mov ecx, [r12 + 8]
    movzx eax, word ptr [r12 + 14]
    mov [rip + bpp], eax
    mov r14d, [r12 + 16]
    mov eax, [r12 + 32]
    mov [rsp + 4], eax
    mov r15d, 4
2:  # rows run up unless the height is negative
    xor eax, eax
    test ecx, ecx
    jns 21f
    neg ecx
    mov eax, 1
21: mov [rip + topdown], eax
    cmp dword ptr [rip + ico], 0
    je 22f
    shr ecx, 1                  # icons: color and mask halves
22: mov [rip + height], ecx
    mov eax, [rip + width]
    test eax, eax
    jle .Lfail
    test ecx, ecx
    jle .Lfail
    # bit fields
    mov dword ptr [rsp], 0      # alpha from the pixels
    cmp r14d, 3
    je 3f
    cmp r14d, 6
    je 3f
    test r14d, r14d
    jnz .Lunsupported           # RLE, embedded JPEG / PNG
    mov eax, [rip + bpp]
    cmp eax, 16
    jne 23f
    mov edi, 0x7c00
    mov esi, 0x03e0
    mov edx, 0x001f
    xor ecx, ecx
    jmp 5f
23: mov edi, 0xff0000
    mov esi, 0xff00
    mov edx, 0xff
    xor ecx, ecx
    cmp eax, 32
    jne 5f
    mov ecx, 0xff000000         # taken when some pixel has it
    mov dword ptr [rsp], 1
    jmp 5f
3:  # in the header (V2 and later), or right after a 40-byte one
    cmp ebx, 52
    jae 31f
    mov eax, 52
    cmp r14d, 6
    jne 30f
    mov eax, 56
30: cmp rax, r13
    ja .Lfail
31: mov edi, [r12 + 40]
    mov esi, [r12 + 44]
    mov edx, [r12 + 48]
    xor ecx, ecx
    cmp ebx, 56
    jae 32f
    cmp r14d, 6
    jne 5f
32: mov ecx, [r12 + 52]
    test ecx, ecx
    jz 5f
    mov dword ptr [rsp], 1
5:  push rcx
    push rdx
    push rsi
    mov esi, edi
    lea rdi, [rip + chans]
    call chan_params
    pop rsi
    lea rdi, [rip + chans + CH_SIZE]
    call chan_params
    pop rsi
    lea rdi, [rip + chans + 2*CH_SIZE]
    call chan_params
    pop rsi
    lea rdi, [rip + chans + 3*CH_SIZE]
    call chan_params
    # where the color table (or the pixels) start
    lea rsi, [r12 + rbx]
    cmp ebx, 40
    jne 51f
    cmp r14d, 3
    jne 50f
    add rsi, 12
50: cmp r14d, 6
    jne 51f
    add rsi, 16
51: mov eax, [rip + bpp]
    cmp eax, 8
    ja 7f
    # color table: 2^bpp entries, or as many as the header says
    mov ecx, eax
    mov eax, 1
    shl eax, cl
    mov ecx, [rsp + 4]
    test ecx, ecx
    jz 6f
    cmp ecx, eax
    cmovb eax, ecx
6:  lea rdi, [rip + pal]
    xor ecx, ecx
62: cmp ecx, 256
    jae 7f
    mov dword ptr [rdi + rcx*4], 0xff000000
    cmp ecx, eax
    jae 63f
    lea rdx, [rsi + r15]
    cmp rdx, [rip + pend]
    ja 63f
    mov edx, [rsi]              # (a 3-byte entry reads one more byte, still inside the file)
    and edx, 0xffffff
    or edx, 0xff000000
    mov [rdi + rcx*4], edx
    add rsi, r15
63: inc ecx
    jmp 62b
7:  cmp qword ptr [rip + pixels], 0
    jne 8f
    mov [rip + pixels], rsi     # icons: right after
8:  # rows of whole 32-bit words
    mov eax, [rip + bpp]
    cmp eax, 1
    je 81f
    cmp eax, 4
    je 81f
    cmp eax, 8
    je 81f
    cmp eax, 16
    je 81f
    cmp eax, 24
    je 81f
    cmp eax, 32
    jne .Lunsupported
81: imul eax, [rip + width]
    add rax, 31
    shr rax, 5
    shl eax, 2
    mov [rip + stride], eax
    mov rdi, [rip + img]
    mov esi, [rip + width]
    mov edx, [rip + height]
    call img_alloc
    test rax, rax
    jz .Lfail
    call rows
    # alpha that is zero everywhere was never meant as alpha
    cmp dword ptr [rsp], 0
    je 9f
    call alpha_used
    test eax, eax
    jnz 9f
    call opaque_all
    mov dword ptr [rsp], 0
9:  # icons without alpha: the AND mask says what is transparent
    cmp dword ptr [rip + ico], 0
    je 91f
    cmp dword ptr [rsp], 0
    jne 91f
    call and_mask
91: xor eax, eax
    EPILOGUE
.Lunsupported:
    lea rax, [rip + .Lerr_kind]
    mov [rip + g_img_err], rax
.Lfail:
    mov eax, -1
    EPILOGUE

# chan_params(CH*, mask)
chan_params:
    mov [rdi + CH_mask], esi
    xor eax, eax
    mov [rdi + CH_shift], eax
    mov [rdi + CH_s2], eax
    mov [rdi + CH_mult], eax
    test esi, esi
    jz 9f
    bsf ecx, esi
    mov [rdi + CH_shift], ecx
    shr esi, cl
    bsr ecx, esi
    inc ecx                     # bits of the field
    xor eax, eax
    cmp ecx, 8
    jbe 1f
    lea eax, [rcx - 8]
    mov ecx, 8
1:  mov [rdi + CH_s2], eax
    mov eax, 1
    shl eax, cl
    dec eax
    mov ecx, eax
    mov eax, 255 << 16
    xor edx, edx
    div ecx
    mov [rdi + CH_mult], eax
9:  ret

# FIELD ch: ecx = channel ch of the pixel in eax, 0..255
.macro FIELD ch
    mov ecx, [rip + chans + \ch*CH_SIZE + CH_shift]
    mov edx, eax
    and edx, [rip + chans + \ch*CH_SIZE + CH_mask]
    shr edx, cl
    mov ecx, [rip + chans + \ch*CH_SIZE + CH_s2]
    shr edx, cl
    imul edx, [rip + chans + \ch*CH_SIZE + CH_mult]
    shr edx, 16
    mov ecx, edx
.endm

# rows(): the stored rows into the image, straight ARGB
rows:
    PROLOGUE 16
    mov rbx, [rip + img]
    # bit fields that are plain bytes need no work
    xor eax, eax
    cmp dword ptr [rip + chans + CH_mask], 0xff0000
    jne 1f
    cmp dword ptr [rip + chans + CH_SIZE + CH_mask], 0xff00
    jne 1f
    cmp dword ptr [rip + chans + 2*CH_SIZE + CH_mask], 0xff
    jne 1f
    mov ecx, [rip + chans + 3*CH_SIZE + CH_mask]
    mov eax, 1                  # alpha byte kept
    cmp ecx, 0xff000000
    je 1f
    mov eax, 2                  # opaque
    test ecx, ecx
    jz 1f
    xor eax, eax
1:  mov [rsp], eax
    xor r12d, r12d              # image row
.Lrow:
    cmp r12d, [rip + height]
    jae .Lrows_done
    mov eax, r12d
    cmp dword ptr [rip + topdown], 0
    jne 2f
    mov eax, [rip + height]
    sub eax, r12d
    dec eax
2:  mov ecx, [rip + stride]
    imul rax, rcx
    mov rsi, [rip + pixels]
    add rsi, rax
    lea rdx, [rsi + rcx]
    cmp rdx, [rip + pend]
    ja .Lrow_next               # beyond the data: stays transparent
    mov eax, r12d
    imul eax, [rbx + IMG_w]
    mov rdi, [rbx + IMG_px]
    lea rdi, [rdi + rax*4]
    mov r13d, [rip + width]
    xor r11d, r11d              # x
    mov eax, [rip + bpp]
    cmp eax, 8
    jbe .Lindexed
    cmp eax, 24
    je .L24
    cmp eax, 16
    je .L16
    mov eax, [rsp]
    cmp eax, 1
    je .L32argb
    cmp eax, 2
    je .L32rgb
.L32:
    mov eax, [rsi + r11*4]
    call fields
    mov [rdi + r11*4], eax
    inc r11d
    cmp r11d, r13d
    jb .L32
    jmp .Lrow_next
.L32argb:
    mov eax, [rsi + r11*4]
    mov [rdi + r11*4], eax
    inc r11d
    cmp r11d, r13d
    jb .L32argb
    jmp .Lrow_next
.L32rgb:
    mov eax, [rsi + r11*4]
    or eax, 0xff000000
    mov [rdi + r11*4], eax
    inc r11d
    cmp r11d, r13d
    jb .L32rgb
    jmp .Lrow_next
.L16:
    movzx eax, word ptr [rsi + r11*2]
    call fields
    mov [rdi + r11*4], eax
    inc r11d
    cmp r11d, r13d
    jb .L16
    jmp .Lrow_next
.L24:
    movzx eax, byte ptr [rsi + 2]
    shl eax, 8
    mov al, [rsi + 1]
    shl eax, 8
    mov al, [rsi]
    or eax, 0xff000000
    mov [rdi + r11*4], eax
    add rsi, 3
    inc r11d
    cmp r11d, r13d
    jb .L24
    jmp .Lrow_next
.Lindexed:
    mov r9d, eax                # bits
    mov ecx, eax
    mov r8d, 1
    shl r8d, cl
    dec r8d                     # mask
    xor r10d, r10d              # bits used in this byte
    lea r14, [rip + pal]
3:  movzx eax, byte ptr [rsi]
    mov ecx, 8
    sub ecx, r10d
    sub ecx, r9d
    shr eax, cl
    and eax, r8d
    mov eax, [r14 + rax*4]
    mov [rdi + r11*4], eax
    add r10d, r9d
    cmp r10d, 8
    jb 4f
    xor r10d, r10d
    inc rsi
4:  inc r11d
    cmp r11d, r13d
    jb 3b
.Lrow_next:
    inc r12d
    jmp .Lrow
.Lrows_done:
    EPILOGUE

# fields(eax pixel) -> eax ARGB by the bit fields (alpha 255 without an alpha field); clobbers rcx, rdx, r8-r10
fields:
    mov r10d, eax
    FIELD 0
    mov r8d, ecx
    mov eax, r10d
    FIELD 1
    mov r9d, ecx
    mov eax, r10d
    FIELD 2
    mov eax, 255
    cmp dword ptr [rip + chans + 3*CH_SIZE + CH_mask], 0
    je 1f
    push rcx
    mov eax, r10d
    FIELD 3
    mov eax, ecx
    pop rcx
1:  shl eax, 8
    or eax, r8d
    shl eax, 8
    or eax, r9d
    shl eax, 8
    or eax, ecx
    ret

# alpha_used() -> 1 if some pixel has alpha
alpha_used:
    mov rax, [rip + img]
    mov rdi, [rax + IMG_px]
    mov ecx, [rax + IMG_w]
    imul ecx, [rax + IMG_h]
1:  test dword ptr [rdi], 0xff000000
    jnz 2f
    add rdi, 4
    dec ecx
    jnz 1b
    xor eax, eax
    ret
2:  mov eax, 1
    ret

# opaque_all(): every pixel opaque
opaque_all:
    mov rax, [rip + img]
    mov rdi, [rax + IMG_px]
    mov ecx, [rax + IMG_w]
    imul ecx, [rax + IMG_h]
1:  or dword ptr [rdi], 0xff000000
    add rdi, 4
    dec ecx
    jnz 1b
    ret

# and_mask(): an icon's 1-bit mask, rows bottom up after the color rows; set bits are transparent
and_mask:
    push rbx
    push r12
    mov rbx, [rip + img]
    mov eax, [rip + stride]
    imul eax, [rip + height]
    mov rsi, [rip + pixels]
    add rsi, rax                # the mask
    mov r8d, [rip + width]
    add r8d, 31
    shr r8d, 5
    shl r8d, 2                  # its stride
    xor r9d, r9d                # image row
1:  cmp r9d, [rip + height]
    jae 9f
    mov eax, [rip + height]
    sub eax, r9d
    dec eax
    imul eax, r8d
    lea r10, [rsi + rax]
    lea rax, [r10 + r8]
    cmp rax, [rip + pend]
    ja 4f
    mov eax, r9d
    imul eax, [rbx + IMG_w]
    mov rdi, [rbx + IMG_px]
    lea rdi, [rdi + rax*4]
    xor r11d, r11d
2:  cmp r11d, [rip + width]
    jae 4f
    mov eax, r11d
    shr eax, 3
    movzx eax, byte ptr [r10 + rax]
    mov ecx, r11d
    and ecx, 7
    xor ecx, 7
    bt eax, ecx
    jnc 3f
    mov dword ptr [rdi + r11*4], 0
3:  inc r11d
    jmp 2b
4:  inc r9d
    jmp 1b
9:  pop r12
    pop rbx
    ret

.section .rodata
.Lerr_kind: .asciz "Compressed (RLE) bitmaps are not supported"
