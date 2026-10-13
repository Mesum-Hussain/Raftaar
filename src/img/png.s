# PNG: every color type and bit depth, tRNS, Adam7 interlacing
.include "raftaar.inc"

.equ CH_IHDR, 0x52444849
.equ CH_PLTE, 0x45544c50
.equ CH_tRNS, 0x534e5274
.equ CH_IDAT, 0x54414449
.equ CH_IEND, 0x444e4549
.equ CH_CgBI, 0x49426743

.bss
.p2align 3
img: .quad 0
width: .long 0
height: .long 0
depth: .long 0
ctype: .long 0
interlace: .long 0
chans: .long 0
bpp: .long 0                    # bytes per complete pixel, at least 1 (filter distance)
has_trns: .long 0
trns_len: .long 0               # bytes of a sample to compare against trns_key
.p2align 3
trns_key: .quad 0               # the transparent color exactly as it appears in a row
idat: .zero SB_SIZE
raw: .quad 0
zero_row: .quad 0
conv: .quad 0                   # row converter
.p2align 4
pal: .zero 4 * 256              # RGB
pal_a: .zero 256
lut: .zero 4 * 256              # ARGB for palette and low bit depth gray

.text

# png_decode(ptr, len, IMG*) -> 0 or -1
FN png_decode
    PROLOGUE 64
    mov [rip + img], rdx
    mov r12, rdi
    lea r13, [rdi + rsi]
    mov dword ptr [rip + width], 0
    mov dword ptr [rip + has_trns], 0
    mov qword ptr [rip + raw], 0
    mov qword ptr [rip + zero_row], 0
    lea rdi, [rip + idat]
    call sb_clear
    lea rdi, [rip + pal]
    xor eax, eax
    mov ecx, 256
    rep stosd
    lea rdi, [rip + pal_a]
    mov eax, 255
    mov ecx, 256
    rep stosb
    add r12, 8
.Lchunk:
    mov rax, r13
    sub rax, r12
    jle .Lparsed
    cmp rax, 8
    jb .Lparsed
    LDBE32 ebx, [r12]
    mov eax, [r12 + 4]
    lea r14, [r12 + 8]
    mov rcx, r13
    sub rcx, r14
    cmp rbx, rcx
    jbe 1f
    mov rbx, rcx                # cut short: take what is there
1:  lea r12, [r14 + rbx + 4]
    cmp eax, CH_IHDR
    je .Lihdr
    cmp dword ptr [rip + width], 0
    je .Lfail                   # IHDR comes first
    cmp eax, CH_IDAT
    je .Lidat
    cmp eax, CH_PLTE
    je .Lplte
    cmp eax, CH_tRNS
    je .Ltrns
    cmp eax, CH_IEND
    je .Lparsed
    cmp eax, CH_CgBI
    je .Lfail
    jmp .Lchunk

.Lihdr:
    cmp dword ptr [rip + width], 0
    jne .Lfail
    cmp rbx, 13
    jb .Lfail
    LDBE32 eax, [r14]
    LDBE32 ecx, [r14 + 4]
    test eax, eax
    jz .Lfail
    test ecx, ecx
    jz .Lfail
    mov [rip + width], eax
    mov [rip + height], ecx
    movzx eax, byte ptr [r14 + 8]
    mov [rip + depth], eax
    movzx ecx, byte ptr [r14 + 9]
    mov [rip + ctype], ecx
    movzx edx, byte ptr [r14 + 12]
    mov [rip + interlace], edx
    cmp edx, 1
    ja .Lfail
    cmp word ptr [r14 + 10], 0  # compression and filter method
    jne .Lfail
    # allowed depths per color type (bit n = depth n)
    cmp ecx, 6
    ja .Lfail
    lea rdx, [rip + depth_ok]
    mov edx, [rdx + rcx*4]
    cmp eax, 16
    ja .Lfail
    bt edx, eax
    jnc .Lfail
    lea rdx, [rip + channels]
    movzx edx, byte ptr [rdx + rcx]
    mov [rip + chans], edx
    imul edx, eax
    add edx, 7
    shr edx, 3
    mov [rip + bpp], edx
    jmp .Lchunk

