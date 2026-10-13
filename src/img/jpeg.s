# JPEG: baseline and progressive huffman coding, any sampling factors, restart markers,
# gray, YCbCr, RGB and Adobe CMYK / YCCK; the EXIF orientation is applied
.include "raftaar.inc"

.equ FASTB, 9                   # code bits resolved by one table lookup
.equ KIND_COPY, 0                # upsampling
.equ KIND_H2, 1
.equ KIND_V2, 2
.equ KIND_H2V2, 3
.equ KIND_BOX, 4

# huffman table
STRUCT
F HT_fast, 2<<FASTB             # (length << 8) | symbol for codes up to FASTB bits, 0 = longer
F HT_max, 4*18                  # (last code + 1) << (16 - length), for lengths 1..16; [17] ends the search
F HT_delta, 4*17                # sorted index of a length's first symbol minus its first code
F HT_val, 256                   # symbols in code order
F HT_n, 4
F HT_pad, 4
ENDSTRUCT HT_SIZE

# frame component
STRUCT
F C_id, 4
F C_h, 4
F C_v, 4
F C_tq, 4                       # quantization table
F C_td, 4                       # DC table of the scan
F C_ta, 4                       # AC table of the scan
F C_bw, 4                       # blocks per row, padded to whole MCUs
F C_bh, 4
F C_pred, 4                     # DC prediction
F C_pad, 4
F C_coef, 8                     # 64 int16 per block, natural order, not dequantized
F C_plane, 8                    # samples, bw * 8 wide
ENDSTRUCT C_SIZE

.bss
.p2align 4
huff: .zero 8 * HT_SIZE         # DC 0-3, AC 0-3
qt: .zero 4 * 64 * 2            # natural order
comps: .zero 4 * C_SIZE
blk: .zero 64 * 4
val: .zero 64 * 4
cr_r: .zero 256 * 4             # color conversion
cb_b: .zero 256 * 4
cr_g: .zero 256 * 4
cb_g: .zero 256 * 4
clamp: .zero 1024               # [v + 384]
.p2align 3
img: .quad 0
pos: .quad 0                    # parser position
end: .quad 0
scan_rsp: .quad 0
xtabs: .zero 4 * 8              # per component: sample column of each pixel column
rows: .zero 4 * 8               # per component: this row's samples, one per pixel
bufs: .zero 4 * 8               # rows of the components that are not copied
colsum: .quad 0
ckind: .zero 4 * 4              # KIND_*
cdw: .zero 4 * 4                # samples across
cdh: .zero 4 * 4                # and down
block_fn: .quad 0
width: .long 0
height: .long 0
ncomp: .long 0
progressive: .long 0
hmax: .long 0
vmax: .long 0
mcux: .long 0
mcuy: .long 0
restart: .long 0
adobe: .long 0                  # APP14 transform, -1 without one
jfif: .long 0
orient: .long 0
scans: .long 0
ns: .long 0
scomp: .zero 4                  # component indices of the scan
spec_s: .long 0                 # spectral selection
spec_e: .long 0
succ_h: .long 0                 # successive approximation
succ_l: .long 0
eobrun: .long 0
todo: .long 0
marker: .long 0
tables_ok: .long 0
pad: .long 0                    # zero bytes fed after the data ended

.text

# jpeg_decode(ptr, len, IMG*) -> 0 or -1
FN jpeg_decode
    PROLOGUE 32
    mov [rip + img], rdx
    lea rax, [rdi + 2]
    mov [rip + pos], rax
    add rdi, rsi
    mov [rip + end], rdi
    xor eax, eax
    mov [rip + width], eax
    mov [rip + ncomp], eax
    mov [rip + restart], eax
    mov [rip + jfif], eax
    mov [rip + scans], eax
    mov dword ptr [rip + orient], 1
    mov dword ptr [rip + adobe], -1
    lea rdi, [rip + comps]
    mov ecx, 4 * C_SIZE
    rep stosb
.Lseg:
    # next marker: 0xff, maybe more 0xff, then its code
    mov r12, [rip + pos]
    mov r13, [rip + end]
1:  lea rax, [r12 + 1]
    cmp rax, r13
    jae .Lfinish
    cmp byte ptr [r12], 0xff
    jne 2f
    movzx ebx, byte ptr [r12 + 1]
    cmp ebx, 0xff
    je 2f
    test ebx, ebx
    jnz 3f
2:  inc r12
    jmp 1b
3:  add r12, 2
    mov [rip + pos], r12
    cmp ebx, 0xd9
    je .Lfinish
    cmp ebx, 0xd8
    je .Lseg
    mov eax, ebx
    and eax, 0xf8
    cmp eax, 0xd0               # stray restart marker
    je .Lseg
    cmp ebx, 0x01
    je .Lseg
    # everything else has a length
    mov rax, r13
    sub rax, r12
    cmp rax, 2
    jb .Lfinish
    LDBE16 r14d, r14w, [r12]
    cmp r14d, 2
    jb .Lfail
    cmp r14, rax
    ja .Lfinish                 # cut short
    lea r15, [r12 + r14]        # after the segment
    add r12, 2                  # its data
    sub r14d, 2                 # and length
    cmp ebx, 0xc0
    je .Lsof
    cmp ebx, 0xc1
    je .Lsof
    cmp ebx, 0xc2
    je .Lsof
    cmp ebx, 0xc4
    je .Ldht
    cmp ebx, 0xdb
    je .Ldqt
    cmp ebx, 0xda
    je .Lsos
    cmp ebx, 0xdd
    je .Ldri
    cmp ebx, 0xe0
    je .Lapp0
    cmp ebx, 0xe1
    je .Lapp1
    cmp ebx, 0xee
    je .Lapp14
    cmp ebx, 0xc3
    jb .Lnext
    cmp ebx, 0xcf
    jbe .Lunsupported           # lossless, hierarchical, arithmetic coding
.Lnext:
    mov [rip + pos], r15
    jmp .Lseg

.Lsof:
    cmp dword ptr [rip + ncomp], 0
    jne .Lfail
    xor eax, eax
    cmp ebx, 0xc2
    sete al
    mov [rip + progressive], eax
    cmp r14d, 6
    jb .Lfail
    cmp byte ptr [r12], 8
    jne .Lunsupported           # 12 and 16 bit samples
    LDBE16 eax, ax, [r12 + 1]
    test eax, eax
    jz .Lunsupported            # height given later (DNL)
    mov [rip + height], eax
    LDBE16 eax, ax, [r12 + 3]
    test eax, eax
    jz .Lfail
    mov [rip + width], eax
    movzx ecx, byte ptr [r12 + 5]
    cmp ecx, 1
    je 1f
    cmp ecx, 3
    je 1f
    cmp ecx, 4
    jne .Lunsupported
1:  mov [rip + ncomp], ecx
    lea eax, [rcx + rcx*2 + 6]
    cmp r14d, eax
    jb .Lfail
    lea rsi, [r12 + 6]
    lea rdi, [rip + comps]
    xor edx, edx
    mov dword ptr [rip + hmax], 1
    mov dword ptr [rip + vmax], 1
2:  cmp edx, [rip + ncomp]
    jae 3f
    movzx eax, byte ptr [rsi]
    mov [rdi + C_id], eax
    movzx eax, byte ptr [rsi + 1]
    mov r8d, eax
    shr r8d, 4
    and eax, 15
    lea r9d, [r8 - 1]
    cmp r9d, 3
    ja .Lfail
    lea r9d, [rax - 1]
    cmp r9d, 3
    ja .Lfail
    mov [rdi + C_h], r8d
    mov [rdi + C_v], eax
    cmp r8d, [rip + hmax]
    jbe 21f
    mov [rip + hmax], r8d
21: cmp eax, [rip + vmax]
    jbe 22f
    mov [rip + vmax], eax
