#!/bin/sh
# =====================================================================
# 90_geri_al.sh - EXTROOT'U DEVRE DISI BIRAKIR (GERI DONUS)
#
# Calisma prensibi: Acilista extroot karari DAHILI overlay'deki
# (mmcblk0p4 icindeki loop) /etc/config/fstab'a gore verilir. Bu betik
# o dosyadaki extroot kaydini enabled=0 yapar. Bir sonraki acilista cihaz
# tasima ONCESI haline (dahili overlay) doner. Extroot verisi SILINMEZ;
# istenirse tekrar etkinlestirilebilir.
#
# Normal modda, extroot aktifken ve FAILSAFE modunda calisir.
# (Failsafe'te 'mount_root' CALISTIRMAYIN - extroot'u baglar!)
#
# Kullanim:
#   sh 90_geri_al.sh --kuru            # salt okunur: ne degisecegini gosterir
#   sh 90_geri_al.sh                   # devre disi birak
#   sh 90_geri_al.sh --yeniden-baslat  # devre disi birak + reboot
#   sh 90_geri_al.sh --etkinlestir     # (ters islem) extroot'u tekrar ac
# =====================================================================
ROOTPART=/dev/mmcblk0p4
KURU=0; REBOOT=0; HEDEF=0
for a in "$@"; do
	case "$a" in
		--kuru) KURU=1 ;;
		--yeniden-baslat) REBOOT=1 ;;
		--etkinlestir) HEDEF=1 ;;
		-h|--help) sed -n '2,22p' "$0"; exit 0 ;;
		*) echo "Bilinmeyen secenek: $a"; exit 2 ;;
	esac
done
die(){ echo "[DUR] $*"; exit 1; }

# Dahili overlay offset'ini squashfs superblock'undan hesapla (fstools ile ayni yontem)
magic=$(hexdump -n 4 -e '4/1 "%c"' $ROOTPART)
[ "$magic" = "hsqs" ] || die "$ROOTPART squashfs degil (magic=$magic)"
set -- $(hexdump -s 40 -n 8 -e '2/4 "%u "' $ROOTPART)
BU=$(($1 + $2*4294967296)); OFF=$(( (BU + 65535) / 65536 * 65536 ))
echo "Dahili overlay offset: $OFF"

CLEANUP=""; CFG=""
# Dahili overlay zaten bagli mi? (extroot aktif DEGILSE /overlay loop'tur)
LIVE=$(losetup -a 2>/dev/null | grep "mmcblk0p4" | grep "offset $OFF" | cut -d: -f1 | head -1)
if [ -n "$LIVE" ] && grep -q "^$LIVE " /proc/mounts; then
	MP=$(awk -v d="$LIVE" '$1==d{print $2; exit}' /proc/mounts)
	echo "Dahili overlay zaten bagli ve aktif: $LIVE -> $MP (extroot su an aktif degil)"
	[ "$KURU" -eq 1 ] || grep "^$LIVE " /proc/mounts | grep -q " rw" || die "Dahili overlay salt okunur bagli"
	# Canli overlay'in upper dizinine dogrudan yazmak overlayfs'te tanimsizdir; normal yol kullanilir.
	CFG=/etc/config
else
	if [ "$KURU" -eq 1 ]; then
		L=$(losetup -f) && losetup -r -o $OFF "$L" $ROOTPART || die "loop kurulamadi"
		MOPT="ro,noload"
	else
		L=$(losetup -f) && losetup -o $OFF "$L" $ROOTPART || die "loop kurulamadi"
		MOPT="rw,noatime"
	fi
	MP=/tmp/dahili_overlay; mkdir -p $MP
	if ! mount -t ext4 -o $MOPT "$L" $MP 2>/dev/null; then
		if [ "$KURU" -eq 0 ]; then
			echo "Mount basarisiz, e2fsck -p deneniyor..."; e2fsck -p "$L"
			mount -t ext4 -o $MOPT "$L" $MP || { losetup -d "$L"; die "Dahili overlay baglanamadi"; }
		else
			losetup -d "$L"; die "Dahili overlay (salt okunur) baglanamadi"
		fi
	fi
	echo "Dahili overlay baglandi: $L -> $MP ($MOPT)"
	CLEANUP="$L"
fi

[ -n "$CFG" ] || CFG=$MP/upper/etc/config
[ -f $CFG/fstab ] || die "$CFG/fstab bulunamadi"
echo "--- ONCE (dahili fstab):"
uci -c $CFG -q show fstab | grep -E "\.(target|uuid|device|enabled)="

degisti=0
for s in $(uci -c $CFG -q show fstab | sed -n "s/^fstab\.\([^.]*\)\.target='\/overlay'$/\1/p; s/^fstab\.\([^.]*\)\.target='\/'$/\1/p"); do
	e=$(uci -c $CFG -q get fstab.$s.enabled); [ -z "$e" ] && e=1
	u=$(uci -c $CFG -q get fstab.$s.uuid); dv=$(uci -c $CFG -q get fstab.$s.device)
	# Dahili overlay'in kendi kaydina (loop UUID) dokunma
	case "$dv" in *loop*) continue ;; esac
	if [ -n "$u" ] && block info 2>/dev/null | grep "UUID=\"$u\"" | grep -q "/dev/loop"; then continue; fi
	if [ "$HEDEF" -eq 0 ] && [ "$e" != "0" ]; then
		echo ">> fstab.$s (uuid=$u device=$dv) : enabled $e -> 0"
		[ "$KURU" -eq 1 ] || uci -c $CFG set fstab.$s.enabled=0; degisti=1
	elif [ "$HEDEF" -eq 1 ] && [ "$s" = "extroot" ] && [ "$e" = "0" ]; then
		echo ">> fstab.$s : enabled 0 -> 1"
		[ "$KURU" -eq 1 ] || uci -c $CFG set fstab.$s.enabled=1; degisti=1
	fi
done

if [ "$degisti" -eq 0 ]; then echo "Degistirilecek kayit yok."
elif [ "$KURU" -eq 1 ]; then echo "(KURU: hicbir sey yazilmadi)"
else uci -c $CFG commit fstab && sync && echo "--- SONRA:" && uci -c $CFG -q show fstab | grep -E "\.(target|uuid|enabled)="
fi

if [ -n "$CLEANUP" ]; then sync; umount $MP; losetup -d "$CLEANUP"; rmdir $MP 2>/dev/null; fi

if [ "$KURU" -eq 0 ] && [ "$degisti" -eq 1 ]; then
	echo
	[ "$HEDEF" -eq 0 ] && echo "Extroot DEVRE DISI. Sonraki acilis dahili overlay (tasima oncesi hal) ile olacak." \
	                   || echo "Extroot ETKIN. Sonraki acilis appdata ile olacak."
	if [ "$REBOOT" -eq 1 ]; then echo "5 sn icinde yeniden baslatiliyor..."; sleep 5; reboot; else echo "Uygulamak icin: reboot"; fi
fi
