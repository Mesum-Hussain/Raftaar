# line diff (Myers) between a file's text at HEAD and the document, as marks for the gutter
.include "raftaar.inc"

.equ DMAX, 1000                 # beyond this many differences the middle counts as changed

.bss
.p2align 3
vbuf: .quad 0                   # V, 2 * DMAX + 3 ints
trace: .quad 0                  # V after each step: (DMAX + 1)^2 ints at most
tcap: .quad 0
delpts: .quad 0                 # per document line + 1: lines deleted before it
delcap: .quad 0
marks: .quad 0                  # the document's marks while diffing

.text

# hash_line(ptr, len) -> rax
FN hash_line
    mov rax, 0xcbf29ce484222325
    mov r8, 0x100000001b3
    xor ecx, ecx
1:  cmp rcx, rsi
    jae 2f
    movzx edx, byte ptr [rdi + rcx]
    xor rax, rdx
    imul rax, r8
    inc rcx
    jmp 1b
2:  xor rax, rsi
    imul rax, r8
    ret

# hash_text(ptr, len, *count) -> array of line hashes (mem_free it); a final newline ends the last line
FN hash_text
    PROLOGUE 16
    mov r12, rdi
    mov r13, rsi
    mov [rsp], rdx
    # count lines
    xor ecx, ecx
    xor ebx, ebx
1:  cmp rcx, r13
    jae 2f
    cmp byte ptr [r12 + rcx], 10
    jne 11f
    inc rbx
11: inc rcx
    jmp 1b
2:  test r13, r13
    jz 3f
    cmp byte ptr [r12 + r13 - 1], 10
    je 3f
    inc rbx
3:  lea rdi, [rbx*8 + 8]
    call mem_alloc
    mov r14, rax
    mov rax, [rsp]
    mov [rax], rbx
    xor r15d, r15d              # line
    xor ebx, ebx                # line start
    xor ecx, ecx
4:  cmp rcx, r13
    jae 6f
    cmp byte ptr [r12 + rcx], 10
    jne 5f
    lea rdi, [r12 + rbx]
    mov rsi, rcx
    sub rsi, rbx
    push rcx
    push rcx
    call hash_line
    pop rcx
    pop rcx
    mov [r14 + r15*8], rax
    inc r15
    lea rbx, [rcx + 1]
5:  inc rcx
    jmp 4b
6:  cmp rbx, r13
    jae 7f
    lea rdi, [r12 + rbx]
    mov rsi, r13
    sub rsi, rbx
    call hash_line
    mov [r14 + r15*8], rax
7:  mov rax, r14
    EPILOGUE

# diff_marks(doc): DOC_gmarks from DOC_ghash and the document's lines
FN diff_marks
    PROLOGUE 64
    mov rbx, rdi
    # document hashes; the empty line after a final newline is not a line of the file
    mov r15, [rbx + DOC_nlines]
    mov rdi, rbx
    lea rsi, [r15 - 1]
    call doc_line_text
    test rdx, rdx
    jnz 1f
    dec r15
1:  mov [rsp], r15              # nb
    # hashes the document keeps for lines not changed since
    xor r12d, r12d
3:  cmp r12, r15
    jae 4f
    mov rcx, [rbx + DOC_lhash]
    cmp qword ptr [rcx + r12*8], 0
    jne 2f
    mov rdi, rbx
    mov rsi, r12
    call doc_line_text
    mov rdi, rax
    mov rsi, rdx
    call hash_line
    mov rcx, [rbx + DOC_lhash]
    mov [rcx + r12*8], rax
2:  inc r12
    jmp 3b
4:  # marks: a byte per document line, cleared
    mov rsi, [rbx + DOC_nlines]
    inc rsi
    cmp rsi, [rbx + DOC_gmcap]
    jbe 5f
    mov [rbx + DOC_gmcap], rsi
    mov rdi, [rbx + DOC_gmarks]
    call mem_realloc
    mov [rbx + DOC_gmarks], rax
5:  mov rdi, [rbx + DOC_gmarks]
    mov [rip + marks], rdi
    mov rcx, [rbx + DOC_gmcap]
    xor eax, eax
    rep stosb
    mov rdi, [rip + delpts]
    mov rsi, [rbx + DOC_nlines]
    add rsi, 2
    cmp rsi, [rip + delcap]
    jbe 51f
    mov [rip + delcap], rsi
    call mem_realloc
    mov [rip + delpts], rax
51: mov rdi, [rip + delpts]
    mov rcx, [rip + delcap]
    xor eax, eax
    rep stosb
    # common start and end
    mov r12, [rbx + DOC_ghash]  # a
    mov r13, [rbx + DOC_lhash]  # b
    mov r14, [rbx + DOC_gnl]    # na
    xor ecx, ecx
