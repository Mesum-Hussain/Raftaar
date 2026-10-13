# updates: the latest version from GitHub releases, checked in the background with curl or wget.
# Unix uses the release's install.sh; Windows stages with the embedded PowerShell installer.
#   RAFTAAR_RELEASES_URL   another place for the releases (tests use file://)
#   RAFTAAR_UPDATE_TARGET  the installation to update and restart into (tests)
.include "raftaar.inc"

.equ UP_FIRST, 5000             # ms after startup: the first automatic check
.equ UP_EVERY, 86400000         # ms between automatic checks
.equ UP_JOB_CHECK, 1
.equ UP_JOB_INSTALL, 2

.bss
.p2align 3
up_out: .zero SB_SIZE           # output of the running program
up_path: .zero SB_SIZE          # the state file's path
up_sb: .zero SB_SIZE            # scratch: urls, file contents, messages
up_next_at: .quad 0             # time_ms of the next automatic check, 0 for none
up_checked: .quad 0             # unix seconds of the last answer
up_pid: .long 0
up_kind: .long 0                # UP_JOB_* running, 0 for none
up_manual: .long 0              # the check was asked for: its result is reported
.globl g_update_state, g_restart, g_update_desc, g_version_text
g_update_state: .long 0         # UP_*
g_restart: .long 0              # quitting starts the new version
up_latest: .zero 32             # the latest version known
up_ready_version: .zero 32      # the version being installed or ready, pinned across later checks
up_error: .zero 256             # why the last check or install failed
up_item: .zero 64
up_target: .zero 4096           # what the installer replaces and the restart runs
up_exec: .zero 4096 + 32        # the program the restart runs
g_update_desc: .zero 256        # the Check now row's text in Settings
g_version_text: .zero 48        # "Version X" of this raftaar: the Check now row's label, the welcome screen
.data
up_fd: .long -1

.text

# ---------------- checking ----------------

# update_init(): what the last check found, and the first automatic check
FN update_init
    PROLOGUE INI_SIZE
    lea rdi, [rip + g_version_text]
    lea rsi, [rip + .Ld_version]
    call cstr_copy
    mov rdi, rax
    lea rsi, [rip + raftaar_version]
    call cstr_copy
    call up_state_path
    test rax, rax
    jz 5f
    mov rdi, rax
    call file_read_all
    test rax, rax
    jz 5f
    mov r12, rax
    lea rdi, [rsp]
    mov rsi, rax
    call ini_init
1:  lea rdi, [rsp]
    call ini_next
    test eax, eax
    jz 4f
    lea rdi, [rsp]
    lea rsi, [rip + .Lk_checked]
    call ini_key_is
    test eax, eax
    jz 2f
    mov rdi, [rsp + INI_val]
    mov rsi, [rsp + INI_vallen]
    call parse_u64
    mov [rip + up_checked], rax
    jmp 1b
2:  lea rdi, [rsp]
    lea rsi, [rip + .Lk_latest]
    call ini_key_is
    test eax, eax
    jz 1b
    mov rdi, [rsp + INI_val]
    mov rsi, [rsp + INI_vallen]
    call up_set_latest
    jmp 1b
4:  mov rdi, r12
    call mem_free
5:  call update_apply
    EPILOGUE

# update_apply(): the setting changed: schedule the automatic check or stop it
FN update_apply
    push rbx
    call up_auto_allowed
    test eax, eax
    jz 1f
    cmp qword ptr [rip + up_next_at], 0
    jne 9f
    call time_ms
    add rax, UP_FIRST
    mov [rip + up_next_at], rax
    jmp 9f
1:  mov qword ptr [rip + up_next_at], 0
9:  pop rbx
    ret

# update_timeout() -> ms until the next automatic check, or -1
FN update_timeout
    mov rax, [rip + up_next_at]
    test rax, rax
    jz 1f
    push rbx
    mov rbx, rax
    call time_ms
    sub rbx, rax
    mov eax, ebx
    pop rbx
    test eax, eax
    jns 2f
    xor eax, eax
2:  ret
1:  mov eax, -1
    ret

FN update_tick
    PROLOGUE
    mov rbx, [rip + up_next_at]
    test rbx, rbx
    jz 9f
    call time_ms
    cmp rax, rbx
    jb 9f
    add rax, UP_EVERY
    mov [rip + up_next_at], rax
    call up_auto_allowed
    test eax, eax
    jnz 1f
    mov qword ptr [rip + up_next_at], 0
    jmp 9f
1:  cmp dword ptr [rip + up_kind], 0
    jne 9f
    mov dword ptr [rip + up_manual], 0
    call up_start_check
9:  EPILOGUE

FN cmd_check_for_updates
    push rbx
    cmp dword ptr [rip + up_kind], 0
    jne 9f
    mov dword ptr [rip + up_manual], 1
    call up_start_check
9:  pop rbx
    ret

# update_busy() -> 1 while a check or an install runs
FN update_busy
    xor eax, eax
    cmp dword ptr [rip + up_kind], 0
    je 1f
    mov eax, 1
1:  ret

