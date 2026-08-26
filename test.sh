#!/bin/sh
# ============================================================
# DNS Manager v3.4-FINAL
# ash-safe | независимый тест | bypass/clean | 8 профилей | сток
# ============================================================

MANAGER_PATH="/usr/bin/dns-manager"
SELF_SOURCE="$0"
CATVER="3.4"

install_self() {
    [ "$SELF_SOURCE" = "$MANAGER_PATH" ] && return 0
    echo "=== Установка DNS Manager v3.4 ==="
    if command -v apk >/dev/null 2>&1; then PKG="apk"
    elif command -v opkg >/dev/null 2>&1; then PKG="opkg"
    else echo "[!] Нет пакетного менеджера"; exit 1; fi

    NEED=0
    command -v https-dns-proxy >/dev/null 2>&1 || NEED=1
    command -v curl >/dev/null 2>&1 || NEED=1
    if [ "$NEED" = "1" ]; then
        echo "[*] Установка пакетов..."
        if [ "$PKG" = "apk" ]; then
            apk update && apk add https-dns-proxy ca-certificates curl bind-tools
        else
            opkg update && opkg install https-dns-proxy ca-certificates curl bind-dig
        fi
    fi

    if [ -f "$SELF_SOURCE" ]; then
        cp "$SELF_SOURCE" "$MANAGER_PATH" 2>/dev/null || cat "$SELF_SOURCE" > "$MANAGER_PATH"
    else
        wget -q -O "$MANAGER_PATH" "https://raw.githubusercontent.com/PoTuStoronu222/Openwrt-Smartdns-DoH/main/test.sh" 2>/dev/null || \
        curl -fsSL "https://raw.githubusercontent.com/PoTuStoronu222/Openwrt-Smartdns-DoH/main/test.sh" -o "$MANAGER_PATH"
    fi
    chmod +x "$MANAGER_PATH"
    echo ""; echo "✅ Установлено! Запуск: dns-manager"; echo ""
    exec "$MANAGER_PATH"
}

CONFIG_FILE="/root/.dns-manager.conf"
DNS_CATALOG="/root/.dns-catalog.conf"
TEST_RESULTS="/root/.dns-test-results.conf"
VERSION="3.4-FINAL"

# ============================================================
# КАТАЛОГ: id|Название|URL|тип(bypass/clean)
# bypass = обходит блокировки (прокси/антизаглушки)
# clean  = чистый DNS без обхода
# ============================================================
create_catalog() {
    cat > "$DNS_CATALOG" << 'CATALOG'
#CATVER=3.4
#== ОБХОД БЛОКИРОВОК (российские анти-цензурные) ==
mafioznik|Mafioznik|https://dns.mafioznik.com/dns-query|bypass
comss_one|Comss.one|https://dns.comss.one/dns-query|bypass
comss_ru|Comss.ru|https://doh.comss.ru/dns-query|bypass
astrakat|Astrakat|https://dns.astrakat.com/dns-query|bypass
malw_link|Malw.link|https://dns.malw.link/dns-query|bypass
vppay|VPPay|https://dns.vppay.ru/dns-query|bypass
bluedns|BlueDNS|https://doh.bluedns.ru/dns-query|bypass
neutrdns|Neutrdns|https://dns.neutrdns.com/dns-query|bypass
dns_403|DNS.403|https://dns.403.online/dns-query|bypass
#== РУНЕТ (чистые, соблюдают РФ) ==
yandex|Yandex Basic|https://common.dot.dns.yandex.net/dns-query|clean
yandex_safe|Yandex Safe|https://safe.dns.yandex.ru/dns-query|clean
yandex_family|Yandex Family|https://family.dns.yandex.ru/dns-query|clean
skydns|SkyDNS|https://doh.skydns.ru/dns-query|clean
sber|Sber DNS|https://dns.sber.ru/dns-query|clean
#== ГЛОБАЛЬНЫЕ (чистые) ==
cloudflare|Cloudflare|https://cloudflare-dns.com/dns-query|clean
cloudflare_sec|CF Security|https://security.cloudflare-dns.com/dns-query|clean
cloudflare_fam|CF Family|https://family.cloudflare-dns.com/dns-query|clean
google|Google DNS|https://dns.google/dns-query|clean
quad9|Quad9|https://dns.quad9.net/dns-query|clean
quad9_unsec|Quad9 Unsecured|https://dns10.quad9.net/dns-query|clean
quad9_ecs|Quad9 ECS|https://dns11.quad9.net/dns-query|clean
opendns|OpenDNS|https://doh.opendns.com/dns-query|clean
opendns_fam|OpenDNS Family|https://doh.familyshield.opendns.com/dns-query|clean
#== PRIVACY / ADBLOCK (чистые) ==
adguard|AdGuard|https://dns.adguard-dns.com/dns-query|clean
adguard_fam|AdGuard Family|https://family.adguard-dns.com/dns-query|clean
adguard_unf|AdGuard Unfiltered|https://unfiltered.adguard-dns.com/dns-query|clean
controld_p0|ControlD Free|https://freedns.controld.com/p0|clean
controld_p1|ControlD Malware|https://freedns.controld.com/p1|clean
controld_p2|ControlD Ads+Mal|https://freedns.controld.com/p2|clean
controld_p3|ControlD Family|https://freedns.controld.com/p3|clean
mullvad|Mullvad|https://doh.mullvad.net/dns-query|clean
mullvad_adb|Mullvad Adblock|https://adblock.doh.mullvad.net/dns-query|clean
mullvad_ext|Mullvad Extended|https://extended.doh.mullvad.net/dns-query|clean
dns_sb|DNS.SB|https://doh.dns.sb/dns-query|clean
cleanbr_sec|CleanBrowsing Sec|https://doh.cleanbrowsing.org/doh/security-filter/|clean
cleanbr_fam|CleanBrowsing Fam|https://doh.cleanbrowsing.org/doh/family-filter/|clean
cleanbr_adu|CleanBrowsing Adult|https://doh.cleanbrowsing.org/doh/adult-filter/|clean
nextdns|NextDNS|https://dns.nextdns.io/dns-query|clean
rethinkdns|RethinkDNS|https://max.rethinkdns.com/dns-query|clean
decloudus|DeCloudUs|https://doh.decloudus.com/dns-query|clean
#== РЕГИОНАЛЬНЫЕ (чистые) ==
ahadns_nl|AhaDNS NL|https://doh.nl.ahadns.net/dns-query|clean
ahadns_es|AhaDNS ES|https://doh.es.ahadns.net/dns-query|clean
ahadns_in|AhaDNS IN|https://doh.in.ahadns.net/dns-query|clean
cznic|CZ.NIC (CZ)|https://odvr.nic.cz/doh|clean
digigesch|DigiGesellschaft CH|https://dns.digitale-gesellschaft.ch/dns-query|clean
switch_ch|Switch.ch (CH)|https://dns.switch.ch/dns-query|clean
libredns|LibreDNS (GR)|https://doh.libredns.gr/dns-query|clean
applied_at|AppliedPrivacy (AT)|https://doh.applied-privacy.net/query|clean
dnswatch|DNS.WATCH (DE)|https://resolver2.dns.watch/dns-query|clean
blahdns_de|BlahDNS DE|https://doh-de.blahdns.com/dns-query|clean
blahdns_fi|BlahDNS FI|https://doh-fi.blahdns.com/dns-query|clean
blahdns_jp|BlahDNS JP|https://doh-jp.blahdns.com/dns-query|clean
blahdns_sg|BlahDNS SG|https://doh-sg.blahdns.com/dns-query|clean
quad101|Quad101 (TW)|https://dns.twnic.tw/dns-query|clean
dnspod|DNSPod (CN)|https://doh.pub/dns-query|clean
alidns|AliDNS (CN)|https://dns.alidns.com/dns-query|clean
cira_ca|CIRA Shield (CA)|https://private.canadianshield.cira.ca/dns-query|clean
CATALOG
}

