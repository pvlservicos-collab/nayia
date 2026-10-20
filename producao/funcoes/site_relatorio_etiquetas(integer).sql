CREATE OR REPLACE FUNCTION public.site_relatorio_etiquetas(p_foto integer DEFAULT NULL::integer)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'privado'
AS $function$
  WITH f AS (
    SELECT * FROM privado.relatorio_etiquetas_foto
     WHERE id = coalesce(p_foto, (SELECT max(id) FROM privado.relatorio_etiquetas_foto))),
  c AS (SELECT x.* FROM privado.relatorio_etiquetas_contato x JOIN f ON f.id = x.foto_id)
  SELECT jsonb_build_object(
    'foto', (SELECT jsonb_build_object('id', f.id, 'linha', f.linha, 'tirada_em', f.tirada_em, 'observacao', f.observacao) FROM f),
    'fotos', (SELECT coalesce(jsonb_agg(jsonb_build_object('id', id, 'linha', linha, 'tirada_em', tirada_em) ORDER BY id DESC), '[]')
                FROM privado.relatorio_etiquetas_foto),
    'contatos', (SELECT count(DISTINCT lead_id) FROM c),
    'etiquetas', coalesce((
      SELECT jsonb_agg(jsonb_build_object('etiqueta', e.etiqueta, 'n', e.n, 'contatos', e.contatos) ORDER BY e.n DESC, e.etiqueta)
        FROM (SELECT etiqueta, count(*) AS n,
                     jsonb_agg(jsonb_build_object('nome', nome, 'telefone', telefone, 'ultima', ultima_atividade, 'criado', criado_no_crm)
                               ORDER BY ultima_atividade DESC NULLS LAST) AS contatos
                FROM c GROUP BY etiqueta) e), '[]'))
$function$;
