CREATE OR REPLACE FUNCTION public.scrap_contatos_rebuild(p_lista bigint)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE v_n integer;
BEGIN
  UPDATE scrap_anuncio SET telefones = scrap_telefones_do_texto(descricao)
   WHERE lista_id = p_lista AND descricao IS NOT NULL;

  WITH tel AS (
    SELECT unnest(a.telefones) AS telefone, a.*
      FROM scrap_anuncio a WHERE a.lista_id = p_lista
  ), agr AS (
    SELECT lista_id, telefone,
           mode() WITHIN GROUP (ORDER BY nullif(trim(anunciante), '')) AS nome,
           mode() WITHIN GROUP (ORDER BY anunciante_id) AS anunciante_id,
           bool_or(telefone_mascarado IS NOT NULL AND left(telefone, 7) = left(regexp_replace(telefone_mascarado, '\D', '', 'g'), 7)) AS confirmado,
           count(*)::int AS n_anuncios,
           (SELECT array_agg(DISTINCT b ORDER BY b) FROM unnest(array_agg(bairro)) b WHERE b IS NOT NULL) AS bairros,
           min(preco) AS preco_min, max(preco) AS preco_max,
           (array_agg(url ORDER BY coalesce(data_olx, coletado_em) DESC))[1] AS exemplo_url,
           (array_agg(titulo ORDER BY coalesce(data_olx, coletado_em) DESC))[1] AS exemplo_titulo
      FROM tel GROUP BY lista_id, telefone
  )
  INSERT INTO scrap_contato AS c (lista_id, telefone, nome, anunciante_id, confirmado, n_anuncios, bairros, preco_min, preco_max,
                                  exemplo_url, exemplo_titulo, origem)
  SELECT lista_id, telefone, nome, anunciante_id, confirmado, n_anuncios, coalesce(bairros, '{}'), preco_min, preco_max,
         exemplo_url, exemplo_titulo, 'olx'
    FROM agr
  ON CONFLICT (lista_id, telefone) DO UPDATE SET
    nome = CASE WHEN c.origem = 'olx' THEN EXCLUDED.nome ELSE c.nome END,
    anunciante_id = coalesce(EXCLUDED.anunciante_id, c.anunciante_id),
    confirmado = c.confirmado OR EXCLUDED.confirmado,
    n_anuncios = EXCLUDED.n_anuncios, bairros = EXCLUDED.bairros,
    preco_min = EXCLUDED.preco_min, preco_max = EXCLUDED.preco_max,
    exemplo_url = EXCLUDED.exemplo_url, exemplo_titulo = EXCLUDED.exemplo_titulo,
    atualizado_em = now();
  GET DIAGNOSTICS v_n = ROW_COUNT;
  UPDATE scrap_lista SET atualizado_em = now() WHERE id = p_lista;
  RETURN v_n;
END
$function$;
