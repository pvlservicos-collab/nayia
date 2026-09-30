CREATE OR REPLACE FUNCTION public.nai_sec_perguntar_ao_tel(p_turno bigint, p_pergunta text)
 RETURNS TABLE(texto_pronto text, instrucao_para_voce text)
 LANGUAGE plpgsql
AS $function$
DECLARE t nai_turno; k nai_contato; v_nome text; v_pend int;
BEGIN
  SELECT * INTO t FROM nai_turno WHERE id = p_turno;
  SELECT * INTO k FROM nai_contato WHERE id = t.contato_id;
  IF k.id IS NULL THEN
    RETURN QUERY SELECT NULL::text, 'nao achei o contato deste turno.'::text; RETURN;
  END IF;
  v_nome := coalesce(k.nome_completo, k.nome_whatsapp, k.telefone);

  -- A MESMA MESA DE PENDENCIAS que ele ja responde no WhatsApp: "RESPOSTA 81
  -- <texto>". Nao invento canal novo -- o Tel ja tem o dele, e a resposta
  -- volta sozinha para quem perguntou.
  INSERT INTO pendencias (codigo, o_que_falta, de_quem, avisar, status)
       VALUES (NULL, left(btrim(coalesce(p_pergunta, t.texto, '')), 400),
               'secretaria', regexp_replace(coalesce(k.telefone, ''), '\D', '', 'g'), 'aberta')
    RETURNING id INTO v_pend;

  PERFORM nai_avisar_tel(p_turno, NULL,
    'Tel, ' || v_nome || ' (' || nai_fone_fmt(k.telefone) || ') perguntou uma coisa que eu ainda '
    || 'não sei responder:' || E'\n"' || left(btrim(coalesce(p_pergunta, t.texto, '')), 300) || '"'
    || E'\nMe ensina? Responda: RESPOSTA ' || v_pend || ' <o que eu digo a ele>. '
    || 'Eu mando para ele e guardo para a próxima.',
    'secretaria_pergunta');

  PERFORM nai_usou_ferramenta(p_turno, 'escalar');
  PERFORM nai_anotar(p_turno, 5, 'secretaria_perguntou', 'mudou', 'pendencia ' || v_pend);

  -- Ela NAO cala (Tel, 16/09: "teve um que mandou boa noite e ela n
  -- respondeu"). Diz que vai ver e o Tel responde pela pendencia.
  RETURN QUERY SELECT
    ('Vou confirmar isso certinho'
     || coalesce(', ' || nai_vocativo(coalesce(k.nome_completo, k.nome_whatsapp)), '')
     || ', e já te respondo por aqui!')::text,
    ('mande o texto_pronto como veio e pare por aqui: quem responde o resto e o Tel.')::text;
END;
$function$
;
