CREATE OR REPLACE FUNCTION public.nai_resposta_aprovacao_valida(p_contato bigint, p_texto text)
 RETURNS boolean
 LANGUAGE sql
 STABLE
AS $function$
  SELECT p_contato IS NOT NULL
     AND nai_e_resposta_aprovacao(p_texto)
     AND nai_e_da_equipe_contato(p_contato)
     AND EXISTS (SELECT 1 FROM nai_visita x WHERE x.estado = 'aguardando_rayssa')
     AND (btrim(coalesce(p_texto, '')) ~ '\d'
          OR EXISTS (SELECT 1 FROM nai_contato c
                      WHERE c.id = ANY (nai_contato_irmaos(p_contato))
                        AND c.chave = nai_chave(nai_cfg('aprovador_visita_telefone', ''))));
$function$;
