#!/bin/bash
rm -f $0
PATH=/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/bin:/usr/local/sbin:~/bin
export PATH

rootness(){
    if [[ $EUID -ne 0 ]]; then
       echo "必须使用root账号运行!" 1>&2
       exit 1
    fi
}

tunavailable(){
    if [[ ! -e /dev/net/tun ]]; then
        echo "TUN/TAP设备不可用!" 1>&2
        exit 1
    fi
}

disable_selinux(){
if [ -s /etc/selinux/config ] && grep 'SELINUX=enforcing' /etc/selinux/config; then
    sed -i 's/SELINUX=enforcing/SELINUX=disabled/g' /etc/selinux/config
    setenforce 0
fi
}

get_os_info(){
    IP=$( ip addr | egrep -o '[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}' | egrep -v "^192\.168|^172\.1[6-9]\.|^172\.2[0-9]\.|^172\.3[0-2]\.|^10\.|^127\.|^255\.|^0\." | head -n 1 )
    [ -z ${IP} ] && IP=$( wget -qO- -t1 -T2 ipv4.icanhazip.com )
}

preinstall_l2tp(){
    if [ -d "/proc/vz" ]; then
        echo -e "\033[41;37m WARNING: \033[0m Your VPS is based on OpenVZ, and IPSec might not be supported by the kernel."
        echo "Continue installation? (y/n)"
        read -p "(Default: n)" agree
        [ -z ${agree} ] && agree="n"
        if [ "${agree}" == "n" ]; then
            echo
            echo "L2TP installation cancelled."
            echo
            exit 0
        fi
    fi
    
    # 固定参数配置
    iprange="192.168.18"
    mypsk="1472580369"  # 预共享密钥
    
    echo "###########################"
    echo "公网ip: ${IP}"
    echo "l2tp网关: ${iprange}.1"
    echo "拨入客户端可用ip范围: ${iprange}.2-${iprange}.254"
    echo "PSK预共享密钥: ${mypsk}"
    echo "###########################"
}

install_l2tp(){
    mknod /dev/random c 1 9
    yum -y install epel-release
    yum -y install ppp libreswan xl2tpd iptables iptables-services
    config_install
}

config_install(){
    cat > /etc/ipsec.conf<<EOF
version 2.0

config setup
    protostack=netkey
    nhelpers=0
    uniqueids=no
    interfaces=%defaultroute
    virtual_private=%v4:10.0.0.0/8,%v4:192.168.0.0/16,%v4:172.16.0.0/12,%v4:!${iprange}.0/24

conn l2tp-psk
    rightsubnet=vhost:%priv
    also=l2tp-psk-nonat

conn l2tp-psk-nonat
    authby=secret
    pfs=no
    auto=add
    keyingtries=3
    rekey=no
    ikelifetime=8h
    keylife=1h
    type=transport
    left=%defaultroute
    leftid=${IP}
    leftprotoport=17/1701
    right=%any
    rightprotoport=17/%any
    dpddelay=40
    dpdtimeout=130
    dpdaction=clear
    sha2-truncbug=yes
EOF

    cat > /etc/ipsec.secrets<<EOF
%any %any : PSK "${mypsk}"
EOF

    cat > /etc/xl2tpd/xl2tpd.conf<<EOF
[global]
port = 1701

[lns default]
ip range = ${iprange}.2-${iprange}.254
local ip = ${iprange}.1
require chap = yes
refuse pap = yes
require authentication = yes
name = l2tpd
ppp debug = yes
pppoptfile = /etc/ppp/options.xl2tpd
length bit = yes
EOF

    cat > /etc/ppp/options.xl2tpd<<EOF
ipcp-accept-local
ipcp-accept-remote
require-mschap-v2
ms-dns 8.8.8.8
ms-dns 8.8.4.4
noccp
auth
hide-password
idle 0
mtu 1410
mru 1410
nodefaultroute
debug
proxyarp
connect-delay 5000
EOF

    rm -f /etc/ppp/chap-secrets
    cat > /etc/ppp/chap-secrets<<EOF
# Secrets for authentication using CHAP
# client    server    secret    IP addresses
EOF

    # 系统参数配置
    cp -pf /etc/sysctl.conf /etc/sysctl.conf.bak
    echo "# Added by L2TP VPN" >> /etc/sysctl.conf
    echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf
    sysctl -p

    # 服务管理
    systemctl enable ipsec xl2tpd
    systemctl restart ipsec xl2tpd
}

