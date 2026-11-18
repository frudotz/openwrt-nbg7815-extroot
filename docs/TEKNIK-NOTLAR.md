# Teknik Notlar
Rehberdeki yöntemin dayandığı bulgular. Tüm tespitler NBG7815 (OpenWRT 25.12, qualcommax/ipq807x) üzerinde ve `fstools` kaynak kodunda doğrulanmıştır.

## eMMC yapısı
| Partition | Ad | Boyut | Not |
|---|---|---|---|
| p1 | rootfs_data | 8 MB | Kullanılmıyor |
| p3 / p7 | 0:HLOS / 0:HLOS_1 | 6 MB | Kernel (slot 0 / 1) |
| p4 | rootfs | 60 MB | squashfs + dahili overlay (ext4, loop) |
| p8 | rootfs_1 | 60 MB | Yedek slot |
| p10 | nbg | 512 MB | Zyxel stok verisi |
| p11 | appdata | 2816 MB | Kullanılmıyor, extroot hedefi |

- Partition'lar arasında çakışma yoktur. Aktif slot, `0:bootconfig` MTD partition'ının 168. baytından okunur (0 = rootfs).
- Dahili overlay, `mmcblk0p4` üzerinde squashfs'in bittiği yerden (64 KB'a hizalı) başlayan bir loop cihazıdır. Offset: squashfs superblock'undaki `bytes_used` (bayt 40, 8 bayt) değeri 65536'ya yukarı yuvarlanarak hesaplanır.
- Ethernet ve NSS sürücüleri ROM'dadır, overlay taşınınca kaybolmaz.

## Extroot kararı nerede verilir?
- Açılışta `block extroot`, **dahili** overlay'deki `/etc/config/fstab`'ı okur (`/tmp/overlay/upper/etc/config/fstab`). `target '/overlay'` olan ve `enabled '0'` olmayan ilk kayıt bağlanır.
- Extroot aktifken görülen fstab extroot'taki kopyadır; onu değiştirmek açılışı etkilemez. Geri dönmek için dahili overlay'e loop ile erişilmelidir.
- Dahili overlay'in loop'u `LO_FLAGS_AUTOCLEAR` ile kurulur. Extroot aktifken bu loop yoktur, `losetup -o <offset>` ile yeniden kurulmalıdır.
- Extroot cihazı bulunamaz veya bağlanamazsa sistem dahili overlay ile açılır.
- Failsafe'te `mount_root` önce extroot'u dener (`mount_root.c`). Bu yüzden failsafe'te fstab düzenlemek için `mount_root` yerine loop yöntemi kullanılmalıdır.

## UUID kontrolü fiilen kapalı
`fstools` commit `3a07943e` (2023) ile `check_extroot()` fonksiyonu, `/etc/.extroot-default` dosyası **yoksa** UUID kontrolünü atlar (commit mesajı tersini söyler). Sonuç olarak `.extroot-uuid` hiç yazılmaz ve sysupgrade sonrası eski extroot yeni firmware'in üzerine bağlanır. Bu yüzden güncellemeden önce extroot kapatılmalıdır.

## Kopyalama
- BusyBox `tar`, overlay whiteout'larını (silinmiş ROM dosyalarını işaretleyen karakter cihazları) korur. Bu önemlidir: kurulumdan sonra bir kez çalışıp silinen `uci-defaults` betikleri (DHCP, dnsmasq ve ağ ayarlarını yapanlar dahil) whiteout kaybolursa tekrar çalışır.
- BusyBox `tar` xattr kopyalamaz. Opaque dizin varsa sorun çıkarabilir; test edilen cihazda opaque dizin bulunmadı.
- Sadece `upper` kopyalanır, `work` boş oluşturulur. Kopya; dosya listesi, md5, symlink hedefleri ve whiteout listesi ile kaynağa karşı doğrulanır.

## Biçimlendirme
Varsayılan `mkfs.ext4`, inode tablolarını ilk bağlamalardan sonra arka planda sıfırlar (lazy init). 2.8 GB'lık yavaş eMMC'de bu, açılışta uzun süreli disk yükü demektir. Rehber `-E lazy_itable_init=0,lazy_journal_init=0` kullanır.

## DHCP yarış durumu
Extroot sonrası bildirilen "cihazlar IP alamıyor" sorununun sebebi:
- Açılışta Wi-Fi köprüsü (`br-wifi`) birkaç kez inip kalkar. dnsmasq'ın başlatma betiği, o anda ayakta olmayan arayüz için `dhcp-range` satırı üretmez.
- dnsmasq sonradan yeniden başlasa bile aralık eksik kalabilir. Test edilen cihazda `/var/etc/` altında açılışta yarım kalmış ve Wi-Fi aralığı içermeyen bir geçici yapılandırma dosyası bulundu.
- Belirti: `logread` içinde `no address range available for DHCP request via br-wifi`. Bu sırada eski lease'i olan ve kablolu cihazlar çalışmaya devam ettiği için sorun gözden kaçar.
- Sorun extroot'a özgü olmayabilir; yarış her açılışta yaşanır, ancak bazen sonuç doğru çıkar.

`dhcp-aralik-bekci`, cron ile dakikada bir **çalışan** dnsmasq'ın `-C` ile kullandığı dosyayı okur. DHCP'si açık, arayüzü ayakta ve statik IP'li her ağın aralığı var mı bakar, eksikse dnsmasq'ı yeniden başlatır (5 dakikada en fazla bir kez).

## Reset butonu ve failsafe
- `/etc/rc.button/reset`: sistem açıkken 1 saniyeden kısa basış reboot, 5 saniye ve üzeri basış **fabrika ayarı** yapar.
- Failsafe penceresi, preinit sırasında 4 saniyedir (`fs_failsafe_wait_timeout=4`). Bu cihazda durum LED'i tanımlı değildir.
- Failsafe ağı kullanıcı ayarlarını değil, cihazın varsayılan port düzenini kullanır: lan1–lan4 ve 10G, IP `192.168.1.1`.
- Seri konsol: `ttyMSM0`, 115200 8N1.
