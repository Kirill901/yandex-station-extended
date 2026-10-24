# Патч retail CA из factory через ADB

Этот способ меняет только CA-бандл в retail-разделе, пока колонка загружена в
factory. Версия прошивки при этом не меняется.

Подходит для колонок на **Amlogic/Buildroot** с native quasar/maind. Android-модели
(Станция Макс, Станция первого поколения) этим способом не покрываются.

Для Станции Лайт 2 (Plum) ориентиром служит дата сборки прошивки:

- до 21 октября 2026 года — сборка уязвима, используйте [обычный DNS-метод](root.md);
- после 21 октября 2026 года — сборка уже не уязвима, используйте этот способ через factory.

Для Plum в проверенной разметке:

- `mtd3` — раздел `system`;
- UBI-том внутри него называется `rootfs`;
- `/bkupgrade` — отдельный раздел данных;
- после normal-загрузки файл виден как
  `/system/vendor/quasar/certs/ca-certificates.crt`.

На других моделях номера MTD и UBI нужно проверить перед монтированием.

## Что понадобится

- Linux-хост в одной сети с колонкой;
- [eQuasar](https://git.gay/iwakura/eQuasar/), nginx и DNS-сервер;
- роутер, в котором можно выдать свой DNS через DHCP;
- `adb`;
- файл `retail-ca-certificates-with-aaa.pem`.

## 1. Поднять eQuasar

[eQuasar](https://git.gay/iwakura/eQuasar/) — готовый nginx MITM для Quasar.
Он сам отвечает за `get_sync_info` с включённым network ADB и возвращает
`{"hasUpdate":false}` на `check_updates`, а остальные запросы проксирует дальше.

Скачать репозиторий:

~~~sh
git clone https://git.gay/iwakura/eQuasar.git
cd eQuasar
~~~

### Вариант с системным nginx

Если nginx ещё не установлен на Ubuntu/Debian:

~~~sh
sudo apt update
sudo apt install -y nginx
~~~

Скопировать файлы из репозитория в пути, которые использует конфигурация
eQuasar:

~~~sh
sudo install -d /opt/fakequasar
sudo cp -r copymetoroot/opt/fakequasar/certs /opt/fakequasar/
sudo install -d /etc/nginx/sites-enabled
sudo cp copymetoroot/etc/nginx/sites-enabled/quasar \
  /etc/nginx/sites-enabled/quasar
sudo nginx -t
sudo systemctl reload nginx
~~~

В каталоге `copymetoroot/opt/fakequasar/certs` уже лежат сертификаты и ключ,
на которые ссылается nginx-конфигурация. Вики не содержит их содержимое — нужно
использовать файлы из самого репозитория eQuasar.

### Вариант с Docker

Вместо установки системного nginx можно запустить compose-конфигурацию из
репозитория:

~~~sh
docker compose up -d --build
~~~

Не запускайте оба варианта одновременно: оба занимают порты `80` и `443`.

### Настроить DNS

В DNS-сервере направить на IP машины с eQuasar (`<IP_EQUASAR>`):

~~~text
quasar.yandex.net
quasar.yandex.ru
scbh.yandex.net
~~~

Следующие домены направить на `127.0.0.1` или другой недоступный адрес:

~~~text
strm.yandex.ru
rpc.alice.yandex.net
uniproxy.alice.yandex.net
alice.yandex.net
alice-ats.yandex.net
alice-ats-test.yandex.net
~~~

Выдать этот DNS-сервер колонке через DHCP роутера. Для доменов eQuasar не должно
быть рабочих AAAA-записей, иначе колонка может уйти по IPv6 мимо nginx.

### Проверить eQuasar до включения колонки

Проверить ответы nginx с Linux-хоста:

~~~sh
curl -sk -w '\nHTTP %{http_code}\n' \
  --resolve quasar.yandex.net:443:<IP_EQUASAR> \
  https://quasar.yandex.net/check_updates
~~~

Ожидается:

~~~text
{"hasUpdate":false}
HTTP 200
~~~

Проверить включение network ADB:

~~~sh
curl -sk --resolve quasar.yandex.net:443:<IP_EQUASAR> \
  https://quasar.yandex.net/get_sync_info
~~~

В ответе должны быть `"remoteActivation":true` и `"network":true`.

Для системного nginx смотреть логи можно так:

~~~sh
sudo tail -f /var/log/nginx/quasar.yandex.net.access.log
~~~

Для Docker:

~~~sh
docker compose logs -f quasar
~~~

Оставить eQuasar запущенным на всём протяжении процедуры.

## 2. Загрузить колонку в factory mode

Следующий способ входа в factory mode актуален для **Plum / Станции Лайт 2**.
Для остальных колонок способ сброса и входа в factory mode нужно искать отдельно
по запросу `как сбросить колонку <название колонки>`.

1. Отключите колонку от питания.
2. Зажмите кнопку отключения микрофона.
3. Не отпуская кнопку, подключите питание.
4. Через приложение умного дома подключите колонку к сети, в которой через DHCP
   выдан DNS-сервер eQuasar.

Приложение может сообщить, что настроить колонку не удалось. Это можно
игнорировать, если в логе eQuasar уже видны запросы колонки, а `check_updates`
возвращает `{"hasUpdate":false}`.

Если в логах нет запросов или `check_updates` возвращает `true`, остановиться и
исправить DNS/nginx до продолжения.

Найдите IP колонки в списке клиентов роутера.

## 3. Подключиться по ADB

~~~sh
adb connect <IP_колонки>:5555
adb wait-for-device
adb root
adb shell id
~~~

Ожидается:

~~~text
uid=0(root)
~~~

Передать CA-бандл во временный каталог:

~~~sh
adb push \
  /path/to/retail-ca-certificates-with-aaa.pem \
  /data/local/tmp/retail-ca-certificates.crt
~~~

## 4. Проверить разметку и подключить retail

Зайти в shell factory-системы:

~~~sh
adb shell
~~~

Сначала проверить разметку:

~~~sh
cat /proc/mtd
cat /proc/cmdline
mount | grep -E 'ubi|ubifs|system|bkupgrade'
ubinfo -a
~~~

### Как определить MTD-номер

В выводе `/proc/mtd` найди строку, имя которой — `system`:

~~~text
dev:    size   erasesize  name
mtd0: ...      ...        "env"
mtd2: ...      ...        "factory"
mtd3: ...      ...        "system"
mtd4: ...      ...        "bkupgrade"
~~~

В этом примере нужный раздел — `mtd3`, поэтому MTD-номер для `ubiattach` —
`3`. В команду передаётся только число, без префикса `mtd`:

~~~sh
ubiattach /dev/ubi_ctrl -m 3
~~~

`bkupgrade` не является retail-системой: не выбирай его только потому, что он
есть в списке. Целевой раздел должен содержать путь
`system/vendor/quasar/certs/ca-certificates.crt` после монтирования. Если в
`/proc/mtd` нет строки `"system"` и назначение разделов нельзя однозначно
определить по `mount` и `cat /proc/cmdline`, остановись и не подставляй номер
наугад.

### Проверить уже подключённый UBI

Перед `ubiattach` проверь `ubinfo -a`. Если в выводе есть блок с нужным
`MTD device number` и томом `rootfs`, UBI уже подключён. Например:

~~~text
UBI device number 2
MTD device number: 3
...
Name: rootfs
~~~

В этом случае повторно выполнять `ubiattach` не нужно: номер UBI-устройства —
`2`, и после создания точки монтирования можно сразу использовать `ubi2:rootfs`.

Если нужного UBI-блока нет, подключить найденный выше MTD-раздел:

Создать точку монтирования и подключить rootfs:

~~~sh
mkdir -p /mnt/retail
ubiattach /dev/ubi_ctrl -m <MTD_НОМЕР>
ubinfo -a
~~~

После `ubiattach` найди в его выводе строку вида:

~~~text
UBI device number 2
~~~

Именно этот номер подставляется в имя тома. Для примера выше команда будет
такой:

~~~sh
mount -t ubifs -o rw ubi2:rootfs /mnt/retail
~~~

Если у тебя выведен другой номер, замени `2` на него.

Проверить целевой файл и режим монтирования:

~~~sh
TARGET=/mnt/retail/system/vendor/quasar/certs/ca-certificates.crt
test -f "$TARGET" && echo OK
mount | grep '/mnt/retail'
~~~

Ожидается `OK` и режим `rw`.

Если раздел подключился как ro:

~~~sh
mount -o remount,rw /mnt/retail
~~~

Если remount не сработал, остановиться. Не использовать `dd`, `ubiformat`,
`erase` и запись всего MTD-раздела.

## 5. Заменить CA-бандл

Сохранить оригинал и заменить только файл trust store:

~~~sh
cp -a "$TARGET" "$TARGET.orig"
cp /data/local/tmp/retail-ca-certificates.crt "$TARGET"
chmod 0644 "$TARGET"
chown 0:0 "$TARGET"
sync
~~~

Проверить результат:

~~~sh
grep -c 'BEGIN CERTIFICATE' "$TARGET"
sha256sum "$TARGET"
grep -a 'AAA Certificate Services' "$TARGET"
~~~

Проверка выполняется уже по файлу, записанному в retail-раздел. Ожидается `123`
сертификата и SHA-256:

~~~text
5b62f4434ecee31e1e0dfbd57a50fce15be54c4fdfc0f4ccc4a140f0c88f68db
~~~

Если hash не совпадает, не перезагружать колонку.

## 6. Вернуться в normal/retail

Проверить текущие переменные загрузчика:

~~~sh
fw_printenv upgrade_step boot_to_recovery
~~~

Для проверенной AXG factory-конфигурации выставить normal-загрузку:

~~~sh
fw_setenv upgrade_step 1
fw_setenv boot_to_recovery 0
fw_printenv upgrade_step boot_to_recovery
~~~

Ожидается:

~~~text
upgrade_step=1
boot_to_recovery=0
~~~

Если переменных нет или factory-образ использует другую схему загрузки, не
подставлять имена наугад.

Размонтировать retail и перезагрузить:

~~~sh
sync
mount -o remount,ro /mnt/retail
umount /mnt/retail
exit
adb reboot
~~~

## 7. Проверить normal-загрузку

После загрузки retail-системы проверить файл:

~~~sh
adb shell sha256sum /system/vendor/quasar/certs/ca-certificates.crt
~~~

Hash должен совпадать с:

~~~text
5b62f4434ecee31e1e0dfbd57a50fce15be54c4fdfc0f4ccc4a140f0c88f68db
~~~

После проверки остановить eQuasar и вернуть обычные DNS-настройки.

## Вернуть исходный CA-бандл

Загрузить колонку в factory mode, подключить retail-раздел по шагу 4 и выполнить:

~~~sh
TARGET=/mnt/retail/system/vendor/quasar/certs/ca-certificates.crt
test -f "$TARGET.orig" || { echo 'original backup is missing'; exit 1; }
cp -a "$TARGET.orig" "$TARGET"
chmod 0644 "$TARGET"
chown 0:0 "$TARGET"
sync
mount -o remount,ro /mnt/retail
umount /mnt/retail
~~~

После этого снова выставить normal-загрузку:

~~~sh
fw_setenv upgrade_step 1
fw_setenv boot_to_recovery 0
reboot
~~~

Если `$TARGET.orig` отсутствует, не подбирать другой CA-бандл и не стирать раздел.
Использовать [восстановление](recovery.md) для конкретной модели.

## Если что-то не получилось

??? failure "В factory mode колонка начала обновляться и загрузилась обычная Алиса"
    eQuasar не перехватил запросы колонки: MITM не работает. Начать гайд заново
    и перед повторным подключением колонки проверить, что eQuasar запущен,
    DNS указывает на него, а `check_updates` возвращает
    `{"hasUpdate":false}`.

??? failure "Приложение пишет «не удалось настроить Алису»"
    Проверить лог eQuasar. В factory важны запросы Quasar и появление ADB, а не
    финальный экран приложения.

??? failure "adb connect не работает"
    Проверить актуальный IP после загрузки factory mode, одну LAN без AP isolation,
    доступность портов `80`/`443` на eQuasar и DNS-подмену.

??? failure "ubiattach сообщает, что устройство уже подключено"
    Не повторять `ubiattach`. Найти существующий `ubiN:rootfs` через `ubinfo -a`.

??? failure "Файл CA не найден"
    Проверить выбранный UBI-том и путь
    `/mnt/retail/system/vendor/quasar/certs/ca-certificates.crt`. Если файла нет,
    остановиться.

??? failure "Retail-система загрузилась, но ADB нет"
    eQuasar должен работать на протяжении всей процедуры — от загрузки factory
    mode до получения root-доступа в retail-прошивке. Если после замены CA и
    normal-загрузки ADB не появился, начать гайд заново и заново пройти
    подключение через eQuasar. Не перезаписывать boot или recovery наугад.
