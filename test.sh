#!/bin/sh
# ============================================================
# DNS Manager v3.3-FINAL
# С возвратом в сток + IP-only NTP + расширенным каталогом
# ============================================================

MANAGER_PATH="/usr/bin/dns-manager"
SELF_SOURCE="$0"

install_self() {
    [ "$SELF_SOURCE" = "$MANAGER_PATH" ] && return 0

    echo "=== Установка DNS Manager v3.3 ==="
    if command -v apk >/dev/null 2>&1; then
        PKG="apk"; echo "[*] apk (OpenWrt 25.x)"
    elif command -v opkg >/dev/null 2>&1; then
        PKG="opkg"; echo "[*] opkg (21.02-24.x)"
    else
        echo "[!] Пакетный менеджер не найден!"; exit 1
    fi

    NEED_INSTALL=0
    command -v https-dns-proxy >/dev/null 2>&1 || NEED_INSTALL=1
    command -v curl >/dev/null 2>&1 || NEED_INSTALL=1

    if [ "$NEED_INSTALL" = "1" ]; then
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
    echo ""; echo "✅ DNS Manager установлен!"
    echo "Запуск: dns-manager"; echo ""
    exec "$MANAGER_PATH"
}

# ============================================================
CONFIG_FILE="/root/.dns-manager.conf"
DNS_CATALOG="/root/.dns-catalog.conf"
TEST_RESULTS="/root/.dns-test-results.conf"
VERSION="3.3-FINAL"

C_RED='\033[0;31m'; C_GREEN='\033[0;32m'; C_YELLOW='\033[1;33m'
C_BLUE='\033[0;34m'; C_CYAN='\033[0;36m'; C_NC='\033[0m'

# ============================================================
# КАТАЛОГ DNS (56 серверов, 4 категории)
# ============================================================
create_catalog() {
    cat > "$DNS_CATALOG" << 'CATALOG'
#==ANTI== Anti-Block & Рунет
mafioznik|Mafioznik|https://dns.mafioznik.com/dns-query
comss_one|Comss.one|https://dns.comss.one/dns-query
comss_ru|Comss.ru|https://doh.comss.ru/dns-query
astrakat|Astrakat|https://dns.astrakat.com/dns-query
malw_link|Malw.link|https://dns.malw.link/dns-query
vppay|VPPay|https://dns.vppay.ru/dns-query
bluedns|BlueDNS|https://doh.bluedns.ru/dns-query
neutrdns|Neutrdns|https://dns.neutrdns.com/dns-query
dns_403|DNS.403|https://dns.403.online/dns-query
yandex|Yandex Basic|https://common.dot.dns.yandex.net/dns-query
yandex_safe|Yandex Safe|https://safe.dns.yandex.ru/dns-query
yandex_family|Yandex Family|https://family.dns.yandex.ru/dns-query
skydns|SkyDNS|https://doh.skydns.ru/dns-query
sber|Sber DNS|https://dns.sber.ru/dns-query
#==GLOBAL== Глобальные публичные
cloudflare|Cloudflare 1.1.1.1|https://cloudflare-dns.com/dns-query
cloudflare_sec|CF Security|https://security.cloudflare-dns.com/dns-query
cloudflare_fam|CF Family|https://family.cloudflare-dns.com/dns-query
google|Google DNS|https://dns.google/dns-query
quad9|Quad9 Recommended|https://dns.quad9.net/dns-query
quad9_unsec|Quad9 Unsecured|https://dns10.quad9.net/dns-query
quad9_ecs|Quad9 ECS|https://dns11.quad9.net/dns-query
opendns|Cisco OpenDNS|https://doh.opendns.com/dns-query
opendns_fam|OpenDNS Family|https://doh.familyshield.opendns.com/dns-query
#==PRIVACY== AdBlock & Privacy
adguard|AdGuard Default|https://dns.adguard-dns.com/dns-query
adguard_fam|AdGuard Family|https://family.adguard-dns.com/dns-query
adguard_unf|AdGuard Unfiltered|https://unfiltered.adguard-dns.com/dns-query
controld_p0|ControlD Free|https://freedns.controld.com/p0
controld_p1|ControlD Malware|https://freedns.controld.com/p1
controld_p2|ControlD Ads+Mal|https://freedns.controld.com/p2
controld_p3|ControlD Family|https://freedns.controld.com/p3
mullvad|Mullvad Base|https://doh.mullvad.net/dns-query
mullvad_adb|Mullvad Adblock|https://adblock.doh.mullvad.net/dns-query
mullvad_ext|Mullvad Extended|https://extended.doh.mullvad.net/dns-query
dns_sb|DNS.SB|https://doh.dns.sb/dns-query
cleanbr_sec|CleanBrowsing Sec|https://doh.cleanbrowsing.org/doh/security-filter/
cleanbr_fam|CleanBrowsing Fam|https://doh.cleanbrowsing.org/doh/family-filter/
cleanbr_adu|CleanBrowsing Adult|https://doh.cleanbrowsing.org/doh/adult-filter/
nextdns|NextDNS|https://dns.nextdns.io/dns-query
rethinkdns|RethinkDNS|https://max.rethinkdns.com/dns-query
decloudus|DeCloudUs|https://doh.decloudus.com/dns-query
#==REGION== Региональные
ahadns_nl|AhaDNS NL|https://doh.nl.ahadns.net/dns-query
ahadns_es|AhaDNS ES|https://doh.es.ahadns.net/dns-query
ahadns_in|AhaDNS IN|https://doh.in.ahadns.net/dns-query
cznic|CZ.NIC (Чехия)|https://odvr.nic.cz/doh
digigesch|Digitale-Gesellschaft (CH)|https://dns.digitale-gesellschaft.ch/dns-query
switch_ch|Switch.ch (CH)|https://dns.switch.ch/dns-query
libredns|LibreDNS (GR)|https://doh.libredns.gr/dns-query
applied_at|Applied Privacy (AT)|https://doh.applied-privacy.net/query
dnswatch|DNS.WATCH (DE)|https://resolver2.dns.watch/dns-query
blahdns_de|BlahDNS DE|https://doh-de.blahdns.com/dns-query
blahdns_fi|BlahDNS FI|https://doh-fi.blahdns.com/dns-query
blahdns_jp|BlahDNS JP|https://doh-jp.blahdns.com/dns-query
blahdns_sg|BlahDNS SG|https://doh-sg.blahdns.com/dns-query
quad101|Quad101 (TW)|https://dns.twnic.tw/dns-query
dnspod|DNSPod Tencent (CN)|https://doh.pub/dns-query
alidns|AliDNS Alibaba (CN)|https://dns.alidns.com/dns-query
cira_ca|CIRA Canadian Shield|https://private.canadianshield.cira.ca/dns-query
CATALOG
}

