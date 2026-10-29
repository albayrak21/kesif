-- Ziyaret ölçümü (migration olcum_olay, 29.10.2026). Çerez yok, kalıcı kimlik yok, IP tutulmaz.
-- Oturum = sekme başına rastgele kimlik. Tabloyu yalnızca yöneticiler okur; 180 günden eskiler gece silinir.
create table public.olay (
  id bigint generated always as identity primary key,
  zaman timestamptz not null default now(),
  oturum text not null,
  tur text not null,
  veri jsonb not null default '{}'::jsonb
);
create index olay_zaman_idx on public.olay (zaman);
create index olay_oturum_idx on public.olay (oturum, zaman);
create index olay_tur_idx on public.olay (tur, zaman);
alter table public.olay enable row level security;
create policy "olay yonetici okur" on public.olay for select to authenticated using ((select private.yonetici_mi()));
revoke all on public.olay from anon;
revoke insert, update, delete on public.olay from authenticated;
grant select on public.olay to authenticated;   -- satırları RLS süzer: yalnız yöneticiler görür

-- Yazma tek yoldan: en çok 25 olaylık parti, izinli türler, olay başına 1,5 KB,
-- oturum başına saatte 600 ve genel dakikada 3000 olay sınırı.
create or replace function public.olay_yaz(p_oturum text, p_olaylar jsonb)
returns integer language plpgsql security definer set search_path = '' as $$
declare o jsonb; n int := 0;
begin
  if p_oturum is null or p_oturum !~ '^[a-z0-9]{12,32}$' then return 0; end if;
  if jsonb_typeof(p_olaylar) <> 'array' or jsonb_array_length(p_olaylar) > 25 then return 0; end if;
  if (select count(*) from public.olay where oturum = p_oturum and zaman > now() - interval '1 hour') >= 600 then return 0; end if;
  if (select count(*) from public.olay where zaman > now() - interval '1 minute') >= 3000 then return 0; end if;
  for o in select * from jsonb_array_elements(p_olaylar) loop
    continue when jsonb_typeof(o) <> 'object';
    continue when coalesce(o->>'t','') not in ('acilis','arama','filtre','mekan','sekme','paylas','kurulum','hata');
    continue when jsonb_typeof(coalesce(o->'v','{}'::jsonb)) <> 'object' or pg_column_size(coalesce(o->'v','{}'::jsonb)) > 1500;
    insert into public.olay (oturum, tur, veri) values (p_oturum, o->>'t', coalesce(o->'v','{}'::jsonb));
    n := n + 1;
  end loop;
  return n;
end $$;
revoke all on function public.olay_yaz(text, jsonb) from public;
grant execute on function public.olay_yaz(text, jsonb) to anon, authenticated;

-- Özet: select olay_ozet(7);  (yalnız yöneticiler; tam tanım veritabanında)
-- oturum, gunluk, cihaz, ziyaretci, uygulama, giris, sonucsuz_aramalar, sik_aramalar,
-- kategoriler, filtreler, sekmeler, mekan_acilis, paylasim, kurulum, hata

select cron.schedule('olay-temizle', '17 2 * * *', $c$delete from public.olay where zaman < now() - interval '180 days'$c$);
