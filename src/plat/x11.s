# X11 client over a unix socket (fallback when there is no Wayland display)
.include "raftaar.inc"

.equ XOUT, 65536
.equ XIN, 262144
.equ PEND_MAX, 256              # keys waiting for a new keymap
.equ AUTH_FAMILY_LOCAL, 256
.equ AUTH_FAMILY_WILD, 65535
.equ EVMASK, 0x0001 | 0x0002 | 0x0004 | 0x0008 | 0x0010 | 0x0020 | 0x0040 | 0x8000 | 0x20000 | 0x200000
# KeyPress KeyRelease ButtonPress ButtonRelease EnterWindow LeaveWindow PointerMotion Exposure StructureNotify FocusChange

.bss
.p2align 4
xout: .zero XOUT
xin: .zero XIN
xout_len: .long 0
xin_len: .long 0
seq: .long 0
id_base: .long 0
id_mask: .long 0
id_next: .long 0
root: .long 0
root_depth: .long 0
win: .long 0
gc: .long 0
max_req: .long 0                # in 4-byte units
big_req: .long 0
win_w: .long 0
win_h: .long 0
.p2align 3
fbuf: .quad 0
fb_w: .long 0
fb_h: .long 0
min_kc: .long 0
max_kc: .long 0
kpk: .long 0                    # keysyms per keycode
.p2align 3
kmap: .quad 0                   # keysym table
xmods: .long 0
cursors: .zero 4 * 8
cursor_font: .long 0
# atoms
a_wm_protocols: .long 0
a_wm_delete: .long 0
a_net_wm_name: .long 0
a_net_active: .long 0
a_utf8: .long 0
a_clipboard: .long 0
a_targets: .long 0
a_sel_prop: .long 0
a_net_wm_state: .long 0
a_max_h: .long 0
a_max_v: .long 0
a_wm_change_state: .long 0
a_xs_selection: .long 0         # _XSETTINGS_S0, owned by the XSETTINGS manager
a_xs_settings: .long 0
a_manager: .long 0
a_gtk_variant: .long 0
xs_owner: .long 0               # the manager's window, whose property changes raftaar selects
xs_stale: .long 0               # XSETTINGS changed: read again on the next tick
# pending synchronous reply
got_reply: .long 0
.p2align 3
reply_buf: .zero 32
reply_extra: .quad 0            # pointer into xin (valid until the next read)
reply_extra_len: .quad 0
.p2align 3
xclip: .zero SB_SIZE
own_clip: .long 0
addr: .zero 110
tmp: .zero SB_SIZE
iov2: .zero 32

.data
variant_dark: .long -1          # the _GTK_THEME_VARIANT last set: 1 dark, 0 light

.text

# ---- output ----

x_new_id:
    mov eax, [rip + id_next]
    inc dword ptr [rip + id_next]
    and eax, [rip + id_mask]
    or eax, [rip + id_base]
    ret

# x_req(ptr, len): append a request, bump the sequence number
x_req:
    push rbx
    push r12
    sub rsp, 8
    mov rbx, rdi
    mov r12, rsi
    mov eax, [rip + xout_len]
    add eax, r12d
    cmp eax, XOUT
    jb 1f
    call x_flush
1:  lea rdi, [rip + xout]
    mov eax, [rip + xout_len]
    add rdi, rax
    mov rsi, rbx
    mov rcx, r12
    rep movsb
    add [rip + xout_len], r12d
    inc dword ptr [rip + seq]
    add rsp, 8
    pop r12
    pop rbx
    ret

FN x_flush
    mov eax, [rip + xout_len]
    test eax, eax
    jz 1f
    mov edi, [rip + xfd]
    lea rsi, [rip + xout]
    mov edx, eax
    call write_all
    mov dword ptr [rip + xout_len], 0
1:  ret

# ---- input ----

# x_read() -> bytes read
x_read:
    mov edi, [rip + xfd]
    lea rsi, [rip + xin]
    mov eax, [rip + xin_len]
    add rsi, rax
    mov edx, XIN
    sub edx, eax
    SYS SYS_read
    test rax, rax
    jle 1f
    add [rip + xin_len], eax
1:  ret

# x_process(): handle complete messages in xin
x_process:
    PROLOGUE
    xor ebx, ebx
1:  mov eax, [rip + xin_len]
    sub eax, ebx
    cmp eax, 32
    jb 8f
    lea r12, [rip + xin]
    add r12, rbx
    mov r13d, 32
    movzx ecx, byte ptr [r12]
    and ecx, 0x7f
    cmp ecx, 1
    je 2f
    cmp ecx, 35
    jne 3f
2:  mov edx, [r12 + 4]
    shl edx, 2
    add r13d, edx
3:  cmp eax, r13d
    jb 8f
    mov rdi, r12
    mov esi, r13d
    call x_message
    add ebx, r13d
    cmp dword ptr [rip + keymap_stale], 0
    je 1b
    # a new keymap: load it before the messages after this one
    mov ecx, [rip + xin_len]
    sub ecx, ebx
    mov [rip + xin_len], ecx
    lea rdi, [rip + xin]
    lea rsi, [rdi + rbx]
    rep movsb
    call x_keymap_refresh
    xor ebx, ebx
    jmp 1b
8:  # keep the tail
    mov ecx, [rip + xin_len]
    sub ecx, ebx
    mov [rip + xin_len], ecx
    lea rdi, [rip + xin]
    lea rsi, [rdi + rbx]
    rep movsb
    EPILOGUE

# x_keymap_refresh(): load the keymap until it is current, then the keys that waited for it
x_keymap_refresh:
    push rbx
    mov dword ptr [rip + keymap_busy], 1
1:  cmp dword ptr [rip + keymap_stale], 0
    je 2f
    mov dword ptr [rip + keymap_stale], 0
    call x_load_keymap
    jmp 1b
2:  xor ebx, ebx
3:  cmp ebx, [rip + pend_n]
    jae 4f
    lea rax, [rip + pend]
    mov ecx, [rax + rbx*8 + 4]
    mov [rip + xmods], ecx
    mov edi, [rax + rbx*8]
    call x_key
    inc ebx
    cmp dword ptr [rip + keymap_stale], 0
    jne 1b
    jmp 3b
4:  mov dword ptr [rip + pend_n], 0
    mov dword ptr [rip + keymap_busy], 0
    pop rbx
    ret

# x_message(ptr, len)
x_message:
    PROLOGUE
    mov rbx, rdi
    mov r12d, esi
    movzx eax, byte ptr [rbx]
    and eax, 0x7f
    test eax, eax
    jz .Lxm_error
    cmp eax, 1
    je .Lxm_reply
    cmp eax, 2
    je .Lxm_key
    cmp eax, 4
    je .Lxm_bpress
    cmp eax, 5
    je .Lxm_brelease
    cmp eax, 6
    je .Lxm_motion
    cmp eax, 8
    je .Lxm_leave
    cmp eax, 9
    je .Lxm_focusin
    cmp eax, 10
    je .Lxm_focusout
    cmp eax, 12
    je .Lxm_expose
    cmp eax, 22
    je .Lxm_configure
    cmp eax, 29
    je .Lxm_selclear
    cmp eax, 30
    je .Lxm_selreq
    cmp eax, 31
    je .Lxm_selnotify
    cmp eax, 33
    je .Lxm_client
    cmp eax, 34
    je .Lxm_mapping
    cmp eax, 28
    je .Lxm_property
    cmp eax, 17
    je .Lxm_destroy
    # XKB NewKeyboardNotify (0) and MapNotify (1): a client using XKB gets no MappingNotify for these
    cmp eax, [rip + xkb_event]
    jne .Lxm_ret
    cmp byte ptr [rbx + 1], 1
    jbe .Lxm_mapping
    jmp .Lxm_ret
.Lxm_error:
    # errors are non-fatal for us (e.g. a stale property), but one answering the request a reply is
    # awaited for ends the wait: reply_buf then starts with 0
    movzx eax, word ptr [rbx + 2]
    cmp eax, [rip + want_seq]
    jne .Lxm_ret
    lea rdi, [rip + reply_buf]
    mov rsi, rbx
    mov ecx, 32
    rep movsb
    lea rax, [rbx + 32]
    mov [rip + reply_extra], rax
    mov qword ptr [rip + reply_extra_len], 0
    mov dword ptr [rip + got_reply], 1
    jmp .Lxm_ret
