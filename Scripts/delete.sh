#!/bin/bash

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' 

check_panel() {
    if [ -d "/var/www/pterodactyl" ] && [ -f "/var/www/pterodactyl/artisan" ]; then
        return 0
    else
        return 1
    fi
}

check_wings() {
    if systemctl is-active --quiet wings || systemctl is-enabled --quiet wings 2>/dev/null; then
        return 0
    elif [ -f "/usr/local/bin/wings" ] || [ -f "/etc/systemd/system/wings.service" ]; then
        return 0
    else
        return 1
    fi
}

get_db_credentials() {
    if [ -f "/var/www/pterodactyl/.env" ]; then
        DB_DATABASE=$(grep "^DB_DATABASE=" /var/www/pterodactyl/.env | cut -d '=' -f2)
        DB_USERNAME=$(grep "^DB_USERNAME=" /var/www/pterodactyl/.env | cut -d '=' -f2)
        DB_PASSWORD=$(grep "^DB_PASSWORD=" /var/www/pterodactyl/.env | cut -d '=' -f2)
    else
        DB_DATABASE="panel"
        DB_USERNAME="pterodactyl"
        DB_PASSWORD=""
    fi
}

uninstall_panel() {
    echo -e "${YELLOW}Uninstalling Pterodactyl Panel...${NC}"
    
    get_db_credentials
    
    systemctl stop pteroq 2>/dev/null || true
    systemctl disable pteroq 2>/dev/null || true
    systemctl stop nginx 2>/dev/null || true
    systemctl stop php8.3-fpm 2>/dev/null || true
    systemctl stop php-fpm 2>/dev/null || true
    
    if [ -d "/var/www/pterodactyl" ]; then
        rm -rf /var/www/pterodactyl
        echo -e "${GREEN}Removed panel files${NC}"
    fi
    
    crontab -l | grep -v "pterodactyl/artisan schedule:run" | crontab - 2>/dev/null || true
    echo -e "${GREEN}Removed cron job${NC}"
    
    if [ -f "/etc/systemd/system/pteroq.service" ]; then
        rm -f /etc/systemd/system/pteroq.service
        echo -e "${GREEN}Removed pteroq service${NC}"
    fi
    
    if command -v mysql &>/dev/null && [ -n "$DB_DATABASE" ] && [ -n "$DB_USERNAME" ]; then
        echo -e "${YELLOW}Removing database and user...${NC}"
        mysql -e "DROP DATABASE IF EXISTS \`$DB_DATABASE\`;" 2>/dev/null || true
        mysql -e "DROP USER IF EXISTS '$DB_USERNAME'@'127.0.0.1';" 2>/dev/null || true
        mysql -e "DROP USER IF EXISTS '$DB_USERNAME'@'localhost';" 2>/dev/null || true
        mysql -e "FLUSH PRIVILEGES;" 2>/dev/null || true
        echo -e "${GREEN}Removed database and user${NC}"
    fi
    
    if [ -f "/etc/nginx/sites-available/pterodactyl.conf" ]; then
        rm -f /etc/nginx/sites-available/pterodactyl.conf
    fi
    if [ -f "/etc/nginx/sites-enabled/pterodactyl.conf" ]; then
        rm -f /etc/nginx/sites-enabled/pterodactyl.conf
    fi
    if [ -f "/etc/nginx/conf.d/pterodactyl.conf" ]; then
        rm -f /etc/nginx/conf.d/pterodactyl.conf
    fi
    
    if [ -f "/1.pem" ]; then
        rm -f /1.pem
    fi
    if [ -f "/2.pem" ]; then
        rm -f /2.pem
    fi
    
    echo -e "${GREEN}Pterodactyl Panel has been uninstalled successfully!${NC}"
}

uninstall_wings() {
    echo -e "${YELLOW}Uninstalling Pterodactyl Wings...${NC}"
    
    systemctl stop wings 2>/dev/null || true
    systemctl disable wings 2>/dev/null || true
    
    if [ -f "/usr/local/bin/wings" ]; then
        rm -f /usr/local/bin/wings
        echo -e "${GREEN}Removed wings binary${NC}"
    fi
    
    if [ -f "/etc/systemd/system/wings.service" ]; then
        rm -f /etc/systemd/system/wings.service
        echo -e "${GREEN}Removed wings service${NC}"
    fi
    
    if [ -d "/etc/pterodactyl" ]; then
        rm -rf /etc/pterodactyl
        echo -e "${GREEN}Removed wings configuration${NC}"
    fi
    
    read -p "Do you want to remove all wings data and containers? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        if command -v docker &>/dev/null; then
            docker ps -aq | xargs docker stop 2>/dev/null || true
            docker ps -aq | xargs docker rm 2>/dev/null || true
            docker volume ls -q | xargs docker volume rm 2>/dev/null || true
            docker network ls -q | xargs docker network rm 2>/dev/null || true
            echo -e "${GREEN}Removed Docker containers and volumes${NC}"
        fi
        if [ -d "/var/lib/pterodactyl" ]; then
            rm -rf /var/lib/pterodactyl
            echo -e "${GREEN}Removed wings data directory${NC}"
        fi
    fi
    
    echo -e "${GREEN}Pterodactyl Wings has been uninstalled successfully!${NC}"
}

