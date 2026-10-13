# inflate: deflate and zlib streams (RFC 1950, 1951)
.include "raftaar.inc"

.equ ZFAST, 10                  # code bits resolved by one table lookup

# canonical huffman code (after stb_image)
STRUCT
F HF_fast, 2<<ZFAST             # (length << 9) | symbol for codes up to ZFAST bits, 0 = longer
F HF_max, 4*17                  # (last code + 1) << (16 - length), bit reversed codes compare against it
F HF_first, 2*16                # first code of each length
F HF_firstsym, 2*16             # sorted index of that code's symbol
F HF_value, 2*288               # symbols sorted by code
F HF_size, 288                  # their lengths
F HF_pad, 4
ENDSTRUCT HF_SIZE

.bss
.p2align 4
tabs: .zero 2 * HF_SIZE         # literal/length, then distance
clen: .zero HF_SIZE             # code length code
lens: .zero 320
.p2align 3
in_end: .quad 0
out_base: .quad 0
out_end: .quad 0
over: .long 0                   # zero bytes fed past the end of the input
final: .long 0

.text

# inflate(src, len, dst, cap, zlib) -> rax bytes written, rdx 0 stream end, 1 dst full, -1 bad data, -2 truncated
# The stream state lives in registers: r12 bit buffer (LSB first), r13d bit count, r14 input, r15 output, rbx tables.
FN inflate
    PROLOGUE
    mov r14, rdi
    lea rax, [rdi + rsi]
    mov [rip + in_end], rax
    mov r15, rdx
    mov [rip + out_base], rdx
    lea rax, [rdx + rcx]
    mov [rip + out_end], rax
    mov dword ptr [rip + over], 0
    xor r12d, r12d
    xor r13d, r13d
    lea rbx, [rip + tabs]
    test r8d, r8d
    jz .Lblock
    # zlib header: deflate, window up to 32K, no preset dictionary, check bits
    cmp rsi, 2
    jb .Ltrunc
    movzx eax, byte ptr [r14]
    movzx ecx, byte ptr [r14 + 1]
    mov edx, eax
    and edx, 15
    cmp edx, 8
    jne .Lbad
    cmp eax, 0x80
    jae .Lbad
    test ecx, 0x20
    jnz .Lbad
    shl eax, 8
    or eax, ecx
    xor edx, edx
    mov ecx, 31
    div ecx
    test edx, edx
    jnz .Lbad
    add r14, 2
.Lblock:
    call fill
    mov eax, r12d
    and eax, 1
    mov [rip + final], eax
    mov eax, r12d
    shr eax, 1
    and eax, 3
    shr r12, 3
    sub r13d, 3
    test eax, eax
    jz .Lstored
    cmp eax, 1
    je .Lfixed
    cmp eax, 2
    jne .Lbad
    # ---- dynamic codes ----
    mov eax, r12d
    and eax, 31
    add eax, 257
    mov r8d, eax                # hlit
    mov eax, r12d
    shr eax, 5
    and eax, 31
    inc eax
    mov r9d, eax                # hdist
    mov eax, r12d
    shr eax, 10
    and eax, 15
    add eax, 4
    mov r10d, eax               # hclen
    shr r12, 14
    sub r13d, 14
    cmp r8d, 286
    ja .Lbad
    cmp r9d, 30
    ja .Lbad
    push r8
    push r9
    # code length code lengths, 3 bits each in a fixed order
    lea rdi, [rip + lens]
    xor eax, eax
    mov ecx, 19
    rep stosb
    xor r11d, r11d
1:  cmp r11d, r10d
    jae 2f
    call fill
    lea rax, [rip + clen_order]
    movzx eax, byte ptr [rax + r11]
    mov ecx, r12d
    and ecx, 7
    lea rdx, [rip + lens]
    mov [rdx + rax], cl
    shr r12, 3
    sub r13d, 3
    inc r11d
    jmp 1b
2:  lea rdi, [rip + clen]
    lea rsi, [rip + lens]
    mov edx, 19
    call hf_build
    test eax, eax
    js .Lbad_pop
    # literal/length and distance code lengths
    mov r8, [rsp + 8]           # hlit
    mov r9, [rsp]               # hdist
    lea r10d, [r8 + r9]         # total
    xor r11d, r11d              # filled
3:  cmp r11d, r10d
    jae 8f
    call fill
    mov eax, r12d
    and eax, (1 << ZFAST) - 1
    lea rsi, [rip + clen]
    movzx eax, word ptr [rsi + HF_fast + rax*2]
    test eax, eax
    jz 31f
    mov ecx, eax
    shr ecx, 9
    shr r12, cl
    sub r13d, ecx
    and eax, 511
    jmp 32f
