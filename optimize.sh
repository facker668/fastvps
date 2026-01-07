#!/bin/bash

# ====================================================
# Project: FastVPS-Pro
# Author: facker668
# GitHub: https://github.com/facker668/fastvps
# Version: 1.1 (Support BBRv3 & ARM Check)
# ====================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
PLAIN='\033[0m'

LOCAL_VERSION="1.1"

# --- 自动检查架构 ---
ARCH=$(uname -m)

# --- 1. 自动更新检查 ---
check_update() {
    REMOTE_VERSION=$(curl -s https://raw.githubusercontent.com/facker668/fastvps/main/version.txt)
    if [[ -n "$REMOTE_VERSION" && "$REMOTE_VERSION" != "$LOCAL_VERSION" ]]; then
        echo -e "${YELLOW}检测到新版本 v$REMOTE_VERSION，正在为您自动更新...${PLAIN}"
        wget -qO optimize.sh https://raw.githubusercontent.com/facker668/fastvps/main/optimize.sh
        chmod +x optimize.sh
        echo -e "${GREEN}更新成功！请重新运行脚本。${PLAIN}"
        exit 0
    fi
}

# --- 2. BBRv3 安装模块 (仅限 x86_64) ---
func_bbrv3() {
    if [[ "$ARCH" != "x86_64" ]]; then
        echo -e "${RED}错误: BBRv3 (XanMod) 仅支持 x86_64 架构，您的架构为 $ARCH，请使用选项 2 开启普通 BBR。${PLAIN}"
        return
    fi

    echo -e "${YELLOW}正在为 Debian/Ubuntu 安装 XanMod BBRv3 内核...${PLAIN}"
    apt update && apt install -y gpg wget curl
    wget -qO - https://dl.xanmod.org/archive.key | gpg --dearmor -o /usr/share/keyrings/xanmod-archive-keyring.gpg
    echo 'deb [signed-by=/usr/share/keyrings/xanmod-archive-keyring.gpg] http://deb.xanmod.org releases main' | tee /etc/apt/sources.list.d/xanmod-kernel.list
    apt update && apt install -y linux-xanmod-x64v3
    
    # 写入配置
    if [ ! -f /etc/sysctl.conf ]; then touch /etc/sysctl.conf; fi
    sed -i '/net.core.default_qdisc/d' /etc/sysctl.conf
    sed -i '/net.ipv4.tcp_congestion_control/d' /etc/sysctl.conf
    echo "net.core.default_qdisc=fq" >> /etc/sysctl.conf
    echo "net.ipv4.tcp_congestion_control=bbr" >> /etc/sysctl.conf
    sysctl -p
    
    echo -e "${GREEN}BBRv3 内核安装完成！重启后生效。${PLAIN}"
    read -p "是否立即重启? (y/n): " confirm
    [[ "$confirm" == "y" ]] && reboot
}

# --- 3. 标准 BBR 加速 (全架构通用) ---
func_bbr_standard() {
    echo -e "${YELLOW}正在开启标准 BBR 加速...${PLAIN}"
    if [ ! -f /etc/sysctl.conf ]; then touch /etc/sysctl.conf; fi
    sed -i '/net.core.default_qdisc/d' /etc/sysctl.conf
    sed -i '/net.ipv4.tcp_congestion_control/d' /etc/sysctl.conf
    echo "net.core.default_qdisc=fq" >> /etc/sysctl.conf
    echo "net.ipv4.tcp_congestion_control=bbr" >> /etc/sysctl.conf
    sysctl -p
    echo -e "${GREEN}标准 BBR 已开启。${PLAIN}"
}

# --- 4. 修改 SSH 端口 ---
func_ssh() {
    echo -e "${YELLOW}正在修改 SSH 端口为 60000...${PLAIN}"
    sed -i "s/^#\?Port [0-9]*/Port 60000/g" /etc/ssh/sshd_config
    systemctl restart sshd
    echo -e "${GREEN}SSH 端口已改为 60000。${PLAIN}"
}

# --- 5. 安装 Docker ---
func_docker() {
    echo -e "${YELLOW}安装 Docker...${PLAIN}"
    curl -fsSL https://get.docker.com | bash
    systemctl enable --now docker
    echo -e "${GREEN}Docker 安装完成。${PLAIN}"
}

# --- 6. 智能 Swap ---
func_swap() {
    local mem=$(free -m | grep Mem | awk '{print $2}')
    local size=$mem
    [[ $mem -gt 1024 ]] && size=1024
    if [ ! -f /swapfile ]; then
        dd if=/dev/zero of=/swapfile bs=1M count=$size
        chmod 600 /swapfile
        mkswap /swapfile && swapon /swapfile
        echo '/swapfile none swap sw 0 0' >> /etc/fstab
    fi
    echo -e "${GREEN}Swap 配置完成。${PLAIN}"
}

# --- 菜单控制 ---
main_menu() {
    clear
    echo -e "${BLUE}====================================${PLAIN}"
    echo -e "${GREEN}    FastVPS Pro 管理工具 v$LOCAL_VERSION    ${PLAIN}"
    echo -e "${BLUE}    当前架构: $ARCH                  ${PLAIN}"
    echo -e "${BLUE}====================================${PLAIN}"
    echo -e "1. 🚀 安装 BBRv3 内核 (仅 x86_64 推荐)"
    echo -e "2. 🚀 开启标准 BBR 加速 (全架构通用)"
    echo -e "3. 🛡️ 修改 SSH 端口为 60000"
    echo -e "4. 📦 安装 Docker 环境"
    echo -e "5. 🧠 配置智能 Swap (虚拟内存)"
    echo -e "0. 退出"
    echo -e "${BLUE}====================================${PLAIN}"
    read -p "选择操作 [0-5]: " choice

    case $choice in
        1) func_bbrv3 ;;
        2) func_bbr_standard ;;
        3) func_ssh ;;
        4) func_docker ;;
        5) func_swap ;;
        *) exit 0 ;;
    esac
}

main_menu
