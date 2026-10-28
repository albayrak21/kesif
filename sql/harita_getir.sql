-- Haritadaki alan için tek sorgu (harita öncelikli mod).
-- p_kutu: [güney, batı, kuzey, doğu]
-- p_ne: 'igne' (ekran ızgarasında hücre başına en iyiler) | 'liste' (sayfa sayfa, puana göre) | 'sayi' (filtre sayıları)
-- Kapsam:
--   p_q boş ve p_kats boş -> öne çıkanlar (mekan_nokta.ilgi > 0), ilgi sırasıyla
--   p_q dolu              -> adı eşleşenler + p_q_kats (aramanın eşleştiği kategoriler) + p_q_turler ([kategori, tür] çiftleri)
--   p_kats dolu           -> yalnız bu kategoriler (aramayla birlikte: arama sonuçları bu kategorilerle sınırlanır)
-- p_filtre: [{alan, tip: secim|evet_hayir|coklu, eslesme: herhangi|hepsi, s}] (yalnız etkin olanlar). Bilgisi olmayan kayıt elenmez.
-- p_izgara: [sütun, satır, hücre başına]. Dönüş: {toplam, kayitlar} ya da {toplam, sayilar}.
create or replace function public.harita_getir(
  p_kutu float8[],
  p_ne text default 'igne',
  p_q text default null,
  p_kats text[] default null,
  p_q_kats text[] default null,
  p_q_turler jsonb default null,
  p_filtre jsonb default null,
  p_izgara int[] default array[7,5,1],
  p_limit int default 100,
  p_offset int default 0,
  p_alanlar jsonb default null
) returns jsonb
language plpgsql stable
set search_path = public, extensions
as $$
declare
  s float8 := p_kutu[1]; w float8 := p_kutu[2]; n float8 := p_kutu[3]; e float8 := p_kutu[4];
  tam text := btrim(regexp_replace(lower(translate(coalesce(p_q, ''), 'ÇĞİIÖŞÜÂÎÛçğıöşüâîû', 'cgiiosuaiucgiosuaiu')), '[^a-z0-9]+', ' ', 'g'));
  kel text[];
  gez boolean;
  kutu_k text;
  ad_k text := '';
  filtre_k text := '';
  kosullar jsonb := '{}';
  taban0 text;
  parca text;
  kat_k text := '';
  taban text;
  f jsonb;
  alan text;
  esle text;
  sonuc jsonb;
  toplam int;
  w2 text;
  iller text[];
  il_k text := '';
  m_kat_k text := '';
  tur_s text := '';
  ad_sinir int := 5000;
  ad_haric text := '';
