#!/bin/sh
# =====================================================================
# Zyxel NBG7815 - Guvenli Extroot kurulumu (baslatici)
# https://github.com/frudotz/openwrt-nbg7815-extroot
#
#   sh kur.sh             # indir + on kontrol + otomatik tasima
#   sh kur.sh --kontrol   # sadece indir + on kontrol (hicbir sey degismez)
# =====================================================================
URL="${KIT_URL:-https://codeload.github.com/frudotz/openwrt-nbg7815-extroot/tar.gz/refs/heads/main}"
K=/tmp/extroot-kit
TMPD=/tmp/nbg7815-extroot-indir

[ "$(cat /tmp/sysinfo/board_name 2>/dev/null)" = "zyxel,nbg7815" ] || { echo "[X] Bu betik sadece Zyxel NBG7815 icindir."; exit 1; }
[ "$(id -u)" = 0 ] || { echo "[X] root olarak calistirin."; exit 1; }

echo "[1/3] Betikler indiriliyor..."
rm -rf "$TMPD" "$K"; mkdir -p "$TMPD"
wget -q -O "$TMPD/kit.tar.gz" "$URL" || { echo "[X] Indirilemedi. Internet/HTTPS erisimini kontrol edin."; exit 1; }
tar -C "$TMPD" -xzf "$TMPD/kit.tar.gz" || { echo "[X] Arsiv acilamadi."; exit 1; }
mv "$TMPD"/*/scripts "$K" && rm -rf "$TMPD" || { echo "[X] Betikler bulunamadi."; exit 1; }
chmod +x "$K"/*
for f in "$K"/*; do sh -n "$f" || { echo "[X] Bozuk betik: $f"; exit 1; }; done

echo "[2/3] On kontrol..."
sh "$K/01_onkontrol.sh" | tee /tmp/extroot_onkontrol.txt
grep -q "SONUC: .* 0 HATA" /tmp/extroot_onkontrol.txt || { echo; echo "[X] On kontrolde HATA var. Hicbir sey degistirilmedi."; exit 1; }
t=$(sh "$K/95_bekci.sh" --test); echo "$t"
case "$t" in *BASARILI*) ;; *) echo "[X] Ag kontrolleri su anki sistemde basarisiz. Once bunu cozun. Hicbir sey degistirilmedi."; exit 1 ;; esac

[ "$1" = "--kontrol" ] && { echo; echo "Kontrol tamam. Kurulum icin: sh $0"; exit 0; }

echo
echo "[3/3] Tasima 15 sn icinde baslayacak. Iptal icin Ctrl+C."
echo "      Cihaz kendiliginden yeniden baslayacak, ag birkac dakika kesilecek."
sleep 15
rm -f /tmp/otomatik.log
if command -v setsid >/dev/null; then
	setsid sh "$K/00_otomatik.sh" </dev/null >/dev/null 2>&1 &
else
	start-stop-daemon -S -b -x /bin/sh -- "$K/00_otomatik.sh"
fi
sleep 2
echo "Basladi. Ilerlemeyi izlemek icin:  tail -f /tmp/otomatik.log"
echo "Reboot sonrasi sonuc:              cat /root/extroot-kit/bekci.log"
