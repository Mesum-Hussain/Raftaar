# application shell: init, tabs, layout, chrome (titlebar, tabs, status bar), input routing
.include "raftaar.inc"

.equ ID_TITLE, 0x2000
.equ ID_WMIN, 0x2001
.equ ID_WMAX, 0x2002
.equ ID_WCLOSE, 0x2003
.equ ID_TOG_SIDE, 0x2004
.equ ID_SETTINGS_BTN, 0x2006
.equ ID_TOG_TERM, 0x2007
.equ ID_GIT_BTN, 0x2008
.equ ID_PROJECT_BTN, 0x2009
.equ ID_TAB_NEW, 0x200a
.equ ID_SEARCH, 0x200b
.equ ID_CRUMB, 0x2c00               # + folder of the status bar's path; + 100 "…", + 101 Home
.equ CRUMB_MAX, 200                 # entries of a folder read for its menu
.equ CRUMB_SHOW, 22                 # and shown
.equ CRUMB_BLOB, 16384
.equ CRUMB_BUF, 32768
.equ PM_RECENT, 3                 # the project menu's first recent folder
.equ ID_TAB, 0x2100              # + index
.equ ID_TABX, 0x2400             # + index
.equ ID_SPLIT_L, 0x2700
.equ ID_DLG, 0x2800              # + button
.equ ID_STATUS, 0x2900           # + item
.equ TIP_DELAY, 500              # ms of steady hover before a tooltip shows
.equ TIP_PENDING, 0
.equ TIP_SHOWN, 1
.equ TIP_GRACE, 400               # ms after a tooltip hides that the next one shows at once
.equ TIP_DISMISSED, 2
.equ TT_id, 0                    # tip_table entry: button, text, handler
.equ TT_text, 8
.equ TT_fn, 16
.equ TT_SIZE, 24
.equ TIP_TEXT_MAX, 4400          # bytes of a tip_note_text tooltip (a git command with a file's path)
.equ RAFTAAR_LEN, 7             # bytes of "Raftaar", the name on the welcome screen
.equ ID_WELCOME, 0x2a00          # + item

.bss
.p2align 3
.globl g_focus, g_win_focused, g_tabs, g_tab_cur, g_project, g_project_name, g_branch
g_focus: .long 0
g_tabs: .zero VEC_SIZE
g_project: .quad 0
# the project is the folder of a file opened without one: it is not remembered as the last project
# and its session is not saved, so the folder's own session stays as it was
.globl g_project_adopted, g_wait
g_project_adopted: .long 0
g_wait: .long 0                 # --wait: a program waits for the editor
.p2align 3
.globl g_start_paths
g_start_paths: .zero VEC_SIZE
restart_paths: .quad 0
g_project_name: .quad 0
g_branch: .zero 64
.globl g_toast, g_toast_until
g_toast: .zero 256
g_toast_until: .quad 0
tip_id: .long 0                  # button whose tooltip is pending or visible, 0 = none
tip_cand: .long 0                # button hovered in this frame, noted while drawing
tip_cx: .long 0                  # its x, the y its tooltip hangs from, and its width
tip_cy: .long 0
tip_cw: .long 0
tip_state: .long 0               # TIP_PENDING, TIP_SHOWN, or TIP_DISMISSED by a key press
scroll_rem: .long 0, 0           # what scroll sensitivity left of a pixel, x and y, in hundredths
.p2align 3
tip_since: .quad 0               # time_ms when the pointer reached tip_id
tip_left: .quad 0                # time_ms when the pointer left a shown tooltip
tip_text_id: .long 0             # the button whose tooltip is in tip_text (tip_note_text)
tip_text: .zero TIP_TEXT_MAX
g_tabscroll: .long 0
.globl g_side_shown, g_argb
g_argb: .long 0                  # the window's pixels have alpha (Wayland): its corners can be see-through
g_side_shown: .long 0            # the sidebar is drawn (it gives way in a narrow window)
crumb_term: .long 0              # the status bar's folders are a terminal's: a click is a cd
crumb_leaf: .long 0              # the last of them is a file's name
crumb_homelen: .long 0           # bytes of crumb_path that are the home folder, 0: not under it
crumb_nsegs: .long 0
crumb_first: .long 0             # the first one shown; those before it are behind "…"
crumb_x: .long 0                 # where their menu stands
crumb_r: .zero 16
crumb_segs: .zero 16 * 64        # ptr into crumb_path, length, width
crumb_ptr: .zero 8 * CRUMB_MAX   # a folder's menu: its entries' names (crumb_names), folders marked
crumb_isdir: .zero CRUMB_MAX
crumb_items: .zero 16 * (CRUMB_SHOW + 2)
crumb_path: .zero 4096
crumb_tmp: .zero 4352
cwd_now: .zero 4096              # follow_cwd: the folder the shell shown is in
drop_path: .zero 4096            # app_on_drop: a dropped file's path
.p2align 3
drop_text: .zero SB_SIZE         # and what a terminal is given for the files
cwd_seen: .zero 4096             # and the one it was in when last looked at
crumb_dir: .zero 4096
crumb_names: .zero CRUMB_BLOB
crumb_buf: .zero CRUMB_BUF
side_fit: .long 0                # the sidebar was shown again: its width is fitted once drawn
side_narrow: .long 0             # the window is too narrow for the sidebar (app_render)
side_asked: .long 0              # and the toggle asked for it there, until the window is wide again
.p2align 3
group_seq: .quad 0               # the last TAB_group and TAB_id given out
tab_seq: .quad 0
g_side_px: .long 0
dlg_kind: .long 0                # 0 none, 1 close tab, 2 quit, 3 open another project, 4 app_confirm, 5 close all
dlg_tab: .quad 0
.p2align 3
dlg_title: .quad 0               # app_confirm: the question, a line under it, the button, its function
dlg_text: .quad 0
dlg_ok: .quad 0
dlg_fn: .quad 0
dlg_cancel: .quad 0              # app_confirm's Cancel calls this when it is set
dlg_term: .quad 0                # the terminal a close asks about
ro_doc: .quad 0                  # ask_readonly: the file asked about, and the question
ro_kind: .long 0                 # a close or quit that asked about it (dlg_kind), carried on after Overwrite
ro_close: .long 0                # vim's :wq asked: Overwrite closes the file too
ro_title: .zero 256
ro_path: .zero 4096              # Save As onto a read-only file: that path
ro_dir: .zero 4096
switch_pending: .long 0          # a project switch waits on unsaved files
switch_path: .zero 4096
nw_exe: .zero 4096               # app_new_window: this program
.p2align 3
pm_items: .zero 16 * 13         # the project menu: 2 commands, a line, 9 folders, the end
.globl g_shot_path
g_shot_path: .quad 0
tmp_sb: .zero SB_SIZE
split_grab: .long 0             # a divider's drag: the pointer's distance from it at the press
split_moved: .long 0            # and whether the pointer has moved since
split_reanchor: .long 0         # a double-click reset the width: the next frame takes hold anew
split_l_bits: .long 0           # UB_* of the divider, hit tested before the panels
side_fit_px: .long 0            # the width that cuts no name of the tree, as last measured
split_fold: .long 0             # the sidebar's drag went under its least width: folded while held
.globl g_editor_rect
g_editor_rect: .zero 16
.globl g_title_inset
g_title_inset: .long 0           # title bar space the platform keeps (macOS window buttons)
.p2align 3
.globl g_file
g_file: .quad 0                  # DOC of the active tab when it shows a file (text or image)

.text

# ---------------- init ----------------

FN app_init
    PROLOGUE 16
    call config_load
    call app_sync_panels
    call theme_scan
    mov edi, 1
    call theme_settings_init
    call theme_apply_config
    call app_load_fonts
    call syntax_load_all
    call keys_init
    call vim_sync
    call watch_init
    call update_init
    call ai_apply
    EPILOGUE

# app_load_fonts(): built-in fonts unless the config names .ttf files
FN app_load_fonts
    PROLOGUE
    lea rdi, [rip + font_mono]
    lea rsi, [rip + font_mono_end]
    sub rsi, rdi
    mov rdx, [rip + cfg_font]
    call load_font_or
    mov [rip + g_font_code], rax
    lea rdi, [rip + font_ui]
    lea rsi, [rip + font_ui_end]
    sub rsi, rdi
    mov rdx, [rip + cfg_ui_font]
    call load_font_or
    mov [rip + g_font_ui], rax
    EPILOGUE

# load_font_or(builtin ptr, len, path cstr) -> FONT*
load_font_or:
    PROLOGUE
    mov r12, rdi
    mov r13, rsi
    cmp byte ptr [rdx], 0
    je 1f
    mov rdi, rdx
    call file_read_all
    test rax, rax
    jz 1f
    mov rdi, rax
    mov rsi, rdx
    call font_load
    test rax, rax
    jnz 2f
1:  mov rdi, r12
    mov rsi, r13
    call font_load
2:  EPILOGUE

# app_set_project(dir cstr): project root for explorer and session
FN app_set_project
    mov dword ptr [rip + g_project_adopted], 0
    mov dword ptr [rip + panels_hidden], 0 # a folder opened as such shows its panels
set_project:
    PROLOGUE
    mov rbx, rdi
    call app_sync_panels
    mov rdi, [rip + g_project]
    call mem_free
    mov rdi, rbx
    call strlen
    # strip trailing slash, retaining the complete filesystem root
.ifdef WINDOWS
    mov r12, rax
    mov rdi, rbx
    call path_rootlen
    mov rcx, rax
    mov rax, r12
    cmp rax, rcx
.else
    cmp rax, 1
.endif
    jbe 1f
    cmp byte ptr [rbx + rax - 1], '/'
    jne 1f
    dec rax
1:  mov rdi, rbx
    mov rsi, rax
    call mem_dup
    mov [rip + g_project], rax
    mov rdi, rax
    call strlen
    mov rdi, [rip + g_project]
    mov rsi, rax
    call path_basename
    mov [rip + g_project_name], rax
    call git_set_project
    call explorer_set_root
    call session_remember_project
    mov dword ptr [rip + g_dirty], 1
    EPILOGUE

# app_on_drop(text, len): files dragged in from another program, as a text/uri-list (a line each,
# "file://host/path" with %xx escapes). A terminal gets their paths typed at its cursor, quoted for
# the shell, as other terminals do; anywhere else they open as tabs (a folder as the project).
FN app_on_drop
    PROLOGUE
    mov r12, rdi
    lea r13, [rdi + rsi]
    lea rdi, [rip + drop_text]
    call sb_clear
.Lod_line:
    cmp r12, r13
    jae .Lod_done
    mov r14, r12
1:  cmp r14, r13
    jae 2f
    mov al, [r14]
    cmp al, 13
    je 2f
    cmp al, 10
    je 2f
    inc r14
    jmp 1b
2:  mov rax, r14
    sub rax, r12
    cmp rax, 8
    jb .Lod_next
    cmp dword ptr [r12], 0x656c6966     # "file"
    jne .Lod_next
    cmp word ptr [r12 + 4], 0x2f3a      # ":/"
    jne .Lod_next
    cmp byte ptr [r12 + 6], '/'
    jne .Lod_next
    lea rsi, [r12 + 7]
3:  cmp rsi, r14                        # past the host
    jae .Lod_next
    cmp byte ptr [rsi], '/'
    je 4f
    inc rsi
    jmp 3b
4:  lea rdi, [rip + drop_path]
    xor ecx, ecx
5:  cmp rsi, r14
    jae 7f
    cmp ecx, 4094
    jae .Lod_next
    movzx eax, byte ptr [rsi]
    inc rsi
    cmp al, '%'
    jne 6f
    lea rdx, [rsi + 2]
    cmp rdx, r14
    ja 6f
    movzx edx, byte ptr [rsi]
    call drop_hex
    js 6f
    mov r8d, edx
    movzx edx, byte ptr [rsi + 1]
    call drop_hex
    js 6f
    shl r8d, 4
    lea eax, [r8 + rdx]
    add rsi, 2
    test eax, eax
    jz .Lod_next
    jmp 61f
6:  movzx eax, byte ptr [rsi - 1]
61: mov [rdi + rcx], al
    inc ecx
    jmp 5b
7:  mov byte ptr [rdi + rcx], 0
    test ecx, ecx
    jz .Lod_next
    cmp dword ptr [rip + g_term_open], 0
    jne 8f
    lea rdi, [rip + drop_path]
    call app_open_path
    jmp .Lod_next
8:  # 'path' and a space, a quote in it as '\''
    lea rdi, [rip + drop_text]
    mov esi, 39
    call sb_push_byte
    lea rbx, [rip + drop_path]
81: movzx esi, byte ptr [rbx]
    test esi, esi
    jz 83f
    inc rbx
    cmp esi, 39
    jne 82f
    lea rdi, [rip + drop_text]
    lea rsi, [rip + .Ldrop_quote]
    call sb_push_cstr
    jmp 81b
82: lea rdi, [rip + drop_text]
    call sb_push_byte
    jmp 81b
83: lea rdi, [rip + drop_text]
    lea rsi, [rip + .Ldrop_end]
    call sb_push_cstr
.Lod_next:
    lea r12, [r14 + 1]
    jmp .Lod_line
.Lod_done:
    mov rsi, [rip + drop_text + SB_len]
    test rsi, rsi
    jz 9f
    mov rdi, [rip + drop_text + SB_ptr]
    call term_tab_paste
9:  mov dword ptr [rip + g_dirty], 1
    EPILOGUE

# drop_hex(edx character) -> edx its value as a hex digit, the sign flag set when it is none
drop_hex:
    sub edx, '0'
    cmp edx, 9
    jbe 1f
    or edx, 32
    sub edx, 'a' - '0' - 10
    cmp edx, 10
    jb 2f
    cmp edx, 15
    ja 2f
1:  test edx, edx
    ret
2:  mov edx, -1
    test edx, edx
    ret
CSTR .Ldrop_quote, "'\\''"
CSTR .Ldrop_end, "' "

# follow_cwd(): the folder the shell shown is in is the project: the tree, git, new files and the next
# launch go by it. The project turns when the shell is seen in another folder than before, so a
# folder opened as the project (Open Folder) stays until the shell moves. A window without a
# project (--empty, --wait) keeps none.
follow_cwd:
    cmp dword ptr [rip + g_term_open], 0
    je 1f
    cmp qword ptr [rip + g_project], 0
    jne 2f
1:  ret
2:  PROLOGUE
    lea rdi, [rip + cwd_now]
    call term_shown_cwd
    test rax, rax
    jle 9f
    lea rdi, [rip + cwd_now]
    lea rsi, [rip + cwd_seen]
    call strcmp_eq
    test eax, eax
    jnz 9f
    lea rdi, [rip + cwd_seen]
    lea rsi, [rip + cwd_now]
    call cstr_copy
    mov rdi, [rip + g_project]
    lea rsi, [rip + cwd_now]
    call strcmp_eq
    test eax, eax
    jnz 9f
    # the same folder by another spelling (the project opened through a symlink) stays as it is
    lea rdi, [rip + cwd_now]
    call file_id
    test rax, rax
    jz 9f
    mov r12, rax
    mov r13, rdx
    mov rdi, [rip + g_project]
    call file_id
    cmp rax, r12
    jne 3f
    cmp rdx, r13
    je 9f
3:  lea rdi, [rip + cwd_now]
    call set_project
    call app_update_title
9:  EPILOGUE

# app_new_window(folder): another raftaar opens the folder in a window of its own (on macOS with a Dock
# icon of its own) and this one keeps its project. It runs this program with the same environment,
# in a session of its own as a copy started from a terminal is, and is reaped when it quits.
# RAFTAAR_NEW_WINDOW names another program to run (tests); without it a headless raftaar starts none.
FN app_new_window
.ifdef WINDOWS
    PROLOGUE
    cmp dword ptr [rip + g_headless], 0
    jne 8f
    call win_new_window
    test eax, eax
    jnz 9f
8:  lea rdi, [rip + .Lnew_window_failed]
    call app_toast
9:  EPILOGUE
.else
    PROLOGUE 32
    mov rbx, rdi
    lea rdi, [rip + .Lenv_new_window]
    call getenv
    test rax, rax
    jz 2f
    cmp byte ptr [rax], 0
    je 2f
    mov r12, rax
    mov rdi, rax
    call strlen
    cmp rax, 4096
    jae 8f
    lea rdi, [rip + nw_exe]
    mov rsi, r12
    call cstr_copy
    jmp 3f
2:  cmp dword ptr [rip + g_headless], 0
    jne 8f
.ifdef MACOS
    lea rdi, [rip + nw_exe]
    mov esi, 4096
    call mac_exe_path
    test rax, rax
    js 8f
.else
    lea rdi, [rip + .Lproc_self_exe]
    lea rsi, [rip + nw_exe]
    mov edx, 4095
    SYS SYS_readlink
    test rax, rax
    jle 8f
    lea rcx, [rip + nw_exe]
    mov byte ptr [rcx + rax], 0
    # " (deleted)": an update replaced the file, and the new version opens the folder
    mov r12, rax
    lea rdi, [rip + nw_exe]
    mov rsi, rax
    lea rdx, [rip + .Ldeleted]
    mov ecx, 10
    call str_ends
    test eax, eax
    jz 1f
    lea rcx, [rip + nw_exe]
    mov byte ptr [rcx + r12 - 10], 0
1:
.endif
3:  lea rdi, [rip + .Ldevnull]
    mov esi, O_RDWR | O_CLOEXEC
    xor edx, edx
    SYS SYS_open
    test rax, rax
    js 8f
    mov r12d, eax
    lea rax, [rip + nw_exe]
    mov [rsp], rax
    mov [rsp + 8], rbx
    mov qword ptr [rsp + 16], 0
    lea rdi, [rsp]
    mov rsi, [rip + g_envp]
    xor edx, edx
    mov ecx, r12d
    mov r8d, r12d
    mov r9d, r12d
    push 1                      # a new session; the terminal ioctl on /dev/null fails, so none
    push 1
    call proc_spawn
    add rsp, 16
    mov r13, rax
    mov edi, r12d
    SYS SYS_close
    test r13, r13
    jle 8f
    mov edi, r13d
    call reap_later
    EPILOGUE
8:  lea rdi, [rip + .Lnew_window_failed]
    call app_toast
    EPILOGUE
.endif

# app_switch_project(path): this window takes up another folder. The project's open files are
# remembered, unsaved ones are asked about (Cancel keeps the project), then they are closed and the
# folder opens with its last session.
FN app_switch_project
    PROLOGUE
    mov rbx, rdi
    mov rsi, [rip + g_project]
    test rsi, rsi
    jz 1f
.ifdef WINDOWS
    call win_path_equal
.else
    call strcmp_eq
.endif
    test eax, eax
    jnz 8f
1:  mov rdi, rbx
    call strlen
    cmp rax, 4000
    ja 9f
    lea rdi, [rip + switch_path]
    mov rsi, rbx
    call cstr_copy
    # before the questions: an answer closes that file, and a quit meanwhile must not save again
    call session_save
    mov dword ptr [rip + g_session_final], 1
    mov dword ptr [rip + switch_pending], 1
    call switch_continue
    jmp 9f
8:  # the same folder: a file's folder becomes the project itself, its last session joining the tabs
    cmp dword ptr [rip + g_project_adopted], 0
    je 9f
    mov dword ptr [rip + g_project_adopted], 0
    mov dword ptr [rip + panels_hidden], 0
    call app_sync_panels
    call session_remember_project
    call session_restore
    call app_update_title
9:  EPILOGUE

# app_adopt_folder(file): a file opened in a window without a project brings in its folder as one,
# for the explorer, new files, git and the terminal (see g_project_adopted). Not with --wait: a
# program waiting for an editor (git's commit message) wants just the file.
app_adopt_folder:
    PROLOGUE
    cmp qword ptr [rip + g_project], 0
    jne 9f
    cmp dword ptr [rip + g_wait], 0
    jne 9f
    mov rbx, rdi
    call strlen
    mov rdi, rbx
    mov rsi, rax
    call path_dirlen
    test rax, rax
    jnz 1f
    mov eax, 1                  # "/"
1:  mov rdi, rbx
    mov rsi, rax
    call mem_dup
    mov r12, rax
    mov rdi, rax
    call file_is_dir
    test eax, eax
    jz 8f
    mov dword ptr [rip + g_project_adopted], 1
    mov rdi, r12
    call set_project
8:  mov rdi, r12
    call mem_free
9:  EPILOGUE

# switch_continue(): the next unsaved file asks first; with none left the project changes
switch_continue:
    PROLOGUE
    cmp dword ptr [rip + switch_pending], 0
    je 9f
    mov edi, 3
    call ask_unsaved
    test eax, eax
    jnz 9f
    mov dword ptr [rip + switch_pending], 0
    call close_tabs_now
    call closed_clear           # the last project's tabs are not this one's to reopen
    mov byte ptr [rip + g_explorer_dir], 0
    mov byte ptr [rip + g_explorer_target], 0
    lea rdi, [rip + switch_path]
    call app_set_project
    # the new project saves its own session
    mov dword ptr [rip + g_session_final], 0
    call session_restore
    call app_update_title
    mov dword ptr [rip + g_focus], FOCUS_EDITOR
9:  mov dword ptr [rip + g_dirty], 1
    EPILOGUE

# project_menu_open(x, y): Open Folder, Open File and the recent folders, under the project name
project_menu_open:
    PROLOGUE
    mov r12d, edi
    mov r13d, esi
    lea rbx, [rip + pm_items]
    lea rax, [rip + .Lpm_folder]
    mov [rbx], rax
    lea rax, [rip + cmd_open_folder]
    mov [rbx + 8], rax
    lea rax, [rip + .Lpm_file]
    mov [rbx + 16], rax
    lea rax, [rip + cmd_open_file]
    mov [rbx + 24], rax
    add rbx, 32
    call session_recent
    mov r14d, eax
    test r14d, r14d
    jz 2f
    # a line, then the folders
    lea rax, [rip + .Lpm_line]
    mov [rbx], rax
    mov qword ptr [rbx + 8], 0
    add rbx, 16
    xor r15d, r15d
1:  cmp r15d, r14d
    jae 2f
    mov eax, r15d
    shl eax, 12
    lea rcx, [rip + g_recent_label]
    add rcx, rax
    mov [rbx], rcx
    lea rax, [rip + recent_open]
    mov [rbx + 8], rax
    add rbx, 16
    inc r15d
    jmp 1b
2:  mov qword ptr [rbx], 0
    mov qword ptr [rbx + 8], 0
    lea rdi, [rip + pm_items]
    mov esi, r12d
    mov edx, r13d
    call ctx_menu_open
    mov dword ptr [rip + g_menu_keys], 1
    EPILOGUE

# recent_open(): the recent folder picked in the project menu (the items after the line): this window
# takes it up, or with Shift held another window opens it
recent_open:
    mov eax, [rip + g_menu_index]
    sub eax, PM_RECENT
    js 1f
    shl eax, 12
    lea rdi, [rip + g_recent_path]
    add rdi, rax
    test dword ptr [rip + g_mods], MOD_SHIFT
    jnz app_new_window
    jmp app_switch_project
1:  ret

# ---------------- tabs ----------------

# app_restart_paths(executable) -> allocated argv. Project sessions reopen by folder;
# standalone windows keep their normal file tabs across an update restart.
FN app_restart_paths
    PROLOGUE
    mov rbx, rdi
    cmp dword ptr [rip + g_restart], 0
    je 8f
    mov r12, [rip + restart_paths]
    test r12, r12
    jz 8f
    xor r13d, r13d
5:  inc r13
    cmp qword ptr [r12 + r13*8], 0
    jne 5b
    lea rdi, [r13*8 + 8]
    call mem_alloc
    mov r14, rax
    mov rdi, rax
    mov rsi, r12
    lea rdx, [r13*8 + 8]
    call memcpy
    mov [r14], rbx
    mov rax, r14
    EPILOGUE
8:
    mov rdi, [rip + g_tabs + VEC_len]
    add rdi, 3
    shl rdi, 3
    call mem_alloc
    mov r14, rax
    mov [r14], rbx
    mov r13d, 1
    mov rax, [rip + g_project]
    test rax, rax
    jz 1f
    cmp dword ptr [rip + g_project_adopted], 0
    jne 1f                      # a file's folder comes back with the file
    mov [r14 + r13*8], rax
    inc r13
    jmp 4f
1:  xor r12d, r12d
2:  cmp r12, [rip + g_tabs + VEC_len]
    jae 4f
    mov rdi, r12
    call tab_at
    cmp qword ptr [rax + TAB_kind], TAB_DOC
    je 21f
    cmp qword ptr [rax + TAB_kind], TAB_IMAGE
    jne 3f
21:
    mov rax, [rax + TAB_doc]
    mov rax, [rax + DOC_path]
    test rax, rax
    jz 3f
    mov [r14 + r13*8], rax
    inc r13
3:  inc r12
    jmp 2b
4:  cmp r13d, 1
    jne 41f
    lea rax, [rip + .Lrestart_empty]
    mov [r14 + r13*8], rax
    inc r13
41: mov qword ptr [r14 + r13*8], 0
    mov rax, r14
    EPILOGUE

# Snapshot before quit confirmations close dirty tabs. Owned path copies survive
# those closes; cancelling and requesting another restart replaces the snapshot.
FN app_remember_restart
    PROLOGUE
    mov r12, [rip + restart_paths]
    test r12, r12
    jz 3f
    mov r13d, 1
1:  mov rdi, [r12 + r13*8]
    test rdi, rdi
    jz 2f
    call mem_free
    inc r13
    jmp 1b
2:  mov rdi, r12
    call mem_free
3:  mov qword ptr [rip + restart_paths], 0
    lea rdi, [rip + .Lraftaar]
    call app_restart_paths
    mov r12, rax
    mov r13d, 1