.Lxm_reply:
    movzx eax, word ptr [rbx + 2]
    # a paste reply is handled right here (the buffer moves after this). It has a sequence number of
    # its own, as it may come while a synchronous request (want_seq) waits for its reply.
    cmp dword ptr [rip + paste_wait], 0
    je 1f
    cmp eax, [rip + paste_seq]
    jne 1f
    mov dword ptr [rip + paste_wait], 0
    lea rdi, [rbx + 32]
    mov esi, [rbx + 16]         # value length in format units (format 8)
    call app_on_paste
    jmp .Lxm_ret
1:  cmp eax, [rip + want_seq]
    jne .Lxm_ret
    lea rdi, [rip + reply_buf]
    mov rsi, rbx
    mov ecx, 32
    rep movsb
    lea rax, [rbx + 32]
    mov [rip + reply_extra], rax
    mov eax, r12d
    sub eax, 32
    mov [rip + reply_extra_len], rax
    mov dword ptr [rip + got_reply], 1
    jmp .Lxm_ret
.Lxm_key:
    movzx eax, word ptr [rbx + 28]
    movzx edi, byte ptr [rbx + 1]
    # the keymap changed: keys wait for the new one (programs that type by remapping a spare key)
    mov ecx, [rip + keymap_stale]
    or ecx, [rip + keymap_busy]
    jnz 1f
    mov [rip + xmods], eax
    call x_key
    jmp .Lxm_ret
1:  mov ecx, [rip + pend_n]
    cmp ecx, PEND_MAX
    jae .Lxm_ret
    lea rdx, [rip + pend]
    mov [rdx + rcx*8], edi
    mov [rdx + rcx*8 + 4], eax
    inc dword ptr [rip + pend_n]
    jmp .Lxm_ret
.Lxm_bpress:
    movzx eax, word ptr [rbx + 28]
    mov [rip + xmods], eax
    call x_motion_from
    movzx edi, byte ptr [rbx + 1]
    cmp edi, 4
    jb 1f
    cmp edi, 7
    ja .Lxm_ret
    # wheel buttons
    mov esi, 60
    xor edi, edi
    movzx eax, byte ptr [rbx + 1]
    cmp eax, 4
    jne 11f
    neg esi
    jmp 13f
11: cmp eax, 5
    je 13f
    mov edi, esi
    xor esi, esi
    cmp eax, 6
    jne 13f
    neg edi
13: mov edx, [rip + xmods]
    call app_on_scroll
    jmp .Lxm_ret
1:  call x_btn
    mov esi, 1
    mov edx, [rip + xmods]
    call x_mods
    call app_on_button
    jmp .Lxm_ret
.Lxm_brelease:
    call x_motion_from
    movzx edi, byte ptr [rbx + 1]
    cmp edi, 4
    jae .Lxm_ret
    call x_btn
    xor esi, esi
    mov edx, [rip + xmods]
    call x_mods
    call app_on_button
    jmp .Lxm_ret
.Lxm_motion:
    call x_motion_from
    jmp .Lxm_ret
.Lxm_leave:
    call app_on_pointer_leave
    jmp .Lxm_ret
.Lxm_focusin:
    mov edi, 1
    call app_on_focus
    jmp .Lxm_ret
.Lxm_focusout:
    xor edi, edi
    call app_on_focus
    jmp .Lxm_ret
.Lxm_expose:
    mov dword ptr [rip + g_dirty], 1
    jmp .Lxm_ret
.Lxm_configure:
    # ours, not the root's (raftaar selects the root's structure events for XSETTINGS managers)
    mov eax, [rbx + 8]
    cmp eax, [rip + win]
    jne .Lxm_ret
    movzx eax, word ptr [rbx + 20]
    movzx ecx, word ptr [rbx + 22]
    cmp eax, [rip + win_w]
    jne 2f
    cmp ecx, [rip + win_h]
    je .Lxm_ret
2:  mov [rip + win_w], eax
    mov [rip + win_h], ecx
    call x_resize_fb
    jmp .Lxm_ret
.Lxm_selclear:
    mov dword ptr [rip + own_clip], 0
    jmp .Lxm_ret
.Lxm_selreq:
    mov rdi, rbx
    call x_serve_selection
    jmp .Lxm_ret
.Lxm_selnotify:
    # property with the pasted text is ready: fetch it
    mov eax, [rbx + 20]
    test eax, eax
    jz .Lxm_ret
    call x_get_paste
    jmp .Lxm_ret
.Lxm_client:
    mov eax, [rbx + 8]
    cmp eax, [rip + a_manager]
    jne 1f
    # a new XSETTINGS manager announces itself to the root
    mov eax, [rbx + 16]
    cmp eax, [rip + a_xs_selection]
    jne .Lxm_ret
    mov dword ptr [rip + xs_stale], 1
    jmp .Lxm_ret
1:  cmp eax, [rip + a_wm_protocols]
    jne .Lxm_ret
    mov eax, [rbx + 12]
    cmp eax, [rip + a_wm_delete]
    jne .Lxm_ret
    call app_on_close
    jmp .Lxm_ret
.Lxm_mapping:
    call x_load_keymap_async
    jmp .Lxm_ret
.Lxm_property:
    # the XSETTINGS manager's settings changed
    mov eax, [rbx + 4]
    test eax, eax
    jz .Lxm_ret
    cmp eax, [rip + xs_owner]
    jne .Lxm_ret
    mov eax, [rbx + 8]
    cmp eax, [rip + a_xs_settings]
    jne .Lxm_ret
    mov dword ptr [rip + xs_stale], 1
    jmp .Lxm_ret
.Lxm_destroy:
    # the manager quit
    mov eax, [rbx + 8]
    test eax, eax
    jz .Lxm_ret
    cmp eax, [rip + xs_owner]
    jne .Lxm_ret
    mov dword ptr [rip + xs_stale], 1
.Lxm_ret:
    EPILOGUE

x_motion_from:
    movsx edi, word ptr [rbx + 24]
    movsx esi, word ptr [rbx + 26]
    push rbx
    call app_on_motion
    pop rbx
    ret

# X buttons 1 left 2 middle 3 right -> ours
x_btn:
    cmp edi, 2
    jne 1f
    mov edi, BTN_MIDDLE
    ret
1:  cmp edi, 3
    jne 2f
    mov edi, BTN_RIGHT
2:  ret

# x_mods: X state -> MOD_* in edx
x_mods:
    mov eax, edx
    xor edx, edx
    test eax, 1
    jz 1f
    or edx, MOD_SHIFT
1:  test eax, 4
    jz 2f
    or edx, MOD_CTRL
2:  test eax, 8
    jz 3f
    or edx, MOD_ALT
3:  test eax, 64
    jz 4f
    or edx, MOD_SUPER
4:  ret

# x_key(keycode)
x_key:
    PROLOGUE
    mov rax, [rip + kmap]
    test rax, rax
    jz 9f
    cmp edi, [rip + min_kc]
    jb 9f
    cmp edi, [rip + max_kc]
    ja 9f
    mov ebx, edi
    sub ebx, [rip + min_kc]
    imul ebx, [rip + kpk]
    # columns: group 1 levels 1-2, group 2 levels 1-2, group 1 levels 3-4, group 2 levels 3-4;
    # the group is in state bits 13-14 (XKB is on), AltGr (level 3) sets Mod5
    xor edx, edx
    mov ecx, [rip + xmods]
    shr ecx, 13
    and ecx, 3
    cmp dword ptr [rip + kpk], 4
    jb 1f
    test ecx, ecx
    jz 1f
    # shortcuts use the first layout
    test dword ptr [rip + xmods], 4 | 8 | 64
    jnz 1f
    mov edx, 2
1:  test dword ptr [rip + xmods], 0x80
    jz 11f
    lea ecx, [rdx + 6]
    cmp ecx, [rip + kpk]
    ja 11f
    lea ecx, [rbx + rdx + 4]
    mov rax, [rip + kmap]
    cmp dword ptr [rax + rcx*4], 0
    je 11f
    add edx, 4
11: add ebx, edx
    mov r12d, ebx               # base column
    mov eax, [rip + xmods]
    xor edx, edx
    test eax, 1
    setnz dl
    # num lock (mod2): keypad keys swap levels, digits first
    test eax, 0x10
    jz 12f
    mov rcx, [rip + kmap]
    mov ecx, [rcx + r12*4 + 4]
    sub ecx, 0xff80
    cmp ecx, 0xffbd - 0xff80
    ja 12f
    xor edx, 1
