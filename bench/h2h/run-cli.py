import json,subprocess,time,sys
Q=json.load(open(sys.argv[1]));out=[]
for i,x in enumerate(Q):
  row={'i':i}
  for name,args in (('routed',[]),('searxng',['-p','searxng'])):
    t=time.time();o=subprocess.run(['websearch',x['q'],'-n','5','--json',*args],capture_output=True,text=True).stdout
    try: j=json.loads(o[o.index('{'):]); r=j['results']; prov=j.get('provider') or (r[0]['source'] if r else None)
    except Exception: r=[];prov=None
    row[name]={'sec':round(time.time()-t,2),'prov':prov,'urls':[a['url'] for a in r],'text':' '.join(a['title']+' '+a['snippet'] for a in r)}
  out.append(row);time.sleep(16)
json.dump(out,open(sys.argv[2],'w'))
print('DONE')
