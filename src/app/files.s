# file manager tab: what a folder holds, in a grid. While the tab has the keys the sidebar holds its
#   places in the tree's stead: Home, Recent, Starred and Trash; the pinned folders (GTK's bookmarks,
#   as GNOME Files keeps them); the drives and partitions (lsblk; a click mounts one that is not).
#   Copies, moves, the trash, archives and mounts run the system's own programs, in the background.
.include "raftaar.inc"

STRUCT
F FI_name, 8            # into FI_path: its last part
F FI_path, 8            # follows the item in its block
F FI_dir, 4
F FI_pad, 4
F FI_size, 8            # files: bytes, -1 until asked; Recent: its time while sorting
F FI_count, 8           # folders: what they hold, -1 until counted
ENDSTRUCT FI_SIZE

STRUCT
F PL_name, 8            # mem_alloc'd
F PL_path, 8            # mem_alloc'd; 0: a drive not mounted
F PL_dev, 8             # drives: the device ("/dev/sdb1"), mem_alloc'd
F PL_icon, 4
F PL_pad, 4
ENDSTRUCT PL_SIZE

STRUCT
F FJ_pid, 4
F FJ_fd, 4
F FJ_cb, 8              # cb(ctx, output ptr, len, status) when the program ends
F FJ_ctx, 8
F FJ_out, SB_SIZE
ENDSTRUCT FJ_SIZE

.equ ID_FM_ITEM, 0x500000       # + item
.equ ID_FM_PLACE, 0x9000        # + row of the sidebar
.equ ID_FM_EJECT, 0x9400        # + drive
.equ ID_FM_BACK, 0x9800
.equ ID_FM_FWD, 0x9801
.equ ID_FM_UP, 0x9802
.equ ID_FM_SCROLL, 0x9803
.equ HIST_MAX, 64
.equ MENU_MAX, 24
.equ RECENT_MAX, 100
.equ TOOLS, 4                   # Home, Recent, Starred, Trash

.data
.p2align 2
fm_sel: .long -1                # the selected item, -1 none
fm_cols: .long 1
fm_rows_seen: .long 1           # rows that fit, for Page Up and Page Down

.bss
.p2align 3
items: .zero VEC_SIZE           # FI*
pinned: .zero VEC_SIZE          # PL
drives: .zero VEC_SIZE          # PL
starred: .zero VEC_SIZE         # cstr
back: .zero VEC_SIZE            # cstr: where Back goes, the last one last
fwd: .zero VEC_SIZE
menu: .zero 16 * (MENU_MAX + 1)
sb: .zero SB_SIZE
fm_stamp: .quad 0               # the folder's mtime when read
bm_stamp: .quad 0               # the bookmarks file's
drives_at: .quad 0              # time_ms of the last scan of the drives
fm_path: .zero 4096             # the folder shown; "\1" Recent, "\2" Starred
fm_want: .zero 4096             # the item to select once read (the folder Up came from)
fm_target: .zero 4096           # the item a menu or a key is for
fm_term: .zero 4096             # the folder the next terminal starts in
fm_clip: .zero 4096             # what Cut or Copy took
fm_dest: .zero 4096
fm_tmp: .zero 4096
fm_cwd: .zero 4096
trash_dir: .zero 4096
pr_path: .zero 4096             # Properties: the item, its title and its line
pr_title: .zero 512
pr_line: .zero 4096
pr_size: .zero 64
pr_base: .quad 0                # bytes of pr_line before the size
pr_gen: .quad 0
fm_meta: .zero 512              # the status bar's words for the selected item
toast_buf: .zero 512
fm_scroll: .long 0
fm_reveal: .long 0              # scroll the selected item into view on the next draw
fm_cut: .long 0                 # fm_clip goes, rather than a copy of it
fm_hidden: .long 0              # cfg_hide_dotfiles when read
fm_loaded: .long 0
fm_err: .long 0                 # the folder could not be read
menu_n: .long 0
fm_drive: .long 0               # the drive a menu is for
drives_running: .long 0
starred_loaded: .long 0
bm_loaded: .long 0

.text

# ---------------- small things ----------------

# home() -> rax $HOME, or "/"
home:
    push rbx
    lea rdi, [rip + .Lhome]
    call getenv
    test rax, rax
    jz 1f
    cmp byte ptr [rax], 0
    jne 2f
1:  lea rax, [rip + .Lslash]
2:  pop rbx
    ret

# xdg_dir(dst, env name, fallback under home) -> rax end of dst: $env, or $HOME/fallback
xdg_dir:
    PROLOGUE
    mov rbx, rdi
    mov r12, rdx
    mov rdi, rsi
    call getenv
    test rax, rax
    jz 1f
    cmp byte ptr [rax], 0
    je 1f
    mov rdi, rbx
    mov rsi, rax
    call cstr_copy
    EPILOGUE
1:  call home
    mov rdi, rbx
    mov rsi, rax
    call cstr_copy
    mov rdi, rax
    mov rsi, r12
    call cstr_copy
    EPILOGUE

# trash_path() -> rax trash_dir: "$XDG_DATA_HOME/Trash/files"
trash_path:
    push rbx
    lea rax, [rip + trash_dir]
    cmp byte ptr [rax], 0
    jne 1f
    lea rdi, [rip + trash_dir]
    lea rsi, [rip + .Lxdg_data]
    lea rdx, [rip + .Ldot_share]
    call xdg_dir
    mov rdi, rax
    lea rsi, [rip + .Ltrash_rel]
    call cstr_copy
    lea rax, [rip + trash_dir]
1:  pop rbx
    ret

# is_here(path) -> eax 1 when the page shows that folder
is_here:
    push rbx
    lea rsi, [rip + fm_path]
    call strcmp_eq
    test eax, eax
    setnz al
    movzx eax, al
    pop rbx
    ret

# path_join_to(dst, dir, name) -> rax end of dst: "dir/name" ("/name" under the root)
path_join_to:
    PROLOGUE
    mov r12, rdx
    mov rbx, rsi
    call cstr_copy
    cmp byte ptr [rbx], '/'
    jne 1f
    cmp byte ptr [rbx + 1], 0
    je 2f
1:  mov byte ptr [rax], '/'
    inc rax
2:  mov rdi, rax
    mov rsi, r12
    call cstr_copy
    EPILOGUE

# parent_to(dst, path) -> rax end of dst: the folder path is in ("/" for the root's)
parent_to:
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    mov rdi, rsi
    call strlen
    mov rdi, r12
    mov rsi, rax
    call path_dirlen
    test rax, rax
    jnz 1f
    mov eax, 1
1:  mov r13, rax
    mov rdi, rbx
    mov rsi, r12
    mov rdx, r13
    call memcpy
    mov byte ptr [rbx + r13], 0
    lea rax, [rbx + r13]
    EPILOGUE

# base_of(path) -> rax its last part (a cstr in path)
base_of:
    push rbx
    mov rbx, rdi
    call strlen
    mov rdi, rbx
    mov rsi, rax
    call path_basename
    pop rbx
    ret

# url_decode(dst, src, len): %XX as the byte it stands for; dst ends with a NUL
url_decode:
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    lea r13, [rsi + rdx]
1:  cmp r12, r13
    jae 9f
    movzx eax, byte ptr [r12]
    cmp al, '%'
    jne 2f
    lea rax, [r12 + 2]
    cmp rax, r13
    jae 2f
    lea rdi, [r12 + 1]
    mov esi, 2
    call parse_hex
    cmp rdx, 2
    jne 3f
    mov [rbx], al
    inc rbx
    add r12, 3
    jmp 1b
3:  movzx eax, byte ptr [r12]
2:  mov [rbx], al
    inc rbx
    inc r12
    jmp 1b
9:  mov byte ptr [rbx], 0
    EPILOGUE

# url_encode(sb, path): the path as a URI's, bytes other than letters, digits and /._~- as %XX
url_encode:
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
1:  movzx r13d, byte ptr [r12]
    test r13d, r13d
    jz 9f
    inc r12
    mov eax, r13d
    or eax, 0x20
    sub eax, 'a'
    cmp eax, 25
    jbe 2f
    lea eax, [r13 - '0']
    cmp eax, 9
    jbe 2f
    cmp r13d, '/'
    je 2f
    cmp r13d, '.'
    je 2f
    cmp r13d, '_'
    je 2f
    cmp r13d, '~'
    je 2f
    cmp r13d, '-'
    je 2f
    mov rdi, rbx
    mov esi, '%'
    call sb_push_byte
    mov eax, r13d
    shr eax, 4
    lea rcx, [rip + .Lhex]
    movzx esi, byte ptr [rcx + rax]
    mov rdi, rbx
    call sb_push_byte
    mov eax, r13d
    and eax, 15
    lea rcx, [rip + .Lhex]
    movzx esi, byte ptr [rcx + rax]
    mov rdi, rbx
    call sb_push_byte
    jmp 1b
2:  mov rdi, rbx
    mov esi, r13d
    call sb_push_byte
    jmp 1b
9:  EPILOGUE

# push_size(sb, bytes): "812 bytes", "4.2 kB", "1.3 MB", "2.1 GB", as GNOME counts them (by 1000)
push_size:
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    cmp r12, 1000
    jae 1f
    mov rdi, rbx
    mov rsi, r12
    call sb_push_u64
    mov rdi, rbx
    lea rsi, [rip + .Lbytes]
    cmp r12, 1
    jne 0f
    lea rsi, [rip + .Lbyte]
0:  call sb_push_cstr
    EPILOGUE
1:  lea r13, [rip + size_units]
2:  mov rax, [r13 + 16]
    test rax, rax
    jz 3f
    cmp r12, rax
    jb 3f
    add r13, 16
    jmp 2b
3:  mov rax, r12                # tenths of the unit
    imul rax, rax, 10
    xor edx, edx
    div qword ptr [r13]
    mov r14, rax
    xor edx, edx
    mov ecx, 10
    div rcx
    mov r15, rdx
    mov rdi, rbx
    mov rsi, rax
    call sb_push_u64
    mov rdi, rbx
    mov esi, '.'
    call sb_push_byte
    mov rdi, rbx
    mov rsi, r15
    call sb_push_u64
    mov rdi, rbx
    mov rsi, [r13 + 8]
    call sb_push_cstr
    EPILOGUE

# ---------------- items ----------------

# fi_add(dir or 0, name, is_dir) -> rax FI*: an item; with no dir the name is its whole path
fi_add:
    PROLOGUE 16
    mov rbx, rdi
    mov r12, rsi
    mov r13d, edx
    mov rdi, r12
    call strlen
    mov r14, rax
    xor r15d, r15d
    test rbx, rbx
    jz 1f
    mov rdi, rbx
    call strlen
    mov r15, rax
1:  lea rdi, [r14 + r15 + FI_SIZE + 2]
    call mem_alloc
    mov [rsp], rax
    lea rdi, [rax + FI_SIZE]
    mov [rax + FI_path], rdi
    mov [rax + FI_dir], r13d
    mov qword ptr [rax + FI_size], -1
    mov qword ptr [rax + FI_count], -1
    test rbx, rbx
    jz 2f
    mov rsi, rbx
    mov rdx, r15
    call memcpy
    lea rdi, [rax + r15]
    cmp r15, 1
    jne 3f
    cmp byte ptr [rbx], '/'
    je 2f
3:  mov byte ptr [rdi], '/'
    inc rdi
2:  mov rsi, r12
    call cstr_copy
    mov rax, [rsp]
    mov rdi, [rax + FI_path]
    call base_of
    mov rcx, [rsp]
    mov [rcx + FI_name], rax
    lea rdi, [rip + items]
    mov esi, 8
    call vec_push
    mov rcx, [rsp]
    mov [rax], rcx
    mov rax, rcx
    EPILOGUE

# fm_clear(): no items
fm_clear:
    push rbx
    xor ebx, ebx
1:  cmp rbx, [rip + items + VEC_len]
    jae 2f
    mov rax, [rip + items + VEC_ptr]
    mov rdi, [rax + rbx*8]
    call mem_free
    inc rbx
    jmp 1b
2:  mov qword ptr [rip + items + VEC_len], 0
    pop rbx
    ret

# item(i) -> rax FI*, or 0 past the end
item:
    movsxd rax, edi
    test rax, rax
    js 1f
    cmp rax, [rip + items + VEC_len]
    jae 1f
    mov rcx, [rip + items + VEC_ptr]
    mov rax, [rcx + rax*8]
    ret
1:  xor eax, eax
    ret

# sel_item() -> rax the selected FI*, or 0
sel_item:
    mov edi, [rip + fm_sel]
    jmp item

# hidden(name) -> eax 1 when the setting hides it (a dot file)
hidden:
    xor eax, eax
    cmp dword ptr [rip + cfg_hide_dotfiles], 0
    je 1f
    cmp byte ptr [rdi], '.'
    sete al
1:  ret

# dir entries: ctx unused
load_cb:
    PROLOGUE
    mov rbx, rsi
    mov r12d, edx
    mov rdi, rsi
    call hidden
    test eax, eax
    jnz 9f
    lea rdi, [rip + fm_path]
    mov rsi, rbx
    mov edx, r12d
    call fi_add
9:  EPILOGUE

# count_cb(ctx = *count, name, is_dir): what a folder shows, counted
count_cb:
    push rbx
    mov rbx, rdi
    mov rdi, rsi
    call hidden
    test eax, eax
    jnz 1f
    inc qword ptr [rbx]
1:  pop rbx
    ret

# count_of(path) -> rax what the folder holds (what the setting shows of it)
count_of:
    push rbx
    sub rsp, 16
    mov qword ptr [rsp], 0
    lea rsi, [rip + count_cb]
    mov rdx, rsp
    call dir_each
    mov rax, [rsp]
    add rsp, 16
    pop rbx
    ret

# fi_info(FI*): its size or what it holds, read once
fi_info:
    push rbx
    mov rbx, rdi
    cmp dword ptr [rbx + FI_dir], 0
    je 1f
    cmp qword ptr [rbx + FI_count], -1
    jne 9f
    mov rdi, [rbx + FI_path]
    call count_of
    mov [rbx + FI_count], rax
    jmp 9f
1:  cmp qword ptr [rbx + FI_size], -1
    jne 9f
    mov rdi, [rbx + FI_path]
    call file_stamp
    mov [rbx + FI_size], rdx
9:  pop rbx
    ret

# fi_less(a, b) -> 1 if a comes first: folders, then by name ignoring case
fi_less:
    mov eax, [rdi + FI_dir]
    cmp eax, [rsi + FI_dir]
    je 1f
    seta al
    movzx eax, al
    ret
1:  mov rdi, [rdi + FI_name]
    mov rsi, [rsi + FI_name]
2:  movzx eax, byte ptr [rdi]
    movzx ecx, byte ptr [rsi]
    lea edx, [rax - 'A']
    cmp edx, 25
    ja 3f
    or eax, 0x20
3:  lea edx, [rcx - 'A']
    cmp edx, 25
    ja 4f
    or ecx, 0x20
4:  cmp eax, ecx
    jne 5f
    test eax, eax
    jz 6f
    inc rdi
    inc rsi
    jmp 2b
5:  setb al
    movzx eax, al
    ret
6:  xor eax, eax
    ret

# fm_sort(array, n): FI pointers in fi_less order, by bottom-up merge sort (as the explorer's)
fm_sort:
    PROLOGUE 64
    mov r12, rdi
    mov r13, rsi
    cmp r13, 2
    jb 9f
    lea rdi, [r13*8]
    call mem_alloc
    mov r14, rax
    mov r15, r12
    mov rbx, r14
    mov qword ptr [rsp], 1
.Lfs_pass:
    mov rax, [rsp]
    cmp rax, r13
    jae .Lfs_done
    mov qword ptr [rsp + 8], 0
.Lfs_run:
    mov rax, [rsp + 8]
    cmp rax, r13
    jae .Lfs_swap
    mov rcx, rax
    add rcx, [rsp]
    cmp rcx, r13
    cmova rcx, r13
    mov [rsp + 16], rcx
    mov rdx, rcx
    add rdx, [rsp]
    cmp rdx, r13
    cmova rdx, r13
    mov [rsp + 24], rdx
    mov [rsp + 32], rax
    mov [rsp + 40], rcx
    mov [rsp + 48], rax
.Lfs_merge:
    mov rax, [rsp + 48]
    cmp rax, [rsp + 24]
    jae .Lfs_next
    mov rcx, [rsp + 32]
    cmp rcx, [rsp + 16]
    jae .Lfs_right
    mov rdx, [rsp + 40]
    cmp rdx, [rsp + 24]
    jae .Lfs_left
    mov rdi, [r15 + rdx*8]
    mov rsi, [r15 + rcx*8]
    call fi_less
    test eax, eax
    jz .Lfs_left
.Lfs_right:
    mov rdx, [rsp + 40]
    mov rax, [r15 + rdx*8]
    inc qword ptr [rsp + 40]
    jmp .Lfs_put