init_system() {
    printf "${C_BLUE}=== Инициализация системы ===${C_NC}\n"
    command -v apk >/dev/null 2>&1 && PKG="apk" || PKG="opkg"

    NEED=0
    command -v https-dns-proxy >/dev/null 2>&1 || NEED=1
    command -v curl >/dev/null 2>&1 || NEED=1
    if [ "$NEED" = "1" ]; then
        printf "[*] Установка пакетов...\n"
        if [ "$PKG" = "apk" ]; then
            apk update && apk add https-dns-proxy ca-certificates curl bind-tools
        else
            opkg update && opkg install https-dns-proxy ca-certificates curl bind-dig
        fi
    fi

    printf "[*] Очистка старых артефактов...\n"
    rm -f /etc/dnsmasq.d/telemetry.conf /etc/dnsmasq.d/.bogus-old /usr/bin/update-bogus-dns
    [ -f /etc/crontabs/root ] && sed -i '/update-bogus-dns/d' /etc/crontabs/root
    [ ! -f "$DNS_CATALOG" ] && create_catalog
    printf "${C_GREEN}[✓] Система готова${C_NC}\n"
}

load_config() {
    if [ -f "$CONFIG_FILE" ]; then
        . "$CONFIG_FILE"
    else
        SLOT_1="mafioznik"; SLOT_2="comss_one"; SLOT_3="astrakat"
        SLOT_4="malw_link"; SLOT_5="comss_ru"; SLOT_6="vppay"
        SLOT_RU="yandex"; SLOT_RU_2=""
        BOOTSTRAP_DNS="77.88.8.8,77.88.8.1,94.140.14.14,94.140.15.15,1.1.1.1,1.0.0.1,8.8.8.8,8.8.4.4,9.9.9.9,149.112.112.112"
        TLD_RU_ENABLED="1"; BLOCK_QUIC="0"
        MTU_FIX="1"; NTP_REDIRECT="1"; SYSCTL_TUNING="1"; GO_OPTIMIZE="1"
        BALANCER_ENABLED="1"; NTP_PRESET="mixed"; NTP_CUSTOM=""
        save_config
    fi
    : "${SLOT_RU_2:=}"; : "${BALANCER_ENABLED:=1}"
    : "${NTP_PRESET:=mixed}"; : "${NTP_CUSTOM:=}"
    : "${MTU_FIX:=1}"; : "${NTP_REDIRECT:=1}"
    : "${SYSCTL_TUNING:=1}"; : "${GO_OPTIMIZE:=1}"
    : "${BOOTSTRAP_DNS:=77.88.8.8,77.88.8.1,94.140.14.14,94.140.15.15,1.1.1.1,1.0.0.1,8.8.8.8,8.8.4.4,9.9.9.9,149.112.112.112}"
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

get_dns_name() {
    id="$1"
    [ -z "$id" ] && { printf "(пусто)"; return; }
    echo "$id" | grep -q "^custom:" && { printf "(custom)"; return; }
    result=$(grep -v '^#' "$DNS_CATALOG" | grep "^${id}|" | cut -d'|' -f2)
    [ -z "$result" ] && result="(неизвестный)"
    printf "%s" "$result"
}

# ============================================================
# NTP ТОЛЬКО ЧЕРЕЗ IP (не зависит от DNS!)
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
        cloudflare)  echo "Cloudflare (IP only)" ;;
        google)      echo "Google Time (IP only)" ;;
        ntp_pool)    echo "NTP Pool (IP fallback)" ;;
        ru_vniiftri) echo "ВНИИФТРИ (атомные часы, RU)" ;;
        ru_ps)       echo "Российские (psn.ru, qstu.ru)" ;;
        mixed)       echo "Смешанный (CF+Google+RU) [рек]" ;;
        dhcp)        echo "От провайдера (DHCP)" ;;
        custom)      echo "Свой список" ;;
        *)           echo "Неизвестный" ;;
    esac
}

