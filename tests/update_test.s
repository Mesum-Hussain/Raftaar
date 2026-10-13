# ver_cmp and ver_valid on the cases in a file, one per line: "A B"; prints ver_cmp(A, B) and
# ver_valid(A) for each
.include "raftaar.inc"
.bss
.p2align 3
out: .zero SB_SIZE
.text
FN main
    PROLOGUE 16
    mov rax, [rip + g_argv]
    mov rdi, [rax + 8]
    call file_read_all
    test rax, rax
    jz 9f
    mov r12, rax
    lea r13, [rax + rdx]
1:  cmp r12, r13
    jae 9f
    mov rbx, r12                # A
2:  cmp byte ptr [r12], ' '
    je 3f
    inc r12
    jmp 2b
3:  mov byte ptr [r12], 0
    mov r14, r12
    sub r14, rbx                # its length
    inc r12
    mov r15, r12                # B
4:  cmp byte ptr [r12], 10
    je 5f
    inc r12
    jmp 4b
5:  mov byte ptr [r12], 0
    inc r12
    mov rdi, rbx
    mov rsi, r15
    call ver_cmp
    mov [rsp], eax
    cmp dword ptr [rsp], 0
    jge 6f
    lea rdi, [rip + out]
    mov esi, '-'
    call sb_push_byte
    neg dword ptr [rsp]
6:  lea rdi, [rip + out]
    mov esi, [rsp]
    add esi, '0'
    call sb_push_byte
    lea rdi, [rip + out]
    mov esi, ' '
    call sb_push_byte
    mov rdi, rbx
    mov rsi, r14
    call ver_valid
    lea rdi, [rip + out]
    mov esi, eax
    add esi, '0'
    call sb_push_byte
    lea rdi, [rip + out]
    mov esi, 10
    call sb_push_byte
    jmp 1b
9:  mov rdi, [rip + out + SB_ptr]
    mov rsi, [rip + out + SB_len]
    call log_write
    xor eax, eax
    EPILOGUE
