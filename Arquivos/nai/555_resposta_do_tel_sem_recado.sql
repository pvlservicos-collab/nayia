-- 555: a resposta do Tel não chega crua ao corretor da Parceria (Pedro, 31/10/2026: "resolve as falhas da Nay" e
-- "sim autorizo e não me pergunta já faz", depois do CRM › Guia de atendimento).
--
-- A leitura das conversas achou respostas da fila que não eram resposta: "chegou", "Ah sim", "ela passa a atender",
-- "Dele que se faz análise" (pergunta_fila 241, 284, 292, 307, 309). O Tel escrevia no PV sobre outra coisa e a fila
-- tomava a frase como a resposta da pergunta da vez; ao corretor ia "Sobre a sua pergunta: Chegou". E a ordem dele para
-- a Nay ia como estava: "Sobre a sua pergunta: Fala que a gente vai ver via WhatsApp".
--   pergunta_fila_e_recado      o que é recado, não resposta (a pergunta continua esperando)
--   pergunta_fila_fala_do_tel   "Fala que a gente vai ver" -> "a gente vai ver" (a Nay fala, não repassa a ordem)
-- O WhatsApp Leads passa pelo nay-olx (resposta_ao_cliente, mesmo dia), que reescreve com o modelo.
BEGIN;

CREATE OR REPLACE FUNCTION public.pergunta_fila_e_recado(p_texto text)
 RETURNS boolean
 LANGUAGE sql
 STABLE
 SET search_path TO 'public'
AS $function$
  SELECT lower(unaccent(btrim(coalesce(p_texto, '')))) ~ ('^(ah sim|ah ta|ah ok|chegou|excelente|perfeito|otimo|top|tranquilo'
           || '|entendi|ta bom|ta certo|sim sim|ok obrigad[oa]|obrigad[oa] nay|k{2,}|(ha){2,}|rs+)[[:space:]!.,]*$')
      OR lower(unaccent(coalesce(p_texto, ''))) ~ '\m(passa a atender|nunca responde)\M'
$function$;

CREATE OR REPLACE FUNCTION public.pergunta_fila_fala_do_tel(p_texto text)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
AS $function$
  SELECT coalesce(nullif(btrim(regexp_replace(btrim(coalesce(p_texto, '')),
           ('^(fala|diz|diga|avisa|responde|explica)([[:space:]]+(pra|para|pro|a|ao|à)[[:space:]]+(ele|ela|o corretor'
            || '|a corretora|o cliente|a cliente|o rapaz|a moça))?[[:space:]]+(que[[:space:]]+)?'), '', 'i')), ''),
         btrim(coalesce(p_texto, '')))
$function$;

