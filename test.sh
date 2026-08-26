#!/bin/sh
# ============================================================
# DNS Manager v6.6-FIX5
# Русский DNS/DoH Manager для OpenWrt 22.03+ / 23.05 / 24.x / 25.x
# Первым делом читает реальное состояние роутера.
# Ничего не применяет без действия пользователя.
#
# Функции:
#   - DNS/DoH каталог 69 проверенных опубликованных endpoint'ов
#   - NTP IP-first: Cloudflare / NIST / Google отдельным профилем /
#     ВНИИФТРИ (Москва + регионы)
#   - Bootstrap DNS
#   - Bogus-NXDOMAIN каталог (только явно выбранные пользователем)
#   - обнаружение Zapret/Proxy/VPN/TG WS/Tailscale/SmartDNS/Unbound/AdGuard/MosDNS
#   - ownership OURS / FOREIGN / UNKNOWN
#   - ADD/UPDATE своих объектов, KEEP чужих
#   - журнал и транзакции
# ============================================================

MANAGER_PATH="/usr/bin/dns-manager"
VERSION="6.6-FIX5"
BASE_DIR="/etc/dns-manager"
CFG_DIR="$BASE_DIR/config"
STATE_DIR="$BASE_DIR/state"
LOG_FILE="/var/log/dns-manager.log"
TX_LOG="/var/log/dns-manager.tx"
CONFIG_FILE="$CFG_DIR/manager.conf"
DNS_CATALOG="$CFG_DIR/dns-catalog.conf"
NTP_CATALOG="$CFG_DIR/ntp-catalog.conf"
BOOTSTRAP_CATALOG="$CFG_DIR/bootstrap-catalog.conf"
BOGUS_CATALOG="$CFG_DIR/bogus-catalog.conf"
OWNERSHIP="$STATE_DIR/ownership.conf"
TEST_RESULTS="$STATE_DIR/dns-test-results.conf"
TMP_DIR="/tmp/dnsmgr"
TX_ID="$(date +%Y%m%d-%H%M%S)-$$"

C_RED='[1;31m'; C_GREEN='[1;32m'; C_YELLOW='[1;33m'; C_WHITE='[1;37m'; C_CYAN='[1;37m'; C_TITLE='[1;33m'; C_SECTION='[1;37m'; C_NC='[0m'

log_msg() {
    mkdir -p "$BASE_DIR" "$STATE_DIR" 2>/dev/null
    printf '[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >> "$LOG_FILE" 2>/dev/null
}
log_tx() {
    printf 'TX|%s|%s|%s|%s|%s|%s\n' "$TX_ID" "$(date +%s)" "$1" "$2" "$3" "$4" "$5" >> "$TX_LOG" 2>/dev/null
}
ok_msg() { log_msg "OK $*"; printf "${C_GREEN}[✓] %s${C_NC}\n" "$*"; }
warn_msg() { log_msg "WARN $*"; printf "${C_YELLOW}[!] %s${C_NC}\n" "$*"; }
err_msg() { log_msg "ERROR $*"; printf "${C_RED}[✗] %s${C_NC}\n" "$*"; }
safe_read() { read -r "$@"; }
pause() { printf "\n${C_WHITE}Нажмите Enter...${C_NC}"; safe_read _dummy; }
clear_screen() { command -v clear >/dev/null 2>&1 && clear || printf '\033[2J\033[H'; }
menu_header() {
    clear_screen
    printf "${C_TITLE}╔════════════════════════════════════════════════════╗${C_NC}\n"
    printf "${C_TITLE}║ %-50s ║${C_NC}\n" "$1"
    printf "${C_TITLE}╚════════════════════════════════════════════════════╝${C_NC}\n\n"
}

# ----- Bootstrap self-install. No config change here. -----
if [ ! -f "$0" ] || [ "$0" = "sh" ] || [ "$0" = "/bin/sh" ] || [ "$0" = "/bin/ash" ]; then
    mkdir -p "$(dirname "$MANAGER_PATH")" 2>/dev/null
    if wget -q -O "$MANAGER_PATH" "https://raw.githubusercontent.com/PoTuStoronu222/Openwrt-Smartdns-DoH/main/test.sh" 2>/dev/null ||
       curl -fsSL "https://raw.githubusercontent.com/PoTuStoronu222/Openwrt-Smartdns-DoH/main/test.sh" -o "$MANAGER_PATH" 2>/dev/null; then
        chmod +x "$MANAGER_PATH" 2>/dev/null
        exec "$MANAGER_PATH"
    fi
    printf "Не удалось скачать DNS Manager.\n" >&2
    exit 1
fi

preflight_readonly() {
    [ "$(id -u 2>/dev/null)" = 0 ] || { err_msg "Нужны права root."; exit 1; }
    [ -f /etc/openwrt_release ] || { err_msg "Это не OpenWrt."; exit 1; }
    if command -v apk >/dev/null 2>&1; then PKG_MGR="apk"; else PKG_MGR="opkg"; fi
    command -v timeout >/dev/null 2>&1 && HAVE_TIMEOUT=yes || HAVE_TIMEOUT=no
    SYS_OWRT="$(sed -n "s/^DISTRIB_RELEASE='\([^']*\)'.*/\1/p" /etc/openwrt_release | head -n1)"
    SYS_REV="$(sed -n "s/^DISTRIB_REVISION='\([^']*\)'.*/\1/p" /etc/openwrt_release | head -n1)"
    SYS_TARGET="$(sed -n "s/^DISTRIB_TARGET='\([^']*\)'.*/\1/p" /etc/openwrt_release | head -n1)"
    SYS_ARCH="$(sed -n "s/^DISTRIB_ARCH='\([^']*\)'.*/\1/p" /etc/openwrt_release | head -n1)"
}

init_dirs() {
    mkdir -p "$CFG_DIR" "$STATE_DIR" "$TMP_DIR" 2>/dev/null
    touch "$LOG_FILE" "$TX_LOG" "$OWNERSHIP" 2>/dev/null
}

