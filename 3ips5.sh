#!/bin/sh

# 安装必要工具
if ! command -v curl &> /dev/null; then
    yum install -y curl >/dev/null 2>&1 || apt-get install -y curl >/dev/null 2>&1
fi

# 基础配置
CONFIG_FILE="/etc/sk5/config.txt"
SERVICE_FILE="/etc/systemd/system/sk5.service"
BIN_PATH="/usr/local/bin/sk5"
CONFIG_DIR="/etc/sk5"
TOML_FILE="$CONFIG_DIR/serve.toml"
LOCK_FILE="/tmp/sk5.lock"
BASE_PORT=55620

# 可靠的下载函数
download_sk5() {
    local max_retries=3
    local retry_count=0
    
    # 检测服务器地理位置 (国内/国外)
    local geo_location
    if timeout 3 curl -s ipinfo.io | grep -q '"country": "CN"'; then
        geo_location="CN"
        echo "检测到服务器位于国内，优先使用国内镜像源"
    else
        geo_location="INTL"
        echo "检测到服务器位于国外，优先使用国际镜像源"
    fi
    
    # 根据地理位置选择镜像优先级
    if [ "$geo_location" = "CN" ]; then
        local mirrors=(
            "https://monojson.com/s/pKH7m"      # 修正后的国内镜像
            "https://ghproxy.com/https://github.com/yanpeng997995/prxoy/raw/main/sk5"  # 国内加速镜像
            "https://github.com/yanpeng997995/prxoy/raw/main/sk5"
            "https://cdn.jsdelivr.net/gh/yanpeng997995/prxoy@main/sk5"     # JSDelivr CDN
            "https://raw.githubusercontent.com/yanpeng997995/prxoy/main/sk5"
        )
    else
        local mirrors=(
            "https://github.com/yanpeng997995/prxoy/raw/main/sk5"
            "https://cdn.jsdelivr.net/gh/yanpeng997995/prxoy@main/sk5"     # JSDelivr CDN
            "https://raw.githubusercontent.com/yanpeng997995/prxoy/main/sk5"
            "https://gitcode.com/2401_89691644/socks5/-/raw/main/sk5"      # 备用国内镜像
        )
    fi
    
    while [ $retry_count -lt $max_retries ]; do
        for mirror in "${mirrors[@]}"; do
            echo "尝试从镜像下载: $mirror (尝试 $((retry_count+1))/$max_retries)"
            curl -sL -o "$BIN_PATH" "$mirror"
            
            if [ $? -eq 0 ] && [ -s "$BIN_PATH" ]; then
                # 验证下载的文件是有效的二进制文件
                if file "$BIN_PATH" | grep -q "ELF"; then
                    chmod +x "$BIN_PATH"
                    echo "下载成功并验证为有效二进制文件"
                    return 0
                else
                    echo "下载的文件无效，可能不是二进制文件"
                    rm -f "$BIN_PATH"
                fi
            fi
        done
        
        retry_count=$((retry_count+1))
        sleep 2
    done
    
    echo "错误: 无法下载 sk5 二进制文件，请检查网络连接"
    return 1
}

# 菜单系统
main_menu() {
    clear
    echo "======================================================="
    echo "          Socks5 代理管理菜单 (多IP独立出口)           "
    echo "======================================================="
    
    # 检查是否已安装
    if [ -f $SERVICE_FILE ]; then
        echo "当前状态: 已安装"
        echo "---------------------------------------"
        echo "1. 查看当前配置"
        echo "2. 测试代理连接"
        echo "3. 修改用户名密码"
        echo "4. 修改代理端口"
        echo "5. 重启代理服务"
        echo "6. 卸载 Socks5 代理"
    else
        echo "当前状态: 未安装"
        echo "---------------------------------------"
        echo "1. 安装代理 (随机生成用户名密码)"
        echo "2. 安装代理 (手动设置用户名密码)"
    fi
    
    echo "0. 退出"
    echo "======================================================="
    read -p "请输入选项 [0-6]: " option
    
    case $option in
        1) if [ -f $SERVICE_FILE ]; then show_config; else install_random; fi ;;
        2) if [ -f $SERVICE_FILE ]; then test_proxies; else install_manual; fi ;;
        3) if [ -f $SERVICE_FILE ]; then change_credentials; else main_menu; fi ;;
        4) if [ -f $SERVICE_FILE ]; then change_ports; else main_menu; fi ;;
        5) if [ -f $SERVICE_FILE ]; then restart_service; else main_menu; fi ;;
        6) if [ -f $SERVICE_FILE ]; then uninstall_sk5; else main_menu; fi ;;
        0) exit 0 ;;
        *) echo "无效选项，请重新输入" && sleep 1 && main_menu ;;
    esac
}

