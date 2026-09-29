-- =====================================================================
-- 147 — A JANELA DE 20 S, A RAJADA SEM FURO, O ECO REPETIDO E A FILA QUE
--       ESPERA A RESPOSTA (28/09/2026)
--
-- Tel: "olha a conversa com o +55 92 8477-1312: ela perguntou aluguel ou
-- venda mas não esperou, mandou vários ap de vendas para a mulher que ela não
-- pediu, ela não pode fazer isso" e "muda o tempo de espera na hora de
-- identificar as mensagens, põe 20 segundos, melhor para tudo, menos os
-- testes internos é claro, e evita isso aí de duplicata".
--
-- O QUE ACONTECEU (Taysa, 11:19-11:20): sete mensagens em 44 s viraram quatro
-- turnos. No do "Pq das laranjeiras ou pq dez" ela perguntou "alugar ou
-- comprar?" e, no MESMO turno, a fila dos outros imóveis leu "Laranjeiras"
-- (o bairro) como o Residencial Laranjeiras e o Laranjeiras Premium e mandou
-- o card de venda de R$ 2 milhões com 29 fotos.
--
--   1. JANELA: 20 s para todo mundo; os testes internos (nai_chaves_teste)
--      ficam nos 15 s de antes. `nai_janela_segundos(telefone)` é a conta
--      única -- a trava da rajada e o n8n (nó Gravar na fila) leem dela.
--   2. RAJADA: a trava excluía a própria mensagem da conta, e a mais nova
--      escapava sozinha. Agora ela também espera.
--   3. ECO: a mensagem enviada é gravada uma vez por fluxo.
--   4. FILA: nome de bairro dentro da frase não vira condomínio, e com
--      locação/venda ainda sem resposta só vai o código que ele digitou.
-- =====================================================================
\set ON_ERROR_STOP on
BEGIN;
SET LOCAL lock_timeout = '5s';

UPDATE nai_config
   SET valor = '20', atualizado_em = now(),
       descricao = 'Quantos segundos esperar antes de responder, para juntar as mensagens que a pessoa ainda esta digitando. '
                || '20 desde 28/09 (Tel). Os testes internos usam janela_segundos_teste.'
 WHERE chave = 'janela_segundos';
INSERT INTO nai_config (chave, valor, descricao, atualizado_em)
VALUES ('janela_segundos_teste', '15',
        'A janela dos testes internos (nai_chaves_teste: o espelho do treino e o numero de teste). Tel, 28/09: "menos os testes internos".',
        now())
ON CONFLICT (chave) DO NOTHING;

-- A janela de cada pessoa. O @lid de um número de teste também é teste.
CREATE OR REPLACE FUNCTION nai_janela_segundos(p_telefone text)
RETURNS integer
LANGUAGE sql
STABLE
AS $fn$
  SELECT CASE WHEN nai_chave(p_telefone) = ANY (nai_chaves_teste())
                OR EXISTS (SELECT 1 FROM nai_contato c
                             JOIN nai_contato i ON i.id = ANY (nai_contato_irmaos(c.id))
                            WHERE c.chave = nai_chave(p_telefone)
                              AND i.chave = ANY (nai_chaves_teste()))
              THEN nai_cfg_int('janela_segundos_teste', 15)
              ELSE nai_cfg_int('janela_segundos', 20) END;
$fn$;