.Lplte:
    mov eax, ebx
    xor edx, edx
    mov ecx, 3
    div ecx
    cmp eax, 256
    jbe 1f
    mov eax, 256
1:  lea rdi, [rip + pal]
    mov rsi, r14
2:  test eax, eax
    jz .Lchunk
    movzx ecx, byte ptr [rsi]
    shl ecx, 16
    mov ch, [rsi + 1]
    mov cl, [rsi + 2]
    mov [rdi], ecx
    add rsi, 3
    add rdi, 4
    dec eax
    jmp 2b

.Ltrns:
    mov eax, [rip + ctype]
    cmp eax, 3
    jne 2f
    mov ecx, ebx
    cmp ecx, 256
    jbe 1f
    mov ecx, 256
1:  lea rdi, [rip + pal_a]
    mov rsi, r14
    rep movsb
    jmp .Lchunk
2:  # gray: one 16-bit sample, RGB: three; kept as the bytes a row would hold
    xor ecx, ecx
    mov edx, 2
    test eax, eax
    jz 3f
    cmp eax, 2
    jne .Lchunk
    mov edx, 6
3:  cmp rbx, rdx
    jb .Lchunk
    xor r8, r8                  # key
    xor r9d, r9d                # key bytes
    xor ecx, ecx
4:  cmp ecx, edx
    jae 5f
    cmp dword ptr [rip + depth], 16
    je 41f
    # 8 bits or less: the low byte of each sample
    movzx eax, byte ptr [r14 + rcx + 1]
    cmp byte ptr [r14 + rcx], 0
    jne .Lchunk                 # out of range: nothing matches
    mov r10d, r9d
    shl r10d, 3
    xchg ecx, r10d
    shl rax, cl
    xchg ecx, r10d
    or r8, rax
    inc r9d
    jmp 42f
41: movzx eax, byte ptr [r14 + rcx]
    mov r10d, r9d
    shl r10d, 3
    xchg ecx, r10d
    shl rax, cl
    xchg ecx, r10d
    or r8, rax
    movzx eax, byte ptr [r14 + rcx + 1]
    lea r10d, [r9 + 1]
    shl r10d, 3
    xchg ecx, r10d
    shl rax, cl
    xchg ecx, r10d
    or r8, rax
    add r9d, 2
42: add ecx, 2
    jmp 4b
5:  mov [rip + trns_key], r8
    mov [rip + trns_len], r9d
    mov dword ptr [rip + has_trns], 1
    jmp .Lchunk

.Lidat:
    lea rdi, [rip + idat]
    mov rsi, r14
    mov rdx, rbx
    call sb_push
    jmp .Lchunk

.Lparsed:
    cmp dword ptr [rip + width], 0
    je .Lfail
    cmp qword ptr [rip + idat + SB_len], 0
    je .Lfail
    cmp dword ptr [rip + ctype], 3
    jne 1f
    cmp dword ptr [rip + depth], 16
    je .Lfail
1:  mov rdi, [rip + img]
    mov esi, [rip + width]
    mov edx, [rip + height]
    call img_alloc
    test rax, rax
    jz .Lfail
    # size of the filtered data, pass by pass when interlaced
    xor r14d, r14d
    cmp dword ptr [rip + interlace], 0
    jne 2f
    mov edi, [rip + width]
    call row_bytes
    inc rax
    mov ecx, [rip + height]
    imul rax, rcx
    mov r14, rax
    jmp 4f
2:  xor ebx, ebx
3:  cmp ebx, 7
    jae 4f
    mov edi, ebx
    call pass_dims
    test eax, eax
    jz 31f
    test edx, edx
    jz 31f
    mov r15d, edx
    mov edi, eax
    call row_bytes
    inc rax
    imul rax, r15
    add r14, rax
