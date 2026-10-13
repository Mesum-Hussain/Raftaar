# native wayland client: wire protocol over a unix socket, no libwayland
.include "raftaar.inc"

.equ OUTSZ, 65536
.equ INSZ, 65536
.equ MAXFDQ, 16

# wl_shm format
.equ WL_SHM_XRGB8888, 1
.equ WL_SHM_ARGB8888, 0

.bss
.p2align 4
out_buf: .zero OUTSZ
in_buf: .zero INSZ
out_len: .long 0
in_len: .long 0
msg_start: .long 0
wl_fd: .long 0
next_id: .long 0
free_ids: .zero 4 * 256
free_n: .long 0
fdq: .zero 4 * MAXFDQ
fdq_n: .long 0
.p2align 3
cmsg_buf: .zero 256
msghdr: .zero 56
iov: .zero 16
sockaddr: .zero 110

# globals (object ids / names)
id_registry: .long 0
id_compositor: .long 0
id_shm: .long 0
id_wm_base: .long 0
id_seat: .long 0
id_ddm: .long 0
id_deco_mgr: .long 0
id_cursor_mgr: .long 0
id_viewporter: .long 0
id_fscale_mgr: .long 0
id_activation: .long 0
activation_sent: .long 0
id_sync: .long 0
sync_done: .long 0
seat_ver: .long 0
ddm_ver: .long 0

id_surface: .long 0
id_xdg_surface: .long 0
id_toplevel: .long 0
id_deco: .long 0
id_viewport: .long 0
id_fscale: .long 0
id_pointer: .long 0
id_keyboard: .long 0
id_cursor_dev: .long 0
id_ddev: .long 0
id_frame_cb: .long 0
id_pool: .long 0
id_buf: .zero 8
buf_busy: .zero 8
.p2align 3
pool_mem: .quad 0
pool_size: .quad 0
buf_w: .long 0
buf_h: .long 0

configured: .long 0
pend_w: .long 0
pend_h: .long 0
pend_states: .long 0
win_w: .long 0             # logical
win_h: .long 0
scale120: .long 0          # fractional scale * 120, 0 if unused
.globl g_win_states
g_win_states: .long 0      # bit0 maximized, bit1 fullscreen, bit2 activated, bit3 tiled

last_serial: .long 0
enter_serial: .long 0
cur_shape: .long 0
ptr_x: .long 0             # fixed 24.8 logical
ptr_y: .long 0
axis_src: .long 0
.p2align 3
axis_rem: .quad 0, 0       # what is left of a pixel, vertical and horizontal

kb_group: .long 0
kb_mods: .long 0
rep_key: .long 0
.p2align 3
rep_next: .quad 0

# clipboard
offer_new: .long 0
offer_new_text: .long 0
sel_offer: .long 0
sel_offer_text: .long 0
# files dragged in: the offer over the window, and the one dropped, read as text/uri-list
offer_new_uri: .long 0
dnd_offer: .long 0
drop_offer: .long 0
drop_pipe: .zero 8
id_source: .long 0
.p2align 3
clip_sb: .zero SB_SIZE
paste_sb: .zero SB_SIZE
drop_sb: .zero SB_SIZE

.text

# ---------------- message building ----------------

wl_new_id:
    mov ecx, [rip + free_n]
    test ecx, ecx
    jz 1f
    dec ecx
    mov [rip + free_n], ecx
    lea rax, [rip + free_ids]
    mov eax, [rax + rcx*4]
    ret
1:  mov eax, [rip + next_id]
    inc dword ptr [rip + next_id]
    ret

# wl_begin(obj, opcode)
wl_begin:
    mov eax, [rip + out_len]
    cmp eax, OUTSZ - 4096
    jb 1f
    push rdi
    push rsi
    call wl_flush
    pop rsi
    pop rdi
    mov eax, [rip + out_len]
1:  mov [rip + msg_start], eax
    lea rcx, [rip + out_buf]
    mov [rcx + rax], edi
    mov [rcx + rax + 4], esi
    add eax, 8
    mov [rip + out_len], eax
    ret

# wl_put(u32)
wl_put:
    mov eax, [rip + out_len]
    lea rcx, [rip + out_buf]
    mov [rcx + rax], edi
    add eax, 4
    mov [rip + out_len], eax
    ret

# wl_put_str(cstr)
wl_put_str:
    push rbx
    mov rbx, rdi
    call strlen
    lea edi, [rax + 1]
    push rdi
    call wl_put
    pop rdx
    mov eax, [rip + out_len]
    lea rdi, [rip + out_buf]
    add rdi, rax
    mov rsi, rbx
    mov ecx, edx
    rep movsb
    mov ecx, edx
    neg ecx
    and ecx, 3
    xor eax, eax
    rep stosb
    add edx, 3
    and edx, -4
    add [rip + out_len], edx
    pop rbx
    ret

# wl_end(): patch size into header
wl_end:
    mov eax, [rip + msg_start]
    mov ecx, [rip + out_len]
    sub ecx, eax
    shl ecx, 16
    lea rdx, [rip + out_buf]
    or [rdx + rax + 4], ecx
    ret

.macro MSG obj, op
    mov edi, \obj
    mov esi, \op
    call wl_begin
.endm
.macro ARG v
    mov edi, \v
    call wl_put
.endm
.macro SARG label
    lea rdi, [rip + \label]
    call wl_put_str
.endm
.macro END
    call wl_end
.endm

# wl_flush_fd(fd or -1): send pending bytes, optionally with one fd
wl_flush_fd:
    push rbx
    mov ebx, edi
    lea rax, [rip + out_buf]
    mov [rip + iov], rax
    mov eax, [rip + out_len]
    mov [rip + iov + 8], rax
    lea rdi, [rip + msghdr]
    xor eax, eax
    mov ecx, 56
    rep stosb
    lea rax, [rip + iov]
    mov [rip + msghdr + 16], rax
    mov qword ptr [rip + msghdr + 24], 1
    cmp ebx, -1
    je 1f
    lea rax, [rip + cmsg_buf]
    mov qword ptr [rax], 20       # cmsg_len
    mov dword ptr [rax + 8], SOL_SOCKET
    mov dword ptr [rax + 12], SCM_RIGHTS
    mov [rax + 16], ebx
    mov [rip + msghdr + 32], rax
    mov qword ptr [rip + msghdr + 40], 24
1:  cmp dword ptr [rip + out_len], 0
    je 3f
2:  mov edi, [rip + wl_fd]
    lea rsi, [rip + msghdr]
    mov edx, MSG_NOSIGNAL
    SYS SYS_sendmsg
    cmp rax, -EINTR
    je 2b
    cmp rax, -EAGAIN
    je 2b
    test rax, rax
    js 4f
    # partial sends: drop sent bytes, continue without fd
    mov ecx, [rip + out_len]
    sub ecx, eax
    mov [rip + out_len], ecx
    jz 3f
    lea rdi, [rip + out_buf]
    lea rsi, [rdi + rax]
    rep movsb
    mov qword ptr [rip + msghdr + 32], 0
    mov qword ptr [rip + msghdr + 40], 0
    mov eax, [rip + out_len]
    mov [rip + iov + 8], rax
    jmp 2b
3:  pop rbx
    ret
4:  lea rdi, [rip + .Lsend_err]
    call die

FN wl_flush
    mov edi, -1
    jmp wl_flush_fd

# ---------------- receiving ----------------

# wl_read(): recvmsg into in_buf, collect fds. returns bytes read (<=0 on error/eof)
wl_read:
    push rbx
    lea rax, [rip + in_buf]
    mov ecx, [rip + in_len]
    add rax, rcx
    mov [rip + iov], rax
    mov eax, INSZ
    sub eax, ecx
    mov [rip + iov + 8], rax
    lea rdi, [rip + msghdr]
    xor eax, eax
    mov ecx, 56
    rep stosb
    lea rax, [rip + iov]
    mov [rip + msghdr + 16], rax
    mov qword ptr [rip + msghdr + 24], 1
    lea rax, [rip + cmsg_buf]
    mov [rip + msghdr + 32], rax
    mov qword ptr [rip + msghdr + 40], 256
    mov edi, [rip + wl_fd]
    lea rsi, [rip + msghdr]
    mov edx, MSG_DONTWAIT | 0x40000000   # MSG_CMSG_CLOEXEC
    SYS SYS_recvmsg
    mov rbx, rax
    test rax, rax
    jle 9f
    add [rip + in_len], eax
    # walk control messages
    mov rcx, [rip + msghdr + 40]   # controllen
    lea rsi, [rip + cmsg_buf]
