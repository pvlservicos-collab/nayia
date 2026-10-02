# vw_nai_acoplamento  (view, ~0 linhas)
Funcoes da Nay ANTIGA que a NAI nova chama, e quais setores dependem delas (Tel, 19/09).

## colunas
funcao_antiga  text
setor_da_antiga  text
quantas_nai_chamam  bigint
chamada_por  text
setores_afetados  text

## permissões
nay: DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE
nay_leitura: SELECT
nay_site_nai: SELECT

## funções que escrevem aqui
(nenhuma função; quem escreve é o n8n, o site ou o CRM)

## funções que citam
(nenhuma)

## definição da view
 WITH nova AS (
         SELECT p.proname::text AS proname,
            p.prosrc,
            nai_setor_final(p.proname::text) AS setor
           FROM pg_proc p
             JOIN pg_namespace n ON n.oid = p.pronamespace
          WHERE n.nspname = 'public'::name AND p.proname ~~ 'nai\_%'::text AND p.prokind = 'f'::"char"
        ), antiga AS (
         SELECT DISTINCT p.proname::text AS proname,
            nai_setor_final(p.proname::text) AS setor
           FROM pg_proc p
             JOIN pg_namespace n ON n.oid = p.pronamespace
          WHERE n.nspname = 'public'::name AND p.proname ~~ 'nay\_%'::text AND p.prokind = 'f'::"char"
        )
 SELECT a.proname AS funcao_antiga,
    a.setor AS setor_da_antiga,
    count(DISTINCT v.proname) AS quantas_nai_chamam,
    string_agg(DISTINCT v.proname, ', '::text ORDER BY v.proname) AS chamada_por,
    string_agg(DISTINCT v.setor, ', '::text ORDER BY v.setor) AS setores_afetados
   FROM antiga a
     JOIN nova v ON v.prosrc ~ (('\m'::text || a.proname) || '\M'::text)
  GROUP BY a.proname, a.setor
  ORDER BY (count(DISTINCT v.proname)) DESC, a.proname;
