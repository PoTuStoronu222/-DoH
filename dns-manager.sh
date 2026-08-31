#!/bin/sh
MANAGER_PATH="/usr/bin/dns-manager"
VERSION="1.5-HYBRID"
BASE_DIR="/etc/dns-manager"
CFG_DIR="$BASE_DIR/config"
STATE_DIR="/var/run/dns-manager"
LOG_FILE="/var/log/dns-manager.log"
TX_LOG="/var/log/dns-manager.tx"
CONFIG_FILE="$CFG_DIR/manager.conf"
DNS_CATALOG="$CFG_DIR/dns-catalog.conf"
NTP_CATALOG="$CFG_DIR/ntp-catalog.conf"
BOOTSTRAP_CATALOG="$CFG_DIR/bootstrap-catalog.conf"
BOGUS_CATALOG="$CFG_DIR/bogus-catalog.conf"
PREV_DNSMASQ="$CFG_DIR/dnsmasq-previous.conf"
PREV_SERVICES="$CFG_DIR/services-previous.conf"
OWNERSHIP="$STATE_DIR/ownership.conf"
TEST_RESULTS="$STATE_DIR/dns-test-results.conf"
TMP_DIR="$(mktemp -d /tmp/dnsmgr.XXXXXX 2>/dev/null || { d="/tmp/dnsmgr.$$"; mkdir -p "$d"; printf "%s" "$d"; })"
TX_ID="$(date +%Y%m%d-%H%M%S)-$$"
TX_DIR="$STATE_DIR/tx-$TX_ID"
TX_ACTIVE=0
TX_RESERVED_PORTS=""
TX_PRE_SLOTS=""
CORE_ONLY=0
trap 'rm -rf "$TMP_DIR"' EXIT INT TERM
C_RED='\033[1;31m'
C_GREEN='\033[1;32m'
C_YELLOW='\033[1;33m'
C_BLUE='\033[1;34m'
C_MAGENTA='\033[1;35m'
C_PINK='\033[1;35m'
C_CYAN='\033[1;36m'
C_WHITE='\033[1;37m'
C_BOLD='\033[1m'
C_NC='\033[0m'
C_TITLE='\033[1;33m'
C_SECTION='\033[1;37m'
log_msg() {
mkdir -p "$BASE_DIR" "$STATE_DIR" 2>/dev/null
printf '[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >> "$LOG_FILE" 2>/dev/null
}
log_tx() {
printf 'TX|%s|%s|%s|%s|%s|%s\n' "$TX_ID" "$(date +%s)" "$1" "$2" "$3" "$4" "$5" >> "$TX_LOG" 2>/dev/null
}
ok_msg() { log_msg "OK $*"; printf "${C_GREEN}[✓] %s${C_NC}\n" "$*"; }
info_msg() { log_msg "INFO $*"; printf "${C_CYAN}[ℹ] %s${C_NC}\n" "$*"; }
warn_msg() { log_msg "WARN $*"; printf "${C_YELLOW}[!] %s${C_NC}\n" "$*"; }
err_msg() { log_msg "ERROR $*"; printf "${C_RED}[✗] %s${C_NC}\n" "$*"; }
safe_read() { read -r "$@"; }
confirm_action() {
    _prompt="$1"
    printf "\n${C_WHITE}%s${C_NC}\n" "$_prompt"
    printf "  ${C_GREEN}[✓] Y / y  или  Н / н — Да, применить${C_NC}\n"
    printf "  ${C_RED}[✗] N / n  или  Т / т — Нет, назад${C_NC}\n"
    printf "  ${C_WHITE}[Enter] — отмена / назад${C_NC}\n"
    printf "${C_YELLOW}Выбор: ${C_NC}"
    safe_read _ans
    case "$_ans" in
        y|Y|н|Н|yes|YES|да|Да|ДА) return 0 ;;
        n|N|т|Т|no|NO|нет|Нет|НЕТ|"") return 1 ;;
        *) warn_msg "Неверный выбор. Используйте Y/Н — Да или N/Т — Нет."; return 1 ;;
    esac
}
pause() { printf "\n${C_WHITE}Нажмите Enter...${C_NC}"; safe_read _dummy; }
clear_screen() { command -v clear >/dev/null 2>&1 && clear || printf '\033[2J\033[H'; printf '\033[1;37m'; }
menu_header() {
clear_screen
printf "${C_TITLE}╔════════════════════════════════════════════════════╗${C_NC}\n"
printf "${C_TITLE}║ %-50s ║${C_NC}\n" "$1"
printf "${C_TITLE}╚════════════════════════════════════════════════════╝${C_NC}\n"
printf "${C_GREEN}✓${C_NC} работает  ${C_RED}✗${C_NC} ошибка/выключено  ${C_YELLOW}⚠${C_NC} внимание  ${C_PINK}↻${C_NC} изменение  ${C_CYAN}ℹ${C_NC} информация\n"
}
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
if [ ! -s "$DNS_CATALOG" ] || ! grep -q '^# # DNSCATVER=8.1-RU' "$DNS_CATALOG" 2>/dev/null; then
[ -s "$DNS_CATALOG" ] && cp -f "$DNS_CATALOG" "$DNS_CATALOG.previous" 2>/dev/null
cat > "$DNS_CATALOG" <<'EOF_DNS'
# DNSCATVER=8.1-RU
#! Список кандидатов. Работоспособность проверяется с роутера.
# FORMAT=ID|CATEGORY|PROFILE|NAME|URL|REGION|STATUS

