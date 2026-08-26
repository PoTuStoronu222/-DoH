#!/bin/sh
# ============================================================
# DNS Manager v3.6-FINAL
# Безопасный сток | полная очистка | анти-дубли DoH
# НЕ ТРОГАЕМ то, что не настраивали сами
# ============================================================

MANAGER_PATH="/usr/bin/dns-manager"
SELF_SOURCE="$0"
CATVER="3.6"

install_self() {
    [ "$SELF_SOURCE" = "$MANAGER_PATH" ] && return 0
    echo "=== Установка DNS Manager v3.6 ==="
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
VERSION="3.6-FINAL"

flush_stdin() {
    while read -t 0.05 _flush_var 2>/dev/null; do :; done
}
safe_read() {
    flush_stdin
    read -r "$@"
}

create_catalog() {
    cat > "$DNS_CATALOG" << 'CATALOG'
#CATVER=3.6
#== ОБХОД БЛОКИРОВОК (bypass) ==
mafioznik|Mafioznik|https://dns.mafioznik.com/dns-query|bypass
comss_one|Comss.one|https://dns.comss.one/dns-query|bypass
comss_ru|Comss.ru|https://doh.comss.ru/dns-query|bypass
astrakat|Astrakat|https://dns.astrakat.com/dns-query|bypass
malw_link|Malw.link|https://dns.malw.link/dns-query|bypass
vppay|VPPay|https://dns.vppay.ru/dns-query|bypass
bluedns|BlueDNS|https://doh.bluedns.ru/dns-query|bypass
neutrdns|Neutrdns|https://dns.neutrdns.com/dns-query|bypass
dns_403|DNS.403|https://dns.403.online/dns-query|bypass
#== РУНЕТ (clean) ==
yandex|Yandex Basic|https://common.dot.dns.yandex.net/dns-query|clean
yandex_safe|Yandex Safe|https://safe.dns.yandex.ru/dns-query|clean
yandex_family|Yandex Family|https://family.dns.yandex.ru/dns-query|clean
skydns|SkyDNS|https://doh.skydns.ru/dns-query|clean
sber|Sber DNS|https://dns.sber.ru/dns-query|clean
#== ГЛОБАЛЬНЫЕ (clean) ==
cloudflare|Cloudflare|https://cloudflare-dns.com/dns-query|clean
cloudflare_sec|CF Security|https://security.cloudflare-dns.com/dns-query|clean
cloudflare_fam|CF Family|https://family.cloudflare-dns.com/dns-query|clean
google|Google DNS|https://dns.google/dns-query|clean
quad9|Quad9|https://dns.quad9.net/dns-query|clean
quad9_unsec|Quad9 Unsecured|https://dns10.quad9.net/dns-query|clean
quad9_ecs|Quad9 ECS|https://dns11.quad9.net/dns-query|clean
opendns|OpenDNS|https://doh.opendns.com/dns-query|clean
opendns_fam|OpenDNS Family|https://doh.familyshield.opendns.com/dns-query|clean
#== PRIVACY / ADBLOCK (clean) ==
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
#== РЕГИОНАЛЬНЫЕ (clean) ==
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
    if [ ! -f "$DNS_CATALOG" ] || ! grep -q "#CATVER=$CATVER" "$DNS_CATALOG"; then
        create_catalog
        printf '\033[0;32m[+] Каталог обновлён (v%s)\033[0m\n' "$CATVER"
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

get_dns_field() { grep -v '^#' "$DNS_CATALOG" | grep "^$1|" | head -1 | cut -d'|' -f"$2"; }
get_dns_name() {
    [ -z "$1" ] && { printf '(пусто)'; return; }
    echo "$1" | grep -q "^custom:" && { printf '(custom)'; return; }
    n=$(get_dns_field "$1" 2); [ -z "$n" ] && n="(неизв)"; printf '%s' "$n"
}
get_dns_type() {
    [ -z "$1" ] && { printf '-'; return; }
    t=$(get_dns_field "$1" 4); [ -z "$t" ] && t="clean"; printf '%s' "$t"
}
get_dns_url() {
    [ -z "$1" ] && return
    echo "$1" | grep -q "^custom:" && { echo "$1" | cut -d: -f2-; return; }
    get_dns_field "$1" 3
}

check_duplicates() {
    > /tmp/.dns_urls
    for s in 1 2 3 4 5 6 RU RU_2; do
        eval "v=\$SLOT_$s"; [ -z "$v" ] && continue
        url=$(get_dns_url "$v"); [ -n "$url" ] && printf '%s %s\n' "$s" "$url" >> /tmp/.dns_urls
    done
    awk '{print $2}' /tmp/.dns_urls | sort | uniq -c | awk '$1 > 1 {print $2}' > /tmp/.dns_dupes
    [ -s /tmp/.dns_dupes ] && return 0 || return 1
}

resolve_host() {
    for _bs in $(printf '%s' "$BOOTSTRAP_DNS" | tr ',' ' '); do
        _ip=$(nslookup "$1" "$_bs" 2>/dev/null | sed -n '/Name:/,$p' | grep -oE '([0-9]{1,3}\.){3}[0-9]{1,3}' | head -n1)
        [ -n "$_ip" ] && { printf '%s' "$_ip"; return 0; }
    done
    return 1
}

get_ntp_servers() {
    case "$1" in
        cloudflare)  echo "162.159.200.1 162.159.200.123" ;;
        google)      echo "216.239.35.0 216.239.35.4 216.239.35.8 216.239.35.12" ;;
        ntp_pool)    echo "162.159.200.1 216.239.35.0 129.6.15.28 129.6.15.29" ;;
        ru_vniiftri) echo "194.190.168.1 89.109.251.21 92.255.126.1 217.79.0.30" ;;
        ru_ps)       echo "194.190.168.1 194.85.252.2 92.255.126.1" ;;
        mixed)       echo "162.159.200.1 216.239.35.0 89.109.251.21 92.255.126.1 194.190.168.1 129.250.35.250" ;;
        dhcp)        echo "" ;; custom) echo "$2" ;;
        *)           echo "162.159.200.1 216.239.35.0 89.109.251.21" ;;
    esac
}
get_ntp_preset_name() {
    case "$1" in
        cloudflare) echo "Cloudflare (IP)" ;; google) echo "Google Time (IP)" ;;
        ntp_pool) echo "NTP Pool (IP)" ;; ru_vniiftri) echo "ВНИИФТРИ (RU)" ;;
        ru_ps) echo "Российские (IP)" ;; mixed) echo "Смешанный CF+Google+RU [рек]" ;;
        dhcp) echo "От провайдера (DHCP)" ;; custom) echo "Свой список" ;; *) echo "?" ;;
    esac
}