init_system() {
    printf '\033[0;34m=== Инициализация ===\033[0m\n'
    command -v apk >/dev/null 2>&1 && PKG="apk" || PKG="opkg"
    NEED=0
    command -v https-dns-proxy >/dev/null 2>&1 || NEED=1
    command -v curl >/dev/null 2>&1 || NEED=1
    if [ "$NEED" = "1" ]; then
        if [ "$PKG" = "apk" ]; then apk update && apk add https-dns-proxy ca-certificates curl bind-tools
        else opkg update && opkg install https-dns-proxy ca-certificates curl bind-dig; fi
    fi
    rm -f /etc/dnsmasq.d/telemetry.conf /etc/dnsmasq.d/.bogus-old /usr/bin/update-bogus-dns
    [ -f /etc/crontabs/root ] && sed -i '/update-bogus-dns/d' /etc/crontabs/root
    # Каталог обновляется по версии!
    if [ ! -f "$DNS_CATALOG" ] || ! grep -q "#CATVER=$CATVER" "$DNS_CATALOG"; then
        create_catalog
        printf '\033[0;32m[+] Каталог DNS обновлён (v%s)\033[0m\n' "$CATVER"
    fi
    printf '\033[0;32m[✓] Готово\033[0m\n'
}

load_config() {
    if [ -f "$CONFIG_FILE" ]; then . "$CONFIG_FILE"; fi
    : "${SLOT_1:=mafioznik}"; : "${SLOT_2:=comss_one}"; : "${SLOT_3:=astrakat}"
    : "${SLOT_4:=malw_link}"; : "${SLOT_5:=comss_ru}"; : "${SLOT_6:=vppay}"
    : "${SLOT_RU:=yandex}"; : "${SLOT_RU_2:=}"
    : "${BOOTSTRAP_DNS:=77.88.8.8,77.88.8.1,94.140.14.14,94.140.15.15,1.1.1.1,1.0.0.1,8.8.8.8,8.8.4.4,9.9.9.9,149.112.112.112}"
    : "${TLD_RU_ENABLED:=1}"; : "${BLOCK_QUIC:=0}"
    : "${MTU_FIX:=1}"; : "${NTP_REDIRECT:=1}"; : "${SYSCTL_TUNING:=1}"; : "${GO_OPTIMIZE:=1}"
    : "${BALANCER_ENABLED:=1}"; : "${NTP_PRESET:=mixed}"; : "${NTP_CUSTOM:=}"
}

save_config() {
    cat > "$CONFIG_FILE" << CONF
SLOT_1="$SLOT_1"
SLOT_2="$SLOT_2"
SLOT_3="$SLOT_3"
SLOT_4="$SLOT_4"
SLOT_5="$SLOT_5"
SLOT_6="$SLOT_6"
SLOT_RU="$SLOT_RU"
SLOT_RU_2="$SLOT_RU_2"
BOOTSTRAP_DNS="$BOOTSTRAP_DNS"
TLD_RU_ENABLED="$TLD_RU_ENABLED"
BLOCK_QUIC="$BLOCK_QUIC"
MTU_FIX="$MTU_FIX"
NTP_REDIRECT="$NTP_REDIRECT"
SYSCTL_TUNING="$SYSCTL_TUNING"
GO_OPTIMIZE="$GO_OPTIMIZE"
BALANCER_ENABLED="$BALANCER_ENABLED"
NTP_PRESET="$NTP_PRESET"
NTP_CUSTOM="$NTP_CUSTOM"
CONF
}

get_dns_field() {
    # $1=id, $2=номер поля
    grep -v '^#' "$DNS_CATALOG" | grep "^$1|" | head -1 | cut -d'|' -f"$2"
}
get_dns_name() {
    [ -z "$1" ] && { printf '(пусто)'; return; }
    echo "$1" | grep -q "^custom:" && { printf '(custom)'; return; }
    n=$(get_dns_field "$1" 2)
    [ -z "$n" ] && n="(неизвестный)"
    printf '%s' "$n"
}
get_dns_type() {
    t=$(get_dns_field "$1" 4)
    [ -z "$t" ] && t="clean"
    printf '%s' "$t"
}

# ============================================================
# НЕЗАВИСИМЫЙ резолв хоста через bootstrap (без локального DNS!)
# ============================================================
resolve_host() {
    _rh_host="$1"
    for _rh_bs in $(printf '%s' "$BOOTSTRAP_DNS" | tr ',' ' '); do
        _rh_ip=$(nslookup "$_rh_host" "$_rh_bs" 2>/dev/null | sed -n '/Name:/,$p' | grep -oE '([0-9]{1,3}\.){3}[0-9]{1,3}' | head -n1)
        if [ -n "$_rh_ip" ]; then printf '%s' "$_rh_ip"; return 0; fi
    done
    return 1
}

# ============================================================
# NTP (ТОЛЬКО IP — работает без DNS!)
# ============================================================
get_ntp_servers() {
    case "$1" in
        cloudflare)  echo "162.159.200.1 162.159.200.123" ;;
        google)      echo "216.239.35.0 216.239.35.4 216.239.35.8 216.239.35.12" ;;
        ntp_pool)    echo "162.159.200.1 216.239.35.0 129.6.15.28 129.6.15.29" ;;
        ru_vniiftri) echo "194.190.168.1 89.109.251.21 92.255.126.1 217.79.0.30" ;;
        ru_ps)       echo "194.190.168.1 194.85.252.2 92.255.126.1" ;;
        mixed)       echo "162.159.200.1 216.239.35.0 89.109.251.21 92.255.126.1 194.190.168.1 129.250.35.250" ;;
        dhcp)        echo "" ;;
        custom)      echo "$2" ;;
        *)           echo "162.159.200.1 216.239.35.0 89.109.251.21" ;;
    esac
}
get_ntp_preset_name() {
    case "$1" in
        cloudflare)  echo "Cloudflare (IP)" ;;
        google)      echo "Google Time (IP)" ;;
        ntp_pool)    echo "NTP Pool (IP)" ;;
        ru_vniiftri) echo "ВНИИФТРИ (RU, атомные)" ;;
        ru_ps)       echo "Российские (IP)" ;;
        mixed)       echo "Смешанный CF+Google+RU [рек]" ;;
        dhcp)        echo "От провайдера (DHCP)" ;;
        custom)      echo "Свой список" ;;
        *)           echo "Неизвестный" ;;
    esac
}