# ============================================================
# Возврат в СТОК (как с завода)
# ============================================================
menu_reset_to_stock() {
    clear
    printf "${C_RED}╔══════════════════════════════════════════╗${C_NC}\n"
    printf "${C_RED}║     ⚠ ВОЗВРАТ В СТОК (заводское)        ║${C_NC}\n"
    printf "${C_RED}╚══════════════════════════════════════════╝${C_NC}\n"
    echo ""
    printf "${C_YELLOW}Будут удалены:${C_NC}\n"
    printf "  • Все DNS-настройки (DoH, слоты, bootstrap)\n"
    printf "  • Anti-block заглушки\n"
    printf "  • Sysctl-оптимизации\n"
    printf "  • MTU Fix, NTP Redirect, Block-QUIC\n"
    printf "  • Конфиг менеджера и каталог\n"
    printf "  • Скрипт отката\n"
    echo ""
    printf "${C_GREEN}Останутся нетронутыми:${C_NC}\n"
    printf "  • Tailscale, tg-ws-proxy-go (если установлены)\n"
    printf "  • Zapret (если установлен)\n"
    printf "  • WiFi, LAN, WAN настройки\n"
    printf "  • Пользовательские правила firewall\n"
    echo ""
    printf "${C_RED}После отката роутер перезагрузится!${C_NC}\n"
    echo ""
    printf "Введите ${C_GREEN}СТОК${C_NC} для подтверждения: "
    read -r confirm
    [ "$confirm" != "СТОК" ] && [ "$confirm" != "STOCK" ] && {
        printf "${C_YELLOW}Отменено${C_NC}\n"; sleep 1; return
    }

    echo ""
    printf "[1/6] Остановка служб...\n"
    killall -9 https-dns-proxy 2>/dev/null
    /etc/init.d/https-dns-proxy stop 2>/dev/null

    printf "[2/6] Очистка DNS конфигов...\n"
    # Сброс dnsmasq к заводскому
    while uci -q delete dhcp.@dnsmasq[0]; do :; done
    uci add dhcp dnsmasq
    uci set dhcp.@dnsmasq[0].domainneeded='1'
    uci set dhcp.@dnsmasq[0].boguspriv='1'
    uci set dhcp.@dnsmasq[0].filterwin2k='0'
    uci set dhcp.@dnsmasq[0].localise_queries='1'
    uci set dhcp.@dnsmasq[0].rebind_protection='1'
    uci set dhcp.@dnsmasq[0].rebind_localhost='1'
    uci set dhcp.@dnsmasq[0].local='/lan/'
    uci set dhcp.@dnsmasq[0].domain='lan'
    uci set dhcp.@dnsmasq[0].expandhosts='1'
    uci set dhcp.@dnsmasq[0].nonegcache='0'
    uci set dhcp.@dnsmasq[0].cachesize='1000'
    uci set dhcp.@dnsmasq[0].authoritative='1'
    uci set dhcp.@dnsmasq[0].readethers='1'
    uci set dhcp.@dnsmasq[0].leasefile='/tmp/dhcp.leases'
    uci set dhcp.@dnsmasq[0].resolvfile='/tmp/resolv.conf.d/resolv.conf.auto'
    uci set dhcp.@dnsmasq[0].nonwildcard='1'
    uci set dhcp.@dnsmasq[0].localservice='1'
    uci set dhcp.@dnsmasq[0].ednspacket_max='1232'
    uci set dhcp.@dnsmasq[0].filter_aaaa='0'
    uci commit dhcp

    printf "[3/6] Сброс firewall правил...\n"
    for rule in redirect_ntp block_quic; do
        uci -q delete firewall."$rule" 2>/dev/null
    done
    # Очистка MTU fix
    uci -q delete firewall.@defaults[0].mtu_fix
    WAN_SEC=$(uci show firewall 2>/dev/null | grep -m1 "\.name='wan'" | cut -d. -f1,2)
    [ -n "$WAN_SEC" ] && uci -q delete "${WAN_SEC}.mtu_fix"
    uci commit firewall

    printf "[4/6] Сброс NTP (DHCP от провайдера)...\n"
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

    # DHCP option 42 (NTP) — удаляем
    for opt in $(uci -q get dhcp.lan.dhcp_option 2>/dev/null | tr ' ' '\n' | grep '^42,'); do
        uci -q del_list dhcp.lan.dhcp_option="$opt"
    done
    uci commit dhcp

    printf "[5/6] Удаление артефактов менеджера...\n"
    rm -f /etc/dnsmasq.d/anti-block.conf
    rm -f /etc/sysctl.d/99-custom.conf
    rm -f /etc/hotplug.d/ntp/99-tailscale
    rm -f /root/rollback-dns.sh
    rm -f /root/.dns-manager.conf
    rm -f /root/.dns-catalog.conf
    rm -f /root/.dns-test-results.conf
    # Очистка крон
    [ -f /etc/crontabs/root ] && sed -i '/update-bogus-dns/d; /https-dns-proxy/d' /etc/crontabs/root

    # Сброс https-dns-proxy к дефолту
    while uci -q delete https-dns-proxy.@https-dns-proxy[0]; do :; done
    uci -q delete https-dns-proxy.config 2>/dev/null
    uci set https-dns-proxy.config='main'
    uci set https-dns-proxy.config.update_dnsmasq='0'
    uci commit https-dns-proxy

    printf "[6/6] Применение и перезагрузка...\n"
    sysctl -p /etc/sysctl.conf >/dev/null 2>&1
    /etc/init.d/firewall restart
    /etc/init.d/dnsmasq restart
    /etc/init.d/sysntpd restart 2>/dev/null

    echo ""
    printf "${C_GREEN}✅ СТОК ВОССТАНОВЛЕН!${C_NC}\n"
    printf "Перезагрузка через 5 секунд...\n"
    sleep 5
    reboot
    exit 0
}

# ============================================================
# Быстрая настройка (профили)
# ============================================================
menu_profile_default() {
    clear
    printf "${C_BLUE}╔══════════════════════════════════════════╗${C_NC}\n"
    printf "${C_BLUE}║     Быстрая настройка (профиль)         ║${C_NC}\n"
    printf "${C_BLUE}╚══════════════════════════════════════════╝${C_NC}\n"
    echo ""
    printf "Выберите профиль:\n\n"
    printf "  1) ${C_GREEN}Оптимальный (рекомендуется)${C_NC}\n"
    printf "     • 4 DNS + балансировщик вкл\n"
    printf "     • Яндекс для рунета, все оптимизации\n\n"
    printf "  2) Максимальная устойчивость (все 6 DNS)\n"
    printf "  3) Одна голова (слабый роутер)\n"
    printf "  4) Только рунет (без обхода)\n"
    printf "  ${C_CYAN}Enter${C_NC} = отмена\n"
    echo ""
    printf "Выбор: "
    read -r choice
    [ -z "$choice" ] && return

    case "$choice" in
        1) SLOT_1="mafioznik"; SLOT_2="comss_ru"; SLOT_3="comss_one"
           SLOT_4="vppay"; SLOT_5=""; SLOT_6=""
           SLOT_RU="yandex"; SLOT_RU_2=""
           BALANCER_ENABLED="1"; BLOCK_QUIC="1" ;;
        2) SLOT_1="mafioznik"; SLOT_2="comss_one"; SLOT_3="astrakat"
           SLOT_4="malw_link"; SLOT_5="comss_ru"; SLOT_6="vppay"
           SLOT_RU="yandex"; SLOT_RU_2="yandex_safe"
           BALANCER_ENABLED="1"; BLOCK_QUIC="1" ;;
        3) SLOT_1="mafioznik"; SLOT_2=""; SLOT_3=""; SLOT_4=""
           SLOT_5=""; SLOT_6=""; SLOT_RU="yandex"; SLOT_RU_2=""
           BALANCER_ENABLED="0"; BLOCK_QUIC="0"; SYSCTL_TUNING="0" ;;
        4) SLOT_1=""; SLOT_2=""; SLOT_3=""; SLOT_4=""; SLOT_5=""; SLOT_6=""
           SLOT_RU="yandex"; SLOT_RU_2=""
           BALANCER_ENABLED="0"; BLOCK_QUIC="0" ;;
        *) printf "${C_RED}[!] Неверный выбор${C_NC}\n"; sleep 1; return ;;
    esac

    BOOTSTRAP_DNS="77.88.8.8,77.88.8.1,94.140.14.14,94.140.15.15,1.1.1.1,1.0.0.1,8.8.8.8,8.8.4.4,9.9.9.9,149.112.112.112"
    TLD_RU_ENABLED="1"; MTU_FIX="1"; NTP_REDIRECT="1"
    NTP_PRESET="mixed"; GO_OPTIMIZE="1"
    save_config
    printf "${C_GREEN}[✓] Профиль применён${C_NC}\n"
    printf "\nПрименить сейчас? [Enter=да/н]: "
    read -r confirm
    case "$confirm" in
        н|Н|n|N) printf "Сохранено. Примените через пункт 8.\n"; sleep 2 ;;
        *) apply_settings ;;
    esac
}

