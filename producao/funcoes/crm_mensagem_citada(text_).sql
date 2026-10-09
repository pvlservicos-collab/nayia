CREATE OR REPLACE FUNCTION public.crm_mensagem_citada(p_ids text[])
 RETURNS TABLE(message_id text, quem text, texto text)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_id    text;
  v_quem  text;
  v_texto text;
  r       record;
BEGIN
  FOR v_id IN
    SELECT DISTINCT btrim(x) FROM unnest(coalesce(p_ids, '{}'::text[])) x
     WHERE nullif(btrim(x), '') IS NOT NULL LIMIT 300
  LOOP
    v_quem := NULL; v_texto := NULL;

    -- 1. o CARD que o publicador mandou (no grupo, ou direto ao corretor): o mesmo card, montado de novo
    SELECT e.codigo, e.destino, e.grupo_nome, e.enviado_em INTO r
      FROM envios e WHERE e.message_id = v_id ORDER BY e.enviado_em DESC LIMIT 1;
    IF FOUND AND r.codigo ~ '^[0-9]{1,6}$' THEN
      v_quem := CASE WHEN r.destino = 'grupo' THEN 'Card postado no grupo ' || coalesce(nullif(btrim(r.grupo_nome), ''), '(sem nome)')
                     ELSE 'Card enviado pela Nay' END
                || ' · ' || to_char(r.enviado_em AT TIME ZONE 'America/Manaus', 'DD/MM HH24:MI');
      v_texto := coalesce((SELECT nullif(btrim(c.texto_pronto), '') FROM nai_card_do_imovel(r.codigo::int) c LIMIT 1),
                          'Imóvel ' || nay_saida_rotulo_do_imovel(r.codigo));
    END IF;

    -- 2. a FOTO do post (o dedo vai na foto, não no texto)
    IF v_texto IS NULL THEN
      SELECT f.codigo, f.destino, f.grupo_nome, f.enviado_em INTO r
        FROM envios_foto f WHERE f.message_id = v_id ORDER BY f.enviado_em DESC LIMIT 1;
      IF FOUND THEN
        v_quem := CASE WHEN r.destino = 'grupo' THEN 'Foto postada no grupo ' || coalesce(nullif(btrim(r.grupo_nome), ''), '(sem nome)')
                       ELSE 'Foto enviada pela Nay' END
                  || ' · ' || to_char(r.enviado_em AT TIME ZONE 'America/Manaus', 'DD/MM HH24:MI');
        v_texto := '[foto] Imóvel ' || nay_saida_rotulo_do_imovel(r.codigo::text);
      END IF;
    END IF;

    -- 3. a LISTA do grupo: o que era a lista e os imóveis dela, na ordem
    IF v_texto IS NULL THEN
      SELECT min(l.grupo_nome) AS grupo_nome, min(l.enviado_em) AS enviado_em, min(l.categoria) AS categoria,
             min(l.negocio) AS negocio, count(*) AS n,
             string_agg(nay_saida_rotulo_do_imovel(l.codigo::text), E'\n' ORDER BY l.posicao) AS itens
        INTO r FROM envios_lista_grupo l WHERE l.message_id = v_id;
      IF r.n > 0 THEN
        v_quem := 'Lista postada no grupo ' || coalesce(nullif(btrim(r.grupo_nome), ''), '(sem nome)')
                  || ' · ' || to_char(r.enviado_em AT TIME ZONE 'America/Manaus', 'DD/MM HH24:MI');
        v_texto := 'Lista de ' || CASE r.negocio WHEN 'locacao' THEN 'locação' WHEN 'venda' THEN 'venda' ELSE coalesce(r.negocio, 'imóveis') END
                   || coalesce(' · ' || replace(r.categoria, '_', ' '), '') || ' (' || r.n || ' imóveis)' || E'\n' || r.itens;
      END IF;
    END IF;

    -- 4. o que a Nay mandou no privado (a velha, a nova e a antiga)
    IF v_texto IS NULL THEN
      SELECT 'Nay', coalesce(nullif(btrim(s.texto), ''), '[foto do imóvel ' || s.codigo || ']') INTO v_quem, v_texto
        FROM nai_saida s WHERE s.message_id = v_id ORDER BY s.id DESC LIMIT 1;
    END IF;
    IF v_texto IS NULL THEN
      SELECT 'Nay', coalesce(nullif(btrim(s.texto), ''), '[foto do imóvel ' || s.codigo || ']') INTO v_quem, v_texto
        FROM core_saida s WHERE s.message_id = v_id ORDER BY s.id DESC LIMIT 1;
    END IF;
    IF v_texto IS NULL THEN
      SELECT 'Nay', nullif(btrim(s.texto), '') INTO v_quem, v_texto
        FROM mensagem_saida s WHERE s.message_id = v_id LIMIT 1;
    END IF;

    -- 5. mensagem que chegou (dele mesmo, ou de grupo)
    IF v_texto IS NULL THEN
      SELECT CASE WHEN m.direcao = 'recebida' THEN nullif(btrim(m.nome), '') ELSE 'Nay' END,
             coalesce(nullif(btrim(m.texto), ''), '[' || m.origem || ']') INTO v_quem, v_texto
        FROM mensagens m WHERE m.message_id = v_id ORDER BY m.id DESC LIMIT 1;
    END IF;
    IF v_texto IS NULL THEN
      SELECT NULL, coalesce(nullif(btrim(m.texto), ''), nullif(btrim(m.transcricao), ''), '[' || m.tipo || ']') INTO v_quem, v_texto
        FROM core_mensagem m WHERE m.message_id = v_id LIMIT 1;
    END IF;
    IF v_texto IS NULL THEN
      SELECT nullif(btrim(coalesce(g.remetente, '') || coalesce(' no grupo ' || nullif(btrim(g.grupo_nome), ''), '')), ''),
             nullif(btrim(g.texto), '') INTO v_quem, v_texto
        FROM grupo_mensagens g WHERE g.message_id = v_id LIMIT 1;
    END IF;
    IF v_texto IS NULL THEN
      SELECT CASE WHEN c.direcao = 'recebida' THEN NULL ELSE 'Nay (captação)' END, nullif(btrim(c.texto), '') INTO v_quem, v_texto
        FROM captacao_mensagens c WHERE c.message_id = v_id ORDER BY c.id DESC LIMIT 1;
    END IF;

    -- 6. saiu de um robô nosso e só o registro do envio ficou: diz de onde foi
    IF v_texto IS NULL THEN
      SELECT 'Enviada pelo sistema · ' || to_char(s.em AT TIME ZONE 'America/Manaus', 'DD/MM HH24:MI'),
             '[' || CASE WHEN s.rota ~ 'image' THEN 'imagem' WHEN s.rota ~ 'audio' THEN 'áudio' ELSE 'mensagem' END || ' enviada '
             || CASE s.quem WHEN 'disparar_grade.py' THEN 'pela grade dos grupos'
                            WHEN 'servidor.py' THEN 'por comando do Tel'
                            WHEN 'alertar_visitas.py' THEN 'pelo alerta de visitas'
                            WHEN 'detectar_visitas.py' THEN 'pelo detector de visitas'
                            ELSE 'por ' || coalesce(s.quem, 'um robô') END || ']'
        INTO v_quem, v_texto
        FROM saida_do_sistema s WHERE s.message_id = v_id LIMIT 1;
    END IF;

    IF v_texto IS NOT NULL THEN
      message_id := v_id; quem := v_quem; texto := left(v_texto, 3000);
      RETURN NEXT;
    END IF;
  END LOOP;
END
$function$;
