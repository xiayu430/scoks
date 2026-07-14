#!/bin/bash
rm -f $0

# 安装必要工具
if ! command -v curl &> /dev/null; then
    yum install -y curl >/dev/null 2>&1 || apt-get install -y curl >/dev/null 2>&1
fi

# 配置文件路径
CONFIG_FILE="/etc/sk5/sk5_configs.txt"

# 菜单显示函数
show_menu() {
    clear
    echo "###############################################################"
    echo "#            Socks5 代理管理工具                               #"
    echo "#                     QQ群技术支持: 6099725123                  #"
    echo "###############################################################"
    echo "#  1. 安装 Socks5 代理                                        #"
    echo "#  2. 卸载 Socks5 代理                                        #"
    echo "#  3. 查看代理配置信息                                         #"
    echo "#  4. Bug反馈                                                 #"
    echo "#  5. 退出                                                    #"
    echo "###############################################################"
    echo
}

# 卸载函数
uninstall_sk5() {
    clear
    echo ">>> 正在卸载 Socks5 代理服务..."
    
    # 停止服务
    systemctl stop sk5 >/dev/null 2>&1
    systemctl disable sk5 >/dev/null 2>&1
    
    # 删除文件
    rm -f /usr/local/bin/sk5
    rm -rf /etc/sk5
    rm -f /etc/systemd/system/sk5.service
    rm -f $CONFIG_FILE
    
    # 重载系统服务
    systemctl daemon-reload >/dev/null 2>&1
    
    # 清理防火墙规则
    iptables -P INPUT ACCEPT
    iptables -P FORWARD ACCEPT
    iptables -P OUTPUT ACCEPT
    iptables -t nat -F
    iptables -t mangle -F
    iptables -F
    iptables -X
    iptables-save >/dev/null 2>&1
    
    echo ">>> Socks5 代理服务已成功卸载!"
    echo
    read -p "按回车键返回主菜单..." -r
}

# 查看代理配置信息函数
view_configs() {
    clear
    echo "###############################################################"
    echo "#               Socks5 代理配置信息                           #"
    echo "###############################################################"
    echo
    
    if [ ! -f "$CONFIG_FILE" ]; then
        echo ">>> 未找到代理配置信息!"
        echo ">>> 请先安装 Socks5 代理服务"
        echo
        read -p "按回车键返回主菜单..." -r
        return
    fi
    
    # 显示代理配置
    echo "代理服务器配置:"
    echo "---------------------------------------"
    
    # 显示所有代理配置
    while read -r line; do
        arr=($line)
        local_ip=${arr[0]}
        port=${arr[1]}
        user=${arr[2]}
        pass=${arr[3]}
        public_ip=${arr[4]}
        
        echo "服务器IP: $local_ip (公网出口IP: $public_ip)"
        echo "  端口: $port  用户名: $user  密码: $pass"
        echo "---------------------------------------"
    done < "$CONFIG_FILE"
    
    echo
    echo "使用说明:"
    echo "1. 连接时使用对应的服务器IP和端口"
    echo "2. 每个IP的出口公网IP可能不同"
    echo
    read -p "按回车键返回主菜单..." -r
}

