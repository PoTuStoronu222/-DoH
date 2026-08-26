#!/bin/sh
# ============================================================
# DNS Manager v3.1-FINAL
# Единый менеджер для OpenWrt DoH Suite
# Запуск: wget -O - URL | sh   ИЛИ   dns-manager
# ============================================================

MANAGER_PATH="/usr/bin/dns-manager"
SELF_SOURCE="$0"

# Если запущен через sh <(wget...) или wget | sh - устанавливаем себя
install_self() {
    # Если мы уже на месте - не устанавливаем повторно
    [ "$SELF_SOURCE" = "$MANAGER_PATH" ] && return 0

    echo "=== Установка DNS Manager v3.1 в систему ==="

    # Определение пакетного менеджера
    if command -v apk >/dev/null 2>&1; then
        PKG="apk"
        echo "[*] Пакетный менеджер: apk (OpenWrt 25.x)"
    elif command -v opkg >/dev/null 2>&1; then
        PKG="opkg"
        echo "[*] Пакетный менеджер: opkg (OpenWrt 21.02-24.x)"
    else
        echo "[!] Пакетный менеджер не найден!"; exit 1
    fi

    # Установка обязательных пакетов
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
    else
        echo "[+] Все пакеты уже установлены"
    fi

    # Копируем себя в систему (работает и для wget | sh и для sh file.sh)
    if [ -f "$SELF_SOURCE" ]; then
        cp "$SELF_SOURCE" "$MANAGER_PATH" 2>/dev/null || cat "$SELF_SOURCE" > "$MANAGER_PATH"
    else
        # Если запущен через pipe (wget | sh), читаем из stdin невозможно
        # Значит нужно скачать заново
        if command -v wget >/dev/null 2>&1; then
            wget -q -O "$MANAGER_PATH" "https://raw.githubusercontent.com/PoTuStoronu222/Openwrt-Smartdns-DoH/main/test.sh"
        elif command -v curl >/dev/null 2>&1; then
            curl -fsSL "https://raw.githubusercontent.com/PoTuStoronu222/Openwrt-Smartdns-DoH/main/test.sh" -o "$MANAGER_PATH"
        fi
    fi

    chmod +x "$MANAGER_PATH"
    echo ""
    echo "=========================================="
    echo "✅ DNS Manager установлен!"
    echo "=========================================="
    echo "Запуск: dns-manager"
    echo ""
    exec "$MANAGER_PATH"
}

# ============================================================
# ОСНОВНАЯ ЧАСТЬ МЕНЕДЖЕРА
# ============================================================

CONFIG_FILE="/root/.dns-manager.conf"
DNS_CATALOG="/root/.dns-catalog.conf"
TEST_RESULTS="/root/.dns-test-results.conf"
VERSION="3.1-FINAL"

# Цвета (готовые строки для printf)
C_RED='\033[0;31m'
C_GREEN='\033[0;32m'
C_YELLOW='\033[1;33m'
C_BLUE='\033[0;34m'
C_CYAN='\033[0;36m'
C_NC='\033[0m'

# ============================================================
# КАТАЛОГ DNS
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
# ИНИЦИАЛИЗАЦИЯ (бережное отношение к существующим настройкам)
# ============================================================
init_system() {
    printf "${C_BLUE}=== Инициализация системы ===${C_NC}\n"

    if command -v apk >/dev/null 2>&1; then
        PKG="apk"
    elif command -v opkg >/dev/null 2>&1; then
        PKG="opkg"
    else
        printf "${C_RED}[!] Пакетный менеджер не найден!${C_NC}\n"
        exit 1
    fi

    # Устанавливаем только недостающее
    NEED_INSTALL=0
    command -v https-dns-proxy >/dev/null 2>&1 || NEED_INSTALL=1
    command -v curl >/dev/null 2>&1 || NEED_INSTALL=1

    if [ "$NEED_INSTALL" = "1" ]; then
        printf "[*] Установка недостающих пакетов...\n"
        if [ "$PKG" = "apk" ]; then
            apk update && apk add https-dns-proxy ca-certificates curl bind-tools
        else
            opkg update && opkg install https-dns-proxy ca-certificates curl bind-dig
        fi
    fi

    # Очистка ТОЛЬКО артефактов старых версий v8/v9/v10
    printf "[*] Очистка старых артефактов...\n"
    rm -f /etc/dnsmasq.d/telemetry.conf
    rm -f /etc/dnsmasq.d/.bogus-old
    rm -f /usr/bin/update-bogus-dns
    [ -f /etc/crontabs/root ] && sed -i '/update-bogus-dns/d' /etc/crontabs/root

    [ ! -f "$DNS_CATALOG" ] && create_catalog

    printf "${C_GREEN}[✓] Система готова${C_NC}\n"
}

