# x86 semantics the macOS translation (tools/arm64.py) must keep: flags of 8/16/32/64-bit
# arithmetic, partial registers, extensions, multiply and divide, bit instructions, string
# instructions and SSE. The expected output comes from the x86-64 build; each line is
# "case value flags" in hex, flags = CF | ZF << 1 | SF << 2 | OF << 3.
.include "raftaar.inc"

# r12 = the flags of the instruction before
.macro FLAGS
    setc cl
    setz dl
    sets r8b
    seto r9b
    movzx r12d, cl
    movzx edx, dl
    lea r12d, [r12 + rdx*2]
    movzx edx, r8b
    lea r12d, [r12 + rdx*4]
    movzx edx, r9b
    lea r12d, [r12 + rdx*8]
.endm

# prints rbx and r12
.macro CASE text
    lea rdi, [rip + .Lc\@]
    mov rsi, rbx
    mov rdx, r12
    call show
    .section .rodata
.Lc\@: .asciz "\text"
    .text
.endm

# prints the 16 bytes at xbuf
.macro XCASE text
    lea rdi, [rip + .Lx\@]
    mov rsi, [rip + xbuf]
    mov rdx, [rip + xbuf + 8]
    call show
    .section .rodata
.Lx\@: .asciz "\text"
    .text
.endm

# FLAGS without CF: an inc or dec before (their carry is the older instruction's)
.macro FLAGS_ZSO
    setz dl
    sets r8b
    seto r9b
    movzx edx, dl
    lea r12d, [rdx*2]
    movzx edx, r8b
    lea r12d, [r12 + rdx*4]
    movzx edx, r9b
    lea r12d, [r12 + rdx*8]
.endm

.bss
.p2align 4
out: .zero SB_SIZE
xbuf: .zero 16
mem: .zero 64

