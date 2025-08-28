#!/bin/bash
# Pterodactyl Automatic Installer
# Author: Xento
# Repo: https://github.com/curtoz-007/Pterodactyl-Installer

# Ensure script exits on errors
set -e

clear
echo "==========================================="
echo "        🚀 Pterodactyl Auto Installer       "
echo "==========================================="
echo ""
echo "Choose an option to continue:"
echo ""
echo "  0) Install Panel"
echo "  1) Install Wings"
echo "  2) Install Both (Panel + Wings)"
echo "  3) Delete Panel or Wings"
echo "  4) Exit"
echo ""
echo "==========================================="
echo ""

read -p "Enter your choice [0-4]: " choice

case $choice in
    0)
        echo "👉 Starting Panel installation..."
        bash <(curl -s https://raw.githubusercontent.com/curtoz-007/Pterodactyl-Installer/main/Scripts/panel.sh)
        ;;
    1)
        echo "👉 Starting Wings installation..."
        bash <(curl -s https://raw.githubusercontent.com/curtoz-007/Pterodactyl-Installer/main/Scripts/wings.sh)
        ;;
    2)
        echo "👉 Installing both Panel and Wings..."
        bash <(curl -s https://raw.githubusercontent.com/curtoz-007/Pterodactyl-Installer/main/Scripts/panel.sh)
        bash <(curl -s https://raw.githubusercontent.com/curtoz-007/Pterodactyl-Installer/main/Scripts/wings.sh)
        ;;
    3)
        echo "👉 Running delete script..."
        bash <(curl -s https://raw.githubusercontent.com/curtoz-007/Pterodactyl-Installer/main/Scripts/delete.sh)
        ;;
    4)
        echo "👋 Exiting installer. Goodbye!"
        exit 0
        ;;
    *)
        echo "❌ Invalid choice. Please run the script again."
        exit 1
        ;;
esac

echo ""
echo "==========================================="
echo "✅ Task finished! If this helped you,"
echo "please ⭐ star the repo:"
echo "👉 https://github.com/curtoz-007/Pterodactyl-Installer"
echo "==========================================="
