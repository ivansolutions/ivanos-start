#!/usr/bin/env python3
# mashina-provaydera.py — две болезни образа провайдера (Contabo), узнать и вылечить.
#
#   mashina-provaydera.py proverit   # 0 — здорова · 1 — больна (сказано чем) · 2 — не проверить
#   mashina-provaydera.py pochinit   # лечит найденное и проверяет ещё раз; код — как у proverit
#
# 🔴 Слово владельца 27-09 (передано проверяющим): «первый вариант. но надо обязательно
# добавить это в установщик, инструменты и т.д., чтобы больше не повторялось». Первый
# вариант — то, что проверяющий сделал руками на Contabo 27-09 и доказал перезагрузкой:
#
# 1. cloud-init при КАЖДОЙ загрузке исполнял bootcmd из user-data: sed «PermitRootLogin yes»
#    в sshd_config и `pkill -HUP sshd` (на 24.04 sshd по сокету — pkill падает, и с ним
#    cloud-init.service). Лечение: /etc/cloud/cloud-init.disabled. Там же user-data хранит
#    пароль root открытым текстом — в /var/lib/cloud пять копий. Лечение: затереть звёздами
#    той же длины (obj.pkl — двоичный, длина обязана сохраниться) во всех файлах.
# 2. systemd-networkd-wait-online падает по таймауту 2 мин: провайдер не шлёт IPv6 RA, а
#    netplan ждёт его на интерфейсе со статическим IPv6 — интерфейс навсегда «configuring».
#    Лечение: /etc/netplan/60-ivanos-accept-ra.yaml, accept-ra: false для этого интерфейса.
#
# 🔴 Пароль не печатается НИКОГДА — ни он, ни его начало, ни длина. Только имена файлов и счёт.
#
# Один файл на двоих: лежит в пакете IvanOS (/root/bootstrap) и в ivanos-tools/poisk-raboty.
# Копии обязаны совпадать байт в байт — сверяет mashina-proba.sh.
#
# Для пробы: KOREN — корень машины (по умолчанию «/»), MP_NETWORKCTL — файл с выводом
# `networkctl list --no-legend` вместо живого. Подмена НАСТРОЙКИ, разбор и решения те же.
import os, re, subprocess, sys

KOREN = os.environ.get("KOREN", "/") or "/"
ZHIVAYA = os.path.realpath(KOREN) == "/"
ZVEZDA = b"*"
KOROTKIJ = 8          # короче — затирать вслепую по всем файлам опасно: заденет чужие байты

def put(p): return os.path.join(KOREN, p.lstrip("/"))

try:
    import yaml
except ImportError:
    print("   ⚠️  нет python3-yaml — машину провайдера не проверить (apt-get install python3-yaml)")
    sys.exit(2)

def chitat_yaml(p):
    try:
        with open(p, encoding="utf-8", errors="replace") as f:
            t = f.read()
    except OSError:
        return None
    try:
        return yaml.safe_load(t)
    except yaml.YAMLError:
        return None

# ── 1. cloud-init ────────────────────────────────────────────────────────────
def oblako_vyklyucheno():
    if os.path.exists(put("/etc/cloud/cloud-init.disabled")):
        return True
    if ZHIVAYA:
        try:
            return "cloud-init=disabled" in open("/proc/cmdline").read()
        except OSError:
            pass
    return False

def oblako_est():
    return os.path.exists(put("/etc/cloud/cloud.cfg"))

def user_data():
    d = chitat_yaml(put("/var/lib/cloud/instance/user-data.txt"))
    return d if isinstance(d, dict) else {}

OPASNYJ_BOOTCMD = re.compile(r"sshd_config|PermitRootLogin|sshd|PasswordAuthentication")

def opasnye_bootcmd(ud):
    bc = ud.get("bootcmd") or []
    if not isinstance(bc, list):
        bc = [bc]
    out = []
    for k in bc:
        s = " ".join(map(str, k)) if isinstance(k, list) else str(k)
        if OPASNYJ_BOOTCMD.search(s):
            out.append(s)
    return out