# ============================================================
# Тест DNS
# ============================================================
menu_test_dns() {
    clear
    printf "${C_BLUE}╔══════════════════════════════════════════╗${C_NC}\n"
    printf "${C_BLUE}║     Тестирование всех DNS               ║${C_NC}\n"
    printf "${C_BLUE}╚══════════════════════════════════════════╝${C_NC}\n"
    echo ""
    printf "${C_YELLOW}Тест %d серверов...${C_NC}\n" "$(grep -v '^#' "$DNS_CATALOG" | grep -c '|')"
    echo ""
    printf "%-25s %-10s %-10s %s\n" "DNS" "Статус" "Скорость" "Примечание"
    printf "%s\n" "------------------------------------------------------------------------"

    > "$TEST_RESULTS"
    grep -v '^#' "$DNS_CATALOG" | grep '|' | while IFS='|' read -r id name url; do
        [ -z "$id" ] && continue
        time_ms=$(curl -s -o /dev/null -w "%{time_total}" --max-time 5 \
            "${url}?name=google.com&type=A" -H "Accept: application/dns-json" 2>/dev/null)
        if [ -n "$time_ms" ] && [ "$time_ms" != "0.000000" ]; then
            ms=$(echo "$time_ms" | awk '{printf "%.0f", $1 * 1000}')
            if [ "$ms" -lt 100 ]; then
                status_str="${C_GREEN}OK${C_NC}"; note="Быстрый"
            elif [ "$ms" -lt 300 ]; then
                status_str="${C_GREEN}OK${C_NC}"; note="Нормальный"
            else
                status_str="${C_YELLOW}OK${C_NC}"; note="Медленный"
            fi
            printf "%-25s ${status_str}    %-10s %s\n" "$name" "${ms}ms" "$note"
            echo "${id}|${ms}|OK" >> "$TEST_RESULTS"
        else
            printf "%-25s ${C_RED}FAIL${C_NC}    %-10s %s\n" "$name" "-" "Недоступен"
            echo "${id}|0|FAIL" >> "$TEST_RESULTS"
        fi
    done

    echo ""
    printf "%s\n" "------------------------------------------------------------------------"
    total=$(grep -c '|' "$TEST_RESULTS" 2>/dev/null || echo 0)
    ok=$(grep -c "|OK" "$TEST_RESULTS" 2>/dev/null || echo 0)
    fail=$(grep -c "|FAIL" "$TEST_RESULTS" 2>/dev/null || echo 0)
    printf "Всего: $total | ${C_GREEN}ОК: $ok${C_NC} | ${C_RED}FAIL: $fail${C_NC}\n"
    echo ""
    printf "Нажмите Enter..."
    read -r _
}

# ============================================================
# Выбор DNS для слота (с категориями)
# ============================================================
select_dns_for_slot() {
    slot_num="$1"
    while true; do
        clear
        printf "${C_BLUE}╔══════════════════════════════════════════╗${C_NC}\n"
        printf "${C_BLUE}║     Выбор DNS для слота #$slot_num             ║${C_NC}\n"
        printf "${C_BLUE}╚══════════════════════════════════════════╝${C_NC}\n"
        echo ""

        # Считаем только DNS (без комментариев-категорий)
        i=1
        while IFS='|' read -r id name url; do
            [ -z "$id" ] && continue
            test_result=$(grep "^${id}|" "$TEST_RESULTS" 2>/dev/null | cut -d'|' -f2,3)
            if [ -n "$test_result" ]; then
                ms=$(echo "$test_result" | cut -d'|' -f1)
                status=$(echo "$test_result" | cut -d'|' -f2)
                [ "$status" = "OK" ] && status_str="${C_GREEN}${ms}ms${C_NC}" || status_str="${C_RED}FAIL${C_NC}"
            else
                status_str="${C_YELLOW}нет теста${C_NC}"
            fi
            printf "  %2d) %-25s [%b]\n" "$i" "$name" "$status_str"
            i=$((i + 1))
        done < <(grep -v '^#' "$DNS_CATALOG" | grep '|')

        echo ""
        printf "  ${C_CYAN}99) Очистить слот${C_NC}\n"
        printf "  ${C_CYAN}98) Ввести свой URL${C_NC}\n"
        printf "  ${C_CYAN}Enter) Отмена${C_NC}\n"
        echo ""
        printf "Выбор: "
        read -r choice
        [ -z "$choice" ] && return

        case "$choice" in
            99) eval "SLOT_${slot_num}=\"\""; save_config; return ;;
            98)
                printf "URL DoH (https://...): "; read -r custom_url
                [ -z "$custom_url" ] && continue
                eval "SLOT_${slot_num}=\"custom:${custom_url}\""; save_config; return ;;
            *)
                total=$(grep -v '^#' "$DNS_CATALOG" | grep -c '|')
                if [ "$choice" -ge 1 ] 2>/dev/null && [ "$choice" -le "$total" ] 2>/dev/null; then
                    selected_id=$(grep -v '^#' "$DNS_CATALOG" | grep '|' | sed -n "${choice}p" | cut -d'|' -f1)
                    eval "SLOT_${slot_num}=\"$selected_id\""; save_config; return
                fi
                printf "${C_RED}[!] Неверный${C_NC}\n"; sleep 1
                ;;
        esac
    done
}

