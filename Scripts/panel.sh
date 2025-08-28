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


# Ensure Bash version is 3.0 or higher for regex support
if [ "${BASH_VERSINFO[0]}" -lt 3 ]; then
  echo "* ERROR: This script requires Bash 3.0 or higher. Current version: $BASH_VERSION"
  exit 1
fi

fn_exists() { declare -F "$1" >/dev/null; }
if ! fn_exists lib_loaded; then
  source /tmp/lib.sh || source <(curl -sSL "$GITHUB_BASE_URL/$GITHUB_SOURCE"/lib/lib.sh)
  ! fn_exists lib_loaded && echo "* ERROR: Could not load lib script" && exit 1
fi

INSTALL_MARIADB="${INSTALL_MARIADB:-true}"
MYSQL_DB="${MYSQL_DB:-panel}"
MYSQL_USER="${MYSQL_USER:-pterodactyl}"
MYSQL_PASSWORD="${MYSQL_PASSWORD:-$(gen_passwd 64)}"
timezone="${timezone:-Europe/Stockholm}"
ASSUME_SSL=true
CONFIGURE_LETSENCRYPT=false
CONFIGURE_FIREWALL=false
email=""
user_email=""
user_username=""
user_firstname=""
user_lastname=""
user_password=""
FQDN="localhost"

echo -n "* Enter email address: "
read -r email
user_email="$email"
if [ -z "$email" ]; then
  echo "* ERROR: Email is required"
  exit 1
fi

echo -n "* Enter full name (first and last, or single name): "
read -r full_name
if [ -z "$full_name" ]; then
  echo "* ERROR: Full name is required"
  exit 1
fi
if echo "$full_name" | grep -qE '^[^ ]+$'; then
  user_firstname="$full_name"
  user_lastname="DEV"
else
  user_firstname="${full_name%% *}"
  user_lastname="${full_name#* }"
fi

echo -n "* Enter username: "
read -r user_username
if [ -z "$user_username" ]; then
  echo "* ERROR: Username is required"
  exit 1
fi

echo -n "* Enter password: "
read -rs user_password
echo
if [ -z "$user_password" ]; then
  echo "* ERROR: User password is required"
  exit 1
fi

echo -n "* Enter hostname/FQDN (default: localhost): "
read -r INPUT_FQDN
if [ -n "$INPUT_FQDN" ]; then
  FQDN="$INPUT_FQDN"
fi

echo "* Configure Firewall? (y/N): n"
echo "* Configure Let's Encrypt? (y/N): n"
echo "* Assume SSL? (y/N): y"

install_composer() {
  echo "* Installing composer.."
  curl -sS https://getcomposer.org/installer | php -- --install-dir=/usr/local/bin --filename=composer || {
    echo "* ERROR: Failed to install Composer"
    exit 1
  }
  echo "* Composer installed!"
}

