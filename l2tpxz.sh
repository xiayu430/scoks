#!/bin/bash
# 卸载L2TP/IPSec VPN服务

# 停止服务
systemctl stop ipsec
systemctl stop xl2tpd
systemctl stop iptables

# 禁用服务
systemctl disable ipsec
systemctl disable xl2tpd

# 移除软件包
yum remove -y libreswan xl2tpd ppp expect

# 清理配置文件
rm -rf /etc/ipsec.*
rm -rf /etc/xl2tpd/
rm -rf /etc/ppp/
rm -f /etc/sysctl.conf.bak

# 恢复原始sysctl配置
if [ -f /etc/sysctl.conf.bak ]; then
    cp -f /etc/sysctl.conf.bak /etc/sysctl.conf
    sysctl -p
fi

# 删除iptables规则
iptables -F
iptables -t nat -F
iptables-save > /etc/sysconfig/iptables

# 删除生成的文件
rm -f ./l2tp.txt
rm -f ./system_ip.txt

# 重启网络服务
systemctl restart network

echo "L2TP/IPSec VPN 已完全卸载"