menu_slots() {
    while true; do
        clear
        printf "${C_BLUE}╔══════════════════════════════════════════╗${C_NC}\n"
        printf "${C_BLUE}║     Настройка слотов DNS                ║${C_NC}\n"
        printf "${C_BLUE}╚══════════════════════════════════════════╝${C_NC}\n"
        echo ""
        printf "${C_YELLOW}Слоты 1-6: Весь интернет${C_NC}\n"
        printf "  1) Слот 1 (порт 5053): %s\n" "$(get_dns_name "$SLOT_1")"
        printf "  2) Слот 2 (порт 5054): %s\n" "$(get_dns_name "$SLOT_2")"
        printf "  3) Слот 3 (порт 5055): %s\n" "$(get_dns_name "$SLOT_3")"
        printf "  4) Слот 4 (порт 5056): %s\n" "$(get_dns_name "$SLOT_4")"
        printf "  5) Слот 5 (порт 5057): %s\n" "$(get_dns_name "$SLOT_5")"
        printf "  6) Слот 6 (порт 5058): %s\n" "$(get_dns_name "$SLOT_6")"
        echo ""
        printf "${C_YELLOW}Слоты РУ: Рунет (.ru/.su/.рф)${C_NC}\n"
        printf "  7) Слот РУ   (порт 5059): %s\n" "$(get_dns_name "$SLOT_RU")"
        printf "  8) Слот РУ-2 (порт 5060): %s\n" "$(get_dns_name "$SLOT_RU_2")"
        echo ""
        printf "  ${C_CYAN}Enter) Назад${C_NC}\n"
        printf "Выбор: "; read -r choice
        [ -z "$choice" ] && return
        case "$choice" in
            1) select_dns_for_slot "1" ;; 2) select_dns_for_slot "2" ;;
            3) select_dns_for_slot "3" ;; 4) select_dns_for_slot "4" ;;
            5) select_dns_for_slot "5" ;; 6) select_dns_for_slot "6" ;;
            7) select_dns_for_slot "RU" ;; 8) select_dns_for_slot "RU_2" ;;
            *) printf "${C_RED}[!] Неверный${C_NC}\n"; sleep 1 ;;
        esac
    done
}

menu_bootstrap() {
    while true; do
        clear
        printf "${C_BLUE}╔══════════════════════════════════════════╗${C_NC}\n"
        printf "${C_BLUE}║     Bootstrap DNS                       ║${C_NC}\n"
        printf "${C_BLUE}╚══════════════════════════════════════════╝${C_NC}\n"
        echo ""
        printf "Текущий: ${C_YELLOW}%s${C_NC}\n" "$BOOTSTRAP_DNS"
        echo ""
        printf "Пресеты:\n"
        printf "  1) Полный (10 IP: Yandex+AdGuard+CF+Google+Quad9) [рек]\n"
        printf "  2) РФ Безопасный (Yandex + AdGuard)\n"
        printf "  3) Только Yandex\n"
        printf "  4) Только AdGuard\n"
        printf "  5) G-Core + Yandex + AdGuard\n"
        printf "  6) Ввести вручную\n"
        printf "  ${C_CYAN}Enter) Назад${C_NC}\n"
        printf "Выбор: "; read -r choice
        [ -z "$choice" ] && return
        case "$choice" in
            1) BOOTSTRAP_DNS="77.88.8.8,77.88.8.1,94.140.14.14,94.140.15.15,1.1.1.1,1.0.0.1,8.8.8.8,8.8.4.4,9.9.9.9,149.112.112.112"; save_config; return ;;
            2) BOOTSTRAP_DNS="77.88.8.8,77.88.8.1,94.140.14.14,94.140.15.15"; save_config; return ;;
            3) BOOTSTRAP_DNS="77.88.8.8,77.88.8.1"; save_config; return ;;
            4) BOOTSTRAP_DNS="94.140.14.14,94.140.15.15"; save_config; return ;;
            5) BOOTSTRAP_DNS="95.85.85.85,77.88.8.8,94.140.14.14"; save_config; return ;;
            6) printf "IP через запятую: "; read -r BOOTSTRAP_DNS; [ -n "$BOOTSTRAP_DNS" ] && save_config; return ;;
        esac
    done
}

menu_ntp() {
    while true; do
        clear
        printf "${C_BLUE}╔══════════════════════════════════════════╗${C_NC}\n"
        printf "${C_BLUE}║     NTP серверы (только IP!)            ║${C_NC}\n"
        printf "${C_BLUE}╚══════════════════════════════════════════╝${C_NC}\n"
        echo ""
        printf "Текущий: ${C_YELLOW}%s${C_NC}\n" "$(get_ntp_preset_name "$NTP_PRESET")"
        echo ""
        printf "Серверы (IP):\n"
        for srv in $(get_ntp_servers "$NTP_PRESET" "$NTP_CUSTOM"); do
            printf "  • %s\n" "$srv"
        done
        echo ""
        printf "Пресеты (всё по IP, работает без DNS):\n"
        printf "  1) Смешанный (CF+Google+RU) [рекомендуется]\n"
        printf "  2) Cloudflare (только IP)\n"
        printf "  3) Google Time (только IP)\n"
        printf "  4) NTP Pool (IP fallback)\n"
        printf "  5) ВНИИФТРИ (атомные часы, RU)\n"
        printf "  6) Российские (psn.ru, qstu.ru)\n"
        printf "  7) От провайдера (DHCP)\n"
        printf "  8) Свой список\n"
        printf "  ${C_CYAN}Enter) Назад${C_NC}\n"
        printf "Выбор: "; read -r choice
        [ -z "$choice" ] && return
        case "$choice" in
            1) NTP_PRESET="mixed" ;; 2) NTP_PRESET="cloudflare" ;;
            3) NTP_PRESET="google" ;; 4) NTP_PRESET="ntp_pool" ;;
            5) NTP_PRESET="ru_vniiftri" ;; 6) NTP_PRESET="ru_ps" ;;
            7) NTP_PRESET="dhcp" ;;
            8) printf "IP через пробел: "; read -r NTP_CUSTOM; NTP_PRESET="custom" ;;
            *) return ;;
        esac
        save_config
    done
}

