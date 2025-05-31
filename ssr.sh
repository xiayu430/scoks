#!/usr/bin/env bash
PATH=/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/bin:/usr/local/sbin:~/bin
export PATH

#=================================================
#	System Required: CentOS 6+/Debian 6+/Ubuntu 14.04+
#	Description: Install the ShadowsocksR server
#	Version: 2.0.38
#	Author: Toyo
#	Blog: https://doub.io/ss-jc42/
#	Modified: Fixed port and password as requested
#=================================================

sh_ver="2.0.38"
filepath=$(cd "$(dirname "$0")"; pwd)
file=$(echo -e "${filepath}"|awk -F "$0" '{print $1}')
ssr_folder="/usr/local/shadowsocksr"
ssr_ss_file="${ssr_folder}/shadowsocks"
config_file="${ssr_folder}/config.json"
config_folder="/etc/shadowsocksr"
config_user_file="${config_folder}/user-config.json"
ssr_log_file="${ssr_ss_file}/ssserver.log"
Libsodiumr_file="/usr/local/lib/libsodium.so"
jq_file="${ssr_folder}/jq"
Green_font_prefix="\033[32m" && Red_font_prefix="\033[31m" && Green_background_prefix="\033[42;37m" && Red_background_prefix="\033[41;37m" && Font_color_suffix="\033[0m"
Info="${Green_font_prefix}[信息]${Font_color_suffix}"
Error="${Red_font_prefix}[错误]${Font_color_suffix}"
Separator_1="——————————————————————————————"

# 自动确认所有提示
export DEBIAN_FRONTEND=noninteractive
YES_FLAG="-y"
APT_OPTIONS="-o Dpkg::Options::='--force-confdef' -o Dpkg::Options::='--force-confold'"

# URL安全的Base64编码
urlsafe_base64() {
    echo -n "$1" | base64 | tr '+/' '-_' | tr -d '='
}

# 生成SS链接
generate_ss_link() {
    local method="$1"
    local password="$2"
    local ip="$3"
    local port="$4"
    
    # SS格式: ss://method:password@server:port
    local ss_data="${method}:${password}@${ip}:${port}"
    local encoded_data=$(urlsafe_base64 "$ss_data")
    echo "ss://${encoded_data}"
}

# 生成SSR链接
generate_ssr_link() {
    local method="$1"
    local password="$2"
    local protocol="$3"
    local obfs="$4"
    local ip="$5"
    local port="$6"
    
    # 移除协议和混淆的兼容后缀
    local ssr_protocol=$(echo "$protocol" | sed 's/_compatible//g')
    local ssr_obfs=$(echo "$obfs" | sed 's/_compatible//g')
    
    # SSR格式: ssr://server:port:protocol:method:obfs:password_base64/?params
    local password_base64=$(urlsafe_base64 "$password")
    local ssr_data="${ip}:${port}:${ssr_protocol}:${method}:${ssr_obfs}:${password_base64}"
    local encoded_data=$(urlsafe_base64 "$ssr_data")
    echo "ssr://${encoded_data}"
}

check_root(){
    [[ $EUID != 0 ]] && echo -e "${Error} 当前账号非ROOT(或没有ROOT权限)，无法继续操作，请使用${Green_background_prefix} sudo su ${Font_color_suffix}来获取临时ROOT权限（执行后会提示输入当前账号的密码）。" && exit 1
}

check_sys(){
    if [[ -f /etc/redhat-release ]]; then
        release="centos"
    elif cat /etc/issue | grep -q -E -i "debian"; then
        release="debian"
    elif cat /etc/issue | grep -q -E -i "ubuntu"; then
        release="ubuntu"
    elif cat /etc/issue | grep -q -E -i "centos|red hat|redhat"; then
        release="centos"
    elif cat /proc/version | grep -q -E -i "debian"; then
        release="debian"
    elif cat /proc/version | grep -q -E -i "ubuntu"; then
        release="ubuntu"
    elif cat /proc/version | grep -q -E -i "centos|red hat|redhat"; then
        release="centos"
    fi
    bit=`uname -m`
}

