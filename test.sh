cat << 'EOF' > /usr/bin/dns-manager
#!/bin/sh

CONFIG_FILE="/root/.dns-manager.conf"
DNS_CATALOG="/root/.dns-catalog.conf"
TEST_RESULTS="/root/.dns-test-results.conf"
VERSION="3.0-FINAL"

# Цвета
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# ============================================================
# КАТАЛОГ DNS (легко расширять)
# Формат: id|Название|URL
# ============================================================
create_catalog() {
    cat > "$DNS_CATALOG" << 'CATALOG'
mafioznik|Mafioznik|https://dns.mafioznik.com/dns-query
comss_one|Comss.one|https://dns.comss.one/dns-query
astrakat|Astrakat|https://dns.astrakat.ru/dns-query
malw_link|Malw.link|https://dns.malw.link/dns-query
comss_ru|Comss.ru|https://dns.comss.ru/dns-query
vppay|VPPay|https://dns.vppay.ru/dns-query
yandex|Yandex|https://common.dot.dns.yandex.net/dns-query
yandex_safe|Yandex Safe|https://safe.dot.dns.yandex.net/dns-query
yandex_family|Yandex Family|https://family.dot.dns.yandex.net/dns-query
adguard|AdGuard DoH|https://dns.adguard.com/dns-query
adguard_family|AdGuard Family|https://dns-family.adguard.com/dns-query
adguard_unfiltered|AdGuard Unfiltered|https://unfiltered.adguard-dns.com/dns-query
cloudflare|Cloudflare 1.1.1.1|https://cloudflare-dns.com/dns-query
cloudflare_malware|Cloudflare Malware|https://security.cloudflare-dns.com/dns-query
cloudflare_family|Cloudflare Family|https://family.cloudflare-dns.com/dns-query
google|Google 8.8.8.8|https://dns.google/dns-query
quad9|Quad9|https://dns.quad9.net/dns-query
quad9_unsecured|Quad9 Unsecured|https://dns10.quad9.net/dns-query
nextdns|NextDNS|https://dns.nextdns.io/dns-query
controld|ControlD|https://freedns.controld.com/p0/dns-query
opendns|OpenDNS|https://doh.opendns.com/dns-query
opendns_family|OpenDNS Family|https://doh.familyshield.opendns.com/dns-query
cleanbrowsing|CleanBrowsing|https://doh.cleanbrowsing.org/doh/family-filter/dns-query
cleanbrowsing_adult|CleanBrowsing Adult|https://doh.cleanbrowsing.org/doh/adult-filter/dns-query
dns_sb|DNS.SB|https://doh.dns.sb/dns-query
mullvad|Mullvad DoH|https://doh.mullvad.net/dns-query
mullvad_adblock|Mullvad Adblock|https://adblock.doh.mullvad.net/dns-query
dns_403|DNS.403|https://dns.403.online/dns-query
bluedns|BlueDNS|https://dns.bluedns.io/dns-query
neutrdns|Neutrdns|https://doh.neutrdns.org/dns-query
CATALOG
}

# ============================================================
# ИНИЦИАЛИЗАЦИЯ (чистый/грязный роутер)
# ============================================================
init_system() {
    echo -e "${BLUE}=== Инициализация системы ===${NC}"

    # Определение пакетного менеджера
    if command -v apk >/dev/null 2>&1; then
        PKG="apk"
    elif command -v opkg >/dev/null 2>&1; then
        PKG="opkg"
    else
        echo -e "${RED}[!] Пакетный менеджер не найден!${NC}"
        exit 1
    fi

    # Установка необходимых пакетов
    if ! command -v https-dns-proxy >/dev/null 2>&1 || ! command -v curl >/dev/null 2>&1; then
        echo "[*] Установка пакетов..."
        if [ "$PKG" = "apk" ]; then
            apk update && apk add https-dns-proxy ca-certificates curl bind-tools
        else
            opkg update && opkg install https-dns-proxy ca-certificates curl bind-dig
        fi
    fi

    # Очистка артефактов старых версий
    echo "[*] Очистка старых артефактов..."
    rm -f /etc/dnsmasq.d/telemetry.conf
    rm -f /etc/dnsmasq.d/.bogus-old
    rm -f /usr/bin/update-bogus-dns
    [ -f /etc/crontabs/root ] && sed -i '/update-bogus-dns/d' /etc/crontabs/root

    # Создание каталога если нет
    [ ! -f "$DNS_CATALOG" ] && create_catalog

    echo -e "${GREEN}[✓] Система готова${NC}"
}