# update_installable() -> 1 when this raftaar may replace itself: a release build, or a test's target
FN update_installable
    push rbx
    lea rdi, [rip + .Lenv_target]
    call up_env
    test rax, rax
    jnz 1f
    mov eax, [rip + raftaar_dist]
    pop rbx
    ret
1:  mov eax, 1
    pop rbx
    ret

# up_auto_allowed() -> 1 when automatic checks may run: the setting is on, and this is a release
# build with a window (or a test names a target)
up_auto_allowed:
    push rbx
    xor ebx, ebx
    cmp dword ptr [rip + cfg_update_check], 0
    je 9f
    lea rdi, [rip + .Lenv_target]
    call up_env
    test rax, rax
    jnz 1f
    cmp dword ptr [rip + raftaar_dist], 0
    je 9f
    cmp dword ptr [rip + g_headless], 0
    jne 9f
1:  mov ebx, 1
9:  mov eax, ebx
    pop rbx
    ret

# up_start_check(): fetch the latest release's VERSION
up_start_check:
    PROLOGUE 96                 # argv
    lea rdi, [rip + up_sb]
    call sb_clear
    call up_base
    lea rdi, [rip + up_sb]
    mov rsi, rax
    call sb_push_cstr
    lea rdi, [rip + up_sb]
    lea rsi, [rip + .Llatest_path]
    call sb_push_cstr
    lea rdi, [rip + .Lcurl]
    call proc_which
    test rax, rax
    jz 3f
    mov r12, rax
    mov [rsp], rax
    lea rax, [rip + .Lfssl]
    mov [rsp + 8], rax
    lea rax, [rip + .Lmax_time]
    mov [rsp + 16], rax
    lea rax, [rip + .L20]
    mov [rsp + 24], rax
    mov ebx, 4
    # https only, redirects too, unless a test points elsewhere
    lea rdi, [rip + .Lenv_url]
    call up_env
    test rax, rax
    jnz 2f
    lea rax, [rip + .Lproto]
    mov [rsp + 32], rax
    lea rax, [rip + .Lhttps]
    mov [rsp + 40], rax
    lea rax, [rip + .Lproto_redir]
    mov [rsp + 48], rax
    lea rax, [rip + .Lhttps]
    mov [rsp + 56], rax
    mov ebx, 8
    jmp 2f
3:  lea rdi, [rip + .Lwget]
    call proc_which
    test rax, rax
    jz 8f
    mov r12, rax
    mov [rsp], rax
    lea rax, [rip + .Lqo]
    mov [rsp + 8], rax
    lea rax, [rip + .Lt]
    mov [rsp + 16], rax
    lea rax, [rip + .L20]
    mov [rsp + 24], rax
    mov ebx, 4
2:  mov rax, [rip + up_sb + SB_ptr]
    mov [rsp + rbx*8], rax
    mov qword ptr [rsp + rbx*8 + 8], 0
    mov dword ptr [rip + up_kind], UP_JOB_CHECK
    lea rdi, [rsp]
    call up_spawn
    mov r13d, eax
    mov rdi, r12
    call mem_free
    test r13d, r13d
    jnz 9f
    lea rdi, [rip + .Le_download]
    call up_failed
    jmp 9f
8:  lea rdi, [rip + .Le_nodl]
    call up_failed
9:  mov dword ptr [rip + g_dirty], 1
    EPILOGUE

# up_spawn(argv) -> 1 when the program runs; on_up_job collects its output
up_spawn:
    mov rsi, [rip + g_envp]
up_spawn_env:
    PROLOGUE
    xor edx, edx
    call run_piped
    test rax, rax
    jle 8f
    mov [rip + up_pid], eax
    mov [rip + up_fd], edx
    lea rdi, [rip + up_out]
    call sb_clear
    mov edi, [rip + up_fd]
    mov esi, POLLIN
    lea rdx, [rip + on_up_job]
    xor ecx, ecx
    call watch_add
    mov eax, 1
    EPILOGUE
8:  mov dword ptr [rip + up_kind], 0
    xor eax, eax
    EPILOGUE

# on_up_job(fd, revents, ctx): collect the output; at its end, the result
on_up_job:
    PROLOGUE
1:  lea rdi, [rip + up_out]
    mov esi, 4096
    call sb_reserve
    mov rsi, rax
    mov edi, [rip + up_fd]
    mov edx, 4096
    SYS SYS_read
    cmp rax, -EINTR
    je 1b
    cmp rax, -EAGAIN
    je 9f
    test rax, rax
    jle 2f
    cmp qword ptr [rip + up_out + SB_len], 65536
    jae 1b                      # enough kept: the rest is read and dropped
    add [rip + up_out + SB_len], rax
    jmp 1b
2:  mov edi, [rip + up_fd]
    call watch_remove
    mov edi, [rip + up_fd]
    SYS SYS_close
    mov dword ptr [rip + up_fd], -1
    mov edi, [rip + up_pid]
    xor esi, esi
    call proc_wait
    mov ebx, eax
    mov r12d, [rip + up_kind]
    mov dword ptr [rip + up_kind], 0
    mov rax, [rip + up_out + SB_ptr]
    add rax, [rip + up_out + SB_len]
    mov byte ptr [rax], 0
    mov edi, ebx
    cmp r12d, UP_JOB_INSTALL
    je 3f
    call up_check_done
    jmp 4f