SSR_installation_status(){
    [[ ! -e ${config_user_file} ]] && echo -e "${Error} 没有发现 ShadowsocksR 配置文件，请检查 !" && exit 1
    [[ ! -e ${ssr_folder} ]] && echo -e "${Error} 没有发现 ShadowsocksR 文件夹，请检查 !" && exit 1
}

# 设置防火墙规则
Add_iptables(){
    iptables -I INPUT -m state --state NEW -m tcp -p tcp --dport ${ssr_port} -j ACCEPT
    iptables -I INPUT -m state --state NEW -m udp -p udp --dport ${ssr_port} -j ACCEPT
    ip6tables -I INPUT -m state --state NEW -m tcp -p tcp --dport ${ssr_port} -j ACCEPT
    ip6tables -I INPUT -m state --state NEW -m udp -p udp --dport ${ssr_port} -j ACCEPT
}

Save_iptables(){
    if [[ ${release} == "centos" ]]; then
        service iptables save
        service ip6tables save
    else
        iptables-save > /etc/iptables.up.rules
        ip6tables-save > /etc/ip6tables.up.rules
    fi
}

Set_iptables(){
    if [[ ${release} == "centos" ]]; then
        service iptables save
        service ip6tables save
        chkconfig --level 2345 iptables on
        chkconfig --level 2345 ip6tables on
    else
        iptables-save > /etc/iptables.up.rules
        ip6tables-save > /etc/ip6tables.up.rules
        echo -e '#!/bin/bash\n/sbin/iptables-restore < /etc/iptables.up.rules\n/sbin/ip6tables-restore < /etc/ip6tables.up.rules' > /etc/network/if-pre-up.d/iptables
        chmod +x /etc/network/if-pre-up.d/iptables
    fi
}

Get_IP(){
    ip=$(wget -qO- -t1 -T2 ipinfo.io/ip)
    if [[ -z "${ip}" ]]; then
        ip=$(wget -qO- -t1 -T2 api.ip.sb/ip)
        if [[ -z "${ip}" ]]; then
            ip=$(wget -qO- -t1 -T2 members.3322.org/dyndns/getip)
            if [[ -z "${ip}" ]]; then
                ip="VPS_IP"
            fi
        fi
    fi
    echo "$ip"
}

# 设置配置信息 - 使用固定值
Set_config_port(){
    ssr_port="10801"  # 使用指定端口
    echo -e "使用指定端口: ${Green_font_prefix}${ssr_port}${Font_color_suffix}"
}

Set_config_password(){
    ssr_password="Mima123++"  # 使用指定密码
    echo -e "使用指定密码: ${Green_font_prefix}${ssr_password}${Font_color_suffix}"
}

Set_config_method(){
    ssr_method="aes-256-cfb"
    echo -e "加密方式: ${Green_font_prefix}${ssr_method}${Font_color_suffix}"
}

Set_config_protocol(){
    ssr_protocol="origin"
    echo -e "协议: ${Green_font_prefix}${ssr_protocol}${Font_color_suffix}"
}

Set_config_obfs(){
    ssr_obfs="plain"
    echo -e "混淆: ${Green_font_prefix}${ssr_obfs}${Font_color_suffix}"
}

Set_config_protocol_param(){
    ssr_protocol_param=""
    echo -e "协议参数: ${Green_font_prefix}${ssr_protocol_param}${Font_color_suffix}"
}

Set_config_speed_limit_per_con(){
    ssr_speed_limit_per_con=0
    echo -e "单线程限速: ${Green_font_prefix}${ssr_speed_limit_per_con} KB/S${Font_color_suffix}"
}

Set_config_speed_limit_per_user(){
    ssr_speed_limit_per_user=0
    echo -e "端口总限速: ${Green_font_prefix}${ssr_speed_limit_per_user} KB/S${Font_color_suffix}"
}

Set_config_all(){
    Set_config_port
    Set_config_password
    Set_config_method
    Set_config_protocol
    Set_config_obfs
    Set_config_protocol_param
    Set_config_speed_limit_per_con
    Set_config_speed_limit_per_user
}

