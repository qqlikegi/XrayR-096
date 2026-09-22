#!/usr/bin/env bash
set -Eeuo pipefail

REPO="qqlikegi/XrayR-096"
INSTALL_DIR="/usr/local/XrayR"
SERVICE_FILE="/etc/systemd/system/XrayR.service"
TMP_DIR="$(mktemp -d)"

cleanup() { rm -rf "$TMP_DIR"; }
trap cleanup EXIT

if [[ "$(id -u)" -ne 0 ]]; then
  echo "请使用 root 用户运行此脚本。" >&2
  exit 1
fi

if ! command -v curl >/dev/null 2>&1; then
  echo "缺少 curl，请先安装 curl 后重试。" >&2
  exit 1
fi

if ! command -v unzip >/dev/null 2>&1; then
  echo "缺少 unzip，请先安装 unzip 后重试。" >&2
  exit 1
fi

case "$(uname -m)" in
  x86_64|amd64) ASSET="linux-64" ;;
  aarch64|arm64) ASSET="linux-arm64-v8a" ;;
  armv7l|armv7) ASSET="linux-arm32-v7a" ;;
  armv6l|armv6) ASSET="linux-arm32-v6" ;;
  armv5tel|armv5) ASSET="linux-arm32-v5" ;;
  i386|i686) ASSET="linux-32" ;;
  mips) ASSET="linux-mips32" ;;
  mipsel) ASSET="linux-mips32le" ;;
  mips64) ASSET="linux-mips64" ;;
  mips64el) ASSET="linux-mips64le" ;;
  riscv64) ASSET="linux-riscv64" ;;
  s390x) ASSET="linux-s390x" ;;
  ppc64le) ASSET="linux-ppc64le" ;;
  *) echo "不支持的 CPU 架构: $(uname -m)" >&2; exit 1 ;;
esac

BASE_URL="https://github.com/${REPO}/releases/latest/download"
ARCHIVE="XrayR-${ASSET}.zip"
ARCHIVE_PATH="${TMP_DIR}/${ARCHIVE}"

echo "从 ${REPO} 下载 ${ARCHIVE}..."
curl --fail --location --retry 3 --output "$ARCHIVE_PATH" "${BASE_URL}/${ARCHIVE}"

mkdir -p "$INSTALL_DIR"
unzip -oq "$ARCHIVE_PATH" -d "$TMP_DIR/package"

if [[ ! -x "$TMP_DIR/package/XrayR" ]]; then
  chmod +x "$TMP_DIR/package/XrayR" 2>/dev/null || true
fi
if [[ ! -f "$TMP_DIR/package/XrayR" ]]; then
  echo "发布包中没有找到 XrayR 可执行文件。" >&2
  exit 1
fi

systemctl stop XrayR.service 2>/dev/null || true

cp -f "$TMP_DIR/package/XrayR" "$INSTALL_DIR/XrayR"
chmod 755 "$INSTALL_DIR/XrayR"

# 保留已有配置；首次安装时才从你自己的 Release 包复制默认配置。
for file in config.yml dns.json route.json custom_inbound.json custom_outbound.json geosite.dat geoip.dat rulelist; do
  if [[ -f "$TMP_DIR/package/$file" && ! -f "$INSTALL_DIR/$file" ]]; then
    cp -f "$TMP_DIR/package/$file" "$INSTALL_DIR/$file"
  fi
done

cat > "$SERVICE_FILE" <<EOF
[Unit]
Description=XrayR Service
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
WorkingDirectory=${INSTALL_DIR}
ExecStart=${INSTALL_DIR}/XrayR -config ${INSTALL_DIR}/config.yml
Restart=on-failure
RestartSec=5s
LimitNOFILE=1048576

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable XrayR.service
systemctl restart XrayR.service

echo "XrayR 已从 ${REPO} 安装到 ${INSTALL_DIR}。"
systemctl --no-pager --full status XrayR.service || true
