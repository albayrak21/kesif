# AVM mağaza doldurma araçları

Her il için bir tur:

1. **Liste çek:** AVM'nin kendi sitesinden mağaza adlarını yerleşik tarayıcıyla al. Siteyi bulamazsan Google'da ara. Adları `|` ile ayırıp `/home/claude/avm/<il>/<avm>.txt` dosyasına kaydet. Adların içindeki `|` karakterlerini önce değiştir.
2. **Hazırla:** `hazirla_ornek.py` dosyasını `hazirla_<il>.py` adıyla kopyala.
   - `AVM={mekan_id:'<il>/<avm>'}` sözlüğünü değiştir.
   - Gerekirse `ALIAS`, `SUPER`, `COCUK`, `OV` ve `HARIC` listelerine ekleme yap.
   - Çıktı adını `sonuc_<il>.json` yap ve betiği çalıştır.
   - Yeni anahtarları mevcut anahtarlarla karşılaştır, yakın eşleşmeleri `ALIAS` ile bağla.
3. **Seçenekleri ekle:** `python3 secenek_ekle.py sonuc_<il>.json` komutu yeni anahtarları `kategoriler.json` dosyasına ekler.
4. **Veritabanına yaz:** Her AVM için şu kalıpla bir `update` yaz:
   - `ozellikler = (ozellikler - 'marka') || {magazalar, supermarket/sinema/yemek_kati/cocuk_oyun_alani: true, magazalar_kaynak}`
   - `dogrulama_tarihi` = bugün.
   - Liste eksikse ya da adlar logo dosya adlarından çıkarıldıysa `dogrulanacak` alanına `magazalar` ekle.
   - Web adresi yanlışsa https adresiyle düzelt.

   İlin tamamını tek `execute_sql` çağrısında gönder. SQL'i ekrana yazdırıp yeniden yapıştırma.
5. **İnceleme kaydı:** Her AVM için `avm_inceleme` tablosuna bir satır yaz: `mekan_id, il, ad, karar, bilgi, neden, kaynak, tarih`. Aynı kayıt varsa `on conflict (mekan_id) do update` ile güncelle.
   - `karar`: avm / avm_degil / belirsiz
   - `bilgi`: dolduruldu / kismen / bakilamadi / gerekmez
6. **Gönder ve not al:** `kategoriler.json` dosyasını commit edip push et. İl notunu projeye yaz (`claude/avm-<il>.md`).

**Kurallar:**
- Bankalar, ATM'ler, eczane, terzi, döviz, lostra, kuru temizleme, oto yıkama ve sigorta alınmaz.
- Yalnız çok markalı AVM'ler sayılır.
- Kayıt silinmez ya da taşınmaz.
