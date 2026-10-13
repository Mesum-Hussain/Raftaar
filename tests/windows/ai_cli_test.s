# Subscription CLI fixture for Windows PowerShell/native UI integration. No network.
.include "raftaar.inc"
.bss
input: .zero 32768
.text
FN main
    PROLOGUE
    lea rdi, [rip + input]
    mov esi, 32768
    SYS SYS_getcwd
    test rax, rax
    js .Lfail
    lea rdi, [rip + input]
    call strlen
    lea rdi, [rip + input]
    mov rsi, rax
    lea rdx, [rip + .Ltemp_marker]
    mov ecx, 8
    call str_find
    test rax, rax
    js .Lfail
    lea rdi, [rip + .Lapi]
    call getenv
    test rax, rax
    jnz .Lfail
    mov rax, [rip + g_argv]
    cmp qword ptr [rip + g_argc], 2
    jb .Lfail
    mov rbx, [rax + 8]
    mov rdi, rbx
    lea rsi, [rip + .Lauth]
    call strcmp_eq
    test eax, eax
    jnz .Lauth_reply
    mov rdi, rbx
    lea rsi, [rip + .Llogin]
    call strcmp_eq
    test eax, eax
    jnz .Llogin_reply
    mov rdi, rbx
    lea rsi, [rip + .Lprint]
    call strcmp_eq
    test eax, eax
    jz .Lread
    # Claude must receive the empty --tools argument and intact JSON quotes.
    mov rax, [rip + g_argv]
    cmp qword ptr [rip + g_argc], 14
    jb .Lfail
    mov rcx, [rax + 5*8]
    cmp byte ptr [rcx], 0
    jne .Lfail
    mov rdi, [rax + 10*8]
    lea rsi, [rip + .Ljson]
    call strcmp_eq
    test eax, eax
    jz .Lfail
.Lread:
    xor ebx, ebx
1:  xor edi, edi
    lea rsi, [rip + input]
    mov edx, 32768
    SYS SYS_read
    test rax, rax
    js .Lfail
    jz 2f
    add rbx, rax
    jmp 1b
2:  test rbx, rbx
    jz .Lfail
    lea rdi, [rip + .Ldelay]
    call getenv
    test rax, rax
    jz 3f
    xor edi, edi
    xor esi, esi
    mov edx, 3000
    SYS SYS_poll
3:  lea rsi, [rip + .Lmessage]
    mov edx, .Lmessage_end - .Lmessage
    jmp .Lreply
.Lauth_reply:
    lea rsi, [rip + .Lauth_ok]
    mov edx, .Lauth_ok_end - .Lauth_ok
    jmp .Lreply
.Llogin_reply:
    lea rsi, [rip + .Llogin_ok]
    mov edx, .Llogin_ok_end - .Llogin_ok
.Lreply:
    mov edi, 1
    SYS SYS_write
    xor eax, eax
    EPILOGUE
.Lfail:
    mov eax, 1
    EPILOGUE
.section .rodata
.Ltemp_marker: .ascii "raftaar-ai-"
.Lapi: .asciz "OPENAI_API_KEY"
.Ldelay: .asciz "RAFTAAR_AI_TEST_DELAY"
.Lauth: .asciz "auth"
.Llogin: .asciz "login"
.Lprint: .asciz "-p"
.Ljson: .asciz "{\"mcpServers\":{}}"
.Lauth_ok: .ascii "{\"authMethod\":\"claude.ai\"}\n"
.Lauth_ok_end:
.Llogin_ok: .ascii "Logged in using ChatGPT\n"
.Llogin_ok_end:
.Lmessage: .ascii "Describe Windows changes\n"
.Lmessage_end:
