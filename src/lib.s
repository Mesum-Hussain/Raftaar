# strings, numbers, utf-8
.include "raftaar.inc"

.text

# memcpy(dst, src, n) -> dst
FN memcpy
    mov rax, rdi
    mov rcx, rdx
    rep movsb
    ret

# memmove(dst, src, n) -> dst
FN memmove
    mov rax, rdi
    mov rcx, rdx
    cmp rdi, rsi
    jbe 1f
    lea r8, [rsi + rdx]
    cmp rdi, r8
    jae 1f
.ifdef MACOS
    lea rsi, [rsi + rdx - 1]
    lea rdi, [rdi + rdx - 1]
    std
    rep movsb
    cld
    ret
.else
    # from the end, 16 bytes a step, both halves read before either is written (std; rep movsb
    # skips the fast string path: a byte a cycle, for a gap moved back or a line opened in a big file)
    add rsi, rdx
    add rdi, rdx
2:  cmp rcx, 16
    jb 3f
    sub rsi, 16
    sub rdi, 16
    mov r8, [rsi]
    mov r9, [rsi + 8]
    mov [rdi], r8
    mov [rdi + 8], r9
    sub rcx, 16
    jmp 2b
3:  test rcx, rcx
    jz 4f
    dec rsi
    dec rdi
    mov r8b, [rsi]
    mov [rdi], r8b
    dec rcx
    jmp 3b
4:  ret
.endif
1:  rep movsb
    ret

# memset(dst, byte, n) -> dst
FN memset
    mov r8, rdi
    mov eax, esi
    mov rcx, rdx
    rep stosb
    mov rax, r8
    ret

# memeq(a, b, n) -> 1 if equal
FN memeq
    mov rcx, rdx
    xor eax, eax
    repe cmpsb
    sete al
    ret

# strlen(s) -> n
FN strlen
    mov rax, rdi
1:  cmp byte ptr [rax], 0
    je 2f
    inc rax
    jmp 1b
2:  sub rax, rdi
    ret

# str_eq(a, alen, b, blen) -> 1 if equal
FN str_eq
    xor eax, eax
    cmp rsi, rcx
    jne 1f
    mov rcx, rsi
    mov rsi, rdx
    repe cmpsb
    sete al
1:  ret

# str_eq_cstr(a, alen, cstr) -> 1 if equal
FN str_eq_cstr
    xor eax, eax
1:  test rsi, rsi
    jz 2f
    mov cl, [rdx]
    test cl, cl
    jz 3f
    cmp cl, [rdi]
    jne 3f
    inc rdi
    inc rdx
    dec rsi
    jmp 1b
2:  cmp byte ptr [rdx], 0
    sete al
3:  ret

# str_ieq(a, alen, b, blen) -> 1 if equal ignoring case (str_ifind's); keeps rbx, rbp and r11-r15
FN str_ieq
    xor eax, eax
    cmp rsi, rcx
    jne 9f
    push rbx
    push r12
    push r14
    push r15
    mov r12, rdi
    mov r14, rdx
    mov r15, rsi
    xor edi, edi
    xor r9d, r9d
    mov ebx, 1
    call str_find_at
    pop r15
    pop r14
    pop r12
    pop rbx
9:  ret

# str_starts(s, slen, prefix, plen) -> 1 if s starts with prefix
FN str_starts
    xor eax, eax
    cmp rsi, rcx
    jb 1f
    test rcx, rcx
    jz 2f
    mov rsi, rdx
    repe cmpsb
    jne 1f
2:  mov eax, 1
1:  ret

# str_ends(s, slen, suffix, sfxlen) -> 1 if s ends with suffix
FN str_ends
    xor eax, eax
    cmp rsi, rcx
    jb 1f
    add rdi, rsi
    sub rdi, rcx
    mov rsi, rdx
    test rcx, rcx
    jz 2f
    repe cmpsb
    sete al
1:  ret
2:  mov eax, 1
    ret

# str_find(hay, hlen, needle, nlen) -> index or -1 (0 for an empty needle)
# str_ifind: the same, ignoring case: ASCII letters, and the other characters case_fold folds to a
# character of as many bytes, so a match is always nlen bytes long
# Both keep every register but rax and r8-r11. Candidates for the first needle byte are found
# 16 bytes at a time. Ignoring case, a needle starting with a character of several bytes looks for the
# first two bytes of it and of the one other character that folds as it does (я and Я), or, when
# there are more (ς, σ and Σ), for every first byte of a character as long.
FN str_find
    push rbx
    xor ebx, ebx
    jmp str_find_any