.text
FN main
    PROLOGUE 16

    # ---- flags by width
    mov eax, 0x7f
    add al, 1
    mov rbx, rax
    FLAGS
    CASE "add8 overflow"
    mov eax, 0xff
    add al, 1
    mov rbx, rax
    FLAGS
    CASE "add8 carry"
    mov eax, 0x80
    sub al, 1
    mov rbx, rax
    FLAGS
    CASE "sub8 overflow"
    xor eax, eax
    sub al, 1
    mov rbx, rax
    FLAGS
    CASE "sub8 borrow"
    mov eax, 0x7fff
    add ax, 1
    mov rbx, rax
    FLAGS
    CASE "add16 overflow"
    xor eax, eax
    sub ax, 1
    mov rbx, rax
    FLAGS
    CASE "sub16 borrow"
    mov eax, -1
    add eax, 1
    mov rbx, rax
    FLAGS
    CASE "add32 carry"
    mov eax, 0x80000000
    sub eax, 1
    mov rbx, rax
    FLAGS
    CASE "sub32 overflow"
    movabs rax, 0x7fffffffffffffff
    add rax, 1
    mov rbx, rax
    FLAGS
    CASE "add64 overflow"
    mov eax, 1
    cmp rax, 2
    mov rbx, rax
    FLAGS
    CASE "cmp64 below"
    mov eax, 0x80
    cmp al, 0x7f
    mov rbx, rax
    FLAGS
    CASE "cmp8 signed"
    mov eax, 0x8000
    cmp ax, 1
    mov rbx, rax
    FLAGS
    CASE "cmp16 overflow"
    xor eax, eax
    neg eax
    mov rbx, rax
    FLAGS
    CASE "neg zero"
    mov eax, 5
    neg eax
    mov rbx, rax
    FLAGS
    CASE "neg five"
    mov eax, 0x8000
    dec ax
    mov rbx, rax
    FLAGS_ZSO
    CASE "dec16 overflow"
    mov eax, 0x7f
    inc al
    mov rbx, rax
    FLAGS_ZSO
    CASE "inc8 overflow"
    stc
    mov eax, 5
    inc eax
    setc bl
    movzx ebx, bl
    xor r12d, r12d
    CASE "inc keeps carry"
    mov eax, 0x80000000
    or eax, 0
    mov rbx, rax
    FLAGS
    CASE "or sign"
    mov eax, 0xf0
    and eax, 0x0f
    mov rbx, rax
    FLAGS
    CASE "and zero"
    mov eax, 0x80
    test al, al
    mov rbx, rax
    FLAGS
    CASE "test8 sign"
    mov eax, 0x8000
    test ax, 0x8000
    mov rbx, rax
    FLAGS
    CASE "test16"
    mov byte ptr [rip + mem], 0xff
    add byte ptr [rip + mem], 1
    movzx ebx, byte ptr [rip + mem]
    FLAGS
    CASE "add mem8"
    mov dword ptr [rip + mem], 1
    sub dword ptr [rip + mem], 2
    mov ebx, [rip + mem]
    FLAGS
    CASE "sub mem32"
    mov word ptr [rip + mem], 0x7fff
    inc word ptr [rip + mem]
    movzx ebx, word ptr [rip + mem]
    FLAGS_ZSO
    CASE "inc mem16"

    # ---- partial registers and extensions
    mov rax, -1
    mov al, 0x12
    mov rbx, rax
    xor r12d, r12d
    CASE "mov al"
    mov rax, -1
    mov ah, 0x34
    mov rbx, rax
    CASE "mov ah"
    mov rax, -1
    mov ax, 0x5678
    mov rbx, rax
    CASE "mov ax"
    mov rax, -1
    mov eax, 1
    mov rbx, rax
    CASE "mov eax"
    mov rax, -1
    mov ecx, 1
    cmp ecx, 1
    sete ah
    mov rbx, rax
    CASE "sete ah"
    mov eax, 0x1234
    xchg al, ah
    mov rbx, rax
    CASE "xchg al ah"
    mov rax, -1
    mov ecx, 0x80
    movsx eax, cl
    mov rbx, rax
    CASE "movsx eax byte"
    mov ecx, 0x8000
    movsx rax, cx
    mov rbx, rax
    CASE "movsx rax word"
    mov ecx, 0x80000000
    movsxd rax, ecx
    mov rbx, rax
    CASE "movsxd"
    mov rax, -1
    mov ecx, 0xffff
    movzx eax, cx
    mov rbx, rax
    CASE "movzx"
    mov eax, 0x80000000
    cdqe
    mov rbx, rax
    CASE "cdqe"
    mov eax, 0x80000000
    cdq
    mov rbx, rdx
    CASE "cdq"
    mov rax, -5
    cqo
    mov rbx, rdx
    CASE "cqo"

    # ---- shifts
    mov eax, 1
    shl eax, 31
    mov rbx, rax
    CASE "shl32"
    mov eax, 0x80000000
    sar eax, 4
    mov rbx, rax
    CASE "sar32"
    mov eax, 0x80000000
    shr eax, 4
    mov rbx, rax
    CASE "shr32"
    mov eax, 0x80
    sar al, 3
    mov rbx, rax
    CASE "sar8"
    mov eax, 1
    mov ecx, 33
    shl eax, cl
    mov rbx, rax
    CASE "shl32 by 33"
    mov eax, 1
    mov ecx, 65
    shl rax, cl
    mov rbx, rax
    CASE "shl64 by 65"
    mov eax, 0x80000001
    rol eax, 4
    mov rbx, rax
    CASE "rol32"
    movabs rax, 0x0123456789abcdef
    ror rax, 8
    mov rbx, rax
    CASE "ror64"

    # ---- multiply and divide
    mov rax, -1
    mov ecx, 2
    mul rcx
    mov rbx, rax
    mov r12, rdx
    CASE "mul64"
    mov eax, 0x80000000
    mov ecx, 4
    mul ecx
    mov rbx, rax
    mov r12, rdx
    CASE "mul32"
    mov rax, -2
    mov ecx, 3
    imul rcx
    mov rbx, rax
    mov r12, rdx
    CASE "imul64 wide"
    mov eax, -3
    mov ecx, 5
    imul eax, ecx
    mov rbx, rax
    xor r12d, r12d
    CASE "imul32"
    mov ecx, -7
    imul eax, ecx, 7
    mov rbx, rax
    CASE "imul32 imm"
    mov edx, 1
    xor eax, eax
    mov ecx, 0x10
    div ecx
    mov rbx, rax
    mov r12, rdx
    CASE "div32"
    mov edx, 1
    xor eax, eax
    mov ecx, 2
    div rcx
    mov rbx, rax
    mov r12, rdx
    CASE "div128"
    mov eax, -7
    cdq
    mov ecx, 2
    idiv ecx
    mov rbx, rax
    mov r12, rdx
    CASE "idiv32"
    mov rax, -7
    cqo
    mov ecx, -2
    idiv rcx
    mov rbx, rax
    mov r12, rdx
    CASE "idiv64"

    # ---- conditional moves
    mov rax, -1
    mov ecx, 5
    cmp ecx, ecx
    cmovne eax, ecx
    mov rbx, rax
    xor r12d, r12d
    CASE "cmov32 false"
    mov rax, -1
    mov ecx, 5
    cmp ecx, 6
    cmovl rax, rcx
    mov rbx, rax
    CASE "cmov64 true"

    # ---- bits
    mov eax, 8
    bt eax, 3
    setc bl
    movzx ebx, bl
    CASE "bt"
    xor ecx, ecx
    mov eax, 1
    cmp eax, eax
    bt eax, 1
    FLAGS
    mov ebx, eax
    and r12d, 3
    CASE "bt keeps zf"
    xor eax, eax
    bts rax, 63
    setc cl
    bts rax, 63
    setc dl
    mov rbx, rax
    movzx r12d, cl
    shl edx, 1
    or r12d, edx
    CASE "bts64"
    mov rax, -1
    mov r14d, 70
    btr rax, r14
    setc cl
    mov rbx, rax
    movzx r12d, cl
    CASE "btr64 reg"
    mov qword ptr [rip + mem], 0
    mov qword ptr [rip + mem + 8], 0
    mov ecx, 70
    bts qword ptr [rip + mem], rcx
    mov rbx, [rip + mem + 8]
    xor r12d, r12d
    CASE "bts bit string"
    mov esi, 0x50
    bsf ecx, esi
    mov ebx, ecx
    CASE "bsf32"
    mov ecx, 99
    xor esi, esi
    bsf ecx, esi
    setz r12b
    movzx r12d, r12b
    mov ebx, ecx
    CASE "bsf zero"
    movabs rsi, 0x8000000000000000
    bsf rax, rsi
    mov rbx, rax
    xor r12d, r12d
    CASE "bsf64"
    mov esi, 0x50
    bsr ecx, esi
    mov ebx, ecx
    CASE "bsr32"
    mov eax, 0x11223344
    bswap eax
    mov rbx, rax
    CASE "bswap32"
    movabs rax, 0x0102030405060708
    bswap rax
    mov rbx, rax
    CASE "bswap64"
    call carry_set
    setc bl
    movzx ebx, bl
    call carry_clear
    setc r12b
    movzx r12d, r12b
    CASE "stc clc across ret"

    # ---- string instructions
    lea rdi, [rip + mem]
    lea rsi, [rip + s_abcdef]
    mov ecx, 7
    rep movsb
    lea rsi, [rip + mem]
    lea rdi, [rip + mem + 1]
    mov ecx, 4
    rep movsb
    mov rbx, [rip + mem]
    mov r12, rcx
    CASE "movsb overlap"
    lea rsi, [rip + s_abcdef]
    lea rdi, [rip + mem]
    mov ecx, 1
    rep movsd
    lea rax, [rip + mem + 4]
    sub rdi, rax
    lea rax, [rip + s_abcdef + 4]
    sub rsi, rax
    or rdi, rsi
    or rdi, rcx
    mov ebx, [rip + mem]
    mov r12, rdi
    CASE "movsd"
    lea rdi, [rip + mem]
    mov eax, 0x61
    mov ecx, 3
    rep stosb
    mov eax, 0x11223344
    mov ecx, 1
    rep stosd
    mov ebx, [rip + mem]
    mov r12d, [rip + mem + 3]
    CASE "stos"
    lea rsi, [rip + s_abcx]
    lea rdi, [rip + s_abcy]
    mov ecx, 4
    test ecx, ecx               # a count of 0 would leave the flags as they are
    repe cmpsb
    mov rbx, rcx
    FLAGS
    CASE "cmpsb differ"
    lea rsi, [rip + s_abcx]
    lea rdi, [rip + s_abcy]
    mov ecx, 3
    test ecx, ecx               # a count of 0 would leave the flags as they are
    repe cmpsb
    mov rbx, rcx
    FLAGS
    CASE "cmpsb equal"
    xor eax, eax
    cmp eax, 1
    lea rsi, [rip + s_abcx]
    lea rdi, [rip + s_abcy]
    mov ecx, 0
    repe cmpsb
    mov rbx, rcx
    FLAGS
    CASE "cmpsb none"
    lea rdi, [rip + s_abcx]
    xor eax, eax
    mov rcx, -1
    repne scasb
    mov rbx, rcx
    FLAGS
    CASE "scasb"

    # ---- SSE scalar
    movss xmm0, [rip + f_nan]
    movss xmm1, [rip + f_one]
    comiss xmm0, xmm1
    FLAGS
    xor ebx, ebx
    CASE "comiss nan"
    movss xmm0, [rip + f_one]
    movss xmm1, [rip + f_two]
    comiss xmm0, xmm1
    FLAGS
    CASE "comiss less"
    comiss xmm1, xmm0
    FLAGS
    CASE "comiss greater"
    movss xmm0, [rip + f_nan]
    movss xmm1, [rip + f_one]
    minss xmm0, xmm1
    movd ebx, xmm0
    xor r12d, r12d
    CASE "minss nan first"
    movss xmm0, [rip + f_one]
    movss xmm1, [rip + f_nan]
    minss xmm0, xmm1
    movd ebx, xmm0
    CASE "minss nan second"
    movss xmm0, [rip + f_zero]
    movss xmm1, [rip + f_mzero]
    minss xmm0, xmm1
    movd ebx, xmm0
    CASE "minss zeros"
    movss xmm0, [rip + f_mzero]
    movss xmm1, [rip + f_zero]
    maxss xmm0, xmm1
    movd ebx, xmm0
    CASE "maxss zeros"
    movss xmm0, [rip + f_two]
    movss xmm1, [rip + f_one]
    maxss xmm0, xmm1
    movd ebx, xmm0
    CASE "maxss"
    movdqu xmm0, [rip + v_lanes]
    movss xmm1, [rip + f_one]
    minss xmm0, xmm1
    movdqu [rip + xbuf], xmm0
    XCASE "minss upper lanes"
    movss xmm0, [rip + f_2_5]
    cvtss2si eax, xmm0
    mov ebx, eax
    movss xmm0, [rip + f_3_5]
    cvtss2si eax, xmm0
    mov r12d, eax
    CASE "cvtss2si even"
    movss xmm0, [rip + f_m2_7]
    cvttss2si eax, xmm0
    mov ebx, eax
    xor r12d, r12d
    CASE "cvttss2si"
    mov eax, 16777217
    cvtsi2ss xmm0, eax
    movd ebx, xmm0
    CASE "cvtsi2ss round"
    movss xmm0, [rip + f_two]
    sqrtss xmm0, xmm0
    movd ebx, xmm0
    CASE "sqrtss"
    movss xmm0, [rip + f_2_5]
    roundss xmm1, xmm0, 1
    movd ebx, xmm1
    roundss xmm1, xmm0, 2
    movd r12d, xmm1
    CASE "roundss floor ceil"
    movss xmm0, [rip + f_one]
    divss xmm0, [rip + f_three]
    movd ebx, xmm0
    xor r12d, r12d
    CASE "divss"

    # ---- SSE2 integer
    movdqu xmm0, [rip + v_a]
    movdqu xmm1, [rip + v_b]
    por xmm0, xmm1
    movdqu [rip + xbuf], xmm0
    XCASE "por"
    movdqu xmm0, [rip + v_a]
    pxor xmm0, [rip + v_b]
    movdqu [rip + xbuf], xmm0
    XCASE "pxor mem"
    movdqu xmm0, [rip + v_a]
    paddb xmm0, [rip + v_b]
    movdqu [rip + xbuf], xmm0
    XCASE "paddb"
    movdqu xmm0, [rip + v_a]
    paddw xmm0, [rip + v_b]
    movdqu [rip + xbuf], xmm0
    XCASE "paddw"
    movdqu xmm0, [rip + v_a]
    movdqu xmm1, [rip + v_b]
    pmullw xmm0, xmm1
    movdqu [rip + xbuf], xmm0
    XCASE "pmullw"
    movdqu xmm0, [rip + v_a]
    psrlw xmm0, 3
    movdqu [rip + xbuf], xmm0
    XCASE "psrlw"
    movdqu xmm0, [rip + v_a]
    psrlw xmm0, 16
    movdqu [rip + xbuf], xmm0
    XCASE "psrlw 16"
    movdqu xmm0, [rip + v_a]
    psrldq xmm0, 3
    movdqu [rip + xbuf], xmm0
    XCASE "psrldq 3"
    movdqu xmm0, [rip + v_a]
    psrldq xmm0, 15
    movdqu [rip + xbuf], xmm0
    XCASE "psrldq 15"
    movdqu xmm1, [rip + v_a]
    pshufd xmm0, xmm1, 0x4e
    movdqu [rip + xbuf], xmm0
    XCASE "pshufd 4e"
    pshufd xmm0, [rip + v_a], 0x1b
    movdqu [rip + xbuf], xmm0
    XCASE "pshufd 1b mem"
    movdqu xmm0, [rip + v_a]
    pshufd xmm0, xmm0, 0x93
    movdqu [rip + xbuf], xmm0
    XCASE "pshufd self"
    movdqu xmm0, [rip + v_a]
    pshuflw xmm0, xmm0, 0
    movdqu [rip + xbuf], xmm0
    XCASE "pshuflw 0"
    movdqu xmm1, [rip + v_a]
    pshuflw xmm0, xmm1, 0x1b
    movdqu [rip + xbuf], xmm0
    XCASE "pshuflw 1b"
    movdqu xmm0, [rip + v_a]
    movdqu xmm1, [rip + v_b]
    punpcklbw xmm0, xmm1
    movdqu [rip + xbuf], xmm0
    XCASE "punpcklbw"
    movdqu xmm0, [rip + v_a]
    movdqu xmm1, [rip + v_b]
    punpckldq xmm0, xmm1
    movdqu [rip + xbuf], xmm0
    XCASE "punpckldq"
    movdqu xmm0, [rip + v_a]
    movdqu xmm1, [rip + v_b]
    punpcklqdq xmm0, xmm1
    movdqu [rip + xbuf], xmm0
    XCASE "punpcklqdq"
    movdqu xmm0, [rip + v_a]
    punpcklqdq xmm0, xmm0
    movdqu [rip + xbuf], xmm0
    XCASE "punpcklqdq self"
    movdqu xmm0, [rip + v_words]
    movdqu xmm1, [rip + v_b]
    packuswb xmm0, xmm1
    movdqu [rip + xbuf], xmm0
    XCASE "packuswb"
    movdqu xmm0, [rip + v_a]
    movdqu xmm1, [rip + v_a2]
    pcmpeqb xmm0, xmm1
    movdqu [rip + xbuf], xmm0
    pmovmskb ebx, xmm0
    mov r12, [rip + xbuf]
    CASE "pcmpeqb pmovmskb"
    movdqu xmm8, [rip + v_b]
    pmovmskb eax, xmm8
    mov ebx, eax
    xor r12d, r12d
    CASE "pmovmskb xmm8"
    pxor xmm9, xmm9
    movd xmm9, [rip + v_a]
    movdqu [rip + xbuf], xmm9
    XCASE "movd clears"

    mov rdi, 1
    mov rsi, [rip + out + SB_ptr]
    mov rdx, [rip + out + SB_len]
    call write_all
    xor eax, eax
    EPILOGUE

