# vw_nai_envios_resumo  (view, ~0 linhas)
Quantos envios, e quantos foram dela. Painel da locacao.

## colunas
total  bigint
da_nay  bigint
de_gente  bigint
nas_24h  bigint
da_nay_24h  bigint
pessoas  bigint

## permissões
nay: DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE
nay_leitura: SELECT
nay_site_nai: SELECT

## funções que escrevem aqui
(nenhuma função; quem escreve é o n8n, o site ou o CRM)

## funções que citam
(nenhuma)

## definição da view
 SELECT count(*) AS total,
    count(*) FILTER (WHERE quem_mandou = 'a Nay'::text) AS da_nay,
    count(*) FILTER (WHERE quem_mandou = 'alguém digitou'::text) AS de_gente,
    count(*) FILTER (WHERE quando > (now() - '24:00:00'::interval)) AS nas_24h,
    count(*) FILTER (WHERE quando > (now() - '24:00:00'::interval) AND quem_mandou = 'a Nay'::text) AS da_nay_24h,
    count(DISTINCT para_quem) AS pessoas
   FROM vw_nai_envios;