22: movzx eax, byte ptr [rsi + 2]
    cmp eax, 3
    ja .Lfail
    mov [rdi + C_tq], eax
    add rsi, 3
    add rdi, C_SIZE
    inc edx
    jmp 2b
3:  # the image, then coefficients for every block of whole MCUs
    mov rdi, [rip + img]
    mov esi, [rip + width]
    mov edx, [rip + height]
    call img_alloc
    test rax, rax
    jz .Lfail
    mov eax, [rip + hmax]
    shl eax, 3
    mov ecx, eax
    mov eax, [rip + width]
    add eax, ecx
    dec eax
    xor edx, edx
    div ecx
    mov [rip + mcux], eax
    mov eax, [rip + vmax]
    shl eax, 3
    mov ecx, eax
    mov eax, [rip + height]
    add eax, ecx
    dec eax
    xor edx, edx
    div ecx
    mov [rip + mcuy], eax
    lea rbx, [rip + comps]
    xor r13d, r13d
4:  cmp r13d, [rip + ncomp]
    jae .Lnext
    mov eax, [rip + mcux]
    imul eax, [rbx + C_h]
    mov [rbx + C_bw], eax
    mov ecx, [rip + mcuy]
    imul ecx, [rbx + C_v]
    mov [rbx + C_bh], ecx
    imul rax, rcx
    shl rax, 7
    mov rdi, rax
    call mem_alloc_try
    mov [rbx + C_coef], rax
    test rax, rax
    jz .Lbig
    add rbx, C_SIZE
    inc r13d
    jmp 4b

.Ldht:
    test r14d, r14d
    jz .Lnext
    cmp r14d, 17
    jb .Lfail
    movzx eax, byte ptr [r12]
    mov ecx, eax
    shr ecx, 4
    and eax, 15
    cmp ecx, 1
    ja .Lfail
    cmp eax, 3
    ja .Lfail
    lea eax, [rax + rcx*4]
    imul eax, eax, HT_SIZE
    lea rdi, [rip + huff]
    add rdi, rax
    # symbols counted per length
    xor edx, edx
    xor ecx, ecx
1:  movzx eax, byte ptr [r12 + rcx + 1]
    add edx, eax
    inc ecx
    cmp ecx, 16
    jb 1b
    cmp edx, 256
    ja .Lfail
    lea eax, [rdx + 17]
    cmp r14d, eax
    jb .Lfail
    push rax
    push rax
    lea rsi, [r12 + 1]
    lea rdx, [r12 + 17]
    call ht_build
    pop rcx
    pop rcx
    test eax, eax
    jnz .Lfail
    add r12, rcx
    sub r14d, ecx
    jmp .Ldht

.Ldqt:
    test r14d, r14d
    jz .Lnext
    movzx eax, byte ptr [r12]
    mov ecx, eax
    shr ecx, 4                  # 16-bit values when 1
    and eax, 15
    cmp eax, 3
    ja .Lfail
    cmp ecx, 1
    ja .Lfail
    mov edx, 65
    test ecx, ecx
    jz 1f
    mov edx, 129
1:  cmp r14d, edx
    jb .Lfail
    shl eax, 7
    lea rdi, [rip + qt]
    add rdi, rax
    lea r8, [rip + zigzag]
    xor r9d, r9d
2:  movzx r10d, byte ptr [r8 + r9]
    test ecx, ecx
    jnz 3f
    movzx eax, byte ptr [r12 + r9 + 1]
    jmp 4f
3:  LDBE16 eax, ax, [r12 + r9*2 + 1]
4:  mov [rdi + r10*2], ax
    inc r9d
    cmp r9d, 64
    jb 2b
    add r12, rdx
    sub r14d, edx
    jmp .Ldqt

.Ldri:
    cmp r14d, 2
    jb .Lfail
    LDBE16 eax, ax, [r12]
    mov [rip + restart], eax
    jmp .Lnext

.Lapp0:
    cmp r14d, 5
    jb .Lnext
    cmp dword ptr [r12], 0x4649464a     # "JFIF"
    jne .Lnext
    mov dword ptr [rip + jfif], 1
    jmp .Lnext

.Lapp14:
    cmp r14d, 12
    jb .Lnext
    cmp dword ptr [r12], 0x626f6441     # "Adob"
    jne .Lnext
    movzx eax, byte ptr [r12 + 11]
    mov [rip + adobe], eax
    jmp .Lnext

.Lapp1:
    mov rdi, r12
    mov esi, r14d
    call exif_orientation
    jmp .Lnext

.Lsos:
    cmp dword ptr [rip + ncomp], 0
    je .Lfail
    cmp dword ptr [rip + scans], 1000
    jae .Lfinish                # real files have tens; more only costs time
    test r14d, r14d
    jz .Lfail
    movzx ecx, byte ptr [r12]
    lea eax, [rcx - 1]
    cmp eax, 3
    ja .Lfail
    mov [rip + ns], ecx
    lea eax, [rcx*2 + 4]
    cmp r14d, eax
    jb .Lfail
    # components by id, with their tables
    xor r8d, r8d
1:  cmp r8d, [rip + ns]
    jae 3f
    movzx eax, byte ptr [r12 + r8*2 + 1]
    lea rdi, [rip + comps]
    xor r9d, r9d
2:  cmp r9d, [rip + ncomp]
    jae .Lfail
    cmp [rdi + C_id], eax
    je 21f
    add rdi, C_SIZE
    inc r9d
    jmp 2b
21: lea rax, [rip + scomp]
    mov [rax + r8], r9b
    movzx eax, byte ptr [r12 + r8*2 + 2]
    mov ecx, eax
    shr ecx, 4
    and eax, 15
    cmp ecx, 3
    ja .Lfail
    cmp eax, 3
    ja .Lfail
    mov [rdi + C_td], ecx
    mov [rdi + C_ta], eax
    inc r8d
    jmp 1b
3:  lea rsi, [r12 + r8*2 + 1]
    movzx eax, byte ptr [rsi]
    mov [rip + spec_s], eax
    movzx eax, byte ptr [rsi + 1]
    mov [rip + spec_e], eax
    movzx eax, byte ptr [rsi + 2]
    mov ecx, eax
    shr ecx, 4
    and eax, 15
    mov [rip + succ_h], ecx
    mov [rip + succ_l], eax
    # the kind of scan
    lea rax, [rip + blk_baseline]
    cmp dword ptr [rip + progressive], 0
    je 5f
    cmp dword ptr [rip + succ_l], 13
    ja .Lfail
    mov ecx, [rip + spec_s]
    mov edx, [rip + spec_e]
    test ecx, ecx
    jnz 4f
    test edx, edx
    jnz .Lfail
    lea rax, [rip + blk_dc_first]
    cmp dword ptr [rip + succ_h], 0
    je 5f
    lea rax, [rip + blk_dc_refine]
    jmp 5f
4:  cmp edx, 63
    ja .Lfail
    cmp ecx, edx
    ja .Lfail
    cmp dword ptr [rip + ns], 1
    jne .Lfail
    lea rax, [rip + blk_ac_first]
    cmp dword ptr [rip + succ_h], 0
    je 5f
    lea rax, [rip + blk_ac_refine]
5:  mov [rip + block_fn], rax
    mov [rip + pos], r15
    call decode_scan
    inc dword ptr [rip + scans]
    jmp .Lseg

.Lfinish:
    cmp dword ptr [rip + scans], 0
    je .Lfail
    call finish
    test eax, eax
    jnz .Lbig
    call cleanup
    xor eax, eax
    EPILOGUE
.Lunsupported:
    lea rax, [rip + .Lerr_kind]
    mov [rip + g_img_err], rax
    jmp .Lfail
.Lbig:
    lea rax, [rip + .Lerr_big]
    mov [rip + g_img_err], rax
.Lfail:
    call cleanup
    mov eax, -1
    EPILOGUE

