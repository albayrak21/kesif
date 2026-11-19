-- Sağlık: tıp merkezi / poliklinik ayrımı addan (19.11.2026). Uygulandı: migration "sinif_saglik_tur_ayrimi".
-- sinif_il_isle (veritabanındaki güncel sürüm) _sk0 adımında kategori 'saglik' olan kararlar için
-- saglik_tur_ayir(ad, tur, kurum_tipi_var_mi) çağırır; kural sütununa '+saglik_tur' eklenir.
-- Kurum tipi elle doldurulmuş hastanelere ve diş hekimi türlü kayıtlara dokunulmaz.
-- İlk toplu uygulama ve geri alma: tur_ayrim_gecmis tablosu (bkz. proje notu saglik-tur-ayrimi.md).

create or replace function public.saglik_yeni_tur(ad text, tur jsonb) returns text language sql immutable set search_path to 'public' as $$
 select case
  when n ~ 'poliklini' and n !~ '^\s*poliklinik(ler)?\s*$'
   and n !~ '(hastane|hospital|ağız|agiz|diş|dis |dis$|dental|dent|eah|e\.a\.h|\mdh\M|eğitim|egitim|araştırma|arastirma|numune|devlet|üniversite|universite|fakülte|fakulte|şehir hast|nöroloji|noroloji|dahiliye|cerrahi|ortopedi|kadın|kadin|doğum|dogum|onkoloji|acil|kardiyoloji|göz|goz|çocuk|cocuk|psikiyatri|üroloji|uroloji|kbb|kulak|cildiye|dermatoloji|dermo|deri |zührevi|zuhrevi|fizik|endokrin|gastro|nefro|enfeksiyon|göğüs|gogus|plastik|beslenme|psiko|geriatri|anestezi|antenat|romatoloji|alerji|immün|hematoloji|hastalıklar|hastaliklar|servis|veteriner|hayvan|d\.?e\.?ü|\m(mkü|adü|ktü|omü|ksü|paü|sdü|nkü|atü|erü|eskü|ogü|çomü|yyü|deü|aü|eü|iü)\M)'
   and not coalesce(tur ? 'dis_hekimi',false) then 'poliklinik'
  when n ~ '(tıp merkez|tip merkez|tıbbi merkez|tibbi merkez|medical cent|medikal merkez|sağlık merkez|saglik merkez)'
   and n !~ '(hastane|hospital|aile sa[gğ]l|asm|toplum sa[gğ]l|ağız|agiz|diş|dis sa|dental|dent|güzellik|guzellik|estetik merkez|veteriner|hayvan|belediye|işyeri|isyeri|toplum ruh|göçmen|gocmen|sağlıklı hayat|saglikli hayat|verem|kanser erken|ketem|no.?lu|numaralı|nükleer|nukleer|servis|üniversite|universite|fakülte|fakulte|turgut özal|turgut ozal|dursun odabaş|bakanl|d\.?e\.?ü|\m(mkü|adü|ktü|omü|ksü|paü|sdü|nkü|atü|erü|eskü|ogü|çomü|yyü|deü|aü|eü|iü)\M)'
   and not coalesce(tur ? 'dis_hekimi',false) then 'tip_merkezi'
 end from (select lower(replace(replace(ad,'İ','i'),'I','ı')) n) x $$;

create or replace function public.saglik_tur_ayir(p_ad text, p_tur jsonb, p_kurumlu boolean)
returns jsonb language sql immutable set search_path to 'public' as $$
  select case
    when p_kurumlu then p_tur
    when y is null then p_tur
    else jsonb_build_array(y) || coalesce((select jsonb_agg(x) from jsonb_array_elements_text(case when jsonb_typeof(p_tur)='array' then p_tur else '[]'::jsonb end) x
      where x not in ('hastane','hastane_binasi','klinik_tip_merkezi','muayenehane','saglik_kurulusu','saglik_hizmeti','acil_servis','tip_merkezi','poliklinik')), '[]'::jsonb)
  end
  from (select public.saglik_yeni_tur(p_ad, p_tur) y) z $$;

revoke all on function public.saglik_yeni_tur(text,jsonb) from public, anon, authenticated;
revoke all on function public.saglik_tur_ayir(text,jsonb,boolean) from public, anon, authenticated;

-- sinif_il_isle'deki değişiklik (iki satır):
--   _r:   (m.ozellikler ? 'kurum_tipi') kurumlu,
--   _sk0: ... kk.kat, st.tur, case when st.tur is distinct from kk.tur then coalesce(kk.kural || '+', '') || 'saglik_tur' else kk.kural end kural, ...
--         cross join lateral (select case when kk.kat = 'saglik' then saglik_tur_ayir(r.ad, kk.tur, r.kurumlu) else kk.tur end tur) st;
