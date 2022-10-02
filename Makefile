
include Makefile.conf

.PHONY: default tools clean

# First rule
default:
	$(error Please specify a target)

# Available display devices
# None:       -vga none
# Standard:   -device VGA
# Bochs:      -device bochs-display
# VirtIO VGA: -device virtio-vga
# VirtIO GPU: -device virtio-gpu-pci
# QXL VGA:    -device qxl-vga
# QXL:        -device qxl
# Cirrus VGA: -device cirrus-vga
# ATI VGA:    -device ati-vga
# RAMFB:      -device ramfb

# For tap0
# -netdev tap,id=usernet0,ifname=tap0,script=no,downscript=no
QEMU = ./$(QEMU_PATH)$(QEMU_ARCH)
QEMUFLAGS := -display gtk
QEMUHWACCELERATION = -machine q35 -enable-kvm
QEMUMEMORY = -m 4G

ifeq ($(OSARCH), amd64)
QEMUFLAGS += -device bochs-display -M q35 \
			 -usb \
			 -usbdevice mouse \
			 -smp $(shell nproc) \
			 -net user \
			 -netdev user,id=usernet0 \
			 -device e1000,netdev=usernet0,mac=00:69:96:00:42:00 \
			 -object filter-dump,id=usernet0,netdev=usernet0,file=network.log,maxlen=1024 \
			 -serial file:serial.log \
			 -device ahci,id=ahci \
			 -drive id=bootdsk,file=$(OSNAME).iso,format=raw,if=none \
			 -device ide-hd,drive=bootdsk,bus=ahci.0 \
			 -drive id=disk,file=qemu-disk.img,format=raw,if=none \
			 -device ide-hd,drive=disk,bus=ahci.1 \
			 -audiodev pa,id=audio0 \
			 -machine pcspk-audiodev=audio0 \
			 -device AC97,audiodev=audio0
else ifeq ($(OSARCH), i686)
QEMUFLAGS += -M q35 \
			 -usb \
			 -usbdevice mouse \
			 -smp $(shell nproc) \
			 -net user \
			 -netdev user,id=usernet0 \
			 -device e1000,netdev=usernet0,mac=00:69:96:00:42:00 \
			 -object filter-dump,id=usernet0,netdev=usernet0,file=network.log,maxlen=1024 \
			 -serial file:serial.log \
			 -hda $(OSNAME).iso \
			 -audiodev pa,id=audio0 \
			 -machine pcspk-audiodev=audio0 \
			 -device AC97,audiodev=audio0
else ifeq ($(OSARCH), aarch64)
QEMUFLAGS += -M virt \
			 -cpu cortex-a57 \
			 -smp $(shell nproc) \
			 -serial file:serial.log \
			 -hda $(OSNAME).iso
endif

doxygen:
	mkdir -p doxygen-doc
	doxygen Doxyfile
	doxygen Kernel/Doxyfile
	doxygen Lynx/Doxyfile
	doxygen Userspace/Doxyfile

qemu_vdisk:
ifneq (,$(wildcard ./qemu-disk.img))
	$(info qemu-disk.img Already exists)
else
	dd if=/dev/zero of=qemu-disk.img bs=1024K count=4000
endif

# Install necessary packages, build cross-compiler etc...
tools:
	make --quiet -C tools all
	make --quiet -C Kernel prepare
	make --quiet -C Lynx prepare
	make --quiet -C Userspace prepare

build: build_lynx build_kernel build_userspace build_image

rebuild: clean build

# Quickly build the operating system (it won't create the ISO file and doxygen documentation)
build_lynx:
ifeq ($(BOOTLOADER), lynx)
	make --quiet -C boot build
endif

build_kernel:
	make -j$(shell nproc) --quiet -C Kernel build

build_userspace:
	make --quiet -C Userspace build

build_image:
	mkdir -p iso_tmp_data
	tar cf initrd.tar.gz -C initrd/ ./ --format=ustar
	cp Kernel/kernel.fsys initrd.tar.gz \
		iso_tmp_data/
ifeq ($(BOOTLOADER), lynx)
	cp tools/lynx.cfg boot/BIOS/loader.bin boot/UEFI/efi-loader.bin iso_tmp_data/
	xorriso -as mkisofs -b loader.bin \
		-no-emul-boot -boot-load-size 4 -boot-info-table \
		--efi-boot efi-loader.bin \
		-efi-boot-part --efi-boot-image --protective-msdos-label \
		iso_tmp_data -o $(OSNAME).iso
endif
ifeq ($(BOOTLOADER), other)
ifeq ($(OSARCH), amd64)
	cp tools/limine.cfg $(LIMINE_FOLDER)/limine.sys $(LIMINE_FOLDER)/limine-cd.bin $(LIMINE_FOLDER)/limine-cd-efi.bin iso_tmp_data/
	xorriso -as mkisofs -b limine-cd.bin \
		-no-emul-boot -boot-load-size 4 -boot-info-table \
		--efi-boot limine-cd-efi.bin \
		-efi-boot-part --efi-boot-image --protective-msdos-label \
		iso_tmp_data -o $(OSNAME).iso
endif
ifeq ($(OSARCH), i686)
	mkdir -p iso_tmp_data/boot
	mkdir -p iso_tmp_data/boot/grub
	cp tools/grub.cfg iso_tmp_data/boot/grub/
	grub-mkrescue -o $(OSNAME).iso iso_tmp_data
endif
endif

QEMU_UEFI_BIOS :=
ifeq ($(OSARCH), amd64)
QEMU_UEFI_BIOS += -bios /usr/share/qemu/OVMF.fd
endif

vscode_debug: build_kernel build_userspace build_image
	rm -f serial.log network.log
	$(QEMU) -S -gdb tcp::1234 -d int -no-shutdown $(QEMU_UEFI_BIOS) -m 4G $(QEMUFLAGS)

qemu: qemu_vdisk
	rm -f serial.log network.log
	$(QEMU) $(QEMU_UEFI_BIOS) -cpu host $(QEMUFLAGS) $(QEMUHWACCELERATION) $(QEMUMEMORY)

qemubios: qemu_vdisk
	rm -f serial.log network.log
	$(QEMU) -cpu host $(QEMUFLAGS) $(QEMUHWACCELERATION) $(QEMUMEMORY)

run: build qemu

clean:
	rm -rf doxygen-doc iso_tmp_data initrd.tar.gz $(OSNAME).iso
	make --quiet -C Kernel clean
	make --quiet -C Lynx clean
	make --quiet -C Userspace clean
