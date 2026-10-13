# source control: the history's work tree row, as VS Code's Source Control view. A commit message with
# Commit (or Sync Changes, Publish Branch when there is nothing to commit), Pull, Push and Fetch, and the
# changes by group: merge conflicts, staged, not staged, each file to stage, unstage or discard
.include "raftaar.inc"

.equ ID_SCM, 0x100000
.equ ID_SCM_MSG, ID_SCM
.equ ID_SCM_MAIN, ID_SCM + 1            # the button under the message
.equ ID_SCM_PULL, ID_SCM + 2            # Pull, Push, Fetch
.equ ID_SCM_SCROLL, ID_SCM + 5
.equ ID_SCM_AI, ID_SCM + 6
.equ ID_SCM_RESET, ID_SCM + 7
.equ ID_SCM_GROUP, ID_SCM + 0x10        # + group * 4 + button
.equ ID_SCM_FILE, ID_SCM + 0x100        # + file * 4 + button
.equ MAX_LINES, 10                      # of the message shown at once
.equ MAX_MSG, 60000                     # the message fits the pipe to git: raftaar never waits to write it
.equ ENABLED, 0x100                     # with the UB_* bits of a button that takes clicks

# steps of an operation: what git runs (seq_*: steps, then 0)
.equ S_ADD_ALL, 1
.equ S_COMMIT, 2
.equ S_AMEND, 3
.equ S_PULL_CFG, 4                      # is pull.rebase or pull.ff set
.equ S_PULL, 5
.equ S_PUSH, 6
.equ S_REMOTES, 7
.equ S_PUBLISH, 8
.equ S_FETCH, 9
.equ S_ADD, 10                          # the ones on op_path
.equ S_RESET, 11
.equ S_RESET_ALL, 12
.equ S_CHECKOUT, 13
.equ S_CHECKOUT_ALL, 14
.equ S_CLEAN, 15
.equ S_CLEAN_ALL, 16
.equ S_RESET_HARD, 17

# operations, one at a time
.equ OP_NONE, 0
.equ OP_COMMIT, 1
.equ OP_PULL, 2
.equ OP_PUSH, 3
.equ OP_SYNC, 4
.equ OP_FETCH, 5
.equ OP_PUBLISH, 6
.equ OP_INDEX, 7                        # stage, unstage, discard
.equ OP_RESET, 8

# the button under the message
.equ MB_NONE, 0                         # Commit, with nothing to commit
.equ MB_COMMIT, 1
.equ MB_COMMIT_ALL, 2                   # nothing staged: everything is staged first
.equ MB_SYNC, 3
.equ MB_PUBLISH, 4

.bss
.p2align 3
ai_draft: .zero SB_SIZE
tf_msg: .zero TF_SIZE                   # the commit message
list: .zero VEC_SIZE                    # GF of the status by group
xlist: .zero VEC_SIZE                   # expand_folders builds the list in it, then they swap
ubuf: .zero SB_SIZE                     # git ls-files --others: the untracked files, NUL after each
u_want: .long 0                         # g_git_ver when the running ls-files started
u_running: .long 0
u_extra: .long 0                        # rows expand_folders added: a folder's files, less its row
seq: .quad 0                            # the running operation's step
confirm_seq: .quad 0                    # what a confirmed discard runs
lbl: .zero SB_SIZE
tmp: .zero SB_SIZE
tips: .zero SB_SIZE                     # the hovered button's tooltip
argv: .zero 8 * 12
counts: .zero 4 * 4                     # files per group
pan: .zero 16                           # the panel: x, y, w, h
in_x: .long 0                           # its content
in_w: .long 0
ai_row: .long 0                         # Generate has a row of its own, under the message
act_h: .long 0                          # the height of the main button and Push
op: .long 0                             # OP_*
pull_merge: .long 0                     # neither pull.rebase nor pull.ff is set: pull merges
scroll: .long 0
content_h: .long 0
merge_seen: .long 0                     # the merge's message went into the message box
rm_running: .long 0
pc_running: .long 0                     # pull_check runs
has_remote: .long 0
remote: .zero 256                       # to publish to
err: .zero 256                          # what went wrong last
op_path: .zero 4096
question: .zero 4200
reset_root: .zero 4096                  # the repository named by the reset confirmation
.data
list_ver: .long -1                      # g_git_ver of the list
u_ver: .long -1                         # g_git_ver of ubuf

.text

# ---------------- commands ----------------

FN cmd_git_commit
    xor edi, edi
    jmp commit
FN cmd_git_commit_amend
    mov edi, 1
# commit(amend): the message commits what is staged, or every change when nothing is (as VS Code's smart
#   commit); amending keeps the last commit's message when the box is empty
commit:
    PROLOGUE
    mov ebx, edi
    call ready
    test eax, eax
    jz 9f
    lea rdi, [rip + .Llong]
    cmp qword ptr [rip + tf_msg + TF_sb + SB_len], MAX_MSG
    ja 8f
    call sync_list
    lea rsi, [rip + seq_amend]
    test ebx, ebx
    jnz 3f
    lea rdi, [rip + .Lconflicts]
    cmp dword ptr [rip + counts + 4*GG_MERGE], 0
    jne 8f
    lea rdi, [rip + .Lnothing]
    mov eax, [rip + counts + 4*GG_STAGED]
    add eax, [rip + counts + 4*GG_CHANGES]
    jz 8f
    call msg_blank
    test eax, eax
    jz 1f
    lea rdi, [rip + .Lno_message]
    call app_toast
    call scm_focus
    jmp 9f
1:  lea rsi, [rip + seq_commit]
    cmp dword ptr [rip + counts + 4*GG_STAGED], 0
    jne 3f
    lea rsi, [rip + seq_commit_all]
3:  mov edi, OP_COMMIT
    call op_begin
    jmp 9f
8:  call app_toast
9:  EPILOGUE

FN cmd_git_pull
    mov edi, OP_PULL
    lea rsi, [rip + seq_pull]
    jmp start

FN cmd_git_fetch
    mov edi, OP_FETCH
    lea rsi, [rip + seq_fetch]
    jmp start

# pushing a branch without an upstream publishes it, to its remote
FN cmd_git_push
    mov edi, OP_PUSH
    lea rsi, [rip + seq_push]
    jmp 1f
FN cmd_git_sync
    mov edi, OP_SYNC
    lea rsi, [rip + seq_sync]
1:  push rsi
    push rdi
    call unpublished
    pop rdi
    pop rsi
    test eax, eax
    jz start
    mov edi, OP_PUBLISH
    lea rsi, [rip + seq_publish]
    jmp start

FN cmd_git_stage_all
    mov edi, OP_INDEX
    lea rsi, [rip + seq_stage_all]
    jmp start

FN cmd_git_unstage_all
    mov edi, OP_INDEX
    lea rsi, [rip + seq_unstage_all]
    jmp start

# Reset the index and work tree, then remove untracked files and directories.
FN cmd_git_reset_all
    PROLOGUE
    call ready
    test eax, eax
    jz 9f
    cmp qword ptr [rip + g_git_rootlen], 4096
    jae 9f
    lea rdi, [rip + reset_root]
    mov rsi, [rip + g_git_root]
    call cstr_copy
    lea rdi, [rip + .Lq_reset]
    lea rsi, [rip + .Lq_reset_text]
    lea rdx, [rip + .Lb_reset]
    lea rcx, [rip + reset_confirmed]
    call app_confirm
9:  EPILOGUE

reset_confirmed:
    push rbx
    mov rdi, [rip + g_git_root]
    test rdi, rdi
    jz 9f
    lea rsi, [rip + reset_root]
    call strcmp_eq
    test eax, eax
    jz 9f
    mov edi, OP_RESET
    lea rsi, [rip + seq_reset_all]
    call start
9:  pop rbx
    ret

FN cmd_git_discard_all
    PROLOGUE
    call ready
    test eax, eax
    jz 9f
    call sync_list
    cmp dword ptr [rip + counts + 4*GG_CHANGES], 0
    jne 1f
    lea rdi, [rip + .Lnothing_discard]
    call app_toast
    jmp 9f
1:  call discard_all_seq
    mov [rip + confirm_seq], rax
    lea rdi, [rip + .Lq_all]
    lea rsi, [rip + .Lq_all_text]
    lea rdx, [rip + .Lb_discard_all]
    lea rcx, [rip + confirmed]
    call app_confirm
9:  EPILOGUE

# discard_all_seq() -> rax what discarding all changes runs: tracked files go back only when some
#   changed (checkout fails with none to restore)
discard_all_seq:
    lea rax, [rip + seq_clean_all]
    xor ecx, ecx
1:  cmp rcx, [rip + list + VEC_len]
    jae 9f
    imul rdx, rcx, GF_SIZE
    add rdx, [rip + list + VEC_ptr]
    inc rcx
    cmp dword ptr [rdx + GF_group], GG_CHANGES
    jne 1b
    cmp dword ptr [rdx + GF_code], 'U'
    je 1b
    lea rax, [rip + seq_discard_all]
9:  ret

# start(op, seq): an operation when none runs
start:
    PROLOGUE
    mov r12d, edi
    mov r13, rsi
    call ready
    test eax, eax
    jz 9f
    mov edi, r12d
    mov rsi, r13
    call op_begin
9:  EPILOGUE

# confirmed(): the discard the dialog asked about
confirmed:
    mov edi, OP_INDEX
    mov rsi, [rip + confirm_seq]
    jmp op_begin

# ready() -> 1 when an operation can start, else says why not
ready:
    push rbx
    lea rdi, [rip + .Lno_repo]
    cmp dword ptr [rip + g_git_on], 0
    je 1f
    lea rdi, [rip + .Lbusy]
    cmp dword ptr [rip + op], OP_NONE
    jne 1f
    mov eax, 1
    pop rbx
    ret
1:  call app_toast
    xor eax, eax
    pop rbx
    ret

# unpublished() -> 1 when HEAD is a branch without an upstream
unpublished:
    xor eax, eax
    cmp dword ptr [rip + g_git_head], HD_BRANCH
    jne 1f
    cmp byte ptr [rip + g_git_upstream], 0
    jne 1f
    mov eax, 1
1:  ret

# msg_blank() -> 1 when the message has nothing but blanks
msg_blank:
    push rbx
    lea rdi, [rip + tf_msg]
    call tf_text
    pop rbx
    xor ecx, ecx
1:  cmp rcx, rdx
    jae 2f
    cmp byte ptr [rax + rcx], ' '
    ja 3f
    inc rcx
    jmp 1b
2:  mov eax, 1
    ret
3:  xor eax, eax
    ret

# scm_focus(): the history with the work tree selected, typing in the commit message
FN scm_focus
    push rbx
    cmp dword ptr [rip + g_git_on], 0
    jne 1f
    lea rdi, [rip + .Lno_repo]
    call app_toast
    pop rbx
    ret
1:  call gitview_show_wip
    mov dword ptr [rip + g_focus], FOCUS_SCM
    mov dword ptr [rip + scroll], 0
    mov dword ptr [rip + g_dirty], 1
    pop rbx
    ret

# scm_key(keysym, cp, mods) -> 1 if used: the commit message has the keys; Ctrl+Enter commits, Esc leaves
FN scm_key
    PROLOGUE
    mov r12d, edi
    mov r13d, esi
    mov r14d, edx
    # only while the history shows it
    mov rdi, [rip + g_tab_cur]
    test rdi, rdi
    js 8f
    call tab_at
    cmp qword ptr [rax + TAB_kind], TAB_GIT
    jne 8f
    cmp r12d, KEY_ESCAPE
    jne 1f
    mov dword ptr [rip + g_focus], FOCUS_EDITOR
    jmp .Lsk_yes
1:  cmp r12d, KEY_RETURN
    je 2f
    cmp r12d, KEY_KP_ENTER
    jne 3f
2:  test r14d, MOD_CTRL
    jz 3f
    call cmd_git_commit
    jmp .Lsk_yes
3:  lea rdi, [rip + tf_msg]
    mov esi, r12d
    mov edx, r13d
    mov ecx, r14d
    call ta_key
    test eax, eax
    jz 9f
    mov dword ptr [rip + scroll], 0
.Lsk_yes:
    mov dword ptr [rip + g_dirty], 1
    mov eax, 1
    EPILOGUE
8:  mov dword ptr [rip + g_focus], FOCUS_EDITOR
9:  xor eax, eax
    EPILOGUE

# scm_paste(ptr, len): into the commit message
FN scm_paste
    mov rdx, rsi
    mov rsi, rdi
    lea rdi, [rip + tf_msg]
    jmp ta_insert

# scm_reset(): another repository
FN scm_reset
    push rbx
    call ai_cancel_generation
    mov dword ptr [rip + op], OP_NONE
    mov dword ptr [rip + list_ver], -1
    mov qword ptr [rip + list + VEC_len], 0
    lea rdi, [rip + counts]
    xor eax, eax
    mov ecx, 16
    rep stosb
    mov byte ptr [rip + err], 0
    mov byte ptr [rip + remote], 0
    mov dword ptr [rip + has_remote], 0
    mov dword ptr [rip + rm_running], 0
    mov dword ptr [rip + pc_running], 0
    mov dword ptr [rip + u_running], 0
    mov dword ptr [rip + u_ver], -1
    mov dword ptr [rip + u_extra], 0
    lea rdi, [rip + ubuf]
    call sb_clear
    mov dword ptr [rip + merge_seen], 0
    mov dword ptr [rip + scroll], 0
    lea rdi, [rip + tf_msg]
    call tf_clear
    cmp dword ptr [rip + g_focus], FOCUS_SCM
    jne 1f
    mov dword ptr [rip + g_focus], FOCUS_EDITOR
1:  pop rbx
    ret