FN str_ifind
    push rbx
    mov ebx, 1
str_find_any:
    push r12
    push r13
    push r14
    push r15
    push rdi
    push rsi
    push rdx
    push rcx
    sub rsp, 160
    movups [rsp], xmm0
    movups [rsp + 16], xmm1
    movups [rsp + 32], xmm2
    movups [rsp + 48], xmm3
    movups [rsp + 80], xmm4
    movups [rsp + 96], xmm5
    movups [rsp + 112], xmm6
    movups [rsp + 128], xmm7
    mov dword ptr [rsp + 144], 0    # 1: candidates by their first two bytes
    mov r12, rdi                # haystack
    mov r13, rsi                # -> last start
    mov r14, rdx                # needle
    mov r15, rcx                # needle length
    xor eax, eax
    test r15, r15
    jz .Lsf_ret
    sub r13, r15
    jb .Lsf_none
    # the first needle byte; a letter in both cases when case-insensitive. A candidate is a byte that,
    # masked with r11d, is r8d or r9d; it is compared from needle byte r9 on (later 0 or 1)
    movzx r8d, byte ptr [r14]
    mov r9d, r8d
    mov r11d, 0xff
    mov dword ptr [rsp + 76], 1
    test ebx, ebx
    jz 2f
    cmp r8d, 0xc2
    jb 0f
    cmp r8d, 0xf5
    jae 2f                      # not a character: that byte
    # a character of several bytes: its first two bytes and those of the other character folding as
    # it does
    mov rdi, r14
    mov rsi, r15
    call utf8_decode
    cmp edx, 1
    je 5f
    mov edi, eax
    call case_fold
    mov edi, eax
    call fold_variants
    test eax, eax
    jz 6f
    mov dword ptr [rsp + 144], 1
    mov dword ptr [rsp + 76], 0
    mov r11d, 0xff
    movzx r8d, dl
    mov r9d, edx
    shr r9d, 16
    and r9d, 0xff
    mov eax, edx
    shr eax, 8
    and eax, 0xff
    movd xmm5, eax
    punpcklbw xmm5, xmm5
    pshuflw xmm5, xmm5, 0
    pshufd xmm5, xmm5, 0
    shr edx, 24
    movd xmm6, edx
    punpcklbw xmm6, xmm6
    pshuflw xmm6, xmm6, 0
    pshufd xmm6, xmm6, 0
    jmp 2f
5:  movzx r8d, byte ptr [r14]   # not a character: that byte
    mov r9d, r8d
    jmp 2f
    # more: the first byte of any character as long
6:  movzx r8d, byte ptr [r14]
    mov dword ptr [rsp + 76], 0
    mov r9d, 0xc0
    mov r11d, 0xe0
    cmp r8d, 0xe0
    jb 3f
    mov r9d, 0xe0
    mov r11d, 0xf0
    cmp r8d, 0xf0
    jb 3f
    mov r9d, 0xf0
    mov r11d, 0xf8
    cmp r8d, 0xf5
    jb 3f
    mov dword ptr [rsp + 76], 1  # not a character: that byte
    mov r9d, r8d
    mov r11d, 0xff
    jmp 2f
3:  mov r8d, r9d
    jmp 2f
0:  lea r10d, [r8 - 'A']
    cmp r10d, 25
    jbe 1f
    lea r10d, [r8 - 'a']
    cmp r10d, 25
    ja 2f
1:  or r8d, 0x20
    lea r9d, [r8 - 0x20]
2:  mov [rsp + 64], r8d
    mov [rsp + 68], r9d
    mov [rsp + 72], r11d
    movd xmm1, r8d
    punpcklbw xmm1, xmm1
    pshuflw xmm1, xmm1, 0
    pshufd xmm1, xmm1, 0
    movd xmm2, r9d
    punpcklbw xmm2, xmm2
    pshuflw xmm2, xmm2, 0
    pshufd xmm2, xmm2, 0
    movd xmm4, r11d
    punpcklbw xmm4, xmm4
    pshuflw xmm4, xmm4, 0
    pshufd xmm4, xmm4, 0
    mov r9d, [rsp + 76]
    xor r10d, r10d              # next start to try
    cmp dword ptr [rsp + 144], 0
    jne .Lsf_pairs
