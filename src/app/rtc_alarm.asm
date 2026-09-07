; src/app/rtc_alarm.asm
; --------------------------------------------------------------------
; Hardware RTC alarm interrupt (CE4303 - Tarea 1)
;
; The MC146818-compatible RTC chip present on every PC-compatible
; chipset can raise IRQ8 by itself when the wall-clock time matches a
; set of "alarm" registers programmed into its own CMOS RAM. This
; module owns that interrupt directly (IVT vector 0x70, since the
; BIOS/PIC map IRQ8 to INT 70h) instead of polling INT 1Ah from the
; main loop, satisfying the "manejo del tiempo real provisto por el
; hardware" requirement via a real, hardware-triggered interrupt.
;
; Assumes DS = ES = SS = 0 for the whole program's lifetime (true here,
; since boot.asm sets them and app.asm never changes them), so the IVT
; can be read/written through plain [offset] addressing.
;
; Public routines:
;   InstallRtcVector          - saves the current INT 70h vector and
;                                installs RtcAlarmISR in its place.
;                                Call once, at program start.
;   RestoreRtcVector          - puts the original INT 70h vector back.
;                                Call once, before halting.
;   EnableRtcAlarmInterrupt   - programs the RTC's alarm registers from
;                                [AlarmHour]/[AlarmMin] (BCD, same
;                                encoding INT 1Ah returns) and turns on
;                                the chip's Alarm Interrupt Enable bit.
;                                Call whenever the user (re)configures
;                                the alarm.
;   DisableRtcAlarmInterrupt  - turns the chip's alarm interrupt back
;                                off. Call when the alarm is cancelled.
;
; External dependency: byte [AlarmTriggered], byte [AlarmHour],
; byte [AlarmMin] - defined in app.asm's State section.
; --------------------------------------------------------------------

; CMOS/RTC ports and register indices
CMOS_INDEX      equ 0x70
CMOS_DATA       equ 0x71
RTC_REG_SEC_AL  equ 0x01     ; seconds alarm
RTC_REG_MIN_AL  equ 0x03     ; minutes alarm
RTC_REG_HOUR_AL equ 0x05     ; hours alarm
RTC_REG_B       equ 0x0B     ; status register B (AIE lives here)
RTC_REG_C       equ 0x0C     ; status register C (ack/identify IRQ)
RTC_AIE_BIT     equ 0x20     ; Alarm Interrupt Enable / Alarm Flag bit
RTC_DONT_CARE   equ 0xC0     ; bits 6-7 set = "don't care" this field

; IVT vector for IRQ8 (slave PIC line 0) = INT 0x70 -> offset 0x70*4
RTC_VEC_OFFSET  equ 0x1C0

InstallRtcVector:
    push ax
    cli
    mov ax, [RTC_VEC_OFFSET]
    mov [OldRtcOff], ax
    mov ax, [RTC_VEC_OFFSET + 2]
    mov [OldRtcSeg], ax
    mov word [RTC_VEC_OFFSET], RtcAlarmISR
    mov word [RTC_VEC_OFFSET + 2], 0   ; CS is 0 in this flat real-mode setup
    sti
    pop ax
    ret

RestoreRtcVector:
    push ax
    cli
    mov ax, [OldRtcOff]
    mov [RTC_VEC_OFFSET], ax
    mov ax, [OldRtcSeg]
    mov [RTC_VEC_OFFSET + 2], ax
    sti
    pop ax
    ret

; Programs the alarm registers with [AlarmHour]:[AlarmMin] (seconds are
; "don't care" so the alarm fires the instant HH:MM matches) and turns
; on AIE, then unmasks IRQ8 (and its IRQ2 cascade on the master PIC).
EnableRtcAlarmInterrupt:
    pusha
    cli

    mov al, RTC_REG_SEC_AL
    out CMOS_INDEX, al
    jmp $+2
    mov al, RTC_DONT_CARE
    out CMOS_DATA, al
    jmp $+2

    mov al, RTC_REG_MIN_AL
    out CMOS_INDEX, al
    jmp $+2
    mov al, [AlarmMin]
    out CMOS_DATA, al
    jmp $+2

    mov al, RTC_REG_HOUR_AL
    out CMOS_INDEX, al
    jmp $+2
    mov al, [AlarmHour]
    out CMOS_DATA, al
    jmp $+2

    ; Set AIE (bit 5) in Register B without disturbing the other bits
    mov al, RTC_REG_B
    out CMOS_INDEX, al
    jmp $+2
    in al, CMOS_DATA
    or al, RTC_AIE_BIT
    mov bl, al
    mov al, RTC_REG_B
    out CMOS_INDEX, al
    jmp $+2
    mov al, bl
    out CMOS_DATA, al

    ; Unmask IRQ8 on the slave PIC and the IRQ2 cascade line on the master
    in al, 0xA1
    and al, 0xFE
    out 0xA1, al
    in al, 0x21
    and al, 0xFB
    out 0x21, al

    sti
    popa
    ret

; Clears AIE in Register B so the RTC stops raising the alarm interrupt.
DisableRtcAlarmInterrupt:
    pusha
    cli
    mov al, RTC_REG_B
    out CMOS_INDEX, al
    jmp $+2
    in al, CMOS_DATA
    and al, ~RTC_AIE_BIT & 0xFF
    mov bl, al
    mov al, RTC_REG_B
    out CMOS_INDEX, al
    jmp $+2
    mov al, bl
    out CMOS_DATA, al
    sti
    popa
    ret

; IRQ8 handler. Reading Register C both tells us why the RTC interrupted
; and re-arms the chip for the next interrupt (mandatory on every IRQ8,
; even when it turns out not to be our alarm).
RtcAlarmISR:
    push ax
    mov al, RTC_REG_C
    out CMOS_INDEX, al
    jmp $+2
    in al, CMOS_DATA
    test al, RTC_AIE_BIT      ; AF (Alarm Flag) bit in Register C
    jz .Eoi
    mov byte [AlarmTriggered], 1
.Eoi:
    mov al, 0x20
    out 0xA0, al              ; EOI to the slave PIC (IRQ8 lives there)
    out 0x20, al              ; EOI to the master PIC (cascade line)
    pop ax
    iret

OldRtcOff dw 0
OldRtcSeg dw 0
