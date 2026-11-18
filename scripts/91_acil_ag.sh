#!/bin/sh
# =====================================================================
# 91_acil_ag.sh - Acil ag mudahaleleri (DHCP/DNS/internet sorunlarinda)
# Kullanim: sh 91_acil_ag.sh <komut>
#   durum            Ozet durum (salt okunur)
#   dnsmasq          dnsmasq'i yeniden baslat (DHCP+DNS) - IP alinamiyorsa ILK cozum
#   dns-yedek-ac     dnsmasq'a 1.1.1.1 ve 9.9.9.9 yedek DNS ekler (KALICI)
#   dns-yedek-kapat  Yukaridakini geri alir
#   wan              wan arayuzunu yeniden kaldir
#   firewall         firewall'u yeniden yukle
# =====================================================================
durum(){
	echo "dnsmasq: $(pidof dnsmasq >/dev/null && echo calisiyor || echo YOK) | DHCP udp/67: $(netstat -lnu | grep -q ':67 ' && echo dinleniyor || echo YOK)"
	for i in $(ubus list 'network.interface.*' | sed 's/network.interface.//' | grep -v loopback); do printf "%s=%s " $i "$(ifstatus $i 2>/dev/null | jsonfilter -e '@.up')"; done; echo
	echo "DNS: $(nslookup openwrt.org 127.0.0.1 >/dev/null 2>&1 && echo OK || echo HATA) | Ping 1.1.1.1: $(ping -c1 -W3 1.1.1.1 >/dev/null 2>&1 && echo OK || echo HATA)"
	[ -x /usr/sbin/dhcp-aralik-bekci ] && /usr/sbin/dhcp-aralik-bekci --test
	echo "Lease: $(wc -l < /tmp/dhcp.leases)"
}
case "$1" in
	durum|"") durum ;;
	dnsmasq) /etc/init.d/dnsmasq restart; sleep 3; durum ;;
	dns-yedek-ac)
		uci -q del_list dhcp.@dnsmasq[0].server='1.1.1.1'; uci -q del_list dhcp.@dnsmasq[0].server='9.9.9.9'
		uci add_list dhcp.@dnsmasq[0].server='1.1.1.1'; uci add_list dhcp.@dnsmasq[0].server='9.9.9.9'
		uci commit dhcp; /etc/init.d/dnsmasq restart; sleep 2; durum
		echo "Sorun cozulunce: sh $0 dns-yedek-kapat" ;;
	dns-yedek-kapat)
		uci -q del_list dhcp.@dnsmasq[0].server='1.1.1.1'; uci -q del_list dhcp.@dnsmasq[0].server='9.9.9.9'
		uci commit dhcp; /etc/init.d/dnsmasq restart; sleep 2; durum ;;
	wan) ifup wan; sleep 15; durum ;;
	firewall) /etc/init.d/firewall reload; durum ;;
	*) sed -n '2,11p' "$0"; exit 2 ;;
esac
