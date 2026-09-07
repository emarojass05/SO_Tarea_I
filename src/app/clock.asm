; src/app/clock.asm
; --------------------------------------------------------------------
; Modo Reloj: shows the real system time, read straight from the RTC
; via BIOS INT 1Ah/AH=02h (returns BCD: CH=hours, CL=minutes, DH=seconds).
; --------------------------------------------------------------------
DrawClock:
    mov ah, 0x02
    int 0x1a
    push cx
    push dx
    call SetCursorRow2
    pop dx
    pop cx

    mov al, ch
    call PrintBcd
    mov al, ':'
    call PrintChar
    mov al, cl
    call PrintBcd
    mov al, ':'
    call PrintChar
    mov al, dh
    call PrintBcd
    jmp KeyCheck