# ============================================================
# Загрузка и сохранение конфига
# ============================================================
load_config() {
    if [ -f "$CONFIG_FILE" ]; then
        . "$CONFIG_FILE"
    else
        SLOT_1="mafioznik"
        SLOT_2="comss_one"
        SLOT_3="astrakat"
        SLOT_4="malw_link"
        SLOT_5="comss_ru"
        SLOT_6="vppay"
        SLOT_RU="yandex"
        BOOTSTRAP_DNS="77.88.8.8,77.88.8.1,94.140.14.14,94.140.15.15"
        TLD_RU_ENABLED="1"
        BLOCK_QUIC="0"
        save_config
    fi
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
BOOTSTRAP_DNS="$BOOTSTRAP_DNS"
TLD_RU_ENABLED="$TLD_RU_ENABLED"
BLOCK_QUIC="$BLOCK_QUIC"
CONF
}

get_dns_name() {
    id="$1"
    [ -z "$id" ] && { echo "(пусто)"; return; }
    result=$(grep "^${id}|" "$DNS_CATALOG" | cut -d'|' -f2)
    [ -z "$result" ] && result="(кастом)"
    echo "$result"
}

# ============================================================
# ТЕСТ ВСЕХ DNS ИЗ КАТАЛОГА
# ============================================================
menu_test_dns() {
    clear
    echo -e "${BLUE}╔══════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║     Тестирование всех DNS               ║${NC}"
    echo -e "${BLUE}╚══════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "${YELLOW}Проверка доступности и скорости...${NC}"
    echo ""

    printf "%-25s %-10s %-10s %s\\n" "DNS" "Статус" "Скорость" "Примечание"
    echo "------------------------------------------------------------------------"

    > "$TEST_RESULTS"

    while IFS='|' read -r id name url; do
        [ -z "$id" ] && continue

        time_ms=$(curl -s -o /dev/null -w "%{time_total}" --max-time 5 \
            "${url}?name=google.com&type=A" \
            -H "Accept: application/dns-json" 2>/dev/null)

        if [ -n "$time_ms" ] && [ "$time_ms" != "0.000000" ]; then
            ms=$(echo "$time_ms" | awk '{printf "%.0f", $1 * 1000}')
            if [ "$ms" -lt 100 ]; then
                status="${GREEN}OK${NC}"
                note="Быстрый"
            elif [ "$ms" -lt 300 ]; then
                status="${GREEN}OK${NC}"
                note="Нормальный"
            else
                status="${YELLOW}OK${NC}"
                note="Медленный"
            fi
            printf "%-25s %-10b %-10s %s\\n" "$name" "$status" "${ms}ms" "$note"
            echo "${id}|${ms}|OK" >> "$TEST_RESULTS"
        else
            printf "%-25s ${RED}FAIL${NC}     %-10s %s\\n" "$name" "-" "Заблокирован/недоступен"
            echo "${id}|0|FAIL" >> "$TEST_RESULTS"
        fi
    done < "$DNS_CATALOG"

    echo ""
    echo "------------------------------------------------------------------------"
    echo -e "${YELLOW}Результаты сохранены в $TEST_RESULTS${NC}"
    echo ""

    total=$(wc -l < "$TEST_RESULTS")
    ok=$(grep -c "|OK" "$TEST_RESULTS")
    fail=$(grep -c "|FAIL" "$TEST_RESULTS")
    echo -e "Всего: $total | ${GREEN}Работает: $ok${NC} | ${RED}Не работает: $fail${NC}"

    echo ""
    read -p "Нажмите Enter..." _
}

