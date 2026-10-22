"""RASPAGEM DIÁRIA (22/10/2026): a carga das 8 buscas nas MESMAS 16 listas de 18 e 22/10 (atualiza; nada é apagado).
python montar_carga.py <pasta_do_dia> <carga.sql> <cache/detalhes.jsonl>
Junta a lista (todos.json) com o detalhe (detalhes_todos.jsonl) e escreve o SQL da carga do Scrap.
python montar_carga.py <pasta_saida> <carga.sql>

Pedro, 18/10/2026: "temos 4, serão 8, porque uma vai ter as imobiliárias e outra só corretores direto". Cada busca da OLX
vira DUAS listas na pasta OLX: "· Imobiliárias" (nome do anunciante com cara de empresa) e "· Corretores" (nome de gente,
apelido, ou com "corretor"/"CRECI"). Os anúncios da própria Imob Easy ficam de fora. A blacklist (quem falou conosco em
60 dias) é aplicada pelo banco na hora da carga (scrap_contatos_rebuild, 408)."""
import json, sys, collections, re, unicodedata
pasta, saida, cache = sys.argv[1], sys.argv[2], sys.argv[3]
todos = json.load(open(f'{pasta}/todos.json', encoding='utf-8'))
det = {}
for l in open(cache, encoding='utf-8'):
    l = l.strip()
    if not l: continue
    d = json.loads(l)
    if d.get('status') == 200 and not d.get('erro'): det[d['olx_id']] = d

NOSSOS = {'imob easy', 'f v sobreira', 'imobeasy'}     # os nossos anúncios não viram contato
PESSOA = re.compile(r'corretor|creci|consultor|avaliador|broker$|\.corretor')
EMPRESA = re.compile(r'imobili|imoveis|\bimob\b|imob$|\bltda|negoc|broker|house|consultoria|empreend|constru|incorpora|administra|realty|'
                     r'remax|domus|solidez|liberty|casas|apartamentos|galp|soluc|servic|group|grupo|investment|advise|pericia|arquitetura|'
                     r'engenharia|correspondente|escritorio|\bepp\b|\bme\b|punkt|confiance|nexus|tracker|quintal|lopes manaus|maxima|realize|'
                     r'flats|metro quadrado|abrindo portas|casa propria|loja de|\bkl\b|\bkm\b|\btc\b|\bls\b|rgin|\bcnb\b|\bcva\b|\bw g\b|'
                     r'\br r\b|\bb a\b|\bsk\b|\bll\b|\br2\b|\batl\b|\bdpi\b|dantas e duarte|&|imobi|amppengenharias|lauschner|centro de')
def _norm(s):
    s = unicodedata.normalize('NFKD', s or '').encode('ascii', 'ignore').decode().lower()
    return re.sub(r'\s+', ' ', s).strip()
def classificar(nome):
    n = _norm(nome)
    if not n: return 'corretores'
    if PESSOA.search(n): return 'corretores'
    if EMPRESA.search(n): return 'imobiliarias'
    return 'corretores'

BUSCAS = {
    'apto_aluguel_4mil': ('Apto aluguel ≥ R$ 4 mil', 'Apartamentos para alugar em Manaus a partir de R$ 4.000, só profissionais (raspagem diária)',
                          'https://www.olx.com.br/imoveis/aluguel/estado-am/regiao-de-manaus/manaus?ps=4000&q=apartamento%20aluguel&sf=1&f=c'),
    'casa_aluguel_4mil': ('Casa aluguel ≥ R$ 4 mil', 'Casas para alugar em Manaus a partir de R$ 4.000, só profissionais (raspagem diária)',
                          'https://www.olx.com.br/imoveis/aluguel/estado-am/regiao-de-manaus/manaus?ps=4000&q=casa%20aluguel&sf=1&f=c'),
    'apto_venda_400mil': ('Apto venda ≥ R$ 400 mil', 'Apartamentos à venda em Manaus a partir de R$ 400.000, só profissionais (raspagem diária)',
                          'https://www.olx.com.br/imoveis/venda/estado-am/regiao-de-manaus/manaus?ps=400000&q=apartamento%20venda&sf=1&f=c'),
    'casa_venda_400mil': ('Casa venda ≥ R$ 400 mil', 'Casas à venda em Manaus a partir de R$ 400.000, só profissionais (raspagem diária)',
                          'https://www.olx.com.br/imoveis/venda/estado-am/regiao-de-manaus/manaus?ps=400000&q=casa%20venda&sf=1&f=c'),
    'apto_aluguel_ate4mil': ('Apto aluguel até R$ 4 mil', 'Apartamentos para alugar em Manaus até R$ 3.999, só profissionais (raspagem diária)',
                          'https://www.olx.com.br/imoveis/aluguel/estado-am/regiao-de-manaus/manaus?pe=3999&q=apartamento%20aluguel&sf=1&f=c'),
    'casa_aluguel_ate4mil': ('Casa aluguel até R$ 4 mil', 'Casas para alugar em Manaus até R$ 3.999, só profissionais (raspagem diária)',
                          'https://www.olx.com.br/imoveis/aluguel/estado-am/regiao-de-manaus/manaus?pe=3999&q=casa%20aluguel&sf=1&f=c'),
    'apto_venda_ate400mil': ('Apto venda até R$ 400 mil', 'Apartamentos à venda em Manaus até R$ 399.999, só profissionais (raspagem diária)',
                          'https://www.olx.com.br/imoveis/venda/estado-am/regiao-de-manaus/manaus?pe=399999&q=apartamento%20venda&sf=1&f=c'),
    'casa_venda_ate400mil': ('Casa venda até R$ 400 mil', 'Casas à venda em Manaus até R$ 399.999, só profissionais (raspagem diária)',
                          'https://www.olx.com.br/imoveis/venda/estado-am/regiao-de-manaus/manaus?pe=399999&q=casa%20venda&sf=1&f=c'),
}
TIPOS = {'imobiliarias': ('Imobiliárias', '#2563eb'), 'corretores': ('Corretores', '#0e7490')}

