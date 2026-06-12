#!/bin/bash

# =============================================
# Скрипт автоматической установки GLPI на Ubuntu
# Основан на официальной документации:
# https://glpi-install.readthedocs.io/en/latest/install/index.html
# =============================================

set -euo pipefail
IFS=$'\n\t'

# ─── НАСТРОЙКИ ────────────────────────────────────────────────────────────────
GLPI_VERSION="${GLPI_VERSION:-10.0.7}"
MYSQL_ROOT_PASSWORD="${MYSQL_ROOT_PASSWORD:-}"
DB_PASSWORD="${DB_PASSWORD:-}"
SERVER_NAME="${SERVER_NAME:-glpi.local}"
PHP_VERSION="${PHP_VERSION:-8.2}"         # GLPI 10.0.7 требует PHP < 8.3, максимум 8.2

# Пути согласно официальной документации (FHS)
GLPI_INSTALL_DIR="/var/www/glpi"         # Документация: /var/www/glpi
GLPI_CONFIG_DIR="/etc/glpi"
GLPI_VAR_DIR="/var/lib/glpi/files"       # Документация: /var/lib/glpi/files
GLPI_LOG_DIR_PATH="/var/log/glpi"
GLPI_PLUGINS_DIR="/var/lib/glpi/plugins"

LOG_FILE="/tmp/glpi-install.log"         # /tmp точно существует с самого начала
# ──────────────────────────────────────────────────────────────────────────────

# ─── ЦВЕТА И ВЫВОД ────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m'

log()    { local msg="[$(date '+%H:%M:%S')] $*"; echo -e "${GREEN}${msg}${NC}"; echo "$msg" >> "$LOG_FILE"; }
warn()   { local msg="[$(date '+%H:%M:%S')] ⚠️  $*"; echo -e "${YELLOW}${msg}${NC}"; echo "$msg" >> "$LOG_FILE"; }
error()  { local msg="[$(date '+%H:%M:%S')] ❌ $*"; echo -e "${RED}${msg}${NC}" >&2; echo "$msg" >> "$LOG_FILE"; }
header() { echo -e "\n${BOLD}${BLUE}══════════════════════════════════════${NC}"; \
           echo -e "${BOLD}${BLUE}  $*${NC}"; \
           echo -e "${BOLD}${BLUE}══════════════════════════════════════${NC}"; \
           echo "=== $* ===" >> "$LOG_FILE"; }
step()   { echo -e "\n${BOLD}$*${NC}"; echo "--- $*" >> "$LOG_FILE"; }
# ──────────────────────────────────────────────────────────────────────────────

# ─── ПРОВЕРКИ ─────────────────────────────────────────────────────────────────
check_root() {
    if [[ $EUID -ne 0 ]]; then
        error "Скрипт должен запускаться от root. Используйте: sudo $0"
        exit 1
    fi
}

check_os() {
    if ! grep -qi ubuntu /etc/os-release 2>/dev/null; then
        warn "Скрипт оптимизирован под Ubuntu. На других дистрибутивах возможны ошибки."
    fi
    if ! command -v apt &>/dev/null; then
        error "apt не найден. Скрипт поддерживает только Debian-based системы."
        exit 1
    fi
}

check_internet() {
    log "Проверка доступа к интернету..."
    if ! curl -fsS --max-time 10 https://github.com -o /dev/null; then
        error "Нет доступа к интернету. Проверьте сетевое подключение."
        exit 1
    fi
}

check_disk_space() {
    # Ищем существующий родительский каталог для проверки места
    local check_path="/var/www"
    if [[ ! -d "$check_path" ]]; then
        check_path="/var"
    fi

    local required_mb=1024
    local available_mb
    available_mb=$(df "$check_path" --output=avail -m | tail -1 | tr -d ' ')
    if [[ $available_mb -lt $required_mb ]]; then
        error "Недостаточно места на диске. Требуется минимум ${required_mb}MB, доступно ${available_mb}MB."
        exit 1
    fi
    log "Свободное место на диске: ${available_mb}MB — OK"
}
# ──────────────────────────────────────────────────────────────────────────────

# ─── ЗАПРОС ПАРОЛЕЙ ───────────────────────────────────────────────────────────
ask_password() {
    local prompt="$1"
    local varname="$2"
    local pw confirm

    while true; do
        read -rsp "${prompt}: " pw; echo
        if [[ -z "$pw" ]]; then
            warn "Пароль не может быть пустым. Попробуйте снова."
            continue
        fi
        read -rsp "Подтвердите пароль: " confirm; echo
        if [[ "$pw" == "$confirm" ]]; then
            printf -v "$varname" '%s' "$pw"
            break
        else
            warn "Пароли не совпадают. Попробуйте снова."
        fi
    done
}