-- As palavras do nome do condomínio que aparecem na frase são todas de um
-- bairro que a frase cita? ("Pq das laranjeiras" x "Residencial Laranjeiras")
CREATE OR REPLACE FUNCTION nai_nome_so_do_bairro(p_texto text, p_codigo integer)
RETURNS boolean
LANGUAGE sql
STABLE
AS $fn$
  WITH t AS (SELECT ' ' || nay_normalizar_lugar(coalesce(p_texto, ''), true) || ' ' AS n),
  citados AS (
    SELECT DISTINCT b.nb
      FROM (SELECT DISTINCT nay_normalizar_lugar(x.bairro, true) AS nb
              FROM (SELECT DISTINCT bairro FROM imoveis WHERE coalesce(btrim(bairro), '') <> ''
                    UNION SELECT bairro FROM bairro_zona) x) b, t
     WHERE length(b.nb) >= 4 AND t.n LIKE '% ' || b.nb || ' %'),
  palavras AS (
    SELECT DISTINCT w
      FROM imoveis i, t,
           regexp_split_to_table(nay_normalizar_lugar(coalesce(i.condominio_nome, ''), true), '\s+') w
     WHERE i.codigo = p_codigo AND length(w) >= 3 AND t.n LIKE '% ' || w || ' %')
  SELECT EXISTS (SELECT 1 FROM citados) AND EXISTS (SELECT 1 FROM palavras)
     AND NOT EXISTS (SELECT 1 FROM palavras p
                      WHERE NOT EXISTS (SELECT 1 FROM citados c WHERE ' ' || c.nb || ' ' LIKE '% ' || p.w || ' %'));
$fn$;

CREATE OR REPLACE FUNCTION public.mensagens_espera_a_rajada()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
BEGIN
  -- 147: A MAIS NOVA TAMBEM ESPERA. A conta excluia a propria mensagem
  -- (`m2.id <> NEW.id`): a execucao de uma antiga segurava as antigas e deixava
  -- a MAIS NOVA sair sozinha, antes da hora. Taysa, 28/09 11:19: "Semi
  -- mobiliado" e "?!" viraram turnos proprios, cada um com a sua resposta.
  -- Agora nenhuma sai enquanto qualquer uma dele -- ela inclusive -- for mais
  -- nova que a janela; quem junta tudo e a execucao da ultima.
  -- A janela e por pessoa: 20 s para todo mundo, e a dos testes internos a parte.
  IF OLD.status = 'Recebido' AND NEW.status = 'Processando'
     AND NEW.fluxo = 'nai' AND NEW.direcao = 'recebida'
     AND EXISTS (SELECT 1 FROM mensagens m2
                  WHERE m2.telefone = NEW.telefone AND m2.fluxo = 'nai' AND m2.direcao = 'recebida'
                    AND m2.status = 'Recebido'
                    AND m2.criada_em > now() - make_interval(secs => greatest(nai_janela_segundos(NEW.telefone) - 1, 1))) THEN
    RETURN NULL;   -- ainda tem mensagem dele dentro da janela: quem junta e a execucao da ultima
  END IF;
  RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION public.mensagens_uma_vez_so()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
DECLARE
  v_primeira bigint;
BEGIN
  IF NEW.message_id IS NULL OR NEW.message_id !~ '^[0-9A-F]{16,40}$' THEN
    RETURN NEW;
  END IF;

  -- 147: O ECO DO QUE SAIU, UMA VEZ POR FLUXO. A Z-API reavisa a mesma
  -- mensagem enviada ate 10 vezes, ate 38 min depois (medido em 28/09: 2.768
  -- copias a mais em 3 dias). Cada fluxo guarda uma copia -- o painel de
  -- envios le a do fluxo 'nai' -- e as repetidas nem entram. Os dois fluxos ja
  -- param o eco logo depois de gravar, entao nada deixa de rodar.
  IF NEW.direcao = 'enviada' THEN
    PERFORM pg_advisory_xact_lock(hashtext('eco:' || coalesce(NEW.fluxo, '-') || ':' || NEW.message_id));
    IF EXISTS (SELECT 1 FROM mensagens m
                WHERE m.message_id = NEW.message_id AND m.direcao = 'enviada'
                  AND m.fluxo IS NOT DISTINCT FROM NEW.fluxo
                  AND m.criada_em > now() - interval '2 days') THEN
      RETURN NULL;
    END IF;
    RETURN NEW;
  END IF;
  IF NEW.direcao IS DISTINCT FROM 'recebida' THEN
    RETURN NEW;
  END IF;

  -- Duas cópias chegando juntas: a segunda espera a primeira gravar, e só
  -- então olha. Sem isso as duas olhariam ao mesmo tempo e passariam.
  PERFORM pg_advisory_xact_lock(hashtext('mensagem:' || NEW.message_id));

  SELECT m.id INTO v_primeira
    FROM mensagens m
   WHERE m.message_id = NEW.message_id
     AND m.direcao = 'recebida'
     AND m.criada_em > now() - interval '2 days'
   ORDER BY m.id
   LIMIT 1;

  IF v_primeira IS NULL THEN
    RETURN NEW;
  END IF;

  INSERT INTO mensagem_repetida (message_id, telefone, fluxo, origem, primeira_id)
  VALUES (NEW.message_id, NEW.telefone, coalesce(NEW.fluxo, 'antigo'), NEW.origem, v_primeira);
  RETURN NULL;