# Capture the user's draft before starting. Result insertion requires exact equality.
FN cmd_git_generate_message
    PROLOGUE
    cmp dword ptr [rip + g_ai_kind], 3
    jne 1f
    call ai_cancel_generation
    jmp 9f
1:  cmp dword ptr [rip + cfg_commit_ai], 0
    jne 2f
    lea rdi, [rip + .Lai_off]
    call app_toast
    jmp 9f
2:  call ready
    test eax, eax
    jz 9f
    lea rdi, [rip + ai_draft]
    call sb_clear
    lea rdi, [rip + tf_msg]
    call tf_text
    lea rdi, [rip + ai_draft]
    mov rsi, rax
    call sb_push
    call ai_generate
9:  EPILOGUE

FN scm_ai_result
    PROLOGUE
    mov r12, rdi
    mov r13, rsi
    lea rdi, [rip + tf_msg]
    call tf_text
    mov rdi, rax
    mov rsi, rdx
    mov rdx, [rip + ai_draft + SB_ptr]
    mov rcx, [rip + ai_draft + SB_len]
    call str_eq
    test eax, eax
    jz 1f
    lea rdi, [rip + tf_msg]
    mov rsi, r12
    mov rdx, r13
    call tf_set
    mov dword ptr [rip + g_dirty], 1
    jmp 9f
1:  lea rdi, [rip + .Lai_edited]
    call app_toast
9:  EPILOGUE

# ai_width() -> eax: the Generate button's width, room for its wider label (Generate or Cancel) and
# the icon, so it keeps its width while running
ai_width:
    PROLOGUE
    lea rdi, [rip + .Lai_label]
    call strlen
    lea rdi, [rip + g_face_ui]
    lea rsi, [rip + .Lai_label]
    mov rdx, rax
    call text_width
    mov ebx, eax
    lea rdi, [rip + .Lai_cancel]
    call strlen
    lea rdi, [rip + g_face_ui]
    lea rsi, [rip + .Lai_cancel]
    mov rdx, rax
    call text_width
    cmp eax, ebx
    cmovl eax, ebx
    add eax, [rip + g_mt + 4*MI_ICON]
    add eax, [rip + g_mt + 4*MI_6]
    add eax, [rip + g_mt + 4*MI_24]
    EPILOGUE

# draw_ai(y): a compact button beside the message, with a stable width while running; on a row of its
# own (ai_row), as wide as the panel's content.
draw_ai:
    PROLOGUE
    mov r13d, edi
    call ai_width
    mov r12d, eax
    cmp dword ptr [rip + ai_row], 0
    je 3f
    mov r12d, [rip + in_w]
3:
    lea rdi, [rip + lbl]
    call sb_clear
    lea rsi, [rip + .Lai_label]
    cmp dword ptr [rip + g_ai_kind], 3
    jne 1f
    lea rsi, [rip + .Lai_cancel]
1:  lea rdi, [rip + lbl]
    call sb_push_cstr
    mov edi, ID_SCM_AI
    mov esi, [rip + in_x]
    mov edx, r13d
    add esi, [rip + in_w]
    mov ecx, r12d
    sub esi, ecx
    M r8d, MI_32
    mov r9d, IC_SPARK
    cmp dword ptr [rip + g_ai_kind], 3
    jne 2f
    mov r9d, IC_CLOSE
2:  call draw_button
    test eax, eax
    jz 9f
    call cmd_git_generate_message
9:  EPILOGUE

# ---------------- the changes ----------------

# sync_list(): the changes by group, made again when the status changed
sync_list:
    PROLOGUE
    mov eax, [rip + g_git_ver]
    cmp eax, [rip + list_ver]
    je 9f
    mov [rip + list_ver], eax
    lea rdi, [rip + list]
    call git_scm_list
    call expand_folders
    lea rdi, [rip + counts]
    xor eax, eax
    mov ecx, 16
    rep stosb
    xor ebx, ebx
1:  cmp rbx, [rip + list + VEC_len]
    jae 2f
    imul rax, rbx, GF_SIZE
    add rax, [rip + list + VEC_ptr]
    mov ecx, [rax + GF_group]
    lea rdx, [rip + counts]
    inc dword ptr [rdx + rcx*4]
    inc rbx
    jmp 1b
2:  # a branch without an upstream: is there a remote to publish it to
    call unpublished
    test eax, eax
    jz 3f
    call remotes_check
3:  call pull_check
    call merge_message
9:  EPILOGUE

# expand_folders(): git status gives a new folder as one row ("dir/"), which has no diff to show; the
#   row gives way to the untracked files in it (git ls-files --others, by the same ignore rules), each
#   with its changes. The last answer serves while a newer one is asked for; before the first the
#   folder stays.
expand_folders:
    PROLOGUE 16
    mov dword ptr [rip + u_extra], 0
    mov dword ptr [rsp], 0      # untracked folders found
    xor ebx, ebx
1:  cmp rbx, [rip + list + VEC_len]
    jae 2f
    imul r12, rbx, GF_SIZE
    add r12, [rip + list + VEC_ptr]
    mov rdi, r12
    call is_new_folder
    test eax, eax
    jz 11f
    mov dword ptr [rsp], 1
    # These folders may never have been opened in the explorer. Watch them before ls-files runs.
    mov rdi, [r12 + GF_path]
    call watch_untracked
11: inc rbx
    jmp 1b
2:  cmp dword ptr [rsp], 0
    je 9f
    # A project can be inside the repository: new sibling folders still affect the Git panel.
    mov rdi, [rip + g_git_root]
    call watch_worktree
    mov eax, [rip + g_git_ver]
    cmp eax, [rip + u_ver]
    je 3f
    call untracked_check
3:  cmp qword ptr [rip + ubuf + SB_len], 0
    je 9f
    mov qword ptr [rip + xlist + VEC_len], 0
    xor ebx, ebx
4:  cmp rbx, [rip + list + VEC_len]
    jae 8f
    imul r12, rbx, GF_SIZE
    add r12, [rip + list + VEC_ptr]
    inc rbx
    mov rdi, r12
    call is_new_folder
    test eax, eax
    jz 7f
    # its files, as ls-files gave them (sorted, so they stay in the status's order)
    mov r13, [r12 + GF_path]
    mov rdi, r13
    call strlen
    mov r14, rax
    mov dword ptr [rsp], 0      # files found
    mov r15, [rip + ubuf + SB_ptr]
5:  mov rax, [rip + ubuf + SB_ptr]
    add rax, [rip + ubuf + SB_len]
    cmp r15, rax
    jae 6f
    mov rdi, r15
    call strlen
    mov [rsp + 8], rax
    cmp rax, r14
    jb 51f
    mov rdi, r15
    mov rsi, r13
    mov rdx, r14
    call memeq
    test eax, eax
    jz 51f
    mov rdi, r15
    call watch_untracked
    lea rdi, [rip + xlist]
    mov esi, GF_SIZE
    call vec_push
    mov [rax + GF_path], r15
    mov dword ptr [rax + GF_code], 'U'
    mov dword ptr [rax + GF_add], -2
    mov dword ptr [rax + GF_del], 0
    mov dword ptr [rax + GF_group], GG_CHANGES
    inc dword ptr [rsp]
51: mov rax, [rsp + 8]
    lea r15, [r15 + rax + 1]
    jmp 5b
6:  mov eax, [rsp]
    test eax, eax
    jz 7f
    dec eax
    add [rip + u_extra], eax
    jmp 4b
7:  # any other row (and a folder ls-files has nothing in) as it is
    lea rdi, [rip + xlist]
    mov esi, GF_SIZE
    call vec_push
    movups xmm0, [r12]
    movups [rax], xmm0
    mov rcx, [r12 + 16]
    mov [rax + 16], rcx
    jmp 4b
8:  mov rax, [rip + list + VEC_ptr]
    mov rcx, [rip + xlist + VEC_ptr]
    mov [rip + list + VEC_ptr], rcx
    mov [rip + xlist + VEC_ptr], rax
    mov rax, [rip + list + VEC_cap]
    mov rcx, [rip + xlist + VEC_cap]
    mov [rip + list + VEC_cap], rcx
    mov [rip + xlist + VEC_cap], rax
    mov rax, [rip + xlist + VEC_len]
    mov [rip + list + VEC_len], rax
    mov qword ptr [rip + xlist + VEC_len], 0
9:  EPILOGUE

# watch_untracked(relative path): every parent below the repository root, including ancestors
#   without files directly in them. A folder row ends in '/', so its own directory is watched too.
watch_untracked:
    PROLOGUE
    mov rbx, rdi
    mov rdi, [rip + g_git_root]
    call strlen
    mov r12, rax
    mov rdi, [rip + g_git_root]
    mov rsi, rbx
    call path_join
    mov rbx, rax
    lea r13, [rax + r12]
    cmp byte ptr [r13], '/'
    jne 1f
    inc r13
1:  cmp byte ptr [r13], 0
    je 3f
    cmp byte ptr [r13], '/'
    jne 2f
    mov byte ptr [r13], 0
    mov rdi, rbx
    call watch_worktree
    mov byte ptr [r13], '/'
2:  inc r13
    jmp 1b
3:  mov rdi, rbx
    call mem_free
    EPILOGUE

# scm_changes() -> eax the changed files the panel lists (a file both staged and changed once): the
#   history's "Uncommitted changes" count, the same as the panel's when a new folder shows its files
FN scm_changes
    push rbx
    call sync_list
    mov eax, [rip + g_git_changes]
    add eax, [rip + u_extra]
    pop rbx
    ret

# is_new_folder(gf) -> 1 for an untracked folder's row ("dir/")
is_new_folder:
    push rbx
    mov rbx, rdi
    xor eax, eax
    cmp dword ptr [rbx + GF_code], 'U'
    jne 9f
    cmp dword ptr [rbx + GF_group], GG_CHANGES
    jne 9f
    mov rdi, [rbx + GF_path]
    call strlen
    test rax, rax
    jz 8f
    mov rcx, [rbx + GF_path]
    cmp byte ptr [rcx + rax - 1], '/'
    sete al
    movzx eax, al
    jmp 9f
8:  xor eax, eax
9:  pop rbx
    ret

# untracked_check(): the untracked files, for expand_folders
untracked_check:
    cmp dword ptr [rip + u_running], 0
    jne 9f
    push rbx
    mov eax, [rip + g_git_ver]
    mov [rip + u_want], eax
    lea rdi, [rip + args_untracked]
    lea rsi, [rip + on_untracked]
    xor edx, edx
    xor ecx, ecx
    xor r8d, r8d
    call git_run
    mov [rip + u_running], eax
    pop rbx
9:  ret

# on_untracked(ctx, ptr, len, status): the list is made again with them (an error leaves the folders)
on_untracked:
    push rbx
    push r12
    push r13
    mov r12, rsi
    mov r13, rdx
    mov ebx, ecx
    mov dword ptr [rip + u_running], 0
    lea rdi, [rip + ubuf]
    call sb_clear
    test ebx, ebx
    jnz 1f
    lea rdi, [rip + ubuf]
    mov rsi, r12
    mov rdx, r13
    call sb_push
1:  mov eax, [rip + u_want]
    mov [rip + u_ver], eax
    mov dword ptr [rip + list_ver], -1
    mov dword ptr [rip + g_dirty], 1
    pop r13
    pop r12
    pop rbx
    ret

# pull_check(): is pull.rebase or pull.ff set, for the pull the tooltips show (a pull asks again)
pull_check:
    cmp dword ptr [rip + pc_running], 0
    jne 9f
    push rbx
    lea rdi, [rip + args_pull_cfg]
    lea rsi, [rip + on_pull_cfg]
    xor edx, edx
    xor ecx, ecx
    xor r8d, r8d
    call git_run
    mov [rip + pc_running], eax
    pop rbx
9:  ret

# on_pull_cfg(ctx, ptr, len, status): git config finds neither key and exits 1: a pull merges
on_pull_cfg:
    mov dword ptr [rip + pc_running], 0
    xor eax, eax
    test ecx, ecx
    setnz al
    mov [rip + pull_merge], eax
    mov dword ptr [rip + g_dirty], 1
    ret

# remotes_check(): the remotes, for Publish Branch
remotes_check:
    cmp dword ptr [rip + rm_running], 0
    jne 9f
    push rbx
    lea rdi, [rip + args_remote]
    lea rsi, [rip + on_remotes]
    xor edx, edx
    xor ecx, ecx
    xor r8d, r8d
    call git_run
    mov [rip + rm_running], eax
    pop rbx
9:  ret

# on_remotes(ctx, ptr, len, status): a remote per line
on_remotes:
    push rbx
    mov dword ptr [rip + rm_running], 0
    test ecx, ecx
    jnz 1f
    mov rdi, rsi
    mov rsi, rdx
    call pick_remote
    mov dword ptr [rip + g_dirty], 1
1:  pop rbx
    ret

# pick_remote(ptr, len): origin when there is one, else the first remote, into remote
pick_remote:
    PROLOGUE
    mov r12, rdi
    lea r14, [rdi + rsi]
    mov byte ptr [rip + remote], 0
    mov rbx, r12
1:  cmp rbx, r14
    jae 8f
    mov r15, rbx
2:  cmp r15, r14
    jae 3f
    cmp byte ptr [r15], 10
    je 3f
    inc r15
    jmp 2b
3:  mov r13, r15
    sub r13, rbx                # its length
    jz 6f
    cmp r13, 255
    jae 6f
    cmp byte ptr [rip + remote], 0
    je 4f
    cmp r13, 6
    jne 6f
    mov rdi, rbx
    lea rsi, [rip + .Lorigin]
    mov edx, 6
    call memeq
    test eax, eax
    jz 6f