# ============================================================
# Конфигурация
# ============================================================
load_config() {
    if [ -f "$CONFIG_FILE" ]; then
        . "$CONFIG_FILE"
    else
        # Значения по умолчанию
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
        MTU_FIX="1"
        NTP_REDIRECT="1"
        SYSCTL_TUNING="1"
        GO_OPTIMIZE="1"
        save_config
    fi
    # Защита от пустых значений (если конфиг битый)
    : "${MTU_FIX:=1}"
    : "${NTP_REDIRECT:=1}"
    : "${SYSCTL_TUNING:=1}"
    : "${GO_OPTIMIZE:=1}"
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
MTU_FIX="$MTU_FIX"
NTP_REDIRECT="$NTP_REDIRECT"
SYSCTL_TUNING="$SYSCTL_TUNING"
GO_OPTIMIZE="$GO_OPTIMIZE"
CONF
}

get_dns_name() {
    id="$1"
    [ -z "$id" ] && { printf "(пусто)"; return; }
    if echo "$id" | grep -q "^custom:"; then
        printf "(custom)"
        return
    fi
    result=$(grep "^${id}|" "$DNS_CATALOG" | cut -d'|' -f2)
    [ -z "$result" ] && result="(неизвестный)"
    printf "%s" "$result"
}

# ============================================================
# БЫСТРАЯ НАСТРОЙКА (профиль по умолчанию)
# ============================================================
menu_profile_default() {
    clear
    printf "${C_BLUE}╔══════════════════════════════════════════╗${C_NC}\n"
    printf "${C_BLUE}║     Быстрая настройка (профиль)         ║${C_NC}\n"
    printf "${C_BLUE}╚══════════════════════════════════════════╝${C_NC}\n"
    echo ""
    printf "Выберите профиль:\n\n"
    printf "  1) ${C_GREEN}Оптимальный (рекомендуется)${C_NC}\n"
    printf "     • 4 самых быстрых DNS: Mafioznik, Comss.ru, Comss.one, VPPay\n"
    printf "     • Яндекс для рунета\n"
    printf "     • QUIC заблокирован, MTU fix, NTP redirect\n"
    printf "     • Go оптимизация для Tailscale\n\n"
    printf "  2) Максимальная устойчивость (все 6 DNS)\n"
    printf "     • Все 6 SmartDNS + Yandex\n"
    printf "     • Максимальная отказоустойчивость\n\n"
    printf "  3) Минимум (только 2 DNS)\n"
    printf "     • Mafioznik + Comss.ru (самые быстрые)\n"
    printf "     • Экономия ресурсов роутера\n\n"
    printf "  4) Только рунет (без обхода)\n"
    printf "     • Только Yandex для .ru\n"
    printf "     • Интернет слоты пустые\n\n"
    printf "  ${C_CYAN}Enter${C_NC} = отмена\n"
    echo ""
    printf "Выбор: "
    read -r choice

    [ -z "$choice" ] && return

    case "$choice" in
        1)
            SLOT_1="mafioznik"; SLOT_2="comss_ru"; SLOT_3="comss_one"
            SLOT_4="vppay"; SLOT_5=""; SLOT_6=""
            SLOT_RU="yandex"
            BOOTSTRAP_DNS="77.88.8.8,77.88.8.1,94.140.14.14,94.140.15.15"
            TLD_RU_ENABLED="1"; BLOCK_QUIC="1"
            MTU_FIX="1"; NTP_REDIRECT="1"; SYSCTL_TUNING="1"; GO_OPTIMIZE="1"
            ;;
        2)
            SLOT_1="mafioznik"; SLOT_2="comss_one"; SLOT_3="astrakat"
            SLOT_4="malw_link"; SLOT_5="comss_ru"; SLOT_6="vppay"
            SLOT_RU="yandex"
            BOOTSTRAP_DNS="77.88.8.8,77.88.8.1,94.140.14.14,94.140.15.15"
            TLD_RU_ENABLED="1"; BLOCK_QUIC="1"
            MTU_FIX="1"; NTP_REDIRECT="1"; SYSCTL_TUNING="1"; GO_OPTIMIZE="1"
            ;;
        3)
            SLOT_1="mafioznik"; SLOT_2="comss_ru"
            SLOT_3=""; SLOT_4=""; SLOT_5=""; SLOT_6=""
            SLOT_RU="yandex"
            BOOTSTRAP_DNS="77.88.8.8,77.88.8.1,94.140.14.14,94.140.15.15"
            TLD_RU_ENABLED="1"; BLOCK_QUIC="0"
            MTU_FIX="1"; NTP_REDIRECT="1"; SYSCTL_TUNING="0"; GO_OPTIMIZE="1"
            ;;
        4)
            SLOT_1=""; SLOT_2=""; SLOT_3=""; SLOT_4=""; SLOT_5=""; SLOT_6=""
            SLOT_RU="yandex"
            BOOTSTRAP_DNS="77.88.8.8,77.88.8.1"
            TLD_RU_ENABLED="1"; BLOCK_QUIC="0"
            MTU_FIX="1"; NTP_REDIRECT="1"; SYSCTL_TUNING="1"; GO_OPTIMIZE="1"
            ;;
        *)
            printf "${C_RED}[!] Неверный выбор${C_NC}\n"
            sleep 1
            return
            ;;
    esac

    save_config
    printf "${C_GREEN}[✓] Профиль применён в конфигурацию${C_NC}\n"
    printf "\nПрименить настройки сейчас? (д/н): "
    read -r confirm
    case "$confirm" in
        д|Д|y|Y) apply_settings ;;
        *) printf "Настройки сохранены. Примените вручную через меню.\n"; sleep 2 ;;
    esac
}