1:  cmp rcx, 16
    jb 9f
    mov rdx, [rsi]                 # cmsg_len
    cmp rdx, 16
    jb 9f
    cmp dword ptr [rsi + 12], SCM_RIGHTS
    jne 3f
    lea r8, [rsi + 16]
    lea r9, [rsi + rdx]
2:  cmp r8, r9
    jae 3f
    mov eax, [rip + fdq_n]
    cmp eax, MAXFDQ
    jae 21f
    mov r10d, [r8]
    lea r11, [rip + fdq]
    mov [r11 + rax*4], r10d
    inc dword ptr [rip + fdq_n]
21: add r8, 4
    jmp 2b
3:  add rdx, 7
    and rdx, -8
    add rsi, rdx
    sub rcx, rdx
    ja 1b
9:  mov rax, rbx
    pop rbx
    ret

# fdq_pop() -> fd or -1
fdq_pop:
    mov ecx, [rip + fdq_n]
    test ecx, ecx
    jz 2f
    lea rsi, [rip + fdq]
    mov eax, [rsi]
    dec ecx
    mov [rip + fdq_n], ecx
    lea rdi, [rip + fdq]
    lea rsi, [rdi + 4]
    shl ecx, 2
    rep movsb
    ret
2:  mov eax, -1
    ret

# wl_on_readable(fd, revents, ctx)
wl_on_readable:
    push rbx
    push r12
    push r13
    test esi, POLLIN
    jz 8f
    call wl_read
    test rax, rax
    jz 7f
    js 9f
    # dispatch whole messages
    xor ebx, ebx                   # offset
1:  mov eax, [rip + in_len]
    sub eax, ebx
    cmp eax, 8
    jb 5f
    lea r12, [rip + in_buf]
    add r12, rbx
    mov edx, [r12 + 4]
    shr edx, 16                    # size
    cmp edx, 8
    jb 7f
    cmp eax, edx
    jb 5f
    mov r13d, edx
    mov edi, [r12]                 # object
    movzx esi, word ptr [r12 + 4]  # opcode
    lea rdx, [r12 + 8]             # args
    call wl_dispatch
    add ebx, r13d
    jmp 1b
5:  # keep the partial tail
    mov ecx, [rip + in_len]
    sub ecx, ebx
    mov [rip + in_len], ecx
    lea rdi, [rip + in_buf]
    lea rsi, [rdi + rbx]
    rep movsb
9:  pop r13
    pop r12
    pop rbx
    ret
8:  test esi, POLLHUP | POLLERR
    jz 9b
7:  lea rdi, [rip + .Ldisconnected]
    call die

# wl_roundtrip(): sync and dispatch until done
wl_roundtrip:
    push rbx
    call wl_new_id
    mov [rip + id_sync], eax
    mov dword ptr [rip + sync_done], 0
    MSG 1, 0
    ARG [rip + id_sync]
    END
    call wl_flush
1:  cmp dword ptr [rip + sync_done], 0
    jne 2f
    # blocking poll on the socket
    sub rsp, 16
    mov eax, [rip + wl_fd]
    mov [rsp], eax
    mov dword ptr [rsp + 4], POLLIN
    mov rdi, rsp
    mov esi, 1
    mov edx, -1
    SYS SYS_poll
    movzx esi, word ptr [rsp + 6]
    add rsp, 16
    mov edi, [rip + wl_fd]
    call wl_on_readable
    jmp 1b
2:  pop rbx
    ret

# ---------------- dispatch ----------------

# wl_dispatch(obj, opcode, args)
wl_dispatch:
    push rbx
    push r12
    push r13
    mov ebx, edi
    mov r12d, esi
    mov r13, rdx
    cmp ebx, 1
    je .Ld_display
    cmp ebx, [rip + id_registry]
    je .Ld_registry
    cmp ebx, [rip + id_sync]
    je .Ld_sync
    cmp ebx, [rip + id_wm_base]
    je .Ld_wm_base
    cmp ebx, [rip + id_xdg_surface]
    je .Ld_xdg_surface
    cmp ebx, [rip + id_toplevel]
    je .Ld_toplevel
    cmp ebx, [rip + id_frame_cb]
    je .Ld_frame
    cmp ebx, [rip + id_buf]
    je .Ld_buf0
    cmp ebx, [rip + id_buf + 4]
    je .Ld_buf1
    cmp ebx, [rip + id_pointer]
    je .Ld_pointer
    cmp ebx, [rip + id_keyboard]
    je .Ld_keyboard
    cmp ebx, [rip + id_seat]
    je .Ld_seat
    cmp ebx, [rip + id_fscale]
    je .Ld_fscale
    cmp ebx, [rip + id_surface]
    je .Ld_surface
    cmp ebx, [rip + id_ddev]
    je .Ld_ddev
    cmp ebx, [rip + id_source]
    je .Ld_source
    cmp ebx, [rip + offer_new]
    je .Ld_offer
    cmp ebx, [rip + id_deco]
    je .Ld_deco
    jmp .Ld_ret

.Ld_display:
    test r12d, r12d
    jnz 1f
    lea rdi, [rip + .Lproto_err]
    call log_cstr
    lea rdi, [r13 + 12]
    call log_cstr
    call log_nl
    mov edi, 1
    call sys_exit
1:  # delete_id
    mov eax, [r13]
    mov ecx, [rip + free_n]
    cmp ecx, 256
    jae .Ld_ret
    lea rdx, [rip + free_ids]
    mov [rdx + rcx*4], eax
    inc dword ptr [rip + free_n]
    cmp eax, [rip + id_frame_cb]
    jne .Ld_ret
    mov dword ptr [rip + id_frame_cb], 0
    jmp .Ld_ret

.Ld_sync:
    mov dword ptr [rip + sync_done], 1
    mov dword ptr [rip + id_sync], 0
    jmp .Ld_ret

.Ld_registry:
    test r12d, r12d
    jnz .Ld_ret
    mov rdi, r13
    call wl_on_global
    jmp .Ld_ret

.Ld_wm_base:
    MSG [rip + id_wm_base], 3     # pong
    ARG [r13]
    END
    jmp .Ld_ret

.Ld_xdg_surface:
    MSG [rip + id_xdg_surface], 4 # ack_configure
    ARG [r13]
    END
    call apply_configure
    jmp .Ld_ret

.Ld_toplevel:
    cmp r12d, 1
    je .Ld_close
    test r12d, r12d
    jnz .Ld_ret
    mov eax, [r13]
    mov [rip + pend_w], eax
    mov eax, [r13 + 4]
    mov [rip + pend_h], eax
    # states array
    xor edx, edx
    mov ecx, [r13 + 8]
    lea rsi, [r13 + 12]
1:  cmp ecx, 4
    jb 2f
    mov eax, [rsi]
    cmp eax, 1
    jne 3f
    or edx, 1
3:  cmp eax, 2
    jne 3f
    or edx, 2
3:  cmp eax, 4
    jne 3f
    or edx, 4
3:  cmp eax, 5
    jb 3f
    cmp eax, 8
    ja 3f
    or edx, 8
3:  add rsi, 4
    sub ecx, 4
    jmp 1b
2:  mov [rip + pend_states], edx
    jmp .Ld_ret
.Ld_close:
    call app_on_close
    jmp .Ld_ret

.Ld_deco:
    # mode 2 = server side
    xor eax, eax
    cmp dword ptr [r13], 2
    sete al
    xor eax, 1
    mov [rip + g_csd], eax
    mov dword ptr [rip + g_dirty], 1
    jmp .Ld_ret

.Ld_frame:
    mov dword ptr [rip + id_frame_cb], 0
    jmp .Ld_ret
.Ld_buf0:
    mov dword ptr [rip + buf_busy], 0
    jmp .Ld_ret
.Ld_buf1:
    mov dword ptr [rip + buf_busy + 4], 0
    jmp .Ld_ret

.Ld_seat:
    # capabilities: a keyboard or pointer can go away (unplugged, a KVM switch) and come back,
    # each time as a new object
    test r12d, r12d
    jnz .Ld_ret
    mov eax, [r13]
    test eax, 1
    jnz 2f
    cmp dword ptr [rip + id_pointer], 0
    je 1f
    cmp dword ptr [rip + id_cursor_dev], 0
    je 21f
    MSG [rip + id_cursor_dev], 0  # destroy
    END
    mov dword ptr [rip + id_cursor_dev], 0