cat > "$DNS_CATALOG" <<'EOF_DNS'
# DNSCATVER=8.1-RU
#! Список кандидатов. Работоспособность проверяется с роутера.
# FORMAT=ID|CATEGORY|PROFILE|NAME|URL|REGION|STATUS
# --- Обход блокировок / региональных ограничений / сервисы ---
mafioznik|bypass|geo+ai+services|Mafioznik DNS|https://dns.mafioznik.com/dns-query|ru/global|verified-current
mafioznik_xyz|bypass|geo+ai+services|Mafioznik DNS XYZ|https://dns.mafioznik.xyz/dns-query|ru/global|runtime-check
astracat|bypass|geo+ads+services|Astrakat DNS|https://dns.astrakat.ru/dns-query|ru/global|user-confirmed-current
astracat_1498|bypass|geo+ads+services|AstraCat DNS :1498|https://dns.astrakat.ru:1498/dns-query|ru/global|runtime-check
astracat_8443|bypass|geo+ads+services|AstraCat DNS :8443|https://dns.astrakat.ru:8443/dns-query|ru/global|runtime-check
malw_link|bypass|ip-block+geo|Malw.link|https://dns.malw.link/dns-query|ru/global|verified-current
xbox_dns|bypass|games+supercell|Xbox DNS|https://xbox-dns.ru/dns-query|ru/global|verified-current
nullsproxy|bypass|supercell-games|Null's Proxy DNS|https://dns.nullsproxy.com/dns-query|ru/global|verified-current
geohide|bypass|geo+services|GeoHide DNS|https://dns.geohide.ru:444/dns-query|ru/global|verified-current
geohide_8443|bypass|geo+services|GeoHide DNS :8443|https://dns.geohide.ru:8443/dns-query|ru/global|runtime-check
comss_ru|bypass|geo+ai+services|Comss DNS RU|https://dns.comss.ru/dns-query|ru/global|user-confirmed-current
comss_bypass|bypass|geo+ai+security|Comss.one|https://dns.comss.one/dns-query|ru/global|verified-published-current
comss_adblock_bypass|bypass|geo+ads+security|Comss.one Ad Filter|https://router.comss.one/dns-query|ru/global|verified-published-current
vppay|bypass|geo+services|VPPay DNS|https://dns.vppay.ru/dns-query|ru/global|user-confirmed-current
dynx|bypass|geo+youtube|DynX DNS|https://dns.dynx.pro/dns-query|global|review-runtime
paesa|bypass|geo+youtube|Paesa DNS|https://dns.paesa.es/dns-query|global|review-runtime
anon_no|bypass|privacy+geo|Anon.no DNS|https://dns.anon.no/dns-query|norway|review-runtime
bebas_unfiltered|bypass|uncensored|BebasDNS Unfiltered|https://dns.bebasid.com/unfiltered|id/global|source-listed
dns4all|bypass|uncensored|DNS4all|https://doh.dns4all.eu/dns-query|eu/global|source-listed
dns4eu_unfiltered|clean|unfiltered|DNS4EU Unfiltered|https://unfiltered.joindns4.eu/dns-query|eu|verified-published-current
shecan|bypass|geo+services|Shecan DNS|https://free.shecan.ir/dns-query|ir/global|runtime-check
# --- Региональные DNS ---
yandex_ru|regional|ru+su+rf|Yandex RU|https://common.dot.dns.yandex.net/dns-query|ru|verified-published-current
yandex_safe|regional|ru+su+rf|Yandex Safe|https://safe.dot.dns.yandex.net/dns-query|ru|runtime-check
yandex_family|regional|ru+su+rf|Yandex Family|https://family.dot.dns.yandex.net/dns-query|ru|runtime-check
# --- Чистые и публичные (Clean / Unfiltered) ---
cloudflare_clean|clean|unfiltered|Cloudflare|https://cloudflare-dns.com/dns-query|global|verified-published-current
google_clean|clean|unfiltered|Google Public DNS|https://dns.google/dns-query|global|verified-published-current
quad9_unfiltered|clean|unfiltered+dnssec|Quad9 Unsecured|https://dns10.quad9.net/dns-query|global|verified-published-current
adguard_unfiltered|clean|unfiltered|AdGuard Unfiltered|https://unfiltered.adguard-dns.com/dns-query|global|verified-published-current
controld_p0|clean|unfiltered|Control D Unfiltered|https://freedns.controld.com/p0|global|verified-published-current
controld_uncensored|clean|uncensored|Control D Uncensored|https://freedns.controld.com/uncensored|global|verified-published-current
he_public|clean|unfiltered+anycast|Hurricane Electric Public Recursor|https://ordns.he.net/dns-query|global|verified-published-current
18bit_cn|clean|unfiltered|18bit.cn|https://doh.18bit.cn/dns-query|asia|source-listed
aa_dns|clean|unfiltered|Andrews & Arnold|https://dns.aa.net.uk/dns-query|uk/eu|source-listed
aquilenet|clean|unfiltered+dnssec|Aquilenet DNS|https://dns.aquilenet.fr/dns-query|fr/eu|source-listed
belnet|clean|unfiltered|Belnet DNS|https://dns.belnet.be/dns-query|be/eu|source-listed
cynthia|clean|unfiltered|CynthiaLabs DNS|https://dns.cynthialabs.net/dns-query|global|source-listed
digitalsize|clean|unfiltered+privacy|DigitalSize DNS|https://dns.digitalsize.net/dns-query|de/eu|source-listed
doh_disconnect|clean|unfiltered|Disconnect DNS|https://doh.disconnect.app/dns-query|global|source-listed
dnshome|clean|unfiltered|DNSHome|https://dns.dnshome.de/dns-query|de/eu|source-listed
one_dns_pure|clean|unfiltered|OneDNS Pure|https://doh-pure.onedns.net/dns-query|asia|verified-published-current
dns_pub|clean|unfiltered|DNSPod Public DNS|https://dns.pub/dns-query|cn/global|source-listed
dns_fdn0|clean|unfiltered|FDN DNS 0|https://ns0.fdn.fr/dns-query|fr/eu|source-listed
dns_fdn1|clean|unfiltered|FDN DNS 1|https://ns1.fdn.fr/dns-query|fr/eu|source-listed
doh_lacontrevoie|clean|unfiltered|LaContreVoie DNS|https://doh.lacontrevoie.fr/dns-query|fr/eu|source-listed
cznic_odvr_doh|clean|unfiltered|CZ.NIC ODVR DoH|https://odvr.nic.cz/doh|cz/eu|verified-published-current
cznic_odvr_query|clean|unfiltered|CZ.NIC ODVR Query|https://odvr.nic.cz/dns-query|cz/eu|source-listed
doh_seby|clean|unfiltered|Seby DNS|https://doh.seby.io/dns-query|global|source-listed
dns_surfshark|clean|unfiltered|Surfshark DNS|https://dns.surfsharkdns.com/dns-query|global|source-listed
hostux|clean|unfiltered|Hostux DNS|https://dns.hostux.net/dns-query|global|source-listed
# --- Безопасность ---
cloudflare_security|security|malware|Cloudflare Security|https://security.cloudflare-dns.com/dns-query|global|verified-published-current
quad9_secure|security|malware+dnssec|Quad9 Secure|https://dns.quad9.net/dns-query|global|verified-published-current
quad9_ecs|security|malware+ecs|Quad9 Secure ECS|https://dns11.quad9.net/dns-query|global|verified-published-current
controld_p1|security|malware|Control D Malware|https://freedns.controld.com/p1|global|verified-published-current
opendns_standard|security|phishing+malware|OpenDNS Standard|https://doh.opendns.com/dns-query|global|verified-published-current
cleanbrowsing_security|security|phishing+malware|CleanBrowsing Security|https://doh.cleanbrowsing.org/doh/security-filter/|global|verified-published-current
dns4eu_protective|security|malware+phishing|DNS4EU Protective|https://protective.joindns4.eu/dns-query|eu|verified-published-current
cert_ee|security|malware+phishing|CERT-EE|https://dns.cert.ee/dns-query|estonia|verified-published-current
cira_protected|security|malware+phishing|CIRA Protected|https://protected.canadianshield.cira.ca/dns-query|canada|verified-published-current
one_dns_block|security|malware|OneDNS Block|https://doh.onedns.net/dns-query|asia|verified-published-current
hagezi_root|security|ads+tracking+malware+phishing|HaGeZi Root|https://root.hagezi.org/dns-query|germany|verified-published-current
hagezi_wurzn|security|ads+tracking+malware+phishing|HaGeZi Wurzn|https://wurzn.hagezi.org/dns-query|germany|verified-published-current
hagezi_juuri|security|ads+tracking+malware+phishing|HaGeZi Juuri|https://juuri.hagezi.org/dns-query|finland|verified-published-current
hagezi_ctif|security|threat-only|HaGeZi CTIF|https://ctif.hagezi.org/dns-query|germany|verified-published-current
openbld_ada|security|ads+tracking+malware+phishing|OpenBLD ADA|https://ada.openbld.net/dns-query|global|verified-published-current
openbld_ric|security|strict-filtering|OpenBLD RIC|https://ric.openbld.net/dns-query|global|verified-published-current
dnsforge_strict|security|strict-filtering|dnsforge Strict|https://hard.dnsforge.de/dns-query|germany|verified-published-current
dnsbunker|security|balanced-threat|DNSBUNKER Pro+TIF|https://dnsbunker.org/dns-query|germany|verified-published-current
nsec_arnor|security|malware+phishing|arnor.org|https://nsec.arnor.org/dns-query|global|source-listed
# --- Приватность ---
mullvad_clean|privacy|qname-minimization|Mullvad Clean|https://dns.mullvad.net/dns-query|global|verified-published-current
mullvad_adblock|adblock|ads+tracking|Mullvad Adblock|https://adblock.dns.mullvad.net/dns-query|global|verified-published-current
mullvad_base|security|ads+tracking+malware|Mullvad Base|https://base.dns.mullvad.net/dns-query|global|verified-published-current
mullvad_extended|security|ads+tracking+malware+social|Mullvad Extended|https://extended.dns.mullvad.net/dns-query|global|verified-published-current
nextdns_fast|privacy|unfiltered|NextDNS|https://dns.nextdns.io|global|verified-published-current
nextdns_anycast|privacy|anycast|NextDNS Anycast|https://anycast.dns.nextdns.io|global|verified-published-current
dns_sb|privacy|dnssec+no-logging|DNS.SB|https://doh.dns.sb/dns-query|global|verified-published-current
applied_privacy|privacy|privacy|Applied Privacy|https://doh.applied-privacy.net/query|europe|verified-published-current
cznic_odvr|security|dnssec+privacy|CZ.NIC ODVR|https://odvr.nic.cz/doh|czechia|verified-published-current
digitale_gesellschaft|privacy|privacy|Digitale Gesellschaft|https://dns.digitale-gesellschaft.ch/dns-query|switzerland|verified-published-current
cira_private|privacy|unfiltered|CIRA Private|https://private.canadianshield.cira.ca/dns-query|canada|verified-published-current
libredns_clean|privacy|privacy|LibreDNS|https://doh.libredns.gr/dns-query|greece/eu|verified-published-current
switch_ch|privacy|privacy|SWITCH DNS|https://dns.switch.ch/dns-query|switzerland|verified-published-current
wikimedia|privacy|anycast|Wikimedia DNS|https://wikimedia-dns.org/dns-query|global|verified-published-current
pumplex|privacy|no-ads+dnssec|PumpleX|https://dns.pumplex.com/dns-query|france|verified-published-current
dnsforge|privacy|privacy|dnsforge|https://dnsforge.de/dns-query|germany|verified-published-current
ffmuc|privacy|community|FFMUC|https://doh.ffmuc.net/dns-query|germany|verified-published-current
# --- Блокировка рекламы ---
adguard_default|adblock|ads+tracking+phishing|AdGuard DNS|https://dns.adguard-dns.com/dns-query|global|verified-published-current
controld_p2|adblock|ads+tracking|Control D Ads+Tracking|https://freedns.controld.com/p2|global|verified-published-current
dns4eu_noads|adblock|ads+malware|DNS4EU No Ads|https://noads.joindns4.eu/dns-query|eu|verified-published-current
libredns_ads|adblock|ads|LibreDNS Ads|https://doh.libredns.gr/ads|greece/eu|verified-published-current
dnsguard|adblock|ads+tracking+malware|DNSGuard|https://dns.dnsguard.pub/dns-query|global|verified-published-current
nwps_standard|adblock|ads+tracking+malware|NWPS.fi Standard|https://public.ns.nwps.fi/dns-query|finland|verified-published-current
oszx|adblock|ads|OSZX DNS|https://dns.oszx.co/dns-query|france|verified-published-current
angry_im|adblock|ads|Angry.im|https://doh.angry.im/dns-query|global|source-listed
dns_bebas_default|adblock|ads+malware+phishing|BebasDNS|https://dns.bebasid.com/dns-query|id/global|source-listed
blokada|adblock|privacy|Blokada DNS|https://dns.blokada.org/dns-query|global|source-listed
# --- Семейная защита ---
cloudflare_family|family|malware+adult|Cloudflare Family|https://family.cloudflare-dns.com/dns-query|global|verified-published-current
adguard_family|family|ads+tracking+adult|AdGuard Family|https://family.adguard-dns.com/dns-query|global|verified-published-current
mullvad_family|family|ads+tracking+malware+adult+gambling|Mullvad Family|https://family.dns.mullvad.net/dns-query|global|verified-published-current
mullvad_all|family|ads+tracking+malware+adult+gambling+social|Mullvad All|https://all.dns.mullvad.net/dns-query|global|verified-published-current
controld_p3|social|social|Control D Social|https://freedns.controld.com/p3|global|verified-published-current
controld_family|family|family|Control D Family|https://freedns.controld.com/family|global|verified-published-current
opendns_family|family|adult|OpenDNS FamilyShield|https://doh.familyshield.opendns.com/dns-query|global|verified-published-current
cleanbrowsing_adult|family|adult+malware|CleanBrowsing Adult|https://doh.cleanbrowsing.org/doh/adult-filter/|global|verified-published-current
cleanbrowsing_family|family|adult+family|CleanBrowsing Family|https://doh.cleanbrowsing.org/doh/family-filter/|global|verified-published-current
dns4eu_child|family|child+malware|DNS4EU Child|https://child.joindns4.eu/dns-query|eu|verified-published-current
dns4eu_child_noads|family|child+ads|DNS4EU Child No Ads|https://child-noads.joindns4.eu/dns-query|eu|verified-published-current
dns_for_family|family|adult|DNS for Family|https://dns-doh.dnsforfamily.com/dns-query|global|verified-published-current
cira_family|family|adult+malware|CIRA Family|https://family.canadianshield.cira.ca/dns-query|canada|verified-published-current
nwps_kids|family|kids+ads+malware|NWPS.fi Kids|https://kids.ns.nwps.fi/dns-query|finland|verified-published-current
iijjp|family|child-protection|IIJ.JP DNS|https://public.dns.iij.jp/dns-query|japan|verified-published-current
dnsforge_youth|family|youth-protection|dnsforge Youth Protection|https://clean.dnsforge.de/dns-query|germany|verified-published-current
EOF_DNS
fi
if [ ! -s "$NTP_CATALOG" ] || ! grep -q '^# NTPCATVER=6.6-FINAL-HYBRID' "$NTP_CATALOG" 2>/dev/null; then
[ -s "$NTP_CATALOG" ] && cp -f "$NTP_CATALOG" "$NTP_CATALOG.previous" 2>/dev/null
cat > "$NTP_CATALOG" <<'EOF_NTP'
# NTPCATVER=6.6-FINAL-HYBRID
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
if [ ! -s "$BOOTSTRAP_CATALOG" ] || ! grep -q '^# BOOTSTRAPCATVER=6.6-FIX13' "$BOOTSTRAP_CATALOG" 2>/dev/null; then
[ -s "$BOOTSTRAP_CATALOG" ] && cp -f "$BOOTSTRAP_CATALOG" "$BOOTSTRAP_CATALOG.previous" 2>/dev/null
cat > "$BOOTSTRAP_CATALOG" <<'EOF_BOOT'
# BOOTSTRAPCATVER=6.6-FINAL-HYBRID
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
if [ ! -s "$BOGUS_CATALOG" ] || ! grep -q '^# BOGUSCATVER=6.6-FIX13' "$BOGUS_CATALOG" 2>/dev/null; then
[ -s "$BOGUS_CATALOG" ] && cp -f "$BOGUS_CATALOG" "$BOGUS_CATALOG.previous" 2>/dev/null
cat > "$BOGUS_CATALOG" <<'EOF_BOGUS'
# BOGUSCATVER=6.6-FINAL-HYBRID
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
if [ -f "$STATE_DIR/catalog.version" ] && [ "$(cat "$STATE_DIR/catalog.version" 2>/dev/null)" != "$VERSION" ]; then
rm -f "$TEST_RESULTS"
fi
printf '%s\n' "$VERSION" > "$STATE_DIR/catalog.version" 2>/dev/null
}
load_config() {
_had_dns_profile=0
[ -f "$CONFIG_FILE" ] && grep -q '^DNS_PROFILE=' "$CONFIG_FILE" 2>/dev/null && _had_dns_profile=1
[ -f "$CONFIG_FILE" ] && . "$CONFIG_FILE" 2>/dev/null
: "${SLOT_1:=}"; : "${SLOT_2:=}"; : "${SLOT_3:=}"; : "${SLOT_4:=}"; : "${SLOT_5:=}"; : "${SLOT_6:=}"
: "${SLOT_RU:=}"; : "${SLOT_RU_2:=}"
: "${PORT_1:=}"; : "${PORT_2:=}"; : "${PORT_3:=}"; : "${PORT_4:=}"; : "${PORT_5:=}"; : "${PORT_6:=}"
: "${PORT_RU:=}"; : "${PORT_RU_2:=}"
: "${BOOTSTRAP_DNS:=77.88.8.8,77.88.8.1,94.140.14.14,94.140.15.15}"
: "${TLD_RU_ENABLED:=1}"; : "${BLOCK_QUIC:=0}"; : "${MTU_FIX:=0}"; : "${FORCE_DOH:=0}"
: "${NTP_IP_FALLBACK:=1}"; : "${SYSCTL_TUNING:=0}"; : "${GO_OPTIMIZE:=0}"; : "${DNSMASQ_PERF:=0}"; : "${NTP_CLIENTS:=0}"; : "${CLIENT_FIXES:=0}"; : "${SYSCTL_EXTENDED:=0}"; : "${TAILSCALE_HOTPLUG:=0}"; : "${CRON_CLEANUP:=0}"
: "${BALANCER_ENABLED:=1}"; : "${NTP_PRESET:=cf_ip}"; : "${DNS_PROFILE:=hybrid}"
TLD_SPLIT="$TLD_RU_ENABLED"
if [ "$_had_dns_profile" = 0 ] && [ -z "$DNS_PROFILE" ]; then
DNS_PROFILE="hybrid"
fi
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
FORCE_DOH="$FORCE_DOH"
DNSMASQ_PERF="$DNSMASQ_PERF"
NTP_CLIENTS="$NTP_CLIENTS"
CLIENT_FIXES="$CLIENT_FIXES"
SYSCTL_EXTENDED="$SYSCTL_EXTENDED"
TAILSCALE_HOTPLUG="$TAILSCALE_HOTPLUG"
CRON_CLEANUP="$CRON_CLEANUP"
BALANCER_ENABLED="$BALANCER_ENABLED"
NTP_PRESET="$NTP_PRESET"
DNS_PROFILE="$DNS_PROFILE"
EOF_CFG
}
# ----- Discovery -----
disc_system() {
HAS_DNSMASQ="no"; command -v dnsmasq >/dev/null 2>&1 && HAS_DNSMASQ="yes"
SYS_FW="fw3"
if command -v fw4 >/dev/null 2>&1 || [ -x /sbin/fw4 ] || [ -x /usr/sbin/fw4 ] || [ -f /usr/share/fw4/main.uc ] || [ -f /usr/share/fw4/helpers.sh ]; then
SYS_FW="fw4"
fi
HAS_CURL="no"; command -v curl >/dev/null 2>&1 && HAS_CURL="yes"
HAS_DIG="no"; command -v dig >/dev/null 2>&1 && HAS_DIG="yes"
HAS_NTPD="no"; command -v ntpd >/dev/null 2>&1 && HAS_NTPD="yes"
HAS_NTPQ="no"; command -v ntpq >/dev/null 2>&1 && HAS_NTPQ="yes"
HAS_HDP="no"; command -v https-dns-proxy >/dev/null 2>&1 && HAS_HDP="yes"
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
DNSMASQ_RUN="no"; if /etc/init.d/dnsmasq status >/dev/null 2>&1; then DNSMASQ_RUN="yes"; elif pgrep -x dnsmasq >/dev/null 2>&1; then DNSMASQ_RUN="yes"; fi
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
HAS_ZAPRET="$OTHER_ZAPRET"
HAS_ZAPRET2="$OTHER_ZAPRET2"
HAS_NETSHIFT="$OTHER_NETSHIFT"
HAS_SPLIFY="$OTHER_SPLIFY"
HAS_MIXOMO="$OTHER_MIXOMO"
HAS_MAGI="$OTHER_MAGI"
HAS_HEV="$OTHER_HEV"
HAS_AWG="$OTHER_AWG"
HAS_TGGO="$OTHER_TGGO"
HAS_TGRUST="$OTHER_TGRS"
HAS_TGMT="$OTHER_TGMT"
HAS_BYEDPI="$OTHER_BYEDPI"
HAS_TAILSCALE="$OTHER_TAILSCALE"
}
disc_firewall() {
    QUIC_OURS=0
    QUIC_FOREIGN=0
    if uci show firewall 2>/dev/null | grep -q "name='Block_UDP_80'" ||        uci show firewall 2>/dev/null | grep -q "name='Block_UDP_443'"; then
        QUIC_OURS=1
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
ipx="$(nslookup "$host" "$bs" 2>/dev/null | awk '/^Address[ 0-9]*: / {print $NF}' | awk '/^[0-9]+(\.[0-9]+){3}$/ {print;exit}')"
else
ipx=""
fi
[ -n "$ipx" ] && { echo "$ipx"; return 0; }
done
return 1
}
resolve_host_fallback() {
host="$1"
ipx=""
if [ "$HAS_DIG" = yes ]; then
ipx="$(dig +short "$host" A +time=3 +tries=1 2>/dev/null | awk '/^[0-9]+(\.[0-9]+){3}$/{print;exit}')"
elif command -v nslookup >/dev/null 2>&1; then
ipx="$(nslookup "$host" 2>/dev/null | awk '/^Address[ 0-9]*: / {print $NF}' | awk '/^[0-9]+(\.[0-9]+){3}$/ {print;exit}')"
fi
[ -n "$ipx" ] && { echo "$ipx"; return 0; }
return 1
}
# ----- DNS tester -----
test_one_dns() {
id="$1"; url="$(normalize_url "$(dns_url "$id")")"; name="$(dns_name "$id")"; cat="$(dns_cat "$id")"
host="$(url_host "$url")"
port="$(url_port "$url")"
ipx="$(resolve_host "$host")"
[ -n "$ipx" ] || { printf '%s|%s|%s|-1|BOOTSTRAP_FAIL\n' "$id" "$cat" "$name" > "$TMP_DIR/t.$id"; return; }
q="$TMP_DIR/q.$id"; body="$TMP_DIR/body.$id"; hdr="$TMP_DIR/h.$id"
: > "$body"; : > "$hdr"
printf '\022\064\001\000\000\001\000\000\000\000\000\000\007example\003com\000\000\001\000\001' > "$q"
result="$(curl -sS -o "$body" -D "$hdr" -w '%{http_code}|%{time_total}|%{errormsg}' \
--connect-timeout 3 --max-time 6 --resolve "$host:$port:$ipx" \
-H 'Content-Type: application/dns-message' -H 'Accept: application/dns-message' \
--data-binary "@$q" "$url" 2>/dev/null)"
code="${result%%|*}"; rest="${result#*|}"; tim="${rest%%|*}"; err="${rest#*|}"
[ -z "$code" ] && code="000"
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
printf "${C_WHITE}Проверяю %s DNS/DoH параллельно...${C_NC} ${C_YELLOW}(может занять до 5 минут)${C_NC}\n" "$total"
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
awk -F'|' -v c="$cat" '$2==c && $5=="OK"{print}' "$TEST_RESULTS" 2>/dev/null | sort -t'|' -k4,4n | head -n "$limit"
}
# ----- Hybrid SmartDNS (6 DoH + Yandex RU) -----
HYBRID_PORT_1=5053
HYBRID_PORT_2=5054
HYBRID_PORT_3=5055
HYBRID_PORT_4=5056
HYBRID_PORT_5=5057
HYBRID_PORT_6=5058
HYBRID_PORT_RU=5059
hybrid_set_defaults() {
SLOT_1="mafioznik"
SLOT_2="comss_bypass"
SLOT_3="astracat"
SLOT_4="malw_link"
SLOT_5="comss_ru"
SLOT_6="vppay"
SLOT_RU="yandex_ru"
SLOT_RU_2=""
PORT_1="$HYBRID_PORT_1"
PORT_2="$HYBRID_PORT_2"
PORT_3="$HYBRID_PORT_3"
PORT_4="$HYBRID_PORT_4"
PORT_5="$HYBRID_PORT_5"
PORT_6="$HYBRID_PORT_6"
PORT_RU="$HYBRID_PORT_RU"
PORT_RU_2=""
DNS_PROFILE="hybrid"
TLD_RU_ENABLED=1
BALANCER_ENABLED=1
TLD_SPLIT=1
}
hybrid_desired_port() {
case "$1" in
1) printf '%s' "$HYBRID_PORT_1";;
2) printf '%s' "$HYBRID_PORT_2";;
3) printf '%s' "$HYBRID_PORT_3";;
4) printf '%s' "$HYBRID_PORT_4";;
5) printf '%s' "$HYBRID_PORT_5";;
6) printf '%s' "$HYBRID_PORT_6";;
RU) printf '%s' "$HYBRID_PORT_RU";;
RU_2) printf '%s' "5060";;
*) printf '';;
esac
}
hybrid_prepare_selection() {
# Явно выбранные пользователем слоты не перезаписываются.
# Значения по умолчанию используются только для пустого профиля.
if [ -z "$SLOT_1$SLOT_2$SLOT_3$SLOT_4$SLOT_5$SLOT_6$SLOT_RU" ]; then
hybrid_set_defaults
else
DNS_PROFILE="hybrid"
TLD_RU_ENABLED=1
BALANCER_ENABLED=1
PORT_1="$HYBRID_PORT_1"; PORT_2="$HYBRID_PORT_2"; PORT_3="$HYBRID_PORT_3"
PORT_4="$HYBRID_PORT_4"; PORT_5="$HYBRID_PORT_5"; PORT_6="$HYBRID_PORT_6"
[ -n "$SLOT_RU" ] && PORT_RU="$HYBRID_PORT_RU"
fi
# Основной профиль использует шесть общих DNS и отдельный российский DNS.

if [ "${HYBRID_AUTO_REPAIR:-0}" = 1 ] && [ -s "$TEST_RESULTS" ]; then
: > "$TMP_DIR/hybrid-used"
for _s in 1 2 3 4 5 6; do
eval "_id=\${SLOT_$_s}"
_ok="$(awk -F'|' -v id="$_id" '$1==id && $5=="OK"{print "yes";exit}' "$TEST_RESULTS" 2>/dev/null)"
if [ "$_ok" != yes ]; then
_replacement=""
while IFS='|' read -r _rid _rcat _rname _rms _rst; do
[ "$_rst" = OK ] || continue
[ "$_rcat" = bypass ] || continue
grep -qxF "$_rid" "$TMP_DIR/hybrid-used" 2>/dev/null && continue
_replacement="$_rid"
break
done <<EOF_HYB
$(sort -t'|' -k4,4n "$TEST_RESULTS" 2>/dev/null)
EOF_HYB
if [ -n "$_replacement" ]; then
eval "SLOT_$_s=\"$_replacement\""
printf "${C_YELLOW}⚠ %s не прошёл тест → резерв %s.${C_NC}\n" "$(dns_name "$_id")" "$(dns_name "$_replacement")"
_id="$_replacement"
else
warn_msg "Для Hybrid-слота $_s нет проверенного резерва."
eval "SLOT_$_s="
fi
fi
[ -n "$_id" ] && printf '%s\n' "$_id" >> "$TMP_DIR/hybrid-used"
done
_yok="$(awk -F'|' -v id="$SLOT_RU" '$1==id && $5=="OK"{print "yes";exit}' "$TEST_RESULTS" 2>/dev/null)"
if [ "$_yok" != yes ]; then
warn_msg "Yandex RU сейчас не прошёл тест. RU-маршрут не применяется автоматически."
SLOT_RU=""
fi
fi
PORT_1="$HYBRID_PORT_1"; PORT_2="$HYBRID_PORT_2"; PORT_3="$HYBRID_PORT_3"
PORT_4="$HYBRID_PORT_4"; PORT_5="$HYBRID_PORT_5"; PORT_6="$HYBRID_PORT_6"
[ -n "$SLOT_RU" ] && PORT_RU="$HYBRID_PORT_RU"
}
show_hybrid_profile() {
while :; do
clear_screen
printf "${C_WHITE}╔════════════════════════════════════════════════════╗\n"
printf "║        ⭐ Hybrid SmartDNS — 6 DoH + Yandex       ║\n"
printf "╚════════════════════════════════════════════════════╝${C_NC}\n"
printf "${C_CYAN}Общие DoH — параллельно:${C_NC}\n"
for _s in 1 2 3 4 5 6; do
eval "_id=\${SLOT_$_s}"
_p="$(hybrid_desired_port "$_s")"
[ -n "$_id" ] && printf "  ${C_YELLOW}%s${C_NC}  %-28s\n" "$_p" "$(dns_name "$_id")"
done
if [ -n "$SLOT_RU" ]; then
printf "\n${C_CYAN}RU-маршрут:${C_NC}\n"
printf "  ${C_YELLOW}%s${C_NC}  %-28s  .ru / .su / .рф\n" "$HYBRID_PORT_RU" "$(dns_name "$SLOT_RU")"
fi
printf "\n${C_WHITE}Режим общего DNS:${C_NC} allservers=1 → dnsmasq отправляет запросы всем 6 DoH и использует первый успешный ответ.\n"
printf "${C_WHITE}RU:${C_NC} домены .ru/.su/.рф идут только в отдельный российский DNS.\n"
printf "${C_YELLOW}[1]${C_NC} ⚡ Автоматически настроить Hybrid SmartDNS\n"
printf "${C_YELLOW}[2]${C_NC} 🧪 Проверить 6 DoH + Yandex\n"
printf "${C_YELLOW}[3]${C_NC} 🔧 Изменить слоты вручную\n"
printf "${C_GREEN}[Enter]${C_NC} Назад\nВыбор: "
safe_read _c
case "$_c" in
1)
if [ ! -s "$TEST_RESULTS" ]; then
test_dns_catalog
fi
HYBRID_AUTO_REPAIR=1
hybrid_prepare_selection
HYBRID_AUTO_REPAIR=0
save_config
printf "${C_GREEN}✓ Hybrid SmartDNS подготовлен.${C_NC}\n"
printf "${C_YELLOW}✓ 6 общих ролей: 5053–5058\n"
printf "✓ RU-роль: 5059\n"
printf "✓ allservers=1\n"
printf "✓ .ru/.su/.рф → Yandex${C_NC}\n"
if confirm_action "Применить Hybrid SmartDNS сейчас?"; then
apply_settings
fi
pause
;;
2)
test_dns_catalog
show_tests
;;
3) menu_slots;;
'') return;;
*) warn_msg "Неверный пункт."; pause;;
esac
done
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
servers="$(grep -v '^#' "$NTP_CATALOG" 2>/dev/null | grep "^${NTP_PRESET}|" | head -1 | cut -d'|' -f4)"
[ -n "$servers" ] || { warn_msg "NTP-профиль '$NTP_PRESET' не найден в каталоге."; return 1; }
[ -n "$(uci -q get system.ntp 2>/dev/null)" ] || uci -q set system.ntp=timeserver || return 1
for ipx in $servers; do
    _exists=0
    for _cur_ntp in $(uci -q get system.ntp.server 2>/dev/null); do
        [ "$_cur_ntp" = "$ipx" ] && _exists=1
    done
    [ "$_exists" = 1 ] || uci add_list system.ntp.server="$ipx" || return 1
