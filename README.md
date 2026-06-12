# 🚀 Автоматическая установка GLPI на Ubuntu

Скрипт для автоматической установки [GLPI](https://glpi-project.org/) — системы управления IT-активами и сервис-деском — на серверах под управлением Ubuntu.

## 📋 Требования

- **ОС:** Ubuntu (рекомендуется 20.04/22.04/24.04)
- **Права:** root (запуск через `sudo`)
- **Интернет:** доступ к GitHub и APT-репозиториям
- **Диск:** минимум 1 ГБ свободного места

## ⚙️ Устанавливаемые компоненты

| Компонент | Версия/Параметры |
|-----------|-----------------|
| **GLPI** | 10.0.7 (настраивается) |
| **PHP** | 8.2 с необходимыми расширениями |
| **Веб-сервер** | Apache 2 |
| **БД** | MariaDB |
| **ОС** | Ubuntu |

### Расширения PHP

**Обязательные:**
- curl, gd, intl, mysqli, mbstring, bcmath

**Рекомендуемые:**
- apcu, bz2, exif, ldap, zip

**Системные:**
- cli, common, xml, xmlrpc, imap, redis

## 🗂️ Структура каталогов (FHS)

Скрипт следует стандарту Filesystem Hierarchy Standard:

| Каталог | Назначение | Владелец |
|---------|------------|----------|
| `/var/www/glpi` | Веб-файлы GLPI | root:root |
| `/etc/glpi` | Конфигурационные файлы | www-data:www-data |
| `/var/lib/glpi/files` | Загруженные файлы и данные | www-data:www-data |
| `/var/log/glpi` | Логи GLPI | www-data:www-data |
| `/var/lib/glpi/plugins` | Плагины | www-data:www-data |

### Права доступа

- **Веб-каталог:** корень только читает, www-data не имеет прав (безопасность)
- **Marketplace:** www-data имеет права на запись (установка плагинов)
- **Системные каталоги:** www-data читает и пишет (0750 для каталогов, 0640 для файлов)

## 🔧 Переменные окружения

Перед запуском можно переопределить переменные:

```bash
export GLPI_VERSION="10.0.12"
export MYSQL_ROOT_PASSWORD="strong_root_pass"
export DB_PASSWORD="strong_glpi_pass"
export SERVER_NAME="helpdesk.mydomain.com"
export PHP_VERSION="8.2"  # GLPI 10.0.x требует PHP < 8.3
```
## 🚀 Запуск
```bash
# Скачать скрипт
wget https://github.com/ChunkyMonkey1337/glpi-autoinstall/blob/main/autoinstall-glpi.sh

# Сделать исполняемым
chmod +x autoinstall-glpi.sh

# Запустить от root
sudo ./autoinstall-glpi.sh
```
При запуске без переменных окружения скрипт запросит:

   - Пароль для root MariaDB
   - Пароль для пользователя БД glpi

## 📊 Что делает скрипт
### 1. Проверки
- Права `root` 
- Совместимость ОС,
- Доступ в интернет,
- Свободное место на диске (≥ 1 ГБ)

### 2. Установка пакетов
- Добавление репозитория `ondrej/php`
- Установка `Apache, PHP 8.2, MariaDB`
- Установка всех необходимых расширений PHP

### 3. Настройка базы данных
- Защита MariaDB (удаление анонимных пользователей, test-БД)
- Загрузка временных зон
- Создание БД glpi `(utf8mb4_unicode_ci)`
- Создание пользователя glpi с правами на БД
- Предоставление прав на чтение таблицы `time_zone_name`

### 4. Загрузка и распаковка GLPI
- Скачивание из `GitHub Releases`
- Распаковка в `/var/www/glpi`
- Резервное копирование существующей установки (если есть)

### 5. Настройка структуры каталогов
- Создание системных каталогов
- Генерация `downstream.php` (переопределение пути конфигурации)
- Перемещение `config → /etc/glpi`
- Перемещение `files → /var/lib/glpi/files`
- Создание подкаталогов (`_cache, _log, _sessions` и др.)
- Генерация `local_define.php` для переопределения путей

### 6. Настройка PHP

Параметры в `/etc/php/8.2/apache2/php.ini:`

|Директива|Значение|
|---------|--------|
|`memory_limit` |	256M|
|`upload_max_filesize`|	20M|
|`post_max_size`|	25M|
|`max_execution_time`|	600|
|`session.cookie_httponly`|	On|
|`session.cookie_samesite`|	Lax|


### 7. Настройка Apache
- VirtualHost с DocumentRoot `/var/www/glpi/public`
- Включение `mod_rewrite` и `mod_headers`
- Настройка `front controller` (все запросы на index.php)
- Проброс заголовка `Authorization` (для API)
- Запрет доступа к системным каталогам


### 8. Настройка Cron

Задача в `/etc/cron.d/glpi:`
```cron

*/2 * * * * www-data /usr/bin/php /var/www/glpi/front/cron.php --force
```
## 📝 Логи
|Лог|Путь|
|---|----|
|Установки|	`/tmp/glpi-install.log` → `/var/log/glpi-install.log`|
|Apache (GLPI)	|`/var/log/apache2/glpi_error.log` и `glpi_access.log`|
|GLPI|	`/var/lib/glpi/files/_log`|

## 🌐 После установки
- Откройте браузер: `http://ваш-сервер`
- Пройдите мастер установки GLPI:
   *   Хост БД: localhost
   *   БД: glpi
   *   Пользователь БД: glpi
   *   Пароль: (указанный при установке)
- Мастер автоматически удалит install.php после завершения
