#!/bin/sh
# ============================================================
# DNS Manager v4.2-FINAL
# Русские метки | Автоприменение | Реальное чтение UCI
# ============================================================

MANAGER_PATH="/usr/bin/dns-manager"
SELF_SOURCE="$0"
CATVER="4.2"

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
    echo "=== Установка DNS Manager v4.2 ==="
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
VERSION="4.2-FINAL"

cleanup_tmp() {
    rm -f /tmp/.dns_all /tmp/.dns_sel /tmp/.dns_urls /tmp/.dns_dupes
    rm -f /tmp/.added_urls /tmp/.active_ports /tmp/.tgi /tmp/tmp.init
}
trap 'cleanup_tmp; printf "\n%b[!] Прервано%b\n" "$R" "$N"; exit 1' INT TERM

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
#CATVER=4.2
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
# Русская метка типа
get_dns_type_ru() {
    [ -z "$1" ] && { printf '-'; return; }
    t=$(get_dns_field "$1" 4)
    case "$t" in
        bypass) printf 'обход' ;;
        clean) printf 'чистый' ;;
        *) printf 'чистый' ;;
    esac
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
        cloudflare) echo "Cloudflare" ;; google) echo "Google" ;;
        ntp_pool) echo "NTP Pool" ;; ru_vniiftri) echo "ВНИИФТРИ (RU)" ;;
        ru_ps) echo "Российские" ;; mixed) echo "Смешанный" ;;
        dhcp) echo "DHCP" ;; custom) echo "Свой" ;; *) echo "?" ;;
    esac
}

# ============================================================
# 🎯 ЧТЕНИЕ РЕАЛЬНЫХ ЗНАЧЕНИЙ ИЗ UCI
# ============================================================

# Читаем реальный bootstrap из UCI
read_real_bootstrap() {
    _bs=$(uci -q get https-dns-proxy.@https-dns-proxy[0].bootstrap_dns 2>/dev/null)
    if [ -n "$_bs" ]; then
        printf '%s' "$_bs"
    else
        printf ''
    fi
}

# Определяем реальный NTP пресет по содержимому UCI
detect_real_ntp_preset() {
    _ntp_servers=$(uci show system.ntp.server 2>/dev/null | cut -d"'" -f2 | tr '\n' ' ')
    [ -z "$_ntp_servers" ] && { printf 'не настроены'; return; }
    
    # Определяем по первому серверу
    _first=$(printf '%s' "$_ntp_servers" | awk '{print $1}')
    case "$_first" in
        162.159*) printf 'Cloudflare' ;;
        216.239*) printf 'Google' ;;
        194.190*|89.109*|92.255*|217.79*) printf 'ВНИИФТРИ' ;;
        194.85*) printf 'Российские' ;;
        *pool.ntp*|129.6*) printf 'NTP Pool' ;;
        *) printf 'Свой' ;;
    esac
}

# Читаем реальные NTP серверы
read_real_ntp_servers() {
    uci show system.ntp.server 2>/dev/null | cut -d"'" -f2 | tr '\n' ' ' | sed 's/ $//'
}

