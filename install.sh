#!/bin/bash

#Install base packages for Drupal
yum install -y httpd varnish ssmtp community-mysql php php-cli php-common php-mysql php-gd php-mbstring

#Install Google PageSpeed RPM
yum install -y https://dl-ssl.google.com/dl/linux/direct/mod-pagespeed-stable_current_x86_64.rpm

#Disable SELINUX
setenforce 0
echo "SELINUX=disabled" > /etc/selinux/config
echo "SELINUXTYPE=targeted" >> /etc/selinux/config

#Disable IPv6
echo "net.ipv6.conf.all.disable_ipv6=1" >> /etc/sysctl.conf
echo "net.ipv6.conf.all.accept_redirects=0" >> /etc/sysctl.conf
echo "net.ipv6.conf.all.accept_source_route=0" >> /etc/sysctl.conf
echo "net.ipv6.conf.default.disable_ipv6=1" >> /etc/sysctl.conf
echo "net.ipv6.conf.default.accept_redirects=0" >> /etc/sysctl.conf
echo "net.ipv6.conf.default.accept_source_route=0" >> /etc/sysctl.conf

#Disable startup-stuff
cd /lib/systemd/system
for i in fedora*storage* lvm2-monitor.* mdmonitor*.*; do
  systemctl mask $i
done

for i in livesys livesys-late spice-vdagentd cups smartd firewalld atd; do
  chkconfig $i off
done

for i in abrt*.service auditd.service avahi-daemon.* bluetooth.* dev-hugepages.mount dev-mqueue.mount \
fedora-configure.service fedora-loadmodules.service fedora-readonly.service ip6tables.service \
iptables.service irqbalance.service mcelog.service rsyslog.service sendmail.service sm-client.service \
sys-kernel-config.mount sys-kernel-debug.mount; do
  systemctl mask $i
done

for i in *readahead*; do
  systemctl mask $i
done

#Disable plymouth
yum remove -y 'plymouth*'
dracut -f

#Disable finger printing
authconfig --disablefingerprint --update

#Turn up file descriptors for all users
ulimit -n 999999
echo '* hard nofile 999999' >> /etc/security/limits.conf
echo '* soft nofile 999999' >> /etc/security/limits.conf

#Turn off defragging
echo "never" > /sys/kernel/mm/transparent_hugepage/defrag
echo "never" > /sys/kernel/mm/transparent_hugepage/enabled

#Only allow swapping around 80-90% CPU usage
echo "vm.swappiness=10" >> /etc/sysctl.conf
sysctl -p

#Clean yum
yum history new
yum clean all
rm -f /var/lib/rpm/__db*
