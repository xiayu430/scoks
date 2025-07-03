#!/bin/bash
rm -f $0
PATH=/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/bin:/usr/local/sbin:~/bin
export PATH

function rand_psk()
{
    r_psk=`mkpasswd -l 9 -s 0 -c 3 -C 3 -d 3`
    echo $r_psk
}

function rand_pass()
{
    pass=`mkpasswd -l 6 -s 0 -c 0 -C 0 -d 6`
    echo $pass
}

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


rand(){
    index=0
    str=""
    for i in {a..z}; do arr[index]=${i}; index=`expr ${index} + 1`; done
    for i in {A..Z}; do arr[index]=${i}; index=`expr ${index} + 1`; done
    for i in {0..9}; do arr[index]=${i}; index=`expr ${index} + 1`; done
    for i in {1..10}; do str="$str${arr[$RANDOM%$index]}"; done
    echo ${str}
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
    
    # 交互信息固定
    iprange="192.168.18"
	
	# 预共享密钥手动指定
	mypsk="1472580369"
	
    echo "###########################"
    echo "公网ip: ${IP}"
    echo "l2tp网关: ${iprange}.1"
    echo "拨入客户端可用ip范围: ${iprange}.2-${iprange}.254"
    echo "PSK预共享密钥: ${mypsk}"
    echo "###########################"
}

install_l2tp(){

    mknod /dev/random c 1 9
    yum -y install epel-*
    yum -y install ppp libreswan xl2tpd iptables iptables-services
    yum_install

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

}


yum_install(){

    config_install

    cp -pf /etc/sysctl.conf /etc/sysctl.conf.bak

    echo "# Added by L2TP VPN" >> /etc/sysctl.conf
    echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf
    echo "net.ipv4.tcp_syncookies=1" >> /etc/sysctl.conf
    echo "net.ipv4.icmp_echo_ignore_broadcasts=1" >> /etc/sysctl.conf
    echo "net.ipv4.icmp_ignore_bogus_error_responses=1" >> /etc/sysctl.conf

    for each in `ls /proc/sys/net/ipv4/conf/`; do
        echo "net.ipv4.conf.${each}.accept_source_route=0" >> /etc/sysctl.conf
        echo "net.ipv4.conf.${each}.accept_redirects=0" >> /etc/sysctl.conf
        echo "net.ipv4.conf.${each}.send_redirects=0" >> /etc/sysctl.conf
        echo "net.ipv4.conf.${each}.rp_filter=0" >> /etc/sysctl.conf
    done
    sysctl -p

    systemctl enable ipsec
    systemctl enable xl2tpd
    systemctl restart ipsec
    systemctl restart xl2tpd
}

finally(){
    echo "验证安装"
    ipsec verify # ipsec内置命令
    systemctl stop firewalld
    systemctl disable firewalld
    systemctl start iptables
    systemctl enable iptables
    echo "安装完成"
}


l2tp(){
    echo "开始安装"
    rootness
    tunavailable
    disable_selinux
    get_os_info
    preinstall_l2tp
    install_l2tp
    finally
}

if [ -s /etc/selinux/config ] && grep 'SELINUX=enforcing' /etc/selinux/config; then
    sed -i 's/SELINUX=enforcing/SELINUX=disabled/g' /etc/selinux/config
    setenforce 0
fi

if [ ! -e "/usr/bin/wget" ]; then
  yum install -y wget
fi

if [ ! -e "/usr/bin/netstat" ]; then
  yum install -y net-tools
fi

if [ ! -e /usr/bin/mkpasswd ];then
  yum install -y expect
fi

if [ ! -e /usr/bin/expr ];then
  yum install -y coreutils
fi

l2tp

iptables -F
iptables -t nat -F
iptables -P INPUT ACCEPT
#iptables -t nat -A POSTROUTING -j MASQUERADE
ip -4 a | grep inet | grep -v "127.0.0.1" | awk '{print $2,$NF}' | sed "s/\/[0-9]\{1,2\}//g" > system_ip.txt
start_num=2
rm -f ./l2tp.txt
psk=`cat /etc/ipsec.secrets | awk '{print $5}' | sed 's/"//g'`
ip=`cat /etc/ipsec.conf | grep leftid | awk -F "=" '{print $2}'`

# 创建表格标题（使用中文，但添加空格确保对齐）
echo "序号  用户名    密码        预共享密钥    服务器IP         客户端IP         出口公网IP" > ./l2tp.txt
echo "======================================================================================" >> ./l2tp.txt

while read line || [[ -n ${line} ]]
do
    nic_ip=`echo $line | awk '{print $1}'`
    echo "创建第" `expr $start_num - 1` "个"
	
	# 密码手动指定
	l_pass="dd123"
	
    echo "user`expr $start_num - 1`     l2tpd     $l_pass     192.168.18.$start_num" >> /etc/ppp/chap-secrets

    iptables -t nat -A POSTROUTING -s 192.168.18.$start_num -j SNAT --to-source $nic_ip

    public_ip=`curl -s --connect-timeout 10 --interface $nic_ip -A "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/103.0.5060.114 Safari/537.36 Edg/103.0.1264.62" http://whatismyip.akamai.com`
    
    # 格式化输出到表格，使用printf确保对齐
    seq=$((start_num-1))
    printf "%-4s    user%-4s    %-10s    %-12s    %-15s    %-15s    %-15s\n" \
        $seq $seq $l_pass $psk $ip "192.168.18.$start_num" $public_ip >> ./l2tp.txt
        
    start_num=`expr $start_num + 1`

done < system_ip.txt
rm -f system_ip.txt

# Warning - secret file /etc/ppp/chap-secrets has world and/or group access
chmod 600 /etc/ppp/chap-secrets

iptables-save > /etc/sysconfig/iptables
systemctl restart xl2tpd
systemctl restart ipsec

echo -e "\n\033[1;32m账号密码保存在当前目录下 l2tp.txt 中\033[0m"
echo -e "\033[1;33mQQ群：609972590\033[0m\n"

# 输出表格（使用cat保持原样对齐）
cat ./l2tp.txt
