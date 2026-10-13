# feeds escape sequences to the terminal emulator and prints the screens and replies
.include "raftaar.inc"
.bss
.p2align 3
out: .zero SB_SIZE
.text

# show(ptr, len): bytes with ESC as ^[
show:
    push rbx
    push r12
    push r13
    mov r12, rdi
    mov r13, rsi
    xor ebx, ebx
1:  cmp rbx, r13
    jae 3f
    movzx esi, byte ptr [r12 + rbx]
    cmp esi, 0x20
    jae 2f
    push rsi
    lea rdi, [rip + out]
    mov esi, '^'
    call sb_push_byte
    pop rsi
    add esi, 0x40
2:  lea rdi, [rip + out]
    call sb_push_byte
    inc rbx
    jmp 1b
3:  lea rdi, [rip + out]
    mov esi, 10
    call sb_push_byte
    pop r13
    pop r12
    pop rbx
    ret

# replies(t): what the terminal would send back, then clear it
replies:
    push rbx
    mov rbx, rdi
    cmp qword ptr [rbx + TM_out + SB_len], 0
    je 1f
    lea rdi, [rip + out]
    lea rsi, [rip + .Lreply]
    call sb_push_cstr
    mov rdi, [rbx + TM_out + SB_ptr]
    mov rsi, [rbx + TM_out + SB_len]
    call show
    lea rdi, [rbx + TM_out]
    call sb_clear
1:  pop rbx
    ret

# feed_cstr(str): bytes for the terminal in rbx
feed_cstr:
    push r12
    mov r12, rdi
    call strlen
    mov rdi, rbx
    mov rsi, r12
    mov rdx, rax
    call term_feed
    pop r12
    ret

# press(table): keysym, cp, mods entries until a zero keysym, for the terminal in rbx
press:
    push r12
    mov r12, rdi
1:  mov esi, [r12]
    test esi, esi
    jz 2f
    mov rdi, rbx
    mov edx, [r12 + 4]
    mov ecx, [r12 + 8]
    call term_key
    add r12, 12
    jmp 1b
2:  pop r12
    ret

# cell(t, row, col): attributes and colors
cell:
    push rbx
    push r12
    push r13
    mov rdi, rdi
    call term_row
    movsxd rdx, edx
    lea rcx, [rdx + rdx*2]
    lea r12, [rax + rcx*4 + LN_HDR]
    lea rdi, [rip + out]
    lea rsi, [rip + .Lcell]
    call sb_push_cstr
    xor ebx, ebx
1:  lea rdi, [rip + out]
    mov esi, [r12 + rbx*4]
    call hex
    inc ebx
    cmp ebx, 3
    jb 1b
    lea rdi, [rip + out]
    mov esi, 10
    call sb_push_byte
    pop r13
    pop r12
    pop rbx
    ret
hex:
    push rbx
    mov ebx, esi
    mov ecx, 28
1:  mov eax, ebx
    shr eax, cl
    and eax, 15
    lea rdx, [rip + hexdigits]
    movzx esi, byte ptr [rdx + rax]
    push rcx
    push rcx
    lea rdi, [rip + out]
    call sb_push_byte
    pop rcx
    pop rcx
    sub ecx, 4
    jns 1b
    lea rdi, [rip + out]
    mov esi, ' '
    call sb_push_byte
    pop rbx
    ret

# run(case*): cols, rows, text -> term (dumped); returns the term
run:
    push rbx
    push r12
    push r13
    mov r12, rdi
    movzx edi, byte ptr [r12]
    movzx esi, byte ptr [r12 + 1]
    mov edx, 100
    call term_new
    mov rbx, rax
    lea rdi, [r12 + 2]
    call strlen
    mov rdi, rbx
    lea rsi, [r12 + 2]
    mov rdx, rax
    call term_feed
    mov rdi, rbx
    lea rsi, [rip + out]
    call term_dump
    mov rdi, rbx
    call replies
    lea rdi, [rip + out]
    mov esi, 10
    call sb_push_byte
    mov rax, rbx
    pop r13
    pop r12
    pop rbx
    ret

FN main
    PROLOGUE
    lea r12, [rip + cases]
1:  mov rdi, [r12]
    test rdi, rdi
    jz 2f
    call run
    mov rdi, rax
    call term_free
    add r12, 8
    jmp 1b