# ============================================================
# ТЕСТ DNS
# ============================================================
menu_test_dns() {
    clear
    printf "${C_BLUE}╔══════════════════════════════════════════╗${C_NC}\n"
    printf "${C_BLUE}║     Тестирование всех DNS               ║${C_NC}\n"
    printf "${C_BLUE}╚══════════════════════════════════════════╝${C_NC}\n"
    echo ""
    printf "${C_YELLOW}Проверка доступности и скорости...${C_NC}\n"
    echo ""

    printf "%-25s %-10s %-10s %s\n" "DNS" "Статус" "Скорость" "Примечание"
    printf "%s\n" "------------------------------------------------------------------------"

    > "$TEST_RESULTS"

    while IFS='|' read -r id name url; do
        [ -z "$id" ] && continue

        time_ms=$(curl -s -o /dev/null -w "%{time_total}" --max-time 5 \
            "${url}?name=google.com&type=A" \
            -H "Accept: application/dns-json" 2>/dev/null)

        if [ -n "$time_ms" ] && [ "$time_ms" != "0.000000" ]; then
            ms=$(echo "$time_ms" | awk '{printf "%.0f", $1 * 1000}')
            if [ "$ms" -lt 100 ]; then
                status_str="${C_GREEN}OK${C_NC}"
                note="Быстрый"
            elif [ "$ms" -lt 300 ]; then
                status_str="${C_GREEN}OK${C_NC}"
                note="Нормальный"
            else
                status_str="${C_YELLOW}OK${C_NC}"
                note="Медленный"
            fi
            printf "%-25s ${status_str}    %-10s %s\n" "$name" "${ms}ms" "$note"
            echo "${id}|${ms}|OK" >> "$TEST_RESULTS"
        else
            printf "%-25s ${C_RED}FAIL${C_NC}    %-10s %s\n" "$name" "-" "Заблокирован"
            echo "${id}|0|FAIL" >> "$TEST_RESULTS"
        fi
    done < "$DNS_CATALOG"

    echo ""
    printf "%s\n" "------------------------------------------------------------------------"
    printf "${C_YELLOW}Результаты сохранены в $TEST_RESULTS${C_NC}\n"
    echo ""

    total=$(wc -l < "$TEST_RESULTS")
    ok=$(grep -c "|OK" "$TEST_RESULTS")
    fail=$(grep -c "|FAIL" "$TEST_RESULTS")
    printf "Всего: $total | ${C_GREEN}Работает: $ok${C_NC} | ${C_RED}Не работает: $fail${C_NC}\n"

    echo ""
    printf "Нажмите Enter для продолжения..."
    read -r _
}