4:  lea rdi, [rip + remote]
    mov rsi, rbx
    mov rcx, r13
    rep movsb
    mov byte ptr [rdi], 0
6:  lea rbx, [r15 + 1]
    jmp 1b
8:  xor eax, eax
    cmp byte ptr [rip + remote], 0
    setne al
    mov [rip + has_remote], eax
    EPILOGUE

# merge_message(): during a merge its message goes into an empty message box, once
merge_message:
    PROLOGUE
    call git_merge_msg
    test rax, rax
    jnz 1f
    mov dword ptr [rip + merge_seen], 0
    EPILOGUE
1:  mov r12, rax
    mov r13, rdx
    cmp dword ptr [rip + merge_seen], 0
    jne 8f
    mov dword ptr [rip + merge_seen], 1
    cmp qword ptr [rip + tf_msg + TF_sb + SB_len], 0
    jne 8f
    # its lines but the comments
    lea rdi, [rip + tmp]
    call sb_clear
    lea rdi, [rip + tmp]
    lea rsi, [rip + empty_str]
    xor edx, edx
    call sb_push
    mov rbx, r12
    lea r14, [r12 + r13]
2:  cmp rbx, r14
    jae 5f
    mov r15, rbx
3:  cmp r15, r14
    jae 4f
    cmp byte ptr [r15], 10
    je 4f
    inc r15
    jmp 3b
4:  cmp byte ptr [rbx], '#'
    je 41f
    lea rdi, [rip + tmp]
    mov rsi, rbx
    mov rdx, r15
    sub rdx, rbx
    call sb_push
    lea rdi, [rip + tmp]
    mov esi, 10
    call sb_push_byte
41: lea rbx, [r15 + 1]
    jmp 2b
5:  # no blank lines at the end
    mov rax, [rip + tmp + SB_len]
    mov rcx, [rip + tmp + SB_ptr]
51: test rax, rax
    jz 52f
    cmp byte ptr [rcx + rax - 1], ' '
    ja 52f
    dec rax
    jmp 51b
52: lea rdi, [rip + tf_msg]
    mov rsi, rcx
    mov rdx, rax
    call tf_set
8:  mov rdi, r12
    call mem_free
    EPILOGUE

# ---------------- operations ----------------

# op_begin(op, seq): runs the steps of seq one after another
op_begin:
    PROLOGUE
    push rdi
    push rsi
    call ai_cancel_generation
    pop rsi
    pop rdi
    cmp dword ptr [rip + op], OP_NONE
    jne 9f
    cmp dword ptr [rip + g_git_on], 0
    je 9f
    mov [rip + op], edi
    mov [rip + seq], rsi
    mov byte ptr [rip + err], 0
    xor edi, edi
    xor esi, esi
    call run_step
    mov dword ptr [rip + g_dirty], 1
9:  EPILOGUE

# run_step(ptr, len): the next step; after the last the operation is done (ptr, len: that step's output)
run_step:
    PROLOGUE
    mov r12, rdi
    mov r13, rsi
    mov rax, [rip + seq]
    movzx ebx, byte ptr [rax]
    test ebx, ebx
    jnz 1f
    mov rdi, r12
    mov rsi, r13
    call op_done
    EPILOGUE
1:  # its arguments, then what the step adds; a merge as configuration, so branch.<name>.rebase wins
    lea rax, [rip + step_args]
    mov rsi, [rax + rbx*8]
    cmp ebx, S_PULL
    jne 11f
    cmp dword ptr [rip + pull_merge], 0
    je 11f
    lea rsi, [rip + args_pull_merge]
11: lea r13, [rip + argv]
2:  mov rax, [rsi]
    test rax, rax
    jz 3f
    mov [r13], rax
    add rsi, 8
    add r13, 8
    jmp 2b
3:  xor r14d, r14d              # input
    xor r15d, r15d
    cmp ebx, S_COMMIT
    je 4f
    cmp ebx, S_AMEND
    jne 5f
    call msg_blank
    test eax, eax
    jz 41f
    lea rax, [rip + .Lno_edit]
    mov [r13], rax
    add r13, 8
    jmp 8f
41: lea rax, [rip + .Ldash_f]
    mov [r13], rax
    lea rax, [rip + .Ldash]
    mov [r13 + 8], rax
    add r13, 16
4:  lea rdi, [rip + tf_msg]
    call tf_text
    mov r14, rax
    mov r15, rdx
    jmp 8f
5:  cmp ebx, S_PUBLISH
    jne 7f
    lea rax, [rip + remote]
    mov [r13], rax
    lea rax, [rip + .Lhead]
    mov [r13 + 8], rax
    add r13, 16
    jmp 8f
7:  cmp ebx, S_ADD
    je 71f
    cmp ebx, S_RESET
    je 71f
    cmp ebx, S_CHECKOUT
    je 71f
    cmp ebx, S_CLEAN
    jne 8f
71: lea rax, [rip + .Ldashdash]
    mov [r13], rax
    lea rax, [rip + op_path]
    mov [r13 + 8], rax
    add r13, 16
8:  mov qword ptr [r13], 0
    lea rdi, [rip + argv]
    lea rsi, [rip + on_step]
    xor edx, edx
    mov rcx, r14
    mov r8, r15
    # the steps whose output is read take it without git's messages
    cmp ebx, S_REMOTES
    je 81f
    cmp ebx, S_PULL_CFG
    je 81f
    call git_run_all
    jmp 82f
81: call git_run
82: test eax, eax
    jnz 9f
    lea rdi, [rip + .Le_failed]
    call fail_with
9:  EPILOGUE

# on_step(ctx, ptr, len, status): a step ended
on_step:
    PROLOGUE
    mov r12, rsi
    mov r13, rdx
    mov r14d, ecx
    cmp dword ptr [rip + op], OP_NONE
    je 9f
    mov rax, [rip + seq]
    movzx ebx, byte ptr [rax]
    cmp ebx, S_PULL_CFG
    jne 1f
    # neither pull.rebase nor pull.ff: a merge, as git did before it asked
    xor eax, eax
    test r14d, r14d
    setnz al
    mov [rip + pull_merge], eax
    xor r14d, r14d
    jmp 5f
1:  cmp ebx, S_REMOTES
    jne 5f
    test r14d, r14d
    jnz 5f
    mov rdi, r12
    mov rsi, r13
    call pick_remote
    cmp byte ptr [rip + remote], 0
    jne 5f
    lea rdi, [rip + .Lno_remote]
    call fail_with
    jmp 9f
5:  test r14d, r14d
    jz 6f
    mov rdi, r12
    mov rsi, r13
    lea rdx, [rip + err]
    call pick_error
    call failed
    jmp 9f
6:  inc qword ptr [rip + seq]
    mov rdi, r12
    mov rsi, r13
    call run_step
9:  EPILOGUE

# op_done(ptr, len): the operation went through (ptr, len: the last step's output)
op_done:
    PROLOGUE
    mov r12, rdi
    mov r13, rsi
    mov ebx, [rip + op]
    cmp ebx, OP_COMMIT
    jne 1f
    lea rdi, [rip + tf_msg]
    call tf_clear
    jmp 8f
1:  lea rax, [rip + done_toasts]
    mov r14, [rax + rbx*8]
    test r14, r14
    jz 8f
    lea rdx, [rip + .Lpull_same]
    mov ecx, 18
    cmp ebx, OP_PULL
    je 2f
    lea rdx, [rip + .Lpush_same]
    mov ecx, 21
    cmp ebx, OP_PUSH
    jne 3f
2:  mov rdi, r12
    mov rsi, r13
    call str_find
    test rax, rax
    js 3f
    lea r14, [rip + .Lt_same]
3:  mov rdi, r14
    call app_toast
8:  call op_finish
    EPILOGUE

# fail_with(cstr): the operation stops with that message
fail_with:
    push rbx
    mov rsi, rdi
    lea rdi, [rip + err]
    call cstr_copy
    call failed
    pop rbx
    ret

# failed(): the operation stopped; err says why
failed:
    push rbx
    lea rdi, [rip + err]
    call app_toast
    call op_finish
    pop rbx
    ret

# op_finish(): no operation runs; the status, and HEAD unless only the index changed
op_finish:
    push rbx
    mov ebx, [rip + op]
    mov dword ptr [rip + op], OP_NONE
    mov edi, 1
    cmp ebx, OP_INDEX
    je 1f
    mov edi, 3
1:  call git_refresh
    cmp ebx, OP_RESET
    jne 2f
    call explorer_refresh
2:
    mov dword ptr [rip + g_dirty], 1
    pop rbx
    ret

# pick_error(ptr, len, dest): what git's output says went wrong, as a line in dest
pick_error:
    PROLOGUE 32
    mov r12, rdi
    mov r13, rsi
    mov r14, rdx
    # what it means, for the common ones
    mov rdi, r12
    mov rsi, r13
    lea rdx, [rip + .Lk_rejected]
    mov ecx, 10
    call str_find
    lea rbx, [rip + .Le_rejected]
    test rax, rax
    jns .Lpe_cstr
    mov rdi, r12
    mov rsi, r13
    lea rdx, [rip + .Lk_conflict]
    mov ecx, 8
    call str_find
    test rax, rax
    js 1f
    mov rdi, r12
    mov rsi, r13
    lea rdx, [rip + .Lk_rebase]
    mov ecx, 15
    call str_find
    lea rbx, [rip + .Le_conflict]
    test rax, rax
    js .Lpe_cstr
    lea rbx, [rip + .Le_rebase]
    jmp .Lpe_cstr
1:  # the first fatal or error line, else the last line that is not a hint
    xor r15d, r15d              # start of the last line kept
    lea rax, [r12 + r13]
    mov [rsp + 8], rax          # end of the output
    mov rbx, r12
.Lpe_line:
    cmp rbx, [rsp + 8]
    jae .Lpe_last
    mov rcx, rbx
2:  cmp rcx, [rsp + 8]
    jae 3f
    cmp byte ptr [rcx], 10
    je 3f
    inc rcx
    jmp 2b
3:  mov [rsp + 16], rcx         # end of the line
    mov rdi, rbx
    mov rsi, rcx
    sub rsi, rbx
    lea rdx, [rip + .Lk_fatal]
    mov ecx, 7
    call str_starts
    test eax, eax
    jnz 4f
    mov rdi, rbx
    mov rsi, [rsp + 16]
    sub rsi, rbx
    lea rdx, [rip + .Lk_error]
    mov ecx, 7
    call str_starts
    test eax, eax
    jz 5f
4:  lea rdi, [rbx + 7]
    mov rsi, [rsp + 16]
    jmp .Lpe_copy
5:  mov rdi, rbx
    mov rsi, [rsp + 16]
    sub rsi, rbx
    lea rdx, [rip + .Lk_hint]
    mov ecx, 5
    call str_starts
    test eax, eax
    jnz 6f
    mov rcx, rbx
51: cmp rcx, [rsp + 16]
    jae 6f
    cmp byte ptr [rcx], ' '
    ja 52f
    inc rcx
    jmp 51b
52: mov r15, rbx
    mov rax, [rsp + 16]
    mov [rsp], rax
6:  mov rbx, [rsp + 16]
    inc rbx
    jmp .Lpe_line
.Lpe_last:
    lea rbx, [rip + .Le_failed]
    test r15, r15
    jz .Lpe_cstr
    mov rdi, r15
    mov rsi, [rsp]
    jmp .Lpe_copy
.Lpe_cstr:
    mov rdi, rbx
    call strlen
    mov rdi, rbx
    lea rsi, [rbx + rax]
.Lpe_copy:
    # rdi..rsi, at most 250 bytes, no blanks at the end, a capital first
    mov rcx, rsi
    sub rcx, rdi
    cmp rcx, 250
    jbe 1f
    mov ecx, 250
1:  xor eax, eax
2:  cmp rax, rcx
    jae 3f
    mov dl, [rdi + rax]
    mov [r14 + rax], dl
    inc rax
    jmp 2b
3:  test rax, rax
    jz 4f
    cmp byte ptr [r14 + rax - 1], ' '
    ja 4f
    dec rax
    jmp 3b
4:  mov byte ptr [r14 + rax], 0
    movzx eax, byte ptr [r14]
    cmp eax, 'a'
    jb 9f
    cmp eax, 'z'
    ja 9f
    sub eax, 32
    mov [r14], al
9:  EPILOGUE

# file_action(gf, seq): stage or unstage a file
file_action:
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    call ready
    test eax, eax
    jz 9f
    mov rdi, rbx
    call take_path
    test eax, eax
    jz 9f
    mov edi, OP_INDEX
    mov rsi, r12
    call op_begin
9:  EPILOGUE

# ask_discard(gf): asks before its changes go (or before an untracked file is deleted)
ask_discard:
    PROLOGUE
    mov rbx, rdi
    call ready
    test eax, eax
    jz 9f
    mov rdi, rbx
    call take_path
    test eax, eax
    jz 9f
    lea rax, [rip + seq_discard]
    lea r12, [rip + .Lq_discard]
    lea r13, [rip + .Lq_discard_text]
    lea r14, [rip + .Lb_discard]
    cmp dword ptr [rbx + GF_code], 'U'
    jne 1f
    lea rax, [rip + seq_discard_new]
    lea r12, [rip + .Lq_delete]
    lea r13, [rip + .Lq_delete_text]
    lea r14, [rip + .Lb_delete]
1:  mov [rip + confirm_seq], rax
    lea rdi, [rip + question]
    mov rsi, r12
    call cstr_copy
    mov rdi, rax
    lea rsi, [rip + op_path]
    call cstr_copy
    mov byte ptr [rax], '?'
    mov byte ptr [rax + 1], 0
    lea rdi, [rip + question]
    mov rsi, r13
    mov rdx, r14
    lea rcx, [rip + confirmed]
    call app_confirm
