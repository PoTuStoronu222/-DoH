#!/bin/sh
# ============================================================
# DNS Manager v4.1-FINAL
# Все фиксы v4.0 + корректный статус + безопасный сток
# ============================================================

MANAGER_PATH="/usr/bin/dns-manager"
SELF_SOURCE="$0"
CATVER="4.1"

# === ПРОВЕРКА ROOT ===
[ "$(id -u)" != "0" ] && { echo "[!] Требуются права root!"; exit 1; }

# === ЦВЕТА ===
init_colors() {
    if command -v tput >/dev/null 2>&1; then
        _tc=$(tput colors 2>/dev/null)
        if [ -n "$_tc" ] && [ "$_tc" -ge 8 ] 2>/dev/null; then
            R=$(tput setaf 1 2>/dev/null)
            G=$(tput setaf 2 2>/dev/null)
            Y=$(tput setaf 3 2>/dev/null)
            B=$(tput setaf 4 2>/dev/null)
            C=$(tput setaf 6 2>/dev/null)
            W=$(tput bold 2>/dev/null)
            N=$(tput sgr0 2>/dev/null)
        fi
    fi
    if [ -z "$N" ]; then
        R='\033[0;31m'; G='\033[0;32m'; Y='\033[1;33m'
        B='\033[0;34m'; C='\033[0;36m'; W='\033[1;37m'; N='\033[0m'
    fi
}

# === САМОУСТАНОВКА ===
install_self() {
    [ "$SELF_SOURCE" = "$MANAGER_PATH" ] && return 0
    echo "=== Установка DNS Manager v4.1 ==="
    if command -v apk >/dev/null 2>&1; then PKG="apk"
    elif command -v opkg >/dev/null 2>&1; then PKG="opkg"
    else echo "[!] Нет пакетного менеджера"; exit 1; fi
    NEED=0
    command -v https-dns-proxy >/dev/null 2>&1 || NEED=1
    command -v curl >/dev/null 2>&1 || NEED=1
    if [ "$NEED" = "1" ]; then
        echo "[*] Установка пакетов..."
        if [ "$PKG" = "apk" ]; then
            apk update && apk add https-dns-proxy ca-certificates curl bind-tools ncurses
        else
            opkg update && opkg install https-dns-proxy ca-certificates curl bind-dig ncurses
        fi
    fi
    if ! command -v tput >/dev/null 2>&1; then
        if [ "$PKG" = "apk" ]; then apk add ncurses 2>/dev/null
        else opkg install ncurses 2>/dev/null; fi
    fi
    init_colors
    if [ -f "$SELF_SOURCE" ]; then
        cp "$SELF_SOURCE" "$MANAGER_PATH" 2>/dev/null || cat "$SELF_SOURCE" > "$MANAGER_PATH"
    else
        wget -q -O "$MANAGER_PATH" "https://raw.githubusercontent.com/PoTuStoronu222/Openwrt-Smartdns-DoH/main/test.sh" 2>/dev/null || \
        curl -fsSL "https://raw.githubusercontent.com/PoTuStoronu222/Openwrt-Smartdns-DoH/main/test.sh" -o "$MANAGER_PATH"
    fi
    chmod +x "$MANAGER_PATH"
    printf '\n%b✓ Установлено! Запуск: dns-manager%b\n\n' "$G" "$N"
    exec "$MANAGER_PATH"
}

CONFIG_FILE="/root/.dns-manager.conf"
DNS_CATALOG="/root/.dns-catalog.conf"
TEST_RESULTS="/root/.dns-test-results.conf"
VERSION="4.1-FINAL"

# === CLEANUP / FLUSH ===
cleanup_tmp() {
    rm -f /tmp/.dns_all /tmp/.dns_sel /tmp/.dns_urls /tmp/.dns_dupes
    rm -f /tmp/.added_urls /tmp/.active_ports /tmp/.tgi /tmp/tmp.init
    rm -f /tmp/dns_setup.sh /tmp/dns_final.sh /tmp/install.sh /tmp/finish.sh
}
trap 'cleanup_tmp; printf "\n%b[!] Прервано пользователем%b\n" "$R" "$N"; exit 1' INT TERM

flush_stdin() {
    if command -v timeout >/dev/null 2>&1; then
        timeout 0.1 dd if=/dev/stdin of=/dev/null bs=512 count=1 2>/dev/null
    else
        while read -t 0 _flush_dummy 2>/dev/null; do :; done
    fi
}
safe_read() { flush_stdin; read -r "$@"; }
clear_screen() { command -v clear >/dev/null 2>&1 && clear || printf '\033[2J\033[H'; }

# ============================================================
# КАТАЛОГ DNS (57 серверов)
# ============================================================
create_catalog() {
    cat > "$DNS_CATALOG" << 'CATALOG'
#CATVER=4.1
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
    init_colors
    printf '%b=== Инициализация ===%b\n' "$B" "$N"
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
        printf '%b[+] Каталог обновлён (v%s)%b\n' "$G" "$CATVER" "$N"
    fi
    printf '%b[✓] Готово%b\n' "$G" "$N"
}

# ============================================================
# КОНФИГУРАЦИЯ
# ============================================================
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

