CREATE OR REPLACE FUNCTION public.site_ficha_preparada(p_ficha bigint)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  SELECT jsonb_build_object(
    'ficha', c.id, 'estado', c.estado, 'dados', c.dados,
    'campos', a.campos, 'observacao', a.observacao, 'pronto', a.pronto, 'duplicado_de', a.duplicado_de,
    'analisado_em', a.analisado_em,
    'fotos', coalesce((SELECT jsonb_agg(t.u ORDER BY t.o) FROM jsonb_array_elements_text(
                         CASE WHEN jsonb_typeof(c.fotos) = 'array' THEN c.fotos ELSE '[]'::jsonb END) WITH ORDINALITY t(u, o)
                        WHERE t.u ~ '^https?://'), '[]'::jsonb),
    'condominio', (SELECT jsonb_build_object('id', co.id, 'nome', co.nome, 'bairro', co.bairro) FROM condominios co
                    WHERE nullif(btrim(coalesce(a.campos->>'condominio', c.dados->>'condominio')), '') IS NOT NULL
                      AND lower(nay_sem_acento(co.nome)) = lower(nay_sem_acento(btrim(coalesce(a.campos->>'condominio', c.dados->>'condominio'))))
                    LIMIT 1),
    'dono', jsonb_build_object('nome', l.nome, 'telefone', l.telefone, 'tratamento', l.tratamento))
    FROM captacao_cadastro c
    LEFT JOIN captacao_ficha_campos a ON a.ficha_id = c.id
    LEFT JOIN captacao_leads l ON l.id = c.lead_id
   WHERE c.id = p_ficha;
$function$;