# ============================================================
# Выбор DNS для слота (с учётом теста)
# ============================================================
select_dns_for_slot() {
    slot_num="$1"

    while true; do
        clear
        echo -e "${BLUE}╔══════════════════════════════════════════╗${NC}"
        echo -e "${BLUE}║     Выбор DNS для слота #$slot_num             ║${NC}"
        echo -e "${BLUE}╚══════════════════════════════════════════╝${NC}"
        echo ""
        echo "Доступные DNS (с результатами теста):"
        echo ""

        i=1
        while IFS='|' read -r id name url; do
            [ -z "$id" ] && continue

            test_result=$(grep "^${id}|" "$TEST_RESULTS" 2>/dev/null | cut -d'|' -f2,3)
            if [ -n "$test_result" ]; then
                ms=$(echo "$test_result" | cut -d'|' -f1)
                status=$(echo "$test_result" | cut -d'|' -f2)
                if [ "$status" = "OK" ]; then
                    status_str="${GREEN}${ms}ms${NC}"
                else
                    status_str="${RED}FAIL${NC}"
                fi
            else
                status_str="${YELLOW}нет теста${NC}"
            fi

            printf "  %2d) %-25s [%b]\\n" "$i" "$name" "$status_str"
            i=$((i + 1))
        done < "$DNS_CATALOG"

        echo ""
        echo "  ${CYAN}99) Очистить слот${NC}"
        echo "  ${CYAN}98) Ввести свой URL${NC}"
        echo "  ${CYAN}0)  Отмена${NC}"
        echo ""
        echo -n "Выбор: "
        read -r choice

        case "$choice" in
            99)
                eval "SLOT_${slot_num}=\"\""
                save_config
                return
                ;;
            98)
                echo "Введите URL DoH (https://...):"
                read -r custom_url
                eval "SLOT_${slot_num}=\"custom:${custom_url}\""
                save_config
                return
                ;;
            0) return ;;
            *)
                total=$(grep -c '^' "$DNS_CATALOG")
                if [ "$choice" -ge 1 ] 2>/dev/null && [ "$choice" -le "$total" ] 2>/dev/null; then
                    selected_id=$(sed -n "${choice}p" "$DNS_CATALOG" | cut -d'|' -f1)

                    test_status=$(grep "^${selected_id}|" "$TEST_RESULTS" 2>/dev/null | cut -d'|' -f3)
                    if [ "$test_status" = "FAIL" ]; then
                        echo -e "${YELLOW}[!] Внимание: этот DNS не работает по результатам теста${NC}"
                        echo -n "Продолжить? (д/н): "
                        read -r confirm
                        [ "$confirm" != "д" ] && [ "$confirm" != "y" ] && continue
                    fi

                    eval "SLOT_${slot_num}=\"$selected_id\""
                    save_config
                    return
                else
                    echo -e "${RED}[!] Неверный выбор${NC}"
                    sleep 1
                fi
                ;;
        esac
    done
}