4:  mov rbx, [r12 + r13*8]
    test rbx, rbx
    jz 5f
    mov rdi, rbx
    call strlen
    lea rsi, [rax + 1]
    mov rdi, rbx
    call mem_dup
    mov [r12 + r13*8], rax
    inc r13
    jmp 4b
5:  mov [rip + restart_paths], r12
    EPILOGUE

# tab_at(i) -> TAB*
FN tab_at
    imul rax, rdi, TAB_SIZE
    add rax, [rip + g_tabs + VEC_ptr]
    ret

# app_sync_doc(): g_doc and g_file from the active tab, and the terminal it shows
FN app_sync_doc
    push rbx
    xor ebx, ebx                # the active tab's terminal, or 0
    mov qword ptr [rip + g_doc], 0
    mov qword ptr [rip + g_file], 0
    mov rdi, [rip + g_tab_cur]
    test rdi, rdi
    js 1f
    call tab_at
    mov rcx, [rax + TAB_kind]
    cmp rcx, TAB_TERM
    jne 0f
    mov rbx, [rax + TAB_term]
0:  cmp qword ptr [rax + TAB_doc], 0
    je 1f
    mov rdx, [rax + TAB_doc]
    mov [rip + g_file], rdx
    cmp rcx, TAB_DOC
    jne 2f
    mov [rip + g_doc], rdx
1:  # the view's copies of an image are only kept while it is shown
    call iv_cache_free
2:  mov rdi, rbx
    call term_tab_sync
    call focus_sync
    mov dword ptr [rip + g_dirty], 1
    pop rbx
    ret

# focus_sync(): the active tab's view has the keys as FOCUS_EDITOR, a terminal's as FOCUS_TERMINAL:
#   whatever hands the focus back to the editor (a tab activated, the palette or a dialog closed)
#   hands it to the terminal when that is what the tab shows
focus_sync:
    mov eax, [rip + g_focus]
    cmp eax, FOCUS_EDITOR
    je 1f
    cmp eax, FOCUS_TERMINAL
    jne 9f
1:  mov eax, FOCUS_EDITOR
    cmp dword ptr [rip + g_term_open], 0
    je 2f
    mov eax, FOCUS_TERMINAL
2:  mov [rip + g_focus], eax
9:  ret

# app_image() -> the active image view, or 0
FN app_image
    xor eax, eax
    mov rcx, [rip + g_file]
    test rcx, rcx
    jz 1f
    mov rax, [rcx + DOC_img]
1:  ret

FN app_activate_tab
    push rdi
    call vim_leave
    call term_note_back
    pop rdi
    mov [rip + g_tab_cur], rdi
    call mark_shown
    mov dword ptr [rip + g_exp_reveal], 1
    mov dword ptr [rip + g_focus], FOCUS_EDITOR     # a terminal's tab: FOCUS_TERMINAL (focus_sync)
    call app_sync_doc
    call watch_show
    mov dword ptr [rip + g_tabscroll_reveal], 1
    call ed_touch
    jmp app_update_title

# app_update_title(): window title "name — project"
FN app_update_title
    PROLOGUE
    # the window takes its title once the command line or session is open: a session restoring ten
    # tabs set it ten times before the first frame (half a millisecond each on macOS)
    cmp dword ptr [rip + g_started], 0
    je 9f
    lea rdi, [rip + tmp_sb]
    call sb_clear
    mov rbx, [rip + g_file]
    test rbx, rbx
    jz 1f
    lea rdi, [rip + tmp_sb]
    mov rsi, [rbx + DOC_name]
    call sb_push_cstr
    lea rdi, [rip + tmp_sb]
    lea rsi, [rip + .Ldash]
    call sb_push_cstr
1:  mov rsi, [rip + g_project_name]
    test rsi, rsi
    jnz 2f
    lea rsi, [rip + .Lraftaar]
2:  lea rdi, [rip + tmp_sb]
    call sb_push_cstr
    mov rdi, [rip + tmp_sb + SB_ptr]
    PCALL P_title
9:  EPILOGUE

# app_find_tab(path) -> index or -1
FN app_find_tab
    PROLOGUE
    mov r12, rdi
    xor ebx, ebx
1:  cmp rbx, [rip + g_tabs + VEC_len]
    jae 3f
    mov rdi, rbx
    call tab_at
    mov rax, [rax + TAB_doc]
    test rax, rax
    jz 2f
    mov rdi, [rax + DOC_path]
    test rdi, rdi
    jz 2f
    mov rsi, r12
.ifdef WINDOWS
    call win_path_equal
.else
    call strcmp_eq
.endif
    test eax, eax
    jnz 4f
2:  inc rbx
    jmp 1b
3:  mov rax, -1
    EPILOGUE
4:  mov rax, rbx
    EPILOGUE

# app_path_inside(path, dir) -> eax 1 when path is dir or names something inside it, compared as
#   app_find_tab compares paths, and rdx the length of path's part that names dir
.ifdef WINDOWS
# Windows: each part of path that ends at a separator (or all of it), after its root, against dir by
# win_path_equal: spellings that are the same without case may differ in length
FN app_path_inside
    PROLOGUE 4096
    mov r12, rdi
    mov r13, rsi
    call strlen
    mov r15, rax
    mov rdi, r12
    call path_rootlen
    mov r14, rax
    test r14, r14
    jnz 1f
    mov r14d, 1
1:  cmp r14, r15
    ja 8f
    je 2f
    movzx eax, byte ptr [r12 + r14]
    cmp eax, '/'
    je 2f
    cmp eax, 92
    je 2f
3:  inc r14
    jmp 1b
2:  cmp r14, 4096
    jae 8f
    mov rdi, rsp
    mov rsi, r12
    mov rcx, r14
    rep movsb
    mov byte ptr [rdi], 0
    mov rdi, rsp
    mov rsi, r13
    call win_path_equal
    test eax, eax
    jz 3b
    mov eax, 1
    mov rdx, r14
    EPILOGUE
8:  xor eax, eax
    EPILOGUE
.else
FN app_path_inside
    PROLOGUE
    mov r12, rdi
    mov r13, rsi
    mov rdi, rsi
    call strlen
    mov r14, rax
    test r14, r14
    jz 8f
    cmp r14, 1                  # a folder written with its slash, but not / itself
    jbe 1f
    cmp byte ptr [r13 + r14 - 1], '/'
    jne 1f
    dec r14
1:  mov rdi, r12
    call strlen
    mov r15, rax
    cmp r15, r14
    jb 8f
    movzx eax, byte ptr [r12 + r14]
    test eax, eax
    jz 2f
    cmp eax, '/'
    je 2f
    cmp byte ptr [r13 + r14 - 1], '/'   # under a root such as /
    jne 8f
2:  mov rdi, r12
    mov rsi, r15
    mov rdx, r13
    mov rcx, r14
    call str_starts
    mov rdx, r14
    EPILOGUE
8:  xor eax, eax
    EPILOGUE
.endif

# app_retarget_tabs(old, new): after a rename, the tabs of old, or of the files inside it when it
#   is a folder, take their paths under new
FN app_retarget_tabs
    PROLOGUE
    mov r12, rdi
    mov r13, rsi
    xor ebx, ebx
2:  cmp rbx, [rip + g_tabs + VEC_len]
    jae 9f
    mov rdi, rbx
    call tab_at
    mov r15, [rax + TAB_doc]
    test r15, r15
    jz 3f
    mov rdi, [r15 + DOC_path]
    test rdi, rdi
    jz 3f
    mov rsi, r12
    call app_path_inside
    test eax, eax
    jz 3f
    mov r14, rdx                # the tab's own spelling of old ends there
    lea rdi, [rip + tmp_sb]
    call sb_clear
    mov rdi, r13                # the new name without a separator at its end ("e/" in the prompt)
    call strlen
    mov rdx, rax
4:  cmp rdx, 1
    jbe 5f
    cmp byte ptr [r13 + rdx - 1], '/'
.ifdef WINDOWS
    je 41f
    cmp byte ptr [r13 + rdx - 1], 92
.endif
    jne 5f
41: dec rdx
    jmp 4b
5:  lea rdi, [rip + tmp_sb]
    mov rsi, r13
    call sb_push
    lea rdi, [rip + tmp_sb]
    mov rsi, [r15 + DOC_path]
    add rsi, r14
    call sb_push_cstr
    mov rdi, r15
    mov rsi, [rip + tmp_sb + SB_ptr]
    call doc_set_path
3:  inc rbx
    jmp 2b
9:  call app_update_title
    mov dword ptr [rip + g_dirty], 1
    EPILOGUE

# app_open_startup_path(path): initial desktop events follow argv startup precedence.
FN app_open_startup_path
    # Finder delivers its initial URLs during AppKit startup. Queue them with argv so
    # the same project/session precedence applies; later events open ordinary tabs.
    cmp dword ptr [rip + g_started], 0
    jne app_open_path
    PROLOGUE
    mov rbx, rdi
    call strlen
    lea rsi, [rax + 1]
    mov rdi, rbx
    call mem_dup
    mov rbx, rax
    lea rdi, [rip + g_start_paths]
    mov esi, 8
    call vec_push
    mov [rax], rbx
    EPILOGUE
# app_open_file(path) -> tab index or -1
FN app_open_file
    PROLOGUE 16
    mov r12, rdi
    call app_find_tab
    test rax, rax
    js 1f
    mov rdi, rax
    mov rbx, rax
    call app_activate_tab
    mov rax, rbx
    EPILOGUE
1:  # regular files only: opening a pipe or a device blocks until the other end comes (a missing
    # file can still be created)
    mov rdi, r12
    call file_type
    test eax, eax
    jz 12f
    cmp eax, 0x8000
    je 12f
    lea rdi, [rip + .Lnot_regular]
    call app_toast
    mov rax, -1
    EPILOGUE
12: mov r14d, TAB_DOC
    call doc_new
    mov rbx, rax
    # images open in an image tab, decoded when first shown
    mov rdi, r12
    call image_probe
    test eax, eax
    jz 11f
    mov r14d, TAB_IMAGE
    mov rdi, rbx
    mov rsi, r12
    call doc_set_path
    mov rdi, r12
    call file_stamp
    mov [rbx + DOC_mtime], rax
    call iv_new
    mov [rbx + DOC_img], rax
    jmp 3f
11: mov rdi, rbx
    mov rsi, r12
    call doc_load
    cmp rax, -1000
    je .Lof_binary
    cmp rax, -2                # a missing file can be created; other read errors cannot
    je 2f
    test rax, rax
    jns 2f
    lea r15, [rip + .Lopen_failed]
    jmp .Lof_failed
.Lof_binary:
    lea r15, [rip + .Lbinary]
.Lof_failed:
    mov rdi, rbx
    call doc_free
    mov rdi, r15
    call app_toast
    mov rax, -1
    EPILOGUE
2:  mov rdi, rbx
    call app_detect_lang
    mov rdi, rbx
    call git_doc_opened
    # replace an untouched untitled tab
    mov rax, [rip + g_tab_cur]
    test rax, rax
    js 3f
    mov rdi, rax
    call tab_at
    cmp qword ptr [rax + TAB_kind], TAB_DOC
    jne 3f
    mov rcx, [rax + TAB_doc]
    cmp qword ptr [rcx + DOC_path], 0
    jne 3f
    mov rdi, rcx
    push rax
    push rcx
    call doc_len
    pop rcx
    pop rdx
    test rax, rax
    jnz 3f
    mov [rdx + TAB_doc], rbx
    mov [rdx + TAB_kind], r14
    mov rdi, rcx
    call doc_free
    mov rdi, [rip + g_tab_cur]
    mov r13, rdi
    call app_activate_tab
    mov rax, r13
    EPILOGUE
3:  mov rdi, rbx
    mov esi, r14d
    call app_add_tab
    EPILOGUE

# app_add_tab(doc, kind) -> index (inserted after the current tab, activated)
FN app_add_tab
    xor edx, edx
# add_tab(doc, kind, terminal session) -> index: a tab of its own after the active one, or with
#   g_split_next set a pane of the active tab, beside the view that has the keys
add_tab:
    PROLOGUE 16
    mov rbx, rdi
    mov r12d, esi
    mov r15, rdx
    lea rdi, [rip + g_tabs]
    mov esi, TAB_SIZE
    call vec_push
    mov r13, [rip + g_tabs + VEC_len]
    dec r13                     # new slot index
    mov r14, [rip + g_tab_cur]
    mov qword ptr [rsp], 0      # the view split, 0: a tab of its own
    test r14, r14
    js 12f
    mov rdi, r14
    call tab_at
    mov rcx, [rax + TAB_group]
    mov [rsp + 8], rcx
    cmp dword ptr [rip + g_split_next], 0
    je 11f
    mov rcx, [rax + TAB_id]
    mov [rsp], rcx
    jmp 12f
11: # past the other panes of the active tab
    lea rdi, [r14 + 1]
    cmp rdi, r13
    jae 12f
    call tab_at
    mov rcx, [rsp + 8]
    cmp [rax + TAB_group], rcx
    jne 12f
    inc r14
    jmp 11b
12: inc r14                     # insert position
    # shift [r14, r13) right by one
    mov rcx, r13
1:  cmp rcx, r14
    jbe 2f
    mov rdi, rcx
    call tab_at
    lea rsi, [rax - TAB_SIZE]
    TAB_COPY rax, rsi
    dec rcx
    jmp 1b
2:  mov rdi, r14
    call tab_at
    mov [rax + TAB_kind], r12
    mov [rax + TAB_doc], rbx
    mov [rax + TAB_term], r15
    mov qword ptr [rax + TAB_flags], 0
    inc qword ptr [rip + tab_seq]
    mov rsi, [rip + tab_seq]
    mov [rax + TAB_id], rsi
    mov rdi, [rsp]
    test rdi, rdi
    jz 3f
    mov rcx, [rsp + 8]
    mov [rax + TAB_group], rcx
    mov edx, [rip + g_split_next]
    call pane_split
    test eax, eax
    jnz 4f
    mov rdi, r14                # no room for another pane: a tab of its own
    call tab_at
3:  inc qword ptr [rip + group_seq]
    mov rcx, [rip + group_seq]
    mov [rax + TAB_group], rcx
4:  mov dword ptr [rip + g_split_next], 0
    mov rdi, r14
    call app_activate_tab
    mov rax, r14
    EPILOGUE

# view_index(TAB_id) -> index or -1
FN view_index
    xor eax, eax
    mov rcx, [rip + g_tabs + VEC_ptr]
1:  cmp rax, [rip + g_tabs + VEC_len]
    jae 3f
    cmp [rcx + TAB_id], rdi
    je 9f
    add rcx, TAB_SIZE
    inc rax
    jmp 1b
3:  mov rax, -1
9:  ret

# group_first(i) -> the first view of the title bar's tab that view i is a pane of
group_first:
    push rdi
    call tab_at
    mov rdx, rax
    mov rcx, [rdx + TAB_group]
    pop rax
1:  test rax, rax
    jz 9f
    cmp [rdx - TAB_SIZE + TAB_group], rcx
    jne 9f
    sub rdx, TAB_SIZE
    dec rax
    jmp 1b
9:  ret

# group_last(i) -> its last view
group_last:
    push rdi
    call tab_at
    mov rdx, rax
    mov rcx, [rdx + TAB_group]
    pop rax
1:  lea rsi, [rax + 1]
    cmp rsi, [rip + g_tabs + VEC_len]
    jae 9f
    cmp [rdx + TAB_SIZE + TAB_group], rcx
    jne 9f
    add rdx, TAB_SIZE
    inc rax
    jmp 1b
9:  ret

# group_shown(i) -> the view of that tab which had the keys last
group_shown:
    push rbx
    push r12
    push r13
    mov r12, rdi
    call group_last
    mov r13, rax
    mov rdi, r12
    call group_first
    mov rbx, rax
    mov rdi, rax
    call tab_at
    mov rcx, rbx
1:  test qword ptr [rax + TAB_flags], TABF_SHOWN
    jnz 2f
    add rax, TAB_SIZE
    inc rcx
    cmp rcx, r13
    jbe 1b
    mov rcx, rbx
2:  mov rax, rcx
    pop r13
    pop r12
    pop rbx
    ret

# mark_shown(): the active view is the one its tab shows in the title bar
mark_shown:
    push rbx
    push r12
    push r13
    mov r12, [rip + g_tab_cur]
    test r12, r12
    js 9f
    mov rdi, r12
    call group_last
    mov r13, rax
    mov rdi, r12
    call group_first
    mov rbx, rax
    mov rdi, rax
    call tab_at
1:  and qword ptr [rax + TAB_flags], ~TABF_SHOWN
    cmp rbx, r12
    jne 2f
    or qword ptr [rax + TAB_flags], TABF_SHOWN
2:  add rax, TAB_SIZE
    inc rbx
    cmp rbx, r13
    jbe 1b
9:  pop r13
    pop r12
    pop rbx
    ret

# app_drop_file(path, view id, SPLIT_* or 0): a file let go over a pane: beside it, in a pane of its
#   own, or (over its middle) in a tab as any file opened
FN app_drop_file
    PROLOGUE
    mov r12, rdi
    mov r13, rsi
    mov r14d, edx
    mov rdi, r13
    call view_index
    test rax, rax
    js 9f
    mov rbx, rax
    test r14d, r14d
    jz 2f
    mov rdi, r12
    call app_find_tab
    test rax, rax
    js 1f
    cmp rax, rbx
    je 9f                       # onto its own pane
    mov rdi, rax
    mov rsi, r13
    mov edx, r14d
    call app_move_view
    jmp 9f
1:  mov rdi, rbx
    call app_activate_tab
    mov [rip + g_split_next], r14d
    mov rdi, r12
    call app_open_path
    mov dword ptr [rip + g_split_next], 0
    jmp 9f
2:  mov rdi, rbx
    call app_activate_tab
    mov rdi, r12
    call app_open_path
9:  EPILOGUE

# app_move_view(i, view id, SPLIT_*): view i leaves its tab and becomes a pane beside that view
app_move_view:
    PROLOGUE 64
    mov r12, rdi
    mov r13, rsi
    mov r14d, edx
    call tab_at
    TAB_COPY rsp, rax
    mov rdi, [rsp + TAB_id]
    call pane_remove
    # its slot closes up
    mov rcx, r12
1:  lea rdx, [rcx + 1]
    cmp rdx, [rip + g_tabs + VEC_len]
    jae 2f
    mov rdi, rcx
    call tab_at
    lea rsi, [rax + TAB_SIZE]
    TAB_COPY rax, rsi
    inc rcx
    jmp 1b
2:  dec qword ptr [rip + g_tabs + VEC_len]
    mov rdi, r13
    call view_index
    mov rbx, rax
    mov rdi, rax
    call tab_at
    mov r15, [rax + TAB_group]
    # and opens again after the pane it joins
    lea rdi, [rip + g_tabs]
    mov esi, TAB_SIZE
    call vec_push
    mov rcx, [rip + g_tabs + VEC_len]
    dec rcx
3:  lea rdx, [rbx + 1]
    cmp rcx, rdx
    jbe 4f
    mov rdi, rcx
    call tab_at
    lea rsi, [rax - TAB_SIZE]
    TAB_COPY rax, rsi
    dec rcx
    jmp 3b
4:  lea rdi, [rbx + 1]
    call tab_at
    TAB_COPY rax, rsp
    mov [rax + TAB_group], r15
    mov qword ptr [rax + TAB_flags], 0
    mov rdi, r13
    mov rsi, [rsp + TAB_id]
    mov edx, r14d
    mov ecx, r15d
    call pane_split
    test eax, eax
    jnz 5f
    lea rdi, [rbx + 1]
    call tab_at
    inc qword ptr [rip + group_seq]
    mov rcx, [rip + group_seq]
    mov [rax + TAB_group], rcx
5:  lea rdi, [rbx + 1]
    call app_activate_tab
    EPILOGUE

# app_place_tab(i): the active tab moves to place i in the strip (the last place at most), the tabs
#   between closing up behind it
FN app_place_tab
    PROLOGUE 48
    mov r14, rdi
    call panes_any              # tabs with panes keep their views together: nothing moves
    test eax, eax
    jnz 9f
    mov rdi, r14
    mov r12, [rip + g_tab_cur]
    test r12, r12
    js 9f
    mov r13, [rip + g_tabs + VEC_len]
    dec r13
    cmp rdi, r13
    cmovb r13, rdi
    mov rdi, r12
    call tab_at
    TAB_COPY rsp, rax
1:  cmp r12, r13
    je 3f
    mov rdi, r12
    call tab_at
    # the neighbor toward the new place moves into this slot
    mov rcx, TAB_SIZE
    mov rsi, 1
    cmp r12, r13
    jb 2f
    neg rcx
    neg rsi
2:  add r12, rsi
    lea rsi, [rax + rcx]
    TAB_COPY rax, rsi
    jmp 1b
3:  mov rdi, r13
    call tab_at
    TAB_COPY rax, rsp
    mov [rip + g_tab_cur], r13
    mov dword ptr [rip + g_tabscroll_reveal], 1
    mov dword ptr [rip + g_dirty], 1
9:  EPILOGUE

# app_tab_label(i) -> cstr: the name the tab strip shows
FN app_tab_label
    call tab_at
    mov rcx, rax
    mov rax, [rcx + TAB_doc]
    test rax, rax
    jz 1f
    mov rax, [rax + DOC_name]
    ret
1:  cmp qword ptr [rcx + TAB_kind], TAB_TERM
    jne 3f
    mov rdi, [rcx + TAB_term]
    push rax
    call term_tab_label
    pop rcx
    # a title with a path ("user@host: ~/work/site") names its last folder alone
    mov rdx, rax
    xor r8d, r8d                # after the last '/', and after the last ':'
    xor r9d, r9d
4:  mov cl, [rdx]
    test cl, cl
    jz 6f
    inc rdx
    cmp cl, '/'
    jne 5f
    cmp byte ptr [rdx], 0
    je 4b
    mov r8, rdx
    jmp 4b
5:  cmp cl, ':'
    jne 4b
51: cmp byte ptr [rdx], ' '
    jne 52f
    inc rdx
    jmp 51b
52: cmp byte ptr [rdx], 0
    je 4b
    mov r9, rdx
    jmp 4b
6:  test r8, r8
    cmovz r8, r9
    test r8, r8
    cmovnz rax, r8
    ret
3:  lea rax, [rip + .Lhome_tab]
    cmp qword ptr [rcx + TAB_kind], TAB_HOME
    je 2f
    lea rax, [rip + .Lsettings]
    cmp qword ptr [rcx + TAB_kind], TAB_GIT
    jne 2f
    lea rax, [rip + .Lgit_tab]
2:  ret

# app_detect_lang(doc)
FN app_detect_lang
    PROLOGUE
    mov rbx, rdi
    mov rdi, rbx
    xor esi, esi
    call doc_line_text
    mov r12, rax
    mov r13, rdx
    mov rdi, [rbx + DOC_path]
    test rdi, rdi
    jnz 1f
    lea rdi, [rip + .Lempty]
1:  mov rsi, r12
    mov rdx, r13
    call syntax_detect
    mov [rbx + DOC_lang], rax
    mov qword ptr [rbx + DOC_svalid], 0
    EPILOGUE

# cmd_new_file()
FN cmd_new_file
    call doc_new
    mov rdi, rax
    mov esi, TAB_DOC
    jmp app_add_tab

# app_close_tab_now(i): close without asking
FN app_close_tab_now
    PROLOGUE
    mov r12, rdi
    cmp r12, [rip + g_tab_cur]
    jne .Lclose_note
    call vim_leave              # out of visual mode, as leaving the tab is
.Lclose_note:
    mov rdi, r12
    call tab_at
    cmp qword ptr [rax + TAB_kind], TAB_TERM
    jne .Lclose_file
    mov rdi, [rax + TAB_term]   # its shell ends with it: not a tab Reopen Closed Tab brings back
    call term_end
    jmp .Lclose_noted
.Lclose_file:
    mov rdi, r12
    call closed_note            # for Reopen Closed Tab
.Lclose_noted:
    mov rdi, r12
    call tab_at
    xor r13d, r13d
    cmp r12, [rip + g_tab_cur]
    jne .Lclose_focus_saved
    cmp qword ptr [rax + TAB_kind], TAB_SETTINGS
    jne .Lclose_focus_saved
    cmp dword ptr [rip + g_focus], FOCUS_SETTINGS
    jne .Lclose_focus_saved
    mov r13d, 1
.Lclose_focus_saved:
    mov rbx, [rax + TAB_doc]
    mov rdi, [rax + TAB_id]     # its pane closes: one beside it takes the room, and the keys
    call pane_remove
    mov r14, rax
    test rbx, rbx
    jz 1f
    mov rdi, rbx
    call vim_forget
    mov rdi, rbx
    call doc_free
1:  # remove slot
    mov rcx, r12
2:  lea rdx, [rcx + 1]
    cmp rdx, [rip + g_tabs + VEC_len]
    jae 3f
    mov rdi, rcx
    call tab_at
    lea rsi, [rax + TAB_SIZE]
    TAB_COPY rax, rsi
    inc rcx
    jmp 2b
3:  dec qword ptr [rip + g_tabs + VEC_len]
    mov rax, [rip + g_tab_cur]
    cmp rax, r12
    jb 4f
    ja 5f
    # closed the active one: keep index (next tab) or step back
    cmp rax, [rip + g_tabs + VEC_len]
    jb 4f
5:  dec rax
4:  mov rdi, rax
    cmp qword ptr [rip + g_tabs + VEC_len], 0
    jne 6f
    mov rdi, -1
6:  mov [rip + g_tab_cur], rdi
    test rdi, rdi
    js 63f
    test r14, r14
    jz 61f
    mov rdi, r14
    call view_index
    test rax, rax
    jns 62f