6:  cmp rcx, r14
    jae 7f
    cmp rcx, r15
    jae 7f
    mov rax, [r12 + rcx*8]
    cmp rax, [r13 + rcx*8]
    jne 7f
    inc rcx
    jmp 6b
7:  mov [rsp + 8], rcx          # prefix
    mov rsi, r14
    mov rdi, r15
8:  cmp rsi, rcx
    jbe 9f
    cmp rdi, rcx
    jbe 9f
    mov rax, [r12 + rsi*8 - 8]
    cmp rax, [r13 + rdi*8 - 8]
    jne 9f
    dec rsi
    dec rdi
    jmp 8b
9:  # middle: a[p, rsi) against b[p, rdi)
    mov rax, [rsp + 8]
    lea rcx, [r12 + rax*8]
    mov [rsp + 16], rcx         # a
    sub rsi, rax
    mov [rsp + 24], rsi         # n
    lea rcx, [r13 + rax*8]
    mov [rsp + 32], rcx         # b
    sub rdi, rax
    mov [rsp + 40], rdi         # m
    mov rdi, [rsp + 16]
    mov rsi, [rsp + 24]
    mov rdx, [rsp + 32]
    mov rcx, [rsp + 40]
    mov r8, [rsp + 8]
    call myers
    test eax, eax
    jnz .Ldm_group
    # too different: the middle changed as a whole
    mov rcx, [rsp + 40]
    mov r8, [rsp + 8]
    mov rdi, [rbx + DOC_gmarks]
    mov edx, GM_MOD
    cmp qword ptr [rsp + 24], 0
    jne 10f
    mov edx, GM_ADD
10: test rcx, rcx
    jnz 11f
    mov rax, [rip + delpts]
    mov byte ptr [rax + r8], 1
    jmp .Ldm_group
11: mov [rdi + r8], dl
    inc r8
    dec rcx
    jnz 11b
.Ldm_group:
    # runs of added lines touching a deletion are changed lines
    mov r12, [rbx + DOC_gmarks]
    mov r13, [rip + delpts]
    xor ecx, ecx
.Ldm_run:
    cmp rcx, r15
    jae .Ldm_dels
    test byte ptr [r12 + rcx], GM_ADD
    jz 13f
    mov rdx, rcx                # run [rcx, rdx)
12: inc rdx
    cmp rdx, r15
    jae 121f
    test byte ptr [r12 + rdx], GM_ADD
    jnz 12b
121:xor eax, eax
    mov r8, rcx
14: cmp r8, rdx
    ja 15f
    or al, [r13 + r8]
    inc r8
    jmp 14b
15: test al, al
    jz 17f
    mov r8, rcx
16: cmp r8, rdx
    ja 161f
    mov byte ptr [r13 + r8], 0
    cmp r8, rdx
    je 162f
    mov byte ptr [r12 + r8], GM_MOD
162:inc r8
    jmp 16b
161:
17: mov rcx, rdx
    jmp .Ldm_run
13: inc rcx
    jmp .Ldm_run
.Ldm_dels:
    # other deletions: above the line after them, below the last line at the end
    xor ecx, ecx
18: cmp rcx, r15
    ja .Ldm_done
    cmp byte ptr [r13 + rcx], 0
    je 20f
    cmp rcx, r15
    jb 19f
    test r15, r15
    jz 19f
    or byte ptr [r12 + r15 - 1], GM_DELDOWN
    jmp 20f
19: or byte ptr [r12 + rcx], GM_DELUP
20: inc rcx
    jmp 18b
.Ldm_done:
    mov rax, [rbx + DOC_version]
    mov [rbx + DOC_gver], rax
    EPILOGUE

# myers(a, n, b, m, offset) -> 1, or 0 when there are more than DMAX differences
#   marks GM_ADD for inserted lines of b and deletion points in delpts, offset by the common prefix
myers:
    PROLOGUE 64
    mov [rsp], rdi              # a
    mov [rsp + 8], rsi          # n
    mov [rsp + 16], rdx         # b
    mov [rsp + 24], rcx         # m
    mov [rsp + 32], r8          # offset
    cmp qword ptr [rip + vbuf], 0
    jne 1f
    mov edi, (2 * DMAX + 3) * 4
    call mem_alloc
    mov [rip + vbuf], rax
1:  mov rbx, [rip + vbuf]
    add rbx, (DMAX + 1) * 4     # V[k] at rbx + 4k
    mov dword ptr [rbx + 4], 0
    xor r12d, r12d              # d
    mov qword ptr [rsp + 40], 0 # trace used (ints)