begin
  if p_kutu is null or cardinality(p_kutu) <> 4 then return jsonb_build_object('hata', 'kutu'); end if;
  select array_agg(x) into kel from (select x from unnest(string_to_array(tam, ' ')) x where x <> '' limit 5) q;
  gez := kel is null and coalesce(cardinality(p_kats), 0) = 0;
  kutu_k := format('p.lat between %s and %s and p.lng between %s and %s', s, n, w, e);
  -- Filtre sayılarında tür, nokta tablosundaki tur dizisinden sayılır (mekan'a gitmeden).
  if p_ne = 'sayi' then tur_s := ', p.tur'; end if;
  if p_kats is not null and cardinality(p_kats) > 0 then
    kat_k := format(' and p.kategori = any(%L::text[])', p_kats);
    m_kat_k := format(' and m.kategori = any(%L::text[])', p_kats);
  end if;

  -- Filtreler: bilinmeyen değer elenmez (sitede "bilgisi eksik" diye ayrı gösterilir).
  if p_filtre is not null and jsonb_typeof(p_filtre) = 'array' then
    for f in select * from jsonb_array_elements(p_filtre) loop
      alan := f->>'alan';
      if alan is null or alan !~ '^[a-z0-9_]+$' then continue; end if;
      esle := case f->>'tip'
        when 'secim' then format('m.ozellikler->>%L = %L', alan, f->>'s')
        when 'evet_hayir' then format('m.ozellikler->%L = ''true''::jsonb', alan)
        when 'coklu' then format('m.ozellikler->%L %s array(select jsonb_array_elements_text(%L::jsonb))', alan,
          case when f->>'eslesme' = 'herhangi' then '?|' else '?&' end, f->'s')
        end;
      if esle is null then continue; end if;
      parca := format(' and (coalesce(jsonb_typeof(m.ozellikler->%L), ''null'') = ''null'' or %s)', alan, esle);
      filtre_k := filtre_k || parca;
      -- "herhangi" çoklu ve tekli seçimde alanın kendi sayıları kendi seçimi olmadan hesaplanır.
      kosullar := kosullar || jsonb_build_object(alan, jsonb_build_object('k', parca, 'kendi', (f->>'tip' = 'coklu' and f->>'eslesme' = 'herhangi') or f->>'tip' = 'secim'));
    end loop;
  end if;

  if gez then
    taban := format('select p.id, p.lat, p.lng, p.ilgi as puan%s from mekan_nokta p where p.ilgi > 0 and %s', tur_s, kutu_k);
  elsif kel is null then
    taban := format('select p.id, p.lat, p.lng, p.skor as puan%s from mekan_nokta p where %s%s', tur_s, kutu_k, kat_k);
  else
    -- Ad: her kelime adda bir kelimenin başında geçmeli. Kısa aramada (3 harften az) yalnız adı bununla başlayanlar (önek indeksi).
    if (select max(length(x)) from unnest(kel) x) < 3 then
      ad_k := format(' and m.arama like %L', tam || '%');
      ad_sinir := 300;   -- yazarken kısa arama: önek indeksi tek başına seçici değil
    else
      foreach w2 in array kel loop
        ad_k := ad_k || format(' and m.arama like %L and lower(translate(m.ad, ''ÇĞİIÖŞÜÂÎÛçğıöşüâîû'', ''cgiiosuaiucgiosuaiu'')) ~ %L',
          '%' || w2 || '%', '(^|[^a-z0-9])' || w2);
      end loop;
    end if;
    -- Alan en çok 3 ile değiyorsa ad araması il + ad indeksiyle (mekan_il_arama_trgm_idx / il başına) yapılır.
    if (n - s) * (e - w) < 4 then iller := public.kutu_illeri(p_kutu); end if;
    if iller is not null and cardinality(iller) between 1 and 3 then
      il_k := ' and (' || (select string_agg(format('m.il = %L', x), ' or ') from unnest(iller) x) || ')';
    end if;
    -- Parçalar birbirini dışlar (union all, tekilleştirme sıralaması yok): ad parçası aramanın eşleştiği kategori ve türleri,
    -- tür parçası eşleşen kategorileri içermez. Ad eşleşmeleri en çok ad_sinir (çok genel kelime geniş alanda aranırsa).
    if p_q_kats is not null and cardinality(p_q_kats) > 0 then
      ad_haric := format(' and not (m.kategori = any(%L::text[]))', p_q_kats);
    end if;
    if p_q_turler is not null and jsonb_typeof(p_q_turler) = 'array' and jsonb_array_length(p_q_turler) > 0 then
      for f in select jsonb_build_object('k', x->>0, 't', jsonb_agg(x->>1)) from jsonb_array_elements(p_q_turler) x
               where p_q_kats is null or not ((x->>0) = any(p_q_kats)) group by x->>0 loop
        ad_haric := ad_haric || format(' and not (m.kategori = %L and coalesce(m.ozellikler->''tur'' ?| array(select jsonb_array_elements_text(%L::jsonb)), false))', f->>'k', f->'t');
      end loop;
    end if;
    taban := format('select p.id, p.lat, p.lng, p.skor as puan%s from (select m.id from mekan m where m.durum = ''acik'' and m.lat between %s and %s and m.lng between %s and %s%s%s%s%s limit %s) a join mekan_nokta p on p.id = a.id',
      tur_s, s, n, w, e, il_k, ad_k, m_kat_k, ad_haric, ad_sinir);
    if p_q_kats is not null and cardinality(p_q_kats) > 0 then
      taban := taban || format(' union all select p.id, p.lat, p.lng, p.skor%s from mekan_nokta p where %s and p.kategori = any(%L::text[])%s', tur_s, kutu_k, p_q_kats, kat_k);
    end if;
    if p_q_turler is not null and jsonb_typeof(p_q_turler) = 'array' and jsonb_array_length(p_q_turler) > 0 then
      -- Kategori başına ayrı parça: (kategori, lat, lng) indeksi kullanılsın.
      for f in select jsonb_build_object('k', x->>0, 't', jsonb_agg(x->>1)) from jsonb_array_elements(p_q_turler) x
               where p_q_kats is null or not ((x->>0) = any(p_q_kats)) group by x->>0 loop
        taban := taban || format(' union all select p.id, p.lat, p.lng, p.skor%s from mekan_nokta p where p.kategori = %L and %s and p.tur && array(select jsonb_array_elements_text(%L::jsonb))%s',
          tur_s, f->>'k', kutu_k, f->'t', kat_k);
      end loop;
    end if;
  end if;

  taban0 := taban;
  if filtre_k <> '' then
    taban := format('select b.* from (%s) b join mekan m on m.id = b.id where true%s', taban, filtre_k);
  end if;

  if p_ne = 'igne' and coalesce(p_izgara[3], 1) <= 1 then
    -- Hücre başına tek kayıt: sıralama yerine tek geçişte en yüksek (puan, kimlik) seçilir (büyük alanlarda hızlı).
    execute format($q$
      with t as materialized (%s),
      g as (select max(lpad(t.puan::text, 5, '0') || t.id) en from t group by
          least(%s - 1, floor((t.lat - %s) / %s * %s)::int), least(%s - 1, floor((t.lng - %s) / %s * %s)::int))
      select jsonb_build_object('toplam', (select count(*) from t), 'kayitlar', coalesce(jsonb_agg(to_jsonb(x) order by x.puan desc), '[]')) from (
        select m.id, m.kategori, m.ad, m.lat, m.lng, m.adres, m.il, m.ilce, m.telefon, m.web, m.ozellikler,
               m.dogrulanacak, m.dogrulama_tarihi, m.osm_ref, m.onem, left(g.en, 5)::int as puan
        from g join mekan m on m.id = substr(g.en, 6)) x$q$,
      taban,
      p_izgara[2], s, greatest(n - s, 1e-9), p_izgara[2],
      p_izgara[1], w, greatest(e - w, 1e-9), p_izgara[1]) into sonuc;
    return sonuc;
  elsif p_ne = 'igne' then
    -- Ekran p_izgara[1] x p_izgara[2] hücreye bölünür; her hücreden puanı en yüksek p_izgara[3] kayıt (en çok 1000).
    execute format($q$
      with t as materialized (%s),
      h as (select t.*, row_number() over (partition by
          least(%s - 1, floor((t.lat - %s) / %s * %s)::int), least(%s - 1, floor((t.lng - %s) / %s * %s)::int)
          order by t.puan desc, t.id) r from t)
      select jsonb_build_object('toplam', (select count(*) from t), 'kayitlar', coalesce(jsonb_agg(to_jsonb(x) order by x.puan desc), '[]')) from (
        select m.id, m.kategori, m.ad, m.lat, m.lng, m.adres, m.il, m.ilce, m.telefon, m.web, m.ozellikler,
               m.dogrulanacak, m.dogrulama_tarihi, m.osm_ref, m.onem, h.puan
        from (select * from h where h.r <= %s order by h.puan desc limit 1000) h join mekan m on m.id = h.id) x$q$,
      taban,
      p_izgara[2], s, greatest(n - s, 1e-9), p_izgara[2],
      p_izgara[1], w, greatest(e - w, 1e-9), p_izgara[1],
      greatest(p_izgara[3], 1)) into sonuc;
    return sonuc;
  elsif p_ne = 'liste' then
    execute format($q$
      with t0 as materialized (%s)
      select jsonb_build_object('toplam', (select count(*) from t0), 'kayitlar', coalesce(jsonb_agg(to_jsonb(x) order by x.puan desc, x.id), '[]')) from (
        select m.id, m.kategori, m.ad, m.lat, m.lng, m.adres, m.il, m.ilce, m.telefon, m.web, m.ozellikler,
               m.dogrulanacak, m.dogrulama_tarihi, m.osm_ref, m.onem, t.puan
        from (select * from t0 order by t0.puan desc, t0.id limit %s offset %s) t join mekan m on m.id = t.id) x$q$,
      taban, least(greatest(coalesce(p_limit, 100), 1), 500), greatest(coalesce(p_offset, 0), 0)) into sonuc;
    return sonuc;
  elsif p_ne = 'sayi' then
    -- Filtre sayıları: alan başına, ekrandaki sonuçlarda her değerin kaç kayıtta olduğu. Diğer alanların seçimleri uygulanır.
    -- Çok kalabalık alanda (20.000 üstü) hesaplanmaz.
    -- "tur" (nokta tablosunda da duruyor) 50.000 kayda kadar, diğer alanlar 1.500 kayda kadar sayılır.
    execute format('select count(*) from (select 1 from (%s) t limit 50001) c', taban) into toplam;
    if toplam > 50000 or p_alanlar is null or jsonb_typeof(p_alanlar) <> 'array' then return jsonb_build_object('toplam', toplam, 'sayilar', null); end if;
    sonuc := '{}';
    for alan in select jsonb_array_elements_text(p_alanlar) loop
      if alan !~ '^[a-z0-9_]+$' then continue; end if;
      filtre_k := '';
      for parca in select case when kk.key = alan and (kk.value->>'kendi')::boolean then '' else kk.value->>'k' end from jsonb_each(kosullar) kk loop
        filtre_k := filtre_k || parca;
      end loop;
      if alan = 'tur' and filtre_k = '' then
        execute format($q$
          select coalesce(jsonb_object_agg(v.d, v.n), '{}') from (
            select d, count(*) n from (%s) t cross join unnest(t.tur) d group by d) v$q$, taban0) into esle;
        sonuc := sonuc || jsonb_build_object(alan, esle::jsonb);
        continue;
      end if;
      if toplam > 1500 then continue; end if;
      execute format($q$
        select coalesce(jsonb_object_agg(v.deger, v.n), '{}') from (
          select v.deger, count(*) n from (%s) t join mekan m on m.id = t.id
          cross join lateral (
            select x as deger from jsonb_array_elements_text(case when jsonb_typeof(m.ozellikler->%L) = 'array' then m.ozellikler->%L else '[]' end) x
            union all select m.ozellikler->>%L where jsonb_typeof(m.ozellikler->%L) in ('string', 'boolean')
          ) v where true%s group by 1) v$q$, taban0, alan, alan, alan, alan, filtre_k) into esle;
      sonuc := sonuc || jsonb_build_object(alan, esle::jsonb);
    end loop;
    return jsonb_build_object('toplam', toplam, 'sayilar', sonuc);
  end if;
  return jsonb_build_object('hata', 'ne');
end $$;

grant execute on function public.harita_getir(float8[], text, text, text[], text[], jsonb, jsonb, int[], int, int, jsonb) to anon, authenticated;
