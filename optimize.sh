#!/bin/bash

# ====================================================
# Project: FastVPS-Pro
# Author: facker668
# GitHub: https://github.com/facker668/fastvps
# Version: 1.2 (BBRv3 + TCP Pro Tuning)
# ====================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
PLAIN='\033[0m'

LOCAL_VERSION="1.2"
ARCH=$(uname -m)

# --- 自动更新检查 ---
check_update() {
    REMOTE_VERSION=$(curl -s https://raw.githubusercontent.com/facker668/fastvps/main/version.txt)
    if [[ -n "$REMOTE_VERSION" && "$REMOTE_VERSION" != "$LOCAL_VERSION" ]]; then
        echo -e "${YELLOW}检测到新版本 v$REMOTE_VERSION，正在自动更新并运行...${PLAIN}"
        wget -qO optimize.sh https://raw.githubusercontent.com/facker668/fastvps/main/optimize.sh
        chmod +x optimize.sh
        exec ./optimize.sh
    fi
}

# --- 1. 系统初始化 ---
func_init() {
    echo -e "${YELLOW}正在同步时间并安装基础依赖...${PLAIN}"
    timedatectl set-timezone Asia/Shanghai
    apt-get update -y || yum update -y
    apt-get install -y curl wget tar sudo gpg ca-certificates >/dev/null 2>&1
}

# --- 2. BBRv3 内核安装 (XanMod) ---
func_bbrv3() {
    if [[ "$ARCH" != "x86_64" ]]; then
        echo -e "${RED}错误: BBRv3 仅支持 x86_64 架构。您的架构是 $ARCH，请选选项 2。${PLAIN}"
        return
    fi
    echo -e "${YELLOW}准备安装 XanMod BBRv3 专用内核 (支持 Debian/Ubuntu)...${PLAIN}"
    wget -qO - https://dl.xanmod.org/archive.key | gpg --dearmor -o /usr/share/keyrings/xanmod-archive-keyring.gpg
    echo 'deb [signed-by=/usr/share/keyrings/xanmod-archive-keyring.gpg] http://deb.xanmod.org releases main' | tee /etc/apt/sources.list.d/xanmod-kernel.list
    apt update && apt install -y linux-xanmod-x64v3
    
    # 启用 BBRv3 配置
    echo "net.core.default_qdisc=fq" > /etc/sysctl.d/99-bbrv3.conf
    echo "net.ipv4.tcp_congestion_control=bbr" >> /etc/sysctl.d/99-bbrv3.conf
    sysctl --system
    
    echo -e "${GREEN}BBRv3 内核安装完成！${PLAIN}"
    read -p "必须重启系统生效，是否现在重启? (y/n): " confirm
    [[ "$confirm" == "y" ]] && reboot
}

# --- 3. 标准 BBR 加速 + TCP 深度调优 ---
func_bbr_standard() {
    echo -e "${YELLOW}正在开启标准 BBR 并进行 TCP 极致调优...${PLAIN}"
    [ ! -f /etc/sysctl.conf ] && touch /etc/sysctl.conf
    sed -i '/net.core.default_qdisc/d' /etc/sysctl.conf
    sed -i '/net.ipv4.tcp_congestion_control/d' /etc/sysctl.conf
    
    cat > /etc/sysctl.d/99-vps-optimization.conf <<EOF
# TCP 窗口与缓冲区优化
net.core.rmem_max = 67108864
net.core.wmem_max = 67108864
net.ipv4.tcp_rmem = 4096 87380 67108864
net.ipv4.tcp_wmem = 4096 65536 67108864
net.core.netdev_max_backlog = 10000
net.core.somaxconn = 4096

# 开启 TCP Fast Open 与重用
net.ipv4.tcp_fastopen = 3
net.ipv4.tcp_tw_reuse = 1
net.ipv4.tcp_fin_timeout = 30
net.ipv4.tcp_keepalive_time = 1200

# 拥塞控制算法 BBR
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr
EOF
    sysctl --system
    echo -e "${GREEN}标准 BBR + TCP 调优已完成，无需重启即可生效！${PLAIN}"
}

# --- 4. 修改 SSH 端口 ---
func_ssh() {
    echo -e "${YELLOW}正在修改 SSH 端口为 60000...${PLAIN}"
    sed -i "s/^#\?Port [0-9]*/Port 60000/g" /etc/ssh/sshd_config
    systemctl restart sshd
    echo -e "${GREEN}SSH 端口已修改，请确保防火墙已放行 60000。${PLAIN}"
}

# --- 5. 安装 Docker ---
func_docker() {
    echo -e "${YELLOW}正在安装 Docker 环境...${PLAIN}"
    curl -fsSL https://get.docker.com | bash
    mkdir -p /etc/docker
    cat > /etc/docker/daemon.json <<EOF
{"log-driver":"json-file","log-opts":{"max-size":"10m","max-file":"3"}}
EOF
    systemctl restart docker
    echo -e "${GREEN}Docker 安装并限制日志成功。${PLAIN}"
}

# --- 6. 智能 Swap ---
func_swap() {
    echo -e "${YELLOW}正在配置智能 Swap...${PLAIN}"
    if [ $(free -m | grep -i swap | awk '{print $2}') -lt 128 ]; then
        local mem=$(free -m | grep Mem | awk '{print $2}')
        local size=$((mem > 1024 ? 1024 : mem))
        dd if=/dev/zero of=/swapfile bs=1M count=$size >/dev/null 2>&1
        chmod 600 /swapfile && mkswap /swapfile && swapon /swapfile
        echo '/swapfile none swap sw 0 0' >> /etc/fstab
        echo -e "${GREEN}Swap 已创建: ${size}MB${PLAIN}"
    else
        echo -e "${BLUE}已有 Swap，跳过。${PLAIN}"
    fi
}

# --- 菜单控制 ---
main_menu() {
    clear
    echo -e "${BLUE}====================================${PLAIN}"
    echo -e "${GREEN}    FastVPS Pro 极致管理工具 v$LOCAL_VERSION    ${PLAIN}"
    echo -e "${BLUE}    当前架构: $ARCH   OS: Debian/Ubuntu ${PLAIN}"
    echo -e "${BLUE}====================================${PLAIN}"
    echo -e "1. 🚀 安装 BBRv3 内核 (仅 x86_64，需重启)"
    echo -e "2. 🚀 标准 BBR 加速 + TCP 极致调优 (不需重启)"
    echo -e "3. 🛡️ 修改 SSH 端口为 60000"
    echo -e "4. 📦 安装 Docker 容器环境"
    echo -e "5. 🧠 配置智能 Swap (虚拟内存)"
    echo -e "0. 退出"
    echo -e "${BLUE}====================================${PLAIN}"
    read -p "选择操作 [0-5]: " choice

    case $choice in
        1) func_init && func_bbrv3 ;;
        2) func_init && func_bbr_standard ;;
        3) func_ssh ;;
        4) func_docker ;;
        5) func_swap ;;
        *) exit 0 ;;
    esac
}

check_update
main_menu