12:
    # caps lock on letters flips shift
    mov rcx, [rip + kmap]
    mov edi, [rcx + r12*4]
    test eax, 2
    jz 2f
    push rdx
    push rdx
    call keysym_is_lower_x
    pop rdx
    pop rdx
    xor edx, eax
2:  lea r13d, [r12 + rdx]
    mov rcx, [rip + kmap]
    mov eax, [rcx + r13*4]
    test eax, eax
    jnz 3f
    mov eax, [rcx + r12*4]
3:  mov r14d, eax
    mov edi, eax
    call keysym_to_unicode
    mov r15d, eax
    # and the key's unshifted character, the base column's (g_key_base)
    mov rcx, [rip + kmap]
    mov edi, [rcx + r12*4]
    call keysym_to_unicode
    mov [rip + g_key_base], eax
    mov edx, [rip + xmods]
    call x_mods
    mov edi, r14d
    mov esi, r15d
    call app_on_key
    mov dword ptr [rip + g_key_base], 0
9:  EPILOGUE

# x_key_test(keycode, state): feed a key press as if it came from the server (control socket)
FN x_key_test
    mov [rip + xmods], esi
    jmp x_key

keysym_is_lower_x:
    lea eax, [rdi - 'a']
    cmp eax, 25
    jbe 1f
    lea eax, [rdi - 0x6c0]
    cmp eax, 0x1f
    jbe 1f
    lea eax, [rdi - 0xe0]
    cmp eax, 0x1e
    jbe 1f
    xor eax, eax
    ret
1:  mov eax, 1
    ret

x_on_readable:
    push rbx
    test esi, POLLIN
    jz 2f
    call x_read
    test rax, rax
    jz 3f
    js 1f
    call x_process
1:  pop rbx
    ret
2:  test esi, POLLHUP | POLLERR
    jz 1b
3:  lea rdi, [rip + .Lclosed]
    call die

# x_wait_reply(): flush, then read until the reply for want_seq arrives
x_wait_reply:
    push rbx
    mov dword ptr [rip + got_reply], 0
    call x_flush
1:  cmp dword ptr [rip + got_reply], 0
    jne 2f
    call x_read
    test rax, rax
    jle 3f
    call x_process_until_reply
    jmp 1b
2:  mov dword ptr [rip + want_seq], -1
    pop rbx
    ret
3:  lea rdi, [rip + .Lclosed]
    call die

# like x_process but stops right after the wanted reply so reply_extra stays valid
x_process_until_reply:
    PROLOGUE
    xor ebx, ebx
1:  cmp dword ptr [rip + got_reply], 0
    jne 8f
    mov eax, [rip + xin_len]
    sub eax, ebx
    cmp eax, 32
    jb 8f
    lea r12, [rip + xin]
    add r12, rbx
    mov r13d, 32
    movzx ecx, byte ptr [r12]
    and ecx, 0x7f
    cmp ecx, 1
    je 2f
    cmp ecx, 35
    jne 3f
2:  mov edx, [r12 + 4]
    shl edx, 2
    add r13d, edx
3:  cmp eax, r13d
    jb 8f
    mov rdi, r12
    mov esi, r13d
    call x_message
    add ebx, r13d
    jmp 1b
8:  # copy the reply payload out before compacting
    cmp dword ptr [rip + got_reply], 0
    je 9f
    lea rdi, [rip + tmp]
    call sb_clear
    lea rdi, [rip + tmp]
    mov rsi, [rip + reply_extra]
    mov rdx, [rip + reply_extra_len]
    call sb_push
    mov rax, [rip + tmp + SB_ptr]
    mov [rip + reply_extra], rax
9:  mov ecx, [rip + xin_len]
    sub ecx, ebx
    mov [rip + xin_len], ecx
    lea rdi, [rip + xin]
    lea rsi, [rdi + rbx]
    rep movsb
    EPILOGUE

# ---- requests ----

# x_intern(name cstr) -> atom
x_intern:
    PROLOGUE 64
    mov rbx, rdi
    call strlen
    mov r12, rax
    lea rdi, [rsp]
    xor esi, esi
    mov edx, 64
    call memset
    mov byte ptr [rsp], 16      # InternAtom
    mov byte ptr [rsp + 1], 0   # only_if_exists = false
    lea eax, [r12 + 3]
    and eax, -4
    add eax, 8
    mov r13d, eax
    shr eax, 2
    mov [rsp + 2], ax
    mov [rsp + 4], r12w
    lea rdi, [rsp + 8]
    mov rsi, rbx
    mov rcx, r12
    rep movsb
    lea rdi, [rsp]
    mov esi, r13d
    call x_req
    mov eax, [rip + seq]
    and eax, 0xffff
    mov [rip + want_seq], eax
    call x_wait_reply
    mov eax, [rip + reply_buf + 8]
    EPILOGUE

# x_change_prop(window, prop, type, format(8/32), data, nunits)
x_change_prop:
    PROLOGUE 32
    mov r12d, edi
    mov r13d, esi
    mov r14d, edx
    mov r15d, ecx
    mov rbx, r8
    mov [rsp + 16], r9
    # bytes of data
    mov eax, r9d
    cmp r15d, 32
    jne 1f
    shl eax, 2
1:  mov [rsp + 24], eax
    add eax, 3
    and eax, -4
    add eax, 24
    mov [rsp + 28], eax         # request bytes
    lea rdi, [rip + tmp]
    call sb_clear
    lea rdi, [rip + tmp]
    mov esi, [rsp + 28]
    call sb_reserve
    mov rdi, rax
    mov byte ptr [rdi], 18      # ChangeProperty
    mov byte ptr [rdi + 1], 0   # Replace
    mov eax, [rsp + 28]
    shr eax, 2
    mov [rdi + 2], ax
    mov [rdi + 4], r12d
    mov [rdi + 8], r13d
    mov [rdi + 12], r14d
    mov [rdi + 16], r15b
    mov byte ptr [rdi + 17], 0
    mov word ptr [rdi + 18], 0
    mov rax, [rsp + 16]
    mov [rdi + 20], eax
    lea rdi, [rdi + 24]
    mov rsi, rbx
    mov ecx, [rsp + 24]
    rep movsb
    mov ecx, [rsp + 28]
    sub ecx, [rsp + 24]
    sub ecx, 24
    xor eax, eax
    rep stosb
    mov rdi, [rip + tmp + SB_ptr]
    mov esi, [rsp + 28]
    call x_req
    EPILOGUE

# ---- connection ----

# read_auth(display number cstr) -> tmp holds cookie (16 bytes) ; eax = 1 if found
read_auth:
    PROLOGUE 448
    mov [rsp], rdi
    # utsname is 6 * 65 bytes, with nodename at +65. Its sysname is unused.
    lea rdi, [rsp + 16]
    SYS SYS_uname
    test rax, rax
    js 1f
    lea rax, [rsp + 81]         # nodename
    jmp 2f
1:  xor eax, eax
2:  mov [rsp + 16], rax         # hostname pointer, or zero if uname failed
    lea rdi, [rip + .Lxauth_hostname]
    call getenv
    mov [rsp + 432], rax        # optional local hostname used by the session
    lea rdi, [rip + .Lxauth_env]
    call getenv
    test rax, rax
    jnz 1f
    lea rdi, [rip + .Lhome]
    call getenv
    test rax, rax
    jz .Lra_no
    mov rdi, rax
    lea rsi, [rip + .Lxauth_file]
    call path_join_tmp
1:  mov rdi, rax
    call file_read_all
    test rax, rax
    jz .Lra_no
    mov rbx, rax
    lea r15, [rax + rdx]        # end
    mov r12, rax