# ============================================================
# Выбор DNS для слота
# ============================================================
select_dns_for_slot() {
    slot_num="$1"

    while true; do
        clear
        printf "${C_BLUE}╔══════════════════════════════════════════╗${C_NC}\n"
        printf "${C_BLUE}║     Выбор DNS для слота #$slot_num             ║${C_NC}\n"
        printf "${C_BLUE}╚══════════════════════════════════════════╝${C_NC}\n"
        echo ""
        printf "Доступные DNS (с результатами теста):\n\n"

        i=1
        while IFS='|' read -r id name url; do
            [ -z "$id" ] && continue

            test_result=$(grep "^${id}|" "$TEST_RESULTS" 2>/dev/null | cut -d'|' -f2,3)
            if [ -n "$test_result" ]; then
                ms=$(echo "$test_result" | cut -d'|' -f1)
                status=$(echo "$test_result" | cut -d'|' -f2)
                if [ "$status" = "OK" ]; then
                    status_str="${C_GREEN}${ms}ms${C_NC}"
                else
                    status_str="${C_RED}FAIL${C_NC}"
                fi
            else
                status_str="${C_YELLOW}нет теста${C_NC}"
            fi

            printf "  %2d) %-25s [%b]\n" "$i" "$name" "$status_str"
            i=$((i + 1))
        done < "$DNS_CATALOG"

        echo ""
        printf "  ${C_CYAN}99) Очистить слот${C_NC}\n"
        printf "  ${C_CYAN}98) Ввести свой URL${C_NC}\n"
        printf "  ${C_CYAN}Enter) Отмена${C_NC}\n"
        echo ""
        printf "Выбор: "
        read -r choice

        # Enter = отмена
        [ -z "$choice" ] && return

        case "$choice" in
            99)
                eval "SLOT_${slot_num}=\"\""
                save_config
                return
                ;;
            98)
                printf "Введите URL DoH (https://...): "
                read -r custom_url
                [ -z "$custom_url" ] && continue
                eval "SLOT_${slot_num}=\"custom:${custom_url}\""
                save_config
                return
                ;;
            *)
                total=$(grep -c '^' "$DNS_CATALOG")
                if [ "$choice" -ge 1 ] 2>/dev/null && [ "$choice" -le "$total" ] 2>/dev/null; then
                    selected_id=$(sed -n "${choice}p" "$DNS_CATALOG" | cut -d'|' -f1)

                    test_status=$(grep "^${selected_id}|" "$TEST_RESULTS" 2>/dev/null | cut -d'|' -f3)
                    if [ "$test_status" = "FAIL" ]; then
                        printf "${C_YELLOW}[!] Внимание: этот DNS не работает${C_NC}\n"
                        printf "Продолжить? (д/н): "
                        read -r confirm
                        [ "$confirm" != "д" ] && [ "$confirm" != "y" ] && continue
                    fi

                    eval "SLOT_${slot_num}=\"$selected_id\""
                    save_config
                    return
                else
                    printf "${C_RED}[!] Неверный выбор${C_NC}\n"
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
        printf "${C_YELLOW}Слот 7: Только рунет (.ru/.su/.рф)${C_NC}\n"
        printf "  7) Слот РУ (порт 5059): %s\n" "$(get_dns_name "$SLOT_RU")"
        echo ""
        printf "  ${C_CYAN}Enter) Назад${C_NC}\n"
        echo ""
        printf "Выбор: "
        read -r choice

        [ -z "$choice" ] && return

        case "$choice" in
            1) select_dns_for_slot "1" ;;
            2) select_dns_for_slot "2" ;;
            3) select_dns_for_slot "3" ;;
            4) select_dns_for_slot "4" ;;
            5) select_dns_for_slot "5" ;;
            6) select_dns_for_slot "6" ;;
            7) select_dns_for_slot "RU" ;;
            *) printf "${C_RED}[!] Неверный выбор${C_NC}\n"; sleep 1 ;;
        esac
    done
}

# ============================================================
# Меню Bootstrap
# ============================================================
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
        printf "  1) РФ Безопасный (Yandex + AdGuard) [рекомендуется]\n"
        printf "  2) Только Yandex\n"
        printf "  3) Только AdGuard\n"
        printf "  4) G-Core + Yandex + AdGuard\n"
        printf "  5) Ввести вручную\n"
        printf "  ${C_CYAN}Enter) Назад${C_NC}\n"
        echo ""
        printf "Выбор: "
        read -r choice

        [ -z "$choice" ] && return

        case "$choice" in
            1) BOOTSTRAP_DNS="77.88.8.8,77.88.8.1,94.140.14.14,94.140.15.15"; save_config; return ;;
            2) BOOTSTRAP_DNS="77.88.8.8,77.88.8.1"; save_config; return ;;
            3) BOOTSTRAP_DNS="94.140.14.14,94.140.15.15"; save_config; return ;;
            4) BOOTSTRAP_DNS="95.85.85.85,77.88.8.8,94.140.14.14"; save_config; return ;;
            5)
                printf "Введите IP через запятую: "
                read -r BOOTSTRAP_DNS
                [ -n "$BOOTSTRAP_DNS" ] && save_config
                return
                ;;
        esac
    done
}

# ============================================================
# Доп. настройки (ВСЕ функции из оригинального скрипта)
# ============================================================
menu_extras() {
    while true; do
        clear
        printf "${C_BLUE}╔══════════════════════════════════════════╗${C_NC}\n"
        printf "${C_BLUE}║     Дополнительные настройки            ║${C_NC}\n"
        printf "${C_BLUE}╚══════════════════════════════════════════╝${C_NC}\n"
        echo ""

        [ "$TLD_RU_ENABLED" = "1" ] && tld_st="${C_GREEN}[✓]${C_NC}" || tld_st="${C_RED}[ ]${C_NC}"
        [ "$BLOCK_QUIC" = "1" ] && quic_st="${C_GREEN}[✓]${C_NC}" || quic_st="${C_RED}[ ]${C_NC}"
        [ "$MTU_FIX" = "1" ] && mtu_st="${C_GREEN}[✓]${C_NC}" || mtu_st="${C_RED}[ ]${C_NC}"
        [ "$NTP_REDIRECT" = "1" ] && ntp_st="${C_GREEN}[✓]${C_NC}" || ntp_st="${C_RED}[ ]${C_NC}"
        [ "$SYSCTL_TUNING" = "1" ] && sys_st="${C_GREEN}[✓]${C_NC}" || sys_st="${C_RED}[ ]${C_NC}"
        [ "$GO_OPTIMIZE" = "1" ] && go_st="${C_GREEN}[✓]${C_NC}" || go_st="${C_RED}[ ]${C_NC}"

        printf "  1) %b TLD Split (.ru/.su/.рф через слот РУ)\n" "$tld_st"
        printf "  2) %b Блокировка QUIC (UDP 443, для YouTube)\n" "$quic_st"
        printf "  3) %b MTU Fix (для PPPoE/L2TP)\n" "$mtu_st"
        printf "  4) %b NTP Redirect (для корректного DoH/SSL)\n" "$ntp_st"
        printf "  5) %b Sysctl Tuning (оптимизация сети)\n" "$sys_st"
        printf "  6) %b Go-оптимизация (Tailscale, tg-ws-proxy)\n" "$go_st"
        echo ""
        printf "  ${C_CYAN}Enter) Назад${C_NC}\n"
        echo ""
        printf "Выбор: "
        read -r choice

        [ -z "$choice" ] && return

        case "$choice" in
            1) [ "$TLD_RU_ENABLED" = "1" ] && TLD_RU_ENABLED="0" || TLD_RU_ENABLED="1"; save_config ;;
            2) [ "$BLOCK_QUIC" = "1" ] && BLOCK_QUIC="0" || BLOCK_QUIC="1"; save_config ;;
            3) [ "$MTU_FIX" = "1" ] && MTU_FIX="0" || MTU_FIX="1"; save_config ;;
            4) [ "$NTP_REDIRECT" = "1" ] && NTP_REDIRECT="0" || NTP_REDIRECT="1"; save_config ;;
            5) [ "$SYSCTL_TUNING" = "1" ] && SYSCTL_TUNING="0" || SYSCTL_TUNING="1"; save_config ;;
            6) [ "$GO_OPTIMIZE" = "1" ] && GO_OPTIMIZE="0" || GO_OPTIMIZE="1"; save_config ;;
        esac
    done
}

