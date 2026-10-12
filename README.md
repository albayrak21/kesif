# Keşif

Harita tabanlı mekan keşif uygulamasının deneme sürümü. Harita İstanbul ve Mersin'de açık. Kayıtlar: Maltepe'deki hastaneler, çiçekçiler ve spor salonları; Mersin'deki spor salonları ve tekel büfeleri; İstanbul ve Mersin'deki AVM'ler; İstanbul'un otoparkları.

Site: https://albayrak21.github.io/kesif/
Yönetim: https://albayrak21.github.io/kesif/yonetim.html (yalnızca yönetici hesapları)

## Dosyalar

- `index.html`: uygulama (tek sayfa). Mekanları veritabanından okur; veritabanına ulaşamazsa `mekanlar.json`'daki son kopyayı kullanır.
- `yonetim.html`: yönetici girişi ve mekan düzenleme.
- `kategoriler.json`: kategori ve filtre tanımları. Filtre paneli ve yönetim formu bu dosyadan çizilir.
- `mekanlar.json`: mekan kayıtlarının yedek kopyası.
- `sinirlar.json`: İstanbul ve Mersin'in ilçe sınırları, Maltepe'nin mahalle sınırları.

## Veri ve lisanslar

- Mekan kayıtları Supabase (Postgres) veritabanında tutulur. Herkes okuyabilir; yalnızca yönetici listesindeki hesaplar yazabilir. Her değişiklik kim yaptı bilgisiyle geçmişe kaydedilir.
- Sayfadaki anahtar herkese açık (publishable) anahtardır; yetkiler veritabanı kurallarıyla (RLS) sınırlıdır.
- Hastane bilgileri hastanelerin kendi sitelerinden ve resmi kaynaklardan derlenmiştir. Doğrulama sürüyor; bilinmeyen değerler boş bırakılır.
- `osm_ref` alanı boş olan spor salonu kayıtları OpenStreetMap'ten değil, proje sahibinin derlediği bilgilerden gelir ve teyit bekler; bunlar ODbL kapsamında değildir.
- Çiçekçi, spor salonu ve AVM kayıtları OpenStreetMap'ten türetilmiştir: © OpenStreetMap katkıcıları, ODbL 1.0 (https://www.openstreetmap.org/copyright). `mekanlar.json` içinde `osm_ref` alanı dolu olan kayıtlar bu türetilmiş veritabanıdır ve ODbL 1.0 ile kullanılabilir.
- Mersin'deki spor salonu ve tekel büfesi kayıtlarının çoğu ile bazı kayıtların konumu Overture Maps Foundation'ın Places verisinden alınmıştır (overturemaps.org; kaynakları Meta, Foursquare, Microsoft ve diğerleri; CDLA-Permissive-2.0 ve Apache-2.0).
- İSPARK otopark kayıtları (`ispark-` ile başlayan kimlikler) İBB Açık Veri Portalı'nın İSPARK servisinden alınmıştır: İstanbul Büyükşehir Belediyesi / İSPARK A.Ş., İBB Açık Veri Lisansı (https://data.ibb.gov.tr). Ad, konum, tür, kapasite, saatler, ücretsiz süre, aylık abonelik ve tarife bu kaynaktandır; değişebilir.
- Diğer otopark kayıtları (`otopark-` ile başlayan kimlikler) OpenStreetMap'ten türetilmiştir (© OpenStreetMap katkıcıları, ODbL 1.0). Adı OSM'de olmayanların adı türünden üretilmiştir ve teyit bekler.
- Sınırlar: © OpenStreetMap katkıcıları, ODbL 1.0.
- Harita: Leaflet ve Leaflet.markercluster.

## Konum

- "Konumum" düğmesine basılınca tarayıcı konum izni ister. İzin verilirse konum haritada gösterilir ve sonuçlar yakınlığa göre sıralanır.
- Konum yalnızca tarayıcıda, sayfa açıkken kullanılır: veritabanına ya da başka bir sunucuya gönderilmez, kaydedilmez. Harita karoları, her harita kullanımında olduğu gibi, görüntülenen bölge için karo sunucusundan indirilir.
- Yönetim sayfasındaki "Bulunduğum yeri kullan" düğmesi, yöneticinin konumunu yalnızca koordinat alanına yazar; kaydedilirse mekanın konumu olur. Sokak haritası karoları OpenStreetMap verisinden üretilir.

## Favoriler ve listeler

- Kartlardaki yıldıza basılınca kayıt favorilere eklenir; "Göster" menüsündeki "Favorilerim" listeyi ve haritayı favorilerle sınırlar.
- Kartlardaki liste düğmesiyle kayıt, adını ziyaretçinin verdiği listelere eklenir; "Listelerim" penceresinden liste oluşturulur, adı değiştirilir, silinir ve paylaşılır. "Göster" menüsü listeyi ve haritayı seçilen listeyle sınırlar.
- Paylaşım bağlantıyla yapılır: liste adı ve kayıt kimlikleri adresin `#liste=` parçasına yazılır (bu parça sunucuya gönderilmez). Bağlantıyı açan listeyi görür ve kendi listelerine kaydedebilir. Bağlantı listenin o anki kopyasıdır.
- Hesap yoktur: favoriler ve listeler o tarayıcıda (localStorage) saklanır. Başka cihazda ya da tarayıcı verisi silinince görünmez.
- Listeler sunucuya gönderilmez. Favoriler, "En çok favorilenenler" sayımı için tarayıcıya özel rastgele bir cihaz numarasıyla veritabanına da gönderilir (yalnızca cihaz numarası ve mekan kimlikleri; ad, e-posta, konum gönderilmez). Veritabanı dışarıya yalnızca mekan başına toplam sayıyı verir. Bu, test aşaması çözümüdür; canlıda sayım hesaplara bağlanacaktır.

