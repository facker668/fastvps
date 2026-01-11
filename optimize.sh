#!/bin/bash

# ====================================================
# Project: FastVPS-Pro (Fixed & Optimized)
# Author: facker668
# GitHub: https://github.com/facker668/fastvps
# Version: 1.4
# ====================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
PLAIN='\033[0m'

LOCAL_VERSION="1.4"
ARCH=$(uname -m)

# 权限检查
[[ $EUID -ne 0 ]] && echo -e "${RED}错误: 必须使用 root 用户运行此脚本！${PLAIN}" && exit 1

# --- 获取 BBR 状态 ---
get_bbr_status() {
    local status=$(sysctl net.ipv4.tcp_congestion_control | awk '{print $3}')
    if [[ "$status" == "bbr" ]]; then
        echo -e "${GREEN}已开启 (bbr)${PLAIN}"
    elif [[ "$status" == "bbrv3" ]]; then
        echo -e "${GREEN}已开启 (bbrv3)${PLAIN}"
    else
        echo -e "${RED}未开启 ($status)${PLAIN}"
    fi
}

# --- 获取内核版本 ---
get_kernel_version() {
    uname -r
}

# --- 1. 系统初始化 ---
func_init() {
    echo -e "${YELLOW}正在同步时间并安装基础依赖...${PLAIN}"
    timedatectl set-timezone Asia/Shanghai
    
    if command -v apt-get >/dev/null 2>&1; then
        apt-get update -y
        apt-get install -y curl wget tar sudo gpg ca-certificates gnupg2 software-properties-common >/dev/null 2>&1
    elif command -v yum >/dev/null 2>&1; then
        yum makecache
        yum install -y curl wget tar sudo coreutils >/dev/null 2>&1
    fi
}

# --- 2. BBRv3 内核安装 (针对 Debian/Ubuntu 优化) ---
func_bbrv3() {
    if [[ "$ARCH" != "x86_64" ]]; then
        echo -e "${RED}错误: BBRv3 (XanMod) 仅支持 x86_64 架构。${PLAIN}"
        return
    fi
    
    if ! command -v apt-get >/dev/null 2>&1; then
        echo -e "${RED}错误: XanMod 内核安装目前仅支持 Debian/Ubuntu 系统。${PLAIN}"
        return
    fi

    echo -e "${YELLOW}正在配置 XanMod 官方源...${PLAIN}"
    curl -fsSL https://dl.xanmod.org/archive.key | gpg --dearmor --yes -o /usr/share/keyrings/xanmod-archive-keyring.gpg
    echo 'deb [signed-by=/usr/share/keyrings/xanmod-archive-keyring.gpg] http://deb.xanmod.org releases main' | tee /etc/apt/sources.list.d/xanmod-kernel.list
    
    apt update -y
    echo -e "${YELLOW}正在安装 XanMod v3 核心 (BBRv3)...${PLAIN}"
    apt install -y linux-xanmod-x64v3
    
    cat > /etc/sysctl.d/99-bbrv3.conf <<EOF
net.core.default_qdisc = fq_pie
net.ipv4.tcp_congestion_control = bbr
EOF
    sysctl --system
    
    echo -e "${GREEN}BBRv3 内核安装完成！${PLAIN}"
    read -p "必须重启系统生效，是否现在重启? (y/n): " confirm
    [[ "$confirm" == "y" ]] && reboot
}

# --- 3. 标准 BBR 加速 + TCP 深度调优 ---
func_bbr_standard() {
    echo -e "${YELLOW}正在进行 TCP 极致调优...${PLAIN}"
    
    sed -i '/net.core.default_qdisc/d' /etc/sysctl.conf
    sed -i '/net.ipv4.tcp_congestion_control/d' /etc/sysctl.conf
    
    cat > /etc/sysctl.d/99-vps-optimization.conf <<EOF
# 缓冲区优化
net.core.rmem_max = 67108864
net.core.wmem_max = 67108864
net.ipv4.tcp_rmem = 4096 87380 67108864
net.ipv4.tcp_wmem = 4096 65536 67108864
net.core.netdev_max_backlog = 10000
net.core.somaxconn = 4096

# 连接重用与复用
net.ipv4.tcp_fastopen = 3
net.ipv4.tcp_tw_reuse = 1
net.ipv4.tcp_fin_timeout = 30
net.ipv4.tcp_keepalive_time = 1200
net.ipv4.tcp_mtu_probing = 1

# 拥塞控制
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr
EOF
    sysctl --system
    echo -e "${GREEN}标准 BBR + TCP 调优已完成！${PLAIN}"
    sleep 2
}

