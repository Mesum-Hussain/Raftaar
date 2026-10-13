# path_normalize on the paths in a file, one per line, each in a buffer whose bytes after the path
# are not zero, as reused heap memory can be; prints each result
.include "raftaar.inc"
.bss
.p2align 3
out: .zero SB_SIZE
buf: .zero 256
.text
FN main
    PROLOGUE
    mov rax, [rip + g_argv]
    mov rdi, [rax + 8]
    call file_read_all
    test rax, rax
    jz 9f
    mov r12, rax
    lea r13, [rax + rdx]
1:  cmp r12, r13
    jae 9f
    mov r14, r12                # the line
2:  cmp byte ptr [r12], 10
    je 3f
    inc r12
    jmp 2b
3:  mov rbx, r12
    sub rbx, r14                # its length
    inc r12
    lea rdi, [rip + buf]
    mov esi, 3
    mov edx, 255
    call memset
    lea rdi, [rip + buf]
    mov rsi, r14
    mov rdx, rbx
    call memcpy
    lea rax, [rip + buf]
    mov byte ptr [rax + rbx], 0
    lea rdi, [rip + buf]
    call path_normalize
    lea rdi, [rip + out]
    lea rsi, [rip + buf]
    call sb_push_cstr
    lea rdi, [rip + out]
    mov esi, 10
    call sb_push_byte
    jmp 1b
9:  mov rdi, [rip + out + SB_ptr]
    mov rsi, [rip + out + SB_len]
    call log_write
    xor eax, eax
    EPILOGUE
