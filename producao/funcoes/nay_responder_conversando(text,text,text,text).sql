CREATE OR REPLACE FUNCTION public.nay_responder_conversando(p_pendencia_id text, p_texto text, p_msg_id text, p_telefone text DEFAULT NULL::text)
 RETURNS TABLE(acao text, texto_pronto text, avisar text, msg_corretor text)
 LANGUAGE plpgsql
AS $function$
DECLARE
  v_id    int    := NULLIF(regexp_replace(coalesce(p_pendencia_id,''),'[^0-9]','','g'),'')::int;
  v_msg   bigint := coalesce(NULLIF(regexp_replace(coalesce(p_msg_id,''),'[^0-9]','','g'),'')::bigint, 0);
  v_texto text   := btrim(coalesce(p_texto,''));
  r       record;
  d       record;
  n       record;
  achou   boolean;
  v_nome  text;
BEGIN
  -- A PAREDE DE IDENTIDADE, que faltava (achada em auditoria, 31/08).
  -- Sem ela, QUALQUER corretor podia fazer o modelo chamar esta funcao e
  -- gravar resposta falsa em `pendencias.resposta` -- que depois e reusada
  -- com todo mundo que perguntar parecido naquele imovel, para sempre e
  -- sem desfazer. A funcao irma, `nay_guardar_como_funciona_visita`, ja
  -- tinha essa parede; esta nasceu sem, e o buraco ficou aberto dois dias.
  -- O telefone vem do FLUXO, nunca do modelo.
  IF regexp_replace(coalesce(p_telefone,''),'[^0-9]','','g') <> '[telefone …7316]' THEN
    RETURN QUERY SELECT 'nada'::text,
      'so o Tel responde pendencia. nao grave nada e nao diga que respondeu.'::text,
      NULL::text, NULL::text;
    RETURN;
  END IF;

  IF v_id IS NULL THEN
    RETURN QUERY SELECT 'nada'::text,
      'nao entendi de qual pendencia voce esta falando. pergunte ao Tel qual e.'::text,
      NULL::text, NULL::text;
    RETURN;
  END IF;

  SELECT * INTO r FROM pendencias WHERE id = v_id AND status = 'aberta';
  IF NOT FOUND THEN
    RETURN QUERY SELECT 'nada'::text,
      ('a pendencia ' || v_id || ' nao esta aberta. diga isso ao Tel e nao invente resposta.')::text,
      NULL::text, NULL::text;
    RETURN;
  END IF;

  -- O nome do corretor vem do telefone de DESTINO. `de_quem` guarda quem
  -- levantou a pendencia (costuma ser 'tel') -- usa-lo aqui fazia a Nay
  -- dizer "vou dizer ao tel" quando quem espera e o corretor.
  SELECT split_part(btrim(coalesce(c.nome,'')), ' ', 1) INTO v_nome
    FROM corretores c
   WHERE c.telefone = regexp_replace(coalesce(r.avisar,''),'[^0-9]','','g');
  IF coalesce(v_nome,'') = '' THEN
    SELECT split_part(btrim(coalesce(m.nome,'')), ' ', 1) INTO v_nome
      FROM mensagens m
     WHERE m.telefone = regexp_replace(coalesce(r.avisar,''),'[^0-9]','','g')
       AND coalesce(m.nome,'') <> ''
     ORDER BY m.id DESC LIMIT 1;
  END IF;
  v_nome := coalesce(NULLIF(btrim(coalesce(v_nome,'')),''), 'corretor');

  SELECT * INTO d FROM pendencia_rascunho WHERE pendencia_id = v_id;
  achou := FOUND;

  -- ---------------------------------------------------------- 1a chamada
  IF NOT achou THEN
    IF v_texto = '' THEN
      RETURN QUERY SELECT 'nada'::text,
        'o Tel nao disse o que responder. pergunte a ele o que dizer ao corretor.'::text,
        NULL::text, NULL::text;
      RETURN;
    END IF;
    INSERT INTO pendencia_rascunho (pendencia_id, texto, criado_msg_id)
      VALUES (v_id, v_texto, v_msg);
    RETURN QUERY SELECT 'confirmar'::text,
      ('pergunte ao Tel: vou dizer ao ' || v_nome ||
       ' que ' || v_texto || '. confirma? NAO envie nada ate ele responder.')::text,
      NULL::text, NULL::text;
    RETURN;
  END IF;

  -- ------------------------------------- 2a chamada, mesma mensagem do Tel
  -- A PAREDE: ela chamou duas vezes sem o Tel ter falado no meio.
  IF v_msg <= d.criado_msg_id THEN
    RETURN QUERY SELECT 'esperar'::text,
      ('voce ainda nao ouviu a confirmacao do Tel. pergunte: vou dizer ao ' ||
       v_nome || ' que ' || d.texto || '. confirma?')::text,
      NULL::text, NULL::text;
    RETURN;
  END IF;

  -- ------------------------------------ nova mensagem do Tel, texto mudou
  -- Ele corrigiu em vez de confirmar. Vira rascunho novo, confirma de novo.
  IF v_texto <> '' AND v_texto <> d.texto THEN
    UPDATE pendencia_rascunho
       SET texto = v_texto, criado_msg_id = v_msg, criado_em = now()
     WHERE pendencia_id = v_id;
    RETURN QUERY SELECT 'confirmar'::text,
      ('pergunte ao Tel: entao vou dizer ao ' || v_nome ||
       ' que ' || v_texto || '. confirma?')::text,
      NULL::text, NULL::text;
    RETURN;
  END IF;

  -- ------------------------------------------- confirmado: pode enviar
  SELECT * INTO n FROM nay_comando('RESPOSTA', v_id::text, d.texto);
  DELETE FROM pendencia_rascunho WHERE pendencia_id = v_id;

  IF coalesce(n.avisar,'') = '' THEN
    RETURN QUERY SELECT 'nada'::text,
      ('nao consegui responder a pendencia ' || v_id || '. avise o Tel que nao deu certo.')::text,
      NULL::text, NULL::text;
    RETURN;
  END IF;

  RETURN QUERY SELECT 'enviar'::text,
    ('pronto, avisei o ' || v_nome || '. diga isso ao Tel.')::text,
    n.avisar, n.msg_corretor;
END;
$function$;
