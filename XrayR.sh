#!/usr/bin/env bash

set -u

REPO='qqlikegi/XrayR-096'
INSTALLER_URL="https://raw.githubusercontent.com/${REPO}/master/install.sh"
SERVICE_FILE='/etc/systemd/system/XrayR.service'
CONFIG_FILE='/etc/XrayR/config.yml'

if [[ ${EUID} -ne 0 ]]; then
    echo '请使用 root 用户运行 xrayr。' >&2
    exit 1
fi

run_installer() {
    local version="${1:-}"
    local installer
    installer=$(mktemp)
    if ! curl --fail --location --silent --show-error "$INSTALLER_URL" -o "$installer"; then
        echo '无法从个人仓库下载安装脚本。' >&2
        rm -f "$installer"
        return 1
    fi
    if [[ -n $version ]]; then
        bash "$installer" "$version"
    else
        bash "$installer"
    fi
    local result=$?
    rm -f "$installer"
    return "$result"
}

installed() { [[ -f $SERVICE_FILE ]]; }

install_xrayr() {
    if installed; then
        echo 'XrayR 已安装；如需升级，请选择“更新”。'
        return 1
    fi
    run_installer "${1:-}"
}

update_xrayr() {
    local version="${1:-}"
    if [[ -z $version ]]; then
        read -r -p '输入版本号（留空安装最新版）: ' version
    fi
    run_installer "$version"
}

uninstall_xrayr() {
    local answer
    read -r -p '确定卸载 XrayR 并删除 /etc/XrayR 配置吗？[y/N] ' answer
    case "$answer" in y|Y|yes|YES) ;; *) echo '已取消。'; return 0 ;; esac
    systemctl stop XrayR 2>/dev/null || true
    systemctl disable XrayR 2>/dev/null || true
    rm -f "$SERVICE_FILE"
    systemctl daemon-reload
    systemctl reset-failed 2>/dev/null || true
    rm -rf /etc/XrayR /usr/local/XrayR
    echo 'XrayR 程序和配置已卸载。管理菜单仍保留，可再次安装。'
}

edit_config() {
    if [[ ! -f $CONFIG_FILE ]]; then
        echo "配置文件不存在：$CONFIG_FILE"
        return 1
    fi
    if command -v nano >/dev/null 2>&1; then
        nano "$CONFIG_FILE"
    else
        vi "$CONFIG_FILE"
    fi
    if installed; then
        local answer
        read -r -p '配置已编辑，是否重启 XrayR？[Y/n] ' answer
        if [[ -z $answer || $answer == y || $answer == Y ]]; then
            systemctl restart XrayR
        fi
    fi
}

run_action() {
    case "${1:-}" in
        install) install_xrayr "${2:-}" ;;
        update) update_xrayr "${2:-}" ;;
        uninstall) uninstall_xrayr ;;
        start) systemctl start XrayR ;;
        stop) systemctl stop XrayR ;;
        restart) systemctl restart XrayR ;;
        status) systemctl status XrayR --no-pager -l ;;
        log|logs) journalctl -u XrayR.service -e --no-pager -f ;;
        config) edit_config ;;
        enable) systemctl enable XrayR ;;
        disable) systemctl disable XrayR ;;
        version)
            if [[ -x /usr/local/XrayR/XrayR ]]; then
                /usr/local/XrayR/XrayR -version
            else
                echo 'XrayR 未安装。'
            fi
            ;;
        *) return 2 ;;
    esac
}

show_menu() {
    while true; do
        echo
        echo 'XrayR 后端管理菜单'
        if installed; then
            if systemctl is-active --quiet XrayR; then
                echo '状态：运行中'
            else
                echo '状态：已安装，未运行'
            fi
        else
            echo '状态：未安装'
        fi
        echo '--------------------------------'
        echo '1. 安装 XrayR'
        echo '2. 更新 XrayR'
        echo '3. 卸载 XrayR'
        echo '4. 启动 XrayR'
        echo '5. 停止 XrayR'
        echo '6. 重启 XrayR'
        echo '7. 查看状态'
        echo '8. 查看日志'
        echo '9. 修改配置'
        echo '10. 设置开机自启'
        echo '11. 取消开机自启'
        echo '12. 查看版本'
        echo '0. 退出'
        read -r -p '请输入选项: ' choice
        case "$choice" in
            1) install_xrayr ;;
            2) update_xrayr ;;
            3) uninstall_xrayr ;;
            4) systemctl start XrayR ;;
            5) systemctl stop XrayR ;;
            6) systemctl restart XrayR ;;
            7) systemctl status XrayR --no-pager -l ;;
            8) journalctl -u XrayR.service -e --no-pager -f ;;
            9) edit_config ;;
            10) systemctl enable XrayR ;;
            11) systemctl disable XrayR ;;
            12) run_action version ;;
            0) return 0 ;;
            *) echo '请输入有效选项。' ;;
        esac
    done
}

if [[ $# -gt 0 ]]; then
    run_action "$@"
    result=$?
    if [[ $result -eq 2 ]]; then
        echo '用法: xrayr [install|update [版本]|uninstall|start|stop|restart|status|log|config|enable|disable|version]'
        exit 2
    fi
    exit "$result"
fi

show_menu
