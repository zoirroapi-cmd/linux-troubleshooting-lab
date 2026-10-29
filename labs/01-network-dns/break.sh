#!/usr/bin/env bash

set -euo pipefail

# Ломаем DNS
echo "nameserver 127.0.0.1" > /etc/resolv.conf

# На всякий случай убираем другие источники DNS (systemd-resolved)
if systemctl is-active --quiet systemd-resolved; then
    systemctl stop systemd-resolved
    systemctl disable systemd-resolved 2>/dev/null || true
fi

# На системах с NetworkManager тоже подчищаем
if command -v nmcli &>/dev/null; then
    nmcli networking off 2>/dev/null || true
    sleep 1
    nmcli networking on 2>/dev/null || true
fi

echo "DNS сломан."