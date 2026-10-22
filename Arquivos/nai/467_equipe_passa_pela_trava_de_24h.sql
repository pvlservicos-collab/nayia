-- 467 -- O envio de imóvel feito À MÃO pela equipe passa por cima da trava de 24 horas
--
-- Tel, 22/10/2026: "enviei 2 vezes imóvel que a corretora pediu e parou, você colocou para parar de enviar imóvel
-- também?". A Rayssa mandou o 5721 para a Ana Claudia (...6167) às 10:18; os dois pedidos do Tel pelo CRM (11:11 e
-- 11:12) voltaram "já foi para esse número hoje às 10h18, não mandei de novo". Pedro: "Equipe passa sempre".
-- - nai_turno_feito_a_mao(turno): turno de papel 'tel' que não é automático (o radar dos grupos grava "(automático)");
-- - nai_enviar_imoveis_para: o pedido da equipe sai mesmo já enviado, e o aviso diz que já tinha ido e quando;
-- - nai_saida_validar: a 'entrega' desse turno não vira "bloqueado" nem "o X eu já mandei".
-- A Nay e o radar automático continuam com as 24 h.
BEGIN;
SET LOCAL lock_timeout = '3s';

CREATE OR REPLACE FUNCTION public.nai_turno_feito_a_mao(p_turno bigint)
 RETURNS boolean
 LANGUAGE sql
 STABLE
AS $function$
  SELECT EXISTS (SELECT 1 FROM nai_turno t
                  WHERE t.id = p_turno AND t.papel = 'tel' AND coalesce(t.texto, '') !~* 'autom[aá]tico')
$function$;
COMMENT ON FUNCTION public.nai_turno_feito_a_mao(bigint) IS
  '467: turno de comando da equipe feito à mão (painel, WhatsApp), não o automático do radar: passa por cima das 24 h.';

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
      IF v_ja IS NOT NULL AND nai_turno_feito_a_mao(p_turno) THEN
        -- 467 (Tel/Pedro, 22/10: "enviei 2 vezes o imóvel que a corretora pediu e parou"): o envio feito À MÃO pela
        -- equipe (painel do CRM/site, comando no WhatsApp) passa por cima das 24 h. Fica registrado como o último envio
        -- e quem pediu fica sabendo que já tinha ido.
        UPDATE imovel_enviado_no_dia SET primeiro_em = now(), turno_id = p_turno, origem = 'nai'
         WHERE chave = v_chave AND codigo = c AND dia = (now() AT TIME ZONE 'America/Manaus')::date;
        v_linhas := v_linhas || (c || ': já tinha ido para esse número ' || nay_quando_foi(v_ja)
                                 || '; mandei de novo (envio da equipe)');
        v_vao := v_vao || c;
      ELSIF v_ja IS NOT NULL THEN
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

  -- 3. (298, Pedro 06/10) SEM linha de abertura: "não é para ter essa mensagem fixa nos cards de envio de
  --    imóvel ... só o card e fotos". Saiu o "Oi, boa tarde! Segue o imóvel que fiquei de te enviar." que ia
  --    antes de todo envio (comando ENVIA, aba Enviar imóvel do site/CRM e o "Me envia" do /imoveis).

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
$function$;;

CREATE OR REPLACE FUNCTION public.nai_saida_validar()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
DECLARE
  v_chave text;
  v record;
  t record;
  v_cod int;
  v_ja  timestamptz;
  v_ind int;
  v_fin int;   -- 190
  v_neg text;  -- 190
