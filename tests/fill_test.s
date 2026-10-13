# A translucent gfx_fill blends four pixels at a time: it must give what color_mix (the one-pixel
# BLEND) gives each pixel, for every alpha, width and offset, and leave the pixels around it alone.
.include "raftaar.inc"
.equ W, 64
.equ H, 3
.bss
.p2align 4
pixels: .zero W * H * 4
expect: .zero W * H * 4
seed: .quad 0
.text
FN main
    PROLOGUE 16
    lea rdi, [rip + pixels]
    mov esi, W
    mov edx, H
    mov ecx, W
    call gfx_set_target
    mov qword ptr [rip + seed], 12345
    mov ebx, 20000              # rounds
.Lround:
    # random pixels, kept as the expected picture too
    xor r12d, r12d
1:  call rand
    lea rcx, [rip + pixels]
    mov [rcx + r12*4], eax
    lea rcx, [rip + expect]
    mov [rcx + r12*4], eax
    inc r12d
    cmp r12d, W * H
    jb 1b
    # a color with an alpha of 1..254 (255 fills, 0 does nothing), x 0..15, width 1..48, rows 1..2
    call rand
    mov r13d, eax
    and r13d, 0x00ffffff
    call rand
    xor edx, edx
    mov ecx, 254
    div ecx
    lea eax, [rdx + 1]
    shl eax, 24
    or r13d, eax                # color
    call rand
    and eax, 15
    mov r14d, eax               # x
    call rand
    xor edx, edx
    mov ecx, 48
    div ecx
    lea r15d, [rdx + 1]         # w
    # the expected rows 1..2
    mov r12d, W
2:  mov eax, r12d
    sub eax, W
    cmp eax, r15d
    jae 3f
    lea rcx, [rip + expect]
    mov eax, r12d
    add eax, r14d
    mov edi, [rcx + rax*4]
    mov esi, r13d
    mov edx, r13d
    shr edx, 24
    push rax
    push rax
    call color_mix
    pop rcx
    pop rcx
    lea rdx, [rip + expect]
    mov [rdx + rcx*4], eax
    lea eax, [rcx + W]
    lea rcx, [rip + expect]
    mov edi, [rcx + rax*4]
    push rax
    push rax
    mov esi, r13d
    mov edx, r13d
    shr edx, 24
    call color_mix
    pop rcx
    pop rcx
    lea rdx, [rip + expect]
    mov [rdx + rcx*4], eax
    inc r12d
    jmp 2b
3:  mov edi, r14d
    mov esi, 1
    mov edx, r15d
    mov ecx, 2
    mov r8d, r13d
    call gfx_fill
    lea rdi, [rip + pixels]
    lea rsi, [rip + expect]
    mov edx, W * H * 4
    call memeq
    test eax, eax
    jz fail
    dec ebx
    jnz .Lround
    lea rdi, [rip + ok]
    call log_cstr
    xor eax, eax
    EPILOGUE
fail:
    lea rdi, [rip + bad]
    call log_cstr
    mov eax, 1
    EPILOGUE

# rand() -> eax, 32 random bits
rand:
    mov rax, [rip + seed]
    movabs rcx, 6364136223846793005
    imul rax, rcx
    movabs rcx, 1442695040888963407
    add rax, rcx
    mov [rip + seed], rax
    shr rax, 32
    ret

.section .rodata
ok: .asciz "ok\n"
bad: .asciz "a translucent fill differs from color_mix\n"
