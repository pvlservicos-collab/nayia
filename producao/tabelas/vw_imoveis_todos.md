# vw_imoveis_todos  (view, ~0 linhas)

## colunas
codigo  integer
status  text
no_catalogo  boolean
tipo  text
grupo_tipo  text
condominio  text
condo_id  integer
bairro  text
endereco  text
valor_venda  numeric
valor_aluguel  numeric
valor_texto  text
quartos  integer
vagas  integer
area  numeric
suites  integer
banheiros  integer
area_total  numeric
fotos  bigint
capa  text
precisa_confirmacao  boolean
e_parceiro  boolean
financia  text
publicado_no_site  boolean
bloqueado  boolean
vencimento  date
proprietario_nome  text
proprietario_id  integer
criado  timestamp with time zone

## permissões
nay: DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE
nay_leitura: SELECT
nay_site_leitura: SELECT

## funções que escrevem aqui
(nenhuma função; quem escreve é o n8n, o site ou o CRM)

## funções que citam
(nenhuma)

## definição da view
 WITH cods AS (
         SELECT imoveis.codigo
           FROM imoveis
        UNION
         SELECT imoveis_admin_snapshot.codigo::integer AS codigo
           FROM imoveis_admin_snapshot
          WHERE imoveis_admin_snapshot.codigo ~ '^[0-9]+$'::text
        UNION
         SELECT imoveis_admin_detalhe.codigo::integer AS codigo
           FROM imoveis_admin_detalhe
          WHERE imoveis_admin_detalhe.codigo ~ '^[0-9]+$'::text
        UNION
         SELECT imoveis_vendidos.codigo
           FROM imoveis_vendidos
        UNION
         SELECT imoveis_arquivados.codigo
           FROM imoveis_arquivados
        UNION
         SELECT imoveis_removidos.codigo
           FROM imoveis_removidos
        UNION
         SELECT imoveis_rascunho.codigo
           FROM imoveis_rascunho
        UNION
         SELECT imoveis_revisao.codigo
           FROM imoveis_revisao
        ), fot AS (
         SELECT imovel_fotos.codigo,
            count(*) AS n,
            min(imovel_fotos.url) FILTER (WHERE imovel_fotos.e_capa) AS capa_marcada,
            (array_agg(imovel_fotos.url ORDER BY imovel_fotos.ordem, imovel_fotos.id))[1] AS primeira
           FROM imovel_fotos
          WHERE COALESCE(imovel_fotos.url, ''::text) <> ''::text
          GROUP BY imovel_fotos.codigo
        )
 SELECT c.codigo,
        CASE
            WHEN i.status = 'Revisão'::text THEN 'Em revisão'::text
            WHEN COALESCE(i.status, ''::text) <> ''::text THEN i.status
            WHEN s.status_admin IS NOT NULL THEN s.status_admin
            WHEN v.codigo IS NOT NULL THEN 'Vendido'::text
            WHEN a.codigo IS NOT NULL THEN 'Arquivado'::text
            WHEN r.codigo IS NOT NULL THEN 'Removido'::text
            WHEN ra.codigo IS NOT NULL THEN 'Rascunho'::text
            WHEN rv.codigo IS NOT NULL THEN 'Em revisão'::text
            WHEN i.codigo IS NOT NULL AND i.disponivel AND i.publicado_no_site THEN 'Disponível'::text
            WHEN i.codigo IS NOT NULL AND NOT COALESCE(i.disponivel, true) THEN 'Indisponível'::text
            ELSE 'Fora do site'::text
        END AS status,
    i.codigo IS NOT NULL AS no_catalogo,
    COALESCE(i.tipo, d.tipo) AS tipo,
        CASE
            WHEN COALESCE(i.tipo, d.tipo) ~* '^(apartamento|cobertura|flat|kitnet|studio)'::text THEN 'apartamento'::text
            WHEN COALESCE(i.tipo, d.tipo) ~* '^casa'::text THEN 'casa'::text
            WHEN COALESCE(i.tipo, d.tipo) IS NULL THEN 'sem_tipo'::text
            ELSE 'outros'::text
        END AS grupo_tipo,
    COALESCE(NULLIF(btrim(i.condominio_nome), ''::text), NULLIF(btrim(d.condominio), ''::text), NULLIF(btrim(COALESCE(v.condominio, a.condominio, r.condominio, ra.condominio, rv.condominio)), ''::text)) AS condominio,
    COALESCE(i.condo_id, d.condominio_id) AS condo_id,
    COALESCE(NULLIF(i.bairro, ''::text), NULLIF(d.bairro, ''::text)) AS bairro,
    COALESCE(NULLIF(concat_ws(', '::text, NULLIF(i.logradouro, ''::text), NULLIF(i.numero, ''::text)), ''::text), NULLIF(concat_ws(', '::text, NULLIF(d.logradouro, ''::text), NULLIF(d.numero, ''::text)), ''::text), COALESCE(v.endereco, a.endereco, r.endereco, ra.endereco, rv.endereco)) AS endereco,
    COALESCE(i.valor_venda, d.valor_venda) AS valor_venda,
    COALESCE(i.valor_aluguel, d.valor_aluguel) AS valor_aluguel,
    COALESCE(v.valor, a.valor, r.valor, ra.valor, rv.valor) AS valor_texto,
    COALESCE(i.quartos, d.quartos) AS quartos,
    COALESCE(i.vagas, d.vagas) AS vagas,
    COALESCE(i.area_util, d.area) AS area,
    i.suites,
    i.banheiros,
    COALESCE(i.area_total, i.area_util, d.area) AS area_total,
    COALESCE(fot.n, 0::bigint) AS fotos,
    COALESCE(fot.capa_marcada, fot.primeira) AS capa,
    COALESCE(i.precisa_confirmacao, false) AS precisa_confirmacao,
    COALESCE(i.e_parceiro, false) OR nai_dono_e_parceiro(COALESCE(pn.nome, pa.nome, v.proprietario_nome, a.proprietario_nome, r.proprietario_nome, ra.proprietario_nome, rv.proprietario_nome)) AS e_parceiro,
        CASE
            WHEN COALESCE(i.extras ->> 'aceita financiamento'::text, d.financiamento, ''::text) ~* '^s'::text THEN 'Sim'::text
            WHEN COALESCE(i.extras ->> 'aceita financiamento'::text, d.financiamento, ''::text) ~* '^n'::text THEN 'Não'::text
            ELSE '—'::text
        END AS financia,
    COALESCE(i.publicado_no_site, false) AS publicado_no_site,
    COALESCE(i.bloqueado, false) AS bloqueado,
    ct.vencimento,
    COALESCE(pn.nome, pa.nome, v.proprietario_nome, a.proprietario_nome, r.proprietario_nome, ra.proprietario_nome, rv.proprietario_nome) AS proprietario_nome,
    i.proprietario_id,
    COALESCE(i.criado_em, d.captado_em::timestamp with time zone, s.coletado_em, v.extraido_em, a.extraido_em, r.extraido_em, ra.extraido_em, rv.extraido_em) AS criado
   FROM cods c
     LEFT JOIN imoveis i ON i.codigo = c.codigo
     LEFT JOIN imoveis_admin_snapshot s ON s.codigo = c.codigo::text
     LEFT JOIN imoveis_admin_detalhe d ON d.codigo = c.codigo::text
     LEFT JOIN imoveis_vendidos v ON v.codigo = c.codigo
     LEFT JOIN imoveis_arquivados a ON a.codigo = c.codigo
     LEFT JOIN imoveis_removidos r ON r.codigo = c.codigo
     LEFT JOIN imoveis_rascunho ra ON ra.codigo = c.codigo
     LEFT JOIN imoveis_revisao rv ON rv.codigo = c.codigo
     LEFT JOIN contratos_locacao ct ON ct.codigo = c.codigo::text
     LEFT JOIN proprietarios_admin pa ON pa.id = s.proprietario_id
     LEFT JOIN proprietarios pn ON pn.id = i.proprietario_id
     LEFT JOIN fot ON fot.codigo = c.codigo;