61: mov rdi, [rip + g_tab_cur]  # another tab: the pane of it that had the keys
    call group_shown
62: mov [rip + g_tab_cur], rax
    call mark_shown
63: test r13d, r13d
    jz .Lclose_focus_restored
    mov dword ptr [rip + g_focus], FOCUS_EDITOR
.Lclose_focus_restored:
    call app_sync_doc
    call app_update_title
    EPILOGUE

# app_close_tab(i): ask when modified, or when a program runs in its terminal; a terminal takes the
#   welcome page's place; raftaar closes with its last tab
FN app_close_tab
    PROLOGUE
    mov rbx, rdi
    call tab_at
    cmp qword ptr [rax + TAB_kind], TAB_HOME
    je .Lct_home
    cmp qword ptr [rax + TAB_kind], TAB_TERM
    je .Lct_term
    cmp qword ptr [rax + TAB_kind], TAB_DOC
    jne 1f
    mov rdi, [rax + TAB_doc]
    call doc_dirty
    test eax, eax
    jz 1f
    mov [rip + dlg_tab], rbx
    mov dword ptr [rip + dlg_kind], 1
    mov dword ptr [rip + g_focus], FOCUS_DIALOG
    mov rdi, rbx
    call app_activate_tab
    mov dword ptr [rip + g_focus], FOCUS_DIALOG
    EPILOGUE
1:  mov rdi, rbx
    call app_close_tab_now
    call quit_if_empty
    EPILOGUE
.Lct_term:
    mov r12, [rax + TAB_term]
    mov rdi, r12
    call term_busy
    test eax, eax
    jz 1b
    mov [rip + dlg_term], r12
    mov rdi, rbx
    call app_activate_tab
    lea rdi, [rip + .Lq_term]
    lea rsi, [rip + .Lq_term_text]
    lea rdx, [rip + .Lb_term]
    lea rcx, [rip + term_close_confirmed]
    call app_confirm
    EPILOGUE
.Lct_home:
    # the terminal opens after it, and has the keys once the page is gone
    mov rdi, rbx
    call app_activate_tab
    call cmd_new_terminal
    jmp 1b

# app_close_tab_gone(i): close without asking, as its own command does (:q!): raftaar closes with its last tab
FN app_close_tab_gone
    push rbx
    call app_close_tab_now
    call quit_if_empty
    pop rbx
    ret

# term_close_confirmed(): Close Terminal: the terminal asked about, if it is still there
term_close_confirmed:
    push rbx
    mov rdi, [rip + dlg_term]
    call term_tab
    test rax, rax
    js 1f
    mov rdi, rax
    call app_close_tab_now
    call quit_if_empty
1:  pop rbx
    ret

# quit_if_empty(): the last tab was closed: raftaar closes with it (a headless run goes on, for its script)
quit_if_empty:
    cmp qword ptr [rip + g_tabs + VEC_len], 0
    jne 1f
    cmp dword ptr [rip + g_headless], 0
    jne 1f
    jmp cmd_quit
1:  ret

# terms_busy() -> eax the terminals a program runs in
terms_busy:
    PROLOGUE
    xor r12d, r12d
    xor ebx, ebx
1:  cmp rbx, [rip + g_tabs + VEC_len]
    jae 9f
    mov rdi, rbx
    call tab_at
    inc rbx
    cmp qword ptr [rax + TAB_kind], TAB_TERM
    jne 1b
    mov rdi, [rax + TAB_term]
    call term_busy
    add r12d, eax
    jmp 1b
9:  mov eax, r12d
    EPILOGUE

# quit_confirmed(): Quit, with programs running in terminals
quit_confirmed:
    mov dword ptr [rip + g_quit], 1
    ret

FN cmd_close_tab
    mov rdi, [rip + g_tab_cur]
    test rdi, rdi
    js 1f
    jmp app_close_tab
1:  ret

# cmd_close_all: close every tab but the terminals, whose programs go on running. The first modified
# doc asks, and each answer that closes it comes back here for the next; a cancel stops, with the tabs
# not closed yet still open
FN cmd_close_all
    PROLOGUE
    mov edi, 5
    call ask_unsaved
    test eax, eax
    jnz 9f
    call close_tabs_now
    call quit_if_empty
9:  EPILOGUE

# ask_unsaved(kind) -> eax 1 when the first modified doc asks, in dialog kind (dlg_kind), else 0
ask_unsaved:
    PROLOGUE
    mov r12d, edi
    xor ebx, ebx
1:  cmp rbx, [rip + g_tabs + VEC_len]
    jae 3f
    mov rdi, rbx
    call tab_at
    cmp qword ptr [rax + TAB_kind], TAB_DOC
    jne 2f
    mov rdi, [rax + TAB_doc]
    call doc_dirty
    test eax, eax
    jz 2f
    mov [rip + dlg_tab], rbx
    mov [rip + dlg_kind], r12d
    mov rdi, rbx
    call app_activate_tab
    mov dword ptr [rip + g_focus], FOCUS_DIALOG
    mov eax, 1
    EPILOGUE
2:  inc rbx
    jmp 1b
3:  xor eax, eax
    EPILOGUE

# close_tabs_now(): close every tab without asking, the last first; terminals stay
close_tabs_now:
    PROLOGUE
    mov rbx, [rip + g_tabs + VEC_len]
1:  test rbx, rbx
    jz 9f
    dec rbx
    mov rdi, rbx
    call tab_at
    cmp qword ptr [rax + TAB_kind], TAB_TERM
    je 1b
    mov rdi, rbx
    call app_close_tab_now
    jmp 1b
9:  EPILOGUE

# ---------------- terminal tabs ----------------

# term_tab(session) -> index of its tab, or -1
term_tab:
    xor eax, eax
    mov rcx, [rip + g_tabs + VEC_ptr]
1:  cmp rax, [rip + g_tabs + VEC_len]
    jae 3f
    cmp qword ptr [rcx + TAB_kind], TAB_TERM
    jne 2f
    cmp [rcx + TAB_term], rdi
    je 9f
2:  add rcx, TAB_SIZE
    inc rax
    jmp 1b
3:  mov rax, -1
9:  ret

# app_add_term(session): a tab for a shell that has just started, after the active one
FN app_add_term
    mov rdx, rdi
    xor edi, edi
    mov esi, TAB_TERM
    jmp add_tab

# app_show_term(session): go to its tab
FN app_show_term
    call term_tab
    test rax, rax
    js 1f
    mov rdi, rax
    jmp app_activate_tab
1:  ret

# app_close_term(session): its shell is gone, or it is to be killed: the tab closes
FN app_close_term
    push rdi
    call term_tab
    pop rdi
    test rax, rax
    js term_end
    mov rdi, rax
    push rax
    call app_close_tab_now
    pop rax
    jmp quit_if_empty

# term_note_back(): the active tab, unless it is a terminal, is where Toggle Terminal comes back to:
#   its document, or its kind when it has none (Settings, the history)
term_note_back:
    mov rdi, [rip + g_tab_cur]
    test rdi, rdi
    js 9f
    cmp rdi, [rip + g_tabs + VEC_len]
    jae 9f
    call tab_at
    mov rcx, [rax + TAB_kind]
    cmp rcx, TAB_TERM
    je 9f
    mov rax, [rax + TAB_doc]
    test rax, rax
    cmovz rax, rcx
    mov [rip + term_back], rax
9:  ret

# app_term_back(): from a terminal to the tab it was opened from, or, with that one closed, to the
#   nearest tab before it that is not a terminal, else the nearest after
FN app_term_back
    PROLOGUE
    mov r12, -1                 # the tab noted
    mov r13, -1                 # the last one before the active tab
    mov r14, -1                 # the first one after it
    xor ebx, ebx
1:  cmp rbx, [rip + g_tabs + VEC_len]
    jae 5f
    mov rdi, rbx
    call tab_at
    mov rcx, [rax + TAB_kind]
    cmp rcx, TAB_TERM
    je 4f
    mov rax, [rax + TAB_doc]
    test rax, rax
    cmovz rax, rcx
    cmp rax, [rip + term_back]
    jne 2f
    mov r12, rbx
2:  cmp rbx, [rip + g_tab_cur]
    ja 3f
    mov r13, rbx
    jmp 4f
3:  test r14, r14
    jns 4f
    mov r14, rbx
4:  inc rbx
    jmp 1b
5:  mov rdi, r12
    test rdi, rdi
    jns 6f
    mov rdi, r13
    test rdi, rdi
    jns 6f
    mov rdi, r14
    test rdi, rdi
    js 9f
6:  call app_activate_tab
9:  EPILOGUE

# the next and the previous tab of the title bar, each at the pane that had the keys
FN cmd_next_tab
    mov rdi, [rip + g_tab_cur]
    test rdi, rdi
    js 1f
    push rbx
    call group_last
    inc rax
    cmp rax, [rip + g_tabs + VEC_len]
    jb 2f
    xor eax, eax
2:  mov rdi, rax
    call group_shown
    pop rbx
    mov rdi, rax
    jmp app_activate_tab
1:  ret

FN cmd_prev_tab
    mov rdi, [rip + g_tab_cur]
    test rdi, rdi
    js 1f
    push rbx
    call group_first
    dec rax
    jns 2f
    mov rax, [rip + g_tabs + VEC_len]
    dec rax
2:  mov rdi, rax
    call group_shown
    pop rbx
    mov rdi, rax
    jmp app_activate_tab
1:  ret

# cmd_save(): save, or ask for a path for untitled docs; a read-only file asks before it is replaced
FN cmd_save
    xor edi, edi
    jmp save_doc

# app_save_close(): vim's :wq: save, and close the file once it is saved (after Overwrite, for a
#   read-only one)
FN app_save_close
    mov edi, 1
save_doc:
    READONLY_RET
    PROLOGUE
    mov r13d, edi
    mov rbx, [rip + g_doc]
    test rbx, rbx
    jz 9f
    cmp qword ptr [rbx + DOC_path], 0
    jne 1f
    call cmd_save_as
    jmp 9f
1:  mov rdi, rbx
    call doc_readonly
    test eax, eax
    jz 3f
    mov [rip + ro_close], r13d
    mov rdi, rbx
    lea rsi, [rip + save_readonly_confirmed]
    call ask_readonly
    jmp 9f
3:  mov rdi, rbx
    call doc_save
    test rax, rax
    js 2f
    mov rdi, rbx
    call app_after_save
    test r13d, r13d
    jz 9f
    call cmd_close_tab
    jmp 9f
2:  lea rdi, [rip + .Lsave_failed]
    call app_toast
9:  EPILOGUE

# save_readonly_confirmed(): Overwrite, for cmd_save and :wq
save_readonly_confirmed:
    PROLOGUE
    mov rbx, [rip + ro_doc]
    cmp rbx, [rip + g_doc]
    jne 9f
    mov rdi, rbx
    call doc_save_readonly
    test rax, rax
    js 2f
    mov rdi, rbx
    call app_after_save
    cmp dword ptr [rip + ro_close], 0
    je 9f
    call cmd_close_tab
    jmp 9f
2:  lea rdi, [rip + .Lsave_failed]
    call app_toast
9:  EPILOGUE

# doc_readonly(doc) -> eax 1 when saving it would replace a file that says not to write it: file_readonly,
#   with a symlink followed as it is now, as the save will
FN doc_readonly
    mov rdi, [rdi + DOC_path]
    test rdi, rdi
    jnz file_readonly
    xor eax, eax
    ret

# file_readonly(path) -> path_readonly for the file a symlink there leads to (the one a save writes),
#   or for the path itself
FN file_readonly
    PROLOGUE
    mov rbx, rdi
    xor esi, esi
    call link_target
    mov r12, rax
    test rax, rax
    jz 1f
    mov rdi, rax
    call path_readonly
    mov ebx, eax
    mov rdi, r12
    call mem_free
    mov eax, ebx
    EPILOGUE
1:  mov rdi, rbx
    call path_readonly
    EPILOGUE

# path_readonly(path) -> eax 1 when the file there says not to write it (no write permission, or the
#   read-only attribute on Windows) while its folder takes a new file, so a save would replace it
#   anyway; in a folder that does not, a save fails as any other
FN path_readonly
    PROLOGUE
    mov rbx, rdi
    mov esi, 2                  # W_OK
    SYS SYS_access
    cmp rax, -13                # EACCES
    jne 8f
    mov rdi, rbx
    call strlen
    mov rdi, rbx
    mov rsi, rax
    call path_dirlen
    test rax, rax
    jnz 1f
    cmp byte ptr [rbx], '/'
    jne 7f
    mov eax, 1
1:  cmp rax, 4096
    jae 7f
    lea rdi, [rip + ro_dir]
    mov rsi, rbx
    mov rcx, rax
    rep movsb
    mov byte ptr [rdi], 0
    lea rdi, [rip + ro_dir]
    mov esi, 2
    SYS SYS_access
    test rax, rax
    jnz 8f
7:  mov eax, 1
    EPILOGUE
8:  xor eax, eax
    EPILOGUE

# doc_save_readonly(doc) -> doc_save's result: a read-only file is replaced and stays read-only. On
#   Windows, where a read-only file cannot be replaced, the attribute is off while it is written (on
#   the file a symlink leads to, which is the one written).
FN doc_save_readonly
.ifdef WINDOWS
    PROLOGUE
    mov rbx, rdi
    mov rdi, [rbx + DOC_path]
    xor esi, esi
    call link_target            # as the save will follow it
    mov r13, rax
    test rax, rax
    jnz 1f
    mov r13, [rbx + DOC_path]
    mov rdi, r13
    call strlen
    mov rdi, r13
    mov rsi, rax
    call mem_dup                # the doc's paths are made again by the save
    mov r13, rax
1:
    mov rdi, r13
    mov esi, 0666
    SYS SYS_chmod
    mov rdi, rbx
    call doc_save
    mov r12, rax
    mov rdi, r13
    mov esi, 0444
    SYS SYS_chmod
    mov rdi, r13
    call mem_free
    mov rax, r12
    EPILOGUE
.else
    jmp doc_save
.endif

# app_save_as_readonly(path): Save As onto a read-only file asks first, as a save does
FN app_save_as_readonly
    PROLOGUE
    mov rbx, rdi
    call strlen
    cmp rax, 4096
    jae 9f
    lea rdi, [rip + ro_path]
    mov rsi, rbx
    call cstr_copy
    mov rax, [rip + g_doc]
    mov [rip + ro_doc], rax
    lea rdi, [rip + ro_path]
    call strlen
    lea rdi, [rip + ro_path]
    mov rsi, rax
    call path_basename
    mov rdi, rax
    lea rsi, [rip + save_as_readonly_confirmed]
    call ask_readonly_named
9:  EPILOGUE

# save_as_readonly_confirmed(): Overwrite, for Save As
save_as_readonly_confirmed:
    PROLOGUE
    mov rbx, [rip + ro_doc]
    test rbx, rbx
    jz 9f
    cmp rbx, [rip + g_doc]
    jne 9f
    mov rdi, rbx
    lea rsi, [rip + ro_path]
    call doc_set_path
    mov rdi, rbx
    call doc_save_readonly
    test rax, rax
    js 2f
    mov rdi, rbx
    call app_detect_lang
    mov rdi, rbx
    call app_after_save
    call app_update_title
    jmp 9f
2:  lea rdi, [rip + .Lsave_failed]
    call app_toast
9:  EPILOGUE

# ask_readonly(doc, fn): "Overwrite read-only NAME?", whose button calls fn
ask_readonly:
    mov [rip + ro_doc], rdi
    mov rdi, [rdi + DOC_name]
# ask_readonly_named(name, fn): the same for a file of that name
ask_readonly_named:
    PROLOGUE
    mov r12, rsi
    mov rbx, rdi
    call strlen
    cmp rax, 200
    jbe 1f
    mov eax, 200
1:  mov r13, rax
    lea rdi, [rip + ro_title]
    lea rsi, [rip + .Lro_a]
    call cstr_copy
    mov rdi, rax
    mov rsi, rbx
    mov rcx, r13
    rep movsb
    lea rsi, [rip + .Lro_b]
    call cstr_copy
    lea rdi, [rip + ro_title]
    lea rsi, [rip + .Lro_text]
    lea rdx, [rip + .Lro_button]
    mov rcx, r12
    call app_confirm
    EPILOGUE

# app_after_save(doc): re-detect language, config reload, explorer refresh
FN app_after_save
    PROLOGUE
    mov rbx, rdi
    cmp qword ptr [rbx + DOC_lang], 0
    jne 1f
    mov rdi, rbx
    call app_detect_lang
1:  lea rdi, [rip + .Lsaved]
    call app_toast
    call explorer_refresh
    mov rdi, rbx
    call git_doc_saved
    # saving the config file applies it right away
    call config_path
    mov rdi, rax
    mov rsi, [rbx + DOC_path]
.ifdef WINDOWS
    call win_path_equal
.else
    call strcmp_eq
.endif
    test eax, eax
    jz 2f
    call app_reload_config
2:  mov dword ptr [rip + g_dirty], 1
    EPILOGUE

FN cmd_save_as
    READONLY_RET
    lea rdi, [rip + .Lsave_as]
    mov esi, PROMPT_SAVE_AS
    jmp prompt_open

FN cmd_quit
    PROLOGUE
    # the session first, once: each answer to a question closes that file
    cmp dword ptr [rip + g_session_final], 0
    jne 4f
    call session_save
    mov dword ptr [rip + g_session_final], 1
4:  # the first modified doc asks; with none, quit
    mov edi, 2
    call ask_unsaved
    test eax, eax
    jnz 9f
    # then the terminals a program runs in ask, once for all of them
    call terms_busy
    test eax, eax
    jz 5f
    lea rdi, [rip + .Lq_quit]
    lea rsi, [rip + .Lq_quit_text]
    lea rdx, [rip + .Lb_quit]
    lea rcx, [rip + quit_confirmed]
    call app_confirm
    jmp 9f
5:  mov dword ptr [rip + g_quit], 1
9:  EPILOGUE

FN app_on_close
    jmp cmd_quit

# app_toast(cstr)
FN app_toast
    push rbx
    mov rsi, rdi
    lea rdi, [rip + g_toast]
    mov ecx, 250
1:  mov al, [rsi]
    mov [rdi], al
    test al, al
    jz 2f
    inc rsi
    inc rdi
    dec ecx
    jnz 1b
    mov byte ptr [rdi], 0
2:  call time_ms
    add rax, 2200
    mov [rip + g_toast_until], rax
    mov dword ptr [rip + g_dirty], 1
    pop rbx
    ret

# app_reload_config(): re-read config and apply theme/fonts/sizes
FN app_reload_config
    PROLOGUE
    mov ebx, [rip + cfg_follow_system]
    mov rdi, [rip + cfg_theme]
    call theme_find
    mov r12, rax
    call config_load
    xor edi, edi
    call theme_settings_init
    # follow_system turned off in the file: theme becomes the theme shown, as in Settings, unless
    # theme was changed too
    test ebx, ebx
    jz 1f
    cmp dword ptr [rip + cfg_follow_system], 0
    jne 1f
    mov rdi, [rip + cfg_theme]
    call theme_find
    cmp rax, r12
    jne 1f
    lea rdi, [rip + cfg_theme]
    mov rsi, [rip + g_theme_cur]
    call theme_set
1:  call keys_reload
    call app_apply_settings
    EPILOGUE

# app_apply_settings(): push current cfg_* values into the running app
FN app_apply_settings
    PROLOGUE
    call theme_apply_config
    call app_sync_panels
    call git_apply
    call ai_apply
    call vim_sync
    call watch_apply_settings
    mov dword ptr [rip + g_dirty], 1
    EPILOGUE

# ---------------- platform callbacks ----------------

FN app_on_resize
    mov dword ptr [rip + g_dirty], 1
    ret

FN app_on_motion
    call ui_input_motion
    mov dword ptr [rip + g_dirty], 1
    ret

FN app_on_pointer_leave
    mov edi, -10000
    mov esi, -10000
    call ui_input_motion
    mov dword ptr [rip + g_dirty], 1
    ret

# app_on_button(btn, pressed, mods)
FN app_on_button
    mov [rip + g_mods], edx
    # the caret shows at once, as after a key: a press or a release may have placed it
    push rdi
    push rsi
    push rdx
    call time_ms
    mov [rip + g_blink_t0], rax
    pop rdx
    pop rsi
    pop rdi
    call ui_input_button
    mov dword ptr [rip + g_dirty], 1
    ret

# app_on_scroll(dx, dy, mods)
FN app_on_scroll
    mov [rip + g_scroll_mods], edx
    mov ecx, [rip + cfg_scroll_sens]
    test edx, MOD_ALT
    jz 1f
    mov ecx, [rip + cfg_fast_sens]
    # in hundredths; what the division leaves carries to the next scroll, so a trackpad's
    # small steps add up instead of rounding away
1:  imul edi, ecx
    add edi, [rip + scroll_rem]
    imul esi, ecx
    add esi, [rip + scroll_rem + 4]
    mov ecx, 100
    mov eax, edi
    cdq
    idiv ecx
    mov edi, eax
    mov [rip + scroll_rem], edx
    mov eax, esi
    cdq
    idiv ecx
    mov esi, eax
    mov [rip + scroll_rem + 4], edx
    # less than a pixel so far: nothing to draw
    mov eax, edi
    or eax, esi
    jz 2f
    call ui_input_scroll
    mov dword ptr [rip + g_dirty], 1
2:  ret

# wheel_xy() -> eax x, edx y: this frame's wheel for a view that also scrolls sideways (the editor, an
#   image). Shift turns it sideways, as in other apps on Linux and Windows; macOS turns it itself.
#   Views that only scroll down keep Shift's wheel as it is (the terminal's scrollback).
FN wheel_xy
    mov eax, [rip + g_scroll_x]
    mov edx, [rip + g_scroll_y]
.ifndef MACOS
    test dword ptr [rip + g_scroll_mods], MOD_SHIFT
    jz 1f
    add eax, edx
    xor edx, edx
1:
.endif
    ret

FN app_on_focus
    mov [rip + g_win_focused], edi
    # files may have changed while away
    test edi, edi
    jz 1f
    push rdi
    call git_touch
    pop rdi
1:  call ed_touch
    mov dword ptr [rip + g_dirty], 1
    ret

# app_on_paste(ptr, len): route to the focused text target
FN app_on_paste
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    call focus_sync
    call vim_paste
    test eax, eax
    jnz 9f
    # the commit message keeps line breaks
    cmp dword ptr [rip + g_focus], FOCUS_SCM
    jne 0f
    mov rdi, rbx
    mov rsi, r12
    call scm_paste
    jmp 9f
0:  mov rdi, rbx
    mov rsi, r12
    call focused_field
    test rax, rax
    jz 1f
    mov rdi, rax
    mov rsi, rbx
    mov rdx, r12
    call tf_insert
    call field_changed
    jmp 9f
1:  cmp dword ptr [rip + g_focus], FOCUS_TERMINAL
    jne 2f
    mov rdi, rbx
    mov rsi, r12
    call term_tab_paste
    jmp 9f
2:  cmp dword ptr [rip + g_focus], FOCUS_EDITOR
    jne 9f
    mov rdi, rbx
    mov rsi, r12
    call ed_paste
9:  mov dword ptr [rip + g_dirty], 1
    EPILOGUE

# focused_field() -> TF* that has keyboard focus, or 0
focused_field:
    mov eax, [rip + g_focus]
    cmp eax, FOCUS_PALETTE
    je palette_field
    cmp eax, FOCUS_PROMPT
    je palette_field
    cmp eax, FOCUS_FIND
    je find_field
    cmp eax, FOCUS_SETTINGS
    je settings_field
    cmp eax, FOCUS_EDITOR
    je vim_field
    xor eax, eax
    ret

# field_changed(): notify the owner of the focused field
field_changed:
    mov eax, [rip + g_focus]
    cmp eax, FOCUS_PALETTE
    je palette_changed
    cmp eax, FOCUS_PROMPT
    je palette_changed
    cmp eax, FOCUS_FIND
    je find_changed
    cmp eax, FOCUS_EDITOR
    je vim_field_changed
    ret

# app_on_key(keysym, cp, mods)
FN app_on_key
    PROLOGUE 16
    mov r12d, edi
    mov r13d, esi
    mov r14d, edx
    call tip_dismiss
    call focus_sync
    mov edx, r14d
    mov [rip + g_mods], edx
    mov dword ptr [rip + g_dirty], 1
    call time_ms
    mov [rip + g_blink_t0], rax
    # dead keys and the Compose key
    mov edi, r12d
    mov esi, r14d
    call compose_key
    test eax, eax
    jnz 9f
    # modal dialog swallows keys
    cmp dword ptr [rip + dlg_kind], 0
    je 1f
    mov edi, r12d
    call dialog_key
    jmp 9f
1:  # Esc closes a context menu
    cmp r12d, KEY_ESCAPE
    jne 10f
    call explorer_menu_open
    test eax, eax
    jz 10f
    call ctx_menu_close
    jmp 9f
10: # focused components get the first chance
    mov eax, [rip + g_focus]
    cmp eax, FOCUS_PALETTE
    je 2f
    cmp eax, FOCUS_PROMPT
    jne 3f
2:  mov edi, r12d
    mov esi, r13d
    mov edx, r14d
    call palette_key
    test eax, eax
    jnz 9f
    jmp .Lk_bind
3:  cmp eax, FOCUS_FIND
    jne 4f
    mov edi, r12d
    mov esi, r13d
    mov edx, r14d
    call find_key
    test eax, eax
    jnz 9f
    jmp .Lk_bind
4:  cmp eax, FOCUS_SETTINGS
    jne 5f
    mov edi, r12d
    mov esi, r13d
    mov edx, r14d
    call settings_key
    test eax, eax
    jnz 9f
    jmp .Lk_bind
