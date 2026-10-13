# framebuffer dump as binary PPM
.include "raftaar.inc"

.text
# shot_write(path) -> 0 or -errno
FN shot_write
    PROLOGUE 64
    mov r12, rdi
    lea rdi, [rsp]
    xor esi, esi
    mov edx, SB_SIZE
    call memset
    lea rdi, [rsp]
    lea rsi, [rip + .Lp6]
    call sb_push_cstr
    lea rdi, [rsp]
    mov esi, [rip + g_cv + CV_w]
    call sb_push_u64
    lea rdi, [rsp]
    mov esi, ' '
    call sb_push_byte
    lea rdi, [rsp]
    mov esi, [rip + g_cv + CV_h]
    call sb_push_u64
    lea rdi, [rsp]
    lea rsi, [rip + .Lmax]
    call sb_push_cstr
    mov eax, [rip + g_cv + CV_w]
    imul eax, [rip + g_cv + CV_h]
    lea esi, [rax + rax*2]
    lea rdi, [rsp]
    call sb_reserve
    mov rdi, rax
    xor ebx, ebx                # y
.Lsw_row:
    cmp ebx, [rip + g_cv + CV_h]
    jae .Lsw_done
    mov eax, ebx
    imul eax, [rip + g_cv + CV_stride]
    mov rsi, [rip + g_cv + CV_pixels]
    lea rsi, [rsi + rax*4]
    xor ecx, ecx
1:  cmp ecx, [rip + g_cv + CV_w]
    jae 2f
    mov eax, [rsi + rcx*4]
    mov edx, eax
    shr edx, 16
    mov [rdi], dl
    mov [rdi + 1], ah
    mov [rdi + 2], al
    add rdi, 3
    inc ecx
    jmp 1b
2:  inc ebx
    jmp .Lsw_row
.Lsw_done:
    mov eax, [rip + g_cv + CV_w]
    imul eax, [rip + g_cv + CV_h]
    lea eax, [rax + rax*2]
    add [rsp + SB_len], rax
    mov rdi, r12
    mov rsi, [rsp + SB_ptr]
    mov rdx, [rsp + SB_len]
    call file_write_all
    mov rbx, rax
    lea rdi, [rsp]
    call sb_free
    mov rax, rbx
    EPILOGUE

.section .rodata
.Lp6: .asciz "P6\n"
.Lmax: .asciz "\n255\n"
