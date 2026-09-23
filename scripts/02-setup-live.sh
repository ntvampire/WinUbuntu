#!/usr/bin/env bash
set -euo pipefail

WORKDIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CHROOT_DIR="${WORKDIR}/work/chroot"

echo ">>> [Шаг 2] Настройка окружения инсталлятора в chroot..."

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
chmod +x "${CHROOT_DIR}/etc/skel/Desktop/"*.desktop 2>/dev/null || true

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

echo "Установка графической среды (XFCE, Openbox, LightDM) и Calamares..."
apt-get install -y --no-install-recommends \
    xserver-xorg-core \
    xserver-xorg-video-all \
    xserver-xorg-input-all \
    x11-xserver-utils \
    lightdm \
    lightdm-gtk-greeter \
    openbox \
    tint2 \
    xfce4 \
    xfce4-panel \
    xfce4-session \
    xfwm4 \
    xfdesktop4 \
    xfce4-terminal \
    thunar \
    xfce4-whiskermenu-plugin \
    xfce4-pulseaudio-plugin \
    greybird-gtk-theme \
    papirus-icon-theme \
    fonts-noto-core \
    adwaita-icon-theme \
    calamares \
    libqt5svg5 \
    parted \
    dosfstools \
    e2fsprogs \
    btrfs-progs \
    efibootmgr \
    grub-pc-bin \
    grub-efi-amd64-bin \
    grub-efi-amd64-signed \
    shim-signed \
    upower \
    policykit-1 \
    libpolkit-agent-1-0

# Настройка Casper для правильного распознавания пользователя
cat <<'CASPER' > /etc/casper.conf
export USERNAME="ubuntu"
export USERFULLNAME="Live session user"
export HOST="winubuntu"
export BUILD_SYSTEM="Ubuntu"
CASPER

# Создание Live-пользователя 'ubuntu' со всеми правами sudo
for u in ubuntu live; do
    if ! id -u "$u" >/dev/null 2>&1; then
        useradd -m -s /bin/bash -G sudo,adm,video,audio,netdev "$u"
        passwd -d "$u"
    fi
    echo "$u ALL=(ALL) NOPASSWD: ALL" > "/etc/sudoers.d/99-$u"
    chmod 0440 "/etc/sudoers.d/99-$u"
    cp -r /etc/skel/. "/home/$u/" || true
    chmod +x "/home/$u/Desktop/"*.desktop 2>/dev/null || true
    chown -R "$u:$u" "/home/$u"
done

# Настройка меню Openbox для режима инсталлятора
mkdir -p /etc/xdg/openbox
cat <<'OPENBOX_MENU' > /etc/xdg/openbox/menu.xml
<?xml version="1.0" encoding="UTF-8"?>
<openbox_menu xmlns="http://openbox.org/3.4/menu">
  <menu id="root-menu" label="WinUbuntu Installer">
    <item label="Запустить установщик WinUbuntu">
      <action name="Execute"><command>sudo -E calamares -d</command></action>
    </item>
    <item label="Терминал">
      <action name="Execute"><command>xfce4-terminal</command></action>
    </item>
    <separator />
    <item label="Перезагрузить">
      <action name="Execute"><command>systemctl reboot</command></action>
    </item>
    <item label="Выключить">
      <action name="Execute"><command>systemctl poweroff</command></action>
    </item>
  </menu>
</openbox_menu>
OPENBOX_MENU

# Создание скрипта запуска прямого режима инсталлятора (Windows Setup Style)
cat <<'INSTALLER' > /usr/local/bin/start-installer
#!/bin/bash
xhost +local: >/dev/null 2>&1 || true
export DISPLAY="${DISPLAY:-:0}"
export XAUTHORITY="${XAUTHORITY:-$HOME/.Xauthority}"

# Установка приятного темного фона в стиле Windows Setup
xsetroot -solid "#1e222a" &

# Оконный менеджер для поддержки рамок окон
openbox &

# Нижняя панель с переключением раскладки и Wi-Fi
tint2 &
nm-applet &
setxkbmap -layout "us,ru" -option "grp:alt_shift_toggle" &

# Запуск установщика Calamares
while true; do
    sudo -E calamares -d
    ret=$?
    if [ $ret -eq 0 ]; then
        systemctl reboot || true
        break
    fi
    sleep 2
done
INSTALLER
chmod +x /usr/local/bin/start-installer

# Создание xsession для прямого инсталлятора
mkdir -p /usr/share/xsessions
cat <<'XSESSION' > /usr/share/xsessions/installer.desktop
[Desktop Entry]
Name=WinUbuntu Installer
Comment=Direct graphical installer
Exec=/usr/local/bin/start-installer
Type=Application
XSESSION

# Настройка автологина LightDM сразу в сеанс инсталлятора
mkdir -p /etc/lightdm/lightdm.conf.d
cat <<'LIGHTDM' > /etc/lightdm/lightdm.conf.d/20-autologin.conf
[Seat:*]
autologin-guest=false
autologin-user=ubuntu
autologin-user-timeout=0
user-session=installer
LIGHTDM

systemctl enable lightdm || true

# Очистка кэша пакетов
apt-get clean
rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*
EOF

# Копирование всех настроек Calamares в chroot
echo "Копирование конфигурации Calamares..."
mkdir -p "${CHROOT_DIR}/etc/calamares/modules"
mkdir -p "${CHROOT_DIR}/etc/calamares/branding/winubuntu"
cp "${WORKDIR}/config/calamares/settings.conf" "${CHROOT_DIR}/etc/calamares/settings.conf"
cp "${WORKDIR}/config/calamares/modules/"*.conf "${CHROOT_DIR}/etc/calamares/modules/"
cp "${WORKDIR}/config/calamares/branding/winubuntu/"* "${CHROOT_DIR}/etc/calamares/branding/winubuntu/"

echo ">>> [Шаг 2] Настройка окружения инсталлятора завершена успешно!"