.Lsf_block:
    lea r11, [r10 + 15]
    cmp r11, r13
    ja .Lsf_tail
    movups xmm0, [r12 + r10]
    pand xmm0, xmm4
    movups xmm3, xmm0
    pcmpeqb xmm0, xmm1
    pcmpeqb xmm3, xmm2
    por xmm0, xmm3
    pmovmskb r11d, xmm0
3:  test r11d, r11d
    jz 4f
    bsf ecx, r11d
    btr r11d, ecx
    lea rdi, [r10 + rcx]
    call str_find_at
    test eax, eax
    jz 3b
    mov rax, rdi
    jmp .Lsf_ret
4:  add r10, 16
    jmp .Lsf_block
    # by the first two bytes (a needle of two bytes or more: the second load stays in the haystack)
.Lsf_pairs:
    lea r11, [r10 + 15]
    cmp r11, r13
    ja .Lsf_tail
    movups xmm0, [r12 + r10]
    movups xmm4, xmm0
    movups xmm3, [r12 + r10 + 1]
    movups xmm7, xmm3
    pcmpeqb xmm0, xmm1
    pcmpeqb xmm4, xmm2
    pcmpeqb xmm3, xmm5
    pcmpeqb xmm7, xmm6
    pand xmm0, xmm3
    pand xmm4, xmm7
    por xmm0, xmm4
    pmovmskb r11d, xmm0
3:  test r11d, r11d
    jz 4f
    bsf ecx, r11d
    btr r11d, ecx
    lea rdi, [r10 + rcx]
    call str_find_at
    test eax, eax
    jz 3b
    mov rax, rdi
    jmp .Lsf_ret
4:  add r10, 16
    jmp .Lsf_pairs
.Lsf_tail:
    cmp r10, r13
    ja .Lsf_none
    movzx eax, byte ptr [r12 + r10]
    and eax, [rsp + 72]
    cmp eax, [rsp + 64]
    je 5f
    cmp eax, [rsp + 68]
    jne 6f
5:  mov rdi, r10
    call str_find_at
    test eax, eax
    jz 6f
    mov rax, r10
    jmp .Lsf_ret
6:  inc r10
    jmp .Lsf_tail
.Lsf_none:
    mov rax, -1
.Lsf_ret:
    movups xmm0, [rsp]
    movups xmm1, [rsp + 16]
    movups xmm2, [rsp + 32]
    movups xmm3, [rsp + 48]
    movups xmm4, [rsp + 80]
    movups xmm5, [rsp + 96]
    movups xmm6, [rsp + 112]
    movups xmm7, [rsp + 128]
    add rsp, 160
    pop rcx
    pop rdx
    pop rsi
    pop rdi
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

# str_find_at(start in rdi) -> eax 1 if the needle (r14, r15; ebx 1 case-insensitive) is at
# haystack r12 + rdi from needle byte r9 on; uses rax, rdx, rsi, r8
str_find_at:
    mov rsi, r9
1:  cmp rsi, r15
    jae 4f
    lea rax, [rdi + rsi]
    movzx eax, byte ptr [r12 + rax]
    movzx edx, byte ptr [r14 + rsi]
    test ebx, ebx
    jz 22f
    cmp edx, 0xc0
    jae 6f                      # a character of several bytes, as a whole
22: cmp eax, edx
    je 3f
    test ebx, ebx
    jz 5f
    lea r8d, [rax - 'A']
    cmp r8d, 25
    ja 2f
    or eax, 0x20
2:  lea r8d, [rdx - 'A']
    cmp r8d, 25
    ja 21f
    or edx, 0x20
21: cmp eax, edx
    jne 5f
3:  inc rsi
    jmp 1b
4:  mov eax, 1
    ret
5:  xor eax, eax
    ret
6:  call char_ieq
    test rax, rax
    jz 5b
    add rsi, rax
    jmp 1b

