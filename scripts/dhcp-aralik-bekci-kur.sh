#!/bin/sh
# dhcp-aralik-bekci kurulumu / kaldirilmasi
#   sh dhcp-aralik-bekci-kur.sh            # kur (/usr/sbin + cron her dakika)
#   sh dhcp-aralik-bekci-kur.sh --kaldir   # kaldir
D=$(cd "$(dirname "$0")" && pwd)
CR=/etc/crontabs/root
if [ "$1" = "--kaldir" ]; then
	rm -f /usr/sbin/dhcp-aralik-bekci /tmp/dhcp-aralik-bekci.son
	[ -f $CR ] && { grep -v "dhcp-aralik-bekci" $CR > /tmp/cr.$$; cat /tmp/cr.$$ > $CR; rm -f /tmp/cr.$$; }
	/etc/init.d/cron restart; echo "Kaldirildi."; exit 0
fi
[ -f "$D/dhcp-aralik-bekci" ] || { echo "dhcp-aralik-bekci bulunamadi ($D)"; exit 1; }
sh -n "$D/dhcp-aralik-bekci" || exit 1
cp "$D/dhcp-aralik-bekci" /usr/sbin/dhcp-aralik-bekci && chmod 755 /usr/sbin/dhcp-aralik-bekci
mkdir -p /etc/crontabs; touch $CR
grep -q "dhcp-aralik-bekci" $CR || echo "* * * * * /usr/sbin/dhcp-aralik-bekci" >> $CR
/etc/init.d/cron enable; /etc/init.d/cron restart
echo "Kuruldu. Durum:"; /usr/sbin/dhcp-aralik-bekci --test
echo "Mudahaleleri izlemek icin: logread | grep dhcp-aralik-bekci"