# ============================================================
# 🎯 ПРИМЕНЕНИЕ НАСТРОЕК (вызывается автоматически)
# ============================================================
apply_settings() {
    printf '%b[Применение...]%b\n' "$Y" "$N"

    # Бэкапы
    [ ! -d /etc/config/backup-original ] && {
        mkdir -p /etc/config/backup-original
        for f in dhcp firewall https-dns-proxy system; do cp /etc/config/$f /etc/config/backup-original/$f.bak 2>/dev/null; done
    }
    TS=$(date +%Y%m%d_%H%M%S); BA="/etc/config/backup-dns-$TS"; mkdir -p "$BA"
    for f in dhcp firewall https-dns-proxy system; do cp /etc/config/$f "$BA/$f.bak" 2>/dev/null; done
    ln -sfn "$BA" /etc/config/backup-pre-dns-v9
    (cd /etc/config && ls -dt backup-dns-* 2>/dev/null | tail -n +2 | xargs rm -rf 2>/dev/null)

    # Anti-block
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

    # MTU
    [ "$MTU_FIX" = "1" ] && {
        uci -q set firewall.@defaults[0].mtu_fix='1'
        WS=$(uci show firewall 2>/dev/null | grep -m1 "\.name='wan'" | cut -d. -f1,2)
        [ -n "$WS" ] && uci -q set "${WS}.mtu_fix=1"
        uci commit firewall
    }

    # NTP
    if [ "$NTP_REDIRECT" = "1" ]; then
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

    # Go-opt
    if [ "$GO_OPTIMIZE" = "1" ]; then
        for f in /etc/init.d/tg-ws-proxy-go /etc/init.d/tailscale; do
            [ ! -f "$f" ] && continue; sed -i '/GOMAXPROCS/d; /GOMEMLIMIT/d; /GOGC/d' "$f"
            grep -q "procd_open_instance" "$f" && {
                [ "$f" = "/etc/init.d/tg-ws-proxy-go" ] && EV="GOMAXPROCS=1 GOMEMLIMIT=50MiB" || EV="GOMEMLIMIT=85MiB"
                awk -v ev="$EV" '/procd_open_instance/{print;print "    procd_set_param env "ev;next}1' "$f" > /tmp/.tgi && mv /tmp/.tgi "$f"
            }
        done
    fi

    # Sysctl
    [ "$SYSCTL_TUNING" = "1" ] && {
        modprobe nf_conntrack 2>/dev/null
        SF="/etc/sysctl.d/99-custom.conf"; touch "$SF"
        for p in "net.netfilter.nf_conntrack_max=65536" "net.ipv4.tcp_fastopen=3" "net.ipv4.tcp_fin_timeout=15" "net.core.somaxconn=1024" "net.ipv4.tcp_keepalive_time=300" "net.core.rmem_max=2097152" "net.core.wmem_max=2097152"; do
            k=$(echo "$p"|cut -d= -f1); sed -i "/^$k/d" "$SF"; echo "$p">>"$SF"; sysctl -w "$p">/dev/null 2>&1
        done
    }

    # Hotplug tailscale
    [ -f /etc/init.d/tailscale ] && {
        mkdir -p /etc/hotplug.d/ntp
        printf '#!/bin/sh\n[ "$ACTION" = "step" ] || [ "$ACTION" = "stratum" ] || exit 0\nUPTIME=$(cut -d. -f1 /proc/uptime)\n[ "$UPTIME" -lt 600 ] && /etc/init.d/tailscale restart >/dev/null 2>&1\n' > /etc/hotplug.d/ntp/99-tailscale
        chmod +x /etc/hotplug.d/ntp/99-tailscale
    }

    # DoH - полная очистка
    /etc/init.d/https-dns-proxy stop 2>/dev/null; sleep 1
    pgrep https-dns-proxy >/dev/null 2>&1 && killall -9 https-dns-proxy 2>/dev/null && sleep 1
    while uci -q delete https-dns-proxy.@https-dns-proxy[0]; do :; done
    uci -q delete https-dns-proxy.config 2>/dev/null
    uci set https-dns-proxy.config='main'
    uci set https-dns-proxy.config.update_dnsmasq='0'
    > /tmp/.added_urls

    add_doh() {
        _s="$1"; _p="$2"
        eval "_v=\$SLOT_$_s"; [ -z "$_v" ] && return
        _u=$(get_dns_url "$_v"); [ -z "$_u" ] && return
        if grep -qxF "$_u" /tmp/.added_urls 2>/dev/null; then return; fi
        printf '%s\n' "$_u" >> /tmp/.added_urls
        uci add https-dns-proxy https-dns-proxy
        uci set https-dns-proxy.@https-dns-proxy[-1].listen_addr='127.0.0.1'
        uci set https-dns-proxy.@https-dns-proxy[-1].listen_port="$_p"
        uci set https-dns-proxy.@https-dns-proxy[-1].resolver_url="$_u"
        uci set https-dns-proxy.@https-dns-proxy[-1].request_timeout='2'
        uci set https-dns-proxy.@https-dns-proxy[-1].bootstrap_dns="$BOOTSTRAP_DNS"
    }
    for s in 1 2 3 4 5 6; do add_doh "$s" "$((5052 + s))"; done
    [ -n "$SLOT_RU" ] && add_doh "RU" "5059"
    [ -n "$SLOT_RU_2" ] && add_doh "RU_2" "5060"
    uci commit https-dns-proxy

    # dnsmasq
    uci -q get dhcp.@dnsmasq[0] >/dev/null || uci add dhcp dnsmasq
    while uci -q delete dhcp.@dnsmasq[0].server; do :; done
    uci add_list dhcp.@dnsmasq[0].confdir='/etc/dnsmasq.d'
    [ "$BALANCER_ENABLED" = "1" ] && { uci set dhcp.@dnsmasq[0].allservers='1'; uci set dhcp.@dnsmasq[0].strictorder='0'; } \
        || { uci set dhcp.@dnsmasq[0].allservers='0'; uci set dhcp.@dnsmasq[0].strictorder='1'; }
    
    _added_count=$(wc -l < /tmp/.added_urls 2>/dev/null || echo 0)
    if [ "$_added_count" -gt 0 ]; then
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

    # QUIC
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

    # Откат
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
echo "✅ ROLLBACK DONE"
RB
    chmod +x /root/rollback-dns.sh

    # Перезапуск
    /etc/init.d/https-dns-proxy enable 2>/dev/null
    /etc/init.d/https-dns-proxy restart 2>/dev/null; sleep 2
    /etc/init.d/dnsmasq restart 2>/dev/null
    /etc/init.d/firewall restart 2>/dev/null
    [ -f /etc/init.d/sysntpd ] && /etc/init.d/sysntpd restart 2>/dev/null
    sleep 1
    cleanup_tmp
}