# char_ieq -> rax: the length of the needle's character at r14 + rsi (its first byte 0xc0 or more)
# when the haystack at r12 + rdi + rsi has it, in either case, else 0; a byte that does not start a
# character matches only itself. Keeps every register but rax, rdx and r8.
char_ieq:
    push rbx
    push rcx
    push rdi
    push rsi
    push r9
    push r10
    push r11
    sub rsp, 16
    lea rbx, [r12 + rdi]
    add rbx, rsi                # the haystack's character
    lea rdi, [r14 + rsi]
    neg rsi
    add rsi, r15                # needle bytes left
    call utf8_decode
    cmp edx, 1
    je 7f
    mov [rsp], eax
    mov [rsp + 4], edx
    xor ecx, ecx
1:  movzx eax, byte ptr [rdi + rcx]
    cmp al, [rbx + rcx]
    jne 2f
    inc ecx
    cmp ecx, edx
    jb 1b
    mov eax, edx                # the same bytes
    jmp 9f
2:  mov rdi, rbx
    mov esi, edx                # the haystack has at least as many bytes here
    call utf8_decode
    cmp edx, [rsp + 4]
    jne 8f
    mov edi, eax
    call case_fold
    mov [rsp + 8], eax
    mov edi, [rsp]
    call case_fold
    cmp eax, [rsp + 8]
    jne 8f
    mov eax, [rsp + 4]
    jmp 9f
7:  movzx eax, byte ptr [rdi]
    cmp al, [rbx]
    jne 8f
    mov eax, 1
    jmp 9f
8:  xor eax, eax
9:  add rsp, 16
    pop r11
    pop r10
    pop r9
    pop rsi
    pop rdi
    pop rcx
    pop rbx
    ret

# fmt_u64(buf, value) -> len
FN fmt_u64
    mov rax, rsi
    mov r8, rdi
    lea rsi, [rsp - 32]
    mov rcx, rsi
    mov r9d, 10
1:  xor edx, edx
    div r9
    add dl, '0'
    dec rcx
    mov [rcx], dl
    test rax, rax
    jnz 1b
    mov rdx, rsi
    sub rdx, rcx                # len
    mov rax, rdx
    mov rsi, rcx
    mov rdi, r8
    mov rcx, rdx
    rep movsb
    ret

# fmt_hex(buf, value) -> len (lowercase, no prefix)
FN fmt_hex
    mov rax, rsi
    lea rcx, [rsp - 32]
    mov rsi, rcx
1:  mov edx, eax
    and edx, 15
    lea r8, [rip + hexdigits]
    mov dl, [r8 + rdx]
    dec rcx
    mov [rcx], dl
    shr rax, 4
    jnz 1b
    mov rdx, rsi
    sub rdx, rcx
    mov rax, rdx
    mov rsi, rcx
    mov rcx, rdx
    rep movsb
    ret

.section .rodata
.globl hexdigits
hexdigits: .ascii "0123456789abcdef"
.text

# parse_u64(ptr, len) -> rax value, rdx = digits consumed
FN parse_u64
    xor eax, eax
    xor edx, edx
1:  cmp rdx, rsi
    jae 2f
    movzx ecx, byte ptr [rdi + rdx]
    sub ecx, '0'
    cmp ecx, 9
    ja 2f
    imul rax, rax, 10
    add rax, rcx
    inc rdx
    jmp 1b
2:  ret

# parse_hex(ptr, len) -> rax value, rdx = digits consumed
FN parse_hex
    xor eax, eax
    xor edx, edx
1:  cmp rdx, rsi
    jae 3f
    movzx ecx, byte ptr [rdi + rdx]
    lea r8d, [rcx - '0']
    cmp r8d, 9
    jbe 2f
    or ecx, 0x20
    lea r8d, [rcx - 'a']
    cmp r8d, 5
    ja 3f
    add r8d, 10
2:  shl rax, 4
    add rax, r8
    inc rdx
    jmp 1b
3:  ret

# utf8_decode(ptr, avail) -> eax codepoint, edx length (>=1). invalid -> U+FFFD
FN utf8_decode
    test rsi, rsi
    jz .Lud_bad0
    movzx eax, byte ptr [rdi]
    cmp eax, 0x80
    jb .Lud_one
    cmp eax, 0xc2
    jb .Lud_bad
    cmp eax, 0xe0
    jb .Lud_two
    cmp eax, 0xf0
    jb .Lud_three
    cmp eax, 0xf5
    jb .Lud_four
    jmp .Lud_bad
.Lud_one:
    mov edx, 1
    ret