2:  # colors and attributes
    lea rdi, [rip + c_sgr]
    call run
    mov rbx, rax
    mov rdi, rbx
    xor esi, esi
    xor edx, edx
    call cell
    mov rdi, rbx
    xor esi, esi
    mov edx, 1
    call cell
    mov rdi, rbx
    xor esi, esi
    mov edx, 2
    call cell
    mov rdi, rbx
    call term_free
    # scrollback and resizing
    lea rdi, [rip + c_scroll]
    call run
    mov rbx, rax
    lea rdi, [rip + out]
    lea rsi, [rip + .Lsb]
    call sb_push_cstr
    lea rdi, [rip + out]
    mov esi, [rbx + TM_sblen]
    call sb_push_u64
    lea rdi, [rip + out]
    mov esi, 10
    call sb_push_byte
    mov rdi, rbx
    lea rsi, [rip + out]
    mov edx, -2
    xor ecx, ecx
    mov r8d, -1
    mov r9d, 10
    call term_text
    lea rdi, [rip + out]
    mov esi, 10
    call sb_push_byte
    mov rdi, rbx
    mov esi, 10
    mov edx, 5
    call term_resize
    mov rdi, rbx
    lea rsi, [rip + out]
    call term_dump
    mov rdi, rbx
    mov esi, 6
    mov edx, 2
    call term_resize
    mov rdi, rbx
    lea rsi, [rip + out]
    call term_dump
    mov rdi, rbx
    call term_free
    # a hidden terminal's scrollback is packed; read back, a line is the cells it was, and a taller
    # screen pulls packed lines back onto it
    lea rdi, [rip + c_pack]
    call run
    mov rbx, rax
    mov rdi, rbx
    mov esi, -2
    call term_row
    mov r13d, [rax + LN_cap]
    lea r13, [r13 + r13*2]
    lea r13, [r13*4 + LN_HDR]
    mov rdi, rax
    mov rsi, r13
    call mem_dup
    mov r12, rax
    mov rdi, rbx
    call term_pack
    mov eax, [rbx + TM_sblen]
    sub eax, 2
    mov rcx, [rbx + TM_sb]
    mov rcx, [rcx + rax*8]
    mov r14d, [rcx + LN_flags]
    shr r14d, 1
    and r14d, 1
    lea rdi, [rip + out]
    lea rsi, [rip + pk_packed]
    call sb_push_cstr
    lea rdi, [rip + out]
    mov esi, r14d
    call sb_push_u64
    mov rdi, rbx
    mov esi, -2
    call term_row
    mov rdi, rax
    mov rsi, r12
    mov rdx, r13
    call memeq
    mov r14d, eax
    lea rdi, [rip + out]
    lea rsi, [rip + pk_same]
    call sb_push_cstr
    lea rdi, [rip + out]
    mov esi, r14d
    call sb_push_u64
    lea rdi, [rip + out]
    mov esi, 10
    call sb_push_byte
    mov rdi, r12
    call mem_free
    mov rdi, rbx
    mov esi, 30
    mov edx, 5
    call term_resize
    mov rdi, rbx
    lea rsi, [rip + out]
    call term_dump
    mov rdi, rbx
    call term_free
    # keys
    mov edi, 20
    mov esi, 3
    mov edx, 10
    call term_new
    mov rbx, rax
    lea r12, [rip + keys]
3:  mov esi, [r12]
    test esi, esi
    jz 4f
    cmp esi, -1
    jne 31f
    # application cursor keys from here on
    mov rdi, rbx
    lea rsi, [rip + .Lappcur]
    mov edx, 5
    call term_feed
    jmp 32f
31: mov rdi, rbx
    mov edx, [r12 + 4]
    mov ecx, [r12 + 8]
    call term_key
32: add r12, 12
    jmp 3b
4:  mov rdi, rbx
    call replies
    mov rdi, rbx
    lea rsi, [rip + .Lpaste]
    mov edx, 7
    call term_paste
    mov rdi, rbx
    lea rsi, [rip + .Lbpm]
    mov edx, 8
    call term_feed
    mov rdi, rbx
    lea rsi, [rip + .Lpaste]
    mov edx, 7
    call term_paste
    mov rdi, rbx
    call replies
    mov rdi, rbx
    call term_free
    # kitty keyboard protocol: queries, keys with flag 1, the alternate screen's own flags,
    # pops, sets, a full stack, then legacy keys again
    mov edi, 20
    mov esi, 3
    mov edx, 10
    call term_new
    mov rbx, rax
    lea rdi, [rip + .Lkk_on]
    call feed_cstr
    lea rdi, [rip + kk_keys]
    call press
    mov rdi, rbx
    call replies
    lea rdi, [rip + .Lkk_stack]
    call feed_cstr
    mov rdi, rbx
    call replies
    lea rdi, [rip + .Lkk_full]
    call feed_cstr
    lea rdi, [rip + kk_legacy]
    call press
    mov rdi, rbx
    call replies
    mov rdi, rbx
    call term_free
    mov rdi, 1
    mov rsi, [rip + out + SB_ptr]
    mov rdx, [rip + out + SB_len]
    call write_all
    xor eax, eax
    EPILOGUE

.section .rodata
.Lreply: .asciz "reply "
.Lcell: .asciz "cell "
.Lsb: .asciz "scrollback "
.Lappcur: .ascii "\033[?1h"
.Lbpm: .ascii "\033[?2004h"
.Lpaste: .ascii "a\nb\033c\r\n"
.Lkk_on: .asciz "\033[?u\033[>7u\033[?u"
.Lkk_stack: .ascii "\033[?1049h\033[?u\033[>1u\033[?u\033[?1049l\033[?u"
    .ascii "\033[<u\033[?u\033[<u\033[?u\033[=1u\033[?u\033[=1;3u\033[?u\033[=1;2u\033[?u"
    .asciz "\033[=8;2u\033[?u\033[<9u\033[?u"