# ============================================================
# ВОЗВРАТ В СТОК
# ============================================================
menu_reset_to_stock() {
    clear
    printf '\033[0;31m╔══════════════════════════════════════════╗\033[0m\n'
    printf '\033[0;31m║   ⚠ ВОЗВРАТ В СТОК (заводское состояние) ║\033[0m\n'
    printf '\033[0;31m╚══════════════════════════════════════════╝\033[0m\n'
    echo ""
    printf '\033[1;33mБудет удалено:\033[0m все DoH-слоты, anti-block, sysctl,\n'
    printf 'MTU Fix, NTP Redirect, QUIC, конфиг менеджера.\n'
    printf '\033[0;32mОстанется:\033[0m Tailscale, tg-ws-proxy, Zapret, WiFi, WAN.\n\n'
    printf 'Введите \033[0;32mсток\033[0m (или stock / y) для подтверждения: '
    read -r confirm
    conf_lc=$(printf '%s' "$confirm" | tr 'A-Z' 'a-z')
    case "$conf_lc" in
        сток|stock|y|s|да) : ;;
        *) printf '\033[1;33mОтменено.\033[0m\n'; sleep 1; return ;;
    esac

    echo ""
    printf '[1/6] Остановка DoH...\n'
    killall -9 https-dns-proxy 2>/dev/null
    /etc/init.d/https-dns-proxy stop 2>/dev/null

    printf '[2/6] Сброс dnsmasq к стоку...\n'
    while uci -q delete dhcp.@dnsmasq[0].server; do :; done
    uci -q delete dhcp.@dnsmasq[0].address 2>/dev/null
    uci -q delete dhcp.@dnsmasq[0].confdir 2>/dev/null
    uci -q delete dhcp.@dnsmasq[0].allservers 2>/dev/null
    uci -q delete dhcp.@dnsmasq[0].strictorder 2>/dev/null
    uci -q delete dhcp.@dnsmasq[0].noresolv 2>/dev/null
    uci -q delete dhcp.@dnsmasq[0].cachesize 2>/dev/null
    uci -q delete dhcp.@dnsmasq[0].dnsforwardmax 2>/dev/null
    uci -q delete dhcp.@dnsmasq[0].max_cache_ttl 2>/dev/null
    uci -q delete dhcp.@dnsmasq[0].quietdhcp 2>/dev/null
    for opt in $(uci -q get dhcp.lan.dhcp_option 2>/dev/null | tr ' ' '\n' | grep '^42,'); do
        uci -q del_list dhcp.lan.dhcp_option="$opt"
    done
    uci commit dhcp

    printf '[3/6] Сброс firewall...\n'
    uci -q delete firewall.redirect_ntp
    uci -q delete firewall.block_quic
    uci -q delete firewall.@defaults[0].mtu_fix
    WAN_SEC=$(uci show firewall 2>/dev/null | grep -m1 "\.name='wan'" | cut -d. -f1,2)
    [ -n "$WAN_SEC" ] && uci -q delete "${WAN_SEC}.mtu_fix"
    uci commit firewall

    printf '[4/6] NTP к стоку...\n'
    while uci -q delete system.@timeserver[0]; do :; done
    uci -q delete system.ntp 2>/dev/null
    uci set system.ntp=timeserver
    uci set system.ntp.enabled='1'
    uci set system.ntp.enable_server='0'
    uci add_list system.ntp.server='0.openwrt.pool.ntp.org'
    uci add_list system.ntp.server='1.openwrt.pool.ntp.org'
    uci add_list system.ntp.server='2.openwrt.pool.ntp.org'
    uci add_list system.ntp.server='3.openwrt.pool.ntp.org'
    uci commit system

    printf '[5/6] Удаление артефактов...\n'
    rm -f /etc/dnsmasq.d/anti-block.conf
    rm -f /etc/sysctl.d/99-custom.conf
    rm -f /etc/hotplug.d/ntp/99-tailscale
    rm -f /root/rollback-dns.sh
    rm -f "$CONFIG_FILE" "$DNS_CATALOG" "$TEST_RESULTS"
    while uci -q delete https-dns-proxy.@https-dns-proxy[0]; do :; done
    uci commit https-dns-proxy

    printf '[6/6] Применение + перезагрузка...\n'
    sysctl -p /etc/sysctl.conf >/dev/null 2>&1
    /etc/init.d/firewall restart 2>/dev/null
    /etc/init.d/dnsmasq restart
    /etc/init.d/sysntpd restart 2>/dev/null
    echo ""
    printf '\033[0;32m✅ СТОК ВОССТАНОВЛЕН! Перезагрузка через 5 сек...\033[0m\n'
    sleep 5
    reboot
    exit 0
}

# ============================================================
# ПРОФИЛИ (8 штук, все с оптимизациями)
# ============================================================
menu_profile_default() {
    clear
    printf '\033[0;34m╔══════════════════════════════════════════╗\033[0m\n'
    printf '\033[0;34m║     Быстрая настройка (8 профилей)      ║\033[0m\n'
    printf '\033[0;34m╚══════════════════════════════════════════╝\033[0m\n'
    echo ""
    printf '  \033[0;32m1) Оптимальный [рекомендуется]\033[0m\n'
    printf '     4 обходных DNS + Yandex RU\n'
    printf '     Оптимизации: QUIC+MTU+NTP+sysctl+Go\n\n'
    printf '  2) Максимум устойчивости\n'
    printf '     6 обходных + 2 РУ (Yandex+Safe)\n'
    printf '     Оптимизации: QUIC+MTU+NTP+sysctl+Go\n\n'
    printf '  3) Одна голова (слабый роутер)\n'
    printf '     1 DNS, балансир ВЫКЛ, sysctl ВЫКЛ\n'
    printf '     Оптимизации: MTU+NTP+Go\n\n'
    printf '  4) Только рунет\n'
    printf '     Только Yandex для .ru, без обхода\n'
    printf '     Оптимизации: MTU+NTP+sysctl+Go\n\n'
    printf '  5) Семейный\n'
    printf '     AdGuard Fam + CF Fam + CleanBrows Fam\n'
    printf '     РУ: Yandex Family. QUIC вкл\n'
    printf '     Оптимизации: QUIC+MTU+NTP+sysctl+Go\n\n'
    printf '  6) Приватный\n'
    printf '     AdGuard Unf + Mullvad + Quad9 Unsec\n'
    printf '     Оптимизации: QUIC+MTU+NTP+sysctl+Go\n\n'
    printf '  7) Чистый (без обхода)\n'
    printf '     Cloudflare+Google+Quad9+OpenDNS\n'
    printf '     Оптимизации: MTU+NTP+sysctl+Go\n\n'
    printf '  8) Быстрый (минимальные пинги)\n'
    printf '     Mafioznik+Comss.ru+DNS.403+BlueDNS\n'
    printf '     Оптимизации: QUIC+MTU+NTP+sysctl+Go\n\n'
    printf '  \033[0;36mEnter\033[0m = отмена\n\n'
    printf 'Выбор: '
    read -r choice
    [ -z "$choice" ] && return

    # общие значения по умолчанию для всех профилей
    BOOTSTRAP_DNS="77.88.8.8,77.88.8.1,94.140.14.14,94.140.15.15,1.1.1.1,1.0.0.1,8.8.8.8,8.8.4.4,9.9.9.9,149.112.112.112"
    TLD_RU_ENABLED="1"; MTU_FIX="1"; NTP_REDIRECT="1"; NTP_PRESET="mixed"; GO_OPTIMIZE="1"
    SYSCTL_TUNING="1"; BLOCK_QUIC="1"; BALANCER_ENABLED="1"

    case "$choice" in
        1) SLOT_1="mafioznik"; SLOT_2="comss_ru"; SLOT_3="comss_one"; SLOT_4="vppay"
           SLOT_5=""; SLOT_6=""; SLOT_RU="yandex"; SLOT_RU_2="" ;;
        2) SLOT_1="mafioznik"; SLOT_2="comss_one"; SLOT_3="astrakat"; SLOT_4="malw_link"
           SLOT_5="comss_ru"; SLOT_6="vppay"; SLOT_RU="yandex"; SLOT_RU_2="yandex_safe" ;;
        3) SLOT_1="mafioznik"; SLOT_2=""; SLOT_3=""; SLOT_4=""; SLOT_5=""; SLOT_6=""
           SLOT_RU="yandex"; SLOT_RU_2=""
           BALANCER_ENABLED="0"; BLOCK_QUIC="0"; SYSCTL_TUNING="0" ;;
        4) SLOT_1=""; SLOT_2=""; SLOT_3=""; SLOT_4=""; SLOT_5=""; SLOT_6=""
           SLOT_RU="yandex"; SLOT_RU_2=""
           BALANCER_ENABLED="0"; BLOCK_QUIC="0" ;;
        5) SLOT_1="adguard_fam"; SLOT_2="cloudflare_fam"; SLOT_3="cleanbr_fam"
           SLOT_4=""; SLOT_5=""; SLOT_6=""; SLOT_RU="yandex_family"; SLOT_RU_2="" ;;
        6) SLOT_1="adguard_unf"; SLOT_2="mullvad"; SLOT_3="quad9_unsec"; SLOT_4="nextdns"
           SLOT_5=""; SLOT_6=""; SLOT_RU="yandex"; SLOT_RU_2="" ;;
        7) SLOT_1="cloudflare"; SLOT_2="google"; SLOT_3="quad9"; SLOT_4="opendns"
           SLOT_5=""; SLOT_6=""; SLOT_RU="yandex"; SLOT_RU_2=""
           BLOCK_QUIC="0" ;;
        8) SLOT_1="mafioznik"; SLOT_2="comss_ru"; SLOT_3="dns_403"; SLOT_4="bluedns"
           SLOT_5=""; SLOT_6=""; SLOT_RU="yandex"; SLOT_RU_2="" ;;
        *) printf '\033[0;31m[!] Неверный выбор\033[0m\n'; sleep 1; return ;;
    esac

    save_config
    printf '\033[0;32m[✓] Профиль сохранён\033[0m\n'
    printf 'Применить сейчас? [y/n]: '
    read -r confirm
    case "$confirm" in
        n|N) printf 'Примените вручную через пункт 8.\n'; sleep 2 ;;
        *) apply_settings ;;
    esac
}

