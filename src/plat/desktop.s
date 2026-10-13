# the desktop entry and icons of a Linux installation, carried in the program:
#   raftaar --install-desktop [PREFIX]   puts them under PREFIX/share (~/.local without a PREFIX)
.include "raftaar.inc"

.bss
.p2align 3
dk_sb: .zero SB_SIZE
dk_exe: .zero 4096

.text
# desktop_install(prefix cstr or 0): writes the entry, which starts this program by its path
# (graphical sessions often lack ~/.local/bin in PATH), and the icons; exits
FN desktop_install
    PROLOGUE
    mov r12, rdi
    test r12, r12
    jnz 1f
    lea rdi, [rip + .Lenv_home]
    call getenv
    lea rdi, [rip + .Le_home]
    test rax, rax
    jz .Ldk_die
    mov rdi, rax
    lea rsi, [rip + .Llocal]
    call path_join
    mov r12, rax
1:  lea rdi, [rip + .Lself_exe]
    lea rsi, [rip + dk_exe]
    mov edx, 4095
    SYS SYS_readlink
    lea rdi, [rip + .Le_self]
    test rax, rax
    jle .Ldk_die
    lea rcx, [rip + dk_exe]
    mov byte ptr [rcx + rax], 0
    # the entry, with this program in place of the name in its Exec line
    lea r13, [rip + dk_entry]
    lea r14, [rip + dk_entry_end]
    sub r14, r13
    mov rdi, r13
    mov rsi, r14
    lea rdx, [rip + .Lexec]
    mov ecx, 13
    call str_find
    lea rdi, [rip + .Le_entry]
    test rax, rax
    js .Ldk_die
    lea r15, [rax + 6]          # through "Exec="
    lea rdi, [rip + dk_sb]
    mov rsi, r13
    mov rdx, r15
    call sb_push
    call dk_push_exe
    lea rdi, [rip + dk_sb]
    lea rsi, [r13 + r15 + 7]    # after "raftaar"
    lea rdx, [r14 - 7]
    sub rdx, r15
    call sb_push
    lea rsi, [rip + .Lp_entry]
    mov rdx, [rip + dk_sb + SB_ptr]
    mov rcx, [rip + dk_sb + SB_len]
    call dk_write
    lea rbx, [rip + dk_icons]
2:  mov rsi, [rbx]
    test rsi, rsi
    jz 3f
    mov rdx, [rbx + 8]
    mov rcx, [rbx + 16]
    sub rcx, rdx
    call dk_write
    add rbx, 24
    jmp 2b
3:  xor edi, edi
    call sys_exit
.Ldk_die:
    call die

# dk_write(-, name, ptr, len): the file name under the prefix (r12), its folders made first
dk_write:
    push r13
    push r14
    push r15
    mov r13, rdx
    mov r14, rcx
    mov rdi, r12
    call path_join
    mov r15, rax
    mov rdi, rax
    call mkdir_parent
    mov rdi, r15
    mov rsi, r13
    mov rdx, r14
    call file_write_all
    test rax, rax
    jnz 1f
    mov rdi, r15
    call mem_free
    pop r15
    pop r14
    pop r13
    ret
1:  lea rdi, [rip + .Le_write]
    call log_cstr
    mov rdi, r15
    jmp .Ldk_die

# dk_push_exe(): this program's path as the Exec argument: as it is, or in double quotes when a
# byte of it means something there. In quotes " ` $ and \ take a backslash, which is doubled as in
# every string of a desktop entry, and % is doubled as everywhere in Exec.
dk_push_exe:
    push rbx
    push r12
    push r13
    lea rbx, [rip + dk_sb]
    lea r12, [rip + dk_exe]
    mov rsi, r12
1:  movzx eax, byte ptr [rsi]
    inc rsi
    test al, al
    jz 9f
    cmp al, 0x80
    jae 1b
    lea ecx, [rax - '0']
    cmp cl, 10
    jb 1b
    mov ecx, eax
    or cl, 0x20
    sub cl, 'a'
    cmp cl, 26
    jb 1b
    lea rdi, [rip + .Lplain]
2:  mov cl, [rdi]
    inc rdi
    cmp cl, al
    je 1b
    test cl, cl
    jnz 2b
    mov rdi, rbx
    mov esi, '"'
    call sb_push_byte
4:  movzx r13d, byte ptr [r12]
    inc r12
    test r13d, r13d
    jz 8f
    cmp r13d, '%'
    je 6f
    cmp r13d, '\\'
    je 5f
    cmp r13d, '"'
    je 5f
    cmp r13d, '`'
    je 5f
    cmp r13d, '$'
    jne 7f
5:  mov rdi, rbx
    lea rsi, [rip + .Lbackslashes]
    mov edx, 2
    call sb_push
    cmp r13d, '\\'
    jne 7f
6:  mov rdi, rbx
    mov esi, r13d
    call sb_push_byte
7:  mov rdi, rbx
    mov esi, r13d
    call sb_push_byte
    jmp 4b
8:  mov rdi, rbx
    mov esi, '"'
    call sb_push_byte
    jmp 3f
9:  mov rdi, rbx
    mov rsi, r12
    call sb_push_cstr
3:  pop r13
    pop r12
    pop rbx
    ret

.section .rodata
.Lenv_home: .asciz "HOME"
.Llocal: .asciz ".local"
.Lself_exe: .asciz "/proc/self/exe"
.Lexec: .ascii "\nExec=raftaar"
.Lplain: .asciz "/._+-@:,"
.Lbackslashes: .ascii "\\\\"
.Lp_entry: .asciz "share/applications/raftaar.desktop"
.Lp_svg: .asciz "share/icons/hicolor/scalable/apps/raftaar.svg"
.Lp_256: .asciz "share/icons/hicolor/256x256/apps/raftaar.png"
.Lp_512: .asciz "share/icons/hicolor/512x512/apps/raftaar.png"
.Le_home: .asciz "raftaar: HOME is not set; name the folder to install under"
.Le_self: .asciz "raftaar: the running program was not found"
.Le_entry: .asciz "raftaar: the desktop entry has no Exec line"
.Le_write: .asciz "raftaar: could not write "
.p2align 3
dk_icons:
    .quad .Lp_svg, dk_svg, dk_svg_end
    .quad .Lp_256, dk_256, dk_256_end
    .quad .Lp_512, dk_512, dk_512_end
    .quad 0
dk_entry: .incbin "assets/raftaar.desktop"
dk_entry_end:
dk_svg: .incbin "assets/icons/raftaar.svg"
dk_svg_end:
dk_256: .incbin "assets/icons/raftaar-256.png"
dk_256_end:
dk_512: .incbin "assets/icons/raftaar-512.png"
dk_512_end:
