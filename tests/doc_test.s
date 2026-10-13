# exercises the gap buffer, line index, undo grouping and file round trip
.include "raftaar.inc"
.bss
.p2align 3
out: .zero SB_SIZE
doc: .quad 0
.text

# dump(): "len=N lines=N [text] starts=a,b,c dirty=N\n"
dump:
    PROLOGUE
    mov rbx, [rip + doc]
    lea rdi, [rip + out]
    lea rsi, [rip + s_len]
    call sb_push_cstr
    mov rdi, rbx
    call doc_len
    mov r12, rax
    lea rdi, [rip + out]
    mov rsi, rax
    call sb_push_u64
    lea rdi, [rip + out]
    lea rsi, [rip + s_lines]
    call sb_push_cstr
    lea rdi, [rip + out]
    mov rsi, [rbx + DOC_nlines]
    call sb_push_u64
    lea rdi, [rip + out]
    lea rsi, [rip + s_open]
    call sb_push_cstr
    lea rdi, [rip + out]
    mov rsi, r12
    call sb_reserve
    mov rdi, rbx
    xor esi, esi
    mov rdx, r12
    mov rcx, rax
    call doc_copy
    add [rip + out + SB_len], r12
    lea rdi, [rip + out]
    lea rsi, [rip + s_starts]
    call sb_push_cstr
    xor r13d, r13d
1:  cmp r13, [rbx + DOC_nlines]
    jae 2f
    mov rax, [rbx + DOC_lines]
    lea rdi, [rip + out]
    mov rsi, [rax + r13*8]
    call sb_push_u64
    lea rdi, [rip + out]
    mov esi, ','
    call sb_push_byte
    inc r13
    jmp 1b
2:  lea rdi, [rip + out]
    lea rsi, [rip + s_dirty]
    call sb_push_cstr
    mov rdi, rbx
    call doc_dirty
    lea rdi, [rip + out]
    mov esi, eax
    call sb_push_u64
    lea rdi, [rip + out]
    lea rsi, [rip + s_cur]
    call sb_push_cstr
    lea rdi, [rip + out]
    mov rsi, [rbx + DOC_cur]
    call sb_push_u64
    lea rdi, [rip + out]
    mov esi, 10
    call sb_push_byte
    mov rdi, [rip + out + SB_ptr]
    mov rsi, [rip + out + SB_len]
    call log_write
    lea rdi, [rip + out]
    call sb_clear
    EPILOGUE

.macro INS pos, str
    mov rdi, [rip + doc]
    mov esi, \pos
    lea rdx, [rip + 1f]
    mov ecx, 2f - 1f
    mov r8d, EK_TYPE
    call doc_insert
    call dump
    .pushsection .rodata
1:  .ascii "\str"
2:
    .popsection
.endm
.macro DEL pos, n
    mov rdi, [rip + doc]
    mov esi, \pos
    mov edx, \n
    xor ecx, ecx
    call doc_delete
    call dump
.endm

FN main
    PROLOGUE
    call doc_new
    mov [rip + doc], rax
    call dump
    INS 0, "hello"
    INS 5, "\nworld"
    INS 5, " there"
    INS 0, "a\nb\n"
    DEL 1, 3
    DEL 3, 6
    mov rdi, [rip + doc]
    call doc_undo
    call dump
    mov rdi, [rip + doc]
    call doc_undo
    call dump
    mov rdi, [rip + doc]
    call doc_redo
    call dump
    # typing groups: three single chars undo together
    INS 0, "x"
    INS 1, "y"
    INS 2, "z"
    mov rdi, [rip + doc]
    call doc_undo
    call dump
    # word motion
    mov rdi, [rip + doc]
    xor esi, esi
    call doc_word_right
    lea rdi, [rip + out]
    mov rsi, rax
    call sb_push_u64
    lea rdi, [rip + out]
    mov esi, 10
    call sb_push_byte
    # save / load round trip with CRLF
    mov rdi, [rip + doc]
    lea rsi, [rip + path]
    call doc_set_path
    mov rdi, [rip + doc]
    mov dword ptr [rdi + DOC_crlf], 1
    call doc_save
    call dump
    call doc_new
    mov [rip + doc], rax
    mov rdi, rax
    lea rsi, [rip + path]
    call doc_load
    call dump
    mov rdi, [rip + doc]
    lea rsi, [rip + path]
    call doc_len
    lea rdi, [rip + out]
    mov rsi, [rip + doc]
    mov esi, [rsi + DOC_crlf]
    call sb_push_u64
    lea rdi, [rip + out]
    mov esi, 10
    call sb_push_byte
    mov rdi, [rip + out + SB_ptr]
    mov rsi, [rip + out + SB_len]
    call log_write
    xor eax, eax
    EPILOGUE
.section .rodata
s_len: .asciz "len="
s_lines: .asciz " lines="
s_open: .asciz " ["
s_starts: .asciz "] starts="
s_dirty: .asciz " dirty="
s_cur: .asciz " cur="
path: .asciz "build/doc_test.txt"