.Lfs_left:
    mov rcx, [rsp + 32]
    mov rax, [r15 + rcx*8]
    inc qword ptr [rsp + 32]
.Lfs_put:
    mov rcx, [rsp + 48]
    mov [rbx + rcx*8], rax
    inc qword ptr [rsp + 48]
    jmp .Lfs_merge
.Lfs_next:
    mov rax, [rsp + 24]
    mov [rsp + 8], rax
    jmp .Lfs_run
.Lfs_swap:
    xchg r15, rbx
    mov rax, [rsp]
    add rax, rax
    mov [rsp], rax
    jmp .Lfs_pass
.Lfs_done:
    cmp r15, r12
    je 1f
    mov rdi, r12
    mov rsi, r15
    lea rdx, [r13*8]
    call memcpy
1:  mov rdi, r14
    call mem_free
9:  EPILOGUE

# fm_load(): the items of where the page is; the selected one (or fm_want) stays selected
fm_load:
    PROLOGUE
    cmp byte ptr [rip + fm_want], 0
    jne 1f
    call sel_item
    test rax, rax
    jz 1f
    lea rdi, [rip + fm_want]
    mov rsi, [rax + FI_path]
    call cstr_copy
1:  call fm_clear
    mov dword ptr [rip + fm_loaded], 1
    mov dword ptr [rip + fm_err], 0
    mov eax, [rip + cfg_hide_dotfiles]
    mov [rip + fm_hidden], eax
    movzx eax, byte ptr [rip + fm_path]
    cmp eax, 1
    je 2f
    cmp eax, 2
    je 3f
    lea rdi, [rip + fm_path]
    call file_mtime_ns
    mov [rip + fm_stamp], rax
    lea rdi, [rip + fm_path]
    lea rsi, [rip + load_cb]
    xor edx, edx
    call dir_each
    test rax, rax
    jns 21f
    mov dword ptr [rip + fm_err], 1
21: mov rdi, [rip + items + VEC_ptr]
    mov rsi, [rip + items + VEC_len]
    call fm_sort
    jmp 4f
2:  call load_recent
    jmp 4f
3:  call load_starred_items
4:  mov dword ptr [rip + fm_sel], -1
    cmp byte ptr [rip + fm_want], 0
    je 9f
    xor ebx, ebx
5:  mov edi, ebx
    call item
    test rax, rax
    jz 8f
    mov rdi, [rax + FI_path]
    lea rsi, [rip + fm_want]
    call strcmp_eq
    test eax, eax
    jnz 6f
    inc ebx
    jmp 5b
6:  mov [rip + fm_sel], ebx
    mov dword ptr [rip + fm_reveal], 1
8:  mov byte ptr [rip + fm_want], 0
9:  mov dword ptr [rip + g_dirty], 1
    EPILOGUE

# fm_check(): read the folder again when it changed, or when hidden files are shown now; a folder
#   that went away (a drive unmounted) gives way to Home
fm_check:
    push rbx
    cmp dword ptr [rip + fm_loaded], 0
    je 8f
    mov eax, [rip + cfg_hide_dotfiles]
    cmp eax, [rip + fm_hidden]
    jne 8f
    cmp byte ptr [rip + fm_path], 2
    jbe 9f
    lea rdi, [rip + fm_path]
    call file_mtime_ns
    test rax, rax
    jz 7f
    cmp rax, [rip + fm_stamp]
    je 9f
8:  call fm_load
9:  pop rbx
    ret
7:  call home
    mov rdi, rax
    call files_go
    pop rbx
    ret

# ---------------- Recent and Starred ----------------

# newer(a, b) -> eax 1 when FI a's time (FI_size: its "modified" in the list) is later than b's
newer:
    mov rdi, [rdi + FI_size]
    mov rsi, [rsi + FI_size]
    xor eax, eax
    test rdi, rdi
    jz 9f
    mov eax, 1
    test rsi, rsi
    jz 9f
    xor ecx, ecx
1:  movzx eax, byte ptr [rdi + rcx]
    movzx edx, byte ptr [rsi + rcx]
    cmp eax, '"'
    je 8f
    cmp eax, edx
    jne 2f
    inc ecx
    cmp ecx, 40
    jb 1b
8:  xor eax, eax
    ret
2:  seta al
    movzx eax, al
9:  ret

# load_recent(): the files of GTK's recent list (recently-used.xbel), the last used first
load_recent:
    PROLOGUE 32
    lea rdi, [rip + fm_dest]
    lea rsi, [rip + .Lxdg_data]
    lea rdx, [rip + .Ldot_share]
    call xdg_dir
    mov rdi, rax
    lea rsi, [rip + .Lrecent_rel]
    call cstr_copy
    lea rdi, [rip + fm_dest]
    call file_read_all
    test rax, rax
    jz 9f
    mov [rsp], rax
    mov r12, rax
    lea r13, [rax + rdx]
.Llr_next:
    # <bookmark href="file:///..." ... modified="2026-11-08T08:21:42Z" ...>
    mov rdi, r12
    mov rsi, r13
    sub rsi, r12
    lea rdx, [rip + .Lx_bookmark]
    mov ecx, 10
    call str_find
    test rax, rax
    js .Llr_done
    add r12, rax
    mov rdi, r12                # the tag's end
    mov rsi, r13
    sub rsi, r12
    lea rdx, [rip + .Lgt]
    mov ecx, 1
    call str_find
    test rax, rax
    js .Llr_done
    lea r14, [r12 + rax]
    mov rdi, r12
    mov rsi, r14
    sub rsi, r12
    lea rdx, [rip + .Lx_href]
    mov ecx, 13
    call str_find
    test rax, rax
    js .Llr_skip
    lea rbx, [r12 + rax + 13]   # after file://
    mov rdi, rbx
    mov rsi, r14
    sub rsi, rbx
    lea rdx, [rip + .Lquote]
    mov ecx, 1
    call str_find
    test rax, rax
    js .Llr_skip
    cmp rax, 4000
    ja .Llr_skip
    lea rdi, [rip + fm_tmp]
    mov rsi, rbx
    mov rdx, rax
    call url_decode
    mov qword ptr [rsp + 8], 0  # its time
    mov rdi, r12
    mov rsi, r14
    sub rsi, r12
    lea rdx, [rip + .Lx_modified]
    mov ecx, 10
    call str_find
    test rax, rax
    js 1f
    lea rax, [r12 + rax + 10]
    mov [rsp + 8], rax
1:  lea rdi, [rip + fm_tmp]
    call file_type
    test eax, eax
    jz .Llr_skip
    lea rdi, [rip + fm_tmp]
    call file_is_dir
    mov edx, eax
    xor edi, edi
    lea rsi, [rip + fm_tmp]
    call fi_add
    mov rcx, [rsp + 8]
    mov [rax + FI_size], rcx
.Llr_skip:
    lea r12, [r14 + 1]
    jmp .Llr_next
.Llr_done:
    # the last used first, by insertion (the list is a few hundred long)
    mov r14, [rip + items + VEC_ptr]
    mov ebx, 1
2:  cmp rbx, [rip + items + VEC_len]
    jae 5f
    mov r15, [r14 + rbx*8]
    mov r12, rbx
3:  test r12, r12
    jz 4f
    mov rdi, r15
    mov rsi, [r14 + r12*8 - 8]
    call newer
    test eax, eax
    jz 4f
    mov rax, [r14 + r12*8 - 8]
    mov [r14 + r12*8], rax
    dec r12
    jmp 3b
4:  mov [r14 + r12*8], r15
    inc rbx
    jmp 2b
5:  # the times pointed into the file
    xor ebx, ebx
6:  cmp rbx, [rip + items + VEC_len]
    jae 7f
    mov rax, [r14 + rbx*8]
    mov qword ptr [rax + FI_size], -1
    cmp rbx, RECENT_MAX
    jb 61f
    mov rdi, rax
    call mem_free
61: inc rbx
    jmp 6b
7:  cmp qword ptr [rip + items + VEC_len], RECENT_MAX
    jbe 8f
    mov qword ptr [rip + items + VEC_len], RECENT_MAX
8:  mov rdi, [rsp]
    call mem_free
9:  EPILOGUE

# starred_file() -> rax fm_dest: ".../raftaar/starred"
starred_file:
    push rbx
    call config_dir
    lea rdi, [rip + fm_dest]
    mov rsi, rax
    lea rdx, [rip + .Lstarred_name]
    call path_join_to
    lea rax, [rip + fm_dest]
    pop rbx
    ret

# load_starred(): the starred paths, a line each in starred_file, once
load_starred:
    PROLOGUE 16
    cmp dword ptr [rip + starred_loaded], 0
    jne 9f
    mov dword ptr [rip + starred_loaded], 1
    call starred_file
    mov rdi, rax
    call file_read_all
    test rax, rax
    jz 9f
    mov [rsp], rax
    mov r12, rax
    lea r13, [rax + rdx]
1:  cmp r12, r13
    jae 8f
    mov rbx, r12
2:  cmp rbx, r13
    jae 3f
    cmp byte ptr [rbx], 10
    je 3f
    inc rbx
    jmp 2b
3:  mov rsi, rbx
    sub rsi, r12
    jz 4f
    mov rdi, r12
    call mem_dup
    mov r14, rax
    lea rdi, [rip + starred]
    mov esi, 8
    call vec_push
    mov [rax], r14
4:  lea r12, [rbx + 1]
    jmp 1b
8:  mov rdi, [rsp]
    call mem_free
9:  EPILOGUE

# save_starred(): starred_file from the list
save_starred:
    PROLOGUE
    lea rdi, [rip + sb]
    call sb_clear
    xor ebx, ebx
1:  cmp rbx, [rip + starred + VEC_len]
    jae 2f
    mov rax, [rip + starred + VEC_ptr]
    mov rsi, [rax + rbx*8]
    lea rdi, [rip + sb]
    call sb_push_cstr
    lea rdi, [rip + sb]
    mov esi, 10
    call sb_push_byte
    inc rbx
    jmp 1b
2:  call starred_file
    mov rdi, rax
    call mkdir_parent
    call starred_file
    mov rdi, rax
    mov rsi, [rip + sb + SB_ptr]
    mov rdx, [rip + sb + SB_len]
    call file_write_all
    EPILOGUE

# star_index(path) -> rax its index in the starred list, or -1
star_index:
    PROLOGUE
    mov r12, rdi
    call load_starred
    xor ebx, ebx
1:  cmp rbx, [rip + starred + VEC_len]
    jae 8f
    mov rax, [rip + starred + VEC_ptr]
    mov rdi, [rax + rbx*8]
    mov rsi, r12
    call strcmp_eq
    test eax, eax
    jnz 2f
    inc rbx
    jmp 1b
2:  mov rax, rbx
    EPILOGUE
8:  mov rax, -1
    EPILOGUE

# toggle_star(path): starred, or not any more
toggle_star:
    PROLOGUE
    mov r12, rdi
    call star_index
    test rax, rax
    js 1f
    mov rbx, rax
    mov rcx, [rip + starred + VEC_ptr]
    mov rdi, [rcx + rbx*8]
    call mem_free
    mov rcx, [rip + starred + VEC_ptr]
    lea rdi, [rcx + rbx*8]
    lea rsi, [rdi + 8]
    mov rdx, [rip + starred + VEC_len]
    sub rdx, rbx
    dec rdx
    shl rdx, 3
    call memmove
    dec qword ptr [rip + starred + VEC_len]
    jmp 2f
1:  mov rdi, r12
    call strlen
    mov rdi, r12
    mov rsi, rax
    call mem_dup
    mov rbx, rax
    lea rdi, [rip + starred]
    mov esi, 8
    call vec_push
    mov [rax], rbx
2:  call save_starred
    cmp byte ptr [rip + fm_path], 2
    jne 9f
    call fm_load
9:  EPILOGUE

# load_starred_items(): the starred files and folders that are still there
load_starred_items:
    PROLOGUE
    call load_starred
    xor ebx, ebx
1:  cmp rbx, [rip + starred + VEC_len]
    jae 9f
    mov rax, [rip + starred + VEC_ptr]
    mov r12, [rax + rbx*8]
    mov rdi, r12
    call file_type
    test eax, eax
    jz 2f
    mov rdi, r12
    call file_is_dir
    mov edx, eax
    xor edi, edi
    mov rsi, r12
    call fi_add
2:  inc rbx
    jmp 1b
9:  EPILOGUE

# ---------------- pinned folders ----------------

# bm_file() -> rax fm_dest: GTK's bookmarks file
bm_file:
    push rbx
    lea rdi, [rip + fm_dest]
    lea rsi, [rip + .Lxdg_config]
    lea rdx, [rip + .Ldot_config]
    call xdg_dir
    mov rdi, rax
    lea rsi, [rip + .Lbm_rel]
    call cstr_copy
    lea rax, [rip + fm_dest]
    pop rbx
    ret

# place_icon(name cstr) -> eax the icon of a folder by its name: Documents, Music, Pictures...
place_icon:
    PROLOGUE
    mov rbx, rdi
    lea r12, [rip + place_icons]
1:  mov rsi, [r12]
    test rsi, rsi
    jz 8f
    mov rdi, rbx
    call strcmp_eq
    test eax, eax
    jnz 2f
    add r12, 16
    jmp 1b
2:  mov eax, [r12 + 8]
    EPILOGUE
8:  mov eax, IC_FOLDER
    EPILOGUE

# pl_free(vec): its places
pl_free:
    PROLOGUE
    mov r12, rdi
    xor ebx, ebx
1:  cmp rbx, [r12 + VEC_len]
    jae 2f
    imul r13, rbx, PL_SIZE
    add r13, [r12 + VEC_ptr]
    mov rdi, [r13 + PL_name]
    call mem_free
    mov rdi, [r13 + PL_path]
    call mem_free
    mov rdi, [r13 + PL_dev]
    call mem_free
    inc rbx
    jmp 1b
2:  mov qword ptr [r12 + VEC_len], 0
    EPILOGUE

# pl_add(vec, name ptr, name len, path cstr or 0, icon) -> rax PL*
pl_add:
    PROLOGUE 16
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    mov r14, rcx
    mov r15d, r8d
    mov rdi, rbx
    mov esi, PL_SIZE
    call vec_push
    mov [rsp], rax
    mov [rax + PL_icon], r15d
    mov rdi, r12
    mov rsi, r13
    call mem_dup
    mov rcx, [rsp]
    mov [rcx + PL_name], rax
    test r14, r14
    jz 1f
    mov rdi, r14
    call strlen
    mov rdi, r14
    mov rsi, rax
    call mem_dup
    mov rcx, [rsp]
    mov [rcx + PL_path], rax
1:  mov rax, [rsp]
    EPILOGUE

# pin_default(name): $HOME/name pinned, when it is there
pin_default:
    PROLOGUE
    mov rbx, rdi
    call home
    lea rdi, [rip + fm_tmp]
    mov rsi, rax
    mov rdx, rbx
    call path_join_to
    lea rdi, [rip + fm_tmp]
    call file_is_dir
    test eax, eax
    jz 9f
    mov rdi, rbx
    call place_icon
    mov r8d, eax
    mov rdi, rbx
    call strlen
    mov rdx, rax
    lea rdi, [rip + pinned]
    mov rsi, rbx
    lea rcx, [rip + fm_tmp]
    call pl_add
9:  EPILOGUE

# pinned_load(): the pinned folders again when the bookmarks file changed; without one, the usual
#   folders of Home
pinned_load:
    PROLOGUE 16
    call bm_file
    mov rdi, rax
    call file_mtime_ns
    cmp dword ptr [rip + bm_loaded], 0
    je 1f
    cmp rax, [rip + bm_stamp]
    je 9f
1:  mov [rip + bm_stamp], rax
    mov dword ptr [rip + bm_loaded], 1
    lea rdi, [rip + pinned]
    call pl_free
    call bm_file
    mov rdi, rax
    call file_read_all
    test rax, rax
    jnz 2f
    lea rbx, [rip + default_pins]
11: mov rdi, [rbx]
    test rdi, rdi
    jz 9f
    call pin_default
    add rbx, 8
    jmp 11b
2:  mov [rsp], rax
    mov r12, rax
    lea r13, [rax + rdx]
.Lpn_line:
    cmp r12, r13
    jae .Lpn_done
    mov rbx, r12                # the line's end
3:  cmp rbx, r13
    jae 4f
    cmp byte ptr [rbx], 10
    je 4f
    inc rbx
    jmp 3b
4:  mov [rsp + 8], rbx
    # "file:///path Label"
    mov rax, rbx
    sub rax, r12
    cmp rax, 8
    jb .Lpn_skip
    mov rdi, r12
    mov rsi, rax
    lea rdx, [rip + .Lfile_uri]
    mov ecx, 7
    call str_starts
    test eax, eax
    jz .Lpn_skip
    lea r14, [r12 + 7]          # the path's end: a space, or the line's
    mov r15, r14
