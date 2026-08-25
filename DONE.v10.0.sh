cat << 'EOF' > /tmp/dns_setup.sh
#!/bin/sh

echo "============================================================"
echo "=== OPENWRT FULL SETUP v10.1 FINAL STABLE ==="
echo "=== 6 SmartDNS + Yandex | Static Anti-Stub | Auto-Rollback ==="
echo "============================================================"
echo ""

# ============================================================
# 00. BACKUP (динамическая папка + симлинк)
# ============================================================
echo "[00] Creating backup..."
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_ACTUAL="/etc/config/backup-dns-$TIMESTAMP"
mkdir -p "$BACKUP_ACTUAL"
ln -sfn "$BACKUP_ACTUAL" /etc/config/backup-pre-dns-v9

cp /etc/config/dhcp "$BACKUP_ACTUAL/dhcp.bak" 2>/dev/null
cp /etc/config/firewall "$BACKUP_ACTUAL/firewall.bak" 2>/dev/null
cp /etc/config/https-dns-proxy "$BACKUP_ACTUAL/https-dns-proxy.bak" 2>/dev/null
cp /etc/config/system "$BACKUP_ACTUAL/system.bak" 2>/dev/null
[ -f /etc/crontabs/root ] && cp /etc/crontabs/root "$BACKUP_ACTUAL/crontabs.bak"
echo "[+] Backup saved to: $BACKUP_ACTUAL"
echo ""

# ============================================================
# 0. PRE-CHECKS
# ============================================================
echo "[0] Environment check..."
if [ -f /etc/openwrt_release ]; then
    OPENWRT_VERSION=$(grep DISTRIB_RELEASE /etc/openwrt_release 2>/dev/null | cut -d= -f2 | tr -d "'\"")
else
    OPENWRT_VERSION=$(grep VERSION_ID /etc/os-release 2>/dev/null | cut -d'"' -f2)
fi
[ -z "$OPENWRT_VERSION" ] && OPENWRT_VERSION="Unknown"
echo "[*] OpenWrt: $OPENWRT_VERSION"

if command -v apk >/dev/null 2>&1; then
    PKG="apk"; CA_PKG="ca-certificates"
    echo "[*] Package manager: apk (25.x)"
elif command -v opkg >/dev/null 2>&1; then
    PKG="opkg"; CA_PKG="ca-certificates"
    echo "[*] Package manager: opkg (24.x)"
else
    echo "[!] No package manager found!"; exit 1
fi

if [ -f /usr/share/fw4/helpers.sh ] || command -v fw4 >/dev/null 2>&1; then
    FW_VERSION="fw4"; echo "[*] Firewall: fw4 (nftables)"
else
    FW_VERSION="fw3"; echo "[*] Firewall: fw3 (iptables)"
fi

for util in uci sed grep awk nslookup curl; do
    command -v "$util" >/dev/null 2>&1 || { echo "[!] Missing: $util"; exit 1; }
done
mkdir -p /etc/dnsmasq.d /etc/sysctl.d /etc/hotplug.d/ntp /usr/bin
[ -f /etc/dnsmasq.d/telemetry.conf ] && rm -f /etc/dnsmasq.d/telemetry.conf
echo "[+] OK"
echo ""

# ============================================================
# 1. MTU/MSS CLAMPING
# ============================================================
echo "[1] MTU fix..."
uci -q set firewall.@defaults[0].mtu_fix='1'
WAN_SECTION=$(uci show firewall 2>/dev/null | grep -m1 "\.name='wan'" | cut -d. -f1,2)
[ -n "$WAN_SECTION" ] && uci -q set "${WAN_SECTION}.mtu_fix=1"
uci commit firewall

# ============================================================
# 2. NTP REDIRECT
# ============================================================
echo "[2] NTP redirect..."
LAN_IP=$(uci -q get network.lan.ipaddr | cut -d'/' -f1 | awk '{print $1}')
[ -z "$LAN_IP" ] || [ "$LAN_IP" = "0.0.0.0" ] && LAN_IP="192.168.1.1"
for opt in $(uci -q get dhcp.lan.dhcp_option | tr ' ' '\n' | grep '^42,'); do
    uci -q del_list dhcp.lan.dhcp_option="$opt"
