-- Seçki listelerini yöneticiler (public.yonetici) düzenler: yonetim.html → "Öne çıkan listeler".
-- Taslak: gorunurluk = 'gizli' (sitede görünmez); yayında: 'herkes'.
alter table public.liste drop constraint if exists liste_secki_check;
alter table public.liste add constraint liste_secki_check
  check ((sahip is null) = (secki_sira is not null) and (sahip is not null or (tur = 'liste' and gorunurluk in ('herkes', 'gizli'))));

create or replace function public.secki_yonet_listele()
 returns json language plpgsql stable security definer set search_path to ''
as $function$
begin
  if not private.yonetici_mi() then raise exception 'Yetki yok' using errcode = '42501'; end if;
  return (select coalesce(json_agg(json_build_object('id', l.id, 'ad', l.ad, 'aciklama', l.aciklama, 'sira', l.secki_sira,
      'yayinda', l.gorunurluk = 'herkes', 'guncelleme', l.guncelleme,
      'kayit_sayisi', (select count(*) from public.liste_kayit k where k.liste_id = l.id),
      'mekanlar', (select coalesce(json_agg(json_build_object('id', m.id, 'ad', m.ad, 'kategori', m.kategori, 'il', m.il, 'ilce', m.ilce, 'durum', m.durum)
                     order by lm.eklenme desc), '[]'::json)
                   from public.liste_mekan lm join public.mekan m on m.id = lm.mekan_id where lm.liste_id = l.id))
    order by l.secki_sira, l.olusturma), '[]'::json)
  from public.liste l where l.sahip is null);
end $function$;

-- Kaydet: p_id boşsa yeni seçki. p_mekanlar gösterim sırasıyla (ilk = en üstte).
create or replace function public.secki_yonet_kaydet(p_id uuid, p_ad text, p_aciklama text, p_yayinda boolean, p_mekanlar text[])
 returns uuid language plpgsql security definer set search_path to ''
as $function$
declare v uuid := p_id; n int := coalesce(array_length(p_mekanlar, 1), 0); simdi timestamptz := now();
begin
  if not private.yonetici_mi() then raise exception 'Yetki yok' using errcode = '42501'; end if;
  if n > 1000 then raise exception 'Bir listede en çok 1000 yer olabilir' using errcode = 'P0001'; end if;
  if v is null then
    insert into public.liste (sahip, tur, ad, aciklama, gorunurluk, secki_sira)
    values (null, 'liste', btrim(p_ad), nullif(btrim(coalesce(p_aciklama, '')), ''), case when p_yayinda then 'herkes' else 'gizli' end,
            coalesce((select max(secki_sira) from public.liste where sahip is null), 0) + 1)
    returning id into v;
  else
    update public.liste set ad = btrim(p_ad), aciklama = nullif(btrim(coalesce(p_aciklama, '')), ''),
      gorunurluk = case when p_yayinda then 'herkes' else 'gizli' end
    where id = v and sahip is null;
    if not found then raise exception 'Seçki bulunamadı' using errcode = 'P0001'; end if;
  end if;
  delete from public.liste_mekan where liste_id = v and mekan_id <> all (coalesce(p_mekanlar, '{}'));
  insert into public.liste_mekan (liste_id, mekan_id, eklenme)
    select v, x.id, simdi - make_interval(secs => x.i::double precision)
    from unnest(coalesce(p_mekanlar, '{}')) with ordinality x(id, i)
    where exists (select 1 from public.mekan m where m.id = x.id)
  on conflict (liste_id, mekan_id) do update set eklenme = excluded.eklenme;
  update public.liste set guncelleme = simdi where id = v;
  return v;
end $function$;

-- Sıra: p_idler Keşfet'teki gösterim sırası.
create or replace function public.secki_yonet_sirala(p_idler uuid[])
 returns void language plpgsql security definer set search_path to ''
as $function$
begin
  if not private.yonetici_mi() then raise exception 'Yetki yok' using errcode = '42501'; end if;
  update public.liste l set secki_sira = x.i from unnest(p_idler) with ordinality x(id, i)
  where l.id = x.id and l.sahip is null;
end $function$;

create or replace function public.secki_yonet_sil(p_id uuid)
 returns void language plpgsql security definer set search_path to ''
as $function$
begin
  if not private.yonetici_mi() then raise exception 'Yetki yok' using errcode = '42501'; end if;
  delete from public.liste where id = p_id and sahip is null;
end $function$;

revoke all on function public.secki_yonet_listele(), public.secki_yonet_kaydet(uuid, text, text, boolean, text[]),
  public.secki_yonet_sirala(uuid[]), public.secki_yonet_sil(uuid) from public, anon;
grant execute on function public.secki_yonet_listele(), public.secki_yonet_kaydet(uuid, text, text, boolean, text[]),
  public.secki_yonet_sirala(uuid[]), public.secki_yonet_sil(uuid) to authenticated;
