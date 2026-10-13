# loads every built-in theme and prints a few derived slots
.include "raftaar.inc"
.bss
.p2align 3
out: .zero SB_SIZE
.text
hex:
    push rbx
    mov ebx, edi
    lea rdi, [rip + out]
    mov esi, '#'
    call sb_push_byte
    mov ecx, 20
1:  mov eax, ebx
    shr eax, cl
    and eax, 15
    lea rdx, [rip + hexdigits]
    movzx esi, byte ptr [rdx + rax]
    push rcx
    lea rdi, [rip + out]
    call sb_push_byte
    pop rcx
    sub ecx, 4
    jns 1b
    lea rdi, [rip + out]
    mov esi, ' '
    call sb_push_byte
    pop rbx
    ret
FN main
    PROLOGUE
    call theme_scan
    xor ebx, ebx
1:  cmp rbx, [rip + g_themes + VEC_len]
    jae 9f
    mov rdi, rbx
    call theme_apply
    call theme_current_id
    lea rdi, [rip + out]
    mov rsi, rax
    call sb_push_cstr
    lea rdi, [rip + out]
    mov esi, ' '
    call sb_push_byte
    lea r12, [rip + slots]
2:  mov eax, [r12]
    cmp eax, -1
    je 3f
    lea rcx, [rip + g_theme]
    mov edi, [rcx + rax*4]
    call hex
    add r12, 4
    jmp 2b
3:  lea rdi, [rip + out]
    mov esi, 10
    call sb_push_byte
    inc rbx
    jmp 1b
9:  mov rdi, [rip + out + SB_ptr]
    mov rsi, [rip + out + SB_len]
    call log_write
    xor eax, eax
    EPILOGUE
.section .rodata
.p2align 2
slots: .long T_BG, T_FG, T_PANEL, T_SELECTION, T_SYN + C_KEYWORD, T_SYN + C_STRING, T_SYN + C_COMMENT
    # the file icon colors, red to white
    .long T_ICON, T_ICON + 1, T_ICON + 2, T_ICON + 3, T_ICON + 4, T_ICON + 5, T_ICON + 6, T_ICON + 7
    .long T_ICON + 8, T_ICON + 9, -1
