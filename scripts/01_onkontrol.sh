#!/bin/sh
# =====================================================================
# 01_onkontrol.sh - NBG7815 extroot ON KONTROL (TAMAMEN SALT OKUNUR)
# Hicbir ayari/dosyayi degistirmez.
# Kullanim:  sh 01_onkontrol.sh
# =====================================================================
EXT=/dev/mmcblk0p11
ROOTPART=/dev/mmcblk0p4
D=$(cd "$(dirname "$0")" && pwd)
ok=0; warn=0; fail=0
pass(){ echo "[ OK ] $*"; ok=$((ok+1)); }
uyar(){ echo "[UYAR] $*"; warn=$((warn+1)); }
hata(){ echo "[HATA] $*"; fail=$((fail+1)); }
bilgi(){ echo "       $*"; }

echo "================ NBG7815 EXTROOT ON KONTROL ================"
date

echo; echo "== 1. Cihaz =="
b=$(cat /tmp/sysinfo/board_name 2>/dev/null)
[ "$b" = "zyxel,nbg7815" ] && pass "Cihaz: $b" || hata "Beklenmeyen cihaz: '$b' (bu rehber sadece Zyxel NBG7815 icindir)"
. /etc/openwrt_release 2>/dev/null; bilgi "Surum: $DISTRIB_DESCRIPTION"

echo; echo "== 2. Hedef partition ($EXT) =="
if [ ! -b "$EXT" ]; then
	hata "$EXT bulunamadi"
else
	name=$(grep PARTNAME /sys/class/block/mmcblk0p11/uevent | cut -d= -f2)
	[ "$name" = "appdata" ] && pass "PARTNAME=appdata" || hata "PARTNAME beklenmedik: '$name'"
	sz=$(( $(cat /sys/class/block/mmcblk0p11/size) / 2048 ))
	[ "$sz" -gt 2000 ] && pass "Boyut: ${sz} MB" || hata "Boyut beklenenden kucuk: ${sz} MB"
	if grep -q "^$EXT " /proc/mounts; then hata "$EXT su an mount edilmis: $(grep "^$EXT " /proc/mounts)"; else pass "$EXT mount edilmemis"; fi
	fs=$(block info "$EXT" 2>/dev/null | sed -n 's/.*TYPE="\([^"]*\)".*/\1/p')
	if [ -z "$fs" ]; then pass "$EXT uzerinde dosya sistemi yok"
	else uyar "$EXT uzerinde '$fs' var: $(block info "$EXT") (icerik silinecek)"; fi
fi

echo; echo "== 3. Partition sinirlari (cakisma kontrolu) =="
prev_end=-1; cak=0
for d in $(for x in /sys/class/block/mmcblk0p*; do echo "$(cat $x/start) $(basename $x)"; done | sort -n | awk '{print $2}'); do
	s=$(cat /sys/class/block/$d/start); z=$(cat /sys/class/block/$d/size); e=$((s+z-1))
	[ "$s" -le "$prev_end" ] && { hata "CAKISMA: $d"; cak=1; }
	prev_end=$e
done
[ "$cak" -eq 0 ] && pass "Partition'lar arasinda cakisma yok"

echo; echo "== 4. Mevcut overlay =="
src=$(awk '$2=="/overlay"{print $1}' /proc/mounts | tail -1)
case "$src" in
	/dev/loop*) pass "Dahili overlay aktif ($src) - extroot yok";;
	/dev/mmcblk0p11) uyar "Extroot ZATEN aktif ($src)";;
	*) uyar "Beklenmeyen /overlay kaynagi: '$src'";;
esac
df -h /overlay | tail -1 | sed 's/^/       /'
bilgi "upper: $(find /overlay/upper | wc -l) girdi, $(find /overlay/upper -type c | wc -l) whiteout, $(find /overlay/upper -type l | wc -l) symlink, $(du -sk /overlay/upper | cut -f1) KB"
set -- $(hexdump -s 40 -n 8 -e '2/4 "%u "' $ROOTPART)
BU=$(($1 + $2*4294967296)); OFF=$(( (BU + 65535) / 65536 * 65536 ))
bilgi "Dahili overlay offset (hesaplanan): $OFF ; losetup: $(losetup -a | grep mmcblk0p4 | sed -n 's/.*offset \([0-9]*\).*/\1/p')"

echo; echo "== 5. fstab =="
n_en=0
for s in $(uci -q show fstab | sed -n "s/^fstab\.\([^.]*\)\.target='\/overlay'$/\1/p; s/^fstab\.\([^.]*\)\.target='\/'$/\1/p"); do
	e=$(uci -q get fstab.$s.enabled); [ "$e" = "0" ] || { n_en=$((n_en+1)); bilgi "etkin: fstab.$s"; }
done
[ "$n_en" -eq 0 ] && pass "Etkin extroot kaydi yok" || uyar "$n_en adet ETKIN /overlay veya / kaydi var"

echo; echo "== 6. Servisler ve ag =="
if [ -x /etc/init.d/dnsmasq ] && /etc/init.d/dnsmasq enabled; then
	pidof dnsmasq >/dev/null && pass "dnsmasq calisiyor" || hata "dnsmasq etkin ama calismiyor"
fi
netstat -lnu 2>/dev/null | grep -q ":67 " && pass "DHCP (udp/67) dinleniyor" || hata "DHCP (udp/67) dinlenmiyor"
nslookup openwrt.org 127.0.0.1 >/dev/null 2>&1 && pass "DNS (127.0.0.1) cozumluyor" || hata "DNS (127.0.0.1) cozumlemiyor"
ip -4 route show default | grep -q . && pass "Varsayilan rota var" || uyar "Varsayilan rota yok"
ping -c1 -W3 1.1.1.1 >/dev/null 2>&1 && pass "Router internete ulasiyor" || uyar "Router 1.1.1.1'e ulasamiyor"
for i in $(ubus list 'network.interface.*' | sed 's/network.interface.//' | grep -v loopback); do
	u=$(ifstatus $i 2>/dev/null | jsonfilter -e '@.up'); bilgi "arayuz $i: up=$u"
done
if [ -x "$D/dhcp-aralik-bekci" ] || [ -f "$D/dhcp-aralik-bekci" ]; then
	sh "$D/dhcp-aralik-bekci" --test | sed 's/^/       /'
fi
[ "$(date +%Y)" -ge 2025 ] && pass "Saat makul: $(date)" || uyar "Saat yanlis olabilir: $(date)"

echo; echo "== 7. Araclar (failsafe icin ROM'da olmali) =="
for t in losetup hexdump e2fsck mkfs.ext4 uci block md5sum tar; do
	p=$(command -v $t)
	if [ -z "$p" ]; then hata "$t yok (gerekli paket: $( [ $t = mkfs.ext4 ] || [ $t = e2fsck ] && echo e2fsprogs || echo ?))"
	elif [ -e "/rom$p" ]; then pass "$t ($p, ROM)"
	else uyar "$t ($p) ROM'da degil - failsafe'te olmayabilir"; fi
done

echo; echo "============================================================"
echo "SONUC: $ok OK, $warn UYARI, $fail HATA"
[ "$fail" -eq 0 ] && echo "Hata yok." || echo "HATA var - devam etmeden once inceleyin."
