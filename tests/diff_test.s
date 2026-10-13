# line diff marks: base text against document text, one character per document line
#   . unchanged  A added  M changed  ^ lines deleted above  v deleted below
.include "raftaar.inc"
.bss
.p2align 3
out: .zero SB_SIZE
.text
FN main
    PROLOGUE 16
    lea r12, [rip + cases]
1:  mov r13, [r12]
    test r13, r13
    jz 9f
    call doc_new
    mov rbx, rax
    mov rdi, [r12 + 8]
    call strlen
    mov rdi, rbx
    mov rsi, [r12 + 8]
    mov rdx, rax
    call doc_set_text
    mov rdi, r13
    call strlen
    mov rdi, r13
    mov rsi, rax
    lea rdx, [rbx + DOC_gnl]
    call hash_text
    mov [rbx + DOC_ghash], rax
    mov rdi, rbx
    call diff_marks
    xor r14d, r14d
2:  cmp r14, [rbx + DOC_nlines]
    jae 4f
    mov rax, [rbx + DOC_gmarks]
    movzx eax, byte ptr [rax + r14]
    mov esi, '.'
    test eax, GM_ADD
    jz 21f
    mov esi, 'A'
21: test eax, GM_MOD
    jz 22f
    mov esi, 'M'
22: test eax, GM_DELUP
    jz 23f
    mov esi, '^'
    test eax, GM_ADD | GM_MOD
    jz 23f
    mov esi, '!'
23: test eax, GM_DELDOWN
    jz 24f
    mov esi, 'v'
24: lea rdi, [rip + out]
    call sb_push_byte
    inc r14
    jmp 2b
4:  lea rdi, [rip + out]
    mov esi, 10
    call sb_push_byte
    add r12, 16
    jmp 1b
9:  mov rdi, 1
    mov rsi, [rip + out + SB_ptr]
    mov rdx, [rip + out + SB_len]
    call write_all
    xor eax, eax
    EPILOGUE

.section .rodata
b1: .asciz "a\nb\nc\n"
d1: .asciz "a\nb\nc\n"
d2: .asciz "a\nx\nb\nc\n"
d3: .asciz "a\nc\n"
d4: .asciz "a\nB\nc\n"
d5: .asciz "a\nb\nc\nd\ne\n"
d6: .asciz "b\nc\n"
d7: .asciz "a\nb\n"
d8: .asciz "a\nB\nC\nD\n"
b9: .asciz "1\n2\n3\n4\n5\n6\n7\n8\n"
d9: .asciz "1\n2\nx\n4\n5\n7\n8\ny\n"
e0: .asciz ""
.p2align 3
cases:
    .quad b1, d1, b1, d2, b1, d3, b1, d4, b1, d5, b1, d6, b1, d7, b1, d8, b9, d9, e0, b1, b1, e0
    .quad 0, 0
