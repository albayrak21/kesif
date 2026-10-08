# Keşif

Harita tabanlı mekan keşif uygulamasının deneme sürümü. Harita İstanbul ve Mersin'de açık. Kayıtlar: Maltepe'deki hastaneler, çiçekçiler ve spor salonları.

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
- Çiçekçi ve spor salonu kayıtları OpenStreetMap'ten türetilmiştir: © OpenStreetMap katkıcıları, ODbL 1.0 (https://www.openstreetmap.org/copyright). `mekanlar.json` içinde `osm_ref` alanı dolu olan kayıtlar bu türetilmiş veritabanıdır ve ODbL 1.0 ile kullanılabilir.
- Sınırlar: © OpenStreetMap katkıcıları, ODbL 1.0.
- Harita: Leaflet ve Leaflet.markercluster. Sokak haritası karoları OpenStreetMap verisinden üretilir.
