-- İşletme sahipleri — 1. aşama (02.11.2026). Plan ve kararlar: proje notu isletme-sahibi.md.
-- Bir mekanın tek sahibi olur (mekan_sahip.mekan_id birincil anahtar). Sahiplik başvurusu yönetici onayıyla verilir.
-- Kanıt yöntemi henüz seçilmedi: başvuruda açıklama + isteğe bağlı belge (özel depo sahiplik-belge); yönetici elle bakar.
-- Sahip ücretsiz planda: bilgileri düzenler (kritik alanlar onaya gider), 5 fotoğraf yükler, ayda 2 fotoğrafsız duyuru yapar.
-- Bütün yazma işlemleri SECURITY DEFINER fonksiyonlardan geçer; tablolarda istemcinin doğrudan yazma yetkisi yoktur.
-- Bildirimler şimdilik site içinde (e-posta servisi kurulunca e-posta da eklenir).

-- ============ tablolar ============
create table if not exists public.mekan_sahip (
  mekan_id text primary key references public.mekan(id) on delete cascade,
  kullanici_id uuid not null references auth.users(id) on delete cascade,
  plan text not null default 'ucretsiz' check (plan in ('ucretsiz', 'pro')),
  onay_tarihi timestamptz not null default now(),
  onaylayan uuid,
  kanit_turu text,
  basvuru_id uuid
);
create index if not exists mekan_sahip_kullanici_idx on public.mekan_sahip (kullanici_id);

create table if not exists public.sahiplik_basvuru (
  id uuid primary key default gen_random_uuid(),
  mekan_id text not null references public.mekan(id) on delete cascade,
  kullanici_id uuid not null references auth.users(id) on delete cascade,
  ad_soyad text not null check (char_length(ad_soyad) between 3 and 120),
  rol text not null check (char_length(rol) between 2 and 80),
  telefon text check (telefon is null or char_length(telefon) <= 40),
  eposta text check (eposta is null or char_length(eposta) <= 200),
  aciklama text not null check (char_length(aciklama) between 10 and 2000),
  belgeler text[] not null default '{}',
  itiraz boolean not null default false,    -- mekanın başka bir sahibi varken yapıldı (devir / itiraz)
  istisna boolean not null default false,   -- başvuranın zaten başka bir mekanı var (bir hesap bir mekan kuralının istisnası)
  durum text not null default 'bekliyor' check (durum in ('bekliyor', 'onaylandi', 'reddedildi', 'geri_cekildi')),
  karar_notu text,
  karar_veren uuid,
  karar_zamani timestamptz,
  olusturma timestamptz not null default now()
);
create index if not exists sahiplik_basvuru_durum_idx on public.sahiplik_basvuru (durum, olusturma);
create index if not exists sahiplik_basvuru_kullanici_idx on public.sahiplik_basvuru (kullanici_id);
create unique index if not exists sahiplik_basvuru_tek_bekleyen on public.sahiplik_basvuru (mekan_id, kullanici_id) where durum = 'bekliyor';

-- Kritik alan değişiklikleri (ad, konum, ana kategori, kapanış; sağlıkta kurum tipi, acil servis, SGK) yönetici onayına gider.
create table if not exists public.sahip_talep (
  id uuid primary key default gen_random_uuid(),
  mekan_id text not null references public.mekan(id) on delete cascade,
  kullanici_id uuid not null references auth.users(id) on delete cascade,
  alanlar jsonb not null,
  gerekce text check (gerekce is null or char_length(gerekce) <= 1000),
  durum text not null default 'bekliyor' check (durum in ('bekliyor', 'onaylandi', 'reddedildi', 'geri_cekildi')),
  karar_notu text,
  karar_veren uuid,
  karar_zamani timestamptz,
  olusturma timestamptz not null default now()
);
create index if not exists sahip_talep_durum_idx on public.sahip_talep (durum, olusturma);

