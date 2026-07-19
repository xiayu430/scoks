#!/bin/bash
# ============================================================
# Socks5 全自动一键安装脚本 (非交互版)
# 用户名/密码: q123 / q123
# 端口: 随机生成
# ============================================================

rm -f "$0"

# ---------- 固定配置 ----------
SOCKS_USER="q123"
SOCKS_PASS="q123"
BASE_PORT=$((RANDOM % 40000 + 10000))   # 随机端口 10000-49999
CONFIG_FILE="/etc/sk5/sk5_configs.txt"
# ------------------------------

# 安装必要工具
if ! command -v curl &>/dev/null; then
    yum install -y curl >/dev/null 2>&1 || apt-get install -y curl >/dev/null 2>&1
fi

clear
echo "###############################################################"
echo "#          Socks5 全自动一键安装                              #"
echo "#          用户名: $SOCKS_USER  密码: $SOCKS_PASS              "
echo "#          起始端口: $BASE_PORT                                "
echo "###############################################################"
echo

# ====== 防火墙清理 ======
iptables -P INPUT ACCEPT
iptables -P FORWARD ACCEPT
iptables -P OUTPUT ACCEPT
iptables -t nat -F
iptables -t mangle -F
iptables -F
iptables -X
iptables-save >/dev/null 2>&1

# ====== 获取本机IP列表 ======
ips=($(hostname -I))
echo ">>> 检测到 ${#ips[@]} 个IP地址"
for ip in "${ips[@]}"; do echo "    - $ip"; done
echo

# ====== 下载 sk5 二进制 ======
echo ">>> 正在下载 sk5 ..."
wget -q -O /usr/local/bin/sk5 https://github.com/yanpeng997995/prxoy/raw/main/sk5
chmod +x /usr/local/bin/sk5

# ====== 创建 systemd 服务 ======
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
systemctl enable sk5 >/dev/null 2>&1

# ====== 生成配置 ======
mkdir -p /etc/sk5
: > /etc/sk5/serve.toml
: > "$CONFIG_FILE"

get_public_ip_for_interface() {
    local lip="$1"
    local pip
    pip=$(curl --interface "$lip" -s --max-time 5 ifconfig.me 2>/dev/null)
    [[ -z "$pip" || "$pip" == *"error"* ]] && pip=$(curl -s --max-time 5 ifconfig.me)
    echo "$pip"
}

for ((i = 0; i < ${#ips[@]}; i++)); do
    socks_port=$((BASE_PORT + i))
    local_ip="${ips[i]}"

    echo ">>> 配置代理 $((i+1)): $local_ip:$socks_port"
    public_ip=$(get_public_ip_for_interface "$local_ip")

    # 写入持久化配置记录
    echo "$local_ip $socks_port $SOCKS_USER $SOCKS_PASS $public_ip" >> "$CONFIG_FILE"

    # 写入 sk5 TOML 配置
    cat <<EOF >> /etc/sk5/serve.toml

[[inbounds]]
listen = "$local_ip"
port = $socks_port
protocol = "socks"
tag = "$((i+1))"
[inbounds.settings]
auth = "password"
udp = true
ip = "$local_ip"
[[inbounds.settings.accounts]]
user = "$SOCKS_USER"
pass = "$SOCKS_PASS"
[[routing.rules]]
type = "field"
inboundTag = "$((i+1))"
outboundTag = "$((i+1))"

[[outbounds]]
sendThrough = "$local_ip"
protocol = "freedom"
tag = "$((i+1))"
EOF
done

# ====== 启动服务 ======
echo ">>> 启动 sk5 服务..."
systemctl restart sk5
sleep 3

# ====== 连通性测试 ======
echo
echo ">>> 测试代理连通性:"
echo "---------------------------------------"
while read -r line; do
    arr=($line)
    ip=${arr[0]} port=${arr[1]} user=${arr[2]} pass=${arr[3]} expected=${arr[4]}
    printf "  %-21s ... " "$ip:$port"
    export_ip=$(curl -s --connect-timeout 5 --max-time 10 \
        --socks5 "$user:$pass@$ip:$port" ifconfig.me 2>/dev/null)
    if [[ -n "$export_ip" ]]; then
        echo "✅ 出口IP: $export_ip"
    else
        echo "❌ 连接失败"
    fi
done < "$CONFIG_FILE"

# ====== 输出汇总 ======
echo
echo "###############################################################"
echo "#                  ✅ 安装完成                                #"
echo "###############################################################"
echo "#  用户名: $SOCKS_USER"
echo "#  密  码: $SOCKS_PASS"
echo "#  起始端口: $BASE_PORT"
echo "#  IP 数量: ${#ips[@]}"
echo "#  配置文件: $CONFIG_FILE"
echo "###############################################################"
echo
echo "代理列表:"
# 核心修改：严格输出 出口IP:端口:账号:密码
awk '{printf "%s:%s:%s:%s\n", $5, $2, $3, $4}' "$CONFIG_FILE"
echo
echo ">>> 脚本执行完毕，无需任何操作。"
