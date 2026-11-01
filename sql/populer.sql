-- Popülerlik (01.11.2026): aramasız gezinmede yakınlaştıkça hangi işletmelerin önce görüneceği.
-- populer = skor + 15 × (kaynak sayısı − 1) + kategori ağırlığı. Öne çıkanlar (ilgi > 0) her zaman önde (harita_getir).
-- Kaynak sayısı: mekan_ic.kaynaklar içindeki farklı kaynak türleri (OSM, Overture, Foursquare, Wikidata, Wikipedia, diğer resmi).
-- Bir yer birden çok bağımsız veri setinde varsa bilinen bir yerdir; gerçek ziyaret verisi olmadığı için en güçlü sinyal bu.
-- Kolon varsayılanı 1: yalnız 2+ kaynaklı satırlar (~%18) güncellenir, tablo az şişer.

alter table public.mekan_nokta add column if not exists kaynak smallint not null default 1;

create or replace function public.mekan_kaynak_sayi(kaynaklar jsonb)
returns smallint language sql immutable parallel safe set search_path = '' as $$
  select greatest(1, count(distinct case
      when x->>'url' ~* 'openstreetmap|geofabrik|overpass' then 'osm'
      when x->>'url' ~* 'overture' then 'ov'
      when x->>'url' ~* 'foursquare' then 'fsq'
      when x->>'url' ~* 'wikidata' then 'wd'
      when x->>'url' ~* 'wikipedia|wikimedia' then 'wp'
      else 'diger' end))::smallint
  from jsonb_array_elements(case when jsonb_typeof(kaynaklar) = 'array' then kaynaklar else '[]'::jsonb end) x
$$;

-- Haritada insanların aradığı türler önde, ofis / hizmet geride.
-- search_path ayarı bilerek yok: SET'li SQL fonksiyonu sorguya gömülemez (inline), satır başına çağrılır (24 bin satırda ~3 sn).
-- İçerik yalnız sabit ifadeler ve şema adıyla yazılmış çağrılar.
create or replace function public.kategori_agirlik(kategori text)
returns smallint language sql immutable parallel safe as $$
  select (case kategori
    when 'restoran' then 15 when 'kafe' then 15 when 'bar' then 15 when 'meyhane' then 15 when 'kahvalti' then 15
    when 'kultur' then 15 when 'tarihi' then 15 when 'avm' then 15
    when 'park_doga' then 10
    when 'konaklama' then 5 when 'hastane' then 5
    when 'market' then 0 when 'eczane' then 0 when 'spor_salonu' then 0 when 'spor_tesisi' then 0
    when 'ibadet' then 0 when 'saglik' then 0 when 'ulasim' then 0
    when 'guzellik' then -5 when 'magaza' then -5 when 'cicekci' then -5 when 'tekel' then -5
    when 'egitim' then -10 when 'kamu' then -10 when 'arac' then -10 when 'finans' then -10
    when 'otopark' then -15
    when 'hizmet' then -20 when 'diger' then -20
    else 0 end)::smallint
$$;

create or replace function public.mekan_populer(skor smallint, kaynak smallint, kategori text)
returns int language sql immutable parallel safe as $$
  select coalesce(skor, 0) + 15 * (greatest(coalesce(kaynak, 1), 1) - 1) + public.kategori_agirlik(kategori)
$$;

-- mekan tetikleyicisi kaynak sayısını da yazar (mekan_ic satırı varsa).
create or replace function public.mekan_nokta_esle() returns trigger
language plpgsql security definer set search_path = public as $$
declare ks smallint;
begin
  if tg_op = 'DELETE' or (tg_op = 'UPDATE' and old.id <> new.id) then
    delete from public.mekan_nokta where id = old.id;
    if tg_op = 'DELETE' then return null; end if;
  end if;
  if new.durum = 'acik' and new.lat is not null and new.lng is not null then
    select public.mekan_kaynak_sayi(i.kaynaklar) into ks from public.mekan_ic i where i.mekan_id = new.id;
    insert into public.mekan_nokta (id, kategori, lat, lng, skor, ilgi, tur, kaynak)
    values (new.id, new.kategori, new.lat, new.lng,
      public.mekan_skor(new.onem, new.guven, new.telefon, new.web, new.adres, new.dogrulanacak),
      public.mekan_ilgi3(new.id, new.osm_ref, new.kategori, new.ad, new.ozellikler, new.onem, new.guven, new.web),
      case when jsonb_typeof(new.ozellikler->'tur') = 'array' then array(select jsonb_array_elements_text(new.ozellikler->'tur')) end,
      coalesce(ks, 1))
    on conflict (id) do update set kategori = excluded.kategori, lat = excluded.lat, lng = excluded.lng,
      skor = excluded.skor, ilgi = excluded.ilgi, tur = excluded.tur, kaynak = excluded.kaynak
    where (mekan_nokta.kategori, mekan_nokta.lat, mekan_nokta.lng, mekan_nokta.skor, mekan_nokta.ilgi, mekan_nokta.tur, mekan_nokta.kaynak)
      is distinct from (excluded.kategori, excluded.lat, excluded.lng, excluded.skor, excluded.ilgi, excluded.tur, excluded.kaynak);
  else
    delete from public.mekan_nokta where id = new.id;
  end if;
  return null;
end $$;

-- mekan_ic değişince (aktarımda kaynak eklenince) nokta tablosundaki kaynak sayısı güncellenir.
create or replace function public.mekan_ic_nokta() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  update public.mekan_nokta p set kaynak = public.mekan_kaynak_sayi(new.kaynaklar)
  where p.id = new.mekan_id and p.kaynak is distinct from public.mekan_kaynak_sayi(new.kaynaklar);
  return null;
end $$;

drop trigger if exists mekan_ic_nokta on public.mekan_ic;
create trigger mekan_ic_nokta after insert or update of kaynaklar on public.mekan_ic
  for each row execute function public.mekan_ic_nokta();

-- İlk doldurma (parça parça, mekan_id sırasıyla; her çağrı bir sonraki başlangıcı döndürür):
--   select public.nokta_kaynak_doldur('', 200000);  -> dönen değerle tekrar, null dönene kadar
create or replace function public.nokta_kaynak_doldur(p_bas text, p_adet int)
returns text language plpgsql security definer set search_path = public as $$
declare son text;
begin
  with c as materialized (
    select i.mekan_id, i.kaynaklar from public.mekan_ic i where i.mekan_id > p_bas order by i.mekan_id limit p_adet),
  u as (
    update public.mekan_nokta p set kaynak = k.ks
    from (select mekan_id, public.mekan_kaynak_sayi(kaynaklar) ks from c) k
    where p.id = k.mekan_id and k.ks > 1 and p.kaynak is distinct from k.ks)
  select max(mekan_id) into son from c;
  return son;
end $$;
revoke all on function public.nokta_kaynak_doldur(text, int) from public, anon, authenticated;

-- Supabase yeni fonksiyonlarda anon'a çalıştırma izni vermiyor: harita_getir anon olarak bunları çağırır.
grant execute on function public.mekan_populer(smallint, smallint, text), public.kategori_agirlik(text), public.mekan_kaynak_sayi(jsonb) to anon, authenticated;