.Lmy_d:
    cmp r12, DMAX
    ja .Lmy_fail
    mov r13, r12
    neg r13                     # k
.Lmy_k:
    cmp r13, r12
    jg .Lmy_save
    # down (from k + 1) or right (from k - 1)
    mov rax, r12
    neg rax
    cmp r13, rax
    je 2f
    cmp r13, r12
    je 3f
    mov eax, [rbx + r13*4 - 4]
    cmp eax, [rbx + r13*4 + 4]
    jge 3f
2:  mov r14d, [rbx + r13*4 + 4]
    jmp 4f
3:  mov r14d, [rbx + r13*4 - 4]
    inc r14d
4:  movsxd r14, r14d            # x
    mov r15, r14
    sub r15, r13                # y
    # along the diagonal while lines match
    mov rdi, [rsp]
    mov rsi, [rsp + 16]
5:  cmp r14, [rsp + 8]
    jae 6f
    cmp r15, [rsp + 24]
    jae 6f
    mov rax, [rdi + r14*8]
    cmp rax, [rsi + r15*8]
    jne 6f
    inc r14
    inc r15
    jmp 5b
6:  mov [rbx + r13*4], r14d
    cmp r14, [rsp + 8]
    jb 7f
    cmp r15, [rsp + 24]
    jb 7f
    call .Lmy_store
    jmp .Lmy_back
7:  add r13, 2
    jmp .Lmy_k
.Lmy_save:
    call .Lmy_store
    inc r12
    jmp .Lmy_d
.Lmy_fail:
    xor eax, eax
    EPILOGUE
# store V[-d..d] (r12 = d) at the end of the trace
.Lmy_store:
    mov rax, [rsp + 8 + 40]
    lea rsi, [rax + r12*2 + 1]  # ints needed
    lea rsi, [rsi*4]
    cmp rsi, [rip + tcap]
    jbe 1f
    lea rsi, [rsi + rsi]
    add rsi, 4096
    mov [rip + tcap], rsi
    mov rdi, [rip + trace]
    call mem_realloc
    mov [rip + trace], rax
1:  mov rdi, [rip + trace]
    mov rax, [rsp + 8 + 40]
    lea rdi, [rdi + rax*4]
    mov rsi, r12
    neg rsi
    lea rsi, [rbx + rsi*4]
    lea rcx, [r12*2 + 1]
    add [rsp + 8 + 40], rcx
    rep movsd
    ret
.Lmy_back:
    # walk back from (n, m); r12 = d, r14 x, r15 y
    mov rax, [rsp + 40]
    lea rcx, [r12*2 + 1]
    sub rax, rcx
    mov [rsp + 48], rax         # start of step d in the trace
.Lmy_step:
    test r12, r12
    jz .Lmy_ok
    # V of step d - 1
    lea rcx, [r12*2 - 1]
    mov rax, [rsp + 48]
    sub rax, rcx
    mov [rsp + 48], rax
    mov rdi, [rip + trace]
    lea rdi, [rdi + rax*4]
    lea rcx, [r12 - 1]
    lea rdi, [rdi + rcx*4]      # V'[k] at rdi + 4k
    mov r13, r14
    sub r13, r15                # k
    mov rax, r12
    neg rax
    cmp r13, rax
    je 1f
    cmp r13, r12
    je 2f
    mov eax, [rdi + r13*4 - 4]
    cmp eax, [rdi + r13*4 + 4]
    jge 2f
1:  lea rcx, [r13 + 1]          # came down: a line of b was inserted
    jmp 3f
2:  lea rcx, [r13 - 1]          # came right: a line of a was deleted
3:  movsxd rax, dword ptr [rdi + rcx*4]
    mov rdx, rax
    sub rdx, rcx                # previous y
    # the diagonal back to the move
4:  cmp r14, rax
    jle 5f
    cmp r15, rdx
    jle 5f
    dec r14
    dec r15
    jmp 4b
5:  mov r8, [rsp + 32]
    cmp r14, rax
    jne 6f
    # insertion of b[y - 1]
    mov r9, [rip + marks]
    lea r10, [r15 + r8 - 1]
    mov byte ptr [r9 + r10], GM_ADD
    jmp 7f
6:  # deletion of a[x - 1], before b[y]
    mov r9, [rip + delpts]
    lea r10, [r15 + r8]
    mov byte ptr [r9 + r10], 1
7:  mov r14, rax
    mov r15, rdx
    dec r12
    jmp .Lmy_step
.Lmy_ok:
    mov eax, 1
    EPILOGUE