# ============================================================
# 🎯 УМНЫЙ СТАТУС — читает РЕАЛЬНОЕ состояние из UCI
# ============================================================
show_real_status() {
    printf '%b╔══════════════════════════════════════════╗%b\n' "$B" "$N"
    printf '%b║     📊 Текущее состояние               ║%b\n' "$B" "$N"
    printf '%b╚══════════════════════════════════════════╝%b\n\n' "$B" "$N"

    # === 1. DoH процессы ===
    printf '%b▸ DoH:%b ' "$Y" "$N"
    _pc=$(ps | grep https-dns-proxy | grep -v grep | wc -l)
    if [ "$_pc" -eq 0 ]; then
        printf '%bне запущены%b\n' "$R" "$N"
    else
        printf '%b%s проц.%b\n' "$G" "$_pc" "$N"
        _internet_count=0; _ru_count=0
        ps | grep https-dns-proxy | grep -v grep | while read -r _line; do
            _port=$(printf '%s' "$_line" | awk '{for(i=1;i<=NF;i++)if($i=="-p"){print $(i+1);exit}}')
            _url=$(printf '%s' "$_line" | awk '{for(i=1;i<=NF;i++)if($i=="-r"){print $(i+1);exit}}')
            _id=$(find_dns_id_by_url "$_url")
            if [ -n "$_id" ]; then
                _name=$(get_dns_name "$_id")
                _type=$(get_dns_type "$_id")
                if [ "$_type" = "bypass" ]; then
                    printf '    %s %-20s %b[обход]%b\n' "$_port" "$_name" "$G" "$N"
                else
                    printf '    %s %-20s %b[чистый]%b\n' "$_port" "$_name" "$C" "$N"
                fi
            fi
        done
    fi

    # === 2. Балансировщик ===
    printf '%b▸ Балансир:%b ' "$Y" "$N"
    _allservers=$(uci -q get dhcp.@dnsmasq[0].allservers 2>/dev/null)
    if [ "$_allservers" = "1" ]; then
        printf '%bВКЛ%b\n' "$G" "$N"
    elif [ "$_allservers" = "0" ]; then
        printf '%bВЫКЛ%b\n' "$Y" "$N"
    else
        printf '%bне настроен%b\n' "$R" "$N"
    fi

    # === 3. Bootstrap DNS (РЕАЛЬНОЕ ЗНАЧЕНИЕ ИЗ UCI) ===
    printf '%b▸ Bootstrap:%b ' "$Y" "$N"
    _real_bs=$(read_real_bootstrap)
    if [ -n "$_real_bs" ]; then
        _bs_count=$(printf '%s' "$_real_bs" | tr ',' '\n' | wc -l)
        printf '%b%s IP%b\n' "$G" "$_bs_count" "$N"
    else
        printf '%bне настроен%b\n' "$R" "$N"
    fi

    # === 4. NTP серверы (РЕАЛЬНОЕ ЗНАЧЕНИЕ ИЗ UCI) ===
    printf '%b▸ NTP:%b ' "$Y" "$N"
    _real_ntp_preset=$(detect_real_ntp_preset)
    if [ "$_real_ntp_preset" = "не настроены" ]; then
        printf '%bне настроены%b\n' "$R" "$N"
    else
        printf '%b%s%b\n' "$G" "$_real_ntp_preset" "$N"
    fi

    # === 5. QUIC ===
    printf '%b▸ QUIC:%b ' "$Y" "$N"
    _quic_443=$(uci show firewall 2>/dev/null | grep "name='Block_UDP_443'" | head -1)
    if [ -n "$_quic_443" ]; then
        printf '%bВКЛ%b\n' "$G" "$N"
    else
        printf '%bВЫКЛ%b\n' "$R" "$N"
    fi

    # === 6. MTU ===
    printf '%b▸ MTU:%b ' "$Y" "$N"
    _mtu=$(uci -q get firewall.@defaults[0].mtu_fix 2>/dev/null)
    if [ "$_mtu" = "1" ]; then
        printf '%bВКЛ%b\n' "$G" "$N"
    else
        printf '%bВЫКЛ%b\n' "$R" "$N"
    fi

    # === 7. Anti-block ===
    printf '%b▸ Anti-block:%b ' "$Y" "$N"
    if [ -f /etc/dnsmasq.d/anti-block.conf ]; then
        _bogus_count=$(grep -c 'bogus-nxdomain' /etc/dnsmasq.d/anti-block.conf 2>/dev/null || echo 0)
        printf '%b%s%b\n' "$G" "$_bogus_count" "$N"
    else
        printf '%bнет%b\n' "$R" "$N"
    fi

    # === 8. TLD Split ===
    printf '%b▸ TLD (.ru):%b ' "$Y" "$N"
    _ru_rule=$(uci show dhcp.@dnsmasq[0].server 2>/dev/null | grep "'/ru/" | head -1)
    if [ -n "$_ru_rule" ]; then
        printf '%bВКЛ%b\n' "$G" "$N"
    else
        printf '%bВЫКЛ%b\n' "$R" "$N"
    fi

    # === 9. Sysctl ===
    printf '%b▸ Sysctl:%b ' "$Y" "$N"
    if [ -f /etc/sysctl.d/99-custom.conf ] && [ -s /etc/sysctl.d/99-custom.conf ]; then
        _sys_count=$(grep -c '=' /etc/sysctl.d/99-custom.conf)
        printf '%b%s%b\n' "$G" "$_sys_count" "$N"
    else
        printf '%bнет%b\n' "$R" "$N"
    fi

    # === 10. Go-opt ===
    printf '%b▸ Go-opt:%b\n' "$Y" "$N"
    _tg_go=0; _tailscale=0
    [ -f /etc/init.d/tg-ws-proxy-go ] && grep -q "GOMAXPROCS\|GOMEMLIMIT" /etc/init.d/tg-ws-proxy-go 2>/dev/null && _tg_go=1
    [ -f /etc/init.d/tailscale ] && grep -q "GOMEMLIMIT" /etc/init.d/tailscale 2>/dev/null && _tailscale=1
    if [ "$_tg_go" = "1" ] || [ "$_tailscale" = "1" ]; then
        [ "$_tg_go" = "1" ] && printf '    tg-ws-proxy: %b✓%b\n' "$G" "$N"
        [ "$_tailscale" = "1" ] && printf '    tailscale: %b✓%b\n' "$G" "$N"
    else
        printf '    %bне настроены%b\n' "$R" "$N"
    fi

    # === Zapret Manager ===
    _zapret_manager=0
    [ -f /usr/bin/zms ] && _zapret_manager=1
    [ -f /usr/bin/zmsA ] && _zapret_manager=1
    if [ "$_zapret_manager" = "1" ]; then
        printf '\n%b⚠ Zapret Manager обнаружен%b\n' "$Y" "$N"
    fi
}