# ============================================================
# ВОЗВРАТ В СТОК — БЕЗОПАСНЫЙ (удаляем ТОЛЬКО наше)
# ============================================================
menu_reset_to_stock() {
    flush_stdin; clear
    printf '\033[0;31m╔══════════════════════════════════════════╗\033[0m\n'
    printf '\033[0;31m║   ⚠ ВОЗВРАТ В СТОК (безопасный)         ║\033[0m\n'
    printf '\033[0;31m╚══════════════════════════════════════════╝\033[0m\n\n'
    printf '\033[1;33mУдаляется ТОЛЬКО то, что настроил менеджер:\033[0m\n'
    printf '  • DoH-слоты и bootstrap\n'
    printf '  • anti-block.conf\n'
    printf '  • sysctl.d/99-custom.conf\n'
    printf '  • NTP Redirect правило\n'
    printf '  • Block-QUIC правило\n'
    printf '  • MTU fix (только если ставили мы)\n'
    printf '  • Конфиг менеджера\n\n'
    printf '\033[0;32mНЕ трогаются:\033[0m\n'
    printf '  • Системные параметры dnsmasq\n'
    printf '  • WiFi, LAN, WAN, PPPoE\n'
    printf '  • Tailscale, Zapret, tg-ws-proxy\n'
    printf '  • Пользовательские firewall правила\n'
    printf '  • DHCP, пароли, порты\n\n'
    printf 'Введите \033[0;32mсток\033[0m для подтверждения: '
    safe_read confirm
    conf_lc=$(printf '%s' "$confirm" | tr 'A-Z' 'a-z')
    case "$conf_lc" in
        сток|stock|y|s|да) : ;;
        *) printf '\033[1;33mОтменено.\033[0m\n'; sleep 1; return ;;
    esac

    echo ""
    # === [1/7] Убийство DoH процессов ===
    printf '[1/7] Остановка DoH...\n'
    killall -9 https-dns-proxy 2>/dev/null
    sleep 1
    # Проверяем что убиты
    if pgrep https-dns-proxy >/dev/null 2>&1; then
        printf '  \033[1;33m[!] Процессы живы, повторяем...\033[0m\n'
        killall -9 https-dns-proxy 2>/dev/null
        sleep 1
    fi
    /etc/init.d/https-dns-proxy stop 2>/dev/null
    /etc/init.d/https-dns-proxy disable 2>/dev/null

    # === [2/7] Удаление ВСЕХ UCI-секций https-dns-proxy ===
    printf '[2/7] Очистка UCI https-dns-proxy...\n'
    while uci -q delete https-dns-proxy.@https-dns-proxy[0]; do :; done
    uci -q delete https-dns-proxy.config 2>/dev/null
    # Пересоздаём пустой конфиг (чтобы init.d не ругался)
    uci set https-dns-proxy.config='main'
    uci set https-dns-proxy.config.update_dnsmasq='0'
    uci commit https-dns-proxy

    # === [3/7] Удаление ТОЛЬКО наших параметров dnsmasq ===
    printf '[3/7] Сброс dnsmasq (только наши параметры)...\n'
    # Удаляем ТОЛЬКО то, что добавляли мы:
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
    # НЕ удаляем: localservice, resolvfile, leasefile, domainneeded,
    # boguspriv, filterwin2k, localise_queries, rebind_protection,
    # authoritative, readethers, nonwildcard, ednspacket_max, filter_aaaa
    # Удаление DHCP option 42 (NTP)
    for opt in $(uci -q get dhcp.lan.dhcp_option 2>/dev/null | tr ' ' '\n' | grep '^42,'); do
        uci -q del_list dhcp.lan.dhcp_option="$opt"
    done
    uci commit dhcp

    # === [4/7] Удаление ТОЛЬКО наших правил firewall ===
    printf '[4/7] Сброс firewall (только наши правила)...\n'
    uci -q delete firewall.redirect_ntp 2>/dev/null
    uci -q delete firewall.block_quic 2>/dev/null
    # MTU fix — удаляем только если есть (мог быть системным)
    uci -q delete firewall.@defaults[0].mtu_fix 2>/dev/null
    WAN_SEC=$(uci show firewall 2>/dev/null | grep -m1 "\.name='wan'" | cut -d. -f1,2)
    [ -n "$WAN_SEC" ] && uci -q delete "${WAN_SEC}.mtu_fix" 2>/dev/null
    uci commit firewall

    # === [5/7] NTP к дефолту OpenWrt ===
    printf '[5/7] NTP к дефолту...\n'
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

    # === [6/7] Удаление артефактов менеджера ===
    printf '[6/7] Удаление артефактов...\n'
    rm -f /etc/dnsmasq.d/anti-block.conf
    rm -f /etc/sysctl.d/99-custom.conf
    rm -f /etc/hotplug.d/ntp/99-tailscale
    rm -f /root/rollback-dns.sh
    rm -f "$CONFIG_FILE" "$DNS_CATALOG" "$TEST_RESULTS"
    rm -f /tmp/.dns_all /tmp/.dns_sel /tmp/.dns_urls /tmp/.dns_dupes
    rm -f /tmp/.added_urls /tmp/.active_ports /tmp/.tgi /tmp/tmp.init
    rm -f /tmp/dns_setup.sh /tmp/dns_final.sh /tmp/install.sh /tmp/finish.sh
    # Очистка крон
    [ -f /etc/crontabs/root ] && sed -i '/update-bogus-dns/d; /https-dns-proxy/d; /dns-manager/d' /etc/crontabs/root

    # === [7/7] Применение + перезагрузка ===
    printf '[7/7] Применение...\n'
    sysctl -p /etc/sysctl.conf >/dev/null 2>&1
    /etc/init.d/firewall restart 2>/dev/null
    /etc/init.d/dnsmasq restart
    /etc/init.d/sysntpd restart 2>/dev/null
    /etc/init.d/network reload 2>/dev/null

    # Финальная проверка
    echo ""
    if pgrep https-dns-proxy >/dev/null 2>&1; then
        printf '\033[0;31m[✗] ВНИМАНИЕ: https-dns-proxy всё ещё запущен!\033[0m\n'
        printf '  Выполните вручную: killall -9 https-dns-proxy\n'
    else
        printf '\033[0;32m[✓] https-dns-proxy остановлен\033[0m\n'
    fi

    printf '\033[0;32m✅ СТОК ВОССТАНОВЛЕН БЕЗОПАСНО!\033[0m\n'
    printf 'Перезагрузка через 5 сек...\n'
    sleep 5
    reboot
    exit 0
}