# ============================================================
# Меню настройки слотов
# ============================================================
menu_slots() {
    while true; do
        clear
        echo -e "${BLUE}╔══════════════════════════════════════════╗${NC}"
        echo -e "${BLUE}║     Настройка слотов DNS                ║${NC}"
        echo -e "${BLUE}╚══════════════════════════════════════════╝${NC}"
        echo ""
        echo -e "${YELLOW}Слоты 1-6: Весь интернет${NC}"
        echo "  1) Слот 1 (порт 5053): $(get_dns_name "$SLOT_1")"
        echo "  2) Слот 2 (порт 5054): $(get_dns_name "$SLOT_2")"
        echo "  3) Слот 3 (порт 5055): $(get_dns_name "$SLOT_3")"
        echo "  4) Слот 4 (порт 5056): $(get_dns_name "$SLOT_4")"
        echo "  5) Слот 5 (порт 5057): $(get_dns_name "$SLOT_5")"
        echo "  6) Слот 6 (порт 5058): $(get_dns_name "$SLOT_6")"
        echo ""
        echo -e "${YELLOW}Слот 7: Только рунет (.ru/.su/.рф)${NC}"
        echo "  7) Слот РУ (порт 5059): $(get_dns_name "$SLOT_RU")"
        echo ""
        echo "  0) Назад"
        echo ""
        echo -n "Выбор (0-7): "
        read -r choice

        case "$choice" in
            1) select_dns_for_slot "1" ;;
            2) select_dns_for_slot "2" ;;
            3) select_dns_for_slot "3" ;;
            4) select_dns_for_slot "4" ;;
            5) select_dns_for_slot "5" ;;
            6) select_dns_for_slot "6" ;;
            7) select_dns_for_slot "RU" ;;
            0) return ;;
        esac
    done
}

# ============================================================
# Меню Bootstrap
# ============================================================
menu_bootstrap() {
    while true; do
        clear
        echo -e "${BLUE}╔══════════════════════════════════════════╗${NC}"
        echo -e "${BLUE}║     Bootstrap DNS                       ║${NC}"
        echo -e "${BLUE}╚══════════════════════════════════════════╝${NC}"
        echo ""
        echo -e "Текущий: ${YELLOW}$BOOTSTRAP_DNS${NC}"
        echo ""
        echo "Пресеты:"
        echo "  1) РФ Безопасный (Yandex + AdGuard) [рекомендуется]"
        echo "  2) Только Yandex"
        echo "  3) Только AdGuard"
        echo "  4) G-Core + Yandex + AdGuard"
        echo "  5) Ввести вручную"
        echo "  0) Назад"
        echo ""
        echo -n "Выбор: "
        read -r choice

        case "$choice" in
            1) BOOTSTRAP_DNS="77.88.8.8,77.88.8.1,94.140.14.14,94.140.15.15"; save_config; return ;;
            2) BOOTSTRAP_DNS="77.88.8.8,77.88.8.1"; save_config; return ;;
            3) BOOTSTRAP_DNS="94.140.14.14,94.140.15.15"; save_config; return ;;
            4) BOOTSTRAP_DNS="95.85.85.85,77.88.8.8,94.140.14.14"; save_config; return ;;
            5)
                echo "Введите IP через запятую:"
                read -r BOOTSTRAP_DNS
                save_config
                return
                ;;
            0) return ;;
        esac
    done
}

# ============================================================
# Меню дополнительных настроек
# ============================================================
menu_extras() {
    while true; do
        clear
        echo -e "${BLUE}╔══════════════════════════════════════════╗${NC}"
        echo -e "${BLUE}║     Дополнительные настройки            ║${NC}"
        echo -e "${BLUE}╚══════════════════════════════════════════╝${NC}"
        echo ""

        [ "$TLD_RU_ENABLED" = "1" ] && tld_st="${GREEN}[✓]${NC}" || tld_st="${RED}[ ]${NC}"
        [ "$BLOCK_QUIC" = "1" ] && quic_st="${GREEN}[✓]${NC}" || quic_st="${RED}[ ]${NC}"

        echo -e "  1) $tld_st TLD Split (.ru/.su/.рф через слот РУ)"
        echo -e "  2) $quic_st Блокировка QUIC (UDP 443, для YouTube)"
        echo ""
        echo "  0) Назад"
        echo ""
        echo -n "Выбор: "
        read -r choice

        case "$choice" in
            1) [ "$TLD_RU_ENABLED" = "1" ] && TLD_RU_ENABLED="0" || TLD_RU_ENABLED="1"; save_config ;;
            2) [ "$BLOCK_QUIC" = "1" ] && BLOCK_QUIC="0" || BLOCK_QUIC="1"; save_config ;;
            0) return ;;
        esac
    done
}

