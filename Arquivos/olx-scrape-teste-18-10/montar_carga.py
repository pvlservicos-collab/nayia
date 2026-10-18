"""Junta a lista (todos.json) com o detalhe (detalhes_todos.jsonl) e escreve o SQL da carga: 4 chamadas a
site_scrap_importar numa transação. python montar_carga.py <pasta_saida> <carga.sql>"""
import json, sys, collections
pasta, saida = sys.argv[1], sys.argv[2]
todos = json.load(open(f'{pasta}/todos.json', encoding='utf-8'))
det = {}
for l in open(f'{pasta}/detalhes_todos.jsonl', encoding='utf-8'):
    l = l.strip()
    if not l: continue
    d = json.loads(l)
    if d.get('status') == 200 and not d.get('erro'): det[d['olx_id']] = d

LISTAS = {
    'apto_aluguel_4mil': ('OLX · Apto aluguel ≥ R$ 4 mil', '#2563eb', 'Apartamentos para alugar em Manaus a partir de R$ 4.000, só anunciantes profissionais (raspagem de 18/10/2026)'),
    'casa_aluguel_4mil': ('OLX · Casa aluguel ≥ R$ 4 mil', '#0e7490', 'Casas para alugar em Manaus a partir de R$ 4.000, só profissionais (18/10/2026)'),
    'apto_venda_400mil': ('OLX · Apto venda ≥ R$ 400 mil', '#6d28d9', 'Apartamentos à venda em Manaus a partir de R$ 400.000, só profissionais (18/10/2026)'),
    'casa_venda_400mil': ('OLX · Casa venda ≥ R$ 400 mil', '#d97706', 'Casas à venda em Manaus a partir de R$ 400.000, só profissionais (18/10/2026)'),
}
URLS = {
    'apto_aluguel_4mil': 'https://www.olx.com.br/imoveis/aluguel/estado-am/regiao-de-manaus/manaus?ps=4000&q=apartamento%20aluguel&sf=1&f=c',
    'casa_aluguel_4mil': 'https://www.olx.com.br/imoveis/aluguel/estado-am/regiao-de-manaus/manaus?ps=4000&q=casa%20aluguel&sf=1&f=c',
    'apto_venda_400mil': 'https://www.olx.com.br/imoveis/venda/estado-am/regiao-de-manaus/manaus?ps=400000&q=apartamento%20venda&sf=1&f=c',
    'casa_venda_400mil': 'https://www.olx.com.br/imoveis/venda/estado-am/regiao-de-manaus/manaus?ps=400000&q=casa%20venda&sf=1&f=c',
}
por_busca = collections.defaultdict(list)
vistos = set()
sem_detalhe = 0
for a in todos:
    chave = (a['busca'], a['olx_id'])
    if chave in vistos: continue
    vistos.add(chave)
    d = det.get(a['olx_id']) or {}
    if not d: sem_detalhe += 1
    item = {k: a.get(k) for k in ('olx_id', 'titulo', 'preco', 'preco_texto', 'preco_antigo', 'categoria', 'tipo_negocio', 'subtipo', 'quartos', 'banheiros', 'vagas',
                                  'area_m2', 'condominio_valor', 'iptu_valor', 'bairro', 'anunciante', 'n_fotos', 'fotos', 'url', 'data')}
    item.update({
        'descricao': d.get('descricao'), 'cep': d.get('cep'), 'lat': d.get('lat'), 'lng': d.get('lng'),
        'anunciante': d.get('anunciante') or a.get('anunciante'), 'anunciante_id': d.get('anunciante_id'),
        'telefone_mascarado': d.get('telefone_mascarado'), 'publicado_em': d.get('publicado_em'),
        'dados': {k: d.get(k) for k in ('ad_id', 'campos', 'valores', 'zap_id', 'selo', 'conta_pro', 'whatsapp', 'telefone_verificado', 'anunciante_user_id', 'rotulo_preco') if d.get(k) is not None}
                 | {k: a.get(k) for k in ('destaque', 'patrocinado', 'baixou_preco', 'detalhes_imovel', 'detalhes_condominio', 'ultimo_bump_seg', 'local') if a.get(k) is not None},
    })
    por_busca[a['busca']].append(item)

with open(saida, 'w', encoding='utf-8', newline='\n') as f:
    f.write('-- carga das 4 listas da OLX (18/10/2026) no Scrap\nBEGIN;\n')
    for busca, itens in por_busca.items():
        nome, cor, desc = LISTAS[busca]
        corpo = {'lista': {'nome': nome, 'cor': cor, 'descricao': desc, 'url_busca': URLS[busca], 'origem': 'olx'}, 'anuncios': itens}
        js = json.dumps(corpo, ensure_ascii=False).replace('\\u0000', '')
        assert '$carga$' not in js
        f.write(f"SELECT '{nome}' AS lista, site_scrap_importar($carga${js}$carga$::jsonb, 'Pedro (raspagem OLX 18/10)') AS r;\n")
    f.write('COMMIT;\n')
print({b: len(i) for b, i in por_busca.items()}, 'sem detalhe:', sem_detalhe, 'detalhes ok:', len(det))