ptdl_dl() {
  echo "* Downloading pterodactyl panel files .. "
  mkdir -p /var/www/pterodactyl || {
    echo "* ERROR: Failed to create /var/www/pterodactyl directory"
    exit 1
  }
  cd /var/www/pterodactyl || exit
  curl -Lo panel.tar.gz "$PANEL_DL_URL" || {
    echo "* ERROR: Failed to download Pterodactyl Panel files"
    exit 1
  }
  tar -xzvf panel.tar.gz || {
    echo "* ERROR: Failed to extract Pterodactyl Panel files"
    exit 1
  }
  chmod -R 755 storage/* bootstrap/cache/ || {
    echo "* ERROR: Failed to set permissions for Pterodactyl Panel files"
    exit 1
  }
  cp .env.example .env || {
    echo "* ERROR: Failed to copy .env.example to .env"
    exit 1
  }
  echo "* Downloaded pterodactyl panel files!"
}

install_composer_deps() {
  echo "* Installing composer dependencies.."
  [ "$OS" == "rocky" ] || [ "$OS" == "almalinux" ] && export PATH=/usr/local/bin:$PATH
  COMPOSER_ALLOW_SUPERUSER=1 composer install --no-dev --optimize-autoloader || {
    echo "* ERROR: Failed to install Composer dependencies"
    exit 1
  }
  echo "* Installed composer dependencies!"
}

configure() {
  echo "* Configuring environment.."
  local app_url="https://$FQDN"
  php artisan key:generate --force || {
    echo "* ERROR: Failed to generate application key"
    exit 1
  }
  php artisan p:environment:setup \
    --author="$email" \
    --url="$app_url" \
    --timezone="$timezone" \
    --cache="redis" \
    --session="redis" \
    --queue="redis" \
    --redis-host="localhost" \
    --redis-pass="null" \
    --redis-port="6379" \
    --settings-ui=true || {
    echo "* ERROR: Failed to configure environment setup"
    exit 1
  }
  php artisan p:environment:database \
    --host="127.0.0.1" \
    --port="3306" \
    --database="$MYSQL_DB" \
    --username="$MYSQL_USER" \
    --password="$MYSQL_PASSWORD" || {
    echo "* ERROR: Failed to configure database environment"
    exit 1
  }
  php artisan migrate --seed --force || {
    echo "* ERROR: Failed to migrate database"
    exit 1
  }
  php artisan p:user:make \
    --email="$user_email" \
    --username="$user_username" \
    --name-first="$user_firstname" \
    --name-last="$user_lastname" \
    --password="$user_password" \
    --admin=1 || {
    echo "* ERROR: Failed to create admin user"
    exit 1
  }
  echo "* Configured environment!"
}

set_folder_permissions() {
  case "$OS" in
  debian | ubuntu)
    chown -R www-data:www-data ./* || {
      echo "* ERROR: Failed to set folder permissions for www-data"
      exit 1
    }
    ;;
  rocky | almalinux)
    chown -R nginx:nginx ./* || {
      echo "* ERROR: Failed to set folder permissions for nginx"
      exit 1
    }
    ;;
  esac
}

insert_cronjob() {
  echo "* Installing cronjob.. "
  crontab -l | {
    cat
    echo "* * * * * php /var/www/pterodactyl/artisan schedule:run >> /dev/null 2>&1"
  } | crontab - || {
    echo "* ERROR: Failed to install cronjob"
    exit 1
  }
  echo "* Cronjob installed!"
}

install_pteroq() {
  echo "* Installing pteroq service.."
  curl -o /etc/systemd/system/pteroq.service "$GITHUB_URL"/configs/pteroq.service || {
    echo "* ERROR: Failed to download pteroq service file"
    exit 1
  }
  case "$OS" in
  debian | ubuntu)
    sed -i -e "s@<user>@www-data@g" /etc/systemd/system/pteroq.service || {
      echo "* ERROR: Failed to configure pteroq service for www-data"
      exit 1
    }
    ;;
  rocky | almalinux)
    sed -i -e "s@<user>@nginx@g" /etc/systemd/system/pteroq.service || {
      echo "* ERROR: Failed to configure pteroq service for nginx"
      exit 1
    }
    ;;
  esac
  systemctl enable pteroq.service || {
    echo "* ERROR: Failed to enable pteroq service"
    exit 1
  }
  systemctl start pteroq || {
    echo "* ERROR: Failed to start pteroq service"
    exit 1
  }
  echo "* Installed pteroq!"
}

verify_panel_installation() {
  echo "* Verifying Pterodactyl Panel installation..."
  if [ ! -f "/var/www/pterodactyl/artisan" ]; then
    echo "* ERROR: Pterodactyl Panel installation failed - artisan file not found."
    exit 1
  fi
  if ! systemctl is-active --quiet pteroq; then
    echo "* ERROR: Pterodactyl Panel installation failed - pteroq service is not active."
    exit 1
  fi
  echo "* Pterodactyl Panel installation verified successfully!"
}

enable_services() {
  case "$OS" in
  ubuntu | debian)
    systemctl enable redis-server || true
    systemctl start redis-server || true
    ;;
  rocky | almalinux)
    systemctl enable redis || true
    systemctl start redis || true
    ;;
  esac
  systemctl enable nginx || true
  systemctl enable mariadb || true
  systemctl start mariadb || true
}

selinux_allow() {
  setsebool -P httpd_can_network_connect 1 || true
  setsebool -P httpd_execmem 1 || true
  setsebool -P httpd_unified 1 || true
}

php_fpm_conf() {
  curl -o /etc/php-fpm.d/www-pterodactyl.conf "$GITHUB_URL"/configs/www-pterodactyl.conf || {
    echo "* ERROR: Failed to download PHP-FPM configuration"
    exit 1
  }
  systemctl enable php-fpm || true
  systemctl start php-fpm || true
}

create_db_user() {
  local user="$1"
  local password="$2"
  echo "* Creating MySQL user $user..."
  mysql -e "DROP USER IF EXISTS '$user'@'127.0.0.1';" || {
    echo "* ERROR: Failed to drop existing MySQL user $user"
    exit 1
  }
  mysql -e "CREATE USER '$user'@'127.0.0.1' IDENTIFIED BY '$password';" || {
    echo "* ERROR: Failed to create MySQL user $user"
    exit 1
  }
  echo "* MySQL user $user created!"
}

create_db() {
  local db="$1"
  local user="$2"
  echo "* Creating database $db..."
  mysql -e "DROP DATABASE IF EXISTS $db;" || {
    echo "* ERROR: Failed to drop existing database $db"
    exit 1
  }
  mysql -e "CREATE DATABASE $db;" || {
    echo "* ERROR: Failed to create database $db"
    exit 1
  }
  mysql -e "GRANT ALL PRIVILEGES ON $db.* TO '$user'@'127.0.0.1';" || {
    echo "* ERROR: Failed to grant privileges to $user for database $db"
    exit 1
  }
  echo "* Database $db created and privileges granted!"
}

ubuntu_dep() {
  install_packages "software-properties-common apt-transport-https ca-certificates gnupg" || {
    echo "* ERROR: Failed to install Ubuntu dependencies"
    exit 1
  }
  add-apt-repository universe -y || true
  LC_ALL=C.UTF-8 add-apt-repository -y ppa:ondrej/php || true
}

debian_dep() {
  install_packages "dirmngr ca-certificates apt-transport-https lsb-release" || {
    echo "* ERROR: Failed to install Debian dependencies"
    exit 1
  }
  curl -o /etc/apt/trusted.gpg.d/php.gpg https://packages.sury.org/php/apt.gpg || {
    echo "* ERROR: Failed to download PHP GPG key"
    exit 1
  }
  echo "deb https://packages.sury.org/php/ $(lsb_release -sc) main" | tee /etc/apt/sources.list.d/php.list || {
    echo "* ERROR: Failed to add PHP repository"
    exit 1
  }
}

alma_rocky_dep() {
  install_packages "policycoreutils selinux-policy selinux-policy-targeted setroubleshoot-server setools setools-console mcstrans" || {
    echo "* ERROR: Failed to install SELinux dependencies"
    exit 1
  }
  install_packages "epel-release http://rpms.remirepo.net/enterprise/remi-release-$OS_VER_MAJOR.rpm" || {
    echo "* ERROR: Failed to install EPEL and Remi repositories"
    exit 1
  }
  dnf module enable -y php:remi-8.3 || true
}

dep_install() {
  echo "* Installing dependencies for $OS $OS_VER..."
  update_repos || {
    echo "* ERROR: Failed to update package repositories"
    exit 1
  }
  [ "$CONFIGURE_FIREWALL" == true ] && install_firewall && firewall_ports
  case "$OS" in
  ubuntu | debian)
    [ "$OS" == "ubuntu" ] && ubuntu_dep
    [ "$OS" == "debian" ] && debian_dep
    update_repos || {
      echo "* ERROR: Failed to update package repositories after adding PHP repo"
      exit 1
    }
    install_packages "php8.3 php8.3-{cli,common,gd,mysql,mbstring,bcmath,xml,fpm,curl,zip} mariadb-common mariadb-server mariadb-client nginx redis-server zip unzip tar git cron" || {
      echo "* ERROR: Failed to install dependencies"
      exit 1
    }
    [ "$CONFIGURE_LETSENCRYPT" == true ] && install_packages "certbot python3-certbot-nginx" || true
    ;;
  rocky | almalinux)
    alma_rocky_dep
    install_packages "php php-{common,fpm,cli,json,mysqlnd,mcrypt,gd,mbstring,pdo,zip,bcmath,dom,opcache,posix} mariadb mariadb-server nginx redis zip unzip tar git cronie" || {
      echo "* ERROR: Failed to install dependencies"
      exit 1
    }
    [ "$CONFIGURE_LETSENCRYPT" == true ] && install_packages "certbot python3-certbot-nginx" || true
    selinux_allow
    php_fpm_conf
    ;;
  esac
  enable_services
  echo "* Dependencies installed!"
}

firewall_ports() {
  echo "* Opening ports: 22 (SSH), 80 (HTTP) and 443 (HTTPS)"
  firewall_allow_ports "22 80 443" || true
  echo "* Firewall ports opened!"
}

letsencrypt() {
  FAILED=false
  echo "* Configuring Let's Encrypt..."
  certbot --nginx --redirect --no-eff-email --email "$email" -d "$FQDN" || FAILED=true
  if [ ! -d "/etc/letsencrypt/live/$FQDN/" ] || [ "$FAILED" == true ]; then
    echo "* The process of obtaining a Let's Encrypt certificate failed!"
    echo -n "* Still assume SSL? (y/N): "
    read -r CONFIGURE_SSL
    if [[ "$CONFIGURE_SSL" =~ [Yy] ]]; then
      ASSUME_SSL=true
      CONFIGURE_LETSENCRYPT=false
      configure_nginx
    else
      ASSUME_SSL=false
      CONFIGURE_LETSENCRYPT=false
    fi
  else
    echo "* The process of obtaining a Let's Encrypt certificate succeeded!"
  fi
}

configure_nginx() {
  echo "* Configuring nginx .."
  if [ "$ASSUME_SSL" == true ] && [ "$CONFIGURE_LETSENCRYPT" == false ]; then
    DL_FILE="nginx_ssl.conf"
  else
    DL_FILE="nginx.conf"
  fi
  case "$OS" in
  ubuntu | debian)
    PHP_SOCKET="/run/php/php8.3-fpm.sock"
    CONFIG_PATH_AVAIL="/etc/nginx/sites-available"
    CONFIG_PATH_ENABL="/etc/nginx/sites-enabled"
    ;;
  rocky | almalinux)
    PHP_SOCKET="/var/run/php-fpm/pterodactyl.sock"
    CONFIG_PATH_AVAIL="/etc/nginx/conf.d"
    CONFIG_PATH_ENABL="$CONFIG_PATH_AVAIL"
    ;;
  esac
  rm -rf "$CONFIG_PATH_ENABL"/default || true
  curl -o "$CONFIG_PATH_AVAIL"/pterodactyl.conf "$GITHUB_URL"/configs/$DL_FILE || {
    echo "* ERROR: Failed to download Nginx configuration"
    exit 1
  }
  sed -i -e "s@<domain>@${FQDN}@g" "$CONFIG_PATH_AVAIL"/pterodactyl.conf || {
    echo "* ERROR: Failed to configure Nginx domain"
    exit 1
  }
  sed -i -e "s@<php_socket>@${PHP_SOCKET}@g" "$CONFIG_PATH_AVAIL"/pterodactyl.conf || {
    echo "* ERROR: Failed to configure Nginx PHP socket"
    exit 1
  }
  case "$OS" in
  ubuntu | debian)
    ln -sf "$CONFIG_PATH_AVAIL"/pterodactyl.conf "$CONFIG_PATH_ENABL"/pterodactyl.conf || {
      echo "* ERROR: Failed to create Nginx symlink"
      exit 1
    }
    ;;
  esac
  if [ "$ASSUME_SSL" == false ] && [ "$CONFIGURE_LETSENCRYPT" == false ]; then
    systemctl restart nginx || {
      echo "* ERROR: Failed to restart Nginx"
      exit 1
    }
  fi
  echo "* Nginx configured!"
}

post_install_ssl() {
  echo "* Generating self-signed SSL certificate..."
  openssl req -x509 -nodes -days 365 -newkey rsa:2048 -keyout /2.pem -out /1.pem -subj "/CN=localhost" || {
    echo "* ERROR: Failed to generate self-signed SSL certificate"
    exit 1
  }
  echo "* Restarting nginx..."
  sed -i 's|^\s*ssl_certificate\s\+.*|    ssl_certificate /1.pem;|' /etc/nginx/sites-available/pterodactyl.conf || {
    echo "* ERROR: Failed to update SSL certificate path in Nginx config"
    exit 1
  }
  sed -i 's|^\s*ssl_certificate_key\s\+.*|    ssl_certificate_key /2.pem;|' /etc/nginx/sites-available/pterodactyl.conf || {
    echo "* ERROR: Failed to update SSL certificate key path in Nginx config"
    exit 1
  }
  sed -i 's/\b443\b/8443/g; s/\b80\b/8000/g' /etc/nginx/sites-available/pterodactyl.conf || {
    echo "* ERROR: Failed to update Nginx ports"
    exit 1
  }
  systemctl restart nginx || {
    echo "* ERROR: Failed to restart Nginx"
    exit 1
  }
  echo "* SSL certificate and Nginx ports configured!"
}

restart_services() {
  echo "* Restarting services..."
  systemctl restart nginx || {
    echo "* ERROR: Failed to restart Nginx"
    exit 1
  }
  case "$OS" in
  ubuntu | debian)
    systemctl restart php8.3-fpm || {
      echo "* ERROR: Failed to restart PHP-FPM"
      exit 1
    }
    ;;
  rocky | almalinux)
    systemctl restart php-fpm || {
      echo "* ERROR: Failed to restart PHP-FPM"
      exit 1
    }
    ;;
  esac
  systemctl restart pteroq || {
    echo "* ERROR: Failed to restart pteroq"
    exit 1
  }
  systemctl restart mariadb || {
    echo "* ERROR: Failed to restart MariaDB"
    exit 1
  }
  echo "* Services restarted!"
}

perform_install() {
  echo "* Starting installation.. this might take a while!"
  dep_install
  install_composer
  ptdl_dl
  install_composer_deps
  create_db_user "$MYSQL_USER" "$MYSQL_PASSWORD"
  create_db "$MYSQL_DB" "$MYSQL_USER"
  configure
  set_folder_permissions
  insert_cronjob
  install_pteroq
  configure_nginx
  [ "$CONFIGURE_LETSENCRYPT" == true ] && letsencrypt
  post_install_ssl
  verify_panel_installation
  restart_services
  echo "* Pterodactyl Panel installation and configuration completed!"
  return 0
}

perform_install