## İşletme sayfası

- Her kaydın kendi sayfası ve adresi var: `https://albayrak21.github.io/kesif/#mekan=<kimlik>`. Kart, iğne, Keşfet ya da arama sonucuna basınca açılır; bağlantı paylaşılabilir, tarayıcının geri tuşu çalışır.
- Telefonda tam ekran açılır; geniş ekranda filtre paneli ve listenin yerini alır, harita yanında açık kalır.
- Bölümler: hızlı eylemler (Ara, Yol tarifi, Web sitesi, Haritada), "İşletmenin anlattıkları", "Özellikler" (kategori tanımından), "İletişim ve konum", "Yakındaki benzer yerler", kaynak.
- "İşletmenin anlattıkları" işletme sahibinin gireceği bilgilerdir ("İşletme beyanı" etiketiyle, Keşif'in derlediği bilgilerden ayrı gösterilir ve onları değiştirmez). Sahiplenme henüz yok; şimdilik bu bölüm boş görünür.

## Puanlar

- Herkes bir yere 1–5 yıldız verebilir; tarayıcıya özel rastgele bir cihaz numarasıyla tutulur (cihaz başına yer başına bir puan, değiştirilebilir ve kaldırılabilir). Bu test aşaması çözümüdür; canlıda puanlar hesaplara bağlanacaktır.
- Hastanelerde puanlama kapalıdır (`kategoriler.json`'da `"puanlama": false`; veritabanı da aynı kuralı denetler).
- Sıralama ağırlıklı puanla yapılır: (5 × kategori ortalaması + puanların toplamı) / (5 + puan sayısı). Böylece tek bir 5 yıldızlı puan, çok sayıda yüksek puanın önüne geçmez.
- Liste "Puana göre / Yakınlığa göre / Ada göre", arama sonuçları "En iyi eşleşme / Puana göre / Yakınlığa göre" sıralanabilir. Keşfet'te "En yüksek puanlılar" rafı vardır.

## İşletme fotoğrafları

- Fotoğraflar işletme sayfasında gösterilir; büyük görünümde ok tuşlarıyla gezilir.
- Şimdilik yöneticiler yönetim sayfasından yükler. Yer başına hak varsayılan 5'tir, yönetimden artırılabilir (0–50).
- Yüklemeden önce tarayıcıda en uzun kenarı 1600 piksele (ve 480 piksellik küçük boya) küçültülür, webp'ye çevrilir; konum dahil dosya bilgileri silinir. Dosyalar Supabase'in `mekan-foto` deposunda herkese açık olarak durur.

## Otoparklar

- İstanbul'un bütün ilçelerinde: İSPARK'ın resmi listesindeki otoparklar ve OpenStreetMap'te kayıtlı, herkese açık görünen diğer otoparklar (özel, personel, site, TIR ve müşteri otoparkları ayıklandı; İSPARK ile aynı yerdeki OSM kayıtları atıldı).
- "İşletmeci" filtresi: İSPARK, İlçe belediyesi, Özel ve diğer. Belli bir belediyenin otoparkları için ilçeyi seçip "İlçe belediyesi"ni işaretle.
- Diğer filtreler: tür (kapalı/katlı, açık alan, yol üstü), ücret, 7/24, ilk dakikalar ücretsiz, aylık abonelik.
- Tarife, kapasite, çalışma saatleri ve işleten kurum "bilgi" alanlarıdır (`kategoriler.json`'da `bilgiler`): süzmede kullanılmaz, işletme sayfasında gösterilir, yönetimden düzenlenir.
- Anlık doluluk henüz yok. İSPARK'ın servisi tarayıcıdan doğrudan okunamıyor; ileride sunucu tarafında bir ara katmanla eklenebilir.

## Keşfet

- Telefonda alttaki, geniş ekranda üstteki sekmelerle Harita ve Keşfet arasında geçilir.
- Keşfet'te iki liste var: "En çok favorilenenler" ve "Son eklenenler". İkisi de harita sekmesindeki seçime (il, ilçe ya da taranan alan, kategori, filtreler) uyan kayıtlardan çizilir. Eklenme tarihi, veritabanındaki değişiklik geçmişinde kaydın ilk eklendiği andır.
- Arama bütün il ve kategorilerde ad, ilçe, il ve adrese bakar; kategori adları ve filtre seçenekleri (marka, branş, özellik) için filtre önerir. Sonuca basınca harita o kayda gider.
- Haritayı kaydırınca ya da yakınlaştırınca "Bu alanı tara" düğmesi çıkar; basınca liste o anki harita alanıyla sınırlanır (seçili kategori ve filtreler geçerli kalır).