# 随机生成函数
gen_random_string() {
    LC_ALL=C tr -dc 'a-zA-Z0-9' </dev/urandom | fold -w "$1" | head -n 1
}

# 防火墙设置
setup_firewall() {
    iptables -P INPUT ACCEPT
    iptables -P FORWARD ACCEPT
    iptables -P OUTPUT ACCEPT
    iptables -t nat -F
    iptables -t mangle -F
    iptables -F
    iptables -X
    iptables-save >/dev/null 2>&1
}

# 强制重启服务
force_restart_service() {
    # 确保服务完全停止
    systemctl stop sk5 >/dev/null 2>&1
    sleep 1
    
    # 杀死所有可能残留的进程
    pkill -9 sk5 >/dev/null 2>&1
    sleep 1
    
    # 启动服务
    systemctl start sk5
    sleep 2
    
    # 检查服务状态
    if systemctl is-active --quiet sk5; then
        echo "服务已成功重启"
    else
        echo "服务重启失败，尝试手动启动..."
        nohup $BIN_PATH -c $TOML_FILE >/dev/null 2>&1 &
        sleep 1
        if pgrep sk5 >/dev/null; then
            echo "服务已手动启动"
        else
            echo "错误: 服务无法启动，请检查日志"
        fi
    fi
}

