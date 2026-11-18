#!/bin/sh
# =====================================================================
# 02_extroot_kur.sh - Overlay'i appdata (mmcblk0p11) partition'ina tasir.
#
# VARSAYILAN MOD: KURU CALISMA (hicbir sey degistirmez, sadece ne
# yapacagini gosterir). Gercek islem icin:  sh 02_extroot_kur.sh --uygula
#
# Secenekler:
#   --uygula            Islemi gercekten yap
#   --zorla-bicimle     p11 uzerinde dosya sistemi olsa bile bicimle (VERI SILINIR)
#   --check-fs-kapali   Acilista extroot fsck (check_fs=1) ayarini YAPMA
#
# Yeniden baslatma YAPMAZ. Is bitince talimatlari yazar.
# =====================================================================
EXT=/dev/mmcblk0p11
MNT=/mnt/extroot
KITDIR=$(cd "$(dirname "$0")" && pwd)
MODE=kuru; ZORLA=0; CHECKFS=1
for a in "$@"; do
	case "$a" in
		--uygula) MODE=uygula ;;
		--zorla-bicimle) ZORLA=1 ;;
		--check-fs-kapali) CHECKFS=0 ;;
		-h|--help) sed -n '2,16p' "$0"; exit 0 ;;
		*) echo "Bilinmeyen secenek: $a"; exit 2 ;;
	esac
done

die(){ echo; echo "[DUR] $*"; echo "Islem durduruldu. Yapilan degisiklikler icin README 'Yarim kalan kurulum' bolumune bakin."; exit 1; }
adim(){ echo; echo "=== $* ==="; }
run(){ echo "+ $*"; [ "$MODE" = uygula ] || return 0; "$@" || die "Komut basarisiz: $*"; }

echo "Mod: $MODE"
[ "$MODE" = kuru ] && echo "(KURU CALISMA - hicbir sey degistirilmeyecek)"

adim "A. Guvenlik kontrolleri"
[ "$(cat /tmp/sysinfo/board_name 2>/dev/null)" = "zyxel,nbg7815" ] || die "Bu betik sadece zyxel,nbg7815 icindir"
[ "$(id -u)" = 0 ] || die "root olarak calistirin"
[ -b "$EXT" ] || die "$EXT yok"
[ "$(grep PARTNAME /sys/class/block/mmcblk0p11/uevent | cut -d= -f2)" = "appdata" ] || die "$EXT appdata degil"
src=$(awk '$2=="/overlay"{print $1}' /proc/mounts | tail -1)
case "$src" in /dev/loop*) echo "Dahili overlay aktif: $src" ;; *) die "/overlay kaynagi beklenmedik ($src). Extroot zaten aktif olabilir." ;; esac
grep -q "^$EXT " /proc/mounts && die "$EXT su an mount edilmis"
for t in mkfs.ext4 e2fsck block tar md5sum uci; do command -v $t >/dev/null || die "$t yok"; done
fs=$(block info "$EXT" 2>/dev/null | sed -n 's/.*TYPE="\([^"]*\)".*/\1/p')
if [ -n "$fs" ] && [ "$ZORLA" -ne 1 ]; then
	die "$EXT uzerinde '$fs' dosya sistemi var. Icindeki veriyi kaybetmeyi kabul ediyorsaniz --zorla-bicimle ekleyin."
fi
for s in $(uci -q show fstab | sed -n "s/^fstab\.\([^.]*\)\.target='\/overlay'$/\1/p; s/^fstab\.\([^.]*\)\.target='\/'$/\1/p"); do
	[ "$s" = "extroot" ] && continue
	e=$(uci -q get fstab.$s.enabled)
	[ "$e" = "0" ] || die "fstab'da baska ETKIN bir /overlay veya / kaydi var: fstab.$s (once onu enabled=0 yapin)"
done
free_kb=$(df -k /overlay | tail -1 | awk '{print $4}')
echo "Dahili overlay bos alan (df): ${free_kb} KB (df 0 gosterse de root ext4 rezervini kullanabilir)"
if [ "$MODE" = uygula ]; then
	# fstab yazabilmek icin gercek yazma testi (64 KB, hemen silinir)
	if dd if=/dev/zero of=/etc/.extroot_yazma_testi bs=4k count=16 2>/dev/null && sync; then
		rm -f /etc/.extroot_yazma_testi; echo "Yazma testi (64 KB) OK"
	else
		rm -f /etc/.extroot_yazma_testi; die "Dahili overlay'e yazilamiyor (dolu). Once yer acin."
	fi
fi
echo "Kontroller tamam."

adim "B. Bicimlendirme (lazy init KAPALI - acilista arka plan disk yuku olmaz)"
run mkfs.ext4 -F -L extroot -m 1 -E lazy_itable_init=0,lazy_journal_init=0 "$EXT"
if [ "$MODE" = uygula ]; then
	UUID=$(block info "$EXT" | sed -n 's/.*UUID="\([^"]*\)".*/\1/p')
	[ -n "$UUID" ] || die "UUID okunamadi"
else
	UUID="<mkfs-sonrasi-uuid>"
fi
echo "UUID: $UUID"

