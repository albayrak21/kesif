-- Profil fotoğrafı + hesap silme (migration `profil_foto_hesap_sil`, 02.11.2026)
-- Foto herkese açık (Emre kararı). Yol: profil-foto/<kullanıcı uuid>/<uuid>.webp, 512 px kare WebP (tarayıcıda hazırlanır, EXIF yok).

alter table public.profil add column if not exists foto text;
alter table public.profil drop constraint if exists profil_foto_yol;
alter table public.profil add constraint profil_foto_yol
  check (foto is null or foto ~ ('^' || id::text || '/[0-9a-f-]{36}\.webp$'));
grant update (foto) on public.profil to authenticated;

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('profil-foto', 'profil-foto', true, 1048576, array['image/webp'])
on conflict (id) do update set public = true, file_size_limit = 1048576, allowed_mime_types = array['image/webp'];

drop policy if exists "profil-foto kendi yukler" on storage.objects;
drop policy if exists "profil-foto kendi okur" on storage.objects;
drop policy if exists "profil-foto kendi siler" on storage.objects;
create policy "profil-foto kendi yukler" on storage.objects for insert to authenticated
  with check (bucket_id = 'profil-foto' and (storage.foldername(name))[1] = (select auth.uid())::text);
create policy "profil-foto kendi okur" on storage.objects for select to authenticated
  using (bucket_id = 'profil-foto' and (storage.foldername(name))[1] = (select auth.uid())::text);
create policy "profil-foto kendi siler" on storage.objects for delete to authenticated
  using (bucket_id = 'profil-foto' and (storage.foldername(name))[1] = (select auth.uid())::text);

-- Başkalarını okuyan fonksiyonlar fotoğrafı da döndürür.
create or replace function public.profil_getir(p_kullanici_adi text)
 returns json language sql stable security definer set search_path to ''
as $function$
  select json_build_object(
    'kullanici_adi', p.kullanici_adi, 'ad', p.ad, 'foto', p.foto, 'olusturma', p.olusturma, 'benim', p.id = auth.uid(),
    'listeler', coalesce((
      select json_agg(json_build_object('id', l.id, 'ad', l.ad, 'tur', l.tur, 'guncelleme', l.guncelleme,
        'mekanlar', private.liste_mekanlari_json(l.id), 'yerler', private.liste_yerleri_json(l.id),
        'kayit_sayisi', (select count(*) from public.liste_kayit k where k.liste_id = l.id),
        'kaydettim', exists (select 1 from public.liste_kayit k where k.liste_id = l.id and k.sahip = auth.uid()))
        order by (l.tur = 'favori') desc, l.olusturma)
      from public.liste l where l.sahip = p.id and l.gorunurluk = 'herkes'), '[]'::json))
  from public.profil p
  where p.kullanici_adi = lower(ltrim(btrim(coalesce(p_kullanici_adi, '')), '@'));
$function$;

drop function if exists public.kullanici_ara(text);
create function public.kullanici_ara(p_metin text)
 returns table(kullanici_adi text, ad text, liste_sayisi integer, foto text)
 language sql stable security definer set search_path to ''
as $function$
  with q as (select lower(ltrim(btrim(coalesce(p_metin, '')), '@')) as m)
  select p.kullanici_adi, p.ad,
    (select count(*)::integer from public.liste l where l.sahip = p.id and l.gorunurluk = 'herkes'), p.foto
  from public.profil p, q
  where char_length(q.m) >= 2
    and (p.kullanici_adi like replace(replace(q.m, '_', '\_'), '%', '\%') || '%'
      or position(q.m in p.kullanici_adi) > 0
      or position(q.m in lower(coalesce(p.ad, ''))) > 0)
  order by (p.kullanici_adi = q.m) desc, (p.kullanici_adi like replace(replace(q.m, '_', '\_'), '%', '\%') || '%') desc, p.kullanici_adi
  limit 20;
$function$;
grant execute on function public.kullanici_ara(text) to anon, authenticated;

create or replace function public.liste_getir(p_id uuid)
 returns json language sql stable security definer set search_path to ''
as $function$
  select json_build_object('id', l.id, 'ad', l.ad, 'tur', l.tur, 'gorunurluk', l.gorunurluk, 'guncelleme', l.guncelleme,
    'kullanici_adi', coalesce(p.kullanici_adi, 'kesif'), 'sahip_ad', p.ad, 'sahip_foto', p.foto, 'benim', l.sahip = auth.uid(),
    'secki', l.sahip is null, 'aciklama', l.aciklama,
    'mekanlar', private.liste_mekanlari_json(l.id), 'yerler', private.liste_yerleri_json(l.id),
    'kayit_sayisi', (select count(*) from public.liste_kayit k where k.liste_id = l.id),
    'kaydettim', exists (select 1 from public.liste_kayit k where k.liste_id = l.id and k.sahip = auth.uid()))
  from public.liste l left join public.profil p on p.id = l.sahip
  where l.id = p_id and (l.gorunurluk in ('herkes', 'baglanti') or l.sahip = auth.uid());
$function$;

-- Hesabı sil: auth.users satırı silinir; profil, listeler, kişisel yerler, kayıtlar, etiket oyları, sahiplikler zincirleme silinir.
-- Fotoğraf dosyası istemci tarafından önce silinir (storage dosyaları SQL ile silinmez). Yönetici hesapları buradan silinemez.
create or replace function public.hesabimi_sil()
 returns void language plpgsql security definer set search_path to ''
as $function$
begin
  if auth.uid() is null then raise exception 'Oturum yok' using errcode = '42501'; end if;
  if exists (select 1 from public.yonetici y where y.user_id = auth.uid()) then
    raise exception 'Yönetici hesapları buradan silinemez' using errcode = 'P0001';
  end if;
  delete from auth.users where id = auth.uid();
end $function$;
revoke all on function public.hesabimi_sil() from public, anon;
grant execute on function public.hesabimi_sil() to authenticated;
