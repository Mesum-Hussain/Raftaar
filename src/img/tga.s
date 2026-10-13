# TGA: color-mapped, true-color and gray, raw or run-length encoded, either vertical origin
.include "raftaar.inc"

.bss
.p2align 3
p: .quad 0
end: .quad 0
.p2align 2
cmap: .zero 4 * 256
cmap_first: .long 0
cmap_len: .long 0
bytes: .long 0                  # per stored pixel
itype: .long 0                  # 1 mapped, 2 true color, 3 gray (+8 RLE)
pbits: .long 0

.text

# tga_decode(ptr, len, IMG*) -> 0 or -1
FN tga_decode
    PROLOGUE 16
    mov rbx, rdx
    mov r12, rdi
    lea rax, [rdi + rsi]
    mov [rip + end], rax
    cmp rsi, 18
    jb .Lfail
    movzx eax, byte ptr [r12 + 2]
    mov [rip + itype], eax
    movzx eax, byte ptr [r12 + 16]
    mov [rip + pbits], eax
    add eax, 7
    shr eax, 3
    mov [rip + bytes], eax
    movzx eax, word ptr [r12 + 3]
    mov [rip + cmap_first], eax
    movzx eax, word ptr [r12 + 5]
    mov [rip + cmap_len], eax
    movzx eax, byte ptr [r12]
    lea rsi, [r12 + rax + 18]   # after the id
    # color map
    cmp byte ptr [r12 + 1], 0
    je 2f
    movzx r13d, byte ptr [r12 + 7]
    add r13d, 7
    shr r13d, 3                 # bytes per entry
    lea rdi, [rip + cmap]
    xor ecx, ecx
1:  cmp ecx, [rip + cmap_len]
    jae 2f
    lea rax, [rsi + r13]
    cmp rax, [rip + end]
    ja .Lfail
    cmp ecx, 256
    jae 11f
    mov edx, r13d
    call read_px
    mov [rdi + rcx*4], eax
11: add rsi, r13
    inc ecx
    jmp 1b
2:  mov [rip + p], rsi
    mov rdi, rbx
    movzx esi, word ptr [r12 + 12]
    movzx edx, word ptr [r12 + 14]
    call img_alloc
    test rax, rax
    jz .Lfail
    movzx eax, byte ptr [r12 + 17]
    mov [rsp], eax              # descriptor: 0x20 top down, 0x10 right to left
    # pixels in stored order, then placed
    mov r14, [rbx + IMG_px]
    mov r15d, [rbx + IMG_w]
    mov eax, [rbx + IMG_h]
    imul r15, rax
    xor r13d, r13d              # pixels done
    xor r12d, r12d              # left in a run or raw packet
    mov dword ptr [rsp + 4], 0  # 1 while in a run
3:  cmp r13, r15
    jae 8f
    test dword ptr [rip + itype], 8
    jz 5f
    test r12d, r12d
    jnz 4f
    # packet header
    mov rsi, [rip + p]
    cmp rsi, [rip + end]
    jae 8f
    movzx eax, byte ptr [rsi]
    inc qword ptr [rip + p]
    mov r12d, eax
    and r12d, 127
    inc r12d
    shr eax, 7
    mov [rsp + 4], eax
    test eax, eax
    jz 4f
    call next_px
    jc 8f
    mov [rsp + 8], eax          # the run's pixel
4:  dec r12d
    cmp dword ptr [rsp + 4], 0
    je 5f
    mov eax, [rsp + 8]
    jmp 6f
5:  call next_px
    jc 8f
6:  mov [r14 + r13*4], eax
    inc r13
    jmp 3b
8:  # stored bottom up unless the descriptor says otherwise; mirrored when right to left
    test dword ptr [rsp], 0x20
    jnz 81f
    mov rdi, rbx
    call flip_rows
81: test dword ptr [rsp], 0x10
    jz 82f
    mov rdi, rbx
    call flip_cols
82: # 32 bits with an alpha of zero everywhere carries no alpha
    cmp dword ptr [rip + pbits], 32
    jne 9f
    mov rdi, [rbx + IMG_px]
    mov ecx, [rbx + IMG_w]
    imul ecx, [rbx + IMG_h]
    mov rdx, rdi
