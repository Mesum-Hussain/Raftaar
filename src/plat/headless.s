# headless platform: offscreen framebuffer, used by tests and scripted runs
.include "raftaar.inc"

.bss
.p2align 3
hbuf: .quad 0
hw: .long 0
hh: .long 0
.p2align 3
hclip: .zero SB_SIZE
# window requests, recorded for tests; a move grabs the pointer like a compositor does
.globl g_hl_grab, g_hl_moves, g_hl_minimized, g_hl_frames
g_hl_grab: .long 0
g_hl_moves: .long 0
g_hl_minimized: .long 0
g_hl_frames: .long 0            # frames drawn, for tests

.text

FN headless_init
    PROLOGUE
    mov r12d, edi
    mov r13d, esi
    lea rax, [rip + hl_nop]
    lea rdi, [rip + g_plat]
    mov ecx, PLAT_SIZE / 8
1:  mov [rdi], rax
    add rdi, 8
    dec ecx
    jnz 1b
    lea rax, [rip + hl_timeout]
    mov [rip + g_plat + P_timeout], rax
    lea rax, [rip + hl_draw]
    mov [rip + g_plat + P_draw], rax
    lea rax, [rip + hl_clip_set]
    mov [rip + g_plat + P_clip_set], rax
    lea rax, [rip + hl_clip_get]
    mov [rip + g_plat + P_clip_get], rax
    lea rax, [rip + hl_move]
    mov [rip + g_plat + P_move], rax
    lea rax, [rip + hl_minimize]
    mov [rip + g_plat + P_minimize], rax
    lea rax, [rip + hl_maximize]
    mov [rip + g_plat + P_maximize], rax
    mov dword ptr [rip + g_headless], 1
    mov dword ptr [rip + g_csd], 1
    mov edi, r12d
    mov esi, r13d
    call headless_resize
    EPILOGUE

FN headless_resize
    push rbx
    push r12
    push r13
    mov r12d, edi
    mov r13d, esi
    mov [rip + hw], edi
    mov [rip + hh], esi
    mov rdi, [rip + hbuf]
    call mem_free
    mov eax, r12d
    imul eax, r13d
    lea rdi, [rax*4]
    call mem_alloc
    mov [rip + hbuf], rax
    mov edi, r12d
    mov esi, r13d
    call app_on_resize
    mov dword ptr [rip + g_dirty], 1
    pop r13
    pop r12
    pop rbx
    ret

hl_nop:
    ret

hl_move:
    inc dword ptr [rip + g_hl_moves]
    mov dword ptr [rip + g_hl_grab], 1
    ret

hl_minimize:
    inc dword ptr [rip + g_hl_minimized]
    ret

hl_maximize:
    xor dword ptr [rip + g_win_states], 1
    mov dword ptr [rip + g_dirty], 1
    ret

# hl_timeout(): at once when the last frame asked for another, otherwise forever
hl_timeout:
    xor eax, eax
    cmp dword ptr [rip + g_dirty], 0
    jne 1f
    mov eax, -1
1:  ret

hl_draw:
    push rbx
    mov rdi, [rip + hbuf]
    mov esi, [rip + hw]
    mov edx, [rip + hh]
    mov ecx, esi
    call gfx_set_target
    mov dword ptr [rip + g_dirty], 0
    inc dword ptr [rip + g_hl_frames]
    call app_render
    pop rbx
    ret

hl_clip_set:
    push rbx
    push r12
    push r13
    mov r12, rdi
    mov r13, rsi
    lea rdi, [rip + hclip]
    call sb_clear
    lea rdi, [rip + hclip]
    mov rsi, r12
    mov rdx, r13
    call sb_push
    pop r13
    pop r12
    pop rbx
    ret

hl_clip_get:
    mov rdi, [rip + hclip + SB_ptr]
    mov rsi, [rip + hclip + SB_len]
    test rdi, rdi
    jz 1f
    jmp app_on_paste
1:  ret
