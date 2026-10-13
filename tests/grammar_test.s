# built-in grammars: loading parses none, each one's build-time header (name, files, first_line, icon)
# matches its text, the parser warns about none, the samples in SAMPLES-DIR/NAME.txt as classes (one
# base 36 digit per byte, then the state at the line's end); then the grammar detection picks for
# each line of DETECT, a file name and, after a tab, a first line
# usage: grammar_test DETECT SAMPLES-DIR
#        grammar_test --try FILE.syn SAMPLES   (a grammar being written: its warnings and classes)
.include "raftaar.inc"
.bss
.p2align 3
out: .zero SB_SIZE
pb: .zero SB_SIZE
cls: .zero 4096
name: .zero 512
.text

# put(cstr), putn(ptr, len), putu(n), nl(): append to the output
put:
    mov rsi, rdi
    lea rdi, [rip + out]
    jmp sb_push_cstr
putn:
    mov rdx, rsi
    mov rsi, rdi
    lea rdi, [rip + out]
    jmp sb_push
putu:
    mov rsi, rdi
    lea rdi, [rip + out]
    jmp sb_push_u64
nl:
    lea rdi, [rip + out]
    mov esi, 10
    jmp sb_push_byte

# same(cstr, cstr) -> 1 if equal
same:
    PROLOGUE
    mov r12, rdi
    mov r13, rsi
    call strlen
    mov rbx, rax
    mov rdi, r13
    call strlen
    mov rdi, r12
    mov rsi, rbx
    mov rdx, r13
    mov rcx, rax
    call str_eq
    EPILOGUE

# classes(gr, text, len): each line of text, then its classes and the state at its end
classes:
    PROLOGUE 16
    mov rbx, rdi
    mov r12, rsi
    lea r13, [rsi + rdx]
    xor r15d, r15d
1:  cmp r12, r13
    jae 9f
    mov r14, r12
2:  cmp r12, r13
    jae 3f
    cmp byte ptr [r12], 10
    je 3f
    inc r12
    jmp 2b
3:  mov rax, r12
    sub rax, r14
    cmp rax, 4096
    jbe 4f
    mov eax, 4096
4:  mov [rsp], rax
    mov rdi, r14
    mov rsi, rax
    call putn
    call nl
    mov rdi, rbx
    mov rsi, r14
    mov rdx, [rsp]
    mov ecx, r15d
    lea r8, [rip + cls]
    call tokenize
    mov r15d, eax
    mov qword ptr [rsp + 8], 0
5:  mov rcx, [rsp + 8]
    cmp rcx, [rsp]
    jae 6f
    lea rax, [rip + cls]
    movzx eax, byte ptr [rax + rcx]
    lea rdx, [rip + digits]
    movzx esi, byte ptr [rdx + rax]
    lea rdi, [rip + out]
    call sb_push_byte
    inc qword ptr [rsp + 8]
    jmp 5b
6:  lea rdi, [rip + out]
    mov esi, ' '
    call sb_push_byte
    mov edi, r15d
    call putu
    call nl
    inc r12
    jmp 1b
9:  EPILOGUE

FN main
    PROLOGUE 16
    mov rbx, [rip + g_argv]
    mov rdi, [rbx + 8]
    test rdi, rdi
    jz .Lend
    call strlen
    mov rdi, [rbx + 8]
    mov rsi, rax
    lea rdx, [rip + .Ltry]
    call str_eq_cstr
    test eax, eax
    jnz .Ltry_mode
    call syntax_load_all
    lea rdi, [rip + .Lloaded]
    call put
    mov edi, [rip + g_grammars_parsed]
    call putu
    lea rdi, [rip + .Lparsed_nl]
    call put
    # each built-in grammar, parsed afresh
    xor r12d, r12d
1:  cmp r12, [rip + syntax_count]
    jae 5f
    imul r13, r12, 56
    lea rax, [rip + syntax_table]
    add r13, rax
    mov dword ptr [rip + g_grammar_warnings], 0
    mov rdi, [r13 + 8]
    mov rsi, [r13 + 16]
    sub rsi, rdi
    call grammar_parse
    mov r14, rax
    cmp dword ptr [rip + g_grammar_warnings], 0
    je 2f
    mov rdi, [r13]
    call put
    lea rdi, [rip + .Lwarnings]
    call put
    mov edi, [rip + g_grammar_warnings]
    call putu
    call nl
2:  mov rdi, [r14 + GR_name]
    mov rsi, [r13 + 24]
    call same
    mov r15d, eax
    mov rdi, [r14 + GR_files]
    mov rsi, [r13 + 32]
    call same
    and r15d, eax
    mov rdi, [r14 + GR_first]
    mov rsi, [r13 + 40]
    call same
    and r15d, eax
    mov rdi, [r14 + GR_icon]
    mov rsi, [r13 + 48]
    call same
    and r15d, eax
    jnz 3f
    mov rdi, [r13]
    call put
    lea rdi, [rip + .Lheader]
    call put
    call nl
