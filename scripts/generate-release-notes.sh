#!/usr/bin/env bash
set -euo pipefail

WORKDIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUTPUT_DIR="${WORKDIR}/output"

ISO_PATH=$(ls "${OUTPUT_DIR}"/*.iso | head -n 1)
ISO_FILE=$(basename "${ISO_PATH}")
SHA_VAL=$(cat "${OUTPUT_DIR}"/*.sha256 | awk '{print $1}')
SIZE_VAL=$(du -h "${ISO_PATH}" | awk '{print $1}')
DATE_VAL=$(date +'%Y-%m-%d')

CUSTOM_NOTES="${1:-}"
if [ -n "${CUSTOM_NOTES}" ]; then
    NOTES="${CUSTOM_NOTES}"
else
    NOTES=$(git log -1 --pretty=%B | head -n 5)
fi

# Экспорт для GitHub Actions (если запущен в CI)
if [ -n "${GITHUB_OUTPUT:-}" ]; then
    echo "iso_name=${ISO_FILE}" >> "${GITHUB_OUTPUT}"
    echo "iso_size=${SIZE_VAL}" >> "${GITHUB_OUTPUT}"
    echo "sha256=${SHA_VAL}" >> "${GITHUB_OUTPUT}"
fi

cat <<EOF > "${WORKDIR}/release_body.md"
## 💿 WinUbuntu 24.04 LTS (Minimal Netinstall)

Минимальный, легковесный и интуитивно понятный образ на базе **Ubuntu 24.04 LTS (Noble Numbat)** в привычном стиле **Windows 10/11**, созданный специально для слабых ПК и ноутбуков (уровень Celeron J1800 / 4GB RAM).

---

### 📌 Что изменилось в этой версии
${NOTES}

---

### 💾 Файлы релиза
- **Образ**: \`${ISO_FILE}\` (~${SIZE_VAL})
- **Контрольная сумма SHA256**:
\`\`\`
${SHA_VAL}
\`\`\`

---

### 🖥️ Состав сборки:
- **Рабочий стол**: XFCE 4.18 (интерфейс Windows 10/11: нижняя панель, меню «Пуск» с поиском, быстрый трей, кнопка «Свернуть все окна»).
- **Веб-браузер**: **Яндекс.Браузер** (официальный репозиторий Яндекса с автообновлением).
- **Магазин приложений**: **GNOME Software** (каталог программ для установки в один клик).
- **Медиаплееры**: **Celluloid** (видео с аппаратным ускорением Intel VA-API) + **Audacious** (аудио).
- **Утилиты**: **Eye of GNOME** (просмотр фото), **File-Roller** (архиватор zip, rar, 7z), **Atril** (документы и PDF).

### ⚡ Оптимизации для слабого железа и HDD:
- **\`zram-tools\`**: сжатый swap в RAM (zstd 50% ОЗУ) — спасает от зависаний при нехватке памяти.
- **\`preload\` + \`noatime\`**: ускорение загрузки приложений с обычных механических дисков (HDD) и снижение лишней записи.
- **Драйверы Intel VA-API**: аппаратное декодирование видео силами встроенной графики Intel HD.

---

### 🚀 Как записать и установить:
1. Скопируйте файл \`.iso\` на флешку с **Ventoy** или запишите через **Rufus** (режим UEFI или BIOS).
2. Загрузитесь с флешки — откроется графический установщик **Calamares**.
3. Подключитесь к сети (Wi-Fi или кабель) и следуйте шагам мастера на экране.
EOF

echo "Файл release_body.md успешно сформирован!"