BEGIN
  SELECT chave INTO v_chave FROM nai_contato WHERE id = NEW.contato_id;
  IF v_chave IS NULL THEN
    RAISE EXCEPTION 'NAI saida: contato % nao existe', NEW.contato_id;
  END IF;
  -- O destino e SEMPRE a chave do contato. Quem enfileira nao escolhe.
  NEW.chave_destino := v_chave;

  -- SEM SR. E SRA. (Tel, 28/09/2026): "retire o SR e SRA das mensagens e so
  -- cita o nome do corretor, porque os nomes no BR variam muito". Aqui e a
  -- ultima parede: o tratamento vinha do nome (`nai_vocativo`), do prompt, de
  -- frase pronta de funcao e ate da dica dentro do no do n8n -- qualquer um
  -- que escape sai limpo daqui.
  IF NEW.tipo = 'texto' AND NEW.texto ~ '\mSra?\M' AND coalesce(NEW.motivo, '') <> 'olx_proprietario' THEN
    NEW.texto := nai_sem_senhor(NEW.texto);
  END IF;

  -- SEM `IF ... IS NOT NULL` EM VOLTA, e a ausencia do IF e a correcao (30/09).
  --
  -- O QUE ACONTECEU: a NAI mandou "record \"t\" is not assigned yet" a cada
  -- minuto a noite toda, e a agenda dela ficou 10 HORAS sem completar uma
  -- rodada -- a funcao e uma transacao so, entao o erro desfazia ate o carimbo
  -- `_agenda_rodou_em`. Nada de lembrete, expiracao ou aviso ao Tel saiu.
  --
  -- A CADEIA, reproduzida com BEGIN/ROLLBACK:
  --   nai_agenda_tick linha 203 chama
  --     nai_enfileirar_texto(NULL, v.id, v.motoboy_id, 'motoboy', ...)
  --                          ^^^^ turno_id NULL, que e legitimo: lembrete da
  --                               agenda nao nasce de turno nenhum
  --   -> INSERT em nai_saida -> este trigger -> `t.papel` na linha 124.
  --
  -- POR QUE ESTOURAVA: as linhas 124 e 216 leem `t.papel` dentro de
  -- `NEW.papel_destino = 'turno' AND t.papel = ...`. Quem escreveu contou com
  -- CURTO-CIRCUITO do AND -- mas o Postgres avalia a expressao inteira, entao
  -- `t.papel` e tocado mesmo com o papel sendo 'motoboy'. E record que nunca
  -- recebeu atribuicao nao tem estrutura de tupla: qualquer campo estoura.
  --
  -- POR QUE TIRAR O IF RESOLVE, e nao e sorte: `SELECT INTO` que nao acha
  -- linha ATRIBUI o record com todos os campos NULL. Medido:
  --   SELECT * INTO t FROM nai_turno WHERE id = NULL  ->  t.id = NULL
  -- Ou seja, com o SELECT sempre rodando, `t` e `v` existem sempre, os
  -- `IS NULL` daqui passam a funcionar como quem escreveu queria, e a familia
  -- inteira de erro morre -- inclusive nos ramos 'turno', 'entrega',
  -- 'corretor', 'proprietario' e 'motoboy', que tinham o mesmo defeito
  -- esperando um `visita_id` nulo para aparecer.
  SELECT * INTO v FROM nai_visita WHERE id = NEW.visita_id;
  SELECT * INTO t FROM nai_turno  WHERE id = NEW.turno_id;

  IF NEW.papel_destino = 'turno' THEN
    -- Resposta: so para quem escreveu aquele turno.
    IF t.id IS NULL OR t.contato_id <> NEW.contato_id THEN
      RAISE EXCEPTION 'NAI saida: resposta do turno % para contato % que nao e o autor', NEW.turno_id, NEW.contato_id;
    END IF;
  ELSIF NEW.papel_destino = 'entrega' THEN
    -- O TEL FALANDO PELA NAY (Tel, 16/09): o `DEVOLVER <telefone> <resposta>`
    -- precisa mandar texto para quem NAO escreveu aquele turno -- quem escreveu
    -- foi o Tel. A trava do papel 'turno' barrava, e estava certa.
    --
    -- Entao este papel tem trava propria: so sai de um turno cujo papel e
    -- 'tel'. Sem essa exigencia, qualquer funcao poderia mandar mensagem para
    -- qualquer pessoa do cadastro, que e o tipo de porta que nao se abre.
    IF t.id IS NULL OR t.papel <> 'tel' THEN
      RAISE EXCEPTION 'NAI saida: entrega so sai de um comando do Tel (turno %)', NEW.turno_id;
    END IF;
  ELSIF NEW.papel_destino = 'corretor' THEN
    IF v.id IS NULL OR v.corretor_id <> NEW.contato_id THEN
      RAISE EXCEPTION 'NAI saida: contato % nao e o corretor da visita %', NEW.contato_id, NEW.visita_id;
    END IF;
  ELSIF NEW.papel_destino = 'proprietario' THEN
    IF v.id IS NULL OR v.proprietario_id IS DISTINCT FROM NEW.contato_id THEN
      RAISE EXCEPTION 'NAI saida: contato % nao e o proprietario da visita %', NEW.contato_id, NEW.visita_id;
    END IF;
  ELSIF NEW.papel_destino = 'motoboy' THEN
    IF v.id IS NULL OR v.motoboy_id IS DISTINCT FROM NEW.contato_id OR NOT nai_e_motoboy(v_chave) THEN
      RAISE EXCEPTION 'NAI saida: contato % nao e o acompanhante da visita %', NEW.contato_id, NEW.visita_id;
    END IF;
  ELSIF NEW.papel_destino = 'equipe' THEN
    -- 141: o pedido de aprovacao da visita (a Rayssa) -- so para a equipe.
    IF NOT nai_e_da_equipe_contato(NEW.contato_id) THEN
      RAISE EXCEPTION 'NAI saida: contato % nao e da equipe', NEW.contato_id;
    END IF;
  ELSIF NEW.papel_destino = 'seguimento' THEN
    -- 141: o follow-up do dia seguinte -- so para quem recebeu imovel nos
    -- ultimos 3 dias (pelas duas linhas da pessoa).
    IF NOT EXISTS (SELECT 1 FROM imovel_enviado_no_dia e
                    WHERE e.chave IN (SELECT c.chave FROM nai_contato c
                                       WHERE c.id = ANY (nai_contato_irmaos(NEW.contato_id)))
                      AND e.primeiro_em > now() - interval '3 days') THEN
      RAISE EXCEPTION 'NAI saida: contato % nao recebeu imovel para ter seguimento', NEW.contato_id;
    END IF;
  ELSIF NEW.papel_destino = 'tel' THEN
    IF v_chave IS DISTINCT FROM nai_chave(nai_cfg('tel_telefone')) THEN
      RAISE EXCEPTION 'NAI saida: contato % nao e o Tel', NEW.contato_id;
    END IF;
  END IF;

  -- IMOVEL DE PARCERIA NAO SAI DAQUI (Tel, 16/09): "a Nay enviou um imovel de
  -- parceiro; esses imoveis de parceiros nao e pra enviar, quero eles em
  -- blacklist, so listados no site mas nunca enviados".
  --
  -- O QUE ACONTECEU: as 13:46 ela mandou 13 fotos do 3649 (Vitali Residencial,
  -- Alvorada) e ainda disse que estava disponivel. O card ja sabia da regra --
  -- `nai_card_do_imovel` devolve aviso de parceria e ZERO fotos --, mas as
  -- fotos saem por outro caminho, e ali ninguem perguntava de quem era o
  -- imovel.
  --
  -- ESTA E A ULTIMA PAREDE, no gatilho por onde toda saida passa: cobre o card,
  -- a foto, a lista e qualquer caminho que venha a existir. Sao 908 imoveis de
  -- parceria no catalogo, 566 deles no mercado -- a maior parte da base --,
  -- entao a regra precisa valer por baixo, nao so na boa vontade do modelo.
  --
  -- NAO LEVANTA EXCECAO: a saida e gravada como 'bloqueado', com o motivo. Fica
  -- o rastro no painel de envios, e o resto da resposta segue viva -- estourar
  -- aqui derrubaria a mensagem inteira, inclusive o que podia ser dito.
  --
  -- O TEL CONTINUA RECEBENDO: e por ele que a parceria anda.
  IF NEW.codigo IS NOT NULL
     AND NEW.papel_destino <> 'tel'
     AND EXISTS (SELECT 1 FROM imoveis i
                  WHERE i.codigo = NEW.codigo AND coalesce(i.e_parceiro, false)) THEN
    NEW.estado   := 'bloqueado';
    NEW.bloqueio := 'imovel de parceria: so no site, nunca enviado';
    RETURN NEW;
  END IF;

  -- VENDA NAO SAI EM CONVERSA DE LOCACAO, NEM O CONTRARIO (190, 29/09/2026).
  -- Pedro: "se o cara ta pedindo locacao ela deve continuar enviando locacao, a
  -- nao ser se ele peca claramente venda... ela nunca deve confundir as duas
  -- listas de imoveis sem um pedido claro do corretor". Naquele dia sairam 24
  -- fotos do 5748 (Jardim Adrianopolis, venda, R$ 2 mi) para quem tinha pedido
  -- aluguel de 7 mil na Ponta Negra de manha.
  --
  -- A conversa diz o negocio (`nai_negocio_da_conversa`: a palavra dele, o
  -- valor, e o que ele ja recebeu); o imovel diz a finalidade
  -- (`nai_finalidade_do_imovel`). Nao casou: card e foto ficam 'bloqueado'. O
  -- pedido claro passa: o codigo que ELE digitou ou colou nos ultimos 3 dias.
  -- So resposta a corretor -- o Tel, a entrega e o seguimento ficam de fora.
  IF NEW.papel_destino = 'turno' AND t.papel = 'corretor' THEN
    v_fin := NEW.codigo;
    IF v_fin IS NULL AND NEW.tipo = 'texto'
       AND position('📍' IN coalesce(NEW.texto, '')) > 0
       AND (SELECT count(*) FROM regexp_matches(NEW.texto, 'C[óo]digo:\s*\d{3,5}', 'gi')) = 1 THEN
      v_fin := (regexp_match(NEW.texto, 'C[óo]digo:\s*(\d{3,5})', 'i'))[1]::int;
    END IF;
    IF v_fin IS NOT NULL AND NOT (v_fin = ANY (nai_codigos_que_ele_digitou(NEW.contato_id))) THEN
      v_neg := nai_negocio_da_conversa(NEW.contato_id, t.texto);
      IF NOT nai_finalidade_serve(v_fin, v_neg) THEN
        NEW.estado   := 'bloqueado';
        NEW.bloqueio := 'finalidade: conversa de ' || v_neg || ', o ' || v_fin || ' e so de '
                        || coalesce(nai_finalidade_do_imovel(v_fin), '?');
        RETURN NEW;
      END IF;
    END IF;
  END IF;

  -- IMOVEL INDISPONIVEL NAO VAI (Tel, 28/09/2026): "qualquer status alem de
  -- disponivel ela diz que esta indisponivel e nem manda o card e fotos". A
  -- foto fica 'bloqueado'; o CARD vira a resposta de situacao
  -- (`nai_status_do_imovel`): diz que esta alugado/indisponivel e ja lista os
  -- disponiveis do mesmo condominio. Vale para qualquer caminho da NAI, venha
  -- do modelo, da busca ou de regra nova. O Tel continua recebendo tudo.
  IF NEW.papel_destino <> 'tel' THEN
    v_ind := NEW.codigo;
    IF v_ind IS NULL AND NEW.tipo = 'texto'
       AND position('📍' IN coalesce(NEW.texto, '')) > 0
       AND (SELECT count(*) FROM regexp_matches(NEW.texto, 'C[óo]digo:\s*\d{3,5}', 'gi')) = 1 THEN
      v_ind := (regexp_match(NEW.texto, 'C[óo]digo:\s*(\d{3,5})', 'i'))[1]::int;
    END IF;
    IF v_ind IS NOT NULL AND EXISTS (SELECT 1 FROM imoveis i WHERE i.codigo = v_ind)
       AND NOT nai_imovel_disponivel(v_ind) THEN
      IF NEW.tipo = 'imagem' THEN
        NEW.estado   := 'bloqueado';
        NEW.bloqueio := 'imovel indisponivel: nem card nem foto';
        RETURN NEW;
      END IF;
      NEW.texto := coalesce((SELECT s.texto_pronto FROM nai_status_do_imovel(v_ind) s), NEW.texto);
    END IF;
  END IF;

  -- UM IMOVEL POR CORRETOR POR DIA (27/09/2026): "enviar somente uma vez um
  -- imovel ao corretor por dia... isso nunca pode acontecer mais". Naquele
  -- dia o 3210 chegou TRES vezes ao [telefone …1119] a partir de um unico pedido
  -- do Tel. Ver o cabecalho da 131.
  --
  -- Aqui pega o que sai pela NAI: a foto (que traz o codigo) e o CARD (texto
  -- com o alfinete e UM "Codigo: NNNN" -- lista com varios codigos nao e card
  -- e segue). A mesma resposta continua passando inteira: o card e as fotos
  -- sao linhas separadas do mesmo turno, e a reserva e do turno.
  --
  -- Foto repetida fica 'bloqueado', com o rastro no painel de envios. Card
  -- repetido vira a frase dizendo que ja foi e a hora -- sumir calado seria
  -- pior do que avisar.
  -- 467: a entrega feita À MÃO pela equipe (painel, comando) não para nas 24 h: card e fotos saem de novo.
  IF NEW.papel_destino <> 'tel' AND nai_cfg('envio_simulado', 'nao') <> 'sim'
     AND NOT (NEW.papel_destino = 'entrega' AND nai_turno_feito_a_mao(NEW.turno_id)) THEN
    v_cod := NEW.codigo;
    IF v_cod IS NULL AND NEW.tipo = 'texto'
       AND position('📍' IN coalesce(NEW.texto, '')) > 0
       AND (SELECT count(*) FROM regexp_matches(NEW.texto, 'C[óo]digo:\s*\d{3,5}', 'gi')) = 1 THEN
      v_cod := (regexp_match(NEW.texto, 'C[óo]digo:\s*(\d{3,5})', 'i'))[1]::int;
    END IF;
    IF v_cod IS NOT NULL THEN
      -- A MARCA E DAS FOTOS (Tel, 28/09 10h): "essa regra de nao mandar as fotos
      -- deve ser linkada ao codigo do imovel, ela manda as fotos baseada no
      -- codigo do imovel 1 vez por cliente, hoje ela ta mandando so o card".
      -- Ate aqui o CARD tambem marcava: um card que saiu sem foto (lista com
      -- "qual deles?") travava as fotos do imovel por 24h -- em 28/09 o 5717 e
      -- o 5737 foram pedidos com foto e sairam so com o card. Agora so a FOTO
      -- reserva; o card so CONSULTA -- e vira "ja te mandei" apenas quando as
      -- fotos daquele codigo ja foram para essa pessoa.
      v_ja := CASE WHEN NEW.tipo = 'imagem'
                   THEN nay_reservar_imovel_do_dia(v_chave, v_cod, 'nai', NEW.turno_id)
                   ELSE nay_imovel_ja_foi_24h(v_chave, v_cod, NEW.turno_id) END;
      IF v_ja IS NOT NULL THEN
        IF NEW.tipo = 'imagem' THEN
          NEW.estado   := 'bloqueado';
          NEW.bloqueio := 'imovel ja enviado a este corretor nas ultimas 24h ('
                          || nay_quando_foi(v_ja) || ')';
          RETURN NEW;
        END IF;
        NEW.texto := 'O ' || v_cod || ' eu já mandei ' || nay_quando_foi(v_ja)
                     || ', está aqui em cima na conversa.';
      END IF;
    END IF;
  END IF;

  IF NEW.tipo = 'imagem' THEN
    -- Foto so para corretor, e so a foto que o banco diz ser DAQUELE imovel.
    -- 'entrega' (135): o card pedido pela equipe vai com as fotos. O papel so
    -- sai de turno de comando (papel 'tel'), conferido la em cima.
    IF NEW.papel_destino NOT IN ('turno', 'corretor', 'entrega')
       OR (NEW.papel_destino = 'turno' AND t.papel NOT IN ('corretor', 'tel')) THEN
      RAISE EXCEPTION 'NAI saida: foto so vai para corretor';
    END IF;
    -- A COLAGEM conta como imagem daquele imovel (Tel, 12/09): ela e nossa,
    -- montada das 4 primeiras fotos, e mora em `imovel_colagem`, nao em
    -- `imovel_fotos`. O resto da parede continua igual: url que nao esteja
    -- num dos dois lugares nao sai.
    IF NOT EXISTS (SELECT 1 FROM imovel_fotos f WHERE f.codigo = NEW.codigo AND f.url = NEW.imagem_url)
       AND NOT EXISTS (SELECT 1 FROM imovel_colagem c WHERE c.codigo = NEW.codigo AND c.url = NEW.imagem_url) THEN
      RAISE EXCEPTION 'NAI saida: a foto % nao e do imovel %', NEW.imagem_url, NEW.codigo;
    END IF;
  END IF;

  RETURN NEW;
END;
$function$;;

COMMIT;
