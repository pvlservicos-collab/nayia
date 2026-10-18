import json, sys, collections, statistics
pasta = sys.argv[1]
todos = json.load(open(f'{pasta}/todos.json', encoding='utf-8'))
det = json.load(open(f'{pasta}/detalhes.json', encoding='utf-8'))
res = json.load(open(f'{pasta}/resumo.json', encoding='utf-8'))
print('== buscas'); [print(f"  {r['busca']}: OLX diz {r['total_olx']}, {r['paginas']} páginas, {r['anuncios']} anúncios lidos") for r in res]
ids = collections.Counter(a['olx_id'] for a in todos)
print(f"== {len(todos)} linhas, {len(ids)} anúncios distintos, {sum(1 for v in ids.values() if v>1)} aparecem em mais de uma busca")
print('== profissionais:', sum(1 for a in todos if a['profissional']), 'de', len(todos))
campos = ['preco','quartos','banheiros','vagas','area_m2','condominio_valor','iptu_valor','bairro','anunciante','detalhes_imovel','detalhes_condominio','n_fotos']
print('== preenchimento (%):', {c: round(100*sum(1 for a in todos if a.get(c) not in (None,'',0))/len(todos)) for c in campos})
for b in res:
    xs=[a for a in todos if a['busca']==b['busca']]
    pr=sorted(a['preco'] for a in xs if a['preco'])
    print(f"== {b['busca']}: preço mediana R$ {int(statistics.median(pr)):,} | min {pr[0]:,} | max {pr[-1]:,}".replace(',','.'))
    print('   bairros:', ', '.join(f'{k} {v}' for k,v in collections.Counter(a['bairro'] for a in xs).most_common(8)))
    print('   anunciantes:', ', '.join(f'{k} {v}' for k,v in collections.Counter(a['anunciante'] for a in xs).most_common(8)))
    print('   subtipo:', dict(collections.Counter(a['subtipo'] for a in xs).most_common(5)))
    print('   patrocinados:', sum(1 for a in xs if a['patrocinado']), '| destaque:', sum(1 for a in xs if a['destaque']), '| baixou preço:', sum(1 for a in xs if a['baixou_preco']), '| com preço antigo:', sum(1 for a in xs if a['preco_antigo']))
dias = collections.Counter((a['data'] or '')[:10] for a in todos)
print('== por data de publicação/bump (top 10):', dias.most_common(10))
print('== detalhes:', len(det), 'ok', sum(1 for d in det if not d.get('erro')), 'erro', [d.get('erro') for d in det if d.get('erro')])
for d in det[:20]:
    if d.get('erro'): continue
    print(f"  {d['olx_id']} | {d['anunciante']} | {d['bairro']} CEP {d['cep']} ({d['lat']},{d['lng']}) | tel {d['telefone_mascarado']} | {d['rotulo_preco']} {d['preco_texto']} | fotos {len(d['fotos'])} | descr {len(d['descricao'])} chars | zap {d['zap_id']} | pub {d['publicado_em']}")
