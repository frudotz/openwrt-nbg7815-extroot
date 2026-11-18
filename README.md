# Zyxel Armor G5 için Türkçe OpenWRT Extroot Rehberi
OpenWRT kurulu NBG7815 cihazlarda kullanılabilir hafıza ~40 MB ile sınırlıdır, eMMC'deki 2.8 GB'lık **`appdata`** alanı ise boşta durur.  
Bu rehberdeki yöntemle overlay'i bu alana kayıpsız taşıyabilir, sorun çıkarsa cihazın kendiliğinden eski haline dönmesini sağlayabilirsiniz.  
*Bu işlem cihazınızın depolama yapılandırmasını değiştirir, oluşabilecek tüm komplikasyonlar sizin sorumluluğunuzdadır.*  
*Konu ile ilgili hiçbir sorumluluk kabul etmiyoruz. Rehberimizi kaynak göstererek paylaşmanız önemle rica olunur.* 🙏

<p align="left">
  <a href="https://discord.gg/k6y5MBKCPW"><img src="https://img.shields.io/badge/Discord-Yardım İçin-blue?logo=discord&logoColor=white"/></a>
</p>

<details>
  <summary>İçindekiler</summary>
  <ol>
    <li><a href="#-başlarken">✨ Başlarken</a></li>
    <li><a href="#-kurulum">🚀 Kurulum</a></li>
    <li><a href="#-kurulum-sonrası">😎 Kurulum Sonrası</a></li>
    <li><a href="#-sorun-giderme">🛟 Sorun Giderme</a></li>
    <li><a href="#%EF%B8%8F-geri-dönüş">↩️ Geri Dönüş</a></li>
    <li><a href="#-firmware-güncellerken">🔄 Firmware Güncellerken</a></li>
    <li><a href="#-katkıda-bulun--bağış">🤝 Katkıda Bulun / Bağış</a></li>
    <li><a href="#%EF%B8%8F-kaynaklar">🗃️ Kaynaklar</a></li>
  </ol>
</details>