CREATE OR REPLACE FUNCTION public.pergunta_fila_resposta_valida(p_contato bigint, p_texto text, p_citado text DEFAULT NULL::text)
 RETURNS boolean
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'public'
AS $function$
DECLARE v_tel bigint; s text; a text;
BEGIN
  IF p_contato IS NULL OR NOT pergunta_fila_ligada() THEN RETURN false; END IF;
  IF NOT EXISTS (SELECT 1 FROM pergunta_fila WHERE estado = 'perguntada') THEN RETURN false; END IF;
  SELECT id INTO v_tel FROM nai_contato WHERE chave = nai_chave(nai_cfg('tel_telefone')) LIMIT 1;
  IF v_tel IS NULL OR NOT (p_contato = v_tel OR p_contato = ANY (coalesce(nai_contato_irmaos(v_tel), '{}'))) THEN
    RETURN false;
  END IF;
  s := btrim(regexp_replace(coalesce(p_texto, ''), '^\s*@?nay[\s,:;.!-]*', '', 'i'));
  IF s = '' THEN RETURN false; END IF;
  -- marcou uma mensagem: só vale se for a pergunta (ou a cobrança) da fila
  IF nullif(btrim(coalesce(p_citado, '')), '') IS NOT NULL THEN
    RETURN EXISTS (SELECT 1 FROM nai_saida o WHERE o.message_id = btrim(p_citado)
                      AND o.motivo IN ('pergunta_fila', 'pergunta_fila_cobranca'));
  END IF;
  -- os outros comandos dele passam antes: a fila não engole comando
  IF nai_e_comando_tel(s) OR nai_e_comando_extra(s) OR nai_e_comando_envio(s) OR nai_e_comando_checklist(s)
     OR nai_e_pedido_lembrete(s) OR nay_saida_resposta_valida(p_contato, s, NULL)
     OR nai_resposta_aprovacao_valida(p_contato, s) THEN
    RETURN false;
  END IF;
  a := lower(unaccent(s));
  -- os do caminho antigo (RESPOSTA n, DESCARTA n, PENDENCIAS) e os do publicador (posta, vendeu, envia ... para)
  IF a ~ '^(resposta|responde|responder)( a)?( pendencias?)?\s+\d{1,6}\s'
     OR a ~ '^(descarta|descartar|descarte|esquece|esquecer|apaga|apagar|cancela|cancelar|ignora|ignorar)\s+(\d{1,6}|tudo)\M'
     OR a ~ '^(pendencias?|pendentes)\s*$'
     OR a ~ '^(posta|postar|publica|publicar|dispara|disparar|solta|tira|tirar|remove|remover|retira|retirar|vendeu|vendido|vendida|alugou|alugado|alugada|vagas?|lista)\M'
     OR a ~ '^(envi|m[a]?nd|repass|encaminh|mostr|post|public|dispar|solt)[a-z]*\M.*\m(para|pra|pro)\M'
     OR a ~ '^\d{3,5}\s*[-:,]?\s*(ja)?\s*(vendeu|vendido|vendida|alugou|alugado|alugada)\M' THEN
    RETURN false;
  END IF;
  -- cumprimento e "ok" não são resposta; anúncio colado (o publicador) também não
  IF a ~ '^(bom dia|boa tarde|boa noite|oi+|ola|opa|ok|okay|blz|beleza|obrigad[oa]|valeu|show|certo)[\s!.,]*$' THEN
    RETURN false;
  END IF;
  IF length(s) > 400 AND s ~* 'R\$\s*\d' THEN RETURN false; END IF;
  -- 555: recado dele para a Nay ou para a equipe ("chegou", "ah sim", "ela passa a atender") não responde a
  -- pergunta da fila: a pergunta continua esperando a resposta de verdade
  IF pergunta_fila_e_recado(s) THEN RETURN false; END IF;
  RETURN true;
END
$function$;

CREATE OR REPLACE FUNCTION public.pergunta_fila_responder(p_turno bigint, p_contato bigint, p_texto text, p_citado text DEFAULT NULL::text)
 RETURNS text
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
DECLARE
  f      pergunta_fila;
  s      text;
  a      text;
  pos    record;
  v_dest bigint;
  v_msg  text;
  v_ass  text;
  v_quem text;
  v_int  bigint;
