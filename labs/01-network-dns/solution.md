# Решение: 01-network-dns

### В чём была проблема

В файле `/etc/resolv.conf` был прописан нерабочий DNS-сервер `127.0.0.1`.  
Также мог быть остановлен `systemd-resolved`.

### Как чинить

1. Посмотреть текущие настройки:
```bash
cat /etc/resolv.conf
```

2. Вернуть нормальные DNS:
```Bash
echo -e "nameserver 8.8.8.8\nnameserver 1.1.1.1" | sudo tee /etc/resolv.conf
```
3. Если используешь systemd-resolved — лучше сделать правильно:
```Bash
sudo systemctl enable --now systemd-resolved
sudo ln -sf /run/systemd/resolve/stub-resolv.conf /etc/resolv.conf
```
4. Проверить:
```Bash
ping -c 2 google.com
getent hosts google.com
```