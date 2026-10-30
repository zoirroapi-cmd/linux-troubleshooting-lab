# 01 — Network DNS: полный разбор и справочник

**Симптом:** `ping 8.8.8.8` работает, а `ping google.com` → `Name or service not known`. Браузер и `curl` по имени не работают.

**Цель:** вернуть нормальную работу DNS.

---

## 0. TL;DR — что делать, если некогда читать теорию

```bash
# 1. Подтвердить симптом
ping -c2 8.8.8.8                    # OK  → сеть (L3) жива
ping -c2 google.com                 # FAIL → проблема именно в резолвинге

# 2. Что настроено у системы?
cat /etc/resolv.conf                # какие nameserver?
ls -l /etc/resolv.conf              # файл или симлинк? не битый ли?
grep ^hosts /etc/nsswitch.conf      # есть ли dns в списке?
resolvectl status                   # (если есть systemd-resolved)

# 3. Работает ли ВНЕШНИЙ DNS, если обратиться к нему напрямую?
dig @8.8.8.8 google.com +short      # OK  → проблема в локальной настройке
                                    # FAIL → порт 53 режет firewall/сеть

# 4. Быстрый временный фикс
echo "nameserver 8.8.8.8" | sudo tee /etc/resolv.conf

# 5. Проверка
getent hosts google.com && curl -sI https://google.com | head -1
```

Дальше — всё то же самое, но с объяснениями.

---

## 1. Теория: как вообще работает DNS

### 1.1 Зачем нужен DNS

Компьютеры общаются по IP-адресам (`142.250.74.14`), люди запоминают имена (`google.com`). **DNS (Domain Name System)** — распределённая «телефонная книга», которая переводит имя в IP (и обратно).

Важно: **DNS — это отдельный сервис поверх сети.** Сеть может работать идеально (пакеты ходят), а DNS — быть сломан. Именно это и показывает наш симптом.

### 1.2 Почему `ping 8.8.8.8` работает, а `ping google.com` нет

Это ключевая диагностическая подсказка. Разберём, что она говорит:

| Факт | Что это значит |
|---|---|
| `ping 8.8.8.8` работает | Есть IP-адрес, есть маршрут (default gateway), есть выход в интернет. Уровни L1–L3 в порядке |
| `ping google.com` не работает | Ошибка возникает **до отправки пакета**: система не смогла превратить имя в IP |
| Ошибка `Name or service not known` | Это ошибка резолвера (`getaddrinfo`), а не сети. Ответ «я не знаю такого имени / не смог спросить» |

Вывод: **сеть не виновата, ломается именно цепочка резолвинга имён.** Искать нужно не кабель/роутер/маршрут, а DNS-настройки.

> Если бы не работал и `ping 8.8.8.8` — проблема была бы в другом месте (интерфейс, IP, шлюз, маршрут). Это отдельная диагностика (см. раздел 9).

### 1.3 Цепочка резолвинга на Linux (самое важное)

Когда приложение (curl, браузер, ping) просит «дай IP для google.com», происходит так:

```
Приложение (curl, ping, браузер)
        │  вызывает getaddrinfo() из glibc
        ▼
┌───────────────────────────────┐
│ NSS — Name Service Switch     │  читает /etc/nsswitch.conf
│ строка: hosts: files dns ...  │  определяет ПОРЯДОК источников
└───────────────────────────────┘
        │
        ├─► 1) files → /etc/hosts        (локальный статический файл)
        │        нашлось? → возвращаем, КОНЕЦ
        │
        └─► 2) dns → stub resolver (glibc) читает /etc/resolv.conf
                 │   nameserver 127.0.0.53   (или реальный DNS)
                 ▼
          Локальный кэширующий резолвер (systemd-resolved, dnsmasq, unbound...)
                 │   есть в кэше? → отвечает
                 ▼
          Upstream DNS-сервер (от провайдера / роутера / 8.8.8.8 / 1.1.1.1)
                 │  UDP/TCP порт 53
                 ▼
          Рекурсивный резолвер ходит по иерархии:
             Root (.) → TLD (.com) → авторитативный NS google.com
                 │
                 ▼
          Ответ: google.com A 142.250.74.14  (с TTL)
```

Ломаться может **любое звено**:

1. `nsswitch.conf` — нет `dns` в строке `hosts` → система вообще не пойдёт спрашивать DNS.
2. `/etc/resolv.conf` — пустой, битый симлинк, указывает на неверный/мёртвый сервер.
3. Локальный резолвер (`systemd-resolved`) — упал/не запущен, а `resolv.conf` смотрит на `127.0.0.53`.
4. Upstream DNS — недоступен, не отвечает.
5. Сеть до DNS — firewall блокирует порт 53 (UDP/TCP).
6. `/etc/hosts` — содержит неверную запись, перехватывающую имя.
7. Сам домен — не существует / проблема на стороне авторитативных серверов (не наш случай, т.к. `google.com` живой).

