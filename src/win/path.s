.include "win.inc"
.text
# win_file_path(UTF-8 path) -> allocated UTF-16 filesystem path, or 0.
# Preserve ordinary short paths and explicit device namespaces. Resolve ordinary
# long paths before adding the extended prefix, which does not interpret dot components.
FN win_file_path
    PROLOGUE 8320
    call win_wide
    mov rbx, rax
    test rax, rax
    jz .Lfp_fail
    xor r12d, r12d
.Lfp_len:
    cmp word ptr [rbx + r12*2], 0
    je .Lfp_kind
    inc r12d
    jmp .Lfp_len
.Lfp_kind:
    cmp r12d, 4
    jb .Lfp_resolve
    movzx eax, word ptr [rbx]
    cmp eax, '/'
    je 1f
    cmp eax, 92
    jne .Lfp_drive
1:  movzx eax, word ptr [rbx + 2]
    cmp eax, '/'
    je 2f
    cmp eax, 92
    jne .Lfp_resolve
2:  movzx eax, word ptr [rbx + 4]
    cmp eax, '?'
    je 3f
    cmp eax, '.'
    jne .Lfp_absolute
3:  movzx eax, word ptr [rbx + 6]
    cmp eax, '/'
    je .Lfp_namespace
    cmp eax, 92
    je .Lfp_namespace
    jmp .Lfp_absolute
.Lfp_drive:
    cmp word ptr [rbx + 2], ':'
    jne .Lfp_resolve
    movzx eax, word ptr [rbx + 4]
    cmp eax, '/'
    je .Lfp_absolute
    cmp eax, 92
    jne .Lfp_resolve
.Lfp_absolute:
    # CreateDirectory also needs room below MAX_PATH for a short-name suffix.
    cmp r12d, 248
    jb .Lfp_original
.Lfp_resolve:
    mov rcx, rbx
    mov edx, 4096
    lea r8, [rsp + 96]
    xor r9d, r9d
    API GetFullPathNameW
    test eax, eax
    jz .Lfp_release
    cmp eax, 4096
    jae .Lfp_release
    cmp eax, 248
    jb .Lfp_original
    mov r12d, eax
    mov r14d, 4               # drive prefix adds four wide characters
    lea r15, [rsp + 96]
    cmp word ptr [r15], 92
    jne .Lfp_allocate
    cmp word ptr [r15 + 2], 92
    jne .Lfp_release
    # A relative path can resolve inside an already extended current directory.
    cmp word ptr [r15 + 6], 92
    jne 7f
    cmp word ptr [r15 + 4], '?'
    je .Lfp_resolved_namespace
    cmp word ptr [r15 + 4], '.'
    je .Lfp_resolved_namespace
7:  mov r14d, 6               # UNC replaces two slashes with \\?\UNC\
    add r15, 4
.Lfp_allocate:
    lea edi, [r12 + r14 + 1]
    add edi, edi
    call mem_alloc
    mov r13, rax
    mov rax, 0x005c003f005c005c  # \\?\
    mov [r13], rax
    lea rdi, [r13 + 8]
    cmp r14d, 6
    jne 4f
    mov rax, 0x005c0043004e0055  # UNC\
    mov [rdi], rax
    add rdi, 8
    sub r12d, 2
4:  mov rsi, r15
    lea edx, [r12*2 + 2]
    call memcpy
    mov rdi, rbx
    call mem_free
    mov rax, r13
    EPILOGUE
.Lfp_resolved_namespace:
    lea edi, [r12*2 + 2]
    call mem_alloc
    mov r13, rax
    mov rdi, rax
    mov rsi, r15
    lea edx, [r12*2 + 2]
    call memcpy
    mov rdi, rbx
    call mem_free
    mov rax, r13
    EPILOGUE
.Lfp_namespace:
    # Core paths can use '/', including paths already carrying a namespace.
    xor ecx, ecx
5:  movzx eax, word ptr [rbx + rcx*2]
    test eax, eax
    jz .Lfp_original
    cmp eax, '/'
    jne 6f
    mov word ptr [rbx + rcx*2], 92
6:  inc rcx
    jmp 5b
.Lfp_original:
    mov rax, rbx
    EPILOGUE
.Lfp_release:
    mov rdi, rbx
    call mem_free
.Lfp_fail:
    xor eax, eax
    EPILOGUE

