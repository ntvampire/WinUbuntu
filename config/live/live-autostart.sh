#!/bin/bash
# Запуск системного трея и апплета Wi-Fi для подключения к сети
nm-applet &
tint2 &

# Установка русской раскладки клавиатуры и переключения по Alt+Shift
setxkbmap -layout "us,ru" -option "grp:alt_shift_toggle" &

# Автоматический запуск установщика Calamares
exec sudo calamares -d