5:  cmp eax, FOCUS_EXPLORER
    jne 6f
    mov edi, r12d
    mov esi, r13d
    mov edx, r14d
    call explorer_key
    test eax, eax
    jnz 9f
    jmp .Lk_bind
6:  cmp eax, FOCUS_TERMINAL
    jne 71f
    mov edi, r12d
    mov esi, r13d
    mov edx, r14d
    call term_tab_key
    test eax, eax
    jnz 9f
    jmp .Lk_bind
71: cmp eax, FOCUS_SCM
    jne .Lk_bind
    mov edi, r12d
    mov esi, r13d
    mov edx, r14d
    call scm_key
    test eax, eax
    jnz 9f
.Lk_bind:
    cmp dword ptr [rip + g_focus], FOCUS_EDITOR
    jne 1f
    call md_active              # a Markdown page has no cursor for vim's keys
    test eax, eax
    jnz 1f
    mov edi, r12d
    mov esi, r13d
    mov edx, r14d
    call vim_key
    test eax, eax
    jnz 9f
1:  mov edi, r12d
    mov esi, r14d
    call keys_lookup
    test rax, rax
    jz .Lk_editor
    call rax
    jmp 9f
.Lk_editor:
    cmp dword ptr [rip + g_focus], FOCUS_EDITOR
    jne 9f
    call app_image
    test rax, rax
    jz 1f
    mov rdi, rax
    mov esi, r12d
    mov edx, r13d
    mov ecx, r14d
    call iv_key
    jmp 9f
1:  # the history tab takes the arrows
    mov rdi, [rip + g_tab_cur]
    test rdi, rdi
    js 8f
    call tab_at
    cmp qword ptr [rax + TAB_kind], TAB_GIT
    jne 8f
    mov edi, r12d
    mov esi, r13d
    mov edx, r14d
    call gitview_key
    jmp 9f
8:  call md_active
    test eax, eax
    jz .Lk_edkey
    mov edi, r12d
    mov esi, r13d
    mov edx, r14d
    call md_key
    jmp 9f
.Lk_edkey:
    mov edi, r12d
    mov esi, r13d
    mov edx, r14d
    call editor_key
9:  EPILOGUE

# editor_key(keysym, cp, mods): keys not bound to commands
FN editor_key
    PROLOGUE
    mov r12d, edi
    mov r13d, esi
    mov r14d, edx
    cmp qword ptr [rip + g_doc], 0
    je 9f
    mov r15d, r14d
    and r15d, MOD_SHIFT         # extend selection
    xor ebx, ebx                # word modifier
    test r14d, MOD_CTRL
    setnz bl
    mov eax, r12d
    cmp eax, KEY_LEFT
    jne 1f
    mov edi, 0
    test r14d, MOD_CTRL | MOD_ALT       # Alt too: Ctrl with an arrow is bound to the panes' splits
    jz 11f
    mov edi, 6
11: mov esi, r15d
    call ed_move
    jmp 9f
1:  cmp eax, KEY_RIGHT
    jne 2f
    mov edi, 1
    test r14d, MOD_CTRL | MOD_ALT
    jz 21f
    mov edi, 7
21: mov esi, r15d
    call ed_move
    jmp 9f
2:  cmp eax, KEY_UP
    jne 3f
    test ebx, ebx
    jnz 31f
    mov edi, 2
    mov esi, r15d
    call ed_move
    jmp 9f
31: mov rax, [rip + g_doc]
    sub qword ptr [rax + DOC_scrolly], 256
    jmp 9f
3:  cmp eax, KEY_DOWN
    jne 4f
    test ebx, ebx
    jnz 41f
    mov edi, 3
    mov esi, r15d
    call ed_move
    jmp 9f
41: mov rax, [rip + g_doc]
    add qword ptr [rax + DOC_scrolly], 256
    jmp 9f
4:  cmp eax, KEY_HOME
    jne 5f
    mov edi, 4
    test ebx, ebx
    jz 51f
    mov edi, 10
51: mov esi, r15d
    call ed_move
    jmp 9f
5:  cmp eax, KEY_END
    jne 6f
    mov edi, 5
    test ebx, ebx
    jz 61f
    mov edi, 11
61: mov esi, r15d
    call ed_move
    jmp 9f
6:  cmp eax, KEY_PAGEUP
    jne 7f
    mov edi, 8
    mov esi, r15d
    call ed_move
    jmp 9f
7:  cmp eax, KEY_PAGEDOWN
    jne 8f
    mov edi, 9
    mov esi, r15d
    call ed_move
    jmp 9f
8:  cmp eax, KEY_BACKSPACE
    jne 81f
    mov edi, ebx
    call ed_backspace
    jmp 9f
81: cmp eax, KEY_DELETE
    jne 82f
    mov edi, ebx
    call ed_delete_fwd
    jmp 9f
82: cmp eax, KEY_RETURN
    je 83f
    cmp eax, KEY_KP_ENTER
    jne 84f
83: call ed_newline
    jmp 9f
84: cmp eax, KEY_TAB
    jne 85f
    test r14d, MOD_SHIFT
    jnz 86f
    call ed_tab
    jmp 9f
85: cmp eax, KEY_ISO_LEFT_TAB
    jne 87f
86: mov edi, -1
    call ed_indent
    jmp 9f
87: cmp eax, KEY_ESCAPE
    jne 88f
    # collapse selection
    mov rax, [rip + g_doc]
    mov rcx, [rax + DOC_cur]
    mov [rax + DOC_anchor], rcx
    lea rdi, [rip + g_ed_find]
    call sb_clear
    jmp 9f
88: # printable
    test r14d, MOD_CTRL | MOD_ALT | MOD_SUPER
    jnz 9f
    cmp r13d, 32
    jb 9f
    cmp r13d, 127
    je 9f
    mov edi, r13d
    call ed_type
9:  EPILOGUE

# ---------------- timers ----------------

FN app_timeout
    PROLOGUE
    call ed_blink_timeout
    mov ebx, eax
    # toast expiry
    mov rax, [rip + g_toast_until]
    test rax, rax
    jz 1f
    push rax
    call time_ms
    pop rcx
    sub rcx, rax
    jns 11f
    xor ecx, ecx
11: cmp ebx, -1
    je 12f
    cmp ecx, ebx
    jge 1f
12: mov ebx, ecx
1:  call git_timeout
    cmp eax, -1
    je 3f
    cmp ebx, -1
    je 31f
    cmp eax, ebx
    jge 3f
31: mov ebx, eax
3:  call update_timeout
    cmp eax, -1
    je 4f
    cmp ebx, -1
    je 41f
    cmp eax, ebx
    jge 4f
41: mov ebx, eax
4:  call ai_timeout
    cmp eax, -1
    je 5f
    cmp ebx, -1
    je 51f
    cmp eax, ebx
    jge 5f
51: mov ebx, eax
5:  call watch_timeout
    cmp eax, -1
    je 6f
    cmp ebx, -1
    je 61f
    cmp eax, ebx
    jge 6f
61: mov ebx, eax
6:  call tip_timeout
    cmp eax, -1
    je 7f
    cmp ebx, -1
    je 71f
    cmp eax, ebx
    jge 7f
71: mov ebx, eax
7:  call palette_timeout
    cmp eax, -1
    je 8f
    cmp ebx, -1
    je 81f
    cmp eax, ebx
    jge 8f
81: mov ebx, eax
8:  call editor_timeout
    cmp eax, -1
    je 82f
    cmp ebx, -1
    je 83f
    cmp eax, ebx
    jge 82f
83: mov ebx, eax
82: call sb_timeout
    cmp eax, -1
    je 84f
    cmp ebx, -1
    je 85f
    cmp eax, ebx
    jge 84f
85: mov ebx, eax
84: call term_timeout
    cmp eax, -1
    je 86f
    cmp ebx, -1
    je 87f
    cmp eax, ebx
    jge 86f
87: mov ebx, eax
86: mov eax, ebx
    EPILOGUE

FN app_tick
    PROLOGUE
    call watch_tick
    call tip_tick
    call sb_tick
    call ed_blink_tick
    mov rax, [rip + g_toast_until]
    test rax, rax
    jz 2f
    call time_ms
    cmp rax, [rip + g_toast_until]
    jb 2f
    mov qword ptr [rip + g_toast_until], 0
    mov dword ptr [rip + g_dirty], 1
2:  call term_tick
    call git_tick
    call update_tick
    call ai_tick
    call palette_tick
    call editor_tick
    EPILOGUE

# ---------------- rendering ----------------

FN app_render
    PROLOGUE 64
    call ui_update_metrics
    call focus_sync
    call follow_cwd
    call term_frame_begin
    call ui_begin
    mov dword ptr [rip + tip_cand], 0   # hovered-button candidates are collected below
    mov eax, [rip + g_cv + CV_w]
    mov [rsp], eax              # W
    mov eax, [rip + g_cv + CV_h]
    mov [rsp + 4], eax          # H
    # modal layers block the base UI
    call app_modal_open
    mov [rsp + 8], eax
    mov [rip + g_block], eax
    call resize_edges
    mov [rsp + 36], eax
    test eax, eax
    jz 1f
    mov dword ptr [rip + g_block], 1
1:
    # no background: the bars, panels, dividers and the editor column cover the window, each with
    # its own color (a whole-window fill under them was a fifth of every frame). A theme with a
    # translucent color (#rrggbbaa) still gets it, so nothing blends with the frame before.
    lea rcx, [rip + g_theme]
    mov eax, -1
    xor edx, edx
0:  and eax, [rcx + rdx*4]
    inc edx
    cmp edx, T_COUNT
    jb 0b
    shr eax, 24
    cmp eax, 255
    je 0f
    xor edi, edi
    xor esi, esi
    mov edx, [rsp]
    mov ecx, [rsp + 4]
    COLOR r8d, T_BG
    call gfx_fill
0:  # panel sizes
    mov dword ptr [rip + g_scm_drawn], 0
    mov edi, [rip + cfg_sidebar_w]
    call sc
    mov [rip + g_side_px], eax
    M eax, MI_TITLE
    M edx, MI_STATUS
    cmp dword ptr [rip + g_zen], 0
    je 16f
    xor eax, eax                # zen mode: the view with the keys has the whole window
    xor edx, edx
16: mov [rsp + 12], eax         # title h
    mov ecx, [rsp + 4]
    sub ecx, edx
    mov [rsp + 16], ecx         # status y
    # body box
    mov eax, [rsp + 12]
    mov [rsp + 20], eax         # body y
    mov ecx, [rsp + 16]
    sub ecx, eax
    mov [rsp + 24], ecx         # body h
    # the sidebar gives way in a narrow window, whatever its setting
    mov edi, 576
    call fz
    mov edi, eax
    call sc
    mov ecx, eax
    mov eax, [rip + g_show_side]
    mov dword ptr [rip + side_narrow], 0
    cmp [rsp], ecx
    jge 15f
    # until its toggle asks for it there: then it takes no more than half the window
    mov dword ptr [rip + side_narrow], 1
    and eax, [rip + side_asked]
    mov ecx, [rsp]
    sar ecx, 1
    cmp [rip + g_side_px], ecx
    jle 1f
    mov [rip + g_side_px], ecx
    jmp 1f
15: mov dword ptr [rip + side_asked], 0
1:  cmp dword ptr [rip + split_fold], 0
    je 11f
    # folded by a drag that is still held: the divider waits at the edge, to be pulled out again
    test dword ptr [rip + g_mdown], 1 << BTN_LEFT
    jnz 12f
    mov dword ptr [rip + split_fold], 0     # let go: it stays folded, as its toggle would leave it
    cmp dword ptr [rip + g_show_side], 0
    je 13f
    call cmd_toggle_sidebar
13: xor eax, eax
    jmp 11f
12: mov dword ptr [rip + g_side_px], 0
    xor eax, eax
11: cmp dword ptr [rip + g_zen], 0
    je 17f
    xor eax, eax
17: mov [rsp + 44], eax
    mov [rip + g_side_shown], eax
    # the tree is of the folder the terminal with the keys is in
    test eax, eax
    jz 14f
    cmp dword ptr [rip + g_focus], FOCUS_TERMINAL
    jne 14f
    lea rdi, [rip + crumb_tmp]
    call term_shown_cwd
    test rax, rax
    jle 14f
    lea rdi, [rip + crumb_tmp]
    call explorer_follow
14:
    # the title bar first: a tab pressed there is the one drawn under it
    mov dword ptr [rip + split_l_bits], 0
    cmp dword ptr [rip + g_zen], 0
    jne 4f
    xor edi, edi
    xor esi, esi
    mov edx, [rsp]
    mov ecx, [rsp + 12]
    call titlebar_draw
    # the divider takes its strip first: the panels either side are drawn before it
    mov eax, [rsp + 44]
    or eax, [rip + split_fold]
    jz 31f
    mov edi, ID_SPLIT_L
    mov esi, [rip + g_side_px]
    mov edx, [rsp + 20]
    mov ecx, [rsp + 24]
    call splitter_hit
    mov [rip + split_l_bits], eax
31: cmp dword ptr [rsp + 44], 0
    je 4f
    xor edi, edi
    mov esi, [rsp + 20]
    mov edx, [rip + g_side_px]
    mov ecx, [rsp + 24]
    call sidebar_draw
    cmp dword ptr [rip + side_fit], 0
    je 32f
    call side_fit_width
32: cmp dword ptr [rip + g_exp_changed], 0
    je 33f
    mov dword ptr [rip + g_exp_changed], 0
    call side_grow
33: mov eax, [rip + g_side_px]
    mov [rsp + 28], eax
    # border + splitter
    mov edi, eax
    mov esi, [rsp + 20]
    M edx, MI_1
    mov ecx, [rsp + 24]
    COLOR r8d, T_BORDER
    call gfx_fill
    jmp 5f
4:  mov dword ptr [rsp + 28], 0
5:  # the panes
    mov edi, [rsp + 28]
    cmp dword ptr [rsp + 44], 0
    je 51f
    add edi, [rip + g_mt + 4*MI_1]
51: mov [rsp + 40], edi
    mov edx, [rsp]
    sub edx, edi
    mov esi, [rsp + 20]
    mov ecx, [rsp + 24]
    call center_draw
    cmp dword ptr [rip + g_zen], 0
    jne 57f
    # the divider over everything in the body: its line and cursor win
    mov eax, [rsp + 44]
    or eax, [rip + split_fold]
    jz 56f
    mov edi, ID_SPLIT_L
    mov esi, [rsp + 28]
    mov edx, [rsp + 20]
    mov ecx, [rsp + 24]
    mov r8d, [rip + split_l_bits]
    call splitter
56: xor edi, edi
    mov esi, [rsp + 16]
    mov edx, [rsp]
    M ecx, MI_STATUS
    call statusbar_draw
57: # overlays (not blocked)
    mov dword ptr [rip + g_block], 0
    call explorer_menu_draw
    call palette_draw
    call dialog_draw
    call toast_draw
    call tip_commit             # after every button with a tooltip has been drawn
    call tip_draw
    mov edi, [rsp + 36]
    test edi, edi
    jz 2f
    call edge_cursor
    mov [rip + g_cursor], eax
2:  call ed_blink_frame
    call panes_drag_end
    call window_corners
    call ui_end
    # scripted screenshot
    mov rdi, [rip + g_shot_path]
    test rdi, rdi
    jz 9f
    mov qword ptr [rip + g_shot_path], 0
    call shot_write
9:  EPILOGUE

# window_corners(): a window that draws its own frame has rounded corners, unless it fills the
#   screen or is tiled: every pixel is made opaque, then the corners fade out along a thin line
window_corners:
    PROLOGUE
    cmp dword ptr [rip + g_argb], 0     # a surface with alpha shows through whatever is not opaque
    je 3f
    mov rdi, [rip + g_cv + CV_pixels]
    mov r8d, [rip + g_cv + CV_h]
    mov r9d, [rip + g_cv + CV_stride]
    shl r9, 2
1:  test r8d, r8d
    jz 3f
    mov ecx, [rip + g_cv + CV_w]
    mov rdx, rdi
2:  or byte ptr [rdx + 3], 0xff
    add rdx, 4
    dec ecx
    jnz 2b
    add rdi, r9
    dec r8d
    jmp 1b
3:  cmp dword ptr [rip + g_csd], 0
    je 9f
    test dword ptr [rip + g_win_states], 1 | 2 | 8
    jnz 9f
    COLOR edi, T_PANEL
    COLOR esi, T_FG
    mov edx, 40
    call color_mix
    mov r9d, eax
    xor edi, edi
    xor esi, esi
    mov edx, [rip + g_cv + CV_w]
    mov ecx, [rip + g_cv + CV_h]
    M r8d, MI_10
    push 0
    push 0
    call gfx_card_edge
    add rsp, 16
9:  EPILOGUE

app_modal_open:
    cmp dword ptr [rip + dlg_kind], 0
    jne 1f
    call explorer_menu_open
    test eax, eax
    jnz 1f
    call palette_is_open
    ret
1:  mov eax, 1
    ret

# resize_edges() -> EDGE_* bits under the pointer (client-side decorations only); starts a resize on press
resize_edges:
    xor eax, eax
    cmp dword ptr [rip + g_csd], 0
    je 9f
    test dword ptr [rip + g_win_states], 1 | 2 | 8
    jnz 9f
    mov ecx, [rip + g_mx]
    mov edx, [rip + g_my]
    test ecx, ecx
    js 9f
    test edx, edx
    js 9f
    M r8d, MI_6
    cmp ecx, r8d
    jge 1f
    or eax, EDGE_LEFT
1:  mov r9d, [rip + g_cv + CV_w]
    sub r9d, r8d
    cmp ecx, r9d
    jl 2f
    or eax, EDGE_RIGHT
2:  cmp edx, r8d
    jge 3f
    or eax, EDGE_TOP
3:  mov r9d, [rip + g_cv + CV_h]
    sub r9d, r8d
    cmp edx, r9d
    jl 4f
    or eax, EDGE_BOTTOM
4:  test eax, eax
    jz 9f
    test dword ptr [rip + g_pressed], 1 << BTN_LEFT
    jz 9f
    and dword ptr [rip + g_pressed], ~(1 << BTN_LEFT)
    push rax
    push rax
    mov edi, eax
    PCALL P_resize
    and dword ptr [rip + g_mdown], ~(1 << BTN_LEFT)   # the release goes to the compositor
    pop rax
    pop rax
9:  ret

# edge_cursor(edges) -> CUR_*
edge_cursor:
    mov eax, CUR_EW
    cmp edi, EDGE_LEFT
    je 1f
    cmp edi, EDGE_RIGHT
    je 1f
    mov eax, CUR_NS
    cmp edi, EDGE_TOP
    je 1f
    cmp edi, EDGE_BOTTOM
    je 1f
    mov eax, CUR_NWSE
    cmp edi, EDGE_TOP | EDGE_LEFT
    je 1f
    cmp edi, EDGE_BOTTOM | EDGE_RIGHT
    je 1f
    mov eax, CUR_NESW
1:  ret

# splitter_hit(id, x, y, h) -> UB_* bits: the divider's strip, MI_3 either side of x; it keeps its press
splitter_hit:
    PROLOGUE
    M eax, MI_3
    sub esi, eax
    lea r8d, [rax + rax + 1]
    xchg ecx, r8d
    call ui_btn
    test eax, UB_PRESS
    jz 1f
    and dword ptr [rip + g_pressed], ~(1 << BTN_LEFT)   # the press is the drag's; nothing under it takes it too
1:  EPILOGUE

# splitter(id, x, y, h, bits): cursor, line and drag of a divider hit tested by splitter_hit
splitter:
    PROLOGUE 16
    mov ebx, edi
    mov r12d, esi
    mov r13d, edx
    mov r14d, ecx
    mov eax, r8d
    mov [rsp], eax
    COLOR edi, T_BORDER
    COLOR esi, T_FG
    mov edx, 90
    call color_mix
    mov r15d, eax               # the handle's color
    test dword ptr [rsp], UB_HOVER | UB_HELD
    jz 4f
    mov dword ptr [rip + g_cursor], CUR_EW
    COLOR r15d, T_ACCENT        # feedback line over the divider
    M edx, MI_2
    mov edi, edx
    sar edi, 1
    neg edi
    add edi, r12d
    mov esi, r13d
    mov ecx, r14d
    xor r8d, r8d
    mov r9d, r15d
    call gfx_round_rect
4:  # the handle, as the panes' dividers have: MI_4 across, MI_32 along, at the line's middle
    M edx, MI_4
    M ecx, MI_32
    mov edi, edx
    sar edi, 1
    neg edi
    add edi, r12d
    mov esi, r14d
    sub esi, ecx
    sar esi, 1
    add esi, r13d
    M r8d, MI_2
    mov r9d, r15d
    call gfx_round_rect
    mov eax, [rsp]
1:  test eax, UB_DOUBLE
    jz 5f
    # a double-click puts the panel back at its default width, what its longest name needs; a drag
    # after it starts from where the next frame lays the divider out
    call side_fit_width
    mov dword ptr [rip + split_fold], 0
    mov dword ptr [rip + split_reanchor], 1
    mov dword ptr [rip + split_moved], 0
    jmp 3f
5:  test eax, UB_HELD
    jz 9f
    test eax, UB_PRESS
    jz 52f
    # the press takes hold of the divider where it is: it keeps its distance from the pointer
    mov eax, [rip + g_mx]
    sub eax, r12d
    mov [rip + split_grab], eax
    mov dword ptr [rip + split_moved], 0
    mov dword ptr [rip + split_reanchor], 0
    call explorer_fit_width     # under it the drag folds the sidebar
    mov [rip + side_fit_px], eax
    jmp 9f
52: cmp dword ptr [rip + split_reanchor], 0
    je 6f
    mov dword ptr [rip + split_reanchor], 0
    mov eax, [rip + g_press_x]  # the double-click's press against the divider the reset laid out
    sub eax, r12d
    mov [rip + split_grab], eax
6:  # a click that does not move leaves the width alone (even one the layout narrowed); once the
    # pointer has moved, the divider follows it back to where it was pressed too
    mov eax, [rip + g_mx]
    cmp dword ptr [rip + split_moved], 0
    jne 7f
    cmp eax, [rip + g_press_x]
    je 9f
    mov dword ptr [rip + split_moved], 1
7:  # new width in logical points
    sub eax, [rip + split_grab]
    cvtsi2ss xmm0, eax
    divss xmm0, [rip + g_s]
    cvtss2si eax, xmm0
    push rax
    push rax
    mov edi, 90                 # larger text, a larger room to fold in
    call fz
    mov ecx, eax
    # and no name of the tree is cut: under what the longest needs it folds too (as far as the
    # sidebar can be that wide)
    cvtsi2ss xmm0, dword ptr [rip + side_fit_px]
    divss xmm0, [rip + g_s]
    cvtss2si eax, xmm0
    mov edx, 600
    cmp eax, edx
    cmovg eax, edx
    cmp ecx, eax
    cmovl ecx, eax
    pop rax
    pop rax
    cmp eax, ecx
    jge 10f
    # dragged under its least width, the sidebar folds away, and comes back when the same
    # drag pulls it out again; let go folded, its toggle brings it back (app_render)
    cmp dword ptr [rip + split_fold], 0
    jne 9f
    mov dword ptr [rip + split_fold], 1
    mov dword ptr [rip + g_dirty], 1
    jmp 9f
10: mov dword ptr [rip + split_fold], 0
    cmp eax, 140
    jge 11f
    mov eax, 140
11: cmp eax, 600
    jle 12f
    mov eax, 600
12: mov [rip + cfg_sidebar_w], eax
3:  mov dword ptr [rip + g_dirty], 1
    mov dword ptr [rip + g_settings_changed], 1
9:  EPILOGUE

# center_draw(x, y, w, h): the panes of the active tab, or the welcome screen, as cards on the frame
FN center_draw
    PROLOGUE 32
    mov [rsp], edi
    mov [rsp + 4], esi
    mov [rsp + 8], edx
    mov [rsp + 12], ecx
    cmp qword ptr [rip + g_tabs + VEC_len], 0
    je 1f
    call panes_draw
    EPILOGUE
1:  call welcome_draw
    EPILOGUE

# view_draw(i, x, y, w, h, panes): view i in its pane. The one with the keys is drawn as the window's
#   only view was; another pane shows its own document or terminal, takes the wheel and a hover,
#   and leaves presses alone (a press gave it the keys before the frame: panes_draw)
FN view_draw
    PROLOGUE 112
    mov [rsp], esi
    mov [rsp + 4], edx
    mov [rsp + 8], ecx
    mov [rsp + 12], r8d
    mov [rsp + 16], r9d
    mov r12, rdi
    call tab_at
    mov r14, [rax + TAB_kind]
    mov r15, [rax + TAB_doc]
    mov rbx, [rax + TAB_term]
    xor eax, eax
    cmp r12, [rip + g_tab_cur]
    sete al
    mov [rsp + 20], eax         # it has the keys
    test eax, eax
    jnz .Lvd_draw
    mov rax, [rip + g_doc]
    mov [rsp + 24], rax
    mov rax, [rip + g_file]
    mov [rsp + 32], rax
    mov eax, [rip + g_focus]
    mov [rsp + 40], eax
    mov eax, [rip + g_active]
    mov [rsp + 44], eax
    mov eax, [rip + g_pressed]
    mov [rsp + 48], eax
    mov eax, [rip + g_released]
    mov [rsp + 52], eax
    movdqu xmm0, [rip + g_editor_rect]
    movdqu [rsp + 64], xmm0
    mov dword ptr [rip + g_focus], -1
    mov dword ptr [rip + g_active], 0
    mov dword ptr [rip + g_pressed], 0
    mov dword ptr [rip + g_released], 0
    mov [rip + g_file], r15
    mov qword ptr [rip + g_doc], 0
    cmp r14, TAB_DOC
    jne .Lvd_draw
    mov [rip + g_doc], r15