done
uci set system.ntp.enabled='1' || return 1
uci set system.ntp.use_dhcp='0' || return 1
uci commit system || return 1
/etc/init.d/sysntpd restart >/dev/null 2>&1
record_own "ntp" "system.ntp.server" "$servers" "profile=$NTP_PRESET"
ok_msg "NTP: IP-профиль '$NTP_PRESET' добавлен без удаления существующих серверов."
log_tx "APPLY" "NTP" "ADD" "OK" "profile=$NTP_PRESET;servers=$servers"
}
menu_ntp() {
clear_screen
menu_header "🕐 ВРЕМЯ / NTP"
# Показываем ТЕКУЩИЕ серверы из UCI
_cur_ntp="$(uci -q get system.ntp.server 2>/dev/null)"
printf "${C_WHITE}Текущие NTP серверы:${C_NC}\n"
if [ -n "$_cur_ntp" ]; then
for _s in $_cur_ntp; do
printf "  ${C_GREEN}•${C_NC} %s\n" "$_s"
done
else
printf "  ${C_YELLOW}(не настроены)${C_NC}\n"
fi
printf "\n${C_WHITE}Выбранный профиль: ${C_YELLOW}%s${C_NC}\n" "$NTP_PRESET"
printf "  ${C_GREEN}[1]${C_NC} Cloudflare (IP, без DNS)\n"
printf "  ${C_BLUE}[2]${C_NC} NIST (несколько IP)\n"
printf "  ${C_YELLOW}[3]${C_NC} ВНИИФТРИ Москва\n"
printf "  ${C_CYAN}[4]${C_NC} Google (IP, leap-smear)\n"
printf "  ${C_GREEN}[Enter]${C_NC} Назад\n${C_YELLOW}Выбор:${C_NC} "; safe_read c
case "$c" in
1) NTP_PRESET="cf_ip";;
2) NTP_PRESET="nist_ip";;
3) NTP_PRESET="vniiftri_moscow";;
4) NTP_PRESET="google_ip";;
*) return;;
esac
save_config
apply_ntp_ip_fallback
pause
}
# ----- DNS ownership and ports -----
find_own_doh_by_url() {
awk -F'|' -v u="$(normalize_url "$1")" '$6==u && $3=="OURS"{print $1"|"$2"|"$6;exit}' "$DOH_INV"
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
port_reserved_tx() {
p="$1"
for rp in $TX_RESERVED_PORTS; do [ "$rp" = "$p" ] && return 0; done
return 1
}
claim_port_tx() {
p="$1"
port_reserved_tx "$p" && return 1
TX_RESERVED_PORTS="$TX_RESERVED_PORTS $p"
return 0
}
FREE_PORT_RESULT=""
free_port() {
FREE_PORT_RESULT=""
p=5053
while [ "$p" -le 5099 ]; do
port_reserved_tx "$p" && { p=$((p+1)); continue; }
port_used_anywhere "$p"; rc=$?
[ "$rc" = 2 ] && return 2
if [ "$rc" = 1 ]; then
claim_port_tx "$p" || { p=$((p+1)); continue; }
FREE_PORT_RESULT="$p"
return 0
fi
p=$((p+1))
done
return 1
}
clear_all_doh_for_apply() {
    printf "${C_PINK}↻ Все существующие DoH будут удалены и заменены выбранной схемой.${C_NC}\n"
    _i=0
    _removed=0
    while uci -q get "https-dns-proxy.@https-dns-proxy[$_i]" >/dev/null 2>&1; do
        _u="$(uci -q get "https-dns-proxy.@https-dns-proxy[$_i].resolver_url" 2>/dev/null)"
        [ -n "$_u" ] && printf "  ${C_PINK}↻ Удаляется DoH: %s${C_NC}\n" "$_u"
        uci -q delete "https-dns-proxy.@https-dns-proxy[$_i]" || return 1
        _removed=$((_removed+1))
    done
    uci commit https-dns-proxy || return 1
    : > "$DOH_INV"
    DOH_TOTAL=0
    DOH_OURS=0
    DOH_FOREIGN=0
    DOH_UNKNOWN=0
    printf "${C_GREEN}✓ Старых DoH удалено: %s. Будет создана только выбранная схема.${C_NC}\n" "$_removed"
}
record_own() { printf '%s|%s|%s|%s\n' "$1" "$2" "$3" "$4" >> "$OWNERSHIP"; }
ensure_doh_slot() {
slot="$1"; id="$2"; [ -n "$id" ] || return 0
url="$(normalize_url "$(dns_url "$id")")"; name="$(dns_name "$id")"
[ -n "$url" ] || return 1
local desired=""
[ "$DNS_PROFILE" = "hybrid" ] && desired="$(hybrid_desired_port "$slot")"
# 1. Проверяем, существует ли уже наш собственный экземпляр для этого URL
local existing_own
existing_own="$(find_own_doh_by_url "$url")"
if [ -n "$existing_own" ]; then
local sec_idx="$(printf '%s' "$existing_own" | cut -d'|' -f1)"
local current="$(printf '%s' "$existing_own" | cut -d'|' -f2)"
local target="$current"
if [ -n "$desired" ] && [ "$current" != "$desired" ]; then
# В Hybrid-режиме у ролей фиксированные порты. Если порт занят чужим, ищем безопасный фоллбэк.
port_used_anywhere "$desired"; rc=$?
if [ "$rc" = 2 ]; then
err_msg "Нельзя проверить порт $desired для $name."
return 1
elif [ "$rc" = 1 ]; then
target="$desired"
else
free_port || return 1
target="$FREE_PORT_RESULT"
fi
elif [ -z "$desired" ]; then
target="$current"
fi
if port_reserved_tx "$target" && [ "$target" != "$current" ]; then
free_port || return 1
target="$FREE_PORT_RESULT"
fi

if [ "$target" != "$current" ]; then
if [ -n "$sec_idx" ]; then
[ "$(uci -q get "https-dns-proxy.@https-dns-proxy[$sec_idx].dns_manager" 2>/dev/null)" = "1" ] || return 1
uci set "https-dns-proxy.@https-dns-proxy[$sec_idx].listen_port=$target" || return 1
else
err_msg "Не найден идентификатор секции DoH для $name"
return 1
fi
fi
eval "PORT_$slot=\"$target\""
printf "  ${C_GREEN}+ %s → 127.0.0.1:%s${C_NC}\n" "$name" "$target"
return 0
fi
# 2. Нашего экземпляра нет — проверяем, не занят ли URL сторонней/неизвестной секцией
local existing_foreign
existing_foreign="$(find_any_doh_by_url "$url")"
if [ -n "$existing_foreign" ]; then
local owner="$(printf '%s' "$existing_foreign" | cut -d'|' -f3)"
local p_old="$(printf '%s' "$existing_foreign" | cut -d'|' -f2)"
warn_msg "$name уже используется другой/неизвестной секцией (порт $p_old, владелец=$(owner_ru "$owner")). Создаю отдельный экземпляр DNS Manager."
fi
# 3. Определяем целевой порт для нового экземпляра
local target="$desired"
if [ -n "$target" ]; then
port_used_anywhere "$target"; rc=$?
[ "$rc" = 2 ] && { err_msg "Нельзя проверить порт $target."; return 1; }
[ "$rc" = 0 ] && target=""
fi
if [ -z "$target" ]; then
free_port || return 1
target="$FREE_PORT_RESULT"
else
if ! claim_port_tx "$target"; then

free_port || return 1
target="$FREE_PORT_RESULT"
fi
fi
# 4. Создаем новую секцию с нуля
local sec
sec="$(uci add https-dns-proxy https-dns-proxy 2>/dev/null)" || return 1
# Берем только первый IP-адрес на случай, если там несколько через пробел
local b_list="$(printf '%s' "$BOOTSTRAP_DNS" | tr ',' ' ')"
[ -z "$b_list" ] && b_list="1.1.1.1"
uci set "https-dns-proxy.$sec.bootstrap_dns=$b_list" || return 1
uci set "https-dns-proxy.$sec.listen_port=$target" || return 1
uci set "https-dns-proxy.$sec.resolver_url=$url" || return 1
uci set "https-dns-proxy.$sec.request_timeout=2" || return 1
uci set "https-dns-proxy.$sec.dns_manager=1" || return 1
record_own "doh" "$target" "$url" "slot=$slot;name=$name"
eval "PORT_$slot=\"$target\""
printf "  ${C_GREEN}+ %s → 127.0.0.1:%s${C_NC}\n" "$name" "$target"
}
repair_duplicate_own_doh_ports() {
[ -s "$DOH_INV" ] || return 0
dup_ports="$TMP_DIR/dup-own-ports"
awk -F'|' '$3=="OURS" && $2!=""{cnt[$2]++} END{for(p in cnt) if(cnt[p]>1) print p}' "$DOH_INV" > "$dup_ports"
[ -s "$dup_ports" ] || return 0
while IFS= read -r p; do
first=1
while IFS='|' read -r idx url; do
if [ "$first" -eq 1 ]; then
first=0
claim_port_tx "$p" || return 1
continue
fi
oldp="$p"
free_port || return 1
newp="$FREE_PORT_RESULT"
uci set "https-dns-proxy.@https-dns-proxy[$idx].listen_port=$newp" || return 1
record_own "doh" "$newp" "$url" "repair_duplicate_port=$oldp;section=$idx"
log_tx "PLAN" "doh.duplicate.$idx" "MOVE" "OK" "from=$oldp;to=$newp;url=$url"
printf "  ${C_YELLOW}↻ Исправлен дубликат порта %s для %s → %s (${C_GREEN}успешно${C_NC})\n" "$oldp" "$(dns_name "$url")" "$newp"
done <<EOF_DUP
$(awk -F'|' -v p="$p" '$3=="OURS" && $2==p{print $1"|"$6}' "$DOH_INV")
EOF_DUP
done < "$dup_ports"
}
reconcile_selected_own_doh() {
    # Оставляем выбранные собственные DoH и удаляем только устаревшие собственные секции.
    _keep="$TMP_DIR/keep-own-doh"
    : > "$_keep"
    for s in 1 2 3 4 5 6 RU RU_2; do
        eval "_id=\${SLOT_$s}"
        [ -n "$_id" ] || continue
        _u="$(normalize_url "$(dns_url "$_id")")"
        [ -n "$_u" ] && printf '%s\n' "$_u" >> "$_keep"
    done
    sort -u "$_keep" -o "$_keep" 2>/dev/null || true
    i=0
    while uci -q get "https-dns-proxy.@https-dns-proxy[$i]" >/dev/null 2>&1; do
        _m="$(uci -q get "https-dns-proxy.@https-dns-proxy[$i].dns_manager" 2>/dev/null)"
        if [ "$_m" = 1 ]; then
            _u="$(normalize_url "$(uci -q get "https-dns-proxy.@https-dns-proxy[$i].resolver_url" 2>/dev/null)")"
            if [ -z "$_u" ] || ! grep -qxF "$_u" "$_keep" 2>/dev/null; then
                printf "${C_PINK}↻ Удаляется устаревшая собственная DoH-секция: %s${C_NC}\n" "${_u:-без URL}"
                uci -q delete "https-dns-proxy.@https-dns-proxy[$i]" || return 1
                continue
            fi
        fi
        i=$((i+1))
    done
    return 0
}
validate_selected_slots() {
    _urls="$TMP_DIR/selected-urls"
    _ports="$TMP_DIR/selected-ports"
    : > "$_urls"; : > "$_ports"
    for s in 1 2 3 4 5 6 RU RU_2; do
        eval "_id=\${SLOT_$s}"
        [ -n "$_id" ] || continue
        _u="$(normalize_url "$(dns_url "$_id")")"
        [ -n "$_u" ] || { err_msg "Слот $s содержит DNS без URL."; return 1; }
        if grep -qxF "$_u" "$_urls" 2>/dev/null; then
            err_msg "Один и тот же адрес DoH-сервера выбран несколько раз: $(dns_name "$_id")."
            return 1
        fi
        printf '%s\n' "$_u" >> "$_urls"
    done
    return 0
}
get_dnsmasq_section() {
# В первую очередь используется dnsmasq, привязанный к LAN.
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
    # Сохраняем прежние upstream и связанные параметры для функции «удалить изменения DNS Manager».
    [ -s "$PREV_DNSMASQ" ] || {
  {
    printf 'SERVER\n'
    uci -q get "dhcp.$sec.server" 2>/dev/null | tr ' ' '\n'
    printf 'ALLSERVERS=%s\n' "$(uci -q get "dhcp.$sec.allservers" 2>/dev/null)"
    printf 'STRICTORDER=%s\n' "$(uci -q get "dhcp.$sec.strictorder" 2>/dev/null)"
    printf 'NORESOLV=%s\n' "$(uci -q get "dhcp.$sec.noresolv" 2>/dev/null)"
    printf 'SECTION=%s\n' "$sec"
  } > "$PREV_DNSMASQ" 2>/dev/null || true
}

    while uci -q delete "dhcp.$sec.server" >/dev/null 2>&1; do :; done
    for s in 1 2 3 4 5 6; do
        eval "id=\${SLOT_$s}"; eval "p=\${PORT_$s}"
        [ -n "$id" ] && [ -n "$p" ] || continue
        val="127.0.0.1#$p"
        uci add_list "dhcp.$sec.server=$val" || return 1
        record_own "dnsmasq" "server" "$val" "section=$sec"
    done
    if [ "$TLD_RU_ENABLED" = 1 ] && [ -n "$SLOT_RU" ] && [ -n "$PORT_RU" ]; then
        for t in /ru /su /xn--p1ai; do
            val="$t/127.0.0.1#$PORT_RU"
            uci add_list "dhcp.$sec.server=$val" || return 1
            record_own "dnsmasq" "server" "$val" "section=$sec"
        done
    fi
    if [ "$TLD_RU_ENABLED" = 1 ] && [ -n "$SLOT_RU_2" ] && [ -n "$PORT_RU_2" ]; then
        for t in /ru /su /xn--p1ai; do
            val="$t/127.0.0.1#$PORT_RU_2"
            uci add_list "dhcp.$sec.server=$val" || return 1
            record_own "dnsmasq" "server" "$val" "section=$sec"
        done
    fi
    if ! exact_list_has "dhcp.$sec.confdir" /etc/dnsmasq.d; then
        uci add_list "dhcp.$sec.confdir=/etc/dnsmasq.d" || return 1
        record_own "dnsmasq" "confdir" /etc/dnsmasq.d "section=$sec"
    fi
    if [ "$BALANCER_ENABLED" = 1 ]; then
        uci set "dhcp.$sec.allservers=1" || return 1
        uci set "dhcp.$sec.strictorder=0" || return 1
    else
        uci -q delete "dhcp.$sec.allservers" || true
        uci -q delete "dhcp.$sec.strictorder" || true
    fi
    uci set "dhcp.$sec.noresolv=1" || return 1
    uci commit dhcp || return 1
}

apply_quic() {
    [ "$BLOCK_QUIC" = 1 ] || return 0

    for _rname in Block_UDP_80 Block_UDP_443; do
        while :; do
            _ridx="$(uci show firewall 2>/dev/null | grep "name='$_rname'" | head -n1 | cut -d. -f2 | cut -d= -f1)"
            [ -n "$_ridx" ] || break
            uci -q delete "firewall.$_ridx" || return 1
        done
    done

    uci add firewall rule >/dev/null 2>&1 || return 1
    uci set firewall.@rule[-1].name='Block_UDP_80' || return 1
    uci set firewall.@rule[-1].dns_manager='1' || return 1
    uci add_list firewall.@rule[-1].proto='udp' || return 1
    uci set firewall.@rule[-1].src='lan' || return 1
    uci set firewall.@rule[-1].dest='wan' || return 1
    uci set firewall.@rule[-1].dest_port='80' || return 1
    uci set firewall.@rule[-1].target='REJECT' || return 1

    uci add firewall rule >/dev/null 2>&1 || return 1
    uci set firewall.@rule[-1].name='Block_UDP_443' || return 1
    uci set firewall.@rule[-1].dns_manager='1' || return 1
    uci add_list firewall.@rule[-1].proto='udp' || return 1
    uci set firewall.@rule[-1].src='lan' || return 1
    uci set firewall.@rule[-1].dest='wan' || return 1
    uci set firewall.@rule[-1].dest_port='443' || return 1
    uci set firewall.@rule[-1].target='REJECT' || return 1

    uci commit firewall || return 1
    record_own "firewall" "name" "Block_UDP_80" "created"
    record_own "firewall" "name" "Block_UDP_443" "created"
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
warn_msg "Не меняю $key: найдено стороннее значение ($foreign). Проверьте конфигурацию sysctl для этого параметра."
continue
fi
grep -q "^${key}=${val}$" "$f" 2>/dev/null || printf '%s\n' "$p" >> "$f"
sysctl -w "$p" >/dev/null 2>&1 || warn_msg "Не удалось применить $p"
record_own "sysctl" "$key" "$val" "before=${before:-unknown}"
done
}
remove_sysctl_base() {
    f="/etc/sysctl.d/90-dns-manager.conf"
    sf="$STATE_DIR/sysctl-before.conf"
    [ -f "$f" ] || return 0
    for kv in net.ipv4.tcp_fastopen net.ipv4.tcp_fin_timeout net.core.somaxconn; do
        old="$(awk -F'|' -v k="$kv" '$1==k{print $2;exit}' "$sf" 2>/dev/null)"
        [ -n "$old" ] && [ "$old" != unknown ] && sysctl -w "$kv=$old" >/dev/null 2>&1 || true
    done
    rm -f "$f" "$sf"
}
remove_go_optimize() {
    for f in /etc/init.d/tg-ws-proxy-go /etc/init.d/tailscale; do
        bak="$f.dns-manager.bak"
        [ -f "$bak" ] || continue
        curh="$(file_hash "$f")"
        managedh="$(cat "$STATE_DIR/$(basename "$f").managed.sha256" 2>/dev/null)"
        if [ -n "$managedh" ] && [ -n "$curh" ] && [ "$curh" != "$managedh" ]; then
            warn_msg "Не восстанавливаю $f: файл изменён вручную после настройки."
            continue
        fi
        mv "$bak" "$f" 2>/dev/null || continue
        rm -f "$STATE_DIR/$(basename "$f").managed.sha256"
    done
}
reload_fw() {
    if [ "$SYS_FW" = fw4 ]; then
        /etc/init.d/firewall reload >/dev/null 2>&1 || /etc/init.d/firewall restart >/dev/null 2>&1
    else
        /etc/init.d/firewall restart >/dev/null 2>&1
    fi
}
apply_extras_now() {
    case "$1" in
        balance|tld)
            reconcile_dnsmasq || return 1
            /etc/init.d/dnsmasq restart >/dev/null 2>&1 || return 1
            ;;
        ntp)
            [ "$NTP_IP_FALLBACK" = 1 ] && apply_ntp_ip_fallback || true
            ;;
        quic)
            apply_quic_toggle || return 1
            ;;
        mtu)
            apply_mtu_toggle || return 1
            ;;
        sysctl)
            if [ "$SYSCTL_TUNING" = 1 ]; then apply_sysctl; else remove_sysctl_base; fi
            ;;
        go)
            if [ "$GO_OPTIMIZE" = 1 ]; then apply_go; else remove_go_optimize; fi
            ;;
        force)
            if [ "$FORCE_DOH" = 1 ]; then apply_dns_force; else remove_dns_force; fi
            reload_fw
            ;;
        ntp_clients)
            if [ "$NTP_CLIENTS" = 1 ]; then apply_ntp_clients; else remove_ntp_clients; fi
            /etc/init.d/dnsmasq restart >/dev/null 2>&1 || return 1
            reload_fw
            ;;
        dnsmasq_perf)
            if [ "$DNSMASQ_PERF" = 1 ]; then apply_dnsmasq_perf; else remove_dnsmasq_perf; fi
            /etc/init.d/dnsmasq restart >/dev/null 2>&1 || return 1
            ;;
        client_fixes)
            if [ "$CLIENT_FIXES" = 1 ]; then apply_client_fixes; else remove_client_fixes; fi
            /etc/init.d/dnsmasq restart >/dev/null 2>&1 || return 1
            ;;
        sysctl_ext)
            if [ "$SYSCTL_EXTENDED" = 1 ]; then apply_sysctl_extended; else remove_sysctl_extended; fi
            ;;
        ts_hotplug)
            if [ "$TAILSCALE_HOTPLUG" = 1 ]; then apply_tailscale_hotplug; else remove_tailscale_hotplug; fi
            ;;
        cron)
            if [ "$CRON_CLEANUP" = 1 ]; then cleanup_manager_cron; fi
            ;;
    esac
    run_discovery
    save_config
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

