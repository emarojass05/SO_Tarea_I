; src/app/alarm.asm
; --------------------------------------------------------------------
; Alarm UI: setting the HH:MM (SetAlarmPrompt) and the ringing screen
; (AlarmRing). The actual HH:MM match is detected by the RTC chip's own
; hardware interrupt (see rtc_alarm.asm), not polled here.
; --------------------------------------------------------------------

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

; Prints "Alarma: HH:MM" or "Alarma: --:--" plus CRLF, used by ShowTitle.
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

AlarmSet       db 0          ; 0 = no alarm configured, 1 = configured
AlarmTriggered db 0          ; 0 = not ringing, 1 = ringing
AlarmHour      db 0          ; BCD, same format as INT 1Ah CH
AlarmMin       db 0          ; BCD, same format as INT 1Ah CL
FlashAttr      db 0
FlashState     db 0
InHH           db 0
InMM           db 0

AlarmLabel    db 'Alarma: ', 0
NoAlarmMsg    db '--:--', 0
SetAlarmMsg   db 'Configurar alarma. Ingrese hora HH: ', 0
AlarmBadMsg   db 'Hora invalida (HH 00-23, MM 00-59). Intente de nuevo.', 13, 10, 0
AlarmSetOkMsg db 13, 10, 'Alarma configurada. Presione una tecla...', 13, 10, 0
AlarmMsg      db '*** ALARMA *** Presione C para cancelar', 13, 10, 0