detect_os() {
    if [ -f "/etc/os-release" ]; then
        . /etc/os-release
        OS=$ID
        OS_VER=$VERSION_ID
    else
        OS=$(uname -s)
        OS_VER=$(uname -r)
    fi
}

remove_dependencies() {
    detect_os
    
    read -p "Do you want to remove installed dependencies? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        return
    fi
    
    echo -e "${YELLOW}Removing dependencies...${NC}"
    
    case $OS in
        ubuntu|debian)
            apt-get remove -y php8.3 php8.3-* mariadb-server mariadb-client nginx redis-server \
                certbot python3-certbot-nginx composer 2>/dev/null || true
            apt-get autoremove -y 2>/dev/null || true
            ;;
        rocky|almalinux|centos|rhel|fedora)
            dnf remove -y php php-* mariadb-server mariadb nginx redis \
                certbot python3-certbot-nginx composer 2>/dev/null || true
            dnf autoremove -y 2>/dev/null || true
            ;;
    esac
    
    if command -v docker &>/dev/null; then
        read -p "Do you want to remove Docker? (y/N): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            case $OS in
                ubuntu|debian)
                    apt-get remove -y docker.io docker-compose 2>/dev/null || true
                    ;;
                rocky|almalinux|centos|rhel|fedora)
                    dnf remove -y docker docker-compose 2>/dev/null || true
                    ;;
            esac
        fi
    fi
    
    echo -e "${GREEN}Dependencies removed!${NC}"
}

main() {
    echo -e "${BLUE}=== Pterodactyl Uninstaller ===${NC}"
    echo
    
    PANEL_INSTALLED=false
    WINGS_INSTALLED=false
    
    if check_panel; then
        PANEL_INSTALLED=true
        echo -e "${GREEN}✓ Pterodactyl Panel detected${NC}"
    else
        echo -e "${RED}✗ Pterodactyl Panel not detected${NC}"
    fi
    
    if check_wings; then
        WINGS_INSTALLED=true
        echo -e "${GREEN}✓ Pterodactyl Wings detected${NC}"
    else
        echo -e "${RED}✗ Pterodactyl Wings not detected${NC}"
    fi
    
    echo
    
    if [ "$PANEL_INSTALLED" = false ] && [ "$WINGS_INSTALLED" = false ]; then
        echo -e "${YELLOW}No Pterodactyl components detected on this system.${NC}"
        exit 0
    fi
    
    if [ "$PANEL_INSTALLED" = true ] && [ "$WINGS_INSTALLED" = false ]; then
        read -p "Do you want to delete Pterodactyl Panel? (y/N): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            uninstall_panel
            remove_dependencies
        else
            echo -e "${YELLOW}Aborting uninstallation.${NC}"
            exit 0
        fi
    fi
    
    if [ "$PANEL_INSTALLED" = false ] && [ "$WINGS_INSTALLED" = true ]; then
        read -p "Do you want to delete Pterodactyl Wings? (y/N): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            uninstall_wings
            remove_dependencies
        else
            echo -e "${YELLOW}Aborting uninstallation.${NC}"
            exit 0
        fi
    fi
    
    if [ "$PANEL_INSTALLED" = true ] && [ "$WINGS_INSTALLED" = true ]; then
        echo -e "${YELLOW}Both Panel and Wings detected${NC}"
        echo "0 - Delete Panel only"
        echo "1 - Delete Wings only"
        echo "2 - Delete both"
        echo "3 - Exit"
        echo
        
        read -p "Enter your choice (0-3): " choice
        case $choice in
            0)
                uninstall_panel
                ;;
            1)
                uninstall_wings
                ;;
            2)
                uninstall_panel
                echo
                uninstall_wings
                remove_dependencies
                ;;
            3)
                echo -e "${YELLOW}Exiting without changes.${NC}"
                exit 0
                ;;
            *)
                echo -e "${RED}Invalid choice. Exiting.${NC}"
                exit 1
                ;;
        esac
    fi
    
    echo -e "${GREEN}Uninstallation completed!${NC}"
}

main "$@"