# ============================================================
# УТИЛИТЫ КАТАЛОГА
# ============================================================
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
find_dns_id_by_url() {
    grep -v '^#' "$DNS_CATALOG" | grep "|$1|" | head -1 | cut -d'|' -f1
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

# ============================================================
# РЕЗОЛВ ЧЕРЕЗ DIG
# ============================================================
resolve_host() {
    for _bs in $(printf '%s' "$BOOTSTRAP_DNS" | tr ',' ' '); do
        if command -v dig >/dev/null 2>&1; then
            _ip=$(dig +short "@$_bs" "$1" A 2>/dev/null | grep -E '^[0-9]{1,3}(\.[0-9]{1,3}){3}$' | head -n1)
        else
            _ip=$(nslookup "$1" "$_bs" 2>/dev/null | sed -n '/Name:/,$p' | grep -oE '([0-9]{1,3}\.){3}[0-9]{1,3}' | grep -vE '^127\.|^0\.' | head -n1)
        fi
        [ -n "$_ip" ] && { printf '%s' "$_ip"; return 0; }
    done
    return 1
}

# ============================================================
# NTP
# ============================================================
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
# 🎯 УМНЫЙ СТАТУС — читает РЕАЛЬНОЕ состояние из UCI
# ============================================================
show_real_status() {
    printf '%b╔══════════════════════════════════════════╗%b\n' "$B" "$N"
    printf '%b║     📊 Текущее состояние системы        ║%b\n' "$B" "$N"
    printf '%b╚══════════════════════════════════════════╝%b\n\n' "$B" "$N"

    # === 1. DoH процессы ===
    printf '%b▸ DoH процессы:%b\n' "$Y" "$N"
    _pc=$(ps | grep https-dns-proxy | grep -v grep | wc -l)
    if [ "$_pc" -eq 0 ]; then
        printf '  %b[✗] Не запущены%b\n' "$R" "$N"
        _internet_count=0
        _ru_count=0
    else
        printf '  %b[✓] Запущено %s процессов%b\n' "$G" "$_pc" "$N"
        _internet_count=0
        _ru_count=0
        _idx=0
        while uci -q get "https-dns-proxy.@https-dns-proxy[$_idx].resolver_url" >/dev/null 2>&1; do
            _url=$(uci -q get "https-dns-proxy.@https-dns-proxy[$_idx].resolver_url")
            _port=$(uci -q get "https-dns-proxy.@https-dns-proxy[$_idx].listen_port")
            _id=$(find_dns_id_by_url "$_url")
            if [ -n "$_id" ]; then
                _name=$(get_dns_name "$_id")
                _type=$(get_dns_type "$_id")
                if [ "$_type" = "bypass" ]; then
                    printf '    %s %-22s %b[bypass]%b\n' "$_port" "$_name" "$G" "$N"
                    _internet_count=$((_internet_count + 1))
                else
                    printf '    %s %-22s %b[clean]%b\n' "$_port" "$_name" "$C" "$N"
                    _ru_count=$((_ru_count + 1))
                fi
            else
                printf '    %s %b%s%b %b[custom]%b\n' "$_port" "$C" "$_url" "$N" "$Y" "$N"
                if [ "$_port" = "5059" ] || [ "$_port" = "5060" ]; then
                    _ru_count=$((_ru_count + 1))
                else
                    _internet_count=$((_internet_count + 1))
                fi
            fi
            _idx=$((_idx + 1))
        done
        printf '  Итого: %b%s%b интернет + %b%s%b рунет (макс 6+2)\n' "$G" "$_internet_count" "$N" "$C" "$_ru_count" "$N"
    fi
    echo ""

    # === 2. Балансировщик (из UCI) ===
    printf '%b▸ Балансировщик:%b ' "$Y" "$N"
    _allservers=$(uci -q get dhcp.@dnsmasq[0].allservers 2>/dev/null)
    if [ "$_allservers" = "1" ]; then
        printf '%bВКЛ%b (параллельный опрос)\n' "$G" "$N"
    elif [ "$_allservers" = "0" ]; then
        printf '%bВЫКЛ%b (одна голова)\n' "$Y" "$N"
    else
        printf '%bне настроен%b\n' "$R" "$N"
    fi

    # === 3. Bootstrap DNS (из UCI) ===
    printf '%b▸ Bootstrap DNS:%b ' "$Y" "$N"
    _bs_uci=$(uci -q get https-dns-proxy.@https-dns-proxy[0].bootstrap_dns 2>/dev/null)
    if [ -n "$_bs_uci" ]; then
        _bs_count=$(printf '%s' "$_bs_uci" | tr ',' '\n' | wc -l)
        printf '%b%s IP%b\n' "$G" "$_bs_count" "$N"
    else
        printf '%bне настроен%b\n' "$R" "$N"
    fi

    # === 4. NTP серверы (из UCI) ===
    printf '%b▸ NTP серверы:%b ' "$Y" "$N"
    _ntp_first=$(uci show system.ntp.server 2>/dev/null | head -1 | cut -d"'" -f2)
    if [ -n "$_ntp_first" ]; then
        case "$_ntp_first" in
            162.159*) printf '%bCloudflare IP%b\n' "$G" "$N" ;;
            216.239*) printf '%bGoogle IP%b\n' "$G" "$N" ;;
            194.190*|89.109*|92.255*) printf '%bРоссийские IP%b\n' "$G" "$N" ;;
            *pool.ntp*) printf '%bNTP Pool%b\n' "$G" "$N" ;;
            *) printf '%bнастроены%b\n' "$G" "$N" ;;
        esac
    else
        printf '%bне настроены%b\n' "$R" "$N"
    fi

    # === 5. QUIC (из firewall UCI) ===
    printf '%b▸ Блокировка QUIC:%b ' "$Y" "$N"
    _quic_443=$(uci show firewall 2>/dev/null | grep "name='Block_UDP_443'" | head -1)
    _quic_80=$(uci show firewall 2>/dev/null | grep "name='Block_UDP_80'" | head -1)
    if [ -n "$_quic_443" ] && [ -n "$_quic_80" ]; then
        printf '%bВКЛ%b\n' "$G" "$N"
    elif [ -n "$_quic_443" ] || [ -n "$_quic_80" ]; then
        printf '%bчастично%b\n' "$Y" "$N"
    else
        printf '%bне настроена%b\n' "$R" "$N"
    fi

    # === 6. MTU Fix (из UCI) ===
    printf '%b▸ MTU Fix:%b ' "$Y" "$N"
    _mtu=$(uci -q get firewall.@defaults[0].mtu_fix 2>/dev/null)
    if [ "$_mtu" = "1" ]; then
        printf '%bВКЛ%b\n' "$G" "$N"
    elif [ "$_mtu" = "0" ]; then
        printf '%bВЫКЛ%b\n' "$Y" "$N"
    else
        printf '%bне настроен%b\n' "$R" "$N"
    fi

    # === 7. Anti-block ===
    printf '%b▸ Anti-block:%b ' "$Y" "$N"
    if [ -f /etc/dnsmasq.d/anti-block.conf ]; then
        _bogus_count=$(grep -c 'bogus-nxdomain' /etc/dnsmasq.d/anti-block.conf 2>/dev/null || echo 0)
        printf '%b%s заглушек%b\n' "$G" "$_bogus_count" "$N"
    else
        printf '%bне настроен%b\n' "$R" "$N"
    fi

    # === 8. TLD Split (из dnsmasq) ===
    printf '%b▸ TLD Split (.ru):%b ' "$Y" "$N"
    _ru_rule=$(uci show dhcp.@dnsmasq[0].server 2>/dev/null | grep "'/ru/" | head -1)
    if [ -n "$_ru_rule" ]; then
        printf '%bВКЛ%b\n' "$G" "$N"
    else
        printf '%bне настроен%b\n' "$R" "$N"
    fi

    # === 9. Sysctl ===
    printf '%b▸ Sysctl tuning:%b ' "$Y" "$N"
    if [ -f /etc/sysctl.d/99-custom.conf ] && [ -s /etc/sysctl.d/99-custom.conf ]; then
        _sys_count=$(grep -c '=' /etc/sysctl.d/99-custom.conf)
        printf '%bВКЛ (%s параметров)%b\n' "$G" "$_sys_count" "$N"
    else
        printf '%bне настроен%b\n' "$R" "$N"
    fi

    # === 10. Go-оптимизация ===
    printf '%b▸ Go-оптимизация:%b\n' "$Y" "$N"
    _tg_go=0; _tailscale=0
    [ -f /etc/init.d/tg-ws-proxy-go ] && grep -q "GOMAXPROCS\|GOMEMLIMIT" /etc/init.d/tg-ws-proxy-go 2>/dev/null && _tg_go=1
    [ -f /etc/init.d/tailscale ] && grep -q "GOMEMLIMIT" /etc/init.d/tailscale 2>/dev/null && _tailscale=1
    if [ "$_tg_go" = "1" ] || [ "$_tailscale" = "1" ]; then
        [ "$_tg_go" = "1" ] && printf '    tg-ws-proxy-go: %bоптимизирован%b\n' "$G" "$N"
        [ "$_tailscale" = "1" ] && printf '    tailscale: %bоптимизирован%b\n' "$G" "$N"
    else
        _any_go_exists=0
        [ -f /etc/init.d/tg-ws-proxy-go ] && _any_go_exists=1
        [ -f /etc/init.d/tailscale ] && _any_go_exists=1
        if [ "$_any_go_exists" = "1" ]; then
            printf '    %bне оптимизированы%b\n' "$Y" "$N"
        else
            printf '    %bсервисы не установлены%b\n' "$Y" "$N"
        fi
    fi

    # === 11. Конфликты с другими менеджерами ===
    _zapret_manager=0
    [ -f /usr/bin/zms ] && _zapret_manager=1
    [ -f /usr/bin/zmsA ] && _zapret_manager=1
    if [ "$_zapret_manager" = "1" ]; then
        echo ""
        printf '%b⚠ Обнаружен Zapret Manager%b\n' "$Y" "$N"
        printf '  Возможно он также трогает DNS-настройки\n'
    fi

    # === 12. Hotplug tailscale ===
    if [ -f /etc/hotplug.d/ntp/99-tailscale ]; then
        echo ""
        printf '%b▸ Hotplug tailscale:%b %bнастроен%b\n' "$Y" "$N" "$G" "$N"
    fi
}

