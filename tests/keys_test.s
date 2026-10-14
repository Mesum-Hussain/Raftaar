# Every registered command and shortcut must resolve to the advertised handler.
.include "raftaar.inc"
.text
FN main
    PROLOGUE
    call keys_init
    lea rbx, [rip + g_commands]
.Lcommand:
    mov rdi, [rbx + CMD_name]
    test rdi, rdi
    jz .Ldone
    call strlen
    mov rsi, rax
    mov rdi, [rbx + CMD_name]
    call cmd_find
    cmp rax, rbx
    jne .Lfail
    mov r12, [rbx + CMD_keys]
    mov rdi, r12
    call strlen
    mov r13, rax
.Lbinding:
    test r13, r13
    jz .Lnext
    mov rdi, r12
    mov rsi, r13
    call next_word
    add r12, rcx
    sub r13, rcx
    test rdx, rdx
    jz .Lnext
    mov rdi, rax
    mov rsi, rdx
    call parse_combo
    test eax, eax
    jz .Lfail
    mov edi, eax
    mov esi, edx
    call keys_lookup
    cmp rax, [rbx + CMD_fn]
    jne .Lfail
    jmp .Lbinding
.Lnext:
    add rbx, CMD_SIZE
    jmp .Lcommand
.Ldone:
    # Native hints must account for shortcuts owned by the operating system.
    lea rbx, [rip + hints]
.Lhint:
    mov rdi, [rbx]
    test rdi, rdi
    jz .Lunbound
    call strlen
    mov rsi, rax
    mov rdi, [rbx]
    call cmd_find
    test rax, rax
    jz .Lfail
    mov rdi, rax
    call keys_for
    test rax, rax
    jz .Lfail
    mov r12, rax
    mov rdi, rax
    call strlen
    mov rsi, rax
    mov rdi, r12
    mov rdx, [rbx + 8]
    call str_eq_cstr
    test eax, eax
    jnz .Lhint_ok
    mov rdi, r12
    call log_cstr
    jmp .Lfail
.Lhint_ok:
    add rbx, 16
    jmp .Lhint
.Lunbound:
    # Unbound keys and unknown commands cannot invoke another action.
    mov edi, 'a'
    mov esi, MOD_ALT | MOD_SHIFT
    call keys_lookup
    test rax, rax
    jnz .Lfail
    lea rdi, [rip + unknown]
    mov esi, 17
    call cmd_find
    test rax, rax
    jnz .Lfail
    lea rdi, [rip + ok]
    call log_cstr
    xor eax, eax
    EPILOGUE
.Lfail:
    mov eax, 1
    EPILOGUE
.section .rodata
unknown: .asciz "unknown_command_x"
ok: .asciz "ok\n"
replace_name: .asciz "replace"
next_name: .asciz "next_tab"
sidebar_name: .asciz "toggle_sidebar"
.ifdef MACOS
replace_hint: .asciz "\342\214\203H"
next_hint: .asciz "\342\214\203Tab"
sidebar_hint: .asciz "\342\214\203`"
.else
replace_hint: .asciz "Ctrl+H"
next_hint: .asciz "Ctrl+Tab"
sidebar_hint: .asciz "Ctrl+`"
.endif
.p2align 3
hints:
    .quad replace_name, replace_hint, sidebar_name, sidebar_hint
    .quad next_name, next_hint, 0, 0