# ============================================================
# ВОЗВРАТ В СТОК
# ============================================================
menu_reset_to_stock() {
    flush_stdin; clear_screen
    printf '%b========================================%b\n' "$R" "$N"
    printf '%b  ⚠ ВОЗВРАТ В СТОК (безопасный)%b\n' "$R" "$N"
    printf '%b========================================%b\n\n' "$R" "$N"
    printf 'Введите %bсток%b для подтверждения: ' "$G" "$N"
    safe_read confirm
    conf_clean=$(printf '%s' "$confirm" | tr -d ' \t\r\n' | tr 'A-Z' 'a-z')
    case "$conf_clean" in
        сток|stock|y|s|да) ;;
        *) printf '%bОтменено%b\n' "$Y" "$N"; sleep 1; return ;;
    esac

    /etc/init.d/https-dns-proxy stop 2>/dev/null; sleep 1
    pgrep https-dns-proxy >/dev/null 2>&1 && killall -9 https-dns-proxy 2>/dev/null && sleep 1
    /etc/init.d/https-dns-proxy disable 2>/dev/null
    while uci -q delete https-dns-proxy.@https-dns-proxy[0]; do :; done
    uci -q delete https-dns-proxy.config 2>/dev/null
    uci set https-dns-proxy.config='main'; uci set https-dns-proxy.config.update_dnsmasq='0'
    uci commit https-dns-proxy
    while uci -q delete dhcp.@dnsmasq[0].server; do :; done
    uci -q delete dhcp.@dnsmasq[0].noresolv 2>/dev/null
    uci commit dhcp
    uci -q delete firewall.redirect_ntp 2>/dev/null
    for _RULE in Block_UDP_80 Block_UDP_443; do
        while true; do
            _IDX=$(uci show firewall 2>/dev/null | grep "name='$_RULE'" | cut -d. -f2 | cut -d= -f1 | head -n1)
            [ -z "$_IDX" ] && break; uci -q delete firewall."$_IDX" 2>/dev/null
        done
    done
    uci -q delete firewall.@defaults[0].mtu_fix 2>/dev/null
    uci commit firewall
    while uci -q delete system.@timeserver[0]; do :; done
    uci -q delete system.ntp 2>/dev/null
    uci set system.ntp=timeserver; uci set system.ntp.enabled='1'; uci set system.ntp.enable_server='0'
    uci add_list system.ntp.server='0.openwrt.pool.ntp.org'
    uci add_list system.ntp.server='1.openwrt.pool.ntp.org'
    uci commit system
    rm -f /etc/dnsmasq.d/anti-block.conf /etc/sysctl.d/99-custom.conf /etc/hotplug.d/ntp/99-tailscale
    rm -f /root/rollback-dns.sh "$CONFIG_FILE" "$DNS_CATALOG" "$TEST_RESULTS"
    cleanup_tmp
    /etc/init.d/firewall restart 2>/dev/null
    /etc/init.d/dnsmasq restart 2>/dev/null
    /etc/init.d/sysntpd restart 2>/dev/null
    printf '\n%b✅ СТОК ВОССТАНОВЛЕН!%b\nПерезагрузка через 5 сек...\n' "$G" "$N"
    sleep 5; reboot; exit 0
}

# ============================================================
# ПРОФИЛИ (с АВТОПРИМЕНЕНИЕМ)
# ============================================================
menu_profile_default() {
    flush_stdin; clear_screen
    printf '%b========================================%b\n' "$B" "$N"
    printf '%b  ⚡ Профили (применяются сразу)%b\n' "$B" "$N"
    printf '%b========================================%b\n\n' "$B" "$N"
    printf '  1) Оптимальный: 4 обход + Yandex       [рек]\n'
    printf '  2) Максимум: 6 обход + 2 РУ Yandex\n'
    printf '  3) Одна голова: 1 DNS, балансир ВЫКЛ\n'
    printf '  4) Только рунет: Yandex для .ru\n'
    printf '  5) Семейный: AdGuard/CF/CleanBrows Fam\n'
    printf '  6) Приватный: AdGuard Unf + Mullvad\n'
    printf '  7) Чистый: CF + Google + Quad9\n'
    printf '  8) Быстрый: Mafioznik + Comss.ru\n'
    printf '  %bEnter) Отмена%b\n\n' "$C" "$N"
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
        *) printf '%bНеверный%b\n' "$R" "$N"; sleep 1; return ;;
    esac
    save_config
    printf '%b[✓] Профиль сохранён, применение...%b\n' "$G" "$N"
    apply_settings
}

