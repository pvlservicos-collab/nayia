-- 294 (05/10/2026, Pedro, a lista de erros da manhã). Três funções vivas, cada uma com uma troca pequena.
--
-- 1. crm_etapa_manual: "quando eu pego alguém de fechamento e jogo para proprietário dá erro, diz checklist
--    aberto ... se não foi preenchido, algo é cancelado ao mudar de etapa". Mudar para Visitas ou Proprietários
--    fecha o fechamento aberto (como já acontecia ao voltar para Todos).
-- 2. crm_nay_voltar: "quando clico em Nay voltar a atender é para ela responder a última ou as últimas mensagens
--    do lead". O CRM já reentrega as mensagens; a porta barrava o contato ainda não liberado. O clique libera.
-- 3. nai_enviar_imoveis_para (o ENVIA do Tel e da equipe): "Oi, bom dia! Segue o imóvel que fiquei de te enviar"
--    era fixa; o cumprimento só vai na primeira conversa do dia com a pessoa.
BEGIN;

CREATE OR REPLACE FUNCTION public.crm_etapa_manual(p_telefone text, p_etapa text, p_quem text)
 RETURNS TABLE(ok boolean, mensagem text)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_contato bigint;
  v_ids     bigint[];
  v_quem    text := left(coalesce(nullif(btrim(p_quem), ''), 'CRM'), 80);
BEGIN
  IF p_etapa NOT IN ('todos', 'visitas', 'proprietarios', 'fechamento', 'tel', 'rayssa', 'soltar') THEN
    RETURN QUERY SELECT false, 'Etapa desconhecida: ' || coalesce(p_etapa, '');
    RETURN;
  END IF;
  SELECT id INTO v_contato FROM nai_contato WHERE chave = nai_chave(p_telefone);
  IF v_contato IS NULL THEN
    RETURN QUERY SELECT true, 'A Nay ainda não conversou com esse número: nada a mudar do lado dela.'::text;
    RETURN;
  END IF;
  v_ids := coalesce(nai_contato_irmaos(v_contato), ARRAY[v_contato]);

  IF p_etapa = 'tel' THEN
    UPDATE nai_contato SET humano_assumiu_em = now(), humano_motivo = left('CRM: ' || v_quem || ' mandou para o Tel', 200)
     WHERE id = ANY (v_ids);  -- 215: as duas linhas da pessoa
    RETURN QUERY SELECT true, 'Com o Tel: a Nay não responde até o Tel devolver.'::text;
    RETURN;
  END IF;
  -- 208: a Rayssa, pelo mesmo caminho; "Rayssa: " na frente é o que o CRM lê
  IF p_etapa = 'rayssa' THEN
    UPDATE nai_contato SET humano_assumiu_em = now(),
                           humano_motivo = left('Rayssa: CRM: ' || v_quem || ' mandou para a Rayssa', 200)
     WHERE id = ANY (v_ids);  -- 215: as duas linhas da pessoa
    RETURN QUERY SELECT true, 'Com a Rayssa: a Nay não responde até a conversa voltar para Todos.'::text;
    RETURN;
  END IF;
  -- 212: o × da etiqueta -- só tira a marca de humano, sem mexer em etapa nem fechamento
  IF p_etapa = 'soltar' THEN
    UPDATE nai_contato SET humano_assumiu_em = NULL, humano_motivo = NULL WHERE id = ANY (v_ids);
    RETURN QUERY SELECT true, CASE WHEN nai_com_a_rayssa(v_contato, NULL) IS NULL
      THEN 'Etiqueta tirada: a Nay volta a responder.'
      ELSE 'Etiqueta tirada. A conversa continua em Visitas, Proprietários ou Fechamento: a Nay segue calada.' END;
    RETURN;
  END IF;

  INSERT INTO nai_etapa_manual (contato_id, etapa, definido_por, definido_em, valido_ate)
  VALUES (v_contato, p_etapa, v_quem, now(), CASE WHEN p_etapa = 'visitas' THEN now() + interval '7 days' END)
  ON CONFLICT (contato_id) DO UPDATE SET etapa = EXCLUDED.etapa, definido_por = EXCLUDED.definido_por,
    definido_em = EXCLUDED.definido_em, valido_ate = EXCLUDED.valido_ate;
  DELETE FROM nai_etapa_manual WHERE contato_id = ANY (v_ids) AND contato_id <> v_contato;

  IF p_etapa = 'fechamento' THEN
    INSERT INTO nai_fechamento (contato_id, iniciado_por) VALUES (v_contato, v_quem) ON CONFLICT DO NOTHING;
  ELSIF p_etapa = 'todos' THEN
    UPDATE nai_fechamento SET concluido_em = now(), concluido_por = v_quem
     WHERE contato_id = ANY (v_ids) AND concluido_em IS NULL;
    UPDATE nai_contato SET humano_assumiu_em = NULL, humano_motivo = NULL WHERE id = ANY (v_ids);
  ELSE
    -- 294: mudou de etapa (Visitas, Proprietários) com fechamento aberto: o fechamento é cancelado, senão
    -- ele segurava a conversa em Fechamento e a tela dizia "tem um fechamento aberto"
    UPDATE nai_fechamento SET concluido_em = now(), concluido_por = left(v_quem || ' (mudou de etapa)', 120)
     WHERE contato_id = ANY (v_ids) AND concluido_em IS NULL;
  END IF;
  RETURN QUERY SELECT true, CASE p_etapa
    WHEN 'visitas' THEN 'Em Visitas: quem atende é a Rayssa; a Nay não responde (7 dias ou até voltar para Todos).'
    WHEN 'fechamento' THEN 'Em Fechamento: quem atende é a Rayssa até ela concluir.'
    WHEN 'proprietarios' THEN 'Em Proprietários: a Nay não responde.'
    ELSE 'Em Todos: a Nay volta a atender.' END;