cleanup:
    push rbx
    push r12
    push r13
    lea rbx, [rip + comps]
    xor r12d, r12d
1:  mov rdi, [rbx + C_coef]
    call mem_free
    mov rdi, [rbx + C_plane]
    call mem_free
    xor eax, eax
    mov [rbx + C_coef], rax
    mov [rbx + C_plane], rax
    lea r13, [rip + xtabs]
    mov rdi, [r13 + r12*8]
    call mem_free
    mov qword ptr [r13 + r12*8], 0
    lea r13, [rip + bufs]
    mov rdi, [r13 + r12*8]
    call mem_free
    mov qword ptr [r13 + r12*8], 0
    add rbx, C_SIZE
    inc r12d
    cmp r12d, 4
    jb 1b
    mov rdi, [rip + colsum]
    call mem_free
    mov qword ptr [rip + colsum], 0
    pop r13
    pop r12
    pop rbx
    ret

# ht_build(table, counts[16], symbols) -> 0, or -1 for an over-subscribed code
ht_build:
    push rbx
    push r12
    push r13
    push r14
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    xor eax, eax
    mov ecx, (2 << FASTB) / 8
    rep stosq
    xor r8d, r8d                # code
    xor r9d, r9d                # symbols so far
    mov r10d, 1                 # length
1:  mov eax, r9d
    sub eax, r8d
    mov [rbx + HT_delta + r10*4], eax
    movzx r11d, byte ptr [r12 + r10 - 1]
    test r11d, r11d
    jz 4f
2:  mov eax, 1
    mov ecx, r10d
    shl eax, cl
    cmp r8d, eax
    jae 9f                      # more codes than the length has
    # this code into the fast table when it is short enough
    cmp r10d, FASTB
    ja 3f
    movzx eax, byte ptr [r13 + r9]
    mov [rbx + HT_val + r9], al
    mov edx, r10d
    shl edx, 8
    or eax, edx
    mov ecx, FASTB
    sub ecx, r10d
    mov edx, r8d
    shl edx, cl
    mov r14d, 1
    shl r14d, cl
21: mov [rbx + HT_fast + rdx*2], ax
    inc edx
    dec r14d
    jnz 21b
    jmp 31f
3:  movzx eax, byte ptr [r13 + r9]
    mov [rbx + HT_val + r9], al
31: inc r8d
    inc r9d
    dec r11d
    jnz 2b
4:  mov eax, r8d
    mov ecx, 16
    sub ecx, r10d
    shl eax, cl
    mov [rbx + HT_max + r10*4], eax
    add r8d, r8d
    inc r10d
    cmp r10d, 16
    jbe 1b
    mov dword ptr [rbx + HT_max + 17*4], 0xffffffff
    mov [rbx + HT_n], r9d
    xor eax, eax
    jmp 10f
9:  mov eax, -1
10: pop r14
    pop r13
    pop r12
    pop rbx
    ret

# exif_orientation(data, len): orientation from an APP1 Exif segment (TIFF IFD0, tag 0x112)
exif_orientation:
    cmp esi, 14 + 12
    jb 9f
    cmp dword ptr [rdi], 0x66697845     # "Exif"
    jne 9f
    cmp word ptr [rdi + 4], 0
    jne 9f
    add rdi, 6                  # TIFF header
    sub esi, 6
    xor r8d, r8d                # big endian?
    cmp word ptr [rdi], 0x4949  # "II"
    je 1f
    cmp word ptr [rdi], 0x4d4d  # "MM"
    jne 9f
    mov r8d, 1
1:  mov ecx, 4
    call .Lex32
    mov r9d, eax                # IFD0
    lea eax, [r9 + 2]
    cmp eax, esi
    ja 9f
    mov ecx, r9d
    call .Lex16
    mov r10d, eax               # entries
    lea ecx, [r9 + 2]
2:  test r10d, r10d
    jz 9f
    lea eax, [rcx + 12]
    cmp eax, esi
    ja 9f
    push rcx
    call .Lex16
    pop rcx
    cmp eax, 0x112
    jne 3f
    add ecx, 8
    call .Lex16
    lea ecx, [rax - 1]
    cmp ecx, 7
    ja 9f
    mov [rip + orient], eax
    ret
3:  add ecx, 12
    dec r10d
    jmp 2b
9:  ret
# 16 / 32-bit value at rdi + ecx in the TIFF byte order (r8d)
.Lex16:
    movzx eax, word ptr [rdi + rcx]
    test r8d, r8d
    jz 1f
    rol ax, 8
1:  ret
.Lex32:
    mov eax, [rdi + rcx]
    test r8d, r8d
    jz 1f
    bswap eax
1:  ret

# ---------------- entropy decoding ----------------
# While a scan is decoded: r12 bit buffer (MSB first), r13d bits in it, r14 input,
# r15 the component, rbx its block. The helpers clobber rax, rcx, rdx, r8.

# decode_scan(): the scan at pos; pos is left where the scan's data ends
decode_scan:
    PROLOGUE 32
    mov [rip + scan_rsp], rsp
    xor r12d, r12d
    xor r13d, r13d
    mov r14, [rip + pos]
    mov dword ptr [rip + marker], 0
    mov dword ptr [rip + pad], 0
    call reset
    cmp dword ptr [rip + ns], 1
    jne .Lds_mcus
    # one component: its blocks in raster order, as far as the image reaches
    movzx eax, byte ptr [rip + scomp]
    imul eax, eax, C_SIZE
    lea r15, [rip + comps]
    add r15, rax
    mov eax, [rip + width]
    imul eax, [r15 + C_h]
    add eax, [rip + hmax]
    dec eax
    xor edx, edx
    div dword ptr [rip + hmax]
    add eax, 7
    shr eax, 3
    mov [rsp], eax              # blocks across
    mov eax, [rip + height]
    imul eax, [r15 + C_v]
    add eax, [rip + vmax]
    dec eax
    xor edx, edx
    div dword ptr [rip + vmax]
    add eax, 7
    shr eax, 3
    mov [rsp + 4], eax          # down
    mov dword ptr [rsp + 12], 0 # y
1:  mov eax, [rsp + 12]
    cmp eax, [rsp + 4]
    jae .Lds_done
    mov dword ptr [rsp + 8], 0  # x
2:  mov eax, [rsp + 8]
    cmp eax, [rsp]
    jae 3f
    mov eax, [rsp + 12]
    imul eax, [r15 + C_bw]
    add eax, [rsp + 8]
    shl rax, 7
    mov rbx, [r15 + C_coef]
    add rbx, rax
    call [rip + block_fn]
    call after_mcu
    inc dword ptr [rsp + 8]
    jmp 2b
3:  inc dword ptr [rsp + 12]
    jmp 1b
.Lds_mcus:
    mov dword ptr [rsp + 12], 0 # MCU row
4:  mov eax, [rsp + 12]
    cmp eax, [rip + mcuy]
    jae .Lds_done
    mov dword ptr [rsp + 8], 0  # MCU column
5:  mov eax, [rsp + 8]
    cmp eax, [rip + mcux]
    jae 9f
    mov dword ptr [rsp + 16], 0 # scan component
6:  mov eax, [rsp + 16]
    cmp eax, [rip + ns]
    jae 8f
    lea rcx, [rip + scomp]
    movzx eax, byte ptr [rcx + rax]
    imul eax, eax, C_SIZE
    lea r15, [rip + comps]
    add r15, rax
    mov dword ptr [rsp + 20], 0 # block row within the MCU
61: mov eax, [rsp + 20]
    cmp eax, [r15 + C_v]
    jae 7f
    mov dword ptr [rsp + 24], 0 # block column