83: test dword ptr [rdx], 0xff000000
    jnz 9f
    add rdx, 4
    dec ecx
    jnz 83b
    mov ecx, [rbx + IMG_w]
    imul ecx, [rbx + IMG_h]
84: or dword ptr [rdi], 0xff000000
    add rdi, 4
    dec ecx
    jnz 84b
9:  xor eax, eax
    EPILOGUE
.Lfail:
    mov eax, -1
    EPILOGUE

# next_px() -> eax ARGB of the next stored pixel, CF set when the data ends
next_px:
    mov rsi, [rip + p]
    mov edx, [rip + bytes]
    lea rax, [rsi + rdx]
    cmp rax, [rip + end]
    ja 9f
    mov [rip + p], rax
    mov eax, [rip + itype]
    and eax, 7
    cmp eax, 1
    je 1f
    cmp eax, 3
    je 2f
    call read_px
    clc
    ret
1:  # an index into the color map
    movzx eax, byte ptr [rsi]
    cmp edx, 2
    jb 11f
    movzx eax, word ptr [rsi]
11: sub eax, [rip + cmap_first]
    cmp eax, 255
    ja 12f
    lea rcx, [rip + cmap]
    mov eax, [rcx + rax*4]
    clc
    ret
12: mov eax, 0xff000000
    clc
    ret
2:  movzx eax, byte ptr [rsi]
    imul eax, eax, 0x010101
    or eax, 0xff000000
    clc
    ret
9:  stc
    ret

# read_px(ptr rsi, bytes edx) -> eax ARGB: 2 bytes are 5-5-5, 3 BGR, 4 BGRA
read_px:
    cmp edx, 2
    je 2f
    cmp edx, 3
    je 3f
    cmp edx, 4
    je 4f
    movzx eax, byte ptr [rsi]
    imul eax, eax, 0x010101
    or eax, 0xff000000
    ret
2:  # 5 bits each, widened by repeating the top bits
    push rcx
    movzx eax, word ptr [rsi]
    mov ecx, eax
    shr ecx, 10
    call .Lwiden
    shl r8d, 16
    mov ecx, eax
    shr ecx, 5
    push r8
    call .Lwiden
    pop rcx
    shl r8d, 8
    or ecx, r8d
    call .Lwiden_b
    or eax, ecx
    or eax, 0xff000000
    pop rcx
    ret
.Lwiden:
    and ecx, 31
    mov r8d, ecx
    shl r8d, 3
    shr ecx, 2
    or r8d, ecx
    ret
.Lwiden_b:
    and eax, 31
    mov r8d, eax
    shl eax, 3
    shr r8d, 2
    or eax, r8d
    ret
3:  movzx eax, byte ptr [rsi + 2]
    shl eax, 8
    mov al, [rsi + 1]
    shl eax, 8
    mov al, [rsi]
    or eax, 0xff000000
    ret
4:  mov eax, [rsi]
    ret

# flip_rows(IMG*): upside down
flip_rows:
    push rbx
    mov r8, [rdi + IMG_px]
    mov r9d, [rdi + IMG_w]
    mov eax, [rdi + IMG_h]
    dec eax
    imul rax, r9
    lea r10, [r8 + rax*4]       # last row
1:  cmp r8, r10
    jae 9f
    xor ecx, ecx
2:  mov eax, [r8 + rcx*4]
    mov edx, [r10 + rcx*4]
    mov [r8 + rcx*4], edx
    mov [r10 + rcx*4], eax
    inc ecx
    cmp ecx, r9d
    jb 2b
    lea r8, [r8 + r9*4]
    mov rax, r9
    shl rax, 2
    sub r10, rax
    jmp 1b
9:  pop rbx
    ret

# flip_cols(IMG*): mirrored
flip_cols:
    mov r8, [rdi + IMG_px]
    mov r9d, [rdi + IMG_w]
    mov r11d, [rdi + IMG_h]
1:  test r11d, r11d
    jz 9f
    xor ecx, ecx
    lea edx, [r9 - 1]
2:  cmp ecx, edx
    jae 3f
    mov eax, [r8 + rcx*4]
    mov r10d, [r8 + rdx*4]
    mov [r8 + rcx*4], r10d
    mov [r8 + rdx*4], eax
    inc ecx
    dec edx
    jmp 2b
3:  lea r8, [r8 + r9*4]
    dec r11d
    jmp 1b
9:  ret
