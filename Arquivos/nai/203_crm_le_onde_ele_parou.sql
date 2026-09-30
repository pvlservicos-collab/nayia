-- 203 (30/09/2026): o card do lead no CRM mostra "onde ele parou" (nai_retomada_resumo, 199).
-- Só leitura, para o nay_disparo.
BEGIN;
CREATE OR REPLACE FUNCTION crm_parceria_retomada(p_telefones text[])
 RETURNS TABLE(telefone text, etapa text, resumo text, proximo_passo text, imoveis int[], criado_em timestamptz,
               valido_ate timestamptz)
 LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public' AS $$
  SELECT pe.telefone, r.etapa, r.resumo, r.proximo_passo, r.imoveis, r.criado_em, r.valido_ate
    FROM crm_pessoas(p_telefones) pe
    JOIN LATERAL (SELECT * FROM nai_retomada_resumo r WHERE r.contato_id = ANY (pe.ids)
                   ORDER BY r.criado_em DESC LIMIT 1) r ON true;
$$;
GRANT EXECUTE ON FUNCTION crm_parceria_retomada(text[]) TO nay_disparo;
COMMIT;
