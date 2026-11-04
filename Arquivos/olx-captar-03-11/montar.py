"""IMÓVEIS CAPTAR OLX (585; Pedro, 03/11/2026): monta a carga de olx_captar a partir dos anúncios de particular abertos.

Passos (PC do Pedro, Chrome do Agente OLX ligado: nay-agentes/hermes-painel/navegador-olx.ps1 ligar):
  1. ./scripts/nay q Arquivos/olx-captar-03-11/base.sql | sed -n 2p > base.json
       os anúncios de PARTICULAR da lista 30 ("OLX · Recentes de Manaus"), com quantos anúncios o mesmo nome tem
  2. python montar.py fila base.json fila.json
       tira quem já tem nome de corretor/imobiliária ou aparece como profissional em outro anúncio
  3. node Arquivos/olx-scrape-teste-18-10/detalhes_fetch.js fila.json detalhes.jsonl 3
       abre cada anúncio (descrição, conta, telefone mascarado); retomável
  4. python montar.py carga base.json detalhes.jsonl carga.sql  ->  ./scripts/nay aplicar carga.sql
       a separação (o que sai e por quê, a nota de dono) é feita no banco, em carga.sql; quem já foi chamado continua anotado
"""
import json
import re
import sys

NOME_PRO = re.compile(r'corretor|creci|consultor|avaliador|broker|imobili|im[oó]veis|\bimob\b|imob$|\bltda|negoc|house|consultoria|'
                      r'empreend|constru|incorpora|administra|realty|\beireli\b|assessoria|investimentos|\bcia\b|grupo|lan[cç]amento', re.I)


def fila(arq_base, arq_fila):
    base = json.load(open(arq_base, encoding='utf-8'))
    f = [{'olx_id': x['olx_id'], 'url': x['url'], 'busca': x['busca']} for x in base
         if not NOME_PRO.search(x['anunciante'] or '') and not (x['nome_pro'] or 0)]
    json.dump(f, open(arq_fila, 'w', encoding='utf-8'))
    print(f'{len(base)} de particular; {len(f)} na fila (os outros têm nome de corretor/imobiliária ou outro anúncio profissional)')