# ============================================================
# Anti-block
# ============================================================
menu_antiblock() {
    while true; do
        clear
        printf "${C_BLUE}╔══════════════════════════════════════════╗${C_NC}\n"
        printf "${C_BLUE}║     Anti-block (заглушки провайдеров)   ║${C_NC}\n"
        printf "${C_BLUE}╚══════════════════════════════════════════╝${C_NC}\n"
        echo ""
        printf "Текущие заглушки:\n"
        grep "bogus-nxdomain=" /etc/dnsmasq.d/anti-block.conf 2>/dev/null | sed 's/bogus-nxdomain=/  /' || printf "  (пусто)\n"
        echo ""
        printf "Действия:\n"
        printf "  1) Добавить IP заглушки\n"
        printf "  2) Удалить IP заглушки\n"
        printf "  3) Сбросить к ЭТАЛОННОМУ списку (рекомендуется)\n"
        printf "  ${C_CYAN}Enter) Назад${C_NC}\n"
        echo ""
        printf "Выбор: "
        read -r choice

        [ -z "$choice" ] && return

        case "$choice" in
            1)
                printf "Введите IP заглушки: "
                read -r ip
                [ -z "$ip" ] && return
                echo "bogus-nxdomain=$ip" >> /etc/dnsmasq.d/anti-block.conf
                /etc/init.d/dnsmasq restart
                printf "Нажмите Enter..."
                read -r _
                ;;
            2)
                printf "Введите IP для удаления: "
                read -r ip
                [ -z "$ip" ] && return
                sed -i "/bogus-nxdomain=$ip/d" /etc/dnsmasq.d/anti-block.conf 2>/dev/null
                /etc/init.d/dnsmasq restart
                printf "Нажмите Enter..."
                read -r _
                ;;
            3)
                # Эталонный список — БЕЗ реальных IP LinkedIn/Instagram
                cat > /etc/dnsmasq.d/anti-block.conf << 'ANTIBLOCK'
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
                printf "Нажмите Enter..."
                read -r _
                ;;
        esac
    done
}

