# file_icon for each line of NAMES: the name, its icon and color names; then a data table sized with
# numeric local labels in a macro, as tools/arm64.py once measured from the wrong place
# usage: fileicon_test NAMES
.include "raftaar.inc"
.bss
.p2align 3
out: .zero SB_SIZE
buf: .zero 256
.text

put:
    mov rsi, rdi
    lea rdi, [rip + out]
    jmp sb_push_cstr
putc:
    mov esi, edi
    lea rdi, [rip + out]
    jmp sb_push_byte

# icon_name(icon): its name in file_icon_names, or ?
icon_name:
    PROLOGUE
    mov ebx, edi
    lea r12, [rip + file_icon_names]
1:  movzx r13d, byte ptr [r12]
    test r13d, r13d
    jz 8f
    movzx eax, byte ptr [r12 + 1]
    cmp eax, ebx
    je 2f
    lea r12, [r12 + r13 + 2]
    jmp 1b
2:  lea rdi, [rip + out]
    lea rsi, [r12 + 2]
    mov rdx, r13
    call sb_push
    EPILOGUE
8:  lea rdi, [rip + .Lunknown]
    call put
    EPILOGUE

FN main
    PROLOGUE
    call syntax_load_all
    mov rax, [rip + g_argv]
    mov rdi, [rax + 8]
    call file_read_all
    test rax, rax
    jz 9f
    mov r12, rax
    lea r13, [rax + rdx]
1:  cmp r12, r13
    jae 5f
    mov r14, r12                # the line
2:  cmp byte ptr [r12], 10
    je 3f
    inc r12
    jmp 2b
3:  mov rbx, r12
    sub rbx, r14
    inc r12
    lea rdi, [rip + buf]
    mov rsi, r14
    mov rdx, rbx
    call memcpy
    lea rax, [rip + buf]
    mov byte ptr [rax + rbx], 0
    lea rdi, [rip + buf]
    call put
    mov edi, ' '
    call putc
    lea rdi, [rip + buf]
    call file_icon
    mov r15d, edx
    mov edi, eax
    call icon_name
    mov edi, ' '
    call putc
    sub r15d, T_ICON
    lea rax, [rip + colors]
    mov rdi, [rax + r15*8]
    call put
    mov edi, 10
    call putc
    jmp 1b
5:  # lengths 1 3 6
    lea rdi, [rip + .Llabels]
    call put
    lea r12, [rip + sized]
6:  movzx ebx, byte ptr [r12]
    test ebx, ebx
    jz 7f
    mov edi, ' '
    call putc
    lea rdi, [rip + out]
    mov esi, ebx
    call sb_push_u64
    lea r12, [r12 + rbx + 1]
    jmp 6b
7:  mov edi, 10
    call putc
9:  mov rdi, [rip + out + SB_ptr]
    mov rsi, [rip + out + SB_len]
    call log_write
    xor eax, eax
    EPILOGUE

.macro SIZED word
    .byte 999f - 998f
998: .ascii "\word"
999:
.endm

.section .rodata
.Lunknown: .asciz "?"
.Llabels: .asciz "labels"
.p2align 3
colors:
    .quad .Lc0, .Lc1, .Lc2, .Lc3, .Lc4, .Lc5, .Lc6, .Lc7, .Lc8, .Lc9
.Lc0: .asciz "red"
.Lc1: .asciz "orange"
.Lc2: .asciz "yellow"
.Lc3: .asciz "green"
.Lc4: .asciz "blue"
.Lc5: .asciz "purple"
.Lc6: .asciz "pink"
.Lc7: .asciz "cyan"
.Lc8: .asciz "grey"
.Lc9: .asciz "white"
sized:
    SIZED a
    SIZED bcd
    SIZED efghij
    .byte 0
