# Шаг 1. Root на Станции Мини 3: retail CA и маркеры из factory

Способ для **[Станции Мини 3 (bergamot)](../devices/station-mini3.md)** после обновления
21 октября 2026 года, когда [DNS-метод](root.md) перестал работать. Колонка загружается в
factory mode, в retail-разделе правится только CA-бандл, а в `/data` кладутся маркеры сетевого
ADB и конфиг Wi-Fi. После normal-загрузки ADB с root поднимается сам — без приложения и без
роутера с подменой DNS.

Основа — [гайд для Лайт 2](retail-ca.md): порядок тот же, ниже — с поправками под Мини 3.

После этого шага переходите к [шагу 2](ssh.md): SSH и отключение обновлений.

## Чем Мини 3 отличается от Лайт 2

| | Лайт 2 (plum) | Мини 3 (bergamot) |
|---|---|---|
| factory-образ | отдельный раздел `factory` | отдельного раздела нет: образ лежит в `recovery` (mtd6, ramdisk 27,7 МБ), загрузка с `rootfstype=ramfs` |
| system | mtd3, UBI-том `rootfs` | то же: mtd3, UBI-том `rootfs` |
| UBI в factory | нужен `ubiattach -m 3` | **не нужен**: в cmdline есть `ubi.mtd=system`, ubi0 уже поднят |
| CA | `/system/vendor/quasar/certs/ca-certificates.crt` | тот же файл, а `/system/vendor/quasar/ca-certificates.crt` — **симлинк** на него |
| factory-сборка | — | `0.6.1.4.…factory-6` от 11.11.2024, в ней ещё есть корень AAA |
| normal-загрузка | `upgrade_step=1`, `boot_to_recovery=0` | то же; в factory `upgrade_step=2` |
| OTA | `S01swupdate` + `swupdate` | в `.50` нет ни `S01swupdate`, ни `swupdate`: применяет `device_ota_update.sh` → `apply_packed_ota`, подпись проверяется по `ota_script.pub` |
| Wi-Fi | — | данные сети только в `/data/wpa_supplicant.conf`; без файла после перезагрузки колонка никуда не подключается |

В factory корневая ФС живёт в памяти (`ramfs`) — правки в ней не сохраняются. В retail `/` —
ubifs на mtd3, смонтирован `ro`, но dm-verity нет: `mount -o remount,rw /` и `sync` пишут на
флеш, и правки переживают перезагрузку.

## Что понадобится

