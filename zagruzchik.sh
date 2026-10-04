#!/bin/bash
# zagruzchik.sh — старт IvanOS одной строкой на чистой Ubuntu 24.04 (публичная часть).
#
#   curl -fsSL https://raw.githubusercontent.com/ivansolutions/ivanos-start/<тег>/zagruzchik.sh | bash
#   … | bash -s -- v02        — другой номер поколения (по умолчанию v01)
#   … | bash -s -- <ссылка>   — одноразовая ссылка заказа (z-…): ключи и дом приезжают с ней
#
# Решение владельца 28-09: старт — публичный загрузчик одной строкой. Что он делает и почему так:
#   · ВЕСЬ код — внутри main(), последняя строка — `main "$@"`. При `curl | bash` bash исполняет
#     скрипт по мере чтения: оборванная на середине загрузка без main() исполнила бы половину.
#     С main() обрыв = ничего не исполнено: функция не дочитана — вызывать нечего.
#   · основной скрипт КАЧАЕТСЯ В ФАЙЛ и сверяется по sha256, закреплённому здесь; не сошлось —
#     отказ, ничего не запущено;
#   · запуск — со stdin из терминала: при `curl | bash` stdin занят самим загрузчиком, и без
#     этого установщик не смог бы спросить владельца ни о чём. Терминал — НАСТОЯЩИМ именем
#     (/dev/pts/N), а не /dev/tty: tmux 3.4 на `</dev/tty` отвечает «open terminal failed: can't
#     use /dev/tty» и не встаёт (находка 1 пробы на чистой Hetzner 29-09). Терминала нет — отказ
#     словами: установщику некому задать вопросы;
#   · сразу — в tmux (сессия ivanos-ustanovka): защита перезапускает sshd, и обрыв ssh убил бы
#     установку на полпути. Оборвалось — `tmux attach -t ivanos-ustanovka`;
#   · закрытый пакет IvanOS основной скрипт тянет по ЗАКРЕПЛЁННОМУ коммиту (IVANOS_PAKET_KOMMIT),
#     а не по верхушке main.
# Данных владельца здесь нет и быть не должно — файл публичный (sukhoe-rozhdenie-proba.sh).