### 1.4 Ключевые файлы и их роль

| Файл | Роль |
|---|---|
| `/etc/resolv.conf` | Список DNS-серверов (`nameserver`), `search`-домены, опции (`options`) |
| `/etc/nsswitch.conf` | Порядок источников для имён (`hosts: files dns`) |
| `/etc/hosts` | Локальная статическая таблица «имя ↔ IP». Проверяется **раньше** DNS |
| `/etc/systemd/resolved.conf` | Конфиг systemd-resolved (DNS=, FallbackDNS=, DNSSEC= ...) |
| `/run/systemd/resolve/resolv.conf` | «Настоящий» resolv.conf от systemd-resolved с реальными upstream-серверами |
| `/run/systemd/resolve/stub-resolv.conf` | Заглушка: `nameserver 127.0.0.53` |
| `/etc/NetworkManager/NetworkManager.conf` | Настройки NM, в т.ч. `dns=` (кто управляет resolv.conf) |
| `/etc/netplan/*.yaml` (Ubuntu) | Конфиг сети, в т.ч. `nameservers:` |
| `/etc/dhcp/dhclient.conf` | Поведение DHCP-клиента (может перезаписывать resolv.conf) |

### 1.5 Формат `/etc/resolv.conf`

```
nameserver 8.8.8.8          # IP DNS-сервера (до 3 штук, опрашиваются по порядку)
nameserver 1.1.1.1
search example.local        # домены, дописываемые к коротким именам (host → host.example.local)
options timeout:2 attempts:2 ndots:1
```

- `nameserver` — максимум 3 записи используются. Если первый не отвечает — **ждём timeout** (по умолчанию 5 сек) и идём ко второму. Поэтому «тормозит DNS» часто = мёртвый первый nameserver.
- `search` / `domain` — суффиксы для коротких имён.
- `options ndots:N` — если в имени меньше N точек, сначала пробуются search-суффиксы (важно в Kubernetes: там `ndots:5`).
- Файл часто **симлинк** на файл systemd-resolved. Его не надо править руками, если им управляет systemd-resolved/NM — перезапишет.

### 1.6 Что такое `127.0.0.53`

Это **stub-резолвер systemd-resolved**, слушающий на loopback. Приложения шлют запросы туда, а он уже сам ходит к реальным upstream-серверам, кэширует, умеет split-DNS по интерфейсам. Если `resolv.conf` указывает на `127.0.0.53`, а `systemd-resolved` не запущен — **DNS не работает**, хотя сеть в порядке. Это очень частая причина именно нашего симптома.

### 1.7 Транспорт и порты

- DNS: **порт 53, UDP** (по умолчанию), **TCP** — если ответ большой (>512 байт без EDNS), для зон-трансферов, для DNSSEC.
- DoT (DNS over TLS): порт 853. DoH (DNS over HTTPS): порт 443.
- Если firewall режет **UDP/53** — резолвинг молча «зависает» и падает по таймауту.

### 1.8 Основные типы DNS-записей

| Тип | Что хранит |
|---|---|
| `A` | IPv4-адрес |
| `AAAA` | IPv6-адрес |
| `CNAME` | Алиас (имя → другое имя) |
| `MX` | Почтовые серверы |
| `NS` | Авторитативные серверы зоны |
| `TXT` | Произвольный текст (SPF, DKIM, верификации) |
| `PTR` | Обратная запись (IP → имя) |
| `SOA` | Параметры зоны |
| `SRV` | Сервисы (хост+порт) |

### 1.9 Коды ответа DNS (`status:` в `dig`)

| Код | Значение | Что думать |
|---|---|---|
| `NOERROR` | Успех (может быть пустой ответ — записи такого типа нет) | Всё ок |
| `NXDOMAIN` | Имени не существует | Опечатка, или резолвер врёт/фильтрует |
| `SERVFAIL` | Сервер не смог выполнить запрос | Проблема у upstream, DNSSEC, недоступны авторитативные |
| `REFUSED` | Сервер отказал | ACL/firewall на сервере, не разрешена рекурсия |
| *timeout* ("no servers could be reached") | Нет ответа вообще | Сервер/порт недоступен, firewall |

### 1.10 TTL и кэш

Каждая запись имеет TTL (сек), в течение которого её можно кэшировать. Кэши бывают: в приложении (браузер), в локальном резолвере (`systemd-resolved`, `dnsmasq`, `nscd`), у провайдера. После исправления бывает нужно **сбросить кэш** (см. раздел 5).

---

## 2. Справочник команд диагностики

### 2.1 Проверка «сеть vs DNS» (первый шаг всегда)

