#!/bin/bash

# ====================================================
# Project: FastVPS-Pro
# Author: facker668
# GitHub: https://github.com/facker668/fastvps
# Version: 1.0
# ====================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
PLAIN='\033[0m'

LOCAL_VERSION="1.0"

# --- 自动更新检查 ---
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

# --- 1. 系统初始化 ---
func_init() {
    echo -e "${YELLOW}正在同步时间并安装基础依赖...${PLAIN}"
    timedatectl set-timezone Asia/Shanghai
    apt-get update -y || yum update -y
    apt-get install -y curl wget tar sudo gpg >/dev/null 2>&1
}

# --- 2. 独立 BBR 加速模块 ---
func_bbr() {
    echo -e "${YELLOW}正在配置 BBR 网络加速...${PLAIN}"
    # 移除旧配置避免重复
    sed -i '/net.core.default_qdisc/d' /etc/sysctl.conf
    sed -i '/net.ipv4.tcp_congestion_control/d' /etc/sysctl.conf
    
    echo "net.core.default_qdisc=fq" >> /etc/sysctl.conf
    echo "net.ipv4.tcp_congestion_control=bbr" >> /etc/sysctl.conf
    
    # 极致网络优化参数
    cat > /etc/sysctl.d/99-vps-pro.conf <<EOF
net.ipv4.tcp_tw_reuse = 1
net.ipv4.tcp_rmem = 4096 87380 4194304
net.ipv4.tcp_wmem = 4096 16384 4194304
net.core.rmem_max = 4194304
net.core.wmem_max = 4194304
EOF
    sysctl -p >/dev/null 2>&1
    sysctl --system >/dev/null 2>&1
    echo -e "${GREEN}BBR 加速与内核优化已开启！${PLAIN}"
}

# --- 3. 智能 Swap 模块 ---
func_swap() {
    echo -e "${YELLOW}正在检查虚拟内存 (Swap)...${PLAIN}"
    if [ $(free -m | grep -i swap | awk '{print $2}') -lt 128 ]; then
        local mem=$(free -m | grep Mem | awk '{print $2}')
        local size=$mem
        [[ $mem -gt 1024 ]] && size=1024
        dd if=/dev/zero of=/swapfile bs=1M count=$size >/dev/null 2>&1
        chmod 600 /swapfile
        mkswap /swapfile >/dev/null 2>&1
        swapon /swapfile >/dev/null 2>&1
        echo '/swapfile none swap sw 0 0' >> /etc/fstab
        echo -e "${GREEN}Swap 创建成功: ${size}MB${PLAIN}"
    else
        echo -e "${BLUE}系统已有 Swap，跳过。${PLAIN}"
    fi
}

# --- 4. 修改 SSH 端口 ---
func_ssh() {
    echo -e "${YELLOW}正在修改 SSH 端口为 60000...${PLAIN}"
    sed -i "s/^#\?Port [0-9]*/Port 60000/g" /etc/ssh/sshd_config
    systemctl restart sshd
    echo -e "${GREEN}SSH 端口已改为 60000。请记住在防火墙放行该端口！${PLAIN}"
}

# --- 5. 安装 Docker ---
func_docker() {
    if ! command -v docker >/dev/null 2>&1; then
        echo -e "${YELLOW}正在安装 Docker 环境...${PLAIN}"
        curl -fsSL https://get.docker.com | bash
        systemctl enable --now docker
        # 限制容器日志防止撑爆硬盘
        mkdir -p /etc/docker
        cat > /etc/docker/daemon.json <<EOF
{
  "log-driver": "json-file",
  "log-opts": {"max-size": "10m", "max-file": "3"}
}
EOF
        systemctl restart docker
        echo -e "${GREEN}Docker 与日志回滚限制已配置完成。${PLAIN}"
    else
        echo -e "${BLUE}检测到 Docker 已存在。${PLAIN}"
    fi
}

# --- 6. 磁盘保护清理 ---
func_cleanup() {
    echo -e "${YELLOW}正在设置系统日志限制 (保护硬盘)...${PLAIN}"
    sed -i 's/^#\?SystemMaxUse.*/SystemMaxUse=50M/g' /etc/systemd/journald.conf
    systemctl restart systemd-journald
    apt-get autoremove -y >/dev/null 2>&1
    echo -e "${GREEN}磁盘保护设置完成。${PLAIN}"
}

# --- 菜单控制 ---
main_menu() {
    clear
    echo -e "${BLUE}====================================${PLAIN}"
    echo -e "${GREEN}    FastVPS Pro 极致优化工具 v$LOCAL_VERSION    ${PLAIN}"
    echo -e "${BLUE}====================================${PLAIN}"
    echo -e "1. 【一键极致优化】(含所有功能)"
    echo -e "2. 🚀 开启 BBR 网络加速"
    echo -e "3. 📦 安装 Docker 运行环境"
    echo -e "4. 🧠 配置智能 Swap (保护内存)"
    echo -e "5. 🛡️ 修改 SSH 端口为 60000"
    echo -e "6. 🧹 系统清理与日志限制"
    echo -e "0. 退出"
    echo -e "${BLUE}====================================${PLAIN}"
    read -p "选择操作 [0-6]: " choice

    case $choice in
        1) check_update && func_init && func_bbr && func_swap && func_ssh && func_docker && func_cleanup ;;
        2) func_bbr ;;
        3) func_docker ;;
        4) func_swap ;;
        5) func_ssh ;;
        6) func_cleanup ;;
        *) exit 0 ;;
    esac
}

main_menu