# ============================================================
# Меню Anti-block
# ============================================================
menu_antiblock() {
    while true; do
        clear
        echo -e "${BLUE}╔══════════════════════════════════════════╗${NC}"
        echo -e "${BLUE}║     Anti-block (заглушки провайдеров)   ║${NC}"
        echo -e "${BLUE}╚══════════════════════════════════════════╝${NC}"
        echo ""
        echo "Текущие заглушки:"
        grep "bogus-nxdomain=" /etc/dnsmasq.d/anti-block.conf 2>/dev/null | sed 's/bogus-nxdomain=/  /' || echo "  (пусто)"
        echo ""
        echo "Действия:"
        echo "  1) Добавить IP заглушки"
        echo "  2) Удалить IP заглушки"
        echo "  3) Сбросить к стандартному списку"
        echo "  0) Назад"
        echo ""
        echo -n "Выбор: "
        read -r choice

        case "$choice" in
            1)
                echo "Введите IP заглушки:"
                read -r ip
                if [ -f /usr/bin/add-stub ]; then
                    add-stub "$ip"
                else
                    echo "bogus-nxdomain=$ip" >> /etc/dnsmasq.d/anti-block.conf
                    /etc/init.d/dnsmasq restart
                fi
                echo "Нажмите Enter..."
                read -r _
                ;;
            2)
                echo "Введите IP для удаления:"
                read -r ip
                sed -i "/bogus-nxdomain=$ip/d" /etc/dnsmasq.d/anti-block.conf 2>/dev/null
                /etc/init.d/dnsmasq restart
                echo "Нажмите Enter..."
                read -r _
                ;;
            3)
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
                /etc/init.d/dnsmasq restart
                echo "Нажмите Enter..."
                read -r _
                ;;
            0) return ;;
        esac
    done
}

