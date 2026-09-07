; src/app/video.asm
; --------------------------------------------------------------------
; Low-level screen/keyboard helpers shared by every mode (Reloj,
; Cronometro, Alarma). No mode-specific state lives here.
; --------------------------------------------------------------------

; SI -> null-terminated string
PrintString:
    pusha
    mov ah, 0x0E
.Loop:
    lodsb
    cmp al, 0
    je .Done
    int 0x10
    jmp .Loop
.Done:
    popa
    ret

; AL -> character
PrintChar:
    push ax
    mov ah, 0x0E
    int 0x10
    pop ax
    ret

; AL -> BCD byte, printed as two ASCII digits
PrintBcd:
    push ax
    push bx
    mov bl, al
    shr al, 4
    add al, '0'
    mov ah, 0x0E
    int 0x10
    mov al, bl
    and al, 0x0F
    add al, '0'
    mov ah, 0x0E
    int 0x10
    pop bx
    pop ax
    ret

; AL -> binary value 0-99, printed as two ASCII digits
PrintDec2:
    push ax
    push bx
    xor ah, ah
    mov bl, 10
    div bl
    add al, '0'
    push ax
    mov ah, 0x0E
    int 0x10
    pop ax
    mov al, ah
    add al, '0'
    mov ah, 0x0E
    int 0x10
    pop bx
    pop ax
    ret

ClearScreen:
    push ax
    mov ax, 0x0003
    int 0x10
    pop ax
    ret

HideCursor:
    push ax
    push cx
    mov ah, 0x01
    mov ch, 0x20      ; bit 5 set = cursor hidden
    mov cl, 0x00
    int 0x10
    pop cx
    pop ax
    ret

; Restores the standard 80x25 text-mode cursor shape (start=6, end=7),
; undoing HideCursor. Called on exit so the terminal isn't left with an
; invisible cursor after the program halts.
ShowCursor:
    push ax
    push cx
    mov ah, 0x01
    mov ch, 0x06
    mov cl, 0x07
    int 0x10
    pop cx
    pop ax
    ret

SetCursorRow2:
    push ax
    push bx
    mov ah, 0x02
    mov bh, 0
    mov dh, 2
    mov dl, 0
    int 0x10
    pop bx
    pop ax
    ret

; Fills the whole screen with the attribute in [FlashAttr] (alarm.asm)
; and homes the cursor, used by AlarmRing's blink effect.
FillScreenAttr:
    pusha
    mov ah, 0x06
    xor al, al
    mov bh, [FlashAttr]
    xor cx, cx
    mov dx, 0x184F
    int 0x10
    mov ah, 0x02
    mov bh, 0
    xor dx, dx
    int 0x10
    popa
    ret

; Blocking read of a single '0'-'9' key; echoes it and returns 0-9 in AL.
ReadDigit:
    push bx
.Wait:
    xor ah, ah
    int 0x16
    cmp al, '0'
    jb .Wait
    cmp al, '9'
    ja .Wait
    mov bl, al
    call PrintChar
    mov al, bl
    sub al, '0'
    pop bx
    ret

; Short PC-speaker beep (PIT channel 2, ~1000 Hz) via ports 0x43/0x42/0x61.
Beep:
    pusha
    mov al, 0xB6
    out 0x43, al
    mov ax, 1193
    out 0x42, al
    mov al, ah
    out 0x42, al
    in al, 0x61
    or al, 0x03
    out 0x61, al
    call Delay
    in al, 0x61
    and al, 0xFC
    out 0x61, al
    popa
    ret

; Crude busy-wait, used both to hold the beep tone and to pace the blink.
Delay:
    push cx
.D1:
    mov cx, 0xFFFF
.D2:
    dec cx
    jnz .D2
    dec word [DelayOuter]
    jnz .D1
    mov word [DelayOuter], 3
    pop cx
    ret

DelayOuter dw 3