# ----- Дополнительные модули -----
apply_ntp_clients() {
    [ "${NTP_CLIENTS:-0}" = 1 ] || return 0
    sec="$(get_dnsmasq_section)"
    [ -n "$sec" ] || return 1
    _opt="42,$LAN_IP"
    _cur="$(uci -q get "dhcp.$sec.dhcp_option" 2>/dev/null)"
    if ! printf '%s\n' "$_cur" | tr ' ' '\n' | grep -qxF "$_opt"; then
        uci add_list "dhcp.$sec.dhcp_option=$_opt" || return 1
        record_own "dnsmasq" "dhcp_option" "$_opt" "section=$sec"
    fi
    uci -q delete firewall.dns_manager_ntp_client
    uci set firewall.dns_manager_ntp_client=redirect || return 1
    uci set firewall.dns_manager_ntp_client.name='DNS Manager: NTP клиентов в роутер' || return 1
    uci set firewall.dns_manager_ntp_client.src='lan' || return 1
    uci set firewall.dns_manager_ntp_client.proto='udp' || return 1
    uci set firewall.dns_manager_ntp_client.src_dport='123' || return 1
    uci set firewall.dns_manager_ntp_client.dest_ip="$LAN_IP" || return 1
    uci set firewall.dns_manager_ntp_client.dest_port='123' || return 1
    uci set firewall.dns_manager_ntp_client.target='DNAT' || return 1
    uci commit dhcp || return 1
    uci commit firewall || return 1
}
remove_ntp_clients() {
    sec="$(get_dnsmasq_section)"
    [ -n "$sec" ] && uci -q del_list "dhcp.$sec.dhcp_option=42,$LAN_IP"
    uci -q delete firewall.dns_manager_ntp_client
    uci commit dhcp >/dev/null 2>&1 || true
    uci commit firewall >/dev/null 2>&1 || true
}
apply_dnsmasq_perf() {
    [ "${DNSMASQ_PERF:-0}" = 1 ] || return 0
    sec="$(get_dnsmasq_section)"
    [ -n "$sec" ] || return 1
    _f="$STATE_DIR/dnsmasq-perf-before.conf"
    : > "$_f" || return 1
    for _k in cachesize dnsforwardmax max_cache_ttl boguspriv domainneeded quietdhcp filter_aaaa; do
        _v="$(uci -q get "dhcp.$sec.$_k" 2>/dev/null)"
        printf '%s|%s\n' "$_k" "$_v" >> "$_f"
    done
    uci set "dhcp.$sec.cachesize=1000" || return 1
    uci set "dhcp.$sec.dnsforwardmax=300" || return 1
    uci set "dhcp.$sec.max_cache_ttl=86400" || return 1
    uci set "dhcp.$sec.boguspriv=1" || return 1
    uci set "dhcp.$sec.domainneeded=1" || return 1
    uci set "dhcp.$sec.quietdhcp=1" || return 1
    if [ "$IPV6_ROUTE" != yes ]; then uci set "dhcp.$sec.filter_aaaa=1" || return 1; fi
    uci commit dhcp || return 1
}
remove_dnsmasq_perf() {
    sec="$(get_dnsmasq_section)"
    [ -n "$sec" ] || return 0
    _f="$STATE_DIR/dnsmasq-perf-before.conf"
    if [ -s "$_f" ]; then
        while IFS='|' read -r _k _v; do
            if [ -n "$_v" ]; then uci set "dhcp.$sec.$_k=$_v"; else uci -q delete "dhcp.$sec.$_k"; fi
        done < "$_f"
        uci commit dhcp >/dev/null 2>&1 || true
        rm -f "$_f"
    fi
}
apply_client_fixes() {
    [ "${CLIENT_FIXES:-0}" = 1 ] || return 0
    f="/etc/dnsmasq.d/91-dns-manager-client-fixes.conf"
    [ -f "$f" ] || printf '%s\n' '# DNS_MANAGER_MANAGED=1' > "$f" || return 1
    {
        printf '%s\n' '# DNS_MANAGER_CLIENT_FIXES=1'
        # Явные telemetry-домены: локальная NXDOMAIN-зона dnsmasq.
        printf '%s\n' 'local=/telemetry.mozilla.org/'
        printf '%s\n' 'local=/telemetry.microsoft.com/'
        printf '%s\n' 'local=/vortex.data.microsoft.com/'
        printf '%s\n' 'local=/settings-win.data.microsoft.com/'
        printf '%s\n' 'local=/metrics.android.com/'
        printf '%s\n' 'local=/metrics.samsung.com/'
        # Connectivity-check домены получают нормальный внешний DNS через Yandex, доступный в РФ.
        printf '%s\n' 'server=/clients3.google.com/77.88.8.8'
        printf '%s\n' 'server=/clients3.google.com/77.88.8.1'
        printf '%s\n' 'server=/connectivitycheck.gstatic.com/77.88.8.8'
        printf '%s\n' 'server=/connectivitycheck.gstatic.com/77.88.8.1'
        printf '%s\n' 'server=/connectivitycheck.android.com/77.88.8.8'
        printf '%s\n' 'server=/connectivitycheck.android.com/77.88.8.1'
        printf '%s\n' 'server=/connectivitycheck.samsung.com/77.88.8.8'
        printf '%s\n' 'server=/connectivitycheck.samsung.com/77.88.8.1'
        printf '%s\n' 'server=/connectivitycheck.platform.hicloud.com/77.88.8.8'
        printf '%s\n' 'server=/connectivitycheck.platform.hicloud.com/77.88.8.1'
    } > "$f.tmp" || return 1
    mv "$f.tmp" "$f" || return 1
    record_own "file" "$f" "managed" "client-fixes"
}

remove_client_fixes() {
    f="/etc/dnsmasq.d/91-dns-manager-client-fixes.conf"
    if grep -q '^# DNS_MANAGER_MANAGED=1$' "$f" 2>/dev/null; then rm -f "$f"; /etc/init.d/dnsmasq restart >/dev/null 2>&1 || true; fi
}
apply_sysctl_extended() {
    [ "${SYSCTL_EXTENDED:-0}" = 1 ] || return 0
    f="/etc/sysctl.d/91-dns-manager-extended.conf"
    sf="$STATE_DIR/sysctl-extended-before.conf"
    : > "$sf" || return 1
    for p in "net.netfilter.nf_conntrack_max=65536" "net.ipv4.tcp_keepalive_time=600" "net.ipv4.tcp_keepalive_intvl=60" "net.ipv4.tcp_keepalive_probes=5" "net.core.rmem_max=4194304" "net.core.wmem_max=4194304" "net.core.rmem_default=262144" "net.core.wmem_default=262144"; do
        _k="${p%%=*}"; _v="${p#*=}"; _old="$(sysctl -n "$_k" 2>/dev/null)"; printf '%s|%s\n' "$_k" "${_old:-unknown}" >> "$sf"
        printf '%s\n' "$p" >> "$f.tmp"
    done
    mv "$f.tmp" "$f" || return 1
    command -v modprobe >/dev/null 2>&1 && modprobe nf_conntrack >/dev/null 2>&1 || true
    sysctl -p "$f" >/dev/null 2>&1 || true
    record_own "file" "$f" "managed" "extended-sysctl"
}
remove_sysctl_extended() {
    f="/etc/sysctl.d/91-dns-manager-extended.conf"; sf="$STATE_DIR/sysctl-extended-before.conf"
    if [ -s "$sf" ]; then
        while IFS='|' read -r _k _v; do
            [ -n "$_k" ] && [ "$_v" != unknown ] && sysctl -w "$_k=$_v" >/dev/null 2>&1 || true
        done < "$sf"
    fi
    rm -f "$f" "$sf"
}
apply_tailscale_hotplug() {
    [ "${TAILSCALE_HOTPLUG:-0}" = 1 ] || return 0
    [ -x /etc/init.d/tailscale ] || { warn_msg "Tailscale не установлен — hotplug не создаётся."; return 0; }
    f="/etc/hotplug.d/iface/99-dns-manager-tailscale"
    cat > "$f.tmp" <<'EOF_HOT'
#!/bin/sh
# DNS_MANAGER_TAILSCALE_HOTPLUG=1
[ "$ACTION" = ifup ] || exit 0
[ "$INTERFACE" = wan ] || exit 0
MARK="/var/run/dns-manager/tailscale-hotplug-window"
[ -s "$MARK" ] || exit 0
NOW="$(date +%s)"; START="$(cat "$MARK" 2>/dev/null)"
[ -n "$START" ] || exit 0
[ $((NOW-START)) -ge 0 ] 2>/dev/null || exit 0
[ $((NOW-START)) -le 600 ] 2>/dev/null || { rm -f "$MARK"; exit 0; }
[ -x /etc/init.d/tailscale ] && /etc/init.d/tailscale restart >/dev/null 2>&1 || true
rm -f "$MARK"
EOF_HOT
    mv "$f.tmp" "$f" || return 1
    chmod 755 "$f"
    date +%s > "$STATE_DIR/tailscale-hotplug-window" 2>/dev/null || true
    record_own "file" "$f" "created" "tailscale-hotplug"
}
remove_tailscale_hotplug() {
    f="/etc/hotplug.d/iface/99-dns-manager-tailscale"
    if grep -q '^# DNS_MANAGER_TAILSCALE_HOTPLUG=1$' "$f" 2>/dev/null; then rm -f "$f"; fi
    rm -f "$STATE_DIR/tailscale-hotplug-window"
}
cleanup_manager_cron() {
    [ "${CRON_CLEANUP:-0}" = 1 ] || return 0
    f="/etc/crontabs/root"
    [ -f "$f" ] || return 0
    cand="$TMP_DIR/cron-manager-candidates"
    grep -E '(DNS_MANAGER_CRON|dns-manager|dns_manager).*(dnsmasq|https-dns-proxy|tailscale).*(restart|reload)' "$f" > "$cand" 2>/dev/null || true
    if [ ! -s "$cand" ]; then
        info_msg "Старых помеченных cron-запусков DNS Manager не найдено. Пользовательский cron не изменён."
        return 0
    fi
    awk '!/(DNS_MANAGER_CRON|dns-manager|dns_manager).*(dnsmasq|https-dns-proxy|tailscale).*(restart|reload)/{print}' "$f" > "$f.tmp" || return 1
    mv "$f.tmp" "$f" || return 1
    /etc/init.d/cron reload >/dev/null 2>&1 || true
    ok_msg "Старые cron-запуски DNS Manager удалены. Остальные задания cron сохранены."
}


apply_dns_force() {
    [ "${FORCE_DOH:-0}" = 1 ] || return 0
    if [ "${FORCE_DNS:-}" = 1 ]; then
        warn_msg "Сторонний force_dns уже включён. Второй перехват DNS не создаётся."
        return 0
    fi
    uci -q delete firewall.dns_manager_dns_redirect
    uci set firewall.dns_manager_dns_redirect=redirect || return 1
    uci set firewall.dns_manager_dns_redirect.name='DNS Manager: перенаправление DNS' || return 1
    uci set firewall.dns_manager_dns_redirect.src='lan' || return 1
    uci set firewall.dns_manager_dns_redirect.proto='tcp udp' || return 1
    uci set firewall.dns_manager_dns_redirect.src_dport='53' || return 1
    uci set firewall.dns_manager_dns_redirect.dest_ip="$LAN_IP" || return 1
    uci set firewall.dns_manager_dns_redirect.dest_port='53' || return 1
    uci set firewall.dns_manager_dns_redirect.target='DNAT' || return 1
    uci -q delete firewall.dns_manager_dot_block
    uci set firewall.dns_manager_dot_block=rule || return 1
    uci set firewall.dns_manager_dot_block.name='DNS Manager: блокировка DoT' || return 1
    uci set firewall.dns_manager_dot_block.src='lan' || return 1
    uci set firewall.dns_manager_dot_block.dest='wan' || return 1
    uci set firewall.dns_manager_dot_block.proto='tcp udp' || return 1
    uci set firewall.dns_manager_dot_block.dest_port='853' || return 1
    uci set firewall.dns_manager_dot_block.target='REJECT' || return 1
    uci commit firewall || return 1
    record_own "firewall" "name" "dns_manager_dns_redirect" "created"
    record_own "firewall" "name" "dns_manager_dot_block" "created"
}
remove_dns_force() {
    uci -q delete firewall.dns_manager_dns_redirect
    uci -q delete firewall.dns_manager_dot_block
    uci commit firewall >/dev/null 2>&1 || true
}