.Lvd_draw:
    mov edi, [rsp]
    mov esi, [rsp + 4]
    mov edx, [rsp + 8]
    mov ecx, [rsp + 12]
    mov [rip + g_editor_rect], edi
    mov [rip + g_editor_rect + 4], esi
    mov [rip + g_editor_rect + 8], edx
    mov [rip + g_editor_rect + 12], ecx
    cmp r14, TAB_IMAGE
    jne 4f
    mov rdi, r15
    mov esi, [rsp]
    mov edx, [rsp + 4]
    mov ecx, [rsp + 8]
    mov r8d, [rsp + 12]
    call iv_draw
    jmp .Lvd_done
4:  cmp r14, TAB_TERM
    jne 5f
    cmp dword ptr [rsp + 20], 0
    je 41f
    call term_tab_draw
    jmp .Lvd_done
41: mov r8d, ecx
    mov ecx, edx
    mov edx, esi
    mov esi, edi
    mov rdi, rbx
    call term_pane_draw
    jmp .Lvd_done
5:  cmp r14, TAB_GIT
    jne 1f
    call gitview_draw
    jmp .Lvd_done
1:  cmp r14, TAB_SETTINGS
    jne 11f
    call settings_draw
    jmp .Lvd_done
11: cmp r14, TAB_HOME
    jne 2f
    call welcome_draw
    jmp .Lvd_done
2:  mov rbx, [rip + g_doc]
    test rbx, rbx
    jz .Lvd_done
    # a Markdown file: its switch, and its page in place of the editor
    mov rdi, rbx
    mov esi, [rsp]
    mov edx, [rsp + 4]
    mov ecx, [rsp + 8]
    mov r8d, [rsp + 12]
    mov r9d, [rsp + 20]
    call md_view
    test eax, eax
    jnz .Lvd_done
    mov rdi, rbx
    mov rsi, [rbx + DOC_scrolly]
    shr rsi, 8
    mov eax, [rsp + 12]
    xor edx, edx
    div dword ptr [rip + g_lh]
    lea rsi, [rsi + rax + 2]
    call syntax_prepare
    mov edi, [rsp]
    mov esi, [rsp + 4]
    mov edx, [rsp + 8]
    mov ecx, [rsp + 12]
    call editor_draw
    cmp dword ptr [rsp + 20], 0
    je .Lvd_md
    call find_draw
.Lvd_md:
    mov rdi, rbx
    call md_view_end
.Lvd_done:
    cmp dword ptr [rsp + 20], 0
    jne 6f
    mov rax, [rsp + 24]
    mov [rip + g_doc], rax
    mov rax, [rsp + 32]
    mov [rip + g_file], rax
    mov eax, [rsp + 40]
    mov [rip + g_focus], eax
    mov eax, [rsp + 44]
    mov [rip + g_active], eax
    mov eax, [rsp + 48]
    mov [rip + g_pressed], eax
    mov eax, [rsp + 52]
    mov [rip + g_released], eax
    movdqu xmm0, [rsp + 64]
    movdqu [rip + g_editor_rect], xmm0
6:  # among other panes the one with the keys has a thin outline
    cmp dword ptr [rsp + 16], 0
    je 7f
    cmp dword ptr [rsp + 20], 0
    je 7f
    COLOR edi, T_BORDER
    COLOR esi, T_ACCENT
    mov edx, 150
    call color_mix
    mov r9d, eax
    mov edi, [rsp]
    mov esi, [rsp + 4]
    mov edx, [rsp + 8]
    mov ecx, [rsp + 12]
    xor r8d, r8d
    push 0
    push 0
    call gfx_card_edge
    add rsp, 16
7:  EPILOGUE

# titlebar_draw(x, y, w, h): the sidebar's toggle, the tabs, a button for a new terminal, and at the
#   right the search, the history, Settings and the window's buttons
FN titlebar_draw
    PROLOGUE 80
    mov [rsp], edi
    mov [rsp + 4], esi
    mov [rsp + 8], edx
    mov [rsp + 12], ecx
    COLOR r8d, T_PANEL
    call gfx_fill
    mov edi, [rsp]
    mov esi, [rsp + 12]
    dec esi
    mov edx, [rsp + 8]
    M ecx, MI_1
    COLOR r8d, T_BORDER
    call gfx_fill
    # buttons first; the empty title area (move, maximize, menu) is handled at the end
    mov eax, [rip + g_hot]
    mov [rsp + 32], eax
    mov dword ptr [rip + g_hot], 0
    M eax, MI_28
    mov [rsp + 40], eax         # button size
    M r12d, MI_8
    add r12d, [rip + g_title_inset]
    # sidebar toggle
    mov r13d, [rsp + 40]
    mov edi, ID_TOG_SIDE
    mov esi, r12d
    mov edx, [rsp + 12]
    sub edx, r13d
    sar edx, 1
    mov ecx, r13d
    mov r8d, r13d
    mov r9d, IC_SIDEBAR
    call ui_icon_btn
    mov r8d, eax
    mov edi, ID_TOG_SIDE
    mov esi, r12d
    M edx, MI_TITLE
    mov ecx, r13d
    call tip_note               # keeps the button flags in eax
    test eax, UB_CLICK
    jz 3f
    call cmd_toggle_sidebar
3:  add r12d, r13d
    add r12d, [rip + g_mt + 4*MI_8]
    # a line between it and the tabs
    mov edi, r12d
    M ecx, MI_16
    mov esi, [rsp + 12]
    sub esi, ecx
    sar esi, 1
    M edx, MI_1
    COLOR r8d, T_BORDER
    call gfx_fill
    add r12d, [rip + g_mt + 4*MI_8]
    mov [rsp + 60], r12d        # where the tabs start
    # right side buttons
    mov r12d, [rsp + 8]
    sub r12d, [rip + g_mt + 4*MI_4]
    cmp dword ptr [rip + g_csd], 0
    je 7f
    # the window's buttons as the desktop has them (GNOME's button-layout: close alone), round,
    # the close button last
    M r13d, MI_32
    test dword ptr [rip + g_win_buttons], 1
    jz 62f
    sub r12d, r13d
    mov edi, ID_WCLOSE
    mov esi, r12d
    mov r14d, IC_WCLOSE
    call .Ltb_wbtn
    test eax, UB_CLICK
    jz 62f
    call cmd_quit
62: test dword ptr [rip + g_win_buttons], 2
    jz 64f
    sub r12d, r13d
    mov edi, ID_WMAX
    mov esi, r12d
    mov r14d, IC_MAX
    test dword ptr [rip + g_win_states], 1
    jz 63f
    mov r14d, IC_RESTORE
63: call .Ltb_wbtn
    test eax, UB_CLICK
    jz 64f
    PCALL P_maximize
64: test dword ptr [rip + g_win_buttons], 4
    jz 65f
    sub r12d, r13d
    mov edi, ID_WMIN
    mov esi, r12d
    mov r14d, IC_MIN
    call .Ltb_wbtn
    test eax, UB_CLICK
    jz 65f
    PCALL P_minimize
65: sub r12d, [rip + g_mt + 4*MI_8]
7:  # settings, terminal and history buttons; in a narrow window the last two give their room to the tabs
    mov r13d, [rsp + 40]
    mov eax, r12d
    sub eax, [rsp + 60]
    M ecx, MI_64
    lea ecx, [rcx + rcx*2]
    sub eax, ecx
    mov [rsp + 64], eax         # the room past what the tabs, their button and Settings need
    sub r12d, r13d
    sub r12d, [rip + g_mt + 4*MI_2]
    mov edi, ID_SETTINGS_BTN
    mov esi, r12d
    mov edx, [rsp + 12]
    sub edx, r13d
    sar edx, 1
    mov ecx, r13d
    mov r8d, r13d
    mov r9d, IC_SLIDERS
    call ui_icon_btn
    mov r8d, eax
    mov edi, ID_SETTINGS_BTN
    mov esi, r12d
    M edx, MI_TITLE
    mov ecx, r13d
    call tip_note               # keeps the button flags in eax
    test eax, UB_CLICK
    jz 8f
    call cmd_toggle_settings
8:  cmp dword ptr [rip + g_git_on], 0
    je 9f
    M eax, MI_64
    cmp [rsp + 64], eax
    jl 9f
    sub r12d, r13d
    sub r12d, [rip + g_mt + 4*MI_2]
    mov edi, ID_GIT_BTN
    mov esi, r12d
    mov edx, [rsp + 12]
    sub edx, r13d
    sar edx, 1
    mov ecx, r13d
    mov r8d, r13d
    mov r9d, IC_CLOCK
    call ui_icon_btn
    mov r8d, eax
    mov edi, ID_GIT_BTN
    mov esi, r12d
    M edx, MI_TITLE
    mov ecx, r13d
    call tip_note               # keeps the button flags in eax
    mov ebx, eax
    # the changes source control lists, counted on it
    call scm_changes
    test eax, eax
    jz 84f
    mov ecx, 99
    cmp eax, ecx
    cmova eax, ecx
    lea rdi, [rsp + 44]
    mov esi, eax
    call fmt_u64
    mov byte ptr [rdi], 0
    lea rdi, [rsp + 44]
    call strlen
    lea rdi, [rip + g_face_mini]
    lea rsi, [rsp + 44]
    mov rdx, rax
    call text_width
    add eax, [rip + g_mt + 4*MI_8]
    mov ecx, [rip + g_face_mini + FACE_ascent]
    add ecx, [rip + g_face_mini + FACE_descent]
    M edx, MI_14
    cmp ecx, edx
    cmovl ecx, edx
    mov [rsp + 24], ecx         # the badge's height: its text's, MI_14 at least
    cmp eax, ecx
    cmovl eax, ecx
    mov r14d, eax               # the badge's width
    lea edi, [r12 + r13]
    sub edi, eax
    add edi, [rip + g_mt + 4*MI_3]
    mov [rsp + 16], edi
    mov esi, [rsp + 12]
    sub esi, r13d
    sar esi, 1
    sub esi, [rip + g_mt + 4*MI_2]
    mov [rsp + 20], esi
    mov edx, r14d
    mov r8d, ecx
    sar r8d, 1
    COLOR r9d, T_ACCENT
    call gfx_round_rect
    lea rdi, [rip + g_face_mini]
    mov esi, [rsp + 16]
    mov edx, [rsp + 20]
    mov ecx, r14d
    mov r8d, [rsp + 24]
    lea r9, [rsp + 44]
    COLOR eax, T_BG
    push rax
    push rax
    call ui_text_center
    add rsp, 16
84: test ebx, UB_CLICK
    jz 9f
    call cmd_toggle_git
9:  # the search button before them: Go to File
    M eax, MI_64
    add eax, [rip + g_mt + 4*MI_32]
    cmp [rsp + 64], eax
    jl 95f
    sub r12d, r13d
    sub r12d, [rip + g_mt + 4*MI_2]
    mov edi, ID_SEARCH
    mov esi, r12d
    mov edx, [rsp + 12]
    sub edx, r13d
    sar edx, 1
    mov ecx, r13d
    mov r8d, r13d
    mov r9d, IC_SEARCH
    call ui_icon_btn
    mov r8d, eax
    mov edi, ID_SEARCH
    mov esi, r12d
    M edx, MI_TITLE
    mov ecx, r13d
    call tip_note               # keeps the button flags in eax
    test eax, UB_CLICK
    jz 95f
    call cmd_quick_open
95: # the tabs, in what is left between; the button for a new terminal follows the last
    mov [rsp + 68], r12d
    mov edx, r12d
    sub edx, [rip + g_mt + 4*MI_16]
    sub edx, r13d
    mov edi, [rsp + 60]
    sub edx, edi
    jns 91f
    xor edx, edx
91: mov esi, [rsp + 4]
    mov ecx, [rsp + 12]
    call tabs_draw
    mov r12d, eax
    add r12d, [rip + g_mt + 4*MI_2]
    lea eax, [r12 + r13]        # no room left for the button: the palette still opens a terminal
    cmp eax, [rsp + 68]
    jg 92f
    mov edi, ID_TAB_NEW
    mov esi, r12d
    mov edx, [rsp + 12]
    sub edx, r13d
    sar edx, 1
    mov ecx, r13d
    mov r8d, r13d
    mov r9d, IC_PLUS
    call ui_icon_btn
    mov r8d, eax
    mov edi, ID_TAB_NEW
    mov esi, r12d
    M edx, MI_TITLE
    mov ecx, r13d
    call tip_note               # keeps the button flags in eax
    test eax, UB_CLICK
    jz 92f
    call cmd_new_terminal
92: # a press on a button must not start a window move: the compositor would take the release
    cmp dword ptr [rip + g_hot], 0
    jne 13f
    mov edi, ID_TITLE
    mov esi, [rsp]
    mov edx, [rsp + 4]
    mov ecx, [rsp + 8]
    mov r8d, [rsp + 12]
    call ui_btn
    test eax, UB_DOUBLE
    jz 11f
    PCALL P_maximize
    jmp 13f
11: test eax, UB_PRESS
    jz 12f
    PCALL P_move
    and dword ptr [rip + g_mdown], ~(1 << BTN_LEFT)   # the release goes to the compositor
    mov dword ptr [rip + g_active], 0
    jmp 13f
12: test eax, UB_RPRESS
    jz 13f
    mov edi, [rip + g_mx]
    mov esi, [rip + g_my]
    PCALL P_menu
13: cmp dword ptr [rip + g_hot], 0
    jne 14f
    mov eax, [rsp + 32]
    mov [rip + g_hot], eax
14: EPILOGUE
# a window button: edi id, esi x, r13d w, r14d icon -> eax UB bits. A disc under the icon, as
# GNOME's, lighter under the pointer and when pressed
.Ltb_wbtn:
    push rbx
    push r12
    push rbp
    mov r12d, esi
    xor edx, edx
    mov ecx, r13d
    M r8d, MI_TITLE
    call ui_btn
    mov ebx, eax
    mov edx, 28
    test ebx, UB_HOVER
    jz 1f
    mov edx, 48
    test ebx, UB_HELD
    jz 1f
    mov edx, 72
1:  COLOR edi, T_PANEL
    COLOR esi, T_FG
    call color_mix
    mov r9d, eax
    M edx, MI_24
    mov edi, r13d
    sub edi, edx
    sar edi, 1
    add edi, r12d
    M esi, MI_TITLE
    sub esi, edx
    sar esi, 1
    mov ecx, edx
    mov r8d, edx
    sar r8d, 1
    call gfx_round_rect
    mov edi, r14d
    mov esi, r12d
    xor edx, edx
    mov ecx, r13d
    M r8d, MI_TITLE
    COLOR r9d, T_FG
    call ui_icon_center
    mov eax, ebx
    pop rbp
    pop r12
    pop rbx
    ret

# project_btn(x, y, h, maxw): the name of the folder the tree shows, in the sidebar's header
FN project_btn
    PROLOGUE 48
    mov [rsp], edi
    mov [rsp + 4], esi
    mov [rsp + 8], edx
    mov [rsp + 12], ecx
    call explorer_root_name     # the folder the tree shows: the project's, or a terminal's
    test rax, rax
    jnz 1f
    mov rax, [rip + g_project_name]
    test rax, rax
    jnz 1f
    lea rax, [rip + .Lraftaar]
1:  mov [rsp + 16], rax
    mov rdi, rax
    call strlen
    lea rdi, [rip + g_face_ui]
    mov rsi, [rsp + 16]
    mov rdx, rax
    call text_width
    mov r15d, eax
    add r15d, [rip + g_mt + 4*MI_8]
    add r15d, [rip + g_mt + 4*MI_14]
    add r15d, [rip + g_mt + 4*MI_6]
    add r15d, [rip + g_mt + 4*MI_4]
    add r15d, [rip + g_mt + 4*MI_12]
    add r15d, [rip + g_mt + 4*MI_6]
    cmp r15d, [rsp + 12]
    cmovg r15d, [rsp + 12]      # w
    test r15d, r15d
    jle 9f
    mov r14d, [rsp]             # x
    M r12d, MI_28               # h
    mov r13d, [rsp + 8]
    sub r13d, r12d
    sar r13d, 1
    add r13d, [rsp + 4]         # y
    mov edi, r14d
    mov esi, [rsp + 4]
    mov edx, r15d
    mov ecx, [rsp + 8]
    call gfx_clip_push
    mov edi, IC_FOLDER
    mov esi, r14d
    add esi, [rip + g_mt + 4*MI_8]
    M ecx, MI_14
    mov edx, r12d
    sub edx, ecx
    sar edx, 1
    add edx, r13d
    COLOR r8d, T_MUTED
    call icon_draw
    lea rdi, [rip + g_face_ui]
    mov esi, r14d
    add esi, [rip + g_mt + 4*MI_8]
    add esi, [rip + g_mt + 4*MI_14]
    add esi, [rip + g_mt + 4*MI_6]
    mov edx, r13d
    mov ecx, r12d
    mov r8, [rsp + 16]
    COLOR r9d, T_PANEL_FG
    call ui_text_c
    call gfx_clip_pop
9:  EPILOGUE

# cmd_project_menu(): Open Folder, Open File and the recent folders, in a menu under the sidebar's header
FN cmd_project_menu
    push rax
    call ui_update_metrics      # a script may ask before the first frame has them
    pop rax
    M edi, MI_6
    M esi, MI_TITLE
    add esi, [rip + g_mt + 4*MI_6]
    add esi, [rip + g_mt + 4*MI_28]
    jmp project_menu_open

# sidebar_draw(x, y, w, h): the explorer. Source control is the history tab's, behind the title bar's
#   button, which counts its changes
sidebar_draw:
    jmp explorer_draw

# tabs_draw(x, y, w, h) -> eax the x after the last one: the title bar's tabs, a rounded one for each
#   group of views, named after the pane of it that had the keys
FN tabs_draw
    PROLOGUE 96
    mov [rsp], edi
    mov [rsp + 4], esi
    mov [rsp + 8], edx
    mov [rsp + 12], ecx
    call gfx_clip_push
    # wheel scrolls the strip
    mov edi, [rsp]
    mov esi, [rsp + 4]
    mov edx, [rsp + 8]
    mov ecx, [rsp + 12]
    call ui_in
    test eax, eax
    jz 1f
    mov eax, [rip + g_scroll_y]
    add eax, [rip + g_scroll_x]
    add [rip + g_tabscroll], eax
1:  cmp dword ptr [rip + g_tabscroll], 0
    jge 2f
    mov dword ptr [rip + g_tabscroll], 0
2:  mov r12d, [rsp]
    sub r12d, [rip + g_tabscroll]
    M eax, MI_28
    mov [rsp + 68], eax         # a tab's height
    mov ecx, [rsp + 12]
    sub ecx, eax
    sar ecx, 1
    add ecx, [rsp + 4]
    mov [rsp + 64], ecx         # and its y
    xor ebx, ebx                # the first view of the group
.Ltd_tab:
    cmp rbx, [rip + g_tabs + VEC_len]
    jae .Ltd_done
    mov rdi, rbx
    call group_last
    mov [rsp + 40], rax
    mov rdi, rbx
    call group_shown
    mov [rsp + 48], rax         # the view the tab stands for
    xor ecx, ecx
    mov rax, [rip + g_tab_cur]
    cmp rax, rbx
    jb 3f
    cmp rax, [rsp + 40]
    ja 3f
    mov ecx, 1
    mov [rsp + 48], rax
3:  mov [rsp + 56], ecx         # the active tab
    mov rdi, [rsp + 48]
    call tab_at
    mov r15, rax
    mov rdi, [rsp + 48]
    call app_tab_label
    mov r13, rax
    mov rdi, r13
    call strlen
    mov r14, rax
    lea rdi, [rip + g_face_small]
    mov rsi, r13
    mov rdx, r14
    call text_width
    M ecx, MI_64                # long names are cut
    lea ecx, [rcx + rcx*2]
    cmp eax, ecx
    cmovg eax, ecx
    mov [rsp + 60], eax         # the label's width
    add eax, [rip + g_mt + 4*MI_10]
    add eax, [rip + g_mt + 4*MI_16]
    add eax, [rip + g_mt + 4*MI_6]
    add eax, [rip + g_mt + 4*MI_6]
    add eax, [rip + g_mt + 4*MI_16]
    add eax, [rip + g_mt + 4*MI_6]
    mov [rsp + 16], eax         # tab width
    # reveal the active tab
    cmp dword ptr [rsp + 56], 0
    je 5f
    cmp dword ptr [rip + g_tabscroll_reveal], 0
    je 5f
    mov dword ptr [rip + g_tabscroll_reveal], 0
    mov ecx, r12d
    sub ecx, [rsp]
    jns 41f
    add [rip + g_tabscroll], ecx
    mov dword ptr [rip + g_dirty], 1
41: mov ecx, r12d
    add ecx, eax
    mov edx, [rsp]
    add edx, [rsp + 8]
    sub ecx, edx
    jle 5f
    add [rip + g_tabscroll], ecx
    mov dword ptr [rip + g_dirty], 1
5:  # interaction
    mov edi, [rsp + 48]
    add edi, ID_TAB
    mov esi, r12d
    mov edx, [rsp + 64]
    mov ecx, [rsp + 16]
    mov r8d, [rsp + 68]
    call ui_btn
    mov [rsp + 20], eax
    test eax, UB_PRESS
    jz 6f
    mov rdi, [rsp + 48]
    call app_activate_tab
    mov dword ptr [rsp + 56], 1
6:  test dword ptr [rsp + 20], UB_HOVER
    jz 61f
    test dword ptr [rip + g_pressed], 1 << BTN_MIDDLE
    jz 61f
    mov rdi, [rsp + 48]
    call app_close_tab
    jmp .Ltd_closed
61: # background: the active tab stands out of the bar, a hovered one a little
    cmp dword ptr [rsp + 56], 0
    je 7f
    COLOR edi, T_PANEL
    COLOR esi, T_FG
    mov edx, 44
    call color_mix
    mov [rsp + 72], eax
    COLOR edi, T_PANEL
    COLOR esi, T_FG
    mov edx, 24
    call color_mix
    mov edi, r12d
    mov esi, [rsp + 64]
    mov edx, [rsp + 16]
    mov ecx, [rsp + 68]
    M r8d, MI_RADIUS
    mov r9d, [rsp + 72]
    push rax
    push rax
    call gfx_frame
    add rsp, 16
    jmp 8f
7:  test dword ptr [rsp + 20], UB_HOVER
    jz 8f
    COLOR edi, T_PANEL
    COLOR esi, T_FG
    mov edx, 14
    call color_mix
    mov edi, r12d
    mov esi, [rsp + 64]
    mov edx, [rsp + 16]
    mov ecx, [rsp + 68]
    M r8d, MI_RADIUS
    mov r9d, eax
    call gfx_round_rect
8:  # the icon: a file's by its name, else what the view is
    COLOR r8d, T_MUTED
    cmp dword ptr [rsp + 56], 0
    je 80f
    COLOR r8d, T_FG
80: mov [rsp + 76], r8d
    mov rax, [r15 + TAB_doc]
    test rax, rax
    jz 81f
    mov rdi, [rax + DOC_name]
    call file_icon
    lea rcx, [rip + g_theme]
    mov r8d, [rcx + rdx*4]
    mov edi, eax
    jmp 83f
81: mov edi, IC_TERMINAL
    cmp qword ptr [r15 + TAB_kind], TAB_TERM
    je 82f
    mov edi, IC_CLOCK
    cmp qword ptr [r15 + TAB_kind], TAB_GIT
    je 82f
    mov edi, IC_HOME
    cmp qword ptr [r15 + TAB_kind], TAB_HOME
    je 82f
    mov edi, IC_SLIDERS
82: mov r8d, [rsp + 76]
83: mov esi, r12d
    add esi, [rip + g_mt + 4*MI_10]
    M ecx, MI_16
    mov edx, [rsp + 68]
    sub edx, ecx
    sar edx, 1
    add edx, [rsp + 64]
    call icon_draw
    # text: git status color, else muted (foreground when active)
    mov rax, [r15 + TAB_doc]
    test rax, rax
    jz 84f
    mov rdi, [rax + DOC_path]
    xor eax, eax
    test rdi, rdi
    jz 84f
    call git_path_color
84: test eax, eax
    jnz 85f
    mov eax, [rsp + 76]
85: lea rdi, [rip + g_face_small]
    mov esi, r12d
    add esi, [rip + g_mt + 4*MI_10]
    add esi, [rip + g_mt + 4*MI_16]
    add esi, [rip + g_mt + 4*MI_6]
    mov edx, [rsp + 64]
    mov ecx, [rsp + 68]
    mov r8, r13
    mov r9, r14
    mov r10d, [rsp + 60]
    inc r10d
    push r10
    push rax
    call ui_text_v_fit
    add rsp, 16
    # close button / modified dot
    M r13d, MI_16
    mov esi, r12d
    add esi, [rsp + 16]
    sub esi, r13d
    sub esi, [rip + g_mt + 4*MI_6]
    mov [rsp + 24], esi
    mov edx, [rsp + 68]
    sub edx, r13d
    sar edx, 1
    add edx, [rsp + 64]
    mov [rsp + 28], edx
    mov edi, [rsp + 48]
    add edi, ID_TABX
    mov ecx, r13d
    mov r8d, r13d
    call ui_btn
    mov [rsp + 32], eax
    xor r14d, r14d              # modified?
    cmp qword ptr [r15 + TAB_kind], TAB_DOC
    jne 86f
    mov rdi, [r15 + TAB_doc]
    call doc_dirty
    mov r14d, eax