21: cmp dword ptr [rip + seat_ver], 3
    jb 22f
    MSG [rip + id_pointer], 1     # release
    END
22: mov dword ptr [rip + id_pointer], 0
    jmp 1f
2:  cmp dword ptr [rip + id_pointer], 0
    jne 1f
    call wl_new_id
    mov [rip + id_pointer], eax
    MSG [rip + id_seat], 0
    ARG [rip + id_pointer]
    END
    cmp dword ptr [rip + id_cursor_mgr], 0
    je 1f
    call wl_new_id
    mov [rip + id_cursor_dev], eax
    MSG [rip + id_cursor_mgr], 1
    ARG [rip + id_cursor_dev]
    ARG [rip + id_pointer]
    END
1:  mov eax, [r13]
    test eax, 2
    jz 3f
    cmp dword ptr [rip + id_keyboard], 0
    jne .Ld_ret
    call wl_new_id
    mov [rip + id_keyboard], eax
    MSG [rip + id_seat], 1
    ARG [rip + id_keyboard]
    END
    jmp .Ld_ret
3:  cmp dword ptr [rip + id_keyboard], 0
    je .Ld_ret
    cmp dword ptr [rip + seat_ver], 3
    jb 31f
    MSG [rip + id_keyboard], 0    # release
    END
31: mov dword ptr [rip + id_keyboard], 0
    mov dword ptr [rip + rep_key], 0
    jmp .Ld_ret

.Ld_fscale:
    mov eax, [r13]
    cmp eax, [rip + scale120]
    je .Ld_ret
    mov [rip + scale120], eax
    call apply_size
    jmp .Ld_ret

.Ld_surface:
    cmp r12d, 2                   # preferred_buffer_scale
    jne .Ld_ret
    cmp dword ptr [rip + id_fscale], 0
    jne .Ld_ret
    mov eax, [r13]
    cmp eax, [rip + int_scale]
    je .Ld_ret
    mov [rip + int_scale], eax
    MSG [rip + id_surface], 8
    ARG [rip + int_scale]
    END
    call apply_size
    jmp .Ld_ret

.Ld_pointer:
    mov rdi, r12
    mov rsi, r13
    call on_pointer
    jmp .Ld_ret
.Ld_keyboard:
    mov rdi, r12
    mov rsi, r13
    call on_keyboard
    jmp .Ld_ret

.Ld_ddev:
    test r12d, r12d
    jnz 1f
    # data_offer(new id)
    mov eax, [r13]
    mov [rip + offer_new], eax
    mov dword ptr [rip + offer_new_text], 0
    mov dword ptr [rip + offer_new_uri], 0
    jmp .Ld_ret
1:  cmp r12d, 5                   # selection
    jne 2f
    mov eax, [r13]
    mov ecx, [rip + sel_offer]
    cmp ecx, eax
    je .Ld_ret
    test ecx, ecx
    jz 3f
    push rax
    MSG [rip + sel_offer], 2      # destroy old offer
    END
    pop rax
3:  mov [rip + sel_offer], eax
    xor ecx, ecx
    cmp eax, [rip + offer_new]
    jne 4f
    mov ecx, [rip + offer_new_text]
4:  mov [rip + sel_offer_text], ecx
    jmp .Ld_ret
2:  cmp r12d, 1                   # enter: a drag came over the window
    jne 5f
    mov ebx, [r13 + 16]
    test ebx, ebx
    jz .Ld_ret
    cmp dword ptr [rip + dnd_offer], 0
    jne 21f
    cmp ebx, [rip + offer_new]
    jne 21f
    cmp dword ptr [rip + offer_new_uri], 0
    jne 22f
21: MSG ebx, 2                    # not files: the offer is dropped
    END
    jmp .Ld_ret
22: # files (text/uri-list) are taken, as a copy
    mov [rip + dnd_offer], ebx
    MSG ebx, 0                    # accept(serial, mime)
    ARG [r13]
    SARG .Lmime_uri
    END
    cmp dword ptr [rip + ddm_ver], 3
    jb .Ld_ret
    MSG [rip + dnd_offer], 4      # set_actions(copy, preferred copy)
    ARG 1
    ARG 1
    END
    jmp .Ld_ret
5:  cmp r12d, 2                   # leave without a drop
    jne 6f
    mov ebx, [rip + dnd_offer]
    test ebx, ebx
    jz .Ld_ret
    mov dword ptr [rip + dnd_offer], 0
    MSG ebx, 2
    END
    jmp .Ld_ret
6:  cmp r12d, 4                   # drop: the files' names come through a pipe (on_drop_readable)
    jne .Ld_ret
    mov ebx, [rip + dnd_offer]
    test ebx, ebx
    jz .Ld_ret
    mov dword ptr [rip + dnd_offer], 0
    cmp dword ptr [rip + drop_fd], -1
    jne 61f
    lea rdi, [rip + drop_pipe]
    mov esi, O_CLOEXEC
    SYS SYS_pipe2
    test rax, rax
    jns 62f
61: MSG ebx, 2
    END
    jmp .Ld_ret
62: mov [rip + drop_offer], ebx
    MSG ebx, 1                    # receive(mime, fd)
    SARG .Lmime_uri
    END
    mov edi, [rip + drop_pipe + 4]
    call wl_flush_fd
    mov edi, [rip + drop_pipe + 4]
    SYS SYS_close
    mov edi, [rip + drop_pipe]
    mov [rip + drop_fd], edi
    lea rdi, [rip + drop_sb]
    call sb_clear
    mov edi, [rip + drop_fd]
    mov esi, POLLIN
    lea rdx, [rip + on_drop_readable]
    xor ecx, ecx
    call watch_add
    jmp .Ld_ret

.Ld_offer:
    test r12d, r12d
    jnz .Ld_ret
    lea rdi, [r13 + 4]
    mov esi, [r13]
    dec esi
    lea rdx, [rip + .Lmime_uri]
    call str_eq_cstr
    test eax, eax
    jz 1f
    mov dword ptr [rip + offer_new_uri], 1
    jmp .Ld_ret
1:  lea rdi, [r13 + 4]
    mov esi, [r13]
    dec esi
    call mime_is_text
    test eax, eax
    jz .Ld_ret
    mov dword ptr [rip + offer_new_text], 1
    jmp .Ld_ret

.Ld_source:
    cmp r12d, 1                   # send(mime, fd)
    jne 1f
    call fdq_pop
    mov ebx, eax
    test eax, eax
    js .Ld_ret
    mov edi, ebx
    mov rsi, [rip + clip_sb + SB_ptr]
    mov rdx, [rip + clip_sb + SB_len]
    call write_all
    mov edi, ebx
    SYS SYS_close
    jmp .Ld_ret
1:  cmp r12d, 2                   # cancelled
    jne .Ld_ret
    MSG [rip + id_source], 1
    END
    mov dword ptr [rip + id_source], 0
    jmp .Ld_ret

.Ld_ret:
    pop r13
    pop r12
    pop rbx
    ret

# mime_is_text(ptr, len) -> 1 for utf-8 text types
mime_is_text:
    push rbx
    push r12
    mov rbx, rdi
    mov r12, rsi
    lea rdx, [rip + .Lmime_utf8]
    call str_eq_cstr
    test eax, eax
    jnz 1f
    mov rdi, rbx
    mov rsi, r12
    lea rdx, [rip + .Lmime_plain]
    call str_eq_cstr
    test eax, eax
    jnz 1f
    mov rdi, rbx
    mov rsi, r12
    lea rdx, [rip + .Lmime_utf8str]
    call str_eq_cstr
1:  pop r12
    pop rbx
    ret

# wl_on_global(args): name, interface, version
wl_on_global:
    PROLOGUE 16
    mov r12d, [rdi]               # name
    mov r13d, [rdi + 4]           # strlen incl NUL
    lea r14, [rdi + 8]            # interface
    lea eax, [r13 + 3]
    and eax, -4
    mov r15d, [r14 + rax]         # version
    lea rbx, [rip + global_table]
.Lg_next:
    mov rdi, [rbx]
    test rdi, rdi
    jz .Lg_ret
    mov rdx, rdi
    mov rdi, r14
    lea rsi, [r13 - 1]
    call str_eq_cstr
    test eax, eax
    jnz .Lg_found
    add rbx, 24
    jmp .Lg_next