collect_passwords() {
    if [[ -z "$MYSQL_ROOT_PASSWORD" ]]; then
        ask_password "Введите пароль для root MariaDB" MYSQL_ROOT_PASSWORD
    fi
    if [[ -z "$DB_PASSWORD" ]]; then
        ask_password "Введите пароль для пользователя БД 'glpi'" DB_PASSWORD
    fi
}
# ──────────────────────────────────────────────────────────────────────────────

# ─── УСТАНОВКА ПАКЕТОВ ────────────────────────────────────────────────────────
install_packages() {
    step "📦 1. Установка пакетов (Apache, PHP ${PHP_VERSION}, MariaDB)..."

    # Репозиторий Ondřej Surý для актуальной версии PHP
    if ! grep -rq "ondrej/php" /etc/apt/sources.list.d/ 2>/dev/null; then
        log "Добавление репозитория ondrej/php..."
        DEBIAN_FRONTEND=noninteractive apt-get install -y -q software-properties-common
        add-apt-repository -y ppa:ondrej/php
    fi

    DEBIAN_FRONTEND=noninteractive apt-get update -q
    DEBIAN_FRONTEND=noninteractive apt-get upgrade -y -q

    # Расширения PHP для GLPI 10.0.x
    # openssl и zlib встроены в php-common — отдельных пакетов нет
    local php_extensions=(
        # Обязательные
        curl gd intl mysqli mbstring bcmath
        # Рекомендуемые
        apcu bz2 exif ldap zip
        # Системные
        cli common xml xmlrpc imap redis
    )

    local php_packages=()
    for ext in "${php_extensions[@]}"; do
        php_packages+=("php${PHP_VERSION}-${ext}")
    done

    DEBIAN_FRONTEND=noninteractive apt-get install -y -q \
        apache2 \
        "php${PHP_VERSION}" \
        "${php_packages[@]}" \
        "libapache2-mod-php${PHP_VERSION}" \
        mariadb-server \
        wget curl

    # Переключаем на нужную версию PHP, если их несколько
    local installed_php
    installed_php=$(php -r 'echo PHP_MAJOR_VERSION.".".PHP_MINOR_VERSION;' 2>/dev/null || echo "")
    if [[ "$installed_php" != "$PHP_VERSION" ]]; then
        log "Переключаем PHP на версию ${PHP_VERSION}..."
        update-alternatives --set php "/usr/bin/php${PHP_VERSION}" || true
    fi

    log "Пакеты установлены."
}
# ──────────────────────────────────────────────────────────────────────────────

# ─── НАСТРОЙКА БД ─────────────────────────────────────────────────────────────
configure_database() {
    step "🗄️  2. Настройка MariaDB..."

    systemctl enable --now mariadb

    # Задаём пароль root и выполняем базовое hardening
    if mysql -u root -e "SELECT 1;" &>/dev/null 2>&1; then
        log "Настройка пароля root и безопасности MariaDB..."
        mysql -u root <<SQL
ALTER USER 'root'@'localhost' IDENTIFIED BY '${MYSQL_ROOT_PASSWORD}';
DELETE FROM mysql.user WHERE User='';
DELETE FROM mysql.user WHERE User='root' AND Host NOT IN ('localhost','127.0.0.1','::1');
DROP DATABASE IF EXISTS test;
DELETE FROM mysql.db WHERE Db='test' OR Db='test\\_%';
FLUSH PRIVILEGES;
SQL
    else
        log "Пароль root уже установлен."
    fi

    # Загрузка временных зон (нужно для GLPI)
    log "Загрузка временных зон в MariaDB..."
    mysql_tzinfo_to_sql /usr/share/zoneinfo 2>/dev/null \
        | mysql -u root -p"${MYSQL_ROOT_PASSWORD}" mysql \
        || warn "Не удалось загрузить timezone данные — можно загрузить вручную позже."

    # Создание БД и пользователя
    log "Создание базы данных и пользователя 'glpi'..."
    mysql -u root -p"${MYSQL_ROOT_PASSWORD}" <<SQL
CREATE DATABASE IF NOT EXISTS glpi CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER IF NOT EXISTS 'glpi'@'localhost' IDENTIFIED BY '${DB_PASSWORD}';
GRANT ALL PRIVILEGES ON glpi.* TO 'glpi'@'localhost';
GRANT SELECT ON mysql.time_zone_name TO 'glpi'@'localhost';
FLUSH PRIVILEGES;
SQL

    log "База данных настроена."
}
# ──────────────────────────────────────────────────────────────────────────────