def paroli(ud):
    """Открытые пароли из user-data. Затёртые (одни звёзды) паролем не считаются."""
    sp = []
    def dob(v):
        if isinstance(v, (str, int)) and str(v) and set(str(v)) != {"*"}:
            sp.append(str(v).encode())
    dob(ud.get("password"))
    ch = ud.get("chpasswd") or {}
    if isinstance(ch, dict):
        sl = ch.get("list")
        if isinstance(sl, str):
            sl = sl.splitlines()
        for e in sl or []:
            if isinstance(e, dict):
                for v in e.values(): dob(v)
            elif isinstance(e, str) and ":" in e:
                dob(e.split(":", 1)[1])
        for u in ch.get("users") or []:
            if isinstance(u, dict) and u.get("type", "text") == "text":
                dob(u.get("password"))
    for u in ud.get("users") or []:
        if isinstance(u, dict):
            dob(u.get("plain_text_passwd"))
    # один и тот же пароль в двух местах — одна тайна
    return sorted(set(sp), key=len, reverse=True)

def gde_lezhit(tajny):
    """Файлы под /var/lib/cloud и журналы cloud-init, где тайна лежит байтами."""
    mesta = []
    korni = [put("/var/lib/cloud")]
    fajly = [put("/var/log/cloud-init.log"), put("/var/log/cloud-init-output.log")]
    for k in korni:
        for d, _, ff in os.walk(k):
            fajly += [os.path.join(d, f) for f in ff]
    for p in fajly:
        if os.path.islink(p) or not os.path.isfile(p):
            continue
        try:
            b = open(p, "rb").read()
        except OSError:
            continue
        n = sum(b.count(t) for t in tajny)
        if n:
            mesta.append((p, n))
    return mesta

def zateret(tajny, mesta):
    for p, _ in mesta:
        with open(p, "r+b") as f:          # r+b: права и владелец файла остаются как были
            b = f.read()
            for t in tajny:
                b = b.replace(t, ZVEZDA * len(t))
            f.seek(0); f.write(b); f.truncate()

# ── 2. сеть без IPv6 RA ─────────────────────────────────────────────────────
NASH_NETPLAN = "/etc/netplan/60-ivanos-accept-ra.yaml"

def netplan_interfejsy():
    """{id: {'imya':…, 'v6':bool, 'ra_zadan':bool, 'dhcp6':bool}} по всем файлам netplan."""
    itog = {}
    d = put("/etc/netplan")
    if not os.path.isdir(d):
        return itog
    for f in sorted(os.listdir(d)):
        if not f.endswith(".yaml"):
            continue
        y = chitat_yaml(os.path.join(d, f)) or {}
        eth = ((y.get("network") or {}).get("ethernets") or {}) if isinstance(y, dict) else {}
        for i, c in eth.items():
            c = c or {}
            z = itog.setdefault(i, {"imya": i, "v6": False, "ra_zadan": False, "dhcp6": False})
            if c.get("set-name"): z["imya"] = c["set-name"]
            for a in c.get("addresses") or []:
                a = str(a).split("/")[0]
                if ":" in a and not a.lower().startswith("fe80"):
                    z["v6"] = True
            if "accept-ra" in c: z["ra_zadan"] = True
            if c.get("dhcp6"): z["dhcp6"] = True
    return itog

def zhdut_ra():
    """Интерфейсы, которые networkd НЕ может доконфигурировать. Живой факт, а не догадка."""
    f = os.environ.get("MP_NETWORKCTL")
    try:
        t = open(f).read() if f else subprocess.run(
            ["networkctl", "list", "--no-legend", "--no-pager"],
            capture_output=True, text=True, timeout=10).stdout
    except (OSError, subprocess.SubprocessError):
        return None
    return {s.split()[1] for s in t.splitlines() if len(s.split()) >= 5 and s.split()[4] == "configuring"}

def bolnye_seti():
    zhd = zhdut_ra()
    if zhd is None:
        return None
    return [i for i, z in netplan_interfejsy().items()
            if z["v6"] and not z["ra_zadan"] and not z["dhcp6"] and z["imya"] in zhd]

