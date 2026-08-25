cat << 'EOF' > /tmp/dns_final.sh
#!/bin/sh
echo "=== OPENWRT DNS v10.3.1-FINAL ==="

# 00. BACKUP (с автоочисткой старых)
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_ACTUAL="/etc/config/backup-dns-$TIMESTAMP"
mkdir -p "$BACKUP_ACTUAL"
if [ ! -d "/etc/config/backup-original" ]; then
    mkdir -p /etc/config/backup-original
    cp /etc/config/dhcp /etc/config/backup-original/dhcp.bak 2>/dev/null
    cp /etc/config/firewall /etc/config/backup-original/firewall.bak 2>/dev/null
    cp /etc/config/https-dns-proxy /etc/config/backup-original/https-dns-proxy.bak 2>/dev/null
    cp /etc/config/system /etc/config/backup-original/system.bak 2>/dev/null
    [ -f /etc/crontabs/root ] && cp /etc/crontabs/root /etc/config/backup-original/crontabs.bak
    echo "[+] FIRST backup: /etc/config/backup-original"
fi
cp /etc/config/dhcp "$BACKUP_ACTUAL/dhcp.bak" 2>/dev/null
cp /etc/config/firewall "$BACKUP_ACTUAL/firewall.bak" 2>/dev/null
cp /etc/config/https-dns-proxy "$BACKUP_ACTUAL/https-dns-proxy.bak" 2>/dev/null
cp /etc/config/system "$BACKUP_ACTUAL/system.bak" 2>/dev/null
[ -f /etc/crontabs/root ] && cp /etc/crontabs/root "$BACKUP_ACTUAL/crontabs.bak"
ln -sfn "$BACKUP_ACTUAL" /etc/config/backup-pre-dns-v9
echo "[+] Backup: $BACKUP_ACTUAL"
(cd /etc/config && ls -dt backup-dns-* 2>/dev/null | tail -n +2 | xargs rm -rf 2>/dev/null)

# 0. PRE-CHECKS
[ -f /etc/openwrt_release ] && OPENWRT_VERSION=$(grep DISTRIB_RELEASE /etc/openwrt_release | cut -d= -f2 | tr -d "'\"")
[ -z "$OPENWRT_VERSION" ] && OPENWRT_VERSION="Unknown"
command -v apk >/dev/null 2>&1 && PKG="apk" || PKG="opkg"
[ -f /usr/share/fw4/helpers.sh ] && FW_VERSION="fw4" || FW_VERSION="fw3"
mkdir -p /etc/dnsmasq.d /etc/sysctl.d /etc/hotplug.d/ntp /usr/bin
echo "[+] OpenWrt: $OPENWRT_VERSION | FW: $FW_VERSION | Pkg: $PKG"

# 0b. CLEANUP OLD ARTIFACTS
echo "[0b] Cleaning ALL old artifacts..."
rm -f /etc/dnsmasq.d/telemetry.conf /etc/dnsmasq.d/.bogus-old /usr/bin/update-bogus-dns
[ -f /etc/crontabs/root ] && sed -i '/update-bogus-dns/d' /etc/crontabs/root

# 1. MTU FIX
uci -q set firewall.@defaults[0].mtu_fix='1'
WAN_SECTION=$(uci show firewall 2>/dev/null | grep -m1 "\.name='wan'" | cut -d. -f1,2)
[ -n "$WAN_SECTION" ] && uci -q set "${WAN_SECTION}.mtu_fix=1"
uci commit firewall

# 2. NTP REDIRECT
LAN_IP=$(uci -q get network.lan.ipaddr | cut -d'/' -f1 | awk '{print $1}')
[ -z "$LAN_IP" ] || [ "$LAN_IP" = "0.0.0.0" ] && LAN_IP="192.168.1.1"
for opt in $(uci -q get dhcp.lan.dhcp_option | tr ' ' '\n' | grep '^42,'); do uci -q del_list dhcp.lan.dhcp_option="$opt"; done
uci add_list dhcp.lan.dhcp_option="42,$LAN_IP"
uci commit dhcp
for sec in $(uci show firewall 2>/dev/null | grep -E "dest_port='123'|src_dport='123'" | cut -d. -f2 | cut -d= -f1 | sort -u); do uci -q delete firewall."$sec"; done
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

