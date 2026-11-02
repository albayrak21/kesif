-- Ek kategoriler (02.11.2026, Emre: "restoran olarak da çıksınlar, ikisi beraber olmaz mı?").
-- Bir mekanın tek ana kategorisi (mekan.kategori) ve isteğe bağlı ek kategorileri olur: mekan.ozellikler.ek_kategori
-- (ör. ["restoran"]). Ek kategoride de listelenir, aranır, filtrelenir; kartta ve sayfada ana kategoriyle görünür.
-- Özelliklerin içinde tutulması: kaydı okuyan her yol (REST, harita_getir, yönetim) ek bilgiyi kendiliğinden taşır.
-- Harita sorgusu için dar tablo mekan_nokta_ek (kategori, lat, lng) indeksiyle; mekan_nokta_esle tetikleyicisi günceller.
-- Ek satırlarda tur boş: tür kodları ana kategoriye ait (otelin türü restoran mutfak sayımına girmesin).
-- Bu dosya mekan_nokta_esle'nin güncel sürümüdür (populer.sql'deki sürümün yerine).

create table if not exists public.mekan_nokta_ek (
  id text not null,
  kategori text not null,
  lat float8 not null,
  lng float8 not null,
  skor smallint not null,
  ilgi smallint not null,
  kaynak smallint not null default 1,
  primary key (id, kategori)
);
create index if not exists mekan_nokta_ek_kat_konum_idx on public.mekan_nokta_ek (kategori, lat, lng) include (skor, ilgi, kaynak, id);
alter table public.mekan_nokta_ek enable row level security;
drop policy if exists "nokta ek herkese acik okunur" on public.mekan_nokta_ek;
create policy "nokta ek herkese acik okunur" on public.mekan_nokta_ek for select to anon, authenticated using (true);
grant select on public.mekan_nokta_ek to anon, authenticated;

create or replace function public.mekan_ek_kategoriler(oz jsonb, ana text)
returns text[] language sql immutable parallel safe set search_path = '' as $$
  select coalesce(array_agg(distinct k), '{}') from jsonb_array_elements_text(
    case when jsonb_typeof(oz->'ek_kategori') = 'array' then oz->'ek_kategori' else '[]'::jsonb end) k
  where k <> ana and k ~ '^[a-z_]+$'
$$;
grant execute on function public.mekan_ek_kategoriler(jsonb, text) to anon, authenticated;

create or replace function public.mekan_nokta_esle() returns trigger
language plpgsql security definer set search_path = public as $$
declare ks smallint; sk smallint; il smallint; ekler text[];
begin
  if tg_op = 'DELETE' or (tg_op = 'UPDATE' and old.id <> new.id) then
    delete from public.mekan_nokta where id = old.id;
    delete from public.mekan_nokta_ek where id = old.id;
    if tg_op = 'DELETE' then return null; end if;
  end if;
  if new.durum = 'acik' and new.lat is not null and new.lng is not null then
    select public.mekan_kaynak_sayi(i.kaynaklar) into ks from public.mekan_ic i where i.mekan_id = new.id;
    sk := public.mekan_skor(new.onem, new.guven, new.telefon, new.web, new.adres, new.dogrulanacak);
    il := public.mekan_ilgi3(new.id, new.osm_ref, new.kategori, new.ad, new.ozellikler, new.onem, new.guven, new.web);
    insert into public.mekan_nokta (id, kategori, lat, lng, skor, ilgi, tur, kaynak)
    values (new.id, new.kategori, new.lat, new.lng, sk, il,
      case when jsonb_typeof(new.ozellikler->'tur') = 'array' then array(select jsonb_array_elements_text(new.ozellikler->'tur')) end,
      coalesce(ks, 1))
    on conflict (id) do update set kategori = excluded.kategori, lat = excluded.lat, lng = excluded.lng,
      skor = excluded.skor, ilgi = excluded.ilgi, tur = excluded.tur, kaynak = excluded.kaynak
    where (mekan_nokta.kategori, mekan_nokta.lat, mekan_nokta.lng, mekan_nokta.skor, mekan_nokta.ilgi, mekan_nokta.tur, mekan_nokta.kaynak)
      is distinct from (excluded.kategori, excluded.lat, excluded.lng, excluded.skor, excluded.ilgi, excluded.tur, excluded.kaynak);
    -- Ek kategoriler (çoğu kayıtta yok: yalnız varsa ya da önceden vardıysa dokunulur).
    ekler := public.mekan_ek_kategoriler(new.ozellikler, new.kategori);
    if cardinality(ekler) > 0 or (tg_op = 'UPDATE' and old.ozellikler ? 'ek_kategori') then
      delete from public.mekan_nokta_ek e where e.id = new.id and not (e.kategori = any(ekler));
      insert into public.mekan_nokta_ek (id, kategori, lat, lng, skor, ilgi, kaynak)
      select new.id, k, new.lat, new.lng, sk, il, coalesce(ks, 1) from unnest(ekler) k
      on conflict (id, kategori) do update set lat = excluded.lat, lng = excluded.lng, skor = excluded.skor,
        ilgi = excluded.ilgi, kaynak = excluded.kaynak;
    end if;
  else
    delete from public.mekan_nokta where id = new.id;
    if tg_op = 'UPDATE' and old.ozellikler ? 'ek_kategori' then delete from public.mekan_nokta_ek where id = new.id; end if;
  end if;
  return null;
end $$;

create or replace function public.mekan_ic_nokta() returns trigger
language plpgsql security definer set search_path = public as $$
declare ks smallint := public.mekan_kaynak_sayi(new.kaynaklar);
begin
  update public.mekan_nokta p set kaynak = ks where p.id = new.mekan_id and p.kaynak is distinct from ks;
  update public.mekan_nokta_ek p set kaynak = ks where p.id = new.mekan_id and p.kaynak is distinct from ks;
  return null;
end $$;
