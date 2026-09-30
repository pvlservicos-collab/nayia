CREATE OR REPLACE FUNCTION public.nai_sec_guardar_fotos_do_turno(p_turno bigint)
 RETURNS integer
 LANGUAGE plpgsql
AS $function$
DECLARE t nai_turno; v_id bigint; n int := 0;
BEGIN
  SELECT * INTO t FROM nai_turno WHERE id = p_turno;
  IF t.id IS NULL THEN RETURN 0; END IF;

  SELECT x.id INTO v_id FROM nai_imovel_novo x
   WHERE x.contato_id = t.contato_id AND x.situacao = 'colhendo'
   ORDER BY x.id DESC LIMIT 1;
  IF v_id IS NULL THEN RETURN 0; END IF;

  INSERT INTO nai_imovel_novo_foto (novo_id, url)
  SELECT v_id, m.midia_url
    FROM mensagens m
   WHERE m.id = ANY (coalesce(t.msg_ids, '{}'))
     AND m.midia_url ~ '^https?://'
     AND m.origem IN ('imagem', 'documento')
     -- a mesma foto nao entra duas vezes se o turno for reprocessado
     AND NOT EXISTS (SELECT 1 FROM nai_imovel_novo_foto f
                      WHERE f.novo_id = v_id AND f.url = m.midia_url);
  GET DIAGNOSTICS n = ROW_COUNT;
  IF n > 0 THEN
    PERFORM nai_anotar(p_turno, 6, 'fotos_do_cadastro', 'mudou', n || ' fotos na ficha ' || v_id);
  END IF;
  RETURN n;
END;
$function$;