| Команда | Что показывает | Как читать |
|---|---|---|
| `ping -c2 8.8.8.8` | Доступность IP без DNS | OK → L3 жив |
| `ping -c2 google.com` | Доступность по имени | FAIL при OK выше → проблема DNS |
| `curl -sI https://1.1.1.1 \| head -1` | HTTP по IP | OK → TCP/443 работает |
| `curl -sI https://google.com \| head -1` | HTTP по имени | FAIL → DNS |
| `curl -v --resolve google.com:443:142.250.74.14 https://google.com` | Обходит DNS, подставляя IP вручную | Работает → точно DNS, а не TLS/сеть |

### 2.2 Что настроено в системе

| Команда | Зачем |
|---|---|
| `cat /etc/resolv.conf` | Какие DNS-серверы использует система |
| `ls -l /etc/resolv.conf` | Симлинк или файл? Куда ведёт? Не битый ли (красный цвет в `ls --color`) |
| `readlink -f /etc/resolv.conf` | Конечная цель симлинка; если пусто — симлинк битый |
| `lsattr /etc/resolv.conf` | Нет ли атрибута `i` (immutable) — не даст править файл |
| `cat /etc/nsswitch.conf \| grep hosts` | Порядок источников; должно быть `files ... dns` |
| `cat /etc/hosts` | Нет ли «левых» записей, перехватывающих имя |
| `cat /etc/systemd/resolved.conf` | Конфиг resolved (`DNS=`, `FallbackDNS=`) |
| `ls -la /etc/resolv.conf /run/systemd/resolve/` | Какие файлы есть у resolved |

### 2.3 systemd-resolved

| Команда | Зачем |
|---|---|
| `systemctl status systemd-resolved` | Запущен ли сервис |
| `resolvectl status` | DNS-серверы **по каждому интерфейсу**, текущий DNS-сервер, DNSSEC, домены |
| `resolvectl query google.com` | Резолвинг **через resolved** (то же, что видят приложения), показывает источник ответа |
| `resolvectl statistics` | Статистика кэша, число запросов/ошибок |
| `resolvectl flush-caches` | Сбросить кэш |
| `resolvectl dns eth0 8.8.8.8` | Временно задать DNS на интерфейсе |
| `journalctl -u systemd-resolved -n 50 --no-pager` | Логи резолвера |
| `journalctl -u systemd-resolved -f` | Логи в реальном времени (запустить, затем в другом окне сделать запрос) |

> Старое имя команды: `systemd-resolve` (в старых системах), в новых — `resolvectl`.

### 2.4 Инструменты запросов (самые главные)

#### `dig` — основной инструмент (пакет `dnsutils` / `bind-utils`)

| Команда | Что делает |
|---|---|
| `dig google.com` | Запрос A-записи через DNS из `/etc/resolv.conf`. Смотрим `status`, `ANSWER`, `SERVER`, `Query time` |
| `dig google.com +short` | Только ответ (IP) |
| `dig @8.8.8.8 google.com` | **Спросить конкретный сервер напрямую**, минуя системные настройки |
| `dig @127.0.0.53 google.com` | Спросить локальный stub resolved |
| `dig google.com AAAA` / `MX` / `NS` / `TXT` | Запрос другого типа записи |
| `dig -x 8.8.8.8` | Обратный резолвинг (PTR) |
| `dig +trace google.com` | Полный путь рекурсии: root → TLD → авторитативный. Показывает, где обрывается |
| `dig +tcp @8.8.8.8 google.com` | Запрос по TCP вместо UDP (проверка, режется ли UDP) |
| `dig +time=2 +tries=1 @8.8.8.8 google.com` | Быстрый таймаут для диагностики |
| `dig +norecurse @server name` | Без рекурсии (проверка авторитативности) |
| `dig +dnssec google.com` | Проверка DNSSEC |
| `dig +noall +answer +stats google.com` | Компактный вывод |

**Как читать вывод `dig`:**

```
;; ->>HEADER<<- opcode: QUERY, status: NOERROR, id: 12345       ← статус ответа
;; flags: qr rd ra; QUERY: 1, ANSWER: 1, AUTHORITY: 0 ...      ← qr=ответ, rd=рекурсия запрошена, ra=рекурсия доступна
;; ANSWER SECTION:
google.com.   300   IN   A   142.250.74.14                      ← имя, TTL, класс, тип, значение
;; Query time: 12 msec                                          ← время ответа
;; SERVER: 127.0.0.53#53(127.0.0.53)                            ← КОТОРЫЙ сервер ответил — очень важно
```

- `connection timed out; no servers could be reached` → сервер недоступен/порт закрыт.
- Нет флага `ra` → сервер не поддерживает рекурсию (не годится как resolver).

#### `nslookup`, `host`

| Команда | Что делает |
|---|---|
| `nslookup google.com` | Запрос через системный DNS |
| `nslookup google.com 8.8.8.8` | Запрос к конкретному серверу |
| `host google.com` | Краткий вывод (A, AAAA, MX) |
| `host google.com 8.8.8.8` | Спросить конкретный сервер |

#### `getent` — важнейшая команда для проверки «как видит система»