apply_bogus() {
clear_screen
printf "${C_RED}=== IP-заглушки / bogus-nxdomain ===${C_NC}\n"
printf "Каталог содержит адреса для проверки. Применяйте только подтверждённые для вашего DNS-источника IP.\n"
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
url_host() {
    _u="$1"
    _h="${_u#https://}"
    _h="${_h%%/*}"
    case "$_h" in
        *:*) printf '%s' "${_h%%:*}" ;;
        *) printf '%s' "$_h" ;;
    esac
}
url_port() {
    _u="$1"
    _h="${_u#https://}"
    _h="${_h%%/*}"
    case "$_h" in
        *:*)
            _p="${_h##*:}"
            case "$_p" in
                ''|*[!0-9]*) printf '443' ;;
                *) printf '%s' "$_p" ;;
            esac
            ;;
        *) printf '443' ;;
    esac
}
verify_doh_endpoint() {
    _url="$(normalize_url "$1")"
    _name="$2"
    _host="$(url_host "$_url")"
    _port="$(url_port "$_url")"
    _ip="$(resolve_host "$_host")"
    [ -n "$_ip" ] || { err_msg "DoH «$_name»: не удалось определить адрес $_host."; return 1; }
    _suffix="$$-$(date +%s%N | cut -c1-8)"
    _q="$TMP_DIR/verify-q.$_suffix"; _b="$TMP_DIR/verify-b.$_suffix"; _h="$TMP_DIR/verify-h.$_suffix"
    printf '\022\064\001\000\000\001\000\000\000\000\000\000\007example\003com\000\000\001\000\001' > "$_q"
    _res="$(curl -sS -o "$_b" -D "$_h" -w '%{http_code}|%{errormsg}' --connect-timeout 3 --max-time 6 --resolve "$_host:$_port:$_ip" -H 'Content-Type: application/dns-message' -H 'Accept: application/dns-message' --data-binary "@$_q" "$_url" 2>/dev/null)"
    _code="${_res%%|*}"
    _bytes="$(wc -c < "$_b" 2>/dev/null | tr -d ' ')"; [ -n "$_bytes" ] || _bytes=0
    _ctype="$(awk -F': *' 'tolower($1)=="content-type"{print tolower($2)}' "$_h" 2>/dev/null | tail -n1 | tr -d '\r')"
    rm -f "$_q" "$_b" "$_h"
    [ "$_code" = 200 ] && [ "$_bytes" -ge 12 ] && printf '%s' "$_ctype" | grep -q 'application/dns-message' || {
        err_msg "DoH «$_name»: адрес сервера не подтвердил корректный ответ DNS-over-HTTPS (HTTPS $_code)."
        return 1
    }
    printf "${C_GREEN}✓ Адрес DoH-сервера подтверждён: %s${C_NC}\n" "$_name"
    return 0
}
verify_selected_doh() {
    for s in 1 2 3 4 5 6; do
        eval "_id=\${SLOT_$s}"; eval "_p=\${PORT_$s}"
        [ -n "$_id" ] || continue
        [ -n "$_p" ] || { err_msg "У слота $s не определён порт."; return 1; }
        _listen_ok=1
        if command -v ss >/dev/null 2>&1; then
            ss -lnt 2>/dev/null | grep -Eq "(^|[[:space:]])(127\.0\.0\.1|0\.0\.0\.0):${_p}([[:space:]]|$)" && _listen_ok=0
        elif command -v netstat >/dev/null 2>&1; then
            netstat -lnt 2>/dev/null | grep -Eq "(^|[[:space:]])(127\.0\.0\.1|0\.0\.0\.0):${_p}([[:space:]]|$)" && _listen_ok=0
        else
            _listen_ok=0
        fi
        [ "$_listen_ok" -eq 0 ] || { err_msg "Слот $s: порт 127.0.0.1:$_p не слушается."; return 1; }
        if command -v dig >/dev/null 2>&1; then
            dig +time=3 +tries=1 @127.0.0.1 -p "$_p" example.com A >/dev/null 2>&1 || { err_msg "Слот $s: локальный DNS через 127.0.0.1:$_p не отвечает."; return 1; }
        fi
        verify_doh_endpoint "$(dns_url "$_id")" "$(dns_name "$_id")" || return 1
    done
    if [ -n "$SLOT_RU" ]; then
        [ -n "$PORT_RU" ] || return 1
        if command -v dig >/dev/null 2>&1; then
            dig +time=3 +tries=1 @127.0.0.1 -p "$PORT_RU" yandex.ru A >/dev/null 2>&1 || { err_msg "RU: локальный DNS через 127.0.0.1:$PORT_RU не отвечает."; return 1; }
        fi
        verify_doh_endpoint "$(dns_url "$SLOT_RU")" "$(dns_name "$SLOT_RU")" || return 1
    fi
    if [ -n "$SLOT_RU_2" ]; then
        [ -n "$PORT_RU_2" ] || return 1
        if command -v dig >/dev/null 2>&1; then
            dig +time=3 +tries=1 @127.0.0.1 -p "$PORT_RU_2" example.com A >/dev/null 2>&1 || { err_msg "RU2: локальный DNS через 127.0.0.1:$PORT_RU_2 не отвечает."; return 1; }
        fi
        verify_doh_endpoint "$(dns_url "$SLOT_RU_2")" "$(dns_name "$SLOT_RU_2")" || return 1
    fi
    return 0
}
verify_after_apply() {

sleep 6
if /etc/init.d/dnsmasq status >/dev/null 2>&1; then DNSMASQ_RUN="yes"; elif pgrep -x dnsmasq >/dev/null 2>&1; then DNSMASQ_RUN="yes"; else DNSMASQ_RUN="no"; fi
[ "$DNSMASQ_RUN" = yes ] || { err_msg "dnsmasq не запущен после перезапуска и ожидания."; return 1; }
if [ "$DOH_TOTAL" -gt 0 ]; then
pgrep -f 'https-dns-proxy' >/dev/null 2>&1 || { err_msg "https-dns-proxy не запущен."; return 1; }

for p in "$PORT_1" "$PORT_2" "$PORT_3" "$PORT_4" "$PORT_5" "$PORT_6" "$PORT_RU" "$PORT_RU_2"; do
[ -n "$p" ] || continue

local resolved=0
for i in 1 2 3; do
if netstat -an 2>/dev/null | grep -qE ":$p([[:space:]]|$)" || ( [ -s "$LISTENERS" ] && grep -qE ":$p([[:space:]]|$)" "$LISTENERS" 2>/dev/null ); then
resolved=1
break
fi
sleep 1
done
[ "$resolved" -eq 1 ] || { err_msg "DoH порт $p не слушается. Проверьте конфигурацию https-dns-proxy и убедитесь, что порт не занят другим процессом."; return 1; }
done
fi

local dns_ok=0
for i in 1 2 3; do
if command -v nslookup >/dev/null 2>&1; then
if nslookup example.com 127.0.0.1 >/dev/null 2>&1; then dns_ok=1; break; fi
elif command -v dig >/dev/null 2>&1; then
if dig +time=2 +tries=1 @127.0.0.1 example.com A >/dev/null 2>&1; then dns_ok=1; break; fi
else
dns_ok=1; break # Если нет утилит тестирования, пропускаем эту проверку
fi
sleep 1
done
[ "$dns_ok" -eq 1 ] || { err_msg "Локальный DNS через 127.0.0.1 не отвечает."; return 1; }
verify_selected_doh || return 1
return 0
}
tx_snapshot_start() {
TX_DIR="$STATE_DIR/tx-$TX_ID"
rm -rf "$TX_DIR" 2>/dev/null
mkdir -p "$TX_DIR/files" || return 1
TX_ACTIVE=1
for f in /etc/config/dhcp /etc/config/https-dns-proxy /etc/config/firewall /etc/config/system /etc/sysctl.d/90-dns-manager.conf /etc/sysctl.d/91-dns-manager-extended.conf /etc/dnsmasq.d/90-dns-manager-bogus.conf /etc/dnsmasq.d/91-dns-manager-client-fixes.conf /etc/hotplug.d/iface/99-dns-manager-tailscale /etc/crontabs/root; do
key="$(printf '%s' "$f" | sed 's#^/##; s#[/ ]#_#g')"
if [ -f "$f" ]; then cp -p "$f" "$TX_DIR/files/$key"; file_hash "$f" > "$TX_DIR/$key.before"; printf '%s|%s|1\n' "$f" "$key" >> "$TX_DIR/manifest"; else printf '%s|%s|0\n' "$f" "$key" >> "$TX_DIR/manifest"; fi
done
: > "$TX_DIR/after.manifest"
log_tx "TX" "transaction" "SNAPSHOT" "OK" "dir=$TX_DIR"
}
tx_snapshot_after_apply() {
[ "$TX_ACTIVE" = 1 ] || return 0
: > "$TX_DIR/after.manifest"
while IFS='|' read -r f key existed; do
[ -n "$f" ] || continue
if [ -f "$f" ]; then
file_hash "$f" > "$TX_DIR/$key.after"
printf '%s|%s|1\n' "$f" "$key" >> "$TX_DIR/after.manifest"
else
printf '%s|%s|0\n' "$f" "$key" >> "$TX_DIR/after.manifest"
fi
done < "$TX_DIR/manifest"
}
tx_restore_on_failure() {
[ "$TX_ACTIVE" = 1 ] || return 0
warn_msg "Применение не прошло проверку. Выполняю автоматический откат этой транзакции."
if [ -f "$TX_DIR/manifest" ]; then
while IFS='|' read -r f key existed; do
[ -n "$f" ] || continue
cur="$(file_hash "$f")"
before="$(cat "$TX_DIR/$key.before" 2>/dev/null)"
after="$(cat "$TX_DIR/$key.after" 2>/dev/null)"
# Файл восстанавливается только если после применения его никто не менял.
if [ -n "$after" ] && [ "$cur" != "$after" ]; then
warn_msg "Не откатываю $f: обнаружено изменение после применения. Чужие изменения сохранены. Проверьте конфигурацию вручную."
continue
fi
if [ "$existed" = 1 ]; then
if [ -f "$TX_DIR/files/$key" ]; then
cp -p "$TX_DIR/files/$key" "$f" 2>/dev/null || warn_msg "Не удалось восстановить $f"
fi
else
rm -f "$f" 2>/dev/null
fi
done < "$TX_DIR/manifest"
fi
/etc/init.d/https-dns-proxy restart 2>/dev/null || true
/etc/init.d/dnsmasq restart 2>/dev/null || true
/etc/init.d/firewall reload 2>/dev/null || /etc/init.d/firewall restart 2>/dev/null || true
TX_ACTIVE=0
log_tx "ROLLBACK" "transaction" "RESTORE" "OK" "dir=$TX_DIR;guarded=yes"
}
tx_commit() {
TX_ACTIVE=0
printf '%s\n' "$(date +%s)" > "$TX_DIR/COMMITTED" 2>/dev/null
log_tx "TX" "transaction" "COMMIT" "OK" "dir=$TX_DIR"
}
# ----- Hybrid port reconciler -----
hybrid_reconcile_existing() {
[ "$DNS_PROFILE" = hybrid ] || return 0
# 1. Удаляем только дубликаты управляемых менеджером секций для каждого URL
for id in mafioznik comss_bypass astracat malw_link comss_ru vppay yandex_ru; do
local url="$(normalize_url "$(dns_url "$id")")"
[ -n "$url" ] || continue
local first_found=""
for sec in $(uci show https-dns-proxy 2>/dev/null | awk -F'[.=]' '/\..*=https-dns-proxy$/ {print $2}'); do
local m="$(uci -q get "https-dns-proxy.$sec.dns_manager" 2>/dev/null)"
local u="$(normalize_url "$(uci -q get "https-dns-proxy.$sec.resolver_url" 2>/dev/null)")"
if [ "$m" = "1" ] && [ "$u" = "$url" ]; then
if [ -z "$first_found" ]; then
first_found="$sec"
else
uci -q delete "https-dns-proxy.$sec"
fi
fi
done
done
# 2. Перемещаем менеджерские объекты, блокирующие другие выбранные роли, на временные свободные порты
for slot in 1 2 3 4 5 6 RU; do
eval "want=\${SLOT_$slot}"
[ -n "$want" ] || continue
local target="$(hybrid_desired_port "$slot")"
[ -n "$target" ] || continue
local want_url="$(normalize_url "$(dns_url "$want")")"
for sec in $(uci show https-dns-proxy 2>/dev/null | awk -F'[.=]' '/\..*=https-dns-proxy$/ {print $2}'); do
local m="$(uci -q get "https-dns-proxy.$sec.dns_manager" 2>/dev/null)"
local p="$(uci -q get "https-dns-proxy.$sec.listen_port" 2>/dev/null)"
local u="$(normalize_url "$(uci -q get "https-dns-proxy.$sec.resolver_url" 2>/dev/null)")"
if [ "$m" = "1" ] && [ "$p" = "$target" ] && [ "$u" != "$want_url" ]; then
free_port || return 1
local tmp="$FREE_PORT_RESULT"
[ "$tmp" != "$target" ] || { free_port || return 1; tmp="$FREE_PORT_RESULT"; }
uci set "https-dns-proxy.$sec.listen_port"="$tmp" || return 1
fi
done
done
uci commit https-dns-proxy 2>/dev/null || return 1
return 0
}
apply_settings() {
clear_screen
run_discovery
load_config
if [ "$DNS_PROFILE" = hybrid ]; then
hybrid_prepare_selection
fi
printf "${C_TITLE}=== ⚡ ПОДГОТОВКА И ПЛАН ПРИМЕНЕНИЯ ===${C_NC}\n"
printf "${C_WHITE}Будет настроено:${C_NC}\n"
if [ "$DNS_PROFILE" = hybrid ]; then
printf "  ${C_YELLOW}Hybrid SmartDNS — 6 DoH + Yandex RU${C_NC}\n"
printf "${C_WHITE}Обычные запросы — параллельно:${C_NC}\n"
for _s in 1 2 3 4 5 6; do
eval "_v=\${SLOT_$_s}"
[ -n "$_v" ] && printf "  127.0.0.1:%s  ←  %s\n" "$(hybrid_desired_port "$_s")" "$(dns_name "$_v")"
done
[ -n "$SLOT_RU" ] && printf "\n${C_WHITE}Российские домены:${C_NC}\n"
printf "127.0.0.1:%s  ←  %s  (.ru / .su / .рф)\n" "$HYBRID_PORT_RU" "$(dns_name "$SLOT_RU")"
printf "\nРежим: allservers=1\n"
printf "  Результат: первый успешный ответ из 6 обычных DoH\n"
else
printf "  ${C_YELLOW}Пользовательский DNS-профиль${C_NC}\n"
for _s in 1 2 3 4 5 6; do eval "_v=\${SLOT_$_s}"; [ -n "$_v" ] && printf "  Слот %s: %s\n" "$_s" "$(dns_name "$_v")"; done
[ -n "$SLOT_RU" ] && printf "  RU: %s\n" "$(dns_name "$SLOT_RU")"
fi
printf "\n${C_WHITE}Изменения DNS Core:${C_NC}\n"
[ "$TLD_RU_ENABLED" = 1 ] && printf "  ${C_GREEN}✓${C_NC} Раздельный DNS .ru/.su/.рф\n" || printf "  ${C_YELLOW}—${C_NC} Раздельный DNS не выбран\n"
[ "$BALANCER_ENABLED" = 1 ] && printf "  ${C_GREEN}✓${C_NC} Параллельный опрос DoH (allservers=1)\n" || printf "  ${C_YELLOW}—${C_NC} Параллельный режим не выбран\n"
[ "$NTP_IP_FALLBACK" = 1 ] && printf "  ${C_GREEN}✓${C_NC} NTP по IP без зависимости от DNS\n" || printf "  ${C_YELLOW}—${C_NC} NTP не изменяется\n"
if [ "$CORE_ONLY" != 1 ]; then
printf "\n${C_WHITE}Дополнительные модули:${C_NC}\n"
[ "$BLOCK_QUIC" = 1 ] && printf "  ${C_GREEN}✓${C_NC} Блокировка QUIC UDP/80 и UDP/443\n" || printf "  ${C_YELLOW}—${C_NC} QUIC не изменяется\n"
[ "$MTU_FIX" = 1 ] && printf "  ${C_GREEN}✓${C_NC} Исправление MTU\n" || printf "  ${C_YELLOW}—${C_NC} MTU не изменяется\n"
[ "$SYSCTL_TUNING" = 1 ] && printf "  ${C_GREEN}✓${C_NC} Оптимизация sysctl\n" || printf "  ${C_YELLOW}—${C_NC} sysctl не изменяется\n"
[ "$GO_OPTIMIZE" = 1 ] && printf "  ${C_GREEN}✓${C_NC} Оптимизация Go / Tailscale / TG WS\n" || printf "  ${C_YELLOW}—${C_NC} Go/Tailscale/TG WS не изменяется\n"
[ "${FORCE_DOH:-0}" = 1 ] && printf "  ${C_GREEN}✓${C_NC} Принудительный локальный DNS\n" || printf "  ${C_YELLOW}—${C_NC} Принудительный локальный DNS не изменяется\n"
[ "$NTP_CLIENTS" = 1 ] && printf "  ${C_GREEN}✓${C_NC} NTP для клиентов LAN (DHCP 42 + DNAT 123)\n" || printf "  ${C_YELLOW}—${C_NC} NTP клиентов не изменяется\n"
[ "$DNSMASQ_PERF" = 1 ] && printf "  ${C_GREEN}✓${C_NC} Тюнинг производительности dnsmasq\n" || printf "  ${C_YELLOW}—${C_NC} Тюнинг dnsmasq не изменяется\n"
[ "$CLIENT_FIXES" = 1 ] && printf "  ${C_GREEN}✓${C_NC} Клиентские DNS-фиксы\n" || printf "  ${C_YELLOW}—${C_NC} Клиентские фиксы не изменяются\n"
[ "$SYSCTL_EXTENDED" = 1 ] && printf "  ${C_GREEN}✓${C_NC} Расширенный sysctl + conntrack\n" || printf "  ${C_YELLOW}—${C_NC} Расширенный sysctl не изменяется\n"
[ "$TAILSCALE_HOTPLUG" = 1 ] && printf "  ${C_GREEN}✓${C_NC} Tailscale hotplug после NTP\n" || printf "  ${C_YELLOW}—${C_NC} Tailscale hotplug не изменяется\n"
[ "$CRON_CLEANUP" = 1 ] && printf "  ${C_GREEN}✓${C_NC} Чистка старых cron-задач DNS Manager\n" || printf "  ${C_YELLOW}—${C_NC} Cron не изменяется\n"
fi
printf "\n${C_WHITE}Текущее состояние до применения:${C_NC}\n"
printf "  dnsmasq: %b\n" "$(state_word "$DNSMASQ_RUN")"
printf "  DoH: %s (настройка %s / внешние %s / без определения %s)\n" "$DOH_TOTAL" "$DOH_OURS" "$DOH_FOREIGN" "$DOH_UNKNOWN"
if [ "$DOH_TOTAL" -gt 0 ]; then
printf "  ${C_PINK}↻ Найденные DoH после подтверждения будут заменены выбранной схемой DNS Manager.${C_NC}\n"
printf "  ${C_YELLOW}   До изменения создаётся снимок для автоматического отката при ошибке.${C_NC}\n"
fi
printf "\n${C_YELLOW}Только после подтверждения будет создан снимок и внесены изменения.${C_NC}\n"
printf "${C_YELLOW}ℹ Если желаемый порт занят чужим сервисом, слот уедет на ближайший свободный — итог будет показан после применения.${C_NC}\n"
validate_selected_slots || return 1
confirm_action "Применить показанную выше конфигурацию?" || return
TX_ID="$(date +%Y%m%d-%H%M%S)-$$"
TX_RESERVED_PORTS=""
tx_snapshot_start || { err_msg "Не удалось создать снимок транзакции. Изменения не выполняются."; return 1; }
log_tx "PLAN" "all" "APPLY" "START" "version=$VERSION"

if [ "$DOH_TOTAL" -gt 0 ] || [ "$DNS_PROFILE" = hybrid ]; then
/etc/init.d/https-dns-proxy stop >/dev/null 2>&1 || true
sleep 3
fi
clear_all_doh_for_apply || { err_msg "Не удалось удалить старый слой DoH."; tx_restore_on_failure; return 1; }
disc_listeners
disc_dns
if [ "$DNS_PROFILE" = hybrid ]; then
TX_RESERVED_PORTS=""
for s in 1 2 3 4 5 6; do
eval "v=\${SLOT_$s}"
ensure_doh_slot "$s" "$v" || { err_msg "Не удалось подготовить Hybrid-слот $s."; tx_restore_on_failure; return 1; }
done
ensure_doh_slot RU "$SLOT_RU" || { err_msg "Не удалось подготовить RU-слот 5059."; tx_restore_on_failure; return 1; }
else
for s in 1 2 3 4 5 6; do
eval "v=\${SLOT_$s}"
ensure_doh_slot "$s" "$v" || { err_msg "Не удалось подготовить слот $s."; tx_restore_on_failure; return 1; }
done
ensure_doh_slot RU "$SLOT_RU" || { tx_restore_on_failure; return 1; }
ensure_doh_slot RU_2 "$SLOT_RU_2" || { tx_restore_on_failure; return 1; }
fi

plan_dup="$(for s in 1 2 3 4 5 6 RU RU_2; do eval "p=\${PORT_$s}"; [ -n "$p" ] && printf '%s\n' "$p"; done | sort | uniq -d | head -n1)"
if [ -n "$plan_dup" ]; then
err_msg "План отменён: порт $plan_dup назначен нескольким DNS одновременно."; tx_restore_on_failure; return 1
fi
uci commit https-dns-proxy 2>/dev/null || { err_msg "Не удалось сохранить конфигурацию DoH. Проверьте права доступа к /etc/config/https-dns-proxy и убедитесь, что файл не поврежден."; tx_restore_on_failure; return 1; }
reconcile_dnsmasq || { err_msg "Не удалось настроить dnsmasq."; tx_restore_on_failure; return 1; }
if [ "$NTP_IP_FALLBACK" = 1 ]; then
apply_ntp_if_needed || { err_msg "Не удалось настроить NTP по IP."; tx_restore_on_failure; return 1; }
fi
if [ "$CORE_ONLY" != 1 ] && [ "${FORCE_DOH:-0}" = 1 ]; then
apply_dns_force || { err_msg "Не удалось применить принудительный DNS."; tx_restore_on_failure; return 1; }
fi
if [ "$CORE_ONLY" != 1 ] && [ "$BLOCK_QUIC" = 1 ]; then apply_quic || { err_msg "Не удалось применить блокировку QUIC."; tx_restore_on_failure; return 1; }; fi
if [ "$CORE_ONLY" != 1 ] && [ "$MTU_FIX" = 1 ]; then uci -q set firewall.@defaults[0].mtu_fix=1; uci commit firewall; fi
if [ "$CORE_ONLY" != 1 ] && [ "$SYSCTL_TUNING" = 1 ]; then apply_sysctl || { err_msg "Не удалось применить sysctl."; tx_restore_on_failure; return 1; }; fi
if [ "$CORE_ONLY" != 1 ] && [ "$GO_OPTIMIZE" = 1 ]; then apply_go || { err_msg "Не удалось применить оптимизацию Go."; tx_restore_on_failure; return 1; }; fi
if [ "$CORE_ONLY" != 1 ] && [ "$NTP_CLIENTS" = 1 ]; then apply_ntp_clients || { err_msg "Не удалось настроить NTP для клиентов."; tx_restore_on_failure; return 1; }; fi
if [ "$CORE_ONLY" != 1 ] && [ "$DNSMASQ_PERF" = 1 ]; then apply_dnsmasq_perf || { err_msg "Не удалось настроить производительность dnsmasq."; tx_restore_on_failure; return 1; }; fi
if [ "$CORE_ONLY" != 1 ] && [ "$CLIENT_FIXES" = 1 ]; then apply_client_fixes || { err_msg "Не удалось применить клиентские DNS-фиксы."; tx_restore_on_failure; return 1; }; fi
if [ "$CORE_ONLY" != 1 ] && [ "$SYSCTL_EXTENDED" = 1 ]; then apply_sysctl_extended || { err_msg "Не удалось применить расширенный sysctl."; tx_restore_on_failure; return 1; }; fi
if [ "$CORE_ONLY" != 1 ] && [ "$TAILSCALE_HOTPLUG" = 1 ]; then apply_tailscale_hotplug || { err_msg "Не удалось настроить автоматический запуск Tailscale."; tx_restore_on_failure; return 1; }; fi
if [ "$CORE_ONLY" != 1 ] && [ "$CRON_CLEANUP" = 1 ]; then cleanup_manager_cron || { err_msg "Не удалось очистить cron DNS Manager."; tx_restore_on_failure; return 1; }; fi
tx_snapshot_after_apply
sleep 1

uci revert https-dns-proxy 2>/dev/null
uci revert dhcp 2>/dev/null
uci revert firewall 2>/dev/null
uci revert system 2>/dev/null
/etc/init.d/https-dns-proxy restart 2>/dev/null || true
/etc/init.d/dnsmasq restart 2>/dev/null || true
if [ "$SYS_FW" = fw4 ]; then /etc/init.d/firewall reload 2>/dev/null || /etc/init.d/firewall restart 2>/dev/null; else /etc/init.d/firewall restart 2>/dev/null; fi
run_discovery
if verify_after_apply; then
tx_commit
save_config
printf "\n${C_WHITE}Фактические порты после применения:${C_NC}\n"
for _s in 1 2 3 4 5 6; do
    eval "_v=\${SLOT_$_s}"; eval "_p=\${PORT_$_s}"
    [ -n "$_v" ] && printf "  ${C_GREEN}✓${C_NC} 127.0.0.1:%s ← %s\n" "$_p" "$(dns_name "$_v")"
done
[ -n "$SLOT_RU" ] && printf "  ${C_GREEN}✓${C_NC} 127.0.0.1:%s ← %s (.ru/.su/.рф)\n" "$PORT_RU" "$(dns_name "$SLOT_RU")"
ok_msg "Готово. Выбранная конфигурация успешно применена и проверена."
log_tx "VERIFY" "all" "VERIFY" "OK" "dnsmasq=$DNSMASQ_RUN,doh=$DOH_TOTAL"
else
log_tx "VERIFY" "all" "VERIFY" "FAIL" "dnsmasq=$DNSMASQ_RUN,doh=$DOH_TOTAL"
tx_restore_on_failure
err_msg "Конфигурация не прошла проверку. Все изменения этой транзакции отменены, где это безопасно возможно."
fi
pause
}
rollback_ours() {
clear_screen
printf "${C_YELLOW}=== 🔄 Удаление только своих изменений ===${C_NC}\n"
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
# При ручном удалении своих изменений возвращаем DNS-upstream, существовавшие до установки менеджера.
if [ -s "$PREV_DNSMASQ" ]; then
    _prev_sec="$(sed -n 's/^SECTION=//p' "$PREV_DNSMASQ" | head -n1)"
    [ -n "$_prev_sec" ] || _prev_sec="$sec"
    while uci -q delete "dhcp.$_prev_sec.server" >/dev/null 2>&1; do :; done
    _in_servers=0
    while IFS= read -r _line; do
        case "$_line" in
            SERVER) _in_servers=1; continue ;;
            ALLSERVERS=*) _in_servers=0; _v="${_line#ALLSERVERS=}"; [ -n "$_v" ] && uci set "dhcp.$_prev_sec.allservers=$_v" || uci -q delete "dhcp.$_prev_sec.allservers"; continue ;;
            STRICTORDER=*) _v="${_line#STRICTORDER=}"; [ -n "$_v" ] && uci set "dhcp.$_prev_sec.strictorder=$_v" || uci -q delete "dhcp.$_prev_sec.strictorder"; continue ;;
            NORESOLV=*) _v="${_line#NORESOLV=}"; [ -n "$_v" ] && uci set "dhcp.$_prev_sec.noresolv=$_v" || uci -q delete "dhcp.$_prev_sec.noresolv"; continue ;;
            SECTION=*) continue ;;
        esac
        [ "$_in_servers" = 1 ] && [ -n "$_line" ] && uci add_list "dhcp.$_prev_sec.server=$_line" >/dev/null 2>&1 || true
    done < "$PREV_DNSMASQ"
    uci commit dhcp 2>/dev/null
    rm -f "$PREV_DNSMASQ" 2>/dev/null