5:  cmp r15, rbx
    jae 6f
    cmp byte ptr [r15], ' '
    je 6f
    inc r15
    jmp 5b
6:  mov rdx, r15
    sub rdx, r14
    cmp rdx, 4000
    ja .Lpn_skip
    lea rdi, [rip + fm_tmp]
    mov rsi, r14
    call url_decode
    # its label, or the folder's name
    lea r14, [r15 + 1]
    cmp r14, rbx
    jb 7f
    lea rdi, [rip + fm_tmp]
    call base_of
    mov r14, rax
    mov rbx, rax
    add rbx, rdx
7:  mov byte ptr [rbx], 0       # the label as a cstr, for place_icon (the line's end is free now)
    lea rdi, [rip + fm_tmp]
    call base_of
    mov rdi, rax
    call place_icon
    mov r8d, eax
    lea rdi, [rip + pinned]
    mov rsi, r14
    mov rdx, rbx
    sub rdx, r14
    lea rcx, [rip + fm_tmp]
    call pl_add
.Lpn_skip:
    mov r12, [rsp + 8]
    inc r12
    jmp .Lpn_line
.Lpn_done:
    mov rdi, [rsp]
    call mem_free
9:  EPILOGUE

# pinned_index(path) -> rax its index among the pinned folders, or -1
pinned_index:
    PROLOGUE
    mov r12, rdi
    xor ebx, ebx
1:  cmp rbx, [rip + pinned + VEC_len]
    jae 8f
    imul rax, rbx, PL_SIZE
    add rax, [rip + pinned + VEC_ptr]
    mov rdi, [rax + PL_path]
    mov rsi, r12
    call strcmp_eq
    test eax, eax
    jnz 2f
    inc rbx
    jmp 1b
2:  mov rax, rbx
    EPILOGUE
8:  mov rax, -1
    EPILOGUE

# pin_write(path, add): the bookmarks file with the folder's line added, or without it; the usual
#   folders written first when there was no file
pin_write:
    PROLOGUE 16
    mov r12, rdi
    mov r13d, esi
    lea rdi, [rip + sb]
    call sb_clear
    call bm_file
    mov rdi, rax
    call file_read_all
    test rax, rax
    jnz 1f
    # no file yet: the folders shown so far keep their places
    xor ebx, ebx
11: cmp rbx, [rip + pinned + VEC_len]
    jae 3f
    imul rax, rbx, PL_SIZE
    add rax, [rip + pinned + VEC_ptr]
    mov r14, [rax + PL_path]
    mov rdi, r14
    mov rsi, r12
    call strcmp_eq
    test eax, eax
    jnz 12f
    lea rdi, [rip + sb]
    lea rsi, [rip + .Lfile_uri]
    call sb_push_cstr
    lea rdi, [rip + sb]
    mov rsi, r14
    call url_encode
    lea rdi, [rip + sb]
    mov esi, 10
    call sb_push_byte
12: inc rbx
    jmp 11b
1:  mov [rsp], rax
    mov r14, rax
    lea r15, [rax + rdx]
2:  cmp r14, r15
    jae 29f
    mov rbx, r14
21: cmp rbx, r15
    jae 22f
    cmp byte ptr [rbx], 10
    je 22f
    inc rbx
    jmp 21b
22: # the line, unless it is the folder's
    mov rsi, rbx
    sub rsi, r14
    jz 28f
    cmp rsi, 7
    jb 27f
    mov rdi, r14
    lea rdx, [rip + .Lfile_uri]
    mov ecx, 7
    call str_starts
    test eax, eax
    jz 27f
    lea rcx, [r14 + 7]
    mov rdx, rcx
23: cmp rdx, rbx
    jae 24f
    cmp byte ptr [rdx], ' '
    je 24f
    inc rdx
    jmp 23b
24: sub rdx, rcx
    cmp rdx, 4000
    ja 27f
    lea rdi, [rip + fm_tmp]
    mov rsi, rcx
    call url_decode
    lea rdi, [rip + fm_tmp]
    mov rsi, r12
    call strcmp_eq
    test eax, eax
    jnz 28f
27: lea rdi, [rip + sb]
    mov rsi, r14
    mov rdx, rbx
    sub rdx, r14
    call sb_push
    lea rdi, [rip + sb]
    mov esi, 10
    call sb_push_byte
28: lea r14, [rbx + 1]
    jmp 2b
29: mov rdi, [rsp]
    call mem_free
3:  test r13d, r13d
    jz 4f
    lea rdi, [rip + sb]
    lea rsi, [rip + .Lfile_uri]
    call sb_push_cstr
    lea rdi, [rip + sb]
    mov rsi, r12
    call url_encode
    lea rdi, [rip + sb]
    mov esi, 10
    call sb_push_byte
4:  call bm_file
    mov rdi, rax
    call mkdir_parent
    call bm_file
    mov rdi, rax
    mov rsi, [rip + sb + SB_ptr]
    mov rdx, [rip + sb + SB_len]
    call file_write_all
    test rax, rax
    jns 5f
    lea rdi, [rip + .Lpin_failed]
    call app_toast
5:  mov dword ptr [rip + bm_loaded], 0
    mov dword ptr [rip + g_dirty], 1
    EPILOGUE

# ---------------- programs ----------------

.ifdef WINDOWS
fm_run:
    push rbx
    test r8d, r8d
    jnz 1f
    lea rdi, [rip + .Lno_tools]
    call app_toast
1:  xor eax, eax
    pop rbx
    ret
.else
# fm_run(argv, cwd or 0, cb, ctx, quiet) -> eax 1 when it started; cb(ctx, output, len, status) once it
#   ends, its output with its error messages. Unless quiet, a program not there says so
fm_run:
    PROLOGUE 32
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    mov r14, rcx
    mov [rsp], r8d
    mov rdi, [rbx]
    call proc_which
    test rax, rax
    jz 7f
    mov r15, rax
    mov rax, [rbx]
    mov [rsp + 8], rax          # its name, put back after
    mov [rbx], r15
    mov rdi, rbx
    mov rsi, [rip + g_envp]
    mov rdx, r12
    xor ecx, ecx
    xor r8d, r8d
    mov r9d, 1
    call run_piped_input
    mov rcx, [rsp + 8]
    mov [rbx], rcx
    mov r12, rax
    mov [rsp + 4], edx
    mov rdi, r15
    call mem_free
    test r12, r12
    jle 8f
    mov edi, FJ_SIZE
    call mem_alloc
    mov r15, rax
    mov rdi, rax
    xor esi, esi
    mov edx, FJ_SIZE
    call memset
    mov [r15 + FJ_pid], r12d
    mov eax, [rsp + 4]
    mov [r15 + FJ_fd], eax
    mov [r15 + FJ_cb], r13
    mov [r15 + FJ_ctx], r14
    mov edi, [rsp + 4]
    mov esi, POLLIN
    lea rdx, [rip + fm_job_io]
    mov rcx, r15
    call watch_add
    mov eax, 1
    EPILOGUE
7:  cmp dword ptr [rsp], 0
    jne 9f
    lea rdi, [rip + toast_buf]
    mov rsi, [rbx]
    call cstr_copy
    mov rdi, rax
    lea rsi, [rip + .Lnot_installed]
    call cstr_copy
    lea rdi, [rip + toast_buf]
    call app_toast
    jmp 9f
8:  cmp dword ptr [rsp], 0
    jne 9f
    lea rdi, [rip + .Lnot_started]
    call app_toast
9:  xor eax, eax
    EPILOGUE

# fm_job_io(fd, revents, job): its output collected; at its end, handed over
fm_job_io:
    PROLOGUE
    mov rbx, rdx
1:  lea rdi, [rbx + FJ_out]
    mov esi, 65536
    call sb_reserve
    mov rsi, rax
    mov edi, [rbx + FJ_fd]
    mov edx, 65536
    SYS SYS_read
    cmp rax, -EINTR
    je 1b
    cmp rax, -EAGAIN
    je 9f
    test rax, rax
    jle 2f
    add [rbx + FJ_out + SB_len], rax
    jmp 1b
2:  mov edi, [rbx + FJ_fd]
    call watch_remove
    mov edi, [rbx + FJ_fd]
    SYS SYS_close
    mov edi, [rbx + FJ_pid]
    xor esi, esi
    call proc_wait
    mov r12d, eax
    lea rdi, [rbx + FJ_out]
    xor esi, esi
    call sb_push_byte
    dec qword ptr [rbx + FJ_out + SB_len]
    mov rdi, [rbx + FJ_ctx]
    mov rsi, [rbx + FJ_out + SB_ptr]
    mov rdx, [rbx + FJ_out + SB_len]
    mov ecx, r12d
    call [rbx + FJ_cb]
    lea rdi, [rbx + FJ_out]
    call sb_free
    mov rdi, rbx
    call mem_free
    mov dword ptr [rip + g_dirty], 1
9:  EPILOGUE
.endif

# toast_out(ptr, len): the first line of a program's output, as a toast
toast_out:
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    xor ecx, ecx
1:  cmp rcx, r12
    jae 2f
    cmp rcx, 400
    jae 2f
    movzx eax, byte ptr [rbx + rcx]
    cmp eax, 10
    je 2f
    lea rdx, [rip + toast_buf]
    mov [rdx + rcx], al
    inc rcx
    jmp 1b
2:  lea rdx, [rip + toast_buf]
    mov byte ptr [rdx + rcx], 0
    test rcx, rcx
    jnz 3f
    lea rdi, [rip + toast_buf]
    lea rsi, [rip + .Lfailed]
    call cstr_copy
3:  lea rdi, [rip + toast_buf]
    call app_toast
    EPILOGUE

# op_done(ctx 1: a cut that was pasted, output, len, status): the folder read again; a failure said
op_done:
    push rbx
    mov rbx, rdi
    test ecx, ecx
    jz 1f
    mov rdi, rsi
    mov rsi, rdx
    call toast_out
    jmp 2f
1:  test rbx, rbx
    jz 2f
    mov byte ptr [rip + fm_clip], 0
2:  mov qword ptr [rip + fm_stamp], 0
    mov dword ptr [rip + g_dirty], 1
    pop rbx
    ret

# ---------------- drives ----------------

# lsblk_val(line, len, key with its =") -> rax the value, rdx its length; rax 0 without it
lsblk_val:
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    mov rdi, rdx
    call strlen
    mov r14, rax
    xor r15d, r15d              # where the search starts
1:  lea rdi, [rbx + r15]
    mov rsi, r12
    sub rsi, r15
    jle 8f
    mov rdx, r13
    mov rcx, r14
    call str_find
    test rax, rax
    js 8f
    add rax, r15
    # a key of its own: at the start, or after a space (TYPE is in FSTYPE too)
    test rax, rax
    jz 2f
    cmp byte ptr [rbx + rax - 1], ' '
    je 2f
    lea r15, [rax + 1]
    jmp 1b
2:  lea rdi, [rbx + rax]
    add rdi, r14
    mov rsi, rbx
    add rsi, r12
    mov rcx, rdi
3:  cmp rcx, rsi
    jae 8f
    cmp byte ptr [rcx], '"'
    je 4f
    inc rcx
    jmp 3b
4:  mov rax, rdi
    mov rdx, rcx
    sub rdx, rdi
    EPILOGUE
8:  xor eax, eax
    xor edx, edx
    EPILOGUE

# x_decode(dst, src, len): lsblk's \xNN as the byte; dst ends with a NUL
x_decode:
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    lea r13, [rsi + rdx]
1:  cmp r12, r13
    jae 9f
    movzx eax, byte ptr [r12]
    cmp al, '\\'
    jne 2f
    lea rcx, [r12 + 4]
    cmp rcx, r13
    ja 2f
    cmp byte ptr [r12 + 1], 'x'
    jne 2f
    lea rdi, [r12 + 2]
    mov esi, 2
    call parse_hex
    cmp rdx, 2
    jne 3f
    mov [rbx], al
    inc rbx
    add r12, 4
    jmp 1b
3:  movzx eax, byte ptr [r12]
2:  mov [rbx], al
    inc rbx
    inc r12
    jmp 1b
9:  mov byte ptr [rbx], 0
    EPILOGUE

# drives_scan(): lsblk lists them again, unless it still runs
drives_scan:
    PROLOGUE 64
    cmp dword ptr [rip + drives_running], 0
    jne 9f
    call time_ms
    mov [rip + drives_at], rax
    lea rax, [rip + .Llsblk]
    mov [rsp], rax
    lea rax, [rip + .Ldash_p]
    mov [rsp + 8], rax
    lea rax, [rip + .Ldash_n]
    mov [rsp + 16], rax
    lea rax, [rip + .Ldash_o]
    mov [rsp + 24], rax
    lea rax, [rip + .Llsblk_cols]
    mov [rsp + 32], rax
    mov qword ptr [rsp + 40], 0
    mov rdi, rsp
    xor esi, esi
    lea rdx, [rip + on_lsblk]
    xor ecx, ecx
    mov r8d, 1
    call fm_run
    mov [rip + drives_running], eax
9:  EPILOGUE

# media(mountpoint cstr) -> eax 1 when it is where a desktop mounts drives (not /, /boot or /home)
media:
    PROLOGUE
    mov rbx, rdi
    call strlen
    mov r12, rax
    lea r13, [rip + media_roots]
1:  mov rdx, [r13]
    test rdx, rdx
    jz 8f
    mov rdi, rdx
    call strlen
    mov rcx, rax
    mov rdi, rbx
    mov rsi, r12
    mov rdx, [r13]
    call str_starts
    test eax, eax
    jnz 9f
    add r13, 8
    jmp 1b
8:  xor eax, eax
9:  EPILOGUE

# on_lsblk(ctx, output, len, status): PATH="/dev/x" LABEL="Data" FSTYPE="ext4" MOUNTPOINT="/run/media/u/Data"
#   TYPE="part" SIZE="378.2G", a line each. File systems that are mounted where drives go, or not at all
on_lsblk:
    PROLOGUE 64
    mov dword ptr [rip + drives_running], 0
    test ecx, ecx
    jnz 9f
    mov r12, rsi
    lea r13, [rsi + rdx]
    lea rdi, [rip + drives]
    call pl_free
.Lls_line:
    cmp r12, r13
    jae .Lls_done
    mov rbx, r12
1:  cmp rbx, r13
    jae 2f
    cmp byte ptr [rbx], 10
    je 2f
    inc rbx
    jmp 1b
2:  mov [rsp], rbx
    mov r14, rbx
    sub r14, r12                # the line's length
    # a file system, not swap or a container of others
    mov rdi, r12
    mov rsi, r14
    lea rdx, [rip + .Lk_fstype]
    call lsblk_val
    test rdx, rdx
    jz .Lls_next
    mov [rsp + 8], rax
    mov [rsp + 16], rdx
    lea r15, [rip + skip_fs]
3:  mov rcx, [r15]
    test rcx, rcx
    jz 4f
    mov rdi, [rsp + 8]
    mov rsi, [rsp + 16]
    mov rdx, rcx
    call str_eq_cstr
    test eax, eax
    jnz .Lls_next
    add r15, 8
    jmp 3b
4:  # where it is mounted: nowhere, or where drives go
    mov byte ptr [rip + fm_cwd], 0
    mov rdi, r12
    mov rsi, r14
    lea rdx, [rip + .Lk_mount]
    call lsblk_val
    test rdx, rdx
    jz 5f
    cmp rdx, 4000
    ja .Lls_next
    lea rdi, [rip + fm_cwd]
    mov rsi, rax
    call x_decode
    lea rdi, [rip + fm_cwd]
    call media
    test eax, eax
    jz .Lls_next
5:  # its name: the label, else its size ("1.0T Volume")
    mov rdi, r12
    mov rsi, r14
    lea rdx, [rip + .Lk_label]
    call lsblk_val
    test rdx, rdx
    jz 6f
    cmp rdx, 400
    ja 6f
    lea rdi, [rip + fm_tmp]
    mov rsi, rax
    call x_decode
    jmp 7f
6:  mov rdi, r12
    mov rsi, r14
    lea rdx, [rip + .Lk_size]
    call lsblk_val
    and edx, 63
    lea rdi, [rip + fm_tmp]
    mov rsi, rax
    test rax, rax
    jnz 61f
    lea rsi, [rip + .Lempty]
61: call x_decode
    lea rdi, [rip + fm_tmp]
    call strlen
    lea rdi, [rip + fm_tmp]
    add rdi, rax
    lea rsi, [rip + .Lvolume]
    call cstr_copy
7:  lea rdi, [rip + fm_tmp]
    call strlen
    mov rdx, rax
    lea rdi, [rip + drives]
    lea rsi, [rip + fm_tmp]
    xor ecx, ecx
    cmp byte ptr [rip + fm_cwd], 0
    je 71f
    lea rcx, [rip + fm_cwd]
