# Keşif

Harita tabanlı mekan keşif uygulamasının deneme sürümü. İlk kapsam: İstanbul, Maltepe'deki hastaneler.

Site: https://albayrak21.github.io/kesif/

## Dosyalar

- `index.html`: uygulama (tek sayfa).
- `kategoriler.json`: kategori ve filtre tanımları. Filtre paneli bu dosyadan çizilir.
- `mekanlar.json`: mekan kayıtları.
- `sinirlar.json`: ilçe ve mahalle sınırları.

## Veri

- Hastane bilgileri hastanelerin kendi sitelerinden ve resmi kaynaklardan derlenmiştir. Doğrulama sürüyor; bilinmeyen değerler boş bırakılır.
- Sınırlar: © OpenStreetMap katkıcıları, ODbL 1.0 (https://www.openstreetmap.org/copyright).
- Harita: Leaflet. Sokak haritası karoları OpenStreetMap verisinden üretilir.