# 3. GO OPTIMIZATION
f_tg="/etc/init.d/tg-ws-proxy-go"; f_ts="/etc/init.d/tailscale"
if [ -f "$f_tg" ]; then
    sed -i '/GOMAXPROCS/d; /GOMEMLIMIT/d; /GOGC/d' "$f_tg"
    grep -q "procd_open_instance" "$f_tg" && awk '/procd_open_instance/ {print; print "    procd_set_param env GOMAXPROCS=1 GOMEMLIMIT=50MiB"; next} 1' "$f_tg" > /tmp/tg.tmp && mv /tmp/tg.tmp "$f_tg"
fi
if [ -f "$f_ts" ]; then
    sed -i '/GOMAXPROCS/d; /GOMEMLIMIT/d; /GOGC/d' "$f_ts"
    grep -q "procd_open_instance" "$f_ts" && awk '/procd_open_instance/ {print; print "    procd_set_param env GOMEMLIMIT=85MiB"; next} 1' "$f_ts" > /tmp/ts.tmp && mv /tmp/ts.tmp "$f_ts"
fi

# 4. CRON CLEANUP
[ -f /etc/crontabs/root ] && sed -i '/dnsmasq/d; /https-dns-proxy/d; /tailscale/d; /update-bogus-dns/d' /etc/crontabs/root

# 5. NTP SERVERS
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

# 6. INSTALL PACKAGES (добавлен curl для тестов)
command -v https-dns-proxy >/dev/null 2>&1 && command -v curl >/dev/null 2>&1 || {
    [ "$PKG" = "apk" ] && apk update && apk add https-dns-proxy ca-certificates curl
    [ "$PKG" = "opkg" ] && opkg update && opkg install https-dns-proxy ca-certificates curl
}
command -v https-dns-proxy >/dev/null 2>&1 || { echo "[!] Install FAILED"; exit 1; }

# 7. DoH RESOLVERS (БЕЗ Cloudflare/Google/Quad9)
echo "[7] Configuring DoH (SAFE bootstrap)..."
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
    uci -q delete https-dns-proxy.@https-dns-proxy[-1].bootstrap_dns 2>/dev/null
    uci add_list https-dns-proxy.@https-dns-proxy[-1].bootstrap_dns='77.88.8.8'
    uci add_list https-dns-proxy.@https-dns-proxy[-1].bootstrap_dns='94.140.14.14'
done
uci add https-dns-proxy https-dns-proxy
uci set https-dns-proxy.@https-dns-proxy[-1].listen_addr='127.0.0.1'
uci set https-dns-proxy.@https-dns-proxy[-1].listen_port='5059'
uci set https-dns-proxy.@https-dns-proxy[-1].resolver_url='https://common.dot.dns.yandex.net/dns-query'
uci -q delete https-dns-proxy.@https-dns-proxy[-1].bootstrap_dns 2>/dev/null
uci add_list https-dns-proxy.@https-dns-proxy[-1].bootstrap_dns='77.88.8.8'
uci commit https-dns-proxy

# 9. DNSMASQ TLD SPLIT
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

# 10. STATIC ANTI-BLOCK (безопасно для DPI)
cat << 'ANTIBLOCK' > /etc/dnsmasq.d/anti-block.conf
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

# 11. SYSCTL
modprobe nf_conntrack 2>/dev/null
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
    echo "$param" >> "$SYSFILE"
    sysctl -w "$param" >/dev/null 2>&1
done

# 12. HOTPLUG TAILSCALE
rm -rf /tmp/tailscale_ntp_lock
rm -f /etc/hotplug.d/ntp/99-tailscale
cat << 'HOTPLUG' > /etc/hotplug.d/ntp/99-tailscale
#!/bin/sh
[ "$ACTION" = "step" ] || [ "$ACTION" = "stratum" ] || exit 0
UPTIME=$(cut -d. -f1 /proc/uptime)
[ "$UPTIME" -lt 600 ] && mkdir /tmp/tailscale_ntp_lock 2>/dev/null && /etc/init.d/tailscale restart >/dev/null 2>&1
HOTPLUG
chmod +x /etc/hotplug.d/ntp/99-tailscale