# ─── ЗАГРУЗКА GLPI ────────────────────────────────────────────────────────────
download_glpi() {
    step "📥 3. Загрузка GLPI ${GLPI_VERSION}..."

    local archive="/tmp/glpi-${GLPI_VERSION}.tgz"
    local url="https://github.com/glpi-project/glpi/releases/download/${GLPI_VERSION}/glpi-${GLPI_VERSION}.tgz"

    if [[ ! -f "$archive" ]]; then
        log "Скачивание: $url"
        wget --progress=bar:force -O "$archive" "$url" 2>&1 | tail -1 || {
            error "Не удалось скачать GLPI. Проверьте версию и доступ к GitHub."
            rm -f "$archive"
            exit 1
        }
    else
        log "Архив уже скачан, используем кеш: $archive"
    fi

    # Резервная копия существующей установки
    if [[ -d "$GLPI_INSTALL_DIR" ]]; then
        local backup="${GLPI_INSTALL_DIR}.bak.$(date +%Y%m%d_%H%M%S)"
        warn "Найдена существующая установка. Резервная копия: $backup"
        mv "$GLPI_INSTALL_DIR" "$backup"
    fi

    mkdir -p /var/www
    log "Распаковка в /var/www..."
    tar -xzf "$archive" -C /var/www/
    rm -f "$archive"

    # Архив распаковывается в /var/www/glpi
    log "GLPI распакован: $GLPI_INSTALL_DIR"
}
# ──────────────────────────────────────────────────────────────────────────────

# ─── СТРУКТУРА КАТАЛОГОВ ──────────────────────────────────────────────────────
configure_directories() {
    step "📂 4. Настройка структуры каталогов согласно документации (FHS)..."

    # Создаём системные каталоги
    mkdir -p "$GLPI_CONFIG_DIR" "$GLPI_VAR_DIR" "$GLPI_LOG_DIR_PATH" "$GLPI_PLUGINS_DIR"

    # --- downstream.php ---
    # Переопределяет путь к конфигурации; не редактировать если существует (пакетная установка)
    if [[ ! -f "${GLPI_INSTALL_DIR}/inc/downstream.php" ]]; then
        cat > "${GLPI_INSTALL_DIR}/inc/downstream.php" <<'PHP'
<?php
define('GLPI_CONFIG_DIR', '/etc/glpi/');

if (file_exists(GLPI_CONFIG_DIR . '/local_define.php')) {
    require_once GLPI_CONFIG_DIR . '/local_define.php';
}
PHP
    fi

    # --- Перемещение config → /etc/glpi ---
    if [[ -d "${GLPI_INSTALL_DIR}/config" ]]; then
        cp -a "${GLPI_INSTALL_DIR}/config/." "${GLPI_CONFIG_DIR}/"
        rm -rf "${GLPI_INSTALL_DIR}/config"
        log "config → ${GLPI_CONFIG_DIR}"
    else
        warn "Каталог ${GLPI_INSTALL_DIR}/config не найден."
    fi

    # --- Перемещение files → /var/lib/glpi/files ---
    if [[ -d "${GLPI_INSTALL_DIR}/files" ]]; then
        cp -a "${GLPI_INSTALL_DIR}/files/." "${GLPI_VAR_DIR}/"
        rm -rf "${GLPI_INSTALL_DIR}/files"
        log "files → ${GLPI_VAR_DIR}"
    else
        warn "Каталог ${GLPI_INSTALL_DIR}/files не найден."
    fi

    # --- Поддиректории внутри GLPI_VAR_DIR ---
    local data_dirs=(
        _cache _cron _dumps _graphs _lock _pictures
        _plugins _rss _sessions _tmp _uploads _inventories _themes _locales _log
    )
    for dir in "${data_dirs[@]}"; do
        mkdir -p "${GLPI_VAR_DIR}/${dir}"
    done

    # --- local_define.php согласно документации ---
    # https://glpi-install.readthedocs.io/en/latest/install/index.html#files-and-directories-locations
    cat > "${GLPI_CONFIG_DIR}/local_define.php" <<PHP
<?php
define('GLPI_VAR_DIR',          '/var/lib/glpi/files');
define('GLPI_DOC_DIR',          GLPI_VAR_DIR);
define('GLPI_CACHE_DIR',        GLPI_VAR_DIR . '/_cache');
define('GLPI_CRON_DIR',         GLPI_VAR_DIR . '/_cron');
define('GLPI_GRAPH_DIR',        GLPI_VAR_DIR . '/_graphs');
define('GLPI_LOCAL_I18N_DIR',   GLPI_VAR_DIR . '/_locales');
define('GLPI_LOCK_DIR',         GLPI_VAR_DIR . '/_lock');
define('GLPI_LOG_DIR',          GLPI_VAR_DIR . '/_log');
define('GLPI_PICTURE_DIR',      GLPI_VAR_DIR . '/_pictures');
define('GLPI_PLUGIN_DOC_DIR',   GLPI_VAR_DIR . '/_plugins');
define('GLPI_RSS_DIR',          GLPI_VAR_DIR . '/_rss');
define('GLPI_SESSION_DIR',      GLPI_VAR_DIR . '/_sessions');
define('GLPI_TMP_DIR',          GLPI_VAR_DIR . '/_tmp');
define('GLPI_UPLOAD_DIR',       GLPI_VAR_DIR . '/_uploads');
define('GLPI_INVENTORY_DIR',    GLPI_VAR_DIR . '/_inventories');
define('GLPI_THEMES_DIR',       GLPI_VAR_DIR . '/_themes');

PHP

    log "Структура каталогов настроена."
}
# ──────────────────────────────────────────────────────────────────────────────

