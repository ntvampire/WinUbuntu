#!/usr/bin/env bash
set -euo pipefail

WORKDIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CHROOT_DIR="${WORKDIR}/work/chroot"
UBUNTU_RELEASE="noble"
MIRROR_URL="http://archive.ubuntu.com/ubuntu/"

echo ">>> [Шаг 1] Базовый bootstrap Ubuntu 24.04 ($UBUNTU_RELEASE)..."

mkdir -p "${CHROOT_DIR}"

if [ ! -f "${CHROOT_DIR}/bin/bash" ]; then
    echo "Запуск debootstrap minbase..."
    debootstrap --arch=amd64 \
        --variant=minbase \
        --include=ca-certificates,gnupg,curl,wget,locales \
        "${UBUNTU_RELEASE}" "${CHROOT_DIR}" "${MIRROR_URL}"
else
    echo "Базовый chroot уже существует, пропускаем debootstrap."
fi

# Настройка репозиториев
cat <<EOF > "${CHROOT_DIR}/etc/apt/sources.list"
deb ${MIRROR_URL} ${UBUNTU_RELEASE} main restricted universe multiverse
deb ${MIRROR_URL} ${UBUNTU_RELEASE}-updates main restricted universe multiverse
deb ${MIRROR_URL} ${UBUNTU_RELEASE}-security main restricted universe multiverse
EOF

# Настройка имени хоста и хостов
echo "winubuntu-live" > "${CHROOT_DIR}/etc/hostname"
cat <<EOF > "${CHROOT_DIR}/etc/hosts"
127.0.0.1   localhost
127.0.1.1   winubuntu-live
EOF

# Настройка локалей (русская и английская)
cat <<EOF > "${CHROOT_DIR}/etc/locale.gen"
en_US.UTF-8 UTF-8
ru_RU.UTF-8 UTF-8
EOF

echo ">>> [Шаг 1] Bootstrap успешно завершён!"