create table if not exists public.mekan_duyuru (
  id uuid primary key default gen_random_uuid(),
  mekan_id text not null references public.mekan(id) on delete cascade,
  tur text not null check (tur in ('mac', 'canli_muzik', 'etkinlik', 'genel')),
  baslik text not null check (char_length(baslik) between 3 and 80),
  metin text check (metin is null or char_length(metin) <= 500),
  baslangic timestamptz not null,
  bitis timestamptz not null,
  gorsel text,
  yazan uuid not null,
  olusturma timestamptz not null default now(),
  durum text not null default 'yayinda' check (durum in ('yayinda', 'gizli', 'silindi', 'kaldirildi')),
  check (bitis > baslangic)
);
create index if not exists mekan_duyuru_mekan_idx on public.mekan_duyuru (mekan_id, bitis);
create index if not exists mekan_duyuru_yayinda_idx on public.mekan_duyuru (bitis) where durum = 'yayinda';

alter table public.mekan_sahip enable row level security;
alter table public.sahiplik_basvuru enable row level security;
alter table public.sahip_talep enable row level security;
alter table public.mekan_duyuru enable row level security;

-- ============ yardımcılar ============
create or replace function private.mekan_sahibi_mi(p_mekan text)
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (select 1 from public.mekan_sahip s where s.mekan_id = p_mekan and s.kullanici_id = auth.uid());
$$;
grant execute on function private.mekan_sahibi_mi(text) to authenticated;

-- Plan sınırları (isletme-sahibi.md kararları). Pro henüz satılmıyor; değerler hazır.
create or replace function private.plan_sinir(p_plan text)
returns jsonb language sql immutable set search_path = '' as $$
  select case when p_plan = 'pro'
    then '{"foto": 15, "duyuru_ay": 60, "duyuru_gun": 5, "duyuru_yayinda": 10, "duyuru_gorsel": true}'::jsonb
    else '{"foto": 5, "duyuru_ay": 2, "duyuru_gun": 2, "duyuru_yayinda": 2, "duyuru_gorsel": false}'::jsonb end;
$$;

-- ============ okuma kuralları ============
drop policy if exists "sahip kendi kaydini okur" on public.mekan_sahip;
create policy "sahip kendi kaydini okur" on public.mekan_sahip for select to authenticated
  using (kullanici_id = (select auth.uid()) or (select private.yonetici_mi()));
drop policy if exists "basvuru kendi okur" on public.sahiplik_basvuru;
create policy "basvuru kendi okur" on public.sahiplik_basvuru for select to authenticated
  using (kullanici_id = (select auth.uid()) or (select private.yonetici_mi()));
drop policy if exists "talep kendi okur" on public.sahip_talep;
create policy "talep kendi okur" on public.sahip_talep for select to authenticated
  using (kullanici_id = (select auth.uid()) or (select private.yonetici_mi()));
drop policy if exists "duyuru herkese acik" on public.mekan_duyuru;
create policy "duyuru herkese acik" on public.mekan_duyuru for select to anon, authenticated
  using (durum = 'yayinda' and bitis > now() and exists (select 1 from public.mekan m where m.id = mekan_duyuru.mekan_id and m.durum = 'acik'));
drop policy if exists "duyuru sahip ve yonetici okur" on public.mekan_duyuru;
create policy "duyuru sahip ve yonetici okur" on public.mekan_duyuru for select to authenticated
  using ((select private.mekan_sahibi_mi(mekan_id)) or (select private.yonetici_mi()));
revoke all on public.mekan_sahip, public.sahiplik_basvuru, public.sahip_talep, public.mekan_duyuru from anon, authenticated;
grant select on public.mekan_sahip, public.sahiplik_basvuru, public.sahip_talep to authenticated;
grant select on public.mekan_duyuru to anon, authenticated;

-- ============ başvuru ============
create or replace function public.sahiplik_basvur(p_mekan text, p_ad_soyad text, p_rol text, p_telefon text,
  p_eposta text, p_aciklama text, p_belgeler text[] default '{}')
