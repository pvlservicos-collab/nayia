-- 217 (revisão de 30/09/2026): O × DA ETIQUETA DEVOLVE A ETAPA CERTA AO CRM.
-- A Rayssa põe a conversa em Visitas pelo card e depois escolhe "Rayssa": o CRM
-- guarda só a última escolha ('rayssa'), mas a Nay continua com a etapa manual
-- 'visitas' (7 dias). Ao tirar a etiqueta, o CRM mostrava a conversa em Todos
-- enquanto a Nay seguia calada: ninguém respondia. O CRM pergunta aqui em que
-- etapa a Nay está, e põe a conversa nela.
BEGIN;
SET LOCAL lock_timeout = '3s';
CREATE OR REPLACE FUNCTION crm_etapa_da_nay(p_telefone text)
 RETURNS text LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, pg_temp AS $$
  SELECT CASE
    WHEN EXISTS (SELECT 1 FROM nai_fechamento f WHERE f.contato_id = ANY (pe.ids) AND f.concluido_em IS NULL) THEN 'fechamento'
    ELSE (SELECT m.etapa FROM nai_etapa_manual m
           WHERE m.contato_id = ANY (pe.ids) AND (m.valido_ate IS NULL OR m.valido_ate > now())
             AND m.etapa IN ('visitas', 'proprietarios', 'fechamento')
           ORDER BY m.definido_em DESC LIMIT 1)
  END
    FROM crm_pessoas(ARRAY[p_telefone]) pe
   LIMIT 1;
$$;
REVOKE ALL ON FUNCTION crm_etapa_da_nay(text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION crm_etapa_da_nay(text) TO nay_disparo;
COMMIT;