write_catalogs() {
    if [ ! -s "$DNS_CATALOG" ] || ! grep -q '^# DNSCATVER=' "$DNS_CATALOG" 2>/dev/null; then
        cat > "$DNS_CATALOG" <<'EOF_DNS'
# DNSCATVER=6.6-R2
# FORMAT=ID|CATEGORY|PROFILE|NAME|URL|REGION|STATUS
# Main catalog: only endpoints with current published documentation/directory evidence.
# Runtime reachability MUST still be tested from the target OpenWrt router before recommendation/apply.
cloudflare_clean|clean|unfiltered|Cloudflare|https://cloudflare-dns.com/dns-query|global|verified-published-current
cloudflare_security|security|malware|Cloudflare Security|https://security.cloudflare-dns.com/dns-query|global|verified-published-current
cloudflare_family|family|malware+adult|Cloudflare Family|https://family.cloudflare-dns.com/dns-query|global|verified-published-current
google_clean|clean|unfiltered|Google Public DNS|https://dns.google/dns-query|global|verified-published-current
quad9_secure|security|malware+dnssec|Quad9 Secure|https://dns.quad9.net/dns-query|global|verified-published-current
quad9_unfiltered|clean|unfiltered+dnssec|Quad9 Unsecured|https://dns10.quad9.net/dns-query|global|verified-published-current
quad9_ecs|security|malware+ecs|Quad9 Secure ECS|https://dns11.quad9.net/dns-query|global|verified-published-current
adguard_default|adblock|ads+tracking+phishing|AdGuard DNS|https://dns.adguard-dns.com/dns-query|global|verified-published-current
adguard_family|family|ads+tracking+adult|AdGuard Family|https://family.adguard-dns.com/dns-query|global|verified-published-current
adguard_unfiltered|clean|unfiltered|AdGuard Unfiltered|https://unfiltered.adguard-dns.com/dns-query|global|verified-published-current
mullvad_clean|privacy|qname-minimization|Mullvad Clean|https://dns.mullvad.net/dns-query|global|verified-published-current
mullvad_adblock|adblock|ads+tracking|Mullvad Adblock|https://adblock.dns.mullvad.net/dns-query|global|verified-published-current
mullvad_base|security|ads+tracking+malware|Mullvad Base|https://base.dns.mullvad.net/dns-query|global|verified-published-current
mullvad_extended|security|ads+tracking+malware+social|Mullvad Extended|https://extended.dns.mullvad.net/dns-query|global|verified-published-current
mullvad_family|family|ads+tracking+malware+adult+gambling|Mullvad Family|https://family.dns.mullvad.net/dns-query|global|verified-published-current
mullvad_all|family|ads+tracking+malware+adult+gambling+social|Mullvad All|https://all.dns.mullvad.net/dns-query|global|verified-published-current
controld_p0|clean|unfiltered|Control D Unfiltered|https://freedns.controld.com/p0|global|verified-published-current
controld_p1|security|malware|Control D Malware|https://freedns.controld.com/p1|global|verified-published-current
controld_p2|adblock|ads+tracking|Control D Ads+Tracking|https://freedns.controld.com/p2|global|verified-published-current
controld_p3|social|social|Control D Social|https://freedns.controld.com/p3|global|verified-published-current
controld_family|family|family|Control D Family|https://freedns.controld.com/family|global|verified-published-current
controld_uncensored|clean|uncensored|Control D Uncensored|https://freedns.controld.com/uncensored|global|verified-published-current
opendns_standard|security|phishing+malware|OpenDNS Standard|https://doh.opendns.com/dns-query|global|verified-published-current
opendns_family|family|adult|OpenDNS FamilyShield|https://doh.familyshield.opendns.com/dns-query|global|verified-published-current
cleanbrowsing_security|security|phishing+malware|CleanBrowsing Security|https://doh.cleanbrowsing.org/doh/security-filter/|global|verified-published-current
cleanbrowsing_adult|family|adult+malware|CleanBrowsing Adult|https://doh.cleanbrowsing.org/doh/adult-filter/|global|verified-published-current
cleanbrowsing_family|family|adult+family|CleanBrowsing Family|https://doh.cleanbrowsing.org/doh/family-filter/|global|verified-published-current
nextdns_fast|privacy|unfiltered|NextDNS|https://dns.nextdns.io|global|verified-published-current
nextdns_anycast|privacy|anycast|NextDNS Anycast|https://anycast.dns.nextdns.io|global|verified-published-current
dns_sb|privacy|dnssec+no-logging|DNS.SB|https://doh.dns.sb/dns-query|global|verified-published-current
applied_privacy|privacy|privacy|Applied Privacy|https://doh.applied-privacy.net/query|europe|verified-published-current
cznic_odvr|security|dnssec+privacy|CZ.NIC ODVR|https://odvr.nic.cz/doh|czechia|verified-published-current
digitale_gesellschaft|privacy|privacy|Digitale Gesellschaft|https://dns.digitale-gesellschaft.ch/dns-query|switzerland|verified-published-current
dns4eu_protective|security|malware+phishing|DNS4EU Protective|https://protective.joindns4.eu/dns-query|eu|verified-published-current
dns4eu_child|family|child+malware|DNS4EU Child|https://child.joindns4.eu/dns-query|eu|verified-published-current
dns4eu_noads|adblock|ads+malware|DNS4EU No Ads|https://noads.joindns4.eu/dns-query|eu|verified-published-current
dns4eu_child_noads|family|child+ads|DNS4EU Child No Ads|https://child-noads.joindns4.eu/dns-query|eu|verified-published-current
dns4eu_unfiltered|clean|unfiltered|DNS4EU Unfiltered|https://unfiltered.joindns4.eu/dns-query|eu|verified-published-current
dns_for_family|family|adult|DNS for Family|https://dns-doh.dnsforfamily.com/dns-query|global|verified-published-current
cert_ee|security|malware+phishing|CERT-EE|https://dns.cert.ee/dns-query|estonia|verified-published-current
cira_private|privacy|unfiltered|CIRA Private|https://private.canadianshield.cira.ca/dns-query|canada|verified-published-current
cira_protected|security|malware+phishing|CIRA Protected|https://protected.canadianshield.cira.ca/dns-query|canada|verified-published-current
cira_family|family|adult+malware|CIRA Family|https://family.canadianshield.cira.ca/dns-query|canada|verified-published-current
comss_bypass|bypass|geo+ai+security|Comss.one|https://dns.comss.one/dns-query|ru/global|verified-published-current
comss_adblock_bypass|bypass|geo+ads+security|Comss.one Ad Filter|https://router.comss.one/dns-query|ru/global|verified-published-current
libredns_clean|privacy|privacy|LibreDNS|https://doh.libredns.gr/dns-query|greece/eu|verified-published-current
libredns_ads|adblock|ads|LibreDNS Ads|https://doh.libredns.gr/ads|greece/eu|verified-published-current
switch_ch|privacy|privacy|SWITCH DNS|https://dns.switch.ch/dns-query|switzerland|verified-published-current
wikimedia|privacy|anycast|Wikimedia DNS|https://wikimedia-dns.org/dns-query|global|verified-published-current
one_dns_pure|clean|unfiltered|OneDNS Pure|https://doh-pure.onedns.net/dns-query|asia|verified-published-current
one_dns_block|security|malware|OneDNS Block|https://doh.onedns.net/dns-query|asia|verified-published-current
dnsguard|adblock|ads+tracking+malware|DNSGuard|https://dns.dnsguard.pub/dns-query|global|verified-published-current
ffmuc|privacy|community|FFMUC|https://doh.ffmuc.net/dns-query|germany|verified-published-current
hagezi_root|security|ads+tracking+malware+phishing|HaGeZi Root|https://root.hagezi.org/dns-query|germany|verified-published-current
hagezi_wurzn|security|ads+tracking+malware+phishing|HaGeZi Wurzn|https://wurzn.hagezi.org/dns-query|germany|verified-published-current
hagezi_juuri|security|ads+tracking+malware+phishing|HaGeZi Juuri|https://juuri.hagezi.org/dns-query|finland|verified-published-current
nwps_standard|adblock|ads+tracking+malware|NWPS.fi Standard|https://public.ns.nwps.fi/dns-query|finland|verified-published-current
nwps_kids|family|kids+ads+malware|NWPS.fi Kids|https://kids.ns.nwps.fi/dns-query|finland|verified-published-current
oszx|adblock|ads|OSZX DNS|https://dns.oszx.co/dns-query|france|verified-published-current
pumplex|privacy|no-ads+dnssec|PumpleX|https://dns.pumplex.com/dns-query|france|verified-published-current
openbld_ada|security|ads+tracking+malware+phishing|OpenBLD ADA|https://ada.openbld.net/dns-query|global|verified-published-current
openbld_ric|security|strict-filtering|OpenBLD RIC|https://ric.openbld.net/dns-query|global|verified-published-current
dnsforge|privacy|privacy|dnsforge|https://dnsforge.de/dns-query|germany|verified-published-current
iijjp|family|child-protection|IIJ.JP DNS|https://public.dns.iij.jp/dns-query|japan|verified-published-current
he_public|clean|unfiltered+anycast|Hurricane Electric Public Recursor|https://ordns.he.net/dns-query|global|verified-published-current
dnsforge_youth|family|youth-protection|dnsforge Youth Protection|https://clean.dnsforge.de/dns-query|germany|verified-published-current
dnsforge_strict|security|strict-filtering|dnsforge Strict|https://hard.dnsforge.de/dns-query|germany|verified-published-current
hagezi_ctif|security|threat-only|HaGeZi CTIF|https://ctif.hagezi.org/dns-query|germany|verified-published-current
dnsbunker|security|balanced-threat|DNSBUNKER Pro+TIF|https://dnsbunker.org/dns-query|germany|verified-published-current
EOF_DNS
    fi
    if [ ! -s "$NTP_CATALOG" ] || ! grep -q '^# NTPCATVER=' "$NTP_CATALOG" 2>/dev/null; then
        cat > "$NTP_CATALOG" <<'EOF_NTP'
# NTPCATVER=6.6-FINAL
# ID|CATEGORY|NAME|IPV4|IPV6|MODE|LEAP|STATUS
cf_ip|global|Cloudflare|162.159.200.1 162.159.200.123|2606:4700:f1::1 2606:4700:f1::123|ip-first|no-smear|verified-current
nist_ip|global|NIST|129.6.15.28 129.6.15.29 129.6.15.30 129.6.15.27 129.6.15.26|2610:20:6f15:15::27 2610:20:6f15:15::26|ip-first|no-smear|verified-current
google_ip|special|Google Public NTP|216.239.35.0 216.239.35.4 216.239.35.8 216.239.35.12||ip-only|smear|verified-current
vniiftri_moscow|ru|ВНИИФТРИ Менделеево|89.109.251.21 89.109.251.22 89.109.251.23 89.109.251.24 89.109.251.25||ip-first|no-smear|verified-source
vniiftri_irkutsk|ru|ВНИИФТРИ Иркутск|46.254.241.74 46.254.241.75||ip-first|no-smear|verified-source
vniiftri_khabarovsk|ru|ВНИИФТРИ Хабаровск|212.19.6.218 212.19.17.26||ip-first|no-smear|verified-source
vniiftri_novosibirsk|ru|ВНИИФТРИ Новосибирск|80.242.83.227 80.242.83.228||ip-first|no-smear|verified-source
vniiftri_kamchatka|ru|ВНИИФТРИ Камчатка|91.189.237.182||ip-only|no-smear|verified-source
pool_global|pool|NTP Pool Global||||hostname|no-smear|runtime-check
pool_ru|pool|NTP Pool Russia||||hostname|no-smear|runtime-check
EOF_NTP
    fi
    if [ ! -s "$BOOTSTRAP_CATALOG" ] || ! grep -q '^# BOOTSTRAPCATVER=' "$BOOTSTRAP_CATALOG" 2>/dev/null; then
        cat > "$BOOTSTRAP_CATALOG" <<'EOF_BOOT'
# BOOTSTRAPCATVER=6.6
# ID|PROVIDER|IPV4|IPV6|ROLE|STATUS
yandex|Yandex|77.88.8.8,77.88.8.1|2a02:6b8::feed:0ff,2a02:6b8:0:1::feed:0ff|bootstrap|verified-current
adguard|AdGuard|94.140.14.14,94.140.15.15|2a10:50c0::ad1:ff,2a10:50c0::ad2:ff|bootstrap|verified-current
cloudflare|Cloudflare|1.1.1.1,1.0.0.1|2606:4700:4700::1111,2606:4700:4700::1001|bootstrap|verified-current
google|Google|8.8.8.8,8.8.4.4|2001:4860:4860::8888,2001:4860:4860::8844|bootstrap|verified-current
quad9|Quad9|9.9.9.9,149.112.112.112|2620:fe::fe,2620:fe::9|bootstrap|verified-current
opendns|OpenDNS|208.67.222.222,208.67.220.220|2620:119:35::35,2620:119:53::53|bootstrap|verified-current
cira|CIRA|149.112.121.10,149.112.122.10|2620:10A:80BB::10,2620:10A:80BC::10|bootstrap|verified-current
controld|Control D|76.76.2.0,76.76.10.0|2606:1a40::0,2606:1a40:1::0|bootstrap|verified-current
mullvad|Mullvad|194.242.2.2,194.242.2.3|2a07:e340::2,2a07:e340::3|bootstrap|verified-current
EOF_BOOT
    fi
    if [ ! -s "$BOGUS_CATALOG" ] || ! grep -q '^# BOGUSCATVER=' "$BOGUS_CATALOG" 2>/dev/null; then
        cat > "$BOGUS_CATALOG" <<'EOF_BOGUS'
# BOGUSCATVER=6.6
# ID|TYPE|IP|DESCRIPTION|CONFIDENCE|STATUS
rtk_95_167|hijack|95.167.13.50|Ростелеком: исторически подтвержденная заглушка|high|historical-confirmed
ttk_62_33|hijack|62.33.207.195|ТТК: исторически указанный адрес|medium|historical-confirmed
onlime_77_37|hijack|77.37.254.90|Онлайм: исторически указанный адрес|medium|historical-confirmed
enforta_87_241|hijack|87.241.223.133|Enforta: исторически указанный адрес|medium|historical-confirmed
legacy_185_179|hijack|185.179.189.20|Легаси-кандидат|low|needs-runtime-check
legacy_195_208|hijack|195.208.1.1|Легаси-кандидат|low|needs-runtime-check
legacy_95_182|hijack|95.182.120.241|Легаси-кандидат|low|needs-runtime-check
legacy_45_155|hijack|45.155.204.190|Легаси-кандидат|low|needs-runtime-check
legacy_37_230|hijack|37.230.192.51|Легаси-кандидат|low|needs-runtime-check
legacy_217_169|hijack|217.169.211.21|Легаси-кандидат|low|needs-runtime-check
sys_zero|system|0.0.0.0|Системное значение: только вручную|high|manual-only
sys_loop|system|127.0.0.1|Системное значение: только вручную|high|manual-only
EOF_BOGUS
    fi
}

load_config() {
    [ -f "$CONFIG_FILE" ] && . "$CONFIG_FILE" 2>/dev/null
    : "${SLOT_1:=}"; : "${SLOT_2:=}"; : "${SLOT_3:=}"; : "${SLOT_4:=}"; : "${SLOT_5:=}"; : "${SLOT_6:=}"
    : "${SLOT_RU:=}"; : "${SLOT_RU_2:=}"
    : "${PORT_1:=}"; : "${PORT_2:=}"; : "${PORT_3:=}"; : "${PORT_4:=}"; : "${PORT_5:=}"; : "${PORT_6:=}"
    : "${PORT_RU:=}"; : "${PORT_RU_2:=}"
    : "${BOOTSTRAP_DNS:=1.1.1.1,1.0.0.1,77.88.8.8,77.88.8.1,94.140.14.14,94.140.15.15,9.9.9.9,149.112.112.112}"
    : "${TLD_RU_ENABLED:=1}"; : "${BLOCK_QUIC:=0}"; : "${MTU_FIX:=0}"
    : "${NTP_IP_FALLBACK:=1}"; : "${SYSCTL_TUNING:=0}"; : "${GO_OPTIMIZE:=0}"
    : "${BALANCER_ENABLED:=1}"; : "${NTP_PRESET:=cf_ip}"
}
save_config() {
    umask 077
    cat > "$CONFIG_FILE" <<EOF_CFG
SLOT_1="$SLOT_1"
SLOT_2="$SLOT_2"
SLOT_3="$SLOT_3"
SLOT_4="$SLOT_4"
SLOT_5="$SLOT_5"
SLOT_6="$SLOT_6"
SLOT_RU="$SLOT_RU"
SLOT_RU_2="$SLOT_RU_2"
PORT_1="$PORT_1"
PORT_2="$PORT_2"
PORT_3="$PORT_3"
PORT_4="$PORT_4"
PORT_5="$PORT_5"
PORT_6="$PORT_6"
PORT_RU="$PORT_RU"
PORT_RU_2="$PORT_RU_2"
BOOTSTRAP_DNS="$BOOTSTRAP_DNS"
TLD_RU_ENABLED="$TLD_RU_ENABLED"
BLOCK_QUIC="$BLOCK_QUIC"
MTU_FIX="$MTU_FIX"
NTP_IP_FALLBACK="$NTP_IP_FALLBACK"
SYSCTL_TUNING="$SYSCTL_TUNING"
GO_OPTIMIZE="$GO_OPTIMIZE"
BALANCER_ENABLED="$BALANCER_ENABLED"
NTP_PRESET="$NTP_PRESET"
EOF_CFG
}

