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
