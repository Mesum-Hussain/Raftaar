# PNM: PBM, PGM and PPM, plain (P1-P3) and raw (P4-P6), up to 16 bits per sample
.include "raftaar.inc"

.bss
.p2align 3
p: .quad 0
end: .quad 0
scale: .quad 0                  # sample -> 0..255, maxval + 1 entries
kind: .long 0                   # 1..6
maxval: .long 0

.text

# pnm_decode(ptr, len, IMG*) -> 0 or -1
FN pnm_decode
    PROLOGUE 16
    mov rbx, rdx
    lea rax, [rdi + rsi]
    mov [rip + end], rax
    lea rax, [rdi + 2]
    mov [rip + p], rax
    mov qword ptr [rip + scale], 0
    cmp rsi, 3
    jb .Lfail
    movzx eax, byte ptr [rdi + 1]
    sub eax, '0'
    mov [rip + kind], eax
    call number
    mov r12d, eax               # width
    call number
    mov r13d, eax               # height
    mov dword ptr [rip + maxval], 1
    mov eax, [rip + kind]
    cmp eax, 1
    je 1f
    cmp eax, 4
    je 1f
    call number
    lea ecx, [rax - 1]
    cmp ecx, 65535
    jae .Lfail
    mov [rip + maxval], eax
1:  # the raw formats: one blank, then the samples
    cmp dword ptr [rip + kind], 4
    jb 2f
    mov rax, [rip + p]
    cmp rax, [rip + end]
    jae .Lfail
    inc qword ptr [rip + p]
2:  mov rdi, rbx
    mov esi, r12d
    mov edx, r13d
    call img_alloc
    test rax, rax
    jz .Lfail
    # 0..maxval -> 0..255, rounded
    mov edi, [rip + maxval]
    inc edi
    call mem_alloc
    mov [rip + scale], rax
    xor ecx, ecx
3:  cmp ecx, [rip + maxval]
    ja 4f
    imul eax, ecx, 255
    mov r8d, [rip + maxval]
    mov edx, r8d
    shr edx, 1
    add eax, edx
    xor edx, edx
    div r8d
    mov r8, [rip + scale]
    mov [r8 + rcx], al
    inc ecx
    jmp 3b
4:  mov r14, [rbx + IMG_px]
    mov r15d, [rbx + IMG_w]
    mov eax, [rbx + IMG_h]
    imul r15, rax               # pixels
    mov eax, [rip + kind]
    cmp eax, 4
    je .Lp4
    cmp eax, 1
    je .Lp1
    # gray (2, 5) or color (3, 6), one sample or three per pixel
    xor r12d, r12d
5:  cmp r12, r15
    jae .Lok
    call sample
    js .Lok                     # cut short: the rest stays transparent
    mov r13d, eax
    cmp dword ptr [rip + kind], 3
    je 6f
    cmp dword ptr [rip + kind], 6
    je 6f
    imul eax, eax, 0x010101
    jmp 7f
6:  call sample
    js .Lok
    shl r13d, 8
    or r13d, eax
    call sample
    js .Lok
    shl r13d, 8
    or r13d, eax
    mov eax, r13d
7:  or eax, 0xff000000
    mov [r14 + r12*4], eax
    inc r12
    jmp 5b
.Lp1:
    # plain bits: 1 is black, blanks optional
    xor r12d, r12d
1:  cmp r12, r15
    jae .Lok
    mov rsi, [rip + p]
2:  cmp rsi, [rip + end]
    jae .Lok
    movzx eax, byte ptr [rsi]
    inc rsi
    cmp eax, '#'
    jne 3f
    mov [rip + p], rsi
    call skip_comment
    mov rsi, [rip + p]
    jmp 2b
3:  sub eax, '0'
    cmp eax, 1
    ja 2b
    mov [rip + p], rsi
    mov ecx, 0xffffffff
    test eax, eax
    jz 4f
    mov ecx, 0xff000000
4:  mov [r14 + r12*4], ecx
    inc r12
    jmp 1b
.Lp4:
    # packed bits, rows padded to bytes
    mov rsi, [rip + p]
    xor r12d, r12d              # row
1:  cmp r12d, [rbx + IMG_h]
    jae .Lok
    xor ecx, ecx
2:  cmp ecx, [rbx + IMG_w]
    jae 3f
    cmp rsi, [rip + end]
    jae .Lok
    movzx eax, byte ptr [rsi]
    mov edx, ecx
    and edx, 7
    xor edx, 7
    bt eax, edx
    mov eax, 0xffffffff
    mov edx, 0xff000000
    cmovc eax, edx
    mov [r14], eax
    add r14, 4
    inc ecx
    test ecx, 7
    jnz 2b
    inc rsi
    jmp 2b
3:  test ecx, 7
    jz 4f
    inc rsi
4:  inc r12d
    jmp 1b
.Lok:
    mov rdi, [rip + scale]
    call mem_free
    xor eax, eax
    EPILOGUE
.Lfail:
    mov rdi, [rip + scale]
    call mem_free
    mov eax, -1
    EPILOGUE

# sample() -> eax 0..255 of the next sample, SF set when there is none
sample:
    cmp dword ptr [rip + kind], 4
    jb 3f
    mov rsi, [rip + p]
    cmp dword ptr [rip + maxval], 255
    ja 1f
    cmp rsi, [rip + end]
    jae 9f
    movzx eax, byte ptr [rsi]
    inc rsi
    jmp 2f
1:  lea rax, [rsi + 2]
    cmp rax, [rip + end]
    ja 9f
    LDBE16 eax, ax, [rsi]
    add rsi, 2
2:  mov [rip + p], rsi
    jmp 4f
3:  call number
    test eax, eax
    js 9f
4:  cmp eax, [rip + maxval]
    jbe 5f
    mov eax, [rip + maxval]
5:  mov rcx, [rip + scale]
    movzx eax, byte ptr [rcx + rax]
    test eax, eax               # clears SF
    ret
9:  mov eax, -1
    test eax, eax
    ret

# number() -> eax the next decimal number after blanks and comments, -1 if there is none
number:
1:  mov rsi, [rip + p]
    cmp rsi, [rip + end]
    jae 9f
    movzx eax, byte ptr [rsi]
    cmp eax, '#'
    jne 2f
    call skip_comment
    jmp 1b
2:  lea ecx, [rax - '0']
    cmp ecx, 9
    jbe 3f
    cmp eax, ' '
    je 21f
    lea ecx, [rax - 9]
    cmp ecx, 4
    ja 9f                       # neither blank nor digit
21: inc qword ptr [rip + p]
    jmp 1b
3:  xor eax, eax
4:  cmp rsi, [rip + end]
    jae 5f
    movzx ecx, byte ptr [rsi]
    sub ecx, '0'
    cmp ecx, 9
    ja 5f
    imul eax, eax, 10
    add eax, ecx
    cmp eax, 1 << 24
    ja 9f
    inc rsi
    jmp 4b
5:  mov [rip + p], rsi
    ret
9:  mov eax, -1
    ret

# skip_comment(): p at '#', past the end of the line
skip_comment:
    mov rsi, [rip + p]
1:  cmp rsi, [rip + end]
    jae 2f
    movzx eax, byte ptr [rsi]
    inc rsi
    cmp eax, 10
    je 2f
    cmp eax, 13
    jne 1b
2:  mov [rip + p], rsi
    ret