CARGA = r"""-- carga de olx_captar (Arquivos/olx-captar-03-11/montar.py): %(n)d anúncios de particular abertos
BEGIN;
CREATE TEMP TABLE _d ON COMMIT DROP AS
SELECT * FROM jsonb_to_recordset($carga$%(json)s$carga$::jsonb) AS x(
  olx_id bigint, status int, erro text, profissional boolean, conta_pro boolean, anunciante text, anunciante_id text,
  descricao text, telefone_mascarado text, whatsapp boolean, publicado_em timestamptz, n_fotos int, nome_fora text);

CREATE TEMP TABLE _a ON COMMIT DROP AS
SELECT a.olx_id, a.url, a.titulo, a.preco, a.preco_texto, a.tipo_negocio, a.categoria, a.bairro, a.quartos, a.area_m2,
       a.fotos[1] AS foto, coalesce(d.n_fotos, a.n_fotos) AS n_fotos, coalesce(d.anunciante, a.anunciante) AS anunciante,
       d.anunciante_id, d.telefone_mascarado, d.whatsapp, d.descricao, coalesce(d.publicado_em, a.data_olx) AS publicado_em,
       d.status, d.erro, d.profissional, d.conta_pro, d.nome_fora,
       scrap_telefones_do_texto(d.descricao) AS telefones,
       -- o texto sem as frases de DONO que citam corretor ("não aceito corretor", "corretores, favor não ligar")
       regexp_replace(lower(coalesce(d.descricao, '')),
         '((n[aã]o\s+)?(aceito|aceita|aceitamos|trabalho\s+com|parceria\s+com)\s+(com\s+)?(parceria\s+)?(de\s+)?corretor\w*'
         '|sem\s+(corretor|imobili[aá]ri)\w*|dispenso\s+(corretor|imobili[aá]ri)\w*|corretor\w*\s*,?\s*(por\s+)?(favor\s+)?n[aã]o'
         '|n[aã]o\s+(sou|[eé])\s+(corretor|imobili[aá]ri)\w*|direto\s+com\s+(o\s+)?(propriet[aá]ri|dono)\w*\s*,?\s*sem\s+\w+)', ' ', 'g') AS texto
  FROM scrap_anuncio a JOIN _d d ON d.olx_id = a.olx_id
 WHERE a.lista_id = 30;

-- quantos anúncios cada conta e cada telefone têm (os abertos agora + toda a base do Scrap)
CREATE TEMP TABLE _conta ON COMMIT DROP AS
SELECT anunciante_id, count(DISTINCT olx_id) n FROM _d WHERE coalesce(anunciante_id, '') <> '' GROUP BY 1;
CREATE TEMP TABLE _tel ON COMMIT DROP AS
SELECT scrap_chave(t) chave, count(DISTINCT olx_id) n FROM (
  SELECT olx_id, unnest(telefones) t FROM _a
  UNION SELECT olx_id, unnest(telefones) FROM scrap_anuncio WHERE cardinality(telefones) > 0) z GROUP BY 1;

CREATE TEMP TABLE _j ON COMMIT DROP AS
SELECT a.*,
       coalesce((SELECT n FROM _conta c WHERE c.anunciante_id = a.anunciante_id), 1) AS n_conta,
       (SELECT max(n) FROM _tel t WHERE t.chave IN (SELECT scrap_chave(x) FROM unnest(a.telefones) x)) AS n_tel,
       coalesce(a.descricao, '') ~* '(propriet[aá]ri|\mdon[oa]\M|particular|sem\s+intermedi|direto\s+com\s+(o\s+|a\s+)?(propriet|dono|dona)'
                                   '|aceito\s+corretor|n[aã]o\s+aceito\s+corretor|tratar\s+direto|falar\s+direto)' AS diz_dono,
       coalesce(a.descricao, '') ~* '(\m(vendo|alugo|estou\s+vendendo|estou\s+alugando)\M|\mmeu\s+(apartamento|apto|ap|im[oó]vel|terreno)|\mminha\s+(casa|kitnet|kit))' AS primeira_pessoa
  FROM _a a;

INSERT INTO olx_captar AS c (olx_id, url, titulo, preco, preco_texto, tipo_negocio, categoria, bairro, quartos, area_m2, foto, n_fotos,
                             anunciante, anunciante_id, telefone, telefones, telefone_mascarado, whatsapp, descricao, publicado_em,
                             nota, sinais, fora, carregado_em)
SELECT olx_id, url, titulo, preco, preco_texto, tipo_negocio, categoria, bairro, quartos, area_m2, foto, n_fotos,
       anunciante, anunciante_id, telefones[1], telefones, telefone_mascarado, whatsapp, descricao, publicado_em,
       least(100, 60 + CASE WHEN diz_dono THEN 20 ELSE 0 END + CASE WHEN primeira_pessoa THEN 10 ELSE 0 END
                     + CASE WHEN n_conta = 1 THEN 10 ELSE 0 END + CASE WHEN cardinality(telefones) > 0 THEN 5 ELSE 0 END),
       array_remove(ARRAY['a OLX marca como particular',
                          CASE WHEN diz_dono THEN 'diz que é o dono / trata direto' END,
                          CASE WHEN primeira_pessoa THEN 'fala em primeira pessoa (vendo, alugo, meu, minha)' END,
                          CASE WHEN n_conta = 1 THEN 'só este anúncio na conta' ELSE 'tem 2 anúncios na conta' END,
                          CASE WHEN cardinality(telefones) > 0 THEN 'telefone no anúncio' END], NULL),
       CASE WHEN status IS DISTINCT FROM 200 OR erro IS NOT NULL THEN 'anúncio saiu da OLX'
            WHEN nome_fora IS NOT NULL THEN nome_fora
            WHEN profissional OR conta_pro THEN 'anúncio profissional'
            WHEN coalesce(descricao, '') ~* 'creci' THEN 'CRECI no anúncio'
            WHEN texto ~* '(\mcorretor\w*|\mimobili[aá]ria|\mintermedia\w*|\massessoria\s+imobili|\mcorretagem)' THEN 'corretor ou imobiliária no texto'
            WHEN texto ~* '(\mc[oó]d(igo)?\.?\s*(do\s+im[oó]vel)?\s*[:#.-]?\s*[a-z]{0,4}-?\d{2,}|\mref(er[eê]ncia)?\.?\s*[:#-]\s*[a-z]{0,4}-?\d{2,})' THEN 'código de imobiliária no anúncio'
            WHEN n_conta >= 3 THEN 'muitos imóveis (3 ou mais anúncios na conta)'
            WHEN coalesce(n_tel, 0) >= 3 THEN 'muitos imóveis (telefone em 3 ou mais anúncios)'
            WHEN least(100, 60 + CASE WHEN diz_dono THEN 20 ELSE 0 END + CASE WHEN primeira_pessoa THEN 10 ELSE 0 END
                     + CASE WHEN n_conta = 1 THEN 10 ELSE 0 END + CASE WHEN cardinality(telefones) > 0 THEN 5 ELSE 0 END) < 70
              THEN 'nota de dono baixa (menos de 70)'
       END,
       now()
  FROM _j
ON CONFLICT (olx_id) DO UPDATE SET
  url = EXCLUDED.url, titulo = EXCLUDED.titulo, preco = EXCLUDED.preco, preco_texto = EXCLUDED.preco_texto,
  tipo_negocio = EXCLUDED.tipo_negocio, categoria = EXCLUDED.categoria, bairro = EXCLUDED.bairro, quartos = EXCLUDED.quartos,
  area_m2 = EXCLUDED.area_m2, foto = EXCLUDED.foto, n_fotos = EXCLUDED.n_fotos, anunciante = EXCLUDED.anunciante,
  anunciante_id = EXCLUDED.anunciante_id, telefone = EXCLUDED.telefone, telefones = EXCLUDED.telefones,
  telefone_mascarado = EXCLUDED.telefone_mascarado, whatsapp = EXCLUDED.whatsapp, descricao = EXCLUDED.descricao,
  publicado_em = EXCLUDED.publicado_em, nota = EXCLUDED.nota, sinais = EXCLUDED.sinais, fora = EXCLUDED.fora,
  carregado_em = EXCLUDED.carregado_em;

SELECT coalesce(fora, '(entra)') AS como, count(*) FROM olx_captar GROUP BY 1 ORDER BY 2 DESC;
COMMIT;
"""