.Lra_entry:
    lea rax, [r12 + 2]
    cmp rax, r15
    jae .Lra_fallback
    movzx eax, word ptr [r12]   # family
    rol ax, 8
    mov [rsp + 408], rax
    add r12, 2
    # address
    movzx eax, word ptr [r12]
    rol ax, 8
    mov [rsp + 424], rax        # address length
    lea rcx, [r12 + 2]
    mov [rsp + 416], rcx        # address
    lea r12, [r12 + rax + 2]
    # number
    movzx r13d, word ptr [r12]
    rol r13w, 8
    lea r14, [r12 + 2]
    lea r12, [r14 + r13]
    # name
    movzx eax, word ptr [r12]
    rol ax, 8
    mov [rsp + 8], rax
    lea rcx, [r12 + 2]
    lea r12, [rcx + rax]
    # data
    movzx edx, word ptr [r12]
    rol dx, 8
    lea r8, [r12 + 2]
    lea r12, [r8 + rdx]
    cmp r12, r15
    ja .Lra_free
    cmp edx, 16
    jne .Lra_entry
    # Local sockets use this hostname's entry, or an entry for any family/address.
    cmp qword ptr [rsp + 408], AUTH_FAMILY_WILD
    je .Lra_match
    cmp qword ptr [rsp + 408], AUTH_FAMILY_LOCAL
    jne .Lra_entry
    push r8
    push rcx
    xor eax, eax
    mov rdx, [rsp + 16 + 16]
    test rdx, rdx
    jz .Lra_local_done
    mov rdi, [rsp + 416 + 16]
    mov rsi, [rsp + 424 + 16]
    call str_eq_cstr
.Lra_local_done:
    pop rcx
    pop r8
    test eax, eax
    jz .Lra_entry
.Lra_match:
    push r8
    push rcx
    mov rdi, rcx
    mov rsi, [rsp + 8 + 16]
    lea rdx, [rip + .Lmit]
    call str_eq_cstr
    pop rcx
    pop r8
    test eax, eax
    jz .Lra_entry
    # display number matches (empty number matches any)
    test r13, r13
    jz 2f
    push r8
    push r8
    mov rdi, r14
    mov rsi, r13
    mov rdx, [rsp + 16]
    call str_eq_cstr
    pop r8
    pop r8
    test eax, eax
    jz .Lra_entry
2:  lea rdi, [rip + tmp]
    call sb_clear
    lea rdi, [rip + tmp]
    mov rsi, r8
    mov edx, 16
    call sb_push
    mov rdi, rbx
    call mem_free
    mov eax, 1
    EPILOGUE
.Lra_fallback:
    # Retry with the session's hostname only when no normal or wildcard entry matched.
    mov rax, [rsp + 432]
    test rax, rax
    jz .Lra_free
    mov [rsp + 16], rax
    mov qword ptr [rsp + 432], 0
    mov r12, rbx
    jmp .Lra_entry
.Lra_free:
    mov rdi, rbx
    call mem_free
.Lra_no:
    xor eax, eax
    EPILOGUE

# x_connect() -> 1 on success
FN x_connect
    PROLOGUE 64
    lea rdi, [rip + .Ldisplay_env]
    call getenv
    test rax, rax
    jz .Lxc_fail
    # ":N[.S]" or "unix:N" only
    mov rbx, rax
1:  mov al, [rbx]
    test al, al
    jz .Lxc_fail
    inc rbx
    cmp al, ':'
    jne 1b
    # display number into [rsp+32]
    lea rdi, [rsp + 32]
    xor ecx, ecx
2:  mov al, [rbx + rcx]
    cmp al, '0'
    jb 3f
    cmp al, '9'
    ja 3f
    mov [rdi + rcx], al
    inc ecx
    cmp ecx, 8
    jb 2b
3:  mov byte ptr [rdi + rcx], 0
    test ecx, ecx
    jz .Lxc_fail
    # socket path
    lea rdi, [rip + addr]
    mov word ptr [rdi], AF_UNIX
    add rdi, 2
    lea rsi, [rip + .Lsock_prefix]
    call cstr_copy
    mov rdi, rax
    lea rsi, [rsp + 32]
    call cstr_copy
    mov edi, AF_UNIX
    mov esi, SOCK_STREAM | SOCK_CLOEXEC
    xor edx, edx
    SYS SYS_socket
    test rax, rax
    js .Lxc_fail
    mov [rip + xfd], eax
    mov edi, eax
    lea rsi, [rip + addr]
    mov edx, 110
    SYS SYS_connect
    test rax, rax
    js .Lxc_close
    # setup request
    lea rdi, [rsp + 32]
    call read_auth
    mov r12d, eax               # have cookie
    lea rdi, [rsp]
    xor esi, esi
    mov edx, 32
    call memset
    mov byte ptr [rsp], 'l'
    mov word ptr [rsp + 2], 11
    mov word ptr [rsp + 4], 0
    test r12d, r12d
    jz 4f
    mov word ptr [rsp + 6], 18
    mov word ptr [rsp + 8], 16
4:  lea rdi, [rsp]
    mov esi, 12
    call x_req_raw
    test r12d, r12d
    jz 5f
    lea rdi, [rip + .Lmit]
    mov esi, 20                 # 18 + 2 pad
    call x_req_raw
    mov rdi, [rip + tmp + SB_ptr]
    mov esi, 16
    call x_req_raw
5:  call x_flush
    # reply: 8-byte header, then 4*len bytes
6:  cmp dword ptr [rip + xin_len], 8
    jae 7f
    call x_read
    test rax, rax
    jle .Lxc_close
    jmp 6b
7:  cmp byte ptr [rip + xin], 1
    jne .Lxc_close
    movzx eax, word ptr [rip + xin + 6]
    lea r13d, [rax*4 + 8]
8:  cmp [rip + xin_len], r13d
    jae 9f
    call x_read
    test rax, rax
    jle .Lxc_close
    jmp 8b
9:  lea r14, [rip + xin]
    mov eax, [r14 + 12]
    mov [rip + id_base], eax
    mov eax, [r14 + 16]
    mov [rip + id_mask], eax
    movzx eax, word ptr [r14 + 26]
    mov [rip + max_req], eax
    movzx ecx, word ptr [r14 + 24]  # vendor length
    movzx edx, byte ptr [r14 + 29]  # number of formats
    add ecx, 3
    and ecx, -4
    lea r15, [r14 + 40]
    add r15, rcx
    lea r15, [r15 + rdx*8]          # first screen
    mov eax, [r15]
    mov [rip + root], eax
    movzx eax, byte ptr [r15 + 38]
    mov [rip + root_depth], eax
    # drop the setup reply
    mov ecx, [rip + xin_len]
    sub ecx, r13d
    mov [rip + xin_len], ecx
    lea rdi, [rip + xin]
    lea rsi, [rdi + r13]
    rep movsb
    mov dword ptr [rip + seq], 0
    mov eax, 1
    EPILOGUE
.Lxc_close:
    mov edi, [rip + xfd]
    SYS SYS_close
    mov dword ptr [rip + xfd], -1
.Lxc_fail:
    xor eax, eax
    EPILOGUE

# append bytes without counting a request
x_req_raw:
    push rbx
    mov rbx, rdi
    mov ecx, esi
    lea rdi, [rip + xout]
    mov eax, [rip + xout_len]
    add rdi, rax
    add [rip + xout_len], ecx
    mov rsi, rbx
    rep movsb
    pop rbx
    ret

# big requests: lift the 256 KiB request limit if the server allows
x_big_requests:
    PROLOGUE 32
    lea rdi, [rsp]
    xor esi, esi
    mov edx, 32
    call memset
    mov byte ptr [rsp], 98      # QueryExtension
    mov word ptr [rsp + 2], 5   # 8 + 12 bytes name
    mov word ptr [rsp + 4], 12
    lea rdi, [rsp + 8]
    lea rsi, [rip + .Lbigreq]
    mov ecx, 12
    rep movsb
    lea rdi, [rsp]
    mov esi, 20
    call x_req
    mov eax, [rip + seq]
    and eax, 0xffff
    mov [rip + want_seq], eax
    call x_wait_reply
    cmp byte ptr [rip + reply_buf + 8], 0
    je 9f
    movzx eax, byte ptr [rip + reply_buf + 9]
    mov byte ptr [rsp], al
    mov byte ptr [rsp + 1], 0
    mov word ptr [rsp + 2], 1
    lea rdi, [rsp]
    mov esi, 4
    call x_req
    mov eax, [rip + seq]
    and eax, 0xffff
    mov [rip + want_seq], eax
    call x_wait_reply
    mov eax, [rip + reply_buf + 8]
    mov [rip + max_req], eax
    mov dword ptr [rip + big_req], 1
9:  EPILOGUE

