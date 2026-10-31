# vw_imovel_pontuacao  (view, ~0 linhas)
244: quanto de cada imóvel está preenchido (0 a 100%), por peso

## colunas
codigo  integer
pct  integer
pontos  numeric
de  numeric
falta  text[]
falta_essencial  text[]
oferecido  boolean

## permissões
nay: DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE
nay_leitura: SELECT
nay_site_escrita: SELECT
nay_site_leitura: SELECT

## funções que escrevem aqui
(nenhuma função; quem escreve é o n8n, o site ou o CRM)

## funções que citam
crm_imoveis_pontuacao, nai_cadastro_pendente

## definição da view
 SELECT i.codigo,
    (p.p ->> 'pct'::text)::integer AS pct,
    (p.p ->> 'pontos'::text)::numeric AS pontos,
    (p.p ->> 'de'::text)::numeric AS de,
    ARRAY( SELECT jsonb_array_elements_text(p.p -> 'falta'::text) AS jsonb_array_elements_text) AS falta,
    ARRAY( SELECT jsonb_array_elements_text(p.p -> 'falta_essencial'::text) AS jsonb_array_elements_text) AS falta_essencial,
    nay_esta_no_mercado(i.disponivel, i.bloqueado, i.publicado_no_site) AND NOT COALESCE(i.e_parceiro, false) AS oferecido
   FROM imoveis i
     CROSS JOIN LATERAL nai_imovel_pontos(i.codigo) p(p);
