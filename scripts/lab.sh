#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common.sh"

LABS_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)/labs"

usage() {
    cat <<EOF
Использование: $0 <команда> [лаб] [опции]

Команды:
  list                    Показать все доступные лабы
  start <lab>             Запустить (сломать) лаб
  reset <lab>             Сбросить лаб в сломанное состояние
  check <lab>             Проверить, решена ли проблема
  hint <lab> <уровень>    Показать подсказку (1, 2 или 3)
  solution <lab>          Показать полное решение
  status <lab>            Показать статус лаба

Примеры:
  $0 list
  sudo $0 start 01-network-dns
  $0 hint 01-network-dns 1
  sudo $0 check 01-network-dns
EOF
}

list_labs() {
    echo "Доступные лабы:"
    echo
    for lab in "${LABS_DIR}"/*/; do
        lab_name=$(basename "$lab")
        if [[ -f "${lab}/README.md" ]]; then
            # Берём первую строку после заголовка как описание
            desc=$(sed -n '3p' "${lab}/README.md" 2>/dev/null || echo "")
            printf "  %-22s %s\n" "$lab_name" "$desc"
        fi
    done
}

start_lab() {
    local lab_id="$1"
    local lab_dir
    lab_dir=$(get_lab_dir "$lab_id")

    [[ -d "$lab_dir" ]] || die "Лаб '$lab_id' не найден"

    check_root

    if [[ -f "${lab_dir}/break.sh" ]]; then
        info "Запускаю лаб: $lab_id"
        bash "${lab_dir}/break.sh"
        success "Лаб '$lab_id' сломан и готов к решению"
        echo
        echo "Симптомы:"
        sed -n '1,20p' "${lab_dir}/README.md"
    else
        die "В лабе нет break.sh"
    fi
}

reset_lab() {
    local lab_id="$1"
    start_lab "$lab_id"
}

check_lab() {
    local lab_id="$1"
    local lab_dir
    lab_dir=$(get_lab_dir "$lab_id")

    [[ -d "$lab_dir" ]] || die "Лаб '$lab_id' не найден"
    check_root

    if [[ -f "${lab_dir}/check.sh" ]]; then
        if bash "${lab_dir}/check.sh"; then
            success "Поздравляю! Лаб '$lab_id' решён правильно."
        else
            error "Проблема ещё не решена."
            exit 1
        fi
    else
        die "В лабе нет check.sh"
    fi
}

show_hint() {
    local lab_id="$1"
    local level="${2:-1}"
    local lab_dir
    lab_dir=$(get_lab_dir "$lab_id")

    [[ -d "$lab_dir" ]] || die "Лаб '$lab_id' не найден"
    [[ -f "${lab_dir}/hints.md" ]] || die "Подсказки не найдены"

    case "$level" in
        1|2|3) ;;
        *) die "Уровень подсказки должен быть 1, 2 или 3" ;;
    esac

    echo "=== Подсказка уровня $level ==="
    echo
    # Показываем нужный уровень из hints.md
    awk -v lvl="$level" '
        $0 ~ "^## Уровень "lvl {flag=1; next}
        $0 ~ /^## Уровень / {flag=0}
        flag {print}
    ' "${lab_dir}/hints.md"
}

show_solution() {
    local lab_id="$1"
    local lab_dir
    lab_dir=$(get_lab_dir "$lab_id")

    [[ -d "$lab_dir" ]] || die "Лаб '$lab_id' не найден"
    [[ -f "${lab_dir}/solution.md" ]] || die "Решение не найдено"

    cat "${lab_dir}/solution.md"
}

# === main ===
[[ $# -lt 1 ]] && { usage; exit 1; }

command="$1"
shift

case "$command" in
    list)
        list_labs
        ;;
    start)
        [[ $# -eq 1 ]] || die "Укажи название лаба"
        start_lab "$1"
        ;;
    reset)
        [[ $# -eq 1 ]] || die "Укажи название лаба"
        reset_lab "$1"
        ;;
    check)
        [[ $# -eq 1 ]] || die "Укажи название лаба"
        check_lab "$1"
        ;;
    hint)
        [[ $# -ge 1 ]] || die "Укажи название лаба"
        show_hint "$1" "${2:-1}"
        ;;
    solution)
        [[ $# -eq 1 ]] || die "Укажи название лаба"
        show_solution "$1"
        ;;
    help|-h|--help)
        usage
        ;;
    *)
        error "Неизвестная команда: $command"
        usage
        exit 1
        ;;
esac