# XKB on: key events then carry the layout group in state bits 13-14
x_xkb_use:
    PROLOGUE 32
    lea rdi, [rsp]
    xor esi, esi
    mov edx, 32
    call memset
    mov byte ptr [rsp], 98      # QueryExtension
    mov word ptr [rsp + 2], 5   # 8 + 12 bytes name
    mov word ptr [rsp + 4], 9
    lea rdi, [rsp + 8]
    lea rsi, [rip + .Lxkb]
    mov ecx, 9
    rep movsb
    lea rdi, [rsp]
    mov esi, 20
    call x_req
    mov eax, [rip + seq]
    and eax, 0xffff
    mov [rip + want_seq], eax
    call x_wait_reply
    cmp byte ptr [rip + reply_buf + 8], 0
    je 9f
    movzx eax, byte ptr [rip + reply_buf + 10]
    mov [rip + xkb_event], eax
    movzx eax, byte ptr [rip + reply_buf + 9]
    mov byte ptr [rsp], al
    mov byte ptr [rsp + 1], 0   # UseExtension
    mov word ptr [rsp + 2], 2
    mov word ptr [rsp + 4], 1   # version 1.0
    mov word ptr [rsp + 6], 0
    lea rdi, [rsp]
    mov esi, 8
    call x_req
    mov eax, [rip + seq]
    and eax, 0xffff
    mov [rip + want_seq], eax
    call x_wait_reply
    cmp byte ptr [rip + reply_buf + 1], 0
    je 9f
    # layout changes arrive as XKB events: select NewKeyboardNotify and MapNotify
    mov byte ptr [rsp + 1], 1   # SelectEvents (byte 0 still holds the major opcode)
    mov word ptr [rsp + 2], 4
    mov word ptr [rsp + 4], 0x100   # the core keyboard
    mov word ptr [rsp + 6], 3   # affectWhich
    mov word ptr [rsp + 8], 0   # clear
    mov word ptr [rsp + 10], 3  # selectAll (MapNotify takes its parts from affectMap and map)
    mov word ptr [rsp + 12], 7  # affectMap: key types, keysyms, modifier map
    mov word ptr [rsp + 14], 7  # map
    lea rdi, [rsp]
    mov esi, 16
    call x_req
9:  EPILOGUE

# keyboard mapping (synchronous)
x_load_keymap:
    PROLOGUE 16
    # min/max keycode from the setup are not kept; use the usual 8..255
    mov dword ptr [rip + min_kc], 8
    mov dword ptr [rip + max_kc], 255
    mov byte ptr [rsp], 101     # GetKeyboardMapping
    mov byte ptr [rsp + 1], 0
    mov word ptr [rsp + 2], 2
    mov byte ptr [rsp + 4], 8
    mov byte ptr [rsp + 5], 248
    mov word ptr [rsp + 6], 0
    lea rdi, [rsp]
    mov esi, 8
    call x_req
    mov eax, [rip + seq]
    and eax, 0xffff
    mov [rip + want_seq], eax
    call x_wait_reply
    movzx eax, byte ptr [rip + reply_buf + 1]
    mov [rip + kpk], eax
    mov rdi, [rip + kmap]
    call mem_free
    mov rdi, [rip + reply_extra_len]
    call mem_alloc
    mov [rip + kmap], rax
    mov rdi, rax
    mov rsi, [rip + reply_extra]
    mov rcx, [rip + reply_extra_len]
    rep movsb
    EPILOGUE

x_load_keymap_async:
    # MappingNotify arrives inside event processing: reload on the next loop turn
    mov dword ptr [rip + keymap_stale], 1
    ret

# cursors from the standard cursor font
x_cursor_init:
    PROLOGUE 32
    call x_new_id
    mov [rip + cursor_font], eax
    mov byte ptr [rsp], 45      # OpenFont
    mov word ptr [rsp + 2], 5
    mov [rsp + 4], eax
    mov word ptr [rsp + 8], 6
    mov word ptr [rsp + 10], 0
    mov dword ptr [rsp + 12], 0x73727563    # "curs"
    mov dword ptr [rsp + 16], 0x0000726f    # "or"
    lea rdi, [rsp]
    mov esi, 20
    call x_req
    xor ebx, ebx
1:  cmp ebx, 8
    jae 9f
    call x_new_id
    lea rcx, [rip + cursors]
    mov [rcx + rbx*4], eax
    lea rcx, [rip + cursor_glyphs]
    movzx ecx, byte ptr [rcx + rbx]
    mov byte ptr [rsp], 94      # CreateGlyphCursor
    mov byte ptr [rsp + 1], 0
    mov word ptr [rsp + 2], 8
    mov [rsp + 4], eax
    mov edx, [rip + cursor_font]
    mov [rsp + 8], edx
    mov [rsp + 12], edx
    mov [rsp + 16], cx
    inc ecx
    mov [rsp + 18], cx
    mov word ptr [rsp + 20], 0      # fore rgb (black)
    mov word ptr [rsp + 22], 0
    mov word ptr [rsp + 24], 0
    mov word ptr [rsp + 26], 0xffff # back rgb (white)
    mov word ptr [rsp + 28], 0xffff
    mov word ptr [rsp + 30], 0xffff
    lea rdi, [rsp]
    mov esi, 32
    call x_req
    inc ebx
    jmp 1b
9:  EPILOGUE

# x_open_window(title)
FN x_open_window
    PROLOGUE 64
    mov r15, rdi
    call x_big_requests
    call x_xkb_use
    call x_load_keymap
    lea rdi, [rip + .La_wm_protocols]
    call x_intern
    mov [rip + a_wm_protocols], eax
    lea rdi, [rip + .La_wm_delete]
    call x_intern
    mov [rip + a_wm_delete], eax
    lea rdi, [rip + .La_net_wm_name]
    call x_intern
    mov [rip + a_net_wm_name], eax
    lea rdi, [rip + .La_net_active]
    call x_intern
    mov [rip + a_net_active], eax
    lea rdi, [rip + .La_utf8]
    call x_intern
    mov [rip + a_utf8], eax
    lea rdi, [rip + .La_clipboard]
    call x_intern
    mov [rip + a_clipboard], eax
    lea rdi, [rip + .La_targets]
    call x_intern
    mov [rip + a_targets], eax
    lea rdi, [rip + .La_sel_prop]
    call x_intern
    mov [rip + a_sel_prop], eax
    lea rdi, [rip + .La_net_wm_state]
    call x_intern
    mov [rip + a_net_wm_state], eax
    lea rdi, [rip + .La_max_h]
    call x_intern
    mov [rip + a_max_h], eax
    lea rdi, [rip + .La_max_v]
    call x_intern
    mov [rip + a_max_v], eax
    lea rdi, [rip + .La_change_state]
    call x_intern
    mov [rip + a_wm_change_state], eax
    lea rdi, [rip + .La_xs_selection]
    call x_intern
    mov [rip + a_xs_selection], eax
    lea rdi, [rip + .La_xs_settings]
    call x_intern
    mov [rip + a_xs_settings], eax
    lea rdi, [rip + .La_manager]
    call x_intern
    mov [rip + a_manager], eax
    lea rdi, [rip + .La_gtk_variant]
    call x_intern
    mov [rip + a_gtk_variant], eax
    call x_cursor_init
    # window
    call x_new_id
    mov [rip + win], eax
    mov dword ptr [rip + win_w], 1280
    mov dword ptr [rip + win_h], 820
    lea rdi, [rsp]
    xor esi, esi
    mov edx, 64
    call memset
    mov byte ptr [rsp], 1       # CreateWindow
    mov eax, [rip + root_depth]
    mov [rsp + 1], al
    mov word ptr [rsp + 2], 10
    mov eax, [rip + win]
    mov [rsp + 4], eax
    mov eax, [rip + root]
    mov [rsp + 8], eax
    mov word ptr [rsp + 16], 1280
    mov word ptr [rsp + 18], 820
    mov word ptr [rsp + 22], 1      # InputOutput
    mov dword ptr [rsp + 24], 0     # CopyFromParent visual
    mov dword ptr [rsp + 28], 0x0802    # CWBackPixel | CWEventMask
    mov dword ptr [rsp + 32], 0x001c1e24
    mov dword ptr [rsp + 36], EVMASK
    lea rdi, [rsp]
    mov esi, 40
    call x_req
    # gc
    call x_new_id
    mov [rip + gc], eax
    mov byte ptr [rsp], 55      # CreateGC
    mov byte ptr [rsp + 1], 0
    mov word ptr [rsp + 2], 4
    mov [rsp + 4], eax
    mov eax, [rip + win]
    mov [rsp + 8], eax
    mov dword ptr [rsp + 12], 0
    lea rdi, [rsp]
    mov esi, 16
    call x_req
    # WM_PROTOCOLS, WM_CLASS, title
    mov edi, [rip + win]
    mov esi, [rip + a_wm_protocols]
    mov edx, 4                  # ATOM
    mov ecx, 32
    lea r8, [rip + a_wm_delete]
    mov r9d, 1
    call x_change_prop
    mov edi, [rip + win]
    mov esi, 67                 # WM_CLASS
    mov edx, 31                 # STRING
    mov ecx, 8
    lea r8, [rip + .Lwm_class]
    mov r9d, 16
    call x_change_prop
    mov rdi, r15
    call x_title
    # the root's structure events bring MANAGER messages: an XSETTINGS manager starting later
    mov byte ptr [rsp], 2       # ChangeWindowAttributes
    mov byte ptr [rsp + 1], 0
    mov word ptr [rsp + 2], 4
    mov eax, [rip + root]
    mov [rsp + 4], eax
    mov dword ptr [rsp + 8], 0x800      # CWEventMask
    mov dword ptr [rsp + 12], 0x20000   # StructureNotify
    lea rdi, [rsp]
    mov esi, 16
    call x_req
    call xs_refresh
    # map
    mov byte ptr [rsp], 8       # MapWindow
    mov word ptr [rsp + 2], 2
    mov eax, [rip + win]
    mov [rsp + 4], eax
    lea rdi, [rsp]
    mov esi, 8
    call x_req
    call x_activate
    call x_flush
    mov dword ptr [rip + g_csd], 0
    call x_resize_fb
    # vtable
    lea rax, [rip + x_flush]
    mov [rip + g_plat + P_flush], rax
    lea rax, [rip + x_timeout]
    mov [rip + g_plat + P_timeout], rax
    lea rax, [rip + x_tick]
    mov [rip + g_plat + P_tick], rax
    lea rax, [rip + x_draw]
    mov [rip + g_plat + P_draw], rax
    lea rax, [rip + x_set_cursor]
    mov [rip + g_plat + P_cursor], rax
    lea rax, [rip + x_clip_set]
    mov [rip + g_plat + P_clip_set], rax
    lea rax, [rip + x_clip_get]
    mov [rip + g_plat + P_clip_get], rax
    lea rax, [rip + x_nop]
    mov [rip + g_plat + P_move], rax
    mov [rip + g_plat + P_resize], rax
    mov [rip + g_plat + P_menu], rax
    lea rax, [rip + x_minimize]
    mov [rip + g_plat + P_minimize], rax
    lea rax, [rip + x_maximize]
    mov [rip + g_plat + P_maximize], rax
    lea rax, [rip + x_title]
    mov [rip + g_plat + P_title], rax
    mov edi, [rip + xfd]
    mov esi, POLLIN
    lea rdx, [rip + x_on_readable]
    xor ecx, ecx
    call watch_add
    EPILOGUE