# ============================================================
# ТЕСТ ВСЕХ DNS (НЕЗАВИСИМЫЙ от локального DoH!)
# ============================================================
menu_test_dns() {
    clear
    printf '\033[0;34m╔══════════════════════════════════════════╗\033[0m\n'
    printf '\033[0;34m║  Тест всех DNS (независимо от DoH)      ║\033[0m\n'
    printf '\033[0;34m╚══════════════════════════════════════════╝\033[0m\n'
    echo ""
    printf '\033[1;33mХосты резолвятся через bootstrap-IP,\033[0m\n'
    printf '\033[1;33mcurl идёт через --resolve. Локальный DoH не участвует.\033[0m\n'
    echo ""
    printf '%-20s %-8s %-9s %-9s %s\n' "DNS" "Тип" "Статус" "Скорость" "Примечание"
    printf '%s\n' "---------------------------------------------------------------------------"

    > "$TEST_RESULTS"
    grep -v '^#' "$DNS_CATALOG" | grep '|' | while IFS='|' read -r id name url dtype; do
        [ -z "$id" ] && continue
        host=$(printf '%s' "$url" | sed 's|^https://||; s|/.*$||')
        ip=$(resolve_host "$host")
        if [ -z "$ip" ]; then
            printf '%-20s %-8s \033[0;31mFAIL\033[0m   %-9s %s\n' "$name" "$dtype" "-" "bootstrap не резолвит"
            echo "${id}|0|FAIL" >> "$TEST_RESULTS"
            continue
        fi
        t=$(curl -s -o /dev/null -w '%{time_total}' --max-time 5 \
            --resolve "$host:443:$ip" \
            "${url}?name=google.com&type=A" -H 'Accept: application/dns-json' 2>/dev/null)
        if [ -n "$t" ] && [ "$t" != "0.000000" ]; then
            ms=$(echo "$t" | awk '{printf "%.0f", $1 * 1000}')
            if [ "$ms" -lt 100 ]; then note="Быстрый"
            elif [ "$ms" -lt 300 ]; then note="Норм"
            else note="Медленный"; fi
            printf '%-20s %-8s \033[0;32mOK\033[0m     %-9s %s\n' "$name" "$dtype" "${ms}ms" "$note"
            echo "${id}|${ms}|OK" >> "$TEST_RESULTS"
        else
            printf '%-20s %-8s \033[0;31mFAIL\033[0m   %-9s %s\n' "$name" "$dtype" "-" "DoH не ответил"
            echo "${id}|0|FAIL" >> "$TEST_RESULTS"
        fi
    done

    echo ""
    printf '%s\n' "---------------------------------------------------------------------------"
    total=$(wc -l < "$TEST_RESULTS" 2>/dev/null)
    ok=$(grep -c '|OK' "$TEST_RESULTS" 2>/dev/null)
    fail=$(grep -c '|FAIL' "$TEST_RESULTS" 2>/dev/null)
    printf 'Всего: %s | \033[0;32mOK: %s\033[0m | \033[0;31mFAIL: %s\033[0m\n' "$total" "$ok" "$fail"
    echo ""
    printf 'Нажмите Enter...'
    read -r _
}

# ============================================================
# Выбор DNS для слота (с фильтром bypass/clean)
# ============================================================
SELECT_FILTER="all"

build_select_list() {
    grep -v '^#' "$DNS_CATALOG" | grep '|' > /tmp/.dns_all
    case "$SELECT_FILTER" in
        bypass) grep '|bypass$' /tmp/.dns_all > /tmp/.dns_sel ;;
        clean)  grep '|clean$' /tmp/.dns_all > /tmp/.dns_sel ;;
        *)      cat /tmp/.dns_all > /tmp/.dns_sel ;;
    esac
}

select_dns_for_slot() {
    slot_num="$1"
    while true; do
        clear
        build_select_list
        printf '\033[0;34m╔══════════════════════════════════════════╗\033[0m\n'
        printf '\033[0;34m║     Выбор DNS для слота #%-15s║\033[0m\n' "$slot_num"
        printf '\033[0;34m╚══════════════════════════════════════════╝\033[0m\n'
        echo ""
        case "$SELECT_FILTER" in
            bypass) fstr="только ОБХОД" ;;
            clean)  fstr="только ЧИСТЫЕ" ;;
            *)      fstr="все" ;;
        esac
        printf 'Фильтр: \033[1;33m%s\033[0m\n\n' "$fstr"

        i=1
        while IFS='|' read -r id name url dtype; do
            [ -z "$id" ] && continue
            tr_line=$(grep "^${id}|" "$TEST_RESULTS" 2>/dev/null | head -1)
            if [ -n "$tr_line" ]; then
                ms=$(printf '%s' "$tr_line" | cut -d'|' -f2)
                st=$(printf '%s' "$tr_line" | cut -d'|' -f3)
                if [ "$st" = "OK" ]; then
                    printf '  %2d) %-19s \033[0;32m[обход]\033[0m \033[0;32m%5sms\033[0m\n' "$i" "$name" "$ms" 2>/dev/null || true
                    # перерисуем с учётом типа
                fi
            fi
            i=$((i+1))
        done < /tmp/.dns_sel

        # (чистая перерисовка без дублей)
        i=1
        while IFS='|' read -r id name url dtype; do
            [ -z "$id" ] && continue
            if [ "$dtype" = "bypass" ]; then tag="\033[0;32mобход\033[0m "
            else tag="\033[0;36mчистый\033[0m"; fi
            tr_line=$(grep "^${id}|" "$TEST_RESULTS" 2>/dev/null | head -1)
            if [ -n "$tr_line" ]; then
                ms=$(printf '%s' "$tr_line" | cut -d'|' -f2)
                st=$(printf '%s' "$tr_line" | cut -d'|' -f3)
                if [ "$st" = "OK" ]; then
                    printf '  %2d) %-19s %b \033[0;32m%5sms\033[0m\n' "$i" "$name" "$tag" "$ms"
                else
                    printf '  %2d) %-19s %b \033[0;31m FAIL\033[0m\n' "$i" "$name" "$tag"
                fi
            else
                printf '  %2d) %-19s %b \033[1;33m нет теста\033[0m\n' "$i" "$name" "$tag"
            fi
            i=$((i+1))
        done < /tmp/.dns_sel

        echo ""
        printf '  \033[0;36m99) Очистить слот\033[0m\n'
        printf '  \033[0;36m98) Свой URL\033[0m\n'
        printf '  \033[0;36m95) Фильтр: %s\033[0m\n' "$fstr"
        printf '  \033[0;36mEnter) Отмена\033[0m\n\n'
        printf 'Выбор: '
        read -r choice
        [ -z "$choice" ] && return

        case "$choice" in
            99) eval "SLOT_${slot_num}='\"\"'"; save_config; return ;;
            98) printf 'URL DoH: '; read -r cu
                [ -n "$cu" ] && { eval "SLOT_${slot_num}=\"custom:$cu\""; save_config; }
                return ;;
            95) case "$SELECT_FILTER" in
                    all) SELECT_FILTER="bypass" ;;
                    bypass) SELECT_FILTER="clean" ;;
                    *) SELECT_FILTER="all" ;;
                esac ;;
            *)
                total=$(wc -l < /tmp/.dns_sel)
                if [ "$choice" -ge 1 ] 2>/dev/null && [ "$choice" -le "$total" ] 2>/dev/null; then
                    sel_id=$(sed -n "${choice}p" /tmp/.dns_sel | cut -d'|' -f1)
                    eval "SLOT_${slot_num}=\"$sel_id\""
                    save_config
                    return
                fi
                printf '\033[0;31m[!] Неверный\033[0m\n'; sleep 1
                ;;
        esac
    done
}