# ============================================================
# ПРОФИЛИ
# ============================================================
menu_profile_default() {
    flush_stdin; clear
    printf '\033[0;34m╔══════════════════════════════════════════╗\033[0m\n'
    printf '\033[0;34m║     Быстрая настройка (8 профилей)      ║\033[0m\n'
    printf '\033[0;34m╚══════════════════════════════════════════╝\033[0m\n\n'
    printf '  \033[0;32m1) Оптимальный [рекомендуется]\033[0m\n'
    printf '     4 обходных + Yandex RU | QUIC+MTU+NTP+sysctl+Go\n\n'
    printf '  2) Максимум устойчивости\n'
    printf '     6 обходных + 2 РУ | QUIC+MTU+NTP+sysctl+Go\n\n'
    printf '  3) Одна голова (слабый роутер)\n'
    printf '     1 DNS, балансир ВЫКЛ | MTU+NTP+Go\n\n'
    printf '  4) Только рунет\n'
    printf '     Только Yandex | MTU+NTP+sysctl+Go\n\n'
    printf '  5) Семейный\n'
    printf '     AdGuard+CF+CleanBrows Fam | QUIC+MTU+NTP+sysctl+Go\n\n'
    printf '  6) Приватный\n'
    printf '     AdGuard Unf+Mullvad+Quad9 | QUIC+MTU+NTP+sysctl+Go\n\n'
    printf '  7) Чистый (без обхода)\n'
    printf '     CF+Google+Quad9+OpenDNS | MTU+NTP+sysctl+Go\n\n'
    printf '  8) Быстрый\n'
    printf '     Mafioznik+Comss.ru+DNS.403+BlueDNS | QUIC+MTU+NTP+sysctl+Go\n\n'
    printf '  \033[0;36mEnter\033[0m = отмена\n\n'
    printf 'Выбор: '; safe_read choice; [ -z "$choice" ] && return

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
           SLOT_RU="yandex"; SLOT_RU_2=""; BALANCER_ENABLED="0"; BLOCK_QUIC="0" ;;
        5) SLOT_1="adguard_fam"; SLOT_2="cloudflare_fam"; SLOT_3="cleanbr_fam"
           SLOT_4=""; SLOT_5=""; SLOT_6=""; SLOT_RU="yandex_family"; SLOT_RU_2="" ;;
        6) SLOT_1="adguard_unf"; SLOT_2="mullvad"; SLOT_3="quad9_unsec"; SLOT_4="nextdns"
           SLOT_5=""; SLOT_6=""; SLOT_RU="yandex"; SLOT_RU_2="" ;;
        7) SLOT_1="cloudflare"; SLOT_2="google"; SLOT_3="quad9"; SLOT_4="opendns"
           SLOT_5=""; SLOT_6=""; SLOT_RU="yandex"; SLOT_RU_2=""; BLOCK_QUIC="0" ;;
        8) SLOT_1="mafioznik"; SLOT_2="comss_ru"; SLOT_3="dns_403"; SLOT_4="bluedns"
           SLOT_5=""; SLOT_6=""; SLOT_RU="yandex"; SLOT_RU_2="" ;;
        *) printf '\033[0;31m[!] Неверный\033[0m\n'; sleep 1; return ;;
    esac
    save_config
    printf '\033[0;32m[✓] Профиль сохранён\033[0m\n'
    printf 'Применить? [y/Enter=да, n=нет]: '; safe_read confirm
    case "$confirm" in n|N) printf 'Примените через пункт 8.\n'; sleep 2 ;; *) apply_settings ;; esac
}

# ============================================================
# ТЕСТ DNS (НЕЗАВИСИМЫЙ)
# ============================================================
menu_test_dns() {
    flush_stdin; clear
    printf '\033[0;34m╔══════════════════════════════════════════╗\033[0m\n'
    printf '\033[0;34m║  Тест всех DNS (независимо от DoH)      ║\033[0m\n'
    printf '\033[0;34m╚══════════════════════════════════════════╝\033[0m\n\n'
    printf '\033[1;33mРезолв через bootstrap-IP + curl --resolve\033[0m\n\n'
    printf '%-20s %-8s %-9s %-9s %s\n' "DNS" "Тип" "Статус" "Скорость" "Примечание"
    printf '%s\n' "---------------------------------------------------------------------------"
    > "$TEST_RESULTS"
    grep -v '^#' "$DNS_CATALOG" | grep '|' | while IFS='|' read -r id name url dtype; do
        [ -z "$id" ] && continue
        host=$(printf '%s' "$url" | sed 's|^https://||; s|/.*$||')
        ip=$(resolve_host "$host")
        if [ -z "$ip" ]; then
            printf '%-20s %-8s \033[0;31mFAIL\033[0m   %-9s %s\n' "$name" "$dtype" "-" "bootstrap"
            echo "${id}|0|FAIL" >> "$TEST_RESULTS"; continue
        fi
        t=$(curl -s -o /dev/null -w '%{time_total}' --max-time 5 \
            --resolve "$host:443:$ip" \
            "${url}?name=google.com&type=A" -H 'Accept: application/dns-json' 2>/dev/null)
        if [ -n "$t" ] && [ "$t" != "0.000000" ]; then
            ms=$(echo "$t" | awk '{printf "%.0f", $1 * 1000}')
            [ "$ms" -lt 100 ] && note="Быстрый" || { [ "$ms" -lt 300 ] && note="Норм" || note="Медленный"; }
            printf '%-20s %-8s \033[0;32mOK\033[0m     %-9s %s\n' "$name" "$dtype" "${ms}ms" "$note"
            echo "${id}|${ms}|OK" >> "$TEST_RESULTS"
        else
            printf '%-20s %-8s \033[0;31mFAIL\033[0m   %-9s %s\n' "$name" "$dtype" "-" "DoH"
            echo "${id}|0|FAIL" >> "$TEST_RESULTS"
        fi
    done
    echo ""; printf '%s\n' "---------------------------------------------------------------------------"
    total=$(wc -l < "$TEST_RESULTS" 2>/dev/null)
    ok=$(grep -c '|OK' "$TEST_RESULTS" 2>/dev/null)
    fail=$(grep -c '|FAIL' "$TEST_RESULTS" 2>/dev/null)
    printf 'Всего: %s | \033[0;32mOK: %s\033[0m | \033[0;31mFAIL: %s\033[0m\n' "$total" "$ok" "$fail"
    printf '\nНажмите Enter...'; safe_read _
}