adim "C. Dahili fstab'a extroot kaydi (karar bu dosyaya gore verilir)"
echo "+ uci -q delete fstab.extroot   (varsa eski kayit)"
if [ "$MODE" = uygula ]; then uci -q delete fstab.extroot; fi
run uci set fstab.extroot=mount
run uci set fstab.extroot.target=/overlay
run uci set fstab.extroot.uuid="$UUID"
run uci set fstab.extroot.options=noatime
run uci set fstab.extroot.enabled=1
[ "$CHECKFS" -eq 1 ] && run uci set fstab.@global[0].check_fs=1
run uci commit fstab
[ "$MODE" = uygula ] && uci show fstab.extroot

adim "D. Mevcut ayarlarin parmak izi (dogrulama icin)"
# Baglama noktasi parmak izinden ONCE olusturulur (yoksa overlay'e sonradan eklenen
# /mnt/extroot dizini dogrulamada fark olarak gorunur)
run mkdir -p $MNT
SNAP=/tmp/extroot_oncesi
run rm -rf $SNAP
run mkdir -p $SNAP
if [ "$MODE" = uygula ]; then
	(cd /overlay/upper && find . | sort > $SNAP/liste.txt)
	(cd /overlay/upper && find . -type f | sort | while IFS= read -r f; do md5sum "$f"; done > $SNAP/md5.txt)
	(cd /overlay/upper && find . -type l | sort | while IFS= read -r f; do echo "$f -> $(readlink "$f")"; done > $SNAP/symlink.txt)
	(cd /overlay/upper && find . -type c | sort > $SNAP/whiteout.txt)
	md5sum /etc/config/* > $SNAP/config_md5.txt 2>/dev/null
	echo "girdi=$(wc -l < $SNAP/liste.txt) dosya=$(wc -l < $SNAP/md5.txt) symlink=$(wc -l < $SNAP/symlink.txt) whiteout=$(wc -l < $SNAP/whiteout.txt)"
fi

adim "E. Kopyalama (sadece upper; work bos olusturulur)"
run mkdir -p $MNT
run mount -t ext4 -o noatime "$EXT" $MNT
run sync
echo "+ tar -C /overlay -cf - upper | tar -C $MNT -xf -"
if [ "$MODE" = uygula ]; then
	tar -C /overlay -cf - upper | tar -C $MNT -xf - || die "tar basarisiz"
fi
run mkdir -p $MNT/work
run sync

adim "F. Kopya dogrulama"
if [ "$MODE" = uygula ]; then
	(cd $MNT/upper && find . | sort > /tmp/extroot_sonrasi_liste.txt)
	(cd $MNT/upper && find . -type f | sort | while IFS= read -r f; do md5sum "$f"; done > /tmp/extroot_sonrasi_md5.txt)
	(cd $MNT/upper && find . -type l | sort | while IFS= read -r f; do echo "$f -> $(readlink "$f")"; done > /tmp/extroot_sonrasi_symlink.txt)
	(cd $MNT/upper && find . -type c | sort > /tmp/extroot_sonrasi_whiteout.txt)
	sorun=0
	for k in liste md5 symlink whiteout; do
		if cmp -s $SNAP/$k.txt /tmp/extroot_sonrasi_$k.txt; then echo "[ OK ] $k ayni ($(wc -l < $SNAP/$k.txt) satir)"
		else echo "[HATA] $k FARKLI:"
			echo "  sadece kaynakta:"; awk 'NR==FNR{b[$0]=1;next} !($0 in b)' /tmp/extroot_sonrasi_$k.txt $SNAP/$k.txt | head -20
			echo "  sadece kopyada:";  awk 'NR==FNR{a[$0]=1;next} !($0 in a)' $SNAP/$k.txt /tmp/extroot_sonrasi_$k.txt | head -20
			sorun=1; fi
	done
	g=$(uci -c $MNT/upper/etc/config -q get fstab.extroot.uuid)
	[ "$g" = "$UUID" ] && echo "[ OK ] Kopyadaki fstab extroot kaydini iceriyor" || { echo "[HATA] Kopyadaki fstab extroot kaydi yok/yanlis ($g)"; sorun=1; }
	if [ "$sorun" -ne 0 ]; then
		umount $MNT
		echo "Dogrulama BASARISIZ. Dahili fstab'daki kaydi geri aliyorum..."
		uci -q delete fstab.extroot; uci commit fstab
		die "Kopya dogrulanamadi. Cihaz hala dahili overlay ile acilir; yeniden baslatmak guvenli."
	fi
fi

adim "G. Kurtarma kitini extroot'a kopyala (/root/extroot-kit)"
run mkdir -p $MNT/upper/root/extroot-kit
for f in "$KITDIR"/*.sh "$KITDIR"/dhcp-aralik-bekci; do [ -f "$f" ] || continue; run cp "$f" $MNT/upper/root/extroot-kit/; done
[ "$MODE" = uygula ] && cp -r $SNAP $MNT/upper/root/extroot-kit/oncesi

adim "H. Bitis"
run sync
run umount $MNT
echo
if [ "$MODE" = uygula ]; then
cat <<EOF
TASIMA HAZIR. Simdi:
  1) Bu ana kadar AYAR DEGISTIRMEYIN (kopyadan sonraki degisiklikler kaybolur).
  2) reboot
  3) Acilinca (2-3 dk bekleyin):  sh /root/extroot-kit/03_dogrula.sh
  Geri almak icin (her durumda): sh /root/extroot-kit/90_geri_al.sh --yeniden-baslat
  Sorun varsa ONCE teshis:        sh /root/extroot-kit/04_teshis.sh
EOF
else
	echo "KURU CALISMA bitti. Gercek islem icin: sh $0 --uygula"
fi