# ============================================================
# ТЕСТ DNS
# ============================================================
menu_test_dns() {
    flush_stdin; clear_screen
    printf '%b========================================%b\n' "$B" "$N"
    printf '%b  🔍 Тест DNS (независимый)%b\n' "$B" "$N"
    printf '%b========================================%b\n\n' "$B" "$N"
    printf '%-20s %-8s %-8s %s\n' "DNS" "Тип" "Статус" "Скорость"
    printf '%b----------------------------------------------------------------%b\n' "$C" "$N"
    > "$TEST_RESULTS"
    grep -v '^#' "$DNS_CATALOG" | grep '|' | while IFS='|' read -r id name url dtype; do
        [ -z "$id" ] && continue
        host=$(printf '%s' "$url" | sed 's|^https://||; s|/.*$||')
        ip=$(resolve_host "$host")
        if [ "$dtype" = "bypass" ]; then type_ru="обход"; else type_ru="чистый"; fi
        if [ -z "$ip" ]; then
            printf '%-20s %-8s %bFAIL%b   %s\n' "$name" "$type_ru" "$R" "$N" "-"
            echo "${id}|0|FAIL" >> "$TEST_RESULTS"; continue
        fi
        t=$(curl -s -o /dev/null -w '%{time_total}' --max-time 5 \
            --resolve "$host:443:$ip" \
            "${url}?name=google.com&type=A" -H 'Accept: application/dns-json' 2>/dev/null)
        if [ -n "$t" ] && [ "$t" != "0.000000" ]; then
            ms=$(echo "$t" | awk '{printf "%.0f", $1 * 1000}')
            [ "$ms" -lt 100 ] && note="Быстрый" || { [ "$ms" -lt 300 ] && note="Норм" || note="Медл"; }
            printf '%-20s %-8s %bOK%b     %sms (%s)\n' "$name" "$type_ru" "$G" "$N" "$ms" "$note"
            echo "${id}|${ms}|OK" >> "$TEST_RESULTS"
        else
            printf '%-20s %-8s %bFAIL%b   %s\n' "$name" "$type_ru" "$R" "$N" "DoH"
            echo "${id}|0|FAIL" >> "$TEST_RESULTS"
        fi
    done
    echo ""; printf '%b----------------------------------------------------------------%b\n' "$C" "$N"
    ok=$(grep -c '|OK' "$TEST_RESULTS" 2>/dev/null)
    fail=$(grep -c '|FAIL' "$TEST_RESULTS" 2>/dev/null)
    printf 'Итого: %bOK: %s%b | %bFAIL: %s%b\n' "$G" "$ok" "$N" "$R" "$fail" "$N"
    printf '\nНажмите Enter...'; safe_read _
}

# ============================================================
# Выбор DNS для слота (с АВТОПРИМЕНЕНИЕМ)
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
        printf '%b  Слот #%s (применяется сразу)%b\n' "$B" "$slot_num" "$N"
        printf '%b========================================%b\n\n' "$B" "$N"
        case "$SELECT_FILTER" in bypass) fstr="ОБХОД" ;; clean) fstr="ЧИСТЫЕ" ;; *) fstr="все" ;; esac
        printf 'Фильтр: %b%s%b (95=переключить)\n\n' "$Y" "$fstr" "$N"
        i=1
        while IFS='|' read -r id name url dtype; do
            [ -z "$id" ] && continue
            if [ "$dtype" = "bypass" ]; then tag="[обход]"
            else tag="[чистый]"; fi
            tr_line=$(grep "^${id}|" "$TEST_RESULTS" 2>/dev/null | head -1)
            if [ -n "$tr_line" ]; then
                ms=$(printf '%s' "$tr_line" | cut -d'|' -f2)
                st=$(printf '%s' "$tr_line" | cut -d'|' -f3)
                if [ "$st" = "OK" ]; then
                    printf '  %2d) %-18s %-8s %sms\n' "$i" "$name" "$tag" "$ms"
                else
                    printf '  %2d) %-18s %-8s %bFAIL%b\n' "$i" "$name" "$tag" "$R" "$N"
                fi
            else
                printf '  %2d) %-18s %-8s %b(нет теста)%b\n' "$i" "$name" "$tag" "$Y" "$N"
            fi
            i=$((i+1))
        done < /tmp/.dns_sel
        echo ""
        printf '  %b99) Очистить  98) Свой URL  95) Фильтр  Enter) Отмена%b\n\n' "$C" "$N"
        printf 'Выбор: '; safe_read choice; [ -z "$choice" ] && return
        case "$choice" in
            99) eval "SLOT_${slot_num}=\"\""; save_config; apply_settings; return ;;
            98) printf 'URL: '; safe_read cu; [ -n "$cu" ] && { eval "SLOT_${slot_num}=\"custom:$cu\""; save_config; apply_settings; }; return ;;
            95) case "$SELECT_FILTER" in all) SELECT_FILTER="bypass" ;; bypass) SELECT_FILTER="clean" ;; *) SELECT_FILTER="all" ;; esac ;;
            *) total=$(wc -l < /tmp/.dns_sel)
               if [ "$choice" -ge 1 ] 2>/dev/null && [ "$choice" -le "$total" ] 2>/dev/null; then
                   sel_id=$(sed -n "${choice}p" /tmp/.dns_sel | cut -d'|' -f1)
                   eval "SLOT_${slot_num}=\"$sel_id\""
                   save_config
                   apply_settings
                   return
               fi; printf '%bНеверный%b\n' "$R" "$N"; sleep 1 ;;
        esac
    done
}

