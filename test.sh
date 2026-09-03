#!/bin/sh
MANAGER_PATH="/usr/bin/dns-manager"

# ==========================================
# ОСНОВНЫЕ ПАРАМЕТРЫ
# ==========================================
VERSION="1.13-HYBRID"
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
C_GREEN='\033[1;32m'
C_RED='\033[1;31m'
C_CYAN='\033[1;36m'
C_YELLOW='\033[1;33m'
C_MAGENTA='\033[1;35m'
C_BLUE='\033[0;34m'
C_NC='\033[0m'
C_BOLD='\033[1m'
C_WHITE='\033[1;37m'
C_PINK='\033[1;35m'
C_DGRAY='\033[1;37m'
C_TITLE='\033[0;34m'
C_SECTION='\033[1;33m'

# ==========================================
# ПРОВЕРКА И ОБНОВЛЕНИЕ
# ==========================================
UPDATE_URL="https://raw.githubusercontent.com/PoTuStoronu222/DNS-Manager/main/test.sh"

_ver_newer() {
awk -v a="$1" -v b="$2" 'BEGIN{
  split(a, x, "[.-]"); split(b, y, "[.-]");
  if (x[1]+0 > y[1]+0) exit 0;
  if (x[1]+0 < y[1]+0) exit 1;
  if (x[2]+0 > y[2]+0) exit 0;
  exit 1;
}'
}

auto_update_manager() {
[ "$#" -eq 0 ] || return 0
[ "${DNS_MANAGER_NO_UPDATE:-0}" = "1" ] && return 0
[ "$0" = "$MANAGER_PATH" ] || return 0
[ -f "$MANAGER_PATH" ] || return 0
[ -w "${MANAGER_PATH%/*}" ] || return 0
command -v curl >/dev/null 2>&1 || command -v wget >/dev/null 2>&1 || return 0

_upd_tmp="/tmp/dns-manager-update-$$"
rm -f "$_upd_tmp" 2>/dev/null
if command -v curl >/dev/null 2>&1; then
  curl -fsSL --connect-timeout 4 --max-time 15 -o "$_upd_tmp" "$UPDATE_URL" >/dev/null 2>&1
else
  wget -q -T 15 -O "$_upd_tmp" "$UPDATE_URL" >/dev/null 2>&1
fi

if [ ! -s "$_upd_tmp" ]; then
  printf "${C_CYAN}ℹ Проверка обновления: источник недоступен. Запуск продолжается.${C_NC}\n"
  rm -f "$_upd_tmp" 2>/dev/null; return 0
fi

head -n 1 "$_upd_tmp" 2>/dev/null | grep -q '^#!/bin/sh' || { rm -f "$_upd_tmp"; return 0; }
_new_version="$(sed -n 's/^VERSION="\([^"]*\)"$/\1/p' "$_upd_tmp" 2>/dev/null | head -n1)"
if [ -z "$_new_version" ]; then rm -f "$_upd_tmp"; return 0; fi
sh -n "$_upd_tmp" 2>/dev/null || { rm -f "$_upd_tmp"; return 0; }

if [ "$_new_version" = "$VERSION" ]; then
  printf "${C_GREEN}✓ Проверка обновления: версия %s актуальна.${C_NC}\n" "$VERSION"
  rm -f "$_upd_tmp" 2>/dev/null; return 0
fi

if ! _ver_newer "$_new_version" "$VERSION"; then
  printf "${C_CYAN}ℹ Проверка обновления: на GitHub %s — старше установленной %s. Обновление пропущено.${C_NC}\n" "$_new_version" "$VERSION"
  rm -f "$_upd_tmp" 2>/dev/null; return 0
fi

printf "${C_PINK}↻ Доступна версия %s. Обновление...${C_NC}\n" "$_new_version"
if cp -f "$_upd_tmp" "$MANAGER_PATH" 2>/dev/null && chmod 755 "$MANAGER_PATH" 2>/dev/null; then
  rm -f "$_upd_tmp" 2>/dev/null
  printf "${C_GREEN}✓ DNS Manager обновлён: %s → %s${C_NC}\n" "$VERSION" "$_new_version"
  mkdir -p "$STATE_DIR" 2>/dev/null
  log_msg "UPDATE $VERSION -> $_new_version"
  DNS_MANAGER_NO_UPDATE=1 exec "$MANAGER_PATH"
fi

printf "${C_YELLOW}! Не удалось заменить %s. Запуск продолжается на %s.${C_NC}\n" "$MANAGER_PATH" "$VERSION"
rm -f "$_upd_tmp" 2>/dev/null
return 0
}
# ==========================================
# СООБЩЕНИЯ И СЛУЖЕБНЫЙ ВЫВОД
# ==========================================
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
    if [ "${SILENT_APPLY:-0}" = 1 ]; then
        log_msg "Автоматическое подтверждение: $_prompt"
        return 0
    fi
    printf "\n${C_WHITE}%s${C_NC}\n" "$_prompt"
    printf "  ${C_GREEN}[✓] Y / y  или  Н / н — Да, применить${C_NC}\n"
    printf "  ${C_RED}[✗] N / n  или  Т / т — Нет, назад${C_NC}\n"
    printf "  ${C_WHITE}[Enter] — отмена / назад${C_NC}\n"
    menu_prompt
    safe_read _ans
    case "$_ans" in
        y|Y|н|Н|yes|YES|да|Да|ДА) return 0 ;;
        n|N|т|Т|no|NO|нет|Нет|НЕТ|"") return 1 ;;
        *) warn_msg "Неверный выбор. Используйте Y/Н — Да или N/Т — Нет."; return 1 ;;
    esac
}
pause() { [ "${SILENT_APPLY:-0}" = 1 ] && return 0; printf "\n${C_WHITE}Нажмите Enter...${C_NC}"; safe_read _dummy; }
clear_screen() { command -v clear >/dev/null 2>&1 && clear || printf '\033[2J\033[H'; printf '\033[1;37m'; }
menu_header() {
clear_screen
_title="$1"
printf "\n${C_TITLE}╔══════════════════════════════════════════════════════════════╗${C_NC}\n"
printf "${C_TITLE}║${C_NC} ${C_BOLD}${C_YELLOW}%-57s${C_NC} ${C_TITLE}║${C_NC}\n" "$_title"
printf "${C_TITLE}╚══════════════════════════════════════════════════════════════╝${C_NC}\n"
}
menu_section() {
printf "\n${C_YELLOW}${C_BOLD}%s${C_NC}\n" "$1"
}
menu_item() {
printf "  ${C_CYAN}${C_BOLD}%-5s${C_NC} ${C_YELLOW}${C_BOLD}%s${C_NC}\n" "$1" "$2"
}
menu_item_state() {
printf "  ${C_CYAN}${C_BOLD}%-5s${C_NC} ${C_YELLOW}${C_BOLD}%-38s${C_NC} %b\n" "$1" "$2" "$3"
}
menu_note() {
printf "      ${C_CYAN}%s${C_NC}\n" "$1"
}
menu_note_plain() {
printf "      ${C_WHITE}%s${C_NC}\n" "$1"
}
menu_back() {
printf "\n${C_GREEN}${C_BOLD}[Enter]${C_NC} ${C_CYAN}Назад${C_NC}\n\n"
}
menu_prompt() {
printf "${C_YELLOW}${C_BOLD}Выберите пункт: ${C_NC}"
}

