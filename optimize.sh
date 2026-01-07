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

# 检查是否为 Root
[[ $EUID -ne 0 ]] && echo -e "${RED}错误: 必须使用 root 用户运行此脚本！${PLAIN}" && exit 1

# 1. 系统初始化
func_init() {
    echo -e "${YELLOW}正在同步时间并更新基础包...${PLAIN}"
    timedatectl set-timezone Asia/Shanghai
    apt-get update -y || yum update -y
    echo -e "${GREEN}系统初始化完成。${PLAIN}"
}

# 2. DNS 优化
func_dns() {
    echo -e "${YELLOW}正在优化 DNS 配置...${PLAIN}"
    cat > /etc/resolv.conf <<EOF
nameserver 8.8.8.8
nameserver 1.1.1.1
EOF
    echo -e "${GREEN}DNS 已优化为 Google/Cloudflare。${PLAIN}"
}

# 3. 智能 Swap
func_swap() {
    echo -e "${YELLOW}正在智能配置 Swap...${PLAIN}"
    local mem=$(free -m | grep Mem | awk '{print $2}')
    local disk=$(df -m / | awk 'NR==2 {print $4}')
    local size=$mem
    [[ $mem -gt 1024 ]] && size=1024
    
    if [ $disk -lt $((size + 500)) ]; then
        echo -e "${RED}空间不足，跳过 Swap。${PLAIN}"
    elif [ $(free -m | grep -i swap | awk '{print $2}') -lt 128 ]; then
        dd if=/dev/zero of=/swapfile bs=1M count=$size
        chmod 600 /swapfile
        mkswap /swapfile && swapon /swapfile
        echo '/swapfile none swap sw 0 0' >> /etc/fstab
        echo -e "${GREEN}Swap 创建成功: ${size}MB${PLAIN}"
    fi
}

# 4. SSH 端口修改
func_ssh() {
    echo -e "${YELLOW}正在修改 SSH 端口为 60000...${PLAIN}"
    sed -i "s/^#\?Port [0-9]*/Port 60000/g" /etc/ssh/sshd_config
    systemctl restart sshd
    echo -e "${GREEN}SSH 端口已改为 60000。请记住并在防火墙放行！${PLAIN}"
}

# 5. 安装 Docker
func_docker() {
    echo -e "${YELLOW}正在安装 Docker...${PLAIN}"
    if ! command -v docker >/dev/null 2>&1; then
        curl -fsSL https://get.docker.com | bash
        systemctl enable --now docker
        # 限制日志大小，防止爆硬盘
        mkdir -p /etc/docker
        cat > /etc/docker/daemon.json <<EOF
{
  "log-driver": "json-file",
  "log-opts": {"max-size": "10m", "max-file": "3"}
}
EOF
        systemctl restart docker
        echo -e "${GREEN}Docker 环境已就绪。${PLAIN}"
    else
        echo -e "${BLUE}Docker 已存在，跳过。${PLAIN}"
    fi
}

# 6. 网络内核优化 (BBR)
func_network() {
    echo -e "${YELLOW}正在优化内核参数并开启 BBR...${PLAIN}"
    cat > /etc/sysctl.d/99-vps-pro.conf <<EOF
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr
net.ipv4.tcp_tw_reuse = 1
net.ipv4.tcp_rmem = 4096 87380 4194304
net.ipv4.tcp_wmem = 4096 16384 4194304
EOF
    sysctl --system
    echo -e "${GREEN}网络优化完成。${PLAIN}"
}

# 7. 磁盘日志限制 (保护小硬盘)
func_cleanup() {
    echo -e "${YELLOW}正在限制系统日志大小...${PLAIN}"
    sed -i 's/^#\?SystemMaxUse.*/SystemMaxUse=50M/g' /etc/systemd/journald.conf
    systemctl restart systemd-journald
    echo -e "${GREEN}磁盘保护设置完成。${PLAIN}"
}

# 菜单
clear
echo -e "${BLUE}====================================${PLAIN}"
echo -e "${GREEN}    FastVPS Pro 极致优化脚本        ${PLAIN}"
echo -e "${BLUE}====================================${PLAIN}"
echo -e "1. 【一键极致优化】(含所有功能)"
echo -e "2. 仅安装 Docker 环境"
echo -e "3. 仅修改 SSH 端口为 60000"
echo -e "0. 退出"
read -p "选择操作 [0-3]: " choice

case $choice in
    1)
        func_init && func_dns && func_swap && func_ssh && func_docker && func_network && func_cleanup
        echo -e "${GREEN}>>> 极致优化完成！建议执行 reboot 重启系统。<<<${PLAIN}"
        ;;
    2) func_docker ;;
    3) func_ssh ;;
    *) exit 0 ;;
esac