31: call hf_slow
    test eax, eax
    js .Lbad_pop
32: lea rdx, [rip + lens]
    cmp eax, 16
    jae 4f
    mov [rdx + r11], al
    inc r11d
    jmp 3b
4:  # repeats: 16 previous length 3-6 times, 17 zero 3-10 times, 18 zero 11-138 times
    xor edi, edi                # value to repeat
    cmp eax, 16
    jne 5f
    test r11d, r11d
    jz .Lbad_pop
    movzx edi, byte ptr [rdx + r11 - 1]
    mov ecx, r12d
    and ecx, 3
    add ecx, 3
    shr r12, 2
    sub r13d, 2
    jmp 7f
5:  cmp eax, 17
    jne 6f
    mov ecx, r12d
    and ecx, 7
    add ecx, 3
    shr r12, 3
    sub r13d, 3
    jmp 7f
6:  mov ecx, r12d
    and ecx, 127
    add ecx, 11
    shr r12, 7
    sub r13d, 7
7:  lea eax, [r11 + rcx]
    cmp eax, r10d
    ja .Lbad_pop
71: mov [rdx + r11], dil
    inc r11d
    dec ecx
    jnz 71b
    jmp 3b
8:  pop r9
    pop r8
    mov rdi, rbx
    lea rsi, [rip + lens]
    mov edx, r8d
    push r8
    push r9
    call hf_build
    pop r9
    pop r8
    test eax, eax
    js .Lbad
    lea rdi, [rbx + HF_SIZE]
    lea rsi, [rip + lens]
    add rsi, r8
    mov edx, r9d
    call hf_build
    test eax, eax
    js .Lbad
    jmp .Lcodes
.Lbad_pop:
    add rsp, 16
    jmp .Lbad

.Lfixed:
    lea rdi, [rip + lens]
    mov eax, 8
    mov ecx, 144
    rep stosb
    mov eax, 9
    mov ecx, 112
    rep stosb
    mov eax, 7
    mov ecx, 24
    rep stosb
    mov eax, 8
    mov ecx, 8
    rep stosb
    mov rdi, rbx
    lea rsi, [rip + lens]
    mov edx, 288
    call hf_build
    lea rdi, [rip + lens]
    mov eax, 5
    mov ecx, 30
    rep stosb
    lea rdi, [rbx + HF_SIZE]
    lea rsi, [rip + lens]
    mov edx, 30
    call hf_build

    # ---- compressed data ----
.Lcodes:
    call fill
    mov eax, r12d
    and eax, (1 << ZFAST) - 1
    movzx eax, word ptr [rbx + HF_fast + rax*2]
    test eax, eax
    jz .Llit_slow
    mov ecx, eax
    shr ecx, 9
    shr r12, cl
    sub r13d, ecx
    and eax, 511
.Llit:
    cmp eax, 256
    jae .Llength
    cmp r15, [rip + out_end]
    jae .Lfull
    mov [r15], al
    inc r15
    jmp .Lcodes
.Llit_slow:
    mov rsi, rbx
    call hf_slow
    test eax, eax
    js .Lbad
    jmp .Llit
.Llength:
    je .Lblock_end
    sub eax, 257
    cmp eax, 29
    jae .Lbad
    lea rdx, [rip + len_base]
    movzx r8d, word ptr [rdx + rax*2]
    lea rdx, [rip + len_extra]
    movzx ecx, byte ptr [rdx + rax]
    mov eax, 1
    shl eax, cl
    dec eax
    and eax, r12d
    shr r12, cl
    sub r13d, ecx
    add r8d, eax                # length
    # distance
    mov eax, r12d
    and eax, (1 << ZFAST) - 1
    movzx eax, word ptr [rbx + HF_SIZE + HF_fast + rax*2]
    test eax, eax
    jz .Ldist_slow
    mov ecx, eax
    shr ecx, 9
    shr r12, cl
    sub r13d, ecx
    and eax, 511
.Ldist:
    cmp eax, 30
    jae .Lbad
    lea rdx, [rip + dist_base]
    movzx r9d, word ptr [rdx + rax*2]
    lea rdx, [rip + dist_extra]
    movzx ecx, byte ptr [rdx + rax]
    mov eax, 1
    shl eax, cl
    dec eax
    and eax, r12d
    shr r12, cl
    sub r13d, ecx
    add r9d, eax                # distance
    mov rax, r15
    sub rax, [rip + out_base]
    cmp r9, rax
    ja .Lbad
    # copy, clipped to the output
    xor r10d, r10d
    mov rax, [rip + out_end]
    sub rax, r15
    cmp r8, rax
    jbe 1f
    mov r8, rax
    mov r10d, 1