menu_slots() {
    while true; do
        clear
        printf '\033[0;34m╔══════════════════════════════════════════╗\033[0m\n'
        printf '\033[0;34m║     Настройка слотов DNS                ║\033[0m\n'
        printf '\033[0;34m╚══════════════════════════════════════════╝\033[0m\n'
        echo ""
        printf '\033[1;33mСлоты 1-6: Весь интернет\033[0m\n'
        printf '  1) Слот 1 (5053): %s [%s]\n' "$(get_dns_name "$SLOT_1")" "$(get_dns_type "$SLOT_1")"
        printf '  2) Слот 2 (5054): %s [%s]\n' "$(get_dns_name "$SLOT_2")" "$(get_dns_type "$SLOT_2")"
        printf '  3) Слот 3 (5055): %s [%s]\n' "$(get_dns_name "$SLOT_3")" "$(get_dns_type "$SLOT_3")"
        printf '  4) Слот 4 (5056): %s [%s]\n' "$(get_dns_name "$SLOT_4")" "$(get_dns_type "$SLOT_4")"
        printf '  5) Слот 5 (5057): %s [%s]\n' "$(get_dns_name "$SLOT_5")" "$(get_dns_type "$SLOT_5")"
        printf '  6) Слот 6 (5058): %s [%s]\n' "$(get_dns_name "$SLOT_6")" "$(get_dns_type "$SLOT_6")"
        echo ""
        printf '\033[1;33mСлоты РУ: рунет\033[0m\n'
        printf '  7) Слот РУ   (5059): %s\n' "$(get_dns_name "$SLOT_RU")"
        printf '  8) Слот РУ-2 (5060): %s\n' "$(get_dns_name "$SLOT_RU_2")"
        echo ""
        printf '  \033[0;36mEnter) Назад\033[0m\n'
        printf 'Выбор: '; read -r choice
        [ -z "$choice" ] && return
        case "$choice" in
            1) select_dns_for_slot "1" ;; 2) select_dns_for_slot "2" ;;
            3) select_dns_for_slot "3" ;; 4) select_dns_for_slot "4" ;;
            5) select_dns_for_slot "5" ;; 6) select_dns_for_slot "6" ;;
            7) select_dns_for_slot "RU" ;; 8) select_dns_for_slot "RU_2" ;;
            *) printf '\033[0;31m[!] Неверный\033[0m\n'; sleep 1 ;;
        esac
    done
}

menu_bootstrap() {
    while true; do
        clear
        printf '\033[0;34m╔══════════════════════════════════════════╗\033[0m\n'
        printf '\033[0;34m║     Bootstrap DNS                       ║\033[0m\n'
        printf '\033[0;34m╚══════════════════════════════════════════╝\033[0m\n'
        echo ""
        printf 'Текущий: \033[1;33m%s\033[0m\n\n' "$BOOTSTRAP_DNS"
        printf '  1) Полный (10 IP: Yandex+AdGuard+CF+Google+Quad9) [рек]\n'
        printf '  2) РФ Безопасный (Yandex+AdGuard, 4 IP)\n'
        printf '  3) Только Yandex\n'
        printf '  4) Только AdGuard\n'
        printf '  5) Ввести вручную\n'
        printf '  \033[0;36mEnter) Назад\033[0m\n'
        printf 'Выбор: '; read -r choice
        [ -z "$choice" ] && return
        case "$choice" in
            1) BOOTSTRAP_DNS="77.88.8.8,77.88.8.1,94.140.14.14,94.140.15.15,1.1.1.1,1.0.0.1,8.8.8.8,8.8.4.4,9.9.9.9,149.112.112.112"; save_config; return ;;
            2) BOOTSTRAP_DNS="77.88.8.8,77.88.8.1,94.140.14.14,94.140.15.15"; save_config; return ;;
            3) BOOTSTRAP_DNS="77.88.8.8,77.88.8.1"; save_config; return ;;
            4) BOOTSTRAP_DNS="94.140.14.14,94.140.15.15"; save_config; return ;;
            5) printf 'IP через запятую: '; read -r BOOTSTRAP_DNS; [ -n "$BOOTSTRAP_DNS" ] && save_config; return ;;
        esac
    done
}

menu_ntp() {
    while true; do
        clear
        printf '\033[0;34m╔══════════════════════════════════════════╗\033[0m\n'
        printf '\033[0;34m║  NTP серверы (ТОЛЬКО IP, без DNS)       ║\033[0m\n'
        printf '\033[0;34m╚══════════════════════════════════════════╝\033[0m\n'
        echo ""
        printf 'Текущий: \033[1;33m%s\033[0m\n\n' "$(get_ntp_preset_name "$NTP_PRESET")"
        for srv in $(get_ntp_servers "$NTP_PRESET" "$NTP_CUSTOM"); do
            printf '  • %s\n' "$srv"
        done
        echo ""
        printf '  1) Смешанный CF+Google+RU [рек]\n'
        printf '  2) Cloudflare (IP)\n'
        printf '  3) Google Time (IP)\n'
        printf '  4) NTP Pool (IP)\n'
        printf '  5) ВНИИФТРИ (RU, атомные)\n'
        printf '  6) Российские (IP)\n'
        printf '  7) От провайдера (DHCP)\n'
        printf '  8) Свой список\n'
        printf '  \033[0;36mEnter) Назад\033[0m\n'
        printf 'Выбор: '; read -r choice
        [ -z "$choice" ] && return
        case "$choice" in
            1) NTP_PRESET="mixed" ;; 2) NTP_PRESET="cloudflare" ;;
            3) NTP_PRESET="google" ;; 4) NTP_PRESET="ntp_pool" ;;
            5) NTP_PRESET="ru_vniiftri" ;; 6) NTP_PRESET="ru_ps" ;;
            7) NTP_PRESET="dhcp" ;;
            8) printf 'IP через пробел: '; read -r NTP_CUSTOM; NTP_PRESET="custom" ;;
            *) return ;;
        esac
        save_config
    done
}

