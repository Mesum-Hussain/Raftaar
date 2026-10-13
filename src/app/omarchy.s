# Omarchy: "Follow Omarchy" in the theme list uses the theme Omarchy has set.
# Omarchy writes its name to theme.name in ~/.local/state/omarchy/current
# (~/.config/omarchy/current before Omarchy 4), after the theme itself is in place.
.include "raftaar.inc"

.bss
dir_buf: .zero 512              # the directory holding theme.name, or empty

.data
.p2align 3
.globl g_follow, g_follow_target
g_follow: .quad -1              # registry index of "Follow Omarchy", -1 without Omarchy
g_follow_target: .quad -1       # the theme it resolved to last

.text

# omarchy_register(): add "Follow Omarchy" to the theme registry when Omarchy is installed
FN omarchy_register
    PROLOGUE
    lea rdi, [rip + .Lhome]
    call getenv
    test rax, rax
    jz 9f
    mov rbx, rax
    xor r13d, r13d
1:  lea rax, [rip + dirs]
    mov r12, [rax + r13*8]
    test r12, r12
    jz 9f
    lea rdi, [rip + dir_buf]
    mov rsi, rbx
    call cstr_copy
    mov rdi, rax
    mov rsi, r12
    call cstr_copy
    lea rdi, [rip + dir_buf]
    lea rsi, [rip + .Lname_file]
    call path_join_tmp
    mov rdi, rax
    xor esi, esi                # F_OK
    SYS SYS_access
    test rax, rax
    jz 2f
    inc r13d
    jmp 1b
2:  lea rdi, [rip + g_themes]
    mov esi, TH_SIZE
    call vec_push
    lea rcx, [rip + omarchy_id]
    mov [rax + TH_id], rcx
    lea rcx, [rip + .Lfollow]
    mov [rax + TH_name], rcx
    mov dword ptr [rax + TH_dark], 1
    mov qword ptr [rax + TH_src], 0
    mov qword ptr [rax + TH_len], 0
    mov qword ptr [rax + TH_path], 0
    mov rax, [rip + g_themes + VEC_len]
    dec rax
    mov [rip + g_follow], rax
    EPILOGUE
9:  mov byte ptr [rip + dir_buf], 0
    EPILOGUE

# omarchy_dir() -> the directory to watch, or 0
FN omarchy_dir
    lea rax, [rip + dir_buf]
    cmp byte ptr [rax], 0
    jne 1f
    xor eax, eax
1:  ret

# omarchy_target() -> registry index of the theme matching Omarchy's current one
FN omarchy_target
    PROLOGUE
    lea rdi, [rip + dir_buf]
    lea rsi, [rip + .Lname_file]
    call path_join_tmp
    mov rdi, rax
    call file_read_all
    test rax, rax
    jz .Lot_other
    mov rbx, rax
1:  test rdx, rdx
    jz 2f
    cmp byte ptr [rbx + rdx - 1], ' '
    ja 2f
    dec rdx
    jmp 1b
2:  mov byte ptr [rbx + rdx], 0
    # the few names that differ in raftaar
    mov r12, rbx
    lea r13, [rip + aliases]
3:  mov rdi, [r13]
    test rdi, rdi
    jz 4f
    mov rsi, rbx
    call strcmp_eq
    test eax, eax
    jnz 31f
    add r13, 16
    jmp 3b
31: mov r12, [r13 + 8]
4:  mov rdi, r12
    call theme_find
    mov r12, rax
    mov rdi, rbx
    call mem_free
    test r12, r12
    js .Lot_other
    cmp r12, [rip + g_follow]
    je .Lot_other
    mov rax, r12
    EPILOGUE
.Lot_other:
    # a theme raftaar has no match for: raftaar's own, light or dark like it
    call omarchy_light
    lea rdi, [rip + .Ldark_id]
    lea rcx, [rip + .Llight_id]
    test eax, eax
    cmovnz rdi, rcx
    call theme_find
    EPILOGUE

# omarchy_light() -> 1 if Omarchy's current theme is a light one
omarchy_light:
    PROLOGUE INI_SIZE
    xor r12d, r12d
    lea rdi, [rip + dir_buf]
    lea rsi, [rip + .Lcolors]
    call path_join_tmp
    mov rdi, rax
    call file_read_all
    test rax, rax
    jz 8f
    mov rbx, rax
    lea rdi, [rsp]
    mov rsi, rax
    call ini_init
1:  lea rdi, [rsp]
    call ini_next
    test eax, eax
    jz 7f
    lea rdi, [rsp]
    lea rsi, [rip + .Lmode]
    call ini_key_is
    test eax, eax
    jz 1b
    mov rdi, [rsp + INI_val]
    mov rsi, [rsp + INI_vallen]
    lea rdx, [rip + .Llight]
    mov ecx, 5
    call str_find
    test rax, rax
    js 7f
    mov r12d, 1
7:  mov rdi, rbx
    call mem_free
8:  test r12d, r12d
    jnz 9f
    # themes older than colors.toml mark light ones with light.mode
    lea rdi, [rip + dir_buf]
    lea rsi, [rip + .Llight_mode]
    call path_join_tmp
    mov rdi, rax
    xor esi, esi
    SYS SYS_access
    test rax, rax
    sete r12b
9:  mov eax, r12d
    EPILOGUE

# omarchy_changed(): Omarchy rewrote theme.name
FN omarchy_changed
    mov rdi, [rip + g_follow]
    test rdi, rdi
    js 1f
    cmp rdi, [rip + g_theme_cur]
    jne 1f
    jmp theme_apply
1:  ret

.section .rodata
.globl omarchy_id
omarchy_id: .asciz "omarchy"
.Lfollow: .asciz "Follow Omarchy"
.Lhome: .asciz "HOME"
.Lstate: .asciz "/.local/state/omarchy/current"
.Lconfig: .asciz "/.config/omarchy/current"
.Lname_file: .asciz "theme.name"
.Lcolors: .asciz "theme/colors.toml"
.Llight_mode: .asciz "theme/light.mode"
.Lmode: .asciz "mode"
.Llight: .asciz "light"
.Llight_id: .asciz "raftaar-light"
.Ldark_id: .asciz "raftaar-dark"
.La_catppuccin: .asciz "catppuccin"
.Lr_catppuccin: .asciz "catppuccin-mocha"
.La_gruvbox: .asciz "gruvbox"
.Lr_gruvbox: .asciz "gruvbox-dark"
.La_rose_pine: .asciz "rose-pine"
.Lr_rose_pine: .asciz "rose-pine-dawn"
.p2align 3
dirs: .quad .Lstate, .Lconfig, 0
# Omarchy name -> raftaar theme, where they differ
aliases:
    .quad .La_catppuccin, .Lr_catppuccin
    .quad .La_gruvbox, .Lr_gruvbox
    .quad .La_rose_pine, .Lr_rose_pine
    .quad 0
