#!/usr/bin/env bash
# dnsubscription.sh - DN-Subscription HAProxy Manager
# Usage: dnsubscription.sh [command]
#   Commands: install, install-script, up, down, restart, status, logs, help

set -euo pipefail

# ===========================================
# CONSTANTS
# ===========================================
readonly APP_NAME="dn-subscription"
readonly APP_DIR="/opt/${APP_NAME}"
readonly REPOSITORY="erfanask-dev/dn-subscription"
readonly REPO_RAW_URL="https://raw.githubusercontent.com/${REPOSITORY}/refs/heads/main"
readonly SCRIPT_INSTALL_PATH="/usr/local/bin/dnsubscription"

# Colors
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# ===========================================
# UTILITY FUNCTIONS
# ===========================================

log_info()    { echo -e "${BLUE}[INFO]${NC} $*"; }
log_success() { echo -e "${GREEN}[OK]${NC} $*"; }
log_warn()    { echo -e "${YELLOW}[WARN]${NC} $*"; }
log_error()   { echo -e "${RED}[ERROR]${NC} $*"; }

die() {
    log_error "$*"
    exit 1
}

confirm() {
    local prompt="${1:-Continue?} [y/N] "
    local reply
    read -rp "$prompt" reply
    [[ "$reply" =~ ^[Yy]$ ]]
}

# ===========================================
# SYSTEM DETECTION FUNCTIONS
# ===========================================

check_sudo() {
    if [[ $EUID -ne 0 ]]; then
        die "This script must be run as root (use sudo)"
    fi
}

detect_os() {
    if [[ -f /etc/os-release ]]; then
        # shellcheck source=/dev/null
        . /etc/os-release
        OS_ID="${ID}"
        OS_VERSION="${VERSION_ID}"
        OS_NAME="${PRETTY_NAME}"
    elif [[ -f /etc/redhat-release ]]; then
        OS_ID="rhel"
        OS_NAME=$(cat /etc/redhat-release)
    elif [[ -f /etc/arch-release ]]; then
        OS_ID="arch"
        OS_NAME="Arch Linux"
    else
        die "Unsupported OS: cannot detect distribution"
    fi
    log_info "Detected OS: ${OS_NAME} (${OS_ID})"
}

get_package_manager() {
    case "${OS_ID}" in
        ubuntu|debian|linuxmint|pop|elementary|kali|parrot)
            PKG_MGR="apt"
            PKG_UPDATE="apt update -y"
            PKG_INSTALL="apt install -y"
            PKG_CHECK="dpkg -l"
            ;;
        fedora|centos|rhel|rocky|almalinux|nobara)
            if command -v dnf &>/dev/null; then
                PKG_MGR="dnf"
            else
                PKG_MGR="yum"
            fi
            PKG_UPDATE="${PKG_MGR} makecache -y"
            PKG_INSTALL="${PKG_MGR} install -y"
            PKG_CHECK="rpm -q"
            ;;
        arch|manjaro|endeavouros|garuda|artix)
            PKG_MGR="pacman"
            PKG_UPDATE="pacman -Sy --noconfirm"
            PKG_INSTALL="pacman -S --noconfirm"
            PKG_CHECK="pacman -Q"
            ;;
        *)
            die "Unsupported package manager for OS: ${OS_ID}"
            ;;
    esac
    log_info "Package manager: ${PKG_MGR}"
}

# ===========================================
# PACKAGE MANAGEMENT FUNCTIONS
# ===========================================

package_exists() {
    local pkg="$1"
    case "${PKG_MGR}" in
        apt)    dpkg -l "${pkg}" 2>/dev/null | grep -q "^ii" ;;
        dnf|yum) rpm -q "${pkg}" &>/dev/null ;;
        pacman) pacman -Q "${pkg}" &>/dev/null ;;
    esac
}

install_package() {
    local pkg="$1"
    if package_exists "${pkg}"; then
        log_success "Package '${pkg}' already installed"
        return 0
    fi
    log_info "Installing package: ${pkg}"
    eval "${PKG_INSTALL} ${pkg}" || die "Failed to install ${pkg}"
    log_success "Package '${pkg}' installed"
}

update_package_cache() {
    log_info "Updating package cache..."
    eval "${PKG_UPDATE}" || log_warn "Package cache update failed (continuing anyway)"
}

# ===========================================
# DOCKER FUNCTIONS
# ===========================================

check_docker() {
    if command -v docker &>/dev/null && docker compose version &>/dev/null; then
        log_success "Docker and Docker Compose are available"
        return 0
    fi
    return 1
}

