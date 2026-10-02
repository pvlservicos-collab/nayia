# vw_painel_nai  (view, ~0 linhas)

## colunas
modo  text
numeros_teste  integer
locacao_pausada  boolean
nai_pausada  boolean
captacao_pausada  boolean
captacao_teste  boolean

## permissões
nay: DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE
nay_leitura: SELECT
nay_site_leitura: SELECT

## funções que escrevem aqui
(nenhuma função; quem escreve é o n8n, o site ou o CRM)

## funções que citam
(nenhuma)

## definição da view
 SELECT COALESCE(( SELECT nai_config.valor
           FROM nai_config
          WHERE nai_config.chave = 'modo'::text), 'desligado'::text) AS modo,
    (( SELECT count(*) AS count
           FROM unnest(string_to_array(COALESCE(( SELECT nai_config.valor
                   FROM nai_config
                  WHERE nai_config.chave = 'numeros_teste'::text), ''::text), ','::text)) x(x)
          WHERE btrim(x.x) <> ''::text))::integer AS numeros_teste,
    COALESCE(( SELECT config.valor = 'sim'::text
           FROM config
          WHERE config.chave = 'atendimento_pausado'::text), false) AS locacao_pausada,
    COALESCE(( SELECT nai_config.valor
           FROM nai_config
          WHERE nai_config.chave = 'pausada'::text), 'nao'::text) = 'sim'::text AS nai_pausada,
    COALESCE(( SELECT captacao_config.valor = 'sim'::text
           FROM captacao_config
          WHERE captacao_config.chave = 'captacao_pausada'::text), false) AS captacao_pausada,
    COALESCE(( SELECT captacao_config.valor = 'sim'::text
           FROM captacao_config
          WHERE captacao_config.chave = 'modo_teste'::text), false) AS captacao_teste;