menu_slots() {
    flush_stdin
    while true; do
        clear_screen
        printf '%b========================================%b\n' "$B" "$N"
        printf '%b  Слоты DNS (применяются сразу)%b\n' "$B" "$N"
        printf '%b========================================%b\n\n' "$B" "$N"
        printf '%bИнтернет (макс 6):%b\n' "$Y" "$N"
        printf '  1) %s [%s]\n' "$(get_dns_name "$SLOT_1")" "$(get_dns_type_ru "$SLOT_1")"
        printf '  2) %s [%s]\n' "$(get_dns_name "$SLOT_2")" "$(get_dns_type_ru "$SLOT_2")"
        printf '  3) %s [%s]\n' "$(get_dns_name "$SLOT_3")" "$(get_dns_type_ru "$SLOT_3")"
        printf '  4) %s [%s]\n' "$(get_dns_name "$SLOT_4")" "$(get_dns_type_ru "$SLOT_4")"
        printf '  5) %s [%s]\n' "$(get_dns_name "$SLOT_5")" "$(get_dns_type_ru "$SLOT_5")"
        printf '  6) %s [%s]\n' "$(get_dns_name "$SLOT_6")" "$(get_dns_type_ru "$SLOT_6")"
        printf '\n%bРунет (макс 2):%b\n' "$Y" "$N"
        printf '  7) %s [%s]\n' "$(get_dns_name "$SLOT_RU")" "$(get_dns_type_ru "$SLOT_RU")"
        printf '  8) %s [%s]\n' "$(get_dns_name "$SLOT_RU_2")" "$(get_dns_type_ru "$SLOT_RU_2")"
        echo ""
        check_duplicates && printf '%b⚠ Есть дубли URL%b\n\n' "$Y" "$N"
        printf '  %bEnter) Назад%b\n' "$C" "$N"; printf 'Выбор: '; safe_read choice; [ -z "$choice" ] && return
        case "$choice" in
            1) select_dns_for_slot "1" ;; 2) select_dns_for_slot "2" ;; 3) select_dns_for_slot "3" ;;
            4) select_dns_for_slot "4" ;; 5) select_dns_for_slot "5" ;; 6) select_dns_for_slot "6" ;;
            7) select_dns_for_slot "RU" ;; 8) select_dns_for_slot "RU_2" ;;
            *) printf '%bНеверный%b\n' "$R" "$N"; sleep 1 ;;
        esac
    done
}

# ============================================================
# BOOTSTRAP (с АВТОПРИМЕНЕНИЕМ)
# ============================================================
menu_bootstrap() {
    flush_stdin
    while true; do
        clear_screen
        printf '%b========================================%b\n' "$B" "$N"
        printf '%b  Bootstrap DNS (применяется сразу)%b\n' "$B" "$N"
        printf '%b========================================%b\n\n' "$B" "$N"
        
        _real_bs=$(read_real_bootstrap)
        if [ -n "$_real_bs" ]; then
            printf 'Текущий: %b%s%b\n\n' "$G" "$_real_bs" "$N"
        else
            printf 'Текущий: %bне настроен%b\n\n' "$R" "$N"
        fi
        
        printf '  1) Полный 10 IP (Yandex+AdGuard+CF+Google+Quad9) [рек]\n'
        printf '  2) РФ безопасный (Yandex + AdGuard, 4 IP)\n'
        printf '  3) Только Yandex (2 IP)\n'
        printf '  4) Только AdGuard (2 IP)\n'
        printf '  5) Ввести свои IP\n'
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
        save_config
        apply_settings
        return
    done
}

# ============================================================
# NTP (с АВТОПРИМЕНЕНИЕМ)
# ============================================================
menu_ntp() {
    flush_stdin
    while true; do
        clear_screen
        printf '%b========================================%b\n' "$B" "$N"
        printf '%b  NTP серверы (применяются сразу)%b\n' "$B" "$N"
        printf '%b========================================%b\n\n' "$B" "$N"
        
        _real_ntp=$(read_real_ntp_servers)
        _real_preset=$(detect_real_ntp_preset)
        printf 'Текущий: %b%s%b\n' "$G" "$_real_preset" "$N"
        if [ -n "$_real_ntp" ]; then
            printf 'Серверы: %s\n\n' "$_real_ntp"
        else
            printf 'Серверы: %bне настроены%b\n\n' "$R" "$N"
        fi
        
        printf '  1) Смешанный [рек]  2) CF  3) Google  4) Pool\n'
        printf '  5) ВНИИФТРИ  6) RU  7) DHCP  8) Свой\n'
        printf '  %bEnter) Назад%b\n\n' "$C" "$N"
        printf 'Выбор: '; safe_read choice; [ -z "$choice" ] && return
        case "$choice" in
            1) NTP_PRESET="mixed" ;; 2) NTP_PRESET="cloudflare" ;; 3) NTP_PRESET="google" ;;
            4) NTP_PRESET="ntp_pool" ;; 5) NTP_PRESET="ru_vniiftri" ;; 6) NTP_PRESET="ru_ps" ;;
            7) NTP_PRESET="dhcp" ;; 8) printf 'IP: '; safe_read NTP_CUSTOM; NTP_PRESET="custom" ;; *) return ;;
        esac
        save_config
        apply_settings
    done
}