71: mov r8d, IC_DRIVE
    call pl_add
    mov r15, rax
    # its device
    mov rdi, r12
    mov rsi, r14
    lea rdx, [rip + .Lk_path]
    call lsblk_val
    test rdx, rdx
    jz .Lls_next
    and edx, 255
    lea rdi, [rip + fm_tmp]
    mov rsi, rax
    call x_decode
    lea rdi, [rip + fm_tmp]
    call strlen
    lea rdi, [rip + fm_tmp]
    mov rsi, rax
    call mem_dup
    mov [r15 + PL_dev], rax
.Lls_next:
    mov r12, [rsp]
    inc r12
    jmp .Lls_line
.Lls_done:
    mov dword ptr [rip + g_dirty], 1
9:  EPILOGUE

# drive(i) -> rax PL*, or 0
drive:
    movsxd rax, edi
    test rax, rax
    js 1f
    cmp rax, [rip + drives + VEC_len]
    jae 1f
    imul rax, rax, PL_SIZE
    add rax, [rip + drives + VEC_ptr]
    ret
1:  xor eax, eax
    ret

# drive_mount(i): udisksctl mounts it (asking for a password if it must), and the page goes there
drive_mount:
    PROLOGUE 48
    call drive
    test rax, rax
    jz 9f
    mov rbx, [rax + PL_dev]
    test rbx, rbx
    jz 9f
    lea rax, [rip + .Ludisksctl]
    mov [rsp], rax
    lea rax, [rip + .Lmount]
    mov [rsp + 8], rax
    lea rax, [rip + .Ldash_b]
    mov [rsp + 16], rax
    mov [rsp + 24], rbx
    mov qword ptr [rsp + 32], 0
    mov rdi, rsp
    xor esi, esi
    lea rdx, [rip + on_mounted]
    xor ecx, ecx
    xor r8d, r8d
    call fm_run
9:  EPILOGUE

# on_mounted(ctx, output, len, status): "Mounted /dev/x at /run/media/u/Data" (with a dot in some
#   versions): the page goes there
on_mounted:
    PROLOGUE
    mov qword ptr [rip + drives_at], 0
    mov rbx, rsi
    mov r12, rdx
    test ecx, ecx
    jz 1f
    mov rdi, rsi
    mov rsi, rdx
    call toast_out
    EPILOGUE
1:  mov rdi, rbx
    mov rsi, r12
    lea rdx, [rip + .Lat]
    mov ecx, 4
    call str_find
    test rax, rax
    js 9f
    lea r13, [rbx + rax + 4]
    lea r14, [rbx + r12]
    mov rcx, r13
2:  cmp rcx, r14
    jae 3f
    cmp byte ptr [rcx], 10
    je 3f
    inc rcx
    jmp 2b
3:  cmp rcx, r13
    jbe 9f
    cmp byte ptr [rcx - 1], '.'
    jne 4f
    dec rcx
4:  mov rdx, rcx
    sub rdx, r13
    cmp rdx, 4000
    ja 9f
    lea rdi, [rip + fm_tmp]
    mov rsi, r13
    call memcpy
    mov rdx, rcx
    sub rdx, r13
    lea rax, [rip + fm_tmp]
    mov byte ptr [rax + rdx], 0
    lea rdi, [rip + fm_tmp]
    call files_go
9:  call drives_scan
    EPILOGUE

# drive_unmount(i): udisksctl unmounts it; a page inside it goes Home first
drive_unmount:
    PROLOGUE 48
    call drive
    test rax, rax
    jz 9f
    mov rbx, [rax + PL_dev]
    test rbx, rbx
    jz 9f
    mov r12, [rax + PL_path]
    test r12, r12
    jz 1f
    mov rdi, r12
    call strlen
    mov r13, rax
    lea rdi, [rip + fm_path]
    call strlen
    cmp rax, r13
    jb 1f
    lea rdi, [rip + fm_path]
    mov rsi, rax
    mov rdx, r12
    mov rcx, r13
    call str_starts
    test eax, eax
    jz 1f
    call home
    mov rdi, rax
    call files_go
1:  lea rax, [rip + .Ludisksctl]
    mov [rsp], rax
    lea rax, [rip + .Lunmount]
    mov [rsp + 8], rax
    lea rax, [rip + .Ldash_b]
    mov [rsp + 16], rax
    mov [rsp + 24], rbx
    mov qword ptr [rsp + 32], 0
    mov rdi, rsp
    xor esi, esi
    lea rdx, [rip + on_unmounted]
    xor ecx, ecx
    xor r8d, r8d
    call fm_run
9:  EPILOGUE

on_unmounted:
    push rbx
    test ecx, ecx
    jz 1f
    mov rdi, rsi
    mov rsi, rdx
    call toast_out
1:  mov qword ptr [rip + drives_at], 0
    call drives_scan
    pop rbx
    ret

# ---------------- where the page is ----------------

# hist_push(vec, cstr): a copy at its end; the oldest goes past HIST_MAX
hist_push:
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    mov rdi, rsi
    call strlen
    mov rdi, r12
    mov rsi, rax
    call mem_dup
    mov r12, rax
    mov rdi, rbx
    mov esi, 8
    call vec_push
    mov [rax], r12
    cmp qword ptr [rbx + VEC_len], HIST_MAX
    jbe 9f
    mov rax, [rbx + VEC_ptr]
    mov rdi, [rax]
    call mem_free
    mov rdi, [rbx + VEC_ptr]
    lea rsi, [rdi + 8]
    mov rdx, [rbx + VEC_len]
    dec rdx
    shl rdx, 3
    call memmove
    dec qword ptr [rbx + VEC_len]
9:  EPILOGUE

# hist_pop(vec) -> rax its last cstr (to mem_free), or 0
hist_pop:
    mov rax, [rdi + VEC_len]
    test rax, rax
    jz 1f
    dec rax
    mov [rdi + VEC_len], rax
    mov rcx, [rdi + VEC_ptr]
    mov rax, [rcx + rax*8]
    ret
1:  xor eax, eax
    ret

# hist_clear(vec)
hist_clear:
    push rbx
    mov rbx, rdi
1:  mov rdi, rbx
    call hist_pop
    test rax, rax
    jz 2f
    mov rdi, rax
    call mem_free
    jmp 1b
2:  pop rbx
    ret

# set_path(key): the page shows it
set_path:
    push rbx
    mov rsi, rdi
    lea rdi, [rip + fm_path]
    call cstr_copy
    mov dword ptr [rip + fm_sel], -1
    mov dword ptr [rip + fm_scroll], 0
    call fm_load
    pop rbx
    ret

# files_go(path or "\1" Recent, "\2" Starred): the page goes there; Back comes back
FN files_go
    PROLOGUE
    mov rbx, rdi
    call is_here
    test eax, eax
    jnz 9f
    cmp byte ptr [rip + fm_path], 0
    je 1f
    lea rdi, [rip + back]
    lea rsi, [rip + fm_path]
    call hist_push
1:  lea rdi, [rip + fwd]
    call hist_clear
    mov rdi, rbx
    call set_path
9:  EPILOGUE

fm_back:
    lea rdi, [rip + back]
    lea rsi, [rip + fwd]
    jmp hist_step
fm_forward:
    lea rdi, [rip + fwd]
    lea rsi, [rip + back]
# hist_step(from, to): where from's last entry is, the page as it was going to to
hist_step:
    PROLOGUE
    mov r12, rsi
    call hist_pop
    test rax, rax
    jz 9f
    mov rbx, rax
    mov rdi, r12
    lea rsi, [rip + fm_path]
    call hist_push
    mov rdi, rbx
    call set_path
    mov rdi, rbx
    call mem_free
9:  EPILOGUE

# fm_up(): the folder this one is in, with this one selected
fm_up:
    push rbx
    cmp byte ptr [rip + fm_path], 2
    jbe 1f
    cmp word ptr [rip + fm_path], '/'
    je 9f
    lea rdi, [rip + fm_want]
    lea rsi, [rip + fm_path]
    call cstr_copy
    lea rdi, [rip + fm_tmp]
    lea rsi, [rip + fm_path]
    call parent_to
    lea rdi, [rip + fm_tmp]
    call files_go
    jmp 9f
1:  call home
    mov rdi, rax
    call files_go
9:  pop rbx
    ret

# fm_start(): the first place: the project's folder, else Home
fm_start:
    push rbx
    cmp byte ptr [rip + fm_path], 0
    jne 9f
    mov rdi, [rip + g_project]
    test rdi, rdi
    jnz 1f
    call home
    mov rdi, rax
1:  call set_path
9:  pop rbx
    ret

# ---------------- opening ----------------

# binary(path) -> eax 1 when it is not text: a NUL in its first 4 KiB, or a document format
binary:
    PROLOGUE 16
    mov rbx, rdi
    call strlen
    mov rdi, rbx
    mov rsi, rax
    call path_ext
    mov r12, rax
    mov r13, rdx
    lea r14, [rip + doc_exts]
1:  mov rdx, [r14]
    test rdx, rdx
    jz 2f
    mov rdi, r12
    mov rsi, r13
    call str_ieq_cstr
    test eax, eax
    jnz 8f
    add r14, 8
    jmp 1b
2:  mov rdi, rbx
    call file_open_read
    test rax, rax
    js 7f
    mov r12, rax
    mov rdi, rax
    lea rsi, [rip + fm_tmp]
    mov edx, 4096
    SYS SYS_read
    mov r13, rax
    mov rdi, r12
    SYS SYS_close
    test r13, r13
    jle 7f
    xor ecx, ecx
3:  cmp rcx, r13
    jae 7f
    lea rax, [rip + fm_tmp]
    cmp byte ptr [rax + rcx], 0
    je 8f
    inc rcx
    jmp 3b
7:  xor eax, eax
    EPILOGUE
8:  mov eax, 1
    EPILOGUE

# str_ieq_cstr(ptr, len, cstr) -> eax 1 when equal ignoring case
str_ieq_cstr:
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    mov rdi, rdx
    call strlen
    mov rdi, rbx
    mov rsi, r12
    mov rdx, r13
    mov rcx, rax
    call str_ieq
    EPILOGUE

# open_file(path): images and text in a tab here; the rest in the desktop's application for it
open_file:
    PROLOGUE
    mov rbx, rdi
    call image_probe
    test eax, eax
    jnz 1f
    mov rdi, rbx
    call binary
    test eax, eax
    jz 1f
    mov rdi, rbx
    call desktop_open
    EPILOGUE
1:  mov rdi, rbx
    call app_open_file
    test rax, rax
    js 9f
    mov dword ptr [rip + g_focus], FOCUS_EDITOR
9:  EPILOGUE

# fi_open(FI*): a folder is gone into, a file opened
fi_open:
    push rbx
    mov rbx, rdi
    lea rdi, [rip + fm_target]
    mov rsi, [rbx + FI_path]
    call cstr_copy
    cmp dword ptr [rbx + FI_dir], 0
    je 1f
    lea rdi, [rip + fm_target]
    call files_go
    pop rbx
    ret
1:  lea rdi, [rip + fm_target]
    call open_file
    pop rbx
    ret

# ---------------- what is done to files ----------------

# unique_dest(dir, name cstr) -> rax fm_dest: dir/name, or "name (copy).ext", "name (copy 2).ext"...
#   when that is taken
unique_dest:
    PROLOGUE 32
    mov rbx, rdi
    mov r12, rsi
    lea rdi, [rip + fm_dest]
    mov rsi, rbx
    mov rdx, r12
    call path_join_to
    lea rdi, [rip + fm_dest]
    call file_missing
    test eax, eax
    jnz 9f
    # the name's stem and extension (a dot file has no extension)
    mov rdi, r12
    call strlen
    mov r13, rax
    mov r14, rax                # stem length
    cmp byte ptr [r12], '.'
    je 1f
    mov rdi, r12
    mov rsi, r13
    call path_ext
    test rdx, rdx
    jz 1f
    lea r14, [rdx + 1]
    mov rcx, r13
    sub rcx, r14
    mov r14, rcx
1:  mov r15d, 1
2:  lea rdi, [rip + fm_dest]
    mov rsi, rbx
    mov rdx, r12
    call path_join_to
    # back to the end of the stem, then " (copy N)" and the extension
    lea rdi, [rip + fm_dest]
    call strlen
    lea rdi, [rip + fm_dest]
    add rdi, rax
    sub rdi, r13
    add rdi, r14
    lea rsi, [rip + .Lcopy_open]
    call cstr_copy
    mov rdi, rax
    cmp r15d, 1
    je 3f
    mov byte ptr [rdi], ' '
    inc rdi
    mov esi, r15d
    call fmt_u64
3:  mov byte ptr [rdi], ')'
    inc rdi
    lea rsi, [r12 + r14]
    call cstr_copy
    lea rdi, [rip + fm_dest]
    call file_missing
    test eax, eax
    jnz 9f
    inc r15d
    cmp r15d, 100
    jb 2b
9:  lea rax, [rip + fm_dest]
    EPILOGUE

# paste_into(src, dir, move): src (or a copy of it) into dir, under a name not taken there
paste_into:
    PROLOGUE 64
    mov rbx, rdi
    mov r12, rsi
    mov r13d, edx
    cmp byte ptr [rbx], 0
    jne 1f
    lea rdi, [rip + .Lnothing_to_paste]
    call app_toast
    jmp 9f
1:  cmp byte ptr [r12], 2
    ja 11f
    lea rdi, [rip + .Lnot_here]
    call app_toast
    jmp 9f
11: # not into itself, nor into a folder inside it
    mov rdi, rbx
    call strlen
    mov r14, rax
    mov rdi, r12
    call strlen
    mov r15, rax
    cmp r15, r14
    jb 2f
    mov rdi, r12
    mov rsi, r15
    mov rdx, rbx
    mov rcx, r14
    call str_starts
    test eax, eax
    jz 2f
    cmp r15, r14
    je 12f
    cmp byte ptr [r12 + r14], '/'
    jne 2f
12: lea rdi, [rip + .Linside]
    call app_toast
    jmp 9f
2:  # moved where it already is: nothing to do
    test r13d, r13d
    jz 3f
    lea rdi, [rip + fm_tmp]
    mov rsi, rbx
    call parent_to
    lea rdi, [rip + fm_tmp]
    mov rsi, r12
    call strcmp_eq
    test eax, eax
    jnz 9f
3:  mov rdi, rbx
    call base_of
    mov rdi, r12
    mov rsi, rax
    call unique_dest
    lea rax, [rip + .Lmv]
    lea rcx, [rip + .Lcp]
    test r13d, r13d
    cmovz rax, rcx
    mov [rsp], rax
    lea rax, [rip + .Ldash_r]
    mov [rsp + 8], rax
    lea rax, [rip + .Ldashdash]
    mov [rsp + 16], rax
    mov [rsp + 24], rbx
    lea rax, [rip + fm_dest]
    mov [rsp + 32], rax
    mov qword ptr [rsp + 40], 0
    test r13d, r13d
    jz 4f
    # mv takes no -r
    lea rax, [rip + .Ldashdash]
    mov [rsp + 8], rax
    mov [rsp + 16], rbx
    lea rax, [rip + fm_dest]
    mov [rsp + 24], rax
    mov qword ptr [rsp + 32], 0
4:  mov rdi, rsp
    xor esi, esi
    lea rdx, [rip + op_done]
    mov ecx, r13d
    xor r8d, r8d
    call fm_run
9:  EPILOGUE

# fm_trash(path): into the trash (gio); inside the trash, gone for good after asking
fm_trash:
    PROLOGUE 48
    mov rbx, rdi
    lea rdi, [rip + fm_target]
    mov rsi, rbx
    call cstr_copy
    call trash_path
    mov rdi, rax
    call is_here
    test eax, eax
    jnz 5f
    lea rax, [rip + .Lgio]
    mov [rsp], rax
    lea rax, [rip + .Ltrash]
    mov [rsp + 8], rax
    lea rax, [rip + .Ldashdash]
    mov [rsp + 16], rax
    lea rax, [rip + fm_target]
    mov [rsp + 24], rax
    mov qword ptr [rsp + 32], 0
    mov rdi, rsp
    xor esi, esi
    lea rdx, [rip + op_done]
    xor ecx, ecx
    xor r8d, r8d
    call fm_run
    EPILOGUE
5:  # "Delete “NAME” for good?"
    lea rdi, [rip + fm_target]
    call base_of
    mov rbx, rax
    lea rdi, [rip + pr_title]
    lea rsi, [rip + .Ldelete_a]
    call cstr_copy
    mov rdi, rax
    mov rsi, rbx
    call cstr_copy
    mov rdi, rax
    lea rsi, [rip + .Ldelete_b]
    call cstr_copy
    lea rdi, [rip + pr_title]
    lea rsi, [rip + .Ldelete_text]
    lea rdx, [rip + .Ldelete_btn]
    lea rcx, [rip + delete_now]
    call app_confirm
    EPILOGUE

