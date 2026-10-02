# vw_nai_funcao_viva  (view, ~0 linhas)
Toda funcao nai_/nay_/captacao_ viva no banco, com o setor dela.

## colunas
funcao  text
args  text
setor  text
familia  text
tamanho  integer
hash  text
oid  oid

## permissões
nay: DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE
nay_leitura: SELECT
nay_site_nai: SELECT

## funções que escrevem aqui
(nenhuma função; quem escreve é o n8n, o site ou o CRM)

## funções que citam
nai_foto_diferenca, nai_foto_tirar

## definição da view
 SELECT p.proname::text AS funcao,
    pg_get_function_identity_arguments(p.oid) AS args,
    nai_setor_final(p.proname::text) AS setor,
        CASE
            WHEN p.proname ~~ 'nai\_%'::text THEN 'nai'::text
            WHEN p.proname ~~ 'nay\_%'::text THEN 'nay'::text
            ELSE 'outra'::text
        END AS familia,
    length(p.prosrc) AS tamanho,
    md5(p.prosrc) AS hash,
    p.oid
   FROM pg_proc p
     JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public'::name AND p.prokind = 'f'::"char" AND p.proname ~ '^(nai|nay|captacao)_'::text AND p.proname !~ '^nai_(tracar|mascarar|trilha|evento|foto|setor|sobrecarga|funcao|trace|inventario)'::text;