Check_python(){
    if ! command -v python &> /dev/null; then
        echo -e "${Info} 没有安装Python，开始安装..."
        if [[ ${release} == "centos" ]]; then
            yum ${YES_FLAG} install python > /dev/null 2>&1
        else
            apt-get ${YES_FLAG} install python > /dev/null 2>&1
        fi
        [[ $? -eq 0 ]] && echo -e "${Info} Python 安装成功" || echo -e "${Error} Python 安装失败"
    fi
}

Centos_yum(){
    echo -e "${Info} 正在更新系统包..."
    yum update ${YES_FLAG} > /dev/null 2>&1
    
    echo -e "${Info} 正在安装必要工具..."
    cat /etc/redhat-release |grep 7\..*|grep -i centos>/dev/null
    if [[ $? = 0 ]]; then
        yum install ${YES_FLAG} vim unzip net-tools > /dev/null 2>&1
    else
        yum install ${YES_FLAG} vim unzip > /dev/null 2>&1
    fi
    [[ $? -eq 0 ]] && echo -e "${Info} 工具安装成功" || echo -e "${Error} 工具安装失败"
}

Debian_apt(){
    echo -e "${Info} 正在更新软件包列表..."
    apt-get update > /dev/null 2>&1
    
    echo -e "${Info} 正在安装必要工具..."
    cat /etc/issue |grep 9\..*>/dev/null
    if [[ $? = 0 ]]; then
        apt-get ${YES_FLAG} ${APT_OPTIONS} install vim unzip net-tools > /dev/null 2>&1
    else
        apt-get ${YES_FLAG} ${APT_OPTIONS} install vim unzip > /dev/null 2>&1
    fi
    [[ $? -eq 0 ]] && echo -e "${Info} 工具安装成功" || echo -e "${Error} 工具安装失败"
}

# 下载 ShadowsocksR
Download_SSR(){
    cd "/usr/local/"
    echo -e "${Info} 正在下载 ShadowsocksR..."
    wget -N --no-check-certificate "https://github.com/ToyoDAdoubiBackup/shadowsocksr/archive/manyuser.zip" > /dev/null 2>&1
    
    [[ ! -e "manyuser.zip" ]] && echo -e "${Error} ShadowsocksR服务端 压缩包 下载失败 !" && rm -rf manyuser.zip && exit 1
    
    echo -e "${Info} 正在解压 ShadowsocksR..."
    unzip -q "manyuser.zip"
    
    [[ ! -e "/usr/local/shadowsocksr-manyuser/" ]] && echo -e "${Error} ShadowsocksR服务端 解压失败 !" && rm -rf manyuser.zip && exit 1
    
    echo -e "${Info} 正在设置 ShadowsocksR 目录..."
    mv "/usr/local/shadowsocksr-manyuser/" "/usr/local/shadowsocksr/"
    [[ ! -e "/usr/local/shadowsocksr/" ]] && echo -e "${Error} ShadowsocksR服务端 重命名失败 !" && rm -rf manyuser.zip && rm -rf "/usr/local/shadowsocksr-manyuser/" && exit 1
    
    rm -rf manyuser.zip
    
    [[ -e ${config_folder} ]] && rm -rf ${config_folder}
    mkdir -p ${config_folder}
    [[ ! -e ${config_folder} ]] && echo -e "${Error} ShadowsocksR配置文件的文件夹 建立失败 !" && exit 1
    
    echo -e "${Info} ShadowsocksR服务端 下载完成 !"
}