3:  call up_install_done
4:  mov dword ptr [rip + g_dirty], 1
9:  EPILOGUE

# up_check_done(status): the check's answer
up_check_done:
    PROLOGUE
    test edi, edi
    jnz 7f
    mov r12, [rip + up_out + SB_ptr]
    mov r13, [rip + up_out + SB_len]
1:  test r13, r13
    jz 2f
    cmp byte ptr [r12 + r13 - 1], ' '
    ja 2f
    dec r13
    jmp 1b
2:  mov rdi, r12
    mov rsi, r13
    call up_set_latest
    test eax, eax
    jz 6f
    mov byte ptr [rip + up_error], 0
    call time_now
    mov [rip + up_checked], rax
    call up_save_state
    call up_decide
    EPILOGUE
6:  lea rdi, [rip + .Le_reply]
    call up_failed
    EPILOGUE
7:  lea rdi, [rip + .Le_download]
    call up_failed
    EPILOGUE

# up_failed(reason): the check did not answer; a check that was asked for says so
up_failed:
    PROLOGUE
    mov rbx, rdi
    lea rdi, [rip + up_error]
    mov rsi, rbx
    call cstr_copy
    cmp dword ptr [rip + up_manual], 0
    je 9f
    lea rdi, [rip + .Lt_failed]
    mov rsi, rbx
    xor edx, edx
    call up_toast
9:  EPILOGUE

# up_decide(): offer up_latest when it is newer than this raftaar
up_decide:
    PROLOGUE
    cmp byte ptr [rip + up_latest], 0
    je 9f
    lea rdi, [rip + up_latest]
    lea rsi, [rip + raftaar_version]
    call ver_cmp
    test eax, eax
    jle 5f
    call update_installable
    test eax, eax
    jz 4f
    cmp dword ptr [rip + g_update_state], UP_INSTALLING
    jae 9f
    mov dword ptr [rip + g_update_state], UP_AVAILABLE
    jmp 9f
4:  cmp dword ptr [rip + up_manual], 0
    je 9f
    lea rdi, [rip + .Lt_raftaar]
    lea rsi, [rip + up_latest]
    lea rdx, [rip + .Lt_rebuild]
    call up_toast
    jmp 9f
5:  cmp dword ptr [rip + g_update_state], UP_AVAILABLE
    jne 6f
    mov dword ptr [rip + g_update_state], UP_IDLE
6:  cmp dword ptr [rip + up_manual], 0
    je 9f
    lea rdi, [rip + .Lt_raftaar]
    lea rsi, [rip + raftaar_version]
    lea rdx, [rip + .Lt_latest]
    call up_toast
9:  mov dword ptr [rip + g_dirty], 1
    EPILOGUE

# up_set_latest(ptr, len) -> 1 when it is a version; it becomes up_latest
up_set_latest:
    PROLOGUE
    mov r12, rdi
    mov r13, rsi
    call ver_valid
    test eax, eax
    jz 9f
    lea rdi, [rip + up_latest]
    mov rsi, r12
    mov rdx, r13
    call memcpy
    lea rax, [rip + up_latest]
    mov byte ptr [rax + r13], 0
    mov eax, 1
9:  EPILOGUE

# ---------------- the state file ----------------

# up_state_path() -> the state file's path ($XDG_STATE_HOME/raftaar/update), or 0 without a home
up_state_path:
    PROLOGUE
    lea rdi, [rip + up_path]
    call sb_clear
    lea rdi, [rip + .Lenv_state]
    call up_env
    test rax, rax
    jz 1f
    lea rdi, [rip + up_path]
    mov rsi, rax
    call sb_push_cstr
    jmp 2f
1:  lea rdi, [rip + .Lenv_home]
    call up_env
    test rax, rax
    jz 8f
    lea rdi, [rip + up_path]
    mov rsi, rax
    call sb_push_cstr
    lea rdi, [rip + up_path]
    lea rsi, [rip + .Llocal_state]
    call sb_push_cstr
2:  lea rdi, [rip + up_path]
    lea rsi, [rip + .Lstate_name]
    call sb_push_cstr
    mov rax, [rip + up_path + SB_ptr]
    EPILOGUE
8:  xor eax, eax
    EPILOGUE

# up_save_state(): checked and latest into the state file
up_save_state:
    PROLOGUE
    call up_state_path
    test rax, rax
    jz 9f
    mov rbx, rax
    lea rdi, [rip + up_sb]
    call sb_clear
    lea rdi, [rip + .Lk_checked_eq]
    call up_push
    lea rdi, [rip + up_sb]
    mov rsi, [rip + up_checked]
    call sb_push_u64
    lea rdi, [rip + .Lk_latest_eq]
    call up_push
    lea rdi, [rip + up_latest]
    call up_push
    lea rdi, [rip + .Lnl]
    call up_push
    mov rdi, rbx
    call mkdir_parent
    mov rdi, rbx
    mov rsi, [rip + up_sb + SB_ptr]
    mov rdx, [rip + up_sb + SB_len]
    call file_write_all
9:  EPILOGUE

# ---------------- what is shown ----------------

