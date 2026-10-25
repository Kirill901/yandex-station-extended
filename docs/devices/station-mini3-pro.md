# Станция Мини 3 Про (pickle)

Розничное имя — **Яндекс Станция Мини 3 Про**; кодовое имя — **Pickle** (device-tree
`Yandex Pickle EVT`, `yandex,pickle-evt` / `yandex,pickle`, **`amlogic, a4`**). Не путать с
[Мини 3 (bergamot)](station-mini3.md): там рутованная колонка сохраняет правки во всех
разделах, а у Мини 3 Про — **только в `/data`**.

Новый для вики SoC — **Amlogic A4**; программная основа та же, что у
[Миди](station-midi.md): ядро 5.4, Buildroot 2023.11.1, quasar/`maind`. Хранилище при этом
не eMMC, а NAND с UBI, как у AXG-моделей.

!!! info "Страница в работе"
    Способ получить root на текущих прошивках пока не описан — ниже железо и то, что
    известно о закреплении доступа на прошивке `.50`. Есть данные —
    [дополните](../contributing.md).

## Платформа в двух словах

| | |
|---|---|
| SoC | **Amlogic A4** (`amlogic, a4`) |
| CPU | 4× **Cortex-A53** (`0xd03`), до **2.016 ГГц** (100 МГц … 2016 МГц) |
| ОЗУ | **~473 МБ** (MemTotal 484784 kB) |
| Ядро | Linux **5.4.242** aarch64 (сборка 30.05.2025) |
| Userspace | Buildroot **2023.11.1** |
| Флеш | **NAND Toshiba 512 МБ SLC** (TC58NVG2S0HTA00), страница 4096, блок 256 КБ, UBI поверх MTD |
| Усилитель | **ACM8625** (`snd_soc_acm8625`, `3-0x2c`) |
| Индикация | кольцо 16 RGB + логотип 6 RGB + **LED-часы** (сегменты циферблата) |
| Питание | **USB-C Power Delivery** (`husb238_pd` + `ya_pd_controllers`) |
| Умный дом | **Zigbee** (`zigbee_control`) |
| Радио | **Unisoc** (`vlsicomm` + `aml_sdio` + `sdio_bt`), BT-пульт (`input_btrcu`) |
| Безопасность | SELinux `enforcing`, JTAG выключен (`jtag=disable`), `rh_unlock=0` |

## Флеш и разделы { #partitions }

| MTD | Раздел | Размер | Что внутри |
|---|---|---|---|
| `mtd0` | `bootloader` | 4 МБ | |
| `mtd1`–`mtd3` | `bl2e`, `bl2x`, `ddrfip` | по 2 МБ | ступени загрузчика |
| `mtd4` | `tpl` | 12 МБ | |
| `mtd5` | `tee` | 2 МБ | jffs2, `/tee` (ro) |
| `mtd6` | `aml_sysrecovery` | 128 МБ | |
| `mtd7` | `recovery` | 16 МБ | |
| `mtd8` | `boot` | 16 МБ | ядро |
| `mtd9` | `system` | 128,5 МБ | UBI `ubi0:rootfs` → `/`, **ro** |
| `mtd10` | `data` | 187 МБ | UBI `ubi1:data` → `/data`, rw |

`/` и `/data` — **разные UBI-устройства на разных разделах** (`ubi.mtd=system`,
`ubi.mtd=data` в cmdline). Поэтому `/data` и переживает OTA, которое переписывает `system`.

## Шина I2C и периферия

| Шина:адрес | Чип | Назначение |
|---|---|---|
| `1-0x20` | **AW21018** | LED-драйвер (матрица) |
| `1-0x21` | **AW21012** | LED-драйвер (матрица) |
| `1-0x34`, `2-0x34` | **AW21036** | LED-драйверы (матрица) |
| `2-0x50`, `3-0x52`, `3-0x55` | 24C02A | EEPROM |
| `3-0x08` | **HUSB238** (husb238_pd) | USB-C Power Delivery |
| `3-0x12` | **AW93303** (`aw933xx`) | ёмкостные сенсорные кнопки |
| `3-0x13` | **QMA6100P** | акселерометр |
| `3-0x2c` | **ACM8625** | усилитель |
| `3-0x51` | **PCF8563** | RTC |
| `3-0x53` | **LTR-308** (ltr308als01) | датчик освещённости |

## Индикация

Светодиоды — в `/sys/class/leds/pickle:*`:

- кольцо — 16 RGB-зон: `pickle:{red,green,blue}:ring0` … `ring15`;
- логотип — 6 RGB-зон: `pickle:{red,green,blue}:logo0` … `logo5`;
- циферблат — белые сегменты `pickle:white:clockA0` … `clockH3` (8 групп по 4) и
  `clockDEGREE`, `clockDH`, `clockDL`, `clockDM`;
- служебные `pickle:ring:sync0/1`, `pickle:logo:sync`, `pickle:sync:clock`.

Драйверы: `leds_aw2101x`, `leds_yandex_aw21036`, `quasar_led_ring`.

## Звук и вход

- ALSA card0 `AML-AUGESOUND`: `TDM-A-acm8625-speaker` (воспроизведение), `PDM-dummy-mics`
  (микрофоны), `LOOPBACK-A` (опорный сигнал для эхоподавления), `VAD-dummy-vad`.
- Вход: `aw933xx` (сенсорные кнопки), `vad_keypad`, `mute` (отключение микрофона),
  `input_btrcu` (BT-пульт).

Модули ядра: `aml_sdio`, `dtbocfg`, `key_aw933xx`, `leds_aw2101x`, `leds_yandex_aw21036`,
`ltr308als01`, `optee`/`optee_armtz`, `qma6100p`, `quasar_led_ring`, `quasar_pcba_ids`,
`sdio_bt`, `snd_soc_acm8625`, `vlsicomm`, `ya_pd_controllers`, `zigbee_control`.

## Что переживает перезагрузку и OTA { #persistence }

- После перезагрузки сохраняются изменения **только в `/data`**: правки корневой ФС
  (`/etc/init.d`, `/system/vendor/quasar` и т. п.) пропадают. Корень смонтирован `ro`
  (`ubi0:rootfs` на `mtd9`).
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

- Способ получить root на текущих прошивках.
- Почему не сохраняются правки корневой ФС (SELinux в режиме `enforcing`, overlay или что-то
  ещё) и можно ли перенести автозапуск в `/data`.
- Версия quasar и роли `maind` на снимке.
- Zigbee: какой радиочип и можно ли использовать его как координатор.
