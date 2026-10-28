-- Etiketler (29.10.2026)
-- İki tür etiket:
--   resmi     : güvenilir kaynaktan (ör. Michelin Rehberi). Yalnız yöneticiler ekler; her satırda kaynak ve doğrulama tarihi.
--   topluluk  : kullanıcıların hazır listeden eklediği (ör. "Şık"). Bir mekânda en az `esik` kişi ekleyince herkese görünür.
-- Görünen etiket kodları mekan.ozellikler->'etiket' dizisine yazılır (tetikleyiciyle): kart, filtre ve sayımlar
-- var olan özellik altyapısını kullanır. Kaynak tablolar mekan_etiket ve etiket_oy'dur; ozellikler.etiket türetilmiş alandır.

create or replace function public.duz_metin(t text) returns text
language sql immutable parallel safe set search_path = public, pg_catalog as $$
  select btrim(regexp_replace(lower(translate(coalesce(t, ''), 'ÇĞİIÖŞÜÂÎÛçğıöşüâîû', 'cgiiosuaiucgiosuaiu')), '[^a-z0-9]+', ' ', 'g'))
$$;

create table if not exists public.etiket (
  kod text primary key check (kod ~ '^[a-z0-9_]+$'),
  ad text not null,
  grup text,                         -- ör. 'michelin', 'atmosfer' (filtrede ve sayfada gruplamak için)
  tur text not null check (tur in ('resmi', 'topluluk')),
  es_anlam text[] not null default '{}',   -- aramada eşleşen diğer adlar (ör. 'michelin', 'yildizli')
  aciklama text,
  kategoriler text[],                -- null: her kategoride
  esik smallint not null default 3,  -- topluluk etiketinin görünmesi için gereken kişi sayısı
  sira smallint not null default 100,
  aktif boolean not null default true,
  olusturma timestamptz not null default now()
);

create table if not exists public.mekan_etiket (
  mekan_id text not null references public.mekan(id) on delete cascade,
  etiket text not null references public.etiket(kod) on update cascade,
  deger text,                        -- isteğe bağlı ayrıntı
  kaynak text not null,              -- ör. 'Michelin Rehberi Türkiye 2026'
  kaynak_url text,
  dogrulama_tarihi date not null default current_date,
  ekleyen uuid default auth.uid(),
  olusturma timestamptz not null default now(),
  primary key (mekan_id, etiket)
);
create index if not exists mekan_etiket_etiket_idx on public.mekan_etiket (etiket);

create table if not exists public.etiket_oy (
  mekan_id text not null references public.mekan(id) on delete cascade,
  etiket text not null references public.etiket(kod) on update cascade,
  kullanici uuid not null default auth.uid() references auth.users(id) on delete cascade,
  olusturma timestamptz not null default now(),
  primary key (mekan_id, etiket, kullanici)
);
create index if not exists etiket_oy_etiket_idx on public.etiket_oy (etiket, mekan_id);
create index if not exists etiket_oy_kullanici_idx on public.etiket_oy (kullanici);

create table if not exists public.etiket_oneri (
  id bigint generated always as identity primary key,
  kullanici uuid not null default auth.uid() references auth.users(id) on delete cascade,
  ad text not null check (char_length(btrim(ad)) between 2 and 40),
  mekan_id text references public.mekan(id) on delete set null,
  durum text not null default 'bekliyor' check (durum in ('bekliyor', 'eklendi', 'reddedildi')),
  olusturma timestamptz not null default now()
);

-- Görünen etiketler (küçük tablolardan; arama ve sayfa için)
create or replace view public.etiket_gorunur with (security_invoker = false) as
  select me.mekan_id, me.etiket from public.mekan_etiket me join public.etiket e on e.kod = me.etiket and e.aktif
  union
  select o.mekan_id, o.etiket from public.etiket_oy o join public.etiket e on e.kod = o.etiket and e.aktif and e.tur = 'topluluk'
  group by o.mekan_id, o.etiket, e.esik having count(*) >= e.esik;

-- mekan.ozellikler.etiket'i yeniden yazar (yalnız değiştiyse)
create or replace function public.etiket_yenile(p_mekan text) returns void
language plpgsql security definer set search_path = public as $$
declare yeni jsonb; eski jsonb;
begin
  select coalesce(jsonb_agg(g.etiket order by e.sira, g.etiket), '[]') into yeni
    from etiket_gorunur g join etiket e on e.kod = g.etiket where g.mekan_id = p_mekan;
  select ozellikler->'etiket' into eski from mekan where id = p_mekan;
  if coalesce(eski, '[]') is distinct from yeni then
    update mekan set ozellikler = case when yeni = '[]' then ozellikler - 'etiket' else jsonb_set(ozellikler, '{etiket}', yeni) end
      where id = p_mekan;
  end if;
end $$;
revoke all on function public.etiket_yenile(text) from public, anon, authenticated;

