#!/bin/sh
# ============================================================
# DNS Manager v6.6-FINAL
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
VERSION="6.6-FINAL"
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

C_RED='\033[1;31m'; C_GREEN='\033[1;32m'; C_YELLOW='\033[1;33m'
C_BLUE='\033[1;34m'; C_CYAN='\033[1;36m'; C_NC='\033[0m'

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
pause() { printf "\n${C_CYAN}Нажмите Enter...${C_NC}"; safe_read _dummy; }
clear_screen() { command -v clear >/dev/null 2>&1 && clear || printf '\033[2J\033[H'; }

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
    [ -x /usr/sbin/fw4 ] || [ -f /usr/share/fw4/helpers.sh ] && SYS_FW="fw4"
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
    quic80=0; quic443=0
    while IFS='|' read -r name src dest proto dport target; do
        [ "$proto" = udp ] || continue
        [ "$src" = lan ] || continue
        [ "$dest" = wan ] || continue
        [ "$target" = REJECT ] || continue
        [ "$dport" = 80 ] && quic80=1
        [ "$dport" = 443 ] && quic443=1
    done <<EOF_FW
$(uci show firewall 2>/dev/null | awk -F"[.=']+" '/name=/ {name=$3} /src=/ {src=$3} /dest=/ {dest=$3} /proto=/ {proto=$3} /dest_port=/ {dport=$3} /target=/ {target=$3; print name"|"src"|"dest"|"proto"|"dport"|"target"; src=dest=proto=dport=target=""}')
EOF_FW
    if [ "$quic80" = 1 ] && [ "$quic443" = 1 ]; then QUIC_OURS=0; QUIC_FOREIGN=1; fi
    if uci show firewall 2>/dev/null | grep -q "name='DnsMgr_QUIC_"; then QUIC_OURS=1; fi
    [ "$(uci -q get firewall.@defaults[0].flow_offloading 2>/dev/null)" = 1 ] && FLOW_OFFLOAD="yes" || FLOW_OFFLOAD="no"
    command -v nft >/dev/null 2>&1 && nft list ruleset >/dev/null 2>&1 && NFT_ACTIVE="yes" || NFT_ACTIVE="no"
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
    if [ -z "$ipx" ]; then
        printf '%s|%s|%s|0|BOOTSTRAP_FAIL\n' "$id" "$cat" "$name" > "$TMP_DIR/t.$id"
        return
    fi
    q="$TMP_DIR/q.$id"; body="$TMP_DIR/body.$id"; hdr="$TMP_DIR/h.$id"
    # DNS wire query: transaction 0x1234, RD=1, one A/IN question for example.com.
    printf '\022\064\001\000\000\001\000\000\000\000\000\000\007example\003com\000\000\001\000\001' > "$q"
    t0="$(date +%s)"
    code="$(curl -4 -sS -o "$body" -D "$hdr" -w '%{http_code}' \
        --connect-timeout 3 --max-time 6 --resolve "$host:443:$ipx" \
        -H 'Content-Type: application/dns-message' -H 'Accept: application/dns-message' \
        --data-binary "@$q" "$url" 2>/dev/null)"
    t1="$(date +%s)"; ms=$(( (t1-t0)*1000 ))
    bytes="$(wc -c < "$body" 2>/dev/null | tr -d ' ')"
    ctype="$(awk -F': *' 'tolower($1)=="content-type"{print tolower($2)}' "$hdr" 2>/dev/null | tail -n1 | tr -d '\r')"
    case "$ctype" in *application/dns-message*) ct_ok=yes;; *) ct_ok=no;; esac
    if [ "$code" = 200 ] && [ "${bytes:-0}" -ge 12 ] && [ "$ct_ok" = yes ]; then st=OK; else st="FAIL_${code}"; fi
    printf '%s|%s|%s|%s|%s\n' "$id" "$cat" "$name" "$ms" "$st" > "$TMP_DIR/t.$id"
    rm -f "$q" "$body" "$hdr"
}
test_dns_catalog() {
    [ "$HAS_CURL" = yes ] || { warn_msg "curl не установлен. Сначала установите его через пункт I."; return 1; }
    rm -f "$TMP_DIR/t."* "$TEST_RESULTS" 2>/dev/null
    printf "${C_CYAN}Проверяю %s DNS параллельно...${C_NC}\n" "$(count_dns)"
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
    printf "${C_GREEN}OK: %s${C_NC} | Всего: %s\n" "$okn" "$(count_dns)"
    log_tx "TEST" "dns-catalog" "RUN" "OK" "ok=$okn,total=$(count_dns)"
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
    ok_msg "NTP IP fallback настроен в отдельной секции без удаления существующих NTP."
    log_tx "APPLY" "NTP" "ADD" "OK" "profile=$NTP_PRESET"
}
menu_ntp() {
    clear_screen
    printf "${C_BLUE}=== 🕐 NTP / время ===${C_NC}\n\n"
    printf "1) Cloudflare — IP, без DNS, без leap-smear\n"
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
                printf "  ${C_CYAN}= обновляю наш слот %s: %s → %s${C_NC}\n" "$slot" "$old_url" "$url"
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
        printf "  ${C_CYAN}= %s уже наш, порт %s${C_NC}\n" "$name" "$p"
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
        printf "  ${C_CYAN}= QUIC: существующее правило оставлено, дубли не создаются.${C_NC}\n"
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
    printf "${C_BLUE}=== ⚡ Применение ===${C_NC}\n\n"
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

    printf "\n${C_CYAN}План:${C_NC}\n"
    printf "  DoH: выбранные слоты будут добавлены/обновлены, чужие — только REUSE при совместимости.\n"
    printf "  DNS: добавятся только отсутствующие server/confdir записи.\n"
    printf "  NTP: отдельная IP-first секция DNS Manager.\n"
    printf "  Firewall/Sysctl/Go: только включённые пользователем модули.\n\n"
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

show_map() {
    clear_screen
    printf "${C_BLUE}╔══════════════════════════════════════════╗\n║       📊 Карта состояния роутера        ║\n╚══════════════════════════════════════════╝${C_NC}\n\n"
    printf "OpenWrt: %s | revision: %s | target: %s | arch: %s | firewall: %s\n" "$SYS_OWRT" "$SYS_REV" "$SYS_TARGET" "$SYS_ARCH" "$SYS_FW"
    printf "IPv4 route=%s | IPv6 route=%s | LAN=%s | WAN proto=%s\n" "$IPV4_ROUTE" "$IPV6_ROUTE" "$LAN_IP" "$WAN_PROTO"
    printf "Инструменты: curl=%s dig=%s ntpd=%s\n\n" "$HAS_CURL" "$HAS_DIG" "$HAS_NTPD"
    printf "${C_YELLOW}DNS:${C_NC} dnsmasq=%s | DoH=%s (наш=%s, чужой=%s, неизвестный=%s)\n" "$DNSMASQ_RUN" "$DOH_TOTAL" "$DOH_OURS" "$DOH_FOREIGN" "$DOH_UNKNOWN"
    printf "SmartDNS=%s Unbound=%s AdGuardHome=%s MosDNS=%s Sing-box=%s\n" "$DNS_SMARTDNS" "$DNS_UNBOUND" "$DNS_ADGUARD" "$DNS_MOSDNS" "$DNS_SINGBOX"
    printf "${C_YELLOW}Сторонние:${C_NC} Zapret=%s Zapret2=%s NetShift=%s splify=%s Mixomo=%s\n" "$OTHER_ZAPRET" "$OTHER_ZAPRET2" "$OTHER_NETSHIFT" "$OTHER_SPLIFY" "$OTHER_MIXOMO"
    printf "MagiTrickle=%s HevSocks5Tunnel=%s AWG=%s TG-Go=%s TG-Rust=%s TG-MTProto=%s ByeDPI=%s Tailscale=%s\n" "$OTHER_MAGI" "$OTHER_HEV" "$OTHER_AWG" "$OTHER_TGGO" "$OTHER_TGRS" "$OTHER_TGMT" "$OTHER_BYEDPI" "$OTHER_TAILSCALE"
    printf "${C_YELLOW}Firewall:${C_NC} QUIC ours=%s foreign=%s nft-active=%s flow-offload=%s\n" "$QUIC_OURS" "$QUIC_FOREIGN" "$NFT_ACTIVE" "$FLOW_OFFLOAD"
    printf "\n${C_GREEN}✓ Discovery read-only завершён. Изменений конфигурации не выполнено.${C_NC}\n"
    pause
}
show_doh() {
    clear_screen
    printf "${C_BLUE}=== Найденные DoH ===${C_NC}\n\n"
    [ -s "$DOH_INV" ] || { printf "https-dns-proxy секции не найдены.\n"; pause; return; }
    while IFS='|' read -r idx port addr url owner; do
        printf "#%-2s %-5s  %s:%s  %s\n" "$idx" "$url" "$addr" "$port" "$owner"
    done < "$DOH_INV"
    pause
}
show_tests() {
    clear_screen
    printf "${C_BLUE}=== 🔍 Результаты DNS-теста ===${C_NC}\n\n"
    [ -s "$TEST_RESULTS" ] || { printf "Тест не выполнен.\n"; pause; return; }
    printf "%-24s %-10s %-7s %s\n" "DNS" "Категория" "ms" "Статус"
    sort -t'|' -k4,4n "$TEST_RESULTS" | head -80 | while IFS='|' read -r id cat name ms st; do
        printf "%-24s %-10s %-7s %s\n" "$name" "$cat" "$ms" "$st"
    done
    pause
}
show_best() {
    [ -s "$TEST_RESULTS" ] || { warn_msg "Сначала выполните тест DNS."; pause; return; }
    clear_screen
    printf "${C_BLUE}=== ⭐ Лучшие DNS для этого роутера ===${C_NC}\n\n"
    for c in bypass clean security privacy adblock family social regional; do
        case "$c" in bypass) title="ОБХОД";; clean) title="ЧИСТЫЕ";; security) title="БЕЗОПАСНОСТЬ";; privacy) title="ПРИВАТНОСТЬ";; adblock) title="ADBLOCK";; family) title="СЕМЕЙНЫЕ";; social) title="SOCIAL";; regional) title="РЕГИОНАЛЬНЫЕ";; esac
        printf "${C_YELLOW}--- %s ---${C_NC}\n" "$title"
        show_best_category "$c" 3 | while IFS='|' read -r id cat name ms st; do printf "  %-24s %4sms\n" "$name" "$ms"; done
    done
    pause
}
select_slot() {
    slot="$1"; clear_screen
    printf "${C_BLUE}=== Выбор DNS для слота %s ===${C_NC}\n\n" "$slot"
    n=1
    while IFS='|' read -r id cat prof name url region status; do
        case "$id" in ''|\#*) continue;; esac
        printf "%3d) %-24s [%s]\n" "$n" "$name" "$cat"
        n=$((n+1))
    done < "$DNS_CATALOG"
    printf "\n99) Очистить   Enter) Назад\nВыбор: "; safe_read c
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
        printf "${C_BLUE}=== ⚙ Слоты DNS (6+2) ===${C_NC}\n\n"
        for s in 1 2 3 4 5 6; do eval "v=\${SLOT_$s}"; eval "p=\${PORT_$s}"; printf "%s) %-24s порт=%s\n" "$s" "$(dns_name "$v")" "${p:-авто}"; done
        printf "7) RU  %-24s порт=%s\n" "$(dns_name "$SLOT_RU")" "${PORT_RU:-авто}"
        printf "8) RU2 %-24s порт=%s\n\n" "$(dns_name "$SLOT_RU_2")" "${PORT_RU_2:-авто}"
        printf "Enter) Назад\nВыбор: "; safe_read c
        [ -z "$c" ] && return
        case "$c" in 1|2|3|4|5|6) select_slot "$c";; 7) select_slot RU;; 8) select_slot RU_2;; esac
    done
}
menu_bootstrap() {
    clear_screen
    printf "${C_BLUE}=== 🎯 Bootstrap DNS ===${C_NC}\n\n"
    printf "Сейчас: %s\n\n" "$BOOTSTRAP_DNS"
    printf "1) Независимые: Cloudflare + Yandex + AdGuard + Quad9 + Google\n"
    printf "2) Cloudflare + Yandex\n"
    printf "3) Только Cloudflare\n"
    printf "4) Ввести свои IPv4 через запятую\nEnter) Назад\nВыбор: "; safe_read c
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
        printf "${C_BLUE}=== 🔧 Дополнительные настройки ===${C_NC}\n\n"
        printf "1) Балансировка dnsmasq: %s\n" "$BALANCER_ENABLED"
        printf "2) TLD split (.ru/.su/.рф): %s\n" "$TLD_RU_ENABLED"
        printf "3) QUIC: %s\n" "$BLOCK_QUIC"
        printf "4) MTU fix: %s\n" "$MTU_FIX"
        printf "5) NTP IP fallback: %s\n" "$NTP_IP_FALLBACK"
        printf "6) Sysctl: %s\n" "$SYSCTL_TUNING"
        printf "7) Go/Tailscale/TG: %s\n" "$GO_OPTIMIZE"
        printf "8) IP-заглушки\nEnter) Назад\nВыбор: "; safe_read c
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
    printf "${C_BLUE}=== 📦 Установка недостающего ===${C_NC}\n\n"
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
    printf "${C_BLUE}=== 📋 Состояние и журнал ===${C_NC}\n\n"
    printf "Лог:\n"; tail -25 "$LOG_FILE" 2>/dev/null
    printf "\nТранзакции:\n"; tail -25 "$TX_LOG" 2>/dev/null
    pause
}

