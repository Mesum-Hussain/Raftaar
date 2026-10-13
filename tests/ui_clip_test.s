# Mouse hits must agree with the visible canvas clip, including nested clips.
.include "raftaar.inc"
.bss
pixels: .zero 40000
clip_offset: .zero 4
.text
FN main
    PROLOGUE
    lea rdi, [rip + pixels]
    mov esi, 100
    mov edx, 100
    mov ecx, 100
    call gfx_set_target
    mov edi, 20
    mov esi, 20
    mov edx, 20
    mov ecx, 20
    call gfx_clip_push
    mov dword ptr [rip + g_mx], 10
    mov dword ptr [rip + g_my], 30
    call hit
    test eax, eax
    jnz fail
    mov dword ptr [rip + g_mx], 30
    call hit
    test eax, eax
    jz fail
    mov edi, 30
    mov esi, 30
    mov edx, 10
    mov ecx, 10
    call gfx_clip_push
    mov dword ptr [rip + g_my], 25
    call hit
    test eax, eax
    jnz fail
    call gfx_clip_pop
    call hit
    test eax, eax
    jz fail
    mov dword ptr [rip + g_block], 1
    call hit
    test eax, eax
    jnz fail
    mov dword ptr [rip + g_block], 0
    call gfx_clip_pop
    mov dword ptr [rip + g_mx], 10
    call hit
    test eax, eax
    jz fail
    # A previously grabbed scrollbar must stay still while input is blocked.
    mov dword ptr [rip + clip_offset], 300
    mov dword ptr [rip + g_block], 1
    mov dword ptr [rip + g_active], 900
    mov dword ptr [rip + g_mdown], 1
    mov dword ptr [rip + g_my], 70
    mov eax, 100
    push rax
    mov eax, 1000
    push rax
    mov edi, 900
    mov esi, 20
    xor edx, edx
    mov ecx, 20
    mov r8d, 100
    lea r9, [rip + clip_offset]
    call ui_scrollbar
    add rsp, 16
    cmp dword ptr [rip + clip_offset], 300
    jne fail
    lea rdi, [rip + ok]
    call log_cstr
    xor eax, eax
    EPILOGUE
fail:
    mov eax, 1
    EPILOGUE
hit:
    xor edi, edi
    xor esi, esi
    mov edx, 100
    mov ecx, 100
    jmp ui_in
.section .rodata
ok: .asciz "ok\n"