END;
$function$;

CREATE OR REPLACE FUNCTION public.nai_fila_dos_outros_imoveis(p_turno bigint, p_escreveu text)
 RETURNS integer
 LANGUAGE plpgsql
AS $function$
DECLARE
  t       nai_turno;
  k       nai_contato;
  v_cods  int[];
  v_ja    int[];
  v_rej   int[];
  v_ordem int;
  c       int;
  f       record;
  v_card  text;
  n       int := 0;
  v_teto  int := 3;
  p       jsonb;
  v_txt   text;
  v_neg   text;
BEGIN
  SELECT * INTO t FROM nai_turno WHERE id = p_turno;
  IF t.id IS NULL THEN RETURN 0; END IF;
  SELECT * INTO k FROM nai_contato WHERE id = t.contato_id;

  -- 1. a secretaria nao tem catalogo
  IF t.atendente = 'secretaria' THEN
    PERFORM nai_anotar(p_turno, 22, 'fila_de_imoveis', 'cortou',
                       'quem atende é a secretária: ela não manda imóvel do catálogo');
    RETURN 0;
  END IF;

  p := nai_pedido_do_turno(p_turno);

  -- 2. oferta nao e pedido
  IF coalesce((p->>'oferta')::boolean, false) OR coalesce((p->>'link')::boolean, false) THEN
    PERFORM nai_anotar(p_turno, 22, 'fila_de_imoveis', 'cortou',
                       'ele está oferecendo, não pedindo');
    RETURN 0;
  END IF;

  -- 3. o Jev disse que nao foi pedido
  IF NOT nai_pediu_imovel(p_turno) THEN
    PERFORM nai_anotar(p_turno, 22, 'fila_de_imoveis', 'cortou',
                       'o Jev disse que ele não pediu imóvel neste turno');
    RETURN 0;
  END IF;

  -- 144: NOME DE BAIRRO NAO E PEDIDO DE CONDOMINIO (Walter, 28/09 10:44: ele
  -- respondeu "Ponta negra" a pergunta do bairro e recebeu 3 cards do
  -- Residencial Ponta Negra II, de venda).
  IF nai_e_so_bairro(coalesce(nullif(p_escreveu, ''), t.texto)) THEN
    PERFORM nai_anotar(p_turno, 22, 'fila_de_imoveis', 'cortou', 'ele disse um bairro, nao um imovel');
    RETURN 0;
  END IF;
  v_txt  := coalesce(nullif(p_escreveu, ''), t.texto);
  v_cods := nai_imoveis_pedidos(v_txt, k.telefone);
  IF coalesce(array_length(v_cods, 1), 0) < 2 THEN RETURN 0; END IF;

  -- 147: NOME DE BAIRRO DENTRO DA FRASE NAO E CONDOMINIO (Taysa, 28/09 11:19:
  -- "Tem algo de 3 dormitorios / Pq das laranjeiras ou pq dez" virou o
  -- Residencial Laranjeiras e o Laranjeiras Premium, os dois de venda, com
  -- todas as fotos). O codigo que ele DIGITOU fica sempre.
  v_cods := ARRAY(SELECT u.c FROM unnest(v_cods) WITH ORDINALITY u(c, o)
                   WHERE u.c::text = ANY (coalesce(nay_codigos_citados(v_txt), '{}'))
                      OR NOT nai_nome_so_do_bairro(v_txt, u.c)
                   ORDER BY u.o);

  -- 147: LOCACAO OU VENDA AINDA NAO SE SABE -> A PERGUNTA VEM ANTES DO IMOVEL.
  -- Tel: "ela perguntou aluguel ou venda mas nao esperou, mandou varios ap de
  -- vendas para a mulher que ela nao pediu, ela nao pode fazer isso". So o
  -- codigo digitado passa: esse ja e o imovel, seja do negocio que for.
  v_neg := nai_negocio_do_pedido(k.id, v_txt);
  IF v_neg IS NULL THEN
    v_cods := ARRAY(SELECT u.c FROM unnest(v_cods) WITH ORDINALITY u(c, o)
                     WHERE u.c::text = ANY (coalesce(nay_codigos_citados(v_txt), '{}'))
                     ORDER BY u.o);
  END IF;
  IF coalesce(array_length(v_cods, 1), 0) < 2 THEN
    PERFORM nai_anotar(p_turno, 22, 'fila_de_imoveis', 'cortou',
      CASE WHEN v_neg IS NULL THEN 'ainda não se sabe se é locação ou venda: a pergunta vem antes do imóvel'
           ELSE 'o nome era de bairro, não de condomínio' END);
    RETURN 0;
  END IF;

  SELECT coalesce(array_agg(DISTINCT s.codigo), '{}') INTO v_ja
    FROM nai_saida s WHERE s.turno_id = p_turno AND s.codigo IS NOT NULL;
  SELECT coalesce(max(s.ordem), 0) INTO v_ordem FROM nai_saida s WHERE s.turno_id = p_turno;

  -- 4. O QUE ELE RECUSOU (era o que faltava)
  SELECT codigos_rejeitados INTO v_rej FROM nai_estado_conversa WHERE contato_id = t.contato_id;

  FOREACH c IN ARRAY v_cods LOOP
    EXIT WHEN n >= v_teto;
    CONTINUE WHEN c = ANY (v_ja);
    CONTINUE WHEN c = ANY (coalesce(v_rej, '{}'));
    -- 144: o negocio da conversa manda (locacao nao recebe imovel so de venda).
    CONTINUE WHEN v_neg = 'locacao'
                  AND NOT EXISTS (SELECT 1 FROM imoveis i WHERE i.codigo = c AND coalesce(i.valor_aluguel, 0) > 0);
    CONTINUE WHEN v_neg = 'venda'
                  AND NOT EXISTS (SELECT 1 FROM imoveis i WHERE i.codigo = c AND coalesce(i.valor_venda, 0) > 0);
    CONTINUE WHEN NOT EXISTS (SELECT 1 FROM imoveis i
                               WHERE i.codigo = c
                                 AND nay_esta_no_mercado(i.disponivel, i.bloqueado, i.publicado_no_site)
                                 AND NOT coalesce(i.e_parceiro, false));

    SELECT cc.texto_pronto INTO v_card FROM nai_card_do_imovel(c) cc;
    CONTINUE WHEN v_card IS NULL;

    v_ordem := v_ordem + 1;
    PERFORM nai_enfileirar_texto(p_turno, NULL, t.contato_id, 'turno', v_card, 'resposta', v_ordem);

    FOR f IN SELECT * FROM nai_imagens_do_envio(c) LOOP
      v_ordem := v_ordem + 1;
      INSERT INTO nai_saida (turno_id, contato_id, papel_destino, chave_destino, tipo, imagem_url, codigo, ordem, motivo)
           VALUES (p_turno, t.contato_id, 'turno', '', 'imagem', f.url, c, v_ordem,
                   CASE WHEN f.e_colagem THEN 'colagem' ELSE 'foto' END);
    END LOOP;

    n := n + 1;
  END LOOP;

  IF n > 0 THEN
    PERFORM nai_anotar(p_turno, 22, 'fila_de_imoveis', 'mudou',
                       'ele pediu ' || array_length(v_cods, 1) || ' imóveis; ' || n || ' foram para a fila');
  END IF;
  RETURN n;
END;
$function$;

COMMIT;