31: inc ebx
    jmp 3b
4:  lea rdi, [r14 + 16]
    call mem_alloc_try
    test rax, rax
    jz .Lbig
    mov [rip + raw], rax
    mov rdi, [rip + idat + SB_ptr]
    mov rsi, [rip + idat + SB_len]
    mov rdx, rax
    mov rcx, r14
    mov r8d, 1
    call inflate
    cmp rdx, -1
    je .Lfail
    test rax, rax
    jz .Lfail                   # nothing at all (a cut short stream keeps what it has)
    # a zero row stands in for the row above the first
    mov edi, [rip + width]
    call row_bytes
    lea rdi, [rax + 16]
    call mem_alloc
    mov [rip + zero_row], rax
    call pick_converter
    mov rbx, [rip + raw]
    cmp dword ptr [rip + interlace], 0
    jne 5f
    mov rdi, rbx
    mov esi, [rip + width]
    mov edx, [rip + height]
    xor ecx, ecx
    xor r8d, r8d
    xor r9d, r9d                # every pixel of every row
    call do_pass
    test rax, rax
    jz .Lfail
    jmp .Lok
5:  xor r15d, r15d
6:  cmp r15d, 7
    jae .Lok
    mov edi, r15d
    call pass_dims
    test eax, eax
    jz 61f
    test edx, edx
    jz 61f
    lea rcx, [rip + adam7]
    movzx r8d, byte ptr [rcx + r15*4 + 1]
    movzx r9d, word ptr [rcx + r15*4 + 2]
    movzx ecx, byte ptr [rcx + r15*4]
    mov rdi, rbx
    mov esi, eax
    call do_pass
    test rax, rax
    jz .Lfail
    mov rbx, rax
61: inc r15d
    jmp 6b
.Lok:
    call cleanup
    xor eax, eax
    EPILOGUE
.Lbig:
    lea rax, [rip + .Lerr_big]
    mov [rip + g_img_err], rax
.Lfail:
    call cleanup
    mov eax, -1
    EPILOGUE

cleanup:
    push rbx
    mov rdi, [rip + raw]
    call mem_free
    mov qword ptr [rip + raw], 0
    mov rdi, [rip + zero_row]
    call mem_free
    mov qword ptr [rip + zero_row], 0
    lea rdi, [rip + idat]
    call sb_free
    pop rbx
    ret

# row_bytes(pixels) -> bytes of a filtered row (without the filter byte)
row_bytes:
    mov eax, edi
    imul eax, [rip + chans]
    mov ecx, [rip + depth]
    imul rax, rcx
    add rax, 7
    shr rax, 3
    ret

# pass_dims(pass) -> eax width, edx height of an Adam7 pass
pass_dims:
    lea rcx, [rip + adam7]
    lea r8, [rcx + rdi*4]
    # (size - start + step - 1) / step, 0 when start >= size
    movzx ecx, byte ptr [r8 + 2]        # x step as shift
    movzx eax, byte ptr [r8]
    mov edx, [rip + width]
    sub edx, eax
    jle 1f
    mov eax, 1
    shl eax, cl
    lea eax, [rdx + rax - 1]
    shr eax, cl
    jmp 2f
1:  xor eax, eax
2:  movzx ecx, byte ptr [r8 + 3]        # y step as shift
    movzx edx, byte ptr [r8 + 1]
    mov r9d, [rip + height]
    sub r9d, edx
    jle 3f
    mov edx, 1
    shl edx, cl
    lea edx, [r9 + rdx - 1]
    shr edx, cl
    ret
3:  xor edx, edx
    ret