# ----- Discovery -----
disc_system() {
    SYS_FW="fw3"
    if command -v fw4 >/dev/null 2>&1 || [ -x /sbin/fw4 ] || [ -x /usr/sbin/fw4 ] || [ -f /usr/share/fw4/main.uc ] || [ -f /usr/share/fw4/helpers.sh ]; then
        SYS_FW="fw4"
    fi
    HAS_CURL="no"; command -v curl >/dev/null 2>&1 && HAS_CURL="yes"
    HAS_DIG="no"; command -v dig >/dev/null 2>&1 && HAS_DIG="yes"
    HAS_NTPD="no"; command -v ntpd >/dev/null 2>&1 && HAS_NTPD="yes"
    HAS_NTPQ="no"; command -v ntpq >/dev/null 2>&1 && HAS_NTPQ="yes"
    IPV4_ROUTE="no"; ip -4 route show default 2>/dev/null | grep -q . && IPV4_ROUTE="yes"
    IPV6_ROUTE="no"; ip -6 route show default 2>/dev/null | grep -q . && IPV6_ROUTE="yes"
    FREE_OVERLAY="$(df -k /overlay 2>/dev/null | awk 'NR==2{print $4}')"
}
disc_network() {
    LAN_IP="$(ip -4 addr 2>/dev/null | awk '/inet /{print $2}' | cut -d/ -f1 | awk '/^192\.|^10\.|^172\.(1[6-9]|2[0-9]|3[0-1])\./{print; exit}')"
    [ -n "$LAN_IP" ] || LAN_IP="$(uci -q get network.lan.ipaddr 2>/dev/null | cut -d/ -f1 | head -n1)"
    [ -n "$LAN_IP" ] || LAN_IP="192.168.1.1"
    WAN_PROTO="$(uci -q get network.wan.proto 2>/dev/null)"
    IP_RULES="$(ip rule show 2>/dev/null | wc -l)"
    IP6_RULES="$(ip -6 rule show 2>/dev/null | wc -l)"
}
disc_listeners() {
    LISTENERS="$TMP_DIR/listeners"
    : > "$LISTENERS"
    if command -v ss >/dev/null 2>&1; then
        ss -lntup 2>/dev/null >> "$LISTENERS"
    elif command -v netstat >/dev/null 2>&1; then
        netstat -lntup 2>/dev/null >> "$LISTENERS"
    fi
}
disc_dns() {
    DNSMASQ_RUN="no"; pgrep -x dnsmasq >/dev/null 2>&1 && DNSMASQ_RUN="yes"
    DOH_INV="$TMP_DIR/doh_inventory"; : > "$DOH_INV"
    DOH_TOTAL=0; DOH_OURS=0; DOH_FOREIGN=0; DOH_UNKNOWN=0
    FORCE_DNS="$(uci -q get https-dns-proxy.config.force_dns 2>/dev/null)"
    i=0
    while uci -q get "https-dns-proxy.@https-dns-proxy[$i]" >/dev/null 2>&1; do
        p="$(uci -q get "https-dns-proxy.@https-dns-proxy[$i].listen_port" 2>/dev/null)"
        a="$(uci -q get "https-dns-proxy.@https-dns-proxy[$i].listen_addr" 2>/dev/null)"
        u="$(normalize_url "$(uci -q get "https-dns-proxy.@https-dns-proxy[$i].resolver_url" 2>/dev/null)")"
        m="$(uci -q get "https-dns-proxy.@https-dns-proxy[$i].dns_manager" 2>/dev/null)"
        [ "$m" = 1 ] && owner="OURS" || owner="UNKNOWN"
        running="no"
        if [ -n "$p" ] && [ -s "$LISTENERS" ] && grep -qE "(:|\])$p([[:space:]]|$)" "$LISTENERS" 2>/dev/null; then running="yes"; fi
        [ "$owner" = UNKNOWN ] && [ "$running" = yes ] && owner="FOREIGN"
        [ "$owner" = OURS ] && DOH_OURS=$((DOH_OURS+1))
        [ "$owner" = FOREIGN ] && DOH_FOREIGN=$((DOH_FOREIGN+1))
        [ "$owner" = UNKNOWN ] && DOH_UNKNOWN=$((DOH_UNKNOWN+1))
        printf '%s|%s|%s|%s|%s|%s\n' "$i" "$p" "$owner" "$a" "$running" "$u" >> "$DOH_INV"
        i=$((i+1)); DOH_TOTAL=$((DOH_TOTAL+1))
    done
    DNS_SMARTDNS="no"; [ -x /etc/init.d/smartdns ] && DNS_SMARTDNS="yes"
    DNS_UNBOUND="no"; [ -x /etc/init.d/unbound ] && DNS_UNBOUND="yes"
    DNS_ADGUARD="no"; [ -x /etc/init.d/adguardhome ] && DNS_ADGUARD="yes"
    DNS_MOSDNS="no"; [ -x /etc/init.d/mosdns ] && DNS_MOSDNS="yes"
    DNS_SINGBOX="no"; [ -x /etc/init.d/sing-box ] && DNS_SINGBOX="yes"
}
disc_clients() {
    OTHER_ZAPRET="no"; { [ -f /etc/init.d/zapret ] || [ -f /usr/bin/zms ]; } && OTHER_ZAPRET="yes"
    OTHER_ZAPRET2="no"; [ -f /etc/init.d/zapret2 ] && OTHER_ZAPRET2="yes"
    OTHER_NETSHIFT="no"; command -v netshift >/dev/null 2>&1 && OTHER_NETSHIFT="yes"
    OTHER_SPLIFY="no"; [ -x /etc/init.d/splify ] && OTHER_SPLIFY="yes"
    OTHER_MIXOMO="no"; [ -x /etc/init.d/mihomo ] && OTHER_MIXOMO="yes"
    OTHER_MAGI="no"; pgrep -f magitrickle >/dev/null 2>&1 && OTHER_MAGI="yes"
    OTHER_HEV="no"; pgrep -f hev-socks5-tunnel >/dev/null 2>&1 && OTHER_HEV="yes"
    OTHER_AWG="no"; pgrep -f 'awg|amneziawg|wireguard' >/dev/null 2>&1 && OTHER_AWG="yes"
    OTHER_TGGO="no"; pgrep -f tg-ws-proxy-go >/dev/null 2>&1 && OTHER_TGGO="yes"
    OTHER_TGRS="no"; pgrep -f tg-ws-proxy-rs >/dev/null 2>&1 && OTHER_TGRS="yes"
    OTHER_TGMT="no"; pgrep -f tg-ws-proxy-mtproto >/dev/null 2>&1 && OTHER_TGMT="yes"
    OTHER_BYEDPI="no"; { [ -x /etc/init.d/byedpi ] || pgrep -f byedpi >/dev/null 2>&1; } && OTHER_BYEDPI="yes"
    OTHER_TAILSCALE="no"; [ -x /etc/init.d/tailscale ] && OTHER_TAILSCALE="yes"
}
disc_firewall() {
    QUIC_OURS=0; QUIC_FOREIGN=0
    if uci show firewall 2>/dev/null | grep -q "name='DnsMgr_QUIC_"; then
        QUIC_OURS=1
    fi
    if uci show firewall 2>/dev/null | grep -q "name='Block_UDP_80'" && \
       uci show firewall 2>/dev/null | grep -q "name='Block_UDP_443'"; then
        QUIC_FOREIGN=1
    fi
    [ "$(uci -q get firewall.@defaults[0].flow_offloading 2>/dev/null)" = 1 ] && FLOW_OFFLOAD="yes" || FLOW_OFFLOAD="no"
    if command -v nft >/dev/null 2>&1 && nft list ruleset >/dev/null 2>&1; then NFT_ACTIVE="yes"; else NFT_ACTIVE="no"; fi
}
run_discovery() {
    init_dirs
    disc_system
    disc_network
    disc_listeners
    disc_dns
    disc_clients
    disc_firewall
    log_tx "DISCOVER" "router" "READ" "OK" "OpenWrt=$SYS_OWRT;fw=$SYS_FW;dns=$DNSMASQ_RUN;doh=$DOH_TOTAL"
}

# ----- Catalog helpers -----
dns_field() { awk -F'|' -v id="$1" -v f="$2" '$1==id{print $f;exit}' "$DNS_CATALOG"; }
dns_name() { dns_field "$1" 4; }
dns_url() { dns_field "$1" 5; }
dns_cat() { dns_field "$1" 2; }
count_dns() { grep -v '^#' "$DNS_CATALOG" 2>/dev/null | grep -c '|'; }

ntp_name() { awk -F'|' -v id="$1" '$1==id{print $3;exit}' "$NTP_CATALOG"; }
ntp_ipv4() { awk -F'|' -v id="$1" '$1==id{print $4;exit}' "$NTP_CATALOG"; }
ntp_leap() { awk -F'|' -v id="$1" '$1==id{print $7;exit}' "$NTP_CATALOG"; }

# ----- Safe helpers -----
normalize_url() {
    _u="$1"
    _u="$(printf '%s' "$_u" | sed 's/[[:space:]]//g; s:/*$::')"
    printf '%s' "$_u"
}
file_hash() {
    if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" 2>/dev/null | awk '{print $1}'
    elif command -v md5sum >/dev/null 2>&1; then md5sum "$1" 2>/dev/null | awk '{print $1}'
    else printf ''
    fi
}

# ----- Bootstrap resolution -----
resolve_host() {
    host="$1"
    for bs in $(printf '%s' "$BOOTSTRAP_DNS" | tr ',' ' '); do
        if [ "$HAS_DIG" = yes ]; then
            ipx="$(dig +short "@$bs" "$host" A +time=2 +tries=1 2>/dev/null | awk '/^[0-9]+(\.[0-9]+){3}$/{print;exit}')"
        elif command -v nslookup >/dev/null 2>&1; then
            ipx="$(nslookup "$host" "$bs" 2>/dev/null | awk '/^Address: /{print $2}' | awk '/^[0-9]+(\.[0-9]+){3}$/{print;exit}')"
        else
            ipx=""
        fi
        [ -n "$ipx" ] && { echo "$ipx"; return 0; }
    done
    return 1
}