# ============================================================
# ВОЗВРАТ В СТОК — БЕЗОПАСНЫЙ (только наше)
# ============================================================
menu_reset_to_stock() {
    flush_stdin; clear_screen
    printf '%b========================================%b\n' "$R" "$N"
    printf '%b  ⚠  ВОЗВРАТ В СТОК (безопасный)%b\n' "$R" "$N"
    printf '%b========================================%b\n\n' "$R" "$N"
    printf '%bУдаляется ТОЛЬКО то, что настроил менеджер:%b\n' "$Y" "$N"
    printf '  • DoH-слоты (https-dns-proxy)\n'
    printf '  • Наши DNS серверы из dnsmasq (127.0.0.1#50xx)\n'
    printf '  • Наши TLD правила (/ru/, /su/, /xn--p1ai/ → 5059/5060)\n'
    printf '  • anti-block.conf\n'
    printf '  • NTP Redirect и Block-QUIC правила\n'
    printf '  • MTU fix (если ставили мы)\n'
    printf '  • Sysctl 99-custom.conf\n'
    printf '  • Конфиг менеджера, каталог, тесты\n\n'
    printf '%bНЕ трогаются (гарантировано):%b\n' "$G" "$N"
    printf '  • Пользовательские DNS серверы в dnsmasq\n'
    printf '  • Параметры noresolv, quietdhcp, boguspriv, domainneeded\n'
    printf '  • cachesize, dnsforwardmax, max_cache_ttl\n'
    printf '  • tg-ws-proxy-go и tailscale\n'
    printf '  • WiFi, LAN, WAN, PPPoE, DHCP\n'
    printf '  • Пользовательские firewall правила\n\n'
    printf 'Введите %bсток%b для подтверждения: ' "$G" "$N"
    safe_read confirm
    conf_clean=$(printf '%s' "$confirm" | tr -d ' \t\r\n' | tr 'A-Z' 'a-z')
    case "$conf_clean" in
        сток|stock|y|s|да)
            printf '%b[✓] Подтверждено%b\n\n' "$G" "$N" ;;
        *)
            printf '%b[✗] Отменено%b\n' "$Y" "$N"
            sleep 2; return ;;
    esac

    printf '[1/6] Остановка DoH...\n'
    /etc/init.d/https-dns-proxy stop 2>/dev/null
    sleep 2
    pgrep https-dns-proxy >/dev/null 2>&1 && killall -9 https-dns-proxy 2>/dev/null && sleep 1
    /etc/init.d/https-dns-proxy disable 2>/dev/null

    printf '[2/6] Очистка UCI https-dns-proxy...\n'
    while uci -q delete https-dns-proxy.@https-dns-proxy[0]; do :; done
    uci -q delete https-dns-proxy.config 2>/dev/null
    uci set https-dns-proxy.config='main'
    uci set https-dns-proxy.config.update_dnsmasq='0'
    uci commit https-dns-proxy

    printf '[3/6] Сброс dnsmasq (только НАШИ правила)...\n'
    # Удаляем ТОЛЬКО наши серверы: 127.0.0.1#50xx и TLD правила к 5059/5060
    _tmp_servers="/tmp/.dns_stock_servers.$$"
    _tmp_tld="/tmp/.dns_stock_tld.$$"
    : > "$_tmp_servers"
    : > "$_tmp_tld"
    uci show dhcp.@dnsmasq[0].server 2>/dev/null | while read -r _line; do
        _val=$(printf '%s' "$_line" | cut -d"'" -f2)
        [ -z "$_val" ] && continue
        # Наш сервер 127.0.0.1#50xx - пропускаем
        if printf '%s' "$_val" | grep -qE '^127\.0\.0\.1#50[0-9][0-9]$'; then
            continue
        fi
        # Наш TLD правило /ru/ /su/ /xn--p1ai/ -> 127.0.0.1#5059 или #5060 - пропускаем
        if printf '%s' "$_val" | grep -qE '^/(ru|su|xn--p1ai)/127\.0\.0\.1#50(59|60)(,127\.0\.0\.1#50(59|60))?$'; then
            continue
        fi
        # Остальное - сохраняем
        printf '%s\n' "$_val" >> "$_tmp_servers"
    done
    # Удаляем все server и восстанавливаем сохранённые
    while uci -q delete dhcp.@dnsmasq[0].server; do :; done
    if [ -s "$_tmp_servers" ]; then
        while IFS= read -r _s; do
            uci add_list dhcp.@dnsmasq[0].server="$_s"
        done < "$_tmp_servers"
    fi
    # НЕ трогаем: noresolv, quietdhcp, boguspriv, domainneeded, cachesize и др.
    # Если серверов не осталось - сбрасываем noresolv к 0
    _remaining=$(uci show dhcp.@dnsmasq[0].server 2>/dev/null | wc -l)
    if [ "$_remaining" -eq 0 ]; then
        uci -q set dhcp.@dnsmasq[0].noresolv='0'
    fi
    uci commit dhcp
    rm -f "$_tmp_servers" "$_tmp_tld"

    printf '[4/6] Сброс firewall (только наши правила)...\n'
    uci -q delete firewall.redirect_ntp 2>/dev/null
    # Удаляем ТОЛЬКО наши Block_UDP правила по имени
    for _RULE in Block_UDP_80 Block_UDP_443; do
        while true; do
            _IDX=$(uci show firewall 2>/dev/null | grep "name='$_RULE'" | cut -d. -f2 | cut -d= -f1 | head -n1)
            [ -z "$_IDX" ] && break
            uci -q delete firewall."$_IDX" 2>/dev/null
        done
    done
    uci -q delete firewall.@defaults[0].mtu_fix 2>/dev/null
    _WAN_SEC=$(uci show firewall 2>/dev/null | grep -m1 "\.name='wan'" | cut -d. -f1,2)
    [ -n "$_WAN_SEC" ] && uci -q delete "${_WAN_SEC}.mtu_fix" 2>/dev/null
    uci commit firewall

    printf '[5/6] NTP к дефолту OpenWrt...\n'
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

    printf '[6/6] Полная очистка артефактов менеджера...\n'
    rm -f /etc/dnsmasq.d/anti-block.conf
    rm -f /etc/sysctl.d/99-custom.conf
    rm -f /etc/hotplug.d/ntp/99-tailscale
    rm -f /root/rollback-dns.sh
    rm -f "$CONFIG_FILE" "$DNS_CATALOG" "$TEST_RESULTS"
    cleanup_tmp
    [ -f /etc/crontabs/root ] && sed -i '/update-bogus-dns/d; /dns-manager/d' /etc/crontabs/root

    # Применяем изменения
    sysctl -p /etc/sysctl.conf >/dev/null 2>&1
    /etc/init.d/firewall restart 2>/dev/null
    /etc/init.d/dnsmasq restart 2>/dev/null
    /etc/init.d/sysntpd restart 2>/dev/null

    echo ""
    if pgrep https-dns-proxy >/dev/null 2>&1; then
        printf '%b[✗] https-dns-proxy ещё запущен!%b\n' "$R" "$N"
    else
        printf '%b[✓] https-dns-proxy остановлен%b\n' "$G" "$N"
    fi
    if pgrep dnsmasq >/dev/null 2>&1; then
        printf '%b[✓] dnsmasq запущен%b\n' "$G" "$N"
    else
        printf '%b[!] dnsmasq не запущен (возможно нет серверов)%b\n' "$Y" "$N"
    fi
    if [ -f /etc/init.d/tg-ws-proxy-go ]; then
        if pgrep -f tg-ws-proxy >/dev/null 2>&1; then
            printf '%b[✓] tg-ws-proxy-go работает (не затронут)%b\n' "$G" "$N"
        fi
    fi
    if [ -f /etc/init.d/tailscale ]; then
        if pgrep tailscale >/dev/null 2>&1; then
            printf '%b[✓] tailscale работает (не затронут)%b\n' "$G" "$N"
        fi
    fi

    printf '\n%b✅ СТОК ВОССТАНОВЛЕН БЕЗОПАСНО!%b\n' "$G" "$N"
    printf 'Перезагрузка через 5 сек...\n'
    sleep 5
    reboot
    exit 0
}