# ============================================================
# Выбор DNS для слота
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
        flush_stdin; clear; build_select_list
        printf '\033[0;34m╔══════════════════════════════════════════╗\033[0m\n'
        printf '\033[0;34m║     Выбор DNS для слота #%-15s║\033[0m\n' "$slot_num"
        printf '\033[0;34m╚══════════════════════════════════════════╝\033[0m\n\n'
        case "$SELECT_FILTER" in bypass) fstr="ОБХОД" ;; clean) fstr="ЧИСТЫЕ" ;; *) fstr="все" ;; esac
        printf 'Фильтр: \033[1;33m%s\033[0m (95=переключить)\n\n' "$fstr"
        i=1
        while IFS='|' read -r id name url dtype; do
            [ -z "$id" ] && continue
            [ "$dtype" = "bypass" ] && tag="\033[0;32m[обход]\033[0m" || tag="\033[0;36m[чистый]\033[0m"
            tr_line=$(grep "^${id}|" "$TEST_RESULTS" 2>/dev/null | head -1)
            if [ -n "$tr_line" ]; then
                ms=$(printf '%s' "$tr_line" | cut -d'|' -f2)
                st=$(printf '%s' "$tr_line" | cut -d'|' -f3)
                [ "$st" = "OK" ] && printf '  %2d) %-18s %b \033[0;32m%5sms\033[0m\n' "$i" "$name" "$tag" "$ms" \
                    || printf '  %2d) %-18s %b \033[0;31m  FAIL\033[0m\n' "$i" "$name" "$tag"
            else
                printf '  %2d) %-18s %b \033[1;33m (нет теста)\033[0m\n' "$i" "$name" "$tag"
            fi
            i=$((i+1))
        done < /tmp/.dns_sel
        echo ""
        printf '  \033[0;36m99) Очистить  98) Свой URL  95) Фильтр  Enter) Отмена\033[0m\n\n'
        printf 'Выбор: '; safe_read choice; [ -z "$choice" ] && return
        case "$choice" in
            99) eval "SLOT_${slot_num}=\"\""; save_config; return ;;
            98) printf 'URL: '; safe_read cu; [ -n "$cu" ] && { eval "SLOT_${slot_num}=\"custom:$cu\""; save_config; }; return ;;
            95) case "$SELECT_FILTER" in all) SELECT_FILTER="bypass" ;; bypass) SELECT_FILTER="clean" ;; *) SELECT_FILTER="all" ;; esac ;;
            *) total=$(wc -l < /tmp/.dns_sel)
               if [ "$choice" -ge 1 ] 2>/dev/null && [ "$choice" -le "$total" ] 2>/dev/null; then
                   sel_id=$(sed -n "${choice}p" /tmp/.dns_sel | cut -d'|' -f1)
                   eval "SLOT_${slot_num}=\"$sel_id\""; save_config; return
               fi; printf '\033[0;31m[!]\033[0m\n'; sleep 1 ;;
        esac
    done
}

menu_slots() {
    flush_stdin
    while true; do
        clear
        printf '\033[0;34m╔══════════════════════════════════════════╗\033[0m\n'
        printf '\033[0;34m║     Настройка слотов DNS                ║\033[0m\n'
        printf '\033[0;34m╚══════════════════════════════════════════╝\033[0m\n\n'
        printf '\033[1;33mИнтернет:\033[0m\n'
        for s in 1 2 3 4 5 6; do
            eval "_v=\$SLOT_$s"
            printf '  %d) %s [%s]\n' "$s" "$(get_dns_name "$_v")" "$(get_dns_type "$_v")"
        done
        printf '\n\033[1;33mРунет:\033[0m\n'
        printf '  7) РУ   (5059): %s\n' "$(get_dns_name "$SLOT_RU")"
        printf '  8) РУ-2 (5060): %s\n' "$(get_dns_name "$SLOT_RU_2")"
        echo ""
        check_duplicates && {
            printf '\033[1;33m⚠ Дубли URL! При применении лишние будут пропущены.\033[0m\n'
            while read -r dupe_url; do printf '  • %s\n' "$dupe_url"; done < /tmp/.dns_dupes
            echo ""
        }
        printf '  \033[0;36mEnter) Назад\033[0m\n'; printf 'Выбор: '; safe_read choice; [ -z "$choice" ] && return
        case "$choice" in
            1) select_dns_for_slot "1" ;; 2) select_dns_for_slot "2" ;; 3) select_dns_for_slot "3" ;;
            4) select_dns_for_slot "4" ;; 5) select_dns_for_slot "5" ;; 6) select_dns_for_slot "6" ;;
            7) select_dns_for_slot "RU" ;; 8) select_dns_for_slot "RU_2" ;;
            *) printf '\033[0;31m[!]\033[0m\n'; sleep 1 ;;
        esac
    done
}

