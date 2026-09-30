CREATE OR REPLACE FUNCTION public.nai_decidir_corretor(p_fone text, p_e_corretor boolean)
 RETURNS text
 LANGUAGE plpgsql
AS $function$
DECLARE
  v_chave text := nai_chave(p_fone);
  v_dig   text := regexp_replace(coalesce(p_fone, ''), '\D', '', 'g');
  v_nome  text;
BEGIN
  IF v_chave IS NULL OR v_chave ~ '^lid:' THEN
    RETURN 'Não entendi o telefone. Use: CORRETOR [telefone …8888]  ou  NAO CORRETOR [telefone …8888]';
  END IF;
  -- sem DDI, completa com 55: e assim que o corretores guarda
  IF length(v_dig) IN (10, 11) THEN v_dig := '55' || v_dig; END IF;

  SELECT coalesce(c.nome_completo, c.nome_whatsapp) INTO v_nome
    FROM nai_contato c WHERE c.chave = v_chave;

  INSERT INTO nai_corretor_pergunta (chave, telefone, nome, decisao, decidido_em)
  VALUES (v_chave, v_dig, v_nome, CASE WHEN p_e_corretor THEN 'sim' ELSE 'nao' END, now())
  ON CONFLICT (chave) DO UPDATE
     SET decisao = EXCLUDED.decisao, decidido_em = EXCLUDED.decidido_em;

  IF p_e_corretor THEN
    -- Ja existe (com ou sem o nono digito)? Atualiza. Senao, entra.
    UPDATE corretores
       SET pode_falar = true, aprovado = true, ativo = true, fonte = 'tel'
     WHERE nai_chave(telefone) = v_chave;
    IF NOT FOUND THEN
      INSERT INTO corretores (telefone, nome, origem, aprovado, ativo, pode_falar, fonte)
      VALUES (v_dig, v_nome, 'aprovado pelo Tel em ' || to_char(now(), 'DD/MM'),
              true, true, true, 'tel')
      ON CONFLICT (telefone) DO UPDATE
         SET pode_falar = true, aprovado = true, ativo = true, fonte = 'tel';
    END IF;
    RETURN 'Feito: ' || nai_fone_fmt(v_dig) || coalesce(' (' || v_nome || ')', '')
        || ' agora é corretor. A NAI atende a partir da próxima mensagem dele.';
  END IF;

  UPDATE corretores SET pode_falar = false WHERE nai_chave(telefone) = v_chave;
  RETURN 'Feito: a NAI não responde mais ' || nai_fone_fmt(v_dig)
      || coalesce(' (' || v_nome || ')', '')
      || '. Para voltar atrás: CORRETOR ' || nai_fone_fmt(v_dig);
END;
$function$;
