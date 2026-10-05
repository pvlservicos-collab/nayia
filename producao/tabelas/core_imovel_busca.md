# core_imovel_busca  (view materializada, ~5690 linhas)
nay-core: um imóvel por linha com tipo, finalidade, zona, mobília e "ofertável" calculados uma vez. REFRESH CONCURRENTLY pelo worker (005).

## colunas
codigo  integer
tipo_original  text
tipo  text
de_locacao  boolean
de_venda  boolean
valor_aluguel  numeric
valor_venda  numeric
taxa_condominio  numeric
bairro  text
bairro_norm  text
zona  text
condominio_nome  text
condominio_norm  text
quartos  integer
suites  integer
vagas  integer
area_util  numeric
mobilia  text
qtd_fotos  bigint
tem_ficha  boolean
e_parceiro  boolean
ofertavel  boolean
no_mercado  boolean
montado_em  timestamp with time zone

## índices
CREATE INDEX core_imovel_busca_condominio ON public.core_imovel_busca USING gin (condominio_norm gin_trgm_ops) WHERE ofertavel
CREATE INDEX core_imovel_busca_locacao ON public.core_imovel_busca USING btree (tipo, bairro_norm, valor_aluguel) WHERE (ofertavel AND de_locacao)
CREATE INDEX core_imovel_busca_venda ON public.core_imovel_busca USING btree (tipo, bairro_norm, valor_venda) WHERE (ofertavel AND de_venda)
CREATE INDEX core_imovel_busca_zona ON public.core_imovel_busca USING btree (zona) WHERE ofertavel
CREATE UNIQUE INDEX core_imovel_busca_codigo ON public.core_imovel_busca USING btree (codigo)

## permissões
nay_core: DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE
nay_leitura: SELECT

## funções que escrevem aqui
(nenhuma função; quem escreve é o n8n, o site ou o CRM)

## funções que citam
(nenhuma)

## definição da view
 SELECT i.codigo,
    i.tipo AS tipo_original,
        CASE
            WHEN i.tipo = ANY (ARRAY['Apartamento'::text, 'Apartamento em Via Pública'::text]) THEN 'apartamento'::text
            WHEN i.tipo = 'Casa de condomínio'::text THEN 'casa_condominio'::text
            WHEN i.tipo = 'Casa'::text THEN 'casa'::text
            WHEN i.tipo = 'Flat'::text THEN 'flat'::text
            WHEN i.tipo = 'Cobertura'::text THEN 'cobertura'::text
            WHEN i.tipo ~~ 'Sala%'::text THEN 'sala'::text
            WHEN i.tipo ~~ 'Loja%'::text THEN 'loja'::text
            WHEN i.tipo ~~ 'Lote%'::text THEN 'terreno'::text
            ELSE 'outro'::text
        END AS tipo,
    COALESCE(i.valor_aluguel, 0::numeric) > 0::numeric AS de_locacao,
    COALESCE(i.valor_venda, 0::numeric) > 0::numeric AS de_venda,
    i.valor_aluguel,
    i.valor_venda,
    i.taxa_condominio,
    i.bairro,
    lower(unaccent('unaccent'::regdictionary, COALESCE(i.bairro, ''::text))) AS bairro_norm,
    z.zona,
    i.condominio_nome,
    lower(unaccent('unaccent'::regdictionary, COALESCE(i.condominio_nome, ''::text))) AS condominio_norm,
    i.quartos,
    i.suites,
    i.vagas,
    i.area_util,
        CASE
            WHEN i.mobilia ~* '^\s*semi'::text THEN 'semi'::text
            WHEN i.mobilia ~* '^\s*mobiliad'::text THEN 'mobiliado'::text
            WHEN i.mobilia ~* 'ar.condicionado'::text THEN 'nao'::text
            ELSE NULL::text
        END AS mobilia,
    ( SELECT count(*) AS count
           FROM imovel_fotos f
          WHERE f.codigo = i.codigo AND NOT COALESCE(f.e_mosaico, false)) AS qtd_fotos,
    (EXISTS ( SELECT 1
           FROM imovel_ficha f
          WHERE f.codigo = i.codigo AND f.encontrado)) AS tem_ficha,
    COALESCE(i.e_parceiro, false) AS e_parceiro,
    COALESCE(i.disponivel, true) AND NOT COALESCE(i.bloqueado, false) AND COALESCE(i.publicado_no_site, false) AND NOT COALESCE(i.e_parceiro, false) AND (COALESCE(i.valor_aluguel, 0::numeric) > 0::numeric OR COALESCE(i.valor_venda, 0::numeric) > 0::numeric) AS ofertavel,
    COALESCE(i.disponivel, true) AND NOT COALESCE(i.bloqueado, false) AND COALESCE(i.publicado_no_site, false) AND NOT COALESCE(i.e_parceiro, false) AS no_mercado,
    now() AS montado_em
   FROM imoveis i
     LEFT JOIN bairro_zona z ON lower(unaccent('unaccent'::regdictionary, z.bairro)) = lower(unaccent('unaccent'::regdictionary, COALESCE(i.bairro, ''::text)));