# Read a system font without assuming which drive holds Windows.
FN win_read_font
    PROLOGUE 8320
    mov r12, rdi
    lea rcx, [rsp + 96]
    mov edx, 4096
    API GetWindowsDirectoryW
    test eax, eax
    jz 8f
    cmp eax, 4096
    jae 8f
    lea rdi, [rsp + 96]
    call win_utf8
    test rax, rax
    jz 8f
    mov rbx, rax
    mov rdi, rax
    mov rsi, r12
    call path_join_tmp
    mov r12, rax
    mov rdi, rbx
    call mem_free
    mov rdi, r12
    call file_read_all
    EPILOGUE
8:  xor eax, eax
    xor edx, edx
    EPILOGUE

# Session metadata can spell the same path with different separators or drive case.
FN win_path_equal
    PROLOGUE 96
    mov r12, rsi
    call win_fullpath
    mov rbx, rax
    test rax, rax
    jz 8f
    mov rdi, rax
    call win_wide
    mov r13, rax
    mov rdi, rbx
    call mem_free
    mov rdi, r12
    call win_fullpath
    mov rbx, rax
    test rax, rax
    jz 7f
    mov rdi, rax
    call win_wide
    mov r12, rax
    mov rdi, rbx
    call mem_free
    xor ebx, ebx
    test r13, r13
    jz 6f
    test r12, r12
    jz 6f
    mov rcx, r13
    mov edx, -1
    mov r8, r12
    mov r9d, -1
    mov qword ptr [rsp + 32], 1
    API CompareStringOrdinal
    cmp eax, 2
    sete bl
6:  mov rdi, r12
    call mem_free
    mov rdi, r13
    call mem_free
    mov eax, ebx
    EPILOGUE
7:  mov rdi, r13
    call mem_free
8:  xor eax, eax
    EPILOGUE

# Full Unicode path at an ingress boundary, returned in a new allocation.
FN win_fullpath
    PROLOGUE 8320
    call win_wide
    mov rbx, rax
    test rax, rax
    jz 8f
    mov rcx, rax
    mov edx, 4096
    lea r8, [rsp + 96]
    xor r9d, r9d
    API GetFullPathNameW
    mov r12d, eax
    mov rdi, rbx
    call mem_free
    test r12d, r12d
    jz 8f
    cmp r12d, 4096
    jae 8f
    lea rdi, [rsp + 96]
    call win_utf8
    mov rbx, rax
    test rax, rax
    jz 8f
    mov rdi, rax
    call strlen
    cmp rax, 4096
    jae 7f
    mov rdi, rbx
    call win_path_normalize
    mov rax, rbx
    EPILOGUE
7:  mov rdi, rbx
    call mem_free
8:  xor eax, eax
    EPILOGUE

# In-place canonicalization never grows the caller's buffer. Preserve drive and UNC roots.
FN win_path_normalize
    PROLOGUE
    mov rbx, rdi
    call win_slashes
    mov rdi, rbx
    call path_rootlen
    test rax, rax
    jz 9f
    lea r11, [rbx + rax]
    mov rsi, r11
    mov rdx, r11
1:  cmp byte ptr [rsi], '/'
    jne 2f
    inc rsi
    jmp 1b
2:  cmp byte ptr [rsi], 0
    je 8f
    mov rcx, rsi
3:  mov al, [rcx]
    test al, al
    jz 4f
    cmp al, '/'
    je 4f
    inc rcx
    jmp 3b
4:  mov rax, rcx
    sub rax, rsi
    cmp rax, 1
    jne 5f
    cmp byte ptr [rsi], '.'
    jne 6f
    mov rsi, rcx
    jmp 1b
5:  cmp rax, 2
    jne 6f
    cmp word ptr [rsi], 0x2e2e
    jne 6f
    cmp rdx, r11
    jbe 51f
    dec rdx
52: cmp rdx, r11
    jbe 51f
    cmp byte ptr [rdx - 1], '/'
    je 51f
    dec rdx
    jmp 52b
51: mov rsi, rcx
    jmp 1b
6:  mov al, [rsi]
    mov [rdx], al
    inc rsi
    inc rdx
    cmp rsi, rcx
    jb 6b
    cmp byte ptr [rsi], 0
    je 81f
    mov byte ptr [rdx], '/'
    inc rdx
    jmp 1b
8:  cmp rdx, r11
    jbe 81f
    dec rdx
81: mov byte ptr [rdx], 0
9:  EPILOGUE