```bash
getent hosts google.com
```

`getent` использует **тот же путь, что и приложения** (через `nsswitch.conf` → glibc), в отличие от `dig`/`nslookup`, которые делают DNS-запрос напрямую, игнорируя `/etc/hosts` и `nsswitch`.

**Золотое правило диагностики:**

| `dig @8.8.8.8` | `getent hosts` | Вывод |
|---|---|---|
| OK | OK | Всё работает |
| OK | FAIL | Проблема **локальная**: `resolv.conf` / `nsswitch.conf` / resolved / hosts |
| FAIL (timeout) | FAIL | Проблема **сетевая**: порт 53 заблокирован, либо upstream недоступен |
| FAIL | OK | Имя взято из `/etc/hosts` или кэша |

### 2.5 Проверка сетевой части до DNS

| Команда | Зачем |
|---|---|
| `ip a` | Есть ли IP на интерфейсе, состояние `UP` |
| `ip r` | Есть ли `default via <шлюз>` |
| `ping -c2 <шлюз>` | Доступен ли шлюз |
| `nc -vzu 8.8.8.8 53` | Открыт ли UDP/53 (UDP-проверка ненадёжна, ориентир) |
| `nc -vz 8.8.8.8 53` | Открыт ли TCP/53 |
| `timeout 3 bash -c '</dev/tcp/8.8.8.8/53' && echo open` | TCP/53 без nc |
| `ss -lntup \| grep :53` | **Кто слушает порт 53 локально** (resolved, dnsmasq, named...) |
| `sudo lsof -i :53` | То же, через lsof |
| `traceroute -n 8.8.8.8` / `mtr -n 8.8.8.8` | Путь до DNS-сервера |

### 2.6 Firewall

| Команда | Зачем |
|---|---|
| `sudo iptables -L -n -v --line-numbers` | Правила iptables (ищем `DROP`/`REJECT` на `dpt:53`) |
| `sudo iptables -S` | Правила в виде команд |
| `sudo iptables -t nat -L -n -v` | NAT-таблица (редиректы DNS) |
| `sudo nft list ruleset` | Правила nftables |
| `sudo ufw status verbose` | Статус ufw |
| `sudo firewall-cmd --list-all` | firewalld (RHEL/CentOS) |

Что ищем: правила вида `DROP udp dpt:53`, `REJECT tcp dpt:53`, политика `OUTPUT DROP` без разрешения DNS.

### 2.7 Перехват трафика (когда ничего не понятно)

```bash
sudo tcpdump -i any -nn port 53
# в другом терминале: dig google.com
```

Что видим:
- Запросы уходят, ответов нет → блокируют по пути/сервер мёртв.
- Запросов нет вообще → приложение не доходит до DNS (nsswitch / resolv.conf / hosts / resolved).
- Запросы уходят не туда, куда ожидаем → смотрим `resolv.conf`.
- Ответ приходит с `NXDOMAIN`/`SERVFAIL` → смотрим сам ответ.

Полезно: `sudo tcpdump -i any -nn -vv port 53 -c 20`; вывод в файл `-w dns.pcap` для Wireshark.

### 2.8 Трассировка системных вызовов

```bash
strace -f -e trace=openat,connect,sendto,recvfrom curl -sI https://google.com 2>&1 | head -50
```

Покажет, какие файлы читает curl (`nsswitch.conf`, `resolv.conf`, `hosts`) и куда подключается. Удобно, чтобы увидеть, что реально происходит.

### 2.9 NetworkManager / netplan / DHCP

| Команда | Зачем |
|---|---|
| `nmcli device show \| grep -E 'DEVICE\|IP4.DNS'` | Какие DNS выдал NM по интерфейсам |
| `nmcli con show` | Список соединений |
| `nmcli con show "<имя>" \| grep dns` | DNS-настройки соединения |
| `nmcli con mod "<имя>" ipv4.dns "8.8.8.8 1.1.1.1"` | Задать DNS |
| `nmcli con mod "<имя>" ipv4.ignore-auto-dns yes` | Игнорировать DNS от DHCP |
| `nmcli con up "<имя>"` | Переподнять соединение (применить) |
| `cat /etc/netplan/*.yaml` / `sudo netplan get` | Конфиг netplan |
| `sudo netplan try` / `sudo netplan apply` | Применить netplan |
| `journalctl -u NetworkManager -n 50 --no-pager` | Логи NM |
| `cat /var/lib/dhcp/dhclient*.leases` | Что выдал DHCP-сервер (option domain-name-servers) |

### 2.10 Кэш-демоны

| Команда | Зачем |
|---|---|
| `systemctl status nscd` | Запущен ли nscd (кэш NSS) |
| `sudo nscd -i hosts` | Сбросить кэш hosts в nscd |
| `systemctl status dnsmasq` / `unbound` / `named` | Локальные DNS-демоны |
| `sudo rndc flush` | Сбросить кэш BIND |

