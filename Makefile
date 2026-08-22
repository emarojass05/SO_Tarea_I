# Makefile - Tarea 1: Reloj/Cronometro con Alarma Booteable
# CE4303 - Principios de Sistemas Operativos

ASM      := nasm
QEMU     := qemu-system-x86_64

BUILD    := build
BOOT_SRC := src/boot/boot.asm
BOOT_BIN := $(BUILD)/boot.bin
IMAGE    := $(BUILD)/disk.img

.PHONY: all run clean

all: $(IMAGE)

$(BUILD):
	mkdir -p $(BUILD)

$(BOOT_BIN): $(BOOT_SRC) | $(BUILD)
	$(ASM) -f bin $(BOOT_SRC) -o $(BOOT_BIN)

$(IMAGE): $(BOOT_BIN)
	dd if=/dev/zero of=$(IMAGE) bs=512 count=2880 status=none
	dd if=$(BOOT_BIN) of=$(IMAGE) conv=notrunc status=none

run: $(IMAGE)
	$(QEMU) -fda $(IMAGE) -display curses

clean:
	rm -rf $(BUILD)