END $function$;

CREATE OR REPLACE FUNCTION public.crm_nay_voltar(p_telefone text, p_quem text)
 RETURNS TABLE(ok boolean, mensagem text)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
 SET lock_timeout TO '3s'
AS $function$
DECLARE
  v_ids     bigint[];
  v_contato bigint;
  v_chave   text := nai_chave(p_telefone);
  v_quem    text := left(coalesce(nullif(btrim(p_quem), ''), 'CRM'), 80);
  v_extra   text := '';
BEGIN
  SELECT p.ids, p.contato_id INTO v_ids, v_contato FROM crm_pessoas(ARRAY[p_telefone]) p LIMIT 1;
  IF v_ids IS NULL OR cardinality(v_ids) = 0 THEN
    RETURN QUERY SELECT true, 'A Nay já atende esta conversa.'; RETURN;
  END IF;
  v_contato := coalesce(v_contato, v_ids[1]);

  -- 294: o clique também LIBERA a conversa para a porta. Sem isto, o que o CRM reentregava de um "contato
  -- novo" era barrado ("assunto que não é de corretor") e ninguém respondia (três casos em 05/10).
  UPDATE nai_contato SET humano_assumiu_em = NULL, humano_motivo = NULL, liberado_em = coalesce(liberado_em, now())
   WHERE id = ANY (v_ids);

  -- 228: dono de imóvel é da Rayssa (197)
  IF EXISTS (SELECT 1 FROM unnest(v_ids) i WHERE nai_e_proprietario_contato(i)) THEN
    RETURN QUERY SELECT true, 'Marca tirada, mas é proprietário: quem responde é a Rayssa (a Nay não fala com dono de imóvel).';
    RETURN;
  END IF;

  -- 228: Visitas/Proprietários/Fechamento seguravam a Nay calada: volta para Todos
  IF nai_com_a_rayssa(v_contato, 'corretor') IS NOT NULL
     OR EXISTS (SELECT 1 FROM nai_etapa_manual m WHERE m.contato_id = ANY (v_ids) AND m.etapa <> 'todos'
                   AND (m.valido_ate IS NULL OR m.valido_ate > now())) THEN
    INSERT INTO nai_etapa_manual (contato_id, etapa, definido_por, definido_em, valido_ate)
    VALUES (v_contato, 'todos', left(v_quem || ' (Nay voltar a atender)', 120), now(), NULL)
    ON CONFLICT (contato_id) DO UPDATE SET etapa = 'todos', definido_por = EXCLUDED.definido_por,
                                           definido_em = now(), valido_ate = NULL;
    DELETE FROM nai_etapa_manual WHERE contato_id = ANY (v_ids) AND contato_id <> v_contato;
    v_extra := v_extra || ' A conversa voltou para Todos.';
  END IF;

  -- 228: fora da lista de corretores: o clique aprova (o mesmo que CORRETOR <telefone>)
  IF v_chave IS NOT NULL AND v_chave !~ '^lid:'
     AND nai_lista_governa(v_chave, v_contato) AND NOT nai_pode_falar(v_chave, p_telefone) THEN
    PERFORM nai_decidir_corretor(p_telefone, true);
    v_extra := v_extra || ' O número foi aprovado como corretor.';
  END IF;

  RETURN QUERY SELECT true, 'A Nay voltou a atender esta conversa.' || v_extra;