returns uuid language plpgsql security definer set search_path = '' as $$
declare u uuid := auth.uid(); yeni uuid; b text;
begin
  if u is null then raise exception 'giris_gerekli'; end if;
  if not exists (select 1 from public.mekan m where m.id = p_mekan and m.durum = 'acik') then raise exception 'mekan_yok'; end if;
  if exists (select 1 from public.mekan_sahip s where s.mekan_id = p_mekan and s.kullanici_id = u) then raise exception 'zaten_sahip'; end if;
  if exists (select 1 from public.sahiplik_basvuru x where x.mekan_id = p_mekan and x.kullanici_id = u and x.durum = 'bekliyor') then raise exception 'zaten_basvurdun'; end if;
  if (select count(*) from public.sahiplik_basvuru x where x.kullanici_id = u and x.durum = 'bekliyor') >= 3 then raise exception 'cok_basvuru'; end if;
  if (select count(*) from public.sahiplik_basvuru x where x.kullanici_id = u and x.olusturma > now() - interval '1 day') >= 5 then raise exception 'cok_basvuru'; end if;
  if cardinality(coalesce(p_belgeler, '{}')) > 5 then raise exception 'cok_belge'; end if;
  foreach b in array coalesce(p_belgeler, '{}') loop
    if b !~ ('^' || u::text || '/[0-9a-f-]{36}\.(pdf|jpg|png|webp)$') then raise exception 'belge_yolu'; end if;
  end loop;
  insert into public.sahiplik_basvuru (mekan_id, kullanici_id, ad_soyad, rol, telefon, eposta, aciklama, belgeler, itiraz, istisna)
  values (p_mekan, u, btrim(p_ad_soyad), btrim(p_rol), nullif(btrim(coalesce(p_telefon, '')), ''), nullif(btrim(coalesce(p_eposta, '')), ''),
    btrim(p_aciklama), coalesce(p_belgeler, '{}'),
    exists (select 1 from public.mekan_sahip s where s.mekan_id = p_mekan),
    exists (select 1 from public.mekan_sahip s where s.kullanici_id = u))
  returning id into yeni;
  return yeni;
end $$;

create or replace function public.sahiplik_geri_cek(p_id uuid)
returns void language plpgsql security definer set search_path = '' as $$
begin
  update public.sahiplik_basvuru set durum = 'geri_cekildi', karar_zamani = now()
  where id = p_id and kullanici_id = auth.uid() and durum = 'bekliyor';
  if not found then raise exception 'basvuru_yok'; end if;
end $$;

-- Bir mekanın sahiplik durumu (herkes): sahipli mi, benim mi, bekleyen başvurum.
create or replace function public.mekan_sahiplik(p_mekan text)
returns jsonb language sql stable security definer set search_path = '' as $$
  select jsonb_build_object(
    'sahipli', exists (select 1 from public.mekan_sahip s where s.mekan_id = p_mekan),
    'benim', exists (select 1 from public.mekan_sahip s where s.mekan_id = p_mekan and s.kullanici_id = auth.uid()),
    'plan', (select s.plan from public.mekan_sahip s where s.mekan_id = p_mekan and s.kullanici_id = auth.uid()),
    'basvuru', (select jsonb_build_object('id', x.id, 'durum', x.durum, 'olusturma', x.olusturma, 'karar_notu', x.karar_notu)
                from public.sahiplik_basvuru x where x.mekan_id = p_mekan and x.kullanici_id = auth.uid()
                order by x.olusturma desc limit 1));
$$;

-- Sayfam: sahibi olduğum mekanlar ve başvurularım.
create or replace function public.isletmelerim()
returns jsonb language sql stable security definer set search_path = '' as $$
  select jsonb_build_object(
    'mekanlar', coalesce((select jsonb_agg(jsonb_build_object('id', m.id, 'ad', m.ad, 'kategori', m.kategori, 'il', m.il, 'ilce', m.ilce,
        'plan', s.plan, 'onay_tarihi', s.onay_tarihi) order by m.ad)
      from public.mekan_sahip s join public.mekan m on m.id = s.mekan_id where s.kullanici_id = auth.uid()), '[]'),
    'basvurular', coalesce((select jsonb_agg(jsonb_build_object('id', x.id, 'mekan_id', x.mekan_id, 'ad', m.ad, 'durum', x.durum,
        'olusturma', x.olusturma, 'karar_notu', x.karar_notu) order by x.olusturma desc)
      from public.sahiplik_basvuru x join public.mekan m on m.id = x.mekan_id
      where x.kullanici_id = auth.uid() and (x.durum = 'bekliyor' or x.olusturma > now() - interval '60 days')), '[]'));
$$;

