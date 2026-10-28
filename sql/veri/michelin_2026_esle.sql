-- Michelin 2026: kalan eşleşmeler, kayıtta olmayan 7 restoranın eklenmesi ve etiketlerin yazılması.
-- Eşleşmeler aktarim_michelin.mekan_id'de; seçimler elle gözden geçirildi (aday listesi aktarim_michelin_aday).
update aktarim_michelin k set mekan_id = m.id, durum = 'eslesti'
from (values (6,'Nevşehir','Moniq','Nevşehir Merkez'),(12,'İstanbul','Foxy Local & Real','Şişli'),(23,'İstanbul','The Red Balloon','Beyoğlu'),
             (28,'İstanbul','Seraf Restaurant','Bağcılar'),(47,'Nevşehir','Uzundere Anatolian Restaurant','Nevşehir Merkez'),
             (90,'İzmir','Partal Kardeşler Balık Restorant','Urla'),(118,'Muğla','Mori Restaurant','Fethiye'),
             (123,'İzmir','Çark Balık Restorant Çeşme','Çeşme'),(131,'İzmir','İsabey Bağevi','Menderes'),(149,'İstanbul','Kıyı Restaurant','Sarıyer')) v(i, il, ad, ilce)
join lateral (select id from mekan m where m.arama = lower(translate(v.ad || ' ' || v.ilce, 'ÇĞİIÖŞÜÂÎÛçğıöşüâîû', 'cgiiosuaiucgiosuaiu'))
              and m.durum = 'acik' and m.il = v.il and m.kategori in ('restoran','meyhane','kafe','bar','kahvalti','konaklama','diger') limit 1) m on true
where k.i = v.i and k.mekan_id is null;

-- Kayıtta olmayanlar: Michelin sayfasındaki ad, adres, konum, telefon ve web ile eklenir.
insert into mekan (id, kategori, ad, lat, lng, adres, il, ilce, telefon, web, ozellikler, dogrulanacak, dogrulama_tarihi, durum, onem, guven)
select 'restoran-mic-' || k.i, 'restoran', k.ad, k.lat, k.lng, k.adres, s.il, s.ilce, k.telefon, k.web,
       jsonb_build_object('kaynak', 'Michelin Rehberi Türkiye 2026', 'kaynak_url', k.url), '{}', current_date, 'acik', 70, 0.9
from aktarim_michelin k
join lateral (select p.il, p.ilce from sinir_tr_parca p where st_intersects(p.geom, st_setsrid(st_point(k.lng, k.lat), 4326)) limit 1) s on true
where k.mekan_id is null and k.lat is not null
on conflict (id) do nothing;
update aktarim_michelin k set mekan_id = 'restoran-mic-' || k.i, durum = 'eklendi'
where k.mekan_id is null and exists (select 1 from mekan m where m.id = 'restoran-mic-' || k.i);

-- Etiketler
insert into mekan_etiket (mekan_id, etiket, kaynak, kaynak_url, dogrulama_tarihi, ekleyen)
select k.mekan_id, k.etiket, 'Michelin Rehberi Türkiye 2026', k.url, current_date, null from aktarim_michelin k where k.mekan_id is not null
on conflict (mekan_id, etiket) do nothing;
insert into mekan_etiket (mekan_id, etiket, kaynak, kaynak_url, dogrulama_tarihi, ekleyen)
select k.mekan_id, 'michelin_yesil_yildiz', 'Michelin Rehberi Türkiye 2026', k.url, current_date, null from aktarim_michelin k where k.mekan_id is not null and k.yesil
on conflict (mekan_id, etiket) do nothing;
