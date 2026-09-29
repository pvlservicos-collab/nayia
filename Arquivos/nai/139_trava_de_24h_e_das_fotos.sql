-- =====================================================================
-- 139 — A TRAVA DE 24H É DAS FOTOS, PELO CÓDIGO (28/09/2026, 10h)
--
-- Tel: "a nay está com bug, ela não está mandando as fotos achando que já
-- mandou, essa regra de não mandar as fotos deve ser linkada ao código do
-- imóvel, ou seja ela manda as fotos baseada no código do imóvel 1 vez por
-- cliente, hoje ela tá mandando só o card de informações".
--
-- O DEFEITO (131/132): a reserva de 24h era feita pela PRIMEIRA linha do
-- imóvel na caixa de saída -- e a primeira é o card. Quando o card saía sem
-- foto (lista de vários, terminando em "qual deles?"), o imóvel ficava
-- "enviado" e as fotos pedidas depois eram barradas. Medido às 10h: 7 das 15
-- reservas da NAI tinham sido feitas por turno sem foto nenhuma; o 5717 foi
-- pedido com foto duas vezes pelo 559292466604 e saiu só o card.
--
-- AGORA: só a FOTO reserva. O card consulta (`nay_imovel_ja_foi_24h`, sem
-- gravar nada) e só vira "O X eu já mandei..." quando as fotos daquele código
-- já foram para essa pessoa nas últimas 24h -- pela NAI, pelo publicador ou
-- pelo envio da equipe, que mandam card e fotos juntos.
-- =====================================================================
\set ON_ERROR_STOP on

BEGIN;

-- Consulta: as fotos deste imóvel já foram para esta pessoa (as duas linhas
-- dela) nas últimas 24h, por outro envio? Devolve a hora, ou NULL. Não grava.
CREATE OR REPLACE FUNCTION nay_imovel_ja_foi_24h(p_chave text, p_codigo integer, p_turno bigint DEFAULT NULL)
RETURNS timestamptz
LANGUAGE plpgsql
STABLE
AS $fn$
DECLARE
  v_chaves text[];
  r        imovel_enviado_no_dia;
BEGIN
  IF p_codigo IS NULL OR nay_fora_da_regra_do_dia(p_chave) THEN
    RETURN NULL;
  END IF;
  SELECT coalesce(array_agg(DISTINCT c.chave), '{}') INTO v_chaves
    FROM nai_contato k
    JOIN nai_contato c ON c.id = ANY (nai_contato_irmaos(k.id))
   WHERE k.chave = p_chave;
  v_chaves := array_append(v_chaves, p_chave);
  SELECT * INTO r
    FROM imovel_enviado_no_dia e
   WHERE e.chave = ANY (v_chaves) AND e.codigo = p_codigo
     AND e.primeiro_em > now() - interval '24 hours'
   ORDER BY e.primeiro_em DESC
   LIMIT 1;
  IF r.chave IS NULL OR (p_turno IS NOT NULL AND r.turno_id = p_turno) THEN
    RETURN NULL;
  END IF;
  RETURN r.primeiro_em;
END;
$fn$;

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
  IF NEW.tipo = 'texto' AND NEW.texto ~ '\mSra?\M' THEN
    NEW.texto := nai_sem_senhor(NEW.texto);
  END IF;

  IF NEW.visita_id IS NOT NULL THEN
    SELECT * INTO v FROM nai_visita WHERE id = NEW.visita_id;
  END IF;
  IF NEW.turno_id IS NOT NULL THEN
    SELECT * INTO t FROM nai_turno WHERE id = NEW.turno_id;
  END IF;

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
  -- dia o 3210 chegou TRES vezes ao 92 8110-1119 a partir de um unico pedido
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
  IF NEW.papel_destino <> 'tel' AND nai_cfg('envio_simulado', 'nao') <> 'sim' THEN
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
$function$;

-- As reservas erradas de hoje: feitas por turno da NAI que não mandou foto
-- nenhuma daquele imóvel. Guardadas antes de sair.
CREATE TABLE IF NOT EXISTS imovel_enviado_sem_foto_20260928 AS
  SELECT r.*, now() AS removida_em FROM imovel_enviado_no_dia r WHERE false;
INSERT INTO imovel_enviado_sem_foto_20260928
SELECT r.*, now() FROM imovel_enviado_no_dia r
 WHERE r.origem = 'nai' AND r.turno_id IS NOT NULL
   AND NOT EXISTS (SELECT 1 FROM nai_saida x
                    WHERE x.turno_id = r.turno_id AND x.codigo = r.codigo AND x.tipo = 'imagem'
                      AND x.estado IN ('enviado', 'enviando', 'pendente', 'simulado'));
DELETE FROM imovel_enviado_no_dia r
 WHERE r.origem = 'nai' AND r.turno_id IS NOT NULL
   AND NOT EXISTS (SELECT 1 FROM nai_saida x
                    WHERE x.turno_id = r.turno_id AND x.codigo = r.codigo AND x.tipo = 'imagem'
                      AND x.estado IN ('enviado', 'enviando', 'pendente', 'simulado'));

COMMIT;

SELECT 'reservas sem foto removidas: ' || count(*) || ' -> ' || coalesce(string_agg(chave || ':' || codigo, ', '), '-')
  FROM imovel_enviado_sem_foto_20260928;
