#!/bin/bash
set -euo pipefail

# Глобальные переменные
readonly USERS=("dev_1" "audit_1" "devops_1")
readonly KEY_SIZE=2048
readonly CERT_VALIDITY_DAYS=365
readonly WORK_DIR="users"
readonly MINIKUBE_CA_CERT="$HOME/.minikube/ca.crt"
readonly MINIKUBE_CA_KEY="$HOME/.minikube/ca.key"

# Функция для логирования
log() {
    local level="$1"
    shift
    echo "[$level] $*"
}

# Функция для создания директории
create_working_directory() {
    log "INFO" "Создание рабочей директории: $WORK_DIR"
    mkdir -p "$WORK_DIR"
    cd "$WORK_DIR"
}

# Функция для генерации ключей и сертификатов пользователя
create_user_certificate() {
    local user="$1"
    log "INFO" "Обработка пользователя: $user"
    
    # Генерация приватного ключа
    openssl genrsa -out "${user}.key" "$KEY_SIZE"
    
    # Создание запроса на сертификат
    openssl req -new -key "${user}.key" -out "${user}.csr" -subj "/CN=$user"
    
    # Подписание сертификата Minikube CA
    openssl x509 -req -in "${user}.csr" \
        -CA "$MINIKUBE_CA_CERT" \
        -CAkey "$MINIKUBE_CA_KEY" \
        -CAcreateserial \
        -out "${user}.crt" \
        -days "$CERT_VALIDITY_DAYS"
    
    log "INFO" "Сертификат создан для $user"
}

# Функция для настройки kubeconfig
configure_kubeconfig() {
    local user="$1"
    local cluster_name="$2"
    
    kubectl config set-credentials "$user" \
        --client-certificate="${user}.crt" \
        --client-key="${user}.key" \
        --embed-certs=true
    
    kubectl config set-context "${user}-context" \
        --cluster="$cluster_name" \
        --user="$user"
}

# Функция для получения имени кластера
get_cluster_name() {
    kubectl config view -o jsonpath='{.clusters[0].name}'
}

# Функция для очистки временных файлов
cleanup_temp_files() {
    log "INFO" "Очистка временных файлов .csr"
    for user in "${USERS[@]}"; do
        rm -f "${user}.csr"
    done
}


# Основная функция
main() {
    log "INFO" "==> Создание пользователей: ${USERS[*]}..."
    
    create_working_directory
    
    # Создание сертификатов для всех пользователей
    for user in "${USERS[@]}"; do
        create_user_certificate "$user"
    done
    
    # Получение имени кластера
    local cluster_name
    cluster_name=$(get_cluster_name)
    
    log "INFO" "==> Настройка kubeconfig для кластера: $cluster_name"
    
    # Настройка kubeconfig для всех пользователей
    for user in "${USERS[@]}"; do
        configure_kubeconfig "$user" "$cluster_name"
    done
    
    # Очистка временных файлов
    cleanup_temp_files
    
    log "INFO" "Все пользователи добавлены в kubeconfig"
    log "INFO" "Работа завершена успешно"
}

# Проверка зависимостей
check_dependencies() {
    local deps=("openssl" "kubectl")
    for dep in "${deps[@]}"; do
        if ! command -v "$dep" >/dev/null 2>&1; then
            log "ERROR" "Команда $dep не найдена. Установите её и повторите попытку."
            exit 1
        fi
    done
}

# Проверка существования Minikube CA
check_minikube_ca() {
    if [[ ! -f "$MINIKUBE_CA_CERT" ]] || [[ ! -f "$MINIKUBE_CA_KEY" ]]; then
        log "ERROR" "Minikube CA не найден. Убедитесь, что Minikube запущен."
        exit 1
    fi
}

# Обработка ошибок
error_handler() {
    local exit_code=$?
    log "ERROR" "Скрипт завершился с ошибкой (код: $exit_code)"
    exit "$exit_code"
}

# Установка обработчика ошибок
trap error_handler ERR

# Запуск скрипта
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    check_dependencies
    check_minikube_ca
    main
fi
