# decodes the images named on the command line, one line each: "name format WxH opaque hash" or "name -"
#   image_test [--dump FILE] images...   --dump writes the pixels of the last image (premultiplied ARGB)
.include "raftaar.inc"
.bss
.p2align 3
out: .zero SB_SIZE
im: .zero IMG_SIZE
dump: .quad 0
.text
FN main
    PROLOGUE
    mov r12, [rip + g_argv]
    mov r13, [rip + g_argc]
    mov ebx, 1
1:  cmp rbx, r13
    jae 9f
    mov r14, [r12 + rbx*8]
    inc rbx
    lea rdi, [rip + .Ldump]
    mov rsi, r14
    call strcmp_eq
    test eax, eax
    jz 2f
    mov rax, [r12 + rbx*8]
    mov [rip + dump], rax
    inc rbx
    jmp 1b
2:  mov rdi, r14
    call strlen
    mov rdi, r14
    mov rsi, rax
    call path_basename
    lea rdi, [rip + out]
    mov rsi, rax
    call sb_push
    lea rdi, [rip + out]
    mov esi, ' '
    call sb_push_byte
    mov rdi, r14
    call image_probe
    mov r15d, eax
    test eax, eax
    jz 8f
    mov rdi, r14
    call file_read_all
    test rax, rax
    jz 8f
    push rax
    push rax
    mov rdi, rax
    mov rsi, rdx
    mov edx, r15d
    lea rcx, [rip + im]
    call image_decode
    pop rdi
    pop rdi
    push rax
    push rax
    call mem_free
    pop rax
    pop rax
    test eax, eax
    jnz 8f
    mov edi, r15d
    call image_format_name
    lea rdi, [rip + out]
    mov rsi, rax
    call sb_push_cstr
    lea rdi, [rip + out]
    mov esi, ' '
    call sb_push_byte
    lea rdi, [rip + out]
    mov esi, [rip + im + IMG_w]
    call sb_push_u64
    lea rdi, [rip + out]
    mov esi, 'x'
    call sb_push_byte
    lea rdi, [rip + out]
    mov esi, [rip + im + IMG_h]
    call sb_push_u64
    lea rdi, [rip + out]
    lea rsi, [rip + .Lopaque]
    call sb_push_cstr
    lea rdi, [rip + out]
    mov esi, [rip + im + IMG_opaque]
    call sb_push_u64
    lea rdi, [rip + out]
    mov esi, ' '
    call sb_push_byte
    # FNV-1a over the pixel bytes
    mov rsi, [rip + im + IMG_px]
    mov eax, [rip + im + IMG_w]
    mov ecx, [rip + im + IMG_h]
    imul rcx, rax
    shl rcx, 2
    mov eax, 0x811c9dc5
3:  test rcx, rcx
    jz 4f
    movzx edx, byte ptr [rsi]
    xor eax, edx
    imul eax, eax, 0x01000193
    inc rsi
    dec rcx
    jmp 3b
4:  mov edi, eax
    call push_hex
    cmp qword ptr [rip + dump], 0
    je 5f
    mov eax, [rip + im + IMG_w]
    mov edx, [rip + im + IMG_h]
    imul rdx, rax
    shl rdx, 2
    mov rdi, [rip + dump]
    mov rsi, [rip + im + IMG_px]
    call file_write_all
5:  lea rdi, [rip + im]
    call image_free
    jmp 7f
8:  lea rdi, [rip + out]
    mov esi, '-'
    call sb_push_byte
7:  lea rdi, [rip + out]
    mov esi, 10
    call sb_push_byte
    jmp 1b
9:  mov rdi, [rip + out + SB_ptr]
    mov rsi, [rip + out + SB_len]
    call log_write
    xor eax, eax
    EPILOGUE

push_hex:
    push rbx
    mov ebx, edi
    mov ecx, 28
1:  mov eax, ebx
    shr eax, cl
    and eax, 15
    lea rdx, [rip + .Lhex]
    movzx esi, byte ptr [rdx + rax]
    push rcx
    lea rdi, [rip + out]
    call sb_push_byte
    pop rcx
    sub ecx, 4
    jns 1b
    pop rbx
    ret

.section .rodata
.Ldump: .asciz "--dump"
.Lopaque: .asciz " opaque="
.Lhex: .ascii "0123456789abcdef"