fi
for r in Block_UDP_80 Block_UDP_443; do
while :; do idx="$(uci show firewall 2>/dev/null | grep "name='$r'" | head -n1 | cut -d. -f2 | cut -d= -f1)"; [ -n "$idx" ] || break; uci -q delete "firewall.$idx"; done
done
uci commit firewall 2>/dev/null
remove_ntp_clients >/dev/null 2>&1 || true
remove_client_fixes >/dev/null 2>&1 || true
remove_dnsmasq_perf >/dev/null 2>&1 || true
remove_sysctl_extended >/dev/null 2>&1 || true
remove_tailscale_hotplug >/dev/null 2>&1 || true
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
config_state_word() {
if [ "$1" = 1 ]; then
printf "${C_GREEN}ВКЛ • выбрано${C_NC}"
else
printf "${C_YELLOW}ВЫКЛ • не выбрано${C_NC}"
fi
}
show_map() {
clear_screen
printf "${C_WHITE}╔════════════════════════════════════════════════╗\n"
printf "║             📊 Карта состояния роутера         ║\n"
printf "╚════════════════════════════════════════════════╝${C_NC}\n"
printf "${C_SECTION}СИСТЕМА${C_NC}\n"
printf "  OpenWrt:        ${C_WHITE}%s${C_NC}\n" "$SYS_OWRT"
printf "  Платформа:      ${C_WHITE}%s${C_NC}\n" "$SYS_TARGET"
printf "  Архитектура:    ${C_WHITE}%s${C_NC}\n" "$SYS_ARCH"
printf "  Firewall:       ${C_WHITE}%s${C_NC}\n" "$SYS_FW"
printf "  LAN:            ${C_WHITE}%s${C_NC}\n" "$LAN_IP"
printf "  WAN:            ${C_WHITE}%s${C_NC}\n" "$WAN_PROTO"
printf "  IPv4:           %s\n" "$(state_word "$IPV4_ROUTE")"
printf "  IPv6:           %s\n" "$(state_word "$IPV6_ROUTE")"
printf "  curl:            %s\n" "$(state_word "$HAS_CURL")"
printf "  dig:             %s\n" "$(state_word "$HAS_DIG")"
printf "  ntpd:            %s\n" "$(state_word "$HAS_NTPD")"
printf "${C_SECTION}DNS${C_NC}\n"
printf "  dnsmasq:         %s\n" "$(state_word "$DNSMASQ_RUN")"
printf "  DoH всего:       ${C_WHITE}%s${C_NC}\n" "$DOH_TOTAL"
printf "  Наших:           ${C_WHITE}%s${C_NC}\n" "$DOH_OURS"
printf "  Чужих:           ${C_WHITE}%s${C_NC}\n" "$DOH_FOREIGN"
printf "  Неизвестных:     ${C_WHITE}%s${C_NC}\n" "$DOH_UNKNOWN"
printf "  SmartDNS:        %s\n" "$(state_word "$DNS_SMARTDNS")"
printf "  Unbound:         %s\n" "$(state_word "$DNS_UNBOUND")"
printf "  AdGuard Home:    %s\n" "$(state_word "$DNS_ADGUARD")"
printf "  MosDNS:          %s\n" "$(state_word "$DNS_MOSDNS")"
printf "  Sing-box:        %s\n" "$(state_word "$DNS_SINGBOX")"
printf "${C_SECTION}СТОРОННИЕ РЕШЕНИЯ${C_NC}\n"
printf "  Zapret:          %s\n" "$(state_word "$HAS_ZAPRET")"
printf "  Zapret2:         %s\n" "$(state_word "$HAS_ZAPRET2")"
printf "  NetShift:        %s\n" "$(state_word "$HAS_NETSHIFT")"
printf "  splify:          %s\n" "$(state_word "$HAS_SPLIFY")"
printf "  Mixomo:          %s\n" "$(state_word "$HAS_MIXOMO")"
printf "  MagiTrickle:     %s\n" "$(state_word "$HAS_MAGI")"
printf "  HevSocks5Tunnel: %s\n" "$(state_word "$HAS_HEV")"
printf "  AWG:             %s\n" "$(state_word "$HAS_AWG")"
printf "  TG-Go:           %s\n" "$(state_word "$HAS_TGGO")"
printf "  TG-Rust:         %s\n" "$(state_word "$HAS_TGRUST")"
printf "  TG-MTProto:      %s\n" "$(state_word "$HAS_TGMT")"
printf "  ByeDPI:          %s\n" "$(state_word "$HAS_BYEDPI")"
printf "  Tailscale:       %s\n" "$(state_word "$HAS_TAILSCALE")"
printf "${C_SECTION}FIREWALL${C_NC}\n"
printf "  QUIC нашего менеджера:      %s\n" "$(state_word "$QUIC_OURS")"
printf "  Чужое эквивалентное правило: %s\n" "$(state_word "$QUIC_FOREIGN")"
printf "  Активный nft:               %s\n" "$(state_word "$NFT_ACTIVE")"
printf "  Аппаратное ускорение:       %s\n" "$(state_word "$FLOW_OFFLOAD")"
printf "${C_SECTION}МОДУЛИ DNS MANAGER${C_NC}\n"
printf "  Профиль:                    ${C_YELLOW}%s${C_NC}\n" "$( [ "$DNS_PROFILE" = hybrid ] && printf '%s' 'Hybrid SmartDNS — 6 DoH + Yandex RU' || printf '%s' 'Пользовательский' )"
printf "  Балансировка DNS:           %s\n" "$(config_state_word "$BALANCER_ENABLED")"
printf "  Раздельный DNS (.ru/.su/.рф): %s\n" "$(config_state_word "$TLD_SPLIT")"
printf "  Блокировка QUIC:            %s\n" "$(module_state_word quic "$BLOCK_QUIC")"
printf "  Исправление MTU:             %s\n" "$(module_state_word mtu "$MTU_FIX")"
printf "  Резерв времени по IP:       %s\n" "$(config_state_word "$NTP_IP_FALLBACK")"
printf "  Оптимизация ядра:            %s\n" "$(module_state_word sysctl "$SYSCTL_TUNING")"
printf "  Go / Tailscale / TG WS:     %s\n" "$(module_state_word go "$GO_OPTIMIZE")"
printf "  NTP для клиентов:           %s\n" "$(module_state_word ntp_clients "$NTP_CLIENTS")"
printf "  Производительность dnsmasq: %s\n" "$(module_state_word dnsmasq_perf "$DNSMASQ_PERF")"
printf "  Клиентские DNS-фиксы:       %s\n" "$(module_state_word client_fixes "$CLIENT_FIXES")"
printf "  Расширенный sysctl:         %s\n" "$(module_state_word sysctl_ext "$SYSCTL_EXTENDED")"
printf "  Автоматический запуск Tailscale: %s\n" "$(module_state_word ts_hotplug "$TAILSCALE_HOTPLUG")"
printf "  Чистка cron:                %s\n" "$(module_state_word cron "$CRON_CLEANUP")"
printf "${C_GREEN}✓ Discovery завершён. Изменений в конфигурацию не внесено.${C_NC}\n"
pause
}
show_doh() {
clear_screen
printf "${C_WHITE}=== Найденные DoH ===${C_NC}\n"
[ -s "$DOH_INV" ] || { printf "${C_YELLOW}https-dns-proxy секции не найдены.${C_NC}\n"; pause; return; }
while IFS='|' read -r idx port owner addr running url; do
printf "${C_YELLOW}#%-2s${C_NC} ${C_WHITE}%s${C_NC} %s:%s | владелец: %s | состояние: %b\nURL: %s\n" "$idx" "$port" "$addr" "$port" "$(owner_ru "$owner")" "$(state_word "$running")" "$url"
done < "$DOH_INV"
pause
}
show_tests() {
clear_screen
printf "${C_WHITE}╔══════════════════════════════════════════════╗\n"
printf "║             🔍 Результаты DNS-теста          ║\n"
printf "╚══════════════════════════════════════════════╝${C_NC}\n"
[ -s "$TEST_RESULTS" ] || { printf "${C_YELLOW}Тест ещё не запускался.${C_NC}\n"; pause; return; }
okn="$(grep -c '|OK$' "$TEST_RESULTS" 2>/dev/null)"; total="$(count_dns)"; failn=$((total-okn))
printf "${C_GREEN}Работает: %s${C_NC} | ${C_YELLOW}Не прошли тест: %s${C_NC} | Всего: %s\n" "$okn" "$failn" "$total"
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
while :; do
clear_screen
printf "${C_WHITE}╔════════════════════════════════════════════════════╗\n"
printf "║             ⭐ Выбор DNS-режима                   ║\n"
printf "╚════════════════════════════════════════════════════╝${C_NC}\n"
printf "${C_YELLOW}[1]${C_NC} ⭐ Hybrid SmartDNS — 6 DoH + Yandex RU\n"
printf "${C_YELLOW}[2]${C_NC} Обход блокировок\n"
printf "${C_YELLOW}[3]${C_NC} Чистый быстрый DNS\n"
printf "${C_YELLOW}[4]${C_NC} Безопасность\n"
printf "${C_YELLOW}[5]${C_NC} Приватность\n"
printf "${C_YELLOW}[6]${C_NC} Блокировка рекламы\n"
printf "${C_YELLOW}[7]${C_NC} Семейный DNS\n"
printf "${C_YELLOW}[8]${C_NC} Социальные сети / сервисы\n"
printf "${C_YELLOW}[9]${C_NC} Все категории\n"
printf "${C_GREEN}[Enter]${C_NC} Назад\nВыбор: "
safe_read goal
[ -z "$goal" ] && return
case "$goal" in
1) show_hybrid_profile;;
2) menu_best_actions bypass "ОБХОД БЛОКИРОВОК";;
3) menu_best_actions clean "ЧИСТЫЙ БЫСТРЫЙ DNS";;
4) menu_best_actions security "БЕЗОПАСНОСТЬ";;
5) menu_best_actions privacy "ПРИВАТНОСТЬ";;
6) menu_best_actions adblock "БЛОКИРОВКА РЕКЛАМЫ";;
7) menu_best_actions family "СЕМЕЙНЫЙ DNS";;
8) menu_best_actions social "СОЦИАЛЬНЫЕ СЕТИ И СЕРВИСЫ";;
9) menu_best_actions all "ВСЕ КАТЕГОРИИ";;
*) warn_msg "Неверный пункт."; pause;;
esac
done
}
auto_fill_slots() {
_cat="$1"
if [ ! -s "$TEST_RESULTS" ]; then
info_msg "Тест DNS ещё не запускался. Запускаю тест..."
test_dns_catalog
fi
[ -s "$TEST_RESULTS" ] || { warn_msg "Не удалось получить результаты теста."; pause; return 1; }
_pool="$TMP_DIR/auto-slots"
: > "$_pool"
_src="$TMP_DIR/auto-candidates"
: > "$_src"
if [ "$_cat" = all ]; then
    awk -F'|' '$5=="OK" && $2!="regional"{print}' "$TEST_RESULTS" 2>/dev/null | sort -t'|' -k4,4n > "$_src"
else
    awk -F'|' -v c="$_cat" '$2==c && $5=="OK"{print}' "$TEST_RESULTS" 2>/dev/null | sort -t'|' -k4,4n > "$_src"
fi
[ -s "$_src" ] || { warn_msg "Нет успешно проверенных DNS в выбранной категории."; pause; return 1; }
_seen_urls="$TMP_DIR/auto-seen-urls"
: > "$_seen_urls"
i=1
while IFS='|' read -r _id _cat2 _name _ms _st; do
[ -n "$_id" ] || continue
_url="$(normalize_url "$(dns_url "$_id")")"
grep -qxF "$_url" "$_seen_urls" 2>/dev/null && continue
printf '%s\n' "$_url" >> "$_seen_urls"
printf '%s\n' "$_id|$_cat2|$_name|$_ms|$_st" >> "$_pool"
i=$((i+1))
[ "$i" -gt 6 ] && break
done < "$_src"
[ -s "$_pool" ] || { warn_msg "Не удалось сформировать набор DNS."; pause; return 1; }

# Для режима "все категории" в общий пул попадает максимум по одному быстрому DNS из каждой категории,
# после чего набор дополняется лучшими по скорости. Региональная категория в этот пул не входит.
if [ "$_cat" = all ]; then
    _src2="$TMP_DIR/auto-candidates-all"
    : > "$_src2"
    for _c in bypass clean security privacy adblock family social; do
        awk -F'|' -v c="$_c" '$2==c{print}' "$_src" 2>/dev/null | head -n1 >> "$_src2"
    done
    cat "$_src" 2>/dev/null >> "$_src2"
    : > "$_pool"
    _seen_urls="$TMP_DIR/auto-seen-urls"
    : > "$_seen_urls"
    i=1
    while IFS='|' read -r _id _cat2 _name _ms _st; do
        [ -n "$_id" ] || continue
        _url="$(dns_url "$_id")"
        grep -qxF "$_url" "$_seen_urls" 2>/dev/null && continue
        printf '%s\n' "$_url" >> "$_seen_urls"
        printf '%s\n' "$_id|$_cat2|$_name|$_ms|$_st" >> "$_pool"
        i=$((i+1))
        [ "$i" -gt 6 ] && break
    done < "$_src2"
fi

i=1
while IFS='|' read -r _id _cat2 _name _ms _st; do
[ -n "$_id" ] || continue
eval "SLOT_$i=\"$_id\""
i=$((i+1))
[ "$i" -gt 6 ] && break
done < "$_pool"

# RU-сегмент заполняется только региональными DNS. Yandex RU всегда имеет приоритет.
_ru1=""
_yandex_ok="$(awk -F'|' '$1=="yandex_ru" && $2=="regional" && $5=="OK"{print "yes";exit}' "$TEST_RESULTS" 2>/dev/null)"
if [ "$_yandex_ok" = yes ]; then
    SLOT_RU="yandex_ru"
    _ru1="yandex_ru"
else
    _ru1="$(awk -F'|' '$2=="regional" && $5=="OK"{print $1;exit}' "$TEST_RESULTS" 2>/dev/null)"
    if [ -n "$_ru1" ]; then
        SLOT_RU="$_ru1"
    else
        warn_msg "Нет проверенных региональных DNS. RU-сегмент оставлен без нового назначения."
    fi
fi
SLOT_RU_2="$(awk -F'|' -v skip="$_ru1" '$2=="regional" && $5=="OK" && $1!=skip{print $1;exit}' "$TEST_RESULTS" 2>/dev/null)"

save_config
printf "${C_GREEN}✓ Автоматически выбран набор DNS без дублей.${C_NC}\n"
for i in 1 2 3 4 5 6; do eval "_v=\${SLOT_$i}"; [ -n "$_v" ] && printf "  ${C_WHITE}Слот %s: %s${C_NC}\n" "$i" "$(dns_name "$_v")"; done
[ -n "$SLOT_RU" ] && printf "  ${C_WHITE}RU: %s${C_NC}\n" "$(dns_name "$SLOT_RU")"
[ -n "$SLOT_RU_2" ] && printf "  ${C_WHITE}RU2: %s${C_NC}\n" "$(dns_name "$SLOT_RU_2")"
return 0
}
menu_best_actions() {
goal="$1"; title="$2"
while :; do
clear_screen
printf "${C_WHITE}╔══════════════════════════════════════════════╗\n"
printf "║  ⭐ Настройка: %-31s ║\n" "$title"
printf "╚══════════════════════════════════════════════╝${C_NC}\n"
printf "${C_YELLOW}[1]${C_NC} ⚡ Автонастройка: подобрать и применить безопасно\n"
printf "${C_YELLOW}[2]${C_NC} ⭐ Показать лучшие варианты\n"
printf "${C_YELLOW}[3]${C_NC} ⚙ Выбрать DNS вручную\n"
printf "${C_GREEN}[Enter]${C_NC} Назад\nВыбор: "
safe_read a
case "$a" in
1)
if auto_fill_slots "$goal"; then
CORE_ONLY=1
apply_settings
CORE_ONLY=0
fi
;;
2)
clear_screen
printf "${C_YELLOW}ТОП-5 — %s${C_NC}\n" "$title"
show_best_category "$goal" 5 | while IFS='|' read -r _id _cat _name _ms _st; do
printf "  ${C_WHITE}%-34s${C_NC} %s мс\n" "$_name" "$_ms"
done
pause
;;
3) menu_slots; return;;
'') return;;
*) warn_msg "Неверный пункт."; pause;;
esac
done
}
select_slot() {
slot="$1"; clear_screen
printf "${C_TITLE}=== Выбор DNS для слота %s ===${C_NC}\n" "$slot"
n=1
while IFS='|' read -r id cat prof name url region status; do
case "$id" in ''|\#*) continue;; esac
printf "${C_YELLOW}[%3d]${C_NC} %-24s ${C_WHITE}[%s]${C_NC}\n" "$n" "$name" "$cat"
n=$((n+1))
done < "$DNS_CATALOG"
printf "\n${C_YELLOW}[99]${C_NC} Очистить   ${C_GREEN}[Enter]${C_NC} Назад\nВыбор: "; safe_read c
[ -z "$c" ] && return
if [ "$c" = "99" ]; then
eval "SLOT_$slot=''"
save_config
return
fi
row="$(grep -v '^#' "$DNS_CATALOG" | sed -n "${c}p")"
id="$(printf '%s' "$row" | cut -d'|' -f1)"
[ -n "$id" ] || return

eval "SLOT_$slot=\$id"
save_config
}
menu_slots() {
while :; do
clear_screen
printf "${C_TITLE}=== ⚙ DNS-профиль ===${C_NC}\n"
if [ "$DNS_PROFILE" = "hybrid" ]; then
printf "${C_YELLOW}Профиль: Hybrid SmartDNS — 6 DoH + Yandex RU${C_NC}\n"
printf "${C_WHITE}Роли 5053–5058: общий параллельный DNS | 5059: .ru/.su/.рф${C_NC}\n"
else
printf "${C_WHITE}Профиль: пользовательский${C_NC}\n"
fi
for s in 1 2 3 4 5 6; do
eval "v=\${SLOT_$s}"
eval "p=\${PORT_$s}"
[ "$DNS_PROFILE" = "hybrid" ] && p="$(hybrid_desired_port "$s")"
printf "${C_YELLOW}[%s]${C_NC} %-28s порт=${C_WHITE}%s${C_NC}\n" "$s" "$(dns_name "$v")" "${p:-авто}"
done
printf "${C_YELLOW}[7]${C_NC} RU  %-24s порт=${C_WHITE}%s${C_NC}\n" "$(dns_name "$SLOT_RU")" "${PORT_RU:-$HYBRID_PORT_RU}"
printf "${C_YELLOW}[8]${C_NC} RU2 %-24s порт=${C_WHITE}%s${C_NC}\n" "$(dns_name "$SLOT_RU_2")" "${PORT_RU_2:-авто}"
printf "${C_YELLOW}[9]${C_NC} ⚡ Автоподбор лучших 6 по выбранной категории\n"
printf "${C_YELLOW}[10]${C_NC} ⭐ Восстановить стандартный Hybrid SmartDNS\n"
printf "${C_GREEN}[Enter]${C_NC} Назад\nВыбор: "; safe_read c
[ -z "$c" ] && return
case "$c" in
1|2|3|4|5|6) select_slot "$c";;
7) select_slot RU;;
8) select_slot RU_2;;
9) show_best;;
10) hybrid_set_defaults; save_config; ok_msg "Стандартный Hybrid SmartDNS восстановлен: 5053–5058 + Yandex 5059."; pause;;
*) warn_msg "Неверный пункт."; pause;;
esac
done
}
menu_bootstrap() {
clear_screen
menu_header "🎯 BOOTSTRAP DNS"
printf "${C_WHITE}Сейчас:${C_NC} %s\n" "$BOOTSTRAP_DNS"
printf "  ${C_GREEN}[1]${C_NC} Независимые: Yandex + AdGuard + Cloudflare + Google + Quad9\n"
printf "  ${C_BLUE}[2]${C_NC} Cloudflare + Yandex\n"
printf "  ${C_CYAN}[3]${C_NC} Только Cloudflare\n"
printf "  ${C_YELLOW}[4]${C_NC} Ввести свои IPv4\n"
printf "  ${C_WHITE}[Enter]${C_NC} Назад  |  ${C_YELLOW}Выбор:${C_NC} "; safe_read c
case "$c" in
1) BOOTSTRAP_DNS="1.1.1.1,1.0.0.1,77.88.8.8,77.88.8.1,94.140.14.14,94.140.15.15,8.8.8.8,8.8.4.4,9.9.9.9,149.112.112.112";;
2) BOOTSTRAP_DNS="1.1.1.1,1.0.0.1,77.88.8.8,77.88.8.1";;
3) BOOTSTRAP_DNS="1.1.1.1,1.0.0.1";;
4) printf "IP: "; safe_read BOOTSTRAP_DNS;;
*) return;;
esac
save_config
if confirm_action "Применить выбранный Bootstrap сейчас?"; then
    apply_bootstrap_only
    pause