.Lud_two:
    cmp rsi, 2
    jb .Lud_bad
    movzx ecx, byte ptr [rdi + 1]
    mov r8d, ecx
    and r8d, 0xc0
    cmp r8d, 0x80
    jne .Lud_bad
    and eax, 0x1f
    shl eax, 6
    and ecx, 0x3f
    or eax, ecx
    mov edx, 2
    ret
.Lud_three:
    cmp rsi, 3
    jb .Lud_bad
    movzx ecx, byte ptr [rdi + 1]
    movzx r9d, byte ptr [rdi + 2]
    mov r8d, ecx
    and r8d, 0xc0
    cmp r8d, 0x80
    jne .Lud_bad
    mov r8d, r9d
    and r8d, 0xc0
    cmp r8d, 0x80
    jne .Lud_bad
    and eax, 0x0f
    shl eax, 12
    and ecx, 0x3f
    shl ecx, 6
    or eax, ecx
    and r9d, 0x3f
    or eax, r9d
    cmp eax, 0x800
    jb .Lud_bad
    mov edx, 3
    ret
.Lud_four:
    cmp rsi, 4
    jb .Lud_bad
    movzx ecx, byte ptr [rdi + 1]
    movzx r9d, byte ptr [rdi + 2]
    movzx r10d, byte ptr [rdi + 3]
    mov r8d, ecx
    and r8d, 0xc0
    cmp r8d, 0x80
    jne .Lud_bad
    mov r8d, r9d
    and r8d, 0xc0
    cmp r8d, 0x80
    jne .Lud_bad
    mov r8d, r10d
    and r8d, 0xc0
    cmp r8d, 0x80
    jne .Lud_bad
    and eax, 0x07
    shl eax, 18
    and ecx, 0x3f
    shl ecx, 12
    or eax, ecx
    and r9d, 0x3f
    shl r9d, 6
    or eax, r9d
    and r10d, 0x3f
    or eax, r10d
    cmp eax, 0x10000
    jb .Lud_bad
    mov edx, 4
    ret
.Lud_bad:
    mov eax, 0xfffd
    mov edx, 1
    ret
.Lud_bad0:
    xor eax, eax
    mov edx, 1
    ret

# utf8_encode(cp, out) -> length
FN utf8_encode
    cmp edi, 0x80
    jb .Lue_1
    cmp edi, 0x800
    jb .Lue_2
    cmp edi, 0x10000
    jb .Lue_3
    mov eax, edi
    shr eax, 18
    or al, 0xf0
    mov [rsi], al
    mov eax, edi
    shr eax, 12
    and al, 0x3f
    or al, 0x80
    mov [rsi + 1], al
    mov eax, edi
    shr eax, 6
    and al, 0x3f
    or al, 0x80
    mov [rsi + 2], al
    mov eax, edi
    and al, 0x3f
    or al, 0x80
    mov [rsi + 3], al
    mov eax, 4
    ret
.Lue_1:
    mov [rsi], dil
    mov eax, 1
    ret
.Lue_2:
    mov eax, edi
    shr eax, 6
    or al, 0xc0
    mov [rsi], al
    mov eax, edi
    and al, 0x3f
    or al, 0x80
    mov [rsi + 1], al
    mov eax, 2
    ret
.Lue_3:
    mov eax, edi
    shr eax, 12
    or al, 0xe0
    mov [rsi], al
    mov eax, edi
    shr eax, 6
    and al, 0x3f
    or al, 0x80
    mov [rsi + 1], al
    mov eax, edi
    and al, 0x3f
    or al, 0x80
    mov [rsi + 2], al
    mov eax, 3
    ret

# is_ident(byte) -> 1 for [A-Za-z0-9_] and bytes >= 0x80
FN is_ident
    movzx eax, dil
    cmp eax, 0x80
    jae 1f
    lea rcx, [rip + ident_table]
    movzx eax, byte ptr [rcx + rax]
    ret
1:  mov eax, 1
    ret

# to_lower(byte) -> byte
FN to_lower
    movzx eax, dil
    lea ecx, [rax - 'A']
    cmp ecx, 25
    ja 1f
    or eax, 0x20
1:  ret

.section .rodata
.globl ident_table
ident_table:
    .byte 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
    .byte 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
    .byte 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
    .byte 1,1,1,1,1,1,1,1,1,1,0,0,0,0,0,0
    .byte 0,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1
    .byte 1,1,1,1,1,1,1,1,1,1,1,0,0,0,0,1
    .byte 0,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1
    .byte 1,1,1,1,1,1,1,1,1,1,1,0,0,0,0,0