done
uci add_list dhcp.lan.dhcp_option="42,$LAN_IP"
uci commit dhcp
for sec in $(uci show firewall 2>/dev/null | grep -E "dest_port='123'|src_dport='123'|Intercept-NTP|Redirect-NTP" | cut -d. -f2 | cut -d= -f1 | sort -u); do
    uci -q delete firewall."$sec"
done
uci commit firewall
uci set firewall.redirect_ntp=redirect
uci set firewall.redirect_ntp.name='Redirect-NTP'
uci set firewall.redirect_ntp.src='lan'
uci set firewall.redirect_ntp.proto='udp'
uci set firewall.redirect_ntp.src_dport='123'
uci set firewall.redirect_ntp.dest_port='123'
uci set firewall.redirect_ntp.dest_ip="$LAN_IP"
uci set firewall.redirect_ntp.target='DNAT'
[ "$FW_VERSION" = "fw4" ] && uci set firewall.redirect_ntp.family='ipv4'
uci commit firewall
/etc/init.d/firewall reload 2>/dev/null || /etc/init.d/firewall restart 2>/dev/null

# ============================================================
# 3. GO RUNTIME OPTIMIZATION (awk)
# ============================================================
echo "[3] Go optimization..."
f_tg="/etc/init.d/tg-ws-proxy-go"; f_ts="/etc/init.d/tailscale"

if [ -f "$f_tg" ]; then
    sed -i '/GOMAXPROCS/d; /GOMEMLIMIT/d; /GOGC/d' "$f_tg"
    if grep -q "procd_open_instance" "$f_tg"; then
        awk '/procd_open_instance/ {print; print "    procd_set_param env GOMAXPROCS=1 GOMEMLIMIT=50MiB"; next} 1' "$f_tg" > /tmp/tg.tmp && mv /tmp/tg.tmp "$f_tg"
    fi
fi

if [ -f "$f_ts" ]; then
    sed -i '/GOMAXPROCS/d; /GOMEMLIMIT/d; /GOGC/d' "$f_ts"
    if grep -q "procd_open_instance" "$f_ts"; then
        awk '/procd_open_instance/ {print; print "    procd_set_param env GOMEMLIMIT=85MiB"; next} 1' "$f_ts" > /tmp/ts.tmp && mv /tmp/ts.tmp "$f_ts"
    fi
fi

# ============================================================
# 4. CRON CLEANUP (включая артефакты старых версий)
# ============================================================
echo "[4] Cron cleanup..."
[ -f /etc/crontabs/root ] && {
    sed -i '/dnsmasq/d; /https-dns-proxy/d; /tailscale/d; /update-bogus-dns/d' /etc/crontabs/root
}

# Очистка артефактов от старых версий (v8.x, v9.x, v10.0)
rm -f /usr/bin/update-bogus-dns
rm -f /etc/dnsmasq.d/.bogus-old
rm -f /etc/dnsmasq.d/telemetry.conf

# ============================================================
# 5. SYSTEM NTP SERVERS
# ============================================================
echo "[5] NTP servers..."
while uci -q delete system.@timeserver[0]; do :; done
uci -q delete system.ntp 2>/dev/null
uci set system.ntp=timeserver
uci set system.ntp.enabled='1'
uci add_list system.ntp.server='162.159.200.1'
uci add_list system.ntp.server='216.239.35.0'
uci add_list system.ntp.server='89.109.251.21'
uci add_list system.ntp.server='92.255.126.1'
uci add_list system.ntp.server='194.190.168.1'
uci add_list system.ntp.server='129.250.35.250'
uci commit system

# ============================================================
# 6. INSTALL https-dns-proxy
# ============================================================
echo "[6] https-dns-proxy install..."
if ! command -v https-dns-proxy >/dev/null 2>&1; then
    [ "$PKG" = "apk" ] && apk update && apk add https-dns-proxy $CA_PKG
    [ "$PKG" = "opkg" ] && opkg update && opkg install https-dns-proxy $CA_PKG
fi
command -v https-dns-proxy >/dev/null 2>&1 || { 
    echo "[!] https-dns-proxy install FAILED"
    exit 1 
}

