#!/usr/bin/env bash
set -euo pipefail

WORKDIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "=========================================================="
echo "          WinUbuntu: Сборщик минимального ISO             "
echo "=========================================================="

# Проверка прав суперпользователя root
if [ "$(id -u)" -ne 0 ]; then
    echo "ОШИБКА: Этот скрипт должен быть запущен с правами root (sudo)." >&2
    echo "Использование: sudo ./build.sh" >&2
    exit 1
fi

# Установка необходимых утилит хоста для сборки
echo "Проверка и установка сборочных зависимостей хоста..."
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y --no-install-recommends \
    debootstrap \
    squashfs-tools \
    xorriso \
    grub-pc-bin \
    grub-efi-amd64-bin \
    shim-signed \
    mtools \
    dosfstools \
    curl \
    ca-certificates

chmod +x "${WORKDIR}/scripts/"*.sh

# Выполнение шагов сборки
echo "=== Этап 1: Bootstrap базовой системы ==="
"${WORKDIR}/scripts/01-bootstrap-base.sh"

echo "=== Этап 2: Настройка Live-окружения и Calamares ==="
"${WORKDIR}/scripts/02-setup-live.sh"

echo "=== Этап 3: Упаковка и сборка ISO ==="
"${WORKDIR}/scripts/03-build-iso.sh"

echo "Сборка успешно завершена!"
