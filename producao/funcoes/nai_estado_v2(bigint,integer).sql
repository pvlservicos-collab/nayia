CREATE OR REPLACE FUNCTION public.nai_estado_v2(p_contato bigint, p_trocas integer DEFAULT 3)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
AS $function$
DECLARE e nai_estado_conversa; k nai_contato; v_trocas jsonb;
BEGIN
  SELECT * INTO e FROM nai_estado_conversa WHERE contato_id = p_contato;
  SELECT * INTO k FROM nai_contato WHERE id = p_contato;

  -- as ultimas trocas, na ordem da conversa, so com a FALA LIMPA
  SELECT coalesce(jsonb_agg(x ORDER BY x->>'quando'), '[]'::jsonb) INTO v_trocas
    FROM (
      SELECT jsonb_build_object(
               'quando', t.criado_em,
               'ele', t.texto,
               'ela', (SELECT string_agg(s.texto, ' ' ORDER BY s.ordem, s.id)
                         FROM nai_saida s
                        WHERE s.turno_id = t.id AND s.tipo = 'texto')) AS x
        FROM nai_turno t
       WHERE t.contato_id = p_contato AND t.texto IS NOT NULL
       ORDER BY t.id DESC LIMIT p_trocas
    ) u;

  RETURN jsonb_build_object(
    'codigo_foco',        e.codigo_foco,
    'foco_origem',        e.foco_origem,
    'codigos_mostrados',  to_jsonb(coalesce(e.codigos_mostrados, '{}')),
    'codigos_rejeitados', to_jsonb(coalesce(e.codigos_rejeitados, '{}')),
    'visita_pendente',    e.visita_pendente IS NOT NULL,
    'ultima_fala_dela',   e.ultima_fala_dela,
    'papel',              coalesce(e.papel, 'corretor'),
    'tel_assumiu',        k.humano_assumiu_em IS NOT NULL,
    'nome',               coalesce(k.nome_completo, k.nome_whatsapp),
    'ultimas_trocas',     coalesce(v_trocas, '[]'::jsonb)
  );
END;
$function$;