# do_pass(filtered, w, h, x0, y0, steps: x shift | y shift << 8) -> end of the pass's data, or 0 (bad filter)
do_pass:
    PROLOGUE 48
    mov rbx, rdi
    mov [rsp], esi              # w
    mov [rsp + 4], edx          # h
    mov [rsp + 8], ecx          # x0
    mov [rsp + 12], r8d         # y0
    mov [rsp + 16], r9d         # shifts
    mov edi, esi
    call row_bytes
    mov r14, rax                # row bytes
    mov r13, [rip + zero_row]   # previous row
    xor r12d, r12d              # row index
1:  cmp r12d, [rsp + 4]
    jae 8f
    movzx eax, byte ptr [rbx]
    cmp eax, 4
    ja 9f
    lea rdi, [rbx + 1]
    mov rsi, r13
    mov rdx, r14
    mov ecx, eax
    call unfilter
    # destination: (y0 + i << ys) * width + x0, stepping 1 << xs pixels
    movzx ecx, byte ptr [rsp + 17]
    mov eax, r12d
    shl eax, cl
    add eax, [rsp + 12]
    imul eax, [rip + width]
    add eax, [rsp + 8]
    mov rdx, [rip + img]
    mov rdx, [rdx + IMG_px]
    lea rdx, [rdx + rax*4]
    movzx ecx, byte ptr [rsp + 16]
    mov eax, 4
    shl eax, cl
    mov ecx, eax
    lea rdi, [rbx + 1]
    mov esi, [rsp]
    call [rip + conv]
    lea r13, [rbx + 1]
    lea rbx, [rbx + r14 + 1]
    inc r12d
    jmp 1b
8:  mov rax, rbx
    EPILOGUE
9:  xor eax, eax
    EPILOGUE

# unfilter(row, prev, n, type): undo the row filter in place
unfilter:
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov r8d, [rip + bpp]
    test ecx, ecx
    jz .Luf_ret
    cmp ecx, 2
    je .Luf_up
    cmp ecx, 1
    je .Luf_sub
    cmp ecx, 3
    je .Luf_avg
    # paeth: the first pixel only has the row above
    xor ecx, ecx
1:  cmp rcx, r8
    jae 2f
    cmp rcx, rdx
    jae .Luf_ret
    mov al, [rsi + rcx]
    add [rdi + rcx], al
    inc rcx
    jmp 1b
2:  mov r9, rdi
    sub r9, r8                  # left
    mov r10, rsi
    sub r10, r8                 # upper left
3:  cmp rcx, rdx
    jae .Luf_ret
    movzx eax, byte ptr [r9 + rcx]      # a
    movzx ebx, byte ptr [rsi + rcx]     # b
    movzx r11d, byte ptr [r10 + rcx]    # c
    mov r12d, ebx
    sub r12d, r11d              # b - c
    mov r13d, eax
    sub r13d, r11d              # a - c
    lea r14d, [r12 + r13]       # a + b - 2c
    mov r15d, r12d
    sar r15d, 31
    xor r12d, r15d
    sub r12d, r15d              # pa
    mov r15d, r13d
    sar r15d, 31
    xor r13d, r15d
    sub r13d, r15d              # pb
    mov r15d, r14d
    sar r15d, 31
    xor r14d, r15d
    sub r14d, r15d              # pc
    mov r15d, r11d              # c
    cmp r13d, r14d
    cmovbe r15d, ebx            # b when pb <= pc
    cmp r12d, r13d
    ja 4f
    cmp r12d, r14d
    cmovbe r15d, eax            # a when pa <= pb and pa <= pc
4:  add [rdi + rcx], r15b
    inc rcx
    jmp 3b
.Luf_up:
    xor ecx, ecx
1:  lea rax, [rcx + 16]
    cmp rax, rdx
    ja 2f
    movdqu xmm0, [rdi + rcx]
    movdqu xmm1, [rsi + rcx]
    paddb xmm0, xmm1
    movdqu [rdi + rcx], xmm0
    add rcx, 16
    jmp 1b
