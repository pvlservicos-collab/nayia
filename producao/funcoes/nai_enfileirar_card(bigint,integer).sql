CREATE OR REPLACE FUNCTION public.nai_enfileirar_card(p_turno bigint, p_codigo integer)
 RETURNS jsonb
 LANGUAGE plpgsql
AS $function$
DECLARE t nai_turno; v_card text; v_ordem int := 1; f record; n int := 0;
BEGIN
  SELECT * INTO t FROM nai_turno WHERE id = p_turno;
  IF t.id IS NULL OR t.papel NOT IN ('corretor', 'tel') THEN RETURN jsonb_build_object('ok', false); END IF;
  SELECT texto_pronto INTO v_card FROM nai_card_do_imovel(p_codigo);
  IF v_card IS NULL THEN
    PERFORM nai_enfileirar_texto(p_turno, NULL, t.contato_id, 'turno',
      'não achei nenhum imóvel com o código ' || p_codigo || '. confere pra mim?', 'codigo_inexistente', 1);
    RETURN jsonb_build_object('ok', true, 'achou', false);
  END IF;
  PERFORM nai_enfileirar_texto(p_turno, NULL, t.contato_id, 'turno', v_card, 'card', 1);
  -- 224: o codigo solto ("5724") leva o card; a foto so se ele pediu
  IF NOT EXISTS (SELECT 1 FROM imoveis WHERE codigo = p_codigo AND coalesce(e_parceiro, false))
     AND coalesce(nai_deve_mandar_fotos(t.contato_id,
                    (SELECT k.telefone FROM nai_contato k WHERE k.id = t.contato_id), t.texto), false) THEN
    FOR f IN SELECT * FROM nai_imagens_do_envio(p_codigo) LOOP
      v_ordem := v_ordem + 1;
      INSERT INTO nai_saida (turno_id, contato_id, papel_destino, chave_destino, tipo, imagem_url, codigo, ordem, motivo)
           VALUES (p_turno, t.contato_id, 'turno', '', 'imagem', f.url, p_codigo, v_ordem,
                   CASE WHEN f.e_colagem THEN 'colagem' ELSE 'foto' END);
      n := n + 1;
    END LOOP;
  END IF;
  RETURN jsonb_build_object('ok', true, 'achou', true, 'fotos', n);
END;
$function$;