### 2.11 macOS (на случай, если дело на MacBook)

| Команда | Зачем |
|---|---|
| `scutil --dns` | Реальная DNS-конфигурация macOS (аналог resolvectl status) |
| `networksetup -getdnsservers Wi-Fi` | DNS для сервиса Wi-Fi |
| `sudo networksetup -setdnsservers Wi-Fi 8.8.8.8 1.1.1.1` | Задать DNS |
| `sudo dscacheutil -flushcache && sudo killall -HUP mDNSResponder` | Сбросить DNS-кэш |
| `dscacheutil -q host -a name google.com` | Резолвинг «как у приложений» (аналог getent) |

> На macOS `/etc/resolv.conf` — информационный файл, система его не использует для резолвинга приложений; смотреть нужно `scutil --dns`.

### 2.12 Docker / Kubernetes (если DNS сломан внутри контейнера/пода)

| Команда | Зачем |
|---|---|
| `docker run --rm busybox nslookup google.com` | Проверка DNS в контейнере |
| `docker run --rm --dns 8.8.8.8 busybox nslookup google.com` | С явным DNS |
| `cat /etc/docker/daemon.json` | Настройка `"dns": ["8.8.8.8"]` |
| `docker exec <ctr> cat /etc/resolv.conf` | resolv.conf контейнера |
| `kubectl run -it --rm dnstest --image=busybox:1.36 -- nslookup kubernetes.default` | Проверка DNS в кластере |
| `kubectl -n kube-system get pods -l k8s-app=kube-dns` | Статус CoreDNS |
| `kubectl -n kube-system logs -l k8s-app=kube-dns --tail=50` | Логи CoreDNS |
| `kubectl -n kube-system get cm coredns -o yaml` | Corefile (forward, upstream) |

---

## 3. Пошаговый алгоритм диагностики

Идём **строго по порядку**, на каждом шаге — вывод и решение. Не прыгать вперёд.

### Шаг 1. Зафиксировать симптом и отделить сеть от DNS

```bash
ping -c2 8.8.8.8
ping -c2 google.com
```

- Оба не работают → не DNS, смотрите раздел 9 (сеть).
- IP работает, имя нет → **идём дальше, это DNS**.

### Шаг 2. Что у системы записано как DNS-сервер?

```bash
cat /etc/resolv.conf
ls -l /etc/resolv.conf
```

Возможные ситуации:

| Что увидели | Диагноз |
|---|---|
| Файл пустой / нет строк `nameserver` | Нет DNS-серверов → **Причина A** |
| `ls` показывает битый симлинк (`cannot access`, красный) | **Причина B** |
| `nameserver 127.0.0.53` | Используется systemd-resolved → шаг 3 |
| `nameserver <неведомый IP>` (не тот, что должен) | Неверный/мёртвый DNS → **Причина C** |
| Всё выглядит нормально | Шаг 3 и 4 |

### Шаг 3. Если `nameserver 127.0.0.53` — жив ли resolved?

```bash
systemctl status systemd-resolved
ss -lntup | grep :53
resolvectl status
```

- `inactive (dead)`/`failed` → **Причина D**.
- Порт 53 на 127.0.0.53 никто не слушает → то же.
- В `resolvectl status` у интерфейса пустой `DNS Servers` → resolved жив, но upstream-серверов не знает → **Причина E**.

### Шаг 4. Проверить `nsswitch.conf` и `/etc/hosts`

```bash
grep ^hosts /etc/nsswitch.conf
cat /etc/hosts
```

- Нормально: `hosts: files dns` (или `files mdns4_minimal [NOTFOUND=return] dns`, или `files resolve [!UNAVAIL=return] dns`).
- Нет `dns` (например `hosts: files`) → **Причина F**.
- В `/etc/hosts` есть строка с `google.com` на странный IP → **Причина G**.

### Шаг 5. Работает ли внешний DNS напрямую?

```bash
dig @8.8.8.8 google.com +short +time=3 +tries=1
dig @1.1.1.1 google.com +short +time=3 +tries=1
```

- Ответ есть → сам DNS-сервер и сеть до него в порядке; **проблема локальная** (шаги 2–4).
- `timed out` / `no servers could be reached` → порт 53 до внешнего мира недоступен → шаг 6.

### Шаг 6. Проверка firewall и доступности порта 53

```bash
sudo iptables -L -n -v | grep -E '53|DROP|REJECT'
sudo nft list ruleset | grep -E '53|drop|reject'
sudo ufw status verbose
nc -vz 8.8.8.8 53
dig +tcp @8.8.8.8 google.com +short
```

- Нашли `DROP/REJECT` на 53 → **Причина H**.
- UDP не проходит, а TCP проходит → фильтруется только UDP/53.
- Нигде не режется, но DNS молчит → DNS-сервер провайдера/роутера недоступен → смените upstream (временно 8.8.8.8 / 1.1.1.1).