delete_now:
    push rbx
    lea rdi, [rip + fm_target]
    call file_remove_tree
    test rax, rax
    jns 1f
    lea rdi, [rip + .Lnot_deleted]
    call app_toast
1:  mov qword ptr [rip + fm_stamp], 0
    mov dword ptr [rip + g_dirty], 1
    pop rbx
    ret

# compress(src, archive path): zip, or tar for .tar, .tar.gz, .tgz, .tar.xz and .tar.bz2, made in
#   the folder src is in
compress:
    PROLOGUE 64
    mov rbx, rdi
    mov r12, rsi
    mov rdi, r12
    call file_missing
    test eax, eax
    jnz 1f
    lea rdi, [rip + .Lexists]
    call app_toast
    jmp 9f
1:  lea rdi, [rip + fm_cwd]
    mov rsi, rbx
    call parent_to
    mov rdi, rbx
    call base_of
    mov r13, rax
    mov rdi, r12
    call strlen
    mov r14, rax
    lea r15, [rip + archive_kinds]
2:  mov rdx, [r15]
    test rdx, rdx
    jz 8f
    mov rdi, rdx
    call strlen
    mov rcx, rax
    mov rdi, r12
    mov rsi, r14
    mov rdx, [r15]
    call str_ends
    test eax, eax
    jnz 3f
    add r15, 24
    jmp 2b
3:  # program, its flags; then the archive, "--" (zip has none) and the name
    mov rax, [r15 + 8]
    mov [rsp], rax
    mov rax, [r15 + 16]
    mov [rsp + 8], rax
    mov [rsp + 16], r12
    lea rax, [rip + .Ldashdash]
    mov [rsp + 24], rax
    mov [rsp + 32], r13
    mov qword ptr [rsp + 40], 0
    lea rax, [rip + .Lzip]
    cmp [rsp], rax
    jne 4f
    mov [rsp + 24], r13
    mov qword ptr [rsp + 32], 0
4:  mov rdi, rsp
    lea rsi, [rip + fm_cwd]
    lea rdx, [rip + op_done]
    xor ecx, ecx
    xor r8d, r8d
    call fm_run
    jmp 9f
8:  lea rdi, [rip + .Lwhich_archive]
    call app_toast
9:  EPILOGUE

# pr_build(): the Properties dialog's line from what is known
pr_build:
    PROLOGUE
    lea rdi, [rip + pr_line]
    add rdi, [rip + pr_base]
    lea rsi, [rip + pr_size]
    call cstr_copy
    EPILOGUE

# fm_props(path): a dialog with what it is, how big, when it changed and where; its button copies
#   the path. A folder's size is du's, when it has counted
fm_props:
    PROLOGUE 64
    mov rbx, rdi
    lea rdi, [rip + pr_path]
    mov rsi, rbx
    call cstr_copy
    lea rbx, [rip + pr_path]
    inc qword ptr [rip + pr_gen]
    # “NAME”
    mov rdi, rbx
    call base_of
    mov r12, rax
    lea rdi, [rip + pr_title]
    lea rsi, [rip + .Lq_open]
    call cstr_copy
    mov rdi, rax
    mov rcx, rdx
    cmp rcx, 400
    jbe 1f
    mov ecx, 400
1:  mov rsi, r12
    rep movsb
    lea rsi, [rip + .Lq_close]
    call cstr_copy
    # Folder, 11 items · Modified 3 days ago · in /path · SIZE
    lea rdi, [rip + sb]
    call sb_clear
    mov rdi, rbx
    call file_is_dir
    mov r13d, eax
    test eax, eax
    jz 2f
    lea rdi, [rip + sb]
    lea rsi, [rip + .Lfolder_of]
    call sb_push_cstr
    mov rdi, rbx
    call count_of
    mov r12, rax
    lea rdi, [rip + sb]
    mov rsi, rax
    call sb_push_u64
    lea rdi, [rip + sb]
    lea rsi, [rip + .Litems]
    cmp r12, 1
    jne 11f
    lea rsi, [rip + .Litem]
11: call sb_push_cstr
    jmp 3f
2:  lea rdi, [rip + sb]
    lea rsi, [rip + .Lfile_of]
    call sb_push_cstr
    mov rdi, rbx
    call file_stamp
    lea rdi, [rip + sb]
    mov rsi, rdx
    call push_size
3:  lea rdi, [rip + sb]
    lea rsi, [rip + .Lmodified]
    call sb_push_cstr
    mov rdi, rbx
    call file_mtime
    mov rdi, rax
    mov rsi, rsp
    call fmt_age
    lea rdi, [rip + sb]
    mov rsi, rsp
    mov edx, eax
    call sb_push
    lea rdi, [rip + sb]
    lea rsi, [rip + .Lin]
    call sb_push_cstr
    lea rdi, [rip + fm_tmp]
    mov rsi, rbx
    call parent_to
    lea rdi, [rip + sb]
    lea rsi, [rip + fm_tmp]
    call sb_push_cstr
    # the line, cut to fit its buffer
    mov rcx, [rip + sb + SB_len]
    cmp rcx, 3800
    jbe 4f
    mov ecx, 3800
4:  mov [rip + pr_base], rcx
    lea rdi, [rip + pr_line]
    mov rsi, [rip + sb + SB_ptr]
    rep movsb
    mov byte ptr [rip + pr_size], 0
    test r13d, r13d
    jz 5f
    lea rdi, [rip + pr_size]
    lea rsi, [rip + .Lcounting]
    call cstr_copy
    # du -sb counts it
    lea rax, [rip + .Ldu]
    mov [rsp], rax
    lea rax, [rip + .Ldash_sb]
    mov [rsp + 8], rax
    lea rax, [rip + .Ldashdash]
    mov [rsp + 16], rax
    mov [rsp + 24], rbx
    mov qword ptr [rsp + 32], 0
    mov rdi, rsp
    xor esi, esi
    lea rdx, [rip + on_du]
    mov rcx, [rip + pr_gen]
    mov r8d, 1
    call fm_run
5:  call pr_build
    lea rdi, [rip + pr_title]
    lea rsi, [rip + pr_line]
    lea rdx, [rip + .Lcopy_path]
    lea rcx, [rip + copy_pr_path]
    call app_confirm
    EPILOGUE

# on_du(gen, output "123456\t/path", len, status)
on_du:
    PROLOGUE
    cmp rdi, [rip + pr_gen]
    jne 9f
    mov rbx, rsi
    mov r12, rdx
    lea rdi, [rip + sb]
    call sb_clear
    lea rdi, [rip + sb]
    lea rsi, [rip + .Lsep]
    call sb_push_cstr
    mov rdi, rbx
    mov rsi, r12
    call parse_u64
    test rdx, rdx
    jz 8f
    lea rdi, [rip + sb]
    mov rsi, rax
    call push_size
    lea rdi, [rip + sb]
    xor esi, esi
    call sb_push_byte
    lea rdi, [rip + pr_size]
    mov rsi, [rip + sb + SB_ptr]
    call cstr_copy
    call pr_build
    jmp 9f
8:  mov byte ptr [rip + pr_size], 0
    call pr_build
9:  mov dword ptr [rip + g_dirty], 1
    EPILOGUE

copy_pr_path:
    push rbx
    lea rdi, [rip + pr_path]
    call strlen
    lea rdi, [rip + pr_path]
    mov rsi, rax
    PCALL P_clip_set
    pop rbx
    ret

# ---------------- menus ----------------

menu_reset:
    mov dword ptr [rip + menu_n], 0
    mov qword ptr [rip + menu], 0
    mov qword ptr [rip + menu + 8], 0
    ret

# menu_add(label, handler or 0 for a line)
menu_add:
    mov eax, [rip + menu_n]
    cmp eax, MENU_MAX
    jae 1f
    shl eax, 4
    lea rcx, [rip + menu]
    mov [rcx + rax], rdi
    mov [rcx + rax + 8], rsi
    mov qword ptr [rcx + rax + 16], 0
    mov qword ptr [rcx + rax + 24], 0
    inc dword ptr [rip + menu_n]
1:  ret

menu_line:
    lea rdi, [rip + .Lline]
    xor esi, esi
    jmp menu_add

menu_show:
    push rbx
    lea rdi, [rip + menu]
    mov esi, [rip + g_mx]
    mov edx, [rip + g_my]
    call ctx_menu_open
    mov dword ptr [rip + g_menu_keys], 1
    pop rbx
    ret

# item_menu(FI*): what can be done to the item
item_menu:
    PROLOGUE
    mov rbx, rdi
    lea rdi, [rip + fm_target]
    mov rsi, [rbx + FI_path]
    call cstr_copy
    mov r12d, [rbx + FI_dir]
    call menu_reset
    test r12d, r12d
    jz 1f
    lea rdi, [rip + .Lm_term]
    lea rsi, [rip + m_term]
    call menu_add
    jmp 2f
1:  lea rdi, [rip + .Lm_open]
    lea rsi, [rip + m_open]
    call menu_add
    lea rdi, [rip + .Lm_open_app]
    lea rsi, [rip + m_open_app]
    call menu_add
2:  call menu_line
    lea rdi, [rip + .Lm_cut]
    lea rsi, [rip + m_cut]
    call menu_add
    lea rdi, [rip + .Lm_copy]
    lea rsi, [rip + m_copy]
    call menu_add
    lea rdi, [rip + .Lm_move_to]
    lea rsi, [rip + m_move_to]
    call menu_add
    lea rdi, [rip + .Lm_copy_to]
    lea rsi, [rip + m_copy_to]
    call menu_add
    call menu_line
    lea rdi, [rip + .Lm_rename]
    lea rsi, [rip + m_rename]
    call menu_add
    test r12d, r12d
    jz 3f
    lea rdi, [rip + .Lm_paste_into]
    lea rsi, [rip + m_paste_into]
    call menu_add
3:  lea rdi, [rip + .Lm_compress]
    lea rsi, [rip + m_compress]
    call menu_add
    lea rdi, [rip + .Lm_trash]
    lea rsi, [rip + m_trash]
    call menu_add
    call menu_line
    test r12d, r12d
    jz 4f
    lea rdi, [rip + fm_target]
    call pinned_index
    lea rdi, [rip + .Lm_pin]
    lea rsi, [rip + m_pin]
    test rax, rax
    js 31f
    lea rdi, [rip + .Lm_unpin]
    lea rsi, [rip + m_unpin]
31: call menu_add
4:  lea rdi, [rip + fm_target]
    call star_index
    lea rdi, [rip + .Lm_star]
    test rax, rax
    js 41f
    lea rdi, [rip + .Lm_unstar]
41: lea rsi, [rip + m_star]
    call menu_add
    call menu_line
    lea rdi, [rip + .Lm_props]
    lea rsi, [rip + m_props]
    call menu_add
    call menu_show
    EPILOGUE

# bg_menu(): the folder's own: a new folder, paste, a terminal, its properties
bg_menu:
    push rbx
    cmp byte ptr [rip + fm_path], 2
    jbe 9f
    call menu_reset
    lea rdi, [rip + .Lm_new_folder]
    lea rsi, [rip + m_new_folder]
    call menu_add
    lea rdi, [rip + .Lm_paste]
    lea rsi, [rip + m_paste]
    call menu_add
    call menu_line
    lea rdi, [rip + .Lm_term]
    lea rsi, [rip + m_term_here]
    call menu_add
    call menu_line
    lea rdi, [rip + .Lm_props]
    lea rsi, [rip + m_props_here]
    call menu_add
    call menu_show
9:  pop rbx
    ret

# place_menu(path, drive or -1): a pinned folder's, or a drive's
place_menu:
    PROLOGUE
    mov rbx, rdi
    mov [rip + fm_drive], esi
    mov r12d, esi
    mov byte ptr [rip + fm_target], 0
    test rbx, rbx
    jz 1f
    lea rdi, [rip + fm_target]
    mov rsi, rbx
    call cstr_copy
1:  call menu_reset
    test rbx, rbx
    jz 2f
    lea rdi, [rip + .Lm_term]
    lea rsi, [rip + m_term]
    call menu_add
    jmp 3f
2:  lea rdi, [rip + .Lm_mount]
    lea rsi, [rip + m_mount]
    call menu_add
3:  test r12d, r12d
    js 4f
    test rbx, rbx
    jz 5f
    lea rdi, [rip + .Lm_unmount]
    lea rsi, [rip + m_unmount]
    call menu_add
    jmp 5f
4:  lea rdi, [rip + .Lm_unpin]
    lea rsi, [rip + m_unpin]
    call menu_add
5:  call menu_show
    EPILOGUE

# the menus' items: on fm_target (a menu's item), or the folder shown
m_open:
    lea rdi, [rip + fm_target]
    jmp open_file
m_open_app:
    lea rdi, [rip + fm_target]
    jmp desktop_open
m_term_here:
    push rbx
    lea rdi, [rip + fm_target]
    lea rsi, [rip + fm_path]
    call cstr_copy
    pop rbx
m_term:
    push rbx
    lea rdi, [rip + fm_term]
    lea rsi, [rip + fm_target]
    call cstr_copy
    lea rax, [rip + fm_term]
    mov [rip + g_term_dir], rax
    call cmd_new_terminal
    pop rbx
    ret
m_cut:
    mov dword ptr [rip + fm_cut], 1
    jmp 1f
m_copy:
    mov dword ptr [rip + fm_cut], 0
1:  push rbx
    lea rdi, [rip + fm_clip]
    lea rsi, [rip + fm_target]
    call cstr_copy
    pop rbx
    ret
m_move_to:
    lea rdi, [rip + .Lp_move]
    mov esi, PROMPT_FM_MOVE
    jmp prompt_open
m_copy_to:
    lea rdi, [rip + .Lp_copy]
    mov esi, PROMPT_FM_COPY
    jmp prompt_open
m_rename:
    push rbx
    lea rdi, [rip + g_explorer_target]
    lea rsi, [rip + fm_target]
    call cstr_copy
    lea rdi, [rip + .Lp_rename]
    mov esi, PROMPT_RENAME
    call prompt_open
    pop rbx
    ret
m_paste_into:
    lea rdi, [rip + fm_clip]
    lea rsi, [rip + fm_target]
    mov edx, [rip + fm_cut]
    jmp paste_into
m_paste:
    lea rdi, [rip + fm_clip]
    lea rsi, [rip + fm_path]
    mov edx, [rip + fm_cut]
    jmp paste_into
m_compress:
    lea rdi, [rip + .Lp_compress]
    mov esi, PROMPT_FM_COMPRESS
    jmp prompt_open
m_trash:
    lea rdi, [rip + fm_target]
    jmp fm_trash
m_pin:
    lea rdi, [rip + fm_target]
    mov esi, 1
    jmp pin_write
m_unpin:
    lea rdi, [rip + fm_target]
    xor esi, esi
    jmp pin_write
m_star:
    lea rdi, [rip + fm_target]
    jmp toggle_star
m_props:
    lea rdi, [rip + fm_target]
    jmp fm_props
m_props_here:
    lea rdi, [rip + fm_path]
    jmp fm_props
m_new_folder:
    push rbx
    lea rdi, [rip + g_explorer_dir]
    lea rsi, [rip + fm_path]
    call cstr_copy
    lea rdi, [rip + .Lp_new_folder]
    mov esi, PROMPT_NEW_FOLDER
    call prompt_open
    pop rbx
    ret
m_mount:
    mov edi, [rip + fm_drive]
    jmp drive_mount
m_unmount:
    mov edi, [rip + fm_drive]
    jmp drive_unmount

# files_menu_key(handler) -> rax the shortcut its menu item shows, or 0
FN files_menu_key
    lea rcx, [rip + menu_keys]
1:  mov rax, [rcx]
    test rax, rax
    jz 2f
    cmp rax, rdi
    je 3f
    add rcx, 16
    jmp 1b
2:  xor eax, eax
    ret
3:  mov rax, [rcx + 8]
    ret

# ---------------- prompts ----------------

# files_prompt_initial(sb, kind): Move To and Copy To start at the folder shown, Compress at the
#   item's name with .zip
FN files_prompt_initial
    PROLOGUE
    mov rbx, rdi
    cmp esi, PROMPT_FM_COMPRESS
    je 2f
    lea rsi, [rip + fm_path]
    cmp byte ptr [rsi], 2
    ja 1f
    call home
    mov rsi, rax
1:  mov rdi, rbx
    call sb_push_cstr
    mov rdi, rbx
    mov esi, '/'
    call sb_push_byte
    EPILOGUE
2:  mov rdi, rbx
    lea rsi, [rip + fm_target]
    call sb_push_cstr
    mov rdi, rbx
    lea rsi, [rip + .Ldot_zip]
    call sb_push_cstr
    EPILOGUE