62: mov eax, [rsp + 24]
    cmp eax, [r15 + C_h]
    jae 63f
    # block (mcu x * h + bx, mcu y * v + by)
    mov eax, [rsp + 12]
    imul eax, [r15 + C_v]
    add eax, [rsp + 20]
    imul eax, [r15 + C_bw]
    mov ecx, [rsp + 8]
    imul ecx, [r15 + C_h]
    add ecx, [rsp + 24]
    add eax, ecx
    shl rax, 7
    mov rbx, [r15 + C_coef]
    add rbx, rax
    call [rip + block_fn]
    inc dword ptr [rsp + 24]
    jmp 62b
63: inc dword ptr [rsp + 20]
    jmp 61b
7:  inc dword ptr [rsp + 16]
    jmp 6b
8:  call after_mcu
    inc dword ptr [rsp + 8]
    jmp 5b
9:  inc dword ptr [rsp + 12]
    jmp 4b
.Lds_abort:
    # a bad code: keep what was decoded, the parser moves on from here
.Lds_done:
    mov [rip + pos], r14
    EPILOGUE

# jbad: a code that does not decode ends the scan
jbad:
    mov rsp, [rip + scan_rsp]
    jmp .Lds_abort

# reset(): predictions and end-of-band runs start over (scan start, restart interval)
reset:
    lea rax, [rip + comps]
    mov dword ptr [rax + C_pred], 0
    mov dword ptr [rax + C_SIZE + C_pred], 0
    mov dword ptr [rax + 2*C_SIZE + C_pred], 0
    mov dword ptr [rax + 3*C_SIZE + C_pred], 0
    mov dword ptr [rip + eobrun], 0
    mov eax, [rip + restart]
    test eax, eax
    jnz 1f
    mov eax, 0x7fffffff
1:  mov [rip + todo], eax
    ret

# after_mcu(): at the end of a restart interval, expect RSTn and start over
after_mcu:
    # the data ran out before the scan did (a file cut short keeps what it has)
    cmp dword ptr [rip + marker], 0
    je 1f
    mov eax, [rip + pad]
    shl eax, 3
    cmp r13d, eax
    ja 1f
    mov eax, [rip + marker]
    and eax, 0xf8
    cmp eax, 0xd0
    je 1f
    mov rsp, [rip + scan_rsp]
    jmp .Lds_done
1:  dec dword ptr [rip + todo]
    jnz 9f
    cmp dword ptr [rip + restart], 0
    je 9f
    xor r12d, r12d
    xor r13d, r13d
    mov eax, [rip + marker]
    test eax, eax
    jnz 3f
    # the marker was not reached yet: find it
1:  lea rax, [r14 + 1]
    cmp rax, [rip + end]
    jae 8f
    cmp byte ptr [r14], 0xff
    jne 2f
    movzx eax, byte ptr [r14 + 1]
    test eax, eax
    jz 2f
    cmp eax, 0xff
    je 2f
    jmp 3f
2:  inc r14
    jmp 1b
3:  mov ecx, eax
    and ecx, 0xf8
    cmp ecx, 0xd0
    jne 8f
    add r14, 2
    mov dword ptr [rip + marker], 0
    mov dword ptr [rip + pad], 0
    jmp reset
8:  # anything else ends the scan
    mov dword ptr [rip + marker], 0xd9
9:  ret

# jfill(): more than 56 bits in the buffer; at a marker or the end of the data zeros come in
jfill:
1:  cmp r13d, 56
    ja 9f
    cmp dword ptr [rip + marker], 0
    jne 7f
    cmp r14, [rip + end]
    jae 4f
    movzx eax, byte ptr [r14]
    cmp eax, 0xff
    jne 3f
    lea rcx, [r14 + 1]
    cmp rcx, [rip + end]
    jae 4f
    movzx ecx, byte ptr [r14 + 1]
    test ecx, ecx
    jnz 6f
    add r14, 2                  # stuffed zero
    jmp 5f
3:  inc r14
    jmp 5f
4:  mov dword ptr [rip + marker], 0xd9
    jmp 7f
6:  mov [rip + marker], ecx     # stays for the parser
7:  xor eax, eax
    inc dword ptr [rip + pad]
5:  mov ecx, 56
    sub ecx, r13d
    shl rax, cl
    or r12, rax
    add r13d, 8
    jmp 1b
9:  ret

# jdecode(table rsi) -> eax symbol
jdecode:
    cmp r13d, 16
    jae 1f
    call jfill
1:  mov rax, r12
    shr rax, 64 - FASTB
    movzx eax, word ptr [rsi + HT_fast + rax*2]
    test eax, eax
    jz 2f
    mov ecx, eax
    shr ecx, 8
    shl r12, cl
    sub r13d, ecx
    and eax, 255
    ret
2:  mov rdx, r12
    shr rdx, 48
    mov ecx, FASTB + 1
3:  cmp edx, [rsi + HT_max + rcx*4]
    jb 4f
    inc ecx
    cmp ecx, 17
    jb 3b
    jmp jbad
4:  mov r8d, ecx
    mov rax, r12
    mov ecx, 64
    sub ecx, r8d
    shr rax, cl
    add eax, [rsi + HT_delta + r8*4]
    cmp eax, [rsi + HT_n]
    jae jbad
    mov ecx, r8d
    shl r12, cl
    sub r13d, ecx
    movzx eax, byte ptr [rsi + HT_val + rax]
    ret

# jbits(n ecx, 1..16) -> eax the next n bits
jbits:
    cmp r13d, ecx
    jae 1f
    mov r8d, ecx
    call jfill
    mov ecx, r8d
1:  mov rax, r12
    shl r12, cl
    sub r13d, ecx
    neg ecx
    add ecx, 64
    shr rax, cl
    ret

# jextend(n ecx, 1..15) -> eax the next n bits as a signed value
jextend:
    mov edx, ecx
    call jbits
    mov ecx, edx
    dec ecx
    mov r8d, 1
    shl r8d, cl
    cmp eax, r8d
    jae 1f
    lea r8d, [r8*2 - 1]
    sub eax, r8d
1:  ret

# jbit() -> eax one bit
jbit:
    cmp r13d, 1
    jae 1f
    call jfill
1:  mov rax, r12
    shr rax, 63
    add r12, r12
    dec r13d
    ret

# DC difference: category from the DC table, then its bits
dc_diff:
    mov eax, [r15 + C_td]
    imul eax, eax, HT_SIZE
    lea rsi, [rip + huff]
    add rsi, rax
    call jdecode
    test eax, eax
    jz 1f
    cmp eax, 15
    ja jbad
    mov ecx, eax
    call jextend
1:  ret

# ac_table() -> rsi
ac_table:
    mov eax, [r15 + C_ta]
    add eax, 4
    imul eax, eax, HT_SIZE
    lea rsi, [rip + huff]
    add rsi, rax
    ret

blk_baseline:
    call dc_diff
    add eax, [r15 + C_pred]
    mov [r15 + C_pred], eax
    mov [rbx], ax
    call ac_table
    mov r9d, 1
1:  cmp r9d, 64
    jae 9f
    call jdecode
    mov ecx, eax
    and ecx, 15
    shr eax, 4
    test ecx, ecx
    jnz 2f
    cmp eax, 15
    jne 9f                      # end of block
    add r9d, 16
    jmp 1b
2:  add r9d, eax
    cmp r9d, 63
    ja jbad
    call jextend
    lea rcx, [rip + zigzag]
    movzx ecx, byte ptr [rcx + r9]
    mov [rbx + rcx*2], ax
    inc r9d
    jmp 1b
9:  ret

blk_dc_first:
    call dc_diff
    add eax, [r15 + C_pred]
    mov [r15 + C_pred], eax
    mov ecx, [rip + succ_l]
    shl eax, cl
    mov [rbx], ax
    ret

blk_dc_refine:
    call jbit
    test eax, eax
    jz 1f
    mov ecx, [rip + succ_l]
    mov eax, 1
    shl eax, cl
    or [rbx], ax
1:  ret

