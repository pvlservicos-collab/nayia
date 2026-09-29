-- =====================================================================
-- 129 — ENVIA <NÚMERO> O <CÓDIGO> (27/09/2026)
--
-- Tel, urgente: "precisa enviar os imoveis que ele, eu ou a rayssa pedem...
-- ele pede para ela mandar um imovel para um numero e ela n manda".
--
-- A PROVA de que faltava: no histórico dele, nove pedidos em quatro dias, todos
-- na mesma forma, todos sem resposta --
--
--   envia 92 9450-0381 o 3050
--   envia 92 8417-5305 o 5035
--   envia 92 99462-9241 codigo 150
--
-- Não existia comando que casasse com isso. A frase caía como conversa comum e
-- ela respondia outra coisa. Agora existe.
--
-- QUEM PODE: o Tel, quem está em `equipe` (a Rayssa entrou hoje) e quem está na
-- lista curta. Todos os OUTROS comandos continuam só do Tel -- ninguém mais
-- para o atendimento nem devolve conversa por aqui.
--
-- A PAREDE DO PARCEIRO CONTINUA DE PÉ. Imóvel de parceiro não sai: as fotos nem
-- são enfileiradas (mesma checagem do `nai_enfileirar_card`) e o card é barrado
-- pelo gatilho `nai_saida_validar`. Quando isso acontece, quem mandou o comando
-- é avisado na resposta, em vez de achar que foi.
-- =====================================================================
\set ON_ERROR_STOP on

BEGIN;

-- ---------------------------------------------------------------------
-- Manda o card e as fotos de um imóvel para um número qualquer.
--
-- Devolve a frase de confirmação pronta, porque quem chama é um comando de
-- WhatsApp e o que ele precisa é de uma linha para responder.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION nai_enviar_imovel_para(p_turno bigint, p_codigo integer,
                                                  p_telefone text)
RETURNS text
LANGUAGE plpgsql
AS $fn$
DECLARE
  v_digitos text := regexp_replace(coalesce(p_telefone, ''), '[^0-9]', '', 'g');
  v_chave   text;
  v_destino bigint;
  v_card    text;
  v_parceiro boolean;
  v_ordem   int := 1;
  v_fotos   int := 0;
  f         record;
BEGIN
  IF length(v_digitos) < 8 THEN
    RETURN 'não entendi o número "' || coalesce(p_telefone, '') || '". Manda assim: envia 92 99999-9999 o ' || p_codigo;
  END IF;

  v_chave := nai_chave(v_digitos);
  IF v_chave IS NULL THEN
    RETURN 'não consegui ler o número "' || coalesce(p_telefone, '') || '".';
  END IF;

  SELECT texto_pronto INTO v_card FROM nai_card_do_imovel(p_codigo);
  IF v_card IS NULL THEN
    RETURN 'não achei imóvel com o código ' || p_codigo || '. Confere pra mim?';
  END IF;

  SELECT coalesce(e_parceiro, false) INTO v_parceiro FROM imoveis WHERE codigo = p_codigo;

  -- PARCEIRO NAO SAI, e nem chega a entrar na fila. O gatilho
  -- `nai_saida_validar` barraria o card de qualquer jeito (papel_destino
  -- diferente de 'tel'), mas enfileirar para ser barrado deixaria uma linha
  -- 'bloqueado' por comando que nunca devia ter virado fila.
  IF coalesce(v_parceiro, false) THEN
    RETURN 'O ' || p_codigo || ' e imovel DE PARCEIRO -- nao mandei. A regra e sua: parceria nao sai.';
  END IF;

  -- O contato do destino. Não existindo, nasce aqui: é para ele que a saída vai,
  -- e sem contato a caixa de saída não tem para quem apontar.
  SELECT id INTO v_destino FROM nai_contato WHERE chave = v_chave;
  IF v_destino IS NULL THEN
    INSERT INTO nai_contato (chave, telefone, nome_whatsapp)
    VALUES (v_chave, v_digitos, NULL)
    RETURNING id INTO v_destino;
  END IF;

  PERFORM nai_enfileirar_texto(p_turno, NULL, v_destino, 'corretor', v_card, 'envia_comando', 1);

  IF NOT coalesce(v_parceiro, false) THEN
    FOR f IN SELECT * FROM nai_imagens_do_envio(p_codigo) LOOP
      -- A colagem de 4 fotos é só dos grupos (Tel, 14/09): num envio de um para
      -- um vão as fotos soltas.
      CONTINUE WHEN f.e_colagem;
      v_ordem := v_ordem + 1;
      INSERT INTO nai_saida (turno_id, contato_id, papel_destino, chave_destino,
                             tipo, imagem_url, codigo, ordem, motivo)
      VALUES (p_turno, v_destino, 'corretor', v_chave, 'imagem', f.url, p_codigo,
              v_ordem, 'foto');
      v_fotos := v_fotos + 1;
    END LOOP;
  END IF;

  RETURN 'Mandei o ' || p_codigo || ' para ' || nai_fone_fmt(v_digitos)
         || ' — o card e ' || v_fotos || ' foto(s).';