# ============================================================
# Применение настроек (со всеми фиксами из v10.6)
# ============================================================
apply_settings() {
    clear
    echo -e "${BLUE}╔══════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║     Применение настроек                 ║${NC}"
    echo -e "${BLUE}╚══════════════════════════════════════════╝${NC}"
    echo ""

    # Бэкапы
    echo "[1/6] Создание бэкапов..."
    if [ ! -d "/etc/config/backup-original" ]; then
        mkdir -p /etc/config/backup-original
        cp /etc/config/dhcp /etc/config/backup-original/dhcp.bak 2>/dev/null
        cp /etc/config/firewall /etc/config/backup-original/firewall.bak 2>/dev/null
        cp /etc/config/https-dns-proxy /etc/config/backup-original/https-dns-proxy.bak 2>/dev/null
        cp /etc/config/system /etc/config/backup-original/system.bak 2>/dev/null
        [ -f /etc/crontabs/root ] && cp /etc/crontabs/root /etc/config/backup-original/crontabs.bak
        echo "  [+] Эталонный бэкап создан"
    fi

    TIMESTAMP=$(date +%Y%m%d_%H%M%S)
    BACKUP_ACTUAL="/etc/config/backup-dns-$TIMESTAMP"
    mkdir -p "$BACKUP_ACTUAL"
    cp /etc/config/dhcp "$BACKUP_ACTUAL/dhcp.bak" 2>/dev/null
    cp /etc/config/firewall "$BACKUP_ACTUAL/firewall.bak" 2>/dev/null
    cp /etc/config/https-dns-proxy "$BACKUP_ACTUAL/https-dns-proxy.bak" 2>/dev/null
    cp /etc/config/system "$BACKUP_ACTUAL/system.bak" 2>/dev/null
    [ -f /etc/crontabs/root ] && cp /etc/crontabs/root "$BACKUP_ACTUAL/crontabs.bak"
    ln -sfn "$BACKUP_ACTUAL" /etc/config/backup-pre-dns-v9

    # Автоочистка старых бэкапов
    BACKUP_COUNT=$(ls -d /etc/config/backup-dns-* 2>/dev/null | wc -l)
    if [ "$BACKUP_COUNT" -gt 1 ]; then
        (cd /etc/config && ls -dt backup-dns-* 2>/dev/null | tail -n +2 | xargs rm -rf 2>/dev/null)
    fi

    # Anti-block
    echo "[2/6] Настройка anti-block..."
    if [ ! -f /etc/dnsmasq.d/anti-block.conf ]; then
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
    fi

    # https-dns-proxy (КРИТИЧНО: uci set строкой)
    echo "[3/6] Настройка https-dns-proxy..."
    while uci -q delete https-dns-proxy.@https-dns-proxy[0]; do :; done
    uci -q delete https-dns-proxy.config 2>/dev/null
    uci set https-dns-proxy.config='main'
    uci set https-dns-proxy.config.update_dnsmasq='0'

    for slot_num in 1 2 3 4 5 6; do
        eval "slot_value=\$SLOT_${slot_num}"
        [ -z "$slot_value" ] && continue

        port=$((5052 + slot_num))

        if echo "$slot_value" | grep -q "^custom:"; then
            url=$(echo "$slot_value" | cut -d: -f2-)
            name="Custom"
        else
            url=$(grep "^${slot_value}|" "$DNS_CATALOG" | cut -d'|' -f3)
            name=$(get_dns_name "$slot_value")
            [ -z "$url" ] && continue
        fi

        uci add https-dns-proxy https-dns-proxy
        uci set https-dns-proxy.@https-dns-proxy[-1].listen_addr='127.0.0.1'
        uci set https-dns-proxy.@https-dns-proxy[-1].listen_port="$port"
        uci set https-dns-proxy.@https-dns-proxy[-1].resolver_url="$url"
        uci set https-dns-proxy.@https-dns-proxy[-1].request_timeout='2'
        uci set https-dns-proxy.@https-dns-proxy[-1].bootstrap_dns="$BOOTSTRAP_DNS"
        echo "  [+] Слот $slot_num: $name (порт $port)"
    done

    # Слот РУ (порт 5059)
    if [ -n "$SLOT_RU" ]; then
        if echo "$SLOT_RU" | grep -q "^custom:"; then
            ru_url=$(echo "$SLOT_RU" | cut -d: -f2-)
        else
            ru_url=$(grep "^${SLOT_RU}|" "$DNS_CATALOG" | cut -d'|' -f3)
        fi

        if [ -n "$ru_url" ]; then
            uci add https-dns-proxy https-dns-proxy
            uci set https-dns-proxy.@https-dns-proxy[-1].listen_addr='127.0.0.1'
            uci set https-dns-proxy.@https-dns-proxy[-1].listen_port='5059'
            uci set https-dns-proxy.@https-dns-proxy[-1].resolver_url="$ru_url"
            uci set https-dns-proxy.@https-dns-proxy[-1].request_timeout='2'
            uci set https-dns-proxy.@https-dns-proxy[-1].bootstrap_dns="$BOOTSTRAP_DNS"
            echo "  [+] Слот РУ: $(get_dns_name "$SLOT_RU") (порт 5059)"
        fi
    fi

    uci commit https-dns-proxy

    # dnsmasq
    echo "[4/6] Настройка dnsmasq..."
    uci -q get dhcp.@dnsmasq[0] >/dev/null || uci add dhcp dnsmasq
    while uci -q delete dhcp.@dnsmasq[0].server; do :; done
    uci -q delete dhcp.@dnsmasq[0].address 2>/dev/null

    uci add_list dhcp.@dnsmasq[0].confdir='/etc/dnsmasq.d'
    uci set dhcp.@dnsmasq[0].allservers='1'
    uci set dhcp.@dnsmasq[0].strictorder='0'
    uci set dhcp.@dnsmasq[0].noresolv='1'
    uci set dhcp.@dnsmasq[0].cachesize='10000'
    uci set dhcp.@dnsmasq[0].dnsforwardmax='1000'
    uci set dhcp.@dnsmasq[0].max_cache_ttl='300'
    uci set dhcp.@dnsmasq[0].quietdhcp='1'
    uci set dhcp.@dnsmasq[0].boguspriv='1'
    uci set dhcp.@dnsmasq[0].domainneeded='1'

    for slot_num in 1 2 3 4 5 6; do
        eval "slot_value=\$SLOT_${slot_num}"
        [ -n "$slot_value" ] && uci add_list dhcp.@dnsmasq[0].server="127.0.0.1#$((5052 + slot_num))"
    done

    if [ "$TLD_RU_ENABLED" = "1" ] && [ -n "$SLOT_RU" ]; then
        uci add_list dhcp.@dnsmasq[0].server='/ru/127.0.0.1#5059'
        uci add_list dhcp.@dnsmasq[0].server='/su/127.0.0.1#5059'
        uci add_list dhcp.@dnsmasq[0].server='/xn--p1ai/127.0.0.1#5059'
    fi

    uci commit dhcp

    # QUIC
    echo "[5/6] Настройка QUIC..."
    uci -q delete firewall.block_quic 2>/dev/null
    if [ "$BLOCK_QUIC" = "1" ]; then
        uci set firewall.block_quic=rule
        uci set firewall.block_quic.name='Block-QUIC'
        uci set firewall.block_quic.src='lan'
        uci set firewall.block_quic.dest='wan'
        uci set firewall.block_quic.proto='udp'
        uci set firewall.block_quic.dest_port='443'
        uci set firewall.block_quic.target='REJECT'
        uci commit firewall
        echo "  [+] QUIC заблокирован"
    fi

    # Скрипт отката
    echo "[6/6] Создание скрипта отката..."
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
rm -f /etc/sysctl.d/99-custom.conf
sysctl -p /etc/sysctl.conf >/dev/null 2>&1
/etc/init.d/firewall restart 2>/dev/null
/etc/init.d/https-dns-proxy restart 2>/dev/null
/etc/init.d/dnsmasq restart 2>/dev/null
/etc/init.d/sysntpd restart 2>/dev/null
/etc/init.d/cron restart 2>/dev/null
echo "✅ ROLLBACK COMPLETE (reboot recommended)"
ROLLBACK
    chmod +x /root/rollback-dns.sh

    # Перезапуск служб
    echo ""
    echo "Перезапуск служб..."
    killall -9 https-dns-proxy 2>/dev/null
    sleep 1
    /etc/init.d/https-dns-proxy restart
    sleep 2
    /etc/init.d/dnsmasq restart
    /etc/init.d/firewall restart 2>/dev/null
    sleep 2

    echo ""
    echo -e "${GREEN}✓ Настройки применены!${NC}"
    echo ""
    echo "Проверка: dns-diag"
    echo ""
    read -p "Нажмите Enter..." _
}