menu_extras() {
    while true; do
        clear
        printf "${C_BLUE}╔══════════════════════════════════════════╗${C_NC}\n"
        printf "${C_BLUE}║     Дополнительные настройки            ║${C_NC}\n"
        printf "${C_BLUE}╚══════════════════════════════════════════╝${C_NC}\n"
        echo ""
        [ "$BALANCER_ENABLED" = "1" ] && bal="${C_GREEN}[✓]${C_NC}" || bal="${C_RED}[ ]${C_NC}"
        [ "$TLD_RU_ENABLED" = "1" ] && tld="${C_GREEN}[✓]${C_NC}" || tld="${C_RED}[ ]${C_NC}"
        [ "$BLOCK_QUIC" = "1" ] && quic="${C_GREEN}[✓]${C_NC}" || quic="${C_RED}[ ]${C_NC}"
        [ "$MTU_FIX" = "1" ] && mtu="${C_GREEN}[✓]${C_NC}" || mtu="${C_RED}[ ]${C_NC}"
        [ "$NTP_REDIRECT" = "1" ] && ntp="${C_GREEN}[✓]${C_NC}" || ntp="${C_RED}[ ]${C_NC}"
        [ "$SYSCTL_TUNING" = "1" ] && sys="${C_GREEN}[✓]${C_NC}" || sys="${C_RED}[ ]${C_NC}"
        [ "$GO_OPTIMIZE" = "1" ] && go="${C_GREEN}[✓]${C_NC}" || go="${C_RED}[ ]${C_NC}"

        printf "  1) %b Балансировщик (allservers=1)\n" "$bal"
        printf "  2) %b TLD Split (.ru через слот РУ)\n" "$tld"
        printf "  3) %b Блокировка QUIC (UDP 443)\n" "$quic"
        printf "  4) %b MTU Fix (PPPoE/L2TP)\n" "$mtu"
        printf "  5) %b NTP Redirect (перехват NTP)\n" "$ntp"
        printf "  6) %b Sysctl Tuning\n" "$sys"
        printf "  7) %b Go-оптимизация (Tailscale, tg-ws-proxy)\n" "$go"
        echo ""
        printf "  8) ${C_YELLOW}→ NTP серверы: %s${C_NC}\n" "$(get_ntp_preset_name "$NTP_PRESET")"
        echo ""
        printf "  ${C_CYAN}Enter) Назад${C_NC}\n"
        printf "Выбор: "; read -r choice
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
        printf "${C_BLUE}╔══════════════════════════════════════════╗${C_NC}\n"
        printf "${C_BLUE}║     Anti-block                          ║${C_NC}\n"
        printf "${C_BLUE}╚══════════════════════════════════════════╝${C_NC}\n"
        echo ""
        printf "Текущие заглушки:\n"
        grep "bogus-nxdomain=" /etc/dnsmasq.d/anti-block.conf 2>/dev/null | sed 's/bogus-nxdomain=/  /' || printf "  (пусто)\n"
        echo ""
        printf "  1) Добавить IP\n"
        printf "  2) Удалить IP\n"
        printf "  3) Сброс к эталону\n"
        printf "  ${C_CYAN}Enter) Назад${C_NC}\n"
        printf "Выбор: "; read -r choice
        [ -z "$choice" ] && return
        case "$choice" in
            1) printf "IP: "; read -r ip; [ -n "$ip" ] && { echo "bogus-nxdomain=$ip" >> /etc/dnsmasq.d/anti-block.conf; /etc/init.d/dnsmasq restart; }; read -r _ ;;
            2) printf "IP: "; read -r ip; [ -n "$ip" ] && { sed -i "/bogus-nxdomain=$ip/d" /etc/dnsmasq.d/anti-block.conf; /etc/init.d/dnsmasq restart; }; read -r _ ;;
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
               /etc/init.d/dnsmasq restart; read -r _ ;;
        esac
    done
}