# 13. ROLLBACK SCRIPT
cat << 'ROLLBACK' > /root/rollback-dns.sh
#!/bin/sh
BACKUP="/etc/config/backup-pre-dns-v9"
ORIGINAL="/etc/config/backup-original"
if [ -d "$BACKUP" ]; then SOURCE="$BACKUP"
elif [ -d "$ORIGINAL" ]; then SOURCE="$ORIGINAL"
else echo "[!] No backup found!"; exit 1; fi
echo "=== ROLLBACK from $SOURCE ==="
cp "$SOURCE/dhcp.bak" /etc/config/dhcp 2>/dev/null
cp "$SOURCE/firewall.bak" /etc/config/firewall 2>/dev/null
cp "$SOURCE/https-dns-proxy.bak" /etc/config/https-dns-proxy 2>/dev/null
cp "$SOURCE/system.bak" /etc/config/system 2>/dev/null
[ -f "$SOURCE/crontabs.bak" ] && cp "$SOURCE/crontabs.bak" /etc/crontabs/root
rm -f /etc/dnsmasq.d/anti-block.conf /etc/dnsmasq.d/.bogus-old
rm -f /etc/sysctl.d/99-custom.conf /etc/hotplug.d/ntp/99-tailscale
rm -f /usr/bin/update-bogus-dns /usr/bin/add-stub /usr/bin/dns-diag
sysctl -p /etc/sysctl.conf >/dev/null 2>&1
/etc/init.d/firewall restart 2>/dev/null
/etc/init.d/https-dns-proxy restart 2>/dev/null
/etc/init.d/dnsmasq restart 2>/dev/null
/etc/init.d/sysntpd restart 2>/dev/null
/etc/init.d/cron restart 2>/dev/null
echo "✅ ROLLBACK COMPLETE (reboot recommended)"
ROLLBACK
chmod +x /root/rollback-dns.sh

# 14. REQUEST_TIMEOUT
for i in 0 1 2 3 4 5 6; do
    uci -q set https-dns-proxy.@https-dns-proxy[$i].request_timeout='2' 2>/dev/null
done
uci commit https-dns-proxy

# 15. ADD-STUB UTILITY (с якорем $)
cat << 'ADDSTUB' > /usr/bin/add-stub
#!/bin/sh
[ -z "$1" ] && { echo "Usage: add-stub <IP>"; exit 1; }
BF="/etc/dnsmasq.d/anti-block.conf"
grep -q "bogus-nxdomain=$1$" "$BF" 2>/dev/null && { echo "[!] Already in list"; exit 0; }
echo "bogus-nxdomain=$1" >> "$BF" && /etc/init.d/dnsmasq restart
echo "[+] Added: $1"
ADDSTUB
chmod +x /usr/bin/add-stub