# --- 4. 修改 SSH 端口 ---
func_ssh() {
    local port=60000
    echo -e "${YELLOW}正在尝试修改 SSH 端口为 $port...${PLAIN}"
    
    if command -v ufw >/dev/null 2>&1; then
        ufw allow $port/tcp
    elif command -v firewall-cmd >/dev/null 2>&1; then
        firewall-cmd --permanent --add-port=$port/tcp
        firewall-cmd --reload
    fi

    sed -i "s/^#\?Port [0-9]*/Port $port/g" /etc/ssh/sshd_config
    systemctl restart sshd
    echo -e "${GREEN}SSH 端口已修改为 $port。${PLAIN}"
}

# --- 5. 安装 Docker ---
func_docker() {
    echo -e "${YELLOW}正在安装 Docker 环境...${PLAIN}"
    curl -fsSL https://get.docker.com | bash
    
    [ ! -d "/etc/docker" ] && mkdir -p /etc/docker
    
    cat > /etc/docker/daemon.json <<EOF
{
    "log-driver": "json-file",
    "log-opts": {
        "max-size": "10m",
        "max-file": "3"
    }
}
EOF
    systemctl restart docker
    systemctl enable docker
    echo -e "${GREEN}Docker 安装成功。${PLAIN}"
    sleep 2
}

# --- 6. 智能 Swap ---
func_swap() {
    if [ $(free -m | grep -i swap | awk '{print $2}') -lt 128 ]; then
        echo -e "${YELLOW}正在配置智能 Swap...${PLAIN}"
        local mem=$(free -m | grep Mem | awk '{print $2}')
        local size=$((mem > 1024 ? 1024 : mem))
        
        swapoff -a >/dev/null 2>&1
        dd if=/dev/zero of=/swapfile bs=1M count=$size
        chmod 600 /swapfile
        mkswap /swapfile
        swapon /swapfile
        
        sed -i '/\/swapfile/d' /etc/fstab
        echo '/swapfile none swap sw 0 0' >> /etc/fstab
        echo -e "${GREEN}Swap 创建成功: ${size}MB${PLAIN}"
    else
        echo -e "${BLUE}检测到系统已有 Swap，跳过。${PLAIN}"
    fi
    sleep 2
}

# --- 菜单控制 ---
main_menu() {
    while true; do
        clear
        echo -e "${BLUE}====================================${PLAIN}"
        echo -e "${GREEN}    FastVPS Pro 极致管理工具 v$LOCAL_VERSION    ${PLAIN}"
        echo -e "${BLUE}------------------------------------${PLAIN}"
        echo -e " 系统内核: ${YELLOW}$(get_kernel_version)${PLAIN}"
        echo -e " BBR 状态: $(get_bbr_status)"
        echo -e " 当前架构: ${YELLOW}$ARCH${PLAIN}"
        echo -e "${BLUE}====================================${PLAIN}"
        echo -e "1. 🚀 安装 BBRv3 内核 (仅限 Debian/Ubuntu)"
        echo -e "2. 🚀 标准 BBR 加速 + TCP 极致调优"
        echo -e "3. 🛡️ 修改 SSH 端口为 60000"
        echo -e "4. 📦 安装 Docker 容器环境"
        echo -e "5. 🧠 配置智能 Swap (虚拟内存)"
        echo -e "6. 📊 查看详细内核参数报告"
        echo -e "0. 退出"
        echo -e "${BLUE}====================================${PLAIN}"
        read -p "选择操作 [0-6]: " choice

        case $choice in
            1) func_init && func_bbrv3 ;;
            2) func_init && func_bbr_standard ;;
            3) func_ssh ;;
            4) func_docker ;;
            5) func_swap ;;
            6) 
                echo -e "${YELLOW}--- 详细参数 ---${PLAIN}"
                sysctl net.ipv4.tcp_congestion_control
                sysctl net.core.default_qdisc
                lsmod | grep bbr
                read -p "按回车键返回菜单..." 
                ;;
            0) exit 0 ;;
            *) echo -e "${RED}输入错误，请重新选择${PLAIN}" && sleep 1 ;;
        esac
    done
}

main_menu