.Lg_found:
    mov rax, [rbx + 8]            # id slot
    cmp dword ptr [rax], 0
    jne .Lg_ret
    # version = min(offered, wanted)
    mov ecx, [rbx + 16]
    cmp r15d, ecx
    cmova r15d, ecx
    mov [rsp], r15d
    call wl_new_id
    mov rcx, [rbx + 8]
    mov [rcx], eax
    mov [rsp + 4], eax
    MSG [rip + id_registry], 0
    ARG r12d
    mov rdi, [rbx]
    call wl_put_str
    ARG [rsp]
    ARG [rsp + 4]
    END
    mov rax, [rbx + 8]
    lea rcx, [rip + id_ddm]
    cmp rax, rcx
    je .Lg_ddm
    lea rcx, [rip + id_seat]
    cmp rax, rcx
    jne .Lg_ret
    mov eax, [rsp]
    mov [rip + seat_ver], eax
    jmp .Lg_ret
.Lg_ddm:
    mov eax, [rsp]
    mov [rip + ddm_ver], eax
.Lg_ret:
    EPILOGUE

# ---------------- window / buffers ----------------

# phys = logical * scale
logical_to_phys:
    mov eax, edi
    mov ecx, [rip + scale120]
    test ecx, ecx
    jz 1f
    imul eax, ecx
    add eax, 60
    xor edx, edx
    mov ecx, 120
    div ecx
    ret
1:  imul eax, [rip + int_scale]
    ret

apply_configure:
    mov eax, [rip + pend_states]
    mov [rip + g_win_states], eax
    mov eax, [rip + pend_w]
    test eax, eax
    jnz 1f
    mov eax, [rip + win_w]
    test eax, eax
    jnz 1f
    mov eax, 1280
1:  mov [rip + win_w], eax
    mov eax, [rip + pend_h]
    test eax, eax
    jnz 2f
    mov eax, [rip + win_h]
    test eax, eax
    jnz 2f
    mov eax, 820
2:  mov [rip + win_h], eax
    mov dword ptr [rip + configured], 1
    call apply_size
    ret

# apply_size(): (re)create buffers when physical size changed
apply_size:
    PROLOGUE
    cmp dword ptr [rip + configured], 0
    je .Las_ret
    mov edi, [rip + win_w]
    call logical_to_phys
    mov r12d, eax
    mov edi, [rip + win_h]
    call logical_to_phys
    mov r13d, eax
    # ui scale for the app
    mov eax, [rip + scale120]
    test eax, eax
    jnz 1f
    mov eax, [rip + int_scale]
    imul eax, eax, 120
1:  cvtsi2ss xmm0, eax
    divss xmm0, [rip + f_120]
    movss [rip + g_dpi_scale], xmm0
    cmp dword ptr [rip + id_viewport], 0
    je 2f
    MSG [rip + id_viewport], 2    # set_destination
    ARG [rip + win_w]
    ARG [rip + win_h]
    END
2:  mov dword ptr [rip + g_dirty], 1
    cmp r12d, [rip + buf_w]
    jne 3f
    cmp r13d, [rip + buf_h]
    je .Las_notify
3:  # destroy old
    cmp dword ptr [rip + id_pool], 0
    je 4f
    MSG [rip + id_buf], 0
    END
    MSG [rip + id_buf + 4], 0
    END
    MSG [rip + id_pool], 1
    END
    mov rdi, [rip + pool_mem]
    mov rsi, [rip + pool_size]
    SYS SYS_munmap
4:  mov [rip + buf_w], r12d
    mov [rip + buf_h], r13d
    mov eax, r12d
    imul eax, r13d
    shl rax, 3                    # 2 buffers * 4 bytes
    mov [rip + pool_size], rax
    lea rdi, [rip + .Lmemfd_name]
    mov esi, 1                    # MFD_CLOEXEC
    SYS SYS_memfd_create
    test rax, rax
    js .Las_fail
    mov ebx, eax
    mov edi, ebx
    mov rsi, [rip + pool_size]
    SYS SYS_ftruncate
    xor edi, edi
    mov rsi, [rip + pool_size]
    mov edx, PROT_READ | PROT_WRITE
    mov r10d, MAP_SHARED
    mov r8d, ebx
    xor r9d, r9d
    SYS SYS_mmap
    cmp rax, -4096
    ja .Las_fail
    mov [rip + pool_mem], rax
    call wl_new_id
    mov [rip + id_pool], eax
    MSG [rip + id_shm], 0
    ARG [rip + id_pool]
    ARG [rip + pool_size]
    END
    mov edi, ebx
    call wl_flush_fd
    mov edi, ebx
    SYS SYS_close
    xor r14d, r14d
5:  call wl_new_id
    lea rcx, [rip + id_buf]
    mov [rcx + r14*4], eax
    lea rcx, [rip + buf_busy]
    mov dword ptr [rcx + r14*4], 0
    mov r15d, eax
    MSG [rip + id_pool], 0
    ARG r15d
    mov eax, r12d
    imul eax, r13d
    shl eax, 2
    imul eax, r14d
    ARG eax
    ARG r12d
    ARG r13d
    lea eax, [r12*4]
    ARG eax
    ARG WL_SHM_ARGB8888         # the window's corners are see-through (window_corners)
    END
    inc r14d
    cmp r14d, 2
    jb 5b
.Las_notify:
    mov dword ptr [rip + g_argb], 1
    mov edi, r12d
    mov esi, r13d
    call app_on_resize
.Las_ret:
    EPILOGUE
.Las_fail:
    lea rdi, [rip + .Lshm_err]
    call die

# wl_draw(): render into a free buffer and commit
wl_draw:
    PROLOGUE
    call deco_sync
    cmp dword ptr [rip + configured], 0
    je .Ldr_ret
    cmp dword ptr [rip + id_frame_cb], 0
    jne .Ldr_ret
    xor ebx, ebx
    cmp dword ptr [rip + buf_busy], 0
    je 1f
    mov ebx, 1
    cmp dword ptr [rip + buf_busy + 4], 0
    jne .Ldr_ret
1:  mov eax, [rip + buf_w]
    imul eax, [rip + buf_h]
    shl rax, 2
    imul rax, rbx
    mov rdi, [rip + pool_mem]
    add rdi, rax
    mov esi, [rip + buf_w]
    mov edx, [rip + buf_h]
    mov ecx, esi
    call gfx_set_target
    mov dword ptr [rip + g_dirty], 0
    call app_render
    lea rcx, [rip + buf_busy]
    mov dword ptr [rcx + rbx*4], 1
    lea rcx, [rip + id_buf]
    mov r12d, [rcx + rbx*4]
    MSG [rip + id_surface], 1     # attach
    ARG r12d
    ARG 0
    ARG 0
    END
    MSG [rip + id_surface], 9     # damage_buffer
    ARG 0
    ARG 0
    ARG [rip + buf_w]
    ARG [rip + buf_h]
    END
    call wl_new_id
    mov [rip + id_frame_cb], eax
    MSG [rip + id_surface], 3     # frame
    ARG [rip + id_frame_cb]
    END
    MSG [rip + id_surface], 6     # commit
    END
    call wl_activate
.Ldr_ret:
    EPILOGUE

# ---------------- input ----------------

# fixed 24.8 logical -> physical int
fixed_to_phys:
    mov eax, edi
    mov ecx, [rip + scale120]
    test ecx, ecx
    jnz 1f
    imul eax, [rip + int_scale]
    sar eax, 8
    ret
1:  movsxd rax, edi
    movsxd rcx, ecx
    imul rax, rcx
    sar rax, 8
    cqo
    mov ecx, 120
    idiv rcx
    ret

# on_pointer(opcode, args)
on_pointer:
    push rbx
    push r12
    push r13
    mov ebx, edi
    mov r12, rsi
    cmp ebx, 0
    je .Lp_enter
    cmp ebx, 1
    je .Lp_leave
    cmp ebx, 2
    je .Lp_motion
    cmp ebx, 3
    je .Lp_button
    cmp ebx, 4
    je .Lp_axis
    cmp ebx, 6
    je .Lp_source
    jmp .Lp_ret
.Lp_enter:
    mov eax, [r12]
    mov [rip + enter_serial], eax
    mov dword ptr [rip + cur_shape], -1
    mov eax, [r12 + 8]
    mov [rip + ptr_x], eax
    mov eax, [r12 + 12]
    mov [rip + ptr_y], eax
    call send_motion
    jmp .Lp_ret