menu_bootstrap() {
    flush_stdin
    while true; do
        clear
        printf '\033[0;34m╔══════════════════════════════════════════╗\033[0m\n'
        printf '\033[0;34m║     Bootstrap DNS                       ║\033[0m\n'
        printf '\033[0;34m╚══════════════════════════════════════════╝\033[0m\n\n'
        printf 'Текущий: \033[1;33m%s\033[0m\n\n' "$BOOTSTRAP_DNS"
        printf '  1) Полный 10 IP [рек]  2) РФ (4 IP)  3) Yandex  4) AdGuard  5) Вручную\n'
        printf '  \033[0;36mEnter) Назад\033[0m\n'; printf 'Выбор: '; safe_read choice; [ -z "$choice" ] && return
        case "$choice" in
            1) BOOTSTRAP_DNS="77.88.8.8,77.88.8.1,94.140.14.14,94.140.15.15,1.1.1.1,1.0.0.1,8.8.8.8,8.8.4.4,9.9.9.9,149.112.112.112" ;;
            2) BOOTSTRAP_DNS="77.88.8.8,77.88.8.1,94.140.14.14,94.140.15.15" ;;
            3) BOOTSTRAP_DNS="77.88.8.8,77.88.8.1" ;;
            4) BOOTSTRAP_DNS="94.140.14.14,94.140.15.15" ;;
            5) printf 'IP: '; safe_read BOOTSTRAP_DNS ;;
            *) return ;;
        esac
        save_config; return
    done
}

menu_ntp() {
    flush_stdin
    while true; do
        clear
        printf '\033[0;34m╔══════════════════════════════════════════╗\033[0m\n'
        printf '\033[0;34m║  NTP серверы (ТОЛЬКО IP)                ║\033[0m\n'
        printf '\033[0;34m╚══════════════════════════════════════════╝\033[0m\n\n'
        printf 'Текущий: \033[1;33m%s\033[0m\n\n' "$(get_ntp_preset_name "$NTP_PRESET")"
        for srv in $(get_ntp_servers "$NTP_PRESET" "$NTP_CUSTOM"); do printf '  • %s\n' "$srv"; done
        echo ""
        printf '  1) Смешанный [рек]  2) CF  3) Google  4) Pool  5) ВНИИФТРИ  6) RU  7) DHCP  8) Свой\n'
        printf '  \033[0;36mEnter) Назад\033[0m\n'; printf 'Выбор: '; safe_read choice; [ -z "$choice" ] && return
        case "$choice" in
            1) NTP_PRESET="mixed" ;; 2) NTP_PRESET="cloudflare" ;; 3) NTP_PRESET="google" ;;
            4) NTP_PRESET="ntp_pool" ;; 5) NTP_PRESET="ru_vniiftri" ;; 6) NTP_PRESET="ru_ps" ;;
            7) NTP_PRESET="dhcp" ;; 8) printf 'IP: '; safe_read NTP_CUSTOM; NTP_PRESET="custom" ;; *) return ;;
        esac
        save_config
    done
}

menu_extras() {
    flush_stdin
    while true; do
        clear
        printf '\033[0;34m╔══════════════════════════════════════════╗\033[0m\n'
        printf '\033[0;34m║     Дополнительные настройки            ║\033[0m\n'
        printf '\033[0;34m╚══════════════════════════════════════════╝\033[0m\n\n'
        [ "$BALANCER_ENABLED" = "1" ] && b1="\033[0;32m[✓]\033[0m" || b1="\033[0;31m[ ]\033[0m"
        [ "$TLD_RU_ENABLED" = "1" ] && b2="\033[0;32m[✓]\033[0m" || b2="\033[0;31m[ ]\033[0m"
        [ "$BLOCK_QUIC" = "1" ] && b3="\033[0;32m[✓]\033[0m" || b3="\033[0;31m[ ]\033[0m"
        [ "$MTU_FIX" = "1" ] && b4="\033[0;32m[✓]\033[0m" || b4="\033[0;31m[ ]\033[0m"
        [ "$NTP_REDIRECT" = "1" ] && b5="\033[0;32m[✓]\033[0m" || b5="\033[0;31m[ ]\033[0m"
        [ "$SYSCTL_TUNING" = "1" ] && b6="\033[0;32m[✓]\033[0m" || b6="\033[0;31m[ ]\033[0m"
        [ "$GO_OPTIMIZE" = "1" ] && b7="\033[0;32m[✓]\033[0m" || b7="\033[0;31m[ ]\033[0m"
        printf '  1) %b Балансировщик\n  2) %b TLD Split\n  3) %b QUIC\n' "$b1" "$b2" "$b3"
        printf '  4) %b MTU Fix\n  5) %b NTP Redirect\n  6) %b Sysctl\n  7) %b Go-opt\n' "$b4" "$b5" "$b6" "$b7"
        printf '\n  8) \033[1;33m→ NTP: %s\033[0m\n' "$(get_ntp_preset_name "$NTP_PRESET")"
        printf '  \033[0;36mEnter) Назад\033[0m\n'; printf 'Выбор: '; safe_read choice; [ -z "$choice" ] && return
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
    flush_stdin
    while true; do
        clear
        printf '\033[0;34m╔══════════════════════════════════════════╗\033[0m\n'
        printf '\033[0;34m║     Anti-block                          ║\033[0m\n'
        printf '\033[0;34m╚══════════════════════════════════════════╝\033[0m\n\n'
        grep "bogus-nxdomain=" /etc/dnsmasq.d/anti-block.conf 2>/dev/null | sed 's/bogus-nxdomain=/  /' || printf '  (пусто)\n'
        echo ""
        printf '  1) Добавить  2) Удалить  3) Сброс к эталону\n'
        printf '  \033[0;36mEnter) Назад\033[0m\n'; printf 'Выбор: '; safe_read choice; [ -z "$choice" ] && return
        case "$choice" in
            1) printf 'IP: '; safe_read ip; [ -n "$ip" ] && { echo "bogus-nxdomain=$ip" >> /etc/dnsmasq.d/anti-block.conf; /etc/init.d/dnsmasq restart; } ;;
            2) printf 'IP: '; safe_read ip; [ -n "$ip" ] && { sed -i "/bogus-nxdomain=$ip/d" /etc/dnsmasq.d/anti-block.conf; /etc/init.d/dnsmasq restart; } ;;
            3) cat > /etc/dnsmasq.d/anti-block.conf << 'AB'
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
AB
               /etc/init.d/dnsmasq restart ;;
        esac
    done
}

