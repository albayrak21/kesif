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
- Çiçekçi, spor salonu ve AVM kayıtları OpenStreetMap'ten türetilmiştir: © OpenStreetMap katkıcıları, ODbL 1.0 (https://www.openstreetmap.org/copyright). `mekanlar.json` içinde `osm_ref` alanı dolu olan kayıtlar bu türetilmiş veritabanıdır ve ODbL 1.0 ile kullanılabilir.
- Sınırlar: © OpenStreetMap katkıcıları, ODbL 1.0.
- Harita: Leaflet ve Leaflet.markercluster.

## Konum

- "Konumum" düğmesine basılınca tarayıcı konum izni ister. İzin verilirse konum haritada gösterilir ve sonuçlar yakınlığa göre sıralanır.
- Konum yalnızca tarayıcıda, sayfa açıkken kullanılır: veritabanına ya da başka bir sunucuya gönderilmez, kaydedilmez. Harita karoları, her harita kullanımında olduğu gibi, görüntülenen bölge için karo sunucusundan indirilir.
- Yönetim sayfasındaki "Bulunduğum yeri kullan" düğmesi, yöneticinin konumunu yalnızca koordinat alanına yazar; kaydedilirse mekanın konumu olur. Sokak haritası karoları OpenStreetMap verisinden üretilir.

## Favoriler ve listeler

- Kartlardaki yıldıza basılınca kayıt favorilere eklenir; "Yalnızca favorilerim" anahtarı listeyi ve haritayı favorilerle sınırlar.
- Kartlardaki liste düğmesiyle kayıt, adını ziyaretçinin verdiği listelere eklenir; "Listelerim" penceresinden liste oluşturulur, adı değiştirilir, silinir ve paylaşılır. "Göster" menüsü listeyi ve haritayı seçilen listeyle sınırlar.
- Paylaşım bağlantıyla yapılır: liste adı ve kayıt kimlikleri adresin `#liste=` parçasına yazılır (bu parça sunucuya gönderilmez). Bağlantıyı açan listeyi görür ve kendi listelerine kaydedebilir. Bağlantı listenin o anki kopyasıdır.
- Hesap yoktur: favoriler ve listeler yalnızca o tarayıcıda (localStorage) saklanır, sunucuya gönderilmez. Başka cihazda ya da tarayıcı verisi silinince görünmez.