fi
}
menu_bogus() {
apply_bogus
}
module_state() {
key="$1"; val="$2"
[ "$val" = 1 ] || { printf 'ВЫКЛ'; return; }
case "$key" in
balance) printf 'ВКЛ • ожидает применения';;
tld) printf 'ВКЛ • ожидает применения';;
quic) [ "$QUIC_OURS" = 1 ] || [ "$QUIC_FOREIGN" = 1 ] && printf 'ВКЛ • правило найдено' || printf 'ВКЛ • ожидает применения';;
mtu) printf 'ВКЛ • ожидает применения';;
ntp) printf 'ВКЛ • IP-профиль настроен';;
sysctl) printf 'ВКЛ • ожидает применения';;
go) printf 'ВКЛ • ожидает применения';;
*) printf 'ВКЛ';;
esac
}

toggle_and_apply_dnsmasq() {
reconcile_dnsmasq >/dev/null 2>&1
/etc/init.d/dnsmasq restart >/dev/null 2>&1
save_config
}
remove_sysctl_base() {
f="/etc/sysctl.d/90-dns-manager.conf"
sf="$STATE_DIR/sysctl-before.conf"
[ -f "$f" ] || return 0
for kv in net.ipv4.tcp_fastopen net.ipv4.tcp_fin_timeout net.core.somaxconn; do
old="$(awk -F'|' -v k="$kv" '$1==k{print $2;exit}' "$sf" 2>/dev/null)"
[ -n "$old" ] && [ "$old" != unknown ] && sysctl -w "$kv=$old" >/dev/null 2>&1 || true
done
rm -f "$f" "$sf"
}

remove_go_optimize() {
for f in /etc/init.d/tg-ws-proxy-go /etc/init.d/tailscale; do
bak="$f.dns-manager.bak"
[ -f "$bak" ] || continue
curh="$(file_hash "$f")"; managedh="$(cat "$STATE_DIR/$(basename "$f").managed.sha256" 2>/dev/null)"
if [ -n "$managedh" ] && [ -n "$curh" ] && [ "$curh" != "$managedh" ]; then
warn_msg "Не восстанавливаю $f: файл изменён вручную."
continue
fi
mv "$bak" "$f" 2>/dev/null && rm -f "$STATE_DIR/$(basename "$f").managed.sha256"
done
}

reload_fw() {
if [ "$SYS_FW" = fw4 ]; then /etc/init.d/firewall reload >/dev/null 2>&1 || /etc/init.d/firewall restart >/dev/null 2>&1
else /etc/init.d/firewall restart >/dev/null 2>&1; fi
}

apply_extras_now() {
case "$1" in
balance|tld)   reconcile_dnsmasq >/dev/null 2>&1; /etc/init.d/dnsmasq restart >/dev/null 2>&1;;
ntp)           [ "$NTP_IP_FALLBACK" = 1 ] && apply_ntp_ip_fallback;;
quic)          apply_quic_toggle;;
mtu)           apply_mtu_toggle;;
sysctl)        [ "$SYSCTL_TUNING" = 1 ] && apply_sysctl || remove_sysctl_base;;
go)            [ "$GO_OPTIMIZE" = 1 ] && apply_go || remove_go_optimize;;
force)         [ "$FORCE_DOH" = 1 ] && apply_dns_force || remove_dns_force; reload_fw;;
ntp_clients)   [ "$NTP_CLIENTS" = 1 ] && apply_ntp_clients || remove_ntp_clients; /etc/init.d/dnsmasq restart >/dev/null 2>&1; reload_fw;;
dnsmasq_perf)  [ "$DNSMASQ_PERF" = 1 ] && apply_dnsmasq_perf || remove_dnsmasq_perf; /etc/init.d/dnsmasq restart >/dev/null 2>&1;;
client_fixes)  [ "$CLIENT_FIXES" = 1 ] && apply_client_fixes || remove_client_fixes; /etc/init.d/dnsmasq restart >/dev/null 2>&1;;
sysctl_ext)    [ "$SYSCTL_EXTENDED" = 1 ] && apply_sysctl_extended || remove_sysctl_extended;;
ts_hotplug)    [ "$TAILSCALE_HOTPLUG" = 1 ] && apply_tailscale_hotplug || remove_tailscale_hotplug;;
cron)          cleanup_manager_cron;;
esac
save_config
}

apply_bootstrap_only() {
b_list="$(printf '%s' "$BOOTSTRAP_DNS" | tr ',' ' ')"
i=0; changed=0
while uci -q get "https-dns-proxy.@https-dns-proxy[$i]" >/dev/null 2>&1; do
if [ "$(uci -q get "https-dns-proxy.@https-dns-proxy[$i].dns_manager" 2>/dev/null)" = 1 ]; then
uci set "https-dns-proxy.@https-dns-proxy[$i].bootstrap_dns=$b_list"
changed=1
fi
i=$((i+1))
done
if [ "$changed" = 1 ]; then
uci commit https-dns-proxy 2>/dev/null
/etc/init.d/https-dns-proxy restart >/dev/null 2>&1
ok_msg "Bootstrap обновлён для наших DoH-инстансов. Ядро не тронуто."
else
info_msg "Наших DoH-секций нет — bootstrap будет использован при следующем применении."
fi
save_config
}

apply_quic_toggle() {
    if [ "$BLOCK_QUIC" != 1 ]; then
        for _rname in Block_UDP_80 Block_UDP_443; do
            while :; do
                _ridx="$(uci show firewall 2>/dev/null | grep "name='$_rname'" | head -n1 | cut -d. -f2 | cut -d= -f1)"
                [ -n "$_ridx" ] || break
                uci -q delete "firewall.$_ridx" || break
            done
        done
    else
        apply_quic || return 1
    fi
    uci commit firewall >/dev/null 2>&1 || return 1
    if [ "$SYS_FW" = fw4 ]; then
        /etc/init.d/firewall reload >/dev/null 2>&1 || /etc/init.d/firewall restart >/dev/null 2>&1
    else
        /etc/init.d/firewall restart >/dev/null 2>&1
    fi
    save_config
}

