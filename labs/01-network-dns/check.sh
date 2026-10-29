#!/usr/bin/env bash

set -euo pipefail

# Проверяем, что DNS работает
if ! getent hosts google.com > /dev/null 2>&1; then
    echo "DNS всё ещё не работает (getent hosts google.com failed)"
    exit 1
fi

if ! ping -c 1 -W 2 google.com > /dev/null 2>&1; then
    echo "ping google.com не проходит"
    exit 1
fi

echo "DNS работает корректно"
exit 0