# ── Приём одноразовой ссылки ─────────────────────────────────────────────────
# Пакет заказа — ассет релиза <id> в публичном ivanos-tools/ivanos-ssylki, зашифрован ключом из
# строки. Сверка: sha256 пакета — с закреплённым в строке; не сошлось — отказ, ничего не тронуто.
# Ключи развёртывания кладутся на их места в ssh (установщик не заводит ключ, если файл есть —
# окна «СТОП до ключей» нет). Гасит ссылку гаситель в Actions по первому скачиванию (~10 мин).
vzyat_ssylku() {   # <строка> <куда> <каталог ssh>
  local STROKA=$1 KUDA=$2 SSH_K=$3 ID SHA16 KL R F
  IFS=. read -r ID SHA16 KL <<< "$STROKA"
  if ! [[ "$ID" =~ ^z-[0-9]{8}-[0-9]{4}-[0-9a-f]{6}$ && "$SHA16" =~ ^[0-9a-f]{16}$ && "$KL" =~ ^[0-9a-f]{32}$ ]]; then
    echo "🔴 строка ссылки не той формы — проверь, что скопирована целиком"; return 1
  fi
  R=$(mktemp -d); chmod 700 "$R"
  if [ "$(curl -sSL -o "$R/paket.bin" -w '%{http_code}' --max-time 120 \
         "https://github.com/${IVANOS_SSYLKI_REPO:-ivanos-tools/ivanos-ssylki}/releases/download/$ID/paket.bin" || true)" != 200 ]; then
    rm -rf "$R"
    echo "🔴 ОТКАЗ: ссылка $ID не действует — она одноразовая: уже использована или срок вышел. Нужна новая."
    return 1
  fi
  if [ "$(sha256sum "$R/paket.bin" | cut -c1-16)" != "$SHA16" ]; then
    rm -rf "$R"; echo "🔴 ОТКАЗ: пакет $ID не тот, что выпущен (sha256 не сошёлся). Ничего не ставлю."; return 1
  fi
  printf '%s' "$KL" > "$R/k"
  if ! openssl enc -d -aes-256-cbc -pbkdf2 -iter 600000 -pass file:"$R/k" -in "$R/paket.bin" -out "$R/p.tgz" 2>/dev/null; then
    rm -rf "$R"; echo "🔴 ОТКАЗ: пакет $ID не расшифровался"; return 1
  fi
  install -d -m 700 "$KUDA" "$SSH_K"
  tar -C "$KUDA" -xzf "$R/p.tgz"
  rm -rf "$R"
  for F in "$KUDA"/klyuchi/*; do
    [ -f "$F" ] || continue
    install -m 600 "$F" "$SSH_K/$(basename "$F")"
  done
  echo "   ✅ ссылка $ID принята: пакет сверен и расшифрован, ключи — в $SSH_K"
}

main() {
  set -euo pipefail
  export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

  # ── Закреплено при публикации (тег ivanos-start). Меняется ТОЛЬКО вместе с тегом. ──
  local ADRES="${IVANOS_START_ADRES:-https://raw.githubusercontent.com/ivansolutions/ivanos-start/v2.3.0}"
  local SHA_STEND=2e5c99272bd193caa280ef0749fd5a09167fa9940093287b0fcd2fec039e1516
  local SHA_MASHINA=ba1b8d6e4e36b67f2ff9cfa02affc0a27174268ff2718a2213c197a3fc6f100e
  local PAKET_KOMMIT="${IVANOS_PAKET_KOMMIT:-3fc05aff2414e6edf70806180162d076c0d41ffc}"   # ← полный хеш коммита пакета IvanOS; ставится при публикации
  # ────────────────────────────────────────────────────────────────────────────

  # Подмены — только для zagruzchik-proba.sh: папка, tmux и терминал. Владелец их не задаёт.
  # Одноразовая ссылка (слово владельца 03-10: «ссылка действительна один раз… Без пароля, без
  # ничего»): z-<дата>-<время>-<6 hex>.<sha256 пакета, 16 hex>.<ключ, 32 hex>. Ключ — в самой строке.
  local STROKA=""
  case "${1:-}" in z-*) STROKA=$1; shift ;; esac
  local VERSIYA=${1:-v01} KUDA=${IVANOS_START_PAPKA:-/root/ivanos-start} TMUX_K=${IVANOS_START_TMUX:-tmux} TTY=${IVANOS_START_TTY:-} T F SHA
  [ "$(id -u)" = 0 ] || { echo "🔴 запускать от root: sudo -i, потом та же строка"; exit 1; }
  case "$VERSIYA" in v[0-9][0-9]) : ;; *) echo "🔴 поколение — v00…v99, получено «$VERSIYA»"; exit 1 ;; esac
  [ -n "$PAKET_KOMMIT" ] || { echo "🔴 в загрузчике не закреплён коммит пакета — это не опубликованный загрузчик. Ставить нечего"; exit 1; }
  case "$ADRES" in *TEG) echo "🔴 в загрузчике не закреплён тег ivanos-start — это не опубликованный загрузчик"; exit 1 ;; esac

  # Имя терминала — у ps, а не у `tty`: `tty` смотрит на stdin, а он при `curl | bash` — труба;
  # `tty </dev/tty` отдаёт снова «/dev/tty». ps берёт управляющий терминал процесса.
  if [ -z "$TTY" ]; then
    T=$(ps -o tty= -p $$ 2>/dev/null || true); T=${T// /}
    if [ -n "$T" ] && [ "$T" != "?" ] && [ -c "/dev/$T" ]; then TTY=/dev/$T; fi
  fi
  if [ -z "$TTY" ]; then
    echo "🔴 терминала нет — установщику некому задать вопросы (ключи, токен, вход в Claude)."
    echo "   Зайти по ssh с терминалом (ssh -t root@сервер) и ту же строку ещё раз."
    exit 1
  fi

  # Ссылка — ДО всего: не действует (погашена, срок) — отказ словами, машина не тронута.
  local ZAKAZ="" ZAP_ZAKAZ=""
  if [ -n "$STROKA" ]; then
    ZAKAZ=${IVANOS_ZAKAZ_PAPKA:-/root/.ivanos-zakaz}
    vzyat_ssylku "$STROKA" "$ZAKAZ" "${IVANOS_SSH_KATALOG:-/root/.ssh}" || exit 1
    ZAP_ZAKAZ="IVANOS_ZAKAZ=$ZAKAZ "
  fi

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
  ZAPUSK="cd ${IVANOS_START_CD:-/root} && ${ZAP_ZAKAZ}IVANOS_PAKET_KOMMIT=$PAKET_KOMMIT IVANOS_SSH_CONNECTION='${SSH_CONNECTION:-}' bash $KUDA/stend-postavit.sh $VERSIYA"
  if [ -n "${TMUX:-}" ]; then
    eval "$ZAPUSK" <"$TTY"
  elif command -v "$TMUX_K" >/dev/null 2>&1; then
    # Находка 7 (проверяющий, 30-09): при TERM=dumb или пустом (веб-консоль провайдера, ssh без
    # терминала у клиента) tmux отвечает «open terminal failed: terminal does not support clear» и
    # не встаёт. Такой TERM подменяется на xterm-256color — он есть в ncurses-base любой Ubuntu.
    if [ -z "${TERM:-}" ] || [ "$TERM" = dumb ] || ! tput -T "$TERM" clear >/dev/null 2>&1; then
      echo "   TERM=«${TERM:-}» tmux не годится — ставлю xterm-256color"
      export TERM=xterm-256color
    fi
    # 🔴 04-10, проба 2: «если связь оборвётся» — владелец читал «Оборвалась связь…» как сообщение об обрыве.
    echo "   Установка идёт в tmux «ivanos-ustanovka». Если связь оборвётся — зайди снова и: tmux attach -t ivanos-ustanovka"
    # 🔴 04-10, проба 2 (и, похоже, 1): экран владельца застывал сразу после строки выше — клиент tmux
    # attached,focused, а не рисует ничего; вторая вкладка с attach видит всё. Воспроизведено в
    # псевдотерминале (tmux-proba.sh): stdin, ЗАНОВО открытый по имени (<"$TTY"), — 0 байт от tmux;
    # stdin — копия уже открытого терминала (<&1) — экран и вопрос на месте. При `curl | bash` stdin —
    # труба, а stdout — терминал владельца: его и отдаём. Не терминал — по-старому, по имени.
    if [ -t 1 ]; then
      exec "$TMUX_K" new-session -A -s ivanos-ustanovka "$ZAPUSK; echo; echo '   (окно можно закрыть: Ctrl-b d)'; exec bash" <&1
    fi
    exec "$TMUX_K" new-session -A -s ivanos-ustanovka "$ZAPUSK; echo; echo '   (окно можно закрыть: Ctrl-b d)'; exec bash" <"$TTY"
  else
    echo "   ⚠️  tmux нет — ставлю без него. Оборвётся ssh — та же строка ещё раз продолжит с упавшего шага."
    eval "$ZAPUSK" <"$TTY"
  fi
}

main "$@"