9:  EPILOGUE

# take_path(gf) -> 1 when its path went into op_path
take_path:
    push rbx
    mov rbx, rdi
    mov rdi, [rbx + GF_path]
    call strlen
    xor ecx, ecx
    cmp rax, 4000
    ja 1f
    lea rdi, [rip + op_path]
    mov rsi, [rbx + GF_path]
    call cstr_copy
    mov ecx, 1
1:  mov eax, ecx
    pop rbx
    ret

# ---------------- drawing ----------------

.bss
.globl g_scm_drawn
g_scm_drawn: .long 0            # source control is drawn in this frame already
.section .rodata
.Lin_sidebar: .asciz "Source control is open in the sidebar"
.text

# scm_draw(x, y, w, h): the panel right of the history, for the work tree
FN scm_draw
    PROLOGUE 32
    # the sidebar and the history may both show it: the first has it in a frame, the other says so
    cmp dword ptr [rip + g_scm_drawn], 0
    je 0f
    mov [rsp], edi
    mov [rsp + 4], esi
    mov [rsp + 8], edx
    mov [rsp + 12], ecx
    COLOR r8d, T_PANEL
    call gfx_fill
    lea rdi, [rip + g_face_small]
    mov esi, [rsp]
    mov edx, [rsp + 4]
    mov ecx, [rsp + 8]
    M r8d, MI_64
    lea r9, [rip + .Lin_sidebar]
    COLOR eax, T_MUTED
    push rax
    push rax
    call ui_text_center
    add rsp, 16
    EPILOGUE
0:  mov dword ptr [rip + g_scm_drawn], 1
    mov [rip + pan], edi
    mov [rip + pan + 4], esi
    mov [rip + pan + 8], edx
    mov [rip + pan + 12], ecx
    call sync_list
    mov dword ptr [rip + tf_msg + TF_id], ID_SCM_MSG
    call pan_args
    COLOR r8d, T_PANEL
    call gfx_fill
    call pan_args
    call ui_in
    mov [rsp], eax              # the pointer is over the panel
    # else what scrolled out of it takes no clicks (the clip only cuts the drawing)
    mov ecx, [rip + g_block]
    mov [rsp + 4], ecx
    test eax, eax
    jnz 10f
    mov dword ptr [rip + g_block], 1
    jmp 1f
10: mov eax, [rip + g_scroll_y]
    add [rip + scroll], eax
1:  mov eax, [rip + content_h]
    sub eax, [rip + pan + 12]
    jns 11f
    xor eax, eax
11: cmp [rip + scroll], eax
    jle 12f
    mov [rip + scroll], eax
12: cmp dword ptr [rip + scroll], 0
    jge 13f
    mov dword ptr [rip + scroll], 0
13: call pan_args
    call gfx_clip_push
    M eax, MI_16
    mov ecx, [rip + pan]
    add ecx, eax
    mov [rip + in_x], ecx
    mov ecx, [rip + pan + 8]
    sub ecx, eax
    sub ecx, eax
    mov [rip + in_w], ecx
    mov r13d, [rip + pan + 4]
    sub r13d, [rip + scroll]
    # the header: the branch, and Fetch, Pull and Reset All at its right
    mov edi, r13d
    call draw_header
    add r13d, [rip + g_mt + 4*MI_40]
    add r13d, [rip + g_mt + 4*MI_10]
    # The message always wraps, up to MAX_LINES visual rows high. Generate takes its side of the row,
    # unless that would leave the message narrower than the button: then it goes under the message.
    mov esi, [rip + in_w]
    mov dword ptr [rip + ai_row], 0
    cmp dword ptr [rip + cfg_commit_ai], 0
    je 20f
    call ai_width
    mov esi, [rip + in_w]
    sub esi, eax
    sub esi, [rip + g_mt + 4*MI_8]
    cmp esi, eax
    jge 20f
    mov esi, [rip + in_w]
    mov dword ptr [rip + ai_row], 1
20: mov [rsp + 8], esi
    lea rdi, [rip + tf_msg]
    call ta_layout
    mov ecx, MAX_LINES
    cmp eax, ecx
    cmova eax, ecx
    mov ecx, 3                  # three rows at least, and one under them for the hint
    cmp eax, ecx
    cmovb eax, ecx
    mov ebx, eax
    call ta_line_h
    imul ebx, eax
    add ebx, [rip + g_mt + 4*MI_12]
    call hint_h
    add ebx, eax
    mov [rsp + 12], ebx
    lea rax, [rip + .Lph]
    push rax
    push rax
    lea rdi, [rip + tf_msg]
    mov esi, [rip + in_x]
    mov edx, r13d
    mov ecx, [rsp + 24]         # field width, saved before the placeholder pushes
    mov r8d, ebx
    xor r9d, r9d
    cmp dword ptr [rip + g_focus], FOCUS_SCM
    jne 2f
    mov r9d, 1
2:  call ui_textarea
    add rsp, 16
    test eax, UB_PRESS
    jz 3f
    mov dword ptr [rip + g_focus], FOCUS_SCM
    mov dword ptr [rsp], 0
3:  # in the box's last row: how to commit, or the message's length
    lea rdi, [rip + lbl]
    call sb_clear
    lea rdi, [rip + lbl]
    lea rsi, [rip + .Lhint]
    cmp qword ptr [rip + tf_msg + TF_sb + SB_len], 0
    je 32f
    lea rsi, [rip + .Lch]
    call sb_push_cstr
    lea rdi, [rip + lbl]
    mov rsi, [rip + tf_msg + TF_sb + SB_len]
    call sb_push_u64
    jmp 33f
32: call sb_push_cstr
33: COLOR eax, T_MUTED
    push rax
    push rax
    lea rdi, [rip + g_face_mini]
    mov esi, [rip + in_x]
    add esi, [rip + g_mt + 4*MI_10]
    call hint_h
    mov ecx, eax
    mov edx, r13d
    add edx, [rsp + 16 + 12]
    sub edx, eax
    sub edx, [rip + g_mt + 4*MI_4]
    mov r8, [rip + lbl + SB_ptr]
    mov r9, [rip + lbl + SB_len]
    call ui_text_v
    add rsp, 16
    # Generate shares the message row and stays at its top as the draft grows.
    cmp dword ptr [rip + cfg_commit_ai], 0
    je 31f
    cmp dword ptr [rip + ai_row], 0
    jne 30f
    mov edi, r13d
    call draw_ai
    M eax, MI_32
    cmp ebx, eax
    cmovl ebx, eax
    jmp 31f
30: # or the row under it
    mov edi, r13d
    add edi, ebx
    add edi, [rip + g_mt + 4*MI_8]
    call draw_ai
    add ebx, [rip + g_mt + 4*MI_8]
    add ebx, [rip + g_mt + 4*MI_32]
31: add r13d, ebx
    add r13d, [rip + g_mt + 4*MI_8]
    # what is staged; Commit (or Sync Changes, Publish Branch) and Push side by side
    mov edi, r13d
    call draw_staged
    add r13d, [rip + g_mt + 4*MI_16]
    add r13d, [rip + g_mt + 4*MI_8]
    mov edi, r13d
    call draw_actions
    add r13d, eax
    add r13d, [rip + g_mt + 4*MI_10]
    mov edi, [rip + pan]
    mov esi, r13d
    mov edx, [rip + pan + 8]
    M ecx, MI_1
    COLOR r8d, T_BORDER
    call gfx_fill
    add r13d, [rip + g_mt + 4*MI_6]
    # what went wrong last
    mov edi, r13d
    call draw_error
    mov r13d, eax
    add r13d, [rip + g_mt + 4*MI_4]
    # the changes by group
    mov r14d, GG_MERGE
5:  lea rax, [rip + counts]
    cmp dword ptr [rax + r14*4], 0
    je 6f
    mov edi, r14d
    mov esi, r13d
    call draw_group
    mov r13d, eax
6:  inc r14d
    cmp r14d, GG_CHANGES
    jbe 5b
    mov eax, r13d
    add eax, [rip + scroll]
    sub eax, [rip + pan + 4]
    add eax, [rip + g_mt + 4*MI_8]
    mov [rip + content_h], eax
    call gfx_clip_pop
    mov eax, [rsp + 4]
    mov [rip + g_block], eax
    mov eax, [rip + pan + 12]
    push rax
    mov eax, [rip + content_h]
    push rax
    M ecx, MI_12
    mov edi, ID_SCM_SCROLL
    mov esi, [rip + pan]
    add esi, [rip + pan + 8]
    sub esi, ecx
    mov edx, [rip + pan + 4]
    mov r8d, [rip + pan + 12]
    lea r9, [rip + scroll]
    call ui_scrollbar
    add rsp, 16
    # a press elsewhere in the panel takes the keyboard from the message
    cmp dword ptr [rsp], 0
    je 9f
    test dword ptr [rip + g_pressed], 1 << BTN_LEFT
    jz 9f
    cmp dword ptr [rip + g_focus], FOCUS_SCM
    jne 9f
    mov dword ptr [rip + g_focus], FOCUS_EDITOR
9:  EPILOGUE

# draw_error(y) -> eax y under it: err, broken into lines at spaces (at most 4)
draw_error:
    PROLOGUE 16
    mov r13d, edi
    lea rbx, [rip + err]
    mov rdi, rbx
    call strlen
    mov r12, rax
    xor r15d, r15d              # lines
1:  test r12, r12
    jz 8f
    cmp r15d, 4
    jae 8f
    # what fits, up to its last space when the rest goes on
    lea rdi, [rip + g_face_small]
    mov rsi, rbx
    mov rdx, r12
    mov ecx, [rip + in_w]
    call text_fit
    mov r14, rax
    cmp r14, r12
    jae 4f
    mov rcx, r14
2:  test rcx, rcx
    jz 4f
    cmp byte ptr [rbx + rcx], ' '
    je 3f
    dec rcx
    jmp 2b
3:  mov r14, rcx
4:  test r14, r14
    jnz 5f
    mov r14, r12
5:  COLOR eax, T_ERROR
    push rax
    push rax
    lea rdi, [rip + g_face_small]
    mov esi, [rip + in_x]
    mov edx, r13d
    M ecx, MI_20
    mov r8, rbx
    mov r9, r14
    call ui_text_v
    add rsp, 16
    add r13d, [rip + g_mt + 4*MI_20]
    inc r15d
    add rbx, r14
    sub r12, r14
6:  test r12, r12
    jz 1b
    cmp byte ptr [rbx], ' '
    jne 1b
    inc rbx
    dec r12
    jmp 6b
8:  test r15d, r15d
    jz 9f
    add r13d, [rip + g_mt + 4*MI_4]
9:  mov eax, r13d
    EPILOGUE

# pan_args() -> edi, esi, edx, ecx: the panel
pan_args:
    mov edi, [rip + pan]
    mov esi, [rip + pan + 4]
    mov edx, [rip + pan + 8]
    mov ecx, [rip + pan + 12]
    ret

# draw_header(y): the branch and what it has ahead and behind (or why it has no such count), and at
#   the right Fetch, Pull and Reset All; a line under it
draw_header:
    PROLOGUE 16
    mov r13d, edi
    M r15d, MI_40
    mov edi, [rip + pan]
    lea esi, [r13 + r15]
    sub esi, [rip + g_mt + 4*MI_1]
    mov edx, [rip + pan + 8]
    M ecx, MI_1
    COLOR r8d, T_BORDER
    call gfx_fill
    # the buttons, from the right
    mov r12d, [rip + in_x]
    add r12d, [rip + in_w]
    sub r12d, [rip + g_mt + 4*MI_24]
    add r13d, [rip + g_mt + 4*MI_6]
    mov edi, ID_SCM_RESET
    mov esi, IC_DISCARD
    call group_button
    test eax, eax
    jz 1f
    call cmd_git_reset_all
1:  sub r12d, [rip + g_mt + 4*MI_24]
    sub r12d, [rip + g_mt + 4*MI_2]
    mov edi, ID_SCM_PULL
    mov esi, IC_DOWNLOAD
    call group_button
    test eax, eax
    jz 2f
    call cmd_git_pull
2:  sub r12d, [rip + g_mt + 4*MI_24]
    sub r12d, [rip + g_mt + 4*MI_2]
    mov edi, ID_SCM_PULL + 2
    mov esi, IC_REFRESH
    call group_button
    test eax, eax
    jz 3f
    call cmd_git_fetch
3:  sub r13d, [rip + g_mt + 4*MI_6]
    # the branch, in what they leave
    mov edi, [rip + in_x]
    mov esi, r13d
    mov edx, r12d
    sub edx, edi
    sub edx, [rip + g_mt + 4*MI_4]
    mov ecx, r15d
    call gfx_clip_push
    mov edi, IC_BRANCH
    mov esi, [rip + in_x]
    mov edx, r13d
    M ecx, MI_ICON
    mov r8d, r15d
    COLOR r9d, T_MUTED
    call ui_icon_center
    mov r12d, [rip + in_x]
    add r12d, [rip + g_mt + 4*MI_ICON]
    add r12d, [rip + g_mt + 4*MI_6]
    lea r8, [rip + g_branch]
    cmp byte ptr [r8], 0
    jne 4f
    lea r8, [rip + .Lhead]
4:  lea rdi, [rip + g_face_ui]
    mov esi, r12d
    mov edx, r13d
    mov ecx, r15d
    COLOR r9d, T_FG
    call ui_text_c
    add eax, [rip + g_mt + 4*MI_8]
    mov r12d, eax
    lea r8, [rip + .Lh_unborn]
    cmp dword ptr [rip + g_git_head], HD_UNBORN
    je 5f
    lea r8, [rip + .Lh_detached]
    cmp dword ptr [rip + g_git_head], HD_DETACHED
    je 5f
    lea r8, [rip + .Lh_unpublished]
    cmp byte ptr [rip + g_git_upstream], 0
    jne 6f