BEGIN
  IF NOT pergunta_fila_resposta_valida(p_contato, p_texto, p_citado) THEN RETURN NULL; END IF;
  SELECT * INTO f FROM pergunta_fila WHERE estado = 'perguntada' LIMIT 1 FOR UPDATE;
  IF f.id IS NULL THEN RETURN NULL; END IF;
  SELECT * INTO pos FROM pergunta_fila_posicao();
  s := btrim(regexp_replace(coalesce(p_texto, ''), '^\s*@?nay[\s,:;.!-]*', '', 'i'));
  a := lower(unaccent(s));
  v_quem := coalesce(nullif(btrim(f.cliente), '') || ' — ', '') || nai_fone_fmt(f.chave);

  -- 496 (Pedro, 24/10): "Adicionar inteligência: ..." grava a regra nas inteligências gerais (495, a aba da página
  -- Agentes) para as próximas vezes, nas duas Nays; a pergunta continua esperando a resposta ao cliente.
  IF a ~ '^adicionar? (uma )?intelig[eê]ncias?\s*[:\-]' OR a ~ '^intelig[eê]ncia\s*:' THEN
    INSERT INTO nay_inteligencia_geral (regra, porque, origem, vale_para, assunto, criada_por)
    VALUES (btrim(regexp_replace(s, '^\s*(adicionar?\s+(uma\s+)?)?intelig[eêÊ]ncias?\s*[:\-]\s*', '', 'i')),
            'O Tel, respondendo à pergunta ' || pos.k || '/' || pos.n || ' (' || left(btrim(f.pergunta), 160) || ')',
            'tel', ARRAY['parceria', 'leads'], 'do Tel', 'tel (fila de perguntas)')
    RETURNING id INTO v_int;
    v_msg := '🧠 Guardei a inteligência #' || v_int || ' para as próximas vezes (Nay Parceria e Nay Leads; fica na página '
             || 'Agentes). A pergunta ' || pos.k || '/' || pos.n || ' continua aqui: responda o que digo ao cliente, '
             || 'ou PULAR / DESCARTAR.';
    PERFORM nai_enfileirar_texto(p_turno, NULL, p_contato, 'turno', v_msg, 'pergunta_fila_ok', 1);
    RETURN v_msg;
  ELSIF a ~ '^(pular|pula|pulo|depois|deixa (para|pra) depois)[\s.!]*$' THEN
    IF NOT EXISTS (SELECT 1 FROM pergunta_fila WHERE estado = 'fila') THEN
      v_msg := 'Essa é a única pergunta da fila: continua esperando a sua resposta (ou DESCARTAR).';
    ELSE
      UPDATE pergunta_fila SET estado = 'fila', perguntada_em = NULL, cobrada_em = NULL, saida_id = NULL,
                               ordem = (SELECT max(ordem) + 1 FROM pergunta_fila)
       WHERE id = f.id;
      v_msg := 'Deixei a pergunta ' || pos.k || '/' || pos.n || ' para o fim da fila.';
    END IF;
  ELSIF a ~ '^(descartar|descarta|descarte|tira|tirar)( (da|essa|a) (fila|pergunta))?[\s.!]*$' THEN
    UPDATE pergunta_fila SET estado = 'descartada', respondida_em = now() WHERE id = f.id;
    IF f.origem = 'pendencias' THEN
      UPDATE pendencias SET status = 'descartada', respondida_em = now() WHERE id = f.origem_id;
    END IF;
    v_msg := 'Tirei da fila a pergunta ' || pos.k || '/' || pos.n || '.';
  ELSE
    UPDATE pergunta_fila SET estado = 'respondida', resposta = s, respondida_em = now() WHERE id = f.id;
    IF f.linha = 'parceria' THEN
      SELECT id INTO v_dest FROM nai_contato WHERE chave = nai_chave(f.chave) LIMIT 1;
      IF v_dest IS NULL THEN
        SELECT id INTO v_dest FROM nai_contato
         WHERE right(regexp_replace(coalesce(telefone, ''), '\D', '', 'g'), 8) = right(f.chave, 8) ORDER BY id LIMIT 1;
      END IF;
      IF v_dest IS NOT NULL THEN
        -- o mesmo caminho do DEVOLVER: 'entrega' a partir do turno do Tel, motivo resposta_do_tel (fecha a pendência)
        PERFORM nai_enfileirar_texto(p_turno, NULL, v_dest, 'entrega',
          'Sobre ' || CASE WHEN f.codigo IS NOT NULL
                           THEN 'o #' || f.codigo || coalesce(' (' || nullif(btrim(f.imovel), '') || ')', '')
                           ELSE 'a sua pergunta' END || ': ' || nai_frase_maiuscula(pergunta_fila_fala_do_tel(s)),
          'resposta_do_tel', 2);
        UPDATE pergunta_fila SET entregue_em = now() WHERE id = f.id;
        v_msg := '✅ Peguei a resposta da pergunta ' || pos.k || '/' || pos.n || ' e mandei para ' || v_quem || '.';
      ELSE
        UPDATE pergunta_fila SET entrega_erro = 'a conversa do cliente não foi achada' WHERE id = f.id;
        v_msg := '⚠️ Peguei a resposta da pergunta ' || pos.k || '/' || pos.n || ', mas não achei a conversa de '
                 || v_quem || ' para entregar.';
      END IF;
    ELSE
      v_msg := '✅ Peguei a resposta da pergunta ' || pos.k || '/' || pos.n || ': a Nay manda para ' || v_quem
               || ' pelo WhatsApp de captação.';
    END IF;
    IF f.origem = 'pendencias' THEN
      UPDATE pendencias SET status = 'respondida', resposta = s, respondida_em = now() WHERE id = f.origem_id;
    END IF;
    -- a memória: com o código, a resposta fica no imóvel (sem número de unidade, que é de um apartamento só)
    IF f.codigo IS NOT NULL AND a !~ '\m(apto|ap|apartamento|bloco|torre|unidade)\s*\.?\s*\d' THEN
      v_ass := coalesce(nay_assunto_do_imovel(f.pergunta),
                        'pergunta: ' || left(lower(unaccent(btrim(regexp_replace(f.pergunta, '\s+', ' ', 'g')))), 120));
      PERFORM nay_gravar_conhecimento(f.codigo::text, v_ass, s, 'tel (fila de perguntas)');
    END IF;
  END IF;
  PERFORM nai_enfileirar_texto(p_turno, NULL, p_contato, 'turno', v_msg, 'pergunta_fila_ok', 1);
  PERFORM pergunta_fila_perguntar_proxima();
  RETURN v_msg;
