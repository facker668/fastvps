#!/bin/bash

# ====================================================
# Project: FastVPS-Pro
# Author: facker668
# GitHub: https://github.com/facker668/fastvps
# ====================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
PLAIN='\033[0m'

LOCAL_VERSION="1.0"

# 1. 自动更新检查
check_update() {
    REMOTE_VERSION=$(curl -s https://raw.githubusercontent.com/facker668/fastvps/main/version.txt)
    if [[ -n "$REMOTE_VERSION" && "$REMOTE_VERSION" != "$LOCAL_VERSION" ]]; then
        echo -e "${YELLOW}检测到新版本 v$REMOTE_VERSION，正在准备更新...${PLAIN}"
        wget -O optimize.sh https://raw.githubusercontent.com/facker668/fastvps/main/optimize.sh
        chmod +x optimize.sh
        echo -e "${GREEN}更新完毕，请重新运行脚本。${PLAIN}"
        exit 0
    fi
}

# 2. 修改 SSH 端口
change_ssh() {
    local port=60000
    sed -i "s/^#\?Port [0-9]*/Port ${port}/g" /etc/ssh/sshd_config
    systemctl restart sshd
    echo -e "${GREEN}SSH 端口已修改为 $port，请确保防火墙已放行。${PLAIN}"
}

# 3. 智能 Swap
add_swap() {
    local mem=$(free -m | grep Mem | awk '{print $2}')
    local size=$mem
    [[ $mem -gt 1024 ]] && size=1024
    if [ ! -f /swapfile ]; then
        dd if=/dev/zero of=/swapfile bs=1M count=$size
        chmod 600 /swapfile
        mkswap /swapfile && swapon /swapfile
        echo '/swapfile none swap sw 0 0' >> /etc/fstab
        echo -e "${GREEN}Swap 已创建: ${size}MB${PLAIN}"
    fi
}

# 4. 安装 Docker
install_docker() {
    if ! command -v docker >/dev/null 2>&1; then
        curl -fsSL https://get.docker.com | bash
        systemctl enable --now docker
        echo -e "${GREEN}Docker 安装成功。${PLAIN}"
    fi
}

# 菜单
main() {
    clear
    echo -e "${BLUE}FastVPS Pro 一键优化工具 v$LOCAL_VERSION${PLAIN}"
    echo "--------------------------------"
    echo "1. 全自动极致优化 (推荐)"
    echo "2. 仅安装 Docker"
    echo "3. 仅修改 SSH 端口 (60000)"
    echo "0. 退出"
    read -p "请输入数字: " num
    case "$num" in
        1)
            check_update
            add_swap
            change_ssh
            install_docker
            # 这里可以继续添加 DNS 和 BBR 逻辑
            echo -e "${GREEN}所有优化已执行完毕！${PLAIN}"
            ;;
        2) install_docker ;;
        3) change_ssh ;;
        *) exit 0 ;;
    esac
}

main
