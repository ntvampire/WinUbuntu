#!/usr/bin/env bash
set -euo pipefail

WORKDIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CHROOT_DIR="${WORKDIR}/work/chroot"
ISO_DIR="${WORKDIR}/work/iso"
OUTPUT_DIR="${WORKDIR}/output"
BUILD_DATE=$(date +'%Y%m%d')
ISO_NAME="winubuntu-24.04-minimal-${BUILD_DATE}-amd64.iso"

echo ">>> [Шаг 3] Подготовка структуры и сборка ISO-образа..."

mkdir -p "${ISO_DIR}/casper"
mkdir -p "${ISO_DIR}/boot/grub/x86_64-efi"
mkdir -p "${ISO_DIR}/EFI/BOOT"
mkdir -p "${OUTPUT_DIR}"

# 1. Извлечение vmlinuz и initrd из chroot
echo "Копирование ядра и initrd в casper/..."
VMLINUZ=$(ls -1 "${CHROOT_DIR}/boot"/vmlinuz-* | sort -V | tail -n 1)
INITRD=$(ls -1 "${CHROOT_DIR}/boot"/initrd.img-* | sort -V | tail -n 1)

cp "${VMLINUZ}" "${ISO_DIR}/casper/vmlinuz"
cp "${INITRD}" "${ISO_DIR}/casper/initrd"

# 2. Создание сжатого squashfs образа
echo "Сжатие корневой файловой системы в filesystem.squashfs (XZ компрессия)..."
rm -f "${ISO_DIR}/casper/filesystem.squashfs"
mksquashfs "${CHROOT_DIR}" "${ISO_DIR}/casper/filesystem.squashfs" \
    -comp xz \
    -b 1048576 \
    -noappend \
    -wildcards \
    -e "boot/vmlinuz*" \
    -e "boot/initrd.img*"

# Запись размера файловой системы для инсталлятора
du -sx --block-size=1 "${CHROOT_DIR}" | cut -f1 > "${ISO_DIR}/casper/filesystem.size"

# 3. Настройка GRUB меню
echo "Установка конфигурации GRUB..."
cp "${WORKDIR}/config/live/grub.cfg" "${ISO_DIR}/boot/grub/grub.cfg"

# 4. Создание EFI загрузчика (BOOTX64.EFI)
echo "Генерация автономного EFI загрузчика GRUB..."
cat <<'EOF' > /tmp/embedded_grub.cfg
set root=(memdisk)
set prefix=($root)/boot/grub
EOF

grub-mkstandalone \
    --format=x86_64-efi \
    --output="${ISO_DIR}/EFI/BOOT/BOOTX64.EFI" \
    --locales="" \
    --fonts="" \
    "boot/grub/grub.cfg=/tmp/embedded_grub.cfg"

# Создание образа FAT для EFI загрузки в xorriso
echo "Создание FAT раздела EFI (efi.img)..."
EFI_IMG="${ISO_DIR}/boot/grub/efi.img"
rm -f "${EFI_IMG}"
dd if=/dev/zero of="${EFI_IMG}" bs=1M count=8
mkfs.vfat -F 12 "${EFI_IMG}"
mmd -i "${EFI_IMG}" ::/EFI
mmd -i "${EFI_IMG}" ::/EFI/BOOT
mcopy -i "${EFI_IMG}" "${ISO_DIR}/EFI/BOOT/BOOTX64.EFI" ::/EFI/BOOT/BOOTX64.EFI

# 5. Сборка гибридного ISO с поддержкой UEFI, BIOS и Ventoy через xorriso
echo "Генерация гибридного ISO-образа через xorriso..."
xorriso -as mkisofs \
    -iso-level 3 \
    -full-iso9660-filenames \
    -volid "WINUBUNTU" \
    -eltorito-boot boot/grub/efi.img \
    -no-emul-boot \
    -isohybrid-gpt-basdat \
    -output "${OUTPUT_DIR}/${ISO_NAME}" \
    "${ISO_DIR}"

# 6. Создание контрольной суммы SHA256
echo "Генерация контрольной суммы SHA256..."
cd "${OUTPUT_DIR}"
sha256sum "${ISO_NAME}" > "${ISO_NAME}.sha256"

echo "=========================================================="
echo " ISO успешно собран: ${OUTPUT_DIR}/${ISO_NAME}"
echo " Размер: $(du -h "${OUTPUT_DIR}/${ISO_NAME}" | cut -f1)"
echo " SHA256: $(cat "${OUTPUT_DIR}/${ISO_NAME}.sha256")"
echo "=========================================================="