# files_prompt_done(path, kind)
FN files_prompt_done
    PROLOGUE
    mov rbx, rdi
    mov r12d, esi
    cmp esi, PROMPT_FM_COMPRESS
    je 3f
    mov rdi, rbx
    call file_is_dir
    test eax, eax
    jnz 1f
    lea rdi, [rip + .Lno_folder]
    call app_toast
    EPILOGUE
1:  xor edx, edx
    cmp r12d, PROMPT_FM_MOVE
    sete dl
    lea rdi, [rip + fm_target]
    mov rsi, rbx
    call paste_into
    EPILOGUE
3:  lea rdi, [rip + fm_target]
    mov rsi, rbx
    call compress
    EPILOGUE

# ---------------- commands ----------------

# files_tab() -> rax index of the file manager tab, or -1
files_tab:
    xor ecx, ecx
1:  cmp rcx, [rip + g_tabs + VEC_len]
    jae 2f
    imul rax, rcx, TAB_SIZE
    add rax, [rip + g_tabs + VEC_ptr]
    cmp qword ptr [rax + TAB_kind], TAB_FILES
    je 3f
    inc rcx
    jmp 1b
2:  mov rax, -1
    ret
3:  mov rax, rcx
    ret

FN cmd_files
    push rbx
    call files_tab
    test rax, rax
    js 1f
    mov rdi, rax
    call app_activate_tab
    jmp 2f
1:  xor edi, edi
    mov esi, TAB_FILES
    call app_add_tab
2:  mov dword ptr [rip + g_focus], FOCUS_EDITOR
    call fm_start
    mov qword ptr [rip + drives_at], 0
    mov qword ptr [rip + fm_stamp], 0
    mov dword ptr [rip + g_dirty], 1
    pop rbx
    ret

# cmd_toggle_files(): the file manager; closes it when it is the current tab
FN cmd_toggle_files
    push rbx
    call files_here
    test eax, eax
    jz 1f
    mov rdi, [rip + g_tab_cur]
    call app_close_tab
    pop rbx
    ret
1:  call cmd_files
    pop rbx
    ret

# files_here() -> eax 1 when the tab with the keys is the file manager
FN files_here
    push rbx
    xor eax, eax
    mov rdi, [rip + g_tab_cur]
    test rdi, rdi
    js 9f
    call tab_at
    cmp qword ptr [rax + TAB_kind], TAB_FILES
    sete al
    movzx eax, al
9:  pop rbx
    ret

# files_side() -> eax 1 when the sidebar shows the places in the tree's stead (asking for the
#   explorer brings the tree back)
FN files_side
    xor eax, eax
    cmp dword ptr [rip + g_focus], FOCUS_EXPLORER
    je 1f
    jmp files_here
1:  ret

# files_side_least() -> eax the sidebar's least width while it shows the places
FN files_side_least
    mov edi, 220
    jmp sc

# files_crumb_path() -> rax the folder the status bar's path is of: the one shown, while the file
#   manager has the keys (-1 for Recent and Starred, which have none); else 0
FN files_crumb_path
    push rbx
    call files_here
    test eax, eax
    jz 1f
    mov rax, -1
    cmp byte ptr [rip + fm_path], 2
    jbe 2f
    lea rax, [rip + fm_path]
2:  pop rbx
    ret
1:  xor eax, eax
    pop rbx
    ret

# ---------------- keys ----------------

# sel_move(delta): the selection that many items on, inside the list
sel_move:
    mov rcx, [rip + items + VEC_len]
    test rcx, rcx
    jz 9f
    mov eax, [rip + fm_sel]
    test eax, eax
    jns 1f
    xor eax, eax
    jmp 3f
1:  add eax, edi
    jns 2f
    xor eax, eax
2:  cmp rax, rcx
    jb 3f
    lea eax, [rcx - 1]
3:  mov [rip + fm_sel], eax
    mov dword ptr [rip + fm_reveal], 1
    mov dword ptr [rip + g_dirty], 1
9:  mov eax, 1
    ret

# target_sel() -> eax 1 with fm_target the selected item's path
target_sel:
    push rbx
    call sel_item
    test rax, rax
    jz 1f
    lea rdi, [rip + fm_target]
    mov rsi, [rax + FI_path]
    call cstr_copy
    mov eax, 1
1:  pop rbx
    ret

# files_key(keysym, cp, mods) -> eax 1 when the file manager took it
FN files_key
    PROLOGUE
    mov r12d, edi
    mov r13d, edx
    and r13d, MOD_SHIFT | MOD_CTRL | MOD_ALT
    test r13d, r13d
    jnz .Lfk_mods
    mov edi, -1
    cmp r12d, KEY_LEFT
    je .Lfk_move
    mov edi, 1
    cmp r12d, KEY_RIGHT
    je .Lfk_move
    mov edi, [rip + fm_cols]
    neg edi
    cmp r12d, KEY_UP
    je .Lfk_move
    neg edi
    cmp r12d, KEY_DOWN
    je .Lfk_move
    mov eax, [rip + fm_rows_seen]
    imul edi, eax
    cmp r12d, KEY_PAGEDOWN
    je .Lfk_move
    neg edi
    cmp r12d, KEY_PAGEUP
    je .Lfk_move
    cmp r12d, KEY_HOME
    jne 1f
    mov dword ptr [rip + fm_sel], 0
    mov edi, 0
    jmp .Lfk_move
1:  cmp r12d, KEY_END
    jne 2f
    mov rax, [rip + items + VEC_len]
    dec eax
    mov [rip + fm_sel], eax
    xor edi, edi
    jmp .Lfk_move
2:  cmp r12d, KEY_RETURN
    je 3f
    cmp r12d, KEY_KP_ENTER
    jne 4f
3:  call sel_item
    test rax, rax
    jz .Lfk_yes
    mov rdi, rax
    call fi_open
    jmp .Lfk_yes
4:  cmp r12d, KEY_BACKSPACE
    jne 5f
    call fm_up
    jmp .Lfk_yes
5:  cmp r12d, KEY_DELETE
    jne 6f
    call target_sel
    test eax, eax
    jz .Lfk_yes
    lea rdi, [rip + fm_target]
    call fm_trash
    jmp .Lfk_yes
6:  cmp r12d, KEY_F1 + 1        # F2
    jne 7f
    call target_sel
    test eax, eax
    jz .Lfk_yes
    call m_rename
    jmp .Lfk_yes
7:  cmp r12d, KEY_ESCAPE
    jne .Lfk_no
    cmp dword ptr [rip + fm_sel], 0
    jl .Lfk_no
    mov dword ptr [rip + fm_sel], -1
    jmp .Lfk_yes
.Lfk_mods:
    cmp r13d, MOD_ALT
    jne 20f
    cmp r12d, KEY_LEFT
    jne 11f
    call fm_back
    jmp .Lfk_yes
11: cmp r12d, KEY_RIGHT
    jne 12f
    call fm_forward
    jmp .Lfk_yes
12: cmp r12d, KEY_UP
    jne 13f
    call fm_up
    jmp .Lfk_yes
13: cmp r12d, KEY_RETURN
    jne .Lfk_no
    call target_sel
    test eax, eax
    jz .Lfk_yes
    call m_props
    jmp .Lfk_yes
20: mov eax, r12d
    or eax, 0x20                # a letter in either case
    cmp r13d, MOD_CTRL
    jne 30f
    cmp eax, 'c'
    jne 21f
    call target_sel
    test eax, eax
    jz .Lfk_yes
    call m_copy
    jmp .Lfk_yes
21: cmp eax, 'x'
    jne 22f
    call target_sel
    test eax, eax
    jz .Lfk_yes
    call m_cut
    jmp .Lfk_yes
22: cmp eax, 'v'
    jne .Lfk_no
    call m_paste
    jmp .Lfk_yes
30: cmp r13d, MOD_CTRL | MOD_SHIFT
    jne .Lfk_no
    cmp eax, 'n'
    jne .Lfk_no
    cmp byte ptr [rip + fm_path], 2
    jbe .Lfk_yes
    call m_new_folder
    jmp .Lfk_yes
.Lfk_move:
    call sel_move
.Lfk_yes:
    mov dword ptr [rip + g_dirty], 1
    mov eax, 1
    EPILOGUE
.Lfk_no:
    xor eax, eax
    EPILOGUE

# ---------------- drawing ----------------

# draw_folder(x, y, size, glyph icon or -1): a folder as GNOME draws one, its back darker
draw_folder:
    PROLOGUE 32
    mov r12d, edi
    mov r13d, esi
    mov r14d, edx
    mov [rsp], ecx
    COLOR eax, T_ICON + 4       # blue
    mov [rsp + 4], eax
    mov edi, eax
    mov esi, 0xffffffff
    mov edx, 110
    call color_mix
    mov [rsp + 8], eax
    mov eax, r14d               # corner radius: a tenth
    xor edx, edx
    mov ecx, 10
    div ecx
    mov r15d, eax
    # the tab
    imul edi, r14d, 4
    shr edi, 6
    add edi, r12d
    imul esi, r14d, 10
    shr esi, 6
    add esi, r13d
    imul edx, r14d, 24
    shr edx, 6
    imul ecx, r14d, 14
    shr ecx, 6
    mov r8d, r15d
    mov r9d, [rsp + 4]
    call gfx_round_rect
    # the back
    imul edi, r14d, 4
    shr edi, 6
    add edi, r12d
    imul esi, r14d, 15
    shr esi, 6
    add esi, r13d
    imul edx, r14d, 56
    shr edx, 6
    imul ecx, r14d, 42
    shr ecx, 6
    mov r8d, r15d
    mov r9d, [rsp + 4]
    call gfx_round_rect
    # the front
    imul edi, r14d, 4
    shr edi, 6
    add edi, r12d
    imul esi, r14d, 21
    shr esi, 6
    add esi, r13d
    imul edx, r14d, 56
    shr edx, 6
    imul ecx, r14d, 36
    shr ecx, 6
    mov r8d, r15d
    mov r9d, [rsp + 8]
    call gfx_round_rect
    mov edi, [rsp]
    test edi, edi
    js 9f
    imul ebx, r14d, 18          # the glyph on it
    shr ebx, 6
    mov esi, r14d
    sub esi, ebx
    sar esi, 1
    add esi, r12d
    imul edx, r14d, 39
    shr edx, 6
    add edx, r13d
    mov eax, ebx
    sar eax, 1
    sub edx, eax
    mov ecx, ebx
    mov r8d, [rsp + 4]
    call icon_draw
9:  EPILOGUE

# draw_file(x, y, size, name): a page with the file's icon on it
draw_file:
    PROLOGUE 32
    mov r12d, edi
    mov r13d, esi
    mov r14d, edx
    mov rbx, rcx
    imul eax, r14d, 12
    shr eax, 6
    add eax, r12d
    mov [rsp], eax              # page x
    imul eax, r14d, 3
    shr eax, 6
    add eax, r13d
    mov [rsp + 4], eax          # page y
    imul eax, r14d, 40
    shr eax, 6
    mov [rsp + 8], eax          # page w
    imul eax, r14d, 52
    shr eax, 6
    mov [rsp + 12], eax         # page h
    mov edi, [rsp]
    mov esi, [rsp + 4]
    mov edx, [rsp + 8]
    mov ecx, [rsp + 12]
    M r8d, MI_4
    COLOR r9d, T_BORDER
    mov eax, 0xfff4f4f4
    push rax
    push rax
    call gfx_frame
    add rsp, 16
    mov rdi, rbx
    call file_icon
    lea rcx, [rip + g_theme]
    mov r8d, [rcx + rdx*4]
    mov edi, eax
    imul ecx, r14d, 22
    shr ecx, 6
    mov esi, [rsp + 8]
    sub esi, ecx
    sar esi, 1
    add esi, [rsp]
    mov edx, [rsp + 12]
    sub edx, ecx
    sar edx, 1
    add edx, [rsp + 4]
    call icon_draw
    EPILOGUE

# draw_name(x, y, w, name, argb): the name centered in two lines at most, broken after a space, a
#   dash, a dot or an underscore when one fits; the second line cut with "…"
draw_name:
    PROLOGUE 48
    mov [rsp], edi
    mov [rsp + 4], esi
    mov [rsp + 8], edx
    mov rbx, rcx
    mov [rsp + 12], r8d
    mov rdi, rbx
    call strlen
    mov r12, rax                # length
    lea rdi, [rip + g_face_ui]
    mov rsi, rbx
    mov rdx, r12
    mov ecx, [rsp + 8]
    call text_fit
    mov r13, rax                # bytes on the first line
    test r13, r13
    jnz 1f
    mov r13d, 1
1:  cmp r13, r12
    jae 4f
    mov rcx, r13                # a break inside them
2:  dec rcx
    jz 4f
    movzx eax, byte ptr [rbx + rcx]
    cmp al, ' '
    je 3f
    cmp al, '-'
    je 3f
    cmp al, '_'
    je 3f
    cmp al, '.'
    jne 2b
3:  lea r13, [rcx + 1]
4:  cmp r13, r12
    jbe 41f
    mov r13, r12
41: mov r14, r13                # drawn of it: no space at the end
    cmp byte ptr [rbx + r14 - 1], ' '
    jne 5f
    dec r14
5:  lea rdi, [rip + g_face_ui]
    mov rsi, rbx
    mov rdx, r14
    call text_width
    mov esi, [rsp + 8]
    sub esi, eax
    sar esi, 1
    add esi, [rsp]
    lea rdi, [rip + g_face_ui]
    mov edx, [rsp + 4]
    add edx, [rip + g_face_ui + FACE_ascent]
    mov rcx, rbx
    mov r8, r14
    mov r9d, [rsp + 12]
    call text_draw
    cmp r13, r12
    jae 9f
    # the rest
    lea r15, [rbx + r13]
    mov r14, r12
    sub r14, r13
    lea rdi, [rip + g_face_ui]
    mov rsi, r15
    mov rdx, r14
    call text_width
    cmp eax, [rsp + 8]
    jle 6f
    mov eax, [rsp + 8]
6:  mov esi, [rsp + 8]
    sub esi, eax
    sar esi, 1
    add esi, [rsp]
    lea rdi, [rip + g_face_ui]
    mov edx, [rip + g_face_ui + FACE_ascent]
    add edx, [rip + g_face_ui + FACE_descent]
    add edx, [rsp + 4]
    add edx, [rip + g_face_ui + FACE_ascent]
    mov rcx, r15
    mov r8, r14
    mov r9d, [rsp + 12]
    mov eax, [rsp + 8]
    push rax
    push rax
    call text_draw_fit
    add rsp, 16
9:  EPILOGUE

# here_icon_name() -> eax the icon, rdx the name of where the page is
here_icon_name:
    push rbx
    mov eax, IC_CLOCK
    lea rdx, [rip + .Lrecent]
    cmp byte ptr [rip + fm_path], 1
    je 9f
    mov eax, IC_STAR
    lea rdx, [rip + .Lstarred]
    cmp byte ptr [rip + fm_path], 2
    je 9f
    call trash_path
    mov rdi, rax
    call is_here
    mov ecx, eax
    mov eax, IC_TRASH
    lea rdx, [rip + .Ltrash_name]
    test ecx, ecx
    jnz 9f
    call home
    mov rdi, rax
    call is_here
    mov ecx, eax
    mov eax, IC_HOME
    lea rdx, [rip + .Lhome_name]
    test ecx, ecx
    jnz 9f
    lea rdi, [rip + fm_path]
    call base_of
    mov rdx, rax
    cmp byte ptr [rdx], 0
    jne 1f
    lea rdx, [rip + .Lslash]
1:  # a drive's own folder
    push rdx
    xor ebx, ebx
2:  mov edi, ebx
    call drive
    test rax, rax
    jz 3f
    inc ebx
    mov rdi, [rax + PL_path]
    test rdi, rdi
    jz 2b
    call is_here
    test eax, eax
    jz 2b
    pop rdx
    mov eax, IC_DRIVE
    pop rbx
    ret
3:  pop rdx
    mov eax, IC_FOLDER
9:  pop rbx
    ret

# draw_header(x, y, w, h): Back, Forward and Up, and where the page is
draw_header:
    PROLOGUE 32
    mov [rsp], edi
    mov [rsp + 4], esi
    mov [rsp + 8], edx
    mov [rsp + 12], ecx
    M r13d, MI_28
    mov r14d, ecx
    sub r14d, r13d
    sar r14d, 1
    add r14d, esi               # buttons' y
    mov r12d, edi
    add r12d, [rip + g_mt + 4*MI_8]
    lea rbx, [rip + header_btns]
1:  mov edi, [rbx]
    test edi, edi
    jz 2f
    mov esi, r12d
    mov edx, r14d
    mov ecx, r13d
    mov r8d, r13d
    mov r9d, [rbx + 4]
    call ui_icon_btn
    test eax, UB_CLICK
    jz 11f
    call [rbx + 8]
