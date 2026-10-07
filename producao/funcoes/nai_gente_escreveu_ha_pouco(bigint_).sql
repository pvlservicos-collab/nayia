CREATE OR REPLACE FUNCTION public.nai_gente_escreveu_ha_pouco(p_ids bigint[])
 RETURNS boolean
 LANGUAGE sql
 STABLE
AS $function$
  SELECT EXISTS (
    SELECT 1
      FROM crm_quem_mandou(ARRAY(
             SELECT m.message_id
               FROM mensagens m
              WHERE m.direcao = 'enviada'
                AND m.criada_em > now() - make_interval(mins => greatest(nai_cfg_int('gap_tel_min', 30), 0))
                AND nullif(m.message_id, '') IS NOT NULL
                AND nai_chave(m.telefone) IN (SELECT c.chave FROM nai_contato c WHERE c.id = ANY (p_ids)))) q
     WHERE q.origem = 'gente');
$function$;
