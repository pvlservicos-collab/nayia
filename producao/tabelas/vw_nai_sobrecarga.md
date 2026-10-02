# vw_nai_sobrecarga  (view, ~0 linhas)
Funcoes com mais de uma assinatura. As de proposito estao marcadas; sobrecarga NOVA e que precisa de olhar (Tel, 19/09).

## colunas
funcao  text
setor  text
versoes  bigint
assinaturas  text
esperada_porque  text
veredito  text

## permissões
nay: DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE
nay_leitura: SELECT
nay_site_nai: SELECT

## funções que escrevem aqui
(nenhuma função; quem escreve é o n8n, o site ou o CRM)

## funções que citam
(nenhuma)

## definição da view
 SELECT p.proname::text AS funcao,
    nai_setor_final(p.proname::text) AS setor,
    count(*) AS versoes,
    string_agg(('('::text || pg_get_function_identity_arguments(p.oid)) || ')'::text, '  ||  '::text ORDER BY p.oid) AS assinaturas,
    e.porque AS esperada_porque,
        CASE
            WHEN e.funcao IS NOT NULL THEN 'conhecida: de proposito'::text
            ELSE 'NOVA: investigar -- pode ser versao velha ainda chamavel'::text
        END AS veredito
   FROM pg_proc p
     JOIN pg_namespace n ON n.oid = p.pronamespace
     LEFT JOIN nai_sobrecarga_esperada e ON e.funcao = p.proname
  WHERE n.nspname = 'public'::name AND p.prokind = 'f'::"char" AND p.proname ~ '^(nai|nay|captacao)_'::text
  GROUP BY p.proname, e.funcao, e.porque
 HAVING count(*) > 1
  ORDER BY (e.funcao IS NOT NULL), p.proname;