# update_item() -> the status bar's update item, or 0
FN update_item
    PROLOGUE
    mov eax, [rip + g_update_state]
    cmp eax, UP_AVAILABLE
    jne 1f
    lea rdi, [rip + up_item]
    lea rsi, [rip + .Li_update]
    call cstr_copy
    mov rdi, rax
    lea rsi, [rip + up_latest]
    call cstr_copy
    lea rax, [rip + up_item]
    EPILOGUE
1:  lea rcx, [rip + .Li_updating]
    cmp eax, UP_INSTALLING
    je 2f
    lea rcx, [rip + .Li_restart]
    cmp eax, UP_READY
    je 2f
    xor ecx, ecx
2:  mov rax, rcx
    EPILOGUE

# update_desc_refresh(): g_update_desc, the text of the Check now row in Settings
FN update_desc_refresh
    PROLOGUE
    lea rdi, [rip + up_sb]
    call sb_clear
    cmp dword ptr [rip + up_kind], UP_JOB_CHECK
    jne 1f
    lea rdi, [rip + .Ld_checking]
    call up_push
    jmp 8f
1:  mov eax, [rip + g_update_state]
    cmp eax, UP_INSTALLING
    jne 2f
    lea rdi, [rip + .Ld_installing]
    call up_push
    lea rdi, [rip + up_ready_version]
    call up_push
    lea rdi, [rip + .Ld_dots]
    call up_push
    jmp 8f
2:  cmp eax, UP_READY
    jne 3f
    lea rdi, [rip + up_ready_version]
    call up_push
    lea rdi, [rip + .Ld_installed]
    call up_push
    jmp 8f
3:  cmp eax, UP_AVAILABLE
    jne 4f
    lea rdi, [rip + .Ld_version]
    call up_push
    lea rdi, [rip + up_latest]
    call up_push
    lea rdi, [rip + .Ld_available]
    call up_push
    jmp 8f
4:  cmp byte ptr [rip + up_error], 0
    je 5f
    lea rdi, [rip + .Ld_failed]
    call up_push
    lea rdi, [rip + up_error]
    call up_push
    jmp 8f
5:  cmp byte ptr [rip + up_latest], 0
    je 7f
    lea rdi, [rip + up_latest]
    lea rsi, [rip + raftaar_version]
    call ver_cmp
    test eax, eax
    jle 6f
    lea rdi, [rip + up_latest]
    call up_push
    lea rdi, [rip + .Ld_source]
    call up_push
    jmp 8f
6:  cmp qword ptr [rip + up_checked], 0
    je 7f
    lea rdi, [rip + .Ld_latest]
    call up_push
    call up_push_age
    lea rdi, [rip + .Ld_close]
    call up_push
    jmp 8f
7:  lea rdi, [rip + .Ld_never]
    call up_push
8:  mov rsi, [rip + up_sb + SB_ptr]
    mov rbx, [rip + up_sb + SB_len]
    cmp rbx, 255
    jbe 81f
    mov ebx, 255
81: lea rdi, [rip + g_update_desc]
    mov rdx, rbx
    call memcpy
    lea rax, [rip + g_update_desc]
    mov byte ptr [rax + rbx], 0
    EPILOGUE

# up_push_age(): how long ago up_checked was, onto up_sb
up_push_age:
    PROLOGUE
    call time_now
    sub rax, [rip + up_checked]
    jns 1f
    xor eax, eax
1:  cmp rax, 60
    jae 2f
    lea rdi, [rip + .Ld_now]
    call up_push
    EPILOGUE
2:  lea r12, [rip + .Ld_min]
    mov ecx, 60
    cmp rax, 3600
    jb 3f
    lea r12, [rip + .Ld_hour]
    mov ecx, 3600
    cmp rax, 86400
    jb 3f
    lea r12, [rip + .Ld_days]
    mov ecx, 86400
3:  xor edx, edx
    div rcx
    mov rbx, rax
    lea rdi, [rip + up_sb]
    mov rsi, rax
    call sb_push_u64
    cmp rbx, 1
    jne 4f
    lea rax, [rip + .Ld_days]
    cmp r12, rax
    jne 4f
    lea r12, [rip + .Ld_day]
4:  mov rdi, r12
    call up_push
    EPILOGUE

# update_dump(sb): "state=... current=... latest=... error=..." for print-update
FN update_dump
    PROLOGUE
    mov rbx, rdi
    lea r12, [rip + .Ls_checking]
    cmp dword ptr [rip + up_kind], UP_JOB_CHECK
    je 1f
    mov eax, [rip + g_update_state]
    lea rcx, [rip + up_names]
    mov r12, [rcx + rax*8]