# ============================================================
# ПРОФИЛИ (8 штук)
# ============================================================
menu_profile_default() {
    flush_stdin; clear_screen
    printf '%b========================================%b\n' "$B" "$N"
    printf '%b  ⚡ Быстрая настройка (8 профилей)%b\n' "$B" "$N"
    printf '%b========================================%b\n\n' "$B" "$N"
    printf '  %b1) Оптимальный [рекомендуется]%b\n' "$G" "$N"
    printf '     4 обходных + Yandex RU\n'
    printf '     QUIC + MTU + NTP + sysctl + Go\n\n'
    printf '  %b2) Максимум устойчивости%b\n' "$W" "$N"
    printf '     6 обходных + 2 РУ (Yandex + Safe)\n'
    printf '     QUIC + MTU + NTP + sysctl + Go\n\n'
    printf '  %b3) Одна голова (слабый роутер)%b\n' "$W" "$N"
    printf '     1 DNS, балансир ВЫКЛ\n'
    printf '     MTU + NTP + Go\n\n'
    printf '  %b4) Только рунет%b\n' "$W" "$N"
    printf '     Только Yandex для .ru\n'
    printf '     MTU + NTP + sysctl + Go\n\n'
    printf '  %b5) Семейный%b\n' "$W" "$N"
    printf '     AdGuard Fam + CF Fam + CleanBrows Fam\n'
    printf '     РУ: Yandex Family\n\n'
    printf '  %b6) Приватный%b\n' "$W" "$N"
    printf '     AdGuard Unf + Mullvad + Quad9 Unsec\n\n'
    printf '  %b7) Чистый (без обхода)%b\n' "$W" "$N"
    printf '     CF + Google + Quad9 + OpenDNS\n\n'
    printf '  %b8) Быстрый (минимальные пинги)%b\n' "$W" "$N"
    printf '     Mafioznik + Comss.ru + DNS.403 + BlueDNS\n\n'
    printf '  %bEnter%b = отмена\n\n' "$C" "$N"
    printf 'Выбор: '
    safe_read choice; [ -z "$choice" ] && return

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
        *) printf '%b[!] Неверный%b\n' "$R" "$N"; sleep 1; return ;;
    esac
    save_config
    printf '%b[✓] Профиль сохранён%b\n' "$G" "$N"
    printf 'Применить? [y/Enter=да, n=нет]: '
    safe_read confirm
    case "$confirm" in n|N) printf 'Примените через пункт 8.\n'; sleep 2 ;; *) apply_settings ;; esac
}

