# Windows directory change notifications trigger a complete enumeration of that directory.
# Keeping enumeration state across reads avoids losing filenames when a notification burst is
# larger than the core's event buffer. No notification buffer can overflow, and all work runs
# on the main thread. File stamps in app/watch.s suppress reloads of unchanged documents.
# Each notification opens the directory at that path again, so a directory removed and made again
# is followed; one that is gone reports IN_IGNORED, as inotify does, and adding it again later
# watches it again.
.include "win.inc"
.equ WW_SIZE, 24
.equ WW_MAX, 4096
.bss
.p2align 3
ww_entries: .zero WW_SIZE * WW_MAX
ww_count: .long 0
ww_bytes: .long 0
ww_cursor: .long 0
ww_parent: .long 0
ww_dents: .zero 32768
.data
ww_active: .long -1
ww_fd: .long -1
.text
FN ws_watch_init
    xor edi, edi
    mov esi, FD_WATCH
    mov edx, O_NONBLOCK
    jmp win_fd_alloc

FN ws_watch_add
    PROLOGUE 96
    mov r12, rsi
    xor ebx, ebx
1:  cmp ebx, [rip + ww_count]
    jae 2f
    imul eax, ebx, WW_SIZE
    lea r13, [rip + ww_entries]
    add r13, rax
    mov rdi, [r13]
    mov rsi, r12
    call strcmp_eq
    test eax, eax
    jnz 7f
    inc ebx
    jmp 1b
7:  # watched before: once its directory was gone, it is watched again if it is there now
    cmp qword ptr [r13 + 8], 0
    jne 8f
    mov rdi, r12
    call ww_open
    test rax, rax
    jz 9f
    mov [r13 + 8], rax
    jmp 8f
2:  cmp ebx, WW_MAX
    jae 9f
    mov rdi, r12
    call ww_open
    mov r15, rax
    test rax, rax
    jz 9f
    mov rdi, r12
    call strlen
    mov rdi, r12
    mov rsi, rax
    call mem_dup
    imul edx, ebx, WW_SIZE
    lea rcx, [rip + ww_entries]
    add rcx, rdx
    mov [rcx], rax
    mov [rcx + 8], r15
    inc dword ptr [rip + ww_count]
8:  mov eax, ebx
    EPILOGUE
9:  mov rax, -2
    EPILOGUE

# ww_open(path) -> change notification handle of that directory, or 0
ww_open:
    PROLOGUE 96
    call win_file_path
    mov rbx, rax
    xor r12d, r12d
    test rax, rax
    jz 9f
    mov rcx, rax
    xor edx, edx
    mov r8d, 0x1f
    API FindFirstChangeNotificationW
    cmp rax, -1
    je 8f
    mov r12, rax
8:  mov rdi, rbx
    call mem_free
9:  mov rax, r12
    EPILOGUE

FN win_watch_ready
    PROLOGUE 96
    cmp dword ptr [rip + ww_active], -1
    jne 8f
    xor ebx, ebx
1:  cmp ebx, [rip + ww_count]
    jae 9f
    imul eax, ebx, WW_SIZE
    lea r12, [rip + ww_entries]
    add r12, rax
    mov rcx, [r12 + 8]
    test rcx, rcx
    jz 2f
    xor edx, edx
    API WaitForSingleObject
    test eax, eax
    jz 3f
2:  inc ebx
    jmp 1b
3:  # Rearm before enumerating, so changes during enumeration remain signaled: with a handle on the
    # directory at that path now, which a removed one made again is not
    mov rcx, [r12 + 8]
    API FindCloseChangeNotification
    mov qword ptr [r12 + 8], 0
    mov rdi, [r12]
    call ww_open
    mov [r12 + 8], rax
    mov [rip + ww_active], ebx
    mov dword ptr [rip + ww_bytes], 0
    mov dword ptr [rip + ww_cursor], 0
    mov dword ptr [rip + ww_fd], -1
    mov dword ptr [rip + ww_parent], 2      # gone: IN_IGNORED and no entries
    test rax, rax
    jz 8f
    mov dword ptr [rip + ww_parent], 1
    mov rdi, [r12]
    mov esi, O_DIRECTORY | O_CLOEXEC
    xor edx, edx
    call ws_open
    mov [rip + ww_fd], eax
8:  mov eax, 1
    EPILOGUE
9:  xor eax, eax
    EPILOGUE

FN win_watch_read
    PROLOGUE 16
    mov r12, rdi
    mov r13, rsi
    xor r14d, r14d
.Lwr_next:
    call win_watch_ready
    test eax, eax
    jz .Lwr_done
    cmp dword ptr [rip + ww_parent], 0
    je .Lwr_dent
    lea rax, [r14 + 24]
    cmp rax, r13
    ja .Lwr_done
    lea rdx, [r12 + r14]
    mov eax, [rip + ww_active]
    mov [rdx], eax
    mov eax, IN_CREATE | IN_DELETE | IN_MOVED_TO
    cmp dword ptr [rip + ww_parent], 2
    jne 1f
    or eax, IN_IGNORED
1:  mov [rdx + 4], eax
    mov dword ptr [rdx + 8], 0
    mov dword ptr [rdx + 12], 8
    mov qword ptr [rdx + 16], 0
    add r14, 24
    mov dword ptr [rip + ww_parent], 0
.Lwr_dent:
    mov eax, [rip + ww_cursor]
    cmp eax, [rip + ww_bytes]
    jb .Lwr_emit
    mov edi, [rip + ww_fd]
    test edi, edi
    js .Lwr_end
    lea rsi, [rip + ww_dents]
    mov edx, 32768
    call ws_getdents
    test rax, rax
    jle .Lwr_end
    mov [rip + ww_bytes], eax
    mov dword ptr [rip + ww_cursor], 0
    xor eax, eax
.Lwr_emit:
    lea rbx, [rip + ww_dents]
    add rbx, rax
    lea rdi, [rbx + 19]
    call strlen
    lea r15, [rax + 8]
    and r15, -8
    lea rax, [r14 + r15 + 16]
    cmp rax, r13
    ja .Lwr_done
    lea rdx, [r12 + r14]
    mov eax, [rip + ww_active]
    mov [rdx], eax
    mov dword ptr [rdx + 4], IN_CLOSE_WRITE | IN_MOVED_TO
    mov dword ptr [rdx + 8], 0
    mov [rdx + 12], r15d
    lea rdi, [rdx + 16]
    mov rsi, r15
    xor edx, edx
    # zero padding using the core memset(dst, value, len)
    mov rdx, r15
    xor esi, esi
    call memset
    lea rdi, [r12 + r14 + 16]
    lea rsi, [rbx + 19]
    call cstr_copy
    lea r14, [r14 + r15 + 16]
    movzx eax, word ptr [rbx + 16]
    add [rip + ww_cursor], eax
    jmp .Lwr_next
.Lwr_end:
    mov edi, [rip + ww_fd]
    test edi, edi
    js 1f
    call ws_close
1:  mov dword ptr [rip + ww_active], -1
    mov dword ptr [rip + ww_fd], -1
    jmp .Lwr_next
.Lwr_done:
    mov rax, r14
    test rax, rax
    jnz 9f
    mov rax, -11
9:  EPILOGUE