.Lp_leave:
    call app_on_pointer_leave
    jmp .Lp_ret
.Lp_motion:
    mov eax, [r12 + 4]
    mov [rip + ptr_x], eax
    mov eax, [r12 + 8]
    mov [rip + ptr_y], eax
    call send_motion
    jmp .Lp_ret
.Lp_button:
    mov eax, [r12]
    mov [rip + last_serial], eax
    mov eax, [r12 + 8]            # linux button code
    mov edi, BTN_LEFT
    cmp eax, 0x110
    je 1f
    mov edi, BTN_RIGHT
    cmp eax, 0x111
    je 1f
    mov edi, BTN_MIDDLE
    cmp eax, 0x112
    jne .Lp_ret
1:  mov esi, [r12 + 12]
    mov edx, [rip + kb_mods]
    call app_on_button
    jmp .Lp_ret
.Lp_axis:
    # in 1/(256 * 120) physical pixels: the wheel scrolls ~3 lines a notch, a touchpad 3x the
    # finger's travel, and what falls short of a pixel carries to the next event
    movsxd rax, dword ptr [r12 + 8]   # fixed 24.8 logical
    mov ecx, 5
    mov edx, 3
    mov esi, [rip + axis_src]
    dec esi
    cmp esi, 1                    # finger or continuous
    cmovbe ecx, edx
    imul rax, rcx
    mov ecx, [rip + scale120]
    test ecx, ecx
    jnz 1f
    imul ecx, dword ptr [rip + int_scale], 120
1:  imul rax, rcx
    mov ecx, [r12 + 4]            # 0 vertical, 1 horizontal
    and ecx, 1
    lea rsi, [rip + axis_rem]
    add rax, [rsi + rcx*8]
    cqo
    mov edi, 256 * 120
    idiv rdi
    mov [rsi + rcx*8], rdx
    mov r13d, eax
    xor edi, edi
    xor esi, esi
    cmp dword ptr [r12 + 4], 0
    jne 4f
    mov esi, r13d
    jmp 5f
4:  mov edi, r13d
5:  mov edx, [rip + kb_mods]
    call app_on_scroll
    jmp .Lp_ret
.Lp_source:
    mov eax, [r12]
    mov [rip + axis_src], eax
.Lp_ret:
    pop r13
    pop r12
    pop rbx
    ret

send_motion:
    push rbx
    mov edi, [rip + ptr_x]
    call fixed_to_phys
    mov ebx, eax
    mov edi, [rip + ptr_y]
    call fixed_to_phys
    mov edi, ebx
    mov esi, eax
    call app_on_motion
    pop rbx
    ret

# on_keyboard(opcode, args)
on_keyboard:
    PROLOGUE 16
    mov ebx, edi
    mov r12, rsi
    test ebx, ebx
    je .Lk_keymap
    cmp ebx, 1
    je .Lk_enter
    cmp ebx, 2
    je .Lk_leave
    cmp ebx, 3
    je .Lk_key
    cmp ebx, 4
    je .Lk_mods
    cmp ebx, 5
    je .Lk_repeat
    jmp .Lk_ret
.Lk_keymap:
    call fdq_pop
    mov r13d, eax
    test eax, eax
    js .Lk_ret
    mov r14d, [r12 + 4]           # size
    xor edi, edi
    mov esi, r14d
    mov edx, PROT_READ
    mov r10d, MAP_PRIVATE
    mov r8d, r13d
    xor r9d, r9d
    SYS SYS_mmap
    cmp rax, -4096
    ja 1f
    mov r15, rax
    mov rdi, rax
    mov esi, r14d
    call xkb_parse
    lea rdi, [rip + .Lkmdump]
    call getenv
    test rax, rax
    jz 11f
    mov rdi, rax
    mov rsi, r15
    lea edx, [r14 - 1]
    call file_write_all
11:
    mov rdi, r15
    mov esi, r14d
    SYS SYS_munmap
1:  mov edi, r13d
    SYS SYS_close
    jmp .Lk_ret
.Lk_enter:
    mov eax, [r12]
    mov [rip + last_serial], eax
    mov edi, 1
    call app_on_focus
    jmp .Lk_ret
.Lk_leave:
    mov dword ptr [rip + rep_key], 0
    xor edi, edi
    call app_on_focus
    jmp .Lk_ret
.Lk_key:
    mov eax, [r12]
    mov [rip + last_serial], eax
    mov edi, [r12 + 8]
    add edi, 8
    mov esi, [r12 + 12]
    cmp esi, 1
    jne 2f
    # press: arm repeat for non-modifier keys
    mov [rsp], edi
    call key_emit
    mov edi, [rsp]
    call is_modifier_key
    test eax, eax
    jnz .Lk_ret
    mov eax, [rsp]
    mov [rip + rep_key], eax
    call time_ms
    mov ecx, [rip + rep_delay]
    add rax, rcx
    mov [rip + rep_next], rax
    jmp .Lk_ret
2:  cmp edi, [rip + rep_key]
    jne .Lk_ret
    mov dword ptr [rip + rep_key], 0
    jmp .Lk_ret
.Lk_mods:
    mov eax, [r12 + 4]
    or eax, [r12 + 8]
    or eax, [r12 + 12]
    mov [rip + kb_mods], eax
    mov eax, [r12 + 16]
    mov [rip + kb_group], eax
    jmp .Lk_ret
.Lk_repeat:
    mov eax, [r12]
    mov [rip + rep_rate], eax
    mov eax, [r12 + 4]
    mov [rip + rep_delay], eax
.Lk_ret:
    EPILOGUE

# key_emit(xkb keycode)
key_emit:
    push rbx
    push r12
    push r13
    mov r12d, edi
    mov r13d, [rip + kb_group]
    mov esi, r13d
    mov edx, [rip + kb_mods]
    call xkb_keysym
    mov ebx, eax
    # shortcuts on a non-latin layout: use the first layout's key
    test dword ptr [rip + kb_mods], MOD_CTRL | MOD_ALT | MOD_SUPER
    jz 1f
    cmp ebx, 0x100
    jb 1f
    cmp ebx, 0xfe00
    jae 1f
    xor r13d, r13d
    mov edi, r12d
    xor esi, esi
    mov edx, [rip + kb_mods]
    call xkb_keysym
    mov ebx, eax
1:  # and the key's unshifted character in that layout, neither Shift nor Caps Lock (g_key_base)
    mov edi, r12d
    mov esi, r13d
    mov edx, [rip + kb_mods]
    and edx, -4
    call xkb_keysym
    mov edi, eax
    call keysym_to_unicode
    mov [rip + g_key_base], eax
    mov edi, ebx
    call keysym_to_unicode
    mov edi, ebx
    mov esi, eax
    mov edx, [rip + kb_mods]
    and edx, MOD_SHIFT | MOD_CTRL | MOD_ALT | MOD_SUPER
    call app_on_key
    mov dword ptr [rip + g_key_base], 0
    pop r13
    pop r12
    pop rbx
    ret

# is_modifier_key(xkb keycode) -> 1 if its base keysym is a modifier
is_modifier_key:
    mov esi, [rip + kb_group]
    mov edx, [rip + kb_mods]
    call xkb_keysym
    lea ecx, [rax - 0xffe1]
    cmp ecx, 0xffee - 0xffe1
    jbe 1f
    lea ecx, [rax - 0xfe01]
    cmp ecx, 0x20
    jbe 1f
    lea ecx, [rax - 0xfe50]         # dead keys
    cmp ecx, 0xfe93 - 0xfe50
    jbe 1f
    cmp eax, 0xff20                 # Multi_key
    je 1f
    xor eax, eax
    ret
1:  mov eax, 1
    ret

# deco_sync(): the title bar setting changed, tell the compositor
deco_sync:
    push rbx
    mov eax, [rip + cfg_decorations]
    cmp eax, [rip + deco_applied]
    je 9f
    mov [rip + deco_applied], eax
    cmp dword ptr [rip + id_deco], 0
    je 9f
    call deco_wanted
    mov [rip + deco_mode], eax
    MSG [rip + id_deco], 1
    ARG [rip + deco_mode]
    END
9:  pop rbx
    ret

# deco_wanted() -> 1 raftaar draws the title bar, 2 the compositor does.
# Auto: tiling compositors, which keep windows bare, get server side; everything else gets raftaar's own
deco_wanted:
    push rbx
    mov eax, [rip + cfg_decorations]
    cmp eax, 1
    je 1f
    cmp eax, 2
    je 2f
    call tiling_desktop
    test eax, eax
    jnz 2f