### Шаг 7. Если всё равно непонятно — смотрим пакеты

```bash
sudo tcpdump -i any -nn port 53
# в другом терминале:
getent hosts google.com
```

- Пакетов нет → приложение не отправляет DNS-запрос → смотрим `nsswitch`, `resolv.conf`, `hosts`, resolved.
- Пакеты уходят без ответа → блокировка / неверный сервер.
- Ответ с ошибкой → читаем код (`NXDOMAIN`, `SERVFAIL`, `REFUSED`).

### Шаг 8. Проверка итога «как видят приложения»

```bash
getent hosts google.com
curl -sI https://google.com | head -1
ping -c2 google.com
```

---

## 4. Причины и решения (детально)

### Причина A. `/etc/resolv.conf` пустой или без `nameserver`

**Как проявляется:** `cat /etc/resolv.conf` — пусто/только комментарии. `dig` пишет `no servers could be reached`.

**Временное решение:**
```bash
echo -e "nameserver 8.8.8.8\nnameserver 1.1.1.1" | sudo tee /etc/resolv.conf
```

**Постоянное:** файл часто пересоздаётся сетевым менеджером, поэтому надо задавать DNS там, где он управляется (см. раздел 4.X «Как сделать постоянно»).

### Причина B. `/etc/resolv.conf` — битый симлинк

**Как проявляется:** `ls -l /etc/resolv.conf` показывает `-> ../run/systemd/resolve/stub-resolv.conf`, а цель не существует (resolved не запущен), либо симлинк ведёт в никуда.

**Решение (systemd-resolved):**
```bash
sudo systemctl enable --now systemd-resolved
sudo ln -sf /run/systemd/resolve/stub-resolv.conf /etc/resolv.conf
```

**Решение (без resolved, вручную):**
```bash
sudo rm /etc/resolv.conf
echo "nameserver 8.8.8.8" | sudo tee /etc/resolv.conf
```

### Причина C. В `resolv.conf` неверный или недоступный DNS-сервер

**Как проявляется:** в файле, например, `nameserver 10.0.0.1`, а такого сервера нет; `dig` — timeout; `dig @8.8.8.8` — работает.

**Решение:** заменить на рабочий (временно: `echo "nameserver 8.8.8.8" | sudo tee /etc/resolv.conf`), а затем разобраться, откуда взялся неверный (DHCP, NM, netplan, руками) и исправить источник.

### Причина D. systemd-resolved остановлен, а `resolv.conf` → `127.0.0.53`

**Как проявляется:** `nameserver 127.0.0.53`, `systemctl status systemd-resolved` → inactive/failed, `ss -lntup | grep 53` пусто.

**Решение:**
```bash
sudo systemctl enable --now systemd-resolved
sudo systemctl restart systemd-resolved
systemctl status systemd-resolved
resolvectl status
```
Если не стартует — `journalctl -u systemd-resolved -n 50 --no-pager`: часто порт 53 занят другим сервисом (dnsmasq, named) или сломан конфиг `/etc/systemd/resolved.conf`.

**Если порт занят другим:** `ss -lntup | grep :53` → найти процесс → остановить/перенастроить.

### Причина E. resolved работает, но нет upstream DNS

**Как проявляется:** `resolvectl status` — у интерфейса пусто в `DNS Servers`, `resolvectl query google.com` → `No appropriate name servers or networks for name found`.

**Решение (быстро, на интерфейс):**
```bash
sudo resolvectl dns eth0 8.8.8.8 1.1.1.1
sudo resolvectl flush-caches
```

**Решение (постоянно, глобально):** в `/etc/systemd/resolved.conf`:
```ini
[Resolve]
DNS=8.8.8.8 1.1.1.1
FallbackDNS=9.9.9.9
```
```bash
sudo systemctl restart systemd-resolved
```

### Причина F. В `nsswitch.conf` нет `dns`

**Как проявляется:** `grep ^hosts /etc/nsswitch.conf` → `hosts: files` (или опечатка, например `dsn`). При этом `dig google.com` **работает**, а `getent hosts google.com`, `ping google.com`, `curl` — нет. Это характерный признак: `dig` не использует NSS, а приложения используют.

**Решение:**
```bash
sudo sed -i 's/^hosts:.*/hosts:          files dns/' /etc/nsswitch.conf
grep ^hosts /etc/nsswitch.conf
```
(На Ubuntu штатно: `hosts: files mdns4_minimal [NOTFOUND=return] dns`; с resolved — `files resolve [!UNAVAIL=return] dns`.)

### Причина G. Неверная запись в `/etc/hosts`

**Как проявляется:** `getent hosts google.com` возвращает странный IP (например `127.0.0.1`), `dig` возвращает нормальный.

**Решение:** открыть `/etc/hosts`, удалить/закомментировать лишнюю запись:
```bash
sudo nano /etc/hosts
```

### Причина H. Firewall блокирует порт 53

