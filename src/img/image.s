# images: format detection, decoding into premultiplied ARGB
.include "raftaar.inc"

.bss
.p2align 3
.globl g_img_err
g_img_err: .quad 0              # why the last image_decode failed (cstr)
head: .zero 64

.text

# image_probe(path) -> IMF_* from the first bytes of the file, 0 if it is not an image we read
FN image_probe
    PROLOGUE
    mov rbx, rdi
    call file_open_read
    test rax, rax
    js 8f
    mov r12d, eax
    mov edi, eax
    lea rsi, [rip + head]
    mov edx, 64
    SYS SYS_read
    mov r13, rax
    mov edi, r12d
    SYS SYS_close
    test r13, r13
    jle 8f
    lea rdi, [rip + head]
    mov rsi, r13
    mov rdx, rbx
    call image_sniff
    EPILOGUE
8:  xor eax, eax
    EPILOGUE

# image_sniff(ptr, len, path) -> IMF_* or 0 ; ptr holds the file's first bytes (64 when it has them)
FN image_sniff
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    # PNG
    cmp r12, 8
    jb 1f
    mov rax, 0x0a1a0a0d474e5089
    cmp [rbx], rax
    jne 1f
    mov eax, IMF_PNG
    EPILOGUE
1:  # JPEG
    cmp r12, 3
    jb 2f
    cmp word ptr [rbx], 0xd8ff
    jne 2f
    cmp byte ptr [rbx + 2], 0xff
    jne 2f
    mov eax, IMF_JPEG
    EPILOGUE
2:  # GIF87a / GIF89a
    cmp r12, 6
    jb 3f
    cmp dword ptr [rbx], 0x38464947
    jne 3f
    cmp word ptr [rbx + 4], 0x6137
    je 21f
    cmp word ptr [rbx + 4], 0x6139
    jne 3f
21: mov eax, IMF_GIF
    EPILOGUE
3:  # BMP: "BM" and a known header size
    cmp r12, 18
    jb 4f
    cmp word ptr [rbx], 0x4d42
    jne 4f
    mov eax, [rbx + 14]
    cmp eax, 12
    je 31f
    cmp eax, 40
    je 31f
    cmp eax, 52
    je 31f
    cmp eax, 56
    je 31f
    cmp eax, 64
    je 31f
    cmp eax, 108
    je 31f
    cmp eax, 124
    jne 4f
31: mov eax, IMF_BMP
    EPILOGUE
4:  # QOI
    cmp r12, 14
    jb 5f
    cmp dword ptr [rbx], 0x66696f71
    jne 5f
    mov eax, IMF_QOI
    EPILOGUE
5:  # ICO / CUR: reserved 0, type 1 or 2, some entries, the first one plausible
    cmp r12, 22
    jb 6f
    cmp word ptr [rbx], 0
    jne 6f
    movzx eax, word ptr [rbx + 2]
    dec eax
    cmp eax, 1
    ja 6f
    movzx ecx, word ptr [rbx + 4]
    test ecx, ecx
    jz 6f
    cmp byte ptr [rbx + 9], 0
    jne 6f
    shl ecx, 4
    add ecx, 6
    cmp [rbx + 18], ecx
    jb 6f
    mov eax, IMF_ICO
    EPILOGUE
6:  # the rest have no signature to speak of: the extension decides
    test r13, r13
    jz 9f
    mov rdi, r13
    call strlen
    mov rdi, r13
    mov rsi, rax
    call path_ext
    mov r13, rax
    mov r14, rdx
    # PNM: P1..P6 then a blank
    mov rdi, r13
    mov rsi, r14
    lea rdx, [rip + .Lext_pnm]
    call ext_in
    test eax, eax
    jz 7f
    cmp r12, 3
    jb 9f
    cmp byte ptr [rbx], 'P'
    jne 9f
    movzx eax, byte ptr [rbx + 1]
    sub eax, '1'
    cmp eax, 5
    ja 9f
    movzx eax, byte ptr [rbx + 2]     # then a blank
    cmp eax, ' '
    je 61f
    sub eax, 9
    cmp eax, 4
    ja 9f
61: mov eax, IMF_PNM
    EPILOGUE
7:  # TGA: sane header fields
    mov rdi, r13
    mov rsi, r14
    lea rdx, [rip + .Lext_tga]
    call ext_in
    test eax, eax
    jz 9f
    cmp r12, 18
    jb 9f
    cmp byte ptr [rbx + 1], 1
    ja 9f
    movzx eax, byte ptr [rbx + 2]
    and eax, ~8
    dec eax
    cmp eax, 2
    ja 9f
    cmp word ptr [rbx + 12], 0
    je 9f
    cmp word ptr [rbx + 14], 0
    je 9f
    movzx eax, byte ptr [rbx + 16]
    cmp eax, 8
    je 71f
    cmp eax, 15
    je 71f
    cmp eax, 16
    je 71f
    cmp eax, 24
    je 71f
    cmp eax, 32
    jne 9f
71: mov eax, IMF_TGA
    EPILOGUE
9:  xor eax, eax
    EPILOGUE

# ext_in(ext, len, list) -> 1 if ext is one of the space separated words of list (ignoring case)
ext_in:
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    test r12, r12
    jz 9f
1:  cmp byte ptr [r13], 0
    je 9f
    xor ecx, ecx
2:  mov al, [r13 + rcx]
    test al, al
    jz 3f
    cmp al, ' '
    je 3f
    inc ecx
    jmp 2b