1:  mov eax, 1
    pop rbx
    ret
2:  mov eax, 2
    pop rbx
    ret

# tiling_desktop() -> 1 if XDG_CURRENT_DESKTOP names a tiling compositor
tiling_desktop:
    PROLOGUE
    lea rdi, [rip + .Lenv_desktop]
    call getenv
    test rax, rax
    jz 8f
    mov r12, rax
1:  # next ':' separated name
    xor r13d, r13d
2:  movzx eax, byte ptr [r12 + r13]
    test al, al
    jz 3f
    cmp al, ':'
    je 3f
    inc r13
    jmp 2b
3:  lea rbx, [rip + .Ltiling]
4:  mov rdx, [rbx]
    test rdx, rdx
    jz 5f
    mov rdi, r12
    mov rsi, r13
    call str_ieq_cstr
    test eax, eax
    jnz 9f
    add rbx, 8
    jmp 4b
5:  cmp byte ptr [r12 + r13], 0
    je 8f
    lea r12, [r12 + r13 + 1]
    jmp 1b
8:  xor eax, eax
9:  EPILOGUE

# theme_cursor(shape): the compositor cannot draw named cursors; show the theme's image on our own surface
theme_cursor:
    PROLOGUE 16
    mov ebx, edi
    cmp dword ptr [rip + id_pointer], 0
    je 9f
    # integer buffer scale: fractional outputs get the next larger image
    movss xmm0, [rip + g_dpi_scale]
    cvttss2si eax, xmm0
    cvtsi2ss xmm1, eax
    comiss xmm0, xmm1
    jbe 1f
    inc eax
1:  cmp eax, 1
    jge 2f
    mov eax, 1
2:  cmp eax, 4
    jle 3f
    mov eax, 4
3:  cmp eax, [rip + cur_bs]
    je 4f
    mov [rip + cur_bs], eax
    call cursor_drop
4:  lea rax, [rip + cur_ids]
    cmp dword ptr [rax + rbx*4], 0
    jne 5f
    mov edi, ebx
    call cursor_make
    lea rax, [rip + cur_ids]
    cmp dword ptr [rax + rbx*4], 0
    je 9f
5:  cmp dword ptr [rip + cur_surf], 0
    jne 6f
    call wl_new_id
    mov [rip + cur_surf], eax
    MSG [rip + id_compositor], 0  # create_surface
    ARG [rip + cur_surf]
    END
6:  MSG [rip + cur_surf], 8       # set_buffer_scale
    ARG [rip + cur_bs]
    END
    lea rax, [rip + cur_ids]
    mov r12d, [rax + rbx*4]
    MSG [rip + cur_surf], 1       # attach
    ARG r12d
    ARG 0
    ARG 0
    END
    MSG [rip + cur_surf], 2       # damage
    ARG 0
    ARG 0
    ARG 4096
    ARG 4096
    END
    MSG [rip + cur_surf], 6       # commit
    END
    lea rax, [rip + cur_hx]
    mov r12d, [rax + rbx*4]
    lea rax, [rip + cur_hy]
    mov r13d, [rax + rbx*4]
    MSG [rip + id_pointer], 0     # set_cursor
    ARG [rip + enter_serial]
    ARG [rip + cur_surf]
    ARG r12d
    ARG r13d
    END
9:  EPILOGUE

# cursor_make(shape): wl_buffer for the theme image (or the built-in one) at the current scale
cursor_make:
    PROLOGUE 32
    mov ebx, edi
    call xcursor_size
    imul eax, [rip + cur_bs]
    mov r12d, eax
    mov edi, ebx
    mov esi, r12d
    lea rdx, [rip + xcur]
    call xcursor_load
    test eax, eax
    jnz 1f
    mov edi, ebx
    mov esi, r12d
    lea rdx, [rip + xcur]
    call xcursor_builtin
1:  # buffer size must be a multiple of the scale
    mov ecx, [rip + cur_bs]
    mov eax, [rip + xcur + XC_w]
    add eax, ecx
    dec eax
    xor edx, edx
    div ecx
    imul eax, ecx
    mov r13d, eax               # W
    mov eax, [rip + xcur + XC_h]
    add eax, ecx
    dec eax
    xor edx, edx
    div ecx
    imul eax, ecx
    mov r14d, eax               # H
    imul eax, r13d
    shl rax, 2
    mov [rsp], rax              # bytes
    lea rdi, [rip + .Lcursor_name]
    mov esi, 1                  # MFD_CLOEXEC
    SYS SYS_memfd_create
    test rax, rax
    js 8f
    mov r15d, eax
    mov edi, r15d
    mov rsi, [rsp]
    SYS SYS_ftruncate
    xor edi, edi
    mov rsi, [rsp]
    mov edx, PROT_READ | PROT_WRITE
    mov r10d, MAP_SHARED
    mov r8d, r15d
    xor r9d, r9d
    SYS SYS_mmap
    cmp rax, -4096
    ja 7f
    mov [rsp + 8], rax
    # rows into the (zeroed) padded buffer
    xor ecx, ecx
2:  cmp ecx, [rip + xcur + XC_h]
    jae 3f
    mov [rsp + 16], ecx
    mov eax, ecx
    imul eax, r13d
    mov rdi, [rsp + 8]
    lea rdi, [rdi + rax*4]
    mov eax, ecx
    imul eax, [rip + xcur + XC_w]
    mov rsi, [rip + xcur + XC_pixels]
    lea rsi, [rsi + rax*4]
    mov ecx, [rip + xcur + XC_w]
    shl ecx, 2
    rep movsb
    mov ecx, [rsp + 16]
    inc ecx
    jmp 2b
3:  call wl_new_id
    mov [rsp + 16], eax         # pool
    MSG [rip + id_shm], 0         # create_pool
    ARG [rsp + 16]
    ARG [rsp]
    END
    mov edi, r15d
    call wl_flush_fd
    call wl_new_id
    lea rcx, [rip + cur_ids]
    mov [rcx + rbx*4], eax
    mov [rsp + 20], eax
    MSG [rsp + 16], 0             # create_buffer
    ARG [rsp + 20]
    ARG 0
    ARG r13d
    ARG r14d
    lea eax, [r13*4]
    ARG eax
    ARG 0                         # ARGB8888
    END
    MSG [rsp + 16], 1             # pool destroy (the buffer keeps it)
    END
    # hotspot in surface coordinates
    mov eax, [rip + xcur + XC_xhot]
    xor edx, edx
    div dword ptr [rip + cur_bs]
    lea rcx, [rip + cur_hx]
    mov [rcx + rbx*4], eax
    mov eax, [rip + xcur + XC_yhot]
    xor edx, edx
    div dword ptr [rip + cur_bs]
    lea rcx, [rip + cur_hy]
    mov [rcx + rbx*4], eax
    mov rdi, [rsp + 8]
    mov rsi, [rsp]
    SYS SYS_munmap
7:  mov edi, r15d
    SYS SYS_close
8:  mov rdi, [rip + xcur + XC_file]
    call mem_free
    EPILOGUE

# cursor_drop(): forget cursor buffers (the scale changed)
cursor_drop:
    push rbx
    xor ebx, ebx
1:  lea rax, [rip + cur_ids]
    mov eax, [rax + rbx*4]
    test eax, eax
    jz 2f
    MSG eax, 0                    # wl_buffer.destroy
    END
    lea rax, [rip + cur_ids]
    mov dword ptr [rax + rbx*4], 0
2:  inc ebx
    cmp ebx, 8
    jb 1b
    pop rbx
    ret

# ---------------- vtable entries ----------------

wl_timeout:
    cmp dword ptr [rip + rep_key], 0
    je 1f
    cmp dword ptr [rip + rep_rate], 0
    je 1f
    call time_ms
    mov rcx, [rip + rep_next]
    sub rcx, rax
    jns 2f
    xor ecx, ecx
2:  mov eax, ecx
    ret
1:  mov eax, -1
    ret

wl_tick:
    cmp dword ptr [rip + rep_key], 0
    je 1f
    cmp dword ptr [rip + rep_rate], 0
    je 1f
    call time_ms
    cmp rax, [rip + rep_next]
    jb 1f
    mov ecx, 1000
    xor edx, edx
    mov eax, ecx
    div dword ptr [rip + rep_rate]
    add [rip + rep_next], rax
    call time_ms
    cmp rax, [rip + rep_next]     # don't build a backlog
    jb 2f
    mov [rip + rep_next], rax
