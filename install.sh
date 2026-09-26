#!/usr/bin/env bash

red='\033[0;31m'
green='\033[0;32m'
yellow='\033[0;33m'
plain='\033[0m'
repo='qqlikegi/XrayR-096'
install_dir='/usr/local/XrayR'
config_dir='/etc/XrayR'
service_file='/etc/systemd/system/XrayR.service'
temp_dir=$(mktemp -d)
trap 'rm -rf "$temp_dir"' EXIT

if [[ $EUID -ne 0 ]]; then
    echo -e "${red}错误：${plain} 必须使用 root 用户运行此脚本！"
    exit 1
fi

if [[ -f /etc/redhat-release ]]; then
    release='centos'
elif grep -Eqi 'debian' /etc/issue /proc/version 2>/dev/null; then
    release='debian'
elif grep -Eqi 'ubuntu' /etc/issue /proc/version 2>/dev/null; then
    release='ubuntu'
else
    echo -e "${red}未检测到受支持的系统（Debian、Ubuntu 或 CentOS）。${plain}"
    exit 1
fi

case "$(uname -m)" in
    x86_64|x64|amd64) arch='linux-64' ;;
    i386|i486|i586|i686) arch='linux-32' ;;
    aarch64|arm64) arch='linux-arm64-v8a' ;;
    armv7l|armv7) arch='linux-arm32-v7a' ;;
    armv6l|armv6) arch='linux-arm32-v6' ;;
    armv5tel|armv5) arch='linux-arm32-v5' ;;
    mips64) arch='linux-mips64' ;;
    mips64el) arch='linux-mips64le' ;;
    mipsel) arch='linux-mips32le' ;;
    mips) arch='linux-mips32' ;;
    ppc64le) arch='linux-ppc64le' ;;
    riscv64) arch='linux-riscv64' ;;
    s390x) arch='linux-s390x' ;;
    *)
        echo -e "${red}不支持的 CPU 架构：$(uname -m)${plain}"
        exit 1
        ;;
esac
echo "架构：${arch}"

install_base() {
    if [[ $release == 'centos' ]]; then
        yum install -y epel-release
        yum install -y wget curl unzip tar crontabs socat
    else
        apt-get update -y
        apt-get install -y wget curl unzip tar cron socat
    fi
}

install_acme() {
    curl --fail --location --silent --show-error https://get.acme.sh | sh
}

get_latest_version() {
    curl --fail --location --silent --show-error \
        "https://api.github.com/repos/${repo}/releases/latest" |
        sed -n 's/.*"tag_name": *"\([^"]*\)".*/\1/p' | head -n 1
}

echo -e "${green}开始安装 XrayR${plain}"
install_base
install_acme

if [[ -n ${1:-} ]]; then
    version=$1
else
    version=$(get_latest_version)
    if [[ -z $version ]]; then
        echo -e "${red}读取 ${repo} 的最新 Release 失败。${plain}"
        exit 1
    fi
fi

archive="XrayR-${arch}.zip"
download_url="https://github.com/${repo}/releases/download/${version}/${archive}"
echo "下载 XrayR ${version}：${archive}"
if ! curl --fail --location --retry 3 --output "${temp_dir}/${archive}" "$download_url"; then
    echo -e "${red}下载失败：请确认 ${version} Release 已包含 ${archive}。${plain}"
    exit 1
fi

mkdir -p "${temp_dir}/package"
if ! unzip -q "${temp_dir}/${archive}" -d "${temp_dir}/package"; then
    echo -e "${red}安装包解压失败。${plain}"
    exit 1
fi
if [[ ! -f ${temp_dir}/package/XrayR ]]; then
    echo -e "${red}安装包中没有找到 XrayR 可执行文件。${plain}"
    exit 1
fi
if [[ ! -f ${temp_dir}/package/XrayR.service ]]; then
    echo "从 ${repo} 获取 XrayR.service..."
    if ! curl --fail --location --retry 3 --output "${temp_dir}/XrayR.service" \
        "https://raw.githubusercontent.com/${repo}/master/XrayR.service"; then
        echo -e "${red}下载 ${repo} 中的 XrayR.service 失败。${plain}"
        exit 1
    fi
    cp -f "${temp_dir}/XrayR.service" "${temp_dir}/package/XrayR.service"
fi
if [[ -f ${temp_dir}/package/XrayR.sh ]]; then
    cp -f "${temp_dir}/package/XrayR.sh" "${temp_dir}/XrayR.sh"
else
    echo "从 ${repo} 获取管理菜单脚本..."
    if ! curl --fail --location --retry 3 --output "${temp_dir}/XrayR.sh" \
        "https://raw.githubusercontent.com/${repo}/master/XrayR.sh"; then
        echo -e "${red}下载 ${repo} 中的管理菜单脚本失败。${plain}"
        exit 1
    fi
fi

systemctl stop XrayR 2>/dev/null || true
rm -rf "$install_dir"
mkdir -p "$install_dir" "$config_dir"
cp -a "${temp_dir}/package/." "$install_dir/"
chmod +x "${install_dir}/XrayR"

# 原版布局：可执行程序在 /usr/local/XrayR，配置和 Geo 数据在 /etc/XrayR。
cp -f "${install_dir}/XrayR.service" "$service_file"
install -m 755 "${temp_dir}/XrayR.sh" /usr/bin/XrayR
ln -sfn /usr/bin/XrayR /usr/bin/xrayr
had_config=0
[[ ! -f ${config_dir}/config.yml ]] || had_config=1
for file in geoip.dat geosite.dat; do
    [[ ! -f ${install_dir}/${file} ]] || cp -f "${install_dir}/${file}" "$config_dir/"
done
for file in config.yml dns.json route.json custom_outbound.json custom_inbound.json rulelist; do
    if [[ ! -f ${config_dir}/${file} && -f ${install_dir}/${file} ]]; then
        cp -f "${install_dir}/${file}" "$config_dir/"
    fi
done

systemctl daemon-reload
systemctl enable XrayR
echo -e "${green}XrayR ${version} 安装完成，已设置开机自启。${plain}"
echo '输入 xrayr 可打开管理菜单。'

if [[ $had_config -eq 0 ]]; then
    echo -e "${yellow}首次安装，请先编辑 ${config_dir}/config.yml，再启动服务。${plain}"
    exit 0
fi

systemctl restart XrayR
sleep 2
if systemctl is-active --quiet XrayR; then
    echo -e "${green}XrayR 重启成功。${plain}"
else
    echo -e "${red}XrayR 未能启动，请查看日志：journalctl -u XrayR -e --no-pager${plain}"
    exit 1
fi