86: test dword ptr [rsp + 32], UB_HOVER
    jnz 88f
    test r14d, r14d
    jz 87f
    # dot
    M ecx, MI_6
    mov edi, [rsp + 24]
    mov esi, [rsp + 28]
    mov eax, r13d
    sub eax, ecx
    sar eax, 1
    add edi, eax
    add esi, eax
    mov edx, ecx
    mov r8d, ecx
    shr r8d, 1
    mov r9d, [rsp + 76]
    call gfx_round_rect
    jmp .Ltd_next
87: cmp dword ptr [rsp + 56], 0
    jne 88f
    test dword ptr [rsp + 20], UB_HOVER
    jz .Ltd_next
88: # x
    test dword ptr [rsp + 32], UB_HOVER
    jz 89f
    mov edi, [rsp + 24]
    mov esi, [rsp + 28]
    mov edx, r13d
    mov ecx, r13d
    M r8d, MI_4
    COLOR r9d, T_HOVER
    call gfx_round_rect
89: mov edi, IC_CLOSE
    mov esi, [rsp + 24]
    mov edx, [rsp + 28]
    mov ecx, r13d
    mov r8d, r13d
    COLOR r9d, T_MUTED
    call ui_icon_center
    test dword ptr [rsp + 32], UB_CLICK
    jz .Ltd_next
    mov rdi, [rsp + 48]
    call app_close_tab
    jmp .Ltd_closed
.Ltd_next:
    add r12d, [rsp + 16]
    add r12d, [rip + g_mt + 4*MI_2]
    mov rbx, [rsp + 40]
    inc rbx
    jmp .Ltd_tab
.Ltd_done:
    # the strip cannot scroll past its end (a wheel, a tab closed); measured as it is drawn, so a
    # change shows in the next frame
    mov eax, r12d
    add eax, [rip + g_tabscroll]
    sub eax, [rsp]
    sub eax, [rsp + 8]
    xor ecx, ecx
    cmp eax, ecx
    cmovl eax, ecx
    cmp [rip + g_tabscroll], eax
    jle .Ltd_closed
    mov [rip + g_tabscroll], eax
    mov dword ptr [rip + g_dirty], 1
.Ltd_closed:                    # a tab closed while drawn: the strip is measured again next frame
    call gfx_clip_pop
    mov eax, [rsp]
    add eax, [rsp + 8]
    cmp r12d, eax
    cmovl eax, r12d
    cmp eax, [rsp]
    cmovl eax, [rsp]
    EPILOGUE

# crumbs_draw(x, y, h, right) -> eax the x after them: the folders down to what the tab shows, from
#   Home when it is under it: a terminal's current folder, a file's path, else the project's folder.
#   The first ones give way to "…" when they would pass `right`. As in Terax they are buttons: in a
#   terminal a folder is where the shell goes (cd), and the folder it is in lists its folders to go
#   into; elsewhere a folder lists what it holds, a file to open or a folder to look into
crumbs_draw:
    PROLOGUE 64
    mov [rsp], edi
    mov [rsp + 4], esi
    mov [rsp + 8], edx
    mov [rsp + 12], ecx
    mov r12d, edi
    mov dword ptr [rip + crumb_term], 0
    mov dword ptr [rip + crumb_leaf], 0
    cmp dword ptr [rip + g_term_open], 0
    je 1f
    lea rdi, [rip + crumb_path]
    call term_shown_cwd
    test rax, rax
    jle 1f
    mov dword ptr [rip + crumb_term], 1
    jmp 3f
1:  mov rsi, [rip + g_file]
    test rsi, rsi
    jz 2f
    mov rsi, [rsi + DOC_path]
    test rsi, rsi
    jz 2f
    mov dword ptr [rip + crumb_leaf], 1
    jmp 21f
2:  mov rsi, [rip + g_project]
    test rsi, rsi
    jz .Lcr_ret
21: mov rbx, rsi
    mov rdi, rsi
    call strlen
    cmp rax, 4000
    ja .Lcr_ret
    lea rdi, [rip + crumb_path]
    mov rsi, rbx
    call cstr_copy
3:  lea rbx, [rip + crumb_path]
    mov dword ptr [rsp + 16], 0 # it is under Home
    mov dword ptr [rip + crumb_homelen], 0
    lea rdi, [rip + .Lenv_home]
    call getenv
    test rax, rax
    jz 30f
    mov r13, rax
    mov rdi, rax
    call strlen
    mov r14, rax
    cmp r14, 1
    jbe 30f
    mov rdi, rbx
    call strlen
    mov rdi, rbx
    mov rsi, rax
    mov rdx, r13
    mov rcx, r14
    call str_starts
    test eax, eax
    jz 30f
    mov al, [rbx + r14]
    test al, al
    jz 22f
    cmp al, '/'
    jne 30f
22: add rbx, r14
    mov [rip + crumb_homelen], r14d
    mov dword ptr [rsp + 16], 1
30: xor r15d, r15d              # folders
    lea r14, [rip + crumb_segs]
4:  cmp byte ptr [rbx], '/'
    jne 5f
    inc rbx
    jmp 4b
5:  cmp byte ptr [rbx], 0
    je 7f
    mov rdi, rbx
6:  mov al, [rbx]
    test al, al
    jz 61f
    cmp al, '/'
    je 61f
    inc rbx
    jmp 6b
61: cmp r15d, 64
    jae 7f
    mov rax, r15
    shl rax, 4
    mov [r14 + rax], rdi
    mov rcx, rbx
    sub rcx, rdi
    mov [r14 + rax + 8], ecx
    inc r15d
    jmp 4b
7:  mov [rip + crumb_nsegs], r15d
    # their widths, each with the mark before it
    M eax, MI_10
    add eax, [rip + g_mt + 4*MI_12]
    mov [rsp + 28], eax
    xor ebx, ebx
    mov dword ptr [rsp + 20], 0
8:  cmp ebx, r15d
    jae 9f
    mov rax, rbx
    shl rax, 4
    lea rdi, [rip + g_face_mini]
    mov rsi, [r14 + rax]
    mov edx, [r14 + rax + 8]
    call text_width
    mov rcx, rbx
    shl rcx, 4
    mov [r14 + rcx + 12], eax
    add eax, [rsp + 28]
    add [rsp + 20], eax
    inc ebx
    jmp 8b
9:  mov r13d, [rsp + 12]        # the room
    sub r13d, r12d
    sub r13d, [rip + g_mt + 4*MI_64]
    sub r13d, [rip + g_mt + 4*MI_24]
    xor ebx, ebx                # the first folder shown
10: mov eax, [rsp + 20]
    cmp eax, r13d
    jle 11f
    lea ecx, [rbx + 1]
    cmp ecx, r15d
    jae 11f
    mov rcx, rbx
    shl rcx, 4
    mov eax, [r14 + rcx + 12]
    add eax, [rsp + 28]
    sub [rsp + 20], eax
    inc ebx
    jmp 10b
11: mov [rsp + 24], ebx
    mov [rip + crumb_first], ebx
    cmp dword ptr [rsp + 16], 0
    je 13f
    # Home: its icon and name, one button
    lea rdi, [rip + g_face_mini]
    lea rsi, [rip + .Lcr_home]
    mov edx, 4
    call text_width
    add eax, [rip + g_mt + 4*MI_12]
    add eax, [rip + g_mt + 4*MI_5]
    mov esi, eax
    mov edi, ID_CRUMB + 101
    call .Lcr_btn
    mov [rsp + 32], eax
    mov edi, IC_HOME
    mov esi, r12d
    M ecx, MI_12
    mov edx, [rsp + 8]
    sub edx, ecx
    sar edx, 1
    add edx, [rsp + 4]
    mov r8d, r13d
    call icon_draw
    mov eax, r12d
    mov [rsp + 36], eax
    add r12d, [rip + g_mt + 4*MI_12]
    add r12d, [rip + g_mt + 4*MI_5]
    lea rdi, [rip + g_face_mini]
    mov esi, r12d
    mov edx, [rsp + 4]
    mov ecx, [rsp + 8]
    lea r8, [rip + .Lcr_home]
    mov r9d, r13d
    call ui_text_c
    mov r12d, eax
    test dword ptr [rsp + 32], UB_CLICK
    jz 13f
    mov edi, -1
    mov esi, [rsp + 36]
    call crumb_act
13: cmp dword ptr [rsp + 24], 0
    je 14f
    # the folders left out: a button that lists them
    call .Lcr_sep
    M esi, MI_14
    mov edi, ID_CRUMB + 100
    call .Lcr_btn
    mov [rsp + 32], eax
    mov edi, IC_MORE
    mov esi, r12d
    M ecx, MI_14
    mov edx, [rsp + 8]
    sub edx, ecx
    sar edx, 1
    add edx, [rsp + 4]
    mov r8d, r13d
    call icon_draw
    test dword ptr [rsp + 32], UB_CLICK
    jz 131f
    mov edi, r12d
    call crumb_more
131:add r12d, [rip + g_mt + 4*MI_14]
14: mov ebx, [rsp + 24]
15: cmp ebx, r15d
    jae .Lcr_ret
    cmp r12d, [rsp]
    je 16f
    call .Lcr_sep
16: # a file's name is the last and no button
    mov dword ptr [rsp + 32], 0
    lea ecx, [rbx + 1]
    cmp ecx, r15d
    jne 161f
    COLOR r13d, T_FG
    cmp dword ptr [rip + crumb_leaf], 0
    jne 17f
161:mov rcx, rbx
    shl rcx, 4
    mov esi, [r14 + rcx + 12]
    lea edi, [rbx + ID_CRUMB]
    call .Lcr_btn
    mov [rsp + 32], eax
    lea ecx, [rbx + 1]
    cmp ecx, r15d
    jne 17f
    COLOR r13d, T_FG            # where it is
17: mov rcx, rbx
    shl rcx, 4
    lea rdi, [rip + g_face_mini]
    mov esi, r12d
    mov [rsp + 36], esi
    mov edx, [rsp + 4]
    mov r8, [r14 + rcx]
    mov r9d, [r14 + rcx + 8]
    mov ecx, [rsp + 8]
    push r13
    push r13
    call ui_text_v
    add rsp, 16
    mov r12d, eax
    test dword ptr [rsp + 32], UB_CLICK
    jz 18f
    mov edi, ebx
    mov esi, [rsp + 36]
    call crumb_act
18: inc ebx
    jmp 15b
.Lcr_ret:
    mov eax, r12d
    EPILOGUE
# the mark between two folders, at r12d
.Lcr_sep:
    sub rsp, 8
    add r12d, [rip + g_mt + 4*MI_6]
    mov edi, IC_CHEV_R
    mov esi, r12d
    M ecx, MI_10
    mov edx, [rsp + 16 + 8]
    sub edx, ecx
    sar edx, 1
    add edx, [rsp + 16 + 4]
    COLOR r8d, T_MUTED
    call icon_draw
    add r12d, [rip + g_mt + 4*MI_10]
    add r12d, [rip + g_mt + 4*MI_6]
    add rsp, 8
    ret
# a folder's button around what is drawn at r12d: edi id, esi the width -> eax UB_* bits, r13d the
# color to draw it in; under the pointer it is lit
.Lcr_btn:
    push rbx
    mov eax, r12d
    sub eax, [rip + g_mt + 4*MI_4]
    mov [rip + crumb_r], eax
    mov eax, [rsp + 16 + 4]
    add eax, [rip + g_mt + 4*MI_5]
    mov [rip + crumb_r + 4], eax
    add esi, [rip + g_mt + 4*MI_8]
    mov [rip + crumb_r + 8], esi
    mov eax, [rsp + 16 + 8]
    sub eax, [rip + g_mt + 4*MI_10]
    mov [rip + crumb_r + 12], eax
    mov esi, [rip + crumb_r]
    mov edx, [rip + crumb_r + 4]
    mov ecx, [rip + crumb_r + 8]
    mov r8d, eax
    call ui_btn
    mov ebx, eax
    COLOR r13d, T_MUTED
    test ebx, UB_HOVER
    jz 1f
    COLOR r13d, T_FG
    mov dword ptr [rip + g_cursor], CUR_POINTER
    mov edi, [rip + crumb_r]
    mov esi, [rip + crumb_r + 4]
    mov edx, [rip + crumb_r + 8]
    mov ecx, [rip + crumb_r + 12]
    M r8d, MI_4
    COLOR r9d, T_HOVER
    call gfx_round_rect
1:  mov eax, ebx
    pop rbx
    ret

# crumb_act(folder or -1 for Home, x): a folder of the status bar was clicked
crumb_act:
    PROLOGUE
    mov r12d, edi
    mov r13d, esi
    mov eax, [rip + crumb_homelen]
    test r12d, r12d
    js 1f
    lea rcx, [rip + crumb_segs]
    movsxd rdx, r12d
    shl rdx, 4
    mov rax, [rcx + rdx]
    mov edx, [rcx + rdx + 8]
    add rax, rdx
    lea rcx, [rip + crumb_path]
    sub rax, rcx
1:  mov ebx, eax                # the path down to it
    lea rdi, [rip + crumb_tmp]
    lea rsi, [rip + crumb_path]
    mov rdx, rbx
    call memcpy
    lea rax, [rip + crumb_tmp]
    mov byte ptr [rax + rbx], 0
    test ebx, ebx
    jnz 2f
    mov word ptr [rax], 0x002f
2:  # the shell goes there; the folder it is in lists its folders instead
    cmp dword ptr [rip + crumb_term], 0
    je 4f
    lea eax, [r12 + 1]
    cmp eax, [rip + crumb_nsegs]
    je 4f
    lea rdi, [rip + crumb_tmp]
    call term_cd
    jmp 9f
4:  lea rdi, [rip + crumb_tmp]
    mov esi, r13d
    call crumb_menu
9:  EPILOGUE

# crumb_more(x): the folders "…" stands for, in a menu
crumb_more:
    PROLOGUE
    mov [rip + crumb_x], edi
    lea r12, [rip + crumb_names]
    lea r13, [rip + crumb_items]
    xor ebx, ebx
1:  cmp ebx, [rip + crumb_first]
    jae 2f
    cmp ebx, CRUMB_SHOW
    jae 2f
    lea rcx, [rip + crumb_segs]
    mov rax, rbx
    shl rax, 4
    mov rsi, [rcx + rax]
    mov edx, [rcx + rax + 8]
    mov r14d, edx
    mov rdi, r12
    call memcpy
    mov byte ptr [r12 + r14], 0
    mov [r13], r12
    lea rax, [rip + crumb_more_pick]
    mov [r13 + 8], rax
    lea r12, [r12 + r14 + 1]
    add r13, 16
    inc ebx
    jmp 1b
2:  mov qword ptr [r13], 0
    mov qword ptr [r13 + 8], 0
    mov edi, ebx
    call crumb_show
    EPILOGUE

crumb_more_pick:
    mov edi, [rip + g_menu_index]
    mov esi, [rip + crumb_x]
    jmp crumb_act

# crumb_show(items): crumb_items as a menu standing on the status bar at crumb_x
crumb_show:
    push rbx
    M eax, MI_28                # an item's height (explorer_menu_draw)
    imul eax, edi
    add eax, [rip + g_mt + 4*MI_12]
    mov edx, [rip + g_cv + CV_h]
    sub edx, [rip + g_mt + 4*MI_STATUS]
    sub edx, eax
    jns 1f
    xor edx, edx
1:  lea rdi, [rip + crumb_items]
    mov esi, [rip + crumb_x]
    call ctx_menu_open
    pop rbx
    ret

# crumb_menu(folder, x): what the folder holds, its folders first; for a terminal its folders alone
crumb_menu:
    PROLOGUE 16
    mov [rip + crumb_x], esi
    mov rsi, rdi
    lea rdi, [rip + crumb_dir]
    call cstr_copy
    xor r13d, r13d              # entries
    lea r14, [rip + crumb_names]
    lea rdi, [rip + crumb_dir]
    mov esi, O_RDONLY | O_DIRECTORY | O_CLOEXEC
    xor edx, edx
    SYS SYS_open
    test eax, eax
    js .Lcm_items
    mov r12d, eax
.Lcm_read:
    mov edi, r12d
    lea rsi, [rip + crumb_buf]
    mov edx, CRUMB_BUF
    SYS SYS_getdents64
    test eax, eax
    jle .Lcm_close
    mov r15d, eax
    xor ebx, ebx
.Lcm_ent:
    cmp ebx, r15d
    jae .Lcm_read
    lea rcx, [rip + crumb_buf]
    add rcx, rbx
    movzx eax, word ptr [rcx + 16]
    add ebx, eax
    cmp byte ptr [rcx + 19], '.'
    je .Lcm_ent
    cmp r13d, CRUMB_MAX
    jae .Lcm_ent
    mov [rsp], rcx
    movzx eax, byte ptr [rcx + 18]
    cmp eax, 8
    je 2f
    cmp eax, 4
    mov eax, 1
    je 3f
    # a link, or a file system that does not say: ask
    lea rdi, [rip + crumb_dir]
    mov rsi, [rsp]
    add rsi, 19
    call path_join_tmp
    mov rdi, rax
    call file_is_dir
    jmp 3f
2:  xor eax, eax
3:  mov [rsp + 8], eax
    test eax, eax
    jnz 4f
    cmp dword ptr [rip + crumb_term], 0
    jne .Lcm_ent
4:  mov rdi, [rsp]
    add rdi, 19
    call strlen
    lea rcx, [r14 + rax + 4]
    lea rdx, [rip + crumb_names + CRUMB_BLOB]
    cmp rcx, rdx
    jae .Lcm_ent
    lea rcx, [rip + crumb_ptr]
    mov [rcx + r13*8], r14
    lea rcx, [rip + crumb_isdir]
    mov edx, [rsp + 8]
    mov [rcx + r13], dl
    mov rdi, r14
    mov rsi, [rsp]
    add rsi, 19
    call cstr_copy
    cmp dword ptr [rsp + 8], 0
    je 5f
    mov word ptr [rax], 0x002f  # a folder's name ends in /
    inc rax
5:  lea r14, [rax + 1]
    inc r13d
    jmp .Lcm_ent
.Lcm_close:
    mov edi, r12d
    SYS SYS_close
    # folders first, each kind by name
    xor ebx, ebx
6:  lea eax, [rbx + 1]
    cmp eax, r13d
    jae .Lcm_items
    mov r12d, eax
7:  cmp r12d, r13d
    jae 10f
    lea rcx, [rip + crumb_isdir]
    movzx eax, byte ptr [rcx + r12]
    movzx edx, byte ptr [rcx + rbx]
    cmp eax, edx
    ja 9f
    jb 91f
    lea rcx, [rip + crumb_ptr]
    mov rsi, [rcx + r12*8]
    mov rdi, [rcx + rbx*8]
8:  mov al, [rsi]
    mov dl, [rdi]
    cmp al, dl
    jb 9f
    ja 91f
    test al, al
    jz 91f
    inc rsi
    inc rdi
    jmp 8b
9:  lea rcx, [rip + crumb_ptr]
    mov rax, [rcx + r12*8]
    mov rdx, [rcx + rbx*8]
    mov [rcx + rbx*8], rax
    mov [rcx + r12*8], rdx
    lea rcx, [rip + crumb_isdir]
    mov al, [rcx + r12]
    mov dl, [rcx + rbx]
    mov [rcx + rbx], al
    mov [rcx + r12], dl
91: inc r12d
    jmp 7b
10: inc ebx
    jmp 6b
.Lcm_items:
    lea r14, [rip + crumb_items]
    xor ebx, ebx
11: cmp ebx, r13d
    jae 12f
    cmp ebx, CRUMB_SHOW
    jae 12f
    lea rcx, [rip + crumb_ptr]
    mov rax, [rcx + rbx*8]
    mov [r14], rax
    lea rax, [rip + crumb_pick]
    mov [r14 + 8], rax
    add r14, 16
    inc ebx
    jmp 11b
12: test ebx, ebx
    jnz 13f
    lea rax, [rip + .Lcr_empty]
    mov [r14], rax
    lea rax, [rip + crumb_none]
    mov [r14 + 8], rax
    add r14, 16
    inc ebx
13: mov qword ptr [r14], 0
    mov qword ptr [r14 + 8], 0
    mov edi, ebx
    call crumb_show
    EPILOGUE

crumb_none:
    ret

# crumb_pick(): an entry of a folder's menu: the shell goes into a folder (elsewhere the folder's own
#   menu opens), a file opens
crumb_pick:
    PROLOGUE
    mov ebx, [rip + g_menu_index]
    lea rdi, [rip + crumb_tmp]
    lea rsi, [rip + crumb_dir]
    call cstr_copy
    cmp byte ptr [rax - 1], '/'
    je 1f
    mov byte ptr [rax], '/'
    inc rax
1:  mov rdi, rax
    lea rcx, [rip + crumb_ptr]
    mov rsi, [rcx + rbx*8]
    call cstr_copy
    lea rcx, [rip + crumb_isdir]
    cmp byte ptr [rcx + rbx], 0
    je 3f
    mov byte ptr [rax - 1], 0   # the name's /
    cmp dword ptr [rip + crumb_term], 0
    je 2f
    lea rdi, [rip + crumb_tmp]
    call term_cd
    jmp 9f
2:  lea rdi, [rip + crumb_tmp]
    mov esi, [rip + crumb_x]
    call crumb_menu
    jmp 9f
3:  lea rdi, [rip + crumb_tmp]
    call app_open_path
9:  EPILOGUE

# statusbar_draw(x, y, w, h)
FN statusbar_draw
    PROLOGUE 64
    mov [rsp], edi
    mov [rsp + 4], esi
    mov [rsp + 8], edx
    mov [rsp + 12], ecx
    COLOR r8d, T_PANEL
    call gfx_fill
    mov edi, [rsp]
    mov esi, [rsp + 4]
    mov edx, [rsp + 8]
    M ecx, MI_1
    COLOR r8d, T_BORDER
    call gfx_fill
    # the updater's item at the right end; the rest keeps left of it
    mov edi, [rsp]
    add edi, [rsp + 8]
    sub edi, [rip + g_mt + 4*MI_12]
    mov esi, [rsp + 4]
    mov edx, [rsp + 12]
    call statusbar_update
    mov [rsp + 20], eax
    # Keep branch and position glyphs out of the updater's reserved area.
    mov edx, eax
    sub edx, [rsp]
    add edx, [rip + g_mt + 4*MI_12]
    mov edi, [rsp]
    mov esi, [rsp + 4]
    mov ecx, [rsp + 12]
    call gfx_clip_push
    # the branch at the left end; the file's items follow it
    mov edi, [rsp]
    mov esi, [rsp + 4]
    mov edx, [rsp + 12]
    mov ecx, [rsp + 20]
    add ecx, [rip + g_mt + 4*MI_12]
    call statusbar_branch
    mov [rsp + 24], eax
    call app_image
    test rax, rax
    jz 1f
    mov rdi, [rip + g_file]
    mov esi, [rsp + 24]
    sub esi, [rip + g_mt + 4*MI_12]
    mov edx, [rsp + 4]
    mov ecx, [rsp + 20]
    add ecx, [rip + g_mt + 4*MI_12]
    sub ecx, esi
    mov r8d, [rsp + 12]
    call iv_status
    jmp 9f
1:  mov rbx, [rip + g_doc]
    test rbx, rbx
    jz 96f
    lea rdi, [rip + tmp_sb]
    call sb_clear
    # "Ln x, Col y"
    lea rdi, [rip + tmp_sb]
    lea rsi, [rip + .Lln]
    call sb_push_cstr
    mov rdi, rbx
    mov rsi, [rbx + DOC_cur]
    call doc_line_of
    lea rdi, [rip + tmp_sb]
    lea rsi, [rax + 1]
    call sb_push_u64
    lea rdi, [rip + tmp_sb]
    lea rsi, [rip + .Lcol]
    call sb_push_cstr
    mov rdi, rbx
    mov rsi, [rbx + DOC_cur]
    call doc_col_of
    lea rdi, [rip + tmp_sb]
    lea esi, [rax + 1]
    call sb_push_u64
    mov rdi, rbx
    call vim_sel
    sub rdx, rax
    jz 1f
    mov r12, rdx
    lea rdi, [rip + tmp_sb]
    lea rsi, [rip + .Lsel_open]
    call sb_push_cstr
    lea rdi, [rip + tmp_sb]
    mov rsi, r12
    call sb_push_u64
    lea rdi, [rip + tmp_sb]
    lea rsi, [rip + .Lsel_close]
    call sb_push_cstr
1:  lea rdi, [rip + tmp_sb]     # a string for its item at the right
    xor esi, esi
    call sb_push_byte
    mov esi, [rsp + 24]
    mov [rsp + 16], esi
    # vim: the command line in place of the position, else the mode and the keys typed so far
    cmp dword ptr [rip + cfg_vim], 0
    je 11f
    cmp dword ptr [rip + g_vim_cmdline], 0
    je 10f
    mov edi, [rsp + 16]
    mov esi, [rsp + 4]
    mov edx, [rsp + 12]
    call vim_cmdline_draw
    mov eax, [rsp + 20]
    mov [rsp + 28], eax        # command line occupies the available status area
    jmp 12f
10: call vim_status
    lea rdi, [rip + g_face_mini]
    mov esi, [rsp + 16]
    mov edx, [rsp + 4]
    mov ecx, [rsp + 12]
    mov r8, rax
    COLOR r9d, T_ACCENT
    call ui_text_c
    add eax, [rip + g_mt + 4*MI_16]
    mov [rsp + 16], eax
11: # the path down to the file; the position is the first of the items at the right
    mov edi, [rsp + 16]
    mov esi, [rsp + 4]
    mov edx, [rsp + 12]
    mov ecx, [rsp + 20]
    M eax, MI_64
    imul eax, eax, 5
    sub ecx, eax
    call crumbs_draw
    add eax, [rip + g_mt + 4*MI_16]
    mov [rsp + 28], eax        # optional metadata must stay after the path