# 修复服务脚本问题
Create_Service_Script(){
    echo -e "${Info} 创建 ShadowsocksR 服务脚本..."
    
    # 创建服务脚本
    cat > /etc/init.d/ssr <<-'EOF'
#!/bin/bash
### BEGIN INIT INFO
# Provides:          SSR
# Required-Start:    $network $local_fs $remote_fs
# Required-Stop:     $network $local_fs $remote_fs
# Default-Start:     2 3 4 5
# Default-Stop:      0 1 6
# Short-Description: ShadowsocksR Server
# Description:       Start or stop the ShadowsocksR server
### END INIT INFO

# Author: Toyo <doub.io>

name=shadowsocksr
BIN=/usr/local/shadowsocksr/shadowsocks/server.py
conf=/etc/shadowsocksr/user-config.json
RETVAL=0

check_running(){
    pid=`ps -ef | grep -v grep | grep -i "${BIN}" | awk '{print $2}'`
    if [ -n "$pid" ]; then
        return 0
    else
        return 1
    fi
}

do_start(){
    check_running
    if [ $? -eq 0 ]; then
        echo "$name (pid $pid) is already running..."
        exit 0
    fi
    
    if [ ! -f "$conf" ]; then
        echo "$conf not found!"
        exit 1
    fi
    
    python $BIN -c $conf -d start
    RETVAL=$?
    if [ $RETVAL -eq 0 ]; then
        echo "Starting $name success"
    else
        echo "Starting $name failed"
    fi
    return $RETVAL
}

do_stop(){
    check_running
    if [ $? -eq 0 ]; then
        python $BIN -c $conf -d stop
        RETVAL=$?
        if [ $RETVAL -eq 0 ]; then
            echo "Stopping $name success"
        else
            echo "Stopping $name failed"
        fi
    else
        echo "$name is stopped"
        RETVAL=1
    fi
    return $RETVAL
}

do_status(){
    check_running
    if [ $? -eq 0 ]; then
        echo "$name (pid $pid) is running..."
    else
        echo "$name is stopped"
        RETVAL=1
    fi
    return $RETVAL
}

do_restart(){
    do_stop
    sleep 0.5
    do_start
}

case "$1" in
    start|stop|restart|status)
    do_$1
    ;;
    *)
    echo "Usage: $0 { start | stop | restart | status }"
    RETVAL=1
    ;;
esac

exit $RETVAL
EOF

    # 设置权限
    chmod +x /etc/init.d/ssr
    
    # 添加开机启动
    if [[ ${release} == "centos" ]]; then
        chkconfig --add ssr > /dev/null 2>&1
        chkconfig ssr on > /dev/null 2>&1
    else
        update-rc.d -f ssr defaults > /dev/null 2>&1
    fi
    
    echo -e "${Info} ShadowsocksR 服务脚本创建成功!"
}

# 安装 JQ解析器
JQ_install(){
    if [[ ! -e ${jq_file} ]]; then
        echo -e "${Info} 下载并安装 JQ解析器..."
        cd "${ssr_folder}"
        
        # 根据系统架构下载对应的jq版本
        if [[ ${bit} == "x86_64" ]]; then
            wget -q --no-check-certificate "https://github.com/stedolan/jq/releases/download/jq-1.6/jq-linux64" -O jq
        else
            wget -q --no-check-certificate "https://github.com/stedolan/jq/releases/download/jq-1.6/jq-linux32" -O jq
        fi
        
        if [[ ! -e ${jq_file} ]]; then
            echo -e "${Error} JQ解析器 下载失败，请检查 !"
            exit 1
        fi
        
        chmod +x ${jq_file}
        echo -e "${Info} JQ解析器 安装完成" 
    else
        echo -e "${Info} JQ解析器 已安装"
    fi
}

# 安装依赖
Installation_dependency(){
    if [[ ${release} == "centos" ]]; then
        Centos_yum
    else
        Debian_apt
    fi
    
    # 检查unzip是否安装成功
    if ! command -v unzip &> /dev/null; then
        echo -e "${Error} 依赖 unzip(解压压缩包) 安装失败，请手动安装: apt-get install unzip 或 yum install unzip"
        exit 1
    fi
    
    Check_python
    \cp -f /usr/share/zoneinfo/Asia/Shanghai /etc/localtime
}

# 写入配置信息
Write_configuration(){
    cat > ${config_user_file}<<-EOF
{
    "server": "0.0.0.0",
    "server_ipv6": "::",
    "server_port": ${ssr_port},
    "local_address": "127.0.0.1",
    "local_port": 1080,
    "password": "${ssr_password}",
    "method": "${ssr_method}",
    "protocol": "${ssr_protocol}",
    "protocol_param": "${ssr_protocol_param}",
    "obfs": "${ssr_obfs}",
    "obfs_param": "",
    "speed_limit_per_con": ${ssr_speed_limit_per_con},
    "speed_limit_per_user": ${ssr_speed_limit_per_user},
    "additional_ports" : {},
    "timeout": 120,
    "udp_timeout": 60,
    "dns_ipv6": false,
    "connect_verbose_info": 0,
    "redirect": "",
    "fast_open": false
}
EOF
}

