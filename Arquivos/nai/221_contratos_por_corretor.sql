-- 221 (30/09/2026): OS CONTRATOS FECHADOS DE CADA CORRETOR, PARA A ABA CORRETORES.
-- Pedro: "uma aba Corretores ... cada quadradinho um corretor, com métricas que o
-- CRM vai guardar: quantidade de interações, visitas agendadas, contratos fechados,
-- e dar para filtrar pelos nossos melhores corretores parceiros".
-- Contrato fechado = fechamento que a Rayssa concluiu (nai_fechamento.concluido_em,
-- migração 197); em andamento = fechamento aberto. Pelas duas linhas da pessoa.
BEGIN;
SET LOCAL lock_timeout = '3s';
CREATE OR REPLACE FUNCTION crm_fechamentos_por_telefone(p_telefones text[], p_desde timestamptz)
 RETURNS TABLE(telefone text, fechados int, em_andamento int)
 LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, pg_temp AS $$
  SELECT pe.telefone,
         (SELECT count(*)::int FROM nai_fechamento f
           WHERE f.contato_id = ANY (pe.ids) AND f.concluido_em IS NOT NULL AND f.concluido_em >= p_desde),
         (SELECT count(*)::int FROM nai_fechamento f
           WHERE f.contato_id = ANY (pe.ids) AND f.concluido_em IS NULL)
    FROM crm_pessoas(p_telefones) pe;
$$;
REVOKE ALL ON FUNCTION crm_fechamentos_por_telefone(text[], timestamptz) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION crm_fechamentos_por_telefone(text[], timestamptz) TO nay_disparo;
COMMIT;