2:  mov edi, [rip + rep_key]
    call key_emit
1:  ret

wl_set_cursor:
    cmp edi, [rip + cur_shape]
    je 1f
    mov [rip + cur_shape], edi
    cmp dword ptr [rip + id_cursor_dev], 0
    je theme_cursor
    push rbx
    lea rax, [rip + cursor_shapes]
    movzx ebx, byte ptr [rax + rdi]
    MSG [rip + id_cursor_dev], 1
    ARG [rip + enter_serial]
    ARG ebx
    END
    pop rbx
1:  ret

wl_move:
    cmp dword ptr [rip + id_toplevel], 0
    je 1f
    mov dword ptr [rip + rep_key], 0
    MSG [rip + id_toplevel], 5
    ARG [rip + id_seat]
    ARG [rip + last_serial]
    END
1:  ret

wl_resize:
    push rbx
    mov ebx, edi
    MSG [rip + id_toplevel], 6
    ARG [rip + id_seat]
    ARG [rip + last_serial]
    ARG ebx
    END
    pop rbx
    ret

wl_minimize:
    MSG [rip + id_toplevel], 13
    END
    ret

wl_maximize:
    mov esi, 9
    test dword ptr [rip + g_win_states], 1
    jz 1f
    mov esi, 10
1:  MSG [rip + id_toplevel], esi
    END
    ret

wl_title:
    push rbx
    mov rbx, rdi
    MSG [rip + id_toplevel], 2
    mov rdi, rbx
    call wl_put_str
    END
    pop rbx
    ret

wl_menu:
    push rbx
    push r12
    sub rsp, 8
    # physical -> logical
    mov eax, edi
    mov ebx, esi
    call phys_to_logical
    mov r12d, eax
    mov eax, ebx
    call phys_to_logical
    mov ebx, eax
    MSG [rip + id_toplevel], 4
    ARG [rip + id_seat]
    ARG [rip + last_serial]
    ARG r12d
    ARG ebx
    END
    add rsp, 8
    pop r12
    pop rbx
    ret

# eax physical -> eax logical
phys_to_logical:
    mov ecx, [rip + scale120]
    test ecx, ecx
    jz 1f
    imul eax, eax, 120
    xor edx, edx
    div ecx
    ret
1:  xor edx, edx
    div dword ptr [rip + int_scale]
    ret

# clipboard: copy
wl_clip_set:
    push rbx
    push r12
    push r13
    mov rbx, rdi
    mov r12, rsi
    lea rdi, [rip + clip_sb]
    call sb_clear
    lea rdi, [rip + clip_sb]
    mov rsi, rbx
    mov rdx, r12
    call sb_push
    cmp dword ptr [rip + id_ddm], 0
    je 9f
    cmp dword ptr [rip + id_source], 0
    je 1f
    MSG [rip + id_source], 1
    END
1:  call wl_new_id
    mov [rip + id_source], eax
    MSG [rip + id_ddm], 0
    ARG [rip + id_source]
    END
    MSG [rip + id_source], 0
    SARG .Lmime_utf8
    END
    MSG [rip + id_source], 0
    SARG .Lmime_plain
    END
    MSG [rip + id_source], 0
    SARG .Lmime_utf8str
    END
    MSG [rip + id_ddev], 1
    ARG [rip + id_source]
    ARG [rip + last_serial]
    END
9:  pop r13
    pop r12
    pop rbx
    ret

# clipboard: paste (async, delivers app_on_paste)
wl_clip_get:
    push rbx
    sub rsp, 16
    cmp dword ptr [rip + id_source], 0
    je 1f
    # we own the selection
    mov rdi, [rip + clip_sb + SB_ptr]
    mov rsi, [rip + clip_sb + SB_len]
    call app_on_paste
    jmp 9f
1:  cmp dword ptr [rip + sel_offer], 0
    je 9f
    cmp dword ptr [rip + sel_offer_text], 0
    je 9f
    cmp dword ptr [rip + paste_fd], -1
    jne 9f
    mov rdi, rsp
    mov esi, O_CLOEXEC
    SYS SYS_pipe2
    test rax, rax
    js 9f
    MSG [rip + sel_offer], 1      # receive(mime, fd)
    SARG .Lmime_utf8
    END
    mov edi, [rsp + 4]
    call wl_flush_fd
    mov edi, [rsp + 4]
    SYS SYS_close
    mov edi, [rsp]
    mov [rip + paste_fd], edi
    lea rdi, [rip + paste_sb]
    call sb_clear
    mov edi, [rip + paste_fd]
    mov esi, POLLIN
    lea rdx, [rip + on_paste_readable]
    xor ecx, ecx
    call watch_add
9:  add rsp, 16
    pop rbx
    ret

on_paste_readable:
    push rbx
    mov ebx, edi
    lea rdi, [rip + paste_sb]
    mov esi, 65536
    call sb_reserve
    mov edi, ebx
    mov rsi, rax
    mov edx, 65536
    SYS SYS_read
    test rax, rax
    jle 1f
    add [rip + paste_sb + SB_len], rax
    pop rbx
    ret
1:  mov edi, ebx
    call watch_remove
    mov edi, ebx
    SYS SYS_close
    mov dword ptr [rip + paste_fd], -1
    mov rdi, [rip + paste_sb + SB_ptr]
    mov rsi, [rip + paste_sb + SB_len]
    call app_on_paste
    pop rbx
    ret

# the dropped files' names arrive: at the end the drag is finished and the app gets them
on_drop_readable:
    push rbx
    mov ebx, edi
    lea rdi, [rip + drop_sb]
    mov esi, 65536
    call sb_reserve
    mov edi, ebx
    mov rsi, rax
    mov edx, 65536
    SYS SYS_read
    test rax, rax
    jle 1f
    add [rip + drop_sb + SB_len], rax
    pop rbx
    ret
1:  mov edi, ebx
    call watch_remove
    mov edi, ebx
    SYS SYS_close
    mov dword ptr [rip + drop_fd], -1
    cmp dword ptr [rip + ddm_ver], 3
    jb 2f
    MSG [rip + drop_offer], 3     # finish
    END
2:  MSG [rip + drop_offer], 2     # destroy
    END
    mov dword ptr [rip + drop_offer], 0
    mov edi, -1
    call wl_flush_fd
    mov rdi, [rip + drop_sb + SB_ptr]
    mov rsi, [rip + drop_sb + SB_len]
    call app_on_drop
    pop rbx
    ret

# ---------------- setup ----------------

# wl_connect() -> 1 on success, 0 if no wayland display
FN wl_connect
    PROLOGUE 16
    lea rdi, [rip + .Lenv_display]
    call getenv
    mov rbx, rax
    test rax, rax
    jnz 1f
    lea rbx, [rip + .Ldefault_display]
1:  # sockaddr_un
    lea rdi, [rip + sockaddr]
    mov word ptr [rdi], AF_UNIX
    add rdi, 2
    cmp byte ptr [rbx], '/'
    je 2f
    push rdi
    lea rdi, [rip + .Lenv_runtime]
    call getenv
    pop rdi
    test rax, rax
    jz .Lwc_fail
    mov rsi, rax
3:  lodsb
    test al, al
    jz 4f
    stosb
    jmp 3b
4:  mov byte ptr [rdi], '/'
    inc rdi
2:  mov rsi, rbx
5:  lodsb
    stosb
    test al, al
    jnz 5b
    mov edi, AF_UNIX
    mov esi, SOCK_STREAM | SOCK_CLOEXEC
    xor edx, edx
    SYS SYS_socket
    test rax, rax
    js .Lwc_fail
    mov [rip + wl_fd], eax
    mov edi, eax
    lea rsi, [rip + sockaddr]
    mov edx, 110
    SYS SYS_connect
    test rax, rax
    js .Lwc_close
    mov dword ptr [rip + next_id], 2
    # registry
    call wl_new_id
    mov [rip + id_registry], eax
    MSG 1, 1
    ARG [rip + id_registry]
    END
    call wl_roundtrip
    cmp dword ptr [rip + id_compositor], 0
    je .Lwc_close
    cmp dword ptr [rip + id_shm], 0
    je .Lwc_close
    cmp dword ptr [rip + id_wm_base], 0
    je .Lwc_close
    mov eax, 1
    EPILOGUE
