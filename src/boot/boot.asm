; src/boot/boot.asm
; Stage 1 bootloader (Legacy BIOS / MBR) - Tarea 1 CE4303


bits 16
org 0x7C00

APP_LOAD_SEG equ 0x0000
APP_LOAD_OFF equ 0x8000
APP_SECTORS  equ 16      ; sectors to read for Stage 2 (16*512 = 8KB, plenty)
DISK_RETRIES equ 3       ; read attempts before giving up

Start:
    cli
    xor ax, ax
    mov ds, ax
    mov es, ax
    mov ss, ax
    mov sp, 0x7C00
    sti

    ; The BIOS passes the boot drive in DL when it jumps here. Save it,
    ; since the reset/read calls below overwrite DL/DH themselves and we
    ; need the original drive number on every retry.
    mov [BootDrive], dl

    mov si, WelcomeMsg
    call PrintString

    ; Read Stage 2 from disk (starts right after this boot sector) into
    ; ES:BX = 0x0000:0x8000. On real hardware (unlike QEMU) the first
    ; INT 13h read can fail right after power-on before the controller is
    ; fully ready, so reset the disk system (AH=00h) and retry a few
    ; times before giving up.
    mov cx, DISK_RETRIES
.ReadAttempt:
    push cx

    mov dl, [BootDrive]
    xor ah, ah             ; AH=00h: reset disk system
    int 0x13

    mov bx, APP_LOAD_OFF
    mov dl, [BootDrive]
    mov ah, 0x02            ; AH=02h: read sectors
    mov al, APP_SECTORS
    mov ch, 0               ; cylinder 0
    mov cl, 2               ; sector 2 (sector 1 is this boot sector)
    mov dh, 0               ; head 0
    int 0x13

    pop cx
    jnc LoadOk
    loop .ReadAttempt

    jmp DiskError

LoadOk:
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

BootDrive  db 0
WelcomeMsg db 'Bienvenido - Reloj/Cronometro con Alarma', 13, 10, 'Cargando...', 13, 10, 0
ErrorMsg   db 'Error al leer el disco.', 13, 10, 0

times 510-($-$$) db 0
dw 0xAA55