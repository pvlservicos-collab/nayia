CREATE OR REPLACE FUNCTION public.nai_escalar_link_de_catalogo(p_turno bigint, p_escreveu text)
 RETURNS text
 LANGUAGE plpgsql
AS $function$
DECLARE t nai_turno; k nai_contato; v_nome text; v_pend int;
BEGIN
  SELECT * INTO t FROM nai_turno WHERE id = p_turno;
  SELECT * INTO k FROM nai_contato WHERE id = t.contato_id;
  IF k.id IS NULL THEN RETURN NULL; END IF;
  v_nome := coalesce(k.nome_completo, k.nome_whatsapp, k.telefone);

  -- A MESMA MESA DE PENDENCIAS de sempre: ele responde "RESPOSTA <n> <texto>"
  -- e o corretor recebe. Sem isto ele lia o link e nao tinha por onde
  -- responder -- a conversa morria com ele.
  INSERT INTO pendencias (codigo, o_que_falta, de_quem, avisar, status)
       VALUES (NULL, left('link do catálogo: ' || coalesce(p_escreveu, ''), 400),
               'secretaria', regexp_replace(coalesce(k.telefone, ''), '\D', '', 'g'), 'aberta')
    RETURNING id INTO v_pend;

  PERFORM nai_avisar_tel(p_turno, NULL,
    'Tel, ' || v_nome || ' (' || nai_fone_fmt(k.telefone) || ') perguntou de um imóvel mandando o '
    || 'link do catálogo do WhatsApp:' || E'\n' || left(coalesce(p_escreveu, ''), 400) || E'\n'
    || 'O link não diz qual imóvel é — só você abrindo dá para ver.'
    || E'\nMe diz o que responder: RESPOSTA ' || v_pend || ' <o que eu digo a ele>. '
    || 'Eu mando para ele e guardo para a próxima.',
    'link_de_catalogo');

  PERFORM nai_usou_ferramenta(p_turno, 'escalar');

  RETURN ('Recebi' || coalesce(', ' || nai_vocativo(coalesce(k.nome_completo, k.nome_whatsapp)), '')
          || '! Já te respondo por aqui.')::text;
END;
$function$
;