.Lwc_close:
    mov edi, [rip + wl_fd]
    SYS SYS_close
.Lwc_fail:
    xor eax, eax
    EPILOGUE

# Use the desktop launcher's token once the surface is mapped, then remove it
# from the environment so terminals and other children cannot reuse it.
wl_activate:
    PROLOGUE
    cmp dword ptr [rip + activation_sent], 0
    jne 9f
    mov dword ptr [rip + activation_sent], 1
    lea rdi, [rip + .Lenv_activation]
    call getenv
    test rax, rax
    jz 9f
    mov rbx, rax
    cmp byte ptr [rbx], 0
    je 8f
    cmp dword ptr [rip + id_activation], 0
    je 8f
    MSG [rip + id_activation], 2
    mov rdi, rbx
    call wl_put_str
    ARG [rip + id_surface]
    END
8:  lea rdi, [rip + .Lenv_activation]
    call env_unset
9:  EPILOGUE

# wl_open_window(title cstr): create the toplevel and install the vtable
FN wl_open_window
    PROLOGUE 16
    mov rbx, rdi
    call wl_new_id
    mov [rip + id_surface], eax
    MSG [rip + id_compositor], 0
    ARG [rip + id_surface]
    END
    cmp dword ptr [rip + id_fscale_mgr], 0
    je 1f
    cmp dword ptr [rip + id_viewporter], 0
    je 1f
    call wl_new_id
    mov [rip + id_fscale], eax
    MSG [rip + id_fscale_mgr], 1
    ARG [rip + id_fscale]
    ARG [rip + id_surface]
    END
    call wl_new_id
    mov [rip + id_viewport], eax
    MSG [rip + id_viewporter], 1
    ARG [rip + id_viewport]
    ARG [rip + id_surface]
    END
    mov dword ptr [rip + scale120], 120
1:  call wl_new_id
    mov [rip + id_xdg_surface], eax
    MSG [rip + id_wm_base], 2
    ARG [rip + id_xdg_surface]
    ARG [rip + id_surface]
    END
    call wl_new_id
    mov [rip + id_toplevel], eax
    MSG [rip + id_xdg_surface], 1
    ARG [rip + id_toplevel]
    END
    MSG [rip + id_toplevel], 2
    mov rdi, rbx
    call wl_put_str
    END
    MSG [rip + id_toplevel], 3
    SARG .Lapp_id
    END
    MSG [rip + id_toplevel], 8    # min size
    ARG 560
    ARG 360
    END
    mov dword ptr [rip + g_csd], 1
    cmp dword ptr [rip + id_deco_mgr], 0
    je 2f
    call wl_new_id
    mov [rip + id_deco], eax
    MSG [rip + id_deco_mgr], 1
    ARG [rip + id_deco]
    ARG [rip + id_toplevel]
    END
    mov eax, [rip + cfg_decorations]
    mov [rip + deco_applied], eax
    call deco_wanted
    mov [rip + deco_mode], eax
    MSG [rip + id_deco], 1        # set_mode
    ARG [rip + deco_mode]
    END
2:  cmp dword ptr [rip + id_ddm], 0
    je 3f
    cmp dword ptr [rip + id_seat], 0
    je 3f
    call wl_new_id
    mov [rip + id_ddev], eax
    MSG [rip + id_ddm], 1
    ARG [rip + id_ddev]
    ARG [rip + id_seat]
    END
3:  MSG [rip + id_surface], 6     # initial commit
    END
    # vtable
    lea rax, [rip + wl_flush]
    mov [rip + g_plat + P_flush], rax
    lea rax, [rip + wl_timeout]
    mov [rip + g_plat + P_timeout], rax
    lea rax, [rip + wl_tick]
    mov [rip + g_plat + P_tick], rax
    lea rax, [rip + wl_draw]
    mov [rip + g_plat + P_draw], rax
    lea rax, [rip + wl_set_cursor]
    mov [rip + g_plat + P_cursor], rax
    lea rax, [rip + wl_clip_set]
    mov [rip + g_plat + P_clip_set], rax
    lea rax, [rip + wl_clip_get]
    mov [rip + g_plat + P_clip_get], rax
    lea rax, [rip + wl_move]
    mov [rip + g_plat + P_move], rax
    lea rax, [rip + wl_resize]
    mov [rip + g_plat + P_resize], rax
    lea rax, [rip + wl_minimize]
    mov [rip + g_plat + P_minimize], rax
    lea rax, [rip + wl_maximize]
    mov [rip + g_plat + P_maximize], rax
    lea rax, [rip + wl_title]
    mov [rip + g_plat + P_title], rax
    lea rax, [rip + wl_menu]
    mov [rip + g_plat + P_menu], rax
    mov edi, [rip + wl_fd]
    mov esi, POLLIN
    lea rdx, [rip + wl_on_readable]
    xor ecx, ecx
    call watch_add
    call wl_roundtrip
    EPILOGUE

.section .rodata
.p2align 3
# interface name, id slot, max version
global_table:
    .quad .Li_compositor, id_compositor, 6
    .quad .Li_shm, id_shm, 1
    .quad .Li_wm_base, id_wm_base, 2
    .quad .Li_seat, id_seat, 5
    .quad .Li_ddm, id_ddm, 3
    .quad .Li_deco, id_deco_mgr, 1
    .quad .Li_cursor, id_cursor_mgr, 1
    .quad .Li_viewporter, id_viewporter, 1
    .quad .Li_fscale, id_fscale_mgr, 1
    .quad .Li_activation, id_activation, 1
    .quad 0, 0, 0
.Li_compositor: .asciz "wl_compositor"
.Li_shm: .asciz "wl_shm"
.Li_wm_base: .asciz "xdg_wm_base"
.Li_seat: .asciz "wl_seat"
.Li_ddm: .asciz "wl_data_device_manager"
.Li_deco: .asciz "zxdg_decoration_manager_v1"
.Li_cursor: .asciz "wp_cursor_shape_manager_v1"
.Li_viewporter: .asciz "wp_viewporter"
.Li_fscale: .asciz "wp_fractional_scale_manager_v1"
.Li_activation: .asciz "xdg_activation_v1"
.p2align 3
.Ltiling: .quad .Lt_hypr, .Lt_sway, .Lt_niri, .Lt_river, .Lt_dwl, .Lt_qtile, 0
.Lt_hypr: .asciz "Hyprland"
.Lt_sway: .asciz "sway"
.Lt_niri: .asciz "niri"
.Lt_river: .asciz "river"
.Lt_dwl: .asciz "dwl"
.Lt_qtile: .asciz "qtile"
.Lenv_desktop: .asciz "XDG_CURRENT_DESKTOP"
.Lenv_display: .asciz "WAYLAND_DISPLAY"
.Lenv_runtime: .asciz "XDG_RUNTIME_DIR"
.Lenv_activation: .asciz "XDG_ACTIVATION_TOKEN"
.Ldefault_display: .asciz "wayland-0"
.Lmemfd_name: .asciz "raftaar-shm"
.Lcursor_name: .asciz "raftaar-cursor"
.Lapp_id: .asciz "raftaar"
.Lkmdump: .asciz "RAFTAAR_DUMP_KEYMAP"
.Lmime_utf8: .asciz "text/plain;charset=utf-8"
.Lmime_uri: .asciz "text/uri-list"
.Lmime_plain: .asciz "text/plain"
.Lmime_utf8str: .asciz "UTF8_STRING"
.Lproto_err: .asciz "wayland protocol error: "
.Ldisconnected: .asciz "raftaar: wayland connection closed"
.Lsend_err: .asciz "raftaar: wayland send failed"
.Lshm_err: .asciz "raftaar: shm buffer allocation failed"
# CUR_* -> wp_cursor_shape_device_v1 shapes
cursor_shapes: .byte 1, 9, 4, 26, 27, 29, 28, 1
.p2align 2
f_120: .float 120.0

.data
int_scale: .long 1
rep_rate: .long 25
rep_delay: .long 400
paste_fd: .long -1
drop_fd: .long -1
.globl g_csd, g_dpi_scale
g_csd: .long 1
deco_applied: .long -1
cur_bs: .long 0
cur_surf: .long 0
cur_ids: .zero 4 * 8
cur_hx: .zero 4 * 8
cur_hy: .zero 4 * 8
.p2align 3
xcur: .zero XC_SIZE
deco_mode: .long 0
g_dpi_scale: .float 1.0