x_nop:
    ret

# x_timeout(): at once when the last frame asked for another, otherwise forever
x_timeout:
    xor eax, eax
    cmp dword ptr [rip + g_dirty], 0
    jne 1f
    mov eax, -1
1:  ret

x_tick:
    push rbx
1:  cmp dword ptr [rip + xs_stale], 0
    je 2f
    call xs_refresh
    # the messages that came after its reply in the same read (nothing else reads them before the
    # next one), which may change XSETTINGS again
    call x_process
    jmp 1b
2:  pop rbx
    cmp dword ptr [rip + keymap_stale], 0
    jne x_keymap_refresh
    ret

# x_variant(): _GTK_THEME_VARIANT "dark" or "light" like the theme, for title bars window managers
# draw (Mutter's on X11)
x_variant:
    mov eax, [rip + g_theme_dark]
    cmp eax, [rip + variant_dark]
    je 9f
    mov [rip + variant_dark], eax
    push rbx
    lea r8, [rip + .Lvariant_light]
    mov r9d, 5
    test eax, eax
    jz 1f
    lea r8, [rip + .Lvariant_dark]
    mov r9d, 4
1:  mov edi, [rip + win]
    mov esi, [rip + a_gtk_variant]
    mov edx, [rip + a_utf8]
    mov ecx, 8
    call x_change_prop
    pop rbx
9:  ret

# xs_refresh(): the XSETTINGS manager's theme name for the system's dark mode (linux_xsettings).
# Synchronous requests, so never while messages are being handled (x_tick and x_open_window).
xs_refresh:
    PROLOGUE 32
    mov dword ptr [rip + xs_stale], 0
    mov byte ptr [rsp], 23      # GetSelectionOwner
    mov byte ptr [rsp + 1], 0
    mov word ptr [rsp + 2], 2
    mov eax, [rip + a_xs_selection]
    mov [rsp + 4], eax
    lea rdi, [rsp]
    mov esi, 8
    call x_req
    mov eax, [rip + seq]
    and eax, 0xffff
    mov [rip + want_seq], eax
    call x_wait_reply
    cmp byte ptr [rip + reply_buf], 1
    jne 8f
    mov r12d, [rip + reply_buf + 8]
    test r12d, r12d
    jz 8f
    cmp r12d, [rip + xs_owner]
    je 1f
    mov [rip + xs_owner], r12d
    # its property changes, and its window going away
    mov byte ptr [rsp], 2       # ChangeWindowAttributes
    mov byte ptr [rsp + 1], 0
    mov word ptr [rsp + 2], 4
    mov [rsp + 4], r12d
    mov dword ptr [rsp + 8], 0x800      # CWEventMask
    mov dword ptr [rsp + 12], 0x420000  # PropertyChange | StructureNotify
    lea rdi, [rsp]
    mov esi, 16
    call x_req
1:  mov byte ptr [rsp], 20      # GetProperty
    mov byte ptr [rsp + 1], 0
    mov word ptr [rsp + 2], 6
    mov [rsp + 4], r12d
    mov eax, [rip + a_xs_settings]
    mov [rsp + 8], eax
    mov dword ptr [rsp + 12], 0         # AnyPropertyType
    mov dword ptr [rsp + 16], 0
    mov dword ptr [rsp + 20], 16384     # up to 64 KiB
    lea rdi, [rsp]
    mov esi, 24
    call x_req
    mov eax, [rip + seq]
    and eax, 0xffff
    mov [rip + want_seq], eax
    call x_wait_reply
    cmp byte ptr [rip + reply_buf], 1
    jne 8f                      # an error: the window is gone
    mov edi, -1
    cmp byte ptr [rip + reply_buf + 1], 8
    jne 7f
    mov rdi, [rip + reply_extra]
    mov esi, [rip + reply_buf + 16]
    cmp rsi, [rip + reply_extra_len]
    jbe 2f
    mov rsi, [rip + reply_extra_len]
2:  call xs_theme_dark
    mov edi, eax
7:  call linux_xsettings
    EPILOGUE
8:  mov dword ptr [rip + xs_owner], 0
    mov edi, -1
    call linux_xsettings
    EPILOGUE

# xs_theme_dark(data, len) -> eax: XSETTINGS' Net/ThemeName names a dark theme (1), another (0), or
# is not there (-1). Settings: type, pad, name length (16 bits), the name padded to 4, a serial;
# then an integer (4 bytes), a string (length, bytes padded to 4) or a color (8 bytes).
xs_theme_dark:
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    mov eax, -1
    cmp r12, 12
    jb 9f
    cmp byte ptr [rbx], 0       # LSBFirst: what managers on this machine write
    jne 9f
    mov r13d, [rbx + 8]         # how many
    mov r14d, 12
