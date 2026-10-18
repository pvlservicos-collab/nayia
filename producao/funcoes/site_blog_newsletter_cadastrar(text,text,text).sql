CREATE OR REPLACE FUNCTION public.site_blog_newsletter_cadastrar(p_nome text, p_telefone text, p_creci text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE v_tel text := regexp_replace(coalesce(p_telefone, ''), '\D', '', 'g'); v_id bigint; v_novo boolean; v_nome text; v_turno bigint;
BEGIN
  IF v_tel ~ '^55' AND length(v_tel) IN (12, 13) THEN NULL;
  ELSIF length(v_tel) IN (10, 11) THEN v_tel := '55' || v_tel;
  ELSE RETURN jsonb_build_object('ok', false, 'erro', 'Confira o WhatsApp: use DDD + número, ex.: [telefone …9999].');
  END IF;
  v_nome := nullif(left(btrim(coalesce(p_nome, '')), 80), '');
  IF v_nome IS NULL THEN RETURN jsonb_build_object('ok', false, 'erro', 'Diga o seu nome.'); END IF;
  INSERT INTO blog_newsletter_corretor AS c (telefone, nome, creci, ativo, criado_em, saiu_em)
  VALUES (v_tel, v_nome, nullif(left(btrim(coalesce(p_creci, '')), 30), ''), true, now(), NULL)
  ON CONFLICT (telefone) DO UPDATE SET nome = EXCLUDED.nome, creci = coalesce(EXCLUDED.creci, c.creci), ativo = true, saiu_em = NULL,
                                       criado_em = CASE WHEN c.ativo THEN c.criado_em ELSE now() END
  RETURNING id, (xmax = 0) INTO v_id, v_novo;
  -- as boas-vindas saem pelo caminho do Enviar imóvel (papel 'entrega', pela Parceria): a parede exige um turno de
  -- comando do Tel, como o nai_disparo_enfileirar faz
  IF v_novo THEN
    INSERT INTO nai_turno (contato_id, papel, texto)
    VALUES (nai_contato_do_cadastro(nai_cfg('tel_telefone'), 'Tel'), 'tel', left('newsletter do blog: boas-vindas para ' || v_tel, 500))
    RETURNING id INTO v_turno;
    PERFORM nai_enfileirar_texto(v_turno, NULL, nai_contato_do_cadastro(v_tel, v_nome), 'entrega',
      'Olá, ' || split_part(v_nome, ' ', 1) || '! Aqui é a Nay, da Imob Easy. Você entrou na nossa lista de imóveis novos: '
      || 'sempre que cadastrarmos um imóvel, te mando o card por aqui. Parceria de 50% em todos. '
      || 'Para sair da lista é só responder SAIR DA LISTA.', 'newsletter_boas_vindas', 0, now() + interval '2 seconds');
    UPDATE nai_turno SET fechado_em = now() WHERE id = v_turno;
  END IF;
  RETURN jsonb_build_object('ok', true, 'id', v_id, 'novo', v_novo);
END
$function$;