1:  mov rdi, rbx
    lea rsi, [rip + .Lp_state]
    call sb_push_cstr
    mov rdi, rbx
    mov rsi, r12
    call sb_push_cstr
    mov rdi, rbx
    lea rsi, [rip + .Lp_current]
    call sb_push_cstr
    mov rdi, rbx
    lea rsi, [rip + raftaar_version]
    call sb_push_cstr
    mov rdi, rbx
    lea rsi, [rip + .Lp_latest]
    call sb_push_cstr
    mov rdi, rbx
    lea rsi, [rip + up_latest]
    call sb_push_cstr
    mov rdi, rbx
    lea rsi, [rip + .Lp_error]
    call sb_push_cstr
    mov rdi, rbx
    lea rsi, [rip + up_error]
    call sb_push_cstr
    mov rdi, rbx
    mov esi, 10
    call sb_push_byte
    # and the Check now row's text in Settings
    call update_desc_refresh
    mov rdi, rbx
    lea rsi, [rip + .Lp_desc]
    call sb_push_cstr
    mov rdi, rbx
    lea rsi, [rip + g_update_desc]
    call sb_push_cstr
    mov rdi, rbx
    mov esi, 10
    call sb_push_byte
    EPILOGUE

# ---------------- helpers ----------------

# up_toast(a, b, c): a toast of the strings; b and c may be 0
up_toast:
    PROLOGUE
    mov r12, rdi
    mov r13, rsi
    mov r14, rdx
    lea rdi, [rip + up_sb]
    call sb_clear
    mov rdi, r12
    call up_push
    test r13, r13
    jz 1f
    mov rdi, r13
    call up_push
1:  test r14, r14
    jz 2f
    mov rdi, r14
    call up_push
2:  mov rdi, [rip + up_sb + SB_ptr]
    call app_toast
    EPILOGUE

# up_push(cstr): onto up_sb
up_push:
    mov rsi, rdi
    lea rdi, [rip + up_sb]
    jmp sb_push_cstr

# up_env(name) -> the variable's value, or 0 when it is unset or empty
up_env:
    push rbx
    call getenv
    test rax, rax
    jz 1f
    cmp byte ptr [rax], 0
    jne 1f
    xor eax, eax
1:  pop rbx
    ret

# up_base() -> where the releases are: RAFTAAR_RELEASES_URL or GitHub
up_base:
    push rbx
    lea rdi, [rip + .Lenv_url]
    call up_env
    test rax, rax
    jnz 1f
    lea rax, [rip + .Lbase]
1:  pop rbx
    ret

# ---------------- installing ----------------

# cmd_install_update(): install or stage up_latest in the background
FN cmd_install_update
    PROLOGUE 64                 # argv
    cmp dword ptr [rip + g_update_state], UP_AVAILABLE
    jne 9f
    cmp dword ptr [rip + up_kind], 0
    jne 9f
    call update_installable
    test eax, eax
    jnz 1f
    lea rdi, [rip + .Lt_source]
    xor esi, esi
    xor edx, edx
    call up_toast
    jmp 9f
1:  call update_target
    test rax, rax
    jz 8f
    mov r13, rax
.ifdef WINDOWS
    call up_base
    mov rcx, rax
    lea rdi, [rip + .Lprepare]
    lea rsi, [rip + up_latest]
    mov rdx, r13
    call win_update_command
    test rax, rax
    jz 6f
    mov rdi, rax
    mov rsi, rdx
    mov dword ptr [rip + up_kind], UP_JOB_INSTALL
    call up_spawn_env
.else
    lea rdi, [rip + up_sb]
    call sb_clear
    call up_base
    mov rdi, rax
    call up_push
    lea rdi, [rip + .Ldownload_v]
    call up_push
    lea rdi, [rip + up_latest]
    call up_push
    lea rdi, [rip + .Linstall_sh]
    call up_push
    # sh -c SCRIPT sh URL TARGET VERSION, the script by the program that downloads
    lea rdi, [rip + .Lcurl]
    call proc_which
    test rax, rax
    jz 2f
    mov rdi, rax
    call mem_free
    lea r12, [rip + .Lsh_curl]
    lea rdi, [rip + .Lenv_url]
    call up_env
    test rax, rax
    jz 3f
    lea r12, [rip + .Lsh_curl_any]
    jmp 3f
2:  lea rdi, [rip + .Lwget]
    call proc_which
    test rax, rax
    jz 7f
    mov rdi, rax
    call mem_free
    lea r12, [rip + .Lsh_wget]
3:  lea rax, [rip + .Lbin_sh]
    mov [rsp], rax
    lea rax, [rip + .Ldash_c]
    mov [rsp + 8], rax
    mov [rsp + 16], r12
    lea rax, [rip + .Lsh]
    mov [rsp + 24], rax
    mov rax, [rip + up_sb + SB_ptr]
    mov [rsp + 32], rax
    mov [rsp + 40], r13
    lea rax, [rip + up_latest]
    mov [rsp + 48], rax
    mov qword ptr [rsp + 56], 0
    mov dword ptr [rip + up_kind], UP_JOB_INSTALL
    lea rdi, [rsp]
    call up_spawn
.endif
    test eax, eax
    jz 6f
    mov byte ptr [rip + up_error], 0
    mov dword ptr [rip + g_update_state], UP_INSTALLING
    # later checks may move up_latest; what is being installed stays this version
    lea rdi, [rip + up_ready_version]
    lea rsi, [rip + up_latest]
    call cstr_copy
    jmp 9f
6:  lea rdi, [rip + .Le_start]
    call up_install_failed
    jmp 9f
7:  lea rdi, [rip + .Le_nodl]
    call up_install_failed
    jmp 9f
8:  lea rdi, [rip + up_error]
    call up_install_failed