11: add r12d, r13d
    add r12d, [rip + g_mt + 4*MI_4]
    add rbx, 16
    jmp 1b
2:  add r12d, [rip + g_mt + 4*MI_8]
    call here_icon_name
    mov [rsp + 16], rdx
    mov edi, eax
    mov esi, r12d
    M ecx, MI_16
    mov edx, [rsp + 12]
    sub edx, ecx
    sar edx, 1
    add edx, [rsp + 4]
    COLOR r8d, T_MUTED
    call icon_draw
    add r12d, [rip + g_mt + 4*MI_16]
    add r12d, [rip + g_mt + 4*MI_8]
    lea rdi, [rip + g_face_ui]
    mov esi, r12d
    mov edx, [rsp + 4]
    mov ecx, [rsp + 12]
    mov r8, [rsp + 16]
    COLOR r9d, T_FG
    call ui_text_c
    mov edi, [rsp]
    mov esi, [rsp + 4]
    add esi, [rsp + 12]
    sub esi, [rip + g_mt + 4*MI_1]
    mov edx, [rsp + 8]
    M ecx, MI_1
    COLOR r8d, T_BORDER
    call gfx_fill
    EPILOGUE

# files_draw(x, y, w, h): the tab: its header, then the items in a grid
FN files_draw
    PROLOGUE 128
    mov [rsp], edi
    mov [rsp + 4], esi
    mov [rsp + 8], edx
    mov [rsp + 12], ecx
    COLOR r8d, T_BG
    call gfx_fill
    call fm_start
    call fm_check
    # header
    M eax, MI_40
    add eax, [rip + g_mt + 4*MI_4]
    mov [rsp + 16], eax
    mov edi, [rsp]
    mov esi, [rsp + 4]
    mov edx, [rsp + 8]
    mov ecx, eax
    call draw_header
    # the grid's box
    mov eax, [rsp]
    mov [rsp + 20], eax         # gx
    mov eax, [rsp + 4]
    add eax, [rsp + 16]
    mov [rsp + 24], eax         # gy
    mov eax, [rsp + 8]
    sub eax, [rip + g_mt + 4*MI_12]
    mov [rsp + 28], eax         # gw (the scrollbar keeps its strip)
    mov eax, [rsp + 12]
    sub eax, [rsp + 16]
    jns 1f
    xor eax, eax
1:  mov [rsp + 32], eax         # gh
    # cells: as many columns as fit, sharing what is left
    mov edi, 112
    call sc
    mov ecx, eax
    mov eax, [rsp + 28]
    sub eax, [rip + g_mt + 4*MI_16]
    sub eax, [rip + g_mt + 4*MI_16]
    jg 2f
    mov eax, ecx
2:  mov [rsp + 64], eax         # the cells' row width
    xor edx, edx
    div ecx
    cmp eax, 1
    jge 3f
    mov eax, 1
3:  mov [rsp + 40], eax         # cols
    mov [rip + fm_cols], eax
    mov ecx, eax
    mov eax, [rsp + 64]
    xor edx, edx
    div ecx
    mov [rsp + 36], eax         # cell w
    mov edi, 56
    call sc
    mov [rsp + 44], eax         # icon size
    mov ecx, [rip + g_face_ui + FACE_ascent]
    add ecx, [rip + g_face_ui + FACE_descent]
    mov [rsp + 48], ecx         # line height
    lea eax, [rcx + rcx]
    add eax, [rsp + 44]
    add eax, [rip + g_mt + 4*MI_24]
    add eax, [rip + g_mt + 4*MI_4]
    mov [rsp + 52], eax         # cell h
    # content height, and the rows that fit
    mov rax, [rip + items + VEC_len]
    mov ecx, [rsp + 40]
    add eax, ecx
    dec eax
    xor edx, edx
    div ecx
    imul eax, [rsp + 52]
    add eax, [rip + g_mt + 4*MI_16]
    add eax, [rip + g_mt + 4*MI_16]
    mov [rsp + 56], eax
    mov eax, [rsp + 32]
    xor edx, edx
    div dword ptr [rsp + 52]
    cmp eax, 1
    jge 4f
    mov eax, 1
4:  mov [rip + fm_rows_seen], eax
    # the wheel, and the selected item brought into view
    mov edi, [rsp + 20]
    mov esi, [rsp + 24]
    mov edx, [rsp + 8]
    mov ecx, [rsp + 32]
    call ui_in
    test eax, eax
    jz 5f
    mov eax, [rip + g_scroll_y]
    add [rip + fm_scroll], eax
5:  cmp dword ptr [rip + fm_reveal], 0
    je 6f
    mov dword ptr [rip + fm_reveal], 0
    mov eax, [rip + fm_sel]
    test eax, eax
    js 6f
    xor edx, edx
    div dword ptr [rsp + 40]
    imul eax, [rsp + 52]        # the row's top in the content
    cmp eax, [rip + fm_scroll]
    jge 51f
    mov [rip + fm_scroll], eax
    jmp 6f
51: add eax, [rsp + 52]
    add eax, [rip + g_mt + 4*MI_16]
    add eax, [rip + g_mt + 4*MI_16]
    sub eax, [rsp + 32]
    cmp eax, [rip + fm_scroll]
    jle 6f
    mov [rip + fm_scroll], eax
6:  mov eax, [rsp + 56]
    sub eax, [rsp + 32]
    jns 61f
    xor eax, eax
61: cmp [rip + fm_scroll], eax
    jle 62f
    mov [rip + fm_scroll], eax
62: cmp dword ptr [rip + fm_scroll], 0
    jge 63f
    mov dword ptr [rip + fm_scroll], 0
63: mov dword ptr [rsp + 60], 0    # an item took the press
    mov dword ptr [rsp + 68], -1   # an item to open after drawing
    mov dword ptr [rsp + 72], -1   # an item whose menu opens after drawing
    mov edi, [rsp + 20]
    mov esi, [rsp + 24]
    mov edx, [rsp + 28]
    mov ecx, [rsp + 32]
    call gfx_clip_push
    cmp qword ptr [rip + items + VEC_len], 0
    jne 7f
    # nothing to show
    lea r9, [rip + .Lempty_folder]
    cmp dword ptr [rip + fm_err], 0
    je 64f
    lea r9, [rip + .Lunreadable]
64: lea rdi, [rip + g_face_ui]
    mov esi, [rsp + 20]
    mov edx, [rsp + 24]
    mov ecx, [rsp + 28]
    mov r8d, [rsp + 32]
    COLOR eax, T_MUTED
    push rax
    push rax
    call ui_text_center
    add rsp, 16
    jmp .Lfd_items_done
7:  # from the first row in view
    mov eax, [rip + fm_scroll]
    sub eax, [rip + g_mt + 4*MI_16]
    jns 71f
    xor eax, eax
71: xor edx, edx
    div dword ptr [rsp + 52]
    imul eax, [rsp + 40]
    mov ebx, eax                # item
.Lfd_item:
    mov edi, ebx
    call item
    test rax, rax
    jz .Lfd_items_done
    mov r15, rax
    mov eax, ebx
    xor edx, edx
    div dword ptr [rsp + 40]
    mov r12d, edx               # col
    imul eax, [rsp + 52]
    add eax, [rsp + 24]
    add eax, [rip + g_mt + 4*MI_16]
    sub eax, [rip + fm_scroll]
    mov r13d, eax               # cell y
    mov ecx, [rsp + 24]
    add ecx, [rsp + 32]
    cmp r13d, ecx
    jge .Lfd_items_done
    imul r12d, [rsp + 36]
    add r12d, [rsp + 20]
    add r12d, [rip + g_mt + 4*MI_16]   # cell x
    # the item as a button
    lea edi, [rbx + ID_FM_ITEM]
    lea esi, [r12 + 0]
    add esi, [rip + g_mt + 4*MI_4]
    mov edx, r13d
    mov ecx, [rsp + 36]
    sub ecx, [rip + g_mt + 4*MI_8]
    mov r8d, [rsp + 52]
    sub r8d, [rip + g_mt + 4*MI_4]
    call ui_btn
    mov r14d, eax
    test r14d, UB_PRESS
    jz 8f
    mov [rip + fm_sel], ebx
    mov dword ptr [rsp + 60], 1
    mov dword ptr [rip + g_focus], FOCUS_EDITOR
    test r14d, UB_DOUBLE
    jz 8f
    mov [rsp + 68], ebx
8:  test r14d, UB_RPRESS
    jz 81f
    mov [rip + fm_sel], ebx
    mov dword ptr [rsp + 60], 1
    mov [rsp + 72], ebx
81: # its background: selected, or under the pointer
    mov edi, r12d
    add edi, [rip + g_mt + 4*MI_4]
    mov esi, r13d
    mov edx, [rsp + 36]
    sub edx, [rip + g_mt + 4*MI_8]
    mov ecx, [rsp + 52]
    sub ecx, [rip + g_mt + 4*MI_4]
    M r8d, MI_8
    cmp ebx, [rip + fm_sel]
    jne 82f
    COLOR r9d, T_ACTIVE
    call gfx_round_rect
    jmp 83f
82: test r14d, UB_HOVER
    jz 83f
    COLOR r9d, T_HOVER
    call gfx_round_rect
83: # its icon
    mov edi, [rsp + 36]
    sub edi, [rsp + 44]
    sar edi, 1
    add edi, r12d
    mov esi, r13d
    add esi, [rip + g_mt + 4*MI_8]
    mov edx, [rsp + 44]
    cmp dword ptr [r15 + FI_dir], 0
    je 84f
    mov [rsp + 80], edi
    mov [rsp + 84], esi
    mov ecx, -1
    mov [rsp + 88], ecx
    call home                   # the usual folders of Home have their glyphs
    mov rdi, rax
    call is_here
    test eax, eax
    jz 85f
    mov rdi, [r15 + FI_name]
    call place_icon
    cmp eax, IC_FOLDER
    je 85f
    mov [rsp + 88], eax
85: mov edi, [rsp + 80]
    mov esi, [rsp + 84]
    mov edx, [rsp + 44]
    mov ecx, [rsp + 88]
    call draw_folder
    jmp 86f
84: mov rcx, [r15 + FI_name]
    call draw_file
86: # its name
    mov edi, r12d
    add edi, [rip + g_mt + 4*MI_8]
    mov esi, r13d
    add esi, [rsp + 44]
    add esi, [rip + g_mt + 4*MI_12]
    mov edx, [rsp + 36]
    sub edx, [rip + g_mt + 4*MI_16]
    mov rcx, [r15 + FI_name]
    COLOR r8d, T_FG
    call draw_name
    inc ebx
    jmp .Lfd_item
.Lfd_items_done:
    call gfx_clip_pop
    # a press between the items: nothing selected; its right button, the folder's menu
    cmp dword ptr [rsp + 60], 0
    jne 9f
    mov edi, [rsp + 20]
    mov esi, [rsp + 24]
    mov edx, [rsp + 28]
    mov ecx, [rsp + 32]
    call ui_in
    test eax, eax
    jz 9f
    test dword ptr [rip + g_pressed], 1 << BTN_LEFT
    jz 91f
    mov dword ptr [rip + fm_sel], -1
    mov dword ptr [rip + g_focus], FOCUS_EDITOR
91: test dword ptr [rip + g_pressed], 1 << BTN_RIGHT
    jz 9f
    mov dword ptr [rip + fm_sel], -1
    mov dword ptr [rip + g_focus], FOCUS_EDITOR
    call bg_menu
9:  # the scrollbar
    mov eax, [rsp + 32]
    push rax
    mov eax, [rsp + 56 + 8]
    push rax
    mov edi, ID_FM_SCROLL
    mov esi, [rsp + 16]
    add esi, [rsp + 16 + 8]
    sub esi, [rip + g_mt + 4*MI_12]
    mov edx, [rsp + 16 + 24]
    M ecx, MI_12
    mov r8d, [rsp + 16 + 32]
    lea r9, [rip + fm_scroll]
    call ui_scrollbar
    add rsp, 16
    # what the presses asked for, now that drawing is done with the items
    mov edi, [rsp + 72]
    test edi, edi
    js 92f
    call item
    test rax, rax
    jz 92f
    mov rdi, rax
    call item_menu
92: mov edi, [rsp + 68]
    test edi, edi
    js 93f
    call item
    test rax, rax
    jz 93f
    mov rdi, rax
    call fi_open
93: EPILOGUE

# place_row(id, x, y, w, h, icon, [stack] name, active) -> eax UB bits: a row of the sidebar
place_row:
    PROLOGUE 32
    mov [rsp], edi
    mov r12d, esi
    mov r13d, edx
    mov r14d, ecx
    mov r15d, r8d
    mov [rsp + 4], r9d
    mov rax, [rbp + 16]
    mov [rsp + 8], rax
    mov eax, [rbp + 24]
    mov [rsp + 16], eax
    mov edi, [rsp]
    mov esi, r12d
    mov edx, r13d
    mov ecx, r14d
    mov r8d, r15d
    call ui_btn
    mov ebx, eax
    M eax, MI_6
    lea edi, [r12 + rax]
    mov esi, r13d
    mov edx, r14d
    sub edx, eax
    sub edx, eax
    mov ecx, r15d
    M r8d, MI_RADIUS
    cmp dword ptr [rsp + 16], 0
    je 1f
    COLOR r9d, T_ACTIVE
    call gfx_round_rect
    jmp 2f
1:  test ebx, UB_HOVER
    jz 2f
    COLOR r9d, T_HOVER
    call gfx_round_rect
2:  mov edi, [rsp + 4]
    mov esi, r12d
    add esi, [rip + g_mt + 4*MI_16]
    M ecx, MI_16
    mov edx, r15d
    sub edx, ecx
    sar edx, 1
    add edx, r13d
    COLOR r8d, T_FG
    call icon_draw
    mov rdi, [rsp + 8]
    call strlen
    mov rcx, rax
    lea rdi, [rip + g_face_ui]
    mov esi, r12d
    add esi, [rip + g_mt + 4*MI_40]
    mov edx, r15d
    mov eax, [rip + g_face_ui + FACE_ascent]
    add eax, [rip + g_face_ui + FACE_descent]
    sub edx, eax
    sar edx, 1
    add edx, r13d
    add edx, [rip + g_face_ui + FACE_ascent]
    mov r8, rcx
    mov rcx, [rsp + 8]
    COLOR r9d, T_FG
    mov eax, r14d
    sub eax, [rip + g_mt + 4*MI_40]
    sub eax, [rip + g_mt + 4*MI_40]
    jns 3f
    xor eax, eax
3:  push rax
    push rax
    call text_draw_fit
    add rsp, 16
    mov eax, ebx
    EPILOGUE

# files_side_draw(x, y, w, h): the places: Home, Recent, Starred, Trash; the pinned folders; the drives
FN files_side_draw
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
    mov ecx, [rsp + 12]
    call gfx_clip_push
    call pinned_load
    call time_ms
    sub rax, [rip + drives_at]
    cmp rax, 5000
    jb 1f
    call drives_scan
1:  mov edi, 36
    call sc
    mov r14d, eax               # row height
    mov r13d, [rsp + 4]
    add r13d, [rip + g_mt + 4*MI_8]   # row y
    # the tools
    xor ebx, ebx
.Lsd_tool:
    cmp ebx, TOOLS
    jae .Lsd_tools_done
    imul r15, rbx, 24
    lea rax, [rip + tools]
    add r15, rax
    # active: where the page is
    mov rdi, [r15 + 16]
    call [r15 + 8]              # the tool's key
    mov rdi, rax
    call is_here
    push rax
    push qword ptr [r15]
    lea edi, [rbx + ID_FM_PLACE]
    mov esi, [rsp + 16]
    mov edx, r13d
    mov ecx, [rsp + 16 + 8]
    mov r8d, r14d
    mov r9d, [r15 + 20]
    call place_row
    add rsp, 16
    test eax, UB_CLICK
    jz 2f
    call [r15 + 8]
    mov rdi, rax
    call files_go
    mov dword ptr [rip + g_focus], FOCUS_EDITOR
2:  add r13d, r14d
    inc ebx
    jmp .Lsd_tool
.Lsd_tools_done:
    call .Lsd_line
    # the pinned folders
    xor ebx, ebx
.Lsd_pin:
    cmp rbx, [rip + pinned + VEC_len]
    jae .Lsd_pins_done
    imul r15, rbx, PL_SIZE
    add r15, [rip + pinned + VEC_ptr]
    mov rdi, [r15 + PL_path]
    call is_here
    push rax
    push qword ptr [r15 + PL_name]
    lea edi, [rbx + ID_FM_PLACE + 16]
    mov esi, [rsp + 16]
    mov edx, r13d
    mov ecx, [rsp + 16 + 8]
    mov r8d, r14d
    mov r9d, [r15 + PL_icon]
    call place_row
    add rsp, 16
    mov r12d, eax
    test r12d, UB_CLICK
    jz 3f
    mov rdi, [r15 + PL_path]
    call files_go
    mov dword ptr [rip + g_focus], FOCUS_EDITOR