**Как проявляется:** `dig @8.8.8.8` — timeout; `iptables -L` показывает `DROP`/`REJECT` на `dpt:53`, либо `OUTPUT` с политикой `DROP`.

**Решение (iptables):**
```bash
sudo iptables -L OUTPUT -n --line-numbers          # найти номер правила
sudo iptables -D OUTPUT <номер>                    # удалить блокирующее правило
# или добавить разрешающее выше блокирующего:
sudo iptables -I OUTPUT 1 -p udp --dport 53 -j ACCEPT
sudo iptables -I OUTPUT 1 -p tcp --dport 53 -j ACCEPT
sudo iptables -I INPUT 1 -p udp --sport 53 -j ACCEPT
sudo iptables -I INPUT 1 -p tcp --sport 53 -j ACCEPT
```

**Решение (nftables):** `sudo nft list ruleset -a` → найти `handle` правила → `sudo nft delete rule inet filter output handle <N>`.

**Решение (ufw):** `sudo ufw allow out 53` (и `sudo ufw status numbered` → `sudo ufw delete <N>` для deny-правила).

### Причина I. Файл `resolv.conf` защищён (`chattr +i`) или перезаписывается

**Как проявляется:** правки не сохраняются / `Operation not permitted`.

```bash
lsattr /etc/resolv.conf
sudo chattr -i /etc/resolv.conf
```

Если файл постоянно перезаписывается — им управляет NM/DHCP/resolved. Править надо там (см. ниже).

### Причина J. DHCP/NetworkManager выдаёт неверные DNS

**Как проявляется:** после перезагрузки/переподключения `resolv.conf` снова неправильный; `nmcli device show` показывает странный `IP4.DNS`.

**Решение (NM):**
```bash
nmcli con mod "<имя соединения>" ipv4.dns "8.8.8.8 1.1.1.1"
nmcli con mod "<имя соединения>" ipv4.ignore-auto-dns yes
nmcli con up "<имя соединения>"
```

**Решение (netplan, Ubuntu):** `/etc/netplan/01-netcfg.yaml`
```yaml
network:
  version: 2
  ethernets:
    eth0:
      dhcp4: true
      nameservers:
        addresses: [8.8.8.8, 1.1.1.1]
```
```bash
sudo netplan try      # применить с откатом при потере связи
sudo netplan apply
```

### Причина K. Мёртвый первый nameserver → «тормозит» вместо «не работает»

Первый `nameserver` не отвечает, второй живой → каждый запрос ждёт таймаут (5 сек). Убрать/переставить мёртвый, либо `options timeout:1 attempts:2` в `resolv.conf`.

### Причина L. DNSSEC / EDNS / MTU (редкие)

- `SERVFAIL` только для части доменов → `dig +dnssec`, проверить `DNSSEC=` в resolved (временно `DNSSEC=no`).
- Большие ответы не проходят по UDP → `dig +tcp @8.8.8.8 google.com` проходит, а по UDP нет → проблема MTU/фрагментации/firewall.

### Причина M. Проблема IPv6 / AAAA

Если есть AAAA, а IPv6 не работает — `curl` может подвисать. Проверка: `curl -4 -sI https://google.com` vs `curl -6 ...`; `dig AAAA google.com`.

---

## 5. Как сделать исправление постоянным и сбросить кэш

**Правило:** меняйте DNS **в источнике**, а не в итоговом `resolv.conf`.

| Кто управляет DNS | Где править |
|---|---|
| systemd-resolved | `/etc/systemd/resolved.conf` (`DNS=`, `FallbackDNS=`) или `resolvectl dns` |
| NetworkManager | `nmcli con mod ... ipv4.dns` |
| netplan | `/etc/netplan/*.yaml` → `nameservers:` |
| ifupdown (Debian) | `/etc/network/interfaces` → `dns-nameservers 8.8.8.8` |
| dhclient | `/etc/dhcp/dhclient.conf` → `prepend domain-name-servers 8.8.8.8;` |
| Вручную, без менеджеров | `/etc/resolv.conf` (+ `chattr +i`, если что-то перезаписывает) |

**Сброс кэша после исправления:**

```bash
sudo resolvectl flush-caches                  # systemd-resolved
sudo systemctl restart systemd-resolved       # если нужно перезапустить
sudo systemctl restart NetworkManager         # NM
sudo nscd -i hosts                            # nscd
sudo systemctl restart dnsmasq                # dnsmasq
```
Плюс перезапустить браузер/приложение (у них свой кэш).

---

## 6. Проверка результата (Definition of Done)

Все пункты должны проходить:

```bash
cat /etc/resolv.conf                              # есть рабочий nameserver
grep ^hosts /etc/nsswitch.conf                    # есть dns
dig google.com +short                             # возвращает IP
getent hosts google.com                           # возвращает IP (как у приложений)
ping -c2 google.com                               # идут ответы
curl -sI https://google.com | head -1             # HTTP/2 200 или 301
resolvectl query google.com                       # (если resolved) успех
```