# ----- DNS tester -----
test_one_dns() {
    id="$1"; url="$(normalize_url "$(dns_url "$id")")"; name="$(dns_name "$id")"; cat="$(dns_cat "$id")"
    host="$(printf '%s' "$url" | sed 's#^https://##; s#/.*$##')"
    ipx="$(resolve_host "$host")"
    [ -n "$ipx" ] || { printf '%s|%s|%s|-1|BOOTSTRAP_FAIL\n' "$id" "$cat" "$name" > "$TMP_DIR/t.$id"; return; }
    q="$TMP_DIR/q.$id"; body="$TMP_DIR/body.$id"; hdr="$TMP_DIR/h.$id"
    : > "$body"; : > "$hdr"
    # RFC 8484 wire query: example.com A/IN
    printf '\022\064\001\000\000\001\000\000\000\000\000\000\007example\003com\000\000\001\000\001' > "$q"
    result="$(curl -4 -sS -o "$body" -D "$hdr" -w '%{http_code}|%{time_total}|%{errormsg}' \
        --connect-timeout 3 --max-time 6 --resolve "$host:443:$ipx" \
        -H 'Content-Type: application/dns-message' -H 'Accept: application/dns-message' \
        --data-binary "@$q" "$url" 2>/dev/null)"
    code="${result%%|*}"; rest="${result#*|}"; tim="${rest%%|*}"; err="${rest#*|}"
    [ "$code" = "$result" ] && code="000"
    bytes="$(wc -c < "$body" 2>/dev/null | tr -d ' ')"; [ -n "$bytes" ] || bytes=0
    ctype="$(awk -F': *' 'tolower($1)=="content-type"{print tolower($2)}' "$hdr" 2>/dev/null | tail -n1 | tr -d '\r')"
    case "$tim" in ''|0) ms=-1;; *) ms="$(awk -v t="$tim" 'BEGIN{v=t*1000; if(v<1)v=1; printf "%.0f", v}')";; esac
    case "$code" in
        200)
            case "$ctype" in *application/dns-message*) ct_ok=yes;; *) ct_ok=no;; esac
            if [ "$bytes" -ge 12 ] && [ "$ct_ok" = yes ]; then st=OK; else st=BAD_DOH_RESPONSE; fi ;;
        000)
            elc="$(printf '%s' "$err" | tr '[:upper:]' '[:lower:]')"
            case "$elc" in
                *timed*|*timeout*) st=CURL_TIMEOUT;;
                *ssl*|*tls*|*certificate*|*schannel*) st=TLS_ERROR;;
                *could\ not\ resolve*|*resolve\ host*|*name\ or\ service*) st=DNS_ERROR;;
                *connection\ refused*|*failed\ to\ connect*|*connection\ reset*|*could\ not\ connect*) st=CONNECTION_ERROR;;
                *) st=CURL_ERROR;;
            esac ;;
        4??|5??) st="HTTP_$code" ;;
        *) st="HTTP_$code" ;;
    esac
    printf '%s|%s|%s|%s|%s\n' "$id" "$cat" "$name" "$ms" "$st" > "$TMP_DIR/t.$id"
    rm -f "$q" "$body" "$hdr"
}
test_dns_catalog() {
    [ "$HAS_CURL" = yes ] || { warn_msg "curl не установлен. Сначала установите его через пункт I."; return 1; }
    rm -f "$TMP_DIR/t."* "$TMP_DIR/q."* "$TMP_DIR/body."* "$TMP_DIR/h."* "$TEST_RESULTS" 2>/dev/null
    total="$(count_dns)"
    printf "${C_WHITE}Проверяю %s DNS/DoH параллельно...${C_NC}\n" "$total"
    n=0
    while IFS='|' read -r id _rest; do
        case "$id" in ''|\#*) continue;; esac
        test_one_dns "$id" &
        n=$((n+1))
        [ $((n % 8)) -eq 0 ] && wait
    done < "$DNS_CATALOG"
    wait
    cat "$TMP_DIR"/t.* > "$TEST_RESULTS" 2>/dev/null
    okn="$(grep -c '|OK$' "$TEST_RESULTS" 2>/dev/null)"
    failn=$((total-okn))
    printf "${C_GREEN}✓ Успешно: %s${C_NC} | ${C_YELLOW}Проблемные: %s${C_NC} | Всего: %s\n" "$okn" "$failn" "$total"
    log_tx "TEST" "dns-catalog" "RUN" "OK" "ok=$okn,total=$total"
}
show_best_category() {
    cat="$1"; limit="$2"
    grep "|$cat|" "$TEST_RESULTS" 2>/dev/null | grep '|OK$' | sort -t'|' -k4,4n | head -n "$limit"
}

# ----- NTP -----
ntp_servers_for_profile() {
    case "$1" in
        cf_ip) echo "162.159.200.1 162.159.200.123";;
        nist_ip) echo "129.6.15.28 129.6.15.29 129.6.15.30 129.6.15.27 129.6.15.26";;
        google_ip) echo "216.239.35.0 216.239.35.4 216.239.35.8 216.239.35.12";;
        vniiftri_moscow) echo "89.109.251.21 89.109.251.22 89.109.251.23 89.109.251.24 89.109.251.25";;
        vniiftri_all) echo "89.109.251.21 89.109.251.22 89.109.251.23 89.109.251.24 89.109.251.25 46.254.241.74 46.254.241.75 212.19.6.218 212.19.17.26 80.242.83.227 80.242.83.228 91.189.237.182";;
        *) echo "";;
    esac
}
apply_ntp_ip_fallback() {
    servers="$(ntp_servers_for_profile "$NTP_PRESET")"
    [ -n "$servers" ] || { warn_msg "NTP-профиль не найден."; return 1; }
    sec="dns_manager_ntp"
    if [ "$(uci -q get "system.$sec" 2>/dev/null)" != timeserver ]; then
        uci set "system.$sec=timeserver" || return 1
        record_own "uci" "system.$sec" "timeserver" "created"
    fi
    existing="$(uci -q get "system.$sec.server" 2>/dev/null)"
    for ipx in $servers; do
        echo "$existing" | tr ' ' '\n' | grep -qxF "$ipx" || { uci add_list "system.$sec.server=$ipx"; record_own "ntp" "server" "$ipx" "section=$sec"; }
    done
    uci set "system.$sec.enabled=1"
    uci commit system
    ok_msg "Резерв времени по IP настроен в отдельной секции без удаления существующих NTP."
    log_tx "APPLY" "NTP" "ADD" "OK" "profile=$NTP_PRESET"
}
menu_ntp() {
    clear_screen
    printf "${C_TITLE}=== 🕐 NTP / время ===${C_NC}\n\n"
    printf "${C_YELLOW}[1]${C_NC} Cloudflare — IP, без DNS, без leap-smear\n"
    printf "2) NIST — несколько независимых IP, без DNS\n"
    printf "3) ВНИИФТРИ Москва — 5 IP\n"
    printf "4) ВНИИФТРИ все регионы — 12 IP\n"
    printf "5) Google — 4 IP, отдельный leap-smear профиль\n"
    printf "6) Текущий профиль: %s\n" "$NTP_PRESET"
    printf "Enter) Назад\n\nВыбор: "; safe_read c
    case "$c" in
        1) NTP_PRESET=cf_ip;;
        2) NTP_PRESET=nist_ip;;
        3) NTP_PRESET=vniiftri_moscow;;
        4) NTP_PRESET=vniiftri_all;;
        5) NTP_PRESET=google_ip;;
        *) return;;
    esac
    save_config
    printf "\nПрименить IP-резерв NTP сейчас? (y/n): "; safe_read a
    case "$a" in y|Y|д|Д) apply_ntp_ip_fallback; pause;; esac
}

# ----- DNS ownership and ports -----
find_own_doh_by_url() {
    awk -F'|' -v u="$(normalize_url "$1")" '$6==u && $3=="OURS"{print $1"|"$2;exit}' "$DOH_INV"
}
find_any_doh_by_url() {
    awk -F'|' -v u="$(normalize_url "$1")" '$6==u{print $1"|"$2"|"$3"|"$4"|"$5;exit}' "$DOH_INV"
}
find_own_doh_by_port() {
    awk -F'|' -v p="$1" '$2==p && $3=="OURS"{print $1"|"$2"|"$6;exit}' "$DOH_INV"
}
port_used_anywhere() {
    p="$1"
    [ -s "$LISTENERS" ] || return 2
    grep -qE ":$p([[:space:]]|$)" "$LISTENERS" 2>/dev/null && return 0
    awk -F'|' -v p="$p" '$2==p{found=1} END{exit found?0:1}' "$DOH_INV"
}
free_port() {
    p=5053
    while [ "$p" -le 5099 ]; do
        port_used_anywhere "$p"; rc=$?
        [ "$rc" = 2 ] && return 2
        [ "$rc" = 1 ] && { echo "$p"; return 0; }
        p=$((p+1))
    done
    return 1
}
record_own() { printf '%s|%s|%s|%s\n' "$1" "$2" "$3" "$4" >> "$OWNERSHIP"; }