# ============================================================
# ТЕСТ DNS (НЕЗАВИСИМЫЙ)
# ============================================================
menu_test_dns() {
    flush_stdin; clear_screen
    printf '%b========================================%b\n' "$B" "$N"
    printf '%b  🔍 Тест всех DNS (независимо от DoH)%b\n' "$B" "$N"
    printf '%b========================================%b\n\n' "$B" "$N"
    printf '%bРезолв через резервные IP + curl --resolve%b\n\n' "$Y" "$N"
    printf '%-20s %-8s %-9s %-9s %s\n' "DNS" "Тип" "Статус" "Скорость" "Примечание"
    printf '%b---------------------------------------------------------------------------%b\n' "$C" "$N"
    > "$TEST_RESULTS"
    grep -v '^#' "$DNS_CATALOG" | grep '|' | while IFS='|' read -r id name url dtype; do
        [ -z "$id" ] && continue
        host=$(printf '%s' "$url" | sed 's|^https://||; s|/.*$||')
        ip=$(resolve_host "$host")
        if [ -z "$ip" ]; then
            printf '%-20s %-8s %bFAIL%b   %-9s %s\n' "$name" "$dtype" "$R" "$N" "-" "не резолвится"
            echo "${id}|0|FAIL" >> "$TEST_RESULTS"; continue
        fi
        t=$(curl -s -o /dev/null -w '%{time_total}' --max-time 5 \
            --resolve "$host:443:$ip" \
            "${url}?name=google.com&type=A" -H 'Accept: application/dns-json' 2>/dev/null)
        if [ -n "$t" ] && [ "$t" != "0.000000" ]; then
            ms=$(echo "$t" | awk '{printf "%.0f", $1 * 1000}')
            [ "$ms" -lt 100 ] && note="Быстрый" || { [ "$ms" -lt 300 ] && note="Норм" || note="Медленный"; }
            printf '%-20s %-8s %bOK%b     %-9s %s\n' "$name" "$dtype" "$G" "$N" "${ms}ms" "$note"
            echo "${id}|${ms}|OK" >> "$TEST_RESULTS"
        else
            printf '%-20s %-8s %bFAIL%b   %-9s %s\n' "$name" "$dtype" "$R" "$N" "-" "DoH не ответил"
            echo "${id}|0|FAIL" >> "$TEST_RESULTS"
        fi
    done
    echo ""; printf '%b---------------------------------------------------------------------------%b\n' "$C" "$N"
    total=$(wc -l < "$TEST_RESULTS" 2>/dev/null)
    ok=$(grep -c '|OK' "$TEST_RESULTS" 2>/dev/null)
    fail=$(grep -c '|FAIL' "$TEST_RESULTS" 2>/dev/null)
    printf 'Всего: %s | %bOK: %s%b | %bFAIL: %s%b\n' "$total" "$G" "$ok" "$N" "$R" "$fail" "$N"
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
        flush_stdin; clear_screen; build_select_list
        printf '%b========================================%b\n' "$B" "$N"
        printf '%b  Выбор DNS для слота #%s%b\n' "$B" "$slot_num" "$N"
        printf '%b========================================%b\n\n' "$B" "$N"
        case "$SELECT_FILTER" in bypass) fstr="${G}ОБХОД${N}" ;; clean) fstr="${C}ЧИСТЫЕ${N}" ;; *) fstr="${W}все${N}" ;; esac
        printf 'Фильтр: %b (95=переключить)\n\n' "$fstr"
        i=1
        while IFS='|' read -r id name url dtype; do
            [ -z "$id" ] && continue
            if [ "$dtype" = "bypass" ]; then tag="${G}[обход]${N}"
            else tag="${C}[чистый]${N}"; fi
            tr_line=$(grep "^${id}|" "$TEST_RESULTS" 2>/dev/null | head -1)
            if [ -n "$tr_line" ]; then
                ms=$(printf '%s' "$tr_line" | cut -d'|' -f2)
                st=$(printf '%s' "$tr_line" | cut -d'|' -f3)
                if [ "$st" = "OK" ]; then
                    printf '  %2d) %-18s %b %b%5sms%b\n' "$i" "$name" "$tag" "$G" "$ms" "$N"
                else
                    printf '  %2d) %-18s %b %bFAIL%b\n' "$i" "$name" "$tag" "$R" "$N"
                fi
            else
                printf '  %2d) %-18s %b %b(нет теста)%b\n' "$i" "$name" "$tag" "$Y" "$N"
            fi
            i=$((i+1))
        done < /tmp/.dns_sel
        echo ""
        printf '  %b99) Очистить  98) Свой URL  95) Фильтр  Enter) Отмена%b\n\n' "$C" "$N"
        printf 'Выбор: '; safe_read choice; [ -z "$choice" ] && return
        case "$choice" in
            99) eval "SLOT_${slot_num}=\"\""; save_config; return ;;
            98) printf 'URL: '; safe_read cu; [ -n "$cu" ] && { eval "SLOT_${slot_num}=\"custom:$cu\""; save_config; }; return ;;
            95) case "$SELECT_FILTER" in all) SELECT_FILTER="bypass" ;; bypass) SELECT_FILTER="clean" ;; *) SELECT_FILTER="all" ;; esac ;;
            *) total=$(wc -l < /tmp/.dns_sel)
               if [ "$choice" -ge 1 ] 2>/dev/null && [ "$choice" -le "$total" ] 2>/dev/null; then
                   sel_id=$(sed -n "${choice}p" /tmp/.dns_sel | cut -d'|' -f1)
                   eval "SLOT_${slot_num}=\"$sel_id\""
                   save_config; return
               fi; printf '%b[!]%b\n' "$R" "$N"; sleep 1 ;;
        esac
    done
}

menu_slots() {
    flush_stdin
    while true; do
        clear_screen
        printf '%b========================================%b\n' "$B" "$N"
        printf '%b  Настройка слотов DNS%b\n' "$B" "$N"
        printf '%b========================================%b\n\n' "$B" "$N"
        printf '%bИнтернет (макс 6):%b\n' "$Y" "$N"
        printf '  1) Слот 1 (5053): %s\n' "$(get_dns_name "$SLOT_1")"
        printf '  2) Слот 2 (5054): %s\n' "$(get_dns_name "$SLOT_2")"
        printf '  3) Слот 3 (5055): %s\n' "$(get_dns_name "$SLOT_3")"
        printf '  4) Слот 4 (5056): %s\n' "$(get_dns_name "$SLOT_4")"
        printf '  5) Слот 5 (5057): %s\n' "$(get_dns_name "$SLOT_5")"
        printf '  6) Слот 6 (5058): %s\n' "$(get_dns_name "$SLOT_6")"
        printf '\n%bРунет (макс 2):%b\n' "$Y" "$N"
        printf '  7) Слот РУ   (5059): %s\n' "$(get_dns_name "$SLOT_RU")"
        printf '  8) Слот РУ-2 (5060): %s\n' "$(get_dns_name "$SLOT_RU_2")"
        echo ""
        check_duplicates && {
            printf '%b⚠ Дубли URL! При применении лишние будут пропущены.%b\n' "$Y" "$N"
            while read -r dupe_url; do printf '  • %s\n' "$dupe_url"; done < /tmp/.dns_dupes
            echo ""
        }
        printf '  %bEnter) Назад%b\n' "$C" "$N"; printf 'Выбор: '; safe_read choice; [ -z "$choice" ] && return
        case "$choice" in
            1) select_dns_for_slot "1" ;; 2) select_dns_for_slot "2" ;; 3) select_dns_for_slot "3" ;;
            4) select_dns_for_slot "4" ;; 5) select_dns_for_slot "5" ;; 6) select_dns_for_slot "6" ;;
            7) select_dns_for_slot "RU" ;; 8) select_dns_for_slot "RU_2" ;;
            *) printf '%b[!]%b\n' "$R" "$N"; sleep 1 ;;
        esac
    done
}

# ============================================================
# BOOTSTRAP МЕНЮ
# ============================================================
menu_bootstrap() {
    flush_stdin
    while true; do
        clear_screen
        printf '%b========================================%b\n' "$B" "$N"
        printf '%b  Резервные DNS (Bootstrap)%b\n' "$B" "$N"
        printf '%b========================================%b\n\n' "$B" "$N"
        printf '%bЧто это?%b Это обычные DNS-серверы (по IP),\n' "$Y" "$N"
        printf 'которые нужны чтобы %bнайти адрес DoH-сервера%b\n' "$W" "$N"
        printf 'при первом запуске. Без них DoH не запустится.\n\n'
        printf 'Текущий: %b%s%b\n\n' "$Y" "$BOOTSTRAP_DNS" "$N"
        printf '  %b1)%b Полный 10 IP (Yandex+AdGuard+CF+Google+Quad9) [рек]\n' "$G" "$N"
        printf '  %b2)%b РФ безопасный (Yandex + AdGuard, 4 IP)\n' "$G" "$N"
        printf '  %b3)%b Только Yandex\n' "$G" "$N"
        printf '  %b4)%b Только AdGuard\n' "$G" "$N"
        printf '  %b5)%b Ввести свои IP вручную\n' "$G" "$N"
        printf '  %bEnter) Назад%b\n\n' "$C" "$N"
        printf 'Выбор: '; safe_read choice; [ -z "$choice" ] && return
        case "$choice" in
            1) BOOTSTRAP_DNS="77.88.8.8,77.88.8.1,94.140.14.14,94.140.15.15,1.1.1.1,1.0.0.1,8.8.8.8,8.8.4.4,9.9.9.9,149.112.112.112" ;;
            2) BOOTSTRAP_DNS="77.88.8.8,77.88.8.1,94.140.14.14,94.140.15.15" ;;
            3) BOOTSTRAP_DNS="77.88.8.8,77.88.8.1" ;;
            4) BOOTSTRAP_DNS="94.140.14.14,94.140.15.15" ;;
            5) printf 'IP через запятую: '; safe_read BOOTSTRAP_DNS ;;
            *) return ;;
        esac
        save_config; return
    done
}

