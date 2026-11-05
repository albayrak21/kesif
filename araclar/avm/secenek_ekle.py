import json,sys
s=json.load(open(sys.argv[1]))
kul=set(k for v in s['sonuc'].values() for k in v.get('magazalar',[]))
p='/home/claude/kesif/kategoriler.json'; d=json.load(open(p))
f=[x for x in d['avm']['filtreler'] if x['alan']=='magazalar'][0]; opts=f['secenekler']
var={o['deger'] for o in opts}
ek=[k for k in s['yeni'] if k in kul and k not in var]
for k in ek: opts.append({'deger':k,'etiket':s['yeni'][k]})
A='abcçdefgğhıijklmnoöprsştuüvwxyz'
def key(o):
    t=o['etiket'].replace('I','ı').replace('İ','i').lower()
    return [A.index(c) if c in A else 100+ord(c) for c in t]
opts.sort(key=key)
print('eklendi',len(ek),'eksik',kul-{o['deger'] for o in opts},'toplam',len(opts))
json.dump(d,open(p,'w'),ensure_ascii=False,separators=(',',':'))
