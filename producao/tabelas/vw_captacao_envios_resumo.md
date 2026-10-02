# vw_captacao_envios_resumo  (view, ~0 linhas)
Quantos envios, e quantos foram dela. Painel da captacao.

## colunas
total  bigint
da_nay  bigint
de_gente  bigint
primeiras  bigint
nas_24h  bigint
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
    count(*) FILTER (WHERE quem_mandou ~~ 'a Nay%'::text) AS da_nay,
    count(*) FILTER (WHERE quem_mandou = 'alguém digitou'::text) AS de_gente,
    count(*) FILTER (WHERE quem_mandou = 'a Nay (1ª mensagem)'::text) AS primeiras,
    count(*) FILTER (WHERE quando > (now() - '24:00:00'::interval)) AS nas_24h,
    count(DISTINCT para_quem) AS pessoas
   FROM vw_captacao_envios;
