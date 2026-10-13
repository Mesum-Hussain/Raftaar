# Print the filesystem adapter result without issuing filesystem operations.
.include "win.inc"
.text
FN main
    PROLOGUE
    mov rax, [rip + g_argv]
    mov rdi, [rax + 8]
    call win_file_path
    test rax, rax
    jz 1f
    mov rbx, rax
    mov rdi, rax
    call win_utf8
    mov r12, rax
    mov rdi, rbx
    call mem_free
    mov rdi, r12
    call strlen
    mov rdx, rax
    mov edi, 1
    mov rsi, r12
    SYS SYS_write
    mov rdi, r12
    call mem_free
    xor eax, eax
    EPILOGUE
1:  mov eax, 1
    EPILOGUE