install_docker() {
    log_info "Installing Docker..."

    case "${PKG_MGR}" in
        apt)
            install_package ca-certificates
            install_package curl
            install_package gnupg
            install_package lsb-release

            mkdir -p /etc/apt/keyrings
            curl -fsSL "https://download.docker.com/linux/${OS_ID}/gpg" | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
            echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/${OS_ID} $(lsb_release -cs) stable" > /etc/apt/sources.list.d/docker.list
            update_package_cache
            install_package docker-ce
            install_package docker-ce-cli
            install_package containerd.io
            install_package docker-compose-plugin
            ;;
        dnf|yum)
            install_package dnf-plugins-core || install_package yum-utils
            ${PKG_MGR} config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
            update_package_cache
            install_package docker-ce
            install_package docker-ce-cli
            install_package containerd.io
            install_package docker-compose-plugin
            ;;
        pacman)
            install_package docker
            install_package docker-compose
            systemctl enable --now docker
            ;;
    esac

    systemctl enable --now docker 2>/dev/null || true
    log_success "Docker installed and started"
}

ensure_docker() {
    if check_docker; then
        return 0
    fi
    log_warn "Docker not found, installing..."
    install_docker
    check_docker || die "Docker installation failed"
}

# ===========================================
# DIRECTORY & FILE FUNCTIONS
# ===========================================

check_app_dir() {
    [[ -d "${APP_DIR}" ]]
}

create_app_dir() {
    mkdir -p "${APP_DIR}"
    log_success "Created directory: ${APP_DIR}"
}

download_file() {
    local url="$1"
    local dest="$2"
    log_info "Downloading: ${url}"
    curl -fsSL "${url}" -o "${dest}" || die "Failed to download ${url}"
    log_success "Downloaded to: ${dest}"
}

# ===========================================
# CONFIGURATION FUNCTIONS
# ===========================================

prompt_port() {
    local name="$1"
    local default="$2"
    local port

    while true; do
        read -rp "Enter ${name} port [${default}]: " port
        port="${port:-${default}}"
        if [[ "${port}" =~ ^[0-9]+$ ]] && (( port >= 1 && port <= 65535 )); then
            echo "${port}"
            return 0
        fi
        log_error "Invalid port. Must be 1-65535"
    done
}

prompt_password() {
    local password
    local confirm_pass

    while true; do
        read -rsp "Enter monitoring password: " password
        echo
        read -rsp "Confirm monitoring password: " confirm_pass
        echo

        if [[ -z "${password}" ]]; then
            log_error "Password cannot be empty"
            continue
        fi

        if [[ "${password}" == "${confirm_pass}" ]]; then
            echo "${password}"
            return 0
        fi
        log_error "Passwords do not match. Try again."
    done
}

configure_haproxy() {
    local haproxy_cfg="${APP_DIR}/haproxy.cfg"

    log_info "Configuring HAProxy..."

    local dash_port
    local panel_port
    local default_port
    local monitor_pass

    dash_port=$(prompt_port "dash server" "8080")
    panel_port=$(prompt_port "panel server" "3000")
    default_port=$(prompt_port "default server" "80")
    monitor_pass=$(prompt_password)

    # Use awk for safe replacement (handles special chars in password)
    awk -v dash_port="${dash_port}" \
        -v panel_port="${panel_port}" \
        -v default_port="${default_port}" \
        -v monitor_pass="${monitor_pass}" \
        '{
            gsub(/<DASH_TARGET_IP>:<DASH_TARGET_PORT>/, "127.0.0.1:" dash_port)
            gsub(/<PANEL_TARGET_IP>:<PANEL_TARGET_PORT>/, "127.0.0.1:" panel_port)
            gsub(/<DEFAULT_TARGET_IP>:<DEFAULT_TARGET_PORT>/, "127.0.0.1:" default_port)
            gsub(/<CHANGE_THIS_PASSWORD>/, monitor_pass)
            print
        }' "${haproxy_cfg}" > "${haproxy_cfg}.tmp" && mv "${haproxy_cfg}.tmp" "${haproxy_cfg}"

    log_success "HAProxy configured with:"
    log_info "  dash.subdigital.network -> 127.0.0.1:${dash_port}"
    log_info "  panel.subdigital.network -> 127.0.0.1:${panel_port}"
    log_info "  default -> 127.0.0.1:${default_port}"
    log_info "  Stats password: [hidden]"
}

# ===========================================
# INSTALL FUNCTIONS
# ===========================================

install_app() {
    log_info "Starting ${APP_NAME} installation..."

    check_sudo
    detect_os
    get_package_manager
    update_package_cache
    ensure_docker

    if check_app_dir; then
        log_warn "Directory ${APP_DIR} already exists"
        if confirm "Overwrite existing installation?"; then
            rm -rf "${APP_DIR}"
            create_app_dir
        else
            log_info "Installation cancelled"
            exit 0
        fi
    else
        create_app_dir
    fi

    download_file "${REPO_RAW_URL}/docker-compose.yaml" "${APP_DIR}/docker-compose.yaml"
    download_file "${REPO_RAW_URL}/haproxy.cfg" "${APP_DIR}/haproxy.cfg"

    # Create certs directory
    mkdir -p "${APP_DIR}/certs"
    log_info "Created certs directory: ${APP_DIR}/certs"
    log_warn "Place your SSL certificates (.pem files) in ${APP_DIR}/certs/"

    configure_haproxy

    log_success "Installation complete!"
    log_info "Files installed in: ${APP_DIR}"
    log_info "Next steps:"
    log_info "  1. Add SSL certificates to ${APP_DIR}/certs/"
    log_info "  2. Run: dnsubscription up"
}