2:  cmp rcx, rdx
    jae .Luf_ret
    mov al, [rsi + rcx]
    add [rdi + rcx], al
    inc rcx
    jmp 2b
.Luf_sub:
    mov rcx, r8
    mov r9, rdi
    sub r9, r8
1:  cmp rcx, rdx
    jae .Luf_ret
    mov al, [r9 + rcx]
    add [rdi + rcx], al
    inc rcx
    jmp 1b
.Luf_avg:
    xor ecx, ecx
1:  cmp rcx, r8
    jae 2f
    cmp rcx, rdx
    jae .Luf_ret
    mov al, [rsi + rcx]
    shr al, 1
    add [rdi + rcx], al
    inc rcx
    jmp 1b
2:  mov r9, rdi
    sub r9, r8
3:  cmp rcx, rdx
    jae .Luf_ret
    movzx eax, byte ptr [r9 + rcx]
    movzx ebx, byte ptr [rsi + rcx]
    add eax, ebx
    shr eax, 1
    add [rdi + rcx], al
    inc rcx
    jmp 3b
.Luf_ret:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

# pick_converter(): conv for the color type and depth; builds lut for palette and low depth gray
pick_converter:
    push rbx
    mov eax, [rip + ctype]
    mov ecx, [rip + depth]
    cmp eax, 3
    je 3f
    test eax, eax
    jnz 5f
    cmp ecx, 16
    je 5f
    # gray of 1-8 bits: v * 255 / (2^depth - 1), transparent where it equals the tRNS value
    mov r8d, 1
    shl r8d, cl
    dec r8d                     # max
    xor ecx, ecx
    lea rdi, [rip + lut]
1:  cmp ecx, 256
    jae 2f
    mov eax, ecx
    and eax, r8d
    imul eax, eax, 255
    xor edx, edx
    div r8d
    mov edx, eax
    shl edx, 8
    or eax, edx
    shl edx, 8
    or eax, edx
    or eax, 0xff000000
    cmp dword ptr [rip + has_trns], 0
    je 11f
    movzx edx, byte ptr [rip + trns_key]
    cmp edx, ecx
    jne 11f
    xor eax, eax
11: mov [rdi + rcx*4], eax
    inc ecx
    jmp 1b
2:  jmp 4f
3:  # palette with tRNS alpha
    xor ecx, ecx
    lea rdi, [rip + lut]
    lea rsi, [rip + pal]
    lea rdx, [rip + pal_a]
31: mov eax, [rsi + rcx*4]
    movzx ebx, byte ptr [rdx + rcx]
    shl ebx, 24
    or eax, ebx
    mov [rdi + rcx*4], eax
    inc ecx
    cmp ecx, 256
    jb 31b
4:  lea rax, [rip + conv_lut8]
    cmp dword ptr [rip + depth], 8
    je 9f
    lea rax, [rip + conv_lut]
    jmp 9f
5:  # 8 or 16 bits per sample
    mov eax, [rip + ctype]
    lea rdx, [rip + wide_convs]
    mov rax, [rdx + rax*8]
9:  mov [rip + conv], rax
    pop rbx
    ret

# row converters: (row, count, dst, dst step bytes), straight ARGB out

conv_lut8:
    lea r8, [rip + lut]
1:  test esi, esi
    jz 2f
    movzx eax, byte ptr [rdi]
    mov eax, [r8 + rax*4]
    mov [rdx], eax
    inc rdi
    add rdx, rcx
    dec esi
    jmp 1b
2:  ret

# 1, 2 or 4 bit samples, most significant first
conv_lut:
    push rbx
    lea r8, [rip + lut]
    mov r9d, ecx
    mov r10d, [rip + depth]
    mov r11d, 1
    xchg ecx, r10d
    shl r11d, cl
    xchg ecx, r10d
    dec r11d                    # mask
    xor ebx, ebx                # bits used in the current byte
