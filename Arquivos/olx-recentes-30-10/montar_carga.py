"""A carga da raspagem dos anúncios RECENTES da OLX (30/10/2026) no Scrap: uma lista só, "OLX · Recentes de Manaus",
na pasta Cadastro -- é a base que o Cadastrar imóvel pelo link do CRM (535) procura. Fica fora da pasta OLX (as listas de
prospecção). Sem a descrição (a raspagem não abre anúncio por anúncio); as características vão em dados.campos, que é
o que o cadastro lê.

uso: python montar_carga.py <pasta da raspagem> <saida.sql>"""
import json
import sys

pasta, saida = sys.argv[1], sys.argv[2]
todos = json.load(open(f'{pasta}/todos.json', encoding='utf-8'))

itens, vistos = [], set()
for a in todos:
    if not a.get('olx_id') or a['olx_id'] in vistos:
        continue
    vistos.add(a['olx_id'])
    item = {k: a.get(k) for k in ('olx_id', 'titulo', 'preco', 'preco_texto', 'preco_antigo', 'categoria', 'tipo_negocio', 'subtipo',
                                  'quartos', 'banheiros', 'vagas', 'area_m2', 'condominio_valor', 'iptu_valor', 'bairro', 'n_fotos',
                                  'fotos', 'url', 'data', 'anunciante')}
    item['dados'] = {k: a.get(k) for k in ('campos', 'local', 'detalhes_imovel', 'detalhes_condominio', 'destaque', 'patrocinado',
                                           'baixou_preco', 'ultimo_bump_seg') if a.get(k) is not None}
    item['dados']['tipo_anunciante'] = 'profissional' if a.get('profissional') else 'particular'
    item['dados']['busca'] = a.get('busca')
    itens.append(item)

corpo = {'lista': {'nome': 'OLX · Recentes de Manaus', 'cor': '#0e7490', 'pasta': 'Cadastro', 'origem': 'olx',
                   'url_busca': 'https://www.olx.com.br/imoveis/estado-am/regiao-de-manaus/manaus?sf=1',
                   'descricao': 'Os anúncios mais recentes de Manaus (aluguel e venda, todos os anunciantes e preços), para o '
                                'Cadastrar imóvel pelo link do CRM. Não é lista de prospecção.'},
         'anuncios': itens}
js = json.dumps(corpo, ensure_ascii=False).replace('\\u0000', '')
assert '$carga$' not in js
with open(saida, 'w', encoding='utf-8', newline='\n') as f:
    f.write('-- carga dos anúncios recentes da OLX (30/10/2026) no Scrap, pasta Cadastro\nBEGIN;\n')
    f.write(f"SELECT site_scrap_importar($carga${js}$carga$::jsonb, 'Pedro (raspagem recentes OLX 30/10)') AS r;\n")
    f.write('COMMIT;\n')
particulares = sum(1 for i in itens if i['dados']['tipo_anunciante'] == 'particular')
print(f'{len(itens)} anúncios ({particulares} de particular) | com fotos: {sum(1 for i in itens if i.get("fotos"))}')