# ==========================================
# ПРЕДВАРИТЕЛЬНАЯ ПРОВЕРКА
# ==========================================
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
# ==========================================
# КАТАЛОГИ И НАЧАЛЬНАЯ ИНИЦИАЛИЗАЦИЯ
# ==========================================
init_dirs() {
mkdir -p "$CFG_DIR" "$STATE_DIR" "$TMP_DIR" 2>/dev/null
touch "$LOG_FILE" "$TX_LOG" "$OWNERSHIP" 2>/dev/null
}
write_catalogs() {
rm -f "$DNS_CATALOG.previous" "$NTP_CATALOG.previous" "$BOOTSTRAP_CATALOG.previous" "$BOGUS_CATALOG.previous" 2>/dev/null
if [ ! -s "$DNS_CATALOG" ] || ! grep -q '^# DNSCATVER=8.2-RU' "$DNS_CATALOG" 2>/dev/null; then
cat > "$DNS_CATALOG" <<'EOF_DNS'
# DNSCATVER=8.2-RU
# Список кандидатов. Работоспособность проверяется с роутера.
# ФОРМАТ СТРОКИ: ID|CATEGORY|PROFILE|NAME|URL|REGION|STATUS
# ==========================================
# КАТАЛОГ DNS — ОБХОД И СЕРВИСЫ
# ==========================================
mafioznik|bypass|geo+services|Mafioznik DNS|https://dns.mafioznik.com/dns-query|ru/global|verified-current
mafioznik_xyz|bypass|geo+services|Mafioznik DNS XYZ|https://dns.mafioznik.xyz/dns-query|ru/global|runtime-check
astracat|bypass|geo+ads+services|Astrakat DNS|https://dns.astrakat.ru/dns-query|ru/global|user-confirmed-current
astracat_1498|bypass|geo+ads+services|AstraCat DNS :1498|https://dns.astrakat.ru:1498/dns-query|ru/global|runtime-check
astracat_8443|bypass|geo+ads+services|AstraCat DNS :8443|https://dns.astrakat.ru:8443/dns-query|ru/global|runtime-check
malw_link|bypass|ip-block+geo|Malw.link|https://dns.malw.link/dns-query|ru/global|verified-current
xbox_dns|bypass|games+supercell|Xbox DNS|https://xbox-dns.ru/dns-query|ru/global|verified-current
geohide|bypass|geo+services|GeoHide DNS|https://dns.geohide.ru:444/dns-query|ru/global|verified-current
geohide_8443|bypass|geo+services|GeoHide DNS :8443|https://dns.geohide.ru:8443/dns-query|ru/global|runtime-check
comss_ru|bypass|geo+services|Comss DNS RU|https://dns.comss.ru/dns-query|ru/global|user-confirmed-current
comss_bypass|bypass|geo+security|Comss.one|https://dns.comss.one/dns-query|ru/global|verified-published-current
comss_adblock_bypass|bypass|geo+ads+security|Comss.one Ad Filter|https://router.comss.one/dns-query|ru/global|verified-published-current
vppay|bypass|geo+services|VPPay DNS|https://dns.vppay.ru/dns-query|ru/global|user-confirmed-current
dynx|bypass|geo+youtube|DynX DNS|https://dns.dynx.pro/dns-query|global|review-runtime
paesa|bypass|geo+youtube|Paesa DNS|https://dns.paesa.es/dns-query|global|review-runtime
anon_no|bypass|privacy+geo|Anon.no DNS|https://dns.anon.no/dns-query|norway|review-runtime
bebas_unfiltered|bypass|uncensored|BebasDNS Unfiltered|https://dns.bebasid.com/unfiltered|id/global|source-listed
dns4all|bypass|uncensored|DNS4all|https://doh.dns4all.eu/dns-query|eu/global|source-listed
dns4eu_unfiltered|clean|unfiltered|DNS4EU Unfiltered|https://unfiltered.joindns4.eu/dns-query|eu|verified-published-current
shecan|bypass|geo+services|Shecan DNS|https://free.shecan.ir/dns-query|ir/global|runtime-check
# ==========================================
# КАТАЛОГ DNS — РЕГИОНАЛЬНЫЕ
# ==========================================
yandex_ru|regional|ru+su+rf|Yandex RU|https://common.dot.dns.yandex.net/dns-query|ru|verified-published-current
yandex_safe|regional|ru+su+rf|Yandex Safe|https://safe.dot.dns.yandex.net/dns-query|ru|runtime-check
yandex_family|regional|ru+su+rf|Yandex Family|https://family.dot.dns.yandex.net/dns-query|ru|runtime-check
# ==========================================
# КАТАЛОГ DNS — ЧИСТЫЕ И ПУБЛИЧНЫЕ
# ==========================================
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
# ==========================================
# КАТАЛОГ DNS — БЕЗОПАСНОСТЬ
# ==========================================
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
# ==========================================
# КАТАЛОГ DNS — ПРИВАТНОСТЬ
# ==========================================
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
# ==========================================
# КАТАЛОГ DNS — БЛОКИРОВКА РЕКЛАМЫ
# ==========================================
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
# ==========================================
# КАТАЛОГ DNS — СЕМЕЙНАЯ ЗАЩИТА
# ==========================================
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
if [ ! -s "$NTP_CATALOG" ] || ! grep -q '^# NTPCATVER=6.6-FINAL-HYBRID' "$NTP_CATALOG" 2>/dev/null || ! grep -q '^vniiftri_all|' "$NTP_CATALOG" 2>/dev/null; then
cat > "$NTP_CATALOG" <<'EOF_NTP'
# NTPCATVER=6.6-FINAL-HYBRID
# ID|КАТЕГОРИЯ|ИМЯ|IPV4|IPV6|РЕЖИМ|LEAP|СТАТУС
cf_ip|global|Cloudflare|162.159.200.1 162.159.200.123|2606:4700:f1::1 2606:4700:f1::123|ip-first|no-smear|verified-current
nist_ip|global|NIST|129.6.15.28 129.6.15.29 129.6.15.30 129.6.15.27 129.6.15.26|2610:20:6f15:15::27 2610:20:6f15:15::26|ip-first|no-smear|verified-current
google_ip|special|Google Public NTP|216.239.35.0 216.239.35.4 216.239.35.8 216.239.35.12||ip-only|smear|verified-current
vniiftri_moscow|ru|ВНИИФТРИ Менделеево|89.109.251.21 89.109.251.22 89.109.251.23 89.109.251.24 89.109.251.25||ip-first|no-smear|verified-source
vniiftri_all|ru|ВНИИФТРИ — все регионы|89.109.251.21 89.109.251.22 89.109.251.23 89.109.251.24 89.109.251.25 46.254.241.74 46.254.241.75 212.19.6.218 212.19.17.26 80.242.83.227 80.242.83.228 91.189.237.182||ip-first|no-smear|verified-source
vniiftri_irkutsk|ru|ВНИИФТРИ Иркутск|46.254.241.74 46.254.241.75||ip-first|no-smear|verified-source
vniiftri_khabarovsk|ru|ВНИИФТРИ Хабаровск|212.19.6.218 212.19.17.26||ip-first|no-smear|verified-source
vniiftri_novosibirsk|ru|ВНИИФТРИ Новосибирск|80.242.83.227 80.242.83.228||ip-first|no-smear|verified-source
vniiftri_kamchatka|ru|ВНИИФТРИ Камчатка|91.189.237.182||ip-only|no-smear|verified-source
pool_global|pool|NTP Pool Global||||hostname|no-smear|runtime-check
pool_ru|pool|NTP Pool Russia||||hostname|no-smear|runtime-check
EOF_NTP
fi
if [ ! -s "$BOOTSTRAP_CATALOG" ] || ! grep -q '^# BOOTSTRAPCATVER=6.6-FIX13' "$BOOTSTRAP_CATALOG" 2>/dev/null; then
cat > "$BOOTSTRAP_CATALOG" <<'EOF_BOOT'
# BOOTSTRAPCATVER=6.6-FINAL-HYBRID
# ID|ПРОВАЙДЕР|IPV4|IPV6|РОЛЬ|СТАТУС
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
cat > "$BOGUS_CATALOG" <<'EOF_BOGUS'
# BOGUSCATVER=6.6-FINAL-HYBRID
# ID|ТИП|IP|ОПИСАНИЕ|НАДЁЖНОСТЬ|СТАТУС
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
# ==========================================
# ЗАГРУЗКА И СОХРАНЕНИЕ НАСТРОЕК
# ==========================================
load_config() {
_had_dns_profile=0
[ -f "$CONFIG_FILE" ] && grep -q '^DNS_PROFILE=' "$CONFIG_FILE" 2>/dev/null && _had_dns_profile=1
[ -f "$CONFIG_FILE" ] && . "$CONFIG_FILE" 2>/dev/null
: "${SLOT_1:=}"; : "${SLOT_2:=}"; : "${SLOT_3:=}"; : "${SLOT_4:=}"; : "${SLOT_5:=}"; : "${SLOT_6:=}"
: "${SLOT_RU:=}"; : "${SLOT_RU_2:=}"
: "${SLOT_1_CAT:=}"; : "${SLOT_2_CAT:=}"; : "${SLOT_3_CAT:=}"; : "${SLOT_4_CAT:=}"; : "${SLOT_5_CAT:=}"; : "${SLOT_6_CAT:=}"
: "${SLOT_RU_CAT:=}"; : "${SLOT_RU_2_CAT:=}"
: "${PORT_1:=}"; : "${PORT_2:=}"; : "${PORT_3:=}"; : "${PORT_4:=}"; : "${PORT_5:=}"; : "${PORT_6:=}"
: "${PORT_RU:=}"; : "${PORT_RU_2:=}"
: "${BOOTSTRAP_DNS:=77.88.8.8,77.88.8.1,94.140.14.14,94.140.15.15}"
: "${TLD_RU_ENABLED:=1}"; : "${BLOCK_QUIC:=0}"; : "${MTU_FIX:=0}"; : "${FORCE_DOH:=0}"
: "${NTP_IP_FALLBACK:=1}"; : "${SYSCTL_TUNING:=0}"; : "${GO_OPTIMIZE:=0}"; : "${DNSMASQ_PERF:=0}"; : "${NTP_CLIENTS:=0}"; : "${CLIENT_FIXES:=0}"; : "${SYSCTL_EXTENDED:=0}"; : "${TAILSCALE_HOTPLUG:=0}"; : "${CRON_CLEANUP:=0}"
: "${BALANCER_ENABLED:=1}"; : "${NTP_PRESET:=cf_ip}"; : "${DNS_PROFILE:=hybrid}"
: "${WATCHDOG_ENABLED:=0}"; : "${WATCHDOG_INTERVAL:=15}"
TLD_SPLIT="$TLD_RU_ENABLED"
if [ "$_had_dns_profile" = 0 ] && [ -z "$DNS_PROFILE" ]; then
DNS_PROFILE="hybrid"
fi
if [ "$DNS_PROFILE" = "hybrid" ]; then
    for _slot in 1 2 3 4 5 6 RU RU_2; do
        eval "_sid=\${SLOT_${_slot}:-}"
        eval "_scat=\${SLOT_${_slot}_CAT:-}"
        if [ -n "$_sid" ] && [ -z "$_scat" ]; then
            _scat="$(dns_cat "$_sid")"
            case "$_slot" in RU|RU_2) [ -n "$_scat" ] || _scat="regional" ;; esac
            eval "SLOT_${_slot}_CAT=\"$_scat\""
        fi
    done
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
SLOT_1_CAT="$SLOT_1_CAT"
SLOT_2_CAT="$SLOT_2_CAT"
SLOT_3_CAT="$SLOT_3_CAT"
SLOT_4_CAT="$SLOT_4_CAT"
SLOT_5_CAT="$SLOT_5_CAT"
SLOT_6_CAT="$SLOT_6_CAT"
SLOT_RU_CAT="$SLOT_RU_CAT"
SLOT_RU_2_CAT="$SLOT_RU_2_CAT"
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
WATCHDOG_ENABLED="$WATCHDOG_ENABLED"
WATCHDOG_INTERVAL="$WATCHDOG_INTERVAL"
EOF_CFG
}
# ==========================================
# ОБНАРУЖЕНИЕ СИСТЕМЫ И ЗАВИСИМОСТЕЙ
# ==========================================
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
    _fw_state="$(uci show firewall 2>/dev/null)"
    printf '%s\n' "$_fw_state" | grep -Eq "name='(Block_UDP_80|Block_UDP_443)'" && QUIC_OURS=1
    [ "$(uci -q get firewall.@defaults[0].flow_offloading 2>/dev/null)" = 1 ] && FLOW_OFFLOAD="yes" || FLOW_OFFLOAD="no"
    if command -v nft >/dev/null 2>&1 && nft list ruleset >/dev/null 2>&1; then NFT_ACTIVE="yes"; else NFT_ACTIVE="no"; fi
}

