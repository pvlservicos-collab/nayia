-- 005: o MODELO DE LEITURA do imóvel (setor cérebro). Só leitura sobre as
-- tabelas do sistema velho; nada nelas é alterado.
--
-- Por que existe: cada função do velho recalculava por conta própria o que é
-- "ofertável", a finalidade, o tipo e o dono -- e cada uma de um jeito
-- (perguntas 9, 28, 35, 38). Aqui isso é calculado UMA vez, com nome e índice,
-- e o nay-core só lê.
--
-- Funções de extensão sempre qualificadas (public.unaccent com o dicionário
-- explícito): o pg_restore roda com search_path vazio, e objeto que depende
-- dele não volta (achado no teste de restauração de 30/09).

-- O DONO DE CADA IMÓVEL, com a origem (materializado: a comparação de telefone
-- entre donos, feita como view, levava mais de 60 s por consulta). Fonte principal: imoveis.proprietario_id
-- (5.647 preenchidos, o vínculo do site e do CRM); imovel_privado completa; o
-- admin antigo só quando os dois faltam e ele tem UM dono. Medido em 30/09:
-- onde imoveis e imovel_privado têm dono, os dois batem em 100%, e nenhum id
-- é órfão. `mesmo_telefone_em` lista os outros imóveis cujo dono (outra
-- pessoa no cadastro) tem o mesmo telefone (8 últimos dígitos) -- em 30/09,
-- 15 das 37 locações ofertáveis, por exemplo 2014, 5757, 5628 e 5629 com o
-- mesmo número. Pode ser administrador ou parente; a visita a esses imóveis
-- pede que alguém confira antes de falar com o dono.
DROP MATERIALIZED VIEW IF EXISTS core_imovel_dono;
CREATE MATERIALIZED VIEW core_imovel_dono AS
WITH base AS (
  SELECT i.codigo,
         coalesce(i.proprietario_id, p.proprietario_id) AS proprietario_id,
         CASE WHEN i.proprietario_id IS NOT NULL THEN 'imovel'
              WHEN p.proprietario_id IS NOT NULL THEN 'privado' END AS origem
    FROM imoveis i LEFT JOIN imovel_privado p ON p.codigo = i.codigo
),
admin AS (
  SELECT a.codigo::int AS codigo, count(DISTINCT a.proprietario_id) AS donos,
         min(pa.nome) AS nome, min(pa.telefone) AS telefone
    FROM proprietarios_admin_imoveis a JOIN proprietarios_admin pa ON pa.id = a.proprietario_id
   WHERE a.codigo ~ '^\d{1,6}$'
   GROUP BY 1
),
dono AS (
  SELECT b.codigo, b.proprietario_id,
         coalesce(b.origem, CASE WHEN ad.donos = 1 THEN 'admin' END) AS origem,
         CASE WHEN b.origem IS NOT NULL THEN pr.nome ELSE ad.nome END AS nome,
         CASE WHEN b.origem IS NOT NULL THEN pr.telefone
              WHEN ad.donos = 1 THEN ad.telefone END AS telefone_bruto,
         (b.origem IS NULL AND coalesce(ad.donos, 0) > 1) AS dois_donos
    FROM base b
    LEFT JOIN proprietarios pr ON pr.id = b.proprietario_id
    LEFT JOIN admin ad ON ad.codigo = b.codigo
),
com_tel AS (
  SELECT d.*,
         -- os dígitos do PRIMEIRO telefone do campo; a chave final é do Python
         substring(regexp_replace(coalesce(d.telefone_bruto, ''), '[^\d/;,]', '', 'g') FROM '\d{8,13}') AS telefone_digitos
    FROM dono d
),
repetido AS (
  -- mesmo telefone (8 últimos dígitos), outro proprietário: hash join, uma vez
  SELECT a.codigo, array_agg(DISTINCT b.codigo ORDER BY b.codigo) AS outros
    FROM com_tel a JOIN com_tel b
      ON right(a.telefone_digitos, 8) = right(b.telefone_digitos, 8)
     AND a.codigo <> b.codigo
     AND a.proprietario_id IS DISTINCT FROM b.proprietario_id
   WHERE a.telefone_digitos IS NOT NULL AND b.telefone_digitos IS NOT NULL
   GROUP BY a.codigo
)
SELECT c.codigo, c.proprietario_id, c.origem, c.nome, c.telefone_bruto, c.telefone_digitos,
       c.dois_donos,
       coalesce(c.nome, '') ~* '(tratar|falar|contato)\s+com' AS tratar_com_outra_pessoa,
       r.outros AS mesmo_telefone_em,
       now() AS montado_em
  FROM com_tel c LEFT JOIN repetido r ON r.codigo = c.codigo;

CREATE UNIQUE INDEX core_imovel_dono_codigo ON core_imovel_dono (codigo);
CREATE INDEX core_imovel_dono_telefone ON core_imovel_dono (right(telefone_digitos, 8)) WHERE telefone_digitos IS NOT NULL;