END;
$fn$;

CREATE OR REPLACE FUNCTION public.nai_comando_tel(p_turno bigint, p_texto text)
 RETURNS TABLE(msg_tel text)
 LANGUAGE plpgsql
AS $function$
DECLARE
  t     nai_turno;
  s     text := regexp_replace(btrim(coalesce(p_texto, '')), '^\s*@?nay[\s,:;.!-]*', '', 'i');
  m     text[];
  v     nai_visita;
  q     timestamptz;
  v_ac  text;
  linhas text;
  v_msg text;
  v_lib int := 0;
BEGIN
  SELECT * INTO t FROM nai_turno WHERE id = p_turno;
  IF t.id IS NULL THEN
    RETURN QUERY SELECT 'comando so do Tel.'::text; RETURN;
  END IF;

  -- =====================================================================
  -- ENVIA <NUMERO> O <CODIGO>  (Tel, 27/09/2026)
  --
  -- "ele pede para ela mandar um imovel para um numero e ela n manda".
  --
  -- E verdade: ele pediu NOVE VEZES em quatro dias, sempre na mesma forma --
  -- "envia 92 9450-0381 o 3050" -- e nao existia comando nenhum que casasse.
  -- A mensagem caia como conversa e ela respondia qualquer outra coisa.
  --
  -- Vem ANTES da guarda de papel porque quem manda aqui nao e so o Tel: ele
  -- pediu que valesse tambem para ele proprio, para o Pedro e para a Rayssa
  -- ("os imoveis que ele, eu ou a rayssa pedem"). Todo o RESTO dos comandos
  -- continua sendo so do Tel -- ninguem mais para o atendimento por aqui.
  --
  -- O CODIGO E O ULTIMO GRUPO DE 3 A 5 DIGITOS. O telefone vem antes e tem 10
  -- ou 11 digitos, entao ler de tras para frente e o que faz "envia 92
  -- 99462-9241 codigo 150" funcionar sem confundir as duas coisas.
  -- =====================================================================
  m := regexp_match(s, '^(?:envia|envie|manda|mande)\s+(.+?)\s*(?:o|os|c[oó]digo)?\s*([0-9]{3,5})\s*$', 'i');
  IF m IS NOT NULL
     AND (t.papel = 'tel'
          OR EXISTS (SELECT 1 FROM nay_e_da_equipe((SELECT telefone FROM nai_contato WHERE id = t.contato_id)))
          OR (SELECT c.chave FROM nai_contato c WHERE c.id = t.contato_id)
              = ANY (nai_chaves_de('so_estes_numeros')))
  THEN
    v_msg := nai_enviar_imovel_para(p_turno, m[2]::int, m[1]);
    PERFORM nai_enfileirar_texto(p_turno, NULL, t.contato_id, 'turno', v_msg, 'comando_envia', 1);
    RETURN QUERY SELECT v_msg; RETURN;
  END IF;

  IF t.papel <> 'tel' THEN
    RETURN QUERY SELECT 'comando so do Tel.'::text; RETURN;
  END IF;

  -- AGENDA DE VISITAS (Tel, 15/09): a agenda de hoje em diante, separada por
  -- dia. O comando VISITAS logo abaixo continua igual ao que sempre foi.
  -- PARAR / VOLTAR ATENDIMENTO (Tel, 15/09). A chave geral sempre existiu e so
  -- se mexia por UPDATE no banco; agora ele desliga do proprio WhatsApp.
  -- Parada, ela NAO envia nada para ninguem -- as mensagens continuam chegando
  -- e ficam gravadas, e os comandos dele continuam funcionando.
  IF nai_e_comando_parada(s) THEN
    IF nai_parada_e_para(s) THEN
      UPDATE nai_config SET valor = 'sim' WHERE chave = 'pausada';
      v_msg := 'Parei o atendimento. Não respondo mais ninguém até você mandar VOLTAR ATENDIMENTO.'
               || E'\nAs mensagens continuam chegando e ficando guardadas, e seus comandos continuam valendo.';
    ELSE
      UPDATE nai_config SET valor = 'nao' WHERE chave = 'pausada';
      v_msg := 'Voltei a atender.';
    END IF;
    PERFORM nai_enfileirar_texto(p_turno, NULL, t.contato_id, 'turno', v_msg, 'comando_tel', 1);
    RETURN QUERY SELECT v_msg; RETURN;
  END IF;

  IF nai_e_comando_agenda(s) THEN
    v_msg := nai_agenda_por_dia();
    PERFORM nai_enfileirar_texto(p_turno, NULL, t.contato_id, 'turno', v_msg, 'comando_tel', 1);
    RETURN QUERY SELECT v_msg; RETURN;
  END IF;

  IF s ~* '^visitas\s*$' THEN
    SELECT string_agg('#' || x.id || ' · ' || nai_ref_imovel(x.codigo) || ' · ' || nai_hora_exata(x.quando) || ' · ' || x.estado ||
                      coalesce(' (esperando ' || x.aguardando || ')', ''), E'\n' ORDER BY x.quando)
      INTO linhas FROM nai_visita x WHERE nai_visita_aberta(x.estado);
    v_msg := coalesce(E'Visitas em andamento:\n' || linhas, 'Nenhuma visita em andamento.');
    PERFORM nai_enfileirar_texto(p_turno, NULL, t.contato_id, 'turno', v_msg, 'comando_tel', 1);
    RETURN QUERY SELECT v_msg; RETURN;
  END IF;

  -- CORRETOR <telefone> / NAO CORRETOR <telefone> (Tel, 18/09/2026): a
  -- resposta dele ao "e corretor?" que a NAI manda quando alguem de fora dos
  -- grupos pergunta de imovel. A logica mora em nai_decidir_corretor (36c).
  m := regexp_match(s, '^(n[aã]o\s+)?corretor\s+(.+)$', 'i');
  IF m IS NOT NULL THEN
    v_msg := nai_decidir_corretor(m[2], m[1] IS NULL);
    RETURN QUERY SELECT v_msg; RETURN;
  END IF;

  -- ASSUMIR <telefone> / DEVOLVER <telefone>: o Tel pega ou devolve a conversa.
  m := regexp_match(s, '^(assumir|devolver)\s+(.+)$', 'i');
  IF m IS NOT NULL THEN
    IF nai_chave(m[2]) IS NULL THEN
      v_msg := 'Não entendi o telefone. Use: ASSUMIR 92 99999-8888  ou  DEVOLVER 92 99999-8888';
    ELSIF lower(m[1]) = 'assumir' THEN
      PERFORM nai_contato_do_cadastro(m[2], NULL);
      UPDATE nai_contato SET humano_assumiu_em = coalesce(humano_assumiu_em, now()), humano_motivo = 'comando ASSUMIR do Tel'
       WHERE chave = nai_chave(m[2]);
      v_msg := 'Feito: a conversa com ' || nai_fone_fmt(m[2]) || ' é sua. A NAI não manda mais nada para essa pessoa até você mandar DEVOLVER ' || btrim(m[2]) || '.';
    ELSE
      -- DEVOLVER COM RESPOSTA (Tel, 16/09). Ele escreveu "Devolver (92)
      -- 98807-8540 é apartamento" logo depois de a Nay ter subido a pergunta da
      -- Martinha -- e "é apartamento" era a RESPOSTA para ela, nao um comentario
      -- para a Nay. Nas palavras dele: "quando ele fala devolver, é para a Nay
      -- mandar para a pessoa".
      --
      -- O telefone sai da frente do texto, e o que sobra e a resposta. Sem
      -- sobra nenhuma, o comando continua sendo so a devolucao da conversa, do
      -- jeito que sempre foi.
      DECLARE
        v_resp text;
        v_dest bigint;
      BEGIN
        v_resp := btrim(regexp_replace(m[2], '^[\s(]*\+?[\d()\s.-]{8,}', ''));
        UPDATE nai_contato SET humano_assumiu_em = NULL, humano_motivo = NULL
         WHERE chave = nai_chave(m[2])
        RETURNING id INTO v_dest;

        IF nullif(v_resp, '') IS NOT NULL AND v_dest IS NOT NULL THEN
          PERFORM nai_enfileirar_texto(p_turno, NULL, v_dest, 'entrega',
            nai_frase_maiuscula(v_resp), 'resposta_do_tel', 2);
          v_msg := 'Entreguei para ' || nai_fone_fmt(m[2]) || ': "' || v_resp
                   || '". E a NAI volta a atender essa conversa.';
        ELSE
          v_msg := 'Feito: a NAI volta a atender ' || nai_fone_fmt(m[2]) || '.';
        END IF;
      END;
    END IF;
    PERFORM nai_enfileirar_texto(p_turno, NULL, t.contato_id, 'turno', v_msg, 'comando_tel', 1);
    RETURN QUERY SELECT v_msg; RETURN;
  END IF;

  m := regexp_match(s, '^acesso\s+(\d{3,5})\s+(.+)$', 'i');
  IF m IS NOT NULL THEN
    v_ac := nai_acesso_normalizar(m[2]);
    IF v_ac IS NULL OR NOT EXISTS (SELECT 1 FROM imoveis WHERE codigo = m[1]::int) THEN
      v_msg := 'Não entendi. Use: ACESSO 5611 chave com a gente / buscar a chave na portaria / fechadura / proprietário abre';
    ELSE
      INSERT INTO nai_acesso_imovel (codigo, acesso, detalhe, fonte) VALUES (m[1]::int, v_ac, m[2], 'tel')
      ON CONFLICT (codigo) DO UPDATE SET acesso = EXCLUDED.acesso, detalhe = EXCLUDED.detalhe, fonte = 'tel', atualizado_em = now();
      v_msg := 'Guardei: no ' || nai_ref_imovel(m[1]::int) || ' o acesso é ' || v_ac || '.';
    END IF;
    PERFORM nai_enfileirar_texto(p_turno, NULL, t.contato_id, 'turno', v_msg, 'comando_tel', 1);
    RETURN QUERY SELECT v_msg; RETURN;
  END IF;

  -- IMOVEL ALUGADO / VENDIDO (Tel, 22/09/2026): "o Tel vai te passar quando um
  -- imovel for alugado, tu torna ele indisponivel, prepara o sistema para
  -- receber isso, do whatsapp dele". Aceita varios codigos na mesma mensagem
  -- ("ALUGADO 5727 e 5733") e a volta atras ("DISPONIVEL 5727").
  m := regexp_match(s, '^(alugad[oa]|alugou|aluguei|vendid[oa]|vendeu|vendi|indisponivel|indispon[ií]vel|dispon[ií]vel|disponibiliza|liberar?|voltou)\s+(.*)$', 'i');
  IF m IS NOT NULL THEN
    v_msg := nai_marcar_imovel(m[1], m[2], 'Tel pelo WhatsApp');
    PERFORM nai_enfileirar_texto(p_turno, NULL, t.contato_id, 'turno', v_msg, 'comando_tel', 1);
    RETURN QUERY SELECT v_msg; RETURN;
  END IF;

  m := regexp_match(s, '^visita\s+#?(\d+)\s+(.*)$', 'i');
  IF m IS NULL THEN RETURN QUERY SELECT NULL::text; RETURN; END IF;
  SELECT * INTO v FROM nai_visita WHERE id = m[1]::bigint FOR UPDATE;
  IF v.id IS NULL OR NOT nai_visita_aberta(v.estado) THEN
    v_msg := 'Não achei a visita #' || m[1] || ' em andamento. Mande VISITAS para ver a lista.';
    PERFORM nai_enfileirar_texto(p_turno, NULL, t.contato_id, 'turno', v_msg, 'comando_tel', 1);
    RETURN QUERY SELECT v_msg; RETURN;
  END IF;

  IF unaccent(m[2]) ~* ('^(fernando|motoboy|' || lower(unaccent(nai_acompanhante())) || ')\s+(ok|confirm)') THEN
    UPDATE nai_visita SET moto_ok_em = now() WHERE id = v.id RETURNING * INTO v;
    IF v.prop_ok_em IS NOT NULL THEN PERFORM nai_confirmar_visita(v.id, p_turno); END IF;
    v_msg := 'Feito: ' || nai_acompanhante() || ' confirmado na visita #' || v.id || CASE WHEN v.prop_ok_em IS NOT NULL THEN '. Confirmei ao corretor.' ELSE '. Ainda falta o proprietário.' END;
  ELSIF m[2] ~* '^(ok|confirm|pode)' THEN
    UPDATE nai_visita SET prop_ok_em = now(), quando = coalesce(quando_sugerido, quando) WHERE id = v.id;
    PERFORM nai_evento(v.id, 'tel_confirmou_proprietario', NULL);
    IF (SELECT acesso FROM nai_visita WHERE id = v.id) IS NULL AND NOT EXISTS (SELECT 1 FROM nai_acesso_imovel WHERE codigo = v.codigo) THEN
      UPDATE nai_visita SET acesso_detalhe = 'combinado pelo Tel' WHERE id = v.id;
    END IF;
    -- Sem conversa com o proprietario (foi o Tel): segue direto para o Fernando.
    IF v.proprietario_id IS NULL OR v.estado = 'com_tel' THEN
      UPDATE nai_visita SET acesso = coalesce(acesso, (SELECT acesso FROM nai_acesso_imovel WHERE codigo = v.codigo)) WHERE id = v.id;
      UPDATE nai_visita SET estado = 'aguardando_acesso' WHERE id = v.id AND acesso IS NULL;
      IF (SELECT acesso FROM nai_visita WHERE id = v.id) IS NULL THEN
        v_msg := 'Anotado o OK do proprietário na visita #' || v.id || '. Como é o acesso? Responda: ACESSO ' || v.codigo || ' chave com a gente / buscar a chave / fechadura / proprietário abre — e depois VISITA ' || v.id || ' OK de novo.';
        PERFORM nai_enfileirar_texto(p_turno, NULL, t.contato_id, 'turno', v_msg, 'comando_tel', 1);
        RETURN QUERY SELECT v_msg; RETURN;
      END IF;
      UPDATE nai_visita SET senha = coalesce(senha, 'com o Tel') WHERE id = v.id AND acesso = 'fechadura';
      UPDATE nai_visita SET acesso_detalhe = coalesce(acesso_detalhe, 'combinado pelo Tel') WHERE id = v.id AND acesso = 'buscar_chave';
    END IF;
    PERFORM nai_prosseguir_acesso(v.id, p_turno, false);
    v_msg := 'Feito: visita #' || v.id || ' com o OK do proprietário. Estou chamando o ' || nai_acompanhante() || '.';
  ELSIF m[2] ~* '^cancel' THEN
    UPDATE nai_visita SET estado = 'cancelada', aguardando = NULL, motivo = 'Tel: ' || m[2], senha = NULL,
                          encerrada_em = now(), atualizado_em = now() WHERE id = v.id;
    PERFORM nai_evento(v.id, 'cancelada_pelo_tel', m[2]);
    PERFORM nai_enfileirar_texto(p_turno, v.id, v.corretor_id, 'corretor',
      coalesce(nai_vocativo((SELECT coalesce(nome_completo, nome_whatsapp) FROM nai_contato WHERE id = v.corretor_id)) || ', ', '') ||
      'a visita de ' || nai_quando_humano(v.quando) || ' no ' || nai_ref_imovel(v.codigo) ||
      ' não vai dar certo. Quer que eu veja outro horário?', 'cancelada_pelo_tel', 400);
    IF v.motoboy_id IS NOT NULL AND (v.moto_ok_em IS NOT NULL OR v.ult_msg_moto_em IS NOT NULL) THEN
      PERFORM nai_enfileirar_texto(p_turno, v.id, v.motoboy_id, 'motoboy',
        '' || nai_acompanhante() || ', a visita do ' || nai_ref_imovel(v.codigo) || ' de ' || nai_hora_exata(v.quando) || ' foi cancelada.', 'cancelada', 600);
    END IF;
    v_msg := 'Feito: visita #' || v.id || ' cancelada e o corretor avisado.';
  -- VISITA <id> REMARCA <quando> (Tel, 15/09): "remarcar uma visita manualmente
  -- pelo whatsapp dele". NAO e o HORARIO logo abaixo: aquele PERGUNTA ao
  -- corretor se o horario novo serve (e a negociacao que veio do proprietario);
  -- este e decisao do Tel -- muda a hora e comunica os tres.
  ELSIF m[2] ~* '^remarc' THEN
    q := nai_ler_hora_tel(m[2], v.quando);
    IF q IS NULL OR q <= now() THEN
      v_msg := 'Não entendi o horário. Use: VISITA ' || v.id || ' REMARCA 16h  ou  VISITA ' || v.id || ' REMARCA 18/09 16h';
    ELSE
      -- Os carimbos de aviso voltam a zero: senao a agenda entenderia que ja
      -- avisou desta visita e ninguem seria lembrado no horario novo.
      UPDATE nai_visita
         SET quando = q, quando_sugerido = NULL, atualizado_em = now(),
             aviso_motoboy_em = NULL, lembrete_1h_em = NULL, lembrete_periodo_em = NULL,
             aviso_tel_em = NULL, pos_visita_em = NULL
       WHERE id = v.id;
      PERFORM nai_evento(v.id, 'tel_remarcou', nai_hora_exata(q));
      PERFORM nai_enfileirar_texto(p_turno, v.id, v.corretor_id, 'corretor',
        coalesce(nai_vocativo((SELECT coalesce(nome_completo, nome_whatsapp) FROM nai_contato WHERE id = v.corretor_id)) || ', ', '') ||
        'a visita ao ' || nai_ref_imovel(v.codigo) || ' foi remarcada para ' || nai_quando_humano(q) || '.',
        'tel_remarcou', 400);
      IF v.proprietario_id IS NOT NULL THEN
        PERFORM nai_enfileirar_texto(p_turno, v.id, v.proprietario_id, 'proprietario',
          -- `nai_ref_imovel_prop` ja devolve "no seu imovel do X": sem isto sai
          -- "A visita ao no seu imovel do X".
          'A visita ' || nai_ref_imovel_prop(v.codigo) || ' foi remarcada para ' || nai_quando_humano(q) || '.',
          'tel_remarcou', 420);
      END IF;
      IF v.motoboy_id IS NOT NULL AND (v.moto_ok_em IS NOT NULL OR v.ult_msg_moto_em IS NOT NULL) THEN
        PERFORM nai_enfileirar_texto(p_turno, v.id, v.motoboy_id, 'motoboy',
          '' || nai_acompanhante() || ', a visita do ' || nai_ref_imovel(v.codigo) || ' passou para ' || nai_hora_exata(q) || '.',
          'tel_remarcou', 440);
      END IF;
      v_msg := 'Feito: visita #' || v.id || ' remarcada para ' || nai_hora_exata(q) || '. Avisei o corretor'
               || CASE WHEN v.proprietario_id IS NOT NULL THEN ', o proprietário' ELSE '' END
               || CASE WHEN v.motoboy_id IS NOT NULL AND (v.moto_ok_em IS NOT NULL OR v.ult_msg_moto_em IS NOT NULL)
                       THEN ' e o ' || nai_acompanhante() || '' ELSE '' END || '.';
    END IF;
  ELSIF m[2] ~* '^hor' THEN
    q := nai_ler_hora_tel(m[2], v.quando);
    IF q IS NULL OR q <= now() THEN
      v_msg := 'Não entendi o horário. Use: VISITA ' || v.id || ' HORARIO 16h  ou  VISITA ' || v.id || ' HORARIO 13/09 16h';
    ELSE
      UPDATE nai_visita SET quando_sugerido = q, estado = 'negociando', aguardando = 'corretor', atualizado_em = now() WHERE id = v.id;
      PERFORM nai_evento(v.id, 'tel_sugeriu_horario', nai_hora_exata(q));
      -- Mesmo card p_repassa do caminho do proprietario: com o tratamento
      -- ("Sr. Pedro, o proprietario nao consegue..."). No teste ao vivo de 13/09
      -- saia sem tratamento e com letra minuscula quando quem mandava era o Tel.
      PERFORM nai_enfileirar_texto(p_turno, v.id, v.corretor_id, 'corretor',
        coalesce(nai_vocativo((SELECT coalesce(nome_completo, nome_whatsapp) FROM nai_contato WHERE id = v.corretor_id)) || ', ', '') ||
        'o proprietário não consegue ' || nai_quando_humano(v.quando) || ', mas sugeriu ' || nai_quando_humano(q) || '. Funciona pro seu cliente?',
        'tel_sugeriu', 400);
      v_msg := 'Feito: perguntei ao corretor se ' || nai_hora_exata(q) || ' serve.';
    END IF;
  ELSIF m[2] ~* '^avis' THEN
    q := nai_ler_hora_tel(m[2], now());
    IF q IS NULL OR q <= now() THEN
      v_msg := 'Não entendi a hora. Use: VISITA ' || v.id || ' AVISA 10h';
    ELSE
      UPDATE nai_visita SET proximo_aviso_prop_em = q WHERE id = v.id;
      -- Card "Acionar o Tel" (2h antes): a resposta dele devolve a visita ao proprietario.
      UPDATE nai_visita SET estado = 'aguardando_proprietario', aguardando = 'proprietario', atualizado_em = now()
       WHERE id = v.id AND estado = 'com_tel' AND proprietario_id IS NOT NULL AND prop_ok_em IS NULL;
      v_msg := 'Combinado: mando o próximo aviso ao proprietário ' || nai_hora_exata(q) || '. Se ele não responder em ' ||
               nai_cfg_int('reenvio_proprietario_min', 30) || ' minutos, te aviso para ligar.';
    END IF;
  ELSE
    v_msg := 'Comandos: VISITAS · AGENDA DE VISITAS · VISITA ' || v.id || ' OK · VISITA ' || v.id || ' CANCELA · VISITA ' || v.id ||
             ' REMARCA 16h · VISITA ' || v.id || ' HORARIO 16h · VISITA ' || v.id || ' AVISA 10h · VISITA ' || v.id ||
             ' ' || nai_acompanhante_maiusculo() || ' OK · ACESSO <código> <como> · ASSUMIR <telefone> · DEVOLVER <telefone> · PARAR ATENDIMENTO · VOLTAR ATENDIMENTO';
  END IF;
  -- Quando o fluxo para, a Nay para os chats (13/09); o comando do Tel sobre a
  -- visita e o "pode seguir": volta a atender quem estava parado por ELA.
  IF v_msg NOT LIKE 'Comandos:%' AND v_msg NOT LIKE 'Não entendi%' THEN
    v_lib := nai_liberar_chats_da_visita(v.id);
    IF v_lib > 0 THEN v_msg := v_msg || ' Voltei a atender quem estava parado por essa visita.'; END IF;
  END IF;
  PERFORM nai_enfileirar_texto(p_turno, NULL, t.contato_id, 'turno', v_msg, 'comando_tel', 1);
  RETURN QUERY SELECT v_msg;
END;
$function$;

COMMIT;

\echo '=== o comando entende a frase dele? ==='
SELECT (regexp_match('envia 92 9450-0381 o 3050',
        '^(?:envia|envie|manda|mande)\s+(.+?)\s*(?:o|os|c[oó]digo)?\s*([0-9]{3,5})\s*$', 'i')) AS partes;
SELECT (regexp_match('envia 92 99462-9241 codigo 150',
        '^(?:envia|envie|manda|mande)\s+(.+?)\s*(?:o|os|c[oó]digo)?\s*([0-9]{3,5})\s*$', 'i')) AS partes;
SELECT (regexp_match('envia 92 8417-5305 o 5035',
        '^(?:envia|envie|manda|mande)\s+(.+?)\s*(?:o|os|c[oó]digo)?\s*([0-9]{3,5})\s*$', 'i')) AS partes;

\echo '=== e NAO pega conversa comum (tem de vir vazio) ==='
SELECT (regexp_match('me manda o Arezzo Residencial por favor',
        '^(?:envia|envie|manda|mande)\s+(.+?)\s*(?:o|os|c[oó]digo)?\s*([0-9]{3,5})\s*$', 'i')) AS partes;