Проверка после **перезагрузки** (чтобы убедиться, что фикс постоянный):
```bash
sudo reboot
# после загрузки повторить проверки выше
```

---

## 7. Быстрая таблица «симптом → причина → команда проверки»

| Что видим | Вероятная причина | Чем проверить |
|---|---|---|
| `dig google.com` OK, `ping google.com` FAIL | Нет `dns` в nsswitch.conf / запись в hosts | `grep ^hosts /etc/nsswitch.conf`, `cat /etc/hosts` |
| `dig` → `no servers could be reached` | Пустой/битый resolv.conf, мёртвый DNS, firewall | `cat /etc/resolv.conf`, `dig @8.8.8.8` |
| `dig @8.8.8.8` OK, `dig` FAIL | Локальный резолвер/resolv.conf сломан | `resolvectl status`, `ls -l /etc/resolv.conf` |
| `dig @8.8.8.8` timeout | Порт 53 заблокирован | `iptables -L -n`, `nc -vz 8.8.8.8 53`, `tcpdump` |
| `nameserver 127.0.0.53` + FAIL | resolved не запущен | `systemctl status systemd-resolved` |
| `ls -l resolv.conf` — красный симлинк | Битый симлинк | `readlink -f /etc/resolv.conf` |
| Правки в resolv.conf пропадают | Перезаписывает NM/DHCP/resolved | `lsattr`, `nmcli`, `netplan get` |
| `SERVFAIL` | Проблема upstream / DNSSEC | `dig +dnssec`, смена upstream |
| `NXDOMAIN` для существующего домена | Резолвер фильтрует/врёт, hosts, search-домен | `dig @8.8.8.8`, `cat /etc/hosts` |
| Работает по IP, по имени «долго» | Первый nameserver мёртв | `cat /etc/resolv.conf`, `dig +time=2` |
| Контейнер не резолвит, хост резолвит | DNS в Docker/k8s | `docker run --rm busybox nslookup`, `daemon.json`, CoreDNS |

---

## 8. Мини-шпаргалка (запомнить)

1. **IP пингуется, имя нет → DNS.** Сеть не трогаем.
2. **Цепочка:** приложение → `nsswitch.conf` → `/etc/hosts` → `resolv.conf` → (resolved) → upstream DNS → порт 53.
3. **`dig` ≠ `getent`**: `dig` ходит в DNS напрямую, `getent` — как приложения. Расхождение = проблема NSS/hosts/resolv.conf.
4. **`dig @8.8.8.8`** — главный разделитель: «локальная настройка» против «сеть/порт 53».
5. **`127.0.0.53` в resolv.conf** → смотреть `systemd-resolved`.
6. **Временный фикс:** `echo "nameserver 8.8.8.8" | sudo tee /etc/resolv.conf`. **Постоянный:** править там, где DNS генерируется.
7. **Не уверен — `tcpdump -i any -nn port 53`.**
8. **После фикса:** сбросить кэш, проверить `getent`, `curl`, перезагрузиться.

---

## 9. Если на самом деле проблема не в DNS (проверка сети по слоям)

Если не работает и `ping 8.8.8.8`:

```bash
ip link                    # L1/L2: интерфейс UP? (state UP, LOWER_UP)
ip a                       # L3: есть ли IP-адрес
ip r                       # есть ли default via <шлюз>
ping -c2 <шлюз>            # доступен ли шлюз
ping -c2 8.8.8.8           # выход в интернет
traceroute -n 8.8.8.8      # где обрывается путь
```

| Проблема | Признак | Решение |
|---|---|---|
| Интерфейс DOWN | `state DOWN` | `sudo ip link set eth0 up` |
| Нет IP | в `ip a` нет `inet` | `sudo dhclient eth0` / `nmcli con up` / задать статикой |
| Нет default route | в `ip r` нет `default` | `sudo ip route add default via <шлюз>` |
| Шлюз недоступен | `ping <шлюз>` FAIL | кабель/Wi-Fi/VLAN/ARP: `ip neigh` |

---

## 10. Шаблон для записи решения задачи (для отчёта)

```
### Диагностика
- ping 8.8.8.8: OK; ping google.com: FAIL → проблема DNS
- cat /etc/resolv.conf → <что увидел>
- grep ^hosts /etc/nsswitch.conf → <что увидел>
- dig @8.8.8.8 google.com → <результат>
- systemctl status systemd-resolved → <результат>
- iptables -L -n → <есть ли блок на 53>

### Причина
<одна фраза: что именно было сломано и почему это даёт такой симптом>

### Исправление
<команды, которые выполнил>

### Проверка
- dig google.com +short → <IP>
- getent hosts google.com → <IP>
- ping google.com → OK
- curl -sI https://google.com → HTTP/2 200
- проверка после reboot → OK
```