5:  lea rdi, [rip + g_face_mini]
    mov esi, r12d
    mov edx, r13d
    mov ecx, r15d
    COLOR r9d, T_MUTED
    call ui_text_c
    jmp 7f
6:  lea rsi, [rip + .Lup]
    mov edx, [rip + g_git_ahead]
    call hdr_badge
    lea rsi, [rip + .Ldown]
    mov edx, [rip + g_git_behind]
    call hdr_badge
7:  call gfx_clip_pop
    EPILOGUE
# hdr_badge(arrow cstr, count): the count in a small frame at r12d on the header at r13d, when it is
#   not 0; r12d moves past it
hdr_badge:
    test edx, edx
    jz 9f
    push rbx
    push r14
    sub rsp, 8
    mov rbx, rsi
    mov r14d, edx
    lea rdi, [rip + lbl]
    call sb_clear
    lea rdi, [rip + lbl]
    mov rsi, rbx
    call sb_push_cstr
    lea rdi, [rip + lbl]
    mov esi, r14d
    call sb_push_u64
    lea rdi, [rip + g_face_mini]
    mov rsi, [rip + lbl + SB_ptr]
    mov rdx, [rip + lbl + SB_len]
    call text_width
    add eax, [rip + g_mt + 4*MI_8]
    mov ebx, eax
    COLOR eax, T_PANEL
    push rax
    push rax
    mov edi, r12d
    M ecx, MI_16
    mov esi, r15d
    sub esi, ecx
    sar esi, 1
    add esi, r13d
    mov edx, ebx
    M r8d, MI_4
    COLOR r9d, T_BORDER
    call gfx_frame
    COLOR eax, T_MUTED
    mov [rsp], rax
    lea rdi, [rip + g_face_mini]
    mov esi, r12d
    add esi, [rip + g_mt + 4*MI_4]
    mov edx, r13d
    mov ecx, r15d
    mov r8, [rip + lbl + SB_ptr]
    mov r9, [rip + lbl + SB_len]
    call ui_text_v
    add rsp, 16
    add r12d, ebx
    add r12d, [rip + g_mt + 4*MI_3]
    add rsp, 8
    pop r14
    pop rbx
9:  ret

# hint_h() -> eax the height of the message box's last row: the small text's, MI_16 at least
hint_h:
    mov eax, [rip + g_face_mini + FACE_ascent]
    add eax, [rip + g_face_mini + FACE_descent]
    add eax, [rip + g_mt + 4*MI_2]
    mov ecx, [rip + g_mt + 4*MI_16]
    cmp eax, ecx
    cmovl eax, ecx
    ret

# draw_staged(y): a dot and how many files the commit takes
draw_staged:
    PROLOGUE
    mov r13d, edi
    M r15d, MI_16
    mov ebx, [rip + counts + 4*GG_STAGED]
    COLOR r9d, T_MUTED
    test ebx, ebx
    jz 1f
    COLOR r9d, T_FG
1:  M edx, MI_6
    mov edi, [rip + in_x]
    mov esi, r15d
    sub esi, edx
    sar esi, 1
    add esi, r13d
    mov ecx, edx
    mov r8d, edx
    sar r8d, 1
    call gfx_round_rect
    lea rdi, [rip + lbl]
    call sb_clear
    lea rdi, [rip + lbl]
    lea rsi, [rip + .Lst_none]
    test ebx, ebx
    jz 3f
    mov esi, ebx
    call sb_push_u64
    lea rdi, [rip + lbl]
    lea rsi, [rip + .Lst_file]
    cmp ebx, 1
    je 3f
    lea rsi, [rip + .Lst_files]
3:  call sb_push_cstr
    COLOR eax, T_FG
    push rax
    push rax
    lea rdi, [rip + g_face_mini]
    mov esi, [rip + in_x]
    add esi, [rip + g_mt + 4*MI_12]
    mov edx, r13d
    mov ecx, r15d
    mov r8, [rip + lbl + SB_ptr]
    mov r9, [rip + lbl + SB_len]
    call ui_text_v
    add rsp, 16
    EPILOGUE

# draw_actions(y) -> eax their height: the main button and Push, each half the width; a label wider
#   than its half takes two lines, and both buttons are that high
draw_actions:
    PROLOGUE 16
    mov r13d, edi
    mov eax, [rip + in_w]
    mov [rsp], eax
    sub eax, [rip + g_mt + 4*MI_6]
    sar eax, 1
    mov r14d, eax
    M eax, MI_28
    mov [rip + act_h], eax
    xor edi, edi
    call main_label
    call lbl_split
    test rdx, rdx
    js 0f
    add ecx, [rip + g_mt + 4*MI_12]
    cmp ecx, r14d
    jg 1f
0:  call push_label
    call lbl_split
    test rdx, rdx
    js 2f
    add ecx, [rip + g_mt + 4*MI_12]
    cmp ecx, r14d
    jle 2f
1:  mov eax, [rip + g_face_ui + FACE_ascent]
    add eax, [rip + g_face_ui + FACE_descent]
    add eax, eax
    add eax, [rip + g_mt + 4*MI_8]
    cmp eax, [rip + act_h]
    jle 2f
    mov [rip + act_h], eax
2:  mov eax, r14d
    mov [rip + in_w], eax       # draw_main fills the content's width: half of it here
    mov edi, r13d
    call draw_main
    mov eax, [rsp]
    mov [rip + in_w], eax
    call push_label
    mov edi, ID_SCM_PULL + 1
    mov esi, [rip + in_x]
    add esi, [rsp]
    sub esi, r14d
    mov edx, r13d
    mov ecx, r14d
    mov r8d, [rip + act_h]
    mov r9d, -1
    call draw_button
    test eax, eax
    jz 9f
    call cmd_git_push
9:  mov eax, [rip + act_h]
    EPILOGUE

# push_label(): Push and what it has to push, into lbl
push_label:
    push rbx
    lea rdi, [rip + lbl]
    call sb_clear
    lea rdi, [rip + lbl]
    lea rsi, [rip + .Lr_push]
    call sb_push_cstr
    lea rsi, [rip + empty_str]
    mov edx, [rip + g_git_ahead]
    call push_count
    pop rbx
    ret

# main_label(idle) -> eax MB_*: the main button's label into lbl: what runs (unless idle), or what it does
main_label:
    push rbx
    push r12
    push r13
    mov r12d, edi
    call main_button
    mov ebx, eax
    lea rdi, [rip + lbl]
    call sb_clear
    test r12d, r12d
    jnz 1f
    mov eax, [rip + op]
    cmp eax, OP_NONE
    je 1f
    cmp eax, OP_INDEX
    je 1f
    lea rcx, [rip + busy_labels]
    mov rsi, [rcx + rax*8]
    lea rdi, [rip + lbl]
    call sb_push_cstr
    jmp 3f
1:  lea rcx, [rip + main_labels]
    mov rsi, [rcx + rbx*8]
    lea rdi, [rip + lbl]
    call sb_push_cstr
    cmp ebx, MB_SYNC
    jne 3f
    # Sync Changes 2↓ 1↑
    lea rsi, [rip + .Ldown]
    mov edx, [rip + g_git_behind]
    call push_count
    lea rsi, [rip + .Lup]
    mov edx, [rip + g_git_ahead]
    call push_count
3:  mov eax, ebx
    pop r13
    pop r12
    pop rbx
    ret

# lbl_split() -> eax the width lbl needs in two lines (in one, with no space to break it at), rdx the
#   space it breaks at (-1: one line), ecx its width in one line
lbl_split:
    PROLOGUE 16
    lea rdi, [rip + g_face_ui]
    mov rsi, [rip + lbl + SB_ptr]
    mov rdx, [rip + lbl + SB_len]
    call text_width
    mov [rsp], eax
    mov r12d, eax               # the least so far
    mov r13, -1
    xor ebx, ebx
1:  cmp rbx, [rip + lbl + SB_len]
    jae 4f
    mov rax, [rip + lbl + SB_ptr]
    cmp byte ptr [rax + rbx], ' '
    jne 3f
    lea rdi, [rip + g_face_ui]
    mov rsi, rax
    mov rdx, rbx
    call text_width
    mov r14d, eax
    lea rdi, [rip + g_face_ui]
    mov rsi, [rip + lbl + SB_ptr]
    lea rsi, [rsi + rbx + 1]
    mov rdx, [rip + lbl + SB_len]
    sub rdx, rbx
    dec rdx
    call text_width
    cmp eax, r14d
    cmovl eax, r14d
    cmp eax, r12d
    jge 3f
    mov r12d, eax
    mov r13, rbx
3:  inc rbx
    jmp 1b
4:  mov eax, r12d
    mov rdx, r13
    mov ecx, [rsp]
    EPILOGUE

# scm_least_width() -> eax the panel's least width: under it the label of the main button or of Push
#   would not fit its half in two lines, or Generate its row. What a running command names in the
#   button does not count (the panel would fold under it): such a label is cut at the button's edge.
FN scm_least_width
    PROLOGUE
    mov edi, 1
    call main_label
    call lbl_split
    mov r12d, eax
    call push_label
    call lbl_split
    cmp eax, r12d
    cmovg r12d, eax
    add r12d, [rip + g_mt + 4*MI_12]
    lea eax, [r12 + r12 + 1]
    add eax, [rip + g_mt + 4*MI_6]
    add eax, [rip + g_mt + 4*MI_32]
    mov r12d, eax
    cmp dword ptr [rip + cfg_commit_ai], 0
    je 9f
    call ai_width
    add eax, [rip + g_mt + 4*MI_32]
    cmp eax, r12d
    cmovg r12d, eax
9:  mov eax, r12d
    EPILOGUE

# checkbox(x, y, h, checked, hovered): a small box in the row at y, filled and ticked when checked
checkbox:
    PROLOGUE
    mov r12d, edi
    M r14d, MI_14
    mov r13d, edx
    sub r13d, r14d
    sar r13d, 1
    add r13d, esi
    mov ebx, r8d
    test ecx, ecx
    jz 2f
    mov edi, r12d
    mov esi, r13d
    mov edx, r14d
    mov ecx, r14d
    M r8d, MI_3
    COLOR r9d, T_ACCENT
    call gfx_round_rect
    M eax, MI_1
    lea esi, [r12 + rax]
    lea edx, [r13 + rax]
    mov ecx, r14d
    sub ecx, eax
    sub ecx, eax
    mov edi, IC_CHECK
    COLOR r8d, T_ACCENT_FG
    call icon_draw
    EPILOGUE
2:  COLOR edi, T_PANEL
    COLOR esi, T_FG
    mov edx, 80
    test ebx, ebx
    jz 3f
    mov edx, 170
3:  call color_mix
    mov r9d, eax
    COLOR eax, T_PANEL
    push rax
    push rax
    mov edi, r12d
    mov esi, r13d
    mov edx, r14d
    mov ecx, r14d
    M r8d, MI_3
    call gfx_frame
    add rsp, 16
    EPILOGUE

# main_button() -> MB_*: what the button under the message does
main_button:
    mov eax, MB_COMMIT
    cmp dword ptr [rip + counts + 4*GG_STAGED], 0
    jne 9f
    cmp dword ptr [rip + counts + 4*GG_MERGE], 0
    jne 9f
    mov eax, MB_COMMIT_ALL
    cmp dword ptr [rip + counts + 4*GG_CHANGES], 0
    jne 9f
    mov eax, MB_NONE
    cmp dword ptr [rip + g_git_head], HD_BRANCH
    jne 9f
    cmp byte ptr [rip + g_git_upstream], 0
    je 1f
    mov ecx, [rip + g_git_ahead]
    or ecx, [rip + g_git_behind]
    jz 9f
    mov eax, MB_SYNC
    ret
1:  cmp dword ptr [rip + has_remote], 0
    je 9f
    mov eax, MB_PUBLISH
9:  ret

# draw_main(y): the button under the message
draw_main:
    PROLOGUE 16
    mov r13d, edi
    mov r15d, [rip + act_h]
    xor edi, edi
    call main_label
    mov ebx, eax
3:  # it takes clicks with nothing running and something to do
    xor eax, eax
    cmp dword ptr [rip + op], OP_NONE
    jne 4f
    cmp ebx, MB_NONE
    je 4f
    mov edi, ID_SCM_MAIN
    mov esi, [rip + in_x]
    mov edx, r13d
    mov ecx, [rip + in_w]
    mov r8d, r15d
    call ui_btn
    mov r9d, eax
    mov edi, ID_SCM_MAIN
    mov esi, [rip + in_x]
    mov edx, r13d
    mov ecx, [rip + in_w]
    mov r8d, r15d
    call note_tip
    or eax, ENABLED
4:  mov [rsp], eax
    COLOR r12d, T_ACCENT
    COLOR r14d, T_ACCENT_FG
    test eax, ENABLED
    jnz 5f
    COLOR edi, T_PANEL
    mov esi, r12d
    mov edx, 110
    call color_mix
    mov r12d, eax
    COLOR edi, T_PANEL
    mov esi, r14d
    mov edx, 150
    call color_mix
    mov r14d, eax
    jmp 6f
5:  test dword ptr [rsp], UB_HOVER
    jz 6f
    mov edi, r12d
    mov esi, r14d
    mov edx, 36
    call color_mix
    mov r12d, eax