install_script() {
    local script_source="${BASH_SOURCE[0]}"

    log_info "Installing CLI script to ${SCRIPT_INSTALL_PATH}..."
    cp "${script_source}" "${SCRIPT_INSTALL_PATH}"
    chmod +x "${SCRIPT_INSTALL_PATH}"
    log_success "CLI installed. You can now run 'dnsubscription' from anywhere"
}

uninstall_app() {
    log_info "Uninstalling ${APP_NAME}..."

    check_sudo

    if ! check_app_dir; then
        log_warn "Installation not found at ${APP_DIR}"
        return 0
    fi

    if ! confirm "This will remove ${APP_DIR} and stop all services. Continue?"; then
        log_info "Uninstall cancelled"
        return 0
    fi

    # Stop services if running
    if cd "${APP_DIR}" 2>/dev/null && docker compose ps -q | grep -q .; then
        log_info "Stopping services..."
        docker compose down || true
    fi

    # Remove app directory
    rm -rf "${APP_DIR}"
    log_success "Removed ${APP_DIR}"

    # Remove CLI script if installed
    if [[ -f "${SCRIPT_INSTALL_PATH}" ]]; then
        if confirm "Also remove CLI command from ${SCRIPT_INSTALL_PATH}?"; then
            rm -f "${SCRIPT_INSTALL_PATH}"
            log_success "Removed CLI command"
        fi
    fi

    log_success "Uninstall complete"
}

# ===========================================
# DOCKER COMPOSE WRAPPER
# ===========================================

dc_exec() {
    local args=("$@")
    cd "${APP_DIR}" || die "App directory not found: ${APP_DIR}"
    docker compose "${args[@]}"
}

cmd_up() {
    log_info "Starting services..."
    dc_exec up -d
    log_success "Services started"
}

cmd_down() {
    log_info "Stopping services..."
    dc_exec down
    log_success "Services stopped"
}

cmd_restart() {
    log_info "Restarting services..."
    dc_exec down
    dc_exec up -d
    log_success "Services restarted"
}

cmd_status() {
    cd "${APP_DIR}" || die "App directory not found: ${APP_DIR}"
    docker compose ps
}

cmd_logs() {
    cd "${APP_DIR}" || die "App directory not found: ${APP_DIR}"
    docker compose logs -f
}

# ===========================================
# MENU & MAIN
# ===========================================

show_menu() {
    cat <<EOF
===========================================
  ${APP_NAME} Manager
===========================================
  1) install        - Install ${APP_NAME} (docker, configs, certs)
  2) install-script - Install this script as 'dnsubscription' command
  3) up             - Start services (docker compose up -d)
  4) down           - Stop services (docker compose down)
  5) restart        - Restart services (down then up)
  6) status         - Show service status (docker compose ps)
  7) logs           - Follow logs (docker compose logs -f)
  8) uninstall      - Uninstall ${APP_NAME} completely
  9) help           - Show this menu
  0) Exit
===========================================
EOF
}

run_menu() {
    while true; do
        show_menu
        read -rp "Select option [0-9]: " choice
        case "${choice}" in
            1) install_app ;;
            2) install_script ;;
            3) cmd_up ;;
            4) cmd_down ;;
            5) cmd_restart ;;
            6) cmd_status ;;
            7) cmd_logs ;;
            8) uninstall_app ;;
            9) show_menu ;;
            0) log_info "Goodbye!"; exit 0 ;;
            *) log_error "Invalid option" ;;
        esac
        echo
    done
}

main() {
    local cmd="${1:-}"

    case "${cmd}" in
        install)        install_app ;;
        install-script) install_script ;;
        up)             cmd_up ;;
        down)           cmd_down ;;
        restart)        cmd_restart ;;
        status)         cmd_status ;;
        logs)           cmd_logs ;;
        uninstall)        uninstall_app ;;
        menu|"")        run_menu ;;
        help|--help|-h)
            cat <<EOF
Usage: dnsubscription [command]

Commands:
  install         Install ${APP_NAME} (docker, configs, certificates)
  install-script  Install this script as system-wide 'dnsubscription' command
  uninstall       Uninstall ${APP_NAME} completely (remove configs, stop services)
  up              Start all services
  down            Stop all services
  restart         Restart all services
  status          Show service status
  logs            Follow service logs
  menu            Show interactive menu (default)
  help            Show this help

Examples:
  sudo dnsubscription install
  sudo dnsubscription uninstall
  dnsubscription up
  dnsubscription logs
  dnsubscription menu
EOF
            ;;
        *)
            log_error "Unknown command: ${cmd}"
            log_info "Run 'dnsubscription help' for usage"
            exit 1
            ;;
    esac
}

main "$@"