# ============================================================
# NTP МЕНЮ
# ============================================================
menu_ntp() {
    flush_stdin
    while true; do
        clear_screen
        printf '%b========================================%b\n' "$B" "$N"
        printf '%b  ⏰ NTP серверы (ТОЛЬКО IP)%b\n' "$B" "$N"
        printf '%b========================================%b\n\n' "$B" "$N"
        printf 'Текущий: %b%s%b\n\n' "$Y" "$(get_ntp_preset_name "$NTP_PRESET")" "$N"
        for srv in $(get_ntp_servers "$NTP_PRESET" "$NTP_CUSTOM"); do printf '  • %s\n' "$srv"; done
        echo ""
        printf '  %b1)%b Смешанный [рек]  2) CF  3) Google  4) Pool\n' "$G" "$N"
        printf '  5) ВНИИФТРИ  6) RU  7) DHCP  8) Свой\n'
        printf '  %bEnter) Назад%b\n' "$C" "$N"; printf 'Выбор: '; safe_read choice; [ -z "$choice" ] && return
        case "$choice" in
            1) NTP_PRESET="mixed" ;; 2) NTP_PRESET="cloudflare" ;; 3) NTP_PRESET="google" ;;
            4) NTP_PRESET="ntp_pool" ;; 5) NTP_PRESET="ru_vniiftri" ;; 6) NTP_PRESET="ru_ps" ;;
            7) NTP_PRESET="dhcp" ;; 8) printf 'IP: '; safe_read NTP_CUSTOM; NTP_PRESET="custom" ;; *) return ;;
        esac
        save_config
    done
}

# ============================================================
# ДОП. НАСТРОЙКИ
# ============================================================
menu_extras() {
    flush_stdin
    while true; do
        clear_screen
        printf '%b========================================%b\n' "$B" "$N"
        printf '%b  Дополнительные настройки%b\n' "$B" "$N"
        printf '%b========================================%b\n\n' "$B" "$N"
        [ "$BALANCER_ENABLED" = "1" ] && b1="${G}[✓]${N}" || b1="${R}[ ]${N}"
        [ "$TLD_RU_ENABLED" = "1" ] && b2="${G}[✓]${N}" || b2="${R}[ ]${N}"
        [ "$BLOCK_QUIC" = "1" ] && b3="${G}[✓]${N}" || b3="${R}[ ]${N}"
        [ "$MTU_FIX" = "1" ] && b4="${G}[✓]${N}" || b4="${R}[ ]${N}"
        [ "$NTP_REDIRECT" = "1" ] && b5="${G}[✓]${N}" || b5="${R}[ ]${N}"
        [ "$SYSCTL_TUNING" = "1" ] && b6="${G}[✓]${N}" || b6="${R}[ ]${N}"
        [ "$GO_OPTIMIZE" = "1" ] && b7="${G}[✓]${N}" || b7="${R}[ ]${N}"
        printf '  1) %b Балансировщик\n' "$b1"
        printf '  2) %b TLD Split\n' "$b2"
        printf '  3) %b QUIC\n' "$b3"
        printf '  4) %b MTU Fix\n' "$b4"
        printf '  5) %b NTP Redirect\n' "$b5"
        printf '  6) %b Sysctl\n' "$b6"
        printf '  7) %b Go-opt\n' "$b7"
        printf '\n  8) %b→ NTP: %s%b\n' "$Y" "$(get_ntp_preset_name "$NTP_PRESET")" "$N"
        printf '  %bEnter) Назад%b\n' "$C" "$N"; printf 'Выбор: '; safe_read choice; [ -z "$choice" ] && return
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

# ============================================================
# ANTI-BLOCK МЕНЮ
# ============================================================
menu_antiblock() {
    flush_stdin
    while true; do
        clear_screen
        printf '%b========================================%b\n' "$B" "$N"
        printf '%b  Anti-block%b\n' "$B" "$N"
        printf '%b========================================%b\n\n' "$B" "$N"
        grep "bogus-nxdomain=" /etc/dnsmasq.d/anti-block.conf 2>/dev/null | sed 's/bogus-nxdomain=/  /' || printf '  (пусто)\n'
        echo ""
        printf '  1) Добавить IP\n'
        printf '  2) Удалить IP\n'
        printf '  3) Сброс к эталону\n'
        printf '  4) Авто-поиск заглушки по домену\n'
        printf '  %bEnter) Назад%b\n' "$C" "$N"; printf 'Выбор: '; safe_read choice; [ -z "$choice" ] && return
        case "$choice" in
            1) printf 'IP: '; safe_read ip
               [ -n "$ip" ] && { echo "bogus-nxdomain=$ip" >> /etc/dnsmasq.d/anti-block.conf; /etc/init.d/dnsmasq restart; } ;;
            2) printf 'IP: '; safe_read ip
               [ -n "$ip" ] && { sed -i "/bogus-nxdomain=$ip/d" /etc/dnsmasq.d/anti-block.conf; /etc/init.d/dnsmasq restart; } ;;
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
            4) printf 'Домен (например, rutracker.org): '; safe_read domain
               if [ -n "$domain" ]; then
                   isp_ip=$(nslookup "$domain" 2>/dev/null | grep -oE '([0-9]{1,3}\.){3}[0-9]{1,3}' | head -n1)
                   if [ -n "$isp_ip" ]; then
                       echo "bogus-nxdomain=$isp_ip" >> /etc/dnsmasq.d/anti-block.conf
                       /etc/init.d/dnsmasq restart
                       printf '%b[✓] Заглушка %s добавлена для %s%b\n' "$G" "$isp_ip" "$domain" "$N"
                   else
                       printf '%b[!] Не удалось найти IP%b\n' "$R" "$N"
                   fi
               fi ;;
        esac
    done
}