1:  mov rsi, r15
    sub rsi, r9
    mov rcx, r8
    cmp r9d, 1
    je .Lrun
    cmp r9d, 8
    jb .Lbytes
2:  cmp rcx, 8
    jb .Lbytes
    mov rax, [rsi]
    mov [r15], rax
    add rsi, 8
    add r15, 8
    sub rcx, 8
    jmp 2b
.Lbytes:
    test rcx, rcx
    jz 3f
    mov al, [rsi]
    mov [r15], al
    inc rsi
    inc r15
    dec rcx
    jmp .Lbytes
.Lrun:
    movzx eax, byte ptr [rsi]
    mov rdi, r15
    rep stosb
    mov r15, rdi
3:  test r10d, r10d
    jnz .Lfull
    jmp .Lcodes
.Ldist_slow:
    lea rsi, [rbx + HF_SIZE]
    call hf_slow
    test eax, eax
    js .Lbad
    jmp .Ldist

.Lblock_end:
    cmp dword ptr [rip + final], 0
    je .Lblock
    # the last code must not have used padding
    mov eax, [rip + over]
    shl eax, 3
    cmp eax, r13d
    ja .Ltrunc
    xor edx, edx
    jmp .Lret

    # ---- stored block ----
.Lstored:
    # drop to a byte boundary and hand the whole bytes back to the input
    mov ecx, r13d
    and ecx, 7
    shr r12, cl
    sub r13d, ecx
    mov eax, [rip + over]
    shl eax, 3
    cmp eax, r13d
    ja .Ltrunc
    mov eax, r13d
    shr eax, 3
    sub eax, [rip + over]
    sub r14, rax
    xor r12d, r12d
    xor r13d, r13d
    mov dword ptr [rip + over], 0
    mov rax, [rip + in_end]
    sub rax, r14
    cmp rax, 4
    jb .Ltrunc
    movzx ecx, word ptr [r14]
    movzx edx, word ptr [r14 + 2]
    xor edx, 0xffff
    cmp ecx, edx
    jne .Lbad
    add r14, 4
    sub rax, 4                  # input left
    xor r10d, r10d              # 1 = input short, 2 = output full
    cmp rcx, rax
    jbe 1f
    mov rcx, rax
    mov r10d, 1
1:  mov rax, [rip + out_end]
    sub rax, r15
    cmp rcx, rax
    jbe 2f
    mov rcx, rax
    mov r10d, 2
2:  mov rsi, r14
    mov rdi, r15
    add r14, rcx
    add r15, rcx
    rep movsb
    cmp r10d, 1
    je .Ltrunc
    cmp r10d, 2
    je .Lfull
    jmp .Lblock_end

.Lfull:
    mov edx, 1
    jmp .Lret
.Lbad:
    mov rdx, -1
    jmp .Lret
.Ltrunc:
    mov rdx, -2
.Lret:
    mov rax, r15
    sub rax, [rip + out_base]
    EPILOGUE

# fill(): top the bit buffer up to at least 56 bits; past the end of the input it adds zero bytes,
# and once more than a buffer of them would be needed the stream is cut short (jumps to .Ltrunc)
fill:
    mov rax, [rip + in_end]
    sub rax, r14
    cmp rax, 8
    jb 2f
    mov rax, [r14]
    mov ecx, r13d
    shl rax, cl
    or r12, rax
    mov eax, 63
    sub eax, r13d
    shr eax, 3
    add r14, rax
    or r13d, 56
    ret
2:  cmp r13d, 56
    ja 4f
    cmp r14, [rip + in_end]
    jae 3f
    movzx eax, byte ptr [r14]
    inc r14
    mov ecx, r13d
    shl rax, cl
    or r12, rax
    add r13d, 8
    jmp 2b
3:  add r13d, 8
    inc dword ptr [rip + over]
    cmp dword ptr [rip + over], 8
    jbe 2b
    add rsp, 8                  # called from inflate's body only
    jmp .Ltrunc
4:  ret

# hf_slow(): code longer than ZFAST bits with the table in rsi -> eax symbol or -1; consumes the bits
hf_slow:
    # the next 16 bits, reversed (codes are stored MSB first)
    mov rdx, r12
    xor eax, eax
    mov ecx, 16
1:  add eax, eax
    mov edi, edx
    and edi, 1
    or eax, edi
    shr rdx, 1
    dec ecx
    jnz 1b
    mov ecx, ZFAST + 1
2:  cmp eax, [rsi + HF_max + rcx*4]
    jb 3f
    inc ecx
    cmp ecx, 16
    jb 2b
    mov eax, -1
    ret
