; src/app/app.asm

bits 16
org 0x8000

AppStart:
    mov si, ConfirmMsg
    call PrintString

    xor ah, ah
    int 0x16                 ; Block until a key is pressed

    call InstallRtcVector     ; hook the RTC's own alarm interrupt (IRQ8/INT 70h)
    call ShowTitle

MainLoop:
    ; AlarmTriggered is set directly by RtcAlarmISR (rtc_alarm.asm), fired
    ; by the RTC chip's own hardware alarm interrupt - no need to poll
    ; INT 1Ah here anymore.
    cmp byte [AlarmTriggered], 0
    jne AlarmRing

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
    cmp al, 'a'
    je DoSetAlarm
    cmp al, 'A'
    je DoSetAlarm
    cmp al, 'c'
    je DoCancelAlarm
    cmp al, 'C'
    je DoCancelAlarm
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

DoSetAlarm:
    call SetAlarmPrompt
    jmp MainLoop

DoCancelAlarm:
    call DisableRtcAlarmInterrupt
    mov byte [AlarmSet], 0
    mov byte [AlarmTriggered], 0
    call ShowTitle
    jmp MainLoop

Finish:
    call DisableRtcAlarmInterrupt
    call RestoreRtcVector
    call ClearScreen
    mov si, ExitMsg
    call PrintString
.Hang:
    hlt
    jmp .Hang

; --------------------------------------------------------------------
; Alarm
; --------------------------------------------------------------------
; The alarm match itself is now detected in hardware by the RTC chip
; (see rtc_alarm.asm: EnableRtcAlarmInterrupt / RtcAlarmISR), which sets
; [AlarmTriggered] via a real IRQ8 interrupt instead of being polled
; here.

; Full-screen blink + speaker beep, looping until 'C' cancels it.
AlarmRing:
    call ClearScreen
.RingLoop:
    xor byte [FlashState], 1
    cmp byte [FlashState], 0
    je .ColorA
    mov byte [FlashAttr], 0x4F     ; white on red
    jmp .DoFlash
.ColorA:
    mov byte [FlashAttr], 0x1F     ; white on blue
.DoFlash:
    call FillScreenAttr
    mov si, AlarmMsg
    call PrintString
    call Beep

    mov ah, 0x01
    int 0x16
    jz .NoKeyRing
    xor ah, ah
    int 0x16
    cmp al, 'c'
    je .CancelAlarm
    cmp al, 'C'
    je .CancelAlarm
.NoKeyRing:
    call Delay
    jmp .RingLoop
.CancelAlarm:
    call DisableRtcAlarmInterrupt
    mov byte [AlarmSet], 0
    mov byte [AlarmTriggered], 0
    call ShowTitle
    jmp MainLoop

; Interactive HH:MM prompt. Reads 4 digit keys (echoed as typed),
; clamps to valid ranges, stores as BCD (same format INT 1Ah returns)
; so the RTC's own alarm registers can be programmed directly from it.
SetAlarmPrompt:
    call ClearScreen
    mov si, SetAlarmMsg
    call PrintString

    call ReadDigit
    mov [InHH], al
    call ReadDigit
    mov bl, al
    mov al, [InHH]
    shl al, 4
    or al, bl
    cmp al, 0x23
    jbe .HourOk
    mov al, 0x23
.HourOk:
    mov [AlarmHour], al

    mov al, ':'
    call PrintChar

    call ReadDigit
    mov [InMM], al
    call ReadDigit
    mov bl, al
    mov al, [InMM]
    shl al, 4
    or al, bl
    cmp al, 0x59
    jbe .MinOk
    mov al, 0x59
.MinOk:
    mov [AlarmMin], al

    mov byte [AlarmSet], 1
    mov byte [AlarmTriggered], 0
    call EnableRtcAlarmInterrupt   ; arm the RTC's own hardware alarm

    mov si, AlarmSetOkMsg
    call PrintString
    xor ah, ah
    int 0x16
    call ShowTitle
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

; Fills the whole screen with the attribute in [FlashAttr] and homes
; the cursor, used for the blink effect.
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

; --------------------------------------------------------------------
; Helper routines
; --------------------------------------------------------------------

ClearScreen:
    push ax
    mov ax, 0x0003
    int 0x10
    pop ax
    ret

ShowTitle:
    call ClearScreen
    call HideCursor
    cmp byte [Mode], 0
    je .C
    mov si, SwTitle
    call PrintString
    call PrintAlarmStatus
    ret
.C:
    mov si, ClockTitle
    call PrintString
    call PrintAlarmStatus
    ret

PrintAlarmStatus:
    push ax
    mov si, AlarmLabel
    call PrintString
    cmp byte [AlarmSet], 0
    je .None
    mov al, [AlarmHour]
    call PrintBcd
    mov al, ':'
    call PrintChar
    mov al, [AlarmMin]
    call PrintBcd
    jmp .Done
.None:
    mov si, NoAlarmMsg
    call PrintString
.Done:
    mov al, 13
    call PrintChar
    mov al, 10
    call PrintChar
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
Mode           db 0          ; 0 = Clock, 1 = Stopwatch
SwRunning      db 0          ; 0 = paused, 1 = running
SwBase         dw 0          ; tick count when Stopwatch was last (re)started
SwElapsed      dw 0          ; accumulated elapsed ticks while paused

AlarmSet       db 0          ; 0 = no alarm configured, 1 = configured
AlarmTriggered db 0          ; 0 = not ringing, 1 = ringing
AlarmHour      db 0          ; BCD, same format as INT 1Ah CH
AlarmMin       db 0          ; BCD, same format as INT 1Ah CL
FlashAttr      db 0
FlashState     db 0
InHH           db 0
InMM           db 0
DelayOuter     dw 3

ConfirmMsg    db 'Presione una tecla para continuar...', 13, 10, 0
ClockTitle    db 'Modo Reloj  (A: alarma, C: cancelar, M: modo, ESC: salir)', 13, 10, 0
SwTitle       db 'Modo Cronometro (S: iniciar/pausar, R: reset, A: alarma, M: modo, ESC: salir)', 13, 10, 0
AlarmLabel    db 'Alarma: ', 0
NoAlarmMsg    db '--:--', 0
SetAlarmMsg   db 'Configurar alarma. Ingrese hora HH: ', 0
AlarmSetOkMsg db 13, 10, 'Alarma configurada. Presione una tecla...', 13, 10, 0
AlarmMsg      db '*** ALARMA *** Presione C para cancelar', 13, 10, 0
ExitMsg       db 13, 10, 'Programa finalizado.', 0

; --------------------------------------------------------------------
; Hardware RTC alarm interrupt module (modular by design, see rubric
; "Makefiles y modularidad")
; --------------------------------------------------------------------
%include "rtc_alarm.asm"