# Bug反馈函数（HTTP方式）
bug_feedback() {
    clear
    echo "###############################################################"
    echo "#                    Bug 反馈                                 #"
    echo "###############################################################"
    echo
    
    # 安全读取问题描述
    while true; do
        read -e -p "请输入您的问题描述: " feedback
        if [ -z "$feedback" ]; then
            echo "错误：反馈内容不能为空!"
            continue
        fi
        break
    done
    
    # 安全读取联系方式
    while true; do
        read -e -p "请输入您的联系方式: " lxfs
        if [ -z "$lxfs" ]; then
            echo "错误：联系方式不能为空!"
            continue
        fi
        break
    done

    # 获取系统信息 - 简化的系统信息
    os_info=""
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        os_info="$NAME $VERSION_ID"
    elif [ -f /etc/redhat-release ]; then
        os_info=$(cat /etc/redhat-release)
    else
        os_info=$(uname -s -r)
    fi
    
    public_ip=$(curl -s ifconfig.me)
    date_info=$(date)
    
    # 反馈服务器配置
    FEEDBACK_SERVER="http://43.163.94.138:8000"
    API_ENDPOINT="/feedback"
    
    # 准备JSON数据
    if command -v jq >/dev/null 2>&1; then
        json_data=$(jq -n \
            --arg fb "$feedback" \
            --arg lf "$lxfs" \
            --arg os "$os_info" \
            --arg ip "$public_ip" \
            --arg ts "$date_info" \
            '{feedback: $fb, lxfs: $lf, os_info: $os, public_ip: $ip, timestamp: $ts}')
    else
        # 手动创建JSON
        json_data=$(cat <<EOF
{
    "feedback": "$feedback",
    "lxfs": "$lxfs",
    "os_info": "$os_info",
    "public_ip": "$public_ip",
    "timestamp": "$date_info"
}
EOF
        )
    fi
    
    # 发送HTTP POST请求
    echo ">>> 正在发送反馈到服务器..."
    response=$(curl -s -X POST -H "Content-Type: application/json" \
        -d "$json_data" "$FEEDBACK_SERVER$API_ENDPOINT" 2>/dev/null)
    
    if [ $? -eq 0 ]; then
        if echo "$response" | grep -q "success"; then
            echo ">>> 反馈已成功发送! 感谢您的支持!"
        else
            echo ">>> 服务器处理反馈时出错: $response"
        fi
    else
        echo ">>> 错误：无法连接到反馈服务器!"
        echo ">>> 请手动将以下内容发送至 support@example.com:"
        echo "操作系统: $os_info"
        echo "公网IP: $public_ip"
        echo "问题描述: $feedback"
        echo "联系方式: $lxfs"
    fi
    
    echo
    read -p "按回车键返回主菜单..." -r
}

# 获取指定IP的出口公网IP
get_public_ip_for_interface() {
    local ip=$1
    # 使用curl通过指定接口获取出口IP
    public_ip=$(curl --interface $ip -s ifconfig.me)
    if [ -z "$public_ip" ] || [[ "$public_ip" == *"error"* ]]; then
        # 如果失败，使用默认方法获取公网IP
        public_ip=$(curl -s ifconfig.me)
    fi
    echo "$public_ip"
}

