# Станция Мини 3 Про

Розничное имя — **Яндекс Станция Мини 3 Про**. Не путать с
[Мини 3 (bergamot)](station-mini3.md): там рутованная колонка сохраняет правки во всех
разделах, а у Мини 3 Про — **только в `/data`**.

!!! info "Страница в работе"
    Железо, кодовое имя и способ получить root пока не описаны — ниже то, что известно
    о закреплении доступа на прошивке `.50`. Есть данные — [дополните](../contributing.md).

## Что переживает перезагрузку и OTA { #persistence }

- После перезагрузки сохраняются изменения **только в `/data`**: правки корневой ФС
  (`/etc/init.d`, `/system/vendor/quasar` и т. п.) пропадают.
- OTA полностью переписывает разделы **mtd0–mtd4 и mtd9**, но не трогает **mtd10** — это
  `/data`. В `/data` обновление удаляет только `/data/overlay` и `/data/quasar_activate_*`.
- `chattr +i` защищает файл от правки и удаления, но **не** от перезаписи всего раздела: файлы,
  которые должны пережить обновление, держите в `/data`.

Отсюда правило: всё своё — в `/data`, а то, что требует автозапуска из корневой ФС (например,
SSH из `init.d`), придётся запускать заново после каждого включения.

## Постоянный ADB { #adb }

Root ADB, настроенный так, пережил обновление на `.50` и поднимается сам на каждой загрузке.
Всё делается заранее, с root-доступом (например, на factory-прошивке).

1. Добавьте в `/data/quasar/data/user_config.dat` (это JSON) блок `system_config.adbd`.
   Если файла нет, создайте его с таким содержимым; если есть — сохраните копию и
   впишите блок в существующий JSON, не затирая остальное:

    ```json
    {
      "system_config": {
        "adbd": {
          "remoteActivation": true,
          "network": true
        }
      }
    }
    ```

2. Создайте пустые маркеры и защитите их от удаления:

    ```sh
    mkdir -p /data/quasar
    touch /data/quasar/activate_adb_quasmodrom /data/quasar/activate_network_adb
    chattr +i /data/quasar/activate_adb_quasmodrom /data/quasar/activate_network_adb
    ```

Как это срабатывает на загрузке:

- `onboot.sh` вызывает `activate_adb.sh check`, тот видит маркеры в `/data/quasar/` и
  запускает ADB;
- `syncd` читает локальный `user_config.dat`, передаёт `system_config.adbd` в `AdbService`, и
  тот подтверждает активацию сетевого ADB.

!!! warning "Путь маркеров"
    Только `/data/quasar/activate_*` (через слэш). Файлы `/data/quasar_activate_*` (через
    подчёркивание) — старая схема: их удаляет и `onboot.sh`, и OTA.

## SSH

Автозапуск из корневой ФС здесь не сохраняется, поэтому Dropbear, ключ и скрипт запуска
лежат в `/data` (например, `/data/alice-ssh`), а запускать его нужно после каждого включения —
вручную по ADB:

```sh
adb connect <IP_колонки>:5555
adb shell sh /data/alice-ssh/start-ssh.sh
```

??? example "Пример `start-ssh.sh` (по образцу [шага 2](../start/ssh.md#dropbear))"
    ```sh
    #!/bin/sh
    # Dropbear on :2222 from /data (rootfs changes do not survive a reboot here).
    D=/data/alice-ssh
    pidof dropbear >/dev/null 2>&1 && exit 0
    [ -s "$D/hk_ed25519" ] || "$D/dropbearkey" -t ed25519 -f "$D/hk_ed25519" >> "$D/dropbear.log" 2>&1
    # -B: root has an empty password
    "$D/dropbear" -r "$D/hk_ed25519" -p 2222 -B 2>>"$D/dropbear.log"
    ```

Чтобы не делать это руками, SSH может поднимать компьютер в домашней сети, который включён
постоянно (мини-ПК, NAS, роутер с `adb`): периодически проверять Dropbear по ADB и запускать
его, если он не работает. Пример цикла — оберните его в службу systemd или cron:

```sh
#!/bin/sh
# Keep SSH up on the speaker: check every minute over ADB, start dropbear if it is not running.
IP=<IP_колонки>
while :; do
  adb connect "$IP:5555" >/dev/null 2>&1
  adb -s "$IP:5555" shell 'pidof dropbear >/dev/null || sh /data/alice-ssh/start-ssh.sh' >/dev/null 2>&1
  sleep 60
done
```

Пакеты (`yse`, Entware) ставятся в `/data` и переживают и перезагрузку, и OTA.

## Что ещё проверить

- Кодовое имя, SoC, разметка флеша (какие разделы — mtd0–mtd4, mtd9, mtd10).
- Способ получить root на текущих прошивках.
- Почему не сохраняются правки корневой ФС: overlay, dm-verity или что-то ещё — и можно ли
  перенести автозапуск в `/data`.
