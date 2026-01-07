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
}

# 2. 独立 BBR 加速模块
func_bbr() {
    echo -e "${YELLOW}正在检测 BBR 状态...${PLAIN}"
    if [[ $(sysctl net.ipv4.tcp_congestion_control | awk '{print $3}') == "bbr" ]]; then
        echo -e "${BLUE}检测到系统已开启 BBR，正在优化内核参数...${PLAIN}"
    else
        echo -e "${YELLOW}正在开启 BBR 加速...${PLAIN}"
        echo "net.core.default_qdisc=fq" >> /etc/sysctl.conf
        echo "net.ipv4.tcp_congestion_control=bbr" >> /etc/sysctl.conf
    fi
    
    # 写入通用的内核优化参数
    cat > /etc/sysctl.d/99-vps-pro.conf <<EOF
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr
net.ipv4.tcp_tw_reuse = 1
net.ipv4.tcp_rmem = 4096 87380 4194304
net.ipv4.tcp_wmem = 4096 16384 4194304
EOF
    sysctl --system
    echo -e "${GREEN}BBR 加速与内核优化已完成！${PLAIN}"
}

# 3. 智能 Swap
func_swap() {
    echo -e "${YELLOW}正在配置智能 Swap...${PLAIN}"
    local mem=$(free -m | grep Mem | awk '{print $2}')
    local size=$mem
    [[ $mem -gt 1024 ]] && size=1024
    if [ $(free -m | grep -i swap | awk '{print $2}') -lt 128 ]; then
        dd if=/dev/zero of=/swapfile bs=1M count=$size
        chmod 600 /swapfile
        mkswap /swapfile && swapon /swapfile
        echo '/swapfile none swap sw 0 0' >> /etc/fstab
        echo -e "${GREEN}Swap 已创建: ${size}MB${PLAIN}"
    else
        echo -e "${BLUE}系统已有 Swap，跳过。${PLAIN}"
    fi
}

# 4. SSH 端口修改 (60000)
func_ssh() {
    echo -e "${YELLOW}正在修改 SSH 端口为 60000...${PLAIN}"
    sed -i "s/^#\?Port [0-9]*/Port 60000/g" /etc/ssh/sshd_config
    systemctl restart sshd
    echo -e "${GREEN}SSH 端口已改为 60000。${PLAIN}"
}

# 5. 安装 Docker
func_docker() {
    echo -e "${YELLOW}正在安装 Docker 引擎...${PLAIN}"
    if ! command -v docker >/dev/null 2>&1; then
        curl -fsSL https://get.docker.com | bash
        systemctl enable --now docker
        # 限制容器日志，防止硬盘满
        mkdir -p /etc/docker
        cat > /etc/docker/daemon.json <<EOF
{
  "log-driver": "json-file",
  "log-opts": {"max-size": "10m", "max-file": "3"}
}
EOF
        systemctl restart docker
        echo -e "${GREEN}Docker 安装完成。${PLAIN}"
    else
        echo -e "${BLUE}Docker 已存在。${PLAIN}"
    fi
}

# 6. 系统清理与日志限制
func_cleanup() {
    echo -e "${YELLOW}正在清理系统并限制日志占用...${PLAIN}"
    sed -i 's/^#\?SystemMaxUse.*/SystemMaxUse=50M/g' /etc/systemd/journald.conf
    systemctl restart systemd-journald
    apt-get autoremove -y
    echo -e "${GREEN}磁盘保护设置完成。${PLAIN}"
}

# 菜单
main_menu() {
    clear
    echo -e "${BLUE}====================================${PLAIN}"
    echo -e "${GREEN}    FastVPS Pro 极致优化管理菜单    ${PLAIN}"
    echo -e "${BLUE}====================================${PLAIN}"
    echo -e "1. 执行【全自动极致优化】(含所有项)"
    echo -e "2. 🚀 开启 BBR 网络加速与内核优化"
    echo -e "3. 📦 安装 Docker 与 Compose 环境"
    echo -e "4. 🧠 配置智能 Swap (适配小内存)"
    echo -e "5. 🛡️ 修改 SSH 端口为 60000"
    echo -e "6. 🧹 清理日志并保护磁盘空间"
    echo -e "0. 退出"
    echo -e "${BLUE}====================================${PLAIN}"
    read -p "请输入选项 [0-6]: " choice

    case $choice in
        1) func_init && func_bbr && func_swap && func_ssh && func_docker && func_cleanup ;;
        2) func_bbr ;;
        3) func_docker ;;
        4) func_swap ;;
        5) func_ssh ;;
        6) func_cleanup ;;
        *) exit 0 ;;
    esac
}

main_menu