12: # right side: language, indentation, eol, encoding
    mov r12d, [rsp + 20]
    lea r13, [rip + .Lutf8]
    call .Lsb_item
    lea r13, [rip + .Llf]
    cmp dword ptr [rbx + DOC_crlf], 0
    je 2f
    lea r13, [rip + .Lcrlf]
2:  call .Lsb_item
    lea r13, [rip + .Ltabs]
    cmp dword ptr [rip + cfg_insert_spaces], 0
    je 3f
    lea rdi, [rsp + 32]
    lea rsi, [rip + .Lspaces]
    call cstr_copy
    mov rdi, rax
    mov esi, [rip + cfg_tab_width]
    call fmt_u64
    mov byte ptr [rdi], 0      # fmt_u64 leaves rdi after the digits
    lea r13, [rsp + 32]
3:  call .Lsb_item
    lea r13, [rip + .Lplain]
    mov rax, [rbx + DOC_lang]
    test rax, rax
    jz 4f
    mov r13, [rax + GR_name]
4:  mov r14d, r12d
    call .Lsb_item
    cmp r12d, r14d
    je 95f                    # no picker hitbox for a label that did not fit
    # the language name opens the language picker
    mov esi, r12d
    add esi, [rip + g_mt + 4*MI_12]
    mov ecx, r14d
    sub ecx, esi
    add ecx, [rip + g_mt + 4*MI_8]
    mov edi, ID_STATUS
    mov edx, [rsp + 4]
    M r8d, MI_STATUS
    call ui_btn
    test eax, UB_HOVER
    jz 5f
    mov dword ptr [rip + g_cursor], CUR_POINTER
5:  test eax, UB_CLICK
    jz 95f
    call cmd_select_language
95: mov r13, [rip + tmp_sb + SB_ptr]
    call .Lsb_item
    jmp 9f
96: # no text: the path of what the tab shows, or the project's folder
    mov edi, [rsp + 24]
    mov esi, [rsp + 4]
    mov edx, [rsp + 12]
    mov ecx, [rsp + 20]
    call crumbs_draw
9:  call gfx_clip_pop
    EPILOGUE
# statusbar_branch(x, y, h, right) -> eax the x where the bar's items start. The branch is not here:
# source control names it, in the history tab
statusbar_branch:
    M eax, MI_12
    add eax, edi
    ret

# statusbar_update(right, y, h) -> eax the right edge left of it: the updater's item, when it has one
statusbar_update:
    PROLOGUE 16
    mov r12d, edi
    mov [rsp], esi
    mov [rsp + 4], edx
    call update_item
    test rax, rax
    jz 9f
    mov r13, rax
    mov rdi, rax
    call strlen
    lea rdi, [rip + g_face_mini]
    mov rsi, r13
    mov rdx, rax
    call text_width
    add eax, [rip + g_mt + 4*MI_16]
    mov r14d, eax               # w
    sub r12d, eax               # x
    mov eax, [rsp]
    add eax, [rip + g_mt + 4*MI_3]
    mov [rsp + 8], eax          # box y
    mov eax, [rsp + 4]
    sub eax, [rip + g_mt + 4*MI_6]
    mov [rsp + 12], eax         # box h
    mov edi, ID_STATUS + 1
    mov esi, r12d
    mov edx, [rsp + 8]
    mov ecx, r14d
    mov r8d, [rsp + 12]
    call ui_btn
    mov r15d, eax
    test eax, UB_HOVER
    jz 1f
    mov dword ptr [rip + g_cursor], CUR_POINTER
1:  mov edi, r12d
    mov esi, [rsp + 8]
    mov edx, r14d
    mov ecx, [rsp + 12]
    M r8d, MI_RADIUS
    COLOR r9d, T_ACCENT
    COLOR eax, T_STATUS
    test r15d, UB_HOVER
    jz 2f
    COLOR eax, T_HOVER
2:  push rax
    push rax
    call gfx_frame
    add rsp, 16
    lea rdi, [rip + g_face_mini]
    mov esi, r12d
    mov edx, [rsp + 8]
    mov ecx, r14d
    mov r8d, [rsp + 12]
    mov r9, r13
    COLOR eax, T_ACCENT
    push rax
    push rax
    call ui_text_center
    add rsp, 16
    test r15d, UB_CLICK
    jz 3f
    call update_click
3:  sub r12d, [rip + g_mt + 4*MI_20]
9:  mov eax, r12d
    EPILOGUE

# right-aligned status item: r13 cstr, r12d right edge (moves left)
.Lsb_item:
    push rbx
    mov rdi, r13
    call strlen
    lea rdi, [rip + g_face_mini]
    mov rsi, r13
    mov rdx, rax
    call text_width
    mov edx, r12d
    sub edx, eax
    cmp edx, [rsp + 16 + 28]
    jl 9f                     # leave room for the cursor label and earlier items
    sub r12d, eax
    lea rdi, [rip + g_face_mini]
    mov esi, r12d
    mov edx, [rsp + 16 + 4]
    mov ecx, [rsp + 16 + 12]
    mov r8, r13
    COLOR r9d, T_MUTED
    call ui_text_c
    sub r12d, [rip + g_mt + 4*MI_20]
9:  pop rbx
    ret

# welcome_draw(x, y, w, h)
FN welcome_draw
    PROLOGUE 48
    mov [rsp], edi
    mov [rsp + 4], esi
    mov [rsp + 8], edx
    mov [rsp + 12], ecx
    COLOR r8d, T_BG
    call gfx_fill
    # wordmark
    mov eax, [rsp + 12]
    shr eax, 1
    add eax, [rsp + 4]
    sub eax, [rip + g_mt + 4*MI_64]
    sub eax, [rip + g_mt + 4*MI_48]
    mov r12d, eax
    # the mark and "Raftaar", centered together; the mark is as tall as the h
    mov eax, [rip + g_face_huge + FACE_px]
    imul eax, eax, 11
    xor edx, edx
    mov ecx, 9
    div ecx
    mov [rsp + 20], eax         # icon box
    imul eax, eax, 68
    shr eax, 7
    mov [rsp + 24], eax         # the mark's visible width
    lea rdi, [rip + g_face_huge]
    lea rsi, [rip + .Lraftaar_name]
    mov edx, RAFTAAR_LEN
    call text_width
    mov [rsp + 28], eax
    mov eax, [rsp + 20]
    shr eax, 2
    mov [rsp + 32], eax         # gap
    add eax, [rsp + 24]
    add eax, [rsp + 28]
    mov ecx, [rsp + 8]
    sub ecx, eax
    sar ecx, 1
    add ecx, [rsp]
    mov [rsp + 36], ecx         # left edge of the group
    mov esi, [rsp + 20]
    imul esi, esi, 30
    sar esi, 7
    neg esi
    add esi, ecx                # icon box x
    M eax, MI_48
    shr eax, 1
    mov edx, r12d
    sub edx, [rip + g_mt + 4*MI_20]
    add edx, eax
    mov eax, [rsp + 20]
    shr eax, 1
    sub edx, eax                # icon box y: centered on the text row,
    mov eax, [rsp + 20]
    shr eax, 5
    sub edx, eax                # then up a little to sit on the baseline
    mov edi, IC_RUNE
    mov ecx, [rsp + 20]
    mov r8d, 0xffe5262e         # the mark's own red (assets/icons/raftaar.svg)
    call icon_draw
    lea rdi, [rip + g_face_huge]
    mov esi, [rsp + 36]
    add esi, [rsp + 24]
    add esi, [rsp + 32]
    mov edx, r12d
    sub edx, [rip + g_mt + 4*MI_20]
    M ecx, MI_48
    lea r8, [rip + .Lraftaar_name]
    mov r9d, RAFTAAR_LEN
    COLOR eax, T_FG
    push rax
    push rax
    call ui_text_v
    add rsp, 16
    add r12d, [rip + g_mt + 4*MI_48]
    add r12d, [rip + g_mt + 4*MI_12]
    # shortcut rows
    lea rbx, [rip + welcome_rows]
    xor r15d, r15d
1:  mov r13, [rbx]
    test r13, r13
    jz 9f
    M r14d, MI_32
    # row: label right-aligned to the center, keys left-aligned after it
    mov eax, [rsp + 8]
    shr eax, 1
    add eax, [rsp]
    mov [rsp + 16], eax         # center x
    mov rdi, r13
    call strlen
    lea rdi, [rip + g_face_ui]
    mov rsi, r13
    mov rdx, rax
    call text_width
    mov esi, [rsp + 16]
    sub esi, eax
    sub esi, [rip + g_mt + 4*MI_12]
    # clickable
    lea edi, [r15 + ID_WELCOME]
    push rsi
    push rsi
    mov esi, [rsp + 16 + 16]
    sub esi, [rip + g_mt + 4*MI_64]
    sub esi, [rip + g_mt + 4*MI_64]
    sub esi, [rip + g_mt + 4*MI_32]
    mov edx, r12d
    M ecx, MI_64
    shl ecx, 2
    mov r8d, r14d
    call ui_btn
    mov [rsp + 40 + 16], eax
    pop rsi
    pop rsi
    COLOR r9d, T_MUTED
    test dword ptr [rsp + 40], UB_HOVER
    jz 2f
    COLOR r9d, T_FG
2:  lea rdi, [rip + g_face_ui]
    mov edx, r12d
    mov ecx, r14d
    mov r8, r13
    call ui_text_c
    # key chip
    mov r13, [rbx + 8]
    mov rdi, r13
    call strlen
    lea rdi, [rip + g_face_small]
    mov rsi, r13
    mov rdx, rax
    call text_width
    add eax, [rip + g_mt + 4*MI_16]
    mov edx, eax
    mov edi, [rsp + 16]
    add edi, [rip + g_mt + 4*MI_12]
    mov esi, r12d
    add esi, [rip + g_mt + 4*MI_6]
    mov ecx, r14d
    sub ecx, [rip + g_mt + 4*MI_12]
    M r8d, MI_4
    COLOR r9d, T_HOVER
    call gfx_round_rect
    lea rdi, [rip + g_face_small]
    mov esi, [rsp + 16]
    add esi, [rip + g_mt + 4*MI_20]
    mov edx, r12d
    mov ecx, r14d
    mov r8, r13
    COLOR r9d, T_FG
    call ui_text_c
    test dword ptr [rsp + 40], UB_CLICK
    jz 3f
    call [rbx + 16]
3:  add r12d, r14d
    add rbx, 24
    inc r15d
    jmp 1b
9:  EPILOGUE

# ---------------- dialog ----------------

FN dialog_draw
    PROLOGUE 64
    cmp dword ptr [rip + dlg_kind], 0
    je .Ldd_ret
    # scrim
    xor edi, edi
    xor esi, esi
    mov edx, [rip + g_cv + CV_w]
    mov ecx, [rip + g_cv + CV_h]
    mov r8d, 0x60000000
    call gfx_fill
    mov edi, 420
    call sc
    mov r12d, eax               # w
    # Confirmation details can include model names or file paths. Size to the
    # content where space allows, and fit the line inside the visible dialog.
    cmp dword ptr [rip + dlg_kind], 4
    jne 8f
    mov rdi, [rip + dlg_text]
    call strlen
    mov rdx, rax
    mov rsi, [rip + dlg_text]
    lea rdi, [rip + g_face_small]
    call text_width
    add eax, [rip + g_mt + 4*MI_40]
    cmp eax, r12d
    cmovg r12d, eax
    mov eax, [rip + g_cv + CV_w]
    sub eax, [rip + g_mt + 4*MI_40]
    cmp r12d, eax
    cmovg r12d, eax
8:
    mov edi, 150
    call sc
    mov r13d, eax               # h
    mov eax, [rip + g_cv + CV_w]
    sub eax, r12d
    sar eax, 1
    mov r14d, eax               # x
    mov eax, [rip + g_cv + CV_h]
    sub eax, r13d
    sar eax, 1
    sub eax, [rip + g_mt + 4*MI_48]
    mov r15d, eax               # y
    mov edi, r14d
    mov esi, r15d
    mov edx, r12d
    mov ecx, r13d
    call ui_card
    # title
    lea rdi, [rip + tmp_sb]
    call sb_clear
    cmp dword ptr [rip + dlg_kind], 4
    jne 1f
    lea rdi, [rip + tmp_sb]
    mov rsi, [rip + dlg_title]
    call sb_push_cstr
    jmp 2f
1:  lea rdi, [rip + tmp_sb]
    lea rsi, [rip + .Ldlg_q]
    call sb_push_cstr
    mov rdi, [rip + dlg_tab]
    call tab_at
    mov rax, [rax + TAB_doc]
    lea rdi, [rip + tmp_sb]
    mov rsi, [rax + DOC_name]
    call sb_push_cstr
    lea rdi, [rip + tmp_sb]
    mov esi, '?'
    call sb_push_byte
2:  mov eax, r12d
    sub eax, [rip + g_mt + 4*MI_40]
    push rax
    COLOR eax, T_FG
    push rax
    lea rdi, [rip + g_face_ui]
    mov esi, r14d
    add esi, [rip + g_mt + 4*MI_20]
    mov edx, r15d
    add edx, [rip + g_mt + 4*MI_16]
    M ecx, MI_24
    mov r8, [rip + tmp_sb + SB_ptr]
    mov r9, [rip + tmp_sb + SB_len]
    call ui_text_v_fit
    add rsp, 16
    lea r8, [rip + .Ldlg_msg]
    cmp dword ptr [rip + dlg_kind], 4
    jne 3f
    mov r8, [rip + dlg_text]
3:  mov [rsp + 16], r8
    mov rdi, r8
    call strlen
    mov r9, rax
    mov eax, r12d
    sub eax, [rip + g_mt + 4*MI_40]
    push rax
    COLOR eax, T_MUTED
    push rax
    lea rdi, [rip + g_face_small]
    mov esi, r14d
    add esi, [rip + g_mt + 4*MI_20]
    mov edx, r15d
    add edx, [rip + g_mt + 4*MI_40]
    M ecx, MI_24
    mov r8, [rsp + 32]
    call ui_text_v_fit
    add rsp, 16
    # buttons: Save (primary), Don't Save, Cancel
    M ebx, MI_32
    mov eax, r15d
    add eax, r13d
    sub eax, ebx
    sub eax, [rip + g_mt + 4*MI_16]
    mov [rsp], eax              # button y
    mov eax, r14d
    add eax, r12d
    sub eax, [rip + g_mt + 4*MI_16]
    mov [rsp + 4], eax          # right edge
    xor ecx, ecx
    mov [rsp + 8], ecx
.Ldd_btn:
    mov ecx, [rsp + 8]
    cmp ecx, 3
    jae .Ldd_ret
    lea rax, [rip + dlg_labels]
    mov r13, [rax + rcx*8]
    # a question: Cancel and its button
    cmp dword ptr [rip + dlg_kind], 4
    jne 0f
    cmp ecx, 1
    je 4f
    cmp ecx, 2
    jne 0f
    mov r13, [rip + dlg_ok]
0:  mov rdi, r13
    call strlen
    lea rdi, [rip + g_face_ui]
    mov rsi, r13
    mov rdx, rax
    call text_width
    add eax, [rip + g_mt + 4*MI_32]
    mov [rsp + 12], eax         # button w
    mov esi, [rsp + 4]
    sub esi, eax
    mov [rsp + 16], esi
    mov [rsp + 4], esi
    mov eax, [rip + g_mt + 4*MI_8]
    sub [rsp + 4], eax
    mov edi, [rsp + 8]
    add edi, ID_DLG
    mov edx, [rsp]
    mov ecx, [rsp + 12]
    mov r8d, ebx
    call ui_btn
    mov [rsp + 20], eax
    # style: last drawn (index 2) is the primary Save button
    mov edi, [rsp + 16]
    mov esi, [rsp]
    mov edx, [rsp + 12]
    mov ecx, ebx
    M r8d, MI_RADIUS
    cmp dword ptr [rsp + 8], 2
    jne 1f
    COLOR r9d, T_ACCENT
    COLOR eax, T_ACCENT
    jmp 2f
1:  COLOR r9d, T_BORDER
    COLOR eax, T_POPUP
    test dword ptr [rsp + 20], UB_HOVER
    jz 2f
    COLOR eax, T_HOVER
2:  push rax
    push rax
    call gfx_frame
    add rsp, 16
    COLOR eax, T_FG
    cmp dword ptr [rsp + 8], 2
    jne 3f
    COLOR eax, T_ACCENT_FG
3:  lea rdi, [rip + g_face_ui]
    mov esi, [rsp + 16]
    mov edx, [rsp]
    mov ecx, [rsp + 12]
    mov r8d, ebx
    mov r9, r13
    push rax
    push rax
    call ui_text_center
    add rsp, 16
    test dword ptr [rsp + 20], UB_CLICK
    jz 4f
    mov edi, [rsp + 8]
    call dialog_choose
    jmp .Ldd_ret
4:  inc dword ptr [rsp + 8]
    jmp .Ldd_btn
.Ldd_ret:
    EPILOGUE

# dialog_choose(i): 0 cancel, 1 don't save, 2 save (or app_confirm's button)
dialog_choose:
    PROLOGUE
    mov ebx, edi
    mov r12d, [rip + dlg_kind]
    mov dword ptr [rip + dlg_kind], 0
    mov dword ptr [rip + g_focus], FOCUS_EDITOR
    cmp r12d, 4
    jne 0f
    mov rax, [rip + dlg_cancel]
    mov qword ptr [rip + dlg_cancel], 0
    cmp ebx, 2
    je 5f
    test rax, rax
    jz 9f
    call rax
    jmp 9f
5:  call [rip + dlg_fn]
    jmp 9f
0:  test ebx, ebx
    jz 8f
    cmp ebx, 2
    jne 1f
    mov rdi, [rip + dlg_tab]
    call tab_at
    mov rbx, [rax + TAB_doc]
    cmp qword ptr [rbx + DOC_path], 0
    je 2f
    mov rdi, rbx
    call doc_readonly
    test eax, eax
    jnz 6f
    mov rdi, rbx
    call doc_save
    test rax, rax
    js 7f
    jmp 1f
2:  call cmd_save_as
    jmp 8f
6:  # a read-only file asks first: Overwrite saves it and goes on, Cancel stops here
    mov [rip + ro_kind], r12d
    mov rdi, rbx
    lea rsi, [rip + close_readonly_confirmed]
    call ask_readonly
    lea rax, [rip + unsaved_kept]
    mov [rip + dlg_cancel], rax
    jmp 9f
1:  mov edi, r12d
    call unsaved_done
    jmp 9f
7:  # the file stays open and modified: say why
    lea rdi, [rip + .Lsave_failed]
    call app_toast
8:  call unsaved_kept
9:  mov dword ptr [rip + g_dirty], 1
    EPILOGUE

# unsaved_done(kind): the file asked about (dlg_tab) is saved or let go: close it and go on with what
#   asked (dlg_kind)
unsaved_done:
    push rbx
    mov ebx, edi
    mov rdi, [rip + dlg_tab]
    call app_close_tab_now
    cmp ebx, 3
    jne 1f
    pop rbx
    jmp switch_continue
1:  cmp ebx, 2
    jne 2f
    pop rbx
    jmp cmd_quit
2:  cmp ebx, 5
    jne 3f
    pop rbx
    jmp cmd_close_all
3:  pop rbx
    jmp quit_if_empty

# unsaved_kept(): not quitting after all: no restart into an update either, no other project, and the
#   session is saved again when it comes to that
unsaved_kept:
    mov dword ptr [rip + g_restart], 0
    mov dword ptr [rip + switch_pending], 0
    mov dword ptr [rip + g_session_final], 0
    ret

# close_readonly_confirmed(): Overwrite, for a close or quit that asked to save a read-only file
close_readonly_confirmed:
    PROLOGUE
    mov rdi, [rip + dlg_tab]
    call tab_at
    mov rdi, [rax + TAB_doc]
    call doc_save_readonly
    test rax, rax
    js 1f
    mov edi, [rip + ro_kind]
    call unsaved_done
    jmp 9f
1:  lea rdi, [rip + .Lsave_failed]
    call app_toast
    call unsaved_kept
9:  mov dword ptr [rip + g_dirty], 1
    EPILOGUE

# dialog_key(keysym)
dialog_key:
    cmp edi, KEY_ESCAPE
    jne 1f
    xor edi, edi
    jmp dialog_choose
1:  cmp edi, KEY_RETURN
    jne 2f
    mov edi, 2
    jmp dialog_choose
2:  ret

# app_confirm(question cstr, line cstr, button cstr, fn): a dialog with Cancel and the button, which calls
#   fn; the strings must last while it is open
FN app_confirm
    mov [rip + dlg_title], rdi
    mov [rip + dlg_text], rsi
    mov [rip + dlg_ok], rdx
    mov [rip + dlg_fn], rcx
    mov qword ptr [rip + dlg_cancel], 0
    mov dword ptr [rip + dlg_kind], 4
    mov dword ptr [rip + g_focus], FOCUS_DIALOG
    mov dword ptr [rip + g_dirty], 1
    ret

# ---------------- tooltips (debounced hover) ----------------
# A button notes itself while it is drawn and hovered; tip_commit, once everything is drawn,
# turns the frame's note into a pending tooltip, and tip_tick shows it after TIP_DELAY. Buttons
# with a tooltip are listed in tip_table.

# tip_note(id, x, y_bottom, w, flags) -> flags: remember the button if it is hovered
FN tip_note
    test r8d, UB_HOVER
    jz 1f
    mov [rip + tip_cand], edi
    mov [rip + tip_cx], esi
    mov [rip + tip_cy], edx
    mov [rip + tip_cw], ecx
1:  mov eax, r8d
    ret

# tip_note_text(id, x, y_bottom, w, flags, cstr) -> flags: tip_note for a button whose tooltip says
#   what it does now (a git command with its file); the text is copied and needs no tip_table entry
FN tip_note_text
    test r8d, UB_HOVER
    jz 9f
    mov [rip + tip_cand], edi
    mov [rip + tip_cx], esi
    mov [rip + tip_cy], edx
    mov [rip + tip_cw], ecx
    mov [rip + tip_text_id], edi
    lea rdi, [rip + tip_text]
    mov ecx, TIP_TEXT_MAX - 1
1:  mov al, [r9]
    test al, al
    jz 2f
    mov [rdi], al
    inc rdi
    inc r9
    dec ecx
    jnz 1b
2:  mov byte ptr [rdi], 0
9:  mov eax, r8d
    ret

# tip_commit(): a new button restarts the delay, the same button keeps it, none hides at once;
# so do a press, a drag, and the setting being off
FN tip_commit
    xor eax, eax
    cmp dword ptr [rip + cfg_tooltips], 0
    je 1f
    cmp dword ptr [rip + g_mdown], 0
    jne 1f
    test dword ptr [rip + g_pressed], 1 << BTN_LEFT
    jnz 1f
    mov eax, [rip + tip_cand]
1:  cmp eax, [rip + tip_id]
    je 9f
    mov ecx, [rip + tip_state]
    mov [rip + tip_id], eax
    mov dword ptr [rip + tip_state], TIP_PENDING
    push rax
    push rcx
    call time_ms
    mov rdx, rax
    pop rcx
    pop rax
    cmp ecx, TIP_SHOWN              # leaving a shown tip: the next one within TIP_GRACE skips the delay
    jne 3f
    mov [rip + tip_left], rdx
3:  test eax, eax
    jz 9f
    cmp ecx, TIP_SHOWN
    je 4f
    mov rcx, rdx
    sub rcx, [rip + tip_left]
    cmp rcx, TIP_GRACE
    jb 4f
    mov [rip + tip_since], rdx
    ret
4:  mov dword ptr [rip + tip_state], TIP_SHOWN
9:  ret

# tip_dismiss(): a key press hides the tooltip until the pointer reaches another button
FN tip_dismiss
    cmp dword ptr [rip + tip_id], 0
    je 1f
    mov dword ptr [rip + tip_state], TIP_DISMISSED
1:  ret

# tip_timeout() -> ms until a pending tooltip shows (0 when due), or -1
FN tip_timeout
    cmp dword ptr [rip + tip_id], 0
    je 2f
    cmp dword ptr [rip + tip_state], TIP_PENDING
    jne 2f
    sub rsp, 8
    call time_ms
    add rsp, 8
    sub rax, [rip + tip_since]
    mov ecx, TIP_DELAY
    sub rcx, rax
    xor eax, eax
    test rcx, rcx
    cmovg eax, ecx             # already due: wake at once, tip_tick shows it
    ret
2:  mov eax, -1
    ret

# tip_tick(): show the pending tooltip once its delay has passed
FN tip_tick
    cmp dword ptr [rip + tip_id], 0
    je 1f
    cmp dword ptr [rip + tip_state], TIP_PENDING
    jne 1f
    sub rsp, 8
    call time_ms
    add rsp, 8
    sub rax, [rip + tip_since]
    cmp rax, TIP_DELAY
    jl 1f
    mov dword ptr [rip + tip_state], TIP_SHOWN
    mov dword ptr [rip + g_dirty], 1
1:  ret

# tip_find(id) -> rax entry of tip_table, or 0
tip_find:
    lea rax, [rip + tip_table]
1:  mov ecx, [rax]
    test ecx, ecx
    jz 2f
    cmp ecx, edi
    je 3f
    add rax, TT_SIZE
    jmp 1b
2:  xor eax, eax
3:  ret

# tip_current() -> rax the text of the tooltip on screen, or 0; rdx its tip_table entry, 0 for the
#   text of a tip_note_text button
tip_current:
    PROLOGUE
    xor ebx, ebx
    xor r12d, r12d
    cmp dword ptr [rip + tip_id], 0
    je 9f
    cmp dword ptr [rip + tip_state], TIP_SHOWN
    jne 9f
    call ctx_menu_list             # no tooltip over an open menu
    test rax, rax
    jnz 9f
    mov edi, [rip + tip_id]
    lea rbx, [rip + tip_text]
    cmp edi, [rip + tip_text_id]
    je 9f
    xor ebx, ebx
    call tip_find
    test rax, rax
    jz 9f
    mov r12, rax
    mov rbx, [rax + TT_text]
