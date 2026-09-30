CREATE OR REPLACE FUNCTION public.nai_sec_abrir_cadastro(p_turno bigint)
 RETURNS TABLE(texto_pronto text, instrucao_para_voce text)
 LANGUAGE plpgsql
AS $function$
DECLARE t nai_turno; v_id bigint; v_falta text;
BEGIN
  SELECT * INTO t FROM nai_turno WHERE id = p_turno;
  IF t.id IS NULL THEN
    RETURN QUERY SELECT NULL::text, 'turno inexistente'::text; RETURN;
  END IF;

  SELECT n.id INTO v_id FROM nai_imovel_novo n
   WHERE n.contato_id = t.contato_id AND n.situacao = 'colhendo'
   ORDER BY n.id DESC LIMIT 1;

  IF v_id IS NULL THEN
    INSERT INTO nai_imovel_novo (contato_id, turno_id) VALUES (t.contato_id, p_turno)
      RETURNING id INTO v_id;
    PERFORM nai_anotar(p_turno, 6, 'cadastro_aberto', 'mudou', 'ficha ' || v_id);
  END IF;

  v_falta := nai_imovel_novo_falta(v_id);
  IF v_falta IS NULL THEN
    RETURN QUERY SELECT 'Obrigada! Já deixei registrado aqui.'::text,
      ('a ficha ja esta completa. Agradeca e encerre, sem perguntar mais nada.')::text;
    RETURN;
  END IF;
  RETURN QUERY SELECT nai_imovel_novo_pergunta(v_falta),
    ('ficha ' || v_id || '. Diga SO essa pergunta, sem juntar outra. Quando ele responder, '
     || 'chame guardar_do_imovel com o que veio.')::text;
END;
$function$
;