apply_mtu_toggle() {
uci -q set firewall.@defaults[0].mtu_fix="$MTU_FIX"
uci commit firewall >/dev/null 2>&1
if [ "$SYS_FW" = "fw4" ]; then
/etc/init.d/firewall reload >/dev/null 2>&1 || /etc/init.d/firewall restart >/dev/null 2>&1
else
/etc/init.d/firewall restart >/dev/null 2>&1
fi
save_config
}
check_module_state() {
    sec="$(get_dnsmasq_section)"
    case "$1" in
        balance) [ "$(uci -q get "dhcp.$sec.allservers" 2>/dev/null)" = 1 ] && printf 1 || printf 0 ;;
        tld) uci -q get "dhcp.$sec.server" 2>/dev/null | tr ' ' '\n' | grep -q '^/ru/' && printf 1 || printf 0 ;;
        ntp) [ "$(uci -q get system.ntp.use_dhcp 2>/dev/null)" = 0 ] && uci -q get system.ntp.server 2>/dev/null | grep -qE '([0-9]{1,3}\.){3}[0-9]{1,3}' && printf 1 || printf 0 ;;
        quic) [ "$QUIC_OURS" = 1 ] && printf 1 || printf 0 ;;
        mtu) [ "$(uci -q get firewall.@defaults[0].mtu_fix 2>/dev/null)" = 1 ] && printf 1 || printf 0 ;;
        sysctl) [ -f /etc/sysctl.d/90-dns-manager.conf ] && printf 1 || printf 0 ;;
        sysctl_ext) [ -f /etc/sysctl.d/91-dns-manager-extended.conf ] && printf 1 || printf 0 ;;
        go) grep -qs 'DNS_MANAGER_GOMEMLIMIT' /etc/init.d/tg-ws-proxy-go /etc/init.d/tailscale 2>/dev/null && printf 1 || printf 0 ;;
        force) uci -q get firewall.dns_manager_dns_redirect >/dev/null 2>&1 && printf 1 || printf 0 ;;
        ntp_clients) uci -q get firewall.dns_manager_ntp_client >/dev/null 2>&1 && printf 1 || printf 0 ;;
        dnsmasq_perf) [ "$(uci -q get "dhcp.$sec.cachesize" 2>/dev/null)" = 1000 ] && printf 1 || printf 0 ;;
        client_fixes) [ -f /etc/dnsmasq.d/91-dns-manager-client-fixes.conf ] && printf 1 || printf 0 ;;
        ts_hotplug) [ -x /etc/init.d/tailscale ] || { printf 1; return; }; [ -f /etc/hotplug.d/iface/99-dns-manager-tailscale ] && printf 1 || printf 0 ;;
        cron) [ "${CRON_CLEANUP:-0}" = 1 ] && printf 1 || printf 0 ;;
        *) printf 0 ;;
    esac
}
module_state_word() {
    _desired="$2"
    _real="$(check_module_state "$1")"
    if [ "$_desired" = 1 ] && [ "$_real" = 1 ]; then
        printf "${C_GREEN}✓ ВКЛ • применено${C_NC}"
    elif [ "$_desired" = 1 ]; then
        printf "${C_YELLOW}⚠ ВКЛ • ещё не применено${C_NC}"
    elif [ "$_real" = 1 ]; then
        printf "${C_PINK}↻ есть на роутере • в меню ВЫКЛ${C_NC}"
    else
        printf "${C_YELLOW}✗ ВЫКЛ${C_NC}"
    fi
}
menu_extras() {
while :; do
clear_screen
printf "${C_WHITE}╔══════════════════════════════════════════════╗\n"
printf "║           🔧 Дополнительные настройки         ║\n"
printf "╚══════════════════════════════════════════════╝${C_NC}\n\n"
printf "${C_SECTION}ОСНОВА DNS${C_NC}\n"
printf "  ${C_GREEN}[1]${C_NC} Балансировка dnsmasq: %b\n" "$(module_state_word balance "$BALANCER_ENABLED")"
printf "  ${C_GREEN}[2]${C_NC} Раздельный DNS (.ru/.su/.рф): %b\n" "$(module_state_word tld "$TLD_RU_ENABLED")"
printf "  ${C_GREEN}[3]${C_NC} NTP IP-first: %b\n" "$(module_state_word ntp "$NTP_IP_FALLBACK")"
printf "\n${C_SECTION}ДОПОЛНИТЕЛЬНЫЕ МОДУЛИ${C_NC}\n"
printf "  ${C_YELLOW}[4]${C_NC} Блокировка QUIC: %b\n" "$(module_state_word quic "$BLOCK_QUIC")"
printf "  ${C_YELLOW}[5]${C_NC} Исправление MTU: %b\n" "$(module_state_word mtu "$MTU_FIX")"
printf "  ${C_YELLOW}[6]${C_NC} Базовый Sysctl: %b\n" "$(module_state_word sysctl "$SYSCTL_TUNING")"
printf "  ${C_YELLOW}[7]${C_NC} Go / Tailscale / TG WS: %b\n" "$(module_state_word go "$GO_OPTIMIZE")"
printf "  ${C_YELLOW}[8]${C_NC} Принудительный локальный DNS: %b\n" "$(module_state_word force "$FORCE_DOH")"
printf "  ${C_YELLOW}[9]${C_NC} NTP для клиентов: %b\n" "$(module_state_word ntp_clients "$NTP_CLIENTS")"
printf "  ${C_YELLOW}[10]${C_NC} Производительность dnsmasq: %b\n" "$(module_state_word dnsmasq_perf "$DNSMASQ_PERF")"
printf "  ${C_YELLOW}[11]${C_NC} Клиентские фиксы Android/Windows: %b\n" "$(module_state_word client_fixes "$CLIENT_FIXES")"
printf "  ${C_YELLOW}[12]${C_NC} Расширенный Sysctl + conntrack: %b\n" "$(module_state_word sysctl_ext "$SYSCTL_EXTENDED")"
printf "  ${C_YELLOW}[13]${C_NC} Автоматический запуск Tailscale после NTP: %b\n" "$(module_state_word ts_hotplug "$TAILSCALE_HOTPLUG")"
printf "  ${C_YELLOW}[14]${C_NC} Чистка старых cron-задач: %b\n" "$(module_state_word cron "$CRON_CLEANUP")"
printf "  ${C_YELLOW}[15]${C_NC} IP-заглушки\n"
printf "\n${C_CYAN}Переключатели применяются сразу и не перезаписывают DNS-ядро.${C_NC}\n"
printf "${C_CYAN}Пункт 14 в главном меню — только для слотов, профилей и bootstrap.${C_NC}\n"
printf "  ${C_GREEN}[Enter]${C_NC} Назад\n\n${C_YELLOW}Выбор:${C_NC} "; safe_read c
case "$c" in
1) [ "$BALANCER_ENABLED" = 1 ] && BALANCER_ENABLED=0 || BALANCER_ENABLED=1; apply_extras_now balance; pause;;
2) [ "$TLD_RU_ENABLED" = 1 ] && TLD_RU_ENABLED=0 || TLD_RU_ENABLED=1; TLD_SPLIT="$TLD_RU_ENABLED"; apply_extras_now tld; pause;;
3) [ "$NTP_IP_FALLBACK" = 1 ] && NTP_IP_FALLBACK=0 || NTP_IP_FALLBACK=1; apply_extras_now ntp; pause;;
4) [ "$BLOCK_QUIC" = 1 ] && BLOCK_QUIC=0 || BLOCK_QUIC=1; apply_extras_now quic; pause;;
5) [ "$MTU_FIX" = 1 ] && MTU_FIX=0 || MTU_FIX=1; apply_extras_now mtu; pause;;
6) [ "$SYSCTL_TUNING" = 1 ] && SYSCTL_TUNING=0 || SYSCTL_TUNING=1; apply_extras_now sysctl; pause;;
7) [ "$GO_OPTIMIZE" = 1 ] && GO_OPTIMIZE=0 || GO_OPTIMIZE=1; apply_extras_now go; pause;;
8) [ "$FORCE_DOH" = 1 ] && FORCE_DOH=0 || FORCE_DOH=1; apply_extras_now force; pause;;
9) [ "$NTP_CLIENTS" = 1 ] && NTP_CLIENTS=0 || NTP_CLIENTS=1; apply_extras_now ntp_clients; pause;;
10) [ "$DNSMASQ_PERF" = 1 ] && DNSMASQ_PERF=0 || DNSMASQ_PERF=1; apply_extras_now dnsmasq_perf; pause;;
11) [ "$CLIENT_FIXES" = 1 ] && CLIENT_FIXES=0 || CLIENT_FIXES=1; apply_extras_now client_fixes; pause;;
12) [ "$SYSCTL_EXTENDED" = 1 ] && SYSCTL_EXTENDED=0 || SYSCTL_EXTENDED=1; apply_extras_now sysctl_ext; pause;;
13) [ "$TAILSCALE_HOTPLUG" = 1 ] && TAILSCALE_HOTPLUG=0 || TAILSCALE_HOTPLUG=1; apply_extras_now ts_hotplug; pause;;
14) [ "$CRON_CLEANUP" = 1 ] && CRON_CLEANUP=0 || CRON_CLEANUP=1; apply_extras_now cron; pause;;
15) menu_bogus;;
'') return;;
*) warn_msg "Неизвестный пункт."; pause;;
esac
done
}

ensure_dependencies(){
missing=""
[ "$HAS_CURL" = yes ] || missing="$missing curl"

if [ "$PKG_MGR" = "apk" ]; then
[ "$HAS_DIG" = yes ] || missing="$missing bind-tools"
else
[ "$HAS_DIG" = yes ] || missing="$missing bind-dig"
fi
[ "$HAS_HDP" = yes ] || missing="$missing https-dns-proxy"
CA_OK=no
[ -s /etc/ssl/certs/ca-certificates.crt ] && CA_OK=yes
if [ "$CA_OK" != yes ]; then
if command -v apk >/dev/null 2>&1; then
apk info -e ca-certificates >/dev/null 2>&1 && CA_OK=yes
apk info -e ca-bundle >/dev/null 2>&1 && CA_OK=yes
elif command -v opkg >/dev/null 2>&1; then
opkg status ca-certificates 2>/dev/null | grep -q '^Status:.*installed' && CA_OK=yes
opkg status ca-bundle 2>/dev/null | grep -q '^Status:.*installed' && CA_OK=yes
fi
fi
[ "$CA_OK" = yes ] || missing="$missing ca-certificates"
[ "$HAS_DNSMASQ" = yes ] || missing="$missing dnsmasq"
printf '%s\n' "$missing"
}
menu_install() {
clear_screen
printf "${C_WHITE}╔════════════════════════════════════════════════════╗\n"
printf "║              📦 Компоненты DNS Manager            ║\n"
printf "╚════════════════════════════════════════════════════╝${C_NC}\n"
printf "  curl              : %s\n" "$(state_word "$HAS_CURL")"
printf "  dig               : %s\n" "$(state_word "$HAS_DIG")"
printf "  https-dns-proxy   : %s\n" "$(state_word "$HAS_HDP")"
CA_OK=no
[ -s /etc/ssl/certs/ca-certificates.crt ] && CA_OK=yes
if [ "$CA_OK" != yes ]; then
if command -v apk >/dev/null 2>&1; then
apk info -e ca-certificates >/dev/null 2>&1 && CA_OK=yes
apk info -e ca-bundle >/dev/null 2>&1 && CA_OK=yes
elif command -v opkg >/dev/null 2>&1; then
opkg status ca-certificates 2>/dev/null | grep -q '^Status:.*installed' && CA_OK=yes
opkg status ca-bundle 2>/dev/null | grep -q '^Status:.*installed' && CA_OK=yes
fi
fi
printf "  CA-сертификаты    : %s\n" "$(state_word "$CA_OK")"
printf "  dnsmasq           : %s\n" "$(state_word "$HAS_DNSMASQ")"
need="$(ensure_dependencies)"
if [ -z "$need" ]; then
ok_msg "Все обязательные компоненты уже установлены."
pause
return
fi
printf "${C_YELLOW}Необходимо установить:${C_NC}\n"
for pkg in $need; do
printf "  ${C_PINK}↻${C_NC} %s\n" "$pkg"
done
printf "\n"
if confirm_action "Установить недостающие компоненты сейчас?"; then
if [ "$PKG_MGR" = "apk" ]; then
apk update && apk add $need
else
opkg update && opkg install $need
fi
run_discovery
if [ "$HAS_CURL" = yes ] && [ "$HAS_DIG" = yes ] && \
[ "$HAS_HDP" = yes ] && [ "$HAS_DNSMASQ" = yes ]; then
ok_msg "Обязательные компоненты установлены."
else
warn_msg "После установки остались недостающие компоненты. Проверьте состояние."
fi
else
info_msg "Установка отменена."
fi
pause
}
menu_status() {
clear_screen
printf "${C_WHITE}╔══════════════════════════════════════════════╗\n"
printf "║             📋 Состояние и журнал            ║\n"
printf "╚══════════════════════════════════════════════╝${C_NC}\n"
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
quick_max_bypass() {
clear_screen
printf "${C_TITLE}╔════════════════════════════════════════════════════╗\n"
printf "║        🚀 МАКСИМАЛЬНЫЙ ГИБРИДНЫЙ ОБХОД            ║\n"
printf "╚════════════════════════════════════════════════════╝${C_NC}\n"
printf "${C_WHITE}Сначала роутер будет перечитан, затем весь каталог DNS будет протестирован.${C_NC}\n"
printf "${C_WHITE}После теста будут выбраны только реально доступные кандидаты.${C_NC}\n"
printf "${C_YELLOW}⏳ Идёт параллельный перебор всех DoH-эндпоинтов — это не самый быстрый шаг.${C_NC}\n"
printf "${C_GREEN}✓${C_NC} 6 разных рабочих DoH для общего пула\n"
printf "${C_GREEN}✓${C_NC} Yandex RU для .ru / .su / .рф\n"
printf "${C_GREEN}✓${C_NC} dnsmasq :53\n"
printf "${C_GREEN}✓${C_NC} allservers=1\n"
printf "${C_GREEN}✓${C_NC} уникальные порты\n"
printf "${C_GREEN}✓${C_NC} чужие DoH/Firewall не присваиваются менеджеру\n"
printf "${C_GREEN}✓${C_NC} проверка после применения + автоматический откат\n"
printf "${C_YELLOW}⚠${C_NC} DNS не заменяет Zapret/VPN при блокировках по IP, SNI, DPI и HTTP.\n"
test_dns_catalog
[ -s "$TEST_RESULTS" ] || return
DNS_PROFILE="hybrid"
auto_fill_slots bypass
SLOT_RU="yandex_ru"
SLOT_RU_2=""
TLD_RU_ENABLED=1
TLD_SPLIT=1
BALANCER_ENABLED=1
PORT_1="$HYBRID_PORT_1"; PORT_2="$HYBRID_PORT_2"; PORT_3="$HYBRID_PORT_3"
PORT_4="$HYBRID_PORT_4"; PORT_5="$HYBRID_PORT_5"; PORT_6="$HYBRID_PORT_6"
PORT_RU="$HYBRID_PORT_RU"; PORT_RU_2=""
save_config
CORE_ONLY=1
apply_settings
CORE_ONLY=0
}
dependency_preflight(){
run_discovery >/dev/null 2>&1 || true
printf "${C_TITLE}📦 ПРОВЕРКА ЗАВИСИМОСТЕЙ${C_NC}\n"
printf '  curl              : %b\n' "$(state_word "$HAS_CURL")"
printf '  dig               : %b\n' "$(state_word "$HAS_DIG")"
printf '  https-dns-proxy   : %b\n' "$(state_word "$HAS_HDP")"
if [ -s /etc/ssl/certs/ca-certificates.crt ]; then
printf '  CA-сертификаты    : %b✓ ВКЛ%b\n' "$C_GREEN" "$C_NC"
else
printf '  CA-сертификаты    : %b✗ НЕТ%b\n' "$C_RED" "$C_NC"
fi
}
main_menu() {
while :; do
run_discovery
menu_header "🚀 DNS MANAGER $VERSION"
printf "${C_SECTION}СОСТОЯНИЕ${C_NC}\n"
printf "  IPv4          : %b\n" "$(state_word "$IPV4_ROUTE")"
printf "  IPv6          : %b\n" "$(state_word "$IPV6_ROUTE")"
printf "  dnsmasq       : %b\n" "$(state_word "$DNSMASQ_RUN")"
printf "  https-dns-proxy: %b\n" "$(state_word "$HAS_HDP")"
printf "  DoH обнаружено: ${C_WHITE}%s${C_NC}\n" "$DOH_TOTAL"
[ "$FORCE_DNS" = 1 ] && printf "  ${C_YELLOW}⚠ force_dns стороннего DoH включён${C_NC}\n"
printf "${C_BOLD}${C_PINK}🚀 БЫСТРАЯ НАСТРОЙКА${C_NC}\n"
printf "  ${C_PINK}[1]${C_NC} 🚀 ${C_BOLD}МАКСИМАЛЬНЫЙ ГИБРИДНЫЙ ОБХОД${C_NC}\n"
printf "      ${C_WHITE}6 рабочих DoH + Yandex RU + автоматическая проверка${C_NC}\n"
printf "\n${C_SECTION}DNS ПРОФИЛИ${C_NC}\n"
printf "  ${C_GREEN}[2]${C_NC} ⚡ Максимальная скорость\n"
printf "  ${C_BLUE}[3]${C_NC} 🛡 Максимальная безопасность\n"
printf "  ${C_MAGENTA}[4]${C_NC} 🔐 Максимальная приватность\n"
printf "  ${C_YELLOW}[5]${C_NC} 🧹 Блокировка рекламы\n"
printf "  ${C_PINK}[6]${C_NC} ⭐ Выбор по категориям\n"
printf "\n${C_SECTION}НАСТРОЙКА${C_NC}\n"
printf "  ${C_CYAN}[7]${C_NC} 📊 Карта состояния\n"
printf "  ${C_CYAN}[8]${C_NC} 🔍 Тест всех DNS/DoH (${C_WHITE}%s${C_NC})\n" "$(count_dns)"
printf "  ${C_CYAN}[9]${C_NC} ⚙ Слоты DNS (6+2)\n"
printf "  ${C_CYAN}[10]${C_NC} 🎯 Bootstrap DNS\n"
printf "  ${C_CYAN}[11]${C_NC} 🕐 Время / NTP\n"
printf "  ${C_CYAN}[12]${C_NC} 🔧 Дополнительные настройки\n"
printf "  ${C_CYAN}[13]${C_NC} 📋 Состояние и журнал\n"
printf "  ${C_GREEN}[14]${C_NC} ⚡ Показать и применить выбранное\n"
printf "  ${C_BLUE}[15]${C_NC} 📦 Установить недостающее\n"
printf "  ${C_RED}[16]${C_NC} 🔄 Удалить только изменения DNS Manager\n"
printf "  ${C_WHITE}[Enter]${C_NC} 🚪 Выход\n"
printf "\n${C_YELLOW}Выбор:${C_NC} "
safe_read c
[ -z "$c" ] && { clear_screen; printf "${C_GREEN}DNS Manager завершён.${C_NC}\n"; exit 0; }
        case "$c" in
            1) quick_max_bypass ;;
            2) menu_best_actions clean "МАКСИМАЛЬНАЯ СКОРОСТЬ" ;;
            3) menu_best_actions security "МАКСИМАЛЬНАЯ БЕЗОПАСНОСТЬ" ;;
            4) menu_best_actions privacy "МАКСИМАЛЬНАЯ ПРИВАТНОСТЬ" ;;
            5) menu_best_actions adblock "БЛОКИРОВКА РЕКЛАМЫ" ;;
            6) show_best ;;
            7) show_map ;;
            8) test_dns_catalog; show_tests ;;
            9) menu_slots ;;
            10) menu_bootstrap ;;
            11) menu_ntp ;;
            12) menu_extras ;;
            13) menu_status ;;
            14) apply_settings ;;
            15) menu_install ;;
            16)
                clear_screen
                menu_header "🔄 УДАЛЕНИЕ ТОЛЬКО DNS MANAGER"
                warn_msg "Будут удалены только DoH-секции с dns_manager=1 и записи, ранее отмеченные как наши."
                if confirm_action "Удалить только изменения DNS Manager?"; then
                    rollback_ours
                else
                    info_msg "Отменено."
                fi
                ;;
            *) warn_msg "Неизвестный пункт. Используйте номер меню или Enter."; pause ;;
        esac
done
}
# ENTRY: always read first.
preflight_readonly
init_dirs
write_catalogs
load_config
if [ "${_had_dns_profile:-1}" = 0 ]; then
hybrid_set_defaults
save_config
printf "${C_YELLOW}ℹ Обнаружена старая конфигурация без профиля. Создан основной профиль Hybrid SmartDNS (без изменений роутера).${C_NC}\n"
fi
run_discovery
printf "${C_GREEN}✓ Первый проход завершён. Настройки роутера пока не изменялись.${C_NC}\n"
printf "${C_YELLOW}ℹ Каталог DNS: %s вариантов. Если найден старый каталог — он сохранён как .previous.${C_NC}\n" "$(count_dns)"
log_msg "START v$VERSION OpenWrt=$SYS_OWRT target=$SYS_TARGET arch=$SYS_ARCH fw=$SYS_FW"
main_menu
