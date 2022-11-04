
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

ifeq ($(OSARCH), amd64)
QEMUHWACCELERATION = -machine q35 -enable-kvm
QEMUMEMORY = -m 4G
else ifeq ($(OSARCH), i686)
QEMUHWACCELERATION = -machine q35 -enable-kvm
QEMUMEMORY = -m 4G
else ifeq ($(OSARCH), aarch64)
QEMUHWACCELERATION =
QEMUMEMORY = -m 1G
endif

ifeq ($(OSARCH), amd64)
QEMUFLAGS += -device bochs-display -M q35 \
			 -usb \
			 -usbdevice mouse \
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
			 -audiodev pa,id=pa1,server=/run/user/1000/pulse/native \
			 -machine pcspk-audiodev=pa1 \
			 -device AC97,audiodev=pa1
else ifeq ($(OSARCH), i686)
QEMUFLAGS += -M q35 \
			 -usb \
			 -usbdevice mouse \
			 -net user \
			 -netdev user,id=usernet0 \
			 -device e1000,netdev=usernet0,mac=00:69:96:00:42:00 \
			 -object filter-dump,id=usernet0,netdev=usernet0,file=network.log,maxlen=1024 \
			 -serial file:serial.log \
			 -hda $(OSNAME).iso \
			 -audiodev pa,id=pa1,server=/run/user/1000/pulse/native \
			 -machine pcspk-audiodev=pa1 \
			 -device AC97,audiodev=pa1
else ifeq ($(OSARCH), aarch64)
QEMUFLAGS += -M raspi3b \
			 -cpu cortex-a57 \
			 -serial file:serial.log \
			 -kernel $(OSNAME).img
endif

doxygen:
	mkdir -p doxygen-doc
	doxygen Doxyfile
	doxygen Kernel/Doxyfile
	doxygen Lynx/Doxyfile
	doxygen Userspace/Doxyfile
	doxygen Drivers/Doxyfile

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
	make --quiet -C Drivers prepare

build: build_lynx build_kernel build_userspace build_drivers build_image

rebuild: clean build

# Quickly build the operating system (it won't create the ISO file and doxygen documentation)
build_lynx:
ifeq ($(BOOTLOADER), lynx)
	make --quiet -C Lynx build
endif

build_kernel:
	make -j$(shell nproc) --quiet -C Kernel build

build_userspace:
	make --quiet -C Userspace build
	cp -r Userspace/out/* initrd/

build_drivers:
	make --quiet -C Drivers build
	cp Drivers/out/* initrd/system/drivers/

build_image:
	mkdir -p iso_tmp_data
	tar cf initrd.tar.gz -C initrd/ ./ --format=ustar
	cp Kernel/kernel.fsys initrd.tar.gz \
		iso_tmp_data/
ifeq ($(BOOTLOADER), lynx)
	cp tools/lynx.cfg Lynx/loader.bin Lynx/efi-loader.bin iso_tmp_data/
	xorriso -as mkisofs -b loader.bin \
		-no-emul-boot -boot-load-size 4 -boot-info-table \
		--efi-boot efi-loader.bin -V FENNIX \
		-efi-boot-part --efi-boot-image --protective-msdos-label \
		iso_tmp_data -o $(OSNAME).iso
endif
ifeq ($(BOOTLOADER), other)
ifeq ($(OSARCH), amd64)
	cp tools/limine.cfg $(LIMINE_FOLDER)/limine.sys $(LIMINE_FOLDER)/limine-cd.bin $(LIMINE_FOLDER)/limine-cd-efi.bin iso_tmp_data/
	xorriso -as mkisofs -b limine-cd.bin \
		-no-emul-boot -boot-load-size 4 -boot-info-table \
		--efi-boot limine-cd-efi.bin -V FENNIX \
		-efi-boot-part --efi-boot-image --protective-msdos-label \
		iso_tmp_data -o $(OSNAME).iso
endif
ifeq ($(OSARCH), i686)
# TODO: Add custom language support for GRUB or detect the system language using "echo $LANG | cut -d . -f 1" and set "lang" variable inside grub.cfg
	mkdir -p iso_tmp_data/boot
	mkdir -p iso_tmp_data/boot/grub
	cp tools/grub.cfg iso_tmp_data/boot/grub/
	grub-mkrescue -o $(OSNAME).iso iso_tmp_data
endif
ifeq ($(OSARCH), aarch64)
	$(COMPILER_PATH)/$(COMPILER_ARCH)objcopy Kernel/kernel.fsys -O binary $(OSNAME).img
endif
endif

ifeq ($(OSARCH), amd64)
QEMU_UEFI_BIOS = -bios /usr/share/qemu/OVMF.fd
endif
# ifeq ($(OSARCH), aarch64)
# QEMU_UEFI_BIOS = -bios -bios /usr/share/AAVMF/AAVMF_CODE.fd
# endif

vscode_debug: build_kernel build_userspace build_drivers build_image
	rm -f serial.log network.log
	$(QEMU) -S -gdb tcp::1234 -d int -no-reboot -no-shutdown $(QEMU_UEFI_BIOS) -m 4G $(QEMUFLAGS) -smp $(shell echo $(shell nproc)/4 | bc)

qemu: qemu_vdisk
	rm -f serial.log network.log
	$(QEMU) $(QEMU_UEFI_BIOS) -cpu host $(QEMUFLAGS) $(QEMUHWACCELERATION) $(QEMUMEMORY) -smp $(shell nproc)

qemubios: qemu_vdisk
	rm -f serial.log network.log
	$(QEMU) -cpu host $(QEMUFLAGS) $(QEMUHWACCELERATION) $(QEMUMEMORY) -smp $(shell nproc)

run: build qemu

clean:
	rm -rf doxygen-doc iso_tmp_data
	rm -f initrd/system/drivers/*.fex initrd.tar.gz $(OSNAME).iso $(OSNAME).img
	make -C Kernel clean
	make -C Lynx clean
	make -C Userspace clean
	make -C Drivers clean