# ── осмотр ──────────────────────────────────────────────────────────────────
def osmotr():
    bol, ne_znayu = [], []
    ud = {}
    if oblako_est():
        ud = user_data()
        if not oblako_vyklyucheno() and opasnye_bootcmd(ud):
            bol.append(("bootcmd", f"cloud-init включён и при КАЖДОЙ загрузке правит ssh "
                        f"({len(opasnye_bootcmd(ud))} команд bootcmd в user-data)"))
    tajny = paroli(ud)
    mesta = gde_lezhit(tajny) if tajny else []
    if mesta:
        if min(map(len, tajny)) < KOROTKIJ:
            ne_znayu.append(f"пароль из user-data короче {KOROTKIJ} знаков — затирать вслепую опасно, "
                            f"нужна рука: файлов с ним {len(mesta)}")
        bol.append(("parol", f"пароль из user-data лежит открытым текстом: файлов {len(mesta)}, "
                    f"вхождений {sum(n for _, n in mesta)}"))
    seti = bolnye_seti()
    if seti is None:
        ne_znayu.append("networkctl не ответил — сеть без RA не проверена")
    elif seti:
        bol.append(("ra", f"сеть ждёт IPv6 RA, которого нет: {', '.join(seti)} — «configuring», "
                    f"загрузка ждёт 2 мин"))
    return bol, ne_znayu, tajny, mesta, seti or []

def skazat(bol, ne_znayu):
    for _, s in bol: print(f"   🔴 {s}")
    for s in ne_znayu: print(f"   ⚠️  {s}")
    if not bol and not ne_znayu:
        print("   ✅ машина провайдера здорова: cloud-init не правит ssh, открытого пароля нет, сеть не ждёт RA")

def pochinit():
    bol, ne_znayu, tajny, mesta, seti = osmotr()
    chto = {k for k, _ in bol}
    if "bootcmd" in chto:
        with open(put("/etc/cloud/cloud-init.disabled"), "w") as f:
            f.write("IvanOS 27-09: слово владельца «первый вариант». Вернуть — удалить этот файл.\n")
        print("   🔧 cloud-init выключен: /etc/cloud/cloud-init.disabled")
    if "parol" in chto and min(map(len, tajny)) >= KOROTKIJ:
        zateret(tajny, mesta)
        print(f"   🔧 пароль затёрт звёздами той же длины в {len(mesta)} файлах")
    if "ra" in chto:
        p = put(NASH_NETPLAN)
        tekst = ("# IvanOS 27-09: провайдер не шлёт IPv6 RA — без этого интерфейс навсегда «configuring»,\n"
                 "# загрузка ждёт 2 мин. Вернуть — удалить этот файл.\n"
                 "network:\n  version: 2\n  ethernets:\n" +
                 "".join(f"    {i}:\n      accept-ra: false\n" for i in seti))
        fd = os.open(p, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
        with os.fdopen(fd, "w") as f:
            f.write(tekst)
        if ZHIVAYA:
            r = subprocess.run(["netplan", "generate"], capture_output=True, text=True)
            if r.returncode != 0:
                os.remove(p)                 # сломанный netplan хуже ожидания RA: откат
                print(f"   🔴 netplan generate отверг правку — файл убран, сеть не тронута: {r.stderr.strip()[:200]}")
                return 1
        print(f"   🔧 accept-ra: false для {', '.join(seti)} ({NASH_NETPLAN}); вступит при следующей загрузке")
    # повторный осмотр — починка доказывается им, а не словами выше
    bol2, ne2, *_ = osmotr()
    skazat(bol2, ne2)
    return 1 if bol2 else (2 if ne2 else 0)

def main():
    rezhim = sys.argv[1] if len(sys.argv) > 1 else "proverit"
    if rezhim == "proverit":
        bol, ne_znayu, *_ = osmotr()
        skazat(bol, ne_znayu)
        return 1 if bol else (2 if ne_znayu else 0)
    if rezhim == "pochinit":
        if ZHIVAYA and os.geteuid() != 0:
            print("   🔴 чинить машину можно только от root"); return 1
        return pochinit()
    print(f"   непонятный режим «{rezhim}»: proverit | pochinit"); return 2

if __name__ == "__main__":
    sys.exit(main())
