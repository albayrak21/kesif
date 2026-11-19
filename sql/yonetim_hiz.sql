-- 19.11.2026: yönetim sayfası "Mekanlar yüklenemedi: statement timeout" veriyordu.
-- Sayfa büyük kategoriler dışındaki kayıtları (avm, tekel) "kategori NOT IN (...)" ile istiyordu; bu, 2,77 milyon satırı
-- baştan sona tarıyordu (soğuk önbellekte ~9,4 sn; giriş yapmış kullanıcı sınırı 8 sn). Sorgu "kategori IN (...)" yapıldı
-- ve bu dizin eklendi: aynı sorgu ~0,5 sn. Dizin ~170 MB.
create index concurrently if not exists mekan_kategori_id_idx on public.mekan (kategori, id);
