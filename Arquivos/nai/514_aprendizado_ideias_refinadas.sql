-- 514 (Pedro, 28/10): "vai pegar essa transcrição, analisar ela, analisar a nossa empresa no obsidian com todo nosso
-- contexto, e ver quais ideias do vídeo poderiam ajudar nós de verdade, e vai pôr em uma segunda aba lá em aprendizado,
-- Ideias refinadas: cada ideia vai ter a tua sugestão, como é hoje, onde isso pode nos ajudar, e se a execução é curto,
-- médio ou longo prazo, e uma nota em formato de uma barrinha vertical que eu vou mexer ... no final posso filtrar lá em
-- cima só as ideias acima de 90". E depois: "eu não pedi para pôr nada no obsidian, tu só vai ler o obsidian ... os
-- aprendizados ficam em aprendizado na nova aba".
--
-- aprendizado_video: um vídeo estudado (o youtube_id é o que marca o vídeo como feito para a rotina da noite).
-- aprendizado_ideia: uma ideia por linha. `nota` é do Pedro (a barrinha da tela); `nota_claude` é a nota da análise.
-- A tela admin › Aprendizado › Ideias refinadas lê por site_aprendizado_ideias() e grava a barrinha por
-- site_aprendizado_ideia_nota(). A rotina grava por aprendizado_gravar(jsonb) (scripts/aprendizado.py gravar), que
-- nunca mexe na nota que o Pedro já deu.
BEGIN;
SET LOCAL lock_timeout = '3s';

CREATE TABLE IF NOT EXISTS public.aprendizado_video (
  youtube_id  text PRIMARY KEY,
  titulo      text NOT NULL,
  quem        text,
  link        text,
  data        date NOT NULL DEFAULT current_date,
  duracao     text,
  defende     text,            -- o que o vídeo defende (markdown curto, um item por linha)
  nao_serve   text,            -- o que do vídeo não serve para nós
  criado_em   timestamptz NOT NULL DEFAULT now()
);
COMMENT ON TABLE public.aprendizado_video IS
  '514: os vídeos estudados na rotina de aprendizado (admin › Aprendizado › Ideias refinadas).';

CREATE TABLE IF NOT EXISTS public.aprendizado_ideia (
  id            bigserial PRIMARY KEY,
  numero        int NOT NULL UNIQUE,
  youtube_id    text REFERENCES public.aprendizado_video (youtube_id),
  titulo        text NOT NULL,
  area          text,
  prazo         text NOT NULL CHECK (prazo IN ('curto', 'medio', 'longo')),
  nota          int NOT NULL CHECK (nota BETWEEN 0 AND 100),
  nota_claude   int NOT NULL CHECK (nota_claude BETWEEN 0 AND 100),
  nota_revisada boolean NOT NULL DEFAULT false,
  nota_por      text,
  sugestao      text,
  como_hoje     text,
  onde_ajuda    text,
  porque_prazo  text,
  do_video      text,
  criada_em     timestamptz NOT NULL DEFAULT now(),
  mudada_em     timestamptz NOT NULL DEFAULT now()
);
COMMENT ON TABLE public.aprendizado_ideia IS
  '514: as ideias refinadas dos vídeos: sugestão, como é hoje, onde ajuda, prazo; nota do Pedro (barrinha) e nota_claude.';

CREATE OR REPLACE FUNCTION public.site_aprendizado_ideias()
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  SELECT jsonb_build_object(
    'ideias', coalesce((SELECT jsonb_agg(to_jsonb(i) || jsonb_build_object('video', v.titulo, 'video_quem', v.quem,
                                                                           'video_link', v.link)
                                         ORDER BY i.nota DESC, i.numero)
                          FROM aprendizado_ideia i LEFT JOIN aprendizado_video v USING (youtube_id)), '[]'::jsonb),
    'videos', coalesce((SELECT jsonb_agg(to_jsonb(v) || jsonb_build_object(
                                 'ideias', (SELECT count(*) FROM aprendizado_ideia i WHERE i.youtube_id = v.youtube_id))
                               ORDER BY v.data DESC, v.titulo)
                          FROM aprendizado_video v), '[]'::jsonb))
$function$;

CREATE OR REPLACE FUNCTION public.site_aprendizado_ideia_nota(p_id bigint, p_nota int, p_quem text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  r aprendizado_ideia;
BEGIN
  IF p_nota IS NULL OR p_nota < 0 OR p_nota > 100 THEN RAISE EXCEPTION 'a nota vai de 0 a 100'; END IF;
  UPDATE aprendizado_ideia
     SET nota = p_nota, nota_revisada = true, nota_por = left(p_quem, 80), mudada_em = now()
   WHERE id = p_id
  RETURNING * INTO r;
  IF NOT FOUND THEN RAISE EXCEPTION 'não achei a ideia %', p_id; END IF;
  RETURN jsonb_build_object('id', r.id, 'nota', r.nota, 'nota_revisada', r.nota_revisada);
END;
$function$;

-- A rotina da noite: {"video": {...}, "ideias": [{numero, titulo, area, prazo, nota_claude, sugestao, ...}]}.
-- Ideia que já existe (o mesmo número) atualiza o texto e a nota_claude; a nota e o "revisada" do Pedro ficam.
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

REVOKE ALL ON FUNCTION public.site_aprendizado_ideias() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.site_aprendizado_ideia_nota(bigint, int, text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.aprendizado_gravar(jsonb) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.site_aprendizado_ideias() TO nay, nay_site_leitura, nay_site_escrita;
GRANT EXECUTE ON FUNCTION public.site_aprendizado_ideia_nota(bigint, int, text) TO nay, nay_site_escrita;
GRANT SELECT ON public.aprendizado_video, public.aprendizado_ideia TO nay_leitura;

COMMIT;
