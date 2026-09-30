CREATE OR REPLACE FUNCTION public.nai_midia_do_turno(p_turno bigint)
 RETURNS text
 LANGUAGE plpgsql
 STABLE
AS $function$
DECLARE
  t     nai_turno;
  n_img int;
  n_aud int;
  n_doc int;
  n_vid int;
  itens text[] := '{}';
BEGIN
  SELECT * INTO t FROM nai_turno WHERE id = p_turno;
  IF t.id IS NULL THEN RETURN NULL; END IF;

  SELECT count(*) FILTER (WHERE m.origem IN ('imagem', 'figurinha')),
         count(*) FILTER (WHERE m.origem = 'audio'),
         count(*) FILTER (WHERE m.origem = 'documento'),
         count(*) FILTER (WHERE m.origem = 'video')
    INTO n_img, n_aud, n_doc, n_vid
    FROM mensagens m
   WHERE m.id = ANY (coalesce(t.msg_ids, '{}'));

  IF n_img > 0 THEN itens := itens || (CASE WHEN n_img = 1 THEN 'uma imagem'
                                            ELSE n_img || ' imagens' END); END IF;
  IF n_aud > 0 THEN itens := itens || (CASE WHEN n_aud = 1 THEN 'um audio'
                                            ELSE n_aud || ' audios' END); END IF;
  IF n_doc > 0 THEN itens := itens || (CASE WHEN n_doc = 1 THEN 'um arquivo'
                                            ELSE n_doc || ' arquivos' END); END IF;
  IF n_vid > 0 THEN itens := itens || (CASE WHEN n_vid = 1 THEN 'um video'
                                            ELSE n_vid || ' videos' END); END IF;

  IF coalesce(array_length(itens, 1), 0) = 0 THEN RETURN NULL; END IF;
  RETURN nai_lista_pt(itens);
END;
$function$;
