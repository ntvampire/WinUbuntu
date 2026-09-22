#!/usr/bin/env bash
set -e

export DEBIAN_FRONTEND=noninteractive
echo "======================================================"
echo "    WinUbuntu: Начало сетевой настройки системы       "
echo "======================================================"

# 1. Проверка доступности интернета
echo "[1/7] Проверка подключения к интернету..."
if ! ping -c 1 -W 3 8.8.8.8 >/dev/null 2>&1; then
    echo "ВНИМАНИЕ: Нет пинга до 8.8.8.8, попытка продолжить..."
fi

# 2. Подключение репозиториев Ubuntu (universe, multiverse)
echo "[2/7] Подключение официальных репозиториев..."
apt-get update
apt-get install -y --no-install-recommends \
    software-properties-common \
    curl \
    gnupg \
    ca-certificates \
    apt-transport-https

add-apt-repository -y universe
add-apt-repository -y multiverse

# 3. Подключение официального репозитория Яндекс.Браузера
echo "[3/7] Подключение репозитория Яндекс.Браузера..."
curl -fsSL https://repo.yandex.ru/yandex-browser/YANDEX-BROWSER-KEY.GPG | \
    gpg --dearmor -o /etc/apt/trusted.gpg.d/yandex-browser.gpg --yes

echo "deb [arch=amd64 signed-by=/etc/apt/trusted.gpg.d/yandex-browser.gpg] http://repo.yandex.ru/yandex-browser/deb stable main" > \
    /etc/apt/sources.list.d/yandex-browser.list

apt-get update

# 4. Установка рабочего стола XFCE и темы
echo "[4/7] Установка легковесного окружения XFCE и тем оформления..."
apt-get install -y --no-install-recommends \
    xorg \
    lightdm \
    lightdm-gtk-greeter \
    xfce4 \
    xfce4-goodies \
    xfce4-whiskermenu-plugin \
    xfce4-pulseaudio-plugin \
    xfce4-power-manager \
    xfce4-taskmanager \
    xfce4-screenshooter \
    xfce4-terminal \
    thunar \
    thunar-archive-plugin \
    thunar-media-tags-plugin \
    tumbler \
    gvfs-backends \
    gvfs-fuse \
    network-manager-gnome \
    pavucontrol \
    pulseaudio \
    xcape \
    greybird-gtk-theme \
    papirus-icon-theme \
    fonts-noto-core \
    fonts-dejavu-core \
    gnome-software \
    gnome-software-plugin-pk-packagekit \
    preload

# 5. Установка приложений по списку пользователя
echo "[5/7] Установка набора приложений (Яндекс, Celluloid, Audacious, eog, file-roller, atril)..."
apt-get install -y --no-install-recommends \
    yandex-browser-stable \
    celluloid \
    audacious \
    audacious-plugins \
    eog \
    file-roller \
    p7zip-full \
    unrar-free \
    zip \
    unzip \
    atril

# 6. Оптимизация для слабого железа (Celeron J1800, 4Гб ОЗУ) и кодеки
echo "[6/7] Оптимизация железа (VA-API аппаратное видео) и памяти (zram)..."
apt-get install -y --no-install-recommends \
    intel-media-va-driver \
    i965-va-driver \
    va-driver-all \
    mesa-va-drivers \
    zram-tools \
    gstreamer1.0-plugins-good \
    gstreamer1.0-plugins-bad \
    gstreamer1.0-plugins-ugly \
    gstreamer1.0-libav

# Настройка zram (50% ОЗУ в виде быстрого сжатого swap zstd)
if [ -f /etc/default/zramswap ]; then
    sed -i 's/^#*PERCENTAGE=.*/PERCENTAGE=50/' /etc/default/zramswap
    sed -i 's/^#*ALLOCATION=.*/ALLOCATION=2048/' /etc/default/zramswap
    sed -i 's/^#*PRIORITY=.*/PRIORITY=100/' /etc/default/zramswap
else
    cat <<EOF > /etc/default/zramswap
PERCENTAGE=50
PRIORITY=100
EOF
fi
systemctl enable zramswap || true
systemctl enable preload || true

# 7. Применение конфигурации Windows-стиля для пользователей
echo "[7/7] Применение профилей рабочего стола и очистка установщика..."

# Копирование настроек для всех пользователей
for user_home in /home/*; do
    if [ -d "$user_home" ]; then
        user=$(basename "$user_home")
        cp -r /etc/skel/. "$user_home/" || true
        chown -R "$user:$user" "$user_home" || true
    fi
done

# Включение LightDM в качестве дисплейного менеджера
systemctl enable lightdm || true

# Удаление следов Live-образа и инсталлятора из системы
apt-get purge -y --autoremove \
    casper \
    calamares \
    calamares-settings-ubuntu || true

# Очистка apt кэша для экономии места на диске
apt-get clean
rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

# Финальное обновление загрузчика и initramfs
update-initramfs -u -k all || true
update-grub || true

echo "======================================================"
echo "    WinUbuntu: Установка и настройка завершены!       "
echo "======================================================"