ensure_doh_slot() {
    slot="$1"; id="$2"; [ -n "$id" ] || return 0
    url="$(normalize_url "$(dns_url "$id")")"; name="$(dns_name "$id")"
    [ -n "$url" ] || return 1

    # First choice: the exact port previously owned by this slot.
    p="$(eval "printf '%s' \"\${PORT_$slot}\"")"
    if [ -n "$p" ]; then
        ownp="$(find_own_doh_by_port "$p")"
        if [ -n "$ownp" ]; then
            sec_idx="$(printf '%s' "$ownp" | cut -d'|' -f1)"
            old_url="$(printf '%s' "$ownp" | cut -d'|' -f3)"
            if [ "$old_url" != "$url" ]; then
                printf "  ${C_WHITE}= обновляю наш слот %s: %s → %s${C_NC}\n" "$slot" "$old_url" "$url"
                uci set "https-dns-proxy.@https-dns-proxy[$sec_idx].resolver_url=$url"
                uci set "https-dns-proxy.@https-dns-proxy[$sec_idx].bootstrap_dns=$BOOTSTRAP_DNS"
                uci set "https-dns-proxy.@https-dns-proxy[$sec_idx].request_timeout=2"
            fi
            return 0
        fi
    fi

    existing="$(find_own_doh_by_url "$url")"
    if [ -n "$existing" ]; then
        p="$(printf '%s' "$existing" | cut -d'|' -f2)"
        eval "PORT_$slot=\"$p\""
        printf "  ${C_WHITE}= %s уже наш, порт %s${C_NC}\n" "$name" "$p"
        return 0
    fi

    existing="$(find_any_doh_by_url "$url")"
    if [ -n "$existing" ]; then
        p="$(printf '%s' "$existing" | cut -d'|' -f2)"
        owner="$(printf '%s' "$existing" | cut -d'|' -f3)"
        addr="$(printf '%s' "$existing" | cut -d'|' -f4)"
        run="$(printf '%s' "$existing" | cut -d'|' -f5)"
        if [ "$run" = yes ] && { [ "$addr" = 127.0.0.1 ] || [ "$addr" = 0.0.0.0 ] || [ "$addr" = "::1" ] || [ "$addr" = "::" ]; }; then
            printf "  ${C_YELLOW}= найден существующий %s (%s) на %s:%s.${C_NC}\n" "$name" "$owner" "$addr" "$p"
            printf "  Переиспользовать его вместо создания второго экземпляра? (y/n): "; safe_read _reuse
            case "$_reuse" in
                y|Y|д|Д) eval "PORT_$slot=\"$p\""; log_tx "PLAN" "doh.$id" "REUSE" "USER" "owner=$owner;port=$p"; return 0 ;;
                *) warn_msg "Не переиспользую чужой/неизвестный DoH автоматически."; return 1 ;;
            esac
        fi
        warn_msg "$name найден, но его нельзя безопасно переиспользовать (owner=$owner addr=$addr running=$run)."
        return 1
    fi

    if [ -n "$p" ]; then
        port_used_anywhere "$p"; rc=$?
        [ "$rc" = 0 ] && p=""
        [ "$rc" = 2 ] && p=""
    fi
    [ -n "$p" ] || p="$(free_port)"
    [ -n "$p" ] || { err_msg "Не удалось выбрать свободный порт для $name."; return 1; }
    port_used_anywhere "$p"; rc=$?; [ "$rc" = 2 ] && { err_msg "Нельзя доказать, что порт $p свободен."; return 1; }
    [ "$rc" = 0 ] && { err_msg "Порт $p уже занят."; return 1; }

    uci add https-dns-proxy https-dns-proxy >/dev/null || return 1
    sec='@https-dns-proxy[-1]'
    uci set "https-dns-proxy.$sec.listen_addr=127.0.0.1"
    uci set "https-dns-proxy.$sec.listen_port=$p"
    uci set "https-dns-proxy.$sec.resolver_url=$url"
    uci set "https-dns-proxy.$sec.bootstrap_dns=$BOOTSTRAP_DNS"
    uci set "https-dns-proxy.$sec.request_timeout=2"
    uci set "https-dns-proxy.$sec.dns_manager=1"
    record_own "doh" "$p" "$url" "slot=$slot;name=$name"
    eval "PORT_$slot=\"$p\""
    printf "  ${C_GREEN}+ %s → 127.0.0.1:%s${C_NC}\n" "$name" "$p"
}

get_dnsmasq_section() {
    # Prefer a dnsmasq instance explicitly attached to LAN.
    _secs="$(uci show dhcp 2>/dev/null | sed -n 's/^dhcp\.\([^.=]*\)=dnsmasq$/\1/p')"
    for _s in $_secs; do
        _iface="$(uci -q get "dhcp.$_s.interface" 2>/dev/null)"
        [ "$_iface" = "lan" ] && { printf '%s' "$_s"; return; }
    done
    _s="$(printf '%s\n' $_secs | head -n1)"
    [ -n "$_s" ] && { printf '%s' "$_s"; return; }
    printf '%s' "@dnsmasq[0]"
}
exact_list_has() {
    target="$1"; val="$2"
    uci -q get "$target" 2>/dev/null | tr ' ' '\n' | sed "s/^['\"]//; s/['\"]$//" | grep -qxF "$val"
}
reconcile_dnsmasq() {
    sec="$(get_dnsmasq_section)"
    uci -q get "dhcp.$sec" >/dev/null 2>&1 || return 1
    for s in 1 2 3 4 5 6; do
        eval "id=\${SLOT_$s}"; eval "p=\${PORT_$s}"
        [ -n "$id" ] && [ -n "$p" ] || continue
        val="127.0.0.1#$p"
        if ! exact_list_has "dhcp.$sec.server" "$val"; then
            uci add_list "dhcp.$sec.server=$val" || return 1
            record_own "dnsmasq" "server" "$val" "section=$sec"
        fi
    done
    if [ "$TLD_RU_ENABLED" = 1 ] && [ -n "$SLOT_RU" ] && [ -n "$PORT_RU" ]; then
        for t in /ru /su /xn--p1ai; do
            val="$t/127.0.0.1#$PORT_RU"
            exact_list_has "dhcp.$sec.server" "$val" || { uci add_list "dhcp.$sec.server=$val" || return 1; record_own "dnsmasq" "server" "$val" "section=$sec"; }
        done
    fi
    if [ "$TLD_RU_ENABLED" = 1 ] && [ -n "$SLOT_RU_2" ] && [ -n "$PORT_RU_2" ]; then
        for t in /ru /su /xn--p1ai; do
            val="$t/127.0.0.1#$PORT_RU_2"
            exact_list_has "dhcp.$sec.server" "$val" || { uci add_list "dhcp.$sec.server=$val" || return 1; record_own "dnsmasq" "server" "$val" "section=$sec"; }
        done
    fi
    if ! exact_list_has "dhcp.$sec.confdir" /etc/dnsmasq.d; then
        uci add_list "dhcp.$sec.confdir=/etc/dnsmasq.d" || return 1
        record_own "dnsmasq" "confdir" /etc/dnsmasq.d "section=$sec"
    fi
    # Do not silently rewrite an existing user's allservers/strictorder/noresolv.
    if [ "$BALANCER_ENABLED" = 1 ]; then
        cur_all="$(uci -q get "dhcp.$sec.allservers" 2>/dev/null)"
        cur_strict="$(uci -q get "dhcp.$sec.strictorder" 2>/dev/null)"
        if [ "$cur_all" != 1 ] || [ "$cur_strict" != 0 ]; then
            printf "${C_YELLOW}Балансировка dnsmasq: сейчас allservers=%s strictorder=%s. Изменить? (y/n): ${C_NC}" "${cur_all:-unset}" "${cur_strict:-unset}"
            safe_read _c
            case "$_c" in y|Y|д|Д) uci set "dhcp.$sec.allservers=1"; uci set "dhcp.$sec.strictorder=0"; record_own "dnsmasq" "option" "allservers=1;strictorder=0" "section=$sec";; esac
        fi
    fi
    if [ -n "$SLOT_1$SLOT_2$SLOT_3$SLOT_4$SLOT_5$SLOT_6$SLOT_RU$SLOT_RU_2" ]; then
        cur_nr="$(uci -q get "dhcp.$sec.noresolv" 2>/dev/null)"
        if [ "$cur_nr" != 1 ]; then
            printf "${C_YELLOW}Включить noresolv=1 для выбранной DoH-цепочки? (y/n): ${C_NC}"; safe_read _nr
            case "$_nr" in y|Y|д|Д) uci set "dhcp.$sec.noresolv=1"; record_own "dnsmasq" "option" "noresolv=1" "section=$sec";; esac
        fi
    fi
    uci commit dhcp
}

apply_quic() {
    [ "$BLOCK_QUIC" = 1 ] || return 0
    # REUSE semantics: never remove Block_UDP_* belonging to other managers.
    if [ "$QUIC_FOREIGN" = 1 ] || [ "$QUIC_OURS" = 1 ]; then
        printf "  ${C_WHITE}= QUIC: существующее правило оставлено, дубли не создаются.${C_NC}\n"
        return 0
    fi
    uci add firewall rule >/dev/null 2>&1 || return 1
    uci set firewall.@rule[-1].name=DnsMgr_QUIC_80
    uci add_list firewall.@rule[-1].proto=udp; uci set firewall.@rule[-1].src=lan; uci set firewall.@rule[-1].dest=wan; uci set firewall.@rule[-1].dest_port=80; uci set firewall.@rule[-1].target=REJECT
    uci add firewall rule >/dev/null 2>&1 || return 1
    uci set firewall.@rule[-1].name=DnsMgr_QUIC_443
    uci add_list firewall.@rule[-1].proto=udp; uci set firewall.@rule[-1].src=lan; uci set firewall.@rule[-1].dest=wan; uci set firewall.@rule[-1].dest_port=443; uci set firewall.@rule[-1].target=REJECT
    uci commit firewall
    record_own "firewall" "name" "DnsMgr_QUIC_80" "created"
    record_own "firewall" "name" "DnsMgr_QUIC_443" "created"
}

apply_sysctl() {
    [ "$SYSCTL_TUNING" = 1 ] || return 0
    f="/etc/sysctl.d/90-dns-manager.conf"
    sf="$STATE_DIR/sysctl-before.conf"
    [ -f "$f" ] || : > "$f" || return 1
    for p in "net.ipv4.tcp_fastopen=3" "net.ipv4.tcp_fin_timeout=15" "net.core.somaxconn=1024"; do
        key="${p%%=*}"; val="${p#*=}"; before="$(sysctl -n "$key" 2>/dev/null)"
        grep -q "^${key}|" "$sf" 2>/dev/null || printf '%s|%s\n' "$key" "${before:-unknown}" >> "$sf"
        foreign="$(grep -Rhs "^${key}=" /etc/sysctl.d 2>/dev/null | grep -v '^#' | grep -v "^${key}=${val}$" | head -n1)"
        if [ -n "$foreign" ] && ! grep -q "^${key}=${val}$" "$f" 2>/dev/null; then
            warn_msg "Не меняю $key: найдено стороннее значение ($foreign)."
            continue
        fi
        grep -q "^${key}=${val}$" "$f" 2>/dev/null || printf '%s\n' "$p" >> "$f"
        sysctl -w "$p" >/dev/null 2>&1 || warn_msg "Не удалось применить $p"
        record_own "sysctl" "$key" "$val" "before=${before:-unknown}"
    done
}

apply_go() {
    [ "$GO_OPTIMIZE" = 1 ] || return 0
    for f in /etc/init.d/tg-ws-proxy-go /etc/init.d/tailscale; do
        [ -f "$f" ] || continue
        marker="$(grep -c 'DNS_MANAGER_GOMEMLIMIT' "$f" 2>/dev/null)"
        current_hash="$(file_hash "$f")"
        hash_file="$STATE_DIR/$(basename "$f").managed.sha256"
        if [ -s "$hash_file" ] && [ "$(cat "$hash_file")" != "$current_hash" ] && [ "$marker" = 1 ]; then
            warn_msg "$f был изменён после последнего применения DNS Manager. Пропускаю Go-оптимизацию."
            continue
        fi
        if [ "$marker" = 1 ]; then
            continue
        fi
        bak="$f.dns-manager.bak"
        [ -f "$bak" ] || cp "$f" "$bak" 2>/dev/null || { warn_msg "Не удалось создать backup $f"; continue; }
        ev="GOMEMLIMIT=85MiB"; [ "$f" = "/etc/init.d/tg-ws-proxy-go" ] && ev="GOMAXPROCS=1 GOMEMLIMIT=50MiB"
        awk -v ev="$ev" '/procd_open_instance/{print;print "    # DNS_MANAGER_GOMEMLIMIT";print "    procd_set_param env "ev;next}1' "$f" > "$TMP_DIR/go.$$" || { rm -f "$TMP_DIR/go.$$"; continue; }
        mv "$TMP_DIR/go.$$" "$f" || continue
        file_hash "$f" > "$hash_file"
        record_own "file" "$f" "managed-hash" "$hash_file"
    done
}