1:  test esi, esi
    jz 3f
    movzx eax, byte ptr [rdi]
    mov ecx, 8
    sub ecx, ebx
    sub ecx, r10d
    shr eax, cl
    and eax, r11d
    mov eax, [r8 + rax*4]
    mov [rdx], eax
    add rdx, r9
    add ebx, r10d
    cmp ebx, 8
    jb 2f
    xor ebx, ebx
    inc rdi
2:  dec esi
    jmp 1b
3:  pop rbx
    ret

# trns_hit: sets eax to 0 (transparent) when the sample bytes at rdi equal the tRNS key
.macro TRNS_CHECK
    cmp dword ptr [rip + has_trns], 0
    je 7f
    mov r10, [rdi]
    mov ecx, [rip + trns_len]
    shl ecx, 3
    mov r11, -1
    shl r11, cl
    not r11
    and r10, r11
    cmp r10, [rip + trns_key]
    jne 7f
    xor eax, eax
7:
.endm

conv_gray16:
    push rbx
    mov r9, rcx
1:  test esi, esi
    jz 2f
    movzx eax, byte ptr [rdi]
    mov ebx, eax
    shl ebx, 8
    or eax, ebx
    shl ebx, 8
    or eax, ebx
    or eax, 0xff000000
    TRNS_CHECK
    mov [rdx], eax
    add rdi, 2
    add rdx, r9
    dec esi
    jmp 1b
2:  pop rbx
    ret

conv_rgb:
    push rbx
    mov r9, rcx
    mov ebx, [rip + depth]
    shr ebx, 3                  # bytes per sample
1:  test esi, esi
    jz 2f
    movzx eax, byte ptr [rdi]
    shl eax, 8
    mov al, [rdi + rbx]
    shl eax, 8
    mov al, [rdi + rbx*2]
    or eax, 0xff000000
    TRNS_CHECK
    mov [rdx], eax
    lea rdi, [rdi + rbx*2]
    add rdi, rbx
    add rdx, r9
    dec esi
    jmp 1b
2:  pop rbx
    ret

conv_gray_alpha:
    push rbx
    mov r9, rcx
    mov ebx, [rip + depth]
    shr ebx, 3
1:  test esi, esi
    jz 2f
    movzx eax, byte ptr [rdi]
    mov ecx, eax
    shl ecx, 8
    or eax, ecx
    shl ecx, 8
    or eax, ecx
    movzx ecx, byte ptr [rdi + rbx]
    shl ecx, 24
    or eax, ecx
    mov [rdx], eax
    lea rdi, [rdi + rbx*2]
    add rdx, r9
    dec esi
    jmp 1b
2:  pop rbx
    ret

conv_rgba:
    push rbx
    mov r9, rcx
    mov ebx, [rip + depth]
    shr ebx, 3
    lea r10, [rbx + rbx*2]
1:  test esi, esi
    jz 2f
    movzx eax, byte ptr [rdi + r10]
    shl eax, 8
    mov al, [rdi]
    shl eax, 8
    mov al, [rdi + rbx]
    shl eax, 8
    mov al, [rdi + rbx*2]
    mov [rdx], eax
    lea rdi, [rdi + rbx*4]
    add rdx, r9
    dec esi
    jmp 1b
2:  pop rbx
    ret

.section .rodata
.Lerr_big: .asciz "The image is too large to show"
# allowed bit depths per color type, as bit masks
.p2align 2
depth_ok: .long 0x10116, 0, 0x10100, 0x0116, 0x10100, 0, 0x10100
channels: .byte 1, 0, 3, 1, 2, 0, 4
# Adam7: x0, y0, x step shift, y step shift
adam7: .byte 0, 0, 3, 3,  4, 0, 3, 3,  0, 4, 2, 3,  2, 0, 2, 2,  0, 2, 1, 2,  1, 0, 1, 1,  0, 1, 0, 1
.p2align 3
wide_convs: .quad conv_gray16, 0, conv_rgb, 0, conv_gray_alpha, 0, conv_rgba