# 16. DNS-DIAG UTILITY (исправлен ложный 127.0.0.1)
cat << 'DIAG' > /usr/bin/dns-diag
#!/bin/sh
echo "=== DNS DIAG ==="
for item in "5053:Mafioznik" "5054:Comss.one" "5055:Astrakat" "5056:Malw.link" "5057:Comss.ru" "5058:VPPay" "5059:Yandex"; do
    port=$(echo "$item" | cut -d: -f1); name=$(echo "$item" | cut -d: -f2)
    ip=$(nslookup chatgpt.com 127.0.0.1#$port 2>/dev/null | grep -vE '127\.0\.0\.|0\.0\.0\.0' | grep -oE '([0-9]{1,3}\.){3}[0-9]{1,3}' | tail -n1)
    printf "%-12s (port %s) → %s\n" "$name" "$port" "${ip:-NO_ANSWER}"
done
echo "--- Resolution ---"
for dom in ya.ru chatgpt.com youtube.com instagram.com linkedin.com; do
    ip=$(nslookup "$dom" 127.0.0.1 2>/dev/null | grep -vE '127\.0\.0\.|0\.0\.0\.0' | grep -oE '([0-9]{1,3}\.){3}[0-9]{1,3}' | head -n1)
    printf "%-20s → %s\n" "$dom" "${ip:-NO_ANSWER}"
done
DIAG
chmod +x /usr/bin/dns-diag

# 17. RESTART SERVICES
echo "[17] Restarting services..."
/etc/init.d/sysntpd enable 2>/dev/null
/etc/init.d/https-dns-proxy enable 2>/dev/null
/etc/init.d/dnsmasq enable 2>/dev/null
/etc/init.d/cron enable 2>/dev/null
[ -f "$f_tg" ] && /etc/init.d/tg-ws-proxy-go enable 2>/dev/null
[ -f "$f_ts" ] && /etc/init.d/tailscale enable 2>/dev/null
/etc/init.d/sysntpd restart 2>/dev/null
/etc/init.d/https-dns-proxy restart
sleep 3
/etc/init.d/dnsmasq stop
sleep 2
/etc/init.d/dnsmasq start
/etc/init.d/cron restart 2>/dev/null
sleep 3
[ -f "$f_tg" ] && /etc/init.d/tg-ws-proxy-go restart 2>/dev/null
[ -f "$f_ts" ] && /etc/init.d/tailscale restart 2>/dev/null

# 18. VERIFICATION
echo ""
echo "=== VERIFICATION ==="
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
    if command -v curl >/dev/null 2>&1; then
        time_ms=$(curl -s -o /dev/null -w "%{time_total}" --max-time 5 "$url?name=chatgpt.com&type=A" -H "Accept: application/dns-json" 2>/dev/null)
        if [ -n "$time_ms" ] && [ "$time_ms" != "0.000000" ]; then
            ms=$(echo "$time_ms" | awk '{printf "%.0f", $1 * 1000}')
            echo "[✓] $name ($port): ${ms}ms"
        else
            echo "[✗] $name ($port): NO ANSWER"
        fi
    else
        echo "[!] curl not available for speedtest"
    fi
done
echo ""
real_ip=0; proxy_ip=0; stub_ip=0; no_answer=0
stub_pattern="^(45\.155\.204\.190|95\.182\.120\.241|37\.230\.192\.51|77\.37\.254\.90|87\.241\.223\.133|95\.167\.13\.50|62\.33\.207\.195|195\.208\.1\.1|185\.179\.189\.20|0\.0\.0\.0|127\.0\.0\.1)$"
proxy_pattern="^(45\.88\.|91\.207\.|185\.246\.|8\.6\.112\.|194\.87\.|85\.143\.|109\.94\.|5\.61\.|46\.17\.|31\.129\.|45\.12\.|91\.215\.|185\.221\.|45\.141\.|45\.138\.)"
for dom in ya.ru chatgpt.com claude.ai gemini.google.com youtube.com github.com discord.com linkedin.com instagram.com twitter.com; do
    ip=$(nslookup "$dom" 127.0.0.1 2>/dev/null | grep -vE "127\.0\.0\.|0\.0\.0\.0" | grep -oE '([0-9]{1,3}\.){3}[0-9]{1,3}' | head -n1)
    if [ -z "$ip" ]; then status="❌"; no_answer=$((no_answer + 1))
    elif echo "$ip" | grep -qE "$stub_pattern"; then status="🚫"; stub_ip=$((stub_ip + 1))
    elif echo "$ip" | grep -qE "$proxy_pattern"; then status="🔄"; proxy_ip=$((proxy_ip + 1))
    else status="✅"; real_ip=$((real_ip + 1)); fi
    printf "  %-25s → %-18s %s\n" "$dom" "${ip:-—}" "$status"
done
total=$((real_ip + proxy_ip + stub_ip + no_answer))
[ $total -eq 0 ] && total=1
echo ""
echo "✅ Real: $real_ip ($((real_ip * 100 / total))%)"
echo "🔄 Proxy: $proxy_ip ($((proxy_ip * 100 / total))%)"
echo "🚫 Stubs: $stub_ip ($((stub_ip * 100 / total))%) ← SHOULD BE 0!"
echo "❌ No Ans: $no_answer ($((no_answer * 100 / total))%)"
[ $stub_ip -eq 0 ] && echo "🏆 PERFECT" || echo "⚠️  WARNING"
echo ""
echo "=== DONE v10.3.1-FINAL ==="
echo "🔄 Rollback: sh /root/rollback-dns.sh"
echo "🛠️  Tools: dns-diag, add-stub <IP>"
EOF
sh /tmp/dns_final.sh
rm -f /tmp/dns_final.sh
