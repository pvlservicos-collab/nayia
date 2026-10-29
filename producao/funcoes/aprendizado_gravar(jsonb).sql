CREATE OR REPLACE FUNCTION public.aprendizado_gravar(p jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v jsonb := p->'video';
  i jsonb;
  n_novas int := 0;
  n_mudadas int := 0;
BEGIN
  IF v IS NOT NULL THEN
    IF coalesce(v->>'youtube_id', '') = '' OR coalesce(v->>'titulo', '') = '' THEN
      RAISE EXCEPTION 'o vídeo precisa de youtube_id e titulo';
    END IF;
    INSERT INTO aprendizado_video (youtube_id, titulo, quem, link, data, duracao, defende, nao_serve)
    VALUES (v->>'youtube_id', v->>'titulo', v->>'quem', v->>'link', coalesce((v->>'data')::date, current_date),
            v->>'duracao', v->>'defende', v->>'nao_serve')
    ON CONFLICT (youtube_id) DO UPDATE
       SET titulo = EXCLUDED.titulo, quem = EXCLUDED.quem, link = EXCLUDED.link, data = EXCLUDED.data,
           duracao = EXCLUDED.duracao, defende = EXCLUDED.defende, nao_serve = EXCLUDED.nao_serve;
  END IF;
  FOR i IN SELECT * FROM jsonb_array_elements(coalesce(p->'ideias', '[]'::jsonb)) LOOP
    IF EXISTS (SELECT 1 FROM aprendizado_ideia WHERE numero = (i->>'numero')::int) THEN
      UPDATE aprendizado_ideia
         SET titulo = i->>'titulo', area = i->>'area', prazo = i->>'prazo',
             nota_claude = (i->>'nota_claude')::int,
             nota = CASE WHEN nota_revisada THEN nota ELSE (i->>'nota_claude')::int END,
             sugestao = i->>'sugestao', como_hoje = i->>'como_hoje', onde_ajuda = i->>'onde_ajuda',
             porque_prazo = i->>'porque_prazo', do_video = i->>'do_video', mudada_em = now()
       WHERE numero = (i->>'numero')::int;
      n_mudadas := n_mudadas + 1;
    ELSE
      INSERT INTO aprendizado_ideia (numero, youtube_id, titulo, area, prazo, nota, nota_claude, sugestao, como_hoje,
                                     onde_ajuda, porque_prazo, do_video)
      VALUES ((i->>'numero')::int, coalesce(i->>'youtube_id', v->>'youtube_id'), i->>'titulo', i->>'area', i->>'prazo',
              (i->>'nota_claude')::int, (i->>'nota_claude')::int, i->>'sugestao', i->>'como_hoje', i->>'onde_ajuda',
              i->>'porque_prazo', i->>'do_video');
      n_novas := n_novas + 1;
    END IF;
  END LOOP;
  RETURN jsonb_build_object('novas', n_novas, 'atualizadas', n_mudadas,
                            'proximo_numero', (SELECT coalesce(max(numero), 0) + 1 FROM aprendizado_ideia));
END;
$function$;