# ============================================================
# ПРИМЕНЕНИЕ НАСТРОЕК (все блоки)
# ============================================================
apply_settings() {
    clear
    printf "${C_BLUE}╔══════════════════════════════════════════╗${C_NC}\n"
    printf "${C_BLUE}║     Применение настроек                 ║${C_NC}\n"
    printf "${C_BLUE}╚══════════════════════════════════════════╝${C_NC}\n"
    echo ""

    # ===== [1/10] Бэкапы =====
    printf "[1/10] Создание бэкапов...\n"
    if [ ! -d "/etc/config/backup-original" ]; then
        mkdir -p /etc/config/backup-original
        cp /etc/config/dhcp /etc/config/backup-original/dhcp.bak 2>/dev/null
        cp /etc/config/firewall /etc/config/backup-original/firewall.bak 2>/dev/null
        cp /etc/config/https-dns-proxy /etc/config/backup-original/https-dns-proxy.bak 2>/dev/null
        cp /etc/config/system /etc/config/backup-original/system.bak 2>/dev/null
        [ -f /etc/crontabs/root ] && cp /etc/crontabs/root /etc/config/backup-original/crontabs.bak
        printf "  [+] Эталонный бэкап создан\n"
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

    # Автоочистка старых бэкапов (оставить только 1)
    cd /etc/config
    ls -dt backup-dns-* 2>/dev/null | tail -n +2 | while read -r old; do
        rm -rf "$old" 2>/dev/null
    done
    cd - > /dev/null

    # ===== [2/10] Anti-block =====
    printf "[2/10] Anti-block...\n"
    if [ ! -f /etc/dnsmasq.d/anti-block.conf ]; then
        cat > /etc/dnsmasq.d/anti-block.conf << 'ANTIBLOCK'
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

    # ===== [3/10] MTU Fix =====
    if [ "$MTU_FIX" = "1" ]; then
        printf "[3/10] MTU Fix...\n"
        uci -q set firewall.@defaults[0].mtu_fix='1'
        WAN_SECTION=$(uci show firewall 2>/dev/null | grep -m1 "\.name='wan'" | cut -d. -f1,2)
        [ -n "$WAN_SECTION" ] && uci -q set "${WAN_SECTION}.mtu_fix=1"
        uci commit firewall
    fi

    # ===== [4/10] NTP Redirect =====
    if [ "$NTP_REDIRECT" = "1" ]; then
        printf "[4/10] NTP Redirect...\n"
        LAN_IP=$(uci -q get network.lan.ipaddr | cut -d'/' -f1 | awk '{print $1}')
        [ -z "$LAN_IP" ] || [ "$LAN_IP" = "0.0.0.0" ] && LAN_IP="192.168.1.1"

        # DHCP option 42 (NTP)
        for opt in $(uci -q get dhcp.lan.dhcp_option | tr ' ' '\n' | grep '^42,'); do
            uci -q del_list dhcp.lan.dhcp_option="$opt"
        done
        uci add_list dhcp.lan.dhcp_option="42,$LAN_IP"
        uci commit dhcp

        # Удаляем старые правила NTP
        for sec in $(uci show firewall 2>/dev/null | grep -E "dest_port='123'|src_dport='123'|Redirect-NTP" | cut -d. -f2 | cut -d= -f1 | sort -u); do
            uci -q delete firewall."$sec"
        done

        # Определяем fw3/fw4
        if [ -f /usr/share/fw4/helpers.sh ] || command -v fw4 >/dev/null 2>&1; then
            FW_VERSION="fw4"
        else
            FW_VERSION="fw3"
        fi

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

        # NTP серверы
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
    fi

    # ===== [5/10] Go-оптимизация =====
    if [ "$GO_OPTIMIZE" = "1" ]; then
        printf "[5/10] Go-оптимизация (Tailscale, tg-ws-proxy)...\n"
        f_tg="/etc/init.d/tg-ws-proxy-go"
        f_ts="/etc/init.d/tailscale"

        if [ -f "$f_tg" ]; then
            sed -i '/GOMAXPROCS/d; /GOMEMLIMIT/d; /GOGC/d' "$f_tg"
            if grep -q "procd_open_instance" "$f_tg"; then
                awk '/procd_open_instance/ {print; print "    procd_set_param env GOMAXPROCS=1 GOMEMLIMIT=50MiB"; next} 1' "$f_tg" > /tmp/tg.tmp && mv /tmp/tg.tmp "$f_tg"
                printf "  [+] tg-ws-proxy-go: GOMAXPROCS=1 GOMEMLIMIT=50MiB\n"
            fi
        fi

        if [ -f "$f_ts" ]; then
            sed -i '/GOMAXPROCS/d; /GOMEMLIMIT/d; /GOGC/d' "$f_ts"
            if grep -q "procd_open_instance" "$f_ts"; then
                awk '/procd_open_instance/ {print; print "    procd_set_param env GOMEMLIMIT=85MiB"; next} 1' "$f_ts" > /tmp/ts.tmp && mv /tmp/ts.tmp "$f_ts"
                printf "  [+] tailscale: GOMEMLIMIT=85MiB\n"
            fi
        fi
    fi

    # ===== [6/10] Sysctl tuning =====
    if [ "$SYSCTL_TUNING" = "1" ]; then
        printf "[6/10] Sysctl tuning...\n"
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
    fi

    # ===== [7/10] Hotplug для tailscale =====
    if [ -f /etc/init.d/tailscale ]; then
        printf "[7/10] Hotplug tailscale...\n"
        rm -rf /tmp/tailscale_ntp_lock
        mkdir -p /etc/hotplug.d/ntp
        cat > /etc/hotplug.d/ntp/99-tailscale << 'HOTPLUG'
#!/bin/sh
[ "$ACTION" = "step" ] || [ "$ACTION" = "stratum" ] || exit 0
UPTIME=$(cut -d. -f1 /proc/uptime)
[ "$UPTIME" -lt 600 ] && mkdir -p /tmp/tailscale_ntp_lock && /etc/init.d/tailscale restart >/dev/null 2>&1
HOTPLUG
        chmod +x /etc/hotplug.d/ntp/99-tailscale
    fi

    # ===== [8/10] https-dns-proxy =====
    printf "[8/10] Настройка https-dns-proxy...\n"
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
        # КРИТИЧНО: строкой, а не add_list!
        uci set https-dns-proxy.@https-dns-proxy[-1].bootstrap_dns="$BOOTSTRAP_DNS"
        printf "  [+] Слот $slot_num: $name (порт $port)\n"
    done

    # Слот РУ (5059)
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
            printf "  [+] Слот РУ: %s (порт 5059)\n" "$(get_dns_name "$SLOT_RU")"
        fi
    fi

    uci commit https-dns-proxy

    # ===== [9/10] dnsmasq =====
    printf "[9/10] Настройка dnsmasq...\n"
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

    # Активные слоты
    for slot_num in 1 2 3 4 5 6; do
        eval "slot_value=\$SLOT_${slot_num}"
        [ -n "$slot_value" ] && uci add_list dhcp.@dnsmasq[0].server="127.0.0.1#$((5052 + slot_num))"
    done

    # TLD Split
    if [ "$TLD_RU_ENABLED" = "1" ] && [ -n "$SLOT_RU" ]; then
        uci add_list dhcp.@dnsmasq[0].server='/ru/127.0.0.1#5059'
        uci add_list dhcp.@dnsmasq[0].server='/su/127.0.0.1#5059'
        uci add_list dhcp.@dnsmasq[0].server='/xn--p1ai/127.0.0.1#5059'
    fi

    uci commit dhcp

    # ===== [10/10] QUIC и скрипт отката =====
    printf "[10/10] QUIC + откат...\n"
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
        printf "  [+] QUIC заблокирован\n"
    fi

    # Скрипт отката
    cat > /root/rollback-dns.sh << 'ROLLBACK'
#!/bin/sh
BACKUP="/etc/config/backup-pre-dns-v9"
ORIGINAL="/etc/config/backup-original"
if [ -d "$BACKUP" ]; then SOURCE="$BACKUP"
elif [ -d "$ORIGINAL" ]; then SOURCE="$ORIGINAL"
else printf "[!] No backup found!\n"; exit 1; fi
printf "=== ROLLBACK from %s ===\n" "$SOURCE"
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
printf "✅ ROLLBACK COMPLETE (reboot recommended)\n"
ROLLBACK
    chmod +x /root/rollback-dns.sh

    # Перезапуск служб
    echo ""
    printf "Перезапуск служб...\n"
    killall -9 https-dns-proxy 2>/dev/null
    sleep 1
    /etc/init.d/https-dns-proxy restart
    sleep 2
    /etc/init.d/dnsmasq restart
    /etc/init.d/firewall restart 2>/dev/null
    [ -f /etc/init.d/sysntpd ] && /etc/init.d/sysntpd restart 2>/dev/null
    sleep 2

    echo ""
    printf "${C_GREEN}✓ Все настройки применены!${C_NC}\n"
    printf "\nНажмите Enter..."
    read -r _
}