# ============================================================
# ДОП. НАСТРОЙКИ (с АВТОПРИМЕНЕНИЕМ)
# ============================================================
menu_extras() {
    flush_stdin
    while true; do
        clear_screen
        printf '%b========================================%b\n' "$B" "$N"
        printf '%b  Доп. настройки (применяются сразу)%b\n' "$B" "$N"
        printf '%b========================================%b\n\n' "$B" "$N"
        
        # Читаем реальные значения из UCI
        _real_bal=$(uci -q get dhcp.@dnsmasq[0].allservers 2>/dev/null)
        [ "$_real_bal" = "1" ] && b1="${G}[✓]${N}" || b1="${R}[ ]${N}"
        
        _real_tld=$(uci show dhcp.@dnsmasq[0].server 2>/dev/null | grep "'/ru/" | head -1)
        [ -n "$_real_tld" ] && b2="${G}[✓]${N}" || b2="${R}[ ]${N}"
        
        _real_quic=$(uci show firewall 2>/dev/null | grep "name='Block_UDP_443'" | head -1)
        [ -n "$_real_quic" ] && b3="${G}[✓]${N}" || b3="${R}[ ]${N}"
        
        _real_mtu=$(uci -q get firewall.@defaults[0].mtu_fix 2>/dev/null)
        [ "$_real_mtu" = "1" ] && b4="${G}[✓]${N}" || b4="${R}[ ]${N}"
        
        [ "$NTP_REDIRECT" = "1" ] && b5="${G}[✓]${N}" || b5="${R}[ ]${N}"
        
        _real_sys=0
        [ -f /etc/sysctl.d/99-custom.conf ] && [ -s /etc/sysctl.d/99-custom.conf ] && _real_sys=1
        [ "$_real_sys" = "1" ] && b6="${G}[✓]${N}" || b6="${R}[ ]${N}"
        
        _real_go=0
        [ -f /etc/init.d/tg-ws-proxy-go ] && grep -q "GOMAXPROCS\|GOMEMLIMIT" /etc/init.d/tg-ws-proxy-go 2>/dev/null && _real_go=1
        [ -f /etc/init.d/tailscale ] && grep -q "GOMEMLIMIT" /etc/init.d/tailscale 2>/dev/null && _real_go=1
        [ "$_real_go" = "1" ] && b7="${G}[✓]${N}" || b7="${R}[ ]${N}"
        
        printf '  1) %b Балансир\n' "$b1"
        printf '  2) %b TLD Split\n' "$b2"
        printf '  3) %b QUIC\n' "$b3"
        printf '  4) %b MTU\n' "$b4"
        printf '  5) %b NTP Redirect\n' "$b5"
        printf '  6) %b Sysctl\n' "$b6"
        printf '  7) %b Go-opt\n' "$b7"
        printf '  8) %b→ NTP: %s%b\n' "$Y" "$(detect_real_ntp_preset)" "$N"
        printf '  %bEnter) Назад%b\n\n' "$C" "$N"
        printf 'Выбор: '; safe_read choice; [ -z "$choice" ] && return
        case "$choice" in
            1) [ "$BALANCER_ENABLED" = "1" ] && BALANCER_ENABLED="0" || BALANCER_ENABLED="1"; save_config; apply_settings ;;
            2) [ "$TLD_RU_ENABLED" = "1" ] && TLD_RU_ENABLED="0" || TLD_RU_ENABLED="1"; save_config; apply_settings ;;
            3) [ "$BLOCK_QUIC" = "1" ] && BLOCK_QUIC="0" || BLOCK_QUIC="1"; save_config; apply_settings ;;
            4) [ "$MTU_FIX" = "1" ] && MTU_FIX="0" || MTU_FIX="1"; save_config; apply_settings ;;
            5) [ "$NTP_REDIRECT" = "1" ] && NTP_REDIRECT="0" || NTP_REDIRECT="1"; save_config; apply_settings ;;
            6) [ "$SYSCTL_TUNING" = "1" ] && SYSCTL_TUNING="0" || SYSCTL_TUNING="1"; save_config; apply_settings ;;
            7) [ "$GO_OPTIMIZE" = "1" ] && GO_OPTIMIZE="0" || GO_OPTIMIZE="1"; save_config; apply_settings ;;
            8) menu_ntp ;;
        esac
    done
}

