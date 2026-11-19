-- GEÇİCİ (test dönemi), migration konum_kayit_test, 19.11.2026. Yayından önce kaldırılacak (en altta).
-- Konum düğmesini açan ziyaretçinin tam konumu. Yalnızca yöneticiler okur; 30 günden eskiler gece silinir.
create table public.konum_kayit (
  id bigint generated always as identity primary key,
  zaman timestamptz not null default now(),
  oturum text not null,
  lat double precision not null,
  lng double precision not null,
  dogruluk real,
  cihaz text
);
create index konum_kayit_zaman_idx on public.konum_kayit (zaman);
create index konum_kayit_oturum_idx on public.konum_kayit (oturum, zaman);
alter table public.konum_kayit enable row level security;
create policy "konum yonetici okur" on public.konum_kayit for select to authenticated using ((select private.yonetici_mi()));
revoke all on public.konum_kayit from anon, authenticated;
grant select on public.konum_kayit to authenticated;

-- Yazma tek yoldan: oturum başına 30 sn'de bir ve günde 300, genel dakikada 600.
create or replace function public.konum_yaz(p_oturum text, p_lat double precision, p_lng double precision, p_dogruluk real, p_cihaz text)
returns boolean language plpgsql security definer set search_path = '' as $$
begin
  if p_oturum is null or p_oturum !~ '^[a-z0-9]{12,32}$' then return false; end if;
  if p_lat is null or p_lng is null or p_lat not between -90 and 90 or p_lng not between -180 and 180 then return false; end if;
  if exists (select 1 from public.konum_kayit where oturum = p_oturum and zaman > now() - interval '30 seconds') then return false; end if;
  if (select count(*) from public.konum_kayit where oturum = p_oturum and zaman > now() - interval '1 day') >= 300 then return false; end if;
  if (select count(*) from public.konum_kayit where zaman > now() - interval '1 minute') >= 600 then return false; end if;
  insert into public.konum_kayit (oturum, lat, lng, dogruluk, cihaz)
  values (p_oturum, p_lat, p_lng, least(greatest(coalesce(p_dogruluk, 0), 0), 100000),
          case when p_cihaz in ('telefon','tablet','masaustu') then p_cihaz end);
  return true;
end $$;
revoke all on function public.konum_yaz(text, double precision, double precision, real, text) from public;
grant execute on function public.konum_yaz(text, double precision, double precision, real, text) to anon, authenticated;

select cron.schedule('konum-temizle', '23 2 * * *', $c$delete from public.konum_kayit where zaman < now() - interval '30 days'$c$);

-- YAYINDAN ÖNCE KALDIRMA (index.html'deki konumKaydet ve yonetim.html'deki Konumlar sekmesiyle birlikte):
-- select cron.unschedule('konum-temizle');
-- drop function public.konum_yaz(text, double precision, double precision, real, text);
-- drop table public.konum_kayit;
