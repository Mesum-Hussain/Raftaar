# prints "keycode group mods -> keysym unicode" for a keymap file
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
    mov rdi, rax
    mov rsi, rdx
    call xkb_parse
    lea rbx, [rip + cases]
1:  mov edi, [rbx]
    cmp edi, 0
    je 8f
    mov esi, [rbx + 4]
    mov edx, [rbx + 8]
    call xkb_keysym
    mov r12d, eax
    mov edi, eax
    call keysym_to_unicode
    mov r13d, eax
    lea rdi, [rip + out]
    mov esi, [rbx]
    call sb_push_u64
    lea rdi, [rip + out]
    mov esi, ' '
    call sb_push_byte
    lea rdi, [rip + out]
    mov esi, [rbx + 4]
    call sb_push_u64
    lea rdi, [rip + out]
    mov esi, ' '
    call sb_push_byte
    lea rdi, [rip + out]
    mov esi, [rbx + 8]
    call sb_push_u64
    lea rdi, [rip + out]
    lea rsi, [rip + arrow]
    call sb_push_cstr
    lea rdi, [rip + out]
    mov esi, r12d
    call sb_push_u64
    lea rdi, [rip + out]
    mov esi, ' '
    call sb_push_byte
    test r13d, r13d
    jz 2f
    lea rdi, [rip + out]
    mov esi, r13d
    call sb_push_utf8
2:  lea rdi, [rip + out]
    mov esi, 10
    call sb_push_byte
    add rbx, 12
    jmp 1b
8:  mov rdi, [rip + out + SB_ptr]
    mov rsi, [rip + out + SB_len]
    call log_write
    xor eax, eax
    EPILOGUE
9:  mov eax, 1
    EPILOGUE
.section .rodata
arrow: .asciz " -> "
.p2align 2
# keycode, group, mods (1 shift, 2 caps, 0x10 num lock, 0x80 level3)
cases:
    .long 38, 0, 0
    .long 38, 0, 1
    .long 38, 0, 2
    .long 38, 0, 3
    .long 38, 1, 0
    .long 38, 1, 1
    .long 38, 1, 2
    .long 24, 1, 0
    .long 34, 0, 1
    .long 34, 1, 0
    .long 47, 1, 1
    .long 23, 0, 1
    .long 10, 0, 1
    .long 9, 0, 0
    .long 61, 0, 0x80
    .long 61, 0, 0x81
    .long 50, 0, 1
    .long 38, 0, 0x80
    .long 38, 0, 0x81
    .long 48, 1, 0
    .long 48, 1, 1
    .long 48, 0, 0x80
    .long 87, 0, 0
    .long 87, 0, 0x10
    .long 87, 0, 0x11
    .long 91, 0, 0x10
    .long 38, 0, 0x10
    .long 0, 0, 0
