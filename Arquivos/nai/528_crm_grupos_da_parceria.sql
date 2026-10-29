-- 528 (Pedro, 29/10/2026: "os grupos do parceria nao aparecem no crm"): a lista de CRM > Grupos vinha so da Z-API
-- (groups + group-metadata, ~30 chamadas); se a Z-API falhava ou nao devolvia um grupo, ele sumia do CRM mesmo com as
-- mensagens guardadas aqui. Esta funcao devolve os grupos que o banco conhece (nome, mensagens, ultima), para o CRM
-- completar a lista. So leitura.
BEGIN;

CREATE OR REPLACE FUNCTION public.crm_grupos_da_parceria()
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  SELECT coalesce(jsonb_agg(jsonb_build_object('id', t.grupo_id, 'nome', t.nome, 'mensagens', t.n,
                                               'ultima', t.ultima) ORDER BY t.ultima DESC), '[]'::jsonb)
    FROM (SELECT m.grupo_id,
                 (array_agg(m.grupo_nome ORDER BY m.enviada_em DESC) FILTER (WHERE m.grupo_nome IS NOT NULL AND m.grupo_nome <> ''))[1] AS nome,
                 count(*) AS n, max(m.enviada_em) AS ultima
            FROM privado.grupo_conversa m
           GROUP BY m.grupo_id) t;
$function$;

REVOKE ALL ON FUNCTION public.crm_grupos_da_parceria() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.crm_grupos_da_parceria() TO nay_disparo;

COMMIT;
