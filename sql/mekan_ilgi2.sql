-- Öne çıkan puanı, 2. sürüm (28.10.2026): kaynak güveni eklendi.
-- Wikidata'dan gelen kayıtlar (kimlik "wd-") bilinen yerlerdir: +15. OSM kaydı +3. Yalnız Overture / Foursquare kaynaklı -10
-- (ör. müze diye işaretlenmiş mağaza ve showroom'lar). Müze puanı düşürüldü, doğa ve seyir noktaları yükseltildi.
create or replace function public.mekan_ilgi2(id text, osm_ref text, kategori text, oz jsonb, onem smallint, guven real, web text)
returns smallint language sql immutable parallel safe set search_path = '' as $$
  select (case when b.t = 0 or coalesce(oz->>'adsiz', '') = 'true' then 0 else greatest(1, b.t
    + case when id like 'wd-%' then 15 when osm_ref is not null then 3 when id like '%-ov-%' or id like 'fsq-%' then -10 else 0 end
    + case when coalesce(web, '') <> '' then 3 else 0 end
    + case when oz ? 'koruma' or oz ? 'yapim_yili' then 5 else 0 end
    + case when coalesce(onem, 0) >= 80 then 5 else 0 end
    + round((coalesce(guven, 0.75) - 0.75) * 20)::int) end)::smallint
  from (select case kategori
      when 'tarihi' then case
        when oz->'tur' ?| array['muze','saray_kosk','kale_sur','arkeoloji'] then 90
        when oz->'tur' ?| array['dini','carsi_han','anit','park_meydan'] then 85
        else 75 end
      when 'kultur' then case
        when oz->'tur' ? 'muze' then 80
        when oz->'tur' ? 'hayvanat_bahcesi' then 65
        else 0 end
      when 'park_doga' then case
        when oz->'tur' ?| array['seyir_noktasi','doga_alani'] then 85
        when oz->'tur' ? 'meydan' then 80
        when oz->'tur' ? 'plaj_sahil' then 75
        when oz->'tur' ? 'yuruyus_yolu' then 50
        when oz->'tur' ?| array['park','piknik_alani'] then 45
        when oz->'tur' ? 'bahce' then 40
        else 0 end
      when 'diger' then case
        when oz->'tur' ?| array['tarihi_kalinti','tarihi_yer'] then 75
        when oz->'tur' ? 'anit' then 65
        when oz->'tur' ? 'anit_hatira' then 55
        else 0 end
      when 'ibadet' then case
        when coalesce(onem, 0) >= 80 then 85
        when oz->'tur' ? 'kilise' then 45
        else 0 end
      when 'avm' then 40
      when 'spor_tesisi' then case when oz->'tur' ? 'stadyum' then 45 else 0 end
      else 0 end as t) b
$$;
grant execute on function public.mekan_ilgi2(text, text, text, jsonb, smallint, real, text) to anon, authenticated;

create or replace function public.mekan_nokta_esle() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if tg_op = 'DELETE' or (tg_op = 'UPDATE' and old.id <> new.id) then
    delete from public.mekan_nokta where id = old.id;
    if tg_op = 'DELETE' then return null; end if;
  end if;
  if new.durum = 'acik' and new.lat is not null and new.lng is not null then
    insert into public.mekan_nokta (id, kategori, lat, lng, skor, ilgi, tur)
    values (new.id, new.kategori, new.lat, new.lng,
      public.mekan_skor(new.onem, new.guven, new.telefon, new.web, new.adres, new.dogrulanacak),
      public.mekan_ilgi2(new.id, new.osm_ref, new.kategori, new.ozellikler, new.onem, new.guven, new.web),
      case when jsonb_typeof(new.ozellikler->'tur') = 'array' then array(select jsonb_array_elements_text(new.ozellikler->'tur')) end)
    on conflict (id) do update set kategori = excluded.kategori, lat = excluded.lat, lng = excluded.lng,
      skor = excluded.skor, ilgi = excluded.ilgi, tur = excluded.tur
    where (mekan_nokta.kategori, mekan_nokta.lat, mekan_nokta.lng, mekan_nokta.skor, mekan_nokta.ilgi, mekan_nokta.tur)
      is distinct from (excluded.kategori, excluded.lat, excluded.lng, excluded.skor, excluded.ilgi, excluded.tur);
  else
    delete from public.mekan_nokta where id = new.id;
  end if;
  return null;
end $$;

-- Mevcut noktaların puanı yeniden: yalnız puan alabilecek kategoriler (diger'de yalnız tarihi türler).
create or replace function public.nokta_ilgi_yenile() returns int
language plpgsql set search_path = public as $$
declare n int;
begin
  update mekan_nokta p set ilgi = x.yeni
  from (select m.id, mekan_ilgi2(m.id, m.osm_ref, m.kategori, m.ozellikler, m.onem, m.guven, m.web) yeni
        from mekan_nokta q join mekan m on m.id = q.id
        where q.kategori in ('tarihi','kultur','park_doga','ibadet','avm','spor_tesisi')
           or (q.kategori = 'diger' and q.tur && array['tarihi_kalinti','tarihi_yer','anit','anit_hatira'])) x
  where p.id = x.id and p.ilgi is distinct from x.yeni;
  get diagnostics n = row_count;
  return n;
end $$;