# ============================================================
# Просмотр состояния
# ============================================================
menu_status() {
    clear
    echo -e "${BLUE}╔══════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║     Текущее состояние                   ║${NC}"
    echo -e "${BLUE}╚══════════════════════════════════════════╝${NC}"
    echo ""

    echo -e "${CYAN}Активные DoH процессы:${NC}"
    ps | grep https-dns-proxy | grep -v grep | awk '{
        for(i=1;i<=NF;i++) {
            if($i=="-p") port=$(i+1);
            if($i=="-r") url=$(i+1);
        }
        printf "  Порт %s → %s\\n", port, url
    }'

    echo ""
    echo -e "${CYAN}Bootstrap DNS:${NC}"
    ps | grep https-dns-proxy | grep -v grep | head -1 | awk '{
        for(i=1;i<=NF;i++) if($i=="-b") {print "  " $(i+1); exit}
    }'

    echo ""
    echo -e "${CYAN}DNS Resolution:${NC}"
    for dom in ya.ru chatgpt.com youtube.com instagram.com linkedin.com; do
        ip=$(nslookup "$dom" 127.0.0.1 2>/dev/null | grep -vE '127\.0\.0\.|0\.0\.0\.0' | grep -oE '([0-9]{1,3}\.){3}[0-9]{1,3}' | head -n1)
        printf "  %-20s → %s\\n" "$dom" "${ip:-NO_ANSWER}"
    done

    echo ""
    echo -e "${CYAN}Anti-block заглушек:${NC}"
    count=$(grep -c bogus-nxdomain /etc/dnsmasq.d/anti-block.conf 2>/dev/null || echo 0)
    echo "  $count записей"

    echo ""
    echo -e "${CYAN}Бэкапы:${NC}"
    echo "  Эталон: $(ls -d /etc/config/backup-original 2>/dev/null || echo 'нет')"
    echo "  Текущих: $(ls -d /etc/config/backup-dns-* 2>/dev/null | wc -l)"

    echo ""
    read -p "Нажмите Enter..." _
}