create or replace function public.etiket_tetik() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if tg_op in ('DELETE', 'UPDATE') then perform etiket_yenile(old.mekan_id); end if;
  if tg_op in ('INSERT', 'UPDATE') and (tg_op = 'INSERT' or new.mekan_id <> old.mekan_id) then perform etiket_yenile(new.mekan_id); end if;
  return null;
end $$;
drop trigger if exists mekan_etiket_tetik on public.mekan_etiket;
create trigger mekan_etiket_tetik after insert or update or delete on public.mekan_etiket for each row execute function public.etiket_tetik();
drop trigger if exists etiket_oy_tetik on public.etiket_oy;
create trigger etiket_oy_tetik after insert or update or delete on public.etiket_oy for each row execute function public.etiket_tetik();

-- Etiket tanımı (eşik, aktiflik) değişince o etiketi taşıyan / oylanan yerler yenilenir
create or replace function public.etiket_tanim_tetik() returns trigger
language plpgsql security definer set search_path = public as $$
declare r record;
begin
  if new.esik is distinct from old.esik or new.aktif is distinct from old.aktif then
    for r in select mekan_id from mekan_etiket where etiket = new.kod union select mekan_id from etiket_oy where etiket = new.kod loop
      perform etiket_yenile(r.mekan_id);
    end loop;
  end if;
  return null;
end $$;
drop trigger if exists etiket_tanim_tetik on public.etiket;
create trigger etiket_tanim_tetik after update on public.etiket for each row execute function public.etiket_tanim_tetik();

-- Bir mekânın etiket durumu (sayfa için): resmi etiketler kaynağıyla, topluluk etiketleri sayı ve "ben ekledim mi" ile
create or replace function public.mekan_etiketleri(p_mekan text) returns jsonb
language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
    'resmi', coalesce((select jsonb_agg(jsonb_build_object('etiket', me.etiket, 'kaynak', me.kaynak, 'kaynak_url', me.kaynak_url,
                        'dogrulama_tarihi', me.dogrulama_tarihi, 'deger', me.deger) order by e.sira)
                       from mekan_etiket me join etiket e on e.kod = me.etiket and e.aktif where me.mekan_id = p_mekan), '[]'),
    'topluluk', coalesce((select jsonb_agg(jsonb_build_object('etiket', o.etiket, 'sayi', o.n, 'benim', o.benim, 'esik', o.esik))
                       from (select o.etiket, count(*) n, bool_or(o.kullanici = auth.uid()) benim, min(e.esik) esik
                             from etiket_oy o join etiket e on e.kod = o.etiket and e.aktif and e.tur = 'topluluk'
                             where o.mekan_id = p_mekan group by o.etiket) o), '[]'))
$$;

-- RLS
alter table public.etiket enable row level security;
alter table public.mekan_etiket enable row level security;
alter table public.etiket_oy enable row level security;
alter table public.etiket_oneri enable row level security;

drop policy if exists etiket_oku on public.etiket;
create policy etiket_oku on public.etiket for select to anon, authenticated using (true);
drop policy if exists etiket_yonetici on public.etiket;
create policy etiket_yonetici on public.etiket for all to authenticated
  using ((select private.yonetici_mi())) with check ((select private.yonetici_mi()));

drop policy if exists mekan_etiket_oku on public.mekan_etiket;
create policy mekan_etiket_oku on public.mekan_etiket for select to anon, authenticated using (true);
drop policy if exists mekan_etiket_yonetici on public.mekan_etiket;
create policy mekan_etiket_yonetici on public.mekan_etiket for all to authenticated
  using ((select private.yonetici_mi())) with check ((select private.yonetici_mi()));

drop policy if exists etiket_oy_kendi_oku on public.etiket_oy;
create policy etiket_oy_kendi_oku on public.etiket_oy for select to authenticated using (kullanici = (select auth.uid()));
drop policy if exists etiket_oy_kendi_ekle on public.etiket_oy;
create policy etiket_oy_kendi_ekle on public.etiket_oy for insert to authenticated
  with check (kullanici = (select auth.uid())
              and exists (select 1 from public.etiket e where e.kod = etiket and e.tur = 'topluluk' and e.aktif));
drop policy if exists etiket_oy_kendi_sil on public.etiket_oy;
create policy etiket_oy_kendi_sil on public.etiket_oy for delete to authenticated using (kullanici = (select auth.uid()));

drop policy if exists etiket_oneri_ekle on public.etiket_oneri;
create policy etiket_oneri_ekle on public.etiket_oneri for insert to authenticated
  with check (kullanici = (select auth.uid()) and durum = 'bekliyor');
drop policy if exists etiket_oneri_oku on public.etiket_oneri;
create policy etiket_oneri_oku on public.etiket_oneri for select to authenticated
  using (kullanici = (select auth.uid()) or (select private.yonetici_mi()));