# ============================================================
# Состояние
# ============================================================
menu_status() {
    clear
    printf "${C_BLUE}╔══════════════════════════════════════════╗${C_NC}\n"
    printf "${C_BLUE}║     Текущее состояние                   ║${C_NC}\n"
    printf "${C_BLUE}╚══════════════════════════════════════════╝${C_NC}\n"
    echo ""

    # Балансировщик
    allservers=$(uci -q get dhcp.@dnsmasq[0].allservers)
    if [ "$allservers" = "1" ]; then
        printf "${C_GREEN}[✓] Балансировщик: allservers=1${C_NC}\n"
    else
        printf "${C_RED}[✗] Балансировщик: ОТКЛЮЧЕН!${C_NC}\n"
    fi

    echo ""
    printf "${C_CYAN}Активные DoH процессы:${C_NC}\n"
    ps | grep https-dns-proxy | grep -v grep | awk '{
        port=""; url=""
        for(i=1;i<=NF;i++) {
            if($i=="-p") port=$(i+1)
            if($i=="-r") url=$(i+1)
        }
        if(port!="" && url!="") printf "  Порт %s → %s\n", port, url
    }'

    echo ""
    printf "${C_CYAN}Bootstrap DNS:${C_NC}\n"
    ps | grep https-dns-proxy | grep -v grep | head -1 | awk '{
        for(i=1;i<=NF;i++) if($i=="-b") {printf "  %s\n", $(i+1); exit}
    }'

    echo ""
    printf "${C_CYAN}DNS Resolution:${C_NC}\n"
    for dom in ya.ru chatgpt.com youtube.com instagram.com linkedin.com; do
        ip=$(nslookup "$dom" 127.0.0.1 2>/dev/null | grep -vE '127\.0\.0\.|0\.0\.0\.0' | grep -oE '([0-9]{1,3}\.){3}[0-9]{1,3}' | head -n1)
        printf "  %-20s → %s\n" "$dom" "${ip:-NO_ANSWER}"
    done

    echo ""
    printf "${C_CYAN}Anti-block:${C_NC}\n"
    count=$(grep -c bogus-nxdomain /etc/dnsmasq.d/anti-block.conf 2>/dev/null || echo 0)
    printf "  %s записей\n" "$count"

    echo ""
    printf "${C_CYAN}Службы:${C_NC}\n"
    [ -f /etc/init.d/tailscale ] && printf "  Tailscale: установлен\n"
    [ -f /etc/init.d/tg-ws-proxy-go ] && printf "  tg-ws-proxy-go: установлен\n"

    echo ""
    printf "${C_CYAN}Бэкапы:${C_NC}\n"
    [ -d /etc/config/backup-original ] && printf "  Эталон: ✓\n" || printf "  Эталон: ✗\n"
    printf "  Текущих: %s\n" "$(ls -d /etc/config/backup-dns-* 2>/dev/null | wc -l)"

    echo ""
    printf "Нажмите Enter..."
    read -r _
}

