Уставновка telemt и telemt-panel на entware keenetic (только aarch64)
```bash
opkg update
opkg install curl
opkg install libnghttp2
```
```bash
curl -L https://raw.githubusercontent.com/augin/telemt_script/refs/heads/main/installer_telemt_v2.sh -o /opt/tmp/install_telemt.sh
sh /opt/tmp/install_telemt.sh
```
```bash
curl -L https://raw.githubusercontent.com/augin/telemt_script/refs/heads/main/install_telemt-panel.sh -o /opt/tmp/install_telemt-panel.sh
sh /opt/tmp/install_telemt-panel.sh
```
эмуляция systemD для работы перезапуска через панель и логов
```bash
curl -L https://raw.githubusercontent.com/anch665/keendev/refs/heads/main/systemctl.sh -o /opt/usr/bin/systemctl
chmod +x /opt/usr/bin/systemctl
curl -L https://raw.githubusercontent.com/anch665/keendev/refs/heads/main/journalctl.sh -o /opt/usr/bin/journalctl
chmod +x /opt/usr/bin/journalctl
/opt/etc/init.d/S99telemt-panel restart
```

удаление
```
# Остановить службы Entware
/opt/etc/init.d/S99telemt-panel stop 2>/dev/null || true
/opt/etc/init.d/S99telemt stop 2>/dev/null || true

# Удалить init-скрипты
rm -f /opt/etc/init.d/S99telemt
rm -f /opt/etc/init.d/S99telemt-panel

# Удалить бинарники
rm -f /opt/usr/bin/telemt
rm -f /opt/sbin/telemt-panel

# Удалить конфигурацию
rm -rf /opt/etc/telemt
rm -rf /opt/etc/telemt-panel

# Очистить временные каталоги, которые создавали установщики
rm -rf /opt/tmp/telemt_dl
rm -rf /opt/tmp/telemt-panel-install

# Удалить лог (если был создан)
rm -f /tmp/log/telemt.log

# Удалить кэш beobachten (если был создан)
rm -f /tmp/cache/beobachten.txt
```
