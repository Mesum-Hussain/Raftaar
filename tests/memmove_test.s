# memmove copies overlapping ranges in either direction as a byte-at-a-time copy would: every size
# 0..100 moved 1..40 bytes up and down, the bytes around the destination untouched.
.include "raftaar.inc"
.equ N, 256
.bss
buf: .zero N
ref: .zero N
.text
FN main
    PROLOGUE 128
    mov r12d, 0                 # size
.Lsize:
    mov r13d, 1                 # distance
.Ldist:
    mov r14d, 0                 # 0 up, 1 down
.Ldir:
    # buf and ref: 0, 1, 2, ...
    xor ecx, ecx
1:  lea rax, [rip + buf]
    mov [rax + rcx], cl
    lea rax, [rip + ref]
    mov [rax + rcx], cl
    inc ecx
    cmp ecx, N
    jb 1b
    # src at 80, dst 80 +/- distance
    mov r15d, 80
    mov ebx, 80
    add ebx, r13d
    test r14d, r14d
    jz 2f
    mov ebx, 80
    sub ebx, r13d
2:  # the reference: a temporary copy, then back
    xor ecx, ecx
3:  cmp ecx, r12d
    jae 4f
    lea rax, [rip + buf]
    lea edx, [r15 + rcx]
    movzx edx, byte ptr [rax + rdx]
    mov [rsp + rcx], dl
    inc ecx
    jmp 3b
4:  xor ecx, ecx
5:  cmp ecx, r12d
    jae 6f
    movzx edx, byte ptr [rsp + rcx]
    lea rax, [rip + ref]
    lea r8d, [rbx + rcx]
    mov [rax + r8], dl
    inc ecx
    jmp 5b
6:  lea rdi, [rip + buf]
    add rdi, rbx
    lea rsi, [rip + buf]
    add rsi, r15
    mov edx, r12d
    call memmove
    lea rdi, [rip + buf]
    lea rsi, [rip + ref]
    mov edx, N
    call memeq
    test eax, eax
    jz fail
    inc r14d
    cmp r14d, 2
    jb .Ldir
    inc r13d
    cmp r13d, 40
    jbe .Ldist
    inc r12d
    cmp r12d, 100
    jbe .Lsize
    lea rdi, [rip + ok]
    call log_cstr
    xor eax, eax
    EPILOGUE
fail:
    lea rdi, [rip + bad]
    call log_cstr
    mov eax, 1
    EPILOGUE

.section .rodata
ok: .asciz "ok\n"
bad: .asciz "memmove differs from a byte copy\n"
