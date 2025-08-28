#!/bin/bash

############################################################
#                                                          #
#   🚀 Pterodactyl Installer Script                        #
#                                                          #
#   Author : XENTO                                         #
#   Email  : me@xento.xyz                                  #
#   Website: https://ptero.xento.xyz                       #
#                                                          #
#   ⚠️ Please do not remove this watermark.                 #
#                                                          #
############################################################


fn_exists() { declare -F "$1" >/dev/null; }
if ! fn_exists lib_loaded; then
  source /tmp/lib.sh || source <(curl -sSL "$GITHUB_BASE_URL/$GITHUB_SOURCE"/lib/lib.sh)
  ! fn_exists lib_loaded && echo "* ERROR: Could not load lib script" && exit 1
fi

INSTALL_MARIADB="${INSTALL_MARIADB:-true}"
CONFIGURE_FIREWALL="${CONFIGURE_FIREWALL:-false}"
CONFIGURE_LETSENCRYPT="${CONFIGURE_LETSENCRYPT:-false}"
CONFIGURE_DBHOST="${CONFIGURE_DBHOST:-true}"
CONFIGURE_DB_FIREWALL="${CONFIGURE_DB_FIREWALL:-false}"
MYSQL_DBHOST_HOST="${MYSQL_DBHOST_HOST:-127.0.0.1}"
MYSQL_DBHOST_USER="${MYSQL_DBHOST_USER:-wingsadmin}"
MYSQL_DBHOST_PASSWORD="${MYSQL_DBHOST_PASSWORD:-}"
WINGS_DB_NAME="wingsdb"
FQDN="${FQDN:-}"
EMAIL="${EMAIL:-}"
DEPLOY_CODE="${DEPLOY_CODE:-}"

if [ -f "/usr/local/bin/wings" ]; then
  echo "* Pterodactyl Wings is already installed!"
  echo -n "* Do you want to delete and reinstall Wings? (y/N): "
  read -r REINSTALL
  if [[ ! "$REINSTALL" =~ ^[Yy]$ ]]; then
    echo "* Installation aborted."
    exit 0
  else
    echo "* Removing existing Wings installation..."
    systemctl stop wings || true
    systemctl disable wings || true
    rm -f /usr/local/bin/wings
    rm -rf /etc/pterodactyl
    rm -f /etc/systemd/system/wings.service
    systemctl daemon-reload
  fi
fi

echo "* Is this an unsupported type of virtualization? (y/N): y"
echo "* Proceeding with unsupported virtualization type..."

echo "* Do you want to configure UFW firewall? (y/N): n"
CONFIGURE_FIREWALL=false

echo "* Do you want to configure Let's Encrypt? (y/N): n"
CONFIGURE_LETSENCRYPT=false

if [ "$CONFIGURE_DBHOST" == true ]; then
  echo -n "* Enter MySQL database host username (default: wingsadmin): "
  read -r INPUT_USER
  if [ -n "$INPUT_USER" ]; then
    MYSQL_DBHOST_USER="$INPUT_USER"
  fi
fi

if [[ "$CONFIGURE_DBHOST" == true && -z "${MYSQL_DBHOST_PASSWORD}" ]]; then
  echo -n "* Enter MySQL database host user password for $MYSQL_DBHOST_USER: "
  read -rs MYSQL_DBHOST_PASSWORD
  echo
  if [ -z "$MYSQL_DBHOST_PASSWORD" ]; then
    echo "* ERROR: MySQL database host user password is required"
    exit 1
  fi
fi

if [ "$CONFIGURE_DBHOST" == true ]; then
  echo -n "* Please provide the daemon auto-deploy code (e.g., cd /etc/pterodactyl && sudo wings configure ...): "
  read -r DEPLOY_CODE
  if [ -z "$DEPLOY_CODE" ]; then
    echo "* ERROR: Daemon auto-deploy code is required!"
    exit 1
  fi
fi

enable_services() {
  [ "$INSTALL_MARIADB" == true ] && systemctl enable mariadb
  [ "$INSTALL_MARIADB" == true ] && systemctl start mariadb
  systemctl start docker
  systemctl enable docker
}

dep_install() {
  echo "* Installing dependencies for $OS $OS_VER..."

  [ "$CONFIGURE_FIREWALL" == true ] && install_firewall && firewall_ports

  case "$OS" in
  ubuntu | debian)
    install_packages "ca-certificates gnupg lsb-release"

    mkdir -p /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/debian/gpg | gpg --dearmor --yes -o /etc/apt/keyrings/docker.gpg

    echo \
      "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/$OS \
      $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list >/dev/null
    ;;

  rocky | almalinux)
    install_packages "dnf-utils"
    dnf config-manager --add-repo=https://download.docker.com/linux/centos/docker-ce.repo

    [ "$CONFIGURE_LETSENCRYPT" == true ] && install_packages "epel-release"

    install_packages "device-mapper-persistent-data lvm2"
    ;;
  esac

  update_repos
  install_packages "docker-ce docker-ce-cli containerd.io"
  [ "$INSTALL_MARIADB" == true ] && install_packages "mariadb-server"
  [ "$CONFIGURE_LETSENCRYPT" == true ] && install_packages "certbot"

  enable_services

  echo "* Dependencies installed!"
}

