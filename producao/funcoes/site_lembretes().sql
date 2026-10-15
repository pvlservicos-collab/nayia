CREATE OR REPLACE FUNCTION public.site_lembretes()
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'privado'
AS $function$
  WITH hoje AS (SELECT (now() AT TIME ZONE 'America/Manaus')::date AS d),
  vivos AS (SELECT l.* FROM privado.lembrete_equipe l WHERE l.apagado_em IS NULL)
  SELECT jsonb_build_object(
    'hoje', (SELECT d FROM hoje),
    -- do dia em diante e ainda sem "feito": é o que acende o sininho
    'agora', coalesce((SELECT jsonb_agg(jsonb_build_object('id', v.id, 'texto', v.texto, 'dia', v.dia,
                                                           'atrasado', v.dia < (SELECT d FROM hoje)) ORDER BY v.dia, v.id)
                         FROM vivos v WHERE v.feito_em IS NULL AND v.dia <= (SELECT d FROM hoje)), '[]'::jsonb),
    'proximos', coalesce((SELECT jsonb_agg(jsonb_build_object('id', v.id, 'texto', v.texto, 'dia', v.dia) ORDER BY v.dia, v.id)
                            FROM vivos v WHERE v.feito_em IS NULL AND v.dia > (SELECT d FROM hoje)), '[]'::jsonb),
    'feitos', coalesce((SELECT jsonb_agg(x.j ORDER BY x.feito_em DESC) FROM (
                          SELECT v.feito_em, jsonb_build_object('id', v.id, 'texto', v.texto, 'dia', v.dia, 'feito_em', v.feito_em) AS j
                            FROM vivos v WHERE v.feito_em > now() - interval '7 days' ORDER BY v.feito_em DESC LIMIT 10) x), '[]'::jsonb))
$function$;