3:  mov r14, rcx
    mov rdi, rbx
    mov rsi, r12
    mov rdx, r13
    call str_ieq
    test eax, eax
    jnz 8f
    add r13, r14
    cmp byte ptr [r13], ' '
    jne 1b
    inc r13
    jmp 1b
8:  mov eax, 1
    EPILOGUE
9:  xor eax, eax
    EPILOGUE

# image_decode(ptr, len, fmt, IMG*) -> 0, or -1 with g_img_err set
FN image_decode
    PROLOGUE
    mov rbx, rcx
    mov r12d, edx
    lea rax, [rip + .Lerr_bad]
    mov [rip + g_img_err], rax
    mov qword ptr [rbx + IMG_px], 0
    mov qword ptr [rbx + IMG_w], 0
    mov [rbx + IMG_fmt], r12d
    mov dword ptr [rbx + IMG_opaque], 0
    mov rdx, rbx
    lea eax, [r12 - 1]
    cmp eax, IMF_TGA - 1
    ja 8f
    lea rcx, [rip + decoders]
    call [rcx + rax*8]
    test eax, eax
    jnz 8f
    cmp qword ptr [rbx + IMG_px], 0
    je 8f
    mov rdi, rbx
    call img_finish
    xor eax, eax
    EPILOGUE
8:  mov rdi, [rbx + IMG_px]
    call mem_free
    mov qword ptr [rbx + IMG_px], 0
    mov eax, -1
    EPILOGUE

# image_free(IMG*)
FN image_free
    push rbx
    mov rbx, rdi
    mov rdi, [rbx + IMG_px]
    call mem_free
    mov qword ptr [rbx + IMG_px], 0
    pop rbx
    ret

# img_alloc(IMG*, w, h) -> pixels (zeroed) or 0 when the size is out of bounds or memory is short
FN img_alloc
    push rbx
    mov rbx, rdi
    lea eax, [rsi - 1]
    cmp eax, IMG_MAXDIM
    jae 8f
    lea eax, [rdx - 1]
    cmp eax, IMG_MAXDIM
    jae 8f
    mov eax, esi
    mov ecx, edx
    imul rax, rcx
    cmp rax, IMG_MAXPX
    ja 8f
    mov [rbx + IMG_w], esi
    mov [rbx + IMG_h], edx
    mov rdi, [rbx + IMG_px]
    push rax
    call mem_free
    pop rdi
    shl rdi, 2
    call mem_alloc_try
    mov [rbx + IMG_px], rax
    test rax, rax
    jz 8f
    pop rbx
    ret
8:  lea rax, [rip + .Lerr_big]
    mov [rip + g_img_err], rax
    xor eax, eax
    pop rbx
    ret

# img_finish(IMG*): premultiply alpha, note whether the image is opaque
img_finish:
    push rbx
    push r12
    mov r12, rdi
    mov rdi, [r12 + IMG_px]
    mov eax, [r12 + IMG_w]
    mov esi, [r12 + IMG_h]
    imul rsi, rax
    mov r11d, 1                 # opaque so far
    xor ecx, ecx
1:  cmp rcx, rsi
    jae 4f
    mov eax, [rdi + rcx*4]
    cmp eax, 0xff000000
    jae 3f
    xor r11d, r11d
    mov ebx, eax
    shr ebx, 24
    jnz 2f
    mov dword ptr [rdi + rcx*4], 0
    jmp 3f
2:  # c * a / 255, rounded, for red and blue at once, then green
    mov edx, eax
    and edx, 0xff00ff
    imul edx, ebx
    add edx, 0x800080
    mov r8d, edx
    shr r8d, 8
    and r8d, 0xff00ff
    add edx, r8d
    shr edx, 8
    and edx, 0xff00ff
    mov r8d, eax
    shr r8d, 8
    and r8d, 0xff
    imul r8d, ebx
    add r8d, 128
    mov r9d, r8d
    shr r9d, 8
    add r8d, r9d
    and r8d, 0xff00
    or edx, r8d
    shl ebx, 24
    or edx, ebx
    mov [rdi + rcx*4], edx
3:  inc rcx
    jmp 1b
4:  mov [r12 + IMG_opaque], r11d
    pop r12
    pop rbx
    ret

# image_format_name(fmt) -> cstr
FN image_format_name
    lea eax, [rdi - 1]
    cmp eax, IMF_TGA - 1
    ja 1f
    lea rcx, [rip + fmt_names]
    mov rax, [rcx + rax*8]
    ret
1:  lea rax, [rip + .Lempty]
    ret

.section .rodata
.Lext_pnm: .asciz "pbm pgm ppm pnm"
.Lext_tga: .asciz "tga"
.Lempty: .asciz ""
.Lerr_bad: .asciz "The image data is damaged or in a variant raftaar cannot read"
.Lerr_big: .asciz "The image is too large to show"
.Lf1: .asciz "PNG"
.Lf2: .asciz "JPEG"
.Lf3: .asciz "GIF"
.Lf4: .asciz "BMP"
.Lf5: .asciz "ICO"
.Lf6: .asciz "QOI"
.Lf7: .asciz "PNM"
.Lf8: .asciz "TGA"
.p2align 3
fmt_names: .quad .Lf1, .Lf2, .Lf3, .Lf4, .Lf5, .Lf6, .Lf7, .Lf8
decoders: .quad png_decode, jpeg_decode, gif_decode, bmp_decode, ico_decode, qoi_decode, pnm_decode, tga_decode