# flags returned by subroutines
carry_set:
    xor eax, eax
    stc
    ret
carry_clear:
    stc
    clc
    ret

# show(label, value, flags): "label value flags" in hex
show:
    push rbx
    push r12
    push r13
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    lea rdi, [rip + out]
    mov rsi, rbx
    call sb_push_cstr
    mov rsi, r12
    call hex
    mov rsi, r13
    call hex
    lea rdi, [rip + out]
    mov esi, 10
    call sb_push_byte
    pop r13
    pop r12
    pop rbx
    ret

# hex(value): " " and the value
hex:
    push rbx
    sub rsp, 32
    mov rbx, rsi
    lea rdi, [rip + out]
    mov esi, ' '
    call sb_push_byte
    mov rdi, rsp
    mov rsi, rbx
    call fmt_hex
    lea rdi, [rip + out]
    mov rsi, rsp
    mov rdx, rax
    call sb_push
    add rsp, 32
    pop rbx
    ret

.section .rodata
s_abcdef: .asciz "abcdefgh"
s_abcx: .asciz "abcx"
s_abcy: .asciz "abcy"
.p2align 4
v_a: .byte 0x01, 0x82, 0x03, 0xf4, 0x05, 0x86, 0x07, 0x88, 0xf9, 0x0a, 0x8b, 0x0c, 0x8d, 0x0e, 0xff, 0x10
v_a2: .byte 0x01, 0x00, 0x03, 0xf4, 0x00, 0x86, 0x07, 0x88, 0xf9, 0x0a, 0x00, 0x0c, 0x8d, 0x0e, 0xff, 0x00
v_b: .byte 0xff, 0x10, 0x80, 0x7f, 0x01, 0x02, 0x03, 0x04, 0x90, 0xa0, 0xb0, 0xc0, 0xd0, 0xe0, 0xf0, 0x55
v_words: .short -5, 300, 128, 255, 256, 0, -32768, 32767
v_lanes: .long 0x40000000, 0x11111111, 0x22222222, 0x33333333
.p2align 2
f_nan: .long 0x7fc00000
f_one: .float 1.0
f_two: .float 2.0
f_three: .float 3.0
f_zero: .float 0.0
f_mzero: .long 0x80000000
f_2_5: .float 2.5
f_3_5: .float 3.5
f_m2_7: .float -2.7
