CREATE OR REPLACE FUNCTION public.captacao_fora_da_campanha(p_lead bigint)
 RETURNS text
 LANGUAGE sql
 STABLE
AS $function$
  SELECT CASE
    -- o número de teste da campanha conversa sempre
    WHEN right(l.telefone, 8) = right(regexp_replace(coalesce((SELECT c.valor FROM captacao_config c
                                                             WHERE c.chave = 'telefone_teste'), ''), '\D', '', 'g'), 8)
      THEN NULL
    WHEN EXISTS (SELECT 1 FROM corretores k
                  WHERE right(regexp_replace(coalesce(k.telefone, ''), '\D', '', 'g'), 8) = right(l.telefone, 8))
      THEN 'corretor (está na lista de corretores dos grupos)'
    WHEN nai_dono_e_parceiro(l.nome) OR coalesce(l.nome, '') ~* 'parceri'
      THEN 'nome de corretor, imobiliária ou parceria'
    WHEN EXISTS (SELECT 1 FROM imoveis i
                  WHERE coalesce(i.e_parceiro, false)
                    AND (i.codigo::text = l.codigo
                         OR i.codigo::text IN (SELECT x ->> 'codigo'
                                                 FROM jsonb_array_elements(coalesce(l.imoveis_prop, '[]'::jsonb)) x)))
      THEN 'imóvel de parceiro'
  END
    FROM captacao_leads l WHERE l.id = p_lead;
$function$;