blk_ac_first:
    cmp dword ptr [rip + eobrun], 0
    je 1f
    dec dword ptr [rip + eobrun]
    ret
1:  call ac_table
    mov r9d, [rip + spec_s]
2:  cmp r9d, [rip + spec_e]
    ja 9f
    call jdecode
    mov ecx, eax
    and ecx, 15
    shr eax, 4
    test ecx, ecx
    jnz 4f
    cmp eax, 15
    jne 3f
    add r9d, 16
    jmp 2b
3:  # a run of empty bands
    mov ecx, eax
    mov edx, 1
    shl edx, cl
    dec edx
    mov [rip + eobrun], edx
    test ecx, ecx
    jz 9f
    call jbits
    add [rip + eobrun], eax
    ret
4:  add r9d, eax
    cmp r9d, 63
    ja jbad
    call jextend
    mov ecx, [rip + succ_l]
    shl eax, cl
    lea rcx, [rip + zigzag]
    movzx ecx, byte ptr [rcx + r9]
    mov [rbx + rcx*2], ax
    inc r9d
    jmp 2b
9:  ret

# refinement of AC coefficients (after stb_image)
blk_ac_refine:
    mov ecx, [rip + succ_l]
    mov r11d, 1
    shl r11d, cl                # bit
    cmp dword ptr [rip + eobrun], 0
    je 1f
    dec dword ptr [rip + eobrun]
    mov r9d, [rip + spec_s]
    call refine_rest
    ret
1:  call ac_table
    mov r10, rsi
    mov r9d, [rip + spec_s]
2:  cmp r9d, [rip + spec_e]
    ja 9f
    mov rsi, r10
    call jdecode
    mov edi, eax
    shr edi, 4                  # r
    and eax, 15                 # s
    jnz 4f
    cmp edi, 15
    je 5f
    # end of band run: this block's remaining nonzero coefficients get their bit
    mov ecx, edi
    mov edx, 1
    shl edx, cl
    dec edx
    mov [rip + eobrun], edx
    test ecx, ecx
    jz 3f
    call jbits
    add [rip + eobrun], eax
3:  call refine_rest
9:  ret
4:  cmp eax, 1
    jne jbad
    call jbit
    mov esi, r11d
    test eax, eax
    jnz 41f
    neg esi
41: jmp 6f
5:  xor esi, esi                # zero run of 16
6:  # skip r zero coefficients, refining nonzero ones on the way, then place the new one
    cmp r9d, [rip + spec_e]
    ja 2b
    lea rcx, [rip + zigzag]
    movzx ecx, byte ptr [rcx + r9]
    inc r9d
    movsx eax, word ptr [rbx + rcx*2]
    test eax, eax
    jz 7f
    push rcx
    push rsi
    call jbit
    pop rsi
    pop rcx
    test eax, eax
    jz 6b
    movsx eax, word ptr [rbx + rcx*2]
    test eax, r11d
    jnz 6b
    mov edx, r11d
    test eax, eax
    jg 61f
    neg edx
61: add [rbx + rcx*2], dx
    jmp 6b
7:  test edi, edi
    jnz 8f
    mov [rbx + rcx*2], si
    jmp 2b
8:  dec edi
    jmp 6b

# refine_rest(): from r9d to se, every nonzero coefficient takes a correction bit
refine_rest:
1:  cmp r9d, [rip + spec_e]
    ja 9f
    lea rcx, [rip + zigzag]
    movzx ecx, byte ptr [rcx + r9]
    inc r9d
    movsx eax, word ptr [rbx + rcx*2]
    test eax, eax
    jz 1b
    push rcx
    push rcx
    call jbit
    pop rcx
    pop rcx
    test eax, eax
    jz 1b
    movsx eax, word ptr [rbx + rcx*2]
    test eax, r11d
    jnz 1b
    mov edx, r11d
    test eax, eax
    jg 2f
    neg edx
2:  add [rbx + rcx*2], dx
    jmp 1b
9:  ret

# ---------------- reconstruction ----------------

# finish() -> 0, or -1 without memory: IDCT into planes, color conversion, orientation
finish:
    PROLOGUE 32
    call color_tables
    lea r15, [rip + comps]
    xor r14d, r14d
1:  cmp r14d, [rip + ncomp]
    jae 5f
    mov eax, [r15 + C_bw]
    imul eax, [r15 + C_bh]
    shl rax, 6
    mov rdi, rax
    call mem_alloc_try
    mov [r15 + C_plane], rax
    test rax, rax
    jz 9f
    mov eax, [r15 + C_tq]
    shl eax, 7
    lea rcx, [rip + qt]
    add rax, rcx
    mov [rsp], rax              # quantization table
    mov r13, [r15 + C_coef]
    xor r12d, r12d              # block row
2:  cmp r12d, [r15 + C_bh]
    jae 4f
    xor ebx, ebx                # block column
3:  cmp ebx, [r15 + C_bw]
    jae 31f
    # plane + (row * 8 * bw + column) * 8
    mov eax, r12d
    imul eax, [r15 + C_bw]
    shl rax, 3
    add eax, ebx
    shl rax, 3
    mov rdx, [r15 + C_plane]
    add rdx, rax
    mov rdi, r13
    mov rsi, [rsp]
    mov ecx, [r15 + C_bw]
    shl ecx, 3
    call idct
    sub r13, -128
    inc ebx
    jmp 3b
31: inc r12d
    jmp 2b
4:  mov rdi, [r15 + C_coef]
    call mem_free
    mov qword ptr [r15 + C_coef], 0
    add r15, C_SIZE
    inc r14d
    jmp 1b
5:  call convert
    test eax, eax
    jnz 9f
    cmp dword ptr [rip + orient], 1
    je 8f
    call reorient
    test eax, eax
    jnz 9f
8:  xor eax, eax
    EPILOGUE
9:  mov eax, -1
    EPILOGUE

# IDCT_1D base, step: 8 values at base + k * step -> even part x0-x3 in r9, r10, r11, r8; odd part t0-t3 in eax, ebx, ecx, edx
# (integer IDCT of the IJG, 12 fractional bits, as in stb_image)
.macro IDCT_1D base, st
    mov eax, [\base + 2*\st]
    mov ecx, [\base + 6*\st]
    lea edx, [rax + rcx]
    imul edx, edx, 2217
    imul ecx, ecx, -7567
    add ecx, edx                # t2
    imul eax, eax, 3135
    add eax, edx                # t3
    mov edx, [\base]
    mov ebx, [\base + 4*\st]
    lea r8d, [rdx + rbx]
    shl r8d, 12                 # t0
    sub edx, ebx
    shl edx, 12                 # t1
    lea r9d, [r8 + rax]         # x0
    sub r8d, eax                # x3
    lea r10d, [rdx + rcx]       # x1
    sub edx, ecx
    mov r11d, edx               # x2
    mov eax, [\base + 7*\st]    # t0
    mov ebx, [\base + 5*\st]    # t1
    mov ecx, [\base + 3*\st]    # t2
    mov edx, [\base + 1*\st]    # t3
    lea r12d, [rax + rcx]
    imul r12d, r12d, -8034      # p3
    lea r13d, [rbx + rdx]
    imul r13d, r13d, -1597      # p4
    lea r14d, [rax + rbx]
    add r14d, ecx
    add r14d, edx
    imul r14d, r14d, 4816       # p5
    lea r15d, [rax + rdx]
    imul r15d, r15d, -3685
    add r15d, r14d              # p5 + p1
    lea esi, [rbx + rcx]
    imul esi, esi, -10497
    add r14d, esi               # p5 + p2
    imul edx, edx, 6149
    add edx, r15d
    add edx, r13d               # t3
    imul eax, eax, 1223
    add eax, r15d
    add eax, r12d               # t0
    imul ecx, ecx, 12586
    add ecx, r14d
    add ecx, r12d               # t2
    imul ebx, ebx, 8410
    add ebx, r14d
    add ebx, r13d               # t1