-- ============ yönetici kararı ============
create or replace function public.sahiplik_karar(p_id uuid, p_onay boolean, p_not text default null)
returns void language plpgsql security definer set search_path = '' as $$
declare b public.sahiplik_basvuru;
begin
  if not private.yonetici_mi() then raise exception 'yetki_yok'; end if;
  select * into b from public.sahiplik_basvuru where id = p_id and durum = 'bekliyor' for update;
  if not found then raise exception 'basvuru_yok'; end if;
  if p_onay then
    -- Devir: mekanın önceki sahibi varsa yerine geçilir (yöneticinin bilinçli kararı; başvuru "itiraz" işaretli gelir).
    delete from public.mekan_sahip where mekan_id = b.mekan_id;
    insert into public.mekan_sahip (mekan_id, kullanici_id, onaylayan, kanit_turu, basvuru_id)
    values (b.mekan_id, b.kullanici_id, auth.uid(), case when cardinality(b.belgeler) > 0 then 'belge' else 'aciklama' end, b.id);
  end if;
  update public.sahiplik_basvuru set durum = case when p_onay then 'onaylandi' else 'reddedildi' end,
    karar_notu = nullif(btrim(coalesce(p_not, '')), ''), karar_veren = auth.uid(), karar_zamani = now()
  where id = p_id;
end $$;

-- Yöneticinin sahipliği kaldırması (ör. işletme kapandı, kötüye kullanım).
create or replace function public.sahiplik_kaldir(p_mekan text)
returns void language plpgsql security definer set search_path = '' as $$
begin
  if not private.yonetici_mi() then raise exception 'yetki_yok'; end if;
  delete from public.mekan_sahip where mekan_id = p_mekan;
end $$;

-- ============ sahibin düzenlemesi ============
-- Doğrudan uygulanan: telefon, web, adres ve özellikler (kategori filtre alanları, iletişim, saatler, ek kategoriler).
-- Onaya giden (sahip_talep): ad, konum, ana kategori, kapanış; sağlık kategorisinde kurum tipi, acil servis, SGK.
-- Değişiklik degisiklik tablosuna sahibin kimliğiyle düşer (gecmise_yaz) ve mekan_ic.kaynaklar'a "işletme beyanı" eklenir.
create or replace function public.sahip_mekan_guncelle(p_mekan text, p_alanlar jsonb, p_gerekce text default null)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  m public.mekan; k text; v jsonb; oz jsonb; kritik jsonb := '{}'; uygulanan text[] := '{}';
  saglik_kritik text[] := array['kurum_tipi', 'acil_servis', 'sgk_anlasmasi'];
  yasak text[] := array['etiket', 'adsiz', 'isletme_guncelleme', 'wikidata', 'koruma', 'yapim_yili'];
  ust_dogrudan text[] := array['telefon', 'web', 'adres'];
  ust_kritik text[] := array['ad', 'lat', 'lng', 'kategori', 'durum'];
  gecerli_kat text[]; dog text[]; talep_id uuid; ad text;
  n_tel text; n_web text; n_adres text;
