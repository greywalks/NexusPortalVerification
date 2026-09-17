#!/usr/bin/env bash
set -euo pipefail

usage() {
  echo "Usage: $0 [--app-root PATH] [--service-user USER] [--service-group GROUP] [--server-name HOST] [--install-apache]"
}

APP_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SERVICE_USER="lucee"
SERVICE_GROUP="lucee"
SERVER_NAME=""
INSTALL_APACHE=0
H2_VERSION="2.1.214"
H2_SHA256="d623cdc0f61d218cf549a8d09f1c391ff91096116b22e2475475fce4fbe72bd0"
H2_URL="https://repo.maven.apache.org/maven2/com/h2database/h2/${H2_VERSION}/h2-${H2_VERSION}.jar"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --app-root) APP_ROOT="$2"; shift 2 ;;
    --service-user) SERVICE_USER="$2"; shift 2 ;;
    --service-group) SERVICE_GROUP="$2"; shift 2 ;;
    --server-name) SERVER_NAME="$2"; shift 2 ;;
    --install-apache) INSTALL_APACHE=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
done

APP_ROOT="$(cd "$APP_ROOT" && pwd)"
[[ -f "$APP_ROOT/Application.cfc" && -f "$APP_ROOT/index.cfm" ]] || { echo "Application.cfc and index.cfm were not found in $APP_ROOT" >&2; exit 1; }
[[ -d "$APP_ROOT/config" ]] || { echo "$APP_ROOT/config is missing; the checkout is incomplete." >&2; exit 1; }
[[ -f "$APP_ROOT/views/portal.html" ]] || { echo "$APP_ROOT/views/portal.html is missing; the portal shell cannot render." >&2; exit 1; }
id "$SERVICE_USER" >/dev/null 2>&1 || { echo "Service user '$SERVICE_USER' does not exist." >&2; exit 1; }
getent group "$SERVICE_GROUP" >/dev/null 2>&1 || { echo "Service group '$SERVICE_GROUP' does not exist." >&2; exit 1; }

install -d -m 0750 "$APP_ROOT/lib"
H2_JAR="$APP_ROOT/lib/h2-${H2_VERSION}.jar"
if [[ ! -f "$H2_JAR" ]] || [[ "$(sha256sum "$H2_JAR" | awk '{print $1}')" != "$H2_SHA256" ]]; then
  TMP_H2="$(mktemp)"
  trap 'rm -f "$TMP_H2"' EXIT
  if command -v curl >/dev/null 2>&1; then
    curl --fail --location --silent --show-error "$H2_URL" --output "$TMP_H2"
  elif command -v wget >/dev/null 2>&1; then
    wget --quiet "$H2_URL" --output-document "$TMP_H2"
  else
    echo "curl or wget is required to install the H2 driver." >&2
    exit 1
  fi
  echo "$H2_SHA256  $TMP_H2" | sha256sum --check --status || { echo "H2 checksum verification failed." >&2; exit 1; }
  install -m 0640 "$TMP_H2" "$H2_JAR"
fi

for runtime_dir in data uploads outputs; do
  install -d -o "$SERVICE_USER" -g "$SERVICE_GROUP" -m 2770 "$APP_ROOT/$runtime_dir"
done
install -d -o "$SERVICE_USER" -g "$SERVICE_GROUP" -m 2770 "$APP_ROOT/data/training_signoffs" "$APP_ROOT/outputs/.access"
chgrp "$SERVICE_GROUP" "$APP_ROOT/config"
chmod 2770 "$APP_ROOT/config"
find "$APP_ROOT/config" -maxdepth 1 -type f -exec chmod 0660 {} +
chgrp "$SERVICE_GROUP" "$H2_JAR"

if [[ "$INSTALL_APACHE" -eq 1 ]]; then
  [[ -n "$SERVER_NAME" ]] || { echo "--server-name is required with --install-apache." >&2; exit 1; }
  [[ -d /etc/apache2/sites-available ]] || { echo "Automatic Apache installation currently supports Debian/Ubuntu layouts." >&2; exit 1; }
  command -v a2enmod >/dev/null 2>&1 && a2enmod rewrite proxy proxy_http headers
  VHOST_TARGET="/etc/apache2/sites-available/ussi-nexus.conf"
  sed -e "s|__APP_ROOT__|$APP_ROOT|g" -e "s|__SERVER_NAME__|$SERVER_NAME|g" "$APP_ROOT/deploy/apache/ussi-nexus-vhost.conf.example" > "$VHOST_TARGET"
  a2ensite ussi-nexus.conf
  apache2ctl configtest
  echo "Apache configuration installed. Reload Apache after confirming the Lucee backend is listening on 127.0.0.1:8888."
else
  echo "Runtime dependencies and permissions are ready."
  echo "To install the supplied Apache site: sudo $0 --app-root '$APP_ROOT' --service-user '$SERVICE_USER' --service-group '$SERVICE_GROUP' --server-name portal.example.com --install-apache"
fi

echo "H2 driver: $H2_JAR"
echo "Next: restart Lucee/Tomcat, reload Apache, then run deploy/check-deployment.sh against the site URL."