def carga(arq_base, arq_det, arq_sql):
    base = {x['olx_id']: x for x in json.load(open(arq_base, encoding='utf-8'))}
    det = {}
    for linha in open(arq_det, encoding='utf-8'):
        if linha.strip():
            d = json.loads(linha)
            det[d['olx_id']] = d   # a última tentativa vale
    itens = []
    for oid, b in base.items():
        d = det.get(oid)
        if d is None:   # ficou fora da fila pelo nome
            if NOME_PRO.search(b['anunciante'] or ''):
                itens.append({'olx_id': oid, 'status': 200, 'nome_fora': 'nome de corretor ou imobiliária'})
            elif b['nome_pro']:
                itens.append({'olx_id': oid, 'status': 200, 'nome_fora': 'o mesmo nome anuncia como profissional'})
            continue
        itens.append({k: d.get(k) for k in ('olx_id', 'status', 'erro', 'profissional', 'conta_pro', 'anunciante', 'anunciante_id',
                                            'descricao', 'telefone_mascarado', 'whatsapp', 'publicado_em', 'n_fotos')})
    js = json.dumps(itens, ensure_ascii=False)
    assert '$carga$' not in js
    open(arq_sql, 'w', encoding='utf-8', newline='\n').write(CARGA % {'n': len(itens), 'json': js})
    print(f'{len(itens)} anúncios na carga ({sum(1 for i in itens if "nome_fora" in i)} fora pelo nome) -> {arq_sql}')


if __name__ == '__main__':
    {'fila': fila, 'carga': carga}[sys.argv[1]](*sys.argv[2:])
