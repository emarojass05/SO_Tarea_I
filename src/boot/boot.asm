; src/boot/boot.asm
; Bootloader + Clock Mode for the Clock/Stopwatch with Alarm application.
; Loaded by the BIOS at 0x7C00, 16-bit real mode.
;
; Implemented: welcome + confirmation prompt, Clock Mode (BIOS RTC via
; INT 1Ah), ESC to exit.
; Pending: Stopwatch Mode, mode switch, stopwatch reset, alarm.

bits 16
org 0x7C00

Start:
    cli
    xor ax, ax
    mov ds, ax
    mov es, ax
    mov ss, ax
    mov sp, 0x7C00
    sti

    mov si, WelcomeMsg
    call PrintString

    mov si, ConfirmMsg
    call PrintString

    xor ah, ah
    int 0x16                 ; Block until a key is pressed

    call ClearScreen

    mov si, TitleMsg
    call PrintString

; RTC time via BIOS INT 1Ah/AH=02h returns BCD: CH=hours, CL=minutes, DH=seconds.
ClockMode:
    mov ah, 0x02
    int 0x1a
    push cx
    push dx

    mov ah, 0x02              ; Set cursor position
    mov bh, 0
    mov dh, 2
    mov dl, 0
    int 0x10

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

.CheckKey:
    mov ah, 0x01
    int 0x16
    jz ClockMode
    xor ah, ah
    int 0x16
    cmp al, 0x1b              ; ESC
    je Finish
    jmp ClockMode

Finish:
    call ClearScreen
    mov si, ExitMsg
    call PrintString
.Hang:
    hlt
    jmp .Hang

ClearScreen:
    push ax
    mov ax, 0x0003
    int 0x10
    pop ax
    ret

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

WelcomeMsg db 'Bienvenido - Reloj/Cronometro con Alarma', 13, 10, 0
ConfirmMsg db 'Presione una tecla para continuar...', 13, 10, 0
TitleMsg   db 'Modo Reloj (ESC para finalizar)', 13, 10, 0
ExitMsg    db 13, 10, 'Programa finalizado.', 0

times 510-($-$$) db 0
dw 0xAA55
