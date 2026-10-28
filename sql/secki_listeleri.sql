-- Keşif seçkisi: kimsenin hesabına bağlı olmayan, ekibin hazırladığı herkese açık listeler.
-- Keşfet'te "Öne çıkan listeler" rafında görünür (28.10.2026).
-- Seçki listesinde sahip boştur; kullanıcılar RLS yüzünden bu listeleri değiştiremez,
-- yalnız fonksiyonlarla okur. Listeyi ekip SQL ile yönetir.

alter table public.liste alter column sahip drop not null;
alter table public.liste add column if not exists secki_sira smallint;
alter table public.liste add column if not exists aciklama text;
alter table public.liste drop constraint if exists liste_secki_check;
alter table public.liste add constraint liste_secki_check
  check ((sahip is null) = (secki_sira is not null) and (sahip is not null or (tur = 'liste' and gorunurluk = 'herkes')));
alter table public.liste drop constraint if exists liste_aciklama_check;
alter table public.liste add constraint liste_aciklama_check
  check (aciklama is null or char_length(aciklama) between 1 and 300);

-- Kullanıcılar seçki alanlarına yazamasın.
revoke update (secki_sira, aciklama) on public.liste from authenticated, anon;

create or replace function public.liste_getir(p_id uuid)
 returns json language sql stable security definer set search_path to ''
as $function$
  select json_build_object('id', l.id, 'ad', l.ad, 'tur', l.tur, 'gorunurluk', l.gorunurluk, 'guncelleme', l.guncelleme,
    'kullanici_adi', coalesce(p.kullanici_adi, 'kesif'), 'sahip_ad', p.ad, 'benim', l.sahip = auth.uid(),
    'secki', l.sahip is null, 'aciklama', l.aciklama,
    'mekanlar', private.liste_mekanlari_json(l.id), 'yerler', private.liste_yerleri_json(l.id),
    'kayit_sayisi', (select count(*) from public.liste_kayit k where k.liste_id = l.id),
    'kaydettim', exists (select 1 from public.liste_kayit k where k.liste_id = l.id and k.sahip = auth.uid()))
  from public.liste l left join public.profil p on p.id = l.sahip
  where l.id = p_id and (l.gorunurluk in ('herkes', 'baglanti') or l.sahip = auth.uid());
$function$;

create or replace function public.kayitli_listeler()
 returns json language sql stable security definer set search_path to ''
as $function$
  select coalesce(json_agg(
    case when l.gorunurluk in ('herkes', 'baglanti') then
      json_build_object('id', l.id, 'ad', l.ad, 'tur', l.tur, 'erisim', true, 'guncelleme', l.guncelleme,
        'kullanici_adi', coalesce(p.kullanici_adi, 'kesif'), 'sahip_ad', p.ad, 'secki', l.sahip is null, 'kaydetme', k.eklenme,
        'mekanlar', private.liste_mekanlari_json(l.id), 'yerler', private.liste_yerleri_json(l.id))
    else json_build_object('id', l.id, 'erisim', false, 'kullanici_adi', coalesce(p.kullanici_adi, 'kesif'), 'secki', l.sahip is null, 'kaydetme', k.eklenme) end
    order by k.eklenme desc), '[]'::json)
  from public.liste_kayit k
  join public.liste l on l.id = k.liste_id
  left join public.profil p on p.id = l.sahip
  where k.sahip = auth.uid();
$function$;

create or replace function public.liste_kaydet(p_id uuid)
 returns boolean language plpgsql security definer set search_path to ''
as $function$
declare u uuid := auth.uid();
begin
  if u is null or not exists (select 1 from public.profil where id = u) then
    raise exception 'Giriş gerekli' using errcode = '42501';
  end if;
  if not exists (select 1 from public.liste l where l.id = p_id and l.gorunurluk in ('herkes', 'baglanti') and l.sahip is distinct from u) then
    raise exception 'Bu liste kaydedilemez' using errcode = 'P0001', hint = 'liste_kaydedilemez';
  end if;
  if (select count(*) from public.liste_kayit where sahip = u) >= 200 then
    raise exception 'Kayıt sınırı: en çok 200 liste kaydedebilirsin' using errcode = 'P0001', hint = 'kayit_siniri';
  end if;
  insert into public.liste_kayit (sahip, liste_id) values (u, p_id) on conflict do nothing;
  return true;
end $function$;

-- Keşfet rafı: yayındaki seçki listeleri (sıraya göre), açık mekan kimlikleriyle.
create or replace function public.secki_listeleri()
 returns json language sql stable security definer set search_path to ''
as $function$
  select coalesce(json_agg(json_build_object('id', l.id, 'ad', l.ad, 'aciklama', l.aciklama, 'guncelleme', l.guncelleme,
      'mekanlar', private.liste_mekanlari_json(l.id),
      'kayit_sayisi', (select count(*) from public.liste_kayit k where k.liste_id = l.id))
    order by l.secki_sira, l.olusturma), '[]'::json)
  from public.liste l
  where l.sahip is null and l.secki_sira is not null and l.gorunurluk = 'herkes';
$function$;
revoke all on function public.secki_listeleri() from public;
grant execute on function public.secki_listeleri() to anon, authenticated;
