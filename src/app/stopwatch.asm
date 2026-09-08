; src/app/stopwatch.asm
; --------------------------------------------------------------------
; Modo Cronometro: independent elapsed-time counter, started/paused
; with S and reset with R (see app.asm's KeyCheck). Tracks ticks using
; the full 32-bit BIOS tick count (INT 1Ah/AH=00h) so elapsed time
; doesn't silently wrap/corrupt after ~1 hour (65536 ticks) the way a
; 16-bit counter would.
; --------------------------------------------------------------------

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

; Returns total elapsed stopwatch ticks in DX:AX (32-bit; running or paused).
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

SwRunning      db 0          ; 0 = paused, 1 = running
SwBaseLo       dw 0          ; tick count (low word) when Stopwatch was last (re)started
SwBaseHi       dw 0          ; tick count (high word), see SwBaseLo
SwElapsedLo    dw 0          ; accumulated elapsed ticks while paused (low word)
SwElapsedHi    dw 0          ; accumulated elapsed ticks while paused (high word)
TmpTicksHi     dw 0          ; scratch used by TicksToSeconds