main_menu() {
    while :; do
        run_discovery
        clear_screen
        printf "${C_BLUE}╔══════════════════════════════════════════╗\n║             DNS Manager %s            ║\n╚══════════════════════════════════════════╝${C_NC}\n\n" "$VERSION"
        printf "OpenWrt %s | %s | %s | fw=%s\n" "$SYS_OWRT" "$SYS_TARGET" "$SYS_ARCH" "$SYS_FW"
        printf "IPv4=%s IPv6=%s | dnsmasq=%s | DoH=%s (наш %s / чужой %s / неизвестный %s)\n\n" "$IPV4_ROUTE" "$IPV6_ROUTE" "$DNSMASQ_RUN" "$DOH_TOTAL" "$DOH_OURS" "$DOH_FOREIGN" "$DOH_UNKNOWN"
        printf "1) 📊 Карта состояния\n"
        printf "2) 🔍 Тест всех DNS/DoH (%s)\n" "$(count_dns)"
        printf "3) ⭐ Лучшие DNS\n"
        printf "4) ⚙ Слоты DNS (6+2)\n"
        printf "5) 🎯 Bootstrap DNS\n"
        printf "6) 🕐 Время / NTP (IP-first)\n"
        printf "7) 🔧 Дополнительные настройки\n"
        printf "8) 📋 Состояние и журнал\n"
        printf "9) ⚡ Применить выбранное\n"
        printf "I) 📦 Установить недостающее\n"
        printf "R) 🔄 Удалить только изменения DNS Manager\n"
        printf "0) Выход\n\n"
        printf "Выбор: "; safe_read c
        case "$c" in
            1) show_map;;
            2) test_dns_catalog; show_tests;;
            3) show_best;;
            4) menu_slots;;
            5) menu_bootstrap;;
            6) menu_ntp;;
            7) menu_extras;;
            8) menu_status;;
            9) apply_settings;;
            I|i) menu_install;;
            R|r|К|к) rollback_ours;;
            0) rm -rf "$TMP_DIR"; exit 0;;
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
