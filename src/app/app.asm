; src/app/app.asm
; Stage 2 - Reloj/Cronometro con Alarma application.
; Loaded by the Stage 1 bootloader (src/boot/boot.asm) at 0x0000:0x8000
; and executed in 16-bit real mode. DS=ES=SS=0 and SP are inherited from
; Stage 1, so no extra segment setup is needed here.
;
; Implemented: confirmation prompt, Clock Mode (BIOS RTC via INT 1Ah),
; Stopwatch Mode (start/pause/reset, timed via the INT 1Ah tick counter),
; a dedicated key to switch modes, ESC to finish the program.
; Pending: Alarm.

bits 16
org 0x8000

AppStart:
    mov si, ConfirmMsg
    call PrintString

    xor ah, ah
    int 0x16                 ; Block until a key is pressed

    call ShowTitle

MainLoop:
    cmp byte [Mode], 0
    je DrawClock
    jmp DrawStopwatch

; RTC time via BIOS INT 1Ah/AH=02h returns BCD: CH=hours, CL=minutes, DH=seconds.
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

DrawStopwatch:
    call GetStopwatchTicks    ; AX = elapsed ticks (~18.2 ticks/sec)
    xor dx, dx
    mov cx, 18
    div cx                    ; AX = elapsed seconds (approx)
    xor dx, dx
    mov cx, 60
    div cx                    ; AX = minutes, DX = seconds
    push dx
    call SetCursorRow2
    call PrintDec2            ; minutes (AL)
    mov al, ':'
    call PrintChar
    pop ax
    call PrintDec2            ; seconds (AL)
    jmp KeyCheck

KeyCheck:
    mov ah, 0x01
    int 0x16
    jz MainLoop
    xor ah, ah
    int 0x16
    cmp al, 0x1b              ; ESC -> finish
    je Finish
    cmp al, 'm'
    je SwitchMode
    cmp al, 'M'
    je SwitchMode
    cmp byte [Mode], 0
    je MainLoop               ; S/R only apply in Stopwatch Mode
    cmp al, 's'
    je DoToggle
    cmp al, 'S'
    je DoToggle
    cmp al, 'r'
    je DoReset
    cmp al, 'R'
    je DoReset
    jmp MainLoop

SwitchMode:
    xor byte [Mode], 1
    call ShowTitle
    jmp MainLoop

DoToggle:
    call ToggleStopwatch
    jmp MainLoop

DoReset:
    mov word [SwElapsed], 0
    mov byte [SwRunning], 0
    jmp MainLoop

Finish:
    call ClearScreen
    mov si, ExitMsg
    call PrintString
.Hang:
    hlt
    jmp .Hang

; --------------------------------------------------------------------
; Helper routines
; --------------------------------------------------------------------

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
    mov ch, 0x20      ; bit 5 en 1 = cursor oculto
    mov cl, 0x00
    int 0x10
    pop cx
    pop ax
    ret

ShowTitle:
    call ClearScreen
    call HideCursor
    cmp byte [Mode], 0
    je .C
    mov si, SwTitle
    call PrintString
    ret
.C:
    mov si, ClockTitle
    call PrintString
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

; Returns total elapsed stopwatch ticks in AX (running or paused).
GetStopwatchTicks:
    push cx
    push dx
    cmp byte [SwRunning], 0
    je .Paused
    xor ah, ah
    int 0x1a                  ; DX = low word of ticks since midnight
    mov ax, dx
    sub ax, [SwBase]
    add ax, [SwElapsed]
    jmp .Done
.Paused:
    mov ax, [SwElapsed]
.Done:
    pop dx
    pop cx
    ret

; Toggles between running and paused, accumulating elapsed time.
ToggleStopwatch:
    cmp byte [SwRunning], 0
    je .StartIt
    call GetStopwatchTicks
    mov [SwElapsed], ax
    mov byte [SwRunning], 0
    ret
.StartIt:
    xor ah, ah
    int 0x1a
    mov [SwBase], dx
    mov byte [SwRunning], 1
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

; --------------------------------------------------------------------
; State
; --------------------------------------------------------------------
Mode      db 0          ; 0 = Clock, 1 = Stopwatch
SwRunning db 0          ; 0 = paused, 1 = running
SwBase    dw 0          ; tick count when Stopwatch was last (re)started
SwElapsed dw 0          ; accumulated elapsed ticks while paused

ConfirmMsg db 'Presione una tecla para continuar...', 13, 10, 0
ClockTitle db 'Modo Reloj   (M: cambiar modo, ESC: salir)', 13, 10, 0
SwTitle    db 'Modo Cronometro   (S: iniciar/pausar, R: reiniciar, M: modo, ESC: salir)', 13, 10, 0
ExitMsg    db 13, 10, 'Programa finalizado.', 0