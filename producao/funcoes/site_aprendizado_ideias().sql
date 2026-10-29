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