.text

# sort_u64(ptr, n): unsigned qwords ascending, in place (heapsort)
FN sort_u64
    push rbx
    push r12
    push r13
    push r14
    mov r12, rdi
    mov r13, rsi
    cmp r13, 2
    jb 9f
    mov rbx, r13
    shr rbx, 1
1:  test rbx, rbx
    jz 2f
    dec rbx
    mov rdi, rbx
    mov rsi, r13
    call sort_u64_sift
    jmp 1b
2:  mov r14, r13
3:  dec r14
    jz 9f
    mov rax, [r12]
    mov rcx, [r12 + r14*8]
    mov [r12], rcx
    mov [r12 + r14*8], rax
    xor edi, edi
    mov rsi, r14
    call sort_u64_sift
    jmp 3b
9:  pop r14
    pop r13
    pop r12
    pop rbx
    ret

# sort_u64_sift(i, n): sink a[i] into the max-heap a[0..n) (a in r12)
sort_u64_sift:
    mov rax, [r12 + rdi*8]
1:  lea rcx, [rdi*2 + 1]
    cmp rcx, rsi
    jae 3f
    lea rdx, [rcx + 1]
    cmp rdx, rsi
    jae 2f
    mov r8, [r12 + rdx*8]
    cmp r8, [r12 + rcx*8]
    jbe 2f
    mov rcx, rdx
2:  mov r8, [r12 + rcx*8]
    cmp r8, rax
    jbe 3f
    mov [r12 + rdi*8], r8
    mov rdi, rcx
    jmp 1b
3:  mov [r12 + rdi*8], rax
    ret

# path_basename(path, len) -> rax ptr, rdx len
FN path_basename
    lea rax, [rdi + rsi]
    mov rdx, rsi
1:  cmp rax, rdi
    je 2f
    cmp byte ptr [rax - 1], '/'
    je 2f
    dec rax
    jmp 1b
2:  lea rdx, [rdi + rsi]
    sub rdx, rax
    ret

# path_dirlen(path, len) -> length of directory part (without trailing /)
FN path_dirlen
.ifdef WINDOWS
    push rbx
    call path_rootlen
    mov rbx, rax
    mov rax, rsi
1:  test rax, rax
    jz 2f
    cmp byte ptr [rdi + rax - 1], '/'
    je 3f
    dec rax
    jmp 1b
3:  dec rax
2:  cmp rax, rbx
    cmovb rax, rbx
    pop rbx
    ret
.endif
    mov rax, rsi
1:  test rax, rax
    jz 2f
    cmp byte ptr [rdi + rax - 1], '/'
    je 3f
    dec rax
    jmp 1b
3:  dec rax
2:  ret

# path_ext(path, len) -> rax ptr, rdx len of extension after last '.' in basename (len 0 if none)
FN path_ext
    push rdi
    push rsi
    call path_basename
    pop rsi
    pop rdi
    mov r8, rax
    lea rcx, [rax + rdx]
    mov r9, rcx
1:  cmp rcx, r8
    je 2f
    dec rcx
    cmp byte ptr [rcx], '.'
    jne 1b
    cmp rcx, r8
    je 2f
    lea rax, [rcx + 1]
    mov rdx, r9
    sub rdx, rax
    ret
2:  mov rax, r9
    xor edx, edx
    ret

# path_rootlen(path) -> 0 for a relative path; preserve drive and UNC share boundaries.
FN path_rootlen
    xor eax, eax
.ifdef WINDOWS
    cmp byte ptr [rdi], 0
    je 9f
    cmp byte ptr [rdi + 1], ':'
    jne 1f
    cmp byte ptr [rdi + 2], '/'
    jne 9f
    mov eax, 3
    ret
1:  cmp word ptr [rdi], 0x2f2f
    jne 3f
    mov eax, 2
    mov ecx, 2
2:  cmp byte ptr [rdi + rax], 0
    je 9f
    cmp byte ptr [rdi + rax], '/'
    jne 21f
    dec ecx
    jz 22f
21: inc rax
    jmp 2b
22: inc rax
    ret
3:
.endif
    cmp byte ptr [rdi], '/'
    sete al
9:  ret