# ============================================================
# 7. DoH RESOLVERS (6 SmartDNS + Yandex)
# Bootstrap: БЕЗ Cloudflare/Google/Quad9 (заблокированы в РФ)
# ============================================================
echo "[7] DoH resolvers (6 SmartDNS + Yandex)..."
while uci -q delete https-dns-proxy.@https-dns-proxy[0]; do :; done
uci -q delete https-dns-proxy.config 2>/dev/null
uci set https-dns-proxy.config='main'
uci set https-dns-proxy.config.update_dnsmasq='0'

i=0
for url in \
    'https://dns.mafioznik.com/dns-query' \
    'https://dns.comss.one/dns-query' \
    'https://dns.astrakat.ru/dns-query' \
    'https://dns.malw.link/dns-query' \
    'https://dns.comss.ru/dns-query' \
    'https://dns.vppay.ru/dns-query'; do
    port=$((5053 + i)); i=$((i+1))
    uci add https-dns-proxy https-dns-proxy
    uci set https-dns-proxy.@https-dns-proxy[-1].listen_addr='127.0.0.1'
    uci set https-dns-proxy.@https-dns-proxy[-1].listen_port="$port"
    uci set https-dns-proxy.@https-dns-proxy[-1].resolver_url="$url"
    uci add_list https-dns-proxy.@https-dns-proxy[-1].bootstrap_dns='95.85.85.85'
    uci add_list https-dns-proxy.@https-dns-proxy[-1].bootstrap_dns='77.88.8.8'
    uci add_list https-dns-proxy.@https-dns-proxy[-1].bootstrap_dns='94.140.14.14'
done

uci add https-dns-proxy https-dns-proxy
uci set https-dns-proxy.@https-dns-proxy[-1].listen_addr='127.0.0.1'
uci set https-dns-proxy.@https-dns-proxy[-1].listen_port='5059'
uci set https-dns-proxy.@https-dns-proxy[-1].resolver_url='https://common.dot.dns.yandex.net/dns-query'
uci add_list https-dns-proxy.@https-dns-proxy[-1].bootstrap_dns='77.88.8.8'
uci add_list https-dns-proxy.@https-dns-proxy[-1].bootstrap_dns='95.85.85.85'
uci commit https-dns-proxy

# ============================================================
# 8. TELEMETRY - SKIPPED
# ============================================================
echo "[8] Telemetry block SKIPPED (not needed in RU)"

# ============================================================
# 9. DNSMASQ TLD SPLIT
# ============================================================
echo "[9] dnsmasq TLD Split..."
uci -q get dhcp.@dnsmasq[0] >/dev/null || uci add dhcp dnsmasq
uci -q delete dhcp.balancer 2>/dev/null
while uci -q delete dhcp.@dnsmasq[0].server; do :; done
uci -q delete dhcp.@dnsmasq[0].address 2>/dev/null
uci -q delete dhcp.@dnsmasq[0].confdir 2>/dev/null
for param in min_ttl min_cache_ttl max_cache_ttl neg_ttl dnsforwardmax dns_forward_max edns_pktsz ednspacket_max filter_aaaa; do
    uci -q delete dhcp.@dnsmasq[0].$param 2>/dev/null
done

uci add_list dhcp.@dnsmasq[0].confdir='/etc/dnsmasq.d'
uci set dhcp.@dnsmasq[0].allservers='1'
uci set dhcp.@dnsmasq[0].strictorder='0'
uci set dhcp.@dnsmasq[0].noresolv='1'
dnsmasq -v 2>&1 | grep -qi "filter-AAAA" && uci set dhcp.@dnsmasq[0].filter_aaaa='1'
uci set dhcp.@dnsmasq[0].cachesize='10000'
uci set dhcp.@dnsmasq[0].dnsforwardmax='1000'
uci set dhcp.@dnsmasq[0].max_cache_ttl='300'

for p in 5053 5054 5055 5056 5057 5058; do
    uci add_list dhcp.@dnsmasq[0].server="127.0.0.1#$p"
done

uci add_list dhcp.@dnsmasq[0].server='/ru/127.0.0.1#5059'
uci add_list dhcp.@dnsmasq[0].server='/su/127.0.0.1#5059'
uci add_list dhcp.@dnsmasq[0].server='/xn--p1ai/127.0.0.1#5059'