.endm

# COL_OUT x, t, lo, hi: x + t -> slot lo, x - t -> slot hi (int32 slots of val, 8 apart), 2 fraction bits kept
.macro COL_OUT x, t, lo, hi
    mov esi, \x
    add esi, \t
    sar esi, 10
    mov [rdi + \lo*32], esi
    sub \x, \t
    sar \x, 10
    mov [rdi + \hi*32], \x
.endm

# ROW_OUT x, xb, t, lo, hi: bytes, clamped (xb: the low byte of x)
.macro ROW_OUT x, xb, t, lo, hi
    mov esi, \x
    add esi, \t
    sar esi, 17
    cmp esi, 255
    jbe 1f
    not esi
    sar esi, 31
    and esi, 255
1:  mov [rdi + \lo], sil
    sub \x, \t
    sar \x, 17
    cmp \x, 255
    jbe 2f
    not \x
    sar \x, 31
    and \x, 255
2:  mov [rdi + \hi], \xb
.endm

# idct(coefficients int16[64], quantization u16[64], out, stride)
idct:
    PROLOGUE 32
    mov [rsp], rdx
    mov [rsp + 8], rcx
    # a block with only the DC value is flat
    movdqu xmm0, [rdi]
    psrldq xmm0, 2              # drop the DC
    movdqu xmm1, [rdi + 16]
    por xmm0, xmm1
    movdqu xmm1, [rdi + 32]
    por xmm0, xmm1
    movdqu xmm1, [rdi + 48]
    por xmm0, xmm1
    movdqu xmm1, [rdi + 64]
    por xmm0, xmm1
    movdqu xmm1, [rdi + 80]
    por xmm0, xmm1
    movdqu xmm1, [rdi + 96]
    por xmm0, xmm1
    movdqu xmm1, [rdi + 112]
    por xmm0, xmm1
    pxor xmm1, xmm1
    pcmpeqb xmm0, xmm1
    pmovmskb eax, xmm0
    cmp eax, 0xffff
    jne 1f
    movsx eax, word ptr [rdi]
    movzx ecx, word ptr [rsi]
    imul eax, ecx
    shl eax, 14
    add eax, 65536 + (128 << 17)
    sar eax, 17
    cmp eax, 255
    jbe 11f
    not eax
    sar eax, 31
    and eax, 255
11: mov ecx, 0x01010101
    imul eax, ecx
    mov rdi, [rsp]
    mov rcx, [rsp + 8]
    mov edx, 8
12: mov [rdi], eax
    mov [rdi + 4], eax
    add rdi, rcx
    dec edx
    jnz 12b
    EPILOGUE
1:  # dequantize
    lea r8, [rip + blk]
    xor ecx, ecx
2:  movsx eax, word ptr [rdi + rcx*2]
    movzx edx, word ptr [rsi + rcx*2]
    imul eax, edx
    mov [r8 + rcx*4], eax
    inc ecx
    cmp ecx, 64
    jb 2b
    # columns into val, 2 fractional bits kept
    mov dword ptr [rsp + 16], 0
3:  mov eax, [rsp + 16]
    lea rsi, [rip + blk]
    lea rsi, [rsi + rax*4]
    lea rdi, [rip + val]
    lea rdi, [rdi + rax*4]
    mov eax, [rsi + 32]
    or eax, [rsi + 64]
    or eax, [rsi + 96]
    or eax, [rsi + 128]
    or eax, [rsi + 160]
    or eax, [rsi + 192]
    or eax, [rsi + 224]
    jnz 4f
    mov eax, [rsi]
    shl eax, 2
    mov [rdi], eax
    mov [rdi + 32], eax
    mov [rdi + 64], eax
    mov [rdi + 96], eax
    mov [rdi + 128], eax
    mov [rdi + 160], eax
    mov [rdi + 192], eax
    mov [rdi + 224], eax
    jmp 5f
4:  IDCT_1D rsi, 32
    add r9d, 512
    add r10d, 512
    add r11d, 512
    add r8d, 512
    COL_OUT r9d, edx, 0, 7
    COL_OUT r10d, ecx, 1, 6
    COL_OUT r11d, ebx, 2, 5
    COL_OUT r8d, eax, 3, 4
5:  inc dword ptr [rsp + 16]
    cmp dword ptr [rsp + 16], 8
    jb 3b
    # rows into the plane
    mov dword ptr [rsp + 16], 0
6:  mov eax, [rsp + 16]
    lea rsi, [rip + val]
    shl eax, 5
    add rsi, rax
    IDCT_1D rsi, 4
    mov rdi, [rsp]
    mov esi, 65536 + (128 << 17)
    add r9d, esi
    add r10d, esi
    add r11d, esi
    add r8d, esi
    ROW_OUT r9d, r9b, edx, 0, 7
    ROW_OUT r10d, r10b, ecx, 1, 6
    ROW_OUT r11d, r11b, ebx, 2, 5
    ROW_OUT r8d, r8b, eax, 3, 4
    mov rax, [rsp + 8]
    add [rsp], rax
    inc dword ptr [rsp + 16]
    cmp dword ptr [rsp + 16], 8
    jb 6b
    EPILOGUE

# color_tables(): YCbCr -> RGB lookups and the clamp table, once
color_tables:
    cmp dword ptr [rip + tables_ok], 0
    jne 9f
    xor ecx, ecx
1:  lea eax, [rcx - 128]
    imul edx, eax, 91881
    add edx, 32768
    sar edx, 16
    lea r8, [rip + cr_r]
    mov [r8 + rcx*4], edx
    imul edx, eax, 116130
    add edx, 32768
    sar edx, 16
    lea r8, [rip + cb_b]
    mov [r8 + rcx*4], edx
    imul edx, eax, -46802
    lea r8, [rip + cr_g]
    mov [r8 + rcx*4], edx
    imul edx, eax, -22554
    add edx, 32768
    lea r8, [rip + cb_g]
    mov [r8 + rcx*4], edx
    inc ecx
    cmp ecx, 256
    jb 1b
    lea r8, [rip + clamp]
    xor ecx, ecx
2:  lea eax, [rcx - 384]
    test eax, eax
    jns 3f
    xor eax, eax
3:  cmp eax, 255
    jle 4f
    mov eax, 255
4:  mov [r8 + rcx], al
    inc ecx
    cmp ecx, 1024
    jb 2b
    mov dword ptr [rip + tables_ok], 1
9:  ret

# convert() -> 0 or -1: planes into the image's ARGB pixels
#   subsampled components are upsampled like libjpeg does by default: a triangle filter for 2:1 in either
#   direction or both ("fancy upsampling"), replication for other ratios
convert:
    PROLOGUE 32
    lea r15, [rip + comps]
    xor r14d, r14d
1:  cmp r14d, [rip + ncomp]
    jae 3f
    # samples across and down, as far as the image reaches
    mov eax, [rip + width]
    imul eax, [r15 + C_h]
    add eax, [rip + hmax]
    dec eax
    xor edx, edx
    div dword ptr [rip + hmax]
    lea rcx, [rip + cdw]
    mov [rcx + r14*4], eax
    mov eax, [rip + height]
    imul eax, [r15 + C_v]
    add eax, [rip + vmax]
    dec eax
    xor edx, edx
    div dword ptr [rip + vmax]
    lea rcx, [rip + cdh]
    mov [rcx + r14*4], eax
    # the ratios decide how
    mov eax, [rip + hmax]
    xor edx, edx
    div dword ptr [r15 + C_h]
    mov r8d, eax
    mov r10d, edx
    mov eax, [rip + vmax]
    xor edx, edx
    div dword ptr [r15 + C_v]
    mov r9d, eax
    or r10d, edx                # a fraction somewhere
    mov ebx, KIND_BOX
    test r10d, r10d
    jnz 2f
    lea rcx, [rip + cdw]
    mov ecx, [rcx + r14*4]
    lea eax, [r8 + r9*4]        # rh + 4 * rv
    cmp eax, 1 + 4*1
    jne 11f
    mov ebx, KIND_COPY
    jmp 2f