9:  mov dword ptr [rip + g_dirty], 1
    EPILOGUE

# up_install_done(status): the installer's exit; when it failed, its last line says why
up_install_done:
    PROLOGUE
    test edi, edi
    jnz 1f
    mov dword ptr [rip + g_update_state], UP_READY
    EPILOGUE
1:  mov r12, [rip + up_out + SB_ptr]
    mov r13, [rip + up_out + SB_len]
2:  test r13, r13
    jz 3f
    cmp byte ptr [r12 + r13 - 1], ' '
    ja 3f
    dec r13
    jmp 2b
3:  mov rbx, r13
4:  test rbx, rbx
    jz 5f
    cmp byte ptr [r12 + rbx - 1], 10
    je 5f
    dec rbx
    jmp 4b
5:  sub r13, rbx
    jnz 6f
    lea rdi, [rip + .Le_install]
    call up_install_failed
    EPILOGUE
6:  cmp r13, 200
    jbe 7f
    mov r13d, 200
7:  lea rdi, [rip + up_error]
    lea rsi, [r12 + rbx]
    mov rdx, r13
    call memcpy
    lea rax, [rip + up_error]
    mov byte ptr [rax + r13], 0
    lea rdi, [rip + up_error]
    call up_install_failed
    EPILOGUE

# up_install_failed(reason): back to offering the update, with a toast
up_install_failed:
    PROLOGUE
    mov rbx, rdi
    lea rdi, [rip + up_error]
    cmp rbx, rdi
    je 1f
    mov rsi, rbx
    call cstr_copy
1:  mov dword ptr [rip + g_update_state], UP_AVAILABLE
    lea rdi, [rip + .Lt_update_failed]
    lea rsi, [rip + up_error]
    xor edx, edx
    call up_toast
    EPILOGUE

# update_target() -> the installation to replace: the running binary, or on macOS the .app it is in;
# 0 with up_error set when there is none
FN update_target
    PROLOGUE
    lea rdi, [rip + .Lenv_target]
    call up_env
    test rax, rax
    jz 1f
    mov rbx, rax
    mov rdi, rax
    call strlen
    cmp rax, 4096
    jae 7f
    lea rdi, [rip + up_target]
    mov rsi, rbx
    call cstr_copy
    jmp 8f
1:
.ifdef MACOS
    lea rdi, [rip + up_target]
    mov esi, 4096
    call mac_exe_path
    test rax, rax
    js 7f
    lea rdi, [rip + up_target]
    mov rsi, rax
    lea rdx, [rip + .Lcontents]
    mov ecx, 16
    call str_find
    test rax, rax
    jle 6f
    lea rcx, [rip + up_target]
    mov byte ptr [rcx + rax], 0
    jmp 8f
6:  lea rsi, [rip + .Le_bundle]
    jmp 71f
.else
    lea rdi, [rip + .Lself_exe]
    lea rsi, [rip + up_target]
    mov edx, 4095
    SYS SYS_readlink
    test rax, rax
    jle 7f
    mov rbx, rax
    lea rcx, [rip + up_target]
    mov byte ptr [rcx + rax], 0
    # " (deleted)": an earlier update has replaced the file
    lea rdi, [rip + up_target]
    mov rsi, rbx
    lea rdx, [rip + .Ldeleted]
    mov ecx, 10
    call str_ends
    test eax, eax
    jz 8f
    lea rcx, [rip + up_target]
    mov byte ptr [rcx + rbx - 10], 0
    jmp 8f
.endif
7:  lea rsi, [rip + .Le_self]
71: lea rdi, [rip + up_error]
    call cstr_copy
    mov byte ptr [rip + up_target], 0
    xor eax, eax
    EPILOGUE
8:  lea rax, [rip + up_target]
    EPILOGUE

# ---------------- restarting ----------------

FN cmd_restart_to_update
    push rbx
    cmp dword ptr [rip + g_update_state], UP_READY
    jne 9f
    call app_remember_restart
    # quitting asks about unsaved files; Cancel there clears g_restart
    mov dword ptr [rip + g_restart], 1
    call cmd_quit
9:  pop rbx
    ret

# update_click(): the status bar item: install, or restart into what was installed
FN update_click
    mov eax, [rip + g_update_state]
    cmp eax, UP_AVAILABLE
    jne 1f
    jmp cmd_install_update
1:  cmp eax, UP_READY
    jne 2f
    jmp cmd_restart_to_update
2:  ret

# update_restart(): after the loop, with g_restart: the new version takes this one's place, with the
# same environment and in the same terminal, and opens the project (the session brings back its
# files); returns only when it could not be started. On macOS too, rather than through open(1):
# Launch Services would start it with launchd's environment, and XDG_CONFIG_HOME and the like set
# for this raftaar would be lost.
FN update_restart
.ifdef WINDOWS
    PROLOGUE
    call up_base
    mov rcx, rax
    lea rdi, [rip + .Lapply]
    lea rsi, [rip + up_ready_version]
    lea rdx, [rip + up_target]
    call win_update_command
    test rax, rax
    jz 9f
    mov rdi, rax
    mov rsi, rdx
    call win_update_launch
    test eax, eax
    jnz 8f
