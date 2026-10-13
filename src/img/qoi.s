# QOI (qoiformat.org)
.include "raftaar.inc"

.bss
.p2align 2
seen: .zero 4 * 64              # previously seen pixels, by hash

.text

# qoi_decode(ptr, len, IMG*) -> 0 or -1
FN qoi_decode
    PROLOGUE
    mov r12, rdi
    lea r13, [rdi + rsi]        # end
    mov rbx, rdx
    cmp rsi, 14
    jb 9f
    LDBE32 esi, [r12 + 4]
    LDBE32 edx, [r12 + 8]
    mov rdi, rbx
    call img_alloc
    test rax, rax
    jz 9f
    mov rdi, rax
    mov r15d, [rbx + IMG_w]
    mov eax, [rbx + IMG_h]
    imul r15, rax               # pixels
    lea r14, [rdi + r15*4]      # end of the image
    lea rsi, [r12 + 14]
    lea rdi, [rip + seen]
    xor eax, eax
    mov ecx, 64
    rep stosd
    mov rdi, [rbx + IMG_px]
    xor r8d, r8d                # r
    xor r9d, r9d                # g
    xor r10d, r10d              # b
    mov r11d, 255               # a
    xor ecx, ecx                # run
.Lpx:
    cmp rdi, r14
    jae 8f
    test ecx, ecx
    jz 1f
    dec ecx
    jmp .Lput
1:  cmp rsi, r13
    jae 8f                      # cut short: the rest stays transparent
    movzx eax, byte ptr [rsi]
    inc rsi
    cmp eax, 0xfe
    jb 3f
    # RGB, RGBA
    lea rdx, [rsi + 3]
    cmp eax, 0xff
    jne 2f
    inc rdx
2:  cmp rdx, r13
    ja 8f
    movzx r8d, byte ptr [rsi]
    movzx r9d, byte ptr [rsi + 1]
    movzx r10d, byte ptr [rsi + 2]
    cmp eax, 0xff
    jne 21f
    movzx r11d, byte ptr [rsi + 3]
21: mov rsi, rdx
    jmp .Lhash
3:  mov edx, eax
    shr edx, 6
    jz .Lindex
    cmp edx, 1
    je .Ldiff
    cmp edx, 2
    je .Lluma
    # run of the previous pixel (it goes into the index like any other, as the reference decoder does)
    and eax, 63
    mov ecx, eax
    jmp .Lhash
.Lindex:
    lea rdx, [rip + seen]
    mov eax, [rdx + rax*4]
    movzx r10d, al
    shr eax, 8
    movzx r9d, al
    shr eax, 8
    movzx r8d, al
    shr eax, 8
    mov r11d, eax
    jmp .Lhash
.Ldiff:
    mov edx, eax
    shr edx, 4
    and edx, 3
    lea r8d, [r8 + rdx - 2]
    mov edx, eax
    shr edx, 2
    and edx, 3
    lea r9d, [r9 + rdx - 2]
    and eax, 3
    lea r10d, [r10 + rax - 2]
    jmp .Lwrap
.Lluma:
    cmp rsi, r13
    jae 8f
    movzx edx, byte ptr [rsi]
    inc rsi
    and eax, 63
    sub eax, 32                 # green difference
    add r9d, eax
    add r8d, eax
    add r10d, eax
    mov eax, edx
    shr eax, 4
    lea r8d, [r8 + rax - 8]
    and edx, 15
    lea r10d, [r10 + rdx - 8]
.Lwrap:
    and r8d, 255
    and r9d, 255
    and r10d, 255
.Lhash:
    # (r * 3 + g * 5 + b * 7 + a * 11) % 64
    lea eax, [r8 + r8*2]
    lea edx, [r9 + r9*4]
    add eax, edx
    lea edx, [r10*8]
    sub edx, r10d
    add eax, edx
    imul edx, r11d, 11
    add eax, edx
    and eax, 63
    call .Lpack
    lea rdx, [rip + seen]
    mov [rdx + rax*4], r12d
    mov eax, r12d
    jmp .Lstore
.Lput:
    call .Lpack
    mov eax, r12d
.Lstore:
    mov [rdi], eax
    add rdi, 4
    jmp .Lpx
8:  xor eax, eax
    EPILOGUE
9:  mov eax, -1
    EPILOGUE
# the pixel as ARGB in r12d
.Lpack:
    mov r12d, r11d
    shl r12d, 8
    or r12d, r8d
    shl r12d, 8
    or r12d, r9d
    shl r12d, 8
    or r12d, r10d
    ret