3:  test r12d, UB_RPRESS
    jz 4f
    mov rdi, [r15 + PL_path]
    mov esi, -1
    call place_menu
4:  add r13d, r14d
    inc ebx
    jmp .Lsd_pin
.Lsd_pins_done:
    cmp qword ptr [rip + drives + VEC_len], 0
    je .Lsd_end
    call .Lsd_line
    # the drives: a click goes in (mounting it first); the button unmounts one that is mounted
    xor ebx, ebx
.Lsd_drive:
    cmp rbx, [rip + drives + VEC_len]
    jae .Lsd_end
    imul r15, rbx, PL_SIZE
    add r15, [rip + drives + VEC_ptr]
    xor eax, eax
    mov rdi, [r15 + PL_path]
    test rdi, rdi
    jz 5f
    call is_here
5:  push rax
    push qword ptr [r15 + PL_name]
    lea edi, [rbx + ID_FM_PLACE + 0x200]
    mov esi, [rsp + 16]
    mov edx, r13d
    mov ecx, [rsp + 16 + 8]
    mov r8d, r14d
    mov r9d, [r15 + PL_icon]
    call place_row
    add rsp, 16
    mov r12d, eax
    xor eax, eax
    cmp qword ptr [r15 + PL_path], 0
    je 6f
    lea edi, [rbx + ID_FM_EJECT]
    M ecx, MI_24
    mov esi, [rsp]
    add esi, [rsp + 8]
    sub esi, [rip + g_mt + 4*MI_12]
    sub esi, ecx
    mov edx, r14d
    sub edx, ecx
    sar edx, 1
    add edx, r13d
    mov r8d, ecx
    mov r9d, IC_EJECT
    call ui_icon_btn
    test eax, UB_CLICK
    jz 6f
    mov edi, ebx
    call drive_unmount
    jmp 8f
6:  test r12d, UB_CLICK
    jz 7f
    mov dword ptr [rip + g_focus], FOCUS_EDITOR
    mov rdi, [r15 + PL_path]
    test rdi, rdi
    jz 61f
    call files_go
    jmp 7f
61: mov edi, ebx
    call drive_mount
7:  test r12d, UB_RPRESS
    jz 8f
    mov rdi, [r15 + PL_path]
    mov esi, ebx
    call place_menu
8:  add r13d, r14d
    inc ebx
    jmp .Lsd_drive
.Lsd_end:
    call gfx_clip_pop
    EPILOGUE
# a line between the sections
.Lsd_line:
    sub rsp, 8
    add r13d, [rip + g_mt + 4*MI_6]
    mov edi, [rsp + 8 + 8]
    add edi, [rip + g_mt + 4*MI_12]
    mov esi, r13d
    mov edx, [rsp + 8 + 8 + 8]
    sub edx, [rip + g_mt + 4*MI_24]
    M ecx, MI_1
    COLOR r8d, T_BORDER
    call gfx_fill
    add r13d, [rip + g_mt + 4*MI_8]
    add rsp, 8
    ret

# the tools' keys: where each goes
tool_home:
    jmp home
tool_recent:
    lea rax, [rip + .Lkey_recent]
    ret
tool_starred:
    lea rax, [rip + .Lkey_starred]
    ret
tool_trash:
    jmp trash_path

# files_status(right, y, h) -> eax the x left of what it drew: the selected item's name and what it
#   holds, or its size, at the status bar's right
FN files_status
    PROLOGUE 16
    mov r12d, edi
    mov [rsp], esi
    mov [rsp + 4], edx
    mov eax, r12d
    call files_here
    test eax, eax
    jz 8f
    call sel_item
    test rax, rax
    jz 8f
    mov rbx, rax
    mov rdi, rax
    call fi_info
    lea rdi, [rip + sb]
    call sb_clear
    lea rdi, [rip + sb]
    lea rsi, [rip + .Lq_open]
    call sb_push_cstr
    mov rdi, [rbx + FI_name]
    call strlen
    mov rdx, rax
    cmp rdx, 60
    jbe 1f
    mov edx, 60
1:  lea rdi, [rip + sb]
    mov rsi, [rbx + FI_name]
    call sb_push
    lea rdi, [rip + sb]
    lea rsi, [rip + .Lselected]
    call sb_push_cstr
    cmp dword ptr [rbx + FI_dir], 0
    je 2f
    lea rdi, [rip + sb]
    lea rsi, [rip + .Lcontaining]
    call sb_push_cstr
    lea rdi, [rip + sb]
    mov rsi, [rbx + FI_count]
    call sb_push_u64
    lea rdi, [rip + sb]
    lea rsi, [rip + .Litems]
    cmp qword ptr [rbx + FI_count], 1
    jne 11f
    lea rsi, [rip + .Litem]
11: call sb_push_cstr
    jmp 3f
2:  lea rdi, [rip + sb]
    mov rsi, [rbx + FI_size]
    call push_size
3:  lea rdi, [rip + sb]
    mov esi, ')'
    call sb_push_byte
    lea rdi, [rip + sb]
    xor esi, esi
    call sb_push_byte
    mov rcx, [rip + sb + SB_len]
    cmp rcx, 500
    jbe 4f
    mov ecx, 500
4:  lea rdi, [rip + fm_meta]
    mov rsi, [rip + sb + SB_ptr]
    rep movsb
    mov byte ptr [rdi - 1], 0
    lea rdi, [rip + fm_meta]
    call strlen
    lea rdi, [rip + g_face_mini]
    lea rsi, [rip + fm_meta]
    mov rdx, rax
    call text_width
    mov esi, r12d
    sub esi, eax
    mov r13d, esi
    lea rdi, [rip + g_face_mini]
    mov edx, [rsp]
    mov ecx, [rsp + 4]
    lea r8, [rip + fm_meta]
    COLOR r9d, T_MUTED
    call ui_text_c
    mov eax, r13d
    sub eax, [rip + g_mt + 4*MI_16]
    EPILOGUE
8:  mov eax, r12d
    EPILOGUE

.section .rodata
.p2align 3
# sizes: (unit, its name, the next unit's size)
size_units:
    .quad 1000, .Lkb, 1000000
    .quad 1000000, .Lmb, 1000000000
    .quad 1000000000, .Lgb, 1000000000000
    .quad 1000000000000, .Ltb, 0
# folders with icons of their own
place_icons:
    .quad .Ln_documents, IC_FILE
    .quad .Ln_music, IC_MUSIC
    .quad .Ln_pictures, IC_IMAGE
    .quad .Ln_videos, IC_VIDEO
    .quad .Ln_downloads, IC_DOWNLOAD
    .quad .Ln_home, IC_HOME
    .quad 0, 0
default_pins:
    .quad .Ln_documents, .Ln_music, .Ln_pictures, .Ln_videos, .Ln_downloads, 0
media_roots:
    .quad .Lrun_media, .Lmedia, .Lmnt, 0
skip_fs:
    .quad .Lswap, .Lluks, .Llvm, .Lraid, .Lbcache, 0
doc_exts:
    .quad .Le_pdf, .Le_doc, .Le_docx, .Le_xls, .Le_xlsx, .Le_ppt, .Le_pptx, .Le_odt, .Le_ods, .Le_odp
    .quad .Le_epub, 0
# (suffix, program, its flags)
archive_kinds:
    .quad .Ldot_zip, .Lzip, .Lzip_flags
    .quad .Ldot_tgz, .Ltar, .Ltar_gz
    .quad .Ldot_tar_gz, .Ltar, .Ltar_gz
    .quad .Ldot_tar_xz, .Ltar, .Ltar_xz
    .quad .Ldot_tar_bz2, .Ltar, .Ltar_bz2
    .quad .Ldot_tar, .Ltar, .Ltar_c
    .quad 0, 0, 0
# the header's buttons: (id, icon), what a click does
header_btns:
    .long ID_FM_BACK, IC_CHEV_L
    .quad fm_back
    .long ID_FM_FWD, IC_CHEV_R
    .quad fm_forward
    .long ID_FM_UP, IC_CHEV_UP
    .quad fm_up
    .long 0, 0
    .quad 0
# the sidebar's tools: name, where (a function), unused, icon
tools:
    .quad .Lhome_name, tool_home
    .long 0, IC_HOME
    .quad .Lrecent, tool_recent
    .long 0, IC_CLOCK
    .quad .Lstarred, tool_starred
    .long 0, IC_STAR
    .quad .Ltrash_name, tool_trash
    .long 0, IC_TRASH
# the shortcuts the menus show (files_key has them)
menu_keys:
    .quad m_cut, .Lk_cut
    .quad m_copy, .Lk_copy
    .quad m_paste, .Lk_paste
    .quad m_rename, .Lk_f2
    .quad m_trash, .Lk_delete
    .quad m_props, .Lk_props
    .quad m_new_folder, .Lk_new_folder
    .quad 0, 0

.Lhome: .asciz "HOME"
.Lslash: .asciz "/"
.Lempty: .asciz ""
.Lline: .asciz "-"
.Lhex: .ascii "0123456789ABCDEF"
.Lxdg_data: .asciz "XDG_DATA_HOME"
.Lxdg_config: .asciz "XDG_CONFIG_HOME"
.Ldot_share: .asciz "/.local/share"
.Ldot_config: .asciz "/.config"
.Ltrash_rel: .asciz "/Trash/files"
.Lrecent_rel: .asciz "/recently-used.xbel"
.Lbm_rel: .asciz "/gtk-3.0/bookmarks"
.Lstarred_name: .asciz "starred"
.Lfile_uri: .asciz "file://"
.Lx_bookmark: .asciz "<bookmark "
.Lx_href: .asciz "href=\"file://"
.Lx_modified: .asciz "modified=\""
.Lgt: .asciz ">"
.Lquote: .asciz "\""
.Lkey_recent: .byte 1, 0
.Lkey_starred: .byte 2, 0
.Lhome_name: .asciz "Home"
.Lrecent: .asciz "Recent"
.Lstarred: .asciz "Starred"
.Ltrash_name: .asciz "Trash"
.Ln_documents: .asciz "Documents"
.Ln_music: .asciz "Music"
.Ln_pictures: .asciz "Pictures"
.Ln_videos: .asciz "Videos"
.Ln_downloads: .asciz "Downloads"
.Ln_home: .asciz "Home"
.Lrun_media: .asciz "/run/media/"
.Lmedia: .asciz "/media/"
.Lmnt: .asciz "/mnt/"
.Lswap: .asciz "swap"
.Lluks: .asciz "crypto_LUKS"
.Llvm: .asciz "LVM2_member"
.Lraid: .asciz "linux_raid_member"
.Lbcache: .asciz "bcache"
.Llsblk: .asciz "lsblk"
.Ldash_p: .asciz "-P"
.Ldash_n: .asciz "-n"
.Ldash_o: .asciz "-o"
.Llsblk_cols: .asciz "PATH,LABEL,FSTYPE,MOUNTPOINT,TYPE,SIZE"
.Lk_path: .asciz "PATH=\""
.Lk_label: .asciz "LABEL=\""
.Lk_fstype: .asciz "FSTYPE=\""
.Lk_mount: .asciz "MOUNTPOINT=\""
.Lk_size: .asciz "SIZE=\""
.Lvolume: .asciz " Volume"
.Ludisksctl: .asciz "udisksctl"
.Lmount: .asciz "mount"
.Lunmount: .asciz "unmount"
.Ldash_b: .asciz "-b"
.Lat: .asciz " at "
.Lmv: .asciz "mv"
.Lcp: .asciz "cp"
.Ldash_r: .asciz "-r"
.Ldashdash: .asciz "--"
.Lgio: .asciz "gio"
.Ltrash: .asciz "trash"
.Ldu: .asciz "du"
.Ldash_sb: .asciz "-sb"
.Lzip: .asciz "zip"
.Lzip_flags: .asciz "-rq"
.Ltar: .asciz "tar"
.Ltar_gz: .asciz "-czf"
.Ltar_xz: .asciz "-cJf"
.Ltar_bz2: .asciz "-cjf"
.Ltar_c: .asciz "-cf"
.Ldot_zip: .asciz ".zip"
.Ldot_tgz: .asciz ".tgz"
.Ldot_tar_gz: .asciz ".tar.gz"
.Ldot_tar_xz: .asciz ".tar.xz"
.Ldot_tar_bz2: .asciz ".tar.bz2"
.Ldot_tar: .asciz ".tar"
.Le_pdf: .asciz "pdf"
.Le_doc: .asciz "doc"
.Le_docx: .asciz "docx"
.Le_xls: .asciz "xls"
.Le_xlsx: .asciz "xlsx"
.Le_ppt: .asciz "ppt"
.Le_pptx: .asciz "pptx"
.Le_odt: .asciz "odt"
.Le_ods: .asciz "ods"
.Le_odp: .asciz "odp"
.Le_epub: .asciz "epub"
.Lcopy_open: .asciz " (copy"
.Lbyte: .asciz " byte"
.Lbytes: .asciz " bytes"
.Lkb: .asciz " kB"
.Lmb: .asciz " MB"
.Lgb: .asciz " GB"
.Ltb: .asciz " TB"
.Lq_open: .asciz "\xe2\x80\x9c"
.Lq_close: .asciz "\xe2\x80\x9d"
.Lselected: .asciz "\xe2\x80\x9d selected ("
.Lcontaining: .asciz "containing "
.Litems: .asciz " items"
.Litem: .asciz " item"
.Lfolder_of: .asciz "Folder, "
.Lfile_of: .asciz "File, "
.Lmodified: .asciz "  \xc2\xb7  Modified "
.Lin: .asciz "  \xc2\xb7  In "
.Lsep: .asciz "  \xc2\xb7  "
.Lcounting: .asciz "  \xc2\xb7  Counting the size\xe2\x80\xa6"
.Lcopy_path: .asciz "Copy Path"
.Lempty_folder: .asciz "Nothing here"
.Lunreadable: .asciz "This folder can't be opened"
.Lnot_installed: .asciz " is not installed"
.Lnot_started: .asciz "The command could not start"
.Lno_tools: .asciz "Not available on this system"
.Lfailed: .asciz "It did not work"
.Lnothing_to_paste: .asciz "Nothing to paste: cut or copy something first"
.Lnot_here: .asciz "Open a folder to paste into"
.Linside: .asciz "A folder can't go inside itself"
.Lexists: .asciz "Something with that name is there already"
.Lwhich_archive: .asciz "Name the archive .zip, .tar.gz, .tar.xz, .tar.bz2 or .tar"
.Lno_folder: .asciz "There is no such folder"
.Lpin_failed: .asciz "The pinned folders could not be saved"
.Lnot_deleted: .asciz "It could not be deleted"
.Ldelete_a: .asciz "Delete \xe2\x80\x9c"
.Ldelete_b: .asciz "\xe2\x80\x9d for good?"
.Ldelete_text: .asciz "It is in the trash; deleted from there, it can't be brought back."
.Ldelete_btn: .asciz "Delete"
.Lm_term: .asciz "Open in New Terminal Tab"
.Lm_open: .asciz "Open"
.Lm_open_app: .asciz "Open With Default App"
.Lm_cut: .asciz "Cut"
.Lm_copy: .asciz "Copy"
.Lm_move_to: .asciz "Move to\xe2\x80\xa6"
.Lm_copy_to: .asciz "Copy to\xe2\x80\xa6"
.Lm_rename: .asciz "Rename\xe2\x80\xa6"
.Lm_paste_into: .asciz "Paste Into Folder"
.Lm_paste: .asciz "Paste"
.Lm_compress: .asciz "Compress\xe2\x80\xa6"
.Lm_trash: .asciz "Move to Trash"
.Lm_pin: .asciz "Add to Pinned"
.Lm_unpin: .asciz "Remove from Pinned"
.Lm_star: .asciz "Star"
.Lm_unstar: .asciz "Remove Star"
.Lm_props: .asciz "Properties"
.Lm_new_folder: .asciz "New Folder\xe2\x80\xa6"
.Lm_mount: .asciz "Mount"
.Lm_unmount: .asciz "Unmount"
.Lp_move: .asciz "Move to"
.Lp_copy: .asciz "Copy to"
.Lp_compress: .asciz "Compress to"
.Lp_rename: .asciz "Rename"
.Lp_new_folder: .asciz "New folder"
.Lk_cut: .asciz "Ctrl+X"
.Lk_copy: .asciz "Ctrl+C"
.Lk_paste: .asciz "Ctrl+V"
.Lk_f2: .asciz "F2"
.Lk_delete: .asciz "Delete"
.Lk_props: .asciz "Alt+Return"
.Lk_new_folder: .asciz "Ctrl+Shift+N"