END
$function$;

CREATE OR REPLACE FUNCTION public.crm_tel_responder(p_fonte text, p_id bigint, p_acao text, p_texto text, p_quem text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'privado'
 SET lock_timeout TO '3s'
AS $function$
DECLARE
  f      pergunta_fila;
  d      privado.duvida;
  s      text := btrim(coalesce(p_texto, ''));
  v_quem text := coalesce(nullif(btrim(p_quem), ''), 'o Tel pelo CRM');
  v_dest bigint;
  v_turno bigint;
  v_era_pv boolean;
  v_ass  text;
  v_msg  text;
BEGIN
  IF p_acao NOT IN ('responder', 'descartar') THEN
    RETURN jsonb_build_object('ok', false, 'mensagem', 'Ação inválida.');
  END IF;
  IF p_acao = 'responder' AND s = '' THEN
    RETURN jsonb_build_object('ok', false, 'mensagem', 'Escreva a resposta antes de enviar.');
  END IF;

  IF p_fonte = 'fila' THEN
    SELECT * INTO f FROM pergunta_fila WHERE id = p_id AND estado IN ('fila', 'perguntada', 'agente') FOR UPDATE;
    IF f.id IS NULL THEN
      RETURN jsonb_build_object('ok', false, 'mensagem', 'Essa dúvida já foi respondida ou descartada.');
    END IF;
    v_era_pv := f.estado = 'perguntada';
    IF p_acao = 'descartar' THEN
      UPDATE pergunta_fila SET estado = 'descartada', respondida_em = now(),
             detalhe = concat_ws(' · ', nullif(detalhe, ''), 'descartada no CRM por ' || v_quem)
       WHERE id = f.id;
      IF f.origem = 'pendencias' THEN
        UPDATE pendencias SET status = 'descartada', respondida_em = now() WHERE id = f.origem_id;
      END IF;
      v_msg := 'Descartada.';
    ELSE
      UPDATE pergunta_fila SET estado = 'respondida', resposta = s, respondida_em = now(),
             detalhe = concat_ws(' · ', nullif(detalhe, ''), 'respondida no CRM por ' || v_quem)
       WHERE id = f.id;
      IF f.linha = 'parceria' THEN
        SELECT id INTO v_dest FROM nai_contato WHERE chave = nai_chave(f.chave) LIMIT 1;
        IF v_dest IS NULL THEN
          SELECT id INTO v_dest FROM nai_contato
           WHERE right(regexp_replace(coalesce(telefone, ''), '\D', '', 'g'), 8) = right(f.chave, 8) ORDER BY id LIMIT 1;
        END IF;
        IF v_dest IS NULL THEN
          UPDATE pergunta_fila SET entrega_erro = 'a conversa do cliente não foi achada' WHERE id = f.id;
          v_msg := 'Guardei a resposta, mas não achei a conversa do cliente na Parceria para entregar.';
        ELSE
          -- o mesmo caminho do DEVOLVER: 'entrega' a partir de um turno do Tel, motivo resposta_do_tel
          INSERT INTO nai_turno (contato_id, papel, texto)
          VALUES (nai_contato_do_cadastro(nai_cfg('tel_telefone'), 'Tel'), 'tel',
                  left('Respostas Tel no CRM (' || v_quem || '): pergunta ' || f.id, 500))
          RETURNING id INTO v_turno;
          PERFORM nai_enfileirar_texto(v_turno, NULL, v_dest, 'entrega',
            'Sobre ' || CASE WHEN f.codigo IS NOT NULL
                             THEN 'o #' || f.codigo || coalesce(' (' || nullif(btrim(f.imovel), '') || ')', '')
                             ELSE 'a sua pergunta' END || ': ' || nai_frase_maiuscula(pergunta_fila_fala_do_tel(s)),
            'resposta_do_tel', 2);
          UPDATE nai_saida SET enviar_apos = now() + interval '2 seconds' WHERE turno_id = v_turno AND estado = 'pendente';
          UPDATE nai_turno SET fechado_em = now() WHERE id = v_turno;
          UPDATE pergunta_fila SET entregue_em = now() WHERE id = f.id;
          v_msg := 'Resposta enviada ao corretor pela Parceria.';
        END IF;
      ELSE
        v_msg := 'Resposta guardada: a Nay manda ao cliente pelo WhatsApp Leads em até 1 minuto.';
      END IF;
      IF f.origem = 'pendencias' THEN
        UPDATE pendencias SET status = 'respondida', resposta = s, respondida_em = now() WHERE id = f.origem_id;
      END IF;
      -- a memória do imóvel, como no PV (sem número de unidade, que é de um apartamento só)
      IF f.codigo IS NOT NULL AND lower(unaccent(s)) !~ '\m(apto|ap|apartamento|bloco|torre|unidade)\s*\.?\s*\d' THEN
        v_ass := coalesce(nay_assunto_do_imovel(f.pergunta),
                          'pergunta: ' || left(lower(unaccent(btrim(regexp_replace(f.pergunta, '\s+', ' ', 'g')))), 120));
        PERFORM nay_gravar_conhecimento(f.codigo::text, v_ass, s, 'tel (Respostas Tel no CRM)');
      END IF;
    END IF;
    -- a do PV do Tel saiu: o PV passa para a próxima da fila
    IF v_era_pv THEN
      PERFORM pergunta_fila_perguntar_proxima();
    END IF;
    RETURN jsonb_build_object('ok', true, 'mensagem', v_msg);
  END IF;

  IF p_fonte = 'duvida' THEN
    SELECT * INTO d FROM privado.duvida WHERE id = p_id AND estado = 'com_o_tel' FOR UPDATE;
    IF d.id IS NULL THEN
      RETURN jsonb_build_object('ok', false, 'mensagem', 'Essa dúvida já foi respondida ou encerrada.');
    END IF;
    IF p_acao = 'descartar' THEN
      UPDATE privado.duvida SET estado = 'encerrada', situacao = 'descartada_pelo_tel', atualizada_em = now(),
             historico = historico || jsonb_build_array(jsonb_build_object('em', now(), 'feito', 'descartada no CRM por ' || v_quem))
       WHERE id = d.id;
      RETURN jsonb_build_object('ok', true, 'mensagem', 'Descartada.');
    END IF;
    PERFORM nay_duvida_mandar_pela_parceria(d.cliente_tel,
      'Sobre ' || CASE WHEN d.codigo IS NOT NULL THEN 'o #' || d.codigo ELSE 'a sua pergunta' END || ': ' || nai_frase_maiuscula(pergunta_fila_fala_do_tel(s)),
      NULL, d.codigo);
    UPDATE privado.duvida SET estado = 'respondida', situacao = 'tel_respondeu', resposta = s, respondida_em = now(),
           atualizada_em = now(),
           historico = historico || jsonb_build_array(jsonb_build_object('em', now(), 'feito', 'respondida no CRM por ' || v_quem))
     WHERE id = d.id;
    RETURN jsonb_build_object('ok', true, 'mensagem', 'Resposta enviada ao corretor pela Parceria.');
  END IF;

  RETURN jsonb_build_object('ok', false, 'mensagem', 'Dúvida não encontrada.');
END $function$;

COMMIT;