apply_bogus() {
    clear_screen
    printf "${C_RED}=== IP-заглушки / bogus-nxdomain ===${C_NC}\n\n"
    printf "Каталог — это список кандидатов. Применяйте только подтверждённые для вашего upstream IP.\n\n"
    n=1
    while IFS='|' read -r id typ ip desc conf status; do
        case "$id" in ''|\#*) continue;; esac
        printf "%2d) %-15s %-8s %s [%s]\n" "$n" "$ip" "$typ" "$desc" "$status"
        n=$((n+1))
    done < "$BOGUS_CATALOG"
    printf "\nНомера через пробел, Enter=отмена: "; safe_read pick
    [ -n "$pick" ] || return
    conf="/etc/dnsmasq.d/90-dns-manager-bogus.conf"
    if [ ! -f "$conf" ]; then
        printf '%s\n' '# DNS_MANAGER_MANAGED=1' > "$conf" || return 1
        record_own "file" "$conf" "created" "bogus"
    elif ! grep -q '^# DNS_MANAGER_MANAGED=1$' "$conf"; then
        warn_msg "$conf уже существует и не помечен DNS Manager. Не меняю его."
        pause; return
    fi
    for n in $pick; do
        row="$(grep -v '^#' "$BOGUS_CATALOG" | sed -n "${n}p")"
        ip="$(printf '%s' "$row" | cut -d'|' -f3)"; status="$(printf '%s' "$row" | cut -d'|' -f6)"
        case "$status" in manual-only|needs-runtime-check) warn_msg "$ip нельзя применять автоматически: статус=$status"; continue;; esac
        [ -n "$ip" ] && ! grep -qxF "bogus-nxdomain=$ip" "$conf" 2>/dev/null && printf 'bogus-nxdomain=%s\n' "$ip" >> "$conf"
    done
    /etc/init.d/dnsmasq restart 2>/dev/null
    ok_msg "Выбранные подтверждённые bogus-nxdomain добавлены."
    pause
}

apply_ntp_if_needed() {
    [ "$NTP_IP_FALLBACK" = 1 ] || return 0
    apply_ntp_ip_fallback
}

verify_after_apply() {
    sleep 2
    pgrep -x dnsmasq >/dev/null 2>&1 || { err_msg "dnsmasq не запущен."; return 1; }
    if [ "$DOH_TOTAL" -gt 0 ]; then
        pgrep -f 'https-dns-proxy' >/dev/null 2>&1 || { err_msg "https-dns-proxy не запущен."; return 1; }
        for p in "$PORT_1" "$PORT_2" "$PORT_3" "$PORT_4" "$PORT_5" "$PORT_6" "$PORT_RU" "$PORT_RU_2"; do
            [ -n "$p" ] || continue
            [ -s "$LISTENERS" ] || return 1
            grep -qE ":$p([[:space:]]|$)" "$LISTENERS" 2>/dev/null || { err_msg "DoH порт $p не слушается."; return 1; }
        done
    fi
    if command -v nslookup >/dev/null 2>&1; then
        nslookup example.com 127.0.0.1 >/dev/null 2>&1 || { err_msg "Локальный DNS через 127.0.0.1 не отвечает."; return 1; }
    elif command -v dig >/dev/null 2>&1; then
        dig +time=2 +tries=1 @127.0.0.1 example.com A >/dev/null 2>&1 || { err_msg "Локальный DNS через 127.0.0.1 не отвечает."; return 1; }
    fi
    return 0
}

apply_settings() {
    clear_screen
    printf "${C_TITLE}=== ⚡ Применение ===${C_NC}\n\n"
    printf "1. Роутер будет прочитан заново.\n2. Чужие/неизвестные объекты остаются как есть.\n3. Свои объекты могут быть добавлены/обновлены.\n4. Общий https-dns-proxy может кратко перезапуститься.\n\n"
    printf "Продолжить? (y/n): "; safe_read c
    case "$c" in y|Y|д|Д) ;; *) return;; esac

    run_discovery
    load_config
    log_tx "PLAN" "all" "APPLY" "START" "version=$VERSION"

    if [ "$DOH_FOREIGN" -gt 0 ] || [ "$DOH_UNKNOWN" -gt 0 ]; then
        warn_msg "Обнаружены чужие/неизвестные DoH: чужих=$DOH_FOREIGN неизвестных=$DOH_UNKNOWN."
        printf "Перезапуск общей службы допустим? (y/n): "; safe_read c2
        case "$c2" in y|Y|д|Д) ;; *) return;; esac
    fi

    printf "\n${C_WHITE}План:${C_NC}\n"
    printf "  DoH: выбранные слоты будут добавлены или обновлены; чужие настройки не меняются.\n"
    printf "  DNS: будут добавлены только отсутствующие записи.\n"
    printf "  NTP: отдельная IP-first секция DNS Manager.\n"
    printf "  Дополнительные функции: изменяются только выбранные пользователем модули.\n\n"
    for s in 1 2 3 4 5 6; do eval "v=\${SLOT_$s}"; ensure_doh_slot "$s" "$v" || { err_msg "Не удалось подготовить слот $s."; return 1; }; done
    ensure_doh_slot RU "$SLOT_RU" || return 1
    ensure_doh_slot RU_2 "$SLOT_RU_2" || return 1
    uci commit https-dns-proxy 2>/dev/null

    reconcile_dnsmasq
    if [ "$NTP_IP_FALLBACK" = 1 ]; then
        printf "
${C_YELLOW}NTP IP-fallback включён: он нужен для ранней синхронизации времени без DNS.${C_NC}
"
        printf "Применить IP-профиль NTP вместе с DNS? (y/n): "; safe_read _ntp_apply
        case "$_ntp_apply" in y|Y|д|Д) apply_ntp_if_needed || return 1;; esac
    fi
    [ "$BLOCK_QUIC" = 1 ] && apply_quic
    [ "$MTU_FIX" = 1 ] && { uci -q set firewall.@defaults[0].mtu_fix=1; uci commit firewall; }
    [ "$SYSCTL_TUNING" = 1 ] && apply_sysctl
    [ "$GO_OPTIMIZE" = 1 ] && apply_go

    /etc/init.d/https-dns-proxy restart 2>/dev/null
    /etc/init.d/dnsmasq restart 2>/dev/null
    if [ "$SYS_FW" = fw4 ]; then /etc/init.d/firewall reload 2>/dev/null || /etc/init.d/firewall restart 2>/dev/null
    else /etc/init.d/firewall restart 2>/dev/null
    fi

    # Refresh actual state before verify.
    run_discovery
    if verify_after_apply; then
        log_tx "VERIFY" "all" "VERIFY" "OK" "dnsmasq=$DNSMASQ_RUN,doh=$DOH_TOTAL"
        ok_msg "Применение завершено и базовые проверки прошли."
    else
        log_tx "VERIFY" "all" "VERIFY" "FAIL" "dnsmasq=$DNSMASQ_RUN,doh=$DOH_TOTAL"
        err_msg "Базовая проверка не прошла. Чужие настройки автоматически не откатывались."
        warn_msg "Используйте журнал и пункт R для удаления только своих объектов."
    fi
    pause
}

rollback_ours() {
    clear_screen
    printf "${C_YELLOW}=== 🔄 Удаление только своих изменений ===${C_NC}\n\n"
    i=0
    while uci -q get "https-dns-proxy.@https-dns-proxy[$i]" >/dev/null 2>&1; do
        m="$(uci -q get "https-dns-proxy.@https-dns-proxy[$i].dns_manager" 2>/dev/null)"
        if [ "$m" = 1 ]; then uci -q delete "https-dns-proxy.@https-dns-proxy[$i]"; else i=$((i+1)); fi
    done
    uci commit https-dns-proxy 2>/dev/null
    sec="$(get_dnsmasq_section)"
    grep '^dnsmasq|server|' "$OWNERSHIP" 2>/dev/null | while IFS='|' read -r _type _key val _meta; do
        uci -q del_list "dhcp.$sec.server=$val" 2>/dev/null
    done
    uci commit dhcp 2>/dev/null
    for r in DnsMgr_QUIC_80 DnsMgr_QUIC_443; do
        while :; do idx="$(uci show firewall 2>/dev/null | grep "name='$r'" | head -n1 | cut -d. -f2 | cut -d= -f1)"; [ -n "$idx" ] || break; uci -q delete "firewall.$idx"; done
    done
    uci commit firewall 2>/dev/null
    if [ -f /etc/sysctl.d/90-dns-manager.conf ]; then
        for kv in net.ipv4.tcp_fastopen net.ipv4.tcp_fin_timeout net.core.somaxconn; do
            old="$(awk -F'|' -v k="$kv" '$1==k{print $2;exit}' "$STATE_DIR/sysctl-before.conf" 2>/dev/null)"
            cur="$(sysctl -n "$kv" 2>/dev/null)"
            mgr="$(awk -F'=' -v k="$kv" '$1==k{print $2;exit}' /etc/sysctl.d/90-dns-manager.conf 2>/dev/null)"
            [ -n "$old" ] && [ -n "$mgr" ] && [ "$cur" = "$mgr" ] && [ "$old" != unknown ] && sysctl -w "$kv=$old" >/dev/null 2>&1
        done
        rm -f /etc/sysctl.d/90-dns-manager.conf "$STATE_DIR/sysctl-before.conf"
    fi
    for f in /etc/init.d/tg-ws-proxy-go /etc/init.d/tailscale; do
        bak="$f.dns-manager.bak"
        if [ -f "$bak" ]; then
            curh="$(file_hash "$f")"; managedh="$(cat "$STATE_DIR/$(basename "$f").managed.sha256" 2>/dev/null)"
            if [ -n "$managedh" ] && [ -n "$curh" ] && [ "$curh" != "$managedh" ]; then
                warn_msg "Не восстанавливаю $f: он изменён после последнего применения DNS Manager."
            else
                mv "$bak" "$f" 2>/dev/null
            fi
        fi
    done
    /etc/init.d/https-dns-proxy restart 2>/dev/null
    /etc/init.d/dnsmasq restart 2>/dev/null
    printf "${C_GREEN}✓ Свои основные DoH/dnsmasq/firewall/sysctl/NTP изменения обработаны.${C_NC}\n"
    printf "${C_YELLOW}! Изменённые вручную файлы/объекты не перезаписывались.${C_NC}\n"
    pause
}

