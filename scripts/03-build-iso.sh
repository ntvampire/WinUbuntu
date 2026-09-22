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

# Копирование всех x86_64-efi модулей GRUB на ISO образ (за исключением shim_lock)
if [ -d /usr/lib/grub/x86_64-efi ]; then
    echo "Копирование модулей GRUB x86_64-efi на ISO..."
    cp -r /usr/lib/grub/x86_64-efi/*.mod "${ISO_DIR}/boot/grub/x86_64-efi/" || true
    cp -r /usr/lib/grub/x86_64-efi/*.lst "${ISO_DIR}/boot/grub/x86_64-efi/" || true
    # КРИТИЧЕСКИ ВАЖНО: Удаляем shim_lock.mod с диска, чтобы GRUB не блокировал загрузку ядра без shim
    rm -f "${ISO_DIR}/boot/grub/x86_64-efi/shim_lock.mod"
fi

# Копирование шрифта unicode.pf2
for font_path in /usr/share/grub/unicode.pf2 /boot/grub/unicode.pf2 "${CHROOT_DIR}/usr/share/grub/unicode.pf2"; do
    if [ -f "$font_path" ]; then
        cp "$font_path" "${ISO_DIR}/boot/grub/font.pf2" || true
        break
    fi
done

# 4. Настройка официального подписанного Canonical GRUB (для совместимости с Shim и Secure Boot)
GRUB_SIGNED_SRC=""
for g in /usr/lib/grub/x86_64-efi-signed/grubx64.efi.signed "${CHROOT_DIR}/usr/lib/grub/x86_64-efi-signed/grubx64.efi.signed"; do
    if [ -f "$g" ]; then
        GRUB_SIGNED_SRC="$g"
        break
    fi
done

if [ -n "$GRUB_SIGNED_SRC" ]; then
    echo "Использование официального подписанного Canonical GRUB: $GRUB_SIGNED_SRC"
    cp "$GRUB_SIGNED_SRC" "${ISO_DIR}/EFI/BOOT/grubx64.efi"
else
    echo "Подписанный GRUB не найден, сборка автономного grubx64.efi..."
    cat <<'EOF' > /tmp/embedded_grub.cfg
insmod linux
insmod normal
insmod configfile
search --no-floppy --file --set=root /casper/vmlinuz
set prefix=($root)/boot/grub
if [ -f "$prefix/grub.cfg" ]; then
    source "$prefix/grub.cfg"
elif [ -f "($root)/EFI/BOOT/grub.cfg" ]; then
    source "($root)/EFI/BOOT/grub.cfg"
fi
EOF

    TMP_GRUB_MODS="/tmp/grub-x86_64-efi"
    rm -rf "${TMP_GRUB_MODS}"
    mkdir -p "${TMP_GRUB_MODS}"
    if [ -d /usr/lib/grub/x86_64-efi ]; then
        cp -r /usr/lib/grub/x86_64-efi/* "${TMP_GRUB_MODS}/"
        rm -f "${TMP_GRUB_MODS}/shim_lock.mod"
    fi

    grub-mkstandalone \
        -d "${TMP_GRUB_MODS}" \
        --format=x86_64-efi \
        --output="${ISO_DIR}/EFI/BOOT/grubx64.efi" \
        --locales="" \
        --fonts="" \
        "boot/grub/grub.cfg=/tmp/embedded_grub.cfg"
fi

# 5. Настройка официального подписанного Shim (BOOTX64.EFI)
SHIM_SRC=""
for s in /usr/lib/shim/shimx64.efi.signed.latest /usr/lib/shim/shimx64.efi.signed "${CHROOT_DIR}/usr/lib/shim/shimx64.efi.signed.latest" "${CHROOT_DIR}/usr/lib/shim/shimx64.efi.signed"; do
    if [ -f "$s" ]; then
        SHIM_SRC="$s"
        break
    fi
done

if [ -n "$SHIM_SRC" ]; then
    echo "Использование официального Microsoft-signed Shim: $SHIM_SRC"
    cp "$SHIM_SRC" "${ISO_DIR}/EFI/BOOT/BOOTX64.EFI"
else
    echo "Shim не найден, дублирование grubx64.efi в BOOTX64.EFI"
    cp "${ISO_DIR}/EFI/BOOT/grubx64.efi" "${ISO_DIR}/EFI/BOOT/BOOTX64.EFI"
fi

# Копирование mmx64.efi (MokManager), если есть
for mm in /usr/lib/shim/mmx64.efi "${CHROOT_DIR}/usr/lib/shim/mmx64.efi"; do
    if [ -f "$mm" ]; then
        cp "$mm" "${ISO_DIR}/EFI/BOOT/mmx64.efi"
        break
    fi
done

# 6. Создание образа FAT для EFI загрузки (ESP раздел efi.img)
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
mcopy -i "${EFI_IMG}" "${ISO_DIR}/EFI/BOOT/grubx64.efi" ::/EFI/BOOT/grubx64.efi
if [ -f "${ISO_DIR}/EFI/BOOT/mmx64.efi" ]; then
    mcopy -i "${EFI_IMG}" "${ISO_DIR}/EFI/BOOT/mmx64.efi" ::/EFI/BOOT/mmx64.efi
fi
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
