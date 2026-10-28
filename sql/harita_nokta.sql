-- Harita öncelikli mod: dar nokta tablosu, skor ve öne çıkan (ilgi) puanı.
-- mekan'a kolon eklemek tabloyu yeniden yazardı (1,3 GB); bunun yerine harita sorguları
-- yalnız gerekli alanları tutan dar tabloya gider. mekan'daki tetikleyici onu güncel tutar.

-- Genel skor (aramada ve kategoride sıralama): önem + Overture güveni + bilgi doluluğu.
create or replace function public.mekan_skor(onem smallint, guven real, telefon text, web text, adres text, dogrulanacak text[])
returns smallint language sql immutable parallel safe set search_path = '' as $$
  select (coalesce(onem, 40)::int
    + round(coalesce(guven, 0.75) * 20)::int
    + case when coalesce(telefon, '') <> '' then 5 else 0 end
    + case when coalesce(web, '') <> '' then 5 else 0 end
    + case when adres ~ '[0-9]' and not ('adres_yaklasik' = any(coalesce(dogrulanacak, '{}'::text[]))) then 3 else 0 end)::smallint
$$;

-- Öne çıkan puanı (aramasız gezinmede): 0 = öne çıkmaz. Tarihi yapılar, müzeler, doğal güzellikler,
-- seyir noktaları, meydanlar; parklar düşük puanla (yalnız çevresinde daha iyisi yoksa).
create or replace function public.mekan_ilgi(kategori text, oz jsonb, onem smallint, guven real, web text)
returns smallint language sql immutable parallel safe set search_path = '' as $$
  select (case when b.t = 0 or coalesce(oz->>'adsiz', '') = 'true' then 0 else greatest(1, b.t
    + case when coalesce(web, '') <> '' then 3 else 0 end
    + case when oz ? 'koruma' or oz ? 'yapim_yili' then 5 else 0 end
    + case when coalesce(onem, 0) >= 80 then 5 else 0 end
    + round((coalesce(guven, 0.75) - 0.75) * 20)::int) end)::smallint
  from (select case kategori
      when 'tarihi' then case
        when oz->'tur' ?| array['muze','saray_kosk','kale_sur','arkeoloji'] then 95
        when oz->'tur' ?| array['dini','carsi_han','anit','park_meydan'] then 85
        else 75 end
      when 'kultur' then case
        when oz->'tur' ? 'muze' then 90
        when oz->'tur' ? 'hayvanat_bahcesi' then 70
        else 0 end
      when 'park_doga' then case
        when oz->'tur' ? 'seyir_noktasi' then 80
        when oz->'tur' ?| array['doga_alani','plaj_sahil','meydan'] then 75
        when oz->'tur' ? 'yuruyus_yolu' then 50
        when oz->'tur' ?| array['park','piknik_alani'] then 45
        when oz->'tur' ? 'bahce' then 40
        else 0 end
      when 'diger' then case
        when oz->'tur' ?| array['tarihi_kalinti','tarihi_yer'] then 70
        when oz->'tur' ? 'anit' then 65
        when oz->'tur' ? 'anit_hatira' then 60
        else 0 end
      when 'ibadet' then case
        when coalesce(onem, 0) >= 80 then 85
        when oz->'tur' ? 'kilise' then 45
        else 0 end
      when 'avm' then 40
      when 'spor_tesisi' then case when oz->'tur' ? 'stadyum' then 45 else 0 end
      else 0 end as t) b
$$;

create table if not exists public.mekan_nokta (
  id text primary key,
  kategori text not null,
  lat float8 not null,
  lng float8 not null,
  skor smallint not null,
  ilgi smallint not null,
  tur text[]
);
alter table public.mekan_nokta enable row level security;
create policy "nokta herkese acik okunur" on public.mekan_nokta for select to anon, authenticated using (true);
grant select on public.mekan_nokta to anon, authenticated;

-- Tetikleyici: açık ve konumlu kayıtlar nokta tablosunda; kapanan / silinen çıkar.
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
      public.mekan_ilgi(new.kategori, new.ozellikler, new.onem, new.guven, new.web),
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

create trigger mekan_nokta_esle after insert or update or delete on public.mekan
  for each row execute function public.mekan_nokta_esle();
