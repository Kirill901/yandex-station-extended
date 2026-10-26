#!/sbin/busybox sh
# station1-freeze-updatesd.sh — держит службу обновлений Алисы (maind --updatesd)
# замороженной (SIGSTOP), чтобы колонка не уходила в цикл обязательного обновления.
#
# Проверено: Яндекс Станция 1 (tulip), прошивка 2.369.5.46, root через AliceBridge,
# dropbear в /data/dropbear. На колонке лежит как /data/dropbear/freeze_updatesd.sh
# и запускается из /data/dropbear/start.sh в фоне, через /sbin/busybox sh
# (рецепт: docs/recipes/station1-disable-updates.md).
#
# Откат: убрать вызов скрипта из start.sh и перезагрузить колонку
#        (или без перезагрузки: kill -CONT <pid updatesd> и остановить этот скрипт).
BB=/sbin/busybox
echo "$($BB date) freeze started pid $$"
while true; do
    for p in /proc/[0-9]*; do
        [ "${p#/proc/}" = "$$" ] && continue
        # Шаблон привязан к argv[0]: иначе под SIGSTOP попадёт любой процесс,
        # в чьей командной строке лишь упоминается «maind --updatesd»,
        # включая вашу же SSH-сессию с проверочной командой из рецепта.
        case "$($BB tr '\0' ' ' < $p/cmdline 2>/dev/null)" in
            maind\ --updatesd*|*/maind\ --updatesd*)
                [ "$($BB awk '/^State/{print $2}' $p/status)" = T ] ||
                    { kill -STOP ${p#/proc/} &&
                      echo "$($BB date) froze ${p#/proc/}"; } ;;
        esac
    done
    $BB sleep 3
done