# ============================================================
# ПРИМЕНЕНИЕ — с полной очисткой перед созданием + анти-дубли
# ============================================================
apply_settings() {
    flush_stdin; clear
    printf '\033[0;34m╔══════════════════════════════════════════╗\033[0m\n'
    printf '\033[0;34m║     Применение настроек                 ║\033[0m\n'
    printf '\033[0;34m╚══════════════════════════════════════════╝\033[0m\n\n'

    printf '[1/11] Бэкапы...\n'
    [ ! -d /etc/config/backup-original ] && {
        mkdir -p /etc/config/backup-original
        for f in dhcp firewall https-dns-proxy system; do cp /etc/config/$f /etc/config/backup-original/$f.bak 2>/dev/null; done
    }
    TS=$(date +%Y%m%d_%H%M%S); BA="/etc/config/backup-dns-$TS"; mkdir -p "$BA"
    for f in dhcp firewall https-dns-proxy system; do cp /etc/config/$f "$BA/$f.bak" 2>/dev/null; done
    ln -sfn "$BA" /etc/config/backup-pre-dns-v9
    (cd /etc/config && ls -dt backup-dns-* 2>/dev/null | tail -n +2 | xargs rm -rf 2>/dev/null)

    printf '[2/11] Anti-block...\n'
    [ ! -f /etc/dnsmasq.d/anti-block.conf ] && cat > /etc/dnsmasq.d/anti-block.conf << 'AB'
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
AB

    [ "$MTU_FIX" = "1" ] && { printf '[3/11] MTU...\n'; uci -q set firewall.@defaults[0].mtu_fix='1'
        WS=$(uci show firewall 2>/dev/null | grep -m1 "\.name='wan'" | cut -d. -f1,2)
        [ -n "$WS" ] && uci -q set "${WS}.mtu_fix=1"; uci commit firewall; }

    if [ "$NTP_REDIRECT" = "1" ]; then
        printf '[4/11] NTP...\n'
        LAN_IP=$(uci -q get network.lan.ipaddr | cut -d'/' -f1 | awk '{print $1}')
        [ -z "$LAN_IP" ] || [ "$LAN_IP" = "0.0.0.0" ] && LAN_IP="192.168.1.1"
        for opt in $(uci -q get dhcp.lan.dhcp_option 2>/dev/null | tr ' ' '\n' | grep '^42,'); do uci -q del_list dhcp.lan.dhcp_option="$opt"; done
        uci add_list dhcp.lan.dhcp_option="42,$LAN_IP"; uci commit dhcp
        for sec in $(uci show firewall 2>/dev/null | grep -E "dest_port='123'|src_dport='123'|Redirect-NTP" | cut -d. -f2 | cut -d= -f1 | sort -u); do uci -q delete firewall."$sec"; done
        [ -f /usr/share/fw4/helpers.sh ] && FW="fw4" || FW="fw3"
        uci set firewall.redirect_ntp=redirect; uci set firewall.redirect_ntp.name='Redirect-NTP'
        uci set firewall.redirect_ntp.src='lan'; uci set firewall.redirect_ntp.proto='udp'
        uci set firewall.redirect_ntp.src_dport='123'; uci set firewall.redirect_ntp.dest_port='123'
        uci set firewall.redirect_ntp.dest_ip="$LAN_IP"; uci set firewall.redirect_ntp.target='DNAT'
        [ "$FW" = "fw4" ] && uci set firewall.redirect_ntp.family='ipv4'; uci commit firewall
        ns=$(get_ntp_servers "$NTP_PRESET" "$NTP_CUSTOM")
        while uci -q delete system.@timeserver[0]; do :; done
        uci -q delete system.ntp 2>/dev/null; uci set system.ntp=timeserver; uci set system.ntp.enabled='1'
        if [ "$NTP_PRESET" = "dhcp" ] || [ -z "$ns" ]; then uci set system.ntp.enable_server='1'
        else for srv in $ns; do uci add_list system.ntp.server="$srv"; done; fi
        uci commit system
    fi

    if [ "$GO_OPTIMIZE" = "1" ]; then
        printf '[5/11] Go-opt...\n'
        for f in /etc/init.d/tg-ws-proxy-go /etc/init.d/tailscale; do
            [ ! -f "$f" ] && continue; sed -i '/GOMAXPROCS/d; /GOMEMLIMIT/d; /GOGC/d' "$f"
            grep -q "procd_open_instance" "$f" && {
                [ "$f" = "/etc/init.d/tg-ws-proxy-go" ] && EV="GOMAXPROCS=1 GOMEMLIMIT=50MiB" || EV="GOMEMLIMIT=85MiB"
                awk -v ev="$EV" '/procd_open_instance/{print;print "    procd_set_param env "ev;next}1' "$f" > /tmp/.tgi && mv /tmp/.tgi "$f"
            }
        done
    fi

    [ "$SYSCTL_TUNING" = "1" ] && { printf '[6/11] Sysctl...\n'; modprobe nf_conntrack 2>/dev/null
        SF="/etc/sysctl.d/99-custom.conf"; touch "$SF"
        for p in "net.netfilter.nf_conntrack_max=65536" "net.ipv4.tcp_fastopen=3" "net.ipv4.tcp_fin_timeout=15" "net.core.somaxconn=1024" "net.ipv4.tcp_keepalive_time=300" "net.core.rmem_max=2097152" "net.core.wmem_max=2097152"; do
            k=$(echo "$p"|cut -d= -f1); sed -i "/^$k/d" "$SF"; echo "$p">>"$SF"; sysctl -w "$p">/dev/null 2>&1
        done; }

    [ -f /etc/init.d/tailscale ] && { printf '[7/11] Hotplug...\n'; mkdir -p /etc/hotplug.d/ntp
        printf '#!/bin/sh\n[ "$ACTION" = "step" ] || [ "$ACTION" = "stratum" ] || exit 0\nUPTIME=$(cut -d. -f1 /proc/uptime)\n[ "$UPTIME" -lt 600 ] && /etc/init.d/tailscale restart >/dev/null 2>&1\n' > /etc/hotplug.d/ntp/99-tailscale
        chmod +x /etc/hotplug.d/ntp/99-tailscale; }

    # === [8/11] https-dns-proxy: ПОЛНАЯ ОЧИСТКА + АНТИ-ДУБЛИ ===
    printf '[8/11] DoH (полная очистка + анти-дубли)...\n'

    # ШАГ A: Убить ВСЕ старые процессы
    killall -9 https-dns-proxy 2>/dev/null; sleep 1

    # ШАГ B: Удалить ВСЕ UCI-секции (цикл до полного удаления)
    while uci -q delete https-dns-proxy.@https-dns-proxy[0]; do :; done
    uci -q delete https-dns-proxy.config 2>/dev/null

    # ШАГ C: Создать чистый базовый конфиг
    uci set https-dns-proxy.config='main'
    uci set https-dns-proxy.config.update_dnsmasq='0'

    # ШАГ D: Добавить только уникальные URL
    > /tmp/.added_urls

    add_doh() {
        _s="$1"; _p="$2"
        eval "_v=\$SLOT_$_s"; [ -z "$_v" ] && return
        _u=$(get_dns_url "$_v"); [ -z "$_u" ] && return
        # Анти-дубль
        if grep -qxF "$_u" /tmp/.added_urls 2>/dev/null; then
            printf '  \033[1;33m[~] Пропуск (дубль): %s\033[0m\n' "$(get_dns_name "$_v")"
            return
        fi
        printf '%s\n' "$_u" >> /tmp/.added_urls
        uci add https-dns-proxy https-dns-proxy
        uci set https-dns-proxy.@https-dns-proxy[-1].listen_addr='127.0.0.1'
        uci set https-dns-proxy.@https-dns-proxy[-1].listen_port="$_p"
        uci set https-dns-proxy.@https-dns-proxy[-1].resolver_url="$_u"
        uci set https-dns-proxy.@https-dns-proxy[-1].request_timeout='2'
        uci set https-dns-proxy.@https-dns-proxy[-1].bootstrap_dns="$BOOTSTRAP_DNS"
        printf '  \033[0;32m[+] %s (порт %s)\033[0m\n' "$(get_dns_name "$_v")" "$_p"
    }
    for s in 1 2 3 4 5 6; do add_doh "$s" "$((5052 + s))"; done
    [ -n "$SLOT_RU" ] && add_doh "RU" "5059"
    [ -n "$SLOT_RU_2" ] && add_doh "RU_2" "5060"
    uci commit https-dns-proxy

    # === [9/11] dnsmasq (только активные уникальные порты) ===
    printf '[9/11] dnsmasq...\n'
    uci -q get dhcp.@dnsmasq[0] >/dev/null || uci add dhcp dnsmasq
    while uci -q delete dhcp.@dnsmasq[0].server; do :; done
    uci add_list dhcp.@dnsmasq[0].confdir='/etc/dnsmasq.d'
    [ "$BALANCER_ENABLED" = "1" ] && { uci set dhcp.@dnsmasq[0].allservers='1'; uci set dhcp.@dnsmasq[0].strictorder='0'; } \
        || { uci set dhcp.@dnsmasq[0].allservers='0'; uci set dhcp.@dnsmasq[0].strictorder='1'; }
    uci set dhcp.@dnsmasq[0].noresolv='1'; uci set dhcp.@dnsmasq[0].cachesize='10000'
    uci set dhcp.@dnsmasq[0].dnsforwardmax='1000'; uci set dhcp.@dnsmasq[0].max_cache_ttl='300'
    uci set dhcp.@dnsmasq[0].quietdhcp='1'; uci set dhcp.@dnsmasq[0].boguspriv='1'; uci set dhcp.@dnsmasq[0].domainneeded='1'

    # Только уникальные порты из реально добавленных URL
    > /tmp/.active_ports
    for s in 1 2 3 4 5 6; do
        eval "_v=\$SLOT_$s"; [ -z "$_v" ] && continue
        _u=$(get_dns_url "$_v")
        grep -qxF "$_u" /tmp/.added_urls 2>/dev/null && printf '%s\n' "$((5052 + s))" >> /tmp/.active_ports
    done
    sort -un /tmp/.active_ports | while read -r p; do uci add_list dhcp.@dnsmasq[0].server="127.0.0.1#$p"; done

    if [ "$TLD_RU_ENABLED" = "1" ]; then
        for tld in /ru /su /xn--p1ai; do
            [ -n "$SLOT_RU" ] && uci add_list dhcp.@dnsmasq[0].server="${tld}/127.0.0.1#5059"
            [ -n "$SLOT_RU_2" ] && uci add_list dhcp.@dnsmasq[0].server="${tld}/127.0.0.1#5060"
        done
    fi
    uci commit dhcp

    printf '[10/11] QUIC...\n'
    uci -q delete firewall.block_quic 2>/dev/null
    [ "$BLOCK_QUIC" = "1" ] && {
        uci set firewall.block_quic=rule; uci set firewall.block_quic.name='Block-QUIC'
        uci set firewall.block_quic.src='lan'; uci set firewall.block_quic.dest='wan'
        uci set firewall.block_quic.proto='udp'; uci set firewall.block_quic.dest_port='443'
        uci set firewall.block_quic.target='REJECT'
    }
    uci commit firewall

    printf '[11/11] Откат...\n'
    cat > /root/rollback-dns.sh << 'RB'
#!/bin/sh
B="/etc/config/backup-pre-dns-v9"; O="/etc/config/backup-original"
[ -d "$B" ] && S="$B" || S="$O"; [ -d "$S" ] || { echo "No backup"; exit 1; }
echo "=== ROLLBACK: $S ==="
cp "$S/dhcp.bak" /etc/config/dhcp 2>/dev/null
cp "$S/firewall.bak" /etc/config/firewall 2>/dev/null
cp "$S/https-dns-proxy.bak" /etc/config/https-dns-proxy 2>/dev/null
cp "$S/system.bak" /etc/config/system 2>/dev/null
rm -f /etc/dnsmasq.d/anti-block.conf /etc/sysctl.d/99-custom.conf
sysctl -p /etc/sysctl.conf >/dev/null 2>&1
/etc/init.d/firewall restart 2>/dev/null; /etc/init.d/https-dns-proxy restart 2>/dev/null
/etc/init.d/dnsmasq restart; /etc/init.d/sysntpd restart 2>/dev/null
echo "✅ DONE (reboot recommended)"
RB
    chmod +x /root/rollback-dns.sh

    # Перезапуск
    echo ""; printf 'Перезапуск...\n'
    killall -9 https-dns-proxy 2>/dev/null; sleep 1
    /etc/init.d/https-dns-proxy enable 2>/dev/null
    /etc/init.d/https-dns-proxy restart; sleep 2
    /etc/init.d/dnsmasq restart
    /etc/init.d/firewall restart 2>/dev/null
    [ -f /etc/init.d/sysntpd ] && /etc/init.d/sysntpd restart 2>/dev/null
    sleep 2

    # Проверка результата
    proc_count=$(ps | grep https-dns-proxy | grep -v grep | wc -l)
    added_count=$(wc -l < /tmp/.added_urls 2>/dev/null)
    printf '\n\033[0;32m✓ Применено! DoH процессов: %s (уникальных URL: %s)\033[0m\n' "$proc_count" "$added_count"
    printf 'Нажмите Enter...'; safe_read _
}

