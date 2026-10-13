# Incremental column measurement must agree with measuring from the row start,
# including tabs following wide characters and rows starting partway through a line.
.include "raftaar.inc"
.text
FN main
    PROLOGUE 16
    mov dword ptr [rsp], 1
.Lwidth:
    mov eax, [rsp]
    mov [rip + cfg_tab_width], eax
    xor r12d, r12d              # row start
.Lrow:
    mov r13, r12                # previous end
    mov r14, r12                # next end
    xor r15d, r15d              # running column
.Lend:
    lea rdi, [rip + text]
    mov rsi, r13
    mov rdx, r14
    mov ecx, r15d
    call seg_cols_from
    mov r15d, eax
    lea rdi, [rip + text]
    mov rsi, r12
    mov rdx, r14
    call seg_cols
    cmp eax, r15d
    jne .Lfail
    cmp r14, text_end - text
    jae .Lnextrow
    mov r13, r14
    lea rdi, [rip + text]
    add rdi, r14
    mov esi, text_end - text
    sub rsi, r14
    call utf8_decode
    add r14, rdx
    jmp .Lend
.Lnextrow:
    cmp r12, text_end - text
    jae .Lnextwidth
    lea rdi, [rip + text]
    add rdi, r12
    mov esi, text_end - text
    sub rsi, r12
    call utf8_decode
    add r12, rdx
    jmp .Lrow
.Lnextwidth:
    inc dword ptr [rsp]
    cmp dword ptr [rsp], 8
    jbe .Lwidth
    call source_columns
    test eax, eax
    jz .Lfail
    lea rdi, [rip + ok]
    call log_cstr
    xor eax, eax
    EPILOGUE
.Lfail:
    mov eax, 1
    EPILOGUE

# Source columns stay independent of tabs and glyph width, including across the gap buffer.
source_columns:
    PROLOGUE
    call doc_new
    mov rbx, rax
    mov rdi, rax
    lea rsi, [rip + source]
    mov edx, source_end - source
    call doc_set_text
    xor r15d, r15d
1:  xor r12d, r12d
2:  mov rdi, rbx
    mov esi, 1
    mov rdx, r12
    cmp r12, 7
    jne 3f
    mov edx, 100              # clamp to the line end, not into the next line
3:  call doc_pos_at_char
    lea rcx, [rip + source_positions]
    cmp rax, [rcx + r12*8]
    jne 8f
    inc r12
    cmp r12, 8
    jb 2b
    test r15d, r15d
    jnz 7f
    mov rdi, rbx
    mov esi, 14
    lea rdx, [rip + source]
    mov ecx, 1
    call raw_insert
    mov rdi, rbx
    mov esi, 14
    mov edx, 1
    call raw_delete
    inc r15d
    jmp 1b
7:  mov rdi, rbx
    call doc_free
    mov eax, 1
    EPILOGUE
8:  mov rdi, rbx
    call doc_free
    xor eax, eax
    EPILOGUE
.section .rodata
text: .ascii "a\tbc\t\344\270\255\t\303\251x\t\360\237\230\200\tend"
text_end:
source: .ascii "header\n\t\346\227\245e\314\201\360\237\230\200x\nend"
source_end:
.p2align 3
source_positions: .quad 7, 8, 11, 12, 14, 18, 19, 19
ok: .asciz "ok\n"
