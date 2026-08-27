; src/boot/boot.asm
; Stage 1 bootloader (Legacy BIOS / MBR) - Tarea 1 CE4303
; Fits in the mandatory 512-byte boot sector. Welcomes the user, then
; loads the real application (Stage 2, src/app/app.asm) from the
; following disk sectors into memory and jumps to it. The 512-byte
; sector is not big enough to hold Reloj + Cronometro + Alarma, so all
; of that logic lives in Stage 2, which has no size limit.

bits 16
org 0x7C00

APP_LOAD_SEG equ 0x0000
APP_LOAD_OFF equ 0x8000
APP_SECTORS  equ 16      ; sectors to read for Stage 2 (16*512 = 8KB, plenty)

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

    ; Read Stage 2 from disk (starts right after this boot sector)
    ; into ES:BX = 0x0000:0x8000. DL already holds the boot drive,
    ; set by the BIOS before jumping here.
    mov bx, APP_LOAD_OFF
    mov ah, 0x02          ; BIOS: read sectors (INT 13h)
    mov al, APP_SECTORS
    mov ch, 0              ; cylinder 0
    mov cl, 2               ; sector 2 (sector 1 is this boot sector)
    mov dh, 0               ; head 0
    int 0x13
    jc DiskError

    jmp APP_LOAD_SEG:APP_LOAD_OFF

DiskError:
    mov si, ErrorMsg
    call PrintString
.Hang:
    hlt
    jmp .Hang

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

WelcomeMsg db 'Bienvenido - Reloj/Cronometro con Alarma', 13, 10, 'Cargando...', 13, 10, 0
ErrorMsg   db 'Error al leer el disco.', 13, 10, 0

times 510-($-$$) db 0
dw 0xAA55