begin
  if auth.uid() is null or not private.mekan_sahibi_mi(p_mekan) then raise exception 'yetki_yok'; end if;
  if jsonb_typeof(p_alanlar) <> 'object' then raise exception 'bicim'; end if;
  select * into m from public.mekan where id = p_mekan for update;
  n_tel := m.telefon; n_web := m.web; n_adres := m.adres;
  oz := coalesce(m.ozellikler, '{}');
  dog := coalesce(m.dogrulanacak, '{}');
  select array_agg(distinct x.kategori) into gecerli_kat from public.mekan_sayim_mv x;
  for k, v in select * from jsonb_each(p_alanlar) loop
    if k = any(ust_kritik) or (m.kategori = 'saglik' and k = any(saglik_kritik)) then
      if k = 'durum' and v #>> '{}' not in ('acik', 'kapali') then raise exception 'bicim: durum'; end if;
      if k = 'kategori' and not (v #>> '{}' = any(gecerli_kat)) then raise exception 'bicim: kategori'; end if;
      if k in ('lat', 'lng') and jsonb_typeof(v) <> 'number' then raise exception 'bicim: konum'; end if;
      if k = 'ad' and (jsonb_typeof(v) <> 'string' or char_length(v #>> '{}') not between 2 and 120) then raise exception 'bicim: ad'; end if;
      kritik := kritik || jsonb_build_object(k, v);
    elsif k = any(ust_dogrudan) then
      if jsonb_typeof(v) not in ('string', 'null') or char_length(coalesce(v #>> '{}', '')) > 300 then raise exception 'bicim: %', k; end if;
      if k = 'telefon' then n_tel := nullif(btrim(v #>> '{}'), '');
      elsif k = 'web' then
        if v #>> '{}' is not null and v #>> '{}' !~* '^https?://[^\s]+$' then raise exception 'bicim: web'; end if;
        n_web := nullif(btrim(v #>> '{}'), '');
      else n_adres := nullif(btrim(v #>> '{}'), '');
        dog := array_remove(dog, 'adres_yaklasik');
      end if;
      dog := array_remove(dog, k); uygulanan := uygulanan || k;
    else
      if k !~ '^[a-z][a-z0-9_]{1,40}$' or k = any(yasak) then raise exception 'bicim: %', k; end if;
      if k = 'ek_kategori' then
        if jsonb_typeof(v) = 'array' then
          if jsonb_array_length(v) > 3 or exists (select 1 from jsonb_array_elements_text(v) e where not (e = any(gecerli_kat)) or e = m.kategori)
            then raise exception 'bicim: ek_kategori'; end if;
        elsif jsonb_typeof(v) <> 'null' then raise exception 'bicim: ek_kategori'; end if;
      elsif jsonb_typeof(v) = 'array' then
        if jsonb_array_length(v) > 40 or exists (select 1 from jsonb_array_elements(v) e where jsonb_typeof(e) <> 'string' or char_length(e #>> '{}') > 60)
          then raise exception 'bicim: %', k; end if;
      elsif jsonb_typeof(v) = 'string' then
        if char_length(v #>> '{}') > 500 then raise exception 'bicim: %', k; end if;
      elsif jsonb_typeof(v) not in ('boolean', 'number', 'null') then raise exception 'bicim: %', k;
      end if;
      oz := case when jsonb_typeof(v) = 'null' or (jsonb_typeof(v) = 'array' and jsonb_array_length(v) = 0) then oz - k else oz || jsonb_build_object(k, v) end;
      dog := array_remove(dog, k); uygulanan := uygulanan || k;
    end if;
  end loop;
  if cardinality(uygulanan) > 0 then
    oz := oz || jsonb_build_object('isletme_guncelleme', to_char(now() at time zone 'Europe/Istanbul', 'YYYY-MM-DD'));
    update public.mekan set ozellikler = oz, dogrulanacak = dog, telefon = n_tel, web = n_web, adres = n_adres where id = p_mekan;
    select p.kullanici_adi into ad from public.profil p where p.id = auth.uid();
    insert into public.mekan_ic (mekan_id, kaynaklar) values (p_mekan, jsonb_build_array(jsonb_build_object(
      'url', null, 'tur', 'isletme_beyani',
      'kapsam', format('işletme beyanı (sahip @%s): %s; %s', coalesce(ad, '?'), array_to_string(uygulanan, ', '),
        to_char(now() at time zone 'Europe/Istanbul', 'DD.MM.YYYY')))))
    on conflict (mekan_id) do update set kaynaklar = coalesce(public.mekan_ic.kaynaklar, '[]'::jsonb) || excluded.kaynaklar;
  end if;
  if kritik <> '{}' then
    insert into public.sahip_talep (mekan_id, kullanici_id, alanlar, gerekce)
    values (p_mekan, auth.uid(), kritik, nullif(btrim(coalesce(p_gerekce, '')), '')) returning id into talep_id;
  end if;
  return jsonb_build_object('uygulanan', to_jsonb(uygulanan), 'talep', talep_id);
end $$;

create or replace function public.talep_karar(p_id uuid, p_onay boolean, p_not text default null)
returns void language plpgsql security definer set search_path = '' as $$
declare t public.sahip_talep; k text; v jsonb;
begin
  if not private.yonetici_mi() then raise exception 'yetki_yok'; end if;
  select * into t from public.sahip_talep where id = p_id and durum = 'bekliyor' for update;
  if not found then raise exception 'talep_yok'; end if;
  if p_onay then
    for k, v in select * from jsonb_each(t.alanlar) loop
      if k = 'ad' then update public.mekan set ad = v #>> '{}' where id = t.mekan_id;
      elsif k = 'lat' then update public.mekan set lat = (v #>> '{}')::float8 where id = t.mekan_id;
      elsif k = 'lng' then update public.mekan set lng = (v #>> '{}')::float8 where id = t.mekan_id;
      elsif k = 'kategori' then update public.mekan set kategori = v #>> '{}' where id = t.mekan_id;
      elsif k = 'durum' then update public.mekan set durum = v #>> '{}' where id = t.mekan_id;
      else update public.mekan set ozellikler = case when jsonb_typeof(v) = 'null' then ozellikler - k else ozellikler || jsonb_build_object(k, v) end,
          dogrulanacak = array_remove(dogrulanacak, k) where id = t.mekan_id;
      end if;
    end loop;
  end if;
  update public.sahip_talep set durum = case when p_onay then 'onaylandi' else 'reddedildi' end,
    karar_notu = nullif(btrim(coalesce(p_not, '')), ''), karar_veren = auth.uid(), karar_zamani = now() where id = p_id;
end $$;

create or replace function public.talep_geri_cek(p_id uuid)
returns void language plpgsql security definer set search_path = '' as $$
begin
  update public.sahip_talep set durum = 'geri_cekildi', karar_zamani = now() where id = p_id and kullanici_id = auth.uid() and durum = 'bekliyor';
  if not found then raise exception 'talep_yok'; end if;
end $$;

-- ============ duyurular ============
-- Sayım İstanbul takvim ayı ve günü üzerinden, oluşturulan duyuruya göre (silmek hakkı geri vermez). Tarihler sonradan değişmez.
create or replace function public.duyuru_ekle(p_mekan text, p_tur text, p_baslik text, p_metin text, p_baslangic timestamptz, p_bitis timestamptz)
returns uuid language plpgsql security definer set search_path = '' as $$
declare s public.mekan_sahip; sinir jsonb; yeni uuid; ay_bas timestamptz; gun_bas timestamptz; kat text;
begin
  select * into s from public.mekan_sahip where mekan_id = p_mekan and kullanici_id = auth.uid();
  if not found then raise exception 'yetki_yok'; end if;
  perform 1 from public.mekan_sahip where mekan_id = p_mekan for update;   -- aynı anda iki istek sınırı aşamasın
  sinir := private.plan_sinir(s.plan);
  select m.kategori into kat from public.mekan m where m.id = p_mekan;
  if kat = 'saglik' and p_tur <> 'genel' then raise exception 'saglik_yalniz_bilgi'; end if;
  if p_bitis <= p_baslangic or p_bitis <= now() then raise exception 'tarih'; end if;
  if p_baslangic > now() + interval '90 days' or p_bitis > p_baslangic + interval '31 days' then raise exception 'tarih'; end if;
  ay_bas := date_trunc('month', now() at time zone 'Europe/Istanbul') at time zone 'Europe/Istanbul';
  gun_bas := date_trunc('day', now() at time zone 'Europe/Istanbul') at time zone 'Europe/Istanbul';
  if (select count(*) from public.mekan_duyuru d where d.mekan_id = p_mekan and d.olusturma >= ay_bas) >= (sinir->>'duyuru_ay')::int
    then raise exception 'duyuru_ay_doldu' using hint = sinir->>'duyuru_ay'; end if;
  if (select count(*) from public.mekan_duyuru d where d.mekan_id = p_mekan and d.olusturma >= gun_bas) >= (sinir->>'duyuru_gun')::int
    then raise exception 'duyuru_gun_doldu'; end if;
  if (select count(*) from public.mekan_duyuru d where d.mekan_id = p_mekan and d.durum = 'yayinda' and d.bitis > now()) >= (sinir->>'duyuru_yayinda')::int
    then raise exception 'duyuru_yayinda_doldu'; end if;
  if exists (select 1 from public.mekan_duyuru d where d.mekan_id = p_mekan and d.olusturma > now() - interval '1 minute')
    then raise exception 'duyuru_cok_hizli'; end if;
  insert into public.mekan_duyuru (mekan_id, tur, baslik, metin, baslangic, bitis, yazan)
  values (p_mekan, p_tur, btrim(p_baslik), nullif(btrim(coalesce(p_metin, '')), ''), p_baslangic, p_bitis, auth.uid())
  returning id into yeni;
  return yeni;
end $$;

-- Sahip metni düzeltebilir, gizleyebilir, silebilir (silinen sayımda kalır). Yönetici kaldırabilir.
create or replace function public.duyuru_guncelle(p_id uuid, p_baslik text, p_metin text, p_durum text)
returns void language plpgsql security definer set search_path = '' as $$
declare d public.mekan_duyuru;
begin
  select * into d from public.mekan_duyuru where id = p_id for update;
  if not found then raise exception 'duyuru_yok'; end if;
  if private.yonetici_mi() then
    if p_durum not in ('yayinda', 'gizli', 'silindi', 'kaldirildi') then raise exception 'bicim'; end if;
  elsif private.mekan_sahibi_mi(d.mekan_id) then
    if d.durum = 'kaldirildi' or p_durum not in ('yayinda', 'gizli', 'silindi') then raise exception 'yetki_yok'; end if;
  else raise exception 'yetki_yok';
  end if;
  update public.mekan_duyuru set baslik = coalesce(nullif(btrim(coalesce(p_baslik, '')), ''), baslik),
    metin = case when p_metin is null then metin else nullif(btrim(p_metin), '') end, durum = p_durum where id = p_id;
end $$;

-- Sahip paneli: bu ayki hak ve duyurular.
create or replace function public.sahip_ozet(p_mekan text)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare s public.mekan_sahip; sinir jsonb; ay_bas timestamptz;
begin
  select * into s from public.mekan_sahip where mekan_id = p_mekan and kullanici_id = auth.uid();
  if not found then raise exception 'yetki_yok'; end if;
  sinir := private.plan_sinir(s.plan);
  ay_bas := date_trunc('month', now() at time zone 'Europe/Istanbul') at time zone 'Europe/Istanbul';
  return jsonb_build_object('plan', s.plan, 'sinir', sinir,
    'duyuru_bu_ay', (select count(*) from public.mekan_duyuru d where d.mekan_id = p_mekan and d.olusturma >= ay_bas),
    'foto', (select count(*) from public.mekan_foto f where f.mekan_id = p_mekan and f.kaynak = 'isletme'),
    'duyurular', coalesce((select jsonb_agg(to_jsonb(d) order by d.baslangic desc) from (
        select id, tur, baslik, metin, baslangic, bitis, durum, olusturma from public.mekan_duyuru
        where mekan_id = p_mekan and durum <> 'silindi' order by baslangic desc limit 30) d), '[]'),
    'talepler', coalesce((select jsonb_agg(jsonb_build_object('id', t.id, 'alanlar', t.alanlar, 'durum', t.durum, 'olusturma', t.olusturma, 'karar_notu', t.karar_notu) order by t.olusturma desc)
        from public.sahip_talep t where t.mekan_id = p_mekan and (t.durum = 'bekliyor' or t.olusturma > now() - interval '30 days')), '[]'));
end $$;

-- ============ fotoğraflar ============
-- Sahibin fotoğrafları (kaynak 'isletme') plan sınırıyla sayılır; Keşif'in yüklediği fotoğraflar sahibin hakkından düşmez.
create or replace function private.foto_hakki_denetle()
returns trigger language plpgsql security definer set search_path = '' as $$
declare hak integer; n integer; pl text;
begin
  if new.kaynak = 'isletme' then
    select s.plan into pl from public.mekan_sahip s where s.mekan_id = new.mekan_id;
    hak := (private.plan_sinir(coalesce(pl, 'ucretsiz'))->>'foto')::int;
    select count(*) into n from public.mekan_foto f where f.mekan_id = new.mekan_id and f.kaynak = 'isletme';
  else
    select m.foto_hakki into hak from public.mekan m where m.id = new.mekan_id;
    hak := coalesce(hak, 5);
    select count(*) into n from public.mekan_foto f where f.mekan_id = new.mekan_id and f.kaynak <> 'isletme';
  end if;
  if n >= hak then raise exception 'foto_hakki_doldu' using hint = format('%s/%s', n, hak); end if;
  return new;
end $$;

drop policy if exists "mekan_foto sahip ekler" on public.mekan_foto;
create policy "mekan_foto sahip ekler" on public.mekan_foto for insert to authenticated
  with check (kaynak = 'isletme' and yukleyen = (select auth.uid()) and (select private.mekan_sahibi_mi(mekan_id))
    and yol like mekan_id || '/%' and kucuk_yol like mekan_id || '/%');
drop policy if exists "mekan_foto sahip siler" on public.mekan_foto;
create policy "mekan_foto sahip siler" on public.mekan_foto for delete to authenticated
  using (kaynak = 'isletme' and (select private.mekan_sahibi_mi(mekan_id)));
drop policy if exists "mekan_foto sahip okur" on public.mekan_foto;
create policy "mekan_foto sahip okur" on public.mekan_foto for select to authenticated
  using ((select private.mekan_sahibi_mi(mekan_id)));

-- Depo: sahip yalnız kendi mekanının klasörüne yükler; Keşif'in fotoğraf dosyalarını silemez.
drop policy if exists "mekan-foto sahip yukler" on storage.objects;
create policy "mekan-foto sahip yukler" on storage.objects for insert to authenticated
  with check (bucket_id = 'mekan-foto' and (select private.mekan_sahibi_mi((storage.foldername(name))[1])));
drop policy if exists "mekan-foto sahip okur" on storage.objects;
create policy "mekan-foto sahip okur" on storage.objects for select to authenticated
  using (bucket_id = 'mekan-foto' and (select private.mekan_sahibi_mi((storage.foldername(name))[1])));
drop policy if exists "mekan-foto sahip siler" on storage.objects;
create policy "mekan-foto sahip siler" on storage.objects for delete to authenticated
  using (bucket_id = 'mekan-foto' and (select private.mekan_sahibi_mi((storage.foldername(name))[1]))
    and not exists (select 1 from public.mekan_foto f where (f.yol = name or f.kucuk_yol = name) and f.kaynak <> 'isletme'));

-- Belge deposu (özel): başvuran kendi klasörüne (<kullanıcı>/<uuid>.<uzantı>) yükler; yalnız kendisi ve yöneticiler okur.
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('sahiplik-belge', 'sahiplik-belge', false, 5242880, array['application/pdf', 'image/jpeg', 'image/png', 'image/webp'])
on conflict (id) do update set public = false, file_size_limit = excluded.file_size_limit, allowed_mime_types = excluded.allowed_mime_types;
drop policy if exists "belge kendi yukler" on storage.objects;
create policy "belge kendi yukler" on storage.objects for insert to authenticated
  with check (bucket_id = 'sahiplik-belge' and (storage.foldername(name))[1] = (select auth.uid())::text);
drop policy if exists "belge kendi ve yonetici okur" on storage.objects;
create policy "belge kendi ve yonetici okur" on storage.objects for select to authenticated
  using (bucket_id = 'sahiplik-belge' and ((storage.foldername(name))[1] = (select auth.uid())::text or (select private.yonetici_mi())));
drop policy if exists "belge kendi siler" on storage.objects;
create policy "belge kendi siler" on storage.objects for delete to authenticated
  using (bucket_id = 'sahiplik-belge' and (storage.foldername(name))[1] = (select auth.uid())::text);

-- ============ yetkiler ============
revoke all on function public.sahiplik_basvur(text, text, text, text, text, text, text[]), public.sahiplik_geri_cek(uuid),
  public.isletmelerim(), public.sahiplik_karar(uuid, boolean, text), public.sahiplik_kaldir(text),
  public.sahip_mekan_guncelle(text, jsonb, text), public.talep_karar(uuid, boolean, text), public.talep_geri_cek(uuid),
  public.duyuru_ekle(text, text, text, text, timestamptz, timestamptz), public.duyuru_guncelle(uuid, text, text, text),
  public.sahip_ozet(text) from public, anon;
grant execute on function public.sahiplik_basvur(text, text, text, text, text, text, text[]), public.sahiplik_geri_cek(uuid),
  public.isletmelerim(), public.sahiplik_karar(uuid, boolean, text), public.sahiplik_kaldir(text),
  public.sahip_mekan_guncelle(text, jsonb, text), public.talep_karar(uuid, boolean, text), public.talep_geri_cek(uuid),
  public.duyuru_ekle(text, text, text, text, timestamptz, timestamptz), public.duyuru_guncelle(uuid, text, text, text),
  public.sahip_ozet(text) to authenticated;
grant execute on function public.mekan_sahiplik(text) to anon, authenticated;
revoke all on function private.plan_sinir(text) from public, anon;
notify pgrst, 'reload schema';
