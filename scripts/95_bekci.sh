#!/bin/sh
# =====================================================================
# 95_bekci.sh - Extroot sonrasi OTOMATIK BEKCI (tek seferlik)
# 00_otomatik.sh tarafindan extroot'taki /etc/rc.local'a eklenir.
#  - 12 dk boyunca DHCP, DNS ve interneti kontrol eder
#  - 4. dk: dnsmasq yeniden baslatma, 8. dk: wan yeniden kaldirma
#  - 3 ardisik basarili kontrol = BASARI -> rc.local'i eski haline getirir
#  - Basarisizsa: teshis toplar, extroot'u devre disi birakir, reboot
# Test:  sh 95_bekci.sh --test   (tek kontrol, hicbir sey degistirmez)
# =====================================================================
KIT=/root/extroot-kit
LOG=$KIT/bekci.log
SURE=720; ARALIK=20; GEREKEN=3

kontrol() {
	h=""
	if [ -x /etc/init.d/dnsmasq ] && /etc/init.d/dnsmasq enabled; then pidof dnsmasq >/dev/null || h="$h dnsmasq-yok"; fi
	netstat -lnu 2>/dev/null | grep -q ":67 " || h="$h dhcp67-yok"
	if [ -f $KIT/dhcp-aralik-bekci ]; then sh $KIT/dhcp-aralik-bekci --test | grep -q EKSIK && h="$h dhcp-araligi-eksik"
	elif [ -f "$(dirname "$0")/dhcp-aralik-bekci" ]; then sh "$(dirname "$0")/dhcp-aralik-bekci" --test | grep -q EKSIK && h="$h dhcp-araligi-eksik"; fi
	nslookup openwrt.org 127.0.0.1 >/dev/null 2>&1 || h="$h dns-hata"
	ip -4 route show default | grep -q . || h="$h rota-yok"
	ping -c1 -W3 1.1.1.1 >/dev/null 2>&1 || h="$h internet-yok"
	echo "$h"
}

if [ "$1" = "--test" ]; then
	s=$(kontrol); [ -z "$s" ] && echo "TEST: tum kontroller BASARILI" || echo "TEST: HATALAR:$s"; exit 0
fi

[ "$(awk '$2=="/overlay"{print $1}' /proc/mounts | tail -1)" = "/dev/mmcblk0p11" ] || exit 0

log(){ echo "$(date '+%F %T') $*" >> $LOG; logger -t extroot-bekci "$*"; }
rclocal_geri(){ [ -f $KIT/rc.local.orijinal ] && cp $KIT/rc.local.orijinal /etc/rc.local && log "rc.local orijinal haline getirildi"; }

log "=== Bekci basladi (uptime: $(cut -d' ' -f1 /proc/uptime) sn) ==="
gecen=0; ard=0; o4=0; o8=0
while [ $gecen -lt $SURE ]; do
	s=$(kontrol)
	if [ -z "$s" ]; then ard=$((ard+1)); log "kontrol OK ($ard/$GEREKEN)"
	else ard=0; log "kontrol HATA:$s"; fi
	if [ $ard -ge $GEREKEN ]; then
		log "BASARI: extroot ile tum servisler calisiyor"
		sh $KIT/03_dogrula.sh > $KIT/dogrulama_sonucu.txt 2>&1
		rclocal_geri; log "Bekci bitti. Dogrulama: $KIT/dogrulama_sonucu.txt"
		exit 0
	fi
	if [ $gecen -ge 240 ] && [ $o4 -eq 0 ]; then
		o4=1; log "Onarim 1: dnsmasq yeniden baslatiliyor"; /etc/init.d/dnsmasq restart
	fi
	if [ $gecen -ge 480 ] && [ $o8 -eq 0 ]; then
		o8=1; log "Onarim 2: wan yeniden kaldiriliyor"; ifup wan; sleep 20
	fi
	sleep $ARALIK; gecen=$((gecen+ARALIK))
done

log "BASARISIZ: $SURE sn icinde servisler duzelmedi. Teshis + geri alma."
sh $KIT/04_teshis.sh >> $LOG 2>&1
log "90_geri_al.sh calistiriliyor (extroot devre disi)"
if sh $KIT/90_geri_al.sh >> $LOG 2>&1; then
	rclocal_geri; sync
	log "Yeniden baslatiliyor -> tasima oncesi hal"
	sleep 3; reboot
else
	log "!!! GERI ALMA BASARISIZ - reboot YAPILMADI. Bekci bir sonraki acilista tekrar dener. Elle: README 'Geri donus'"
fi