menu_extras() {
    while true; do
        clear
        printf '\033[0;34m╔══════════════════════════════════════════╗\033[0m\n'
        printf '\033[0;34m║     Дополнительные настройки            ║\033[0m\n'
        printf '\033[0;34m╚══════════════════════════════════════════╝\033[0m\n'
        echo ""
        [ "$BALANCER_ENABLED" = "1" ] && b1="\033[0;32m[✓]\033[0m" || b1="\033[0;31m[ ]\033[0m"
        [ "$TLD_RU_ENABLED" = "1" ] && b2="\033[0;32m[✓]\033[0m" || b2="\033[0;31m[ ]\033[0m"
        [ "$BLOCK_QUIC" = "1" ] && b3="\033[0;32m[✓]\033[0m" || b3="\033[0;31m[ ]\033[0m"
        [ "$MTU_FIX" = "1" ] && b4="\033[0;32m[✓]\033[0m" || b4="\033[0;31m[ ]\033[0m"
        [ "$NTP_REDIRECT" = "1" ] && b5="\033[0;32m[✓]\033[0m" || b5="\033[0;31m[ ]\033[0m"
        [ "$SYSCTL_TUNING" = "1" ] && b6="\033[0;32m[✓]\033[0m" || b6="\033[0;31m[ ]\033[0m"
        [ "$GO_OPTIMIZE" = "1" ] && b7="\033[0;32m[✓]\033[0m" || b7="\033[0;31m[ ]\033[0m"
        printf '  1) %b Балансировщик (allservers=1)\n' "$b1"
        printf '  2) %b TLD Split (.ru через слот РУ)\n' "$b2"
        printf '  3) %b Блокировка QUIC (UDP 443)\n' "$b3"
        printf '  4) %b MTU Fix (PPPoE/L2TP)\n' "$b4"
        printf '  5) %b NTP Redirect\n' "$b5"
        printf '  6) %b Sysctl Tuning\n' "$b6"
        printf '  7) %b Go-оптимизация (Tailscale, tg-ws-proxy)\n' "$b7"
        echo ""
        printf '  8) \033[1;33m→ NTP серверы: %s\033[0m\n' "$(get_ntp_preset_name "$NTP_PRESET")"
        printf '  \033[0;36mEnter) Назад\033[0m\n'
        printf 'Выбор: '; read -r choice
        [ -z "$choice" ] && return
        case "$choice" in
            1) [ "$BALANCER_ENABLED" = "1" ] && BALANCER_ENABLED="0" || BALANCER_ENABLED="1"; save_config ;;
            2) [ "$TLD_RU_ENABLED" = "1" ] && TLD_RU_ENABLED="0" || TLD_RU_ENABLED="1"; save_config ;;
            3) [ "$BLOCK_QUIC" = "1" ] && BLOCK_QUIC="0" || BLOCK_QUIC="1"; save_config ;;
            4) [ "$MTU_FIX" = "1" ] && MTU_FIX="0" || MTU_FIX="1"; save_config ;;
            5) [ "$NTP_REDIRECT" = "1" ] && NTP_REDIRECT="0" || NTP_REDIRECT="1"; save_config ;;
            6) [ "$SYSCTL_TUNING" = "1" ] && SYSCTL_TUNING="0" || SYSCTL_TUNING="1"; save_config ;;
            7) [ "$GO_OPTIMIZE" = "1" ] && GO_OPTIMIZE="0" || GO_OPTIMIZE="1"; save_config ;;
            8) menu_ntp ;;
        esac
    done
}

menu_antiblock() {
    while true; do
        clear
        printf '\033[0;34m╔══════════════════════════════════════════╗\033[0m\n'
        printf '\033[0;34m║     Anti-block                          ║\033[0m\n'
        printf '\033[0;34m╚══════════════════════════════════════════╝\033[0m\n'
        echo ""
        grep "bogus-nxdomain=" /etc/dnsmasq.d/anti-block.conf 2>/dev/null | sed 's/bogus-nxdomain=/  /' || printf '  (пусто)\n'
        echo ""
        printf '  1) Добавить IP\n  2) Удалить IP\n  3) Сброс к эталону\n'
        printf '  \033[0;36mEnter) Назад\033[0m\n'
        printf 'Выбор: '; read -r choice
        [ -z "$choice" ] && return
        case "$choice" in
            1) printf 'IP: '; read -r ip
               [ -n "$ip" ] && { echo "bogus-nxdomain=$ip" >> /etc/dnsmasq.d/anti-block.conf; /etc/init.d/dnsmasq restart; } ;;
            2) printf 'IP: '; read -r ip
               [ -n "$ip" ] && { sed -i "/bogus-nxdomain=$ip/d" /etc/dnsmasq.d/anti-block.conf; /etc/init.d/dnsmasq restart; } ;;
            3) cat > /etc/dnsmasq.d/anti-block.conf << 'ANTIBLOCK'
no-negcache
bogus-nxdomain=185.179.189.20
bogus-nxdomain=195.208.1.1
bogus-nxdomain=95.167.13.50
bogus-nxdomain=95.182.120.241
bogus-nxdomain=87.241.223.133
bogus-nxdomain=77.37.254.90
bogus-nxdomain=62.33.207.195
bogus-nxdomain=45.155.204.190
bogus-nxdomain=37.230.192.51
bogus-nxdomain=0.0.0.0
bogus-nxdomain=127.0.0.1
ANTIBLOCK
               /etc/init.d/dnsmasq restart ;;
        esac
    done
}