uci set dhcp.@dnsmasq[0].quietdhcp='1'
uci set dhcp.@dnsmasq[0].boguspriv='1'
uci set dhcp.@dnsmasq[0].domainneeded='1'
uci add_list dhcp.@dnsmasq[0].address='/use-application-dns.net/'
uci add_list dhcp.@dnsmasq[0].server='/connectivitycheck.gstatic.com/127.0.0.1#5059'
uci add_list dhcp.@dnsmasq[0].server='/connectivitycheck.samsungcloud.com/127.0.0.1#5059'
uci commit dhcp

# ============================================================
# 10. ANTI-BLOCK FILTERS (ТОЛЬКО ФИКСИРОВАННЫЙ СПИСОК)
# БЕЗОПАСНО для сетей с DPI-блокировками (ТСПУ)
# ============================================================
echo "[10] Anti-block filters (STATIC list - safe for DPI networks)..."
cat << 'ANTIBLOCK' > /etc/dnsmasq.d/anti-block.conf
# Фиксированный список IP-заглушек провайдеров (только DNS-подмена)
# НЕ обновляется автоматически - безопасно для сетей с DPI (ТСПУ)!

no-negcache

# Ростелеком / Центральный Телеграф
bogus-nxdomain=185.179.189.20
bogus-nxdomain=195.208.1.1
bogus-nxdomain=95.167.13.50

# Билайн (ВымпелКом)
bogus-nxdomain=95.182.120.241

# Дом.ru (ЭР-Телеком)
bogus-nxdomain=87.241.223.133

# Онлайм / Ростелеком
bogus-nxdomain=77.37.254.90

# ТТК (ТрансТелеКом)
bogus-nxdomain=62.33.207.195

# SkyDNS / MNT-NET
bogus-nxdomain=45.155.204.190

# Cloud4Y / Selectel
bogus-nxdomain=37.230.192.51

# Нулевые адреса
bogus-nxdomain=0.0.0.0
bogus-nxdomain=127.0.0.1
ANTIBLOCK

# ============================================================
# 11. SYSCTL TUNING
# ============================================================
echo "[11] Sysctl tuning..."
modprobe nf_conntrack 2>/dev/null
modprobe xt_conntrack 2>/dev/null
SYSFILE="/etc/sysctl.d/99-custom.conf"
touch "$SYSFILE"
for param in \
    "net.netfilter.nf_conntrack_max=65536" \
    "net.ipv4.tcp_fastopen=3" \
    "net.ipv4.tcp_fin_timeout=15" \
    "net.core.somaxconn=1024" \
    "net.ipv4.tcp_keepalive_time=300" \
    "net.ipv4.tcp_keepalive_intvl=15" \
    "net.ipv4.tcp_keepalive_probes=5" \
    "net.core.rmem_max=2097152" \
    "net.core.wmem_max=2097152"; do
    key=$(echo "$param" | cut -d= -f1)
    sed -i "/^$key/d" "$SYSFILE" 2>/dev/null
    sed -i "/^$key/d" /etc/sysctl.conf 2>/dev/null
    echo "$param" >> "$SYSFILE"
    sysctl -w "$param" >/dev/null 2>&1
done

# ============================================================
# 12. HOTPLUG FOR TAILSCALE
# ============================================================
echo "[12] Hotplug..."
rm -rf /tmp/tailscale_ntp_lock
rm -f /etc/hotplug.d/ntp/99-tailscale
cat << 'HOTPLUG' > /etc/hotplug.d/ntp/99-tailscale
#!/bin/sh
[ "$ACTION" = "step" ] || [ "$ACTION" = "stratum" ] || exit 0
UPTIME=$(cut -d. -f1 /proc/uptime)
[ "$UPTIME" -lt 600 ] && mkdir /tmp/tailscale_ntp_lock 2>/dev/null && /etc/init.d/tailscale restart >/dev/null 2>&1
HOTPLUG
chmod +x /etc/hotplug.d/ntp/99-tailscale

# ============================================================
# 13. СОЗДАНИЕ СКРИПТА ОТКАТА
# ============================================================
echo "[13] Creating rollback script..."
cat << 'ROLLBACK' > /root/rollback-dns.sh
#!/bin/sh
echo "============================================================"
echo "=== ROLLBACK DNS SETUP v10.1 ==="
echo "============================================================"
echo ""

BACKUP="/etc/config/backup-pre-dns-v9"