# ============================================================
# Главное меню
# ============================================================
main_menu() {
    while true; do
        clear
        echo -e "${BLUE}╔══════════════════════════════════════════╗${NC}"
        echo -e "${BLUE}║     DNS Manager v$VERSION                  ║${NC}"
        echo -e "${BLUE}║     Все фиксы из v10.6 встроены         ║${NC}"
        echo -e "${BLUE}╚══════════════════════════════════════════╝${NC}"
        echo ""
        echo -e "${YELLOW}Интернет слоты:${NC}"
        echo "  1) $(get_dns_name "$SLOT_1")"
        echo "  2) $(get_dns_name "$SLOT_2")"
        echo "  3) $(get_dns_name "$SLOT_3")"
        echo "  4) $(get_dns_name "$SLOT_4")"
        echo "  5) $(get_dns_name "$SLOT_5")"
        echo "  6) $(get_dns_name "$SLOT_6")"
        echo ""
        echo -e "${YELLOW}Рунет слот:${NC}"
        echo "  РУ) $(get_dns_name "$SLOT_RU")"
        echo ""
        echo -e "Bootstrap: ${GREEN}$BOOTSTRAP_DNS${NC}"
        echo -e "QUIC:      ${GREEN}$([ "$BLOCK_QUIC" = "1" ] && echo "заблокирован" || echo "разблокирован")${NC}"
        echo -e "TLD .ru:   ${GREEN}$([ "$TLD_RU_ENABLED" = "1" ] && echo "через слот РУ" || echo "через интернет")${NC}"
        echo ""
        echo "Меню:"
        echo "  1) Настройка слотов"
        echo "  2) ${GREEN}Тест всех DNS${NC}"
        echo "  3) Bootstrap DNS"
        echo "  4) Доп. настройки"
        echo "  5) Anti-block"
        echo "  6) Состояние"
        echo "  7) ${GREEN}Применить${NC}"
        echo "  8) Откат"
        echo "  0) Выход"
        echo ""
        echo -n "Выбор: "
        read -r choice

        case "$choice" in
            1) menu_slots ;;
            2) menu_test_dns ;;
            3) menu_bootstrap ;;
            4) menu_extras ;;
            5) menu_antiblock ;;
            6) menu_status ;;
            7) apply_settings ;;
            8)
                [ -f /root/rollback-dns.sh ] && sh /root/rollback-dns.sh
                read -p "Нажмите Enter..." _
                ;;
            0) exit 0 ;;
        esac
    done
}

# Инициализация и запуск
init_system
load_config
main_menu
EOF

chmod +x /usr/bin/dns-manager
echo "✓ DNS Manager v3.0 установлен: dns-manager"