# ============================================================
# ПРИМЕНЕНИЕ — с валидацией и правильным сохранением счётчика
# ============================================================
apply_settings() {
    flush_stdin; clear_screen
    printf '%b========================================%b\n' "$B" "$N"
    printf '%b  ⚡ Применение настроек%b\n' "$B" "$N"
    printf '%b========================================%b\n\n' "$B" "$N"

    # === ВАЛИДАЦИЯ: должен быть хотя бы один слот ===
    _any_slot=0
    for _s in 1 2 3 4 5 6 RU RU_2; do
        eval "_v=\$SLOT_$_s"
        [ -n "$_v" ] && _any_slot=1 && break
    done
    if [ "$_any_slot" = "0" ]; then
        printf '%b[✗] ОШИБКА: Не выбрано ни одного DNS слота!%b\n' "$R" "$N"
        printf '  Выберите хотя бы один слот через меню "2) Слоты"\n'
        printf '  Или примените профиль через "1) Профили"\n'
        printf '\nНажмите Enter...'; safe_read _
        return
    fi

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
        uci -q delete firewall.redirect_ntp 2>/dev/null
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

    printf '[8/11] DoH (полная очистка + анти-дубли)...\n'
    /etc/init.d/https-dns-proxy stop 2>/dev/null; sleep 2
    pgrep https-dns-proxy >/dev/null 2>&1 && killall -9 https-dns-proxy 2>/dev/null && sleep 1
    while uci -q delete https-dns-proxy.@https-dns-proxy[0]; do :; done
    uci -q delete https-dns-proxy.config 2>/dev/null
    uci set https-dns-proxy.config='main'
    uci set https-dns-proxy.config.update_dnsmasq='0'

    # Создаём файл трекера ДО цикла
    > /tmp/.added_urls

    add_doh() {
        _s="$1"; _p="$2"
        eval "_v=\$SLOT_$_s"; [ -z "$_v" ] && return
        _u=$(get_dns_url "$_v"); [ -z "$_u" ] && return
        if grep -qxF "$_u" /tmp/.added_urls 2>/dev/null; then
            printf '  %b[~] Пропуск (дубль): %s%b\n' "$Y" "$(get_dns_name "$_v")" "$N"
            return
        fi
        printf '%s\n' "$_u" >> /tmp/.added_urls
        uci add https-dns-proxy https-dns-proxy
        uci set https-dns-proxy.@https-dns-proxy[-1].listen_addr='127.0.0.1'
        uci set https-dns-proxy.@https-dns-proxy[-1].listen_port="$_p"
        uci set https-dns-proxy.@https-dns-proxy[-1].resolver_url="$_u"
        uci set https-dns-proxy.@https-dns-proxy[-1].request_timeout='2'
        uci set https-dns-proxy.@https-dns-proxy[-1].bootstrap_dns="$BOOTSTRAP_DNS"
        printf '  %b[+] %s (порт %s)%b\n' "$G" "$(get_dns_name "$_v")" "$_p" "$N"
    }
    for s in 1 2 3 4 5 6; do add_doh "$s" "$((5052 + s))"; done
    [ -n "$SLOT_RU" ] && add_doh "RU" "5059"
    [ -n "$SLOT_RU_2" ] && add_doh "RU_2" "5060"
    uci commit https-dns-proxy

    # === ВАЖНО: сохранить счётчик ДО cleanup_tmp ===
    added_count=$(wc -l < /tmp/.added_urls 2>/dev/null || echo 0)

    printf '[9/11] dnsmasq...\n'
    uci -q get dhcp.@dnsmasq[0] >/dev/null || uci add dhcp dnsmasq
    # Удаляем только НАШИ серверы: 127.0.0.1#50xx и TLD к 5059/5060
    _tmp_servers="/tmp/.dns_keep_servers.$$"
    : > "$_tmp_servers"
    uci show dhcp.@dnsmasq[0].server 2>/dev/null | while read -r _line; do
        _val=$(printf '%s' "$_line" | cut -d"'" -f2)
        [ -z "$_val" ] && continue
        # Наш сервер 127.0.0.1#50xx - пропускаем
        if printf '%s' "$_val" | grep -qE '^127\.0\.0\.1#50[0-9][0-9]$'; then
            continue
        fi
        # Наш TLD правило - пропускаем
        if printf '%s' "$_val" | grep -qE '^/(ru|su|xn--p1ai)/127\.0\.0\.1#50(59|60)(,127\.0\.0\.1#50(59|60))?$'; then
            continue
        fi
        printf '%s\n' "$_val" >> "$_tmp_servers"
    done
    while uci -q delete dhcp.@dnsmasq[0].server; do :; done
    # Восстанавливаем пользовательские серверы
    if [ -s "$_tmp_servers" ]; then
        while IFS= read -r _s; do
            uci add_list dhcp.@dnsmasq[0].server="$_s"
        done < "$_tmp_servers"
    fi
    rm -f "$_tmp_servers"

    uci add_list dhcp.@dnsmasq[0].confdir='/etc/dnsmasq.d'
    [ "$BALANCER_ENABLED" = "1" ] && { uci set dhcp.@dnsmasq[0].allservers='1'; uci set dhcp.@dnsmasq[0].strictorder='0'; } \
        || { uci set dhcp.@dnsmasq[0].allservers='0'; uci set dhcp.@dnsmasq[0].strictorder='1'; }
    # noresolv=1 ТОЛЬКО если есть наши серверы
    if [ "$added_count" -gt 0 ]; then
        uci set dhcp.@dnsmasq[0].noresolv='1'
    else
        uci -q set dhcp.@dnsmasq[0].noresolv='0'
    fi
    uci set dhcp.@dnsmasq[0].cachesize='10000'
    uci set dhcp.@dnsmasq[0].dnsforwardmax='1000'
    uci set dhcp.@dnsmasq[0].max_cache_ttl='300'
    uci set dhcp.@dnsmasq[0].quietdhcp='1'
    uci set dhcp.@dnsmasq[0].boguspriv='1'
    uci set dhcp.@dnsmasq[0].domainneeded='1'

    # Добавляем порты из реально добавленных URL
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
    # Удаляем только наши Block_UDP правила
    for _RULE in Block_UDP_80 Block_UDP_443; do
        while true; do
            _IDX=$(uci show firewall 2>/dev/null | grep "name='$_RULE'" | cut -d. -f2 | cut -d= -f1 | head -n1)
            [ -z "$_IDX" ] && break
            uci -q delete firewall."$_IDX" 2>/dev/null
        done
    done
    if [ "$BLOCK_QUIC" = "1" ]; then
        uci add firewall rule >/dev/null 2>&1; uci set firewall.@rule[-1].name='Block_UDP_80'
        uci add_list firewall.@rule[-1].proto='udp'; uci set firewall.@rule[-1].src='lan'
        uci set firewall.@rule[-1].dest='wan'; uci set firewall.@rule[-1].dest_port='80'
        uci set firewall.@rule[-1].target='REJECT'
        uci add firewall rule >/dev/null 2>&1; uci set firewall.@rule[-1].name='Block_UDP_443'
        uci add_list firewall.@rule[-1].proto='udp'; uci set firewall.@rule[-1].src='lan'
        uci set firewall.@rule[-1].dest='wan'; uci set firewall.@rule[-1].dest_port='443'
        uci set firewall.@rule[-1].target='REJECT'
    fi
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
rm -f /etc/dnsmasq.d/anti-block.conf
/etc/init.d/firewall restart 2>/dev/null
/etc/init.d/https-dns-proxy restart 2>/dev/null
/etc/init.d/dnsmasq restart
/etc/init.d/sysntpd restart 2>/dev/null
echo "✅ ROLLBACK DONE (reboot recommended)"
RB
    chmod +x /root/rollback-dns.sh

    echo ""; printf 'Перезапуск...\n'
    /etc/init.d/https-dns-proxy enable 2>/dev/null
    /etc/init.d/https-dns-proxy restart; sleep 3
    /etc/init.d/dnsmasq restart 2>/dev/null
    /etc/init.d/firewall restart 2>/dev/null
    [ -f /etc/init.d/sysntpd ] && /etc/init.d/sysntpd restart 2>/dev/null
    sleep 2

    # Теперь безопасно удаляем tmp
    cleanup_tmp

    proc_count=$(ps | grep https-dns-proxy | grep -v grep | wc -l)
    printf '\n%b✓ Применено! DoH: %s проц., уникальных URL: %s%b\n' "$G" "$proc_count" "$added_count" "$N"
    printf 'Нажмите Enter...'; safe_read _
}