# ============================================================
# ПРИМЕНЕНИЕ (11 шагов)
# ============================================================
apply_settings() {
    clear
    printf "${C_BLUE}╔══════════════════════════════════════════╗${C_NC}\n"
    printf "${C_BLUE}║     Применение настроек                 ║${C_NC}\n"
    printf "${C_BLUE}╚══════════════════════════════════════════╝${C_NC}\n\n"

    # [1/11] Бэкапы
    printf "[1/11] Бэкапы...\n"
    if [ ! -d "/etc/config/backup-original" ]; then
        mkdir -p /etc/config/backup-original
        cp /etc/config/dhcp /etc/config/backup-original/dhcp.bak 2>/dev/null
        cp /etc/config/firewall /etc/config/backup-original/firewall.bak 2>/dev/null
        cp /etc/config/https-dns-proxy /etc/config/backup-original/https-dns-proxy.bak 2>/dev/null
        cp /etc/config/system /etc/config/backup-original/system.bak 2>/dev/null
        [ -f /etc/crontabs/root ] && cp /etc/crontabs/root /etc/config/backup-original/crontabs.bak
    fi
    TIMESTAMP=$(date +%Y%m%d_%H%M%S)
    BACKUP_ACTUAL="/etc/config/backup-dns-$TIMESTAMP"
    mkdir -p "$BACKUP_ACTUAL"
    for f in dhcp firewall https-dns-proxy system; do
        cp /etc/config/$f "$BACKUP_ACTUAL/${f}.bak" 2>/dev/null
    done
    [ -f /etc/crontabs/root ] && cp /etc/crontabs/root "$BACKUP_ACTUAL/crontabs.bak"
    ln -sfn "$BACKUP_ACTUAL" /etc/config/backup-pre-dns-v9
    (cd /etc/config && ls -dt backup-dns-* 2>/dev/null | tail -n +2 | xargs rm -rf 2>/dev/null)

    # [2/11] Anti-block
    printf "[2/11] Anti-block...\n"
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

    # [3/11] MTU
    if [ "$MTU_FIX" = "1" ]; then
        printf "[3/11] MTU Fix...\n"
        uci -q set firewall.@defaults[0].mtu_fix='1'
        WAN_SEC=$(uci show firewall 2>/dev/null | grep -m1 "\.name='wan'" | cut -d. -f1,2)
        [ -n "$WAN_SEC" ] && uci -q set "${WAN_SEC}.mtu_fix=1"
        uci commit firewall
    fi

    # [4/11] NTP Redirect (только IP!)
    if [ "$NTP_REDIRECT" = "1" ]; then
        printf "[4/11] NTP (IP only)...\n"
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

        # NTP серверы (ТОЛЬКО IP)
        ntp_servers=$(get_ntp_servers "$NTP_PRESET" "$NTP_CUSTOM")
        while uci -q delete system.@timeserver[0]; do :; done
        uci -q delete system.ntp 2>/dev/null
        uci set system.ntp=timeserver
        uci set system.ntp.enabled='1'
        if [ "$NTP_PRESET" = "dhcp" ] || [ -z "$ntp_servers" ]; then
            uci set system.ntp.enable_server='1'
        else
            for srv in $ntp_servers; do
                uci add_list system.ntp.server="$srv"
            done
        fi
        uci commit system
        /etc/init.d/firewall reload 2>/dev/null
        printf "  [+] NTP: %s (IP only)\n" "$(get_ntp_preset_name "$NTP_PRESET")"
    fi

    # [5/11] Go-оптимизация
    if [ "$GO_OPTIMIZE" = "1" ]; then
        printf "[5/11] Go-оптимизация...\n"
        for f in /etc/init.d/tg-ws-proxy-go /etc/init.d/tailscale; do
            [ ! -f "$f" ] && continue
            sed -i '/GOMAXPROCS/d; /GOMEMLIMIT/d; /GOGC/d' "$f"
            grep -q "procd_open_instance" "$f" && \
                awk -v env="$([ "$f" = "/etc/init.d/tg-ws-proxy-go" ] && echo "GOMAXPROCS=1 GOMEMLIMIT=50MiB" || echo "GOMEMLIMIT=85MiB")" \
                    '/procd_open_instance/ {print; print "    procd_set_param env " env; next} 1' "$f" > /tmp/tmp.init && mv /tmp/tmp.init "$f"
        done
    fi

    # [6/11] Sysctl
    if [ "$SYSCTL_TUNING" = "1" ]; then
        printf "[6/11] Sysctl...\n"
        modprobe nf_conntrack 2>/dev/null
        SYSFILE="/etc/sysctl.d/99-custom.conf"
        touch "$SYSFILE"
        for p in "net.netfilter.nf_conntrack_max=65536" "net.ipv4.tcp_fastopen=3" \
                 "net.ipv4.tcp_fin_timeout=15" "net.core.somaxconn=1024" \
                 "net.ipv4.tcp_keepalive_time=300" "net.core.rmem_max=2097152" \
                 "net.core.wmem_max=2097152"; do
            key=$(echo "$p" | cut -d= -f1)
            sed -i "/^$key/d" "$SYSFILE"
            echo "$p" >> "$SYSFILE"
            sysctl -w "$p" >/dev/null 2>&1
        done
    fi

    # [7/11] Hotplug tailscale
    if [ -f /etc/init.d/tailscale ]; then
        printf "[7/11] Hotplug tailscale...\n"
        mkdir -p /etc/hotplug.d/ntp
        cat > /etc/hotplug.d/ntp/99-tailscale << 'HOTPLUG'
#!/bin/sh
[ "$ACTION" = "step" ] || [ "$ACTION" = "stratum" ] || exit 0
UPTIME=$(cut -d. -f1 /proc/uptime)
[ "$UPTIME" -lt 600 ] && /etc/init.d/tailscale restart >/dev/null 2>&1
HOTPLUG
        chmod +x /etc/hotplug.d/ntp/99-tailscale
    fi

    # [8/11] https-dns-proxy
    printf "[8/11] https-dns-proxy...\n"
    while uci -q delete https-dns-proxy.@https-dns-proxy[0]; do :; done
    uci -q delete https-dns-proxy.config 2>/dev/null
    uci set https-dns-proxy.config='main'
    uci set https-dns-proxy.config.update_dnsmasq='0'

    add_doh() {
        slot="$1"; port="$2"
        eval "slot_value=\$SLOT_${slot}"
        [ -z "$slot_value" ] && return
        if echo "$slot_value" | grep -q "^custom:"; then
            url=$(echo "$slot_value" | cut -d: -f2-)
            name="Custom"
        else
            url=$(grep -v '^#' "$DNS_CATALOG" | grep "^${slot_value}|" | cut -d'|' -f3)
            name=$(get_dns_name "$slot_value")
            [ -z "$url" ] && return
        fi
        uci add https-dns-proxy https-dns-proxy
        uci set https-dns-proxy.@https-dns-proxy[-1].listen_addr='127.0.0.1'
        uci set https-dns-proxy.@https-dns-proxy[-1].listen_port="$port"
        uci set https-dns-proxy.@https-dns-proxy[-1].resolver_url="$url"
        uci set https-dns-proxy.@https-dns-proxy[-1].request_timeout='2'
        uci set https-dns-proxy.@https-dns-proxy[-1].bootstrap_dns="$BOOTSTRAP_DNS"
        printf "  [+] %s (порт %s)\n" "$name" "$port"
    }

    for s in 1 2 3 4 5 6; do
        add_doh "$s" "$((5052 + s))"
    done
    [ -n "$SLOT_RU" ] && add_doh "RU" "5059"
    [ -n "$SLOT_RU_2" ] && add_doh "RU_2" "5060"
    uci commit https-dns-proxy

    # [9/11] dnsmasq
    printf "[9/11] dnsmasq...\n"
    uci -q get dhcp.@dnsmasq[0] >/dev/null || uci add dhcp dnsmasq
    while uci -q delete dhcp.@dnsmasq[0].server; do :; done
    uci -q delete dhcp.@dnsmasq[0].address 2>/dev/null
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
        eval "v=\$SLOT_${s}"
        [ -n "$v" ] && uci add_list dhcp.@dnsmasq[0].server="127.0.0.1#$((5052 + s))"
    done

    if [ "$TLD_RU_ENABLED" = "1" ]; then
        for tld in /ru /su /xn--p1ai; do
            if [ -n "$SLOT_RU" ] && [ -n "$SLOT_RU_2" ]; then
                uci add_list dhcp.@dnsmasq[0].server="${tld}/127.0.0.1#5059,127.0.0.1#5060"
            elif [ -n "$SLOT_RU" ]; then
                uci add_list dhcp.@dnsmasq[0].server="${tld}/127.0.0.1#5059"
            elif [ -n "$SLOT_RU_2" ]; then
                uci add_list dhcp.@dnsmasq[0].server="${tld}/127.0.0.1#5060"
            fi
        done
    fi
    uci commit dhcp

    # [10/11] QUIC
    printf "[10/11] QUIC...\n"
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

    # [11/11] Скрипт отката
    printf "[11/11] Скрипт отката...\n"
    cat > /root/rollback-dns.sh << 'ROLLBACK'
#!/bin/sh
BACKUP="/etc/config/backup-pre-dns-v9"
ORIGINAL="/etc/config/backup-original"
if [ -d "$BACKUP" ]; then SOURCE="$BACKUP"
elif [ -d "$ORIGINAL" ]; then SOURCE="$ORIGINAL"
else echo "[!] No backup"; exit 1; fi
echo "=== ROLLBACK: $SOURCE ==="
cp "$SOURCE/dhcp.bak" /etc/config/dhcp 2>/dev/null
cp "$SOURCE/firewall.bak" /etc/config/firewall 2>/dev/null
cp "$SOURCE/https-dns-proxy.bak" /etc/config/https-dns-proxy 2>/dev/null
cp "$SOURCE/system.bak" /etc/config/system 2>/dev/null
rm -f /etc/dnsmasq.d/anti-block.conf /etc/sysctl.d/99-custom.conf
sysctl -p /etc/sysctl.conf >/dev/null 2>&1
/etc/init.d/firewall restart; /etc/init.d/https-dns-proxy restart
/etc/init.d/dnsmasq restart; /etc/init.d/sysntpd restart 2>/dev/null
echo "✅ ROLLBACK DONE (reboot recommended)"
ROLLBACK
    chmod +x /root/rollback-dns.sh

    echo ""
    printf "Перезапуск...\n"
    killall -9 https-dns-proxy 2>/dev/null; sleep 1
    /etc/init.d/https-dns-proxy restart; sleep 2
    /etc/init.d/dnsmasq restart
    /etc/init.d/firewall restart 2>/dev/null
    [ -f /etc/init.d/sysntpd ] && /etc/init.d/sysntpd restart 2>/dev/null
    sleep 2

    printf "\n${C_GREEN}✓ Все настройки применены!${C_NC}\n"
    printf "Нажмите Enter..."; read -r _
}

