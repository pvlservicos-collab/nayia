CREATE OR REPLACE FUNCTION public.crm_visitas_pessoas(p_ids bigint[])
 RETURNS TABLE(id bigint, corretor_telefone text, proprietario_telefone text, proprietario_chaves text[])
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  SELECT x.id, x.corretor_telefone, x.dono,
         CASE WHEN x.dono_id IS NOT NULL THEN
                ARRAY(SELECT DISTINCT k.chave FROM nai_contato k WHERE k.id = ANY (nai_contato_irmaos(x.dono_id)) OR k.id = x.dono_id)
              WHEN x.dono IS NOT NULL THEN ARRAY[nai_chave(x.dono)]
              ELSE '{}'::text[] END
    FROM (
      SELECT v.id, c.telefone AS corretor_telefone, p.id AS dono_id,
             -- o contato gravado na visita; o número digitado à mão; o dono do cadastro do imóvel
             coalesce(nullif(btrim(p.telefone), ''), nullif(btrim(v.prop_telefone_manual), ''),
                      (SELECT d.telefone FROM nai_proprietario_do_imovel(v.codigo) d
                        WHERE d.motivo IS NULL AND nullif(btrim(d.telefone), '') IS NOT NULL LIMIT 1)) AS dono
        FROM nai_visita v
        LEFT JOIN nai_contato c ON c.id = v.corretor_id
        LEFT JOIN nai_contato p ON p.id = v.proprietario_id
       WHERE v.id = ANY (coalesce(p_ids, '{}'::bigint[]))
    ) x
   LIMIT 2000
$function$;