# 安装函数 - 随机生成
install_random() {
    setup_firewall
    
    # 获取本地IP
    ips=( $(hostname -I) )
    if [ ${#ips[@]} -eq 0 ]; then
        echo "无法获取本地IP地址，请检查网络配置"
        exit 1
    fi

    # 下载并安装 sk5
    download_sk5
    if [ $? -ne 0 ]; then
        echo "安装失败: 无法下载 sk5 二进制文件"
        exit 1
    fi
    
    # 创建服务文件
    cat <<EOF > $SERVICE_FILE
[Unit]
Description=The sk5 Proxy Server
After=network-online.target
[Service]
ExecStart=$BIN_PATH -c $TOML_FILE
ExecStop=/bin/kill -s QUIT \$MAINPID
Restart=always
RestartSec=15s
[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable sk5 >/dev/null 2>&1

    # 配置目录
    mkdir -p $CONFIG_DIR
    echo -n "" > $TOML_FILE
    echo -n "" > $CONFIG_FILE

    # 配置每个IP
    for ((i=0; i<${#ips[@]}; i++)); do
        port=$((BASE_PORT + i))
        user=$(gen_random_string 8)
        pass=$(gen_random_string 12)
        
        # 添加到配置文件
        echo "${ips[i]} $port $user $pass" >> $CONFIG_FILE
        
        # 添加到TOML配置 (确保独立出口)
        cat <<EOF >> $TOML_FILE
[[inbounds]]
listen = "${ips[i]}"
port = $port
protocol = "socks"
tag = "proxy_$i"
[inbounds.settings]
auth = "password"
udp = true
ip = "${ips[i]}"
[[inbounds.settings.accounts]]
user = "$user"
pass = "$pass"
[[routing.rules]]
type = "field"
inboundTag = "proxy_$i"
outboundTag = "proxy_$i"
[[outbounds]]
protocol = "freedom"
tag = "proxy_$i"
sendThrough = "${ips[i]}"
[outbounds.settings]
domainStrategy = "UseIP"
EOF

        # 添加防火墙规则
        iptables -I INPUT -p tcp --dport $port -j ACCEPT
    done
    
    iptables-save >/dev/null 2>&1

    # 启动服务
    force_restart_service

    # 显示结果
    clear
    echo "======================================================="
    echo "          Socks5 代理安装完成 (随机生成)               "
    echo "======================================================="
    show_config
    test_proxies
    main_menu
}

# 安装函数 - 手动设置
install_manual() {
    setup_firewall
    
    # 获取本地IP
    ips=( $(hostname -I) )
    if [ ${#ips[@]} -eq 0 ]; then
        echo "无法获取本地IP地址，请检查网络配置"
        exit 1
    fi

    # 下载并安装 sk5
    download_sk5
    if [ $? -ne 0 ]; then
        echo "安装失败: 无法下载 sk5 二进制文件"
        exit 1
    fi
    
    # 创建服务文件
    cat <<EOF > $SERVICE_FILE
[Unit]
Description=The sk5 Proxy Server
After=network-online.target
[Service]
ExecStart=$BIN_PATH -c $TOML_FILE
ExecStop=/bin/kill -s QUIT \$MAINPID
Restart=always
RestartSec=15s
[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable sk5 >/dev/null 2>&1

    # 配置目录
    mkdir -p $CONFIG_DIR
    echo -n "" > $TOML_FILE
    echo -n "" > $CONFIG_FILE

    # 配置方式选择
    clear
    echo "======================================================="
    echo "          Socks5 代理安装 (手动设置)                   "
    echo "======================================================="
    echo "请选择配置方式:"
    echo "1. 所有代理使用相同的用户名密码"
    echo "2. 为每个代理生成随机用户名密码"
    read -p "请选择 [1-2]: " setup_choice
    
    if [ "$setup_choice" = "1" ]; then
        # 所有代理相同凭证
        read -p "请输入统一用户名: " base_user
        read -p "请输入统一密码: " base_pass
        same_credentials=true
    else
        same_credentials=false
    fi

    # 配置每个IP
    for ((i=0; i<${#ips[@]}; i++)); do
        ip=${ips[i]}
        port=$((BASE_PORT + i))
        
        clear
        echo "======================================================="
        echo "          配置代理 $((i+1)) - IP: $ip                  "
        echo "======================================================="
        
        if [ "$same_credentials" != "true" ]; then
            read -p "端口 (默认 $port): " custom_port
            [ -n "$custom_port" ] && port=$custom_port
            
            read -p "用户名: " user
            read -p "密码: " pass
        else
            user=$base_user
            pass=$base_pass
            echo "端口: $port"
            echo "用户名: $user"
            echo "密码: $pass"
        fi
        
        # 添加到配置文件
        echo "$ip $port $user $pass" >> $CONFIG_FILE
        
        # 添加到TOML配置 (确保独立出口)
        cat <<EOF >> $TOML_FILE
[[inbounds]]
listen = "$ip"
port = $port
protocol = "socks"
tag = "proxy_$i"
[inbounds.settings]
auth = "password"
udp = true
ip = "$ip"
[[inbounds.settings.accounts]]
user = "$user"
pass = "$pass"
[[routing.rules]]
type = "field"
inboundTag = "proxy_$i"
outboundTag = "proxy_$i"
[[outbounds]]
protocol = "freedom"
tag = "proxy_$i"
sendThrough = "$ip"
[outbounds.settings]
domainStrategy = "UseIP"
EOF

        # 添加防火墙规则
        iptables -I INPUT -p tcp --dport $port -j ACCEPT
    done
    
    iptables-save >/dev/null 2>&1

    # 启动服务
    force_restart_service

    # 显示结果
    clear
    echo "======================================================="
    echo "          Socks5 代理安装完成 (手动设置)               "
    echo "======================================================="
    show_config
    test_proxies
    main_menu
}

# 修改用户名密码
change_credentials() {
    clear
    echo "======================================================="
    echo "          修改代理用户名密码                           "
    echo "======================================================="
    
    if [ ! -f $CONFIG_FILE ]; then
        echo "未找到配置文件，请先安装代理"
        sleep 2
        main_menu
        return
    fi
    
    # 显示当前配置
    show_config
    
    # 选择修改范围
    echo "请选择修改范围:"
    echo "1. 修改单个代理的用户名密码"
    echo "2. 修改所有代理的用户名密码 (统一设置)"
    read -p "请选择 [1-2]: " range_choice
    
    if [ "$range_choice" = "1" ]; then
        # 修改单个代理
        read -p "请输入要修改的代理编号: " proxy_num
        if ! [[ "$proxy_num" =~ ^[0-9]+$ ]]; then
            echo "输入无效，请使用数字"
            sleep 1
            change_credentials
            return
        fi
        
        total_proxies=$(wc -l < $CONFIG_FILE)
        if [ $proxy_num -gt $total_proxies ] || [ $proxy_num -lt 1 ]; then
            echo "代理编号无效"
            sleep 1
            change_credentials
            return
        fi
        
        # 获取当前配置
        current_config=$(sed -n "${proxy_num}p" $CONFIG_FILE)
        read -r ip port old_user old_pass <<< $current_config
        
        echo "代理 $proxy_num 当前配置:"
        echo "IP: $ip, 端口: $port"
        echo "用户名: $old_user, 密码: $old_pass"
        echo
        
        read -p "请输入新的用户名: " new_user
        read -p "请输入新的密码: " new_pass
        
        # 更新配置文件
        sed -i "${proxy_num}s/$old_user $old_pass/$new_user $new_pass/" $CONFIG_FILE
        
        # 更新TOML配置 - 精确匹配目标配置块
        # 生成匹配模式
        start_pattern="listen = \"$ip\""
        user_pattern="user = \"$old_user\""
        pass_pattern="pass = \"$old_pass\""
        
        # 使用awk精确修改配置
        awk -v start_pat="$start_pattern" \
            -v user_pat="$user_pattern" \
            -v new_user="$new_user" \
            -v pass_pat="$pass_pattern" \
            -v new_pass="$new_pass" \
            'BEGIN { in_target = 0; user_updated = 0; pass_updated = 0 }
            {
                # 检测目标配置块开始
                if ($0 ~ start_pat) {
                    in_target = 1
                }
                
                # 在目标配置块内
                if (in_target) {
                    # 更新用户名
                    if ($0 ~ user_pat && !user_updated) {
                        gsub(user_pat, "user = \"" new_user "\"")
                        user_updated = 1
                    }
                    
                    # 更新密码
                    if ($0 ~ pass_pat && !pass_updated) {
                        gsub(pass_pat, "pass = \"" new_pass "\"")
                        pass_updated = 1
                    }
                    
                    # 检查是否完成更新
                    if (user_updated && pass_updated) {
                        in_target = 0
                    }
                }
                
                print
            }' $TOML_FILE > $TOML_FILE.tmp
        
        mv $TOML_FILE.tmp $TOML_FILE
        
        echo "代理 $proxy_num 的用户名密码已更新"
        
    elif [ "$range_choice" = "2" ]; then
        # 统一修改所有代理
        read -p "请输入新的统一用户名: " new_user
        read -p "请输入新的统一密码: " new_pass
        
        # 更新配置文件
        while read -r line; do
            read -r ip port old_user old_pass <<< "$line"
            sed -i "s/$ip $port $old_user $old_pass/$ip $port $new_user $new_pass/" $CONFIG_FILE
        done < $CONFIG_FILE
        
        # 更新TOML配置 - 全局替换
        # 使用sed进行全局替换
        sed -i "/user = / s/\".*\"/\"$new_user\"/g" $TOML_FILE
        sed -i "/pass = / s/\".*\"/\"$new_pass\"/g" $TOML_FILE
        
        echo "所有代理的用户名密码已统一更新"
    else
        echo "无效选择"
        sleep 1
        change_credentials
        return
    fi
    
    # 强制重启服务
    force_restart_service
    
    # 验证修改
    echo "验证修改..."
    show_config
    
    echo "服务已重启，新配置生效"
    sleep 2
    main_menu
}

# 修改端口
change_ports() {
    clear
    echo "======================================================="
    echo "          修改代理端口                                 "
    echo "======================================================="
    
    if [ ! -f $CONFIG_FILE ]; then
        echo "未找到配置文件，请先安装代理"
        sleep 2
        main_menu
        return
    fi
    
    # 显示当前配置
    show_config
    
    read -p "请输入要修改的代理编号: " proxy_num
    if ! [[ "$proxy_num" =~ ^[0-9]+$ ]]; then
        echo "输入无效，请使用数字"
        sleep 1
        change_ports
        return
    fi
    
    total_proxies=$(wc -l < $CONFIG_FILE)
    if [ $proxy_num -gt $total_proxies ] || [ $proxy_num -lt 1 ]; then
        echo "代理编号无效"
        sleep 1
        change_ports
        return
    fi
    
    # 获取当前配置
    current_config=$(sed -n "${proxy_num}p" $CONFIG_FILE)
    read -r ip old_port user pass <<< $current_config
    
    read -p "请输入新的端口号 (当前: $old_port): " new_port
    if ! [[ "$new_port" =~ ^[0-9]+$ ]] || [ $new_port -lt 1 ] || [ $new_port -gt 65535 ]; then
        echo "端口号无效 (1-65535)"
        sleep 1
        change_ports
        return
    fi
    
    # 检查端口是否已被使用
    if lsof -i :$new_port >/dev/null 2>&1; then
        echo "端口 $new_port 已被占用，请选择其他端口"
        sleep 1
        change_ports
        return
    fi
    
    # 更新配置文件
    sed -i "${proxy_num}s/$old_port/$new_port/" $CONFIG_FILE
    
    # 更新TOML配置 - 精确匹配目标配置块
    # 生成匹配模式
    start_pattern="listen = \"$ip\""
    port_pattern="port = $old_port"
    
    # 使用awk精确修改配置
    awk -v start_pat="$start_pattern" \
        -v port_pat="$port_pattern" \
        -v new_port="$new_port" \
        'BEGIN { in_target = 0; port_updated = 0 }
        {
            # 检测目标配置块开始
            if ($0 ~ start_pat) {
                in_target = 1
            }
            
            # 在目标配置块内
            if (in_target && !port_updated) {
                # 更新端口
                if ($0 ~ port_pat) {
                    gsub(port_pat, "port = " new_port)
                    port_updated = 1
                }
            }
            
            # 重置标志
            if (in_target && port_updated) {
                in_target = 0
            }
            
            print
        }' $TOML_FILE > $TOML_FILE.tmp
    
    mv $TOML_FILE.tmp $TOML_FILE
    
    # 更新防火墙规则
    iptables -D INPUT -p tcp --dport $old_port -j ACCEPT >/dev/null 2>&1
    iptables -I INPUT -p tcp --dport $new_port -j ACCEPT
    iptables-save >/dev/null 2>&1
    
    # 强制重启服务
    force_restart_service
    
    # 验证修改
    echo "验证修改..."
    show_config
    
    echo "代理 $proxy_num 的端口已从 $old_port 修改为 $new_port"
    echo "服务已重启，新配置生效"
    sleep 2
    main_menu
}

# 卸载函数
uninstall_sk5() {
    clear
    echo "======================================================="
    echo "          卸载 Socks5 代理                             "
    echo "======================================================="
    
    if [ ! -f $SERVICE_FILE ]; then
        echo "Socks5 代理未安装"
        sleep 2
        main_menu
        return
    fi
    
    read -p "确定要卸载吗? 这将删除所有配置! (y/n): " confirm
    if [ "$confirm" != "y" ] && [ "$confirm" != "Y" ]; then
        echo "卸载已取消"
        sleep 1
        main_menu
        return
    fi
    
    # 停止服务
    systemctl stop sk5 >/dev/null 2>&1
    systemctl disable sk5 >/dev/null 2>&1
    
    # 杀死所有可能残留的进程
    pkill -9 sk5 >/dev/null 2>&1
    
    # 删除防火墙规则
    if [ -f $CONFIG_FILE ]; then
        while read -r line; do
            read -r ip port user pass <<< $line
            iptables -D INPUT -p tcp --dport $port -j ACCEPT >/dev/null 2>&1
        done < $CONFIG_FILE
    fi
    
    # 删除文件
    rm -f $BIN_PATH
    rm -f $SERVICE_FILE
    rm -rf $CONFIG_DIR
    rm -f $CONFIG_FILE
    
    # 清理系统
    iptables-save >/dev/null 2>&1
    systemctl daemon-reload
    
    echo "Socks5 代理已成功卸载"
    sleep 2
    main_menu
}

# 显示配置
show_config() {
    clear
    echo "======================================================="
    echo "          当前 Socks5 代理配置                         "
    echo "======================================================="
    
    if [ ! -f $CONFIG_FILE ]; then
        echo "未找到代理配置"
    else
        public_ip=$(curl -s ifconfig.me)
        echo "公网IP: $public_ip"
        echo "本地IP: $(hostname -I)"
        echo
        echo "代理列表:"
        echo "编号 | IP地址        | 端口   | 用户名     | 密码"
        echo "----|---------------|--------|------------|------------"
        
        count=1
        while read -r line; do
            read -r ip port user pass <<< $line
            printf "%-4s| %-13s | %-6s | %-10s | %-12s\n" "$count" "$ip" "$port" "$user" "$pass"
            ((count++))
        done < $CONFIG_FILE
    fi
    
    echo "======================================================="
    read -p "按 Enter 键返回菜单..."
    main_menu
}

# 重启服务
restart_service() {
    force_restart_service
    echo "服务已重启"
    sleep 2
    main_menu
}

# 测试代理
test_proxies() {
    clear
    echo "======================================================="
    echo "          代理连接测试 (独立出口IP)                    "
    echo "======================================================="
    
    if [ ! -f $CONFIG_FILE ]; then
        echo "未找到代理配置"
        sleep 2
        main_menu
        return
    fi
    
    # 用于存储出口IP的数组
    declare -a export_ips
    unique_ips=()
    
    # 创建临时文件存储测试结果
    tmp_file=$(mktemp)
    
    while read -r line; do
        arr=($line)
        ip=${arr[0]}
        port=${arr[1]}
        user=${arr[2]}
        pass=${arr[3]}
        
        echo -n "测试 $ip:$port ($user:$pass) ... "
        
        # 通过代理获取出口IP - 使用超时和重试机制
        export_ip=""
        for attempt in {1..3}; do
            # 强制使用新连接，避免缓存
            export_ip=$(timeout 10 curl -s --socks5 "$user:$pass@$ip:$port" --no-keepalive ifconfig.me 2>/dev/null)
            if [ -n "$export_ip" ]; then
                break
            fi
            sleep 1
        done
        
        if [ -z "$export_ip" ]; then
            echo "失败 ❌"
            export_ips+=("失败")
        else
            echo "成功! 出口IP: $export_ip ✅"
            export_ips+=("$export_ip")
            
            # 存储可用的代理连接信息
            echo "$export_ip:$port:$user:$pass" >> $tmp_file
            
            # 记录唯一出口IP
            if [[ ! " ${unique_ips[@]} " =~ " ${export_ip} " ]]; then
                unique_ips+=("$export_ip")
            fi
        fi
    done < $CONFIG_FILE
    
    # 显示可用的代理连接信息
    if [ -s $tmp_file ]; then
        echo
        echo "======================================================="
        echo "          可用代理连接信息 (可直接复制使用)             "
        echo "======================================================="
        echo "格式: 公网IP:端口:用户名:密码"
        echo "---------------------------------------"
        cat $tmp_file
        echo "---------------------------------------"
        echo "总可用代理数: $(wc -l < $tmp_file)"
        echo "独立出口IP数: ${#unique_ips[@]}"
    else
        echo
        echo "警告: 没有可用的代理连接"
    fi
    
    # 清理临时文件
    rm -f $tmp_file
    
    echo "======================================================="
    read -p "按 Enter 键返回菜单..."
    main_menu    
}

# 主入口
main_menu