delete_manager_quic_rules() {
    _fw_state="$(uci show firewall 2>/dev/null)"
    printf '%s\n' "$_fw_state" | awk -F'[.=]' -v q="'" '$3=="name" && ($4==q"Block_UDP_80"q || $4==q"Block_UDP_443"q) {print $2}' | sort -u | while IFS= read -r _rsec; do
        [ -n "$_rsec" ] || continue
        uci -q delete "firewall.$_rsec"
    done
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
# ==========================================
# РАБОТА С КАТАЛОГАМИ
# ==========================================
dns_field() { awk -F'|' -v id="$1" -v f="$2" '$1==id{print $f;exit}' "$DNS_CATALOG"; }
dns_name() { dns_field "$1" 4; }
dns_url() { dns_field "$1" 5; }
dns_cat() { dns_field "$1" 2; }
count_dns() { awk -F'|' '$0 !~ /^#/ && NF >= 5 {n++} END {print n+0}' "$DNS_CATALOG" 2>/dev/null; }
ntp_name() { awk -F'|' -v id="$1" '$1==id{print $3;exit}' "$NTP_CATALOG"; }
ntp_ipv4() { awk -F'|' -v id="$1" '$1==id{print $4;exit}' "$NTP_CATALOG"; }
ntp_leap() { awk -F'|' -v id="$1" '$1==id{print $7;exit}' "$NTP_CATALOG"; }
# ==========================================
# СЛУЖЕБНЫЕ ФУНКЦИИ
# ==========================================
# НОРМАЛИЗАЦИЯ И ПРОВЕРКА АДРЕСОВ
# ==========================================
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
# ==========================================
# РЕЗОЛВИНГ И BOOTSTRAP DNS
# ==========================================
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
ipx="$(nslookup "$host" 2>/dev/null | awk '/^Address[ 0-9]*: / {x=$NF; if (x ~ /^[0-9]+(\.[0-9]+){3}$/) {print x; exit}}')"
fi
[ -n "$ipx" ] && { echo "$ipx"; return 0; }
return 1
}
# ==========================================
# ПРОВЕРКА DNS И DoH
# ==========================================
# ТЕСТИРОВАНИЕ DNS-СЕРВЕРОВ
# ==========================================
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
# ==========================================
# ТЕСТ КАТАЛОГА DNS
# ==========================================
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
printf "${C_CYAN}Время — полное время ответа DoH, а не ICMP-пинг. Меньше — быстрее.${C_NC}\n"
log_tx "TEST" "dns-catalog" "RUN" "OK" "ok=$okn,total=$total"
}
# ==========================================
# ПОДБОР ЛУЧШИХ DNS
# ==========================================
show_best_category() {
cat="$1"; limit="$2"
awk -F'|' -v c="$cat" '$2==c && $5=="OK"{print}' "$TEST_RESULTS" 2>/dev/null | sort -t'|' -k4,4n | head -n "$limit"
}
# ==========================================
# HYBRID — 6 DoH + YANDEX RU
# ==========================================
HYBRID_PORT_1=5053
HYBRID_PORT_2=5054
HYBRID_PORT_3=5055
HYBRID_PORT_4=5056
HYBRID_PORT_5=5057
HYBRID_PORT_6=5058
HYBRID_PORT_RU=5059
# ==========================================
# HYBRID — НАСТРОЙКИ И СЛОТЫ
# ==========================================
hybrid_set_defaults() {
SLOT_1="mafioznik"
SLOT_2="comss_bypass"
SLOT_3="astracat"
SLOT_4="malw_link"
SLOT_5="comss_ru"
SLOT_6="vppay"
SLOT_RU="yandex_ru"
SLOT_RU_2=""
SLOT_1_CAT="bypass"
SLOT_2_CAT="bypass"
SLOT_3_CAT="bypass"
SLOT_4_CAT="bypass"
SLOT_5_CAT="bypass"
SLOT_6_CAT="bypass"
SLOT_RU_CAT="regional"
SLOT_RU_2_CAT="regional"
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
# ==========================================
# HYBRID — ПРОСМОТР ПРОФИЛЯ
# ==========================================
show_hybrid_profile() {
while :; do
menu_header "⭐ HYBRID SMARTDNS"
menu_section "ОБЩИЙ ПУЛ DOH"
printf "${C_WHITE}  %-8s %-34s %s${C_NC}\n" "ПОРТ" "DNS" "РОЛЬ"
printf "  ──────────────────────────────────────────────────────────\n"
for _s in 1 2 3 4 5 6; do
eval "_id=\${SLOT_$_s}"
_p="$(hybrid_desired_port "$_s")"
[ -n "$_id" ] && printf "  ${C_YELLOW}%-8s${C_NC} %-34s общий\n" "$_p" "$(dns_name "$_id")"
done
if [ -n "$SLOT_RU" ]; then
printf "\n${C_SECTION}РЕГИОНАЛЬНЫЙ МАРШРУТ${C_NC}\n"
printf "  ${C_YELLOW}%-8s${C_NC} %-34s .ru / .su / .рф\n" "$HYBRID_PORT_RU" "$(dns_name "$SLOT_RU")"
fi
printf "\n${C_SECTION}РЕЖИМ${C_NC}\n"
printf "  ${C_WHITE}Общий DNS:${C_NC} 6 DoH работают параллельно.\n"
printf "  ${C_WHITE}RU:${C_NC}       .ru / .su / .рф → отдельный DNS.\n"
menu_section "ДЕЙСТВИЯ"
menu_item "[1]" "⚡ Автоматически настроить"
menu_item "[2]" "🧪 Проверить DNS"
menu_item "[3]" "🔧 Изменить слоты"
menu_back
menu_prompt
safe_read _c
case "$_c" in
1)
if [ ! -s "$TEST_RESULTS" ]; then test_dns_catalog; fi
HYBRID_AUTO_REPAIR=1
hybrid_prepare_selection
HYBRID_AUTO_REPAIR=0
save_config
ok_msg "Hybrid SmartDNS подготовлен."
if confirm_action "Применить настройки Hybrid SmartDNS?"; then apply_settings; fi
pause
;;
2) test_dns_catalog; show_tests;;
3) menu_slots;;
'') return;;
*) warn_msg "Неверный пункт."; pause;;
esac
done
}
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
servers="$(awk -F'|' -v p="$NTP_PRESET" '$1==p{print $4; exit}' "$NTP_CATALOG" 2>/dev/null)"
[ -n "$servers" ] || { warn_msg "NTP-профиль '$NTP_PRESET' не найден в каталоге."; return 1; }
[ -n "$(uci -q get system.ntp 2>/dev/null)" ] || uci -q set system.ntp=timeserver || return 1
# Профиль NTP заменяет предыдущий список серверов целиком.
uci -q delete system.ntp.server
for ipx in $servers; do
    uci add_list system.ntp.server="$ipx" || return 1
