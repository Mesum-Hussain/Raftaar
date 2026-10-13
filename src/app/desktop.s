# Links and file locations in the desktop's default applications.
.include "raftaar.inc"

.text
FN cmd_website
    lea rdi, [rip + .Lwebsite]
    jmp desktop_open

FN cmd_feedback
    lea rdi, [rip + .Lfeedback]
    jmp desktop_open

FN cmd_discord
    lea rdi, [rip + .Ldiscord]
    jmp desktop_open

FN cmd_email
    lea rdi, [rip + .Lemail]
    jmp desktop_open

.ifdef WINDOWS
FN desktop_open
    jmp win_open_link
FN desktop_reveal
    jmp win_reveal
.else
# Pass each argument separately, so paths and URLs never become shell code.
FN desktop_open
    xor esi, esi
    jmp desktop_launch

FN desktop_reveal
    mov esi, 1

desktop_launch:
    PROLOGUE 48
    mov rbx, rdi
    mov r12d, esi
    xor r13d, r13d
    lea rdi, [rip + .Lopener]
    call proc_which
    test rax, rax
    jz 8f
    mov r14, rax
    mov [rsp], rax
    mov [rsp + 8], rbx
    mov qword ptr [rsp + 16], 0
    test r12d, r12d
    jz 2f
.ifdef MACOS
    lea rax, [rip + .Lreveal]
    mov [rsp + 8], rax
    mov [rsp + 16], rbx
    mov qword ptr [rsp + 24], 0
.else
    # xdg-open works with GNOME, KDE, Xfce and other desktop file managers.
    # Open the containing folder without opening the selected file itself.
    mov rdi, rbx
    call strlen
    mov rdi, rbx
    mov rsi, rax
    call path_dirlen
    test rax, rax
    jnz 1f
    mov eax, 1                 # the parent of /name is /
1:
    mov rdi, rbx
    mov rsi, rax
    call mem_dup
    mov r13, rax
    mov [rsp + 8], rax
.endif
2:  mov rdi, rsp
    mov rsi, [rip + g_envp]
    xor edx, edx
    call run_piped
    mov r12, rax
    mov ebx, edx
    mov rdi, r14
    call mem_free
    mov rdi, r13
    call mem_free
    test r12, r12
    jle 8f
    mov edi, ebx
    mov esi, POLLIN
    lea rdx, [rip + desktop_done]
    mov rcx, r12
    call watch_add
    EPILOGUE
8:  call desktop_failed
    EPILOGUE

# Drain the launcher's output and reap it when done, without pausing the editor.
desktop_done:
    PROLOGUE 1024
    mov ebx, edi
    mov r12, rdx
1:  mov edi, ebx
    mov rsi, rsp
    mov edx, 1024
    SYS SYS_read
    cmp rax, -EINTR
    je 1b
    cmp rax, -EAGAIN
    je 9f
    test rax, rax
    jg 1b
    mov edi, ebx
    call watch_remove
    mov edi, ebx
    SYS SYS_close
    mov rdi, r12
    xor esi, esi
    call proc_wait
    test eax, eax
    jz 9f
    call desktop_failed
9:  EPILOGUE
.endif

FN desktop_failed
    lea rdi, [rip + .Lfailed]
    jmp app_toast

.section .rodata
.Lwebsite: .asciz "https://rhun.app"
.Lfeedback: .asciz "https://github.com/vshvedov/rhun/issues"
.Ldiscord: .asciz "https://discord.gg/Aj4drpFbWf"
.Lemail: .asciz "mailto:hi@rhun.app?subject=rhun%20feedback"
.Lfailed: .asciz "Could not open the desktop application"
.ifdef MACOS
.Lopener: .asciz "open"
.Lreveal: .asciz "-R"
.else
.Lopener: .asciz "xdg-open"
.endif