- компьютер с `adb` в одной сети с колонкой;
- стенд — локальный HTTPS-сервер, который отвечает на `get_sync_info` конфигом с `adbd`
  (`remoteActivation`, `network`), а на `check_updates` — `{"hasUpdate":false}`. Его сертификат
  должен строиться до корня `AAA Certificate Services` (утёкшая цепочка eMudhra:
  лист ← `EM OV TLS CA - G3C` ← AAA). Так устроен, например, [eQuasar](retail-ca.md#1-equasar);
- DNS: подмена на роутере или хотспот с компьютера (общий доступ к интернету в Windows отдаёт
  колонке DNS = IP компьютера);
- корень AAA:
  [`contrib/packages/aaa-certificate-services.pem`](https://github.com/Marker284/yandex-station-extended/raw/main/contrib/packages/aaa-certificate-services.pem).

## 0. Проверка: жив ли factory-образ

Сброс кнопкой (зажать кнопку отключения микрофона и подать питание, держать 10–15 с) грузит
factory-образ из `recovery`. После получения shell (шаг 1):

```sh
cat /proc/cmdline                          # rootfstype=ramfs, без root=
cat /system/vendor/quasar/version_full
```

Ожидается `0.6.1.4.…factory-6`. Если видно `0.369.1.50…` — factory-образ обновлён вместе с
retail, войти этим способом нельзя, дальше не идите.

## 1. Стенд и вход в factory mode

1. Поднимите стенд и DNS (роутер или хотспот компьютера).
2. Обесточьте колонку, зажмите кнопку отключения микрофона, подайте питание и держите
   10–15 с, пока подсветка не замигает.
3. В приложении «Дом с Алисой» добавьте колонку и дайте ей Wi-Fi с нужным DNS. Приложение
   может сообщить, что настроить не удалось, — это нормально.
4. Убедитесь, что в логе стенда есть запросы `/get_sync_info` и `/check_updates`, и
   подключитесь по ADB:

```sh
adb connect <IP_колонки>:5555
adb shell id
```

Ожидается `uid=0(root)`.

!!! warning "Сброс стирает /data"
    Вместе с ним исчезают старые маркеры и `/data/quasar/data/user_config.dat`. Всё нужное
    создаётся заново на шагах 4–5.

## 2. Разметка и монтирование retail

```sh
cat /proc/mtd              # system = mtd3, recovery = mtd6
ubinfo -a                  # ubi0, том rootfs
mkdir -p /mnt/retail
mount -t ubifs -o rw ubi0:rootfs /mnt/retail
df -h /mnt/retail
```

`ubiattach` не нужен — ubi0 поднимает ядро (`ubi.mtd=system` в cmdline). Если тома нет, тогда
`ubiattach /dev/ubi_ctrl -m 3` и номер UBI из `ubinfo -a`.

Проверьте, что смонтирован именно retail:

```sh
cat /mnt/retail/system/vendor/quasar/version_full; echo
```

## 3. Замена CA

В `.50` файл в `quasar/` — симлинк, поэтому сохраняйте и правьте цель, а не ссылку:

```sh
Q=/mnt/retail/system/vendor/quasar
D=$Q/certs
ls -l $Q/ca-certificates.crt $D/ca-certificates.crt
grep -c 'BEGIN CERTIFICATE' $D/ca-certificates.crt
grep -c 'MIIEMjCCAxqgAwIBAgIBATANBgkqhkiG9w0BAQUFADB7MQswCQYDVQQGEwJHQjEb' $D/ca-certificates.crt
cp -a $D/ca-certificates.crt $D/ca-certificates.crt.orig
mkdir -p /bkupgrade/data/local/tmp
cp $D/ca-certificates.crt /bkupgrade/data/local/tmp/ca.cur
```

В `.50` ожидается 122 сертификата, а второй `grep` (первая строка сертификата AAA) — `0`:
корень из бандла убран.

Заберите файл на компьютер, допишите в конец корень AAA и верните. Команды запускайте в
каталоге, где лежит `aaa-certificate-services.pem`:

=== "Windows (PowerShell)"

    ```powershell
    adb pull /bkupgrade/data/local/tmp/ca.cur retail-ca.pem
    $p='retail-ca.pem'
    $ca=[IO.File]::ReadAllText($p).TrimEnd()
    [IO.File]::WriteAllText($p, $ca + "`n" + (Get-Content aaa-certificate-services.pem -Raw).TrimEnd() + "`n")
    adb push retail-ca.pem /bkupgrade/data/local/tmp/ca.new
    ```

=== "Linux / macOS"

    ```sh
    adb pull /bkupgrade/data/local/tmp/ca.cur ca.cur
    printf '%s\n%s\n' "$(cat ca.cur)" "$(cat aaa-certificate-services.pem)" > retail-ca.pem
    adb push retail-ca.pem /bkupgrade/data/local/tmp/ca.new
    ```

Снова на колонке (в `adb shell`, переменные `Q` и `D` — как выше):

```sh
cp /bkupgrade/data/local/tmp/ca.new $D/ca-certificates.crt
chmod 0644 $D/ca-certificates.crt
chown 0:0 $D/ca-certificates.crt
sync
grep -c 'BEGIN CERTIFICATE' $D/ca-certificates.crt
sha256sum $D/ca-certificates.crt
```

Ожидается 123 сертификата и хеш (для сборки `0.369.1.50…`; на другой сборке исходный бандл
другой, и хеш будет отличаться):

```text
737b5c4acabcadca46842a90cb7ede2acc31bb8ba4664167864d1697d73e8bf4
```

Если хеш другой — не перезагружайте колонку: восстановите `.orig` (см.
[ниже](#restore)) или повторите склейку.

!!! note "Не проверяйте грепом по имени"
    В PEM имя субъекта закодировано в base64, поэтому `grep 'AAA Certificate Services'` даёт
    ноль и на пропатченном файле. Считайте сертификаты, сверяйте хеш, а наличие корня ищите
    по первой строке его base64, как выше.

??? info "Сертификат AAA Certificate Services"
    Тот же файл, что в `contrib/packages/aaa-certificate-services.pem` (и последний сертификат
    в бандле для Лайт 2). SHA-256 отпечаток —
    `D7:A7:A0:FB:5D:7E:27:31:D7:71:E9:48:4E:BC:DE:F7:1D:5F:0C:3E:0A:29:48:78:2B:C8:3E:E0:EA:69:9E:F4`.

    ```text
    -----BEGIN CERTIFICATE-----
    MIIEMjCCAxqgAwIBAgIBATANBgkqhkiG9w0BAQUFADB7MQswCQYDVQQGEwJHQjEb
    MBkGA1UECAwSR3JlYXRlciBNYW5jaGVzdGVyMRAwDgYDVQQHDAdTYWxmb3JkMRow
    GAYDVQQKDBFDb21vZG8gQ0EgTGltaXRlZDEhMB8GA1UEAwwYQUFBIENlcnRpZmlj
    YXRlIFNlcnZpY2VzMB4XDTA0MDEwMTAwMDAwMFoXDTI4MTIzMTIzNTk1OVowezEL
    MAkGA1UEBhMCR0IxGzAZBgNVBAgMEkdyZWF0ZXIgTWFuY2hlc3RlcjEQMA4GA1UE
    BwwHU2FsZm9yZDEaMBgGA1UECgwRQ29tb2RvIENBIExpbWl0ZWQxITAfBgNVBAMM
    GEFBQSBDZXJ0aWZpY2F0ZSBTZXJ2aWNlczCCASIwDQYJKoZIhvcNAQEBBQADggEP
    ADCCAQoCggEBAL5AnfRu4ep2hxxNRUSOvkbIgwadwSr+GB+O5AL686tdUIoWMQua
    BtDFcCLNSS1UY8y2bmhGC1Pqy0wkwLxyTurxFa70VJoSCsN6sjNg4tqJVfMiWPPe
    3M/vg4aijJRPn2jymJBGhCfHdr/jzDUsi14HZGWCwEiwqJH5YZ92IFCokcdmtet4
    YgNW8IoaE+oxox6gmf049vYnMlhvB/VruPsUK6+3qszWY19zjNoFmag4qMsXeDZR
    rOme9Hg6jc8P2ULimAyrL58OAd7vn5lJ8S3frHRNG5i1R8XlKdH5kBjHYpy+g8cm
    ez6KJcfA3Z3mNWgQIJ2P2N7Sw4ScDV7oL8kCAwEAAaOBwDCBvTAdBgNVHQ4EFgQU
    oBEKIz6W8Qfs4q8p74Klf9AwpLQwDgYDVR0PAQH/BAQDAgEGMA8GA1UdEwEB/wQF
    MAMBAf8wewYDVR0fBHQwcjA4oDagNIYyaHR0cDovL2NybC5jb21vZG9jYS5jb20v
    QUFBQ2VydGlmaWNhdGVTZXJ2aWNlcy5jcmwwNqA0oDKGMGh0dHA6Ly9jcmwuY29t
    b2RvLm5ldC9BQUFDZXJ0aWZpY2F0ZVNlcnZpY2VzLmNybDANBgkqhkiG9w0BAQUF
    AAOCAQEACFb8AvCb6P+k+tZ7xkSAzk/ExfYAWMymtrwUSWgEdujm7l3sAg9g1o1Q
    GE8mTgHj5rCl7r+8dFRBv/38ErjHT1r0iWAFf2C3BUrz9vHCv8S5dIa2LX1rzNLz
    Rt0vxuBqw8M0Ayx9lt1awg6nCpnBBYurDC/zXDrPbDdVCYfeU0BsWO/8tqtlbgT2
    G9w84FoVxp7Z8VlIMCFlA2zs6SFz7JsDoeA3raAVGI/6ugLOpyypEBMs1OUIJqsi
    l2D4kF501KKaU73yqWjgom7C12yxow+ev+to51byrvLjKzg6CYG1a4XXvi3tPxq3
    smPi9WIsgtRqAEFQ8TmDn5XpNpaYbg==
    -----END CERTIFICATE-----
    ```

## 4. Маркеры ADB в /data

`/data` — ссылка на `/bkupgrade/data`, писать можно прямо туда:

```sh
mkdir -p /bkupgrade/data/quasar
touch /bkupgrade/data/quasar/activate_adb_quasmodrom
touch /bkupgrade/data/quasar/activate_network_adb
ls -l /bkupgrade/data/quasar/activate_*
```

Проверьте, что логика срабатывает:

```sh
sh /system/vendor/quasar/activate_adb.sh check
cat /data/quasar/quasar_adb.log
```

Должно быть `Activation file exists. Activate adb`.

!!! warning "Пути важны"
    В `adb_options.inc` маркеры — `/data/quasar/activate_adb_*` (через слэш). `onboot.sh` при
    каждой загрузке чистит `/data/quasar_activate_adb_*` (через подчёркивание, в корне `/data`) —
    это старая схема, такие файлы не помогают. Кладите только в `/data/quasar/`.

## 5. Wi-Fi в /data

Без этого после перезагрузки колонка никуда не подключится: данные сети приложение записывает
только по завершённой настройке, а на стенде она не завершается.

```sh
cat > /bkupgrade/data/wpa_supplicant.conf <<'EOF'
ctrl_interface=/var/run/wpa_supplicant
update_config=0

network={
    ssid="SSID"
    psk="PASSWORD"
    key_mgmt=WPA-PSK
    priority=1
}
EOF
chmod 600 /bkupgrade/data/wpa_supplicant.conf
```

`update_config=0` обязателен: с `1` wpa_supplicant сам перезапишет файл своим состоянием и
выкинет сети, добавленные правкой файла. Две сети — два блока `network={}`, к какой
подключаться, решает `priority`.

## 6. Возврат в normal

```sh
fw_printenv upgrade_step boot_to_recovery
sync
mount -o remount,ro /mnt/retail
umount /mnt/retail
```

Если `upgrade_step=2` — выставьте normal-загрузку и перезагрузитесь:

```sh
fw_setenv upgrade_step 1
fw_setenv boot_to_recovery 0
fw_printenv upgrade_step boot_to_recovery
reboot
```

## 7. Проверка normal-загрузки

IP колонки — в списке клиентов роутера.

```sh
adb connect <IP_колонки>:5555
adb shell cat /proc/cmdline                       # root=ubi0:rootfs rootfstype=ubifs
adb shell cat /system/vendor/quasar/version_full
adb shell cat /data/quasar/quasar_adb.log
```

ADB поднимается сам: маркеры → `activate_adb.sh check` → `yandex-debugctl adb-net`.

## 8. Закрепление: обновления и SSH

Дальше — обычный **[шаг 2: SSH и отключение обновлений](ssh.md)**, сразу, пока есть ADB.
Dropbear из `contrib/bin` (armhf) на Мини 3 подходит.

!!! tip "Если файлы копировались через Windows"
    Busybox спотыкается о переводы строк CRLF (`set: illegal option`). Перед запуском
    уберите их на колонке:
    `tr -d '\r' < /data/opt/yandex-noupdate.sh > /data/opt/noupdate.sh`.

## 9. Страховка на случай перепрошивки разделов

OTA переписывает mtd0–mtd4 целиком, поэтому правки в `system` (CA, `S99zdropbear`) при
перепрошивке пропадут, а `/data` — нет. Держите копии в `/data`:

```sh
mkdir -p /data/opt/ca
cp /system/vendor/quasar/certs/ca-certificates.crt /data/opt/ca/ca-certificates.crt
cp /etc/init.d/S99zdropbear /data/opt/S99zdropbear
```

и скрипт `/data/opt/restore-system.sh`, который вернёт их одной командой:

```sh
#!/bin/sh
mount -o remount,rw / || exit 1
cp /data/opt/ca/ca-certificates.crt /system/vendor/quasar/certs/ca-certificates.crt
chmod 0644 /system/vendor/quasar/certs/ca-certificates.crt
cp /data/opt/S99zdropbear /etc/init.d/S99zdropbear
chmod +x /etc/init.d/S99zdropbear
sync
mount -o remount,ro /
sh /data/opt/yandex-noupdate.sh
/etc/init.d/S99zdropbear start
pidof dropbear
```

## Восстановление исходного CA { #restore }

Из factory mode (шаги 1–2):

```sh
Q=/mnt/retail/system/vendor/quasar
mount -t ubifs -o rw ubi0:rootfs /mnt/retail
cp -a $Q/certs/ca-certificates.crt.orig $Q/certs/ca-certificates.crt
sync
mount -o remount,ro /mnt/retail
umount /mnt/retail
```

## Если что-то не получилось

??? failure "`grep 'AAA Certificate Services'` даёт 0"
    Так и должно быть: в PEM имя закодировано. Считайте сертификаты и сверяйте хеш.

??? failure "`ubiattach` пишет, что устройство уже подключено"
    В factory на Мини 3 ubi0 уже поднят через `ubi.mtd=system`. Просто смонтируйте его том.

??? failure "После перезагрузки колонка не подключается ни к одной сети"
    Нет `/data/wpa_supplicant.conf` (или в нём `update_config=1`, и файл перезаписан). Пропишите
    конфиг, `chmod 600`, перезагрузите.

??? failure "Добавили сеть, а она исчезла"
    `update_config=1` перезаписал файл. Ставьте `0` и добавляйте сети правкой файла, а не через
    `wpa_cli` на работающей системе.

??? failure "Точка доступа вещает WPA3, колонка не подключается"
    Смотрите не свойства сети в Windows, а `wpa_cli -i wlan0 scan_results`: если во флагах
    `[WPA2-PSK-CCMP]`, ставьте `key_mgmt=WPA-PSK`. SAE в wpa_supplicant 2.9 есть, но требует
    поддержки 802.11w драйвером — на вендорных драйверах Amlogic её часто нет.

??? failure "`/data/local/tmp` отсутствует"
    В factory-образе такого пути нет. Используйте `/bkupgrade/data/local/tmp`.

??? failure "Скрипт падает с `set: illegal option`"
    Переводы строк CRLF: `tr -d '\r' < in > out`.

??? failure "После сброса кнопками всё пропало"
    Сброс чистит `/data`: маркеры, Wi-Fi, файлы SSH. `system` при этом остаётся вместе с
    пропатченным CA, поэтому стенд снова даст ADB в factory, а `/data/opt` восстанавливается
    шагами 4–5 и [шагом 2](ssh.md).

## Что в итоге

- ADB с root на каждой загрузке `.50`: маркеры в `/data/quasar/` плюс `adbd` в
  `/data/quasar/data/user_config.dat` (появляется после ответа стенда на `get_sync_info`).
- SSH на порту 2222 стартует сам из `/etc/init.d/S99zdropbear`.
- Обновления закрыты: подменённый `ota_script.pub`, заглушённый `device_ota_update.sh`, убранный
  `updatesd`.
- Если OTA всё же прошьётся: `/data` уцелеет, ADB вернётся, а `restore-system.sh` вернёт CA и
  SSH одной командой.