11: cmp eax, 1 + 4*2
    jne 12f
    mov ebx, KIND_V2
    jmp 2f
12: cmp ecx, 2
    jbe 2f
    cmp eax, 2 + 4*1
    jne 13f
    mov ebx, KIND_H2
    jmp 2f
13: cmp eax, 2 + 4*2
    jne 2f
    mov ebx, KIND_H2V2
2:  lea rcx, [rip + ckind]
    mov [rcx + r14*4], ebx
    cmp ebx, KIND_COPY
    je 22f
    # a row of its own
    mov edi, [rip + width]
    add edi, 16
    call mem_alloc_try
    test rax, rax
    jz 9f
    lea rcx, [rip + bufs]
    mov [rcx + r14*8], rax
    cmp ebx, KIND_BOX
    jne 22f
    # replication: the sample column of every pixel column
    mov edi, [rip + width]
    shl edi, 2
    call mem_alloc_try
    test rax, rax
    jz 9f
    lea rcx, [rip + xtabs]
    mov [rcx + r14*8], rax
    mov r12, rax
    xor ebx, ebx
21: cmp ebx, [rip + width]
    jae 22f
    mov eax, ebx
    imul eax, [r15 + C_h]
    xor edx, edx
    div dword ptr [rip + hmax]
    mov [r12 + rbx*4], eax
    inc ebx
    jmp 21b
22: add r15, C_SIZE
    inc r14d
    jmp 1b
3:  mov edi, [rip + width]
    lea rdi, [rdi*4 + 16]
    call mem_alloc_try
    test rax, rax
    jz 9f
    mov [rip + colsum], rax
    mov rax, [rip + img]
    mov rax, [rax + IMG_px]
    mov [rsp], rax              # destination row
    xor r13d, r13d              # y
4:  cmp r13d, [rip + height]
    jae 8f
    lea r15, [rip + comps]
    xor r14d, r14d
5:  cmp r14d, [rip + ncomp]
    jae 7f
    mov ebx, [r15 + C_bw]
    shl ebx, 3                  # plane stride
    lea rax, [rip + bufs]
    mov rdi, [rax + r14*8]      # this component's row
    lea rax, [rip + ckind]
    mov eax, [rax + r14*4]
    cmp eax, KIND_COPY
    je .Lup_copy
    cmp eax, KIND_BOX
    je .Lup_box
    cmp eax, KIND_H2
    je .Lup_h2
    # 2:1 down: the nearer row and the next nearer one, above for even rows, below for odd
    mov eax, r13d
    shr eax, 1
    mov ecx, eax
    test r13d, 1
    jnz 51f
    dec ecx
    jns 52f
    xor ecx, ecx
    jmp 52f
51: inc ecx
    lea rdx, [rip + cdh]
    mov edx, [rdx + r14*4]
    dec edx
    cmp ecx, edx
    cmova ecx, edx
52: imul rax, rbx
    imul rcx, rbx
    mov rsi, [r15 + C_plane]
    lea rdx, [rsi + rcx]        # next nearer
    add rsi, rax                # nearer
    lea rax, [rip + ckind]
    cmp dword ptr [rax + r14*4], KIND_V2
    je .Lup_v2
    # h2v2: 3 * nearer + next nearer per column, then across
    lea rax, [rip + cdw]
    mov ecx, [rax + r14*4]
    mov r8, [rip + colsum]
    xor r9d, r9d
53: movzx eax, byte ptr [rsi + r9]
    lea eax, [rax + rax*2]
    movzx r10d, byte ptr [rdx + r9]
    add eax, r10d
    mov [r8 + r9*4], eax
    inc r9d
    cmp r9d, ecx
    jb 53b
    mov rsi, r8
    mov edx, ecx
    mov r8d, [rip + width]
    mov r9d, 8
    mov r10d, 7
    mov ecx, 4
    call up2
    jmp .Lup_next
.Lup_v2:
    mov ecx, [rip + width]
    mov r8d, 1
    test r13d, 1
    jz 54f
    mov r8d, 2
54: xor r9d, r9d
55: movzx eax, byte ptr [rsi + r9]
    lea eax, [rax + rax*2]
    movzx r10d, byte ptr [rdx + r9]
    add eax, r10d
    add eax, r8d
    shr eax, 2
    mov [rdi + r9], al
    inc r9d
    cmp r9d, ecx
    jb 55b
    jmp .Lup_next
.Lup_h2:
    mov eax, r13d
    imul rax, rbx
    mov rsi, [r15 + C_plane]
    add rsi, rax
    lea rax, [rip + cdw]
    mov ecx, [rax + r14*4]
    mov r8, [rip + colsum]
    xor r9d, r9d
56: movzx eax, byte ptr [rsi + r9]
    mov [r8 + r9*4], eax
    inc r9d
    cmp r9d, ecx
    jb 56b
    mov rsi, r8
    mov edx, ecx
    mov r8d, [rip + width]
    mov r9d, 1
    mov r10d, 2
    mov ecx, 2
    call up2
    jmp .Lup_next
.Lup_box:
    mov eax, r13d
    imul eax, [r15 + C_v]
    xor edx, edx
    div dword ptr [rip + vmax]
    imul rax, rbx
    mov rsi, [r15 + C_plane]
    add rsi, rax
    lea rax, [rip + xtabs]
    mov r8, [rax + r14*8]
    mov ecx, [rip + width]
    xor r9d, r9d
57: mov eax, [r8 + r9*4]
    mov al, [rsi + rax]
    mov [rdi + r9], al
    inc r9d
    cmp r9d, ecx
    jb 57b
    jmp .Lup_next
.Lup_copy:
    mov eax, r13d
    imul rax, rbx
    mov rdi, [r15 + C_plane]
    add rdi, rax
.Lup_next:
    lea rax, [rip + rows]
    mov [rax + r14*8], rdi
    add r15, C_SIZE
    inc r14d
    jmp 5b
7:  mov rdi, [rsp]
    call convert_row
    mov eax, [rip + width]
    shl rax, 2
    add [rsp], rax
    inc r13d
    jmp 4b
8:  xor eax, eax
    EPILOGUE
9:  mov eax, -1
    EPILOGUE

# up2(column values i32 rsi, count edx, out rdi, width r8d, even bias r9d, odd bias r10d, shift ecx):
#   out[2i] = (3 c[i] + c[i-1] + even) >> shift, out[2i+1] = (3 c[i] + c[i+1] + odd) >> shift, edges repeated
up2:
    push rbx
    push r12
    push r13
    lea r12d, [rdx - 1]         # last column
    xor r11d, r11d
1:  lea eax, [r11 + r11]
    cmp eax, r8d
    jae 9f
    mov ebx, [rsi + r11*4]
    lea ebx, [rbx + rbx*2]
    mov r13d, r11d
    test r13d, r13d
    jz 2f
    dec r13d
2:  mov eax, [rsi + r13*4]
    add eax, ebx
    add eax, r9d
    shr eax, cl
    mov [rdi + r11*2], al
    lea eax, [r11 + r11 + 1]
    cmp eax, r8d
    jae 9f
    mov r13d, r11d
    cmp r13d, r12d
    jae 3f
    inc r13d
3:  mov eax, [rsi + r13*4]
    add eax, ebx
    add eax, r10d
    shr eax, cl
    mov [rdi + r11*2 + 1], al
    inc r11d
    jmp 1b
9:  pop r13
    pop r12
    pop rbx
    ret

