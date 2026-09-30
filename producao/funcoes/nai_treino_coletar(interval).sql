CREATE OR REPLACE FUNCTION public.nai_treino_coletar(p_desde interval DEFAULT '00:30:00'::interval)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE n int;
BEGIN
  INSERT INTO nai_treino_pedido (turno_id, contato_id, quem, criado_em, texto, resposta, motivos)
  SELECT t.id, t.contato_id, coalesce(k.nome_completo, k.nome_whatsapp), t.criado_em,
         left(regexp_replace(t.texto, '\s+', ' ', 'g'), 1500),
         left((SELECT string_agg(s.texto, E'\n' ORDER BY s.ordem) FROM nai_saida s
                WHERE s.turno_id = t.id AND s.tipo = 'texto' AND s.papel_destino = 'turno'
                  AND s.estado IN ('enviado', 'enviando', 'simulado')), 2000),
         array_remove(ARRAY[
           CASE WHEN 'escalar' = ANY (coalesce(t.ferramentas, '{}')) THEN 'escalou ao Tel' END,
           CASE WHEN EXISTS (SELECT 1 FROM nai_conferencia c WHERE c.turno_id = t.id
                              AND c.etapa = 'ficha_de_identificacao' AND c.resultado = 'mudou') THEN 'perguntou qual imóvel' END,
           CASE WHEN EXISTS (SELECT 1 FROM nai_conferencia c WHERE c.turno_id = t.id
                              AND c.etapa IN ('corte_sem_silencio', 'texto_orfao', 'sobras_da_caixa', 'conferencia_da_saida')
                              AND c.resultado IN ('mudou', 'parou', 'barrou', 'retirou')) THEN 'resposta cortada por uma parede' END,
           CASE WHEN 'buscar_por_perfil' = ANY (coalesce(t.ferramentas, '{}'))
                 AND NOT coalesce((nai_pedido_de_perfil(t.texto)->>'e_pedido')::boolean, false) THEN 'pedido não reconhecido pelo filtro' END
         ], NULL)
    FROM nai_turno t JOIN nai_contato k ON k.id = t.contato_id
   WHERE t.papel = 'corretor' AND NOT coalesce(t.teste, false)
     AND t.criado_em > now() - p_desde AND t.criado_em < now() - interval '3 minutes'
     AND coalesce(btrim(t.texto), '') <> ''
     AND NOT nai_e_so_cortesia(t.texto) AND NOT nai_e_da_equipe_contato(t.contato_id)
     AND NOT (k.chave = ANY (nai_chaves_teste()))
     AND NOT EXISTS (SELECT 1 FROM nai_treino_pedido p WHERE p.turno_id = t.id)
     AND ('escalar' = ANY (coalesce(t.ferramentas, '{}'))
          OR EXISTS (SELECT 1 FROM nai_conferencia c WHERE c.turno_id = t.id
                      AND ((c.etapa = 'ficha_de_identificacao' AND c.resultado = 'mudou')
                        OR (c.etapa IN ('corte_sem_silencio', 'texto_orfao', 'sobras_da_caixa', 'conferencia_da_saida')
                            AND c.resultado IN ('mudou', 'parou', 'barrou', 'retirou'))))
          OR ('buscar_por_perfil' = ANY (coalesce(t.ferramentas, '{}'))
              AND NOT coalesce((nai_pedido_de_perfil(t.texto)->>'e_pedido')::boolean, false)));
  GET DIAGNOSTICS n = ROW_COUNT;
  RETURN n;
END;
$function$;