# ─── ПРАВА ДОСТУПА ────────────────────────────────────────────────────────────
configure_permissions() {
    step "🔐 5. Установка прав доступа..."

    # Веб-каталог — root:root, www-data только читает
    chown -R root:root "$GLPI_INSTALL_DIR"
    find "$GLPI_INSTALL_DIR" -type f -exec chmod 0644 {} \;
    find "$GLPI_INSTALL_DIR" -type d -exec chmod 0755 {} \;

     
    # Marketplace — www-data должен иметь права на запись (создание/установка плагинов)
    mkdir -p "${GLPI_INSTALL_DIR}/marketplace"
    chown -R www-data:www-data "${GLPI_INSTALL_DIR}/marketplace"
    chmod -R 0755 "${GLPI_INSTALL_DIR}/marketplace"
    log "marketplace → www-data:www-data 755"
 


    # Системные каталоги — www-data читает и пишет
    for dir in "$GLPI_CONFIG_DIR" "$GLPI_VAR_DIR" "$GLPI_LOG_DIR_PATH" "$GLPI_PLUGINS_DIR"; do
        chown -R www-data:www-data "$dir"
        find "$dir" -type f -exec chmod 0640 {} \;
        find "$dir" -type d -exec chmod 0750 {} \;
    done

    log "Права доступа установлены."
}
# ──────────────────────────────────────────────────────────────────────────────

# ─── НАСТРОЙКА PHP ────────────────────────────────────────────────────────────
configure_php() {
    step "⚙️  6. Настройка PHP..."

    local php_ini="/etc/php/${PHP_VERSION}/apache2/php.ini"

    if [[ ! -f "$php_ini" ]]; then
        warn "Файл $php_ini не найден. Пропускаем настройку PHP."
        return
    fi

    set_php_ini() {
        local key="$1" value="$2"
        if grep -qE "^;?[[:space:]]*${key}[[:space:]]*=" "$php_ini"; then
            sed -i -E "s|^;?[[:space:]]*${key}[[:space:]]*=.*|${key} = ${value}|" "$php_ini"
        else
            echo "${key} = ${value}" >> "$php_ini"
        fi
    }

    set_php_ini "memory_limit"              "256M"
    set_php_ini "upload_max_filesize"       "20M"
    set_php_ini "post_max_size"             "25M"
    set_php_ini "max_execution_time"        "600"
    # Настройки безопасности сессий согласно документации
    set_php_ini "session.cookie_httponly"   "On"
    set_php_ini "session.cookie_samesite"   "Lax"
    # session.cookie_secure = On — только при наличии HTTPS
    # set_php_ini "session.cookie_secure"  "On"

    log "PHP настроен: $php_ini"
}
# ──────────────────────────────────────────────────────────────────────────────

