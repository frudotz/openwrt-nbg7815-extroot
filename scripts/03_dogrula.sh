#!/bin/sh
# =====================================================================
# 03_dogrula.sh - Extroot sonrasi DOGRULAMA (SALT OKUNUR)
# Kullanim:  sh /root/extroot-kit/03_dogrula.sh
# =====================================================================
KIT=/root/extroot-kit
ok=0; warn=0; fail=0
pass(){ echo "[ OK ] $*"; ok=$((ok+1)); }
uyar(){ echo "[UYAR] $*"; warn=$((warn+1)); }
hata(){ echo "[HATA] $*"; fail=$((fail+1)); }
bilgi(){ echo "       $*"; }

echo "================ EXTROOT DOGRULAMA ================"; date; uptime

echo; echo "== 1. Depolama =="
src=$(awk '$2=="/overlay"{print $1}' /proc/mounts | tail -1)
[ "$src" = "/dev/mmcblk0p11" ] && pass "/overlay = $src (extroot AKTIF)" || hata "/overlay = $src (extroot aktif DEGIL)"
kb=$(df -k /overlay | tail -1 | awk '{print $2}')
[ "$kb" -gt 1000000 ] && pass "Overlay boyutu: $((kb/1024)) MB" || hata "Overlay boyutu kucuk: $((kb/1024)) MB"
c=$(dmesg | grep -ciE "EXT4-fs error"); [ "$c" -eq 0 ] && pass "ext4 hatasi yok" || hata "$c ext4 hatasi (dmesg)"

echo; echo "== 2. Kopya butunlugu =="
n=$(ls /etc/uci-defaults 2>/dev/null | wc -l)
[ "$n" -eq 0 ] && pass "/etc/uci-defaults bos (ilk acilis betikleri tekrar calismadi)" || hata "/etc/uci-defaults'ta $n betik var: $(ls /etc/uci-defaults | tr '\n' ' ')"
if [ -f $KIT/oncesi/config_md5.txt ]; then
	fark=$(md5sum -c $KIT/oncesi/config_md5.txt 2>/dev/null | grep -v ': OK$')
	if [ -z "$fark" ]; then pass "/etc/config dosyalari tasimadan oncekiyle ayni"
	else uyar "Degisen config dosyalari (servislerin yazmasi normal olabilir):"; echo "$fark" | sed 's/^/       /'; fi
fi

echo; echo "== 3. DHCP / DNS / internet =="
if [ -x /etc/init.d/dnsmasq ] && /etc/init.d/dnsmasq enabled; then
	pidof dnsmasq >/dev/null && pass "dnsmasq calisiyor" || hata "dnsmasq CALISMIYOR"
fi
netstat -lnu 2>/dev/null | grep -q ":67 " && pass "DHCP udp/67 dinleniyor" || hata "DHCP udp/67 dinlenmiyor"
if [ -f $KIT/dhcp-aralik-bekci ]; then
	r=$(sh $KIT/dhcp-aralik-bekci --test); echo "$r" | sed 's/^/       /'
	echo "$r" | grep -q "EKSIK" && hata "Bazi aglarin DHCP araligi eksik -> /etc/init.d/dnsmasq restart" || pass "Tum DHCP araliklari yuklu"
fi
nslookup openwrt.org 127.0.0.1 >/dev/null 2>&1 && pass "DNS cozumleme calisiyor" || hata "DNS cozumleme CALISMIYOR"
ip -4 route show default | grep -q . && pass "Varsayilan rota var" || hata "Varsayilan rota yok"
ping -c2 -W3 1.1.1.1 >/dev/null 2>&1 && pass "Router internete ulasiyor" || hata "Router internete ulasamiyor"
for i in $(ubus list 'network.interface.*' | sed 's/network.interface.//' | grep -v loopback); do
	bilgi "arayuz $i: up=$(ifstatus $i 2>/dev/null | jsonfilter -e '@.up')"
done
bilgi "Aktif lease: $(wc -l < /tmp/dhcp.leases 2>/dev/null)"

echo; echo "== 4. Donanim =="
c=$(lsmod | grep -c qca_nss); [ "$c" -gt 0 ] && pass "NSS modulleri yuklu ($c)" || bilgi "NSS modulu yok (NSS'siz yapi olabilir)"
[ "$(date +%Y)" -ge 2025 ] && pass "Saat: $(date)" || hata "Saat yanlis: $(date)"

echo; echo "==================================================="
echo "SONUC: $ok OK, $warn UYARI, $fail HATA"
[ "$fail" -gt 0 ] && echo "HATA var -> once:  sh $KIT/04_teshis.sh   sonra README 'Sorun giderme' bolumu."
