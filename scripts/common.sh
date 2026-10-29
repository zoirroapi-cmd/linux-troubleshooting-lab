#!/usr/bin/env bash

set -euo pipefail

# Цвета
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

info() {
    echo -e "${BLUE}[INFO]${NC} $*"
}

success() {
    echo -e "${GREEN}[OK]${NC} $*"
}

warn() {
    echo -e "${YELLOW}[WARN]${NC} $*"
}

error() {
    echo -e "${RED}[ERROR]${NC} $*" >&2
}

die() {
    error "$*"
    exit 1
}

check_root() {
    if [[ $EUID -ne 0 ]]; then
        die "Этот лаб нужно запускать от root (используй sudo)"
    fi
}

get_lab_dir() {
    local lab_id="$1"
    echo "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/labs/${lab_id}"
}