done
uci set system.ntp.enabled='1' || return 1
uci set system.ntp.use_dhcp='0' || return 1
uci commit system || return 1
/etc/init.d/sysntpd restart >/dev/null 2>&1
record_own "ntp" "system.ntp.server" "$servers" "profile=$NTP_PRESET"
ok_msg "NTP: IP-профиль '$NTP_PRESET' добавлен без удаления существующих серверов."
log_tx "APPLY" "NTP" "ADD" "OK" "profile=$NTP_PRESET;servers=$servers"
}
# ==========================================
# МЕНЮ NTP
# ==========================================
menu_ntp() {
while :; do
menu_header "🕐 ВРЕМЯ / NTP"
_cur_ntp="$(uci -q get system.ntp.server 2>/dev/null)"
printf "${C_YELLOW}${C_BOLD}ТЕКУЩАЯ СИНХРОНИЗАЦИЯ${C_NC}\n"
printf "  ${C_YELLOW}${C_BOLD}Профиль:${C_NC} %s\n" "${NTP_PRESET:-не выбран}"
if [ -n "$_cur_ntp" ]; then
    printf "  ${C_YELLOW}${C_BOLD}Серверы:${C_NC}\n"
    for _s in $_cur_ntp; do
        printf "    ${C_GREEN}✓${C_NC} %s\n" "$_s"
    done
else
    printf "  ${C_WHITE}Серверы не настроены${C_NC}\n"
fi
printf "\n${C_YELLOW}${C_BOLD}ГОТОВЫЕ NTP ПРОФИЛИ${C_NC}\n"
menu_item "[1]" "Cloudflare — точное время по IP"
menu_item "[2]" "NIST — несколько серверов"
menu_item "[3]" "ВНИИФТРИ — Москва"
menu_item "[4]" "Google — Public NTP (leap-smear)"
menu_item "[5]" "ВНИИФТРИ — все регионы"
printf "\n${C_YELLOW}${C_BOLD}КЛИЕНТЫ ЛОКАЛЬНОЙ СЕТИ${C_NC}\n"
if [ "${NTP_CLIENTS:-0}" = 1 ]; then
    menu_item "[6]" "NTP для клиентов LAN — ВКЛ"
else
    menu_item "[6]" "NTP для клиентов LAN — ВЫКЛ"
fi
printf "\n${C_GREEN}[Enter]${C_NC} Назад\n\n"
printf "${C_YELLOW}${C_BOLD}Выберите пункт:${C_NC} "; safe_read c
case "$c" in
1) NTP_PRESET="cf_ip"; save_config; apply_ntp_ip_fallback; pause;;
2) NTP_PRESET="nist_ip"; save_config; apply_ntp_ip_fallback; pause;;
3) NTP_PRESET="vniiftri_moscow"; save_config; apply_ntp_ip_fallback; pause;;
4) NTP_PRESET="google_ip"; save_config; apply_ntp_ip_fallback; pause;;
5) NTP_PRESET="vniiftri_all"; save_config; apply_ntp_ip_fallback; pause;;
6)
    if [ "${NTP_CLIENTS:-0}" = 1 ]; then
        NTP_CLIENTS=0
    else
        NTP_CLIENTS=1
    fi
    save_config
    if [ "$NTP_CLIENTS" = 1 ]; then
        apply_ntp_clients
        /etc/init.d/dnsmasq restart >/dev/null 2>&1
        reload_fw
        ok_msg "NTP для клиентов LAN включён."
    else
        remove_ntp_clients
        /etc/init.d/dnsmasq restart >/dev/null 2>&1
        reload_fw
        ok_msg "NTP для клиентов LAN выключен."
    fi
    pause;;
