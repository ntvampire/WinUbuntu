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
mkdir -p "${ISO_DIR}/boot/grub/i386-pc"
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

# 3. Настройка GRUB меню (копирование во все возможные стандартные пути)
echo "Установка конфигурации GRUB..."
cp "${WORKDIR}/config/live/grub.cfg" "${ISO_DIR}/boot/grub/grub.cfg"
cp "${WORKDIR}/config/live/grub.cfg" "${ISO_DIR}/EFI/BOOT/grub.cfg"

# 4. Создание встроенного скрипта GRUB с надежным поиском диска и аварийным меню
echo "Генерация автономного EFI загрузчика GRUB с поиском диска..."
cat <<'EOF' > /tmp/embedded_grub.cfg
# Поиск корневого раздела с ядром /casper/vmlinuz
if [ -z "$root" -o ! -f "($root)/casper/vmlinuz" ]; then
    search --no-floppy --file --set=root /casper/vmlinuz
fi
if [ -z "$root" ]; then
    search --no-floppy --set=root -l WINUBUNTU
fi

set prefix=($root)/boot/grub

# Загрузка основного конфигурационного файла
if [ -f "$prefix/grub.cfg" ]; then
    source "$prefix/grub.cfg"
elif [ -f "($root)/EFI/BOOT/grub.cfg" ]; then
    source "($root)/EFI/BOOT/grub.cfg"
fi

# Резервное встроенное меню на случай проблем с чтением внешнего конфига
set default="0"
set timeout=5

menuentry "Установка WinUbuntu 24.04 LTS" {
    set gfxpayload=keep
    linux /casper/vmlinuz boot=casper iso-scan/filename=${iso_path} quiet splash fsck.mode=skip ---
    initrd /casper/initrd
}

menuentry "Установка WinUbuntu (Безопасный видеорежим)" {
    set gfxpayload=keep
    linux /casper/vmlinuz boot=casper iso-scan/filename=${iso_path} nomodeset quiet splash fsck.mode=skip ---
    initrd /casper/initrd
}
EOF

grub-mkstandalone \
    --format=x86_64-efi \
    --output="${ISO_DIR}/EFI/BOOT/BOOTX64.EFI" \
    --locales="" \
    --fonts="" \
    "boot/grub/grub.cfg=/tmp/embedded_grub.cfg"

# Создание образа FAT для EFI загрузки (ESP раздел efi.img)
echo "Создание FAT раздела EFI (efi.img)..."
EFI_IMG="${ISO_DIR}/boot/grub/efi.img"
rm -f "${EFI_IMG}"
dd if=/dev/zero of="${EFI_IMG}" bs=1M count=8
mkfs.vfat -F 12 "${EFI_IMG}"
mmd -i "${EFI_IMG}" ::/EFI
mmd -i "${EFI_IMG}" ::/EFI/BOOT
mmd -i "${EFI_IMG}" ::/boot
mmd -i "${EFI_IMG}" ::/boot/grub
mcopy -i "${EFI_IMG}" "${ISO_DIR}/EFI/BOOT/BOOTX64.EFI" ::/EFI/BOOT/BOOTX64.EFI
mcopy -i "${EFI_IMG}" "${WORKDIR}/config/live/grub.cfg" ::/EFI/BOOT/grub.cfg
mcopy -i "${EFI_IMG}" "${WORKDIR}/config/live/grub.cfg" ::/boot/grub/grub.cfg

# 5. Создание BIOS загрузчика (для Legacy ПК)
if [ -f /usr/lib/grub/i386-pc/cdboot.img ]; then
    echo "Сборка BIOS El Torito образа..."
    grub-mkimage \
        -O i386-pc \
        -o "${ISO_DIR}/boot/grub/i386-pc/core.img" \
        -p "/boot/grub" \
        biosdisk iso9660 search search_fs_file
    cat /usr/lib/grub/i386-pc/cdboot.img "${ISO_DIR}/boot/grub/i386-pc/core.img" > "${ISO_DIR}/boot/grub/i386-pc/eltorito.img"
fi

# 6. Сборка гибридного ISO с поддержкой UEFI, BIOS и Ventoy через xorriso
echo "Генерация гибридного ISO-образа через xorriso..."
XORRISO_ARGS=(
    -as mkisofs
    -iso-level 3
    -full-iso9660-filenames
    -volid "WINUBUNTU"
)

if [ -f "${ISO_DIR}/boot/grub/i386-pc/eltorito.img" ]; then
    XORRISO_ARGS+=(
        -eltorito-boot boot/grub/i386-pc/eltorito.img
        -no-emul-boot
        -boot-load-size 4
        -boot-info-table
        --grub2-boot-info
        -eltorito-alt-boot
    )
fi

XORRISO_ARGS+=(
    -e boot/grub/efi.img
    -no-emul-boot
    -isohybrid-gpt-basdat
    -output "${OUTPUT_DIR}/${ISO_NAME}"
    "${ISO_DIR}"
)

xorriso "${XORRISO_ARGS[@]}"

# 7. Создание контрольной суммы SHA256
echo "Генерация контрольной суммы SHA256..."
cd "${OUTPUT_DIR}"
sha256sum "${ISO_NAME}" > "${ISO_NAME}.sha256"

echo "=========================================================="
echo " ISO успешно собран: ${OUTPUT_DIR}/${ISO_NAME}"
echo " Размер: $(du -h "${OUTPUT_DIR}/${ISO_NAME}" | cut -f1)"
echo " SHA256: $(cat "${OUTPUT_DIR}/${ISO_NAME}.sha256")"
echo "=========================================================="