if [ ! -d "$BACKUP" ]; then
    echo "[!] Backup not found: $BACKUP"
    echo "[!] Cannot rollback!"
    exit 1
fi

echo "[1] Restoring configs from $BACKUP..."
cp "$BACKUP/dhcp.bak" /etc/config/dhcp 2>/dev/null && echo "  [+] dhcp"
cp "$BACKUP/firewall.bak" /etc/config/firewall 2>/dev/null && echo "  [+] firewall"
cp "$BACKUP/https-dns-proxy.bak" /etc/config/https-dns-proxy 2>/dev/null && echo "  [+] https-dns-proxy"
cp "$BACKUP/system.bak" /etc/config/system 2>/dev/null && echo "  [+] system"
[ -f "$BACKUP/crontabs.bak" ] && cp "$BACKUP/crontabs.bak" /etc/crontabs/root && echo "  [+] crontabs"

echo ""
echo "[2] Removing files created by setup..."
rm -f /etc/dnsmasq.d/anti-block.conf
rm -f /etc/dnsmasq.d/.bogus-old
rm -f /etc/sysctl.d/99-custom.conf
rm -f /etc/hotplug.d/ntp/99-tailscale
rm -f /usr/bin/update-bogus-dns
echo "  [+] Files removed"

echo ""
echo "[3] Resetting sysctl in RAM..."
sysctl -p /etc/sysctl.conf >/dev/null 2>&1
echo "  [+] Sysctl reset"

echo ""
echo "[4] Restarting services..."
/etc/init.d/firewall restart 2>/dev/null
/etc/init.d/https-dns-proxy restart 2>/dev/null
/etc/init.d/dnsmasq restart 2>/dev/null
/etc/init.d/sysntpd restart 2>/dev/null
/etc/init.d/cron restart 2>/dev/null
echo "  [+] Services restarted"

echo ""
echo "============================================================"
echo "✅ ROLLBACK COMPLETE"
echo "============================================================"
echo ""
echo "Проверка:"
echo "  nslookup ya.ru 127.0.0.1"
echo "  uci show dhcp.@dnsmasq[0].server"
echo ""
echo "Для полного сброса: reboot"
ROLLBACK
chmod +x /root/rollback-dns.sh
echo "[+] Rollback script: /root/rollback-dns.sh"

# ============================================================
# 14. RESTART SERVICES
# ============================================================
echo "[14] Restarting services..."
/etc/init.d/sysntpd enable 2>/dev/null
/etc/init.d/https-dns-proxy enable 2>/dev/null
/etc/init.d/dnsmasq enable 2>/dev/null
/etc/init.d/cron enable 2>/dev/null
[ -f "$f_tg" ] && /etc/init.d/tg-ws-proxy-go enable 2>/dev/null
[ -f "$f_ts" ] && /etc/init.d/tailscale enable 2>/dev/null

/etc/init.d/sysntpd restart 2>/dev/null
/etc/init.d/https-dns-proxy restart
sleep 2
/etc/init.d/dnsmasq stop
sleep 2
/etc/init.d/dnsmasq start
/etc/init.d/cron restart 2>/dev/null
sleep 3
[ -f "$f_tg" ] && /etc/init.d/tg-ws-proxy-go restart 2>/dev/null
[ -f "$f_ts" ] && /etc/init.d/tailscale restart 2>/dev/null

# ============================================================
# 15. VERIFICATION
# ============================================================
echo ""
echo "============================================================"
echo "=== VERIFICATION ==="
echo "============================================================"

echo ""
echo "--- ISP DNS Detection ---"
ISP_DNS_LIST=$(grep -E '^nameserver[[:space:]]+[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+' /tmp/resolv.conf.d/resolv.conf.auto 2>/dev/null | awk '{print $2}' | head -n2)
if [ -n "$ISP_DNS_LIST" ]; then
    for dns in $ISP_DNS_LIST; do
        echo "[✓] ISP DNS: $dns"
    done
else
    echo "[!] ISP IPv4 DNS not detected"
fi

