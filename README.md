# Linux Troubleshooting Lab

Практическая лаборатория по диагностике и устранению проблем в Linux.

Набор намеренно сломанных сценариев, которые помогают прокачать навыки troubleshooting.  
Каждый лаб имитирует реальную проблему: сеть, диски, сервисы, права доступа, процессы и т.д.

## Возможности

- 8 готовых сценариев разной сложности
- Автоматический запуск и сброс лабов
- Система подсказок (3 уровня)
- Проверка решения одной командой
- Подробные решения с объяснениями

## Требования

- Linux (Ubuntu 22.04+ / Debian 12+ / Fedora / Arch — желательно)
- Права root (или sudo)
- Bash 4+
- `curl`, `systemctl`, `ip`, `df`, `ps` (обычно уже есть)

> **Важно:** Лабы работают прямо на хосте. Рекомендуется запускать в виртуальной машине или на тестовой системе.

## Быстрый старт

```bash
# Клонируем репозиторий
git clone https://github.com/YOUR_USERNAME/linux-troubleshooting-lab.git
cd linux-troubleshooting-lab

# Делаем скрипт исполняемым
chmod +x scripts/lab.sh

# Смотрим список доступных лабов
./scripts/lab.sh list

Как пользоватьсяBash# Запустить лаб
sudo ./scripts/lab.sh start 01-network-dns

# Посмотреть подсказку (уровень 1, 2 или 3)
./scripts/lab.sh hint 01-network-dns 1

# Проверить, решена ли проблема
sudo ./scripts/lab.sh check 01-network-dns

# Сбросить лаб в исходное (сломанное) состояние
sudo ./scripts/lab.sh reset 01-network-dnsСписок лабов


























































№НазваниеОписаниеСложность01network-dnsНе работает DNS / интернетEasy02disk-fullДиск заполнен на 100%Easy03service-failedsystemd-сервис не запускаетсяMedium04permission-deniedПроблемы с правами доступаEasy05high-cpuПроцесс сильно нагружает CPUMedium06readonly-fsФайловая система перешла в readonlyMedium07firewall-blockFirewall блокирует нужный портMedium08zombie-processМного зомби-процессовHardСтруктура проектаtextlinux-troubleshooting-lab/
├── README.md
├── labs/
│   ├── 01-network-dns/
│   │   ├── README.md          # Описание симптомов
│   │   ├── break.sh           # Скрипт, который ломает
│   │   ├── check.sh           # Проверка решения
│   │   ├── hints.md           # Подсказки
│   │   └── solution.md        # Полное решение
│   ├── 02-disk-full/
│   └── ...
├── scripts/
│   ├── lab.sh                 # Главный скрипт управления
│   └── common.sh
├── docs/
│   ├── how-to-use.md
│   └── contributing.md
└── MakefileРекомендуемый порядок прохождения
01-network-dns
04-permission-denied
02-disk-full
03-service-failed
07-firewall-block
05-high-cpu
06-readonly-fs
08-zombie-process