.Lkk_full: .ascii "\033[>1u\033[>1u\033[>1u\033[>1u\033[>1u\033[>1u\033[>1u\033[>1u\033[>1u"
    .asciz "\033[<8u\033[?u\033[<u\033[?u"
# cols, rows, bytes
t1: .byte 20, 3
    .asciz "hello\r\nworld"
t2: .byte 10, 3
    .asciz "\033[2;3HX\033[1;1HY"
t3: .byte 10, 2
    .asciz "abcdef\033[3D\033[K"
t4: .byte 10, 3
    .asciz "0123456789ABC"
t5: .byte 10, 2
    .asciz "abcdef\033[1;3H\033[2@XY\r\n\033[2PZ"
t6: .byte 10, 2
    .asciz "a\344\270\255b|\360\237\230\200|"
t7: .byte 10, 2
    .asciz "main\033[?1049halt\033[?1049l!"
t8: .byte 10, 2
    .asciz "ab\033[6n\033[c\033[5n"
t9: .byte 10, 2
    .asciz "\033(0lqqk\033(B x\r\n\033(0x\033(B"
t10: .byte 20, 2
    .asciz "a\tb\tc\r\nx\033[3b"
t11: .byte 10, 5
    .asciz "1\r\n2\r\n3\r\n4\r\n5\033[2;4r\033[4;1H\n\033[r"
t12: .byte 10, 2
    .asciz "\033]0;my title\007\033]2;other\033\\t\033]11;?\033\\"
t13: .byte 10, 3
    .asciz "12345\033[2G\033[3X\r\n\033[2J\033[H\033[3;1Hend\033[1;1H\033M\033[L+"
t14: .byte 6, 2
    .asciz "abcdef\033[?7lgh\033[?7hij"
t15: .byte 10, 2
    .asciz "x\344\270\255\033[1;2Hy"
t16: .byte 10, 2
    .asciz "\033[?2026$p\033[?1049$p\033[?25l\033[?25$p"
c_sgr: .byte 10, 2
    .asciz "\033[1;31;48;2;1;2;3mX\033[0;38:2::255:128:0;4;7mY\033[22;24;27;39;38;5;200mZ"
c_pack: .byte 30, 2
    .asciz "\033[1;31;44mred \342\206\222 caf\303\251\033[0m plain\r\nsecond plain line\r\nthird\r\nfourth"
pk_packed: .asciz "packed "
pk_same: .asciz " same "
c_scroll: .byte 10, 3
    .asciz "1\r\n2\r\n3\r\n4\r\n5"
.p2align 3
cases: .quad t1, t2, t3, t4, t5, t6, t7, t8, t9, t10, t11, t12, t13, t14, t15, t16, 0
.p2align 2
# keysym, cp, mods (-1: switch to application cursor keys)
# with kitty flag 1
kk_keys:
    .long KEY_RETURN, 0, 0
    .long KEY_RETURN, 0, MOD_SHIFT
    .long KEY_RETURN, 0, MOD_ALT
    .long KEY_RETURN, 0, MOD_CTRL
    .long KEY_KP_ENTER, 0, MOD_SHIFT
    .long KEY_TAB, 0, 0
    .long KEY_ISO_LEFT_TAB, 0, MOD_SHIFT
    .long KEY_BACKSPACE, 0, MOD_CTRL
    .long KEY_ESCAPE, 0, 0
    .long 'c', 'c', MOD_CTRL
    .long 'x', 'x', MOD_ALT
    .long 'A', 'A', MOD_SHIFT | MOD_ALT
    .long ' ', ' ', MOD_CTRL
    .long 'q', 'q', 0
    .long 'Q', 'Q', MOD_SHIFT
    .long KEY_UP, 0, MOD_ALT
    .long 0, 0, 0
# after the last pop
kk_legacy:
    .long KEY_RETURN, 0, MOD_SHIFT
    .long KEY_RETURN, 0, MOD_ALT
    .long 'c', 'c', MOD_CTRL
    .long KEY_ESCAPE, 0, 0
    .long 0, 0, 0
keys:
    .long KEY_UP, 0, 0
    .long KEY_UP, 0, MOD_CTRL
    .long KEY_F1 + 4, 0, 0
    .long KEY_DELETE, 0, MOD_SHIFT
    .long KEY_F1, 0, 0
    .long 'c', 'c', MOD_CTRL
    .long 'x', 'x', MOD_ALT
    .long KEY_TAB, 0, MOD_SHIFT
    .long KEY_BACKSPACE, 0, 0
    .long KEY_RETURN, 0, 0
    .long 0x439, 0x439, 0
    .long '[', '[', MOD_CTRL
    .long -1, 0, 0
    .long KEY_UP, 0, 0
    .long KEY_HOME, 0, 0
    .long 0, 0, 0