9:  call win_update_error
8:  EPILOGUE
.else
    PROLOGUE 32
    cmp byte ptr [rip + up_target], 0
    je 9f
    lea rdi, [rip + up_exec]
    lea rsi, [rip + up_target]
    call cstr_copy
.ifdef MACOS
    # the program in the bundle, unless a test names a program
    mov rbx, rax
    lea rdi, [rip + .Lenv_target]
    call up_env
    test rax, rax
    jnz 1f
    mov rdi, rbx
    lea rsi, [rip + .Lbundle_exe]
    call cstr_copy
1:
.endif
    call up_fds_cloexec
    lea rdi, [rip + up_exec]
    call app_restart_paths
    mov rbx, rax
    lea rdi, [rip + up_exec]
    mov rsi, rbx
    mov rdx, [rip + g_envp]
    SYS SYS_execve
    mov rdi, rbx
    call mem_free
9:  EPILOGUE
.endif

# update_discard(): quitting without Restart to update. On Windows the download staged for the
# restart is deleted by the helper once this raftaar has exited; elsewhere the update is in place.
FN update_discard
.ifdef WINDOWS
    PROLOGUE
    cmp dword ptr [rip + g_update_state], UP_READY
    jne 9f
    call up_base
    mov rcx, rax
    lea rdi, [rip + .Ldiscard]
    lea rsi, [rip + up_ready_version]
    lea rdx, [rip + up_target]
    call win_update_command
    test rax, rax
    jz 9f
    mov rdi, rax
    mov rsi, rdx
    call win_update_launch
9:  EPILOGUE
.else
    ret
.endif

# up_fds_cloexec(): nothing of this process goes on in the new one: the display connection, pipes,
# terminals (whose shells then end); marked close-on-exec rather than closed, as other threads (on
# macOS) may still use them until the exec
up_fds_cloexec:
    push rbx
.ifdef MACOS
.else
    mov edi, 3
    mov esi, -1
    mov edx, 4                  # CLOSE_RANGE_CLOEXEC
    SYS SYS_close_range
    test rax, rax
    jz 9f
.endif
    mov ebx, 3
1:  mov edi, ebx
    mov esi, 2                  # F_SETFD
    mov edx, 1                  # FD_CLOEXEC
    SYS SYS_fcntl
    inc ebx
    cmp ebx, 1024
    jb 1b
9:  pop rbx
    ret

# ---------------- versions ----------------

# ver_valid(ptr, len) -> 1 for MAJOR.MINOR.PATCH with an optional -suffix of [0-9A-Za-z.], at most
# 31 bytes
FN ver_valid
    xor eax, eax
    test rsi, rsi
    jz 9f
    cmp rsi, 31
    ja 9f
    add rsi, rdi                # end
    xor ecx, ecx                # fields read
1:  # a field: digits
    cmp rdi, rsi
    jae 9f
    movzx edx, byte ptr [rdi]
    sub edx, '0'
    cmp edx, 9
    ja 9f
2:  inc rdi
    cmp rdi, rsi
    jae 3f
    movzx edx, byte ptr [rdi]
    sub edx, '0'
    cmp edx, 9
    jbe 2b
3:  inc ecx
    cmp ecx, 3
    je 4f
    cmp rdi, rsi
    jae 9f
    cmp byte ptr [rdi], '.'
    jne 9f
    inc rdi
    jmp 1b
4:  cmp rdi, rsi
    je 8f
    cmp byte ptr [rdi], '-'
    jne 9f
    inc rdi
    cmp rdi, rsi
    jae 9f                      # a dash with nothing after it
5:  movzx edx, byte ptr [rdi]
    cmp edx, '.'
    je 6f
    mov r8d, edx
    sub r8d, '0'
    cmp r8d, 9
    jbe 6f
    or edx, 0x20
    sub edx, 'a'
    cmp edx, 25
    ja 9f
6:  inc rdi
    cmp rdi, rsi
    jb 5b
8:  mov eax, 1
9:  ret

# ver_cmp(a cstr, b cstr) -> -1, 0 or 1: the numbers compared field by field
FN ver_cmp
    PROLOGUE 64
    mov r12, rsi
    lea rsi, [rsp]
    call ver_fields
    mov rdi, r12
    lea rsi, [rsp + 32]
    call ver_fields
    xor ecx, ecx
1:  mov rax, [rsp + rcx*8]
    cmp rax, [rsp + 32 + rcx*8]
    ja 2f
    jb 3f
    inc ecx
    cmp ecx, 4
    jb 1b
    xor eax, eax
    EPILOGUE
2:  mov eax, 1
    EPILOGUE
3:  mov eax, -1
    EPILOGUE

# ver_fields(cstr, out): up to 4 dot-separated numbers into out[0..3], 0 for those missing; stops at
# anything else, so a -suffix does not count
ver_fields:
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    xor eax, eax
    mov [r12], rax
    mov [r12 + 8], rax
    mov [r12 + 16], rax
    mov [r12 + 24], rax
    xor r13d, r13d