# ============================================================
# Состояние
# ============================================================
menu_status() {
    clear
    printf "${C_BLUE}╔══════════════════════════════════════════╗${C_NC}\n"
    printf "${C_BLUE}║     Состояние                           ║${C_NC}\n"
    printf "${C_BLUE}╚══════════════════════════════════════════╝${C_NC}\n\n"

    allservers=$(uci -q get dhcp.@dnsmasq[0].allservers)
    [ "$allservers" = "1" ] && \
        printf "${C_GREEN}[✓] Балансировщик: ВКЛ${C_NC}\n" || \
        printf "${C_YELLOW}[~] Балансировщик: ВЫКЛ (одна голова)${C_NC}\n"

    echo ""
    printf "${C_CYAN}DoH процессы:${C_NC}\n"
    ps | grep https-dns-proxy | grep -v grep | awk '{
        p=""; u=""
        for(i=1;i<=NF;i++){if($i=="-p")p=$(i+1);if($i=="-r")u=$(i+1)}
        if(p!=""&&u!="")printf "  %s → %s\n",p,u
    }'

    echo ""
    printf "${C_CYAN}Bootstrap:${C_NC}\n"
    ps | grep https-dns-proxy | grep -v grep | head -1 | awk '{for(i=1;i<=NF;i++)if($i=="-b"){printf "  %s\n",$(i+1);exit}}'

    echo ""
    printf "${C_CYAN}NTP (IP only):${C_NC}\n"
    printf "  %s\n" "$(get_ntp_preset_name "$NTP_PRESET")"
    uci show system.ntp 2>/dev/null | grep server | sed 's/.*='\''//' | sed 's/'\''//' | head -6 | while read -r s; do
        printf "  • %s\n" "$s"
    done

    echo ""
    printf "${C_CYAN}DNS Resolution:${C_NC}\n"
    for dom in ya.ru chatgpt.com youtube.com instagram.com linkedin.com; do
        ip=$(nslookup "$dom" 127.0.0.1 2>/dev/null | grep -vE '127\.0\.0\.|0\.0\.0\.0' | grep -oE '([0-9]{1,3}\.){3}[0-9]{1,3}' | head -n1)
        printf "  %-20s → %s\n" "$dom" "${ip:-NO_ANSWER}"
    done

    echo ""
    count=$(grep -c bogus-nxdomain /etc/dnsmasq.d/anti-block.conf 2>/dev/null || echo 0)
    printf "Anti-block: %s записей\n" "$count"

    echo ""
    printf "Нажмите Enter..."; read -r _
}

# ============================================================
# Главное меню
# ============================================================
main_menu() {
    while true; do
        clear
        printf "${C_BLUE}╔══════════════════════════════════════════╗${C_NC}\n"
        printf "${C_BLUE}║     DNS Manager v%-22s║${C_NC}\n" "$VERSION"
        printf "${C_BLUE}║     Возврат в сток + IP-NTP + 56 DNS    ║${C_NC}\n"
        printf "${C_BLUE}╚══════════════════════════════════════════╝${C_NC}\n"
        echo ""
        printf "${C_YELLOW}Интернет слоты:${C_NC}\n"
        for s in 1 2 3 4 5 6; do
            eval "v=\$SLOT_${s}"
            printf "  %d) %s\n" "$s" "$(get_dns_name "$v")"
        done
        echo ""
        printf "${C_YELLOW}Рунет слоты:${C_NC}\n"
        printf "  РУ)  %s (порт 5059)\n" "$(get_dns_name "$SLOT_RU")"
        printf "  РУ2) %s (порт 5060)\n" "$(get_dns_name "$SLOT_RU_2")"
        echo ""
        [ "$BALANCER_ENABLED" = "1" ] && b="${C_GREEN}ВКЛ${C_NC}" || b="${C_YELLOW}ВЫКЛ${C_NC}"
        printf "Балансировщик: %b\n" "$b"
        printf "NTP: ${C_GREEN}%s${C_NC} (IP only)\n" "$(get_ntp_preset_name "$NTP_PRESET")"
        echo ""
        printf "Меню:\n"
        printf "  ${C_GREEN}1) ⚡ Быстрая настройка${C_NC}\n"
        printf "  2) Настройка слотов\n"
        printf "  3) Тест всех DNS (%d)\n" "$(grep -v '^#' "$DNS_CATALOG" | grep -c '|')"
        printf "  4) Bootstrap DNS\n"
        printf "  5) Доп. настройки (баланс, NTP...)\n"
        printf "  6) Anti-block\n"
        printf "  7) Состояние\n"
        printf "  ${C_GREEN}8) ⚡ Применить${C_NC}\n"
        printf "  9) Откат (из бэкапа)\n"
        printf "  ${C_RED}S) ⚠ Возврат в СТОК (заводское)${C_NC}\n"
        printf "  0) Выход\n"
        echo ""
        printf "Выбор: "; read -r choice
        case "$choice" in
            1) menu_profile_default ;;
            2) menu_slots ;;
            3) menu_test_dns ;;
            4) menu_bootstrap ;;
            5) menu_extras ;;
            6) menu_antiblock ;;
            7) menu_status ;;
            8) apply_settings ;;
            9) [ -f /root/rollback-dns.sh ] && sh /root/rollback-dns.sh || printf "${C_RED}Нет отката${C_NC}\n"; read -r _ ;;
            S|s|Ы|ы) menu_reset_to_stock ;;
            0) printf "${C_GREEN}До свидания!${C_NC}\n"; exit 0 ;;
            *) printf "${C_RED}[!] Неверный${C_NC}\n"; sleep 1 ;;
        esac
    done
}

# ============================================================
# Точка входа
# ============================================================
if [ "$SELF_SOURCE" != "$MANAGER_PATH" ] || [ ! -f "$MANAGER_PATH" ]; then
    install_self; exit 0
fi

init_system
load_config
main_menu