state_word() {
    case "$1" in
        yes|1|on|working|running) printf "${C_GREEN}ВКЛ • работает${C_NC}";;
        no|0|off|stopped|missing) printf "${C_YELLOW}ВЫКЛ • нет${C_NC}";;
        warn|warning) printf "${C_YELLOW}ВНИМАНИЕ${C_NC}";;
        error|fail) printf "${C_RED}ОШИБКА${C_NC}";;
        *) printf "${C_WHITE}%s${C_NC}" "$1";;
    esac
}
status_ru() {
    case "$1" in
        OK) printf '%s' '✓ работает';;
        BOOTSTRAP_FAIL) printf '%s' '⚠ не удалось определить адрес сервера';;
        BAD_DOH_RESPONSE) printf '%s' '⚠ неверный ответ DoH';;
        CURL_TIMEOUT|CURL_TIMEOUT*) printf '%s' '✗ тайм-аут соединения';;
        TLS_ERROR|TLS_ERROR*) printf '%s' '✗ ошибка TLS/сертификата';;
        CONNECTION_ERROR|CONNECTION_ERROR*) printf '%s' '✗ сервер недоступен';;
        DNS_ERROR|DNS_ERROR*) printf '%s' '✗ ошибка DNS-запроса';;
        HTTP_400) printf '%s' '✗ сервер отклонил запрос (400)';;
        HTTP_401) printf '%s' '✗ требуется авторизация (401)';;
        HTTP_403) printf '%s' '✗ доступ запрещён (403)';;
        HTTP_404) printf '%s' '✗ адрес DoH не найден (404)';;
        HTTP_429) printf '%s' '✗ слишком много запросов (429)';;
        HTTP_500) printf '%s' '✗ ошибка сервера (500)';;
        HTTP_502) printf '%s' '✗ шлюз сервера недоступен (502)';;
        HTTP_503) printf '%s' '✗ сервис временно недоступен (503)';;
        HTTP_504) printf '%s' '✗ сервер не ответил вовремя (504)';;
        HTTP_*) printf '%s' "✗ ответ HTTPS: код ${1#HTTP_}";;
        CURL_ERROR*) printf '%s' '✗ ошибка соединения HTTPS';;
        *) printf '%s' '✗ неизвестная ошибка';;
    esac
}
category_ru() {
    case "$1" in
        bypass) printf '%s' 'Обход';;
        clean) printf '%s' 'Чистый';;
        security) printf '%s' 'Безопасность';;
        privacy) printf '%s' 'Приватность';;
        adblock) printf '%s' 'Блокировка рекламы';;
        family) printf '%s' 'Семейный';;
        social) printf '%s' 'Социальный';;
        regional) printf '%s' 'Региональный';;
        *) printf '%s' "$1";;
    esac
}
owner_ru() {
    case "$1" in
        OURS) printf '%s' 'наш менеджер';;
        FOREIGN) printf '%s' 'другое приложение';;
        UNKNOWN) printf '%s' 'владелец не определён';;
        *) printf '%s' "$1";;
    esac
}
show_map() {
    clear_screen
    printf "${C_WHITE}╔════════════════════════════════════════════════╗\n"
    printf "║             📊 Карта состояния роутера         ║\n"
    printf "╚════════════════════════════════════════════════╝${C_NC}\n\n"
    printf "${C_WHITE}Система${C_NC}\n"
    printf "  OpenWrt: %s | платформа: %s | архитектура: %s\n" "$SYS_OWRT" "$SYS_TARGET" "$SYS_ARCH"
    printf "  Firewall: %s | LAN: %s | WAN: %s\n" "$SYS_FW" "$LAN_IP" "$WAN_PROTO"
    printf "  IPv4: %b | IPv6: %b\n" "$(state_word "$IPV4_ROUTE")" "$(state_word "$IPV6_ROUTE")"
    printf "  Инструменты: curl=%b dig=%b ntpd=%b\n\n" "$(state_word "$HAS_CURL")" "$(state_word "$HAS_DIG")" "$(state_word "$HAS_NTPD")"
    printf "${C_WHITE}DNS${C_NC}\n"
    printf "  dnsmasq: %b | DoH всего: %s\n" "$(state_word "$DNSMASQ_RUN")" "$DOH_TOTAL"
    printf "  Наших: %s | Чужих: %s | Неизвестных: %s\n" "$DOH_OURS" "$DOH_FOREIGN" "$DOH_UNKNOWN"
    printf "  SmartDNS=%b  Unbound=%b  AdGuardHome=%b\n" "$(state_word "$DNS_SMARTDNS")" "$(state_word "$DNS_UNBOUND")" "$(state_word "$DNS_ADGUARD")"
    printf "  MosDNS=%b  Sing-box=%b\n\n" "$(state_word "$DNS_MOSDNS")" "$(state_word "$DNS_SINGBOX")"
    printf "${C_WHITE}Сторонние решения${C_NC}\n"
    printf "  Zapret=%b  Zapret2=%b  NetShift=%b  splify=%b  Mixomo=%b\n" "$(state_word "$OTHER_ZAPRET")" "$(state_word "$OTHER_ZAPRET2")" "$(state_word "$OTHER_NETSHIFT")" "$(state_word "$OTHER_SPLIFY")" "$(state_word "$OTHER_MIXOMO")"
    printf "  MagiTrickle=%b  Hev=%b  AWG=%b\n" "$(state_word "$OTHER_MAGI")" "$(state_word "$OTHER_HEV")" "$(state_word "$OTHER_AWG")"
    printf "  TG-Go=%b  TG-Rust=%b  TG-MTProto=%b  ByeDPI=%b  Tailscale=%b\n\n" "$(state_word "$OTHER_TGGO")" "$(state_word "$OTHER_TGRS")" "$(state_word "$OTHER_TGMT")" "$(state_word "$OTHER_BYEDPI")" "$(state_word "$OTHER_TAILSCALE")"
    printf "${C_WHITE}Firewall${C_NC}\n"
    printf "  QUIC нашего менеджера: %b | чужое эквивалентное правило: %b\n" "$(state_word "$QUIC_OURS")" "$(state_word "$QUIC_FOREIGN")"
    printf "  активный nft: %b | аппаратное ускорение: %b\n\n" "$(state_word "$NFT_ACTIVE")" "$(state_word "$FLOW_OFFLOAD")"
    printf "${C_WHITE}Модули DNS Manager${C_NC}\n"
    printf "  Балансировка DNS: %b\n" "$(state_word "$BALANCER_ENABLED")"
    printf "  Раздельный DNS для .ru/.su/.рф: %b\n" "$(state_word "$TLD_RU_ENABLED")"
    printf "  Блокировка QUIC: %b\n" "$(state_word "$BLOCK_QUIC")"
    printf "  Исправление MTU: %b\n" "$(state_word "$MTU_FIX")"
    printf "  Резерв времени по IP: %b\n" "$(state_word "$NTP_IP_FALLBACK")"
    printf "  Оптимизация ядра: %b\n" "$(state_word "$SYSCTL_TUNING")"
    printf "  Оптимизация Go / Tailscale / TG WS: %b\n\n" "$(state_word "$GO_OPTIMIZE")"
    printf "${C_GREEN}✓ Discovery завершён. Изменений в конфигурацию не внесено.${C_NC}\n"
    pause
}
show_doh() {
    clear_screen
    printf "${C_WHITE}=== Найденные DoH ===${C_NC}\n\n"
    [ -s "$DOH_INV" ] || { printf "${C_YELLOW}https-dns-proxy секции не найдены.${C_NC}\n"; pause; return; }
    while IFS='|' read -r idx port owner addr running url; do
        printf "${C_YELLOW}#%-2s${C_NC} ${C_WHITE}%s${C_NC} %s:%s | владелец: %s | состояние: %b\n  URL: %s\n" "$idx" "$port" "$addr" "$port" "$(owner_ru "$owner")" "$(state_word "$running")" "$url"
    done < "$DOH_INV"
    pause
}
show_tests() {
    clear_screen
    printf "${C_WHITE}╔══════════════════════════════════════════════╗\n"
    printf "║             🔍 Результаты DNS-теста          ║\n"
    printf "╚══════════════════════════════════════════════╝${C_NC}\n\n"
    [ -s "$TEST_RESULTS" ] || { printf "${C_YELLOW}Тест ещё не запускался.${C_NC}\n"; pause; return; }
    okn="$(grep -c '|OK$' "$TEST_RESULTS" 2>/dev/null)"; total="$(count_dns)"; failn=$((total-okn))
    printf "${C_GREEN}Работает: %s${C_NC} | ${C_YELLOW}Не прошли тест: %s${C_NC} | Всего: %s\n\n" "$okn" "$failn" "$total"
    printf "${C_WHITE}%-26s %-11s %-7s %s${C_NC}\n" "DNS" "Категория" "Время" "Статус"
    printf "%s\n" "---------------------------------------------------------------"
    { grep '|OK$' "$TEST_RESULTS" 2>/dev/null | sort -t'|' -k4,4n; grep -v '|OK$' "$TEST_RESULTS" 2>/dev/null; } | while IFS='|' read -r id cat name ms st; do
        status_text="$(status_ru "$st")"
        cat_text="$(category_ru "$cat")"
        case "$st" in
            OK) status="${C_GREEN}${status_text}${C_NC}";;
            BOOTSTRAP_FAIL|BAD_DOH_RESPONSE) status="${C_YELLOW}${status_text}${C_NC}";;
            *) status="${C_RED}${status_text}${C_NC}";;
        esac
        case "$ms" in
            ''|-1) time="—";;
            *) time="${ms} мс";;
        esac
        printf "%-26s %-18s %-7s %b\n" "$name" "$cat_text" "$time" "$status"
    done
    pause
}
show_best() {
    [ -s "$TEST_RESULTS" ] || { warn_msg "Сначала выполните тест DNS."; pause; return; }
    clear_screen
    printf "${C_WHITE}╔══════════════════════════════════════════════╗\n║       ⭐ Лучшие DNS для этого роутера        ║\n╚══════════════════════════════════════════════╝${C_NC}\n\n"
    for c in bypass clean security privacy adblock family social regional; do
        case "$c" in bypass) title="ОБХОД";; clean) title="ЧИСТЫЕ";; security) title="БЕЗОПАСНОСТЬ";; privacy) title="ПРИВАТНОСТЬ";; adblock) title="БЛОКИРОВКА РЕКЛАМЫ";; family) title="СЕМЕЙНЫЕ";; social) title="СОЦИАЛЬНЫЕ СЕТИ";; regional) title="РЕГИОНАЛЬНЫЕ";; esac
        printf "${C_YELLOW}--- %s ---${C_NC}\n" "$title"
        show_best_category "$c" 3 | awk -F'|' '$4 >= 0 {printf "  %-24s %5sms\n", $3, $4}'
    done
    printf "\n${C_YELLOW}✓ В рекомендации попадают только ответы со статусом «работает».${C_NC}\n"
    pause
}
select_slot() {
    slot="$1"; clear_screen
    printf "${C_TITLE}=== Выбор DNS для слота %s ===${C_NC}\n\n" "$slot"
    n=1
    while IFS='|' read -r id cat prof name url region status; do
        case "$id" in ''|\#*) continue;; esac
        printf "${C_YELLOW}[%3d]${C_NC} %-24s ${C_WHITE}[%s]${C_NC}\n" "$n" "$name" "$cat"
        n=$((n+1))
    done < "$DNS_CATALOG"
    printf "\n${C_YELLOW}[99]${C_NC} Очистить   ${C_GREEN}[Enter]${C_NC} Назад\nВыбор: "; safe_read c
    [ -z "$c" ] && return
    if [ "$c" = 99 ]; then eval "SLOT_$slot="; save_config; return; fi
    row="$(grep -v '^#' "$DNS_CATALOG" | sed -n "${c}p")"
    id="$(printf '%s' "$row" | cut -d'|' -f1)"
    [ -n "$id" ] || return
    eval "SLOT_$slot=\"$id\""
    save_config
}
menu_slots() {
    while :; do
        clear_screen
        printf "${C_TITLE}=== ⚙ Слоты DNS (6+2) ===${C_NC}\n\n"
        for s in 1 2 3 4 5 6; do eval "v=\${SLOT_$s}"; eval "p=\${PORT_$s}"; printf "${C_YELLOW}[%s]${C_NC} %-24s порт=${C_WHITE}%s${C_NC}\n" "$s" "$(dns_name "$v")" "${p:-авто}"; done
        printf "${C_YELLOW}[7]${C_NC} RU  %-24s порт=${C_WHITE}%s${C_NC}\n" "$(dns_name "$SLOT_RU")" "${PORT_RU:-авто}"
        printf "${C_YELLOW}[8]${C_NC} RU2 %-24s порт=${C_WHITE}%s${C_NC}\n\n" "$(dns_name "$SLOT_RU_2")" "${PORT_RU_2:-авто}"
        printf "${C_GREEN}[Enter]${C_NC} Назад\nВыбор: "; safe_read c
        [ -z "$c" ] && return
        case "$c" in 1|2|3|4|5|6) select_slot "$c";; 7) select_slot RU;; 8) select_slot RU_2;; esac
    done
}
menu_bootstrap() {
    clear_screen
    printf "${C_TITLE}=== 🎯 Bootstrap DNS ===${C_NC}\n\n"
    printf "Сейчас: %s\n\n" "$BOOTSTRAP_DNS"
    printf "${C_YELLOW}[1]${C_NC} Независимые: Cloudflare + Yandex + AdGuard + Quad9 + Google\n"
    printf "${C_YELLOW}[2]${C_NC} Cloudflare + Yandex\n"
    printf "${C_YELLOW}[3]${C_NC} Только Cloudflare\n"
    printf "${C_YELLOW}[4]${C_NC} Ввести свои IPv4 через запятую\n${C_GREEN}[Enter]${C_NC} Назад\nВыбор: "; safe_read c
    case "$c" in
        1) BOOTSTRAP_DNS="1.1.1.1,1.0.0.1,77.88.8.8,77.88.8.1,94.140.14.14,94.140.15.15,9.9.9.9,149.112.112.112,8.8.8.8,8.8.4.4";;
        2) BOOTSTRAP_DNS="1.1.1.1,1.0.0.1,77.88.8.8,77.88.8.1";;
        3) BOOTSTRAP_DNS="1.1.1.1,1.0.0.1";;
        4) printf "IP: "; safe_read BOOTSTRAP_DNS;;
        *) return;;
    esac
    save_config
}
menu_bogus() {
    apply_bogus
}
menu_extras() {
    while :; do
        clear_screen
        printf "${C_WHITE}╔══════════════════════════════════════════════╗\n║          🔧 Дополнительные настройки         ║\n╚══════════════════════════════════════════════╝${C_NC}\n\n"
        printf "  ${C_YELLOW}[1]${C_NC} Балансировка dnsmasq: %b\n" "$(state_word "$BALANCER_ENABLED")"
        printf "  ${C_YELLOW}[2]${C_NC} Раздельный DNS (.ru/.su/.рф): %b\n" "$(state_word "$TLD_RU_ENABLED")"
        printf "  ${C_YELLOW}[3]${C_NC} QUIC: %b\n" "$(state_word "$BLOCK_QUIC")"
        printf "  ${C_YELLOW}[4]${C_NC} Исправление MTU: %b\n" "$(state_word "$MTU_FIX")"
        printf "  ${C_YELLOW}[5]${C_NC} Резерв времени по IP: %b\n" "$(state_word "$NTP_IP_FALLBACK")"
        printf "  ${C_YELLOW}[6]${C_NC} Sysctl: %b\n" "$(state_word "$SYSCTL_TUNING")"
        printf "  ${C_YELLOW}[7]${C_NC} Оптимизация Go / Tailscale / TG WS: %b\n" "$(state_word "$GO_OPTIMIZE")"
        printf "  ${C_YELLOW}[8]${C_NC} IP-заглушки\n"
        printf "  ${C_GREEN}[Enter]${C_NC} Назад\n\nВыбор: "; safe_read c
        [ -z "$c" ] && return
        case "$c" in
            1) [ "$BALANCER_ENABLED" = 1 ] && BALANCER_ENABLED=0 || BALANCER_ENABLED=1;;
            2) [ "$TLD_RU_ENABLED" = 1 ] && TLD_RU_ENABLED=0 || TLD_RU_ENABLED=1;;
            3) [ "$BLOCK_QUIC" = 1 ] && BLOCK_QUIC=0 || BLOCK_QUIC=1;;
            4) [ "$MTU_FIX" = 1 ] && MTU_FIX=0 || MTU_FIX=1;;
            5) [ "$NTP_IP_FALLBACK" = 1 ] && NTP_IP_FALLBACK=0 || NTP_IP_FALLBACK=1;;
            6) [ "$SYSCTL_TUNING" = 1 ] && SYSCTL_TUNING=0 || SYSCTL_TUNING=1;;
            7) [ "$GO_OPTIMIZE" = 1 ] && GO_OPTIMIZE=0 || GO_OPTIMIZE=1;;
            8) menu_bogus;;
            *) return;;
        esac
        save_config
    done
}
menu_install() {
    clear_screen
    printf "${C_TITLE}=== 📦 Установка недостающего ===${C_NC}\n\n"
    need=""
    [ "$HAS_CURL" = no ] && need="$need curl"
    [ "$HAS_DIG" = no ] && need="$need bind-dig"
    [ "$HAS_HDP" = no ] && need="$need https-dns-proxy"
    [ -z "$need" ] && { ok_msg "Всё нужное уже установлено."; pause; return; }
    printf "Не хватает:%s\n" "$need"
    printf "Установить сейчас? (y/n): "; safe_read c
    case "$c" in y|Y|д|Д)
        if [ "$PKG_MGR" = apk ]; then
            apk update && apk add --no-cache $need
        else
            [ "$need" != *"bind-dig"* ] && : 
            opkg update && opkg install $need
        fi
        run_discovery
        ;;
    esac
    pause
}
menu_status() {
    clear_screen
    printf "${C_WHITE}╔══════════════════════════════════════════════╗\n║             📋 Состояние и журнал            ║\n╚══════════════════════════════════════════════╝${C_NC}\n\n"
    printf "${C_WHITE}Последние события:${C_NC}\n"
    if [ -s "$LOG_FILE" ]; then tail -15 "$LOG_FILE"; else printf "${C_YELLOW}Журнал пока пуст.${C_NC}\n"; fi
    echo ""
    printf "${C_WHITE}Состояние последнего теста:${C_NC}\n"
    if [ -s "$TEST_RESULTS" ]; then
        total="$(count_dns)"; okn="$(grep -c '|OK$' "$TEST_RESULTS" 2>/dev/null)"; failn=$((total-okn))
        printf "  DNS: ${C_GREEN}%s работают${C_NC}, ${C_YELLOW}%s не прошли${C_NC}, всего %s\n" "$okn" "$failn" "$total"
    else
        printf "  ${C_YELLOW}Тест DNS ещё не запускался.${C_NC}\n"
    fi
    echo ""
    printf "${C_WHITE}Последние транзакции:${C_NC}\n"
    if [ -s "$TX_LOG" ]; then
        tail -10 "$TX_LOG" | awk -F'|' '{
            phase=$3; obj=$4; act=$5; res=$6;
            if (phase=="DISCOVER") phase="Диагностика";
            else if (phase=="TEST") phase="Тест";
            else if (phase=="PLAN") phase="План";
            else if (phase=="APPLY") phase="Применение";
            else if (phase=="VERIFY") phase="Проверка";
            if (res=="OK") res="успешно"; else if (res=="FAIL") res="ошибка";
            printf "  %s: %s → %s → %s\n", phase,obj,act,res;
        }'
    else
        printf "  ${C_YELLOW}Транзакций пока нет.${C_NC}\n"
    fi
    pause
}
main_menu() {
    while :; do
        run_discovery
        menu_header "DNS Manager $VERSION"
        printf "${C_SECTION}СТАТУСЫ: ${C_GREEN}✓ работает${C_NC}  ${C_YELLOW}— не включено / нет${C_NC}  ${C_RED}✗ ошибка${C_NC}

"
        printf "${C_SECTION}СИСТЕМА${C_NC}
"
        printf "  OpenWrt: ${C_WHITE}%s${C_NC} | платформа: ${C_WHITE}%s${C_NC} | архитектура: ${C_WHITE}%s${C_NC} | межсетевой экран: ${C_WHITE}%s${C_NC}
" "$SYS_OWRT" "$SYS_TARGET" "$SYS_ARCH" "$SYS_FW"
        printf "  IPv4: %s  IPv6: %s  dnsmasq: %s  DoH: ${C_WHITE}%s${C_NC}

" "$(state_word "$IPV4_ROUTE")" "$(state_word "$IPV6_ROUTE")" "$(state_word "$DNSMASQ_RUN")" "$DOH_TOTAL"
        printf "${C_SECTION}МЕНЮ${C_NC}
"
        printf "  ${C_YELLOW}[1]${C_NC} 📊 Карта состояния
"
        printf "  ${C_YELLOW}[2]${C_NC} 🔍 Тест всех DNS/DoH (${C_WHITE}%s${C_NC})
" "$(count_dns)"
        printf "  ${C_YELLOW}[3]${C_NC} ⭐ Лучшие DNS
"
        printf "  ${C_YELLOW}[4]${C_NC} ⚙ Слоты DNS (6+2)
"
        printf "  ${C_YELLOW}[5]${C_NC} 🎯 Bootstrap DNS
"
        printf "  ${C_YELLOW}[6]${C_NC} 🕐 Время / NTP (IP-first)
"
        printf "  ${C_YELLOW}[7]${C_NC} 🔧 Дополнительные настройки
"
        printf "  ${C_YELLOW}[8]${C_NC} 📋 Состояние и журнал
"
        printf "  ${C_YELLOW}[9]${C_NC} ⚡ Применить выбранное
"
        printf "  ${C_YELLOW}[I]${C_NC} 📦 Установить недостающее
"
        printf "  ${C_YELLOW}[R]${C_NC} 🔄 Удалить только изменения DNS Manager
"
        printf "
  ${C_GREEN}[Enter]${C_NC} Выход

"
        printf "${C_WHITE}Выбор: ${C_NC}"; safe_read c
        [ -z "$c" ] && { rm -rf "$TMP_DIR"; clear_screen; printf "${C_GREEN}DNS Manager завершён.${C_NC}
"; exit 0; }
        case "$c" in
            1) show_map;; 2) test_dns_catalog; show_tests;; 3) show_best;; 4) menu_slots;;
            5) menu_bootstrap;; 6) menu_ntp;; 7) menu_extras;; 8) menu_status;; 9) apply_settings;;
            I|i) menu_install;; R|r|К|к) rollback_ours;;
            *) warn_msg "Неизвестный пункт. Используйте номер меню или Enter для выхода."; pause;;
        esac
    done
}

# ENTRY: always read first.
preflight_readonly
init_dirs
write_catalogs
load_config
run_discovery
printf "${C_GREEN}✓ Первый проход завершён. Настройки роутера пока не изменялись.${C_NC}\n"
log_msg "START v$VERSION OpenWrt=$SYS_OWRT target=$SYS_TARGET arch=$SYS_ARCH fw=$SYS_FW"
main_menu