# ============================================================
# ПРИМЕНЕНИЕ (11 шагов)
# ============================================================
apply_settings() {
    clear
    printf '\033[0;34m╔══════════════════════════════════════════╗\033[0m\n'
    printf '\033[0;34m║     Применение настроек                 ║\033[0m\n'
    printf '\033[0;34m╚══════════════════════════════════════════╝\033[0m\n\n'

    printf '[1/11] Бэкапы...\n'
    if [ ! -d /etc/config/backup-original ]; then
        mkdir -p /etc/config/backup-original
        for f in dhcp firewall https-dns-proxy system; do
            cp /etc/config/$f /etc/config/backup-original/$f.bak 2>/dev/null
        done
    fi
    TS=$(date +%Y%m%d_%H%M%S)
    BA="/etc/config/backup-dns-$TS"
    mkdir -p "$BA"
    for f in dhcp firewall https-dns-proxy system; do
        cp /etc/config/$f "$BA/$f.bak" 2>/dev/null
    done
    ln -sfn "$BA" /etc/config/backup-pre-dns-v9
    (cd /etc/config && ls -dt backup-dns-* 2>/dev/null | tail -n +2 | xargs rm -rf 2>/dev/null)

    printf '[2/11] Anti-block...\n'
    [ ! -f /etc/dnsmasq.d/anti-block.conf ] && cat > /etc/dnsmasq.d/anti-block.conf << 'ANTIBLOCK'
no-negcache
bogus-nxdomain=185.179.189.20
bogus-nxdomain=195.208.1.1
bogus-nxdomain=95.167.13.50
bogus-nxdomain=95.182.120.241
bogus-nxdomain=87.241.223.133
bogus-nxdomain=77.37.254.90
bogus-nxdomain=62.33.207.195
bogus-nxdomain=45.155.204.190
bogus-nxdomain=37.230.192.51
bogus-nxdomain=0.0.0.0
bogus-nxdomain=127.0.0.1
ANTIBLOCK

    if [ "$MTU_FIX" = "1" ]; then
        printf '[3/11] MTU Fix...\n'
        uci -q set firewall.@defaults[0].mtu_fix='1'
        WS=$(uci show firewall 2>/dev/null | grep -m1 "\.name='wan'" | cut -d. -f1,2)
        [ -n "$WS" ] && uci -q set "${WS}.mtu_fix=1"
        uci commit firewall
    fi

    if [ "$NTP_REDIRECT" = "1" ]; then
        printf '[4/11] NTP (IP only)...\n'
        LAN_IP=$(uci -q get network.lan.ipaddr | cut -d'/' -f1 | awk '{print $1}')
        [ -z "$LAN_IP" ] || [ "$LAN_IP" = "0.0.0.0" ] && LAN_IP="192.168.1.1"
        for opt in $(uci -q get dhcp.lan.dhcp_option 2>/dev/null | tr ' ' '\n' | grep '^42,'); do
            uci -q del_list dhcp.lan.dhcp_option="$opt"
        done
        uci add_list dhcp.lan.dhcp_option="42,$LAN_IP"
        uci commit dhcp
        for sec in $(uci show firewall 2>/dev/null | grep -E "dest_port='123'|src_dport='123'|Redirect-NTP" | cut -d. -f2 | cut -d= -f1 | sort -u); do
            uci -q delete firewall."$sec"
        done
        [ -f /usr/share/fw4/helpers.sh ] && FW="fw4" || FW="fw3"
        uci set firewall.redirect_ntp=redirect
        uci set firewall.redirect_ntp.name='Redirect-NTP'
        uci set firewall.redirect_ntp.src='lan'
        uci set firewall.redirect_ntp.proto='udp'
        uci set firewall.redirect_ntp.src_dport='123'
        uci set firewall.redirect_ntp.dest_port='123'
        uci set firewall.redirect_ntp.dest_ip="$LAN_IP"
        uci set firewall.redirect_ntp.target='DNAT'
        [ "$FW" = "fw4" ] && uci set firewall.redirect_ntp.family='ipv4'
        uci commit firewall
        ns=$(get_ntp_servers "$NTP_PRESET" "$NTP_CUSTOM")
        while uci -q delete system.@timeserver[0]; do :; done
        uci -q delete system.ntp 2>/dev/null
        uci set system.ntp=timeserver
        uci set system.ntp.enabled='1'
        if [ "$NTP_PRESET" = "dhcp" ] || [ -z "$ns" ]; then
            uci set system.ntp.enable_server='1'
        else
            for srv in $ns; do uci add_list system.ntp.server="$srv"; done
        fi
        uci commit system
    fi

    if [ "$GO_OPTIMIZE" = "1" ]; then
        printf '[5/11] Go-оптимизация...\n'
        for f in /etc/init.d/tg-ws-proxy-go /etc/init.d/tailscale; do
            [ ! -f "$f" ] && continue
            sed -i '/GOMAXPROCS/d; /GOMEMLIMIT/d; /GOGC/d' "$f"
            if grep -q "procd_open_instance" "$f"; then
                if [ "$f" = "/etc/init.d/tg-ws-proxy-go" ]; then ENVV="GOMAXPROCS=1 GOMEMLIMIT=50MiB"
                else ENVV="GOMEMLIMIT=85MiB"; fi
                awk -v ev="$ENVV" '/procd_open_instance/ {print; print "    procd_set_param env " ev; next} 1' "$f" > /tmp/.tgi && mv /tmp/.tgi "$f"
            fi
        done
    fi

    if [ "$SYSCTL_TUNING" = "1" ]; then
        printf '[6/11] Sysctl...\n'
        modprobe nf_conntrack 2>/dev/null
        SF="/etc/sysctl.d/99-custom.conf"; touch "$SF"
        for p in "net.netfilter.nf_conntrack_max=65536" "net.ipv4.tcp_fastopen=3" "net.ipv4.tcp_fin_timeout=15" "net.core.somaxconn=1024" "net.ipv4.tcp_keepalive_time=300" "net.core.rmem_max=2097152" "net.core.wmem_max=2097152"; do
            k=$(echo "$p" | cut -d= -f1)
            sed -i "/^$k/d" "$SF"; echo "$p" >> "$SF"
            sysctl -w "$p" >/dev/null 2>&1
        done
    fi

    if [ -f /etc/init.d/tailscale ]; then
        printf '[7/11] Hotplug tailscale...\n'
        mkdir -p /etc/hotplug.d/ntp
        cat > /etc/hotplug.d/ntp/99-tailscale << 'HOTPLUG'
#!/bin/sh
[ "$ACTION" = "step" ] || [ "$ACTION" = "stratum" ] || exit 0
UPTIME=$(cut -d. -f1 /proc/uptime)
[ "$UPTIME" -lt 600 ] && /etc/init.d/tailscale restart >/dev/null 2>&1
HOTPLUG
        chmod +x /etc/hotplug.d/ntp/99-tailscale
    fi

    printf '[8/11] https-dns-proxy...\n'
    while uci -q delete https-dns-proxy.@https-dns-proxy[0]; do :; done
    uci -q delete https-dns-proxy.config 2>/dev/null
    uci set https-dns-proxy.config='main'
    uci set https-dns-proxy.config.update_dnsmasq='0'

    add_doh() {
        _s="$1"; _p="$2"
        eval "_v=\$SLOT_$_s"
        [ -z "$_v" ] && return
        if echo "$_v" | grep -q "^custom:"; then
            _u=$(echo "$_v" | cut -d: -f2-); _n="Custom"
        else
            _u=$(get_dns_field "$_v" 3); _n=$(get_dns_name "$_v")
            [ -z "$_u" ] && return
        fi
        uci add https-dns-proxy https-dns-proxy
        uci set https-dns-proxy.@https-dns-proxy[-1].listen_addr='127.0.0.1'
        uci set https-dns-proxy.@https-dns-proxy[-1].listen_port="$_p"
        uci set https-dns-proxy.@https-dns-proxy[-1].resolver_url="$_u"
        uci set https-dns-proxy.@https-dns-proxy[-1].request_timeout='2'
        uci set https-dns-proxy.@https-dns-proxy[-1].bootstrap_dns="$BOOTSTRAP_DNS"
        printf '  [+] %s (порт %s)\n' "$_n" "$_p"
    }
    for s in 1 2 3 4 5 6; do add_doh "$s" "$((5052 + s))"; done
    [ -n "$SLOT_RU" ] && add_doh "RU" "5059"
    [ -n "$SLOT_RU_2" ] && add_doh "RU_2" "5060"
    uci commit https-dns-proxy

    printf '[9/11] dnsmasq...\n'
    uci -q get dhcp.@dnsmasq[0] >/dev/null || uci add dhcp dnsmasq
    while uci -q delete dhcp.@dnsmasq[0].server; do :; done
    uci add_list dhcp.@dnsmasq[0].confdir='/etc/dnsmasq.d'
    if [ "$BALANCER_ENABLED" = "1" ]; then
        uci set dhcp.@dnsmasq[0].allservers='1'
        uci set dhcp.@dnsmasq[0].strictorder='0'
    else
        uci set dhcp.@dnsmasq[0].allservers='0'
        uci set dhcp.@dnsmasq[0].strictorder='1'
    fi
    uci set dhcp.@dnsmasq[0].noresolv='1'
    uci set dhcp.@dnsmasq[0].cachesize='10000'
    uci set dhcp.@dnsmasq[0].dnsforwardmax='1000'
    uci set dhcp.@dnsmasq[0].max_cache_ttl='300'
    uci set dhcp.@dnsmasq[0].quietdhcp='1'
    uci set dhcp.@dnsmasq[0].boguspriv='1'
    uci set dhcp.@dnsmasq[0].domainneeded='1'
    for s in 1 2 3 4 5 6; do
        eval "_v=\$SLOT_$s"
        [ -n "$_v" ] && uci add_list dhcp.@dnsmasq[0].server="127.0.0.1#$((5052 + s))"
    done
    if [ "$TLD_RU_ENABLED" = "1" ]; then
        for tld in /ru /su /xn--p1ai; do
            [ -n "$SLOT_RU" ] && uci add_list dhcp.@dnsmasq[0].server="${tld}/127.0.0.1#5059"
            [ -n "$SLOT_RU_2" ] && uci add_list dhcp.@dnsmasq[0].server="${tld}/127.0.0.1#5060"
        done
    fi
    uci commit dhcp

    printf '[10/11] QUIC...\n'
    uci -q delete firewall.block_quic 2>/dev/null
    if [ "$BLOCK_QUIC" = "1" ]; then
        uci set firewall.block_quic=rule
        uci set firewall.block_quic.name='Block-QUIC'
        uci set firewall.block_quic.src='lan'
        uci set firewall.block_quic.dest='wan'
        uci set firewall.block_quic.proto='udp'
        uci set firewall.block_quic.dest_port='443'
        uci set firewall.block_quic.target='REJECT'
    fi
    uci commit firewall

    printf '[11/11] Откат...\n'
    cat > /root/rollback-dns.sh << 'ROLLBACK'
#!/bin/sh
B="/etc/config/backup-pre-dns-v9"; O="/etc/config/backup-original"
[ -d "$B" ] && S="$B" || S="$O"
[ -d "$S" ] || { echo "No backup"; exit 1; }
echo "=== ROLLBACK: $S ==="
cp "$S/dhcp.bak" /etc/config/dhcp 2>/dev/null
cp "$S/firewall.bak" /etc/config/firewall 2>/dev/null
cp "$S/https-dns-proxy.bak" /etc/config/https-dns-proxy 2>/dev/null
cp "$S/system.bak" /etc/config/system 2>/dev/null
rm -f /etc/dnsmasq.d/anti-block.conf /etc/sysctl.d/99-custom.conf
sysctl -p /etc/sysctl.conf >/dev/null 2>&1
/etc/init.d/firewall restart 2>/dev/null
/etc/init.d/https-dns-proxy restart 2>/dev/null
/etc/init.d/dnsmasq restart
/etc/init.d/sysntpd restart 2>/dev/null
echo "✅ ROLLBACK DONE (reboot recommended)"
ROLLBACK
    chmod +x /root/rollback-dns.sh

    echo ""
    printf 'Перезапуск...\n'
    killall -9 https-dns-proxy 2>/dev/null; sleep 1
    /etc/init.d/https-dns-proxy restart; sleep 2
    /etc/init.d/dnsmasq restart
    /etc/init.d/firewall restart 2>/dev/null
    [ -f /etc/init.d/sysntpd ] && /etc/init.d/sysntpd restart 2>/dev/null
    sleep 2
    printf '\n\033[0;32m✓ Применено!\033[0m\n'
    printf 'Нажмите Enter...'; read -r _
}

