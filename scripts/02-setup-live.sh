#!/usr/bin/env bash
set -euo pipefail

WORKDIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CHROOT_DIR="${WORKDIR}/work/chroot"

echo ">>> [Шаг 2] Настройка Live-окружения и инсталлятора Calamares в chroot..."

# Функция размонтирования при выходе
cleanup() {
    echo "Размонтирование виртуальных ФС..."
    umount -lf "${CHROOT_DIR}/dev/pts" 2>/dev/null || true
    umount -lf "${CHROOT_DIR}/dev" 2>/dev/null || true
    umount -lf "${CHROOT_DIR}/proc" 2>/dev/null || true
    umount -lf "${CHROOT_DIR}/sys" 2>/dev/null || true
}
trap cleanup EXIT

# Монтирование необходимых ФС
mount --bind /dev "${CHROOT_DIR}/dev"
mount --bind /dev/pts "${CHROOT_DIR}/dev/pts"
mount -t proc proc "${CHROOT_DIR}/proc"
mount -t sysfs sysfs "${CHROOT_DIR}/sys"

# Копирование resolv.conf хоста для сетевого доступа внутри chroot
cp /etc/resolv.conf "${CHROOT_DIR}/etc/resolv.conf"

# Копирование скрипта пост-установки
mkdir -p "${CHROOT_DIR}/usr/local/bin"
cp "${WORKDIR}/scripts/post-install.sh" "${CHROOT_DIR}/usr/local/bin/winubuntu-postinstall.sh"
chmod +x "${CHROOT_DIR}/usr/local/bin/winubuntu-postinstall.sh"

# Копирование файлов профиля рабочего стола в /etc/skel
mkdir -p "${CHROOT_DIR}/etc/skel"
cp -r "${WORKDIR}/config/desktop/etc_skel/." "${CHROOT_DIR}/etc/skel/"

# Выполнение настройки внутри chroot
chroot "${CHROOT_DIR}" /bin/bash -s <<'EOF'
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive

echo "Генерация локалей..."
locale-gen
update-locale LANG=ru_RU.UTF-8

echo "Обновление списков пакетов..."
apt-get update

echo "Установка ядра, casper и сетевых утилит..."
apt-get install -y --no-install-recommends \
    linux-generic \
    initramfs-tools \
    casper \
    systemd-sysv \
    udev \
    dbus \
    network-manager \
    network-manager-gnome \
    wireless-tools \
    wpasupplicant \
    iproute2 \
    sudo

echo "Установка графической подсистемы (минимальный X11 + Openbox)..."
apt-get install -y --no-install-recommends \
    xserver-xorg-core \
    xserver-xorg-video-all \
    xserver-xorg-input-all \
    xinit \
    x11-xserver-utils \
    openbox \
    tint2 \
    adwaita-icon-theme \
    fonts-noto-core

echo "Установка установщика Calamares и утилит разметки дисков..."
apt-get install -y --no-install-recommends \
    calamares \
    calamares-settings-ubuntu \
    libqt5svg5 \
    kpmcore \
    parted \
    dosfstools \
    e2fsprogs \
    btrfs-progs \
    efibootmgr \
    grub-pc-bin \
    grub-efi-amd64-bin \
    grub-efi-amd64-signed \
    upower

# Создание Live-пользователя 'live'
if ! id -u live >/dev/null 2>&1; then
    useradd -m -s /bin/bash -G sudo,adm,video,audio,netdev live
    passwd -d live
fi

# Разрешение sudo без пароля для Live-пользователя
echo "live ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/99-live-user
chmod 0440 /etc/sudoers.d/99-live-user

# Настройка автологина в консоль tty1
mkdir -p /etc/systemd/system/getty@tty1.service.d
cat <<'AUTOLOGIN' > /etc/systemd/system/getty@tty1.service.d/autologin.conf
[Service]
ExecStart=
ExecStart=-/sbin/agetty -o '-p -f -- \\u' --noclear --autologin live %I $TERM
AUTOLOGIN

# Настройка автозапуска графики при входе пользователя live
cat <<'PROFILE' >> /home/live/.profile
if [ -z "$DISPLAY" ] && [ "$(tty)" = "/dev/tty1" ]; then
    exec startx
fi
PROFILE
chown live:live /home/live/.profile

# Настройка сессии .xinitrc для пользователя live
cat <<'XINIT' > /home/live/.xinitrc
#!/bin/bash
# Запуск оконного менеджера и окружения инсталлятора
openbox &
nm-applet &
tint2 &

# Установка русского языка клавиатуры (Alt+Shift)
setxkbmap -layout "us,ru" -option "grp:alt_shift_toggle" &

# Запуск инсталлятора
sudo calamares -d
XINIT
chmod +x /home/live/.xinitrc
chown live:live /home/live/.xinitrc

# Очистка кэша пакетов
apt-get clean
rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*
EOF

# Копирование настроек Calamares в chroot
echo "Копирование конфигурации Calamares..."
mkdir -p "${CHROOT_DIR}/etc/calamares/modules"
mkdir -p "${CHROOT_DIR}/etc/calamares/branding/winubuntu"
cp "${WORKDIR}/config/calamares/settings.conf" "${CHROOT_DIR}/etc/calamares/settings.conf"
cp "${WORKDIR}/config/calamares/modules/"*.conf "${CHROOT_DIR}/etc/calamares/modules/"
cp "${WORKDIR}/config/calamares/branding/winubuntu/"* "${CHROOT_DIR}/etc/calamares/branding/winubuntu/"

echo ">>> [Шаг 2] Настройка Live-окружения завершена успешно!"