COMMENT ON MATERIALIZED VIEW core_imovel_dono IS
  'nay-core: o dono de cada imóvel e de onde veio (imovel > privado > admin), com telefone repetido entre donos. REFRESH CONCURRENTLY pelo worker (005).';

-- A FICHA DE BUSCA, materializada. 5,7 mil linhas: cabe inteira e responde em
-- milissegundos com índice. É atualizada pelo worker (REFRESH CONCURRENTLY a
-- cada 10 min, e logo depois da varredura do catálogo). `ofertavel` é a
-- definição única: disponível, não bloqueado, publicado, não parceiro, com
-- preço na finalidade.
DROP MATERIALIZED VIEW IF EXISTS core_imovel_busca;
CREATE MATERIALIZED VIEW core_imovel_busca AS
SELECT i.codigo,
       i.tipo AS tipo_original,
       CASE
         WHEN i.tipo IN ('Apartamento', 'Apartamento em Via Pública') THEN 'apartamento'
         WHEN i.tipo = 'Casa de condomínio' THEN 'casa_condominio'
         WHEN i.tipo = 'Casa' THEN 'casa'
         WHEN i.tipo = 'Flat' THEN 'flat'
         WHEN i.tipo = 'Cobertura' THEN 'cobertura'
         WHEN i.tipo LIKE 'Sala%' THEN 'sala'
         WHEN i.tipo LIKE 'Loja%' THEN 'loja'
         WHEN i.tipo LIKE 'Lote%' THEN 'terreno'
         ELSE 'outro' END AS tipo,
       coalesce(i.valor_aluguel, 0) > 0 AS de_locacao,
       coalesce(i.valor_venda, 0) > 0 AS de_venda,
       i.valor_aluguel, i.valor_venda, i.taxa_condominio,
       i.bairro,
       lower(public.unaccent('public.unaccent'::regdictionary, coalesce(i.bairro, ''))) AS bairro_norm,
       z.zona,
       i.condominio_nome,
       lower(public.unaccent('public.unaccent'::regdictionary, coalesce(i.condominio_nome, ''))) AS condominio_norm,
       i.quartos, i.suites, i.vagas, i.area_util,
       CASE
         WHEN i.mobilia ~* '^\s*semi' THEN 'semi'
         WHEN i.mobilia ~* '^\s*mobiliad' THEN 'mobiliado'
         WHEN i.mobilia ~* 'ar.condicionado' THEN 'nao'
         END AS mobilia,
       (SELECT count(*) FROM imovel_fotos f WHERE f.codigo = i.codigo AND NOT coalesce(f.e_mosaico, false)) AS qtd_fotos,
       EXISTS (SELECT 1 FROM imovel_ficha f WHERE f.codigo = i.codigo AND f.encontrado) AS tem_ficha,
       coalesce(i.e_parceiro, false) AS e_parceiro,
       (coalesce(i.disponivel, true) AND NOT coalesce(i.bloqueado, false)
        AND coalesce(i.publicado_no_site, false) AND NOT coalesce(i.e_parceiro, false)
        AND (coalesce(i.valor_aluguel, 0) > 0 OR coalesce(i.valor_venda, 0) > 0)) AS ofertavel,
       -- no mercado mas sem preço (10 em 30/09): não entra em busca, sai só pelo código
       (coalesce(i.disponivel, true) AND NOT coalesce(i.bloqueado, false)
        AND coalesce(i.publicado_no_site, false) AND NOT coalesce(i.e_parceiro, false)) AS no_mercado,
       now() AS montado_em
  FROM imoveis i
  LEFT JOIN bairro_zona z
    ON lower(public.unaccent('public.unaccent'::regdictionary, z.bairro))
     = lower(public.unaccent('public.unaccent'::regdictionary, coalesce(i.bairro, '')));

-- único (exigido pelo REFRESH CONCURRENTLY) e os caminhos da busca
CREATE UNIQUE INDEX core_imovel_busca_codigo ON core_imovel_busca (codigo);
CREATE INDEX core_imovel_busca_locacao ON core_imovel_busca (tipo, bairro_norm, valor_aluguel) WHERE ofertavel AND de_locacao;
CREATE INDEX core_imovel_busca_venda ON core_imovel_busca (tipo, bairro_norm, valor_venda) WHERE ofertavel AND de_venda;
CREATE INDEX core_imovel_busca_zona ON core_imovel_busca (zona) WHERE ofertavel;
CREATE INDEX core_imovel_busca_condominio ON core_imovel_busca USING gin (condominio_norm public.gin_trgm_ops) WHERE ofertavel;

COMMENT ON MATERIALIZED VIEW core_imovel_busca IS
  'nay-core: um imóvel por linha com tipo, finalidade, zona, mobília e "ofertável" calculados uma vez. REFRESH CONCURRENTLY pelo worker (005).';