6:  mov edi, [rip + in_x]
    mov esi, r13d
    mov edx, [rip + in_w]
    mov ecx, r15d
    M r8d, MI_RADIUS
    mov r9d, r12d
    call gfx_round_rect
    mov r8d, -1
    mov edi, [rip + in_x]
    mov esi, r13d
    mov edx, [rip + in_w]
    mov ecx, r15d
    mov r9d, r14d
    call center_label
    test dword ptr [rsp], UB_CLICK
    jz 9f
    cmp ebx, MB_SYNC
    jne 7f
    call cmd_git_sync
    jmp 9f
7:  cmp ebx, MB_PUBLISH
    jne 8f
    call cmd_git_push
    jmp 9f
8:  call cmd_git_commit
9:  EPILOGUE

# push_count(arrow cstr, count): " 2↓" onto lbl when count is not 0
push_count:
    test edx, edx
    jz 9f
    push rbx
    push r12
    push r13
    mov r12, rsi
    mov r13d, edx
    lea rdi, [rip + lbl]
    mov esi, ' '
    call sb_push_byte
    lea rdi, [rip + lbl]
    mov esi, r13d
    call sb_push_u64
    lea rdi, [rip + lbl]
    mov rsi, r12
    call sb_push_cstr
    pop r13
    pop r12
    pop rbx
9:  ret

# draw_button(id, x, y, w, h, icon) -> 1 when clicked: a button with the icon and the label in lbl, taking
#   clicks while no operation runs
draw_button:
    PROLOGUE 32
    mov [rsp], edi
    mov [rsp + 4], r9d
    mov r12d, esi
    mov r13d, edx
    mov r14d, ecx
    mov r15d, r8d
    xor eax, eax
    cmp dword ptr [rip + op], OP_NONE
    jne 1f
    mov edi, [rsp]
    mov esi, r12d
    mov edx, r13d
    mov ecx, r14d
    mov r8d, r15d
    call ui_btn
    mov r9d, eax
    mov edi, [rsp]
    mov esi, r12d
    mov edx, r13d
    mov ecx, r14d
    mov r8d, r15d
    call note_tip
    or eax, ENABLED
1:  mov ebx, eax
    COLOR eax, T_PANEL
    test ebx, UB_HOVER
    jz 2f
    COLOR eax, T_HOVER
2:  push rax
    push rax
    mov edi, r12d
    mov esi, r13d
    mov edx, r14d
    mov ecx, r15d
    M r8d, MI_RADIUS
    COLOR r9d, T_BORDER
    call gfx_frame
    add rsp, 16
    COLOR r9d, T_FG
    test ebx, ENABLED
    jnz 3f
    COLOR r9d, T_MUTED
3:  mov edi, r12d
    mov esi, r13d
    mov edx, r14d
    mov ecx, r15d
    mov r8d, [rsp + 4]
    call center_label
    mov eax, ebx
    and eax, UB_CLICK
    shr eax, 2
    EPILOGUE

# line_center(x, y, w, ptr, len, argb): a line of a label, centered in w, in the row at y
line_center:
    PROLOGUE 16
    mov r12d, edi
    mov r13d, esi
    mov r14d, edx
    mov r15, rcx
    mov rbx, r8
    mov [rsp], r9d
    lea rdi, [rip + g_face_ui]
    mov rsi, r15
    mov rdx, rbx
    call text_width
    sub r14d, eax
    sar r14d, 1
    add r12d, r14d
    mov eax, [rsp]
    push rax
    push rax
    lea rdi, [rip + g_face_ui]
    mov esi, r12d
    mov edx, r13d
    mov ecx, [rip + g_face_ui + FACE_ascent]
    add ecx, [rip + g_face_ui + FACE_descent]
    mov r8, r15
    mov r9, rbx
    call ui_text_v
    add rsp, 16
    EPILOGUE

# center_label(x, y, w, h, icon or -1, argb): the icon and the text in lbl, centered in the box; without
#   an icon, a label wider than the box breaks into two lines at a space
center_label:
    PROLOGUE 32
    mov [rsp], edi
    mov [rsp + 4], esi
    mov [rsp + 8], edx
    mov [rsp + 12], ecx
    mov [rsp + 16], r8d
    mov [rsp + 20], r9d
    call gfx_clip_push          # a label no break fits is cut at the box
    cmp dword ptr [rsp + 16], 0
    jge 0f
    # wider than the box, and a space to break it at: two lines
    call lbl_split
    test rdx, rdx
    js 0f
    add ecx, [rip + g_mt + 4*MI_12]
    cmp ecx, [rsp + 8]
    jle 0f
    mov rbx, rdx
    mov r12d, [rip + g_face_ui + FACE_ascent]
    add r12d, [rip + g_face_ui + FACE_descent]
    mov r13d, [rsp + 12]
    sub r13d, r12d
    sub r13d, r12d
    sar r13d, 1
    add r13d, [rsp + 4]
    mov edi, [rsp]
    mov esi, r13d
    mov edx, [rsp + 8]
    mov rcx, [rip + lbl + SB_ptr]
    mov r8, rbx
    mov r9d, [rsp + 20]
    call line_center
    mov edi, [rsp]
    lea esi, [r13 + r12]
    mov edx, [rsp + 8]
    mov rcx, [rip + lbl + SB_ptr]
    lea rcx, [rcx + rbx + 1]
    mov r8, [rip + lbl + SB_len]
    sub r8, rbx
    dec r8
    mov r9d, [rsp + 20]
    call line_center
    jmp 9f
0:  lea rdi, [rip + g_face_ui]
    mov rsi, [rip + lbl + SB_ptr]
    mov rdx, [rip + lbl + SB_len]
    call text_width
    mov ebx, eax
    cmp dword ptr [rsp + 16], 0
    jl 1f
    add ebx, [rip + g_mt + 4*MI_ICON]
    add ebx, [rip + g_mt + 4*MI_6]
1:  mov r12d, [rsp + 8]
    sub r12d, ebx
    sar r12d, 1
    add r12d, [rsp]
    cmp dword ptr [rsp + 16], 0
    jl 2f
    mov edi, [rsp + 16]
    mov esi, r12d
    mov edx, [rsp + 4]
    M ecx, MI_ICON
    mov r8d, [rsp + 12]
    mov r9d, [rsp + 20]
    call ui_icon_center
    add r12d, [rip + g_mt + 4*MI_ICON]
    add r12d, [rip + g_mt + 4*MI_6]
2:  mov eax, [rsp + 20]
    push rax
    push rax
    lea rdi, [rip + g_face_ui]
    mov esi, r12d
    mov edx, [rsp + 16 + 4]
    mov ecx, [rsp + 16 + 12]
    mov r8, [rip + lbl + SB_ptr]
    mov r9, [rip + lbl + SB_len]
    call ui_text_v
    add rsp, 16
9:  call gfx_clip_pop
    EPILOGUE

# draw_group(group, y) -> eax y under it: its title and count, "All" with a box that stages or unstages
#   the whole group, then its files
draw_group:
    PROLOGUE 48
    mov ebx, edi
    mov r13d, esi
    M r15d, MI_28
    lea rax, [rip + group_titles]
    mov r8, [rax + rbx*8]
    lea rdi, [rip + g_face_mini]
    mov esi, [rip + in_x]
    mov edx, r13d
    mov ecx, r15d
    COLOR r9d, T_MUTED
    call ui_text_c
    add eax, [rip + g_mt + 4*MI_6]
    mov r12d, eax
    # the count, in a round frame
    lea rax, [rip + counts]
    mov esi, [rax + rbx*4]
    lea rdi, [rsp + 16]
    call fmt_u64
    mov byte ptr [rsp + 16 + rax], 0
    mov rdx, rax
    lea rdi, [rip + g_face_mini]
    lea rsi, [rsp + 16]
    call text_width
    add eax, [rip + g_mt + 4*MI_8]
    M ecx, MI_16
    cmp eax, ecx
    cmovl eax, ecx
    mov [rsp + 8], eax
    COLOR eax, T_PANEL
    push rax
    push rax
    mov edi, r12d
    M ecx, MI_16
    mov esi, r15d
    sub esi, ecx
    sar esi, 1
    add esi, r13d
    mov edx, [rsp + 16 + 8]
    mov r8d, ecx
    sar r8d, 1
    COLOR r9d, T_BORDER
    call gfx_frame
    COLOR eax, T_MUTED
    mov [rsp], rax
    lea rdi, [rip + g_face_mini]
    mov esi, r12d
    mov edx, r13d
    mov ecx, [rsp + 16 + 8]
    mov r8d, r15d
    lea r9, [rsp + 16 + 16]
    call ui_text_center
    add rsp, 16
    cmp ebx, GG_MERGE
    je 3f
    # "All" and its box at the right
    mov eax, [rip + in_x]
    add eax, [rip + in_w]
    sub eax, [rip + g_mt + 4*MI_14]
    mov [rsp], eax              # the box
    lea rdi, [rip + g_face_mini]
    lea rsi, [rip + .Lall]
    mov edx, 3
    call text_width
    mov ecx, [rsp]
    sub ecx, eax
    sub ecx, [rip + g_mt + 4*MI_10]
    mov [rsp + 4], ecx          # where the button starts
    lea edi, [rbx*4 + ID_SCM_GROUP]
    mov esi, ecx
    mov edx, r13d
    mov ecx, [rip + in_x]
    add ecx, [rip + in_w]
    sub ecx, esi
    mov r8d, r15d
    call ui_btn
    mov r9d, eax
    lea edi, [rbx*4 + ID_SCM_GROUP]
    mov esi, [rsp + 4]
    mov edx, r13d
    mov ecx, [rip + in_x]
    add ecx, [rip + in_w]
    sub ecx, esi
    mov r8d, r15d
    call note_tip
    mov r14d, eax
    lea rdi, [rip + g_face_mini]
    mov esi, [rsp + 4]
    add esi, [rip + g_mt + 4*MI_4]
    mov edx, r13d
    mov ecx, r15d
    lea r8, [rip + .Lall]
    COLOR r9d, T_MUTED
    test r14d, UB_HOVER
    jz 1f
    COLOR r9d, T_FG
1:  call ui_text_c
    mov edi, [rsp]
    mov esi, r13d
    mov edx, r15d
    xor ecx, ecx
    cmp ebx, GG_STAGED
    sete cl
    mov r8d, r14d
    and r8d, UB_HOVER
    call checkbox
    test r14d, UB_CLICK
    jz 3f
    cmp ebx, GG_STAGED
    jne 2f
    call cmd_git_unstage_all
    jmp 3f
2:  call cmd_git_stage_all
3:  add r13d, r15d
    # its files; rows out of sight only take their height
    xor r14d, r14d
.Ldg_file:
    cmp r14, [rip + list + VEC_len]
    jae .Ldg_done
    imul r12, r14, GF_SIZE
    add r12, [rip + list + VEC_ptr]
    cmp [r12 + GF_group], ebx
    jne .Ldg_next
    mov eax, [rip + pan + 4]
    add eax, [rip + pan + 12]
    cmp r13d, eax
    jge .Ldg_row
    mov eax, r13d
    add eax, r15d
    cmp eax, [rip + pan + 4]
    jle .Ldg_row
    mov edi, r14d
    mov rsi, r12
    mov edx, r13d
    call draw_file
.Ldg_row:
    add r13d, r15d
.Ldg_next:
    inc r14
    jmp .Ldg_file
.Ldg_done:
    add r13d, [rip + g_mt + 4*MI_8]
    mov eax, r13d
    EPILOGUE
# group_button(id, icon) -> 1 when clicked: an icon button at r12d on the row at r13d
group_button:
    push rbx
    mov ebx, edi
    mov r9d, esi
    mov esi, r12d
    mov edx, r13d
    add edx, [rip + g_mt + 4*MI_2]
    M ecx, MI_24
    mov r8d, ecx
    call ui_icon_btn
    mov r9d, eax
    mov edi, ebx
    mov esi, r12d
    mov edx, r13d
    add edx, [rip + g_mt + 4*MI_2]
    M ecx, MI_24
    mov r8d, ecx
    call note_tip
    and eax, UB_CLICK
    shr eax, 2
    pop rbx
    ret

# draw_file(index, gf, y): a changed file: a mark in its status' color, its icon, its name and then
#   its folder, and a box that stages or unstages it; hovered, one not staged can be discarded. A
#   click on the row shows its changes
draw_file:
    PROLOGUE 64
    mov ebx, edi
    mov r12, rsi
    mov r13d, edx
    M r15d, MI_28
    lea edi, [rbx*4 + ID_SCM_FILE]
    mov esi, [rip + pan]
    mov edx, r13d
    mov ecx, [rip + pan + 8]
    sub ecx, [rip + g_mt + 4*MI_12]
    mov r8d, r15d
    call ui_btn
    mov r14d, eax
    test eax, UB_HOVER
    jz 1f
    M eax, MI_6
    mov edi, [rip + pan]
    add edi, eax
    mov esi, r13d
    mov edx, [rip + pan + 8]
    sub edx, eax
    sub edx, eax
    mov ecx, r15d
    M r8d, MI_RADIUS
    COLOR r9d, T_HOVER
    call gfx_round_rect
1:  # the mark
    mov edi, [r12 + GF_code]
    call git_code_color
    mov r9d, eax
    M eax, MI_5
    mov edi, [rip + pan]
    add edi, [rip + g_mt + 4*MI_6]
    lea esi, [r13 + rax]
    M edx, MI_2
    mov ecx, r15d
    sub ecx, eax
    sub ecx, eax
    M r8d, MI_1
    call gfx_round_rect
    # the name, and the folder before it; a new folder's row ("dir/") is all name
    mov rdi, [r12 + GF_path]
    call strlen
    mov [rsp + 16], rax
    mov rdi, [r12 + GF_path]
    mov rsi, rax
    call path_basename
    mov qword ptr [rsp + 40], 0 # the folder's length
    test rdx, rdx
    jnz 11f
    mov rax, [r12 + GF_path]
    mov [rsp + 24], rax
    mov rax, [rsp + 16]
    mov [rsp + 32], rax
    mov edi, IC_FOLDER
    COLOR r8d, T_ACCENT
    jmp 13f
