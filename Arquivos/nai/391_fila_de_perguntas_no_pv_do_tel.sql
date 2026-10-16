-- 391: A FILA DE PERGUNTAS NO PV DO TEL (uma por vez, numerada, cobrada a cada 10 min, a resposta vai ao cliente)
--
-- Pedro, 16/10/2026: "Preciso que melhore o sistema de perguntas da memória da Nay que ela não sabe. Preciso que seja
-- criada uma fila de perguntas e perguntadas todas no PV do Tel em ordem, ex. Pergunta 1/12, pergunta, espera a resposta
-- dele, cobra a cada 10 minutos caso ele não responda, e depois pega a resposta dele e manda ao cliente, avisa que pegou
-- a resposta, e depois continua a próxima pergunta no PV. Ele pediu para pôr nessa pergunta: qual WhatsApp, código do
-- imóvel, nome do imóvel e número do cliente, e embaixo a pergunta. Organize para ser sempre assim, e liste logo as que
-- ainda não têm resposta para serem assim e não no grupo."
--
-- COMO ERA: a Nay nova (nay-core) gravava a pergunta em core_pendencia e mandava ao Tel um aviso solto ("Tel, o corretor
-- X perguntou sobre o N ... DEVOLVER <telefone> [resposta]"), sem número, sem ordem e sem cobrança; a Nay do WhatsApp de
-- captação (nay-olx) mandava ao GRUPO. 93 perguntas da Parceria estavam abertas desde 05/10.
--
-- COMO FICA:
--   pergunta_fila             a fila (Parceria e captação), uma 'perguntada' por vez (índice único)
--   pergunta_fila_entrar      entra (a mesma pergunta da mesma pessoa sobre o mesmo imóvel não entra duas vezes)
--   pergunta_fila_tick        na agenda da NAI (todo minuto): manda a próxima ou cobra a aberta (10 min, 07h-22h)
--   pergunta_fila_resposta_valida / pergunta_fila_responder   o que o Tel escreve no PV com uma pergunta aberta é a
--                             resposta (comando dele passa antes; "bom dia" não é resposta); PULAR deixa para o fim,
--                             DESCARTAR tira. Parceria: a resposta sai ao cliente na hora (o mesmo caminho do DEVOLVER,
--                             que também fecha a core_pendencia); captação: a Nay do WhatsApp (nay-olx) entrega.
--                             Com o código do imóvel, a resposta fica em imovel_conhecimento (a memória).
--   gatilhos                  core_pendencia nova entra na fila; o aviso solto da Nay nova ao Tel fica 'bloqueado'
--   remendos (do pg_proc vivo) nai_abrir_turno (a resposta é comando do Tel), nai_comando_tel (responde),
--                             nai_agenda_tick (o relógio)
-- Chave nai_config `pergunta_fila` (sim | nao) liga e desliga tudo; com 'nao' volta o aviso solto.
BEGIN;
SET LOCAL lock_timeout = '3s';
SET LOCAL statement_timeout = '20s';

CREATE TABLE IF NOT EXISTS public.pergunta_fila (
  id            bigserial PRIMARY KEY,
  criada_em     timestamptz NOT NULL DEFAULT now(),
  ordem         bigint NOT NULL DEFAULT 0,
  linha         text NOT NULL CHECK (linha IN ('parceria', 'captacao')),
  chave         text NOT NULL,
  cliente       text,
  codigo        integer,
  imovel        text,
  pergunta      text NOT NULL,
  origem        text NOT NULL,
  origem_id     bigint,
  estado        text NOT NULL DEFAULT 'fila' CHECK (estado IN ('fila', 'perguntada', 'respondida', 'descartada')),
  perguntada_em timestamptz,
  cobrada_em    timestamptz,
  cobrancas     integer NOT NULL DEFAULT 0,
  saida_id      bigint,
  resposta      text,
  respondida_em timestamptz,
  entregue_em   timestamptz,
  entrega_erro  text,
  detalhe       text
);
COMMENT ON TABLE public.pergunta_fila IS
  '391: a fila de perguntas que a Nay não sabe, feitas ao Tel no PV uma por vez (Pergunta k/N). linha: parceria | captacao';
CREATE UNIQUE INDEX IF NOT EXISTS pergunta_fila_da_origem ON public.pergunta_fila (origem, origem_id) WHERE origem_id IS NOT NULL;
CREATE UNIQUE INDEX IF NOT EXISTS pergunta_fila_uma_perguntada ON public.pergunta_fila ((true)) WHERE estado = 'perguntada';
CREATE INDEX IF NOT EXISTS pergunta_fila_aberta ON public.pergunta_fila (ordem, id) WHERE estado IN ('fila', 'perguntada');
GRANT SELECT ON public.pergunta_fila TO nay_leitura;

INSERT INTO nai_config (chave, valor, descricao) VALUES
  ('pergunta_fila', 'sim', '391: a fila de perguntas no PV do Tel (sim | nao). Com nao, a Nay nova volta ao aviso solto.'),
  ('pergunta_fila_cobrar_min', '10', '391: de quantos em quantos minutos a pergunta sem resposta é cobrada'),
  ('pergunta_fila_hora_ini', '7', '391: a fila pergunta e cobra a partir desta hora (Manaus)'),
  ('pergunta_fila_hora_fim', '22', '391: e até esta hora (Manaus)'),
  ('_pergunta_fila_rodada', '', '391 (só leitura): quando começou a rodada da numeração "Pergunta k/N"')
ON CONFLICT (chave) DO NOTHING;

CREATE OR REPLACE FUNCTION public.pergunta_fila_ligada()
 RETURNS boolean LANGUAGE sql STABLE SET search_path TO 'public'
AS $function$ SELECT lower(coalesce(nai_cfg('pergunta_fila', 'nao'), 'nao')) = 'sim' $function$;

CREATE OR REPLACE FUNCTION public.pergunta_fila_linha(p_linha text)
 RETURNS text LANGUAGE sql IMMUTABLE
AS $function$
  SELECT CASE p_linha WHEN 'parceria' THEN 'Parceria (92 9445-3618)' WHEN 'captacao' THEN 'Captação (92 8595-6408)'
                      ELSE coalesce(p_linha, '?') END
$function$;

-- k/N: k = a de agora (as já resolvidas da rodada + 1); N = as resolvidas + as abertas. A rodada começa quando uma
-- pergunta entra com a fila vazia: 1/12, 2/12, ... e, se entra mais uma no meio, 3/13.
CREATE OR REPLACE FUNCTION public.pergunta_fila_posicao(OUT k integer, OUT n integer)
 LANGUAGE sql STABLE SET search_path TO 'public'
AS $function$
  WITH r AS (SELECT coalesce(nullif(nai_cfg('_pergunta_fila_rodada', ''), '')::timestamptz, '-infinity'::timestamptz) AS ini),
       feitas AS (SELECT count(*) AS c FROM pergunta_fila f, r
                   WHERE f.estado IN ('respondida', 'descartada') AND f.respondida_em >= r.ini),
       abertas AS (SELECT count(*) AS c FROM pergunta_fila WHERE estado IN ('fila', 'perguntada'))
  SELECT (feitas.c + 1)::int, greatest(feitas.c + abertas.c, feitas.c + 1)::int FROM feitas, abertas
$function$;

CREATE OR REPLACE FUNCTION public.pergunta_fila_texto(p_id bigint, p_cobranca boolean DEFAULT false)
 RETURNS text LANGUAGE sql STABLE SET search_path TO 'public'
AS $function$
  SELECT CASE WHEN p_cobranca THEN '⏰ *Ainda sem resposta — Pergunta ' ELSE '❓ *Pergunta ' END
         || p.k || '/' || p.n || '*' || E'\n'
         || '📱 WhatsApp: ' || pergunta_fila_linha(f.linha) || E'\n'
         || '🔑 Código: ' || coalesce('#' || f.codigo, 'não informado') || E'\n'
         || '🏠 Imóvel: ' || coalesce(nullif(btrim(f.imovel), ''), 'não informado') || E'\n'
         || '👤 Cliente: ' || coalesce(nullif(btrim(f.cliente), '') || ' — ', '') || nai_fone_fmt(f.chave) || E'\n\n'
         || btrim(f.pergunta) || E'\n'
         || coalesce('_(a Nay não achou na ficha: ' || nullif(btrim(f.detalhe), '') || ')_' || E'\n', '') || E'\n'
         || '_Responda aqui que eu mando ao cliente. PULAR deixa para depois; DESCARTAR tira da fila._'
    FROM pergunta_fila f, pergunta_fila_posicao() p
   WHERE f.id = p_id
$function$;

CREATE OR REPLACE FUNCTION public.pergunta_fila_entrar(p_linha text, p_chave text, p_cliente text, p_codigo integer,
                                                       p_imovel text, p_pergunta text, p_origem text, p_origem_id bigint,
                                                       p_detalhe text DEFAULT NULL)
 RETURNS bigint LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
DECLARE
  v_d  text := regexp_replace(coalesce(p_chave, ''), '\D', '', 'g');
  v_p  text := btrim(coalesce(p_pergunta, ''));
  v_id bigint;
BEGIN
  IF v_p = '' OR length(v_d) < 10 THEN RETURN NULL; END IF;
  -- a mesma pergunta da mesma pessoa sobre o mesmo imóvel, ainda aberta, é a mesma
  SELECT id INTO v_id FROM pergunta_fila
   WHERE estado IN ('fila', 'perguntada') AND right(chave, 8) = right(v_d, 8) AND coalesce(codigo, 0) = coalesce(p_codigo, 0)
     AND lower(unaccent(regexp_replace(pergunta, '\s+', ' ', 'g'))) = lower(unaccent(regexp_replace(v_p, '\s+', ' ', 'g')))
   LIMIT 1;
  IF v_id IS NOT NULL THEN RETURN v_id; END IF;
  -- a fila estava vazia: começa a rodada (a numeração volta a 1)
  IF NOT EXISTS (SELECT 1 FROM pergunta_fila WHERE estado IN ('fila', 'perguntada')) THEN
    UPDATE nai_config SET valor = now()::text, atualizado_em = now() WHERE chave = '_pergunta_fila_rodada';
  END IF;
  INSERT INTO pergunta_fila (linha, chave, cliente, codigo, imovel, pergunta, origem, origem_id, ordem, detalhe)
  VALUES (p_linha, v_d,
          coalesce(nullif(btrim(p_cliente), ''),
                   (SELECT CASE WHEN btrim(k.nome_completo) ~ '[[:alpha:]]{2}' THEN btrim(k.nome_completo)
                                WHEN btrim(k.nome_whatsapp) ~ '[[:alpha:]]{2}' THEN btrim(k.nome_whatsapp) END
                      FROM nai_contato k WHERE k.chave = nai_chave(v_d) LIMIT 1)),
          p_codigo,
          coalesce(nullif(btrim(p_imovel), ''),
                   (SELECT CASE WHEN coalesce(btrim(i.condominio_nome), '') = ''
                                  OR lower(unaccent(btrim(i.condominio_nome)))
                                     ~ '^(apartamento|predio|casa|cobertura|kitnet|terreno|condominio|residencial|sala|loja|galpao)([/ ].*)?$'
                                THEN nullif(concat_ws(' no ', nullif(btrim(i.tipo), ''), nullif(btrim(i.bairro), '')), '')
                                ELSE btrim(i.condominio_nome) END
                      FROM imoveis i WHERE i.codigo = p_codigo)),
          left(v_p, 1000), p_origem, p_origem_id,
          (SELECT coalesce(max(ordem), 0) + 1 FROM pergunta_fila),
          nullif(btrim(replace(coalesce(p_detalhe, ''), '_', ' ')), ''))
  ON CONFLICT (origem, origem_id) WHERE origem_id IS NOT NULL DO NOTHING
  RETURNING id INTO v_id;
  RETURN v_id;
END
$function$;

-- a próxima da fila vai ao Tel (só se nenhuma está esperando resposta, e no horário)
CREATE OR REPLACE FUNCTION public.pergunta_fila_perguntar_proxima()
 RETURNS integer LANGUAGE plpgsql SET search_path TO 'public'
AS $function$
DECLARE f pergunta_fila; v_h int; v_saida bigint;
BEGIN
  IF NOT pergunta_fila_ligada() OR EXISTS (SELECT 1 FROM pergunta_fila WHERE estado = 'perguntada') THEN RETURN 0; END IF;
  v_h := extract(hour FROM now() AT TIME ZONE 'America/Manaus')::int;
  IF v_h < nai_cfg_int('pergunta_fila_hora_ini', 7) OR v_h >= nai_cfg_int('pergunta_fila_hora_fim', 22) THEN RETURN 0; END IF;
  SELECT * INTO f FROM pergunta_fila WHERE estado = 'fila' ORDER BY ordem, id LIMIT 1 FOR UPDATE SKIP LOCKED;
  IF f.id IS NULL THEN RETURN 0; END IF;
  UPDATE pergunta_fila SET estado = 'perguntada', perguntada_em = now(), cobrada_em = NULL WHERE id = f.id;
  v_saida := nai_avisar_tel(NULL, NULL, pergunta_fila_texto(f.id, false), 'pergunta_fila');
  UPDATE pergunta_fila SET saida_id = v_saida WHERE id = f.id;
  RETURN 1;
END
$function$;

-- o relógio (agenda da NAI, todo minuto): cobra a aberta a cada N minutos ou manda a próxima. Nunca derruba a agenda.
CREATE OR REPLACE FUNCTION public.pergunta_fila_tick()
 RETURNS integer LANGUAGE plpgsql SET search_path TO 'public'
AS $function$
DECLARE f pergunta_fila; v_h int; v_saida bigint;
BEGIN
  IF NOT pergunta_fila_ligada() THEN RETURN 0; END IF;
  v_h := extract(hour FROM now() AT TIME ZONE 'America/Manaus')::int;
  IF v_h < nai_cfg_int('pergunta_fila_hora_ini', 7) OR v_h >= nai_cfg_int('pergunta_fila_hora_fim', 22) THEN RETURN 0; END IF;
  SELECT * INTO f FROM pergunta_fila WHERE estado = 'perguntada' LIMIT 1;
  IF f.id IS NOT NULL THEN
    IF coalesce(f.cobrada_em, f.perguntada_em)
       > now() - make_interval(mins => greatest(nai_cfg_int('pergunta_fila_cobrar_min', 10), 1)) THEN
      RETURN 0;
    END IF;
    v_saida := nai_avisar_tel(NULL, NULL, pergunta_fila_texto(f.id, true), 'pergunta_fila_cobranca');
    UPDATE pergunta_fila SET cobrada_em = now(), cobrancas = cobrancas + 1, saida_id = coalesce(v_saida, saida_id)
     WHERE id = f.id;
    RETURN 1;
  END IF;
  RETURN pergunta_fila_perguntar_proxima();
EXCEPTION WHEN OTHERS THEN
  RAISE WARNING 'pergunta_fila_tick: %', SQLERRM;
  RETURN 0;
END
$function$;

-- é a resposta do Tel? Só dele (a linha que recebe as perguntas), só com uma pergunta aberta, e nunca um comando
CREATE OR REPLACE FUNCTION public.pergunta_fila_resposta_valida(p_contato bigint, p_texto text, p_citado text DEFAULT NULL)
 RETURNS boolean LANGUAGE plpgsql STABLE SET search_path TO 'public'
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
  RETURN true;
END
$function$;

-- a resposta: ao cliente, a confirmação ao Tel e a próxima pergunta. NULL = não era resposta da fila.
CREATE OR REPLACE FUNCTION public.pergunta_fila_responder(p_turno bigint, p_contato bigint, p_texto text, p_citado text DEFAULT NULL)
 RETURNS text LANGUAGE plpgsql SET search_path TO 'public'
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
BEGIN
  IF NOT pergunta_fila_resposta_valida(p_contato, p_texto, p_citado) THEN RETURN NULL; END IF;
  SELECT * INTO f FROM pergunta_fila WHERE estado = 'perguntada' LIMIT 1 FOR UPDATE;
  IF f.id IS NULL THEN RETURN NULL; END IF;
  SELECT * INTO pos FROM pergunta_fila_posicao();
  s := btrim(regexp_replace(coalesce(p_texto, ''), '^\s*@?nay[\s,:;.!-]*', '', 'i'));
  a := lower(unaccent(s));
  v_quem := coalesce(nullif(btrim(f.cliente), '') || ' — ', '') || nai_fone_fmt(f.chave);

  IF a ~ '^(pular|pula|pulo|depois|deixa (para|pra) depois)[\s.!]*$' THEN
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
                           ELSE 'a sua pergunta' END || ': ' || nai_frase_maiuscula(s),
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

-- a pergunta nova da Nay nova (core_pendencia) entra na fila; o aviso solto dela ao Tel fica bloqueado
CREATE OR REPLACE FUNCTION public.pergunta_fila_da_pendencia()
 RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
BEGIN
  IF pergunta_fila_ligada() THEN
    PERFORM pergunta_fila_entrar('parceria', NEW.chave, NULL, NEW.codigo, NULL, NEW.pergunta, 'core_pendencia', NEW.id,
                                 array_to_string(array_remove(NEW.faltou, 'assunto nao reconhecido'), ', '));
  END IF;
  RETURN NEW;
EXCEPTION WHEN OTHERS THEN
  RAISE WARNING 'pergunta_fila_da_pendencia: %', SQLERRM;     -- a Nay nova nunca cai por causa da fila
  RETURN NEW;
END
$function$;
DROP TRIGGER IF EXISTS pergunta_fila_da_pendencia ON public.core_pendencia;
CREATE TRIGGER pergunta_fila_da_pendencia AFTER INSERT ON public.core_pendencia
  FOR EACH ROW EXECUTE FUNCTION pergunta_fila_da_pendencia();

CREATE OR REPLACE FUNCTION public.core_saida_pergunta_na_fila()
 RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
BEGIN
  IF NEW.papel_destino = 'tel' AND NEW.motivo = 'aviso_tel' AND NEW.estado = 'pendente'
     AND NEW.texto LIKE 'Tel, o corretor %' AND NEW.texto LIKE '%Para eu entregar a resposta a ele: DEVOLVER%'
     AND pergunta_fila_ligada() THEN
    NEW.estado := 'bloqueado';
    NEW.bloqueio := 'vai pela fila de perguntas no PV do Tel (391)';
  END IF;
  RETURN NEW;
EXCEPTION WHEN OTHERS THEN
  RAISE WARNING 'core_saida_pergunta_na_fila: %', SQLERRM;
  RETURN NEW;
END
$function$;
DROP TRIGGER IF EXISTS core_saida_zz_pergunta_na_fila ON public.core_saida;
CREATE TRIGGER core_saida_zz_pergunta_na_fila BEFORE INSERT ON public.core_saida
  FOR EACH ROW EXECUTE FUNCTION core_saida_pergunta_na_fila();

-- ── os remendos, sobre a função VIVA (pg_proc), cada âncora tem de existir uma vez só ──
DO $do$
DECLARE
  d text;
  p record;
BEGIN
  FOR p IN SELECT * FROM (VALUES
    ('nai_abrir_turno(text,text,text,text,bigint[])',
     '-- 141: SIM/NAO da aprovacao da visita',
     '-- 391: a resposta do Tel à pergunta da fila (PV dele, uma por vez)' || E'\n'
       || '                    OR pergunta_fila_resposta_valida(v_contato, v_texto, p_citado_id)' || E'\n'
       || '                    -- 141: SIM/NAO da aprovacao da visita'),
    ('nai_comando_tel(bigint,text)',
     '  -- 141: SIM <n> / NAO <n> / TELEFONE <n> <numero> -- a aprovacao da visita.',
     '  -- 391: a resposta do Tel à pergunta da fila de perguntas: vai ao cliente, ele recebe a confirmação e a próxima.' || E'\n'
       || '  v_msg := pergunta_fila_responder(p_turno, t.contato_id, s,' || E'\n'
       || '             (SELECT x.citado_id FROM mensagens x' || E'\n'
       || '               WHERE x.id = ANY (coalesce(t.msg_ids, ''{}'')) AND nullif(btrim(x.citado_id), '''') IS NOT NULL' || E'\n'
       || '               ORDER BY x.id DESC LIMIT 1));' || E'\n'
       || '  IF v_msg IS NOT NULL THEN' || E'\n'
       || '    RETURN QUERY SELECT v_msg; RETURN;' || E'\n'
       || '  END IF;' || E'\n\n'
       || '  -- 141: SIM <n> / NAO <n> / TELEFONE <n> <numero> -- a aprovacao da visita.'),
    ('nai_agenda_tick()',
     '  n := n + nay_saidas_perguntar();',
     '  n := n + nay_saidas_perguntar();' || E'\n\n'
       || '  -- 391: a fila de perguntas no PV do Tel (manda a próxima ou cobra a aberta a cada 10 min)' || E'\n'
       || '  n := n + pergunta_fila_tick();')
  ) AS x(fn, ancora, novo)
  LOOP
    d := pg_get_functiondef(p.fn::regprocedure);
    IF position('pergunta_fila' IN d) > 0 THEN
      RAISE NOTICE '% já tem a fila: não remendo de novo', p.fn;
      CONTINUE;
    END IF;
    IF (length(d) - length(replace(d, p.ancora, ''))) / length(p.ancora) <> 1 THEN
      RAISE EXCEPTION 'a âncora de % não aparece exatamente uma vez', p.fn;
    END IF;
    EXECUTE replace(d, p.ancora, p.novo);
  END LOOP;
END
$do$;

-- ── as que ainda não têm resposta ("liste logo as que ainda não têm resposta") ──
UPDATE nai_config SET valor = now()::text, atualizado_em = now() WHERE chave = '_pergunta_fila_rodada';

-- Parceria: as pendências da Nay nova abertas desde 14/10 (as de 05/10 a 13/10 ficam de fora: o corretor já seguiu)
SELECT pergunta_fila_entrar('parceria', p.chave, NULL, p.codigo, NULL, p.pergunta, 'core_pendencia', p.id,
                            array_to_string(array_remove(p.faltou, 'assunto nao reconhecido'), ', '))
  FROM core_pendencia_aberta p
 WHERE p.criado_em >= '2026-10-14 00:00-04'
 ORDER BY p.id;

-- Captação (Nay do WhatsApp): o que ela prometeu retornar hoje e foi só ao grupo
SELECT pergunta_fila_entrar('captacao', l.telefone, l.nome, coalesce(x.codigo, l.codigo), NULL, x.pergunta, 'olx_whatsapp', NULL)
  FROM (VALUES
    ('92991540843', 3883, 'Qual a localização exata da casa? (em 15/10 a equipe disse que o proprietário ia mandar a localização)'),
    ('92982508556', 5758, 'O apartamento aceita financiamento? (ele também pediu visita para sábado, 17/10, às 15h)'),
    ('92991468187', NULL, 'Qual o menor valor do aluguel? E fica tudo como nas fotos (televisão, geladeira, sofá, cama)?'),
    ('92995234069', NULL, 'O que fica por perto do apartamento (uma referência)?'),
    ('92981585907', NULL, 'Ela pediu fotos dos quartos com roupeiros dos imóveis que recebeu (9026, 9037, 5724, 5727, 5743 e 3078).')
  ) AS x(fone, codigo, pergunta)
  JOIN privado.olx_lead_whatsapp l ON right(l.telefone, 8) = right(x.fone, 8);

COMMIT;