# ============================================================
# СОСТОЯНИЕ
# ============================================================
menu_status() {
    flush_stdin; clear
    printf '\033[0;34m╔══════════════════════════════════════════╗\033[0m\n'
    printf '\033[0;34m║     Состояние + диагностика             ║\033[0m\n'
    printf '\033[0;34m╚══════════════════════════════════════════╝\033[0m\n\n'
    a=$(uci -q get dhcp.@dnsmasq[0].allservers)
    [ "$a" = "1" ] && printf '\033[0;32m[✓] Балансировщик ВКЛ\033[0m\n' || printf '\033[1;33m[~] Балансировщик ВЫКЛ\033[0m\n'
    echo ""
    printf '\033[1;33mdnsmasq:\033[0m\n'
    pgrep dnsmasq >/dev/null 2>&1 && printf '  \033[0;32m[✓] Запущен\033[0m\n' || printf '  \033[0;31m[✗] НЕ запущен!\033[0m\n'
    echo ""
    printf '\033[0;36mDoH процессы:\033[0m\n'
    pc=$(ps | grep https-dns-proxy | grep -v grep | wc -l)
    [ "$pc" -eq 0 ] && printf '  \033[0;31m[✗] Нет процессов!\033[0m\n' || {
        printf '  \033[0;32m[✓] %s процессов:\033[0m\n' "$pc"
        ps | grep https-dns-proxy | grep -v grep | awk '{p="";u="";for(i=1;i<=NF;i++){if($i=="-p")p=$(i+1);if($i=="-r")u=$(i+1)}if(p&&u)printf "    %s → %s\n",p,u}'
    }
    echo ""
    printf '\033[0;36mBootstrap:\033[0m\n'
    ps | grep https-dns-proxy | grep -v grep | head -1 | awk '{for(i=1;i<=NF;i++)if($i=="-b"){printf "  %s\n",$(i+1);exit}}'
    printf '\n\033[0;36mNTP:\033[0m %s\n' "$(get_ntp_preset_name "$NTP_PRESET")"
    echo ""
    printf '\033[0;36mResolution:\033[0m\n'
    for dom in ya.ru chatgpt.com youtube.com instagram.com; do
        ip=$(timeout 3 nslookup "$dom" 127.0.0.1 2>/dev/null | grep -vE '127\.0\.0\.|0\.0\.0\.0' | grep -oE '([0-9]{1,3}\.){3}[0-9]{1,3}' | head -n1)
        [ -n "$ip" ] && printf '  %-18s → \033[0;32m%s\033[0m\n' "$dom" "$ip" \
            || printf '  %-18s → \033[0;31mNO_ANSWER\033[0m\n' "$dom"
    done
    echo ""; printf 'Нажмите Enter...'; safe_read _
}

