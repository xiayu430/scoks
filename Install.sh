#!/bin/bash

# 设置颜色
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m'  # 无颜色

# 随机生成用户名(6位)和密码(8位)
generate_random() {
    USER=$(head /dev/urandom | tr -dc A-Za-z0-9 | head -c 6)   # 6位用户名
    PASSWD=$(head /dev/urandom | tr -dc A-Za-z0-9 | head -c 8) # 8位密码
    PORT=$(shuf -i 10000-65535 -n 1)  # 随机生成端口
}

function socks5() {
    # 判断是否是root用户
    if [ "$(id -u)" != "0" ]; then
        echo -e "${RED}此脚本需要以root用户权限运行。${NC}"
        echo "请尝试使用 'sudo -i' 命令切换到root用户，然后再次运行此脚本。"
        exit 1
    fi
    
    # 安装sk5，首先确保文件可以覆盖
    if lsof /usr/local/bin/sk5; then
        echo -e "${RED}sk5 文件正在被占用，正在尝试杀掉相关进程...${NC}"
        pkill -f /usr/local/bin/sk5  # 杀掉正在使用 sk5 的进程
        sleep 2  # 等待进程完全终止
    fi
    
    # 下载并设置 sk5
    wget -O /usr/local/bin/sk5 https://github.com/yanpeng997995/prxoy/raw/main/sk5
    chmod +x /usr/local/bin/sk5
    
    # 获取公网IP
    PUBLIC_IP=$(curl -s https://api.ipify.org)
    
    # sk5 安装
    chmod +x /usr/local/bin/sk5
    cat <<EOF > /etc/systemd/system/sk5.service
[Unit]
Description=The sk5 Proxy Server
After=network-online.target

[Service]
ExecStart=/usr/local/bin/sk5 -c /etc/sk5/serve.toml
ExecStop=/bin/kill -s QUIT \$MAINPID
Restart=always
RestartSec=15s

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable sk5
    
    # sk5 配置
    mkdir -p /etc/sk5
    echo -n "" > /etc/sk5/serve.toml
    
    cat <<EOF >> /etc/sk5/serve.toml
[[inbounds]]
listen = "0.0.0.0"
port = ${PORT}
protocol = "socks"
tag = "socks-inbound"

[inbounds.settings]
auth = "password"
udp = true

[[inbounds.settings.accounts]]
user = "${USER}"
pass = "${PASSWD}"

[[routing.rules]]
type = "field"
inboundTag = "socks-inbound"
outboundTag = "freedom-outbound"

[[outbounds]]
sendThrough = "0.0.0.0"
protocol = "freedom"
tag = "freedom-outbound"
EOF
    
    systemctl stop sk5
    systemctl start sk5
    
    # 仅显示公网IP, 端口, 用户名, 密码
    clear  # 清空当前页面
    echo -e "代理服务器搭建完成！"
    echo -e "公网IP: ${PUBLIC_IP}"
    echo -e "端口: ${PORT}"
    echo -e "用户名: ${USER}"
    echo -e "密码: ${PASSWD}"
}

# 自动执行Socks5代理搭建
generate_random  # 生成随机凭证
socks5           # 执行安装