# ─── НАСТРОЙКА APACHE ─────────────────────────────────────────────────────────
configure_apache() {
    step "🌐 7. Настройка Apache VirtualHost..."

    # Конфигурация из официальной документации
    cat > /etc/apache2/sites-available/glpi.conf <<APACHECONF
<VirtualHost *:80>
    ServerName ${SERVER_NAME}
    DocumentRoot ${GLPI_INSTALL_DIR}/public

    <Directory ${GLPI_INSTALL_DIR}/public>
        Require all granted

        RewriteEngine On

        # Проброс заголовка Authorization (нужен для API и CalDAV)
        RewriteCond %{HTTP:Authorization} ^(.+)$
        RewriteRule .* - [E=HTTP_AUTHORIZATION:%{HTTP:Authorization}]

        # Front controller — все запросы на index.php если файл не существует
        RewriteCond %{REQUEST_FILENAME} !-f
        RewriteRule ^(.*)$ index.php [QSA,L]
    </Directory>

    # Явный запрет доступа к системным каталогам вне DocumentRoot
    # (они уже вынесены из /var/www/glpi, но на всякий случай)
    <LocationMatch "^/(config|files|scripts|vendor|tests)/">
        Require all denied
    </LocationMatch>

    ErrorLog  \${APACHE_LOG_DIR}/glpi_error.log
    CustomLog \${APACHE_LOG_DIR}/glpi_access.log combined
</VirtualHost>
APACHECONF

    a2ensite glpi.conf
    a2dissite 000-default.conf 2>/dev/null || true
    a2enmod rewrite headers

    if apache2ctl configtest 2>&1 | grep -q "Syntax OK"; then
        systemctl restart apache2
        log "Apache перезапущен."
    else
        error "Ошибка в конфигурации Apache. Запустите: apache2ctl configtest"
        exit 1
    fi
}
# ──────────────────────────────────────────────────────────────────────────────

# ─── НАСТРОЙКА CRON ───────────────────────────────────────────────────────────
configure_cron() {
    step "⏰ 8. Настройка cron..."

    local cron_file="/etc/cron.d/glpi"
    if [[ ! -f "$cron_file" ]]; then
        cat > "$cron_file" <<CRON
# GLPI — автоматические задачи (каждые 2 минуты)
*/2 * * * * www-data /usr/bin/php ${GLPI_INSTALL_DIR}/front/cron.php --force > /dev/null 2>&1
CRON
        chmod 0644 "$cron_file"
        log "Cron задача создана: $cron_file"
    else
        log "Cron задача уже существует."
    fi
}
# ──────────────────────────────────────────────────────────────────────────────

# ─── ИТОГОВЫЙ ОТЧЁТ ───────────────────────────────────────────────────────────
print_summary() {
    # Копируем лог в финальное место
    cp "$LOG_FILE" /var/log/glpi-install.log 2>/dev/null || true

    echo ""
    echo -e "${BOLD}${GREEN}╔════════════════════════════════════════════════╗${NC}"
    echo -e "${BOLD}${GREEN}║   ✅  GLPI ${GLPI_VERSION} успешно установлен!          ║${NC}"
    echo -e "${BOLD}${GREEN}╚════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "  🔗 ${BOLD}URL:${NC}              http://${SERVER_NAME}"
    echo -e "  📋 ${BOLD}База данных:${NC}      glpi"
    echo -e "  👤 ${BOLD}Пользователь БД:${NC}  glpi"
    echo -e "  🔑 ${BOLD}Пароль БД:${NC}        (указан при установке)"
    echo ""
    echo -e "  📁 ${BOLD}Каталоги:${NC}"
    echo -e "     Веб-файлы:     ${GLPI_INSTALL_DIR}"
    echo -e "     Конфигурация:  ${GLPI_CONFIG_DIR}"
    echo -e "     Данные:        ${GLPI_VAR_DIR}"
    echo -e "     Плагины:       ${GLPI_PLUGINS_DIR}"
    echo -e "     Логи GLPI:     ${GLPI_VAR_DIR}/_log"
    echo -e "     Лог установки: /var/log/glpi-install.log"
    echo ""
    echo -e "  ${YELLOW}⚠️  Следующие шаги:${NC}"
    echo -e "     1. Откройте http://${SERVER_NAME} и пройдите мастер установки"
    echo -e "     2. В мастере укажите БД: хост=localhost, БД=glpi, пользователь=glpi"
    echo -e "     3. После установки мастер удалит install.php автоматически"
    echo -e "     4. Для HTTPS: настройте certbot/Let's Encrypt и включите"
    echo -e "        session.cookie_secure = On в /etc/php/${PHP_VERSION}/apache2/php.ini"
    echo ""
}
# ──────────────────────────────────────────────────────────────────────────────

# ─── ТОЧКА ВХОДА ──────────────────────────────────────────────────────────────
main() {
    # Инициализация лога ДО любых команд с set -e
    : > "$LOG_FILE"
    chmod 600 "$LOG_FILE"

    header "Установка GLPI ${GLPI_VERSION}"

    check_root
    check_os
    check_internet
    check_disk_space
    collect_passwords

    install_packages
    configure_database
    download_glpi
    configure_directories
    configure_permissions
    configure_php
    configure_apache
    configure_cron

    print_summary
}

main "$@"