# convert_row(dst): the gathered rows into pixels
convert_row:
    PROLOGUE
    lea rax, [rip + rows]
    mov r8, [rax]
    mov r9, [rax + 8]
    mov r10, [rax + 16]
    mov r11, [rax + 24]
    mov r12d, [rip + width]
    xor ecx, ecx
    mov eax, [rip + ncomp]
    cmp eax, 1
    je .Lcr_gray
    cmp eax, 4
    je .Lcr_four
    # three components: RGB when their ids say so, or Adobe says untransformed (and no JFIF)
    lea rax, [rip + comps]
    cmp dword ptr [rax + C_id], 'R'
    jne 1f
    cmp dword ptr [rax + C_SIZE + C_id], 'G'
    jne 1f
    cmp dword ptr [rax + 2*C_SIZE + C_id], 'B'
    je .Lcr_rgb
1:  cmp dword ptr [rip + adobe], 0
    jne 2f
    cmp dword ptr [rip + jfif], 0
    je .Lcr_rgb
2:  call ycc_row
    EPILOGUE
.Lcr_rgb:
    movzx eax, byte ptr [r8 + rcx]
    shl eax, 8
    mov al, [r9 + rcx]
    shl eax, 8
    mov al, [r10 + rcx]
    or eax, 0xff000000
    mov [rdi + rcx*4], eax
    inc ecx
    cmp ecx, r12d
    jb .Lcr_rgb
    EPILOGUE
.Lcr_gray:
    movzx eax, byte ptr [r8 + rcx]
    imul eax, eax, 0x010101
    or eax, 0xff000000
    mov [rdi + rcx*4], eax
    inc ecx
    cmp ecx, r12d
    jb .Lcr_gray
    EPILOGUE
.Lcr_four:
    # Adobe CMYK is stored inverted, so c * k / 255 is already red; YCCK is YCbCr of the inverted CMY
    cmp dword ptr [rip + adobe], 2
    jne 3f
    call ycc_row
    xor ecx, ecx
21: mov eax, [rdi + rcx*4]
    not eax
    movzx edx, byte ptr [r11 + rcx]
    call cmyk_px
    mov [rdi + rcx*4], eax
    inc ecx
    cmp ecx, r12d
    jb 21b
    EPILOGUE
3:  movzx eax, byte ptr [r8 + rcx]
    shl eax, 8
    mov al, [r9 + rcx]
    shl eax, 8
    mov al, [r10 + rcx]
    movzx edx, byte ptr [r11 + rcx]
    call cmyk_px
    mov [rdi + rcx*4], eax
    inc ecx
    cmp ecx, r12d
    jb 3b
    EPILOGUE

# cmyk_px(eax 0x??RRGGBB, edx k) -> eax opaque, each channel * k / 255 (clobbers rbx, rsi, r13, r14)
cmyk_px:
    mov esi, eax
    xor eax, eax
    mov ebx, 16
1:  push rcx
    mov ecx, ebx
    mov r13d, esi
    shr r13d, cl
    and r13d, 255
    imul r13d, edx
    add r13d, 128
    mov r14d, r13d
    shr r14d, 8
    add r13d, r14d
    shr r13d, 8
    shl r13d, cl
    or eax, r13d
    pop rcx
    sub ebx, 8
    jns 1b
    or eax, 0xff000000
    ret

# ycc_row(): YCbCr rows r8, r9, r10 into dst rdi, r12d pixels
ycc_row:
    lea rsi, [rip + clamp + 384]
    lea r13, [rip + cr_r]
    lea r14, [rip + cb_b]
    lea r15, [rip + cb_g]
    lea r11, [rip + cr_g]
    xor ecx, ecx
1:  movzx edx, byte ptr [r8 + rcx]      # Y
    movzx eax, byte ptr [r9 + rcx]      # Cb
    movzx ebx, byte ptr [r10 + rcx]     # Cr
    push rcx
    mov ecx, [r14 + rax*4]
    add ecx, edx
    movsxd rcx, ecx
    movzx ecx, byte ptr [rsi + rcx]     # blue
    mov eax, [r15 + rax*4]
    add eax, [r11 + rbx*4]
    sar eax, 16
    add eax, edx
    cdqe
    movzx eax, byte ptr [rsi + rax]     # green
    shl eax, 8
    or ecx, eax
    mov eax, [r13 + rbx*4]
    add eax, edx
    cdqe
    movzx eax, byte ptr [rsi + rax]     # red
    shl eax, 16
    or eax, ecx
    or eax, 0xff000000
    pop rcx
    mov [rdi + rcx*4], eax
    inc ecx
    cmp ecx, r12d
    jb 1b
    lea rax, [rip + rows]
    mov r11, [rax + 24]
    ret

# reorient() -> 0 or -1: apply the EXIF orientation (2-8) to the image
reorient:
    PROLOGUE 16
    mov rbx, [rip + img]
    mov r12d, [rbx + IMG_w]
    mov r13d, [rbx + IMG_h]
    mov eax, r12d
    imul rax, r13
    lea rdi, [rax*4]
    call mem_alloc_try
    test rax, rax
    jz 9f
    mov r14, rax                # new pixels
    # start, step along a new row, step to the next new row (in source pixels)
    mov eax, [rip + orient]
    mov ecx, r12d               # w
    mov edx, r13d               # h
    lea r8d, [rdx - 1]
    imul r8d, ecx               # (h - 1) * w
    lea r9d, [rcx - 1]          # w - 1
    mov r10d, ecx
    neg r10d                    # -w
    cmp eax, 2
    jne 2f
    mov esi, r9d
    mov edi, -1
    mov r11d, ecx
    jmp 10f
2:  cmp eax, 3
    jne 3f
    lea esi, [r8 + r9]
    mov edi, -1
    mov r11d, r10d
    jmp 10f
3:  cmp eax, 4
    jne 5f
    mov esi, r8d
    mov edi, 1
    mov r11d, r10d
    jmp 10f
5:  cmp eax, 5
    jne 6f
    xor esi, esi
    mov edi, ecx
    mov r11d, 1
    jmp 11f
6:  cmp eax, 6
    jne 7f
    mov esi, r8d
    mov edi, r10d
    mov r11d, 1
    jmp 11f
7:  cmp eax, 7
    jne 8f
    lea esi, [r8 + r9]
    mov edi, r10d
    mov r11d, -1
    jmp 11f
8:  mov esi, r9d
    mov edi, ecx
    mov r11d, -1
11: # 5-8 swap the sides
    xchg r12d, r13d
10: movsxd rsi, esi
    movsxd rdi, edi
    movsxd r11, r11d
    mov r15, [rbx + IMG_px]
    mov rdx, r14
    xor r8d, r8d                # new row
12: cmp r8d, r13d
    jae 14f
    mov r9, rsi                 # source index
    mov r10d, r12d
13: mov eax, [r15 + r9*4]
    mov [rdx], eax
    add rdx, 4
    add r9, rdi
    dec r10d
    jnz 13b
    add rsi, r11
    inc r8d
    jmp 12b
14: mov rdi, r15
    call mem_free
    mov [rbx + IMG_px], r14
    mov [rbx + IMG_w], r12d
    mov [rbx + IMG_h], r13d
    xor eax, eax
    EPILOGUE
9:  mov eax, -1
    EPILOGUE

.section .rodata
.Lerr_kind: .asciz "This kind of JPEG (lossless, arithmetic coded or 12-bit) is not supported"
.Lerr_big: .asciz "The image is too large to show"
zigzag:
    .byte 0, 1, 8, 16, 9, 2, 3, 10, 17, 24, 32, 25, 18, 11, 4, 5
    .byte 12, 19, 26, 33, 40, 48, 41, 34, 27, 20, 13, 6, 7, 14, 21, 28
    .byte 35, 42, 49, 56, 57, 50, 43, 36, 29, 22, 15, 23, 30, 37, 44, 51
    .byte 58, 59, 52, 45, 38, 31, 39, 46, 53, 60, 61, 54, 47, 55, 62, 63