Start_SSR(){
    SSR_installation_status
    check_pid
    [[ ! -z ${PID} ]] && echo -e "${Error} ShadowsocksR 正在运行 !" && exit 1
    
    echo -e "${Info} 正在启动 ShadowsocksR 服务..."
    /etc/init.d/ssr start > /dev/null 2>&1
    sleep 2s
    
    check_pid
    if [[ ! -z ${PID} ]]; then
        echo -e "${Info} ShadowsocksR 启动成功!"
        View_User
    else
        echo -e "${Error} ShadowsocksR 启动失败，请检查日志: ${ssr_log_file}"
        exit 1
    fi
}

check_pid(){
    PID=`ps -ef |grep -v grep | grep server.py |awk '{print $2}'`
}

# 显示配置信息和链接
View_User(){
    SSR_installation_status
    ip=$(Get_IP)
    
    # 从配置文件读取参数
    port=`${jq_file} '.server_port' ${config_user_file}`
    password=`${jq_file} '.password' ${config_user_file} | sed 's/^.//;s/.$//'`
    method=`${jq_file} '.method' ${config_user_file} | sed 's/^.//;s/.$//'`
    protocol=`${jq_file} '.protocol' ${config_user_file} | sed 's/^.//;s/.$//'`
    obfs=`${jq_file} '.obfs' ${config_user_file} | sed 's/^.//;s/.$//'`
    
    # 生成链接
    ss_link=$(generate_ss_link "$method" "$password" "$ip" "$port")
    ssr_link=$(generate_ssr_link "$method" "$password" "$protocol" "$obfs" "$ip" "$port")
    
    echo
    echo "==================================================="
    echo " ShadowsocksR 安装完成！"
    echo "==================================================="
    echo -e " I  P地址: \033[32m${ip}\033[0m"
    echo -e " 端口    : \033[32m${port}\033[0m"
    echo -e " 密码    : \033[32m${password}\033[0m"
    echo -e " 加密方式: \033[32m${method}\033[0m"
    echo -e " 协议    : \033[32m${protocol}\033[0m"
    echo -e " 混淆    : \033[32m${obfs}\033[0m"
    echo "---------------------------------------------------"
    echo -e " SS 链接 : \033[32m${ss_link}\033[0m"
    echo "---------------------------------------------------"
    echo -e " SSR链接 : \033[32m${ssr_link}\033[0m"
    echo "==================================================="
    echo
    echo "提示："
    echo "1. 复制上述链接到支持SS/SSR协议的客户端使用"
    echo "2. 如果使用SS客户端，请使用SS链接"
    echo "3. 如果使用SSR客户端，请使用SSR链接"
    echo
}

# 安装 ShadowsocksR
Install_SSR(){
    check_root
    [[ -e ${config_user_file} ]] && echo -e "${Error} ShadowsocksR 已安装，请检查 !" && exit 1
    [[ -e ${ssr_folder} ]] && echo -e "${Error} ShadowsocksR 文件夹已存在，请检查 !" && exit 1
    
    echo -e "${Info} 开始设置 ShadowsocksR 配置..."
    Set_config_all
    
    echo -e "${Info} 开始安装系统依赖..."
    Installation_dependency
    
    echo -e "${Info} 开始下载 ShadowsocksR..."
    Download_SSR
    
    echo -e "${Info} 创建 ShadowsocksR 服务脚本..."
    Create_Service_Script
    
    echo -e "${Info} 安装 JSON 解析器..."
    JQ_install
    
    echo -e "${Info} 写入配置文件..."
    Write_configuration
    
    echo -e "${Info} 配置防火墙..."
    Set_iptables
    
    echo -e "${Info} 添加防火墙规则..."
    Add_iptables
    
    echo -e "${Info} 保存防火墙规则..."
    Save_iptables
    
    Start_SSR
}

# 主执行逻辑
check_sys
Install_SSR