# ✨ Başlarken
Cihazınızda [rehberimizle](https://github.com/frudotz/openwrt-zyxel-nbg7815) kurulmuş OpenWRT ve SSH erişimi olmalıdır. Bilgisayarı cihaza **kablo ile** bağlayın.  
İşlem sırasında cihaz yeniden başlayacak ve ağ birkaç dakika kesilecektir. Önce ayarlarınızın yedeğini alıp bilgisayara indirin:  
> **`sysupgrade -b /tmp/yedek.tar.gz`**  
> **`scp -O root@192.168.1.1:/tmp/yedek.tar.gz .`** *(bilgisayarda)*

Bu sayfayı bilgisayarınıza kaydedin, internet kesilirse sorun giderme adımları elinizde olsun.

# 🚀 Kurulum
SSH ile cihaza bağlanıp kurulum betiğini indirin ve önce sadece kontrol modunda çalıştırın:  
> **`wget https://raw.githubusercontent.com/frudotz/openwrt-nbg7815-extroot/main/kur.sh -O /tmp/kur.sh`**  
> **`sh /tmp/kur.sh --kontrol`**

Sonuç satırında **`0 HATA`** görmüyorsanız devam etmeyin; hatanın ne olduğu çıktıda yazar. Eksik paket varsa kurun:  
> **`apk add block-mount e2fsprogs`** *(OpenWRT 24.10 ve öncesinde: `opkg update && opkg install block-mount e2fsprogs`)*

Kontrol temizse kurulumu başlatın:  
> **`sh /tmp/kur.sh`**

Betik sırasıyla şunları yapar, herhangi bir adımda sorun görürse **hiçbir şeyi değiştirmeden** durur:
1. `appdata` partition'ını biçimlendirir, overlay'i kopyalar ve kopyayı dosya dosya doğrular.
2. Açılış sonrası çalışacak bir kontrol betiği ve DHCP düzeltmesi kurar, cihazı yeniden başlatır.
3. Açılıştan sonra 12 dakika boyunca DHCP, DNS ve interneti kontrol eder.
   Her şey yolundaysa kendini kaldırır. Sorun düzelmezse extroot'u kapatır ve cihazı **taşıma öncesi haline** döndürür.

İlerlemeyi **`tail -f /tmp/otomatik.log`** ile izleyebilirsiniz. En kötü durumda cihaz ~20 dakika içinde kendiliğinden eski haline döner, beklemeniz yeterlidir.

# 😎 Kurulum Sonrası
Cihaz açıldıktan birkaç dakika sonra sonucu kontrol edin:  
> **`df -h /overlay`** *(~2.6G görmelisiniz)*  
> **`cat /root/extroot-kit/bekci.log`**  
> **`sh /root/extroot-kit/03_dogrula.sh`**

Son olarak telefonunuzun Wi-Fi'sini kapatıp açın ve IP aldığını görün. Tebrikler! Artık paket kurarken yer derdiniz yok. \*alkış efekti\*

# 🛟 Sorun Giderme
Bir sorunla karşılaşırsanız önce logları kaydedin, loglar RAM'de tutulur ve yeniden başlatınca silinir:  
> **`sh /root/extroot-kit/04_teshis.sh`**

**Wi-Fi'ye yeni bağlanan cihazlar IP alamıyor (169.254.x.x):** Açılışta dnsmasq, ağ arayüzü henüz hazır değilken başlarsa o ağ için DHCP aralığı oluşturmaz.  
Kurulumla gelen **`dhcp-aralik-bekci`** bunu dakikada bir kontrol edip düzeltir. Beklemek istemezseniz:  
> **`/etc/init.d/dnsmasq restart`**

**IP var ama DNS çalışmıyor:** Geçici olarak yedek DNS ekleyin, sorun çözülünce kapatın:  
> **`sh /root/extroot-kit/91_acil_ag.sh dns-yedek-ac`**  
> **`sh /root/extroot-kit/91_acil_ag.sh dns-yedek-kapat`**

**`df -h /overlay` hâlâ ~40 MB gösteriyor:** Extroot bağlanamamış ve cihaz eski overlay ile açılmıştır. Sebebi şu komutla görülür:  
> **`logread | grep -i extroot`**

⚠️ Extroot aktifken LuCI'deki *Mount Points* sayfasından veya `/etc/config/fstab` dosyasından extroot'u kapatamazsınız, bu değişiklikler açılışı etkilemez. Geri dönmek için aşağıdaki yöntemleri kullanın.  
⚠️ Reset butonunu **5 saniye veya daha uzun** basılı tutmak cihazı **fabrika ayarlarına** döndürür.

# ↩️ Geri Dönüş
Taşıma sırasında eski overlay değiştirilmez, extroot kapatıldığında cihaz taşıma anındaki haline döner. Extroot'taki veriler silinmez.  
> **`sh /root/extroot-kit/90_geri_al.sh --yeniden-baslat`**

Betiğe ulaşamıyorsanız aynı işlemi yapan komutlar:  
> **`set -- $(hexdump -s 40 -n 8 -e '2/4 "%u "' /dev/mmcblk0p4); OFF=$(( ($1 + $2*4294967296 + 65535) / 65536 * 65536 ))`**  
> **`L=$(losetup -f); losetup -o $OFF $L /dev/mmcblk0p4; mkdir -p /tmp/d; mount -t ext4 $L /tmp/d`**  
> **`uci -c /tmp/d/upper/etc/config set fstab.extroot.enabled=0`**  
> **`uci -c /tmp/d/upper/etc/config commit fstab`**  
> **`sync; umount /tmp/d; losetup -d $L; reboot`**

**Cihaza ağdan ulaşılamıyorsa (failsafe):** Bilgisayarı **lan1–lan4** veya **10G** portuna takın ve bilgisayara **`192.168.1.2`** IP'sini elle verin.  
Cihazın fişini çekip takın, **3. ile 15. saniyeler** arasında reset butonuna **kısa kısa** dokunun (her biri 1 saniyeden kısa).  
**`ping 192.168.1.1`** cevap verdiğinde **`ssh root@192.168.1.1`** ile şifresiz bağlanıp yukarıdaki komutları girin, ardından **`reboot -f`** yazın.  
⚠️ Failsafe modunda **`mount_root`** komutunu **kullanmayın**, bu komut extroot'u bağlar ve yanlış dosyayı düzenlemenize sebep olur.

# 🔄 Firmware Güncellerken
OpenWRT, sysupgrade sonrası eski extroot'u yeni firmware'in üzerine sorgusuz bağlar. Güncellemeden **önce** extroot'u kapatın:  
> **`sh /root/extroot-kit/90_geri_al.sh`**

Güncelleme bittikten sonra paketlerinizi yeniden kurun ve [Kurulum](#-kurulum) adımlarını tekrarlayın.

# 🤝 Katkıda Bulun / Bağış
  - Yanlış gördüğünüz veya eklemek istediğiniz şeyleri PR/Issue açarak iletebilirsiniz.  
  - Rehberimizi faydalı bulduysanız [🍻 bir bira ısmarlayarak](https://coff.ee/frudotz) bana destek olabilirsiniz.

# 🗃️ Kaynaklar
  - [Teknik Notlar](docs/TEKNIK-NOTLAR.md)  
  - [Zyxel NBG7815 OpenWRT Kurulum Rehberi](https://github.com/frudotz/openwrt-zyxel-nbg7815)  
  - [OpenWRT Wiki - Extroot](https://openwrt.org/docs/guide-user/additional-software/extroot_configuration)  
  - [OpenWRT fstools](https://github.com/openwrt/fstools)  
  
-----------
🎀 Rehberimizi okuduğunuz için teşekkür ederiz!  
⭐ İçeriği faydalı bulduysanız desteklemek için **Star** verebilirsiniz.
