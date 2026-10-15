# mv_vocabulario_nomes  (view materializada, ~185 linhas)

## colunas
nome  text
especie  text
palavras  integer
tamanho  integer
chave  text

## índices
CREATE INDEX mv_vocabulario_palavras ON public.mv_vocabulario_nomes USING btree (palavras, tamanho)
CREATE INDEX mv_vocabulario_trgm ON public.mv_vocabulario_nomes USING gin (chave gin_trgm_ops)

## permissões
nay: DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE
nay_core: SELECT
nay_leitura: SELECT
nay_site_nai: SELECT

## funções que escrevem aqui
(nenhuma função; quem escreve é o n8n, o site ou o CRM)

## funções que citam
nai_corrigir_nomes, nai_vocabulario_atualizar

## definição da view
 SELECT nome,
    especie,
    array_length(regexp_split_to_array(btrim(nome), '\s+'::text), 1) AS palavras,
    length(nome) AS tamanho,
    lower(unaccent(nome)) AS chave
   FROM vw_vocabulario_nomes;