# ============================================================
# Главное меню
# ============================================================
main_menu() {
    while true; do
        clear
        printf "${C_BLUE}╔══════════════════════════════════════════╗${C_NC}\n"
        printf "${C_BLUE}║     DNS Manager v%-22s║${C_NC}\n" "$VERSION"
        printf "${C_BLUE}║     Все блоки из v10.6 встроены         ║${C_NC}\n"
        printf "${C_BLUE}╚══════════════════════════════════════════╝${C_NC}\n"
        echo ""
        printf "${C_YELLOW}Интернет слоты:${C_NC}\n"
        printf "  1) %s\n" "$(get_dns_name "$SLOT_1")"
        printf "  2) %s\n" "$(get_dns_name "$SLOT_2")"
        printf "  3) %s\n" "$(get_dns_name "$SLOT_3")"
        printf "  4) %s\n" "$(get_dns_name "$SLOT_4")"
        printf "  5) %s\n" "$(get_dns_name "$SLOT_5")"
        printf "  6) %s\n" "$(get_dns_name "$SLOT_6")"
        echo ""
        printf "${C_YELLOW}Рунет слот:${C_NC}\n"
        printf "  РУ) %s\n" "$(get_dns_name "$SLOT_RU")"
        echo ""
        printf "Bootstrap: ${C_GREEN}%s${C_NC}\n" "$BOOTSTRAP_DNS"
        printf "QUIC: ${C_GREEN}%s${C_NC} | MTU: ${C_GREEN}%s${C_NC} | NTP: ${C_GREEN}%s${C_NC}\n" \
            "$([ "$BLOCK_QUIC" = "1" ] && echo "✓" || echo "✗")" \
            "$([ "$MTU_FIX" = "1" ] && echo "✓" || echo "✗")" \
            "$([ "$NTP_REDIRECT" = "1" ] && echo "✓" || echo "✗")"
        printf "Sysctl: ${C_GREEN}%s${C_NC} | Go: ${C_GREEN}%s${C_NC} | TLD: ${C_GREEN}%s${C_NC}\n" \
            "$([ "$SYSCTL_TUNING" = "1" ] && echo "✓" || echo "✗")" \
            "$([ "$GO_OPTIMIZE" = "1" ] && echo "✓" || echo "✗")" \
            "$([ "$TLD_RU_ENABLED" = "1" ] && echo "✓" || echo "✗")"
        echo ""
        printf "Меню:\n"
        printf "  ${C_GREEN}1) ⚡ Быстрая настройка (профиль по умолчанию)${C_NC}\n"
        printf "  2) Настройка слотов\n"
        printf "  3) Тест всех DNS\n"
        printf "  4) Bootstrap DNS\n"
        printf "  5) Доп. настройки (QUIC, MTU, NTP, sysctl, Go)\n"
        printf "  6) Anti-block\n"
        printf "  7) Состояние\n"
        printf "  ${C_GREEN}8) ⚡ Применить настройки${C_NC}\n"
        printf "  9) Откат\n"
        printf "  0) Выход\n"
        echo ""
        printf "Выбор: "
        read -r choice

        case "$choice" in
            1) menu_profile_default ;;
            2) menu_slots ;;
            3) menu_test_dns ;;
            4) menu_bootstrap ;;
            5) menu_extras ;;
            6) menu_antiblock ;;
            7) menu_status ;;
            8) apply_settings ;;
            9)
                if [ -f /root/rollback-dns.sh ]; then
                    sh /root/rollback-dns.sh
                else
                    printf "${C_RED}[!] Скрипт отката не найден${C_NC}\n"
                fi
                printf "Нажмите Enter..."
                read -r _
                ;;
            0)
                printf "${C_GREEN}До свидания!${C_NC}\n"
                exit 0
                ;;
            *)
                printf "${C_RED}[!] Неверный выбор${C_NC}\n"
                sleep 1
                ;;
        esac
    done
}

# ============================================================
# ТОЧКА ВХОДА
# ============================================================

# Если запущен НЕ из /usr/bin/dns-manager - устанавливаем себя
if [ "$SELF_SOURCE" != "$MANAGER_PATH" ] || [ ! -f "$MANAGER_PATH" ]; then
    install_self
    exit 0
fi

# Основной запуск менеджера
init_system
load_config
main_menu