11: mov [rsp + 24], rax
    mov [rsp + 32], rdx
    sub rax, [r12 + GF_path]
    jz 12f
    dec rax
    mov [rsp + 40], rax
12: mov rdi, [rsp + 24]
    call file_icon
    mov edi, eax
    lea rcx, [rip + g_theme]
    mov r8d, [rcx + rdx*4]
13: mov esi, [rip + in_x]
    M ecx, MI_16
    mov edx, r15d
    sub edx, ecx
    sar edx, 1
    add edx, r13d
    call icon_draw
    # the box, at the right
    mov eax, [rip + in_x]
    add eax, [rip + in_w]
    sub eax, [rip + g_mt + 4*MI_14]
    mov [rsp + 8], eax
    lea edi, [rbx*4 + ID_SCM_FILE + 1]
    mov esi, eax
    sub esi, [rip + g_mt + 4*MI_5]
    mov edx, r13d
    add edx, [rip + g_mt + 4*MI_2]
    M ecx, MI_24
    mov r8d, ecx
    call ui_btn
    mov r9d, eax
    lea edi, [rbx*4 + ID_SCM_FILE + 1]
    mov esi, [rsp + 8]
    sub esi, [rip + g_mt + 4*MI_5]
    mov edx, r13d
    add edx, [rip + g_mt + 4*MI_2]
    M ecx, MI_24
    mov r8d, ecx
    call note_tip
    mov [rsp + 12], eax
    mov edi, [rsp + 8]
    mov esi, r13d
    mov edx, r15d
    xor ecx, ecx
    cmp dword ptr [r12 + GF_group], GG_STAGED
    sete cl
    mov r8d, eax
    and r8d, UB_HOVER
    call checkbox
    test dword ptr [rsp + 12], UB_CLICK
    jz 3f
    mov rdi, r12
    lea rsi, [rip + seq_stage]
    cmp dword ptr [r12 + GF_group], GG_STAGED
    jne 2f
    lea rsi, [rip + seq_unstage]
2:  call file_action
3:  mov eax, [rip + g_mt + 4*MI_8]
    sub [rsp + 8], eax          # right of the text
    test r14d, UB_HOVER
    jz 5f
    cmp dword ptr [r12 + GF_group], GG_CHANGES
    jne 5f
    mov eax, [rip + g_mt + 4*MI_24]
    sub [rsp + 8], eax
    lea edi, [rbx*4 + ID_SCM_FILE + 2]
    mov esi, [rsp + 8]
    mov r9d, IC_DISCARD
    call file_button
    test eax, eax
    jz 4f
    mov rdi, r12
    call ask_discard
4:  mov eax, [rip + g_mt + 4*MI_4]
    sub [rsp + 8], eax
5:  mov eax, [rip + in_x]
    add eax, [rip + g_mt + 4*MI_16]
    add eax, [rip + g_mt + 4*MI_8]
    mov [rsp + 4], eax          # the text's x
    mov ecx, [rsp + 8]
    sub ecx, eax
    jle 6f
    mov [rsp + 48], ecx         # the room for the name
    cmp qword ptr [rsp + 40], 0
    je 51f
    imul ecx, ecx, 58           # with a folder after it, a little over half
    mov eax, ecx
    cdq
    mov ecx, 100
    idiv ecx
    mov [rsp + 48], eax
51: lea rdi, [rip + g_face_small]
    mov rsi, [rsp + 24]
    mov rdx, [rsp + 32]
    call text_width
    cmp eax, [rsp + 48]
    cmovg eax, [rsp + 48]
    mov [rsp + 52], eax         # the name's width
    mov eax, [rsp + 48]
    push rax
    COLOR eax, T_FG
    push rax
    lea rdi, [rip + g_face_small]
    mov esi, [rsp + 16 + 4]
    mov edx, r13d
    mov ecx, r15d
    mov r8, [rsp + 16 + 24]
    mov r9, [rsp + 16 + 32]
    call ui_text_v_fit
    add rsp, 16
    cmp qword ptr [rsp + 40], 0
    je 6f
    mov esi, [rsp + 4]
    add esi, [rsp + 52]
    add esi, [rip + g_mt + 4*MI_6]
    mov eax, [rsp + 8]
    sub eax, esi
    cmp eax, [rip + g_mt + 4*MI_16]
    jl 6f
    push rax
    COLOR eax, T_MUTED
    push rax
    lea rdi, [rip + g_face_mini]
    mov edx, r13d
    mov ecx, r15d
    mov r8, [r12 + GF_path]
    mov r9, [rsp + 16 + 40]
    call ui_text_v_fit
    add rsp, 16
6:  # a click on the row: the file's changes (not for untracked folders)
    test r14d, UB_CLICK
    jz 9f
    mov rdi, [r12 + GF_path]
    call strlen
    test rax, rax
    jz 9f
    mov rsi, [r12 + GF_path]
    cmp byte ptr [rsi + rax - 1], '/'
    je 9f
    mov rdx, rax
    xor edi, edi
    call git_open_diff
9:  EPILOGUE
# file_button(id, x, -, -, -, icon) -> 1 when clicked: an icon button on the row at r13d
file_button:
    push rbx
    push r12
    sub rsp, 8
    mov ebx, edi
    mov r12d, esi
    mov edx, r13d
    add edx, [rip + g_mt + 4*MI_2]
    M ecx, MI_24
    mov r8d, ecx
    call ui_icon_btn
    mov r9d, eax
    mov edi, ebx
    mov esi, r12d
    mov edx, r13d
    add edx, [rip + g_mt + 4*MI_2]
    M ecx, MI_24
    mov r8d, ecx
    call note_tip
    and eax, UB_CLICK
    shr eax, 2
    add rsp, 8
    pop r12
    pop rbx
    ret

# ---------------- tooltips: the git commands a click runs ----------------

# note_tip(id, x, y, w, h, flags) -> flags: the tooltip of a hovered button
note_tip:
    PROLOGUE 16
    mov [rsp], r9d
    test r9d, UB_HOVER
    jz 9f
    mov ebx, edi
    mov r12d, esi
    lea r13d, [rdx + r8]        # its bottom
    mov r14d, ecx
    call tip_for
    test rax, rax
    jz 9f
    mov r9, rax
    mov edi, ebx
    mov esi, r12d
    mov edx, r13d
    mov ecx, r14d
    mov r8d, [rsp]
    call tip_note_text
9:  mov eax, [rsp]
    EPILOGUE

# tip_for(id) -> rax the tooltip of a button that takes clicks: the git commands it runs, or 0
tip_for:
    PROLOGUE
    xor esi, esi                # the file, for a file's buttons
    cmp edi, ID_SCM_FILE
    jae 5f
    cmp edi, ID_SCM_GROUP
    jae 4f
    cmp edi, ID_SCM_MAIN
    jne 1f
    call main_button
    lea rcx, [rip + main_seqs]
    mov rdi, [rcx + rax*8]
    test rdi, rdi
    jz 8f
    jmp 7f
1:  cmp edi, ID_SCM_PULL
    jne 11f
    lea rdi, [rip + seq_pull]
    jmp 7f
11: cmp edi, ID_SCM_PULL + 1
    jne 12f
    # a branch without an upstream is published
    call unpublished
    lea rdi, [rip + seq_push]
    test eax, eax
    jz 7f
    lea rdi, [rip + seq_publish]
    jmp 7f
12: cmp edi, ID_SCM_PULL + 2
    jne 13f
    lea rdi, [rip + seq_fetch]
    jmp 7f
13: cmp edi, ID_SCM_RESET
    jne 14f
    lea rdi, [rip + seq_reset_all]
    jmp 7f
14: cmp edi, ID_SCM_AI
    jne 8f
    # what the helper reads (runtime/ai/commit.sh); it changes nothing
    lea rax, [rip + .Ltip_ai_stop]
    cmp dword ptr [rip + g_ai_kind], 3
    je 9f
    lea rax, [rip + .Ltip_ai_staged]
    cmp dword ptr [rip + counts + 4*GG_STAGED], 0
    jne 9f
    lea rax, [rip + .Ltip_ai_all]
    jmp 9f
4:  # a group's buttons
    sub edi, ID_SCM_GROUP
    mov eax, edi
    shr eax, 2
    and edi, 3
    cmp eax, GG_STAGED
    jne 41f
    test edi, edi
    jnz 8f
    lea rdi, [rip + seq_unstage_all]
    jmp 7f
41: cmp eax, GG_CHANGES
    jne 8f
    test edi, edi
    jnz 42f
    lea rdi, [rip + seq_stage_all]
    jmp 7f
42: call discard_all_seq
    mov rdi, rax
    xor esi, esi
    jmp 7f
5:  # a file's: stage (or unstage), discard
    sub edi, ID_SCM_FILE
    mov ecx, edi
    and ecx, 3
    shr edi, 2
    cmp rdi, [rip + list + VEC_len]
    jae 8f
    imul rdx, rdi, GF_SIZE
    add rdx, [rip + list + VEC_ptr]
    mov rsi, [rdx + GF_path]
    cmp ecx, 1
    jne 51f
    lea rdi, [rip + seq_unstage]
    cmp dword ptr [rdx + GF_group], GG_STAGED
    je 7f
    lea rdi, [rip + seq_stage]
    jmp 7f
51: cmp ecx, 2
    jne 8f
    lea rdi, [rip + seq_discard]
    cmp dword ptr [rdx + GF_code], 'U'
    jne 7f
    lea rdi, [rip + seq_discard_new]
7:  call tip_seq
    mov rax, [rip + tips + SB_ptr]
    jmp 9f
8:  xor eax, eax
9:  EPILOGUE

# tip_seq(seq, path): the steps of seq as a shell line into tips, its queries (git config, git remote)
#   left out; the arguments as run_step gives them (path: the file of a file's button)
tip_seq:
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    lea rdi, [rip + tips]
    call sb_clear
1:  movzx r13d, byte ptr [rbx]
    test r13d, r13d
    jz 9f
    inc rbx
    cmp r13d, S_PULL_CFG
    je 1b
    cmp r13d, S_REMOTES
    je 1b
    cmp qword ptr [rip + tips + SB_len], 0
    je 2f
    lea rdi, [rip + tips]
    lea rsi, [rip + .Ltip_and]
    call sb_push_cstr
2:  lea rdi, [rip + tips]
    lea rsi, [rip + .Ltip_git]
    call sb_push_cstr
    lea rax, [rip + step_args]
    mov r14, [rax + r13*8]
    cmp r13d, S_PULL
    jne 3f
    cmp dword ptr [rip + pull_merge], 0
    je 3f
    lea r14, [rip + args_pull_merge]
3:  mov rdi, [r14]
    test rdi, rdi
    jz 4f
    call tip_arg
    add r14, 8
    jmp 3b
4:  # what run_step adds: the message on standard input, where to publish, the file
    cmp r13d, S_COMMIT
    jne 5f
    lea rdi, [rip + tips]
    lea rsi, [rip + .Ltip_message]
    call sb_push_cstr
    jmp 1b
5:  cmp r13d, S_PUBLISH
    jne 6f
    lea rdi, [rip + remote]
    cmp byte ptr [rdi], 0
    jne 51f
    lea rdi, [rip + tips]
    lea rsi, [rip + .Ltip_remote]
    call sb_push_cstr
    jmp 52f
51: call tip_arg
52: lea rdi, [rip + .Lhead]
    call tip_arg
    jmp 1b
6:  cmp r13d, S_ADD
    je 61f
    cmp r13d, S_RESET
    je 61f
    cmp r13d, S_CHECKOUT
    je 61f
    cmp r13d, S_CLEAN
    jne 1b
61: test r12, r12
    jz 1b
    lea rdi, [rip + .Ldashdash]
    call tip_arg
    mov rdi, r12
    call tip_arg
    jmp 1b
9:  lea rdi, [rip + tips]
    xor esi, esi
    call sb_push_byte           # a C string for tip_note_text
    EPILOGUE

# tip_arg(cstr): a space and the argument onto tips, in single quotes when a shell would split or
#   expand it (a ' inside as '\'')
tip_arg:
    PROLOGUE
    mov rbx, rdi
    lea rdi, [rip + tips]
    mov esi, ' '
    call sb_push_byte
    # plain: letters, digits and -_./+=,:@%
    mov rax, rbx
1:  movzx ecx, byte ptr [rax]
    test ecx, ecx
    jz 7f
    inc rax
    mov edx, ecx
    or edx, 0x20
    sub edx, 'a'
    cmp edx, 26
    jb 1b
    lea edx, [rcx - '0']
    cmp edx, 10
    jb 1b
    lea rdx, [rip + .Ltip_plain]
2:  cmp byte ptr [rdx], 0
    je 3f
    cmp [rdx], cl
    je 1b
    inc rdx
    jmp 2b
3:  lea rdi, [rip + tips]
    mov esi, 0x27
    call sb_push_byte
4:  movzx esi, byte ptr [rbx]
    test esi, esi
    jz 6f
    inc rbx
    cmp esi, 0x27
    jne 5f
    lea rdi, [rip + tips]
    lea rsi, [rip + .Ltip_quote]
    call sb_push_cstr
    jmp 4b
5:  lea rdi, [rip + tips]
    call sb_push_byte
    jmp 4b
6:  lea rdi, [rip + tips]
    mov esi, 0x27
    call sb_push_byte
    EPILOGUE
7:  lea rdi, [rip + tips]
    mov rsi, rbx
    call sb_push_cstr
    EPILOGUE

