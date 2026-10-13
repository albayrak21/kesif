# Foursquare OS Places aktarımı (13.10.2026)

Bu dal yalnızca veritabanına toplu aktarım için kullanılan veri parçalarını içerir; site bu daldan yayınlanmaz.

- Kaynak: Foursquare Open Source Places, sürüm `release/dt=2026-09-15` (Hugging Face `foursquare/fsq-os-places`).
- Lisans: Apache License 2.0. © Foursquare Labs, Inc. Veri değiştirilmiştir: İstanbul'a kırpıldı, 2023 öncesi güncellenmiş
  ve kapanmış kayıtlar atıldı, kategoriler Keşif kategorilerine çevrildi, adlar/telefonlar/web adresleri biçimlendirildi,
  çift kayıtlar birleştirildi, ilçe konumdan hesaplandı.
- Satır biçimi: `[kimlik, kategori, ad, enlem, boylam, adres, ilçe, telefon, web, özellikler, teyit_bekleyen, son_güncelleme, kaynaktaki_alanlar, web_https_yapıldı]`
- `ozet.json`: her parçanın satır sayısı, bayt boyutu ve SHA-256 özeti.