1:  mov eax, -1
    test r13d, r13d
    jz 9f
    dec r13d
    lea rax, [r14 + 4]
    cmp rax, r12
    ja 8f
    movzx r15d, byte ptr [rbx + r14]
    movzx ecx, word ptr [rbx + r14 + 2]
    lea rdx, [r14 + 4]          # the name
    lea rax, [rcx + 3]
    and rax, -4
    lea r8, [rdx + rax + 4]     # the value
    cmp r8, r12
    ja 8f
    cmp r15d, 1
    jne 3f
    # a string: its length, then the bytes
    lea rax, [r8 + 4]
    cmp rax, r12
    ja 8f
    mov r9d, [rbx + r8]
    lea r10, [r8 + 4]
    lea rax, [r10 + r9]
    cmp rax, r12
    ja 8f
    lea rax, [r9 + 3]
    and rax, -4
    lea r14, [r10 + rax]
    cmp ecx, 13
    jne 1b
    lea rdi, [rbx + rdx]
    mov rsi, rcx
    lea rdx, [rip + .Lnet_theme]
    push r9
    push r10
    call str_eq_cstr
    pop r10
    pop r9
    test eax, eax
    jz 1b
    lea rdi, [rbx + r10]
    mov rsi, r9
    call linux_name_dark
    jmp 9f
3:  # an integer or a color
    lea r14, [r8 + 4]
    cmp r15d, 2
    jne 1b
    lea r14, [r8 + 8]
    jmp 1b
8:  mov eax, -1
9:  EPILOGUE

FN x_title
    push rbx
    push r12
    sub rsp, 8
    mov rbx, rdi
    call strlen
    mov r12d, eax
    mov edi, [rip + win]
    mov esi, [rip + a_net_wm_name]
    mov edx, [rip + a_utf8]
    mov ecx, 8
    mov r8, rbx
    mov r9d, r12d
    call x_change_prop
    mov edi, [rip + win]
    mov esi, 39                 # WM_NAME
    mov edx, 31                 # STRING
    mov ecx, 8
    mov r8, rbx
    mov r9d, r12d
    call x_change_prop
    add rsp, 8
    pop r12
    pop rbx
    ret

x_resize_fb:
    push rbx
    mov eax, [rip + win_w]
    cmp eax, [rip + fb_w]
    jne 1f
    mov eax, [rip + win_h]
    cmp eax, [rip + fb_h]
    je 2f
1:  mov rdi, [rip + fbuf]
    call mem_free
    mov eax, [rip + win_w]
    mov [rip + fb_w], eax
    mov ecx, [rip + win_h]
    mov [rip + fb_h], ecx
    imul eax, ecx
    lea rdi, [rax*4]
    call mem_alloc
    mov [rip + fbuf], rax
    mov edi, [rip + fb_w]
    mov esi, [rip + fb_h]
    call app_on_resize
2:  mov dword ptr [rip + g_dirty], 1
    pop rbx
    ret

# x_draw(): render and PutImage (one request with BIG-REQUESTS, strips otherwise)
x_draw:
    PROLOGUE 48
    mov rdi, [rip + fbuf]
    mov esi, [rip + fb_w]
    mov edx, [rip + fb_h]
    mov ecx, esi
    call gfx_set_target
    mov dword ptr [rip + g_dirty], 0
    call app_render
    call x_variant
    call x_flush
    # rows per request
    mov eax, [rip + max_req]
    shl rax, 2
    sub rax, 32
    xor edx, edx
    mov ecx, [rip + fb_w]
    shl ecx, 2
    div rcx
    mov r12d, eax
    test r12d, r12d
    jz .Lxd_ret
    xor ebx, ebx                # row
.Lxd_strip:
    cmp ebx, [rip + fb_h]
    jae .Lxd_ret
    mov r13d, [rip + fb_h]
    sub r13d, ebx
    cmp r13d, r12d
    cmova r13d, r12d            # rows in this request
    mov eax, [rip + fb_w]
    imul eax, r13d
    shl eax, 2
    mov r14d, eax               # pixel bytes
    # header (28 bytes with the big-request length word, else 24)
    lea rdi, [rsp]
    mov byte ptr [rdi], 72      # PutImage
    mov byte ptr [rdi + 1], 2   # ZPixmap
    cmp dword ptr [rip + big_req], 0
    je 1f
    mov word ptr [rdi + 2], 0
    lea eax, [r14 + 28]
    shr eax, 2
    mov [rdi + 4], eax
    add rdi, 4
    mov r15d, 28
    jmp 2f
1:  lea eax, [r14 + 24]
    shr eax, 2
    mov [rdi + 2], ax
    mov r15d, 24
2:  mov eax, [rip + win]
    mov [rdi + 4], eax
    mov eax, [rip + gc]
    mov [rdi + 8], eax
    mov eax, [rip + fb_w]
    mov [rdi + 12], ax
    mov [rdi + 14], r13w
    mov word ptr [rdi + 16], 0
    mov [rdi + 18], bx
    mov byte ptr [rdi + 20], 0
    mov eax, [rip + root_depth]
    mov [rdi + 21], al
    mov word ptr [rdi + 22], 0
    # writev(header, pixels)
    lea rax, [rsp]
    mov [rip + iov2], rax
    mov [rip + iov2 + 8], r15
    mov eax, ebx
    imul eax, [rip + fb_w]
    shl rax, 2
    add rax, [rip + fbuf]
    mov [rip + iov2 + 16], rax
    mov [rip + iov2 + 24], r14
    call x_writev2
    inc dword ptr [rip + seq]
    add ebx, r13d
    jmp .Lxd_strip
.Lxd_ret:
    EPILOGUE

# write both iovecs completely
x_writev2:
    push rbx
1:  mov edi, [rip + xfd]
    lea rsi, [rip + iov2]
    mov edx, 2
    mov eax, 20                 # writev
    XSYS
    cmp rax, -EINTR
    je 1b
    cmp rax, -EAGAIN
    je 1b
    test rax, rax
    js 9f
    # advance
    mov rcx, [rip + iov2 + 8]
    cmp rax, rcx
    jb 2f
    sub rax, rcx
    mov qword ptr [rip + iov2 + 8], 0
    add [rip + iov2 + 16], rax
    sub [rip + iov2 + 24], rax
    cmp qword ptr [rip + iov2 + 24], 0
    jne 1b
    jmp 9f
2:  add [rip + iov2], rax
    sub [rip + iov2 + 8], rax
    jmp 1b
9:  pop rbx
    ret

x_set_cursor:
    cmp edi, [rip + cur_shape]
    je 1f
    mov [rip + cur_shape], edi
    cmp edi, 8
    jae 1f
    lea rax, [rip + cursors]
    mov eax, [rax + rdi*4]
    sub rsp, 24
    mov byte ptr [rsp], 2       # ChangeWindowAttributes
    mov word ptr [rsp + 2], 4
    mov ecx, [rip + win]
    mov [rsp + 4], ecx
    mov dword ptr [rsp + 8], 0x4000     # CWCursor
    mov [rsp + 12], eax
    mov rdi, rsp
    mov esi, 16
    call x_req
    add rsp, 24
1:  ret

# clipboard: become the CLIPBOARD owner
x_clip_set:
    push rbx
    push r12
    sub rsp, 24
    mov rbx, rdi
    mov r12, rsi
    lea rdi, [rip + xclip]
    call sb_clear
    lea rdi, [rip + xclip]
    mov rsi, rbx
    mov rdx, r12
    call sb_push
    mov byte ptr [rsp], 22      # SetSelectionOwner
    mov word ptr [rsp + 2], 4
    mov eax, [rip + win]
    mov [rsp + 4], eax
    mov eax, [rip + a_clipboard]
    mov [rsp + 8], eax
    mov dword ptr [rsp + 12], 0
    mov rdi, rsp
    mov esi, 16
    call x_req
    mov dword ptr [rip + own_clip], 1
    add rsp, 24
    pop r12
    pop rbx
    ret

# paste: ask the owner to convert CLIPBOARD to UTF8_STRING into our property
x_clip_get:
    cmp dword ptr [rip + own_clip], 0
    je 1f
    mov rdi, [rip + xclip + SB_ptr]
    mov rsi, [rip + xclip + SB_len]
    jmp app_on_paste
1:  sub rsp, 40
    mov byte ptr [rsp], 24      # ConvertSelection
    mov word ptr [rsp + 2], 6
    mov eax, [rip + win]
    mov [rsp + 4], eax
    mov eax, [rip + a_clipboard]
    mov [rsp + 8], eax
    mov eax, [rip + a_utf8]
    mov [rsp + 12], eax
    mov eax, [rip + a_sel_prop]
    mov [rsp + 16], eax
    mov dword ptr [rsp + 20], 0
    mov rdi, rsp
    mov esi, 24
    call x_req
    add rsp, 40
    ret

