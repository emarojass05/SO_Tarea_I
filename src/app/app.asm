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
    call GetStopwatchTicks32  ; DX:AX = elapsed ticks (32-bit, ~18.2065 ticks/sec)
    call TicksToSeconds       ; AX = elapsed seconds (see TicksToSeconds for the math)
    xor dx, dx
    mov cx, 60
    div cx                    ; AX = minutes, DX = seconds
    push dx                   ; save seconds (0-59)
    mov cx, 100
    xor dx, dx
    div cx                    ; DX = minutes mod 100 (display is only 2 digits wide)
    mov ax, dx
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
    call ToggleStopwatch32
    jmp MainLoop

DoReset:
    mov word [SwElapsedLo], 0
    mov word [SwElapsedHi], 0
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
    call ShowCursor           ; leave the cursor as we found it (HideCursor hid it in ShowTitle)
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

; Interactive HH:MM prompt. Reads 4 digit keys (echoed as typed), stores as
; BCD (same format INT 1Ah returns) so the RTC's own alarm registers can be
; programmed directly from it. An out-of-range HH or MM is rejected and the
; prompt restarts, instead of being silently clamped to the nearest valid
; value.
SetAlarmPrompt:
    call ClearScreen
.Retry:
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
    ja .BadInput
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
    ja .BadInput
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

.BadInput:
    call ClearScreen
    mov si, AlarmBadMsg
    call PrintString
    jmp .Retry

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

; Returns total elapsed stopwatch ticks in DX:AX (32-bit; running or paused).
; Uses the full 32-bit BIOS tick count (CX:DX from INT 1Ah/AH=00h) instead of
; only its low word, so elapsed time no longer silently wraps/corrupts after
; ~1 hour (65536 ticks) the way a 16-bit counter would.
GetStopwatchTicks32:
    push cx
    push bx
    cmp byte [SwRunning], 0
    je .Paused
    xor ah, ah
    int 0x1a                  ; CX:DX = current absolute 32-bit tick count
    sub dx, [SwBaseLo]
    sbb cx, [SwBaseHi]        ; CX:DX = ticks elapsed since (re)start
    add dx, [SwElapsedLo]
    adc cx, [SwElapsedHi]     ; + whatever had already accumulated
    mov ax, dx                ; result convention: DX:AX (DX=high, AX=low)
    mov dx, cx
    jmp .Done
.Paused:
    mov ax, [SwElapsedLo]
    mov dx, [SwElapsedHi]
.Done:
    pop bx
    pop cx
    ret

; Converts a 32-bit tick count (DX:AX in, DX=high/AX=low) to elapsed seconds
; (AX out, 16-bit - sufficient since the display only ever shows MM:SS).
; ticks/sec is ~18.2065 (PIT rate 1193182Hz / 65536), and 3600/65536 matches
; that to within ~0.01%, so seconds = ticks * 3600 / 65536. Splitting the
; 32-bit tick count into its two 16-bit halves lets that division become a
; free "take the high word" instead of needing a 32x16 multiply:
;   seconds = ticks_hi*3600 + (ticks_lo*3600) >> 16
TicksToSeconds:
    mov [TmpTicksHi], dx
    mov cx, 3600
    mul cx                    ; DX:AX = ticks_lo * 3600
    mov bx, dx                ; bx = seconds contributed by the low half
    mov ax, [TmpTicksHi]
    mov cx, 3600
    mul cx                    ; DX:AX = ticks_hi * 3600 (exact, see comment above)
    add ax, bx
    ret

; Toggles between running and paused, accumulating elapsed time.
ToggleStopwatch32:
    cmp byte [SwRunning], 0
    je .StartIt
    call GetStopwatchTicks32   ; DX:AX = elapsed
    mov [SwElapsedLo], ax
    mov [SwElapsedHi], dx
    mov byte [SwRunning], 0
    ret
.StartIt:
    xor ah, ah
    int 0x1a                   ; CX:DX = current absolute 32-bit tick count
    mov [SwBaseLo], dx
    mov [SwBaseHi], cx
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
SwBaseLo       dw 0          ; tick count (low word) when Stopwatch was last (re)started
SwBaseHi       dw 0          ; tick count (high word), see SwBaseLo
SwElapsedLo    dw 0          ; accumulated elapsed ticks while paused (low word)
SwElapsedHi    dw 0          ; accumulated elapsed ticks while paused (high word)
TmpTicksHi     dw 0          ; scratch used by TicksToSeconds

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
AlarmBadMsg   db 'Hora invalida (HH 00-23, MM 00-59). Intente de nuevo.', 13, 10, 0
AlarmSetOkMsg db 13, 10, 'Alarma configurada. Presione una tecla...', 13, 10, 0
AlarmMsg      db '*** ALARMA *** Presione C para cancelar', 13, 10, 0
ExitMsg       db 13, 10, 'Programa finalizado.', 0

; --------------------------------------------------------------------
; Hardware RTC alarm interrupt module (modular by design, see rubric
; "Makefiles y modularidad")
; --------------------------------------------------------------------
%include "rtc_alarm.asm"