1:  movzx eax, byte ptr [rbx]
    sub eax, '0'
    cmp eax, 9
    ja 9f
    mov rdi, rbx
    mov esi, 20
    call parse_u64
    mov [r12 + r13*8], rax
    add rbx, rdx
    inc r13d
    cmp r13d, 4
    jae 9f
    cmp byte ptr [rbx], '.'
    jne 9f
    inc rbx
    jmp 1b
9:  EPILOGUE

.section .rodata
.Lbase: .asciz "https://github.com/Mesum-Hussain/Raftaar/releases"
.Llatest_path: .asciz "/latest/download/VERSION"
.Lenv_url: .asciz "RAFTAAR_RELEASES_URL"
.Lenv_target: .asciz "RAFTAAR_UPDATE_TARGET"
.Lenv_state: .asciz "XDG_STATE_HOME"
.Lenv_home: .asciz "HOME"
.Llocal_state: .asciz "/.local/state"
.Lstate_name: .asciz "/raftaar/update"
.Lk_checked: .asciz "checked"
.Lk_latest: .asciz "latest"
.Lk_checked_eq: .asciz "checked="
.Lk_latest_eq: .asciz "\nlatest="
.Lnl: .asciz "\n"
.Lcurl: .asciz "curl"
.Lwget: .asciz "wget"
.Lfssl: .asciz "-fsSL"
.Lmax_time: .asciz "--max-time"
.L20: .asciz "20"
.Lproto: .asciz "--proto"
.Lproto_redir: .asciz "--proto-redir"
.Lhttps: .asciz "=https"
.Lqo: .asciz "-qO-"
.Lt: .asciz "-T"
.Le_download: .asciz "download failed"
.Le_reply: .asciz "unexpected reply"
.Le_nodl: .asciz "needs curl or wget"
.Lt_failed: .asciz "Couldn't check for updates: "
.Lt_raftaar: .asciz "raftaar "
.Lt_latest: .asciz " is the latest"
.Lt_rebuild: .asciz " is available; pull and rebuild to update"
.Li_update: .asciz "Update to "
.Li_updating: .asciz "Updating\342\200\246"
.Li_restart: .asciz "Restart to update"
.Ld_checking: .asciz "Checking\342\200\246"
.Ld_installing: .asciz "Installing "
.Ld_dots: .asciz "\342\200\246"
.ifdef WINDOWS
.Ld_installed: .asciz " is downloaded; restart to install it"
.else
.Ld_installed: .asciz " is installed; restart to use it"
.endif
.Ld_available: .asciz " is available"
.Ld_failed: .asciz "Couldn't check: "
.Ld_source: .asciz " is available (built from source)"
.Ld_latest: .asciz "The latest version (checked "
.Ld_version: .asciz "Version "
.Ld_close: .asciz ")"
.Ld_never: .asciz "Not checked yet"
.Ld_now: .asciz "just now"
.Ld_min: .asciz " min ago"
.Ld_hour: .asciz " h ago"
.Ld_day: .asciz " day ago"
.Ld_days: .asciz " days ago"
.Lp_state: .asciz "state="
.Lp_current: .asciz " current="
.Lp_latest: .asciz " latest="
.Lp_error: .asciz " error="
.Lp_desc: .asciz "desc="
.Ls_idle: .asciz "idle"
.Ls_available: .asciz "available"
.Ls_installing: .asciz "installing"
.Ls_ready: .asciz "ready"
.Ls_checking: .asciz "checking"
.p2align 3
up_names: .quad .Ls_idle, .Ls_available, .Ls_installing, .Ls_ready
.Lt_source: .asciz "This raftaar was built from source; pull and rebuild to update"
.Lt_update_failed: .asciz "Update failed: "
.Ldownload_v: .asciz "/download/v"
.Linstall_sh: .asciz "/install.sh"
.Lbin_sh: .asciz "/bin/sh"
.Ldash_c: .asciz "-c"
.Lsh: .asciz "sh"
.Lsh_curl: .asciz "exec 2>&1; f=$(mktemp) || exit 1; curl -fsSL --proto =https --proto-redir =https -o \"$f\" \"$1\" && sh \"$f\" --update --target \"$2\" --version \"$3\"; s=$?; rm -f \"$f\"; exit $s"
.Lsh_curl_any: .asciz "exec 2>&1; f=$(mktemp) || exit 1; curl -fsSL -o \"$f\" \"$1\" && sh \"$f\" --update --target \"$2\" --version \"$3\"; s=$?; rm -f \"$f\"; exit $s"
.Lsh_wget: .asciz "exec 2>&1; f=$(mktemp) || exit 1; wget -q -O \"$f\" \"$1\" && sh \"$f\" --update --target \"$2\" --version \"$3\"; s=$?; rm -f \"$f\"; exit $s"
.Le_start: .asciz "the installer did not start"
.Le_install: .asciz "the installer failed"
.Le_self: .asciz "the running program was not found"
.Le_bundle: .asciz "raftaar is not running from an app bundle"
.Lcontents: .asciz "/Contents/MacOS/"
.Lself_exe: .asciz "/proc/self/exe"
.Ldeleted: .asciz " (deleted)"
.Lbundle_exe: .asciz "/Contents/MacOS/raftaar"
.Lprepare: .asciz "prepare"
.Lapply: .asciz "apply"
.Ldiscard: .asciz "discard"
