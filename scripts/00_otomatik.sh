#!/bin/sh
# =====================================================================
# 00_otomatik.sh - Tasimanin TAMAMINI tek seferde, gozetimsiz yapar
#   1) On kontrol (HATA varsa hicbir sey degistirmeden durur)
#   2) Bekci testi (saglikli sistemde gecmeli; gecmezse durur)
#   3) 02_extroot_kur.sh --uygula (kopya dogrulanmazsa kendini geri alir)
#   4) Extroot'a: tek seferlik acilis bekcisi (rc.local) + kalici
#      dhcp-aralik-bekci (cron) kurar
#   5) Yeniden baslatir
#
# Kullanim (SSH oturumu kapansa da devam eder):
#   setsid sh ./00_otomatik.sh </dev/null >/dev/null 2>&1 &
#   tail -f /tmp/otomatik.log
# Secenek: --dhcp-bekci-yok   (kalici dhcp-aralik-bekci kurulmasin)
# =====================================================================
K=$(cd "$(dirname "$0")" && pwd)
LOG=/tmp/otomatik.log
EXT=/dev/mmcblk0p11; MNT=/mnt/extroot
DHCPB=1; [ "$1" = "--dhcp-bekci-yok" ] && DHCPB=0
exec >> $LOG 2>&1
log(){ echo "$(date '+%F %T') ## $*"; }
dur(){ log "DURDU: $*"; log "Cihaz bugunku haliyle calismaya devam ediyor (reboot yok)."; exit 1; }
geri(){ uci -q get fstab.extroot >/dev/null && { uci -q delete fstab.extroot; uci commit fstab; log "Guvenlik: dahili fstab'daki extroot kaydi silindi"; }; }

log "=== OTOMATIK TASIMA BASLADI ==="
sleep 5

log "1) On kontrol"
sh $K/01_onkontrol.sh > /tmp/otomatik_onkontrol.txt 2>&1
cat /tmp/otomatik_onkontrol.txt
grep -q "SONUC: .* 0 HATA" /tmp/otomatik_onkontrol.txt || dur "On kontrolde HATA var"

log "2) Bekci testi (saglikli sistemde basarili olmali)"
t=$(sh $K/95_bekci.sh --test); echo "$t"
case "$t" in *BASARILI*) ;; *) dur "Kontroller su anki sistemde bile basarisiz: $t" ;; esac

log "3) Tasima"
EK=""
if block info $EXT | grep -q 'LABEL="extroot"'; then EK="--zorla-bicimle"; log "p11'de onceki denemeden kalan extroot var, yeniden bicimlenecek"; fi
sh $K/02_extroot_kur.sh --uygula $EK || { geri; dur "02_extroot_kur.sh basarisiz"; }

log "4) Bekci kurulumu (extroot)"
mkdir -p $MNT && mount -t ext4 -o noatime $EXT $MNT || { geri; dur "p11 tekrar baglanamadi"; }
KD=$MNT/upper/root/extroot-kit
for f in 95_bekci.sh 90_geri_al.sh 04_teshis.sh 03_dogrula.sh dhcp-aralik-bekci; do
	[ -f $KD/$f ] || { umount $MNT; geri; dur "Kit extroot'ta eksik ($f); extroot kaydi geri alindi"; }
done
cp /etc/rc.local $KD/rc.local.orijinal
mkdir -p $MNT/upper/etc
awk 'BEGIN{d=0} /^exit 0/ && !d {print "sh /root/extroot-kit/95_bekci.sh >/dev/null 2>&1 &"; d=1} {print} END{if(!d) print "sh /root/extroot-kit/95_bekci.sh >/dev/null 2>&1 &"}' /etc/rc.local > $MNT/upper/etc/rc.local
grep -q "95_bekci.sh" $MNT/upper/etc/rc.local || { umount $MNT; geri; dur "rc.local yazilamadi; extroot kaydi geri alindi"; }
if [ $DHCPB -eq 1 ]; then
	mkdir -p $MNT/upper/usr/sbin $MNT/upper/etc/crontabs
	cp $KD/dhcp-aralik-bekci $MNT/upper/usr/sbin/dhcp-aralik-bekci && chmod 755 $MNT/upper/usr/sbin/dhcp-aralik-bekci
	{ [ -f /etc/crontabs/root ] && grep -v "dhcp-aralik-bekci" /etc/crontabs/root; echo "* * * * * /usr/sbin/dhcp-aralik-bekci"; } > $MNT/upper/etc/crontabs/root
	log "dhcp-aralik-bekci extroot'a kuruldu (cron her dakika)"
fi

log "5) Yeniden baslatma"
cp $LOG $KD/otomatik.log 2>/dev/null; cp /tmp/otomatik_onkontrol.txt $KD/ 2>/dev/null
sync; umount $MNT; sync
log "REBOOT (10 sn)"
sleep 10
reboot
