#!/bin/sh
# =====================================================================
# 04_teshis.sh - Sorun aninda teshis bilgisini toplar (SALT OKUNUR).
# Extroot aktifse /root altina (kalici), degilse /tmp altina yazar.
# ONEMLI: Geri alma / reboot ONCESI calistirin; loglar RAM'dedir.
# Sifreler/anahtarlar maskelenir; yine de paylasmadan once kontrol edin.
# =====================================================================
T=$(date +%Y%m%d-%H%M%S)
kb=$(df -k /overlay | tail -1 | awk '{print $4}')
if [ "${kb:-0}" -gt 51200 ]; then D=/root/teshis-$T; else D=/tmp/teshis-$T; fi
mkdir -p "$D" || exit 1
c(){ f="$1"; shift; { echo "### $*"; sh -c "$*" 2>&1; echo; } >> "$D/$f.txt"; }
M="sed -E \"s/(password|key|private_key|preshared_key|secret|token)='[^']*'/\\1='***'/\""

c genel    "date; uptime; cat /proc/cmdline; cat /etc/openwrt_release"
c depolama "df -h; cat /proc/mounts; block info; losetup -a; cat /proc/partitions; uci show fstab"
c log      "logread"
c dmesg    "dmesg"
c servis   "ps w; netstat -lnup; netstat -lntp"
c ag       "ip -4 addr; ip -6 addr; ip -4 route show table all; ip -4 rule"
c ag       "for i in \$(ubus list 'network.interface.*' | sed 's/network.interface.//'); do echo == \$i; ifstatus \$i; done"
c dhcpdns  "uci show dhcp | $M; cat /tmp/dhcp.leases; for f in /var/etc/dnsmasq.conf.*; do echo == \$f; cat \$f; done; cat /tmp/resolv.conf.d/resolv.conf.auto 2>/dev/null"
c dhcpdns  "nslookup openwrt.org 127.0.0.1"
c firewall "uci show firewall; nft list ruleset 2>&1 | head -600"
c network  "uci show network | $M; uci show wireless | grep -vE 'key='"
c paketler "apk list -I 2>/dev/null || opkg list-installed"
c ping     "ping -c3 -W3 1.1.1.1"
c uci_defaults "ls -la /etc/uci-defaults/"

tar -C "$(dirname "$D")" -czf "$D.tar.gz" "$(basename "$D")" 2>/dev/null
echo "Teshis raporu: $D/  ve  $D.tar.gz"
