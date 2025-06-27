#!/bin/sh
rm -f $0

# 安装必要工具
if ! command -v curl &> /dev/null; then
    yum install -y curl >/dev/null 2>&1 || apt-get install -y curl >/dev/null 2>&1
fi

# 菜单显示函数
show_menu() {
    clear
    echo "###############################################################"
    echo "#            Socks5 代理管理工具                              #"
    echo "###############################################################"
    echo "#  1. 安装 Socks5 代理                                        #"
    echo "#  2. 卸载 Socks5 代理                                        #"
    echo "#  3. 退出                                                    #"
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

# 安装函数
install_sk5() {
    clear
    echo "###############################################################"
    echo "#                 Socks5 代理安装向导                         #"
    echo "###############################################################"
    echo
    
    # 询问起始端口
    read -p "请输入起始端口号 (默认: 55620): " base_port
    base_port=${base_port:-55620}
    
    # 防火墙设置
    iptables -P INPUT ACCEPT
    iptables -P FORWARD ACCEPT
    iptables -P OUTPUT ACCEPT
    iptables -t nat -F
    iptables -t mangle -F
    iptables -F
    iptables -X
    iptables-save

    # 获取公网IP和本地IP
    public_ip=$(curl -s ifconfig.me)
    ips=( $(hostname -I) )

    # 询问用户密码设置方式
    echo
    read -p "是否手动设置用户名和密码? (y/n, 默认n): " manual_set
    if [ "$manual_set" = "y" ] || [ "$manual_set" = "Y" ]; then
        echo
        read -p "请选择密码生成方式: 
        1) 所有代理使用相同用户名密码
        2) 为每个代理生成随机用户名密码
        请选择 (1/2): " pass_choice

        if [ "$pass_choice" = "1" ]; then
            read -p "请输入统一用户名: " base_user
            read -p "请输入统一密码: " base_pass
            echo "所有代理将使用统一用户名: $base_user 和密码: $base_pass"
            same_credentials=true
        else
            echo "将为每个代理自动生成随机用户名和密码"
            same_credentials=false
        fi
    else
        echo "将为每个代理自动生成随机用户名和密码"
        same_credentials=false
    fi

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

    # 随机生成函数
    gen_random_string() {
        LC_ALL=C tr -dc 'a-zA-Z0-9' </dev/urandom | fold -w "$1" | head -n 1
    }

    # 清屏并显示标题
    clear
    echo "###############################################################"
    echo "#        Socks5 代理配置信息                                  #"
    echo "#        公网IP: $public_ip                                  #"
    echo "###############################################################"
    echo

    # 保存配置用于测试
    config_file="/tmp/sk5_configs.txt"
    echo -n "" > $config_file

    # 配置每个IP
    for ((i = 0; i < ${#ips[@]}; i++)); do
        socks_port=$((base_port + i))

        # 根据用户选择决定用户名密码生成方式
        if [ "$manual_set" = "y" ] && [ "$same_credentials" = "true" ]; then
            # 所有代理使用相同凭证
            socks_user="$base_user"
            socks_pass="$base_pass"
        else
            # 为每个代理生成随机凭证
            socks_user="$(gen_random_string 8)"
            socks_pass="$(gen_random_string 12)"
        fi

        # 保存配置
        echo "${ips[i]} $socks_port $socks_user $socks_pass" >> $config_file

        # 写入配置文件
        cat <<EOF >> /etc/sk5/serve.toml
[[inbounds]]
listen = "${ips[i]}"
port = $socks_port
protocol = "socks"
tag = "$((i+1))"
[inbounds.settings]
auth = "password"
udp = true
ip = "${ips[i]}"
[[inbounds.settings.accounts]]
user = "$socks_user"
pass = "$socks_pass"
[[routing.rules]]
type = "field"
inboundTag = "$((i+1))"
outboundTag = "$((i+1))"
[[outbounds]]
sendThrough = "${ips[i]}"
protocol = "freedom"
tag = "$((i+1))"
EOF

        # 显示配置
        echo "代理 $((i+1)) 配置:"
        echo "监听地址: ${ips[i]}"
        echo "端口: $socks_port"
        echo "用户名: $socks_user"
        echo "密码: $socks_pass"
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

        echo -n "测试 $ip:$port ... "

        # 通过代理获取出口IP
        export_ip=$(curl -s --connect-timeout 5 --max-time 10 --socks5 "$user:$pass@$ip:$port" ifconfig.me 2>/dev/null)

        if [ -z "$export_ip" ]; then
            echo "失败 ❌"
        else
            echo "成功 ✅ 出口IP: $export_ip"
        fi
    done < $config_file

    # 安装完成信息
    echo
    echo "###############################################################"
    echo "#        安装完成!                                           #"
    echo "#        支持系统: CentOS 7+                                  #"
    echo "#        详细说明: socks5 自动安装程序                        #"
    echo "#        TG技术支持: akanonono                                #"
    echo "###############################################################"
    echo
    read -p "按回车键返回主菜单..." -r
}

# 主菜单循环
while true; do
    show_menu
    read -p "请输入选项 (1-3): " choice
    
    case $choice in
        1) install_sk5 ;;
        2) uninstall_sk5 ;;
        3) 
            clear
            echo "已退出"
            exit 0
            ;;
        *) 
            echo "无效选项，请重新输入!"
            sleep 1
            ;;
    esac
done