9:  mov rax, rbx
    mov rdx, r12
    EPILOGUE

# tip_print(sb): "tip=" and the text of the tooltip on screen (nothing when there is none)
FN tip_print
    PROLOGUE
    mov rbx, rdi
    lea rsi, [rip + .Ltip_eq]
    call sb_push_cstr
    call tip_current
    test rax, rax
    jz 1f
    mov rdi, rbx
    mov rsi, rax
    call sb_push_cstr
1:  mov rdi, rbx
    mov esi, 10
    call sb_push_byte
    EPILOGUE

# tip_draw(): the tooltip on top of everything: its text, then "(shortcut)" of the button's
# command as keys_for formats it (the user's binding, macOS symbols on the Mac); a text wider
# than the window is cut with "…"
FN tip_draw
    PROLOGUE 128                   # [rsp + 40] "(shortcut)", at most 2 + 63 bytes
    call tip_current
    test rax, rax
    jz 9f
    mov [rsp], rax
    mov qword ptr [rsp + 24], 0    # "(shortcut)", or 0
    test rdx, rdx
    jz 3f
    mov rdi, [rdx + TT_fn]
    test rdi, rdi
    jz 3f
    call cmd_for_fn
    test rax, rax
    jz 3f
    mov rdi, rax
    call keys_for
    test rax, rax
    jz 3f
    lea rdi, [rsp + 40]
    mov byte ptr [rdi], '('
    inc rdi
    mov rsi, rax
    call cstr_copy
    mov word ptr [rax], ')'        # ')' and the terminating zero
    lea rax, [rsp + 40]
    mov [rsp + 24], rax
3:  mov rdi, [rsp]
    call strlen
    mov [rsp + 8], rax             # text length
    lea rdi, [rip + g_face_small]
    mov rsi, [rsp]
    mov rdx, rax
    call text_width
    mov [rsp + 32], eax            # text width
    mov r12d, eax
    add r12d, [rip + g_mt + 4*MI_8]
    add r12d, [rip + g_mt + 4*MI_8]
    cmp qword ptr [rsp + 24], 0
    je 4f
    mov rdi, [rsp + 24]
    call strlen
    lea rdi, [rip + g_face_small]
    mov rsi, [rsp + 24]
    mov rdx, rax
    call text_width
    add r12d, eax
    add r12d, [rip + g_mt + 4*MI_8]
4:  # no wider than the window: the text gives up what does not fit
    mov eax, [rip + g_cv + CV_w]
    sub eax, [rip + g_mt + 4*MI_8]
    mov ecx, r12d
    sub ecx, eax
    jle 41f
    sub [rsp + 32], ecx
    mov r12d, eax
41: M ebx, MI_24
    # centered under the button, kept inside the window
    mov esi, [rip + tip_cx]
    mov eax, [rip + tip_cw]
    shr eax, 1
    add esi, eax
    mov eax, r12d
    shr eax, 1
    sub esi, eax
    mov eax, [rip + g_cv + CV_w]
    sub eax, r12d
    sub eax, [rip + g_mt + 4*MI_4]
    cmp esi, eax
    cmovg esi, eax
    M eax, MI_4
    cmp esi, eax
    cmovl esi, eax
    mov [rsp + 16], esi
    mov eax, [rip + tip_cy]
    add eax, [rip + g_mt + 4*MI_4]
    # no room below (the status bar's buttons): above the button instead
    lea ecx, [rax + rbx]
    cmp ecx, [rip + g_cv + CV_h]
    jle 5f
    mov eax, [rip + tip_cy]
    sub eax, [rip + g_mt + 4*MI_STATUS]
    sub eax, [rip + g_mt + 4*MI_4]
    sub eax, ebx
5:  mov [rsp + 20], eax
    mov edi, esi
    mov esi, eax
    mov edx, r12d
    mov ecx, ebx
    M r8d, MI_4                    # a tooltip-sized shadow, corners like the buttons
    M r9d, MI_1
    M eax, MI_RADIUS
    push rax
    push rax
    call ui_card_shadow
    add rsp, 16
    mov eax, [rsp + 32]
    push rax
    COLOR eax, T_FG
    push rax
    lea rdi, [rip + g_face_small]
    mov esi, [rsp + 16 + 16]
    add esi, [rip + g_mt + 4*MI_8]
    mov edx, [rsp + 20 + 16]
    mov ecx, ebx
    mov r8, [rsp + 16]
    mov r9, [rsp + 8 + 16]
    call ui_text_v_fit
    add rsp, 16
    cmp qword ptr [rsp + 24], 0
    je 9f
    lea rdi, [rip + g_face_small]
    mov esi, [rsp + 16]
    add esi, [rip + g_mt + 4*MI_8]
    add esi, [rsp + 32]
    add esi, [rip + g_mt + 4*MI_8]
    mov edx, [rsp + 20]
    mov ecx, ebx
    mov r8, [rsp + 24]
    COLOR r9d, T_MUTED
    call ui_text_c
9:  EPILOGUE

# ---------------- toast ----------------

toast_draw:
    PROLOGUE 16
    cmp qword ptr [rip + g_toast_until], 0
    je 9f
    lea rdi, [rip + g_toast]
    call strlen
    mov r13, rax
    lea rdi, [rip + g_face_small]
    lea rsi, [rip + g_toast]
    mov rdx, rax
    call text_width
    add eax, [rip + g_mt + 4*MI_24]
    mov r12d, eax               # w
    M ebx, MI_28                # h
    mov edi, [rip + g_editor_rect]
    add edi, [rip + g_editor_rect + 8]
    sub edi, r12d
    sub edi, [rip + g_mt + 4*MI_24]
    mov [rsp], edi
    mov esi, [rip + g_cv + CV_h]
    sub esi, [rip + g_mt + 4*MI_STATUS]
    sub esi, ebx
    sub esi, [rip + g_mt + 4*MI_12]
    mov [rsp + 4], esi
    mov edx, r12d
    mov ecx, ebx
    call ui_card
    lea rdi, [rip + g_face_small]
    mov esi, [rsp]
    mov edx, [rsp + 4]
    mov ecx, r12d
    mov r8d, ebx
    lea r9, [rip + g_toast]
    COLOR eax, T_FG
    push rax
    push rax
    call ui_text_center
    add rsp, 16
9:  EPILOGUE

# ---------------- misc commands ----------------

FN cmd_toggle_sidebar
    # a narrow window hides it whatever its setting: there the toggle shows it first
    cmp dword ptr [rip + side_narrow], 0
    je 1f
    cmp dword ptr [rip + side_asked], 0
    mov dword ptr [rip + side_asked], 1
    jne 1f
    cmp dword ptr [rip + g_show_side], 0
    je 1f
    mov dword ptr [rip + g_dirty], 1
    ret
1:  mov eax, 1
    lea rcx, [rip + cfg_sidebar]
    push rax
    call toggle_panel
    pop rax
    mov eax, [rip + g_show_side]
    mov [rip + side_fit], eax   # shown again: at the width that cuts no name (app_render)
    ret

# fz(points) -> eax the same room at the interface's font size (13 is its default)
fz:
    mov eax, edi
    imul eax, [rip + cfg_ui_font_size]
    mov ecx, 13
    cdq
    idiv ecx
    ret

# side_fit_width(): the sidebar's width becomes what its longest name and its header need, and no more
side_fit_width:
    PROLOGUE
    mov dword ptr [rip + side_fit], 0
    call explorer_fit_width
    mov ebx, eax
    call explorer_head_width    # the folder's name in the header too
    cmp eax, ebx
    cmovl eax, ebx
    cvtsi2ss xmm0, eax
    divss xmm0, [rip + g_s]
    cvtss2si eax, xmm0
    inc eax
    mov ecx, 600                # the setting's range, and no more than half the window
    cmp eax, ecx
    cmovg eax, ecx
    cvtsi2ss xmm0, dword ptr [rip + g_cv + CV_w]
    divss xmm0, [rip + g_s]
    cvtss2si ecx, xmm0
    sar ecx, 1
    cmp eax, ecx
    cmovg eax, ecx
    mov ecx, 140
    cmp eax, ecx
    cmovl eax, ecx
    cmp eax, [rip + cfg_sidebar_w]
    je 9f
    # a default, not a choice: it is saved with the next setting that changes
    mov [rip + cfg_sidebar_w], eax
    mov dword ptr [rip + g_dirty], 1
9:  EPILOGUE

# side_grow(): the tree's rows changed: the sidebar widens to what its longest name needs, up to the
#   setting's range and half the window, so no name is cut
side_grow:
    PROLOGUE
    call explorer_fit_width
    mov [rip + side_fit_px], eax
    cmp eax, [rip + g_side_px]
    jle 9f
    cvtsi2ss xmm0, eax
    divss xmm0, [rip + g_s]
    cvtss2si eax, xmm0
    inc eax
    mov ecx, 600
    cmp eax, ecx
    cmovg eax, ecx
    cvtsi2ss xmm0, dword ptr [rip + g_cv + CV_w]
    divss xmm0, [rip + g_s]
    cvtss2si ecx, xmm0
    sar ecx, 1
    cmp eax, ecx
    cmovg eax, ecx
    cmp eax, [rip + cfg_sidebar_w]
    jle 9f
    mov [rip + cfg_sidebar_w], eax
    mov dword ptr [rip + g_settings_changed], 1
    mov dword ptr [rip + g_dirty], 1
9:  EPILOGUE

# toggle_panel(bit eax, setting rcx): a panel hidden in this window alone comes back, and the setting
# turns on only if it was off; any other panel flips its setting
toggle_panel:
    test [rip + panels_hidden], eax
    jz 1f
    not eax
    and [rip + panels_hidden], eax
    cmp dword ptr [rcx], 0
    jne app_sync_panels
1:  xor dword ptr [rcx], 1
    mov dword ptr [rip + g_settings_changed], 1
    jmp app_sync_panels

# app_hide_panels(): a window started with files alone is for editing them: the explorer stays
# out of it, whatever the settings say, until shown or a folder is opened
FN app_hide_panels
    mov dword ptr [rip + panels_hidden], 1
    jmp app_sync_panels

# app_reveal_panel(bit): 1 the explorer follows its setting again in this window
FN app_reveal_panel
    not edi
    and [rip + panels_hidden], edi
    jmp app_sync_panels

# app_sync_panels(): g_show_side from the setting and panels_hidden
FN app_sync_panels
    mov eax, [rip + cfg_sidebar]
    test dword ptr [rip + panels_hidden], 1
    jz 1f
    xor eax, eax
1:  mov [rip + g_show_side], eax
    mov dword ptr [rip + g_dirty], 1
    ret

FN cmd_zoom_in
    mov esi, 1
    jmp zoom_focused

FN cmd_zoom_out
    mov esi, -1
    jmp zoom_focused

FN cmd_zoom_reset
    xor esi, esi
    jmp zoom_focused

# zoom_focused(dir): zoom only the focused terminal, otherwise the editor or image.
zoom_focused:
    cmp dword ptr [rip + g_focus], FOCUS_TERMINAL
    je .Lzoom_term
    call image_zoom
    jnz .Lzoom_done
    lea rdi, [rip + cfg_font_size]
    jmp .Lzoom_font
.Lzoom_term:
    lea rdi, [rip + cfg_term_font_size]
.Lzoom_font:
    mov eax, 14                # reset either font to its default size
    test esi, esi
    jz 1f
    mov eax, [rdi]
    add eax, esi
    mov edx, 8                 # both font size settings range over 8..40
    cmp eax, edx
    cmovl eax, edx
    mov edx, 40
    cmp eax, edx
    cmovg eax, edx
1:  mov [rdi], eax
    mov dword ptr [rip + g_settings_changed], 1
    mov dword ptr [rip + g_dirty], 1
.Lzoom_done:
    ret

# image_zoom(dir) -> ZF clear when an image tab took the zoom command (1 in, -1 out, 0 fit)
image_zoom:
    push rsi
    call app_image
    pop rsi
    test rax, rax
    jz 1f
    mov rdi, rax
    call iv_zoom_cmd
    or eax, 1
1:  ret

# app_launch_tab(): a launch that opened nothing shows the welcome page in a tab, or with that turned
#   off a terminal in the project's folder
FN app_launch_tab
    cmp dword ptr [rip + cfg_home_on_launch], 0
    je cmd_new_terminal
# cmd_home(): the welcome page's tab, a new one when none is open
FN cmd_home
    PROLOGUE
    xor ebx, ebx
1:  cmp rbx, [rip + g_tabs + VEC_len]
    jae 2f
    mov rdi, rbx
    call tab_at
    cmp qword ptr [rax + TAB_kind], TAB_HOME
    je 3f
    inc rbx
    jmp 1b
2:  xor edi, edi
    mov esi, TAB_HOME
    call app_add_tab
    jmp 9f
3:  mov rdi, rbx
    call app_activate_tab
9:  EPILOGUE

# app_fit_sidebar(): the sidebar takes the width its tree needs, once drawn
FN app_fit_sidebar
    mov dword ptr [rip + side_fit], 1
    ret

# cmd_toggle_settings(): the settings tab; closes it when it is the current one
FN cmd_toggle_settings
    push rbx
    mov rdi, [rip + g_tab_cur]
    test rdi, rdi
    js 1f
    call tab_at
    cmp qword ptr [rax + TAB_kind], TAB_SETTINGS
    jne 1f
    mov rdi, [rip + g_tab_cur]
    call app_close_tab
    pop rbx
    ret
1:  call cmd_settings
    pop rbx
    ret

FN cmd_settings
    PROLOGUE
    # focus an existing settings tab
    xor ebx, ebx
1:  cmp rbx, [rip + g_tabs + VEC_len]
    jae 2f
    mov rdi, rbx
    call tab_at
    cmp qword ptr [rax + TAB_kind], TAB_SETTINGS
    je 3f
    inc rbx
    jmp 1b
2:  xor edi, edi
    mov esi, TAB_SETTINGS
    call app_add_tab
    jmp 4f
3:  mov rdi, rbx
    call app_activate_tab
4:  mov dword ptr [rip + g_focus], FOCUS_SETTINGS
    cmp dword ptr [rip + cfg_commit_ai], 0
    je 5f
    call cmd_ai_detect
5:  EPILOGUE

FN cmd_open_config
    PROLOGUE
    call config_path
    mov rbx, rax
    mov rdi, rax
    call file_mtime
    test rax, rax
    jnz 1f
    call config_save
1:  mov rdi, rbx
    call app_open_file
    EPILOGUE

# cmd_toggle_zen(): zen mode: the view with the keys alone, over the whole window, without the title
#   bar, the explorer, the status bar or the other panes of its tab, until it is toggled again
FN cmd_toggle_zen
    xor dword ptr [rip + g_zen], 1
    mov dword ptr [rip + g_dirty], 1
    ret

FN cmd_toggle_whitespace
    xor dword ptr [rip + cfg_whitespace], 1
    mov dword ptr [rip + g_settings_changed], 1
    mov dword ptr [rip + g_dirty], 1
    ret

FN cmd_toggle_line_numbers
    xor dword ptr [rip + cfg_line_numbers], 1
    mov dword ptr [rip + g_settings_changed], 1
    mov dword ptr [rip + g_dirty], 1
    ret

FN cmd_newline_below
    push rbx
    mov rdi, 5
    xor esi, esi
    call ed_move
    call ed_newline
    pop rbx
    ret

FN cmd_newline_above
    READONLY_RET
    PROLOGUE 272
    mov rbx, [rip + g_doc]
    test rbx, rbx
    jz 9f
    # an empty line above with the indentation of this one, the cursor at its end
    mov rdi, rbx
    mov rsi, [rbx + DOC_cur]
    call doc_line_of
    mov r13, rax
    mov rdi, rbx
    mov rsi, rax
    call doc_line_start
    mov r12, rax
    mov rdi, rbx
    mov rsi, r13
    call line_indent
    mov r15, rax
    cmp rax, 200
    jbe 1f
    mov eax, 200
1:  mov r14, rax
    mov rdi, rbx
    mov rsi, r12
    mov rdx, r14
    lea rcx, [rsp]
    call doc_copy
    # above a closing bracket: one level more (the block's content)
    lea rsi, [r12 + r15]
    mov rdi, rbx
    call doc_byte
    cmp eax, '}'
    je 2f
    cmp eax, ')'
    je 2f
    cmp eax, ']'
    jne 4f
2:  cmp dword ptr [rip + cfg_insert_spaces], 0
    jne 3f
    mov byte ptr [rsp + r14], 9
    inc r14
    jmp 4f
3:  mov ecx, [rip + cfg_tab_width]
    cmp ecx, 16
    jbe 31f
    mov ecx, 16
31: test ecx, ecx
    jz 4f
    mov byte ptr [rsp + r14], ' '
    inc r14
    dec ecx
    jmp 31b
4:  mov byte ptr [rsp + r14], 10
    mov [rbx + DOC_cur], r12
    mov [rbx + DOC_anchor], r12
    mov rdi, rbx
    lea rsi, [rsp]
    lea rdx, [r14 + 1]
    xor ecx, ecx
    call ed_insert
    lea rax, [r12 + r14]
    mov [rbx + DOC_cur], rax
    mov [rbx + DOC_anchor], rax
9:  EPILOGUE

FN cmd_indent
    mov edi, 1
    jmp ed_indent
FN cmd_outdent
    mov edi, -1
    jmp ed_indent
FN cmd_move_line_up
    mov edi, -1
    jmp ed_move_lines
FN cmd_move_line_down
    mov edi, 1
    jmp ed_move_lines

.section .rodata
.Lraftaar: .asciz "raftaar"      # the name as it is written in the interface
.Lraftaar_name: .asciz "Raftaar" # the name as the welcome screen shows it
.Lempty: .asciz ""
.Lrestart_empty: .asciz "--empty"
.Ldash: .asciz " \342\200\224 "
.Lbinary: .asciz "Binary file, not opened"
.Lopen_failed: .asciz "Could not read the file"
.Lnot_regular: .asciz "Not a regular file, not opened"
.Lsaved: .asciz "Saved"
.Lsave_failed: .asciz "Could not save the file"
.Lro_a: .asciz "Overwrite read-only "
.Lro_b: .asciz "?"
.Lro_text: .asciz "The file is read-only. Overwriting replaces it, and it stays read-only."
.Lro_button: .asciz "Overwrite"
.Lsave_as: .asciz "Save as"
.Lsettings: .asciz "Settings"
.Lhome_tab: .asciz "Home"
.Lq_term: .asciz "Close this terminal?"
.Lq_term_text: .asciz "A program is still running in it and will be stopped."
.Lb_term: .asciz "Close Terminal"
.Lq_quit: .asciz "Quit raftaar?"
.Lq_quit_text: .asciz "Programs are still running in terminals and will be stopped."
.Lb_quit: .asciz "Quit"
.p2align 3
# tip_table: button, text, the handler it runs (0: not a command, no shortcut); 0 ends it
tip_table:
    .quad ID_GIT_BTN, .Ltip_git, cmd_toggle_git
    .quad ID_SETTINGS_BTN, .Ltip_settings, cmd_settings
    .quad ID_TOG_SIDE, .Ltip_side, cmd_toggle_sidebar
    .quad ID_EXP_NEW, .Ltip_exp_new, 0
    .quad ID_EXP_NEW_FOLDER, .Ltip_exp_new_folder, 0
    .quad ID_EXP_REFRESH, .Ltip_exp_refresh, 0
    .quad ID_SEARCH, .Lsearch, cmd_quick_open
    .quad ID_TAB_NEW, .Ltip_new_term, cmd_new_terminal
    .quad 0, 0, 0
.Ltip_git: .asciz "Git history"
.Ltip_new_term: .asciz "New terminal"
.Lsearch: .asciz "Go to file"
.Lenv_home: .asciz "HOME"
.Lcr_home: .asciz "Home"
.Lcr_empty: .asciz "(empty)"
.Ltip_term: .asciz "Terminal"
.Ltip_settings: .asciz "Settings"
.Ltip_side: .asciz "File explorer"
.Ltip_exp_new: .asciz "New file"
.Ltip_exp_new_folder: .asciz "New folder"
.Ltip_exp_refresh: .asciz "Refresh explorer"
.Ltip_eq: .asciz "tip="
.Lgit_tab: .asciz "Git"
.Lln: .asciz "Ln "
.Lcol: .asciz ", Col "
.Lsel_open: .asciz "  ("
.Lsel_close: .asciz " selected)"
.Lsb_worktree: .asciz " \302\267 worktree "
.Lutf8: .asciz "UTF-8"
.Llf: .asciz "LF"
.Lcrlf: .asciz "CRLF"
.Ltabs: .asciz "Tabs"
.Lspaces: .asciz "Spaces: "
.Lplain: .asciz "Plain Text"
.Ldlg_q: .asciz "Save changes to "
.Ldlg_msg: .asciz "Your changes will be lost if you don't save them."
.Lw1: .asciz "Go to file"
.Lw2: .asciz "Command palette"
.Lw3: .asciz "New file"
.Lw5: .asciz "Toggle explorer"
.Lw9: .asciz "Zen mode"
.Lw7: .asciz "Open file"
.Lw8: .asciz "Open folder"
.ifdef MACOS
.Lk1: .asciz "\342\214\230P"
.Lk2: .asciz "\342\207\247\342\214\230P"
.Lk3: .asciz "\342\214\230N"
.Lk5: .asciz "\342\214\230B"
.Lk9: .asciz "\342\214\245Z"
.Lk7: .asciz "\342\214\230O"
.Lk8: .asciz "\342\207\247\342\214\230O"
.else
.Lk1: .asciz "Ctrl+P"
.Lk2: .asciz "Ctrl+Shift+P"
.Lk3: .asciz "Ctrl+N"
.Lk5: .asciz "Ctrl+B"
.Lk9: .asciz "Alt+Z"
.Lk7: .asciz "Ctrl+O"
.Lk8: .asciz "Ctrl+Shift+O"
.endif
.Lpm_folder: .asciz "Open Folder\342\200\246"
.Lnew_window_failed: .asciz "Could not open a new window"
.ifndef WINDOWS
.Lenv_new_window: .asciz "RAFTAAR_NEW_WINDOW"
.Ldevnull: .asciz "/dev/null"
.ifndef MACOS
.Lproc_self_exe: .asciz "/proc/self/exe"
.Ldeleted: .asciz " (deleted)"
.endif
.endif
.Lpm_file: .asciz "Open File\342\200\246"
.Lpm_line: .asciz ""
.Ld0: .asciz "Cancel"
.Ld1: .asciz "Don't Save"
.Ld2: .asciz "Save"
.p2align 3
welcome_rows:
    .quad .Lw1, .Lk1, cmd_quick_open
    .quad .Lw2, .Lk2, cmd_command_palette
    .quad .Lw3, .Lk3, cmd_new_file
    .quad .Lw7, .Lk7, cmd_open_file
    .quad .Lw8, .Lk8, cmd_open_folder
    .quad .Lw5, .Lk5, cmd_toggle_sidebar
    .quad .Lw9, .Lk9, cmd_toggle_zen
    .quad 0
dlg_labels: .quad .Ld0, .Ld1, .Ld2

.data
g_win_focused: .long 1
# the explorer in this window: its setting, unless panels_hidden takes it away (app_sync_panels)
.globl g_show_side
g_show_side: .long 1
# the buttons a window that draws its own frame has: 1 close, 2 maximize, 4 minimize. The desktop's
# own choice replaces it (GNOME's button-layout, src/plat/appearance.s)
.globl g_win_buttons
g_win_buttons: .long 7
.p2align 3
g_tab_cur: .quad -1
.bss
panels_hidden: .long 0          # 1 the explorer: hidden in a window started with files
.globl g_zen
g_zen: .long 0                  # zen mode (cmd_toggle_zen)
.globl g_settings_changed, g_started
g_settings_changed: .long 0
g_started: .long 0              # the command line is open: later folders switch the project
g_tabscroll_reveal: .long 0
.p2align 3
term_back: .quad 0               # the tab Toggle Terminal comes back to (term_note_back)

.text
# app_open_path(path): folder -> project, file -> tab (relative paths use the cwd)
FN app_open_path
    PROLOGUE 16
.ifdef WINDOWS
    call win_fullpath
    test rax, rax
    jnz 91f
    EPILOGUE
91: mov rbx, rax
    mov r13d, 1
    jmp 2f
.endif
    mov rbx, rdi
    # absolute path
    PATH_ABSOLUTE rbx, 1f
    sub rsp, 4096
    mov rdi, rsp
    mov esi, 4000
    SYS SYS_getcwd
    mov rdi, rsp
    mov rsi, rbx
    call path_join
    add rsp, 4096
    mov rbx, rax
    mov r13d, 1
    jmp 2f
1:  mov rdi, rbx
    call strlen
    mov rdi, rbx
    mov rsi, rax
    call mem_dup
    mov rbx, rax
    mov r13d, 1
2:  mov rdi, rbx
    call path_normalize
    mov rdi, rbx
    call file_is_dir
    test eax, eax
    jz 3f
    # once started, a folder (Finder, the Dock, :e, open) takes up the window the way Open Folder
    # does: the project's session is saved and its unsaved files are asked about first
    mov rdi, rbx
    cmp dword ptr [rip + g_started], 0
    je 21f
    call app_switch_project
    jmp 8f
21: call app_set_project
    jmp 8f
3:  mov rdi, rbx
    call app_adopt_folder
    mov rdi, rbx
    call app_open_file
8:  test r13d, r13d
    jz 9f
    mov rdi, rbx
    call mem_free
9:  EPILOGUE