finally(){
    echo "验证安装"
    ipsec verify
    systemctl stop firewalld
    systemctl disable firewalld
    systemctl start iptables
    systemctl enable iptables
    echo "安装完成"
}

l2tp(){
    echo "开始安装L2TP/IPSec VPN"
    rootness
    tunavailable
    disable_selinux
    get_os_info
    preinstall_l2tp
    install_l2tp
    finally
}

# 主执行流程
if [ -s /etc/selinux/config ] && grep 'SELINUX=enforcing' /etc/selinux/config; then
    sed -i 's/SELINUX=enforcing/SELINUX=disabled/g' /etc/selinux/config
    setenforce 0
fi

# 安装必要工具
if ! command -v wget &> /dev/null; then yum install -y wget; fi
if ! command -v netstat &> /dev/null; then yum install -y net-tools; fi

l2tp

# 配置用户和防火墙规则
iptables -F
iptables -t nat -F
iptables -P INPUT ACCEPT

# 获取系统所有非回环IP
ip_list=()
while IFS= read -r line; do
    [ -n "$line" ] && ip_list+=("$line")
done < <(ip -4 addr | awk '/inet /{print $2}' | cut -d'/' -f1 | grep -v '^127\.')

# 创建用户信息表格
rm -f ./l2tp.txt
echo "序号  用户名       密码        预共享密钥    服务器IP         客户端IP         出口公网IP" > ./l2tp.txt
echo "========================================================================================" >> ./l2tp.txt

user_index=1
client_ip=2
fixed_password="dd141242"  # 固定密码

# 为每个IP创建两个用户
for nic_ip in "${ip_list[@]}"; do
    # 第一个用户：userX
    base_username="user$user_index"
    
    # 添加用户到chap-secrets
    echo "$base_username     l2tpd     $fixed_password     192.168.18.$client_ip" >> /etc/ppp/chap-secrets
    
    # 添加SNAT规则
    iptables -t nat -A POSTROUTING -s 192.168.18.$client_ip -j SNAT --to-source $nic_ip
    
    # 获取出口公网IP
    public_ip=$(curl -s --connect-timeout 3 --interface $nic_ip http://whatismyip.akamai.com)
    [ -z "$public_ip" ] && public_ip="N/A"
    
    # 添加到用户信息表格
    printf "%-4s    %-10s    %-10s    %-12s    %-15s    %-15s    %-15s\n" \
        $user_index $base_username $fixed_password $mypsk $IP "192.168.18.$client_ip" $public_ip >> ./l2tp.txt
    
    # 计数器递增
    ((client_ip++))
    
    # 第二个用户：userX_1
    second_username="${base_username}_1"
    
    # 添加用户到chap-secrets
    echo "$second_username     l2tpd     $fixed_password     192.168.18.$client_ip" >> /etc/ppp/chap-secrets
    
    # 添加SNAT规则
    iptables -t nat -A POSTROUTING -s 192.168.18.$client_ip -j SNAT --to-source $nic_ip
    
    # 获取出口公网IP（使用相同接口）
    # 添加到用户信息表格
    printf "%-4s    %-10s    %-10s    %-12s    %-15s    %-15s    %-15s\n" \
        "${user_index}_1" $second_username $fixed_password $mypsk $IP "192.168.18.$client_ip" $public_ip >> ./l2tp.txt
    
    # 计数器递增
    ((client_ip++))
    ((user_index++))
    
    # 检查IP范围是否有效
    if [ $client_ip -gt 254 ]; then
        echo "错误：客户端IP地址超出可用范围(192.168.18.2-254)" >&2
        exit 1
    fi
done

# 安全设置
chmod 600 /etc/ppp/chap-secrets

# 保存防火墙规则
iptables-save > /etc/sysconfig/iptables
systemctl restart xl2tpd ipsec

# 输出结果
echo -e "\n\033[1;32m账号密码保存在当前目录下 l2tp.txt 中\033[0m"
echo -e "\033[1;33mQQ群：609972590\033[0m\n"
cat ./l2tp.txt
