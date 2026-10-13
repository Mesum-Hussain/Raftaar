// raftaar on macOS: inotify on FSEvents
//
// The inotify descriptor is the read end of a pipe. An FSEvents stream over the watched
// directories reports file events on a dispatch queue; each one in a watched directory becomes
// an inotify_event record (watch, mask, name) written to the pipe.
.include "mac.inc"

.equ MAXW, 1024
.equ IN_MODIFY, 0x2
.equ IN_CLOSE_WRITE, 0x8
.equ IN_MOVED_FROM, 0x40
.equ IN_MOVED_TO, 0x80
.equ IN_CREATE, 0x100
.equ IN_DELETE, 0x200

// watch entry: given path, real path, real path length
.equ W_path, 0
.equ W_real, 8
.equ W_len, 16
.equ W_SIZE, 24

.macro LOCK
    ADR x0, lock
    bl _os_unfair_lock_lock
.endm
.macro UNLOCK
    ADR x0, lock
    bl _os_unfair_lock_unlock
.endm

// inotify_init1(flags) -> descriptor
FN sys_inotify_init1
    ENTER 16
    mov w19, w0
    ADR x0, fds
    bl _pipe
    cbnz w0, 8f
    ADR x9, fds
    ldr w0, [x9]
    mov w1, w19
    bl set_fl
    ADR x9, fds
    ldr w0, [x9, #4]
    mov w1, #0x800              // the writer never blocks
    orr w1, w1, #0x80000
    bl set_fl
    ADR x0, s_queue
    mov x1, #0
    bl _dispatch_queue_create
    ADR x9, queue
    str x0, [x9]
    ADR x9, fds
    ldrsw x0, [x9]
    b 9f
8:  mov x0, #-1
    bl linux_ret_errno
9:  LEAVE
    ret

// inotify_add_watch(fd, path, mask) -> watch number
FN sys_inotify_add_watch
    ENTER 16
    mov x19, x1
    mov x0, x19
    mov x1, #0
    bl _realpath
    cbz x0, 5f
    mov x23, x0
    // the same directory is the same watch, however it is spelled
    mov x20, #0
    ADR x21, watches
    ADR x9, nwatch
    ldr w22, [x9]
1:  cmp w20, w22
    b.hs 2f
    mov x9, #W_SIZE
    madd x9, x9, x20, x21
    ldr x0, [x9, #W_real]
    mov x1, x23
    bl _strcmp
    cbz w0, 3f
    add x20, x20, #1
    b 1b
3:  mov x0, x23
    bl _free
    b 7f
2:  cmp w22, #MAXW
    b.hs 6f
    mov x0, x23
    bl _strlen
    mov x24, x0
    mov x0, x19
    bl _strdup
    mov x25, x0
    LOCK
    mov x9, #W_SIZE
    madd x9, x9, x22, x21
    str x25, [x9, #W_path]
    str x23, [x9, #W_real]
    str x24, [x9, #W_len]
    add w22, w22, #1
    ADR x9, nwatch
    str w22, [x9]
    UNLOCK
    bl restart
    mov x20, x22
    sub x20, x20, #1
7:  add x0, x20, #1
    b 9f
5:  mov x0, #-1
    bl linux_ret_errno
    b 9f
6:  mov x0, x23
    bl _free
    mov x0, #-28                // ENOSPC
9:  LEAVE
    ret

FN sys_inotify_rm_watch
    mov x0, #0
    ret

// restart(): a stream over every watched directory
restart:
    ENTER 16
    ADR x9, stream
    ldr x19, [x9]
    cbz x19, 1f
    // the new stream starts after the last event of this one
    mov x0, x19
    bl _FSEventStreamGetLatestEventId
    cmp x0, #0
    csinv x0, x0, xzr, ne       // none yet: from now
    ADR x9, since
    str x0, [x9]
    mov x0, x19
    bl _FSEventStreamStop
    mov x0, x19
    bl _FSEventStreamInvalidate
    mov x0, x19
    bl _FSEventStreamRelease
    ADR x9, stream
    str xzr, [x9]
1:  mov x0, #0
    mov x1, #0
    adrp x2, _kCFTypeArrayCallBacks@GOTPAGE
    ldr x2, [x2, _kCFTypeArrayCallBacks@GOTPAGEOFF]
    bl _CFArrayCreateMutable
    mov x20, x0
    ADR x21, watches
    ADR x9, nwatch
    ldr w22, [x9]
    mov x23, #0
2:  cmp x23, x22
    b.hs 3f
    mov x9, #W_SIZE
    madd x9, x9, x23, x21
    ldr x1, [x9, #W_real]
    mov x0, #0
    mov w2, #0x0100             // kCFStringEncodingUTF8 is 0x08000100
    movk w2, #0x0800, lsl #16
    bl _CFStringCreateWithCString
    mov x24, x0
    mov x0, x20
    mov x1, x24
    bl _CFArrayAppendValue
    mov x0, x24
    bl _CFRelease
    add x23, x23, #1
    b 2b
3:  mov x0, #0
    ADR x1, on_events
    mov x2, #0
    mov x3, x20
    ADR x9, since
    ldr x4, [x9]                // kFSEventStreamEventIdSinceNow at first
    ldr d0, f_latency
    mov w5, #0x12               // file events, no defer
    bl _FSEventStreamCreate
    mov x19, x0
    mov x0, x20
    bl _CFRelease
    cbz x19, 9f
    ADR x9, stream
    str x19, [x9]
    mov x0, x19
    ADR x9, queue
    ldr x1, [x9]
    bl _FSEventStreamSetDispatchQueue
    mov x0, x19
    bl _FSEventStreamStart
9:  LEAVE
    ret

// on_events(stream, info, n, paths, flags, ids): on the dispatch queue
on_events:
    ENTER 560
    mov x19, x2
    mov x20, x3
    mov x21, x4
    mov x22, #0
1:  cmp x22, x19
    b.hs 9f
    ldr x23, [x20, x22, lsl #3]         // path
    ldr w24, [x21, x22, lsl #2]         // flags
    // mask
    mov w25, #0
    tst w24, #0x100
    b.eq 2f
    orr w25, w25, #IN_CREATE
2:  tst w24, #0x200
    b.eq 3f
    orr w25, w25, #IN_DELETE
3:  tst w24, #0x1000
    b.eq 4f
    orr w25, w25, #IN_MODIFY
    orr w25, w25, #IN_CLOSE_WRITE
4:  tst w24, #0x800
    b.eq 5f
    mov x0, x23
    add x1, sp, #400
    bl _lstat
    mov w9, #IN_MOVED_TO
    mov w10, #IN_MOVED_FROM
    cmp w0, #0
    csel w9, w9, w10, eq
    orr w25, w25, w9
5:  cbz w25, 8f
    // directory and name
    mov x0, x23
    mov w1, #'/'
    bl _strrchr
    cbz x0, 8f
    sub x26, x0, x23                    // directory length
    add x27, x0, #1                     // name
    mov x0, x27
    bl _strlen
    cmp x0, #255
    b.hi 8f
    str x0, [sp, #16]
    // the watch holding it
    LOCK
    ADR x9, nwatch
    ldr w10, [x9]
    str w10, [sp, #8]
    mov x24, #0
6:  ldr w10, [sp, #8]
    cmp w24, w10
    b.hs 61f
    ADR x9, watches
    mov x10, #W_SIZE
    madd x9, x10, x24, x9
    ldr x10, [x9, #W_len]
    cmp x10, x26
    b.ne 62f
    ldr x0, [x9, #W_real]
    mov x1, x23
    mov x2, x26
    bl _memcmp
    cbz w0, 63f
62: add x24, x24, #1
    b 6b
61: mov x24, #-1
63: UNLOCK
    tbnz x24, #63, 8f
    // record: wd, mask, cookie, len, name padded to 16
    add x9, sp, #32
    add w10, w24, #1
    str w10, [x9, #0]
    str w25, [x9, #4]
    str wzr, [x9, #8]
    ldr x11, [sp, #16]
    add x12, x11, #16
    and x12, x12, #~15
    str w12, [x9, #12]
    str x12, [sp, #24]
    add x0, x9, #16
    mov w1, #0
    mov x2, x12
    bl _memset
    add x0, sp, #48
    mov x1, x27
    ldr x2, [sp, #16]
    bl _memcpy
    ADR x9, fds
    ldr w0, [x9, #4]
    add x1, sp, #32
    ldr x2, [sp, #24]
    add x2, x2, #16
    bl _write
8:  add x22, x22, #1
    b 1b
9:  LEAVE
    ret

// linux_ret_errno(): -errno of the last libSystem call, Linux numbering
linux_ret_errno:
    stp x29, x30, [sp, #-16]!
    mov x29, sp
    bl ___error
    ldr w0, [x0]
    bl linux_errno
    neg x0, x0
    ldp x29, x30, [sp], #16
    ret

.p2align 3
f_latency: .double 0.005

.section __TEXT,__cstring,cstring_literals
s_queue: .asciz "raftaar.watch"

.data
.p2align 3
stream: .quad 0
since: .quad -1
queue: .quad 0
fds: .long -1, -1
nwatch: .long 0
lock: .long 0

.bss
.p2align 3
watches: .zero W_SIZE * MAXW
