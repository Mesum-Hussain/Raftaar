# Repeated configuration reads must release their input and replace custom keys.
.include "raftaar.inc"
.text
FN main
    PROLOGUE
    call config_load
    mov r12, [rip + g_mem_live]
    mov r13d, 64
1:  call config_load
    cmp [rip + g_mem_live], r12
    jne .Lfail
    cmp dword ptr [rip + cfg_tab_width], 3
    jne .Lfail
    cmp qword ptr [rip + g_keylines + VEC_len], 1
    jne .Lfail
    mov rax, [rip + g_keylines + VEC_ptr]
    mov rdi, [rax]
    mov rsi, [rax + 8]
    lea rdx, [rip + key]
    call str_eq_cstr
    test eax, eax
    jz .Lfail
    mov rax, [rip + g_keylines + VEC_ptr]
    mov rdi, [rax + 16]
    mov rsi, [rax + 24]
    lea rdx, [rip + command]
    call str_eq_cstr
    test eax, eax
    jz .Lfail
    dec r13d
    jnz 1b
    lea rdi, [rip + ok]
    call log_cstr
    xor eax, eax
    EPILOGUE
.Lfail:
    mov eax, 1
    EPILOGUE
.section .rodata
key: .asciz "ctrl+q"
command: .asciz "quit"
ok: .asciz "ok\n"