END $function$;

CREATE OR REPLACE FUNCTION public.nai_enviar_imoveis_para(p_turno bigint, p_codigos integer[], p_telefone text)
 RETURNS text
 LANGUAGE plpgsql
AS $function$
DECLARE
  v_digitos text := regexp_replace(coalesce(p_telefone, ''), '[^0-9]', '', 'g');
  v_chave   text;
  v_destino bigint;
  v_card    text;
  v_ja      timestamptz;
  v_hora    int;
  v_falou   boolean;
  v_ordem   int := 1;
  v_fotos   int;
  v_vao     int[] := '{}';
  v_linhas  text[] := '{}';
  v_feitos  text[] := '{}';
  c         int;
  i         record;
  f         record;
BEGIN
  IF length(v_digitos) < 10 THEN
    RETURN 'Não entendi o número "' || coalesce(p_telefone, '') || '". Manda assim: envia [telefone …9999] o 3210';
  END IF;
  v_chave := nai_chave(v_digitos);
  IF v_chave IS NULL OR coalesce(array_length(p_codigos, 1), 0) = 0 THEN
    RETURN 'Não entendi o pedido. Manda assim: envia [telefone …9999] o 3210';
  END IF;

  -- 1. o que pode ir
  FOREACH c IN ARRAY p_codigos LOOP
    SELECT codigo, coalesce(e_parceiro, false) AS parceiro,
           nay_esta_no_mercado(disponivel, bloqueado, publicado_no_site) AS no_mercado
      INTO i FROM imoveis WHERE codigo = c;
    IF i.codigo IS NULL OR (SELECT texto_pronto FROM nai_card_do_imovel(c)) IS NULL THEN
      v_linhas := v_linhas || (c || ': não achei esse código');
    ELSIF i.parceiro THEN
      v_linhas := v_linhas || (c || ': é imóvel de parceiro, não mandei (parceria não sai)');
    ELSIF NOT coalesce(i.no_mercado, false) THEN
      v_linhas := v_linhas || (c || ': está indisponível, não mandei');
    ELSE
      v_ja := nay_reservar_imovel_do_dia(v_chave, c, 'nai', p_turno);
      IF v_ja IS NOT NULL THEN
        v_linhas := v_linhas || (c || ': já foi para esse número ' || nay_quando_foi(v_ja)
                                 || ', não mandei de novo (libera '
                                 || nay_quando_foi(v_ja + interval '24 hours') || ')');
      ELSE
        v_vao := v_vao || c;
      END IF;
    END IF;
  END LOOP;

  IF coalesce(array_length(v_vao, 1), 0) = 0 THEN
    RETURN 'Não mandei nada para ' || nai_fone_fmt(v_digitos) || E':\n'
           || array_to_string(v_linhas, E'\n');
  END IF;

  -- 2. o contato do destino (nasce aqui se não existir)
  SELECT id INTO v_destino FROM nai_contato WHERE chave = v_chave;
  IF v_destino IS NULL THEN
    INSERT INTO nai_contato (chave, telefone, nome_whatsapp)
    VALUES (v_chave, v_digitos, NULL)
    RETURNING id INTO v_destino;
  END IF;

  -- 3. uma linha antes, dizendo o que vem (Tel, 31/08: "card e foto caindo do
  --    nada"), com a mesma frase do publicador
  v_hora := extract(hour FROM now() AT TIME ZONE 'America/Manaus');
  -- 294 (Pedro, 05/10): "não precisa ser fixa, porque às vezes nem é a primeira conversa do dia". O "Oi, bom
  -- dia!" só vai quando ainda não houve conversa com a pessoa hoje (nossa ou dela, por qualquer caminho).
  v_falou := EXISTS (SELECT 1 FROM nai_saida s
                      WHERE s.contato_id = v_destino AND s.estado IN ('enviado', 'enviando')
                        AND s.criado_em >= date_trunc('day', now() AT TIME ZONE 'America/Manaus') AT TIME ZONE 'America/Manaus')
          OR EXISTS (SELECT 1 FROM core_saida c
                      WHERE c.chave_destino = v_chave AND c.estado IN ('enviado', 'enviando')
                        AND c.criado_em >= date_trunc('day', now() AT TIME ZONE 'America/Manaus') AT TIME ZONE 'America/Manaus')
          OR EXISTS (SELECT 1 FROM mensagens m
                      WHERE m.criada_em >= date_trunc('day', now() AT TIME ZONE 'America/Manaus') AT TIME ZONE 'America/Manaus'
                        AND right(regexp_replace(m.telefone, '\D', '', 'g'), 8) = right(v_digitos, 8));
  PERFORM nai_enfileirar_texto(p_turno, NULL, v_destino, 'entrega',
    CASE WHEN v_falou THEN '' ELSE
      'Oi, ' || CASE WHEN v_hora < 12 THEN 'bom dia' WHEN v_hora < 18 THEN 'boa tarde' ELSE 'boa noite' END || '! ' END
    || CASE WHEN array_length(v_vao, 1) > 1
                    THEN 'Seguem os imóveis que fiquei de te enviar.'
                    ELSE 'Segue o imóvel que fiquei de te enviar.' END,
    'envia_comando', v_ordem);

  -- 4. card e fotos, um imóvel de cada vez, na ordem pedida
  FOREACH c IN ARRAY v_vao LOOP
    SELECT texto_pronto INTO v_card FROM nai_card_do_imovel(c);
    v_ordem := v_ordem + 1;
    PERFORM nai_enfileirar_texto(p_turno, NULL, v_destino, 'entrega', v_card, 'envia_comando', v_ordem);
    v_fotos := 0;
    FOR f IN SELECT * FROM nai_imagens_do_envio(c) LOOP
      -- a colagem de 4 fotos é só dos grupos (Tel, 14/09)
      CONTINUE WHEN f.e_colagem;
      v_ordem := v_ordem + 1;
      INSERT INTO nai_saida (turno_id, contato_id, papel_destino, chave_destino,
                             tipo, imagem_url, codigo, ordem, motivo)
      VALUES (p_turno, v_destino, 'entrega', v_chave, 'imagem', f.url, c, v_ordem, 'foto');
      v_fotos := v_fotos + 1;
    END LOOP;
    v_feitos := v_feitos || (c || ' (card e ' || v_fotos || ' foto' || CASE WHEN v_fotos = 1 THEN '' ELSE 's' END || ')');
  END LOOP;

  RETURN 'Mandei para ' || nai_fone_fmt(v_digitos) || ': ' || array_to_string(v_feitos, ', ')
         || CASE WHEN array_length(v_linhas, 1) > 0
                 THEN E'.\n' || array_to_string(v_linhas, E'\n') ELSE '.' END;
END;
$function$;

COMMIT;
