# vw_vocabulario_nomes  (view, ~0 linhas)

## colunas
nome  text
especie  text

## permissões
nay: DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE
nay_leitura: SELECT

## funções que escrevem aqui
(nenhuma função; quem escreve é o n8n, o site ou o CRM)

## funções que citam
(nenhuma)

## definição da view
 SELECT DISTINCT btrim(i.bairro) AS nome,
    'bairro'::text AS especie
   FROM imoveis i
  WHERE nay_esta_no_mercado(i.disponivel, i.bloqueado, i.publicado_no_site) AND btrim(COALESCE(i.bairro, ''::text)) <> ''::text AND length(btrim(i.bairro)) >= 5
UNION
 SELECT DISTINCT v.nucleo AS nome,
    'condominio'::text AS especie
   FROM vw_condominio_som v
  WHERE length(COALESCE(v.nucleo, ''::text)) >= 5 AND NOT nai_palavra_comum(v.nucleo);
