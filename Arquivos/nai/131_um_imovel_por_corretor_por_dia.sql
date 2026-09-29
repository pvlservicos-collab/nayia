-- =====================================================================
-- 131 — UM IMÓVEL POR CORRETOR POR DIA (27/09/2026)
--
-- "Coloque uma regra para enviar somente uma vez um imovel ao corretor por
-- dia, agora que eu te pedi enviou 3 vezes o imovel para o corretor, isso
-- nunca pode acontecer mais."
--
-- O QUE ACONTECEU: o Tel mandou UMA mensagem às 16:31 ("92 8110-1119 envia o
-- 3210", message_id 3B3DFAB8E4C73E71EAF0) e o corretor recebeu o 3210 três
-- vezes. A mensagem entrou quatro vezes no n8n: o fluxo antigo esperou 10s
-- pela NAI, desistiu ("timeout of 10000ms exceeded") e mandou pelo caminho
-- dele -- duas vezes --, e a NAI, que tinha recebido de fato, mandou de novo
-- às 16:36. Três caminhos, cada um achando que era o único.
--
-- A TRAVA MORA NO BANCO, NUMA TABELA SÓ, porque são vários os caminhos que
-- mandam imóvel para um número: o publicador (ordem do Tel), o
-- `entregar_pendentes`, a resposta da NAI e o `nai_enviar_imovel_para`. Uma
-- trava em cada um, cada uma com sua conta, é o que deixou os três passarem.
--
--   imovel_enviado_no_dia (chave, codigo, dia)  -- chave primária
--
-- "DIA" É O DIA DE MANAUS, não 24 horas: o que ele disse foi "por dia".
--
-- A PESSOA, NÃO A LINHA: cada pessoa tem duas linhas em `nai_contato` (o
-- telefone e o @lid). A conferência olha as duas, senão o mesmo corretor
-- recebe uma vez pelo telefone e outra pelo @lid.
--
-- RESERVA ATÔMICA: `pg_advisory_xact_lock` por código e dia. Às 16:31 os dois
-- envios repetidos começaram com 16 segundos de diferença e nenhum via o
-- outro -- a linha em `envios` só era gravada no FIM de cada envio (25 fotos,
-- três minutos). Agora a reserva é gravada ANTES da primeira mensagem sair.
--
-- FICAM DE FORA: o Tel, a equipe (a mesma definição da 130) e o espelho do
-- treino (`nai_chaves_teste()`) -- a bateria manda o mesmo imóvel para o
-- espelho várias vezes por rodada, e uma parede que barra o espelho mata a
-- rodada inteira (aconteceu na rodada 12).
--
-- PASSA POR CIMA DE UMA DECISÃO ANTIGA: em 22/09 ficou "foto que ELE pediu de
-- novo sai de novo" (`nai_liberar_saida`). Com esta regra, o corretor que pede
-- o mesmo imóvel duas vezes no dia recebe a frase de que já foi, e a hora.
-- =====================================================================
\set ON_ERROR_STOP on

BEGIN;

CREATE TABLE IF NOT EXISTS imovel_enviado_no_dia (
  chave       text        NOT NULL,
  codigo      integer     NOT NULL,
  dia         date        NOT NULL,
  primeiro_em timestamptz NOT NULL DEFAULT now(),
  -- quem mandou: publicador | pendentes | nai | historico
  origem      text        NOT NULL,
  -- o turno da NAI que mandou: o card e as fotos são linhas separadas da
  -- caixa de saída, e as do MESMO turno continuam passando
  turno_id    bigint,
  PRIMARY KEY (chave, codigo, dia)
);

-- ---------------------------------------------------------------------
-- Quem fica fora da regra.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION nay_fora_da_regra_do_dia(p_chave text)
RETURNS boolean
LANGUAGE sql
STABLE
AS $fn$
  SELECT p_chave IS NULL
      OR p_chave = nai_chave(nai_cfg('tel_telefone'))
      OR p_chave = ANY (nai_chaves_teste())
      OR EXISTS (SELECT 1 FROM nai_contato c
                  WHERE c.chave = p_chave AND nai_e_da_equipe_contato(c.id))
      OR EXISTS (SELECT 1 FROM nay_e_da_equipe(p_chave));
$fn$;

-- ---------------------------------------------------------------------
-- Reserva o envio de hoje.
--
-- Devolve NULL quando PODE mandar (acabou de reservar, a reserva é do mesmo
-- turno, ou o número está fora da regra). Devolve a HORA do primeiro envio
-- quando o imóvel já foi hoje para essa pessoa -- quem chama usa a hora na
-- frase de recusa.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION nay_reservar_imovel_do_dia(p_chave text, p_codigo integer,
                                                      p_origem text,
                                                      p_turno bigint DEFAULT NULL)
RETURNS timestamptz
LANGUAGE plpgsql
AS $fn$
DECLARE
  v_dia    date := (now() AT TIME ZONE 'America/Manaus')::date;
  v_chaves text[];
  r        imovel_enviado_no_dia;
BEGIN
  IF p_codigo IS NULL OR nay_fora_da_regra_do_dia(p_chave) THEN
    RETURN NULL;
  END IF;

  -- Dois pedidos iguais chegando juntos: o segundo espera o primeiro gravar.
  PERFORM pg_advisory_xact_lock(hashtext('imovel_do_dia:' || p_codigo || ':' || v_dia));

  -- Todas as linhas da pessoa (telefone e @lid).
  SELECT coalesce(array_agg(DISTINCT c.chave), '{}') INTO v_chaves
    FROM nai_contato k
    JOIN nai_contato c ON c.id = ANY (nai_contato_irmaos(k.id))
   WHERE k.chave = p_chave;
  v_chaves := array_append(v_chaves, p_chave);

  SELECT * INTO r
    FROM imovel_enviado_no_dia e
   WHERE e.chave = ANY (v_chaves) AND e.codigo = p_codigo AND e.dia = v_dia
   ORDER BY e.primeiro_em
   LIMIT 1;

  IF r.chave IS NULL THEN
    INSERT INTO imovel_enviado_no_dia (chave, codigo, dia, origem, turno_id)
    VALUES (p_chave, p_codigo, v_dia, p_origem, p_turno);
    RETURN NULL;
  END IF;

  IF p_turno IS NOT NULL AND r.turno_id = p_turno THEN
    RETURN NULL;
  END IF;

  RETURN r.primeiro_em;
END;
$fn$;

-- ---------------------------------------------------------------------
-- Desfaz a reserva quando o envio FALHOU antes de sair (Z-API fora, imóvel
-- que não está no site). Só a do publicador e a dos pendentes: a da NAI cai
-- junto com a transação dela, sozinha.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION nay_liberar_imovel_do_dia(p_chave text, p_codigo integer)
RETURNS void
LANGUAGE sql
AS $fn$
  DELETE FROM imovel_enviado_no_dia
   WHERE chave = p_chave
     AND codigo = p_codigo
     AND dia = (now() AT TIME ZONE 'America/Manaus')::date
     AND origem IN ('publicador', 'pendentes');
$fn$;

-- ---------------------------------------------------------------------
-- O que JÁ saiu hoje entra na conta -- inclusive o 3210 das 16:31.
-- ---------------------------------------------------------------------
INSERT INTO imovel_enviado_no_dia (chave, codigo, dia, primeiro_em, origem)
SELECT nai_chave(e.telefone), e.codigo::int, (now() AT TIME ZONE 'America/Manaus')::date,
       min(e.enviado_em), 'historico'
  FROM envios e
 WHERE e.destino = 'corretor'
   AND e.codigo ~ '^[0-9]{1,6}$'
   AND (e.enviado_em AT TIME ZONE 'America/Manaus')::date = (now() AT TIME ZONE 'America/Manaus')::date
   AND nai_chave(e.telefone) IS NOT NULL
   AND NOT nay_fora_da_regra_do_dia(nai_chave(e.telefone))
 GROUP BY 1, 2
ON CONFLICT DO NOTHING;

INSERT INTO imovel_enviado_no_dia (chave, codigo, dia, primeiro_em, origem, turno_id)
SELECT s.chave_destino, s.codigo, (now() AT TIME ZONE 'America/Manaus')::date,
       min(coalesce(s.enviado_em, s.criado_em)), 'historico', max(s.turno_id)
  FROM nai_saida s
 WHERE s.codigo IS NOT NULL
   AND s.papel_destino <> 'tel'
   AND s.estado IN ('enviado', 'enviando', 'pendente')
   AND (s.criado_em AT TIME ZONE 'America/Manaus')::date = (now() AT TIME ZONE 'America/Manaus')::date
   AND NOT nay_fora_da_regra_do_dia(s.chave_destino)
 GROUP BY 1, 2
ON CONFLICT DO NOTHING;

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
BEGIN
  SELECT chave INTO v_chave FROM nai_contato WHERE id = NEW.contato_id;
  IF v_chave IS NULL THEN
    RAISE EXCEPTION 'NAI saida: contato % nao existe', NEW.contato_id;
  END IF;
  -- O destino e SEMPRE a chave do contato. Quem enfileira nao escolhe.
  NEW.chave_destino := v_chave;

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
      v_ja := nay_reservar_imovel_do_dia(v_chave, v_cod, 'nai', NEW.turno_id);
      IF v_ja IS NOT NULL THEN
        IF NEW.tipo = 'imagem' THEN
          NEW.estado   := 'bloqueado';
          NEW.bloqueio := 'imovel ja enviado hoje para este corretor ('
                          || to_char(v_ja AT TIME ZONE 'America/Manaus', 'HH24:MI') || ')';
          RETURN NEW;
        END IF;
        NEW.texto := 'O ' || v_cod || ' eu já mandei hoje às '
                     || to_char(v_ja AT TIME ZONE 'America/Manaus', 'HH24"h"MI')
                     || ', está aqui em cima na conversa.';
      END IF;
    END IF;
  END IF;

  IF NEW.tipo = 'imagem' THEN
    -- Foto so para corretor, e so a foto que o banco diz ser DAQUELE imovel.
    IF NEW.papel_destino NOT IN ('turno', 'corretor')
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

CREATE OR REPLACE FUNCTION public.nai_enviar_imovel_para(p_turno bigint, p_codigo integer, p_telefone text)
 RETURNS text
 LANGUAGE plpgsql
AS $function$
DECLARE
  v_digitos text := regexp_replace(coalesce(p_telefone, ''), '[^0-9]', '', 'g');
  v_chave   text;
  v_destino bigint;
  v_card    text;
  v_parceiro boolean;
  v_ordem   int := 1;
  v_fotos   int := 0;
  f         record;
  v_ja      timestamptz;
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

  -- UM IMOVEL POR CORRETOR POR DIA (27/09/2026). Recusa antes de enfileirar
  -- e diz a hora do primeiro envio, para quem mandou o comando saber que foi.
  v_ja := nay_reservar_imovel_do_dia(v_chave, p_codigo, 'nai', p_turno);
  IF v_ja IS NOT NULL THEN
    RETURN 'O ' || p_codigo || ' já foi hoje para ' || nai_fone_fmt(v_digitos)
           || ', às ' || to_char(v_ja AT TIME ZONE 'America/Manaus', 'HH24"h"MI')
           || '. Não mandei de novo: um imóvel por corretor por dia.';
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
$function$;

COMMIT;

\echo '=== o que ja saiu hoje e esta na conta ==='
SELECT chave, codigo, to_char(primeiro_em AT TIME ZONE 'America/Manaus', 'HH24:MI') AS primeiro, origem
  FROM imovel_enviado_no_dia ORDER BY primeiro_em;