# ---------------- scripts ----------------

# scm_dump(sb): "action=commit" (or what runs), the message (line breaks as |), the last error, the changes
FN scm_dump
    PROLOGUE
    mov rbx, rdi
    call sync_list
    mov rdi, rbx
    lea rsi, [rip + .Ld_action]
    call sb_push_cstr
    mov eax, [rip + op]
    lea rcx, [rip + op_names]
    test eax, eax
    jnz 1f
    call main_button
    lea rcx, [rip + mb_names]
1:  mov rsi, [rcx + rax*8]
    mov rdi, rbx
    call sb_push_cstr
    mov rdi, rbx
    mov esi, 10
    call sb_push_byte
    lea rdi, [rip + tf_msg]
    call tf_text
    mov r12, rax
    mov r13, rdx
    test r13, r13
    jz 4f
    mov rdi, rbx
    lea rsi, [rip + .Ld_message]
    call sb_push_cstr
    xor r14d, r14d
2:  cmp r14, r13
    jae 3f
    movzx esi, byte ptr [r12 + r14]
    cmp esi, 10
    jne 21f
    mov esi, '|'
21: mov rdi, rbx
    call sb_push_byte
    inc r14
    jmp 2b
3:  mov rdi, rbx
    mov esi, 10
    call sb_push_byte
4:  cmp byte ptr [rip + err], 0
    je 5f
    mov rdi, rbx
    lea rsi, [rip + .Ld_error]
    call sb_push_cstr
    mov rdi, rbx
    lea rsi, [rip + err]
    call sb_push_cstr
    mov rdi, rbx
    mov esi, 10
    call sb_push_byte
5:  mov rdi, rbx
    call scm_dump_files
    EPILOGUE

# scm_dump_files(sb): the changes, a group title then "    X path" per file
FN scm_dump_files
    PROLOGUE
    mov rbx, rdi
    call sync_list
    mov r12d, GG_MERGE
1:  lea rax, [rip + counts]
    cmp dword ptr [rax + r12*4], 0
    je 5f
    mov rdi, rbx
    lea rsi, [rip + .Lindent]
    call sb_push_cstr
    lea rax, [rip + group_titles]
    mov rsi, [rax + r12*8]
    mov rdi, rbx
    call sb_push_cstr
    mov rdi, rbx
    mov esi, 10
    call sb_push_byte
    xor r13d, r13d
2:  cmp r13, [rip + list + VEC_len]
    jae 5f
    imul r14, r13, GF_SIZE
    add r14, [rip + list + VEC_ptr]
    cmp [r14 + GF_group], r12d
    jne 4f
    mov rdi, rbx
    lea rsi, [rip + .Lindent]
    call sb_push_cstr
    mov rdi, rbx
    mov esi, [r14 + GF_code]
    call sb_push_byte
    mov rdi, rbx
    mov esi, ' '
    call sb_push_byte
    mov rdi, rbx
    mov rsi, [r14 + GF_path]
    call sb_push_cstr
    mov rdi, rbx
    mov esi, 10
    call sb_push_byte
4:  inc r13
    jmp 2b
5:  inc r12d
    cmp r12d, GG_CHANGES
    jbe 1b
    EPILOGUE

.section .rodata
.Lno_repo: .asciz "No git repository"
.Lbusy: .asciz "Wait for the git command that runs"
.Lconflicts: .asciz "Resolve the conflicts and stage the files first"
.Lnothing: .asciz "No changes to commit"
.Lnothing_discard: .asciz "No changes to discard"
.Lno_message: .asciz "Type a commit message first"
.Llong: .asciz "The commit message is too long"
.Lno_remote: .asciz "No remote to publish to: add one with git remote add"
.Le_rejected: .asciz "Push rejected: pull first to bring in the remote's changes"
.Le_conflict: .asciz "Merge conflicts: resolve them, stage the files, then commit"
.Le_rebase: .asciz "Rebase stopped on conflicts: resolve them, then git rebase --continue"
.Le_failed: .asciz "git failed"
.Lk_rejected: .ascii "[rejected]"
.Lk_conflict: .ascii "CONFLICT"
.Lk_rebase: .ascii "could not apply"
.Lk_fatal: .ascii "fatal: "
.Lk_error: .ascii "error: "
.Lk_hint: .ascii "hint:"
.Lpull_same: .ascii "Already up to date"
.Lpush_same: .ascii "Everything up-to-date"
.Lt_same: .asciz "Already up to date"
.Lt_pulled: .asciz "Pulled"
.Lt_pushed: .asciz "Pushed"
.Lt_synced: .asciz "Synced"
.Lt_fetched: .asciz "Fetched"
.Lt_published: .asciz "Branch published"
.Lt_reset: .asciz "All changes reset"
.Lq_reset: .asciz "Reset all changes?"
.Lq_reset_text: .asciz "Staged and unstaged changes will be lost. New files and folders will be deleted."
.Lb_reset: .asciz "Reset All Changes"
.Lq_discard: .asciz "Discard changes in "
.Lq_discard_text: .asciz "Its changes that are not staged will be lost."
.Lq_delete: .asciz "Delete "
.Lq_delete_text: .asciz "The file is not in git: it cannot be restored."
.Lq_all: .asciz "Discard all changes?"
.Lq_all_text: .asciz "Unstaged changes and new files will be lost."
.Lb_discard: .asciz "Discard"
.Lb_delete: .asciz "Delete"
.Lb_discard_all: .asciz "Discard All"
.Lph: .asciz "Commit message"
.ifdef MACOS
.Lhint: .asciz "\342\214\230Enter to commit"
.else
.Lhint: .asciz "Ctrl+Enter to commit"
.endif
.Lch: .asciz "Ch: "
.Lall: .asciz "All"
.Lst_none: .asciz "Nothing staged"
.Lst_file: .asciz " file staged"
.Lst_files: .asciz " files staged"
.Lh_unborn: .asciz "no commits yet"
.Lh_detached: .asciz "detached"
.Lh_unpublished: .asciz "not published"
.Ldown: .asciz "\342\206\223"
.Lup: .asciz "\342\206\221"
.Lm_commit: .asciz "Commit"
.Lm_commit_all: .asciz "Commit All"
.Lm_sync: .asciz "Sync Changes"
.Lm_publish: .asciz "Publish Branch"
.Lw_commit: .asciz "Committing\342\200\246"
.Lw_pull: .asciz "Pulling\342\200\246"
.Lw_push: .asciz "Pushing\342\200\246"
.Lw_sync: .asciz "Syncing\342\200\246"
.Lw_fetch: .asciz "Fetching\342\200\246"
.Lw_publish: .asciz "Publishing\342\200\246"
.Lw_reset: .asciz "Resetting\342\200\246"
.Lr_pull: .asciz "Pull"
.Lr_push: .asciz "Push"
.Lr_fetch: .asciz "Fetch"
.Lg_merge: .asciz "MERGE CHANGES"
.Lg_staged: .asciz "STAGED CHANGES"
.Lg_changes: .asciz "CHANGES"
.Ld_action: .asciz "action="
.Ld_message: .asciz "message="
.Ld_error: .asciz "error="
.Lindent: .asciz "    "
.Ln_none: .asciz "none"
.Ln_commit: .asciz "commit"
.Ln_commit_all: .asciz "commit-all"
.Ln_sync: .asciz "sync"
.Ln_publish: .asciz "publish"
.Ln_committing: .asciz "committing"
.Ln_pulling: .asciz "pulling"
.Ln_pushing: .asciz "pushing"
.Ln_syncing: .asciz "syncing"
.Ln_fetching: .asciz "fetching"
.Ln_publishing: .asciz "publishing"
.Ln_staging: .asciz "staging"
.Ln_resetting: .asciz "resetting"
.Lorigin: .ascii "origin"
# git's arguments
.Ladd: .asciz "add"
.Ldash_a: .asciz "-A"
.Lcommit: .asciz "commit"
.Ldash_q: .asciz "-q"
.Ldash_f: .asciz "-F"
.Ldash: .asciz "-"
.Lamend: .asciz "--amend"
.Lno_edit: .asciz "--no-edit"
.Lconfig: .asciz "config"
.Lget_regexp: .asciz "--get-regexp"
.Lpull_keys: .asciz "^pull\\.(rebase|ff)$"
.Lpull: .asciz "pull"
.Lpull_merge: .asciz "pull.rebase=false"
.Ldash_c: .asciz "-c"
.Lpush: .asciz "push"
.Ldash_u: .asciz "-u"
.Lremote: .asciz "remote"
.Lfetch: .asciz "fetch"
.Lreset: .asciz "reset"
.Lhard: .asciz "--hard"
.Lcheckout: .asciz "checkout"
.Lclean: .asciz "clean"
.Ldash_d: .asciz "-d"
.Lforce: .asciz "-f"
.Ldashdash: .asciz "--"
.Ldot: .asciz "."
.Lhead: .asciz "HEAD"
.Lls_files: .asciz "ls-files"
.Lothers: .asciz "--others"
.Lexclude_std: .asciz "--exclude-standard"
.Lnul_z: .asciz "-z"
.Ltip_git: .asciz "git"
.Ltip_and: .asciz " && "
.Ltip_message: .asciz " < message"
.Ltip_remote: .asciz " <remote>"
.Ltip_plain: .asciz "-_./+=,:@%"
.Ltip_quote: .asciz "'\\''"
.Ltip_ai_staged: .asciz "Writes the message from git diff --cached"
.Ltip_ai_all: .asciz "Writes the message from all changes (git add -A on a temporary index)"
.Ltip_ai_stop: .asciz "Stops writing the message; your draft stays"
.p2align 3
args_add_all: .quad .Ladd, .Ldash_a, 0
args_commit: .quad .Lcommit, .Ldash_q, .Ldash_f, .Ldash, 0
args_amend: .quad .Lcommit, .Ldash_q, .Lamend, 0
args_pull_cfg: .quad .Lconfig, .Lget_regexp, .Lpull_keys, 0
args_pull: .quad .Lpull, .Lno_edit, 0
args_pull_merge: .quad .Ldash_c, .Lpull_merge, .Lpull, .Lno_edit, 0
args_push: .quad .Lpush, 0
args_remote: .quad .Lremote, 0
args_publish: .quad .Lpush, .Ldash_u, 0
args_fetch: .quad .Lfetch, 0
args_untracked: .quad .Lls_files, .Lothers, .Lexclude_std, .Lnul_z, 0
args_add: .quad .Ladd, .Ldash_a, 0
args_reset: .quad .Lreset, .Ldash_q, 0
args_reset_all: .quad .Lreset, .Ldash_q, .Ldashdash, .Ldot, 0
args_reset_hard: .quad .Lreset, .Lhard, .Ldash_q, 0
args_checkout: .quad .Lcheckout, .Ldash_q, 0
args_checkout_all: .quad .Lcheckout, .Ldash_q, .Ldashdash, .Ldot, 0
args_clean: .quad .Lclean, .Lforce, .Ldash_d, .Ldash_q, 0
# by S_*
step_args:
    .quad 0, args_add_all, args_commit, args_amend, args_pull_cfg, args_pull, args_push, args_remote
    .quad args_publish, args_fetch, args_add, args_reset, args_reset_all, args_checkout, args_checkout_all
    .quad args_clean, args_clean, args_reset_hard
# by OP_*
done_toasts:
    .quad 0, 0, .Lt_pulled, .Lt_pushed, .Lt_synced, .Lt_fetched, .Lt_published, 0, .Lt_reset
busy_labels:
    .quad 0, .Lw_commit, .Lw_pull, .Lw_push, .Lw_sync, .Lw_fetch, .Lw_publish, 0, .Lw_reset
op_names:
    .quad .Ln_none, .Ln_committing, .Ln_pulling, .Ln_pushing, .Ln_syncing, .Ln_fetching, .Ln_publishing
    .quad .Ln_staging, .Ln_resetting
# by MB_*
main_labels:
    .quad .Lm_commit, .Lm_commit, .Lm_commit_all, .Lm_sync, .Lm_publish
# by MB_*: what the button runs, for its tooltip
main_seqs:
    .quad 0, seq_commit, seq_commit_all, seq_sync, seq_publish
mb_names:
    .quad .Ln_none, .Ln_commit, .Ln_commit_all, .Ln_sync, .Ln_publish
# by GG_*
group_titles:
    .quad 0, .Lg_merge, .Lg_staged, .Lg_changes
# steps
seq_commit: .byte S_COMMIT, 0
seq_commit_all: .byte S_ADD_ALL, S_COMMIT, 0
seq_amend: .byte S_AMEND, 0
seq_pull: .byte S_PULL_CFG, S_PULL, 0
seq_push: .byte S_PUSH, 0
seq_publish: .byte S_REMOTES, S_PUBLISH, 0
seq_sync: .byte S_PULL_CFG, S_PULL, S_PUSH, 0
seq_fetch: .byte S_FETCH, 0
seq_stage: .byte S_ADD, 0
seq_stage_all: .byte S_ADD_ALL, 0
seq_unstage: .byte S_RESET, 0
seq_unstage_all: .byte S_RESET_ALL, 0
seq_discard: .byte S_CHECKOUT, 0
seq_discard_new: .byte S_CLEAN, 0
seq_discard_all: .byte S_CHECKOUT_ALL, S_CLEAN_ALL, 0
seq_clean_all: .byte S_CLEAN_ALL, 0
seq_reset_all: .byte S_RESET_HARD, S_CLEAN_ALL, 0

.Lai_label: .asciz "Generate"
.Lai_cancel: .asciz "Cancel"
.Lai_off: .asciz "Choose a commit message AI provider in Settings first."
.Lai_edited: .asciz "Your draft changed while generating, so it was kept."