echo ""
echo "--- DoH Speed Test ---"
for item in \
    "https://dns.mafioznik.com/dns-query:Mafioznik:5053" \
    "https://dns.comss.one/dns-query:Comss.one:5054" \
    "https://dns.astrakat.ru/dns-query:Astrakat:5055" \
    "https://dns.malw.link/dns-query:Malw.link:5056" \
    "https://dns.comss.ru/dns-query:Comss.ru:5057" \
    "https://dns.vppay.ru/dns-query:VPPay:5058" \
    "https://common.dot.dns.yandex.net/dns-query:Yandex:5059"; do
    
    url=$(echo "$item" | cut -d: -f1-2)
    name=$(echo "$item" | cut -d: -f3)
    port=$(echo "$item" | cut -d: -f4)
    
    time_ms=$(curl -s -o /dev/null -w "%{time_total}" --max-time 5 \
        "$url?name=chatgpt.com&type=A" \
        -H "Accept: application/dns-json" 2>/dev/null)
    
    if [ -n "$time_ms" ] && [ "$time_ms" != "0.000000" ]; then
        ms=$(echo "$time_ms" | awk '{printf "%.0f", $1 * 1000}')
        echo "[✓] $name (port $port): ${ms}ms"
    else
        echo "[✗] $name (port $port): NO ANSWER"
    fi
done

echo ""
echo "--- DNS Resolution ---"
real_ip=0; proxy_ip=0; stub_ip=0; no_answer=0

stub_pattern="^(45\.155\.204\.190|95\.182\.120\.241|37\.230\.192\.51|77\.37\.254\.90|87\.241\.223\.133|95\.167\.13\.50|62\.33\.207\.195|195\.208\.1\.1|185\.179\.189\.20|0\.0\.0\.0|127\.0\.0\.1)$"
proxy_pattern="^(45\.88\.|91\.207\.|185\.246\.|8\.6\.112\.|194\.87\.|85\.143\.|109\.94\.|5\.61\.|46\.17\.|31\.129\.|45\.12\.|91\.215\.|185\.221\.|45\.141\.|45\.138\.)"

for dom in ya.ru chatgpt.com claude.ai gemini.google.com youtube.com github.com discord.com linkedin.com instagram.com twitter.com; do
    ip=$(nslookup "$dom" 127.0.0.1 2>/dev/null | grep -vE "127\.0\.0\.|0\.0\.0\.0" | grep -oE '([0-9]{1,3}\.){3}[0-9]{1,3}' | head -n1)
    
    if [ -z "$ip" ]; then
        status="❌"; no_answer=$((no_answer + 1))
    elif echo "$ip" | grep -qE "$stub_pattern"; then
        status="🚫"; stub_ip=$((stub_ip + 1))
    elif echo "$ip" | grep -qE "$proxy_pattern"; then
        status="🔄"; proxy_ip=$((proxy_ip + 1))
    else
        status="✅"; real_ip=$((real_ip + 1))
    fi
    printf "  %-25s → %-18s %s\n" "$dom" "${ip:-—}" "$status"
done

echo ""
echo "============================================================"
echo "=== FINAL STATISTICS ==="
echo "============================================================"
total=$((real_ip + proxy_ip + stub_ip + no_answer))
[ $total -eq 0 ] && total=1

echo "✅ Real IPs:   $real_ip ($((real_ip * 100 / total))%)"
echo "🔄 Proxy IPs:  $proxy_ip ($((proxy_ip * 100 / total))%)"
echo "🚫 RKN Stubs:  $stub_ip ($((stub_ip * 100 / total))%)  ← SHOULD BE 0!"
echo "❌ No Answer:  $no_answer ($((no_answer * 100 / total))%)"
echo ""

[ $stub_ip -eq 0 ] && echo "🏆 PERFECT: 0 RKN stubs" || echo "⚠️  WARNING: $stub_ip stubs"

echo ""
echo "============================================================"
echo "=== DONE v10.1 FINAL STABLE ==="
echo "============================================================"
echo "OpenWrt: $OPENWRT_VERSION | FW: $FW_VERSION | Pkg: $PKG"
echo ""
echo "SmartDNS (5053-5058): Mafioznik + Comss.one + Astrakat"
echo "                      + Malw + Comss.ru + VPPay"
echo "Yandex RU (5059): only .ru/.su/.рф"
echo ""
echo "📦 Backup:   $BACKUP_ACTUAL"
echo "🔄 Rollback: sh /root/rollback-dns.sh"
echo "============================================================"
EOF

sh /tmp/dns_setup.sh
rm -f /tmp/dns_setup.sh