3:  # its samples: SAMPLES-DIR/NAME.txt for NAME.syn
    lea rdi, [rip + pb]
    call sb_clear
    mov rax, [rip + g_argv]
    lea rdi, [rip + pb]
    mov rsi, [rax + 16]
    call sb_push_cstr
    lea rdi, [rip + pb]
    mov esi, '/'
    call sb_push_byte
    mov rdi, [r13]
    call strlen
    lea rdx, [rax - 4]
    lea rdi, [rip + pb]
    mov rsi, [r13]
    call sb_push
    lea rdi, [rip + pb]
    lea rsi, [rip + .Ltxt]
    call sb_push_cstr
    lea rdi, [rip + pb]
    xor esi, esi
    call sb_push_byte
    mov rdi, [rip + pb + SB_ptr]
    call file_read_all
    test rax, rax
    jz 4f
    mov [rsp], rax
    mov [rsp + 8], rdx
    lea rdi, [rip + .Lsection]
    call put
    mov rdi, [r13]
    call put
    call nl
    mov rdi, r14
    mov rsi, [rsp]
    mov rdx, [rsp + 8]
    call classes
4:  inc r12
    jmp 1b
5:  lea rdi, [rip + .Lchecked]
    call put
    mov rdi, [rip + syntax_count]
    call putu
    lea rdi, [rip + .Lgrammars]
    call put
    # detection: NAME or NAME<tab>FIRST LINE per line
    mov rax, [rip + g_argv]
    mov rdi, [rax + 8]
    call file_read_all
    test rax, rax
    jz .Lend
    mov r12, rax
    lea r13, [rax + rdx]
6:  cmp r12, r13
    jae .Lend
    mov r14, r12                # the line
    xor r15d, r15d              # its tab
7:  cmp r12, r13
    jae 8f
    movzx eax, byte ptr [r12]
    cmp eax, 10
    je 8f
    cmp eax, 9
    jne 71f
    test r15, r15
    jnz 71f
    mov r15, r12
71: inc r12
    jmp 7b
8:  mov rdx, r12                # the name ends at the tab or the line's end
    test r15, r15
    jz 81f
    mov rdx, r15
81: sub rdx, r14
    cmp rdx, 511
    jbe 82f
    mov edx, 511
82: mov [rsp], rdx
    lea rdi, [rip + name]
    mov rsi, r14
    call memcpy
    lea rax, [rip + name]
    mov rcx, [rsp]
    mov byte ptr [rax + rcx], 0
    xor esi, esi                # the first line after the tab
    xor edx, edx
    test r15, r15
    jz 83f
    lea rsi, [r15 + 1]
    mov rdx, r12
    sub rdx, rsi
83: lea rdi, [rip + name]
    call syntax_detect
    mov [rsp + 8], rax
    lea rdi, [rip + name]
    call put
    lea rdi, [rip + .Larrow]
    call put
    lea rdi, [rip + .Lplain]
    mov rax, [rsp + 8]
    test rax, rax
    jz 84f
    mov rdi, [rax + GR_name]
84: call put
    lea rdi, [rip + .Lparsed_open]
    call put
    mov edi, [rip + g_grammars_parsed]
    call putu
    lea rdi, [rip + .Lclose]
    call put
    inc r12
    jmp 6b
.Ltry_mode:
    mov rdi, [rbx + 16]
    call file_read_all
    test rax, rax
    jz .Lend
    mov dword ptr [rip + g_grammar_warnings], 0
    mov rdi, rax
    mov rsi, rdx
    call grammar_parse
    mov r14, rax
    lea rdi, [rip + .Lwarn_try]
    call put
    mov edi, [rip + g_grammar_warnings]
    call putu
    call nl
    mov rdi, [rbx + 24]
    call file_read_all
    test rax, rax
    jz .Lend
    mov rdi, r14
    mov rsi, rax
    call classes
.Lend:
    mov rdi, [rip + out + SB_ptr]
    mov rsi, [rip + out + SB_len]
    call log_write
    xor eax, eax
    EPILOGUE

.section .rodata
digits: .ascii "0123456789abcdefghijklmnop"
.Ltry: .asciz "--try"
.Lloaded: .asciz "loaded: "
.Lparsed_nl: .asciz " parsed\n"
.Lwarnings: .asciz ": warnings "
.Lwarn_try: .asciz "warnings "
.Lheader: .asciz ": header differs"
.Ltxt: .asciz ".txt"
.Lsection: .asciz "== "
.Lchecked: .asciz "checked "
.Lgrammars: .asciz " grammars\n"
.Larrow: .asciz " -> "
.Lplain: .asciz "plain"
.Lparsed_open: .asciz " (parsed "
.Lclose: .asciz ")\n"