# SelectionNotify arrived: GetProperty (delete) and deliver the reply asynchronously
x_get_paste:
    sub rsp, 40
    mov byte ptr [rsp], 20      # GetProperty
    mov byte ptr [rsp + 1], 1   # delete
    mov word ptr [rsp + 2], 6
    mov eax, [rip + win]
    mov [rsp + 4], eax
    mov eax, [rip + a_sel_prop]
    mov [rsp + 8], eax
    mov dword ptr [rsp + 12], 0         # AnyPropertyType
    mov dword ptr [rsp + 16], 0
    mov dword ptr [rsp + 20], 0x1000000 # up to 64 MiB
    mov rdi, rsp
    mov esi, 24
    call x_req
    mov eax, [rip + seq]
    and eax, 0xffff
    mov [rip + paste_seq], eax
    mov dword ptr [rip + paste_wait], 1
    add rsp, 40
    ret

# x_serve_selection(event): answer another client's paste request
x_serve_selection:
    PROLOGUE 48
    mov rbx, rdi
    mov r12d, [rbx + 12]        # requestor
    mov r13d, [rbx + 16]        # selection
    mov r14d, [rbx + 20]        # target
    mov r15d, [rbx + 24]        # property
    test r15d, r15d
    jnz 1f
    mov r15d, r14d
1:  cmp r14d, [rip + a_targets]
    jne 2f
    mov eax, [rip + a_targets]
    mov [rsp + 32], eax
    mov eax, [rip + a_utf8]
    mov [rsp + 36], eax
    mov dword ptr [rsp + 40], 31        # STRING
    mov edi, r12d
    mov esi, r15d
    mov edx, 4
    mov ecx, 32
    lea r8, [rsp + 32]
    mov r9d, 3
    call x_change_prop
    jmp 4f
2:  cmp r14d, [rip + a_utf8]
    je 3f
    cmp r14d, 31
    je 3f
    xor r15d, r15d              # refuse
    jmp 4f
3:  mov edi, r12d
    mov esi, r15d
    mov edx, r14d
    mov ecx, 8
    mov r8, [rip + xclip + SB_ptr]
    mov r9, [rip + xclip + SB_len]
    call x_change_prop
4:  # SendEvent SelectionNotify
    lea rdi, [rsp]
    xor esi, esi
    mov edx, 44
    call memset
    mov byte ptr [rsp], 25      # SendEvent
    mov byte ptr [rsp + 1], 0
    mov word ptr [rsp + 2], 11
    mov [rsp + 4], r12d
    mov dword ptr [rsp + 8], 0
    mov byte ptr [rsp + 12], 31 # SelectionNotify
    mov eax, [rbx + 4]
    mov [rsp + 16], eax         # time
    mov [rsp + 20], r12d
    mov [rsp + 24], r13d
    mov [rsp + 28], r14d
    mov [rsp + 32], r15d
    lea rdi, [rsp]
    mov esi, 44
    call x_req
    EPILOGUE

# _NET_WM_STATE toggle (maximize) via a client message to the root window
x_activate:
    PROLOGUE 48
    mov rdi, rsp
    xor esi, esi
    mov edx, 44
    call memset
    mov byte ptr [rsp], 25      # SendEvent
    mov word ptr [rsp + 2], 11
    mov eax, [rip + root]
    mov [rsp + 4], eax
    mov dword ptr [rsp + 8], 0x180000
    mov byte ptr [rsp + 12], 33 # ClientMessage
    mov byte ptr [rsp + 13], 32
    mov eax, [rip + win]
    mov [rsp + 16], eax
    mov eax, [rip + a_net_active]
    mov [rsp + 20], eax
    mov dword ptr [rsp + 24], 1 # normal application, CurrentTime
    mov rdi, rsp
    mov esi, 44
    call x_req
    EPILOGUE

x_maximize:
    sub rsp, 56
    mov byte ptr [rsp], 25      # SendEvent
    mov byte ptr [rsp + 1], 0
    mov word ptr [rsp + 2], 11
    mov eax, [rip + root]
    mov [rsp + 4], eax
    mov dword ptr [rsp + 8], 0x180000   # SubstructureNotify | SubstructureRedirect
    mov byte ptr [rsp + 12], 33 # ClientMessage
    mov byte ptr [rsp + 13], 32
    mov word ptr [rsp + 14], 0
    mov eax, [rip + win]
    mov [rsp + 16], eax
    mov eax, [rip + a_net_wm_state]
    mov [rsp + 20], eax
    mov dword ptr [rsp + 24], 2         # toggle
    mov eax, [rip + a_max_h]
    mov [rsp + 28], eax
    mov eax, [rip + a_max_v]
    mov [rsp + 32], eax
    mov dword ptr [rsp + 36], 1
    mov dword ptr [rsp + 40], 0
    mov rdi, rsp
    mov esi, 44
    call x_req
    add rsp, 56
    ret

x_minimize:
    sub rsp, 56
    mov byte ptr [rsp], 25
    mov byte ptr [rsp + 1], 0
    mov word ptr [rsp + 2], 11
    mov eax, [rip + root]
    mov [rsp + 4], eax
    mov dword ptr [rsp + 8], 0x180000
    mov byte ptr [rsp + 12], 33
    mov byte ptr [rsp + 13], 32
    mov word ptr [rsp + 14], 0
    mov eax, [rip + win]
    mov [rsp + 16], eax
    mov eax, [rip + a_wm_change_state]
    mov [rsp + 20], eax
    mov dword ptr [rsp + 24], 3         # IconicState
    mov dword ptr [rsp + 28], 0
    mov dword ptr [rsp + 32], 0
    mov dword ptr [rsp + 36], 0
    mov dword ptr [rsp + 40], 0
    mov rdi, rsp
    mov esi, 44
    call x_req
    add rsp, 56
    ret

.section .rodata
.Ldisplay_env: .asciz "DISPLAY"
.Lxauth_env: .asciz "XAUTHORITY"
.Lxauth_hostname: .asciz "XAUTHLOCALHOSTNAME"
.Lhome: .asciz "HOME"
.Lxauth_file: .asciz ".Xauthority"
.Lsock_prefix: .asciz "/tmp/.X11-unix/X"
.Lmit: .ascii "MIT-MAGIC-COOKIE-1\0\0"
.Lbigreq: .ascii "BIG-REQUESTS"
.Lxkb: .ascii "XKEYBOARD\0\0\0"
.Lclosed: .asciz "raftaar: X11 connection closed"
.La_wm_protocols: .asciz "WM_PROTOCOLS"
.La_wm_delete: .asciz "WM_DELETE_WINDOW"
.La_net_wm_name: .asciz "_NET_WM_NAME"
.La_utf8: .asciz "UTF8_STRING"
.La_clipboard: .asciz "CLIPBOARD"
.La_targets: .asciz "TARGETS"
.La_sel_prop: .asciz "RAFTAAR_SELECTION"
.La_net_wm_state: .asciz "_NET_WM_STATE"
.La_net_active: .asciz "_NET_ACTIVE_WINDOW"
.La_max_h: .asciz "_NET_WM_STATE_MAXIMIZED_HORZ"
.La_max_v: .asciz "_NET_WM_STATE_MAXIMIZED_VERT"
.La_change_state: .asciz "WM_CHANGE_STATE"
.La_xs_selection: .asciz "_XSETTINGS_S0"
.La_xs_settings: .asciz "_XSETTINGS_SETTINGS"
.La_manager: .asciz "MANAGER"
.La_gtk_variant: .asciz "_GTK_THEME_VARIANT"
.Lnet_theme: .asciz "Net/ThemeName"
.Lvariant_dark: .ascii "dark"
.Lvariant_light: .ascii "light"
.Lwm_class: .ascii "raftaar\0raftaar\0"
# CUR_* -> X cursor font glyphs: left_ptr xterm hand2 sb_h_double_arrow sb_v_double_arrow bottom_right_corner bottom_left_corner
cursor_glyphs: .byte 68, 152, 60, 108, 116, 14, 12, 68

.bss
paste_wait: .long 0
paste_seq: .long 0              # the sequence number of the paste's GetProperty, while paste_wait
keymap_stale: .long 0
keymap_busy: .long 0            # loading it, or replaying keys that waited for it
pend_n: .long 0
.p2align 3
pend: .zero PEND_MAX * 8        # keycode, state
xkb_event: .long 0              # first event code of XKEYBOARD, 0 without it

.data
xfd: .long -1
cur_shape: .long -1
want_seq: .long -1