por_lista = collections.defaultdict(list)
vistos = set(); sem_detalhe = 0; nossos = 0; por_anunciante = {}
for a in todos:
    chave = (a['busca'], a['olx_id'])
    if chave in vistos: continue
    vistos.add(chave)
    d = det.get(a['olx_id']) or {}
    if not d: sem_detalhe += 1
    nome = d.get('anunciante') or a.get('anunciante') or ''
    if _norm(nome) in NOSSOS: nossos += 1; continue
    tipo = classificar(nome); por_anunciante[nome] = tipo
    item = {k: a.get(k) for k in ('olx_id', 'titulo', 'preco', 'preco_texto', 'preco_antigo', 'categoria', 'tipo_negocio', 'subtipo', 'quartos', 'banheiros', 'vagas',
                                  'area_m2', 'condominio_valor', 'iptu_valor', 'bairro', 'n_fotos', 'fotos', 'url', 'data')}
    item.update({
        'descricao': d.get('descricao'), 'cep': d.get('cep'), 'lat': d.get('lat'), 'lng': d.get('lng'),
        'anunciante': nome, 'anunciante_id': d.get('anunciante_id'),
        'telefone_mascarado': d.get('telefone_mascarado'), 'publicado_em': d.get('publicado_em'),
        'dados': {k: d.get(k) for k in ('ad_id', 'campos', 'valores', 'zap_id', 'selo', 'conta_pro', 'whatsapp', 'telefone_verificado', 'anunciante_user_id', 'rotulo_preco') if d.get(k) is not None}
                 | {k: a.get(k) for k in ('destaque', 'patrocinado', 'baixou_preco', 'detalhes_imovel', 'detalhes_condominio', 'ultimo_bump_seg', 'local') if a.get(k) is not None}
                 | {'tipo_anunciante': tipo},
    })
    por_lista[(a['busca'], tipo)].append(item)

with open(saida, 'w', encoding='utf-8', newline='\n') as f:
    f.write('-- carga diária das 16 listas da OLX no Scrap, pasta OLX (as mesmas de 18 e 22/10)\nBEGIN;\n')
    for busca in BUSCAS:
        for tipo in ('imobiliarias', 'corretores'):
            itens = por_lista.get((busca, tipo), [])
            rot, desc, url = BUSCAS[busca]; trot, cor = TIPOS[tipo]
            nome = f'{rot} · {trot}'
            corpo = {'lista': {'nome': nome, 'cor': cor, 'pasta': 'OLX', 'origem': 'olx', 'url_busca': url,
                               'descricao': desc + (' · só anunciantes com nome de empresa' if tipo == 'imobiliarias' else ' · só corretores diretos (nome de gente, apelido ou "corretor/CRECI")')},
                     'anuncios': itens}
            js = json.dumps(corpo, ensure_ascii=False).replace('\\u0000', '')
            assert '$carga$' not in js
            f.write(f"SELECT '{nome}' AS lista, site_scrap_importar($carga${js}$carga$::jsonb, 'raspagem diária da OLX') AS r;\n")
    f.write('COMMIT;\n')
print({f'{b}/{t}': len(i) for (b, t), i in sorted(por_lista.items())}, '| sem detalhe:', sem_detalhe, '| nossos (fora):', nossos, '| detalhes ok:', len(det))
imo = sorted(n for n, t in por_anunciante.items() if t == 'imobiliarias'); cor = sorted(n for n, t in por_anunciante.items() if t == 'corretores')
print(f'\nIMOBILIÁRIAS ({len(imo)}):', ' | '.join(imo))
print(f'\nCORRETORES ({len(cor)}):', ' | '.join(cor))
