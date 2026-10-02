# vw_nai_funcao_orfa  (view, ~0 linhas)
Funcoes que nenhuma outra chama. `confianca` separa as que tem chamador de fora anotado das candidatas de verdade (Tel, 19/09).

## colunas
funcao  text
setor  text
familia  text
tamanho  integer
chamador_de_fora  text
confianca  text

## permissões
nay: DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE
nay_leitura: SELECT
nay_site_nai: SELECT

## funções que escrevem aqui
(nenhuma função; quem escreve é o n8n, o site ou o CRM)

## funções que citam
(nenhuma)

## definição da view
 WITH f AS (
         SELECT p.oid,
            p.proname::text AS proname,
            p.prosrc,
            nai_setor_final(p.proname::text) AS setor,
                CASE
                    WHEN p.proname ~~ 'nai\_%'::text THEN 'nai'::text
                    ELSE 'nay'::text
                END AS familia,
            length(p.prosrc) AS tamanho
           FROM pg_proc p
             JOIN pg_namespace n ON n.oid = p.pronamespace
          WHERE n.nspname = 'public'::name AND p.prokind = 'f'::"char" AND p.proname ~ '^(nai|nay)_'::text AND p.proname !~ '^nai_(tracar|mascarar|trilha|evento|foto|setor|sobrecarga|funcao|trace|inventario)'::text
        )
 SELECT proname AS funcao,
    setor,
    familia,
    tamanho,
    ( SELECT string_agg(c.chamador, ', '::text ORDER BY c.chamador) AS string_agg
           FROM nai_funcao_chamador c
          WHERE c.funcao = f.proname) AS chamador_de_fora,
        CASE
            WHEN (EXISTS ( SELECT 1
               FROM nai_funcao_chamador c
              WHERE c.funcao = f.proname)) THEN 'viva: chamada de fora do banco'::text
            ELSE 'CANDIDATA: nenhuma funcao chama e nenhum chamador anotado -- conferir os 7 fluxos e os 11 crons ANTES de apagar'::text
        END AS confianca
   FROM f
  WHERE NOT (EXISTS ( SELECT 1
           FROM f g
          WHERE g.oid <> f.oid AND g.prosrc ~ (('\m'::text || f.proname) || '\M'::text)))
  ORDER BY ((EXISTS ( SELECT 1
           FROM nai_funcao_chamador c
          WHERE c.funcao = f.proname))), familia DESC, tamanho DESC;
