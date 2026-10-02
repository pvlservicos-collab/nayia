-- 268 (02/10/2026): A NAI_CHAVE CHAMA AS OUTRAS COM O SCHEMA.
--
-- O QUE ESTAVA ACONTECENDO (relatório de infra de 02/10, problema 4): o
-- autoanalyze das tabelas `mensagens` e `corretores` falha a cada minuto desde
-- 29/09 -- 9.645 erros "function nai_fone_br(text) does not exist" em 4 dias,
-- 87% dos erros do log do Postgres. Último autoanalyze de `mensagens`: 25/09.
--
-- POR QUÊ: as duas tabelas (e a identidade_lid) têm índice sobre
-- nai_chave(telefone). O autovacuum roda com search_path VAZIO; para analisar o
-- índice ele executa nai_chave, que chama nai_fone_br e nay_fone_chave SEM o
-- schema, e não acha nenhuma das duas. O pg_restore sofre do mesmo jeito (o
-- cabeçalho do backup_banco.sh conta os 3 erros do teste de 30/09).
--
-- O CONSERTO: as duas chamadas ganham `public.`. Nada mais muda: mesmo corpo,
-- mesma assinatura, IMMUTABLE, COST 500. O resultado é idêntico (conferido no
-- ensaio contra todas as linhas de corretores, identidade_lid e nai_contato),
-- então os índices continuam valendo.
--
-- POR QUE NÃO `ALTER FUNCTION ... SET search_path`: função com SET não é
-- embutida na consulta e paga uma troca de configuração por chamada, e esta é
-- chamada em toda mensagem que entra.
BEGIN;
SET LOCAL lock_timeout = '3s';

CREATE OR REPLACE FUNCTION public.nai_chave(p text)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE COST 500
AS $function$
  SELECT CASE
    WHEN p IS NULL OR btrim(p) = '' THEN NULL
    WHEN p ILIKE '%@lid' THEN
      CASE WHEN regexp_replace(p, '\D', '', 'g') ~ '^[0-9]{6,20}$'
           THEN 'lid:' || regexp_replace(p, '\D', '', 'g') END
    WHEN public.nai_fone_br(p) IS NULL THEN NULL
    WHEN public.nai_fone_br(p) !~ '^[0-9]{8,15}$' THEN NULL
    ELSE public.nay_fone_chave(public.nai_fone_br(p))
  END;
$function$;

COMMIT;