ptdl_dl() {
  echo "* Downloading Pterodactyl Wings.. "

  mkdir -p /etc/pterodactyl
  curl -L -o /usr/local/bin/wings "$WINGS_DL_BASE_URL$ARCH"

  chmod u+x /usr/local/bin/wings

  echo "* Pterodactyl Wings downloaded successfully"
}

systemd_file() {
  echo "* Installing systemd service.."

  curl -o /etc/systemd/system/wings.service "$GITHUB_URL"/configs/wings.service
  systemctl daemon-reload
  systemctl enable wings

  echo "* Installed systemd service!"
}

firewall_ports() {
  echo "* Opening port 22 (SSH), 8080 (Wings Port), 2022 (Wings SFTP Port)"

  [ "$CONFIGURE_LETSENCRYPT" == true ] && firewall_allow_ports "80 443"
  [ "$CONFIGURE_DB_FIREWALL" == true ] && firewall_allow_ports "3306"

  firewall_allow_ports "22"
  echo "* Allowed port 22"
  firewall_allow_ports "8080"
  echo "* Allowed port 8080"
  firewall_allow_ports "2022"
  echo "* Allowed port 2022"

  echo "* Firewall ports opened!"
}

letsencrypt() {
  FAILED=false

  echo "* Configuring Let's Encrypt.."

  systemctl stop nginx || true
  certbot certonly --no-eff-email --email "$EMAIL" --standalone -d "$FQDN" || FAILED=true
  systemctl start nginx || true

  if [ ! -d "/etc/letsencrypt/live/$FQDN/" ] || [ "$FAILED" == true ]; then
    echo "* The process of obtaining a Let's Encrypt certificate failed!"
  else
    echo "* The process of obtaining a Let's Encrypt certificate succeeded!"
  fi
}

configure_mysql() {
  echo "* Configuring MySQL.."

  mysql -e "DROP USER IF EXISTS '$MYSQL_DBHOST_USER'@'$MYSQL_DBHOST_HOST';"
  mysql -e "CREATE DATABASE IF NOT EXISTS $WINGS_DB_NAME;"
  create_db_user "$MYSQL_DBHOST_USER" "$MYSQL_DBHOST_PASSWORD" "$MYSQL_DBHOST_HOST"
  grant_all_privileges "$WINGS_DB_NAME" "$MYSQL_DBHOST_USER" "$MYSQL_DBHOST_HOST"

  if [ "$MYSQL_DBHOST_HOST" != "127.0.0.1" ]; then
    echo "* Changing MySQL bind address.."

    case "$OS" in
    debian | ubuntu)
      sed -i 's/127.0.0.1/0.0.0.0/g' /etc/mysql/mariadb.conf.d/50-server.cnf
      ;;
    rocky | almalinux)
      sed -i 's/^#bind-address=0.0.0.0$/bind-address=0.0.0.0/' /etc/my.cnf.d/mariadb-server.cnf
      ;;
    esac

    systemctl restart mysqld
  fi

  echo "* MySQL configured with database $WINGS_DB_NAME and user $MYSQL_DBHOST_USER!"
}

configure_wings() {
  echo "* Configuring Wings with provided daemon auto-deploy code.."

  eval "$DEPLOY_CODE"
  if [ $? -ne 0 ]; then
    echo "* ERROR: Failed to execute daemon auto-deploy code!"
    exit 1
  fi

  echo "* Wings configured successfully!"

  echo -n "* Are the panel and Wings on the same host? (y/N): "
  read -r SAME_HOST
  if [[ "$SAME_HOST" =~ ^[Yy]$ ]]; then
    echo "* Configuring SSL for same host..."
    sed -i 's|^\(\s*cert:\s*\).*|\1/1.pem|' /etc/pterodactyl/config.yml
    sed -i 's|^\(\s*key:\s*\).*|\1/2.pem|' /etc/pterodactyl/config.yml
  else
    echo "* Generating self-signed SSL certificate for different host..."
    openssl req -x509 -nodes -days 365 -newkey rsa:2048 -keyout /2.pem -out /1.pem -subj "/CN=localhost"
    sed -i 's|^\(\s*cert:\s*\).*|\1/1.pem|' /etc/pterodactyl/config.yml
    sed -i 's|^\(\s*key:\s*\).*|\1/2.pem|' /etc/pterodactyl/config.yml
  fi

  systemctl restart wings
  echo "* Wings SSL configuration completed and service restarted!"
}

perform_install() {
  echo "* Installing Pterodactyl Wings.."
  dep_install
  ptdl_dl
  systemd_file
  [ "$CONFIGURE_DBHOST" == true ] && configure_mysql
  [ "$CONFIGURE_LETSENCRYPT" == true ] && letsencrypt
  configure_wings

  echo "* Pterodactyl Wings installation and configuration completed!"
  return 0
}

perform_install