3:  # index = (code >> (16 - length)) - first[length] + firstsym[length]
    mov edx, ecx
    mov ecx, 16
    sub ecx, edx
    shr eax, cl
    movzx ecx, word ptr [rsi + HF_first + rdx*2]
    sub eax, ecx
    movzx ecx, word ptr [rsi + HF_firstsym + rdx*2]
    add eax, ecx
    cmp eax, 288
    jae 4f
    movzx ecx, byte ptr [rsi + HF_size + rax]
    cmp ecx, edx
    jne 4f
    shr r12, cl
    sub r13d, ecx
    movzx eax, word ptr [rsi + HF_value + rax*2]
    ret
4:  mov eax, -1
    ret

# hf_build(table, lengths u8[], n) -> 0 or -1 (over-subscribed code)
hf_build:
    PROLOGUE 176
    mov rbx, rdi
    mov r12, rsi
    mov r13d, edx
    # rsp: sizes u32[17] at 0, next code u32[16] at 80
    xor eax, eax
    lea rdi, [rsp]
    mov ecx, 176 / 8
    rep stosq
    lea rdi, [rbx + HF_fast]
    mov ecx, (2 << ZFAST) / 8
    rep stosq
    xor ecx, ecx
1:  cmp ecx, r13d
    jae 2f
    movzx eax, byte ptr [r12 + rcx]
    inc dword ptr [rsp + rax*4]
    inc ecx
    jmp 1b
2:  mov dword ptr [rsp], 0
    xor edx, edx                # code
    xor r8d, r8d                # symbols so far
    mov ecx, 1
3:  mov [rsp + 80 + rcx*4], edx
    mov [rbx + HF_first + rcx*2], dx
    mov [rbx + HF_firstsym + rcx*2], r8w
    mov eax, [rsp + rcx*4]
    add edx, eax
    add r8d, eax
    test eax, eax
    jz 4f
    mov eax, 1
    shl eax, cl
    cmp edx, eax
    ja 9f
4:  mov eax, edx
    mov r9d, ecx
    mov ecx, 16
    sub ecx, r9d
    shl eax, cl
    mov ecx, r9d
    mov [rbx + HF_max + rcx*4], eax
    add edx, edx
    inc ecx
    cmp ecx, 16
    jb 3b
    mov dword ptr [rbx + HF_max + 16*4], 0x10000
    # symbols
    xor r14d, r14d
5:  cmp r14d, r13d
    jae 8f
    movzx ecx, byte ptr [r12 + r14]
    test ecx, ecx
    jz 7f
    mov eax, [rsp + 80 + rcx*4]         # this symbol's code
    movzx edx, word ptr [rbx + HF_first + rcx*2]
    mov edi, eax
    sub edi, edx
    movzx edx, word ptr [rbx + HF_firstsym + rcx*2]
    add edi, edx                        # sorted index
    cmp edi, 288
    jae 9f
    mov [rbx + HF_size + rdi], cl
    mov [rbx + HF_value + rdi*2], r14w
    inc dword ptr [rsp + 80 + rcx*4]
    cmp ecx, ZFAST
    ja 7f
    # reverse the code, then fill every table slot that starts with it
    xor edx, edx
    mov r9d, ecx
6:  add edx, edx
    mov r10d, eax
    and r10d, 1
    or edx, r10d
    shr eax, 1
    dec r9d
    jnz 6b
    mov eax, ecx
    shl eax, 9
    or eax, r14d
    mov r9d, 1
    shl r9d, cl
61: cmp edx, 1 << ZFAST
    jae 7f
    mov [rbx + HF_fast + rdx*2], ax
    add edx, r9d
    jmp 61b
7:  inc r14d
    jmp 5b
8:  xor eax, eax
    EPILOGUE
9:  mov eax, -1
    EPILOGUE

.section .rodata
clen_order: .byte 16, 17, 18, 0, 8, 7, 9, 6, 10, 5, 11, 4, 12, 3, 13, 2, 14, 1, 15
.p2align 1
len_base: .short 3, 4, 5, 6, 7, 8, 9, 10, 11, 13, 15, 17, 19, 23, 27, 31, 35, 43, 51, 59, 67, 83, 99, 115, 131, 163, 195, 227, 258
dist_base: .short 1, 2, 3, 4, 5, 7, 9, 13, 17, 25, 33, 49, 65, 97, 129, 193, 257, 385, 513, 769, 1025, 1537, 2049, 3073, 4097, 6145, 8193, 12289, 16385, 24577
len_extra: .byte 0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 2, 2, 2, 2, 3, 3, 3, 3, 4, 4, 4, 4, 5, 5, 5, 5, 0
dist_extra: .byte 0, 0, 0, 0, 1, 1, 2, 2, 3, 3, 4, 4, 5, 5, 6, 6, 7, 7, 8, 8, 9, 9, 10, 10, 11, 11, 12, 12, 13, 13