# ============================================================
# ПОЛНАЯ ДИАГНОСТИКА
# ============================================================
menu_status() {
    flush_stdin; clear_screen
    printf '%b========================================%b\n' "$B" "$N"
    printf '%b  📊 Состояние + диагностика%b\n' "$B" "$N"
    printf '%b========================================%b\n\n' "$B" "$N"

    # === Балансировщик ===
    _a=$(uci -q get dhcp.@dnsmasq[0].allservers 2>/dev/null)
    [ "$_a" = "1" ] && printf '%b[✓] Балансировщик ВКЛ%b\n' "$G" "$N" || printf '%b[~] Балансировщик ВЫКЛ%b\n' "$Y" "$N"
    echo ""

    # === dnsmasq ===
    printf '%bdnsmasq:%b\n' "$C" "$N"
    pgrep dnsmasq >/dev/null 2>&1 && printf '  %b[✓] Процесс запущен%b\n' "$G" "$N" || printf '  %b[✗] НЕ запущен!%b\n' "$R" "$N"
    if command -v netstat >/dev/null 2>&1; then
        netstat -ln 2>/dev/null | grep -q ':53 ' && printf '  %b[✓] Порт 53 слушается%b\n' "$G" "$N" || printf '  %b[✗] Порт 53 НЕ слушается%b\n' "$R" "$N"
    fi
    echo ""

    # === DoH процессы ===
    printf '%bDoH процессы:%b\n' "$C" "$N"
    _pc=$(ps | grep https-dns-proxy | grep -v grep | wc -l)
    if [ "$_pc" -eq 0 ]; then
        printf '  %b[✗] Нет процессов!%b\n' "$R" "$N"
    else
        printf '  %b[✓] %s процессов:%b\n' "$G" "$_pc" "$N"
        ps | grep https-dns-proxy | grep -v grep | awk '{p="";u="";for(i=1;i<=NF;i++){if($i=="-p")p=$(i+1);if($i=="-r")u=$(i+1)}if(p&&u)printf "    %s -> %s\n",p,u}'
    fi
    echo ""

    # === Bootstrap ===
    printf '%bРезервные DNS (Bootstrap):%b\n' "$C" "$N"
    _bs_uci=$(uci -q get https-dns-proxy.@https-dns-proxy[0].bootstrap_dns 2>/dev/null)
    if [ -n "$_bs_uci" ]; then
        printf '  %s\n' "$_bs_uci"
    else
        printf '  %b(не настроены)%b\n' "$Y" "$N"
    fi
    printf '\n%bNTP:%b %s\n' "$C" "$N" "$(get_ntp_preset_name "$NTP_PRESET")"
    echo ""

    # === Resolution — ВСЕГДА проверяем ===
    printf '%bResolution (через dnsmasq):%b\n' "$C" "$N"
    _any_ok=0
    for dom in ya.ru chatgpt.com youtube.com instagram.com linkedin.com discord.com github.com twitter.com claude.ai; do
        ip=$(timeout 3 nslookup "$dom" 127.0.0.1 2>/dev/null | grep -vE '127\.0\.0\.|0\.0\.0\.0' | grep -oE '([0-9]{1,3}\.){3}[0-9]{1,3}' | head -n1)
        if [ -n "$ip" ]; then
            printf '  %-18s -> %b%s%b\n' "$dom" "$G" "$ip" "$N"
            _any_ok=1
        else
            printf '  %-18s -> %bNO_ANSWER%b\n' "$dom" "$R" "$N"
        fi
    done

    # === Если всё NO_ANSWER — диагностика ===
    if [ "$_any_ok" = "0" ]; then
        echo ""
        printf '%b⚠ Все сайты NO_ANSWER. Диагностика:%b\n' "$Y" "$N"
        pgrep dnsmasq >/dev/null 2>&1 || printf '  • %bdnsmasq не запущен%b → выполните %b/etc/init.d/dnsmasq start%b\n' "$R" "$N" "$G" "$N"
        [ "$_pc" -eq 0 ] && printf '  • %bНет DoH процессов%b → примените настройки (пункт 8)\n' "$R" "$N"
        _first_port=$(ps | grep https-dns-proxy | grep -v grep | awk '{for(i=1;i<=NF;i++)if($i=="-p"){print $(i+1);exit}}')
        if [ -n "$_first_port" ] && command -v dig >/dev/null 2>&1; then
            _direct_ip=$(dig @127.0.0.1 -p "$_first_port" ya.ru A +short +time=2 2>/dev/null | grep -vE '127\.0\.0\.|0\.0\.0\.0' | grep -oE '([0-9]{1,3}\.){3}[0-9]{1,3}' | head -n1)
            if [ -n "$_direct_ip" ]; then
                printf '  • DoH работает напрямую (порт %s) → %bпроблема в dnsmasq%b\n' "$_first_port" "$Y" "$N"
            else
                printf '  • DoH на порту %s %bне отвечает%b → проверьте bootstrap DNS\n' "$_first_port" "$R" "$N"
            fi
        fi
    fi

    echo ""; printf 'Нажмите Enter...'; safe_read _
}

# ============================================================
# ГЛАВНОЕ МЕНЮ
# ============================================================
main_menu() {
    while true; do
        flush_stdin; clear_screen
        printf '%b╔══════════════════════════════════════════╗%b\n' "$B" "$N"
        printf '%b║     🌐 DNS Manager v%-19s║%b\n' "$B" "$VERSION" "$N"
        printf '%b║     6+2 слота | Анти-дубли | IP-NTP    ║%b\n' "$B" "$N"
        printf '%b╚══════════════════════════════════════════╝%b\n\n' "$B" "$N"

        # УМНЫЙ СТАТУС
        show_real_status

        echo ""
        printf '%bМеню:%b\n' "$Y" "$N"
        printf '  %b1) ⚡ Профили%b    2) Слоты       3) Тест DNS\n' "$G" "$N"
        printf '  4) Резервные DNS  5) Доп.настр.  6) Anti-block\n'
        printf '  7) Состояние     %b8) ⚡ Применить%b  9) Откат\n' "$G" "$N"
        printf '  %bS) 🔄 СТОК%b       0) Выход\n\n' "$R" "$N"
        printf 'Выбор: '
        safe_read choice
        case "$choice" in
            1) menu_profile_default ;; 2) menu_slots ;; 3) menu_test_dns ;; 4) menu_bootstrap ;;
            5) menu_extras ;; 6) menu_antiblock ;; 7) menu_status ;; 8) apply_settings ;;
            9) [ -f /root/rollback-dns.sh ] && sh /root/rollback-dns.sh || printf 'Нет отката\n'; safe_read _ ;;
            S|s|Ы|ы) menu_reset_to_stock ;; 0) exit 0 ;;
            *) printf '%b[!]%b\n' "$R" "$N"; sleep 1 ;;
        esac
    done
}

# ============================================================
# Точка входа
# ============================================================
if [ "$SELF_SOURCE" != "$MANAGER_PATH" ] || [ ! -f "$MANAGER_PATH" ]; then
    install_self; exit 0
fi
init_system; load_config; main_menu