drop policy if exists etiket_oneri_yonetici on public.etiket_oneri;
create policy etiket_oneri_yonetici on public.etiket_oneri for update to authenticated
  using ((select private.yonetici_mi())) with check ((select private.yonetici_mi()));

grant select on public.etiket, public.mekan_etiket to anon, authenticated;
grant insert, update, delete on public.etiket, public.mekan_etiket to authenticated;
grant select, insert, delete on public.etiket_oy to authenticated;
grant select, insert, update on public.etiket_oneri to authenticated;
revoke all on public.etiket_gorunur from anon, authenticated;
grant execute on function public.mekan_etiketleri(text) to anon, authenticated;

-- Başlangıç etiketleri
insert into public.etiket (kod, ad, grup, tur, es_anlam, aciklama, kategoriler, sira) values
  ('michelin_3_yildiz', '3 Michelin Yıldızı', 'michelin', 'resmi', '{michelin,michelin rehberi,michelin yildizli,yildizli}', 'Michelin Rehberi: olağanüstü mutfak, özel bir yolculuğa değer.', '{restoran,meyhane,kahvalti,kafe,bar,konaklama,diger}', 10),
  ('michelin_2_yildiz', '2 Michelin Yıldızı', 'michelin', 'resmi', '{michelin,michelin rehberi,michelin yildizli,yildizli}', 'Michelin Rehberi: mükemmel mutfak, yolunuzu değiştirmeye değer.', '{restoran,meyhane,kahvalti,kafe,bar,konaklama,diger}', 11),
  ('michelin_1_yildiz', '1 Michelin Yıldızı', 'michelin', 'resmi', '{michelin,michelin rehberi,michelin yildizli,yildizli}', 'Michelin Rehberi: yüksek kaliteli mutfak, durmaya değer.', '{restoran,meyhane,kahvalti,kafe,bar,konaklama,diger}', 12),
  ('michelin_yesil_yildiz', 'Michelin Yeşil Yıldız', 'michelin', 'resmi', '{michelin,michelin rehberi,yesil yildiz,surdurulebilir}', 'Michelin Rehberi: sürdürülebilir gastronomide öncü.', '{restoran,meyhane,kahvalti,kafe,bar,konaklama,diger}', 13),
  ('michelin_bib_gourmand', 'Michelin Bib Gourmand', 'michelin', 'resmi', '{michelin,michelin rehberi,bib gourmand}', 'Michelin Rehberi: fiyatına göre iyi yemek.', '{restoran,meyhane,kahvalti,kafe,bar,konaklama,diger}', 14),
  ('michelin_rehber', 'Michelin Rehberi', 'michelin', 'resmi', '{michelin,michelin rehberi}', 'Michelin Rehberi seçkisinde (yıldızsız).', '{restoran,meyhane,kahvalti,kafe,bar,konaklama,diger}', 15),
  ('sik', 'Şık', 'atmosfer', 'topluluk', '{}', 'Kullanıcılar bu yeri şık buluyor.', '{restoran,meyhane,kahvalti,kafe,bar,konaklama}', 50)
on conflict (kod) do nothing;
-- Türkiye'de henüz 3 yıldızlı yok: filtrede boş seçenek görünmesin diye kapalı (yönetimden açılır).
update public.etiket set aktif = false where kod = 'michelin_3_yildiz';

-- Arama için: verilen etiketleri (görünür olarak) taşıyan mekânların kimlikleri. Topluluk oyları anon'a kapalı olduğu için definer.
create or replace function public.etiket_mekanlari(p_etiketler text[]) returns text[]
language sql stable security definer set search_path = public as $$
  select case when p_etiketler is null or cardinality(p_etiketler) = 0 then null
              else (select array_agg(distinct g.mekan_id) from etiket_gorunur g where g.etiket = any(p_etiketler)) end
$$;
grant execute on function public.etiket_mekanlari(text[]) to anon, authenticated;

-- Arama sıralaması için: etiketleri taşıyan mekânlar ve en öndeki eşleşen etiketin sırası (küçük = önce).
create or replace function public.etiket_mekan_sira(p_etiketler text[]) returns table (mekan_id text, sira int)
language sql stable security definer set search_path = public as $$
  select g.mekan_id, min(e.sira)::int from etiket_gorunur g join etiket e on e.kod = g.etiket
  where g.etiket = any(p_etiketler) group by g.mekan_id
$$;
grant execute on function public.etiket_mekan_sira(text[]) to anon, authenticated;
grant execute on function public.duz_metin(text) to anon, authenticated;

-- Filtre sayıları için: görünen (mekan, etiket) çiftleri.
create or replace function public.etiket_ciftleri() returns table (mekan_id text, etiket text)
language sql stable security definer set search_path = public as $$
  select g.mekan_id, g.etiket from etiket_gorunur g
$$;
grant execute on function public.etiket_ciftleri() to anon, authenticated;
