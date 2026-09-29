#!/bin/bash
# zagruzchik.sh — старт IvanOS одной строкой на чистой Ubuntu 24.04 (публичная часть).
#
#   curl -fsSL https://raw.githubusercontent.com/ivansolutions/ivanos-start/<тег>/zagruzchik.sh | bash
#   … | bash -s -- v02        — другой номер поколения (по умолчанию v01)
#
# Решение владельца 28-09: старт — публичный загрузчик одной строкой. Что он делает и почему так:
#   · ВЕСЬ код — внутри main(), последняя строка — `main "$@"`. При `curl | bash` bash исполняет
#     скрипт по мере чтения: оборванная на середине загрузка без main() исполнила бы половину.
#     С main() обрыв = ничего не исполнено: функция не дочитана — вызывать нечего.
#   · основной скрипт КАЧАЕТСЯ В ФАЙЛ и сверяется по sha256, закреплённому здесь; не сошлось —
#     отказ, ничего не запущено;
#   · запуск — `bash файл </dev/tty`: при `curl | bash` stdin занят самим загрузчиком, и без
#     этого установщик не смог бы спросить владельца ни о чём;
#   · сразу — в tmux (сессия ivanos-ustanovka): защита перезапускает sshd, и обрыв ssh убил бы
#     установку на полпути. Оборвалось — `tmux attach -t ivanos-ustanovka`;
#   · закрытый пакет IvanOS основной скрипт тянет по ЗАКРЕПЛЁННОМУ коммиту (IVANOS_PAKET_KOMMIT),
#     а не по верхушке main.
# Данных владельца здесь нет и быть не должно — файл публичный (sukhoe-rozhdenie-proba.sh).

main() {
  set -euo pipefail
  export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

  # ── Закреплено при публикации (тег ivanos-start). Меняется ТОЛЬКО вместе с тегом. ──
  local ADRES="${IVANOS_START_ADRES:-https://raw.githubusercontent.com/ivansolutions/ivanos-start/v2.0.0}"
  local SHA_STEND=3bc5c7ec44bae6574f85214958458d720c6b46a4843f41331f178d34b1fc15ca
  local SHA_MASHINA=ba1b8d6e4e36b67f2ff9cfa02affc0a27174268ff2718a2213c197a3fc6f100e
  local PAKET_KOMMIT="${IVANOS_PAKET_KOMMIT:-0ae376182c4762cfef94604e78e5e915d61a0bac}"   # ← полный хеш коммита пакета IvanOS; ставится при публикации
  # ────────────────────────────────────────────────────────────────────────────

  # Подмены — только для zagruzchik-proba.sh: папка, tmux и терминал. Владелец их не задаёт.
  local VERSIYA=${1:-v01} KUDA=${IVANOS_START_PAPKA:-/root/ivanos-start} TMUX_K=${IVANOS_START_TMUX:-tmux} TTY=${IVANOS_START_TTY:-/dev/tty} T F SHA
  [ "$(id -u)" = 0 ] || { echo "🔴 запускать от root: sudo -i, потом та же строка"; exit 1; }
  case "$VERSIYA" in v[0-9][0-9]) : ;; *) echo "🔴 поколение — v00…v99, получено «$VERSIYA»"; exit 1 ;; esac
  [ -n "$PAKET_KOMMIT" ] || { echo "🔴 в загрузчике не закреплён коммит пакета — это не опубликованный загрузчик. Ставить нечего"; exit 1; }
  case "$ADRES" in *TEG) echo "🔴 в загрузчике не закреплён тег ivanos-start — это не опубликованный загрузчик"; exit 1 ;; esac

  mkdir -p "$KUDA"
  T=$(mktemp -d)
  for F in stend-postavit.sh:$SHA_STEND mashina-provaydera.py:$SHA_MASHINA; do
    SHA=${F#*:}; F=${F%%:*}
    curl -fsSL --retry 3 --max-time 60 -o "$T/$F" "$ADRES/$F" || { rm -rf "$T"; echo "🔴 не скачался $ADRES/$F"; exit 1; }
    if [ "$(sha256sum "$T/$F" | cut -d' ' -f1)" != "$SHA" ]; then
      rm -rf "$T"
      echo "🔴 $F пришёл НЕ ТОТ: sha256 не сошёлся с закреплённым. Ничего не запускаю."
      echo "   Либо подмена по дороге, либо загрузчик и файлы разных тегов."
      exit 1
    fi
    install -m 0755 "$T/$F" "$KUDA/$F"
  done
  rm -rf "$T"
  echo "   ✅ установщик скачан и сверен: $KUDA (sha256 ${SHA_STEND:0:12}…)"

  local ZAPUSK
  ZAPUSK="cd ${IVANOS_START_CD:-/root} && IVANOS_PAKET_KOMMIT=$PAKET_KOMMIT IVANOS_SSH_CONNECTION='${SSH_CONNECTION:-}' bash $KUDA/stend-postavit.sh $VERSIYA"
  if [ -n "${TMUX:-}" ]; then
    eval "$ZAPUSK" <"$TTY"
  elif command -v "$TMUX_K" >/dev/null 2>&1; then
    echo "   Установка идёт в tmux «ivanos-ustanovka». Оборвалась связь — зайти и: tmux attach -t ivanos-ustanovka"
    exec "$TMUX_K" new-session -A -s ivanos-ustanovka "$ZAPUSK; echo; echo '   (окно можно закрыть: Ctrl-b d)'; exec bash" <"$TTY"
  else
    echo "   ⚠️  tmux нет — ставлю без него. Оборвётся ssh — та же строка ещё раз продолжит с упавшего шага."
    eval "$ZAPUSK" <"$TTY"
  fi
}

main "$@"
