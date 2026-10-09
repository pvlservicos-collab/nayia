CREATE OR REPLACE FUNCTION public.site_juntar_cadastro(p_de_codigo integer, p_de_ficha bigint, p_em integer, p_fotos boolean, p_quem text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
 SET lock_timeout TO '3s'
AS $function$
DECLARE
  v_base   int;
  v_tinha  int;
  v_n      int := 0;
  v_dono   int;
  v_quem   text := left(coalesce(nullif(btrim(p_quem), ''), 'cadastro rápido'), 80);
  c        captacao_cadastro;
BEGIN
  IF p_em IS NULL OR NOT EXISTS (SELECT 1 FROM imoveis WHERE codigo = p_em) THEN
    RAISE EXCEPTION 'o imóvel % não existe', p_em;
  END IF;
  IF (p_de_codigo IS NULL) = (p_de_ficha IS NULL) THEN
    RAISE EXCEPTION 'diga de onde vem: um imóvel OU uma ficha';
  END IF;
  IF p_de_codigo = p_em THEN RAISE EXCEPTION 'é o mesmo imóvel'; END IF;

  SELECT coalesce(max(ordem), 0), count(*) INTO v_base, v_tinha FROM imovel_fotos WHERE codigo = p_em;

  IF p_de_codigo IS NOT NULL THEN
    IF NOT EXISTS (SELECT 1 FROM imoveis WHERE codigo = p_de_codigo) THEN RAISE EXCEPTION 'o imóvel % não existe', p_de_codigo; END IF;
    IF p_fotos THEN
      INSERT INTO imovel_fotos (codigo, ordem, url, e_capa)
      SELECT p_em, v_base + q.o, q.url, v_tinha = 0 AND q.o = 1
        FROM (SELECT f.url, row_number() OVER (ORDER BY f.ordem, f.id) AS o
                FROM imovel_fotos f
               WHERE f.codigo = p_de_codigo AND coalesce(f.url, '') <> ''
                 AND f.url NOT IN (SELECT x.url FROM imovel_fotos x WHERE x.codigo = p_em AND x.url IS NOT NULL)) q;
      GET DIAGNOSTICS v_n = ROW_COUNT;
    END IF;
    SELECT coalesce(i.proprietario_id, p.proprietario_id) INTO v_dono
      FROM imoveis i LEFT JOIN imovel_privado p ON p.codigo = i.codigo WHERE i.codigo = p_de_codigo;
    UPDATE imoveis
       SET status = 'Excluído', travado = true, travado_em = now(),
           travado_motivo = left('atualização do #' || p_em || ' (' || v_quem || ')', 200),
           extras = coalesce(extras, '{}'::jsonb) || jsonb_build_object('atualizacao_de', p_em::text)
     WHERE codigo = p_de_codigo;
    UPDATE captacao_cadastro
       SET estado = 'aplicado', codigo = p_em, aplicado_em = now(), aplicado_por = left('cadastro rápido: ' || v_quem, 80),
           atualizado_em = now()
     WHERE codigo = p_de_codigo AND estado IN ('coletando', 'pronto');
  ELSE
    SELECT * INTO c FROM captacao_cadastro WHERE id = p_de_ficha FOR UPDATE;
    IF c.id IS NULL THEN RAISE EXCEPTION 'a ficha % não existe', p_de_ficha; END IF;
    IF p_fotos THEN
      INSERT INTO imovel_fotos (codigo, ordem, url, e_capa)
      SELECT p_em, v_base + q.o, q.url, v_tinha = 0 AND q.o = 1
        FROM (SELECT t.u AS url, row_number() OVER (ORDER BY t.o) AS o
                FROM jsonb_array_elements_text(CASE WHEN jsonb_typeof(c.fotos) = 'array' THEN c.fotos ELSE '[]'::jsonb END)
                     WITH ORDINALITY AS t(u, o)
               WHERE t.u ~ '^https?://'
                 AND t.u NOT IN (SELECT x.url FROM imovel_fotos x WHERE x.codigo = p_em AND x.url IS NOT NULL)) q;
      GET DIAGNOSTICS v_n = ROW_COUNT;
    END IF;
    SELECT l.proprietario_id INTO v_dono FROM captacao_leads l WHERE l.id = c.lead_id;
    UPDATE captacao_cadastro
       SET estado = 'aplicado', codigo = p_em, aplicado_em = now(), aplicado_por = left('cadastro rápido: ' || v_quem, 80),
           atualizado_em = now()
     WHERE id = c.id;
  END IF;

  IF v_dono IS NOT NULL THEN
    INSERT INTO imovel_privado (codigo, proprietario_id) VALUES (p_em, v_dono)
    ON CONFLICT (codigo) DO UPDATE SET proprietario_id = coalesce(imovel_privado.proprietario_id, EXCLUDED.proprietario_id);
    UPDATE imoveis SET proprietario_id = v_dono WHERE codigo = p_em AND proprietario_id IS NULL;
  END IF;

  RETURN jsonb_build_object('ok', true, 'em', p_em, 'fotos', v_n, 'dono', v_dono IS NOT NULL);
END
$function$;
