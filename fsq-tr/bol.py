"""tr.parquet'i il kutularına göre kabaca illere ayırır, il gruplarına (turlara) böler,
her tur için 40.000 satırlık JSON parçalar + SHA-256 manifest üretir.
Kesin il ataması veritabanında (sinir_tr_parca). İstanbul ve zaten yüklenen Ankara kutusu hariç."""
import duckdb, hashlib, json, os, sys

S = '/tmp/claude-0/-home-claude/03f7e290-69c2-5b05-a381-6fee2e03340e/scratchpad/fsq'
P = '/mnt/user-data/uploads/keşif uygulaması/fsq_tr/tr.parquet'
SIN = '/home/claude/kesif/sinirlar.json'
OUT = sys.argv[1]  # çıktı klasörü
HEDEF_TUR = 160_000  # tur başına yaklaşık kayıt

kutular = json.load(open(SIN))['iller']
c = duckdb.connect()
c.execute("create table k (il varchar, x0 double, y0 double, x1 double, y1 double)")
c.executemany("insert into k values (?,?,?,?,?)", [(il, *v['kutu']) for il, v in kutular.items()])

c.execute(f"""
create table a as
select p.*, (select il from k where p.longitude between x0 and x1 and p.latitude between y0 and y1
             order by (p.longitude-(x0+x1)/2)^2 + (p.latitude-(y0+y1)/2)^2 limit 1) kil
from '{P}' p
where not (p.latitude between 38.6 and 40.8 and p.longitude between 30.7 and 34.2)
""")
c.execute("delete from a where kil = 'İstanbul'")
say = c.execute("select coalesce(kil,'?'), count(*) from a group by 1 order by 2 desc").fetchall()
print('toplam', sum(n for _, n in say), 'il', len(say))

# Turlar: büyükten küçüğe, ~HEDEF_TUR kayıt
turlar, cur, n = [], [], 0
for il, m in say:
    cur.append(il); n += m
    if n >= HEDEF_TUR:
        turlar.append((cur, n)); cur, n = [], 0
if cur: turlar.append((cur, n))

man = []
for t, (iller, n) in enumerate(turlar, 1):
    d = f'{OUT}/tur{t:02d}'; os.makedirs(d, exist_ok=True)
    liste = ",".join("'" + i.replace("'", "''") + "'" for i in iller)
    c.execute(f"""create or replace table t as select row_number() over (order by fsq_place_id)-1 sira,
      fsq_place_id, name, latitude, longitude, address, locality, postcode, tel, website, email,
      facebook_id::varchar facebook_id, instagram, twitter, coalesce(fsq_category_labels, []::varchar[]) etiketler, date_refreshed
      from a where coalesce(kil,'?') in ({liste})""")
    cols = [x[0] for x in c.execute('select * exclude(sira) from t limit 0').description]
    parcalar = []
    for i in range((n + 39999) // 40000):
        rows = c.execute(f"select * exclude (sira) from t where sira>={i*40000} and sira<{(i+1)*40000} order by sira").fetchall()
        data = [{k: v for k, v in zip(cols, r) if v is not None and v != []} for r in rows]
        b = json.dumps(data, ensure_ascii=False, separators=(',', ':')).encode('utf-8')
        f = f'{d}/parca-{i:02d}.json'; open(f, 'wb').write(b)
        parcalar.append({'dosya': os.path.basename(f), 'satir': len(rows), 'sha256': hashlib.sha256(b).hexdigest(), 'bayt': len(b)})
    json.dump({'tur': t, 'iller': iller, 'toplam': n, 'parcalar': parcalar}, open(f'{d}/manifest.json', 'w'), ensure_ascii=False, indent=1)
    man.append({'tur': t, 'iller': iller, 'toplam': n, 'parca': len(parcalar)})
    print(t, n, len(parcalar), iller)
json.dump(man, open(f'{OUT}/turlar.json', 'w'), ensure_ascii=False, indent=1)