'') return;;
*) warn_msg "Неизвестный пункт."; pause;;
esac
done
}

menu_install() {
menu_header "📦 КОМПОНЕНТЫ DNS MANAGER"
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
# ==========================================
# МЕНЮ СОСТОЯНИЯ
# ==========================================
menu_status() {
menu_header "📋 СОСТОЯНИЕ И ЖУРНАЛ"
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
menu_header "🚀 МАКСИМАЛЬНЫЙ ГИБРИДНЫЙ ОБХОД"
printf "${C_WHITE}Сначала роутер будет перечитан, затем весь каталог DNS будет протестирован.${C_NC}\n"
printf "${C_WHITE}После теста будут выбраны только реально доступные кандидаты.${C_NC}\n"
printf "${C_YELLOW}⏳ Идёт параллельный перебор всех DoH-эндпоинтов — это не самый быстрый шаг.${C_NC}\n"
menu_section "ЧТО БУДЕТ НАСТРОЕНО"
menu_note "✓ 6 разных рабочих DoH для общего пула"
menu_note "✓ Yandex RU для .ru / .su / .рф"
menu_note "✓ dnsmasq :53"
menu_note "✓ allservers=1"
menu_note "✓ уникальные порты"
menu_note "✓ чужие DoH/Firewall не присваиваются менеджеру"
menu_note "✓ проверка после применения + автоматический откат"
printf "${C_YELLOW}⚠${C_NC} DNS не заменяет Zapret/VPN при блокировках по IP, SNI, DPI и HTTP.\n"
test_dns_catalog
[ -s "$TEST_RESULTS" ] || return
DNS_PROFILE="hybrid"
auto_fill_slots bypass
SLOT_RU="yandex_ru"
SLOT_RU_2=""
SLOT_RU_CAT="regional"
SLOT_RU_2_CAT="regional"
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
# ==========================================
# ПРОВЕРКА ЗАВИСИМОСТЕЙ
# ==========================================
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
# ==========================================
# WATCHDOG — ПРОВЕРКА DoH
# ==========================================
# WATCHDOG — ВЫБОР КАТЕГОРИИ
# ==========================================

# ==========================================
# ГЛАВНОЕ МЕНЮ
# ==========================================
main_menu() {
while :; do
run_discovery
menu_header "🚀 DNS MANAGER $VERSION"

menu_section "СОСТОЯНИЕ РОУТЕРА"
printf "  ${C_YELLOW}${C_BOLD}IPv4${C_NC}               %b\n" "$(state_word "$IPV4_ROUTE")"
printf "  ${C_YELLOW}${C_BOLD}IPv6${C_NC}               %b\n" "$(state_word "$IPV6_ROUTE")"
printf "  ${C_YELLOW}${C_BOLD}dnsmasq${C_NC}            %b\n" "$(state_word "$DNSMASQ_RUN")"
printf "  ${C_YELLOW}${C_BOLD}https-dns-proxy${C_NC}    %b\n" "$(state_word "$HAS_HDP")"
printf "  ${C_YELLOW}${C_BOLD}DoH обнаружено${C_NC}     ${C_YELLOW}${C_BOLD}%s${C_NC}\n" "$DOH_TOTAL"
printf "  ${C_YELLOW}${C_BOLD}Watchdog${C_NC}            %b\n" "$(module_state_word watchdog "$WATCHDOG_ENABLED")"
[ "$FORCE_DNS" = 1 ] && printf "  ${C_YELLOW}${C_BOLD}⚠ force_dns${C_NC} ${C_CYAN}стороннего DoH включён${C_NC}\n"

menu_section "БЫСТРЫЙ ЗАПУСК"
menu_item "[1]" "🚀 МАКСИМАЛЬНЫЙ ГИБРИДНЫЙ ОБХОД"
menu_note "6 DoH + Yandex RU + резерв + Watchdog"

menu_section "DNS ПРОФИЛИ"
menu_item "[2]" "⚡ Максимальная скорость"
menu_item "[3]" "🛡 Максимальная безопасность"
menu_item "[4]" "🔐 Максимальная приватность"
menu_item "[5]" "🧹 Блокировка рекламы"
menu_item "[6]" "⭐ Выбор по категориям"

menu_section "НАСТРОЙКА"
menu_item "[7]" "📊 Карта состояния"
printf "  ${C_CYAN}${C_BOLD}%-5s${C_NC} ${C_YELLOW}${C_BOLD}%-38s${C_NC} ${C_CYAN}${C_BOLD}(%s)${C_NC}\n" "[8]" "🧪 Тест всех DNS/DoH" "$(count_dns)"
printf "  ${C_CYAN}${C_BOLD}%-5s${C_NC} ${C_YELLOW}${C_BOLD}%-38s${C_NC} ${C_CYAN}${C_BOLD}(6+2)${C_NC}\n" "[9]" "⚙ Слоты DNS"
menu_item "[10]" "🎯 Bootstrap DNS"
menu_item "[11]" "🕐 Время / NTP"
menu_item "[12]" "🔧 Дополнительные настройки"
menu_item "[13]" "📋 Состояние и журнал"
menu_item "[14]" "⚡ Показать и применить выбранное"
menu_item "[15]" "📦 Установить недостающее"
menu_item "[16]" "🗑 Удалить только изменения DNS Manager"

menu_back
menu_prompt
safe_read c
[ -z "$c" ] && { clear_screen; printf "${C_GREEN}DNS Manager завершён.${C_NC}\n"; exit 0; }
case "$c" in
1) quick_max_bypass ;;
2) menu_best_actions clean "ЧИСТЫЙ БЫСТРЫЙ DNS" ;;
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
menu_header "↻ УДАЛЕНИЕ ИЗМЕНЕНИЙ"
warn_msg "Будут удалены только изменения DNS Manager."
if confirm_action "Удалить изменения DNS Manager?"; then rollback_ours; else info_msg "Отменено."; fi
;;
*) warn_msg "Неизвестный пункт."; pause ;;
esac
done
}

case "${1:-}" in
watchdog|--watchdog|-w)
    preflight_readonly
    init_dirs
    write_catalogs
    load_config
    log_msg "Запуск автоматической проверки DoH."
    run_watchdog
    exit $?
    ;;
esac

preflight_readonly
init_dirs
auto_update_manager        
write_catalogs
load_config
if [ "${_had_dns_profile:-1}" = 0 ]; then
hybrid_set_defaults
save_config
printf "${C_YELLOW}ℹ Обнаружена старая конфигурацию без профиля. Создан основной профиль Hybrid SmartDNS (без изменений роутера).${C_NC}\n"
fi
run_discovery
printf "${C_GREEN}✓ Первый проход завершён. Настройки роутера пока не изменялись.${C_NC}\n"
printf "${C_YELLOW}ℹ Каталог DNS: %s вариантов.${C_NC}\n" "$(count_dns)"
log_msg "START v$VERSION OpenWrt=$SYS_OWRT target=$SYS_TARGET arch=$SYS_ARCH fw=$SYS_FW"
main_menu
