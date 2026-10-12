# Keşif

Harita tabanlı mekan keşif uygulamasının deneme sürümü. Harita İstanbul ve Mersin'de açık. Kayıtlar: Maltepe'deki hastaneler, çiçekçiler ve spor salonları; Mersin'deki spor salonları; İstanbul ve Mersin'deki AVM'ler.

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

## Keşfet

- Telefonda alttaki, geniş ekranda üstteki sekmelerle Harita ve Keşfet arasında geçilir.
- Keşfet'te iki liste var: "En çok favorilenenler" ve "Son eklenenler". İkisi de harita sekmesindeki seçime (il, ilçe ya da taranan alan, kategori, filtreler) uyan kayıtlardan çizilir. Eklenme tarihi, veritabanındaki değişiklik geçmişinde kaydın ilk eklendiği andır.
- Arama bütün il ve kategorilerde ad, ilçe, il ve adrese bakar; kategori adları ve filtre seçenekleri (marka, branş, özellik) için filtre önerir. Sonuca basınca harita o kayda gider.
- Haritayı kaydırınca ya da yakınlaştırınca "Bu alanı tara" düğmesi çıkar; basınca liste o anki harita alanıyla sınırlanır (seçili kategori ve filtreler geçerli kalır).