# ============================================================
# ANTI-BLOCK
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
        printf '  1) Добавить IP  2) Удалить IP  3) Сброс\n'
        printf '  %bEnter) Назад%b\n' "$C" "$N"; printf 'Выбор: '; safe_read choice; [ -z "$choice" ] && return
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
# СОСТОЯНИЕ + ДИАГНОСТИКА
# ============================================================
menu_status() {
    flush_stdin; clear_screen
    printf '%b========================================%b\n' "$B" "$N"
    printf '%b  📊 Состояние + диагностика%b\n' "$B" "$N"
    printf '%b========================================%b\n\n' "$B" "$N"

    _a=$(uci -q get dhcp.@dnsmasq[0].allservers 2>/dev/null)
    [ "$_a" = "1" ] && printf '%b[✓] Балансир ВКЛ%b\n' "$G" "$N" || printf '%b[~] Балансир ВЫКЛ%b\n' "$Y" "$N"
    echo ""

    printf '%bdnsmasq:%b\n' "$C" "$N"
    pgrep dnsmasq >/dev/null 2>&1 && printf '  %b[✓] запущен%b\n' "$G" "$N" || printf '  %b[✗] НЕ запущен%b\n' "$R" "$N"
    if command -v netstat >/dev/null 2>&1; then
        netstat -ln 2>/dev/null | grep -q ':53 ' && printf '  %b[✓] порт 53%b\n' "$G" "$N" || printf '  %b[✗] порт 53%b\n' "$R" "$N"
    fi
    echo ""

    printf '%bDoH процессы:%b\n' "$C" "$N"
    _pc=$(ps | grep https-dns-proxy | grep -v grep | wc -l)
    if [ "$_pc" -eq 0 ]; then
        printf '  %b[✗] нет процессов%b\n' "$R" "$N"
    else
        printf '  %b[✓] %s процессов:%b\n' "$G" "$_pc" "$N"
        ps | grep https-dns-proxy | grep -v grep | awk '{p="";u="";for(i=1;i<=NF;i++){if($i=="-p")p=$(i+1);if($i=="-r")u=$(i+1)}if(p&&u)printf "    %s -> %s\n",p,u}'
    fi
    echo ""

    printf '%bBootstrap:%b\n' "$C" "$N"
    _real_bs=$(read_real_bootstrap)
    if [ -n "$_real_bs" ]; then
        printf '  %s\n' "$_real_bs"
    else
        printf '  %b(не настроен)%b\n' "$Y" "$N"
    fi
    printf '\n%bNTP:%b %s\n' "$C" "$N" "$(detect_real_ntp_preset)"
    echo ""

    printf '%bResolution (через dnsmasq):%b\n' "$C" "$N"
    _any_ok=0
    for dom in ya.ru chatgpt.com youtube.com instagram.com linkedin.com discord.com github.com; do
        ip=$(timeout 3 nslookup "$dom" 127.0.0.1 2>/dev/null | grep -vE '127\.0\.0\.|0\.0\.0\.0' | grep -oE '([0-9]{1,3}\.){3}[0-9]{1,3}' | head -n1)
        if [ -n "$ip" ]; then
            printf '  %-18s -> %b%s%b\n' "$dom" "$G" "$ip" "$N"
            _any_ok=1
        else
            printf '  %-18s -> %bNO_ANSWER%b\n' "$dom" "$R" "$N"
        fi
    done

    if [ "$_any_ok" = "0" ]; then
        echo ""
        printf '%b⚠ Все NO_ANSWER. Диагностика:%b\n' "$Y" "$N"
        pgrep dnsmasq >/dev/null 2>&1 || printf '  • dnsmasq не запущен\n'
        [ "$_pc" -eq 0 ] && printf '  • Нет DoH процессов → профиль 1\n'
        _first_port=$(ps | grep https-dns-proxy | grep -v grep | awk '{for(i=1;i<=NF;i++)if($i=="-p"){print $(i+1);exit}}')
        if [ -n "$_first_port" ] && command -v dig >/dev/null 2>&1; then
            _direct_ip=$(dig @127.0.0.1 -p "$_first_port" ya.ru A +short +time=2 2>/dev/null | grep -oE '([0-9]{1,3}\.){3}[0-9]{1,3}' | head -n1)
            [ -n "$_direct_ip" ] && printf '  • DoH порт %s отвечает → проблема dnsmasq\n' "$_first_port" \
                || printf '  • DoH порт %s не отвечает → проверь bootstrap\n' "$_first_port"
        fi
    fi

    echo ""; printf 'Нажмите Enter...'; safe_read _
}

# ============================================================
# ГЛАВНОЕ МЕНЮ — КОМПАКТНОЕ
# ============================================================
main_menu() {
    while true; do
        flush_stdin; clear_screen
        printf '%b╔══════════════════════════════════════════╗%b\n' "$B" "$N"
        printf '%b║  🌐 DNS Manager v%-23s║%b\n' "$B" "$VERSION" "$N"
        printf '%b║  Автоприменение | Русские метки%b         ║%b\n' "$B" "$N"
        printf '%b╚══════════════════════════════════════════╝%b\n\n' "$B" "$N"

        show_real_status

        echo ""
        printf '%bМеню:%b\n' "$Y" "$N"
        printf '  1) Профили  2) Слоты  3) Тест  4) Bootstrap  5) Доп  6) Anti-block  7) Сост  S) Сток  0) Выход\n\n'
        printf 'Выбор: '
        safe_read choice
        case "$choice" in
            1) menu_profile_default ;; 2) menu_slots ;; 3) menu_test_dns ;; 4) menu_bootstrap ;;
            5) menu_extras ;; 6) menu_antiblock ;; 7) menu_status ;;
            9) [ -f /root/rollback-dns.sh ] && sh /root/rollback-dns.sh || printf 'Нет отката\n'; safe_read _ ;;
            S|s|Ы|ы) menu_reset_to_stock ;; 0) exit 0 ;;
            *) printf '%bНеверный%b\n' "$R" "$N"; sleep 1 ;;
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