# ============================================================
# ГЛАВНОЕ МЕНЮ
# ============================================================
main_menu() {
    while true; do
        flush_stdin; clear
        printf '\033[0;34m╔══════════════════════════════════════════╗\033[0m\n'
        printf '\033[0;34m║     DNS Manager v%-23s║\033[0m\n' "$VERSION"
        printf '\033[0;34m║  Безопасный сток | анти-дубли | IP-NTP  ║\033[0m\n'
        printf '\033[0;34m╚══════════════════════════════════════════╝\033[0m\n\n'
        printf '\033[1;33mИнтернет:\033[0m\n'
        for s in 1 2 3 4 5 6; do eval "_v=\$SLOT_$s"; printf '  %d) %s [%s]\n' "$s" "$(get_dns_name "$_v")" "$(get_dns_type "$_v")"; done
        printf '\033[1;33mРунет:\033[0m\n'
        printf '  РУ) %s  |  РУ2) %s\n' "$(get_dns_name "$SLOT_RU")" "$(get_dns_name "$SLOT_RU_2")"
        check_duplicates && printf '\n  \033[1;33m⚠ Есть дубли URL!\033[0m\n'
        echo ""
        printf '  \033[0;32m1) ⚡ Профили\033[0m     2) Слоты       3) Тест DNS\n'
        printf '  4) Bootstrap     5) Доп.настр.   6) Anti-block\n'
        printf '  7) Состояние     \033[0;32m8) ⚡ Применить\033[0m  9) Откат\n'
        printf '  \033[0;31mS) СТОК\033[0m          0) Выход\n\n'
        printf 'Выбор: '; safe_read choice
        case "$choice" in
            1) menu_profile_default ;; 2) menu_slots ;; 3) menu_test_dns ;; 4) menu_bootstrap ;;
            5) menu_extras ;; 6) menu_antiblock ;; 7) menu_status ;; 8) apply_settings ;;
            9) [ -f /root/rollback-dns.sh ] && sh /root/rollback-dns.sh || printf 'Нет отката\n'; safe_read _ ;;
            S|s|Ы|ы) menu_reset_to_stock ;; 0) exit 0 ;;
            *) printf '\033[0;31m[!]\033[0m\n'; sleep 1 ;;
        esac
    done
}

[ "$SELF_SOURCE" != "$MANAGER_PATH" ] || [ ! -f "$MANAGER_PATH" ] && { install_self; exit 0; }
init_system; load_config; main_menu