menu_status() {
    clear
    printf '\033[0;34m╔══════════════════════════════════════════╗\033[0m\n'
    printf '\033[0;34m║     Состояние                           ║\033[0m\n'
    printf '\033[0;34m╚══════════════════════════════════════════╝\033[0m\n\n'
    a=$(uci -q get dhcp.@dnsmasq[0].allservers)
    [ "$a" = "1" ] && printf '\033[0;32m[✓] Балансировщик ВКЛ\033[0m\n' || printf '\033[1;33m[~] Балансировщик ВЫКЛ\033[0m\n'
    echo ""
    printf '\033[0;36mDoH процессы:\033[0m\n'
    ps | grep https-dns-proxy | grep -v grep | awk '{p="";u="";for(i=1;i<=NF;i++){if($i=="-p")p=$(i+1);if($i=="-r")u=$(i+1)}if(p!=""&&u!="")printf "  %s → %s\n",p,u}'
    echo ""
    printf '\033[0;36mBootstrap:\033[0m\n'
    ps | grep https-dns-proxy | grep -v grep | head -1 | awk '{for(i=1;i<=NF;i++)if($i=="-b"){printf "  %s\n",$(i+1);exit}}'
    echo ""
    printf '\033[0;36mNTP (IP):\033[0m %s\n' "$(get_ntp_preset_name "$NTP_PRESET")"
    echo ""
    printf '\033[0;36mResolution:\033[0m\n'
    for dom in ya.ru chatgpt.com youtube.com instagram.com; do
        ip=$(nslookup "$dom" 127.0.0.1 2>/dev/null | grep -vE '127\.0\.0\.|0\.0\.0\.0' | grep -oE '([0-9]{1,3}\.){3}[0-9]{1,3}' | head -n1)
        printf '  %-18s → %s\n' "$dom" "${ip:-NO_ANSWER}"
    done
    echo ""
    printf 'Нажмите Enter...'; read -r _
}

main_menu() {
    while true; do
        clear
        printf '\033[0;34m╔══════════════════════════════════════════╗\033[0m\n'
        printf '\033[0;34m║     DNS Manager v%-23s║\033[0m\n' "$VERSION"
        printf '\033[0;34m║  bypass/clean | 8 профилей | сток | IP-NTP║\033[0m\n'
        printf '\033[0;34m╚══════════════════════════════════════════╝\033[0m\n'
        echo ""
        printf '\033[1;33mИнтернет:\033[0m\n'
        for s in 1 2 3 4 5 6; do
            eval "_v=\$SLOT_$s"
            printf '  %d) %s [%s]\n' "$s" "$(get_dns_name "$_v")" "$(get_dns_type "$_v")"
        done
        printf '\033[1;33mРунет:\033[0m\n'
        printf '  РУ)  %s\n  РУ2) %s\n' "$(get_dns_name "$SLOT_RU")" "$(get_dns_name "$SLOT_RU_2")"
        echo ""
        printf 'Меню:\n'
        printf '  \033[0;32m1) ⚡ Профили (8 шт)\033[0m\n'
        printf '  2) Слоты\n'
        printf '  3) Тест всех DNS (независимый)\n'
        printf '  4) Bootstrap\n'
        printf '  5) Доп. настройки\n'
        printf '  6) Anti-block\n'
        printf '  7) Состояние\n'
        printf '  \033[0;32m8) ⚡ Применить\033[0m\n'
        printf '  9) Откат (бэкап)\n'
        printf '  \033[0;31mS) Возврат в СТОК\033[0m\n'
        printf '  0) Выход\n'
        echo ""
        printf 'Выбор: '; read -r choice
        case "$choice" in
            1) menu_profile_default ;;
            2) menu_slots ;;
            3) menu_test_dns ;;
            4) menu_bootstrap ;;
            5) menu_extras ;;
            6) menu_antiblock ;;
            7) menu_status ;;
            8) apply_settings ;;
            9) [ -f /root/rollback-dns.sh ] && sh /root/rollback-dns.sh || printf 'Нет отката\n'; read -r _ ;;
            S|s|Ы|ы|10) menu_reset_to_stock ;;
            0) exit 0 ;;
            *) printf '\033[0;31m[!] Неверный\033[0m\n'; sleep 1 ;;
        esac
    done
}

if [ "$SELF_SOURCE" != "$MANAGER_PATH" ] || [ ! -f "$MANAGER_PATH" ]; then
    install_self; exit 0
fi
init_system
load_config
main_menu