# 安装函数 - 已改为全自动（用户名/密码: q123，端口随机）
install_sk5() {
    clear
    echo "###############################################################"
    echo "#          Socks5 代理全自动安装                              #"
    echo "#          用户名: q123  密码: q123                           #"
    echo "###############################################################"
    echo

    # ========== 以下为修改部分：移除所有交互，硬编码参数 ==========
    base_port=$((RANDOM % 40000 + 10000))   # 随机端口 10000-49999
    manual_set="y"
    same_credentials=true
    base_user="q123"
    base_pass="q123"
    echo ">>> 起始端口: $base_port"
    echo ">>> 统一用户名: $base_user  统一密码: $base_pass"
    # =============================================================

    # 防火墙设置
    iptables -P INPUT ACCEPT
    iptables -P FORWARD ACCEPT
    iptables -P OUTPUT ACCEPT
    iptables -t nat -F
    iptables -t mangle -F
    iptables -F
    iptables -X
    iptables-save >/dev/null 2>&1

    # 获取本地IP
    ips=( $(hostname -I) )
    
    # 显示检测到的IP
    echo "检测到以下服务器IP地址:"
    for ((i = 0; i < ${#ips[@]}; i++)); do
        echo "  $((i+1)). ${ips[i]}"
    done
    echo

    # sk5 安装与设置
    echo
    echo ">>> 正在安装 Socks5 服务..."
    wget -O /usr/local/bin/sk5 https://github.com/yanpeng997995/prxoy/raw/main/sk5 >/dev/null 2>&1
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
    systemctl enable sk5 >/dev/null 2>&1

    # 配置 sk5
    mkdir -p /etc/sk5
    echo -n "" > /etc/sk5/serve.toml

    # 清屏并显示标题
    clear
    echo "###############################################################"
    echo "#        Socks5 代理配置信息                                  #"
    echo "#        服务器IP数量: ${#ips[@]}                             #"
    echo "###############################################################"
    echo

    # 保存配置用于测试和查看
    echo -n "" > $CONFIG_FILE

    # 配置每个IP
    for ((i = 0; i < ${#ips[@]}; i++)); do
        socks_port=$((base_port + i))
        local_ip="${ips[i]}"
        
        # 获取该IP的公网出口IP
        echo ">>> 正在获取 ${local_ip} 的公网出口IP..."
        public_ip=$(get_public_ip_for_interface $local_ip)
        echo ">>> 公网出口IP: $public_ip"

        # 根据用户选择决定用户名密码生成方式
        if [ "$manual_set" = "y" ] && [ "$same_credentials" = "true" ]; then
            # 所有代理使用相同凭证
            socks_user="$base_user"
            socks_pass="$base_pass"
        else
            # 此分支在全自动模式下不会触发，保留以维持原始逻辑结构
            socks_user="q123"
            socks_pass="q123"
        fi

        # 保存配置到永久文件（添加公网出口IP）
        echo "$local_ip $socks_port $socks_user $socks_pass $public_ip" >> $CONFIG_FILE

        # 写入配置文件
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
user = "$socks_user"
pass = "$socks_pass"
[[routing.rules]]
type = "field"
inboundTag = "$((i+1))"
outboundTag = "$((i+1))"

[[outbounds]]
sendThrough = "$local_ip"
protocol = "freedom"
tag = "$((i+1))"
EOF

        # 显示配置
        echo "代理 $((i+1)) 配置:"
        echo "监听地址: $local_ip"
        echo "端口: $socks_port"
        echo "用户名: $socks_user"
        echo "密码: $socks_pass"
        echo "公网出口IP: $public_ip"
        echo "-----------------------------"
    done

    # 启动服务
    systemctl stop sk5 >/dev/null 2>&1
    systemctl start sk5

    # 等待服务启动
    sleep 3

    # 测试每个代理
    echo
    echo "测试代理连通性和出口IP:"
    echo "---------------------------------------"

    while read -r line; do
        arr=($line)
        ip=${arr[0]}
        port=${arr[1]}
        user=${arr[2]}
        pass=${arr[3]}
        expected_public_ip=${arr[4]}

        echo -n "测试 $ip:$port ... "

        # 通过代理获取出口IP
        export_ip=$(curl -s --connect-timeout 5 --max-time 10 --socks5 "$user:$pass@$ip:$port" ifconfig.me 2>/dev/null)

        if [ -z "$export_ip" ]; then
            echo "失败 ❌"
        else
            if [ "$export_ip" == "$expected_public_ip" ]; then
                echo "成功 ✅ 出口IP: $export_ip (匹配)"
            else
                echo "成功 ✅ 出口IP: $export_ip (预期: $expected_public_ip)"
            fi
        fi
    done < $CONFIG_FILE

    # 安装完成信息
    echo
    echo "###############################################################"
    echo "#        安装完成!                                           #"
    echo "#        支持系统: CentOS 7+                                  #"
    echo "#        服务器IP数量: ${#ips[@]}                             #"
    echo "#        起始端口: $base_port                                 #"
    echo "#        用户名/密码: q123 / q123                             #"
    echo "#        详细说明: socks5 自动安装程序                        #"
    echo "#        遇到问题请使用菜单中的'Bug反馈'功能                  #"
    echo "#        QQ群技术支持: 609972590                             #"
    echo "#        可在菜单中查看代理配置信息                           #"
    echo "###############################################################"
    echo
    read -p "按回车键返回主菜单..." -r
}

# 主菜单循环
while true; do
    show_menu
    read -p "请输入选项 (1-5): " choice
    
    case $choice in
        1) install_sk5 ;;
        2) uninstall_sk5 ;;
        3) view_configs ;;
        4) bug_feedback ;;
        5) 
            clear
            echo "感谢使用，再见!"
            exit 0
            ;;
        *) 
            echo "无效选项，请重新输入!"
            sleep 1
            ;;
    esac
done
