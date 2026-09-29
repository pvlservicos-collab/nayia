-- =====================================================================
-- 141 — A VISITA NOVA, A FICHA DE IDENTIFICAÇÃO E AS ETAPAS (28/09/2026)
--
-- Pedido do Tel (colado pelo Pedro) e as correções da manhã em cima das
-- conversas de verdade:
--
-- A VISITA
--   "Quando o corretor pedir uma visita direto ela não precisa mandar os
--   cards na hora, primeiro deve confirmar se sabe qual é o imóvel" /
--   "implementar uma confirmação em texto" / "faz uma confirmação manual com
--   a Rayssa no pv da Rayssa com todos os dados e aguarda a Rayssa falar Sim,
--   e ver se está completo antes de falar com o proprietário" / "a cada
--   confirmação de visita ele pergunta à Rayssa e avisa o Tel" / "enviar
--   confirmação com todos os ativos para o Tel".
--   E o modelo do card (Tel, 11h): "🏠 Confirmação de visita / Sua visita ao
--   imóvel foi agendada. / 🔑 Código / 📅 Data / 🕐 Horário / Por favor,
--   confirme se os dados estão corretos." -- código sempre como #0000.
--
--     pedir_visita  -> visita 'confirmando' + o modelo preenchido
--     ele: "sim"    -> 'aguardando_rayssa' + pedido à Rayssa + aviso ao Tel
--     Rayssa: SIM n -> confere (telefone do dono, antecedência) -> proprietário
--     dono confirma -> (o caminho de sempre) acompanhante -> "Visita
--                      confirmada" ao corretor + TODOS os dados ao Tel
--   Rayssa: NÃO n -> a visita vai para o Tel, e o chat do corretor para.
--   Falta o telefone do dono -> "TELEFONE n 92 9...." e ela segue.
--   Sem resposta da Rayssa: lembra 2x (30 min); perto da hora, vai ao Tel.
--
-- A FICHA DE IDENTIFICAÇÃO (Tel, 11h, conversa da Magna): "ela perguntou o
--   código para o corretor, a confirmação deve ser um modelo também, manda
--   nome do imóvel, endereço e preço de aluguel ou venda e o código no final
--   #0000". `nai_ficha_imovel`, usada pela parede 14i do conferidor.
--
-- AS ETAPAS: identificação / recebeu o imóvel / agendamento de visita,
--   calculadas dos FATOS (visita aberta, imóvel recebido, pedido de busca),
--   gravadas em `nai_etapa_contato` e entregues ao modelo na frente do
--   contexto de cada turno. "É mais internamente na IA para fazer ela
--   funcionar melhor e classificar sem ela bugar."
--
-- O FOLLOW-UP (Tel): quem recebeu imóvel ontem e não recusou claramente
--   recebe hoje, em horário comercial: "Oi Fulano, seu cliente tem
--   interesse?" + "Fulano, qualquer coisa temos muitas opções de imóveis para
--   locação e venda, o que está procurando para seus clientes?".
--
-- AS PAREDES DA MANHÃ:
--   * visita inventada (Walter, 09:28: "A visita do 5712 seria hoje, às
--     11h30?" sem ferramenta nem visita) -> silêncio;
--   * pedido de visita não leva card nem foto na hora;
--   * o que nasce de um turno/visita do ESPELHO do treino sai simulado.
-- =====================================================================
\set ON_ERROR_STOP on

BEGIN;

-- ---------------------------------------------------------------- filtros de texto
-- 📅 🕐 📌 entram na lista do que o filtro de emoji deixa passar: estão nos
-- modelos do Tel (confirmação de visita) e no status.
CREATE OR REPLACE FUNCTION public.nai_sem_emoji_resposta(p text)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
AS $function$
  SELECT btrim(translate(
           regexp_replace(regexp_replace(regexp_replace(
             translate(coalesce(p, ''), '🏢🏠📍🛏🚗💰📐🔑🔐📅🕐📌',
                       chr(1) || chr(2) || chr(3) || chr(4) || chr(5) || chr(6) || chr(7) || chr(14) || chr(15)
                       || chr(16) || chr(17) || chr(18)),
             '[🀀-🫿☀-➿️‍]', '', 'g'),
             '[ \t]{2,}', ' ', 'g'),
             '[ \t]+$', '', 'gn'),
           chr(1) || chr(2) || chr(3) || chr(4) || chr(5) || chr(6) || chr(7) || chr(14) || chr(15)
           || chr(16) || chr(17) || chr(18), '🏢🏠📍🛏🚗💰📐🔑🔐📅🕐📌'));
$function$;

-- "#5759" no começo da linha é o código da ficha, não título de markdown:
-- só sai "#" seguido de espaço.
CREATE OR REPLACE FUNCTION public.nai_limpar_markdown(p_texto text)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
AS $function$
  SELECT btrim(regexp_replace(regexp_replace(coalesce(p_texto, ''), '\*\*', '', 'g'), '^#{1,6}[ \t]+', '', 'gn'));
$function$;

-- "sim", "isso", "correto", "pode" -- sozinho.
CREATE OR REPLACE FUNCTION nai_e_sim_curto(p text)
RETURNS boolean
LANGUAGE sql
IMMUTABLE
AS $fn$
  SELECT lower(unaccent(btrim(coalesce(p, '')))) ~
    ('^(sim|s|isso|isso mesmo|isso ai|correto|certo|certinho|confirmo|confirmado|confirmada|pode|pode ser|pode sim|ok|okay|beleza|blz|'
     || 'perfeito|exato|ta certo|esta certo|tudo certo|sim,? (esta|ta) (certo|correto)|sim,? pode|sim,? isso|sim,? correto|'
     || 'sim,? confirmo|sim,? confirmado|sim,? perfeito)[\s.!,👍]*$');
$fn$;

-- ---------------------------------------------------------------- a ficha
CREATE OR REPLACE FUNCTION nai_ficha_imovel(p_codigo integer)
RETURNS text
LANGUAGE sql
STABLE
AS $fn$
  SELECT '🏠 ' || coalesce(nullif(nai_condominio_ok(i.condominio_nome), ''),
                           coalesce(i.tipo, 'Imóvel') || coalesce(' no ' || nullif(btrim(i.bairro), ''), ''))
      || E'\n📍 ' || concat_ws(', ', nullif(btrim(i.logradouro), ''), nullif(btrim(i.numero::text), ''), nullif(btrim(i.bairro), ''))
      || CASE WHEN coalesce(i.valor_aluguel, 0) > 0
              THEN E'\n💰 Aluguel: R$ ' || replace(to_char(i.valor_aluguel, 'FM999,999,990'), ',', '.')
                   || CASE WHEN coalesce(i.extras->>'incluso no aluguel', '') ~* 'condom' THEN ' (incluso a tx)' ELSE '' END
              ELSE '' END
      || CASE WHEN coalesce(i.valor_venda, 0) > 0
              THEN E'\n💰 Venda: R$ ' || replace(to_char(i.valor_venda, 'FM999,999,990'), ',', '.') ELSE '' END
      || E'\n#' || i.codigo
    FROM imoveis i WHERE i.codigo = p_codigo;
$fn$;

-- ---------------------------------------------------------------- textos da visita
CREATE OR REPLACE FUNCTION nai_dia_da_semana(p_ts timestamptz)
RETURNS text
LANGUAGE sql
STABLE
AS $fn$
  SELECT (ARRAY['segunda', 'terça', 'quarta', 'quinta', 'sexta', 'sábado', 'domingo'])
         [extract(isodow FROM p_ts AT TIME ZONE 'America/Manaus')::int];
$fn$;

-- O modelo do Tel, preenchido.
CREATE OR REPLACE FUNCTION nai_texto_confirmar_visita(p_visita bigint)
RETURNS text
LANGUAGE sql
STABLE
AS $fn$
  SELECT '🏠 *Confirmação de visita*' || E'\n\n'
      || 'Sua visita ao imóvel foi agendada.' || E'\n\n'
      || '🔑 Código do imóvel: #' || v.codigo || E'\n'
      || '📅 Data: ' || to_char(v.quando AT TIME ZONE 'America/Manaus', 'DD/MM') || ' (' || nai_dia_da_semana(v.quando) || ')' || E'\n'
      || '🕐 Horário: ' || to_char(v.quando AT TIME ZONE 'America/Manaus', 'HH24"h"MI') || E'\n\n'
      || 'Por favor, confirme se os dados estão corretos.'
    FROM nai_visita v WHERE v.id = p_visita;
$fn$;

-- Todos os dados de uma visita, para a Rayssa e para o Tel.
CREATE OR REPLACE FUNCTION nai_texto_visita_completa(p_visita bigint, p_titulo text)
RETURNS text
LANGUAGE plpgsql
STABLE
AS $fn$
DECLARE
  v     nai_visita;
  c     nai_contato;
  d     record;
  dono  record;
  m     record;
  i     imoveis;
  v_prop text;
BEGIN
  SELECT * INTO v FROM nai_visita WHERE id = p_visita;
  SELECT * INTO c FROM nai_contato WHERE id = v.corretor_id;
  SELECT * INTO i FROM imoveis WHERE codigo = v.codigo;
  SELECT * INTO d FROM nai_dados_corretor(c.id);
  SELECT * INTO dono FROM nai_proprietario_do_imovel(v.codigo);
  SELECT * INTO m FROM nai_motoboy();
  v_prop := CASE WHEN v.prop_telefone_manual IS NOT NULL
                 THEN coalesce(dono.nome, 'proprietário') || ' ' || nai_fone_fmt(v.prop_telefone_manual)
                 WHEN dono.motivo IS NULL THEN coalesce(dono.nome, '') || ' ' || nai_fone_fmt(dono.telefone)
                 ELSE '⚠ ' || CASE dono.motivo WHEN 'sem_telefone' THEN 'sem telefone no cadastro'
                                                WHEN 'tratar_com_outra_pessoa' THEN 'o cadastro diz: ' || coalesce(dono.nome, '')
                                                WHEN 'dois_donos' THEN 'dois proprietários no cadastro'
                                                ELSE 'sem proprietário cadastrado' END END;
  RETURN p_titulo || ' #' || v.id || ':' || E'\n\n'
      || coalesce(nai_ficha_imovel(v.codigo), '#' || v.codigo) || E'\n'
      || '📅 ' || to_char(v.quando AT TIME ZONE 'America/Manaus', 'DD/MM') || ' (' || nai_dia_da_semana(v.quando) || ') '
      || '🕐 ' || to_char(v.quando AT TIME ZONE 'America/Manaus', 'HH24"h"MI') || E'\n'
      || 'Corretor: ' || coalesce(d.nome_completo, c.nome_completo, c.nome_whatsapp, '') || ' ' || nai_fone_fmt(c.telefone)
      || coalesce(' · CRECI ' || d.creci, '') || E'\n'
      || 'Proprietário: ' || btrim(v_prop) || E'\n'
      || 'Acesso: ' || coalesce(CASE v.acesso WHEN 'chave_conosco' THEN 'chave conosco' WHEN 'buscar_chave' THEN 'buscar a chave'
                                              WHEN 'fechadura' THEN 'fechadura eletrônica' WHEN 'proprietario_acompanha' THEN 'o proprietário abre' END,
                                   'ainda não cadastrado (vou perguntar ao proprietário)')
      || CASE WHEN m.contato_id IS NOT NULL THEN E'\nAcompanhante: ' || coalesce(m.nome, '') || ' ' || nai_fone_fmt(m.telefone) ELSE '' END
      || CASE WHEN v.visitante_nome IS NOT NULL THEN E'\nVisitante: ' || v.visitante_nome || coalesce(', CPF ' || v.visitante_cpf, '') ELSE '' END
      || CASE WHEN v.aprovada_por IS NOT NULL THEN E'\nAprovada por: ' || v.aprovada_por ELSE '' END;
END;
$fn$;

-- ---------------------------------------------------------------- a aprovação (Rayssa)
CREATE OR REPLACE FUNCTION nai_aprovador_contato()
RETURNS bigint
LANGUAGE sql
AS $fn$
  SELECT CASE WHEN nai_chave(nai_cfg('aprovador_visita_telefone', '')) IS NOT NULL
              THEN nai_contato_do_cadastro(nai_cfg('aprovador_visita_telefone', ''), nai_cfg('aprovador_visita_nome', 'Rayssa')) END;
$fn$;

CREATE OR REPLACE FUNCTION nai_e_resposta_aprovacao(p text)
RETURNS boolean
LANGUAGE sql
IMMUTABLE
AS $fn$
  SELECT lower(unaccent(btrim(coalesce(p, '')))) ~
         ('^(sim|s|ok|pode|pode seguir|segue|confirmad[oa]|confirmo|aprovad[oa]|aprovo|nao|nao pode|cancela|recuso)'
          || '[\s,.:#-]*(visita)?[\s#]*\d{0,6}[\s.!]*$')
      OR lower(unaccent(btrim(coalesce(p, '')))) ~ '^telefone\s+#?\d{1,6}\s+\S';
$fn$;

-- Vale como resposta de aprovação? Da equipe; e "sim" sem número só de quem
-- aprova (a Rayssa) -- o Tel e o Pedro dizem "SIM 123", porque um "sim" solto
-- deles pode ser resposta de outra coisa.
CREATE OR REPLACE FUNCTION nai_resposta_aprovacao_valida(p_contato bigint, p_texto text)
RETURNS boolean
LANGUAGE sql
STABLE
AS $fn$
  SELECT p_contato IS NOT NULL
     AND nai_e_resposta_aprovacao(p_texto)
     AND nai_e_da_equipe_contato(p_contato)
     AND EXISTS (SELECT 1 FROM nai_visita x WHERE x.estado = 'aguardando_rayssa')
     AND (btrim(coalesce(p_texto, '')) ~ '\d'
          OR EXISTS (SELECT 1 FROM nai_contato c
                      WHERE c.id = ANY (nai_contato_irmaos(p_contato))
                        AND c.chave = nai_chave(nai_cfg('aprovador_visita_telefone', ''))));
$fn$;

CREATE OR REPLACE FUNCTION nai_visita_corretor_confirmou(p_visita bigint, p_turno bigint)
RETURNS void
LANGUAGE plpgsql
AS $fn$
DECLARE
  v      nai_visita;
  v_apr  bigint := nai_aprovador_contato();
  dono   record;
  v_pede text;
BEGIN
  SELECT * INTO v FROM nai_visita WHERE id = p_visita FOR UPDATE;
  IF v.id IS NULL OR v.estado <> 'confirmando' THEN RETURN; END IF;
  UPDATE nai_visita SET estado = 'aguardando_rayssa', aguardando = 'equipe', confirmada_corretor_em = now(),
                        rayssa_msg_em = now(), rayssa_lembretes = 0, atualizado_em = now()
   WHERE id = v.id;
  PERFORM nai_evento(v.id, 'corretor_confirmou', nai_hora_exata(v.quando));

  SELECT * INTO dono FROM nai_proprietario_do_imovel(v.codigo);
  v_pede := CASE WHEN dono.motivo IS NULL
                 THEN 'Está tudo certo? Responda SIM ' || v.id || ' para eu falar com o proprietário, ou NÃO ' || v.id || '.'
                 ELSE 'Falta o telefone do proprietário. Me manda assim: TELEFONE ' || v.id
                      || ' 92 99999-9999 -- e depois SIM ' || v.id || '. Ou NÃO ' || v.id || '.' END;
  IF v_apr IS NOT NULL THEN
    PERFORM nai_enfileirar_texto(p_turno, v.id, v_apr, 'equipe',
      nai_texto_visita_completa(v.id, nai_cfg('aprovador_visita_nome', 'Rayssa') || ', pedido de visita para confirmar')
      || E'\n\n' || v_pede, 'aprovar_visita', 450);
  END IF;
  PERFORM nai_avisar_tel(p_turno, v.id,
    nai_texto_visita_completa(v.id, 'Tel, novo pedido de visita (a ' || nai_cfg('aprovador_visita_nome', 'Rayssa') || ' vai confirmar)'),
    'visita_pedida');
END;
$fn$;

-- Com o SIM: estado de antes do proprietário, e o caminho de sempre.
CREATE OR REPLACE FUNCTION nai_visita_seguir_para_proprietario(p_visita bigint, p_turno bigint)
RETURNS text
LANGUAGE plpgsql
AS $fn$
BEGIN
  UPDATE nai_visita SET estado = 'coletando', aguardando = 'corretor', atualizado_em = now() WHERE id = p_visita;
  RETURN nai_pedir_ao_proprietario(p_visita, p_turno);
END;
$fn$;

CREATE OR REPLACE FUNCTION nai_aprovar_visita(p_turno bigint, p_texto text)
RETURNS text
LANGUAGE plpgsql
AS $fn$
DECLARE
  t      nai_turno;
  k      nai_contato;
  s      text := lower(unaccent(btrim(coalesce(p_texto, ''))));
  v_id   bigint;
  v_n    int;
  v_lista text;
  v      nai_visita;
  dono   record;
  m      text[];
  v_fone text;
  v_res  text;
  v_min_h int := nai_cfg_int('antecedencia_minima_horas', 2);
BEGIN
  SELECT * INTO t FROM nai_turno WHERE id = p_turno;
  SELECT * INTO k FROM nai_contato WHERE id = t.contato_id;

  -- TELEFONE <n> <numero>
  m := regexp_match(s, '^telefone\s+#?(\d{1,6})\s+(.+)$');
  IF m IS NOT NULL THEN
    SELECT * INTO v FROM nai_visita WHERE id = m[1]::bigint AND estado = 'aguardando_rayssa';
    IF v.id IS NULL THEN RETURN 'Não achei a visita #' || m[1] || ' esperando confirmação.'; END IF;
    v_fone := regexp_replace(m[2], '[^0-9]', '', 'g');
    IF length(v_fone) < 10 OR nai_chave(v_fone) IS NULL THEN
      RETURN 'Não entendi o telefone. Manda assim: TELEFONE ' || v.id || ' 92 99999-9999';
    END IF;
    UPDATE nai_visita SET prop_telefone_manual = v_fone, atualizado_em = now() WHERE id = v.id;
    PERFORM nai_evento(v.id, 'telefone_do_proprietario', v_fone);
    IF v.aprovada_em IS NULL THEN
      RETURN 'Anotei o telefone do proprietário. Responda SIM ' || v.id || ' para eu falar com ele.';
    END IF;
    s := 'sim ' || v.id;   -- ja tinha aprovado: segue
  END IF;

  m := regexp_match(s, '(\d{1,6})');
  IF m IS NOT NULL THEN
    SELECT id INTO v_id FROM nai_visita WHERE id = m[1]::bigint AND estado = 'aguardando_rayssa';
    IF v_id IS NULL THEN RETURN 'Não achei a visita #' || m[1] || ' esperando confirmação.'; END IF;
  ELSE
    SELECT count(*), min(id), string_agg('#' || id || ' (' || nai_ref_imovel(codigo) || ', ' || nai_hora_exata(quando) || ')', E'\n' ORDER BY quando)
      INTO v_n, v_id, v_lista FROM nai_visita WHERE estado = 'aguardando_rayssa';
    IF v_n = 0 THEN RETURN 'Não tem visita esperando confirmação agora.'; END IF;
    IF v_n > 1 THEN RETURN 'Tem ' || v_n || E' visitas esperando:\n' || v_lista || E'\nResponda SIM <número> ou NÃO <número>.'; END IF;
  END IF;

  SELECT * INTO v FROM nai_visita WHERE id = v_id FOR UPDATE;

  IF s ~ '^(nao|cancela|recuso)' THEN
    UPDATE nai_visita SET estado = 'com_tel', aguardando = 'tel', motivo = 'nao aprovada', atualizado_em = now() WHERE id = v.id;
    PERFORM nai_evento(v.id, 'nao_aprovada', coalesce(k.nome_whatsapp, k.telefone));
    PERFORM nai_avisar_tel(p_turno, v.id,
      nai_texto_visita_completa(v.id, 'Tel, a ' || nai_cfg('aprovador_visita_nome', 'Rayssa') || ' NÃO aprovou a visita -- ela é sua. Parei o chat do corretor'),
      'visita_nao_aprovada');
    PERFORM nai_parar_chat(v.corretor_id, 'visita #' || v.id || ': não aprovada');
    RETURN 'Certo, não falei com o proprietário. Passei a visita #' || v.id || ' para o Tel.';
  END IF;

  UPDATE nai_visita SET aprovada_em = coalesce(aprovada_em, now()),
                        aprovada_por = coalesce(aprovada_por, coalesce(k.nome_completo, k.nome_whatsapp, k.telefone)),
                        atualizado_em = now()
   WHERE id = v.id;
  PERFORM nai_evento(v.id, 'aprovada', coalesce(k.nome_whatsapp, k.telefone));

  -- CONFERE ANTES DE FALAR COM O DONO (Tel): antecedência e telefone.
  IF v.quando < now() + make_interval(hours => v_min_h) THEN
    UPDATE nai_visita SET estado = 'com_tel', aguardando = 'tel', atualizado_em = now() WHERE id = v.id;
    PERFORM nai_avisar_tel(p_turno, v.id,
      nai_texto_visita_completa(v.id, 'Tel, visita aprovada mas em cima da hora (menos de ' || v_min_h || 'h) -- ela é sua'),
      'visita_urgente_aprovada');
    PERFORM nai_parar_chat(v.corretor_id, 'visita #' || v.id || ': em cima da hora');
    RETURN 'Essa visita é para daqui a menos de ' || v_min_h || 'h: passei para o Tel.';
  END IF;
  SELECT * INTO dono FROM nai_proprietario_do_imovel(v.codigo);
  IF dono.motivo IS NOT NULL AND v.prop_telefone_manual IS NULL THEN
    RETURN 'Falta o telefone do proprietário do ' || nai_ref_imovel(v.codigo) || '. Me manda assim: TELEFONE ' || v.id
           || ' 92 99999-9999 -- que eu já falo com ele.';
  END IF;

  v_res := nai_visita_seguir_para_proprietario(v.id, p_turno);
  IF v_res = 'com_tel' THEN
    RETURN 'Não consegui falar com o proprietário do ' || nai_ref_imovel(v.codigo) || ': passei a visita #' || v.id || ' para o Tel.';
  END IF;
  RETURN 'Certo! Já pedi ao proprietário' || coalesce(' (' || nullif(btrim(coalesce(dono.nome, '')), '') || ')', '')
         || ' a visita de ' || nai_hora_exata(v.quando) || '. Quando ele responder eu sigo com o corretor e aviso o Tel.';
END;
$fn$;

-- ---------------------------------------------------------------- as etapas
CREATE OR REPLACE FUNCTION nai_etapa_calcular(p_contato bigint, OUT etapa text, OUT motivo text)
LANGUAGE plpgsql
STABLE
AS $fn$
DECLARE
  v_ids    bigint[] := nai_contato_irmaos(p_contato);
  v_chaves text[];
  v_vis    record;
  v_rec    timestamptz;
  v_cods   text;
  v_busca  timestamptz;
BEGIN
  SELECT array_agg(chave) INTO v_chaves FROM nai_contato WHERE id = ANY (v_ids);
  SELECT x.id, x.codigo, x.estado INTO v_vis FROM nai_visita x
   WHERE x.corretor_id = ANY (v_ids) AND nai_visita_aberta(x.estado) AND x.estado <> 'realizada'
   ORDER BY x.id DESC LIMIT 1;
  IF v_vis.id IS NOT NULL THEN
    etapa := 'agendamento_visita';
    motivo := 'visita #' || v_vis.id || ' do ' || v_vis.codigo || ' (' || v_vis.estado || ')';
    RETURN;
  END IF;
  SELECT max(e.primeiro_em), string_agg(DISTINCT e.codigo::text, ', ') INTO v_rec, v_cods
    FROM imovel_enviado_no_dia e WHERE e.chave = ANY (v_chaves) AND e.primeiro_em > now() - interval '7 days';
  -- as ultimas saidas pelo indice (contato_id, id DESC): o espelho do treino
  -- tem milhares de linhas, e varrer tudo a cada turno travava a abertura.
  SELECT greatest(v_rec, max(s.criado_em)) INTO v_rec
    FROM (SELECT x.criado_em, x.tipo, x.estado FROM nai_saida x
           WHERE x.contato_id = ANY (v_ids) ORDER BY x.id DESC LIMIT 300) s
   WHERE s.tipo = 'imagem' AND s.estado IN ('enviado', 'enviando', 'simulado')
     AND s.criado_em > now() - interval '7 days';
  -- pedido de busca DEPOIS do ultimo imovel recebido: no maximo os 12 turnos
  -- mais novos (a regex de busca e cara -- 694 turnos do espelho levaram 2 min).
  SELECT max(tt.criado_em) INTO v_busca
    FROM (SELECT t.criado_em, t.texto FROM nai_turno t
           WHERE t.contato_id = ANY (v_ids)
             AND t.criado_em > greatest(coalesce(v_rec, now() - interval '7 days'), now() - interval '7 days')
           ORDER BY t.id DESC LIMIT 12) tt
   WHERE coalesce((nai_pedido_de_perfil(coalesce(tt.texto, ''))->>'e_pedido')::boolean, false);
  IF v_rec IS NOT NULL AND (v_busca IS NULL OR v_busca < v_rec) THEN
    etapa := 'recebeu_imovel';
    motivo := 'recebeu ' || coalesce(v_cods, 'imóvel') || ' em ' || to_char(v_rec AT TIME ZONE 'America/Manaus', 'DD/MM HH24:MI');
    RETURN;
  END IF;
  etapa := 'identificacao';
  motivo := CASE WHEN v_busca IS NOT NULL THEN 'pediu opções' ELSE 'ainda não se sabe o que o cliente dele quer' END;
END;
$fn$;

CREATE OR REPLACE FUNCTION nai_etapa_atualizar(p_contato bigint)
RETURNS text
LANGUAGE plpgsql
AS $fn$
DECLARE
  r      record;
  v_ant  text;
BEGIN
  IF p_contato IS NULL THEN RETURN NULL; END IF;
  SELECT * INTO r FROM nai_etapa_calcular(p_contato);
  SELECT etapa INTO v_ant FROM nai_etapa_contato WHERE contato_id = p_contato;
  INSERT INTO nai_etapa_contato (contato_id, etapa, motivo)
  VALUES (p_contato, r.etapa, r.motivo)
  ON CONFLICT (contato_id) DO UPDATE
     SET etapa = EXCLUDED.etapa, motivo = EXCLUDED.motivo, atualizado_em = now(),
         desde = CASE WHEN nai_etapa_contato.etapa <> EXCLUDED.etapa THEN now() ELSE nai_etapa_contato.desde END;
  IF v_ant IS DISTINCT FROM r.etapa THEN
    INSERT INTO nai_etapa_evento (contato_id, de, para, motivo) VALUES (p_contato, v_ant, r.etapa, r.motivo);
  END IF;
  RETURN r.etapa;
EXCEPTION WHEN OTHERS THEN
  RAISE WARNING 'nai_etapa_atualizar (%): %', p_contato, SQLERRM;
  RETURN NULL;
END;
$fn$;

-- O que o modelo lê, na frente do contexto.
CREATE OR REPLACE FUNCTION nai_etapa_para_o_modelo(p_contato bigint)
RETURNS text
LANGUAGE plpgsql
STABLE
AS $fn$
DECLARE
  r     record;
  v_txt text;
  v_conf text;
BEGIN
  -- a etapa que o `nai_etapa_atualizar` acabou de gravar neste mesmo turno;
  -- so recalcula se ainda nao existe linha
  SELECT e.etapa, e.motivo INTO r FROM nai_etapa_contato e WHERE e.contato_id = p_contato;
  IF r.etapa IS NULL THEN
    SELECT * INTO r FROM nai_etapa_calcular(p_contato);
  END IF;
  v_txt := '(informação de sistema) ETAPA DESTA CONVERSA: ' ||
    CASE r.etapa
      WHEN 'identificacao' THEN
        'IDENTIFICAÇÃO (' || r.motivo || '). Descubra o que o cliente dele quer: pediu foto, informação ou '
        || 'o imóvel -> card; perguntou se está disponível -> o_que_sei_do_imovel; falou de um imóvel pelo nome e você '
        || 'não tem certeza de qual é -> confirme com a ficha (a ferramenta devolve); pediu opções ou não disse -> '
        || 'buscar_por_perfil (valor, depois bairros). Fale de visita só se ele pedir.'
      WHEN 'recebeu_imovel' THEN
        'RECEBEU O IMÓVEL (' || r.motivo || '). Responda as dúvidas desse imóvel; se ele quiser visitar, vá '
        || 'para a visita; se quiser outras opções, faça o filtro.'
      ELSE
        'AGENDAMENTO DE VISITA (' || r.motivo || '). Cuide só da visita: sem card e sem fotos agora.'
    END;
  SELECT string_agg('o ' || x.codigo || ' em ' || to_char(x.quando AT TIME ZONE 'America/Manaus', 'DD/MM "às" HH24"h"MI')
                    || ' (para confirmar: pedir_visita com codigo ' || x.codigo || ' e quando '
                    || to_char(x.quando AT TIME ZONE 'America/Manaus', 'YYYY-MM-DD HH24:MI') || ')', '; ')
    INTO v_conf
    FROM nai_visita x WHERE x.corretor_id = ANY (nai_contato_irmaos(p_contato)) AND x.estado = 'confirmando';
  IF v_conf IS NOT NULL THEN
    v_txt := v_txt || ' VISITA ESPERANDO A CONFIRMAÇÃO DELE: ' || v_conf
             || '. Se ele confirmar (sim, isso, correto), chame pedir_visita com esses dados.';
  END IF;
  RETURN v_txt;
END;
$fn$;

-- ---------------------------------------------------------------- o follow-up
-- Recusou claramente (ele ou o cliente)? "vai conversar", "vai mandar",
-- silêncio e o resto NÃO são recusa.
CREATE OR REPLACE FUNCTION nai_recusou(p text)
RETURNS boolean
LANGUAGE sql
IMMUTABLE
AS $fn$
  SELECT lower(unaccent(coalesce(p, ''))) ~
    ('(\mnao\s+(gostou|gostaram|curtiu|curtiram|quis|quiseram|quer|querem|tem\s+interesse|teve\s+interesse|se\s+interessou|serve|serviu|atende|atendeu|vai\s+querer|agradou|rolou)'
     || '|\msem\s+interesse|\mdesist\w*|\mdescart\w*|\mdispens\w*'
     || '|\mja\s+(alugou|fechou|achou|encontrou|comprou)|\mfechou\s+(com\s+)?outr|\mficou\s+com\s+outr'
     || '|\machou\s+(muito\s+)?car[oa]|\mmuito\s+car[oa]|\mfora\s+do\s+orcamento'
     || '|\mnao,?\s+obrigad|\mobrigad[oa],?\s+mas\s+nao|\mvou\s+passar\M|\mnao\s+vai\s+dar\M|\mrecus\w*)');
$fn$;

CREATE OR REPLACE FUNCTION nai_followup_rodar()
RETURNS integer
LANGUAGE plpgsql
AS $fn$
DECLARE
  v_hoje   date := (now() AT TIME ZONE 'America/Manaus')::date;
  v_hora   time := (now() AT TIME ZONE 'America/Manaus')::time;
  r        record;
  v_ct     bigint;
  v_ids    bigint[];
  v_chaves text[];
  v_nome   text;
  v_pula   text;
  v_feitos int := 0;
  v_lim    int := greatest(nai_cfg_int('followup_por_minuto', 2), 1);
BEGIN
  IF nai_cfg('followup_ligado', 'nao') <> 'sim' THEN RETURN 0; END IF;
  IF nai_cfg('pausada', 'sim') <> 'nao' OR nai_cfg('modo', 'desligado') <> 'todos' THEN RETURN 0; END IF;
  IF extract(isodow FROM now() AT TIME ZONE 'America/Manaus') = 7 THEN RETURN 0; END IF;   -- domingo
  IF v_hora < nai_cfg('followup_inicio', '09:00')::time OR v_hora > nai_cfg('followup_fim', '18:00')::time THEN RETURN 0; END IF;

  FOR r IN
    SELECT e.chave, array_agg(DISTINCT e.codigo ORDER BY e.codigo) AS codigos, min(e.primeiro_em) AS primeiro
      FROM imovel_enviado_no_dia e
     WHERE (e.primeiro_em AT TIME ZONE 'America/Manaus')::date = v_hoje - 1
       AND NOT EXISTS (SELECT 1 FROM nai_followup f WHERE f.chave = e.chave AND f.dia_recebeu = v_hoje - 1)
     GROUP BY e.chave
     ORDER BY min(e.primeiro_em)
  LOOP
    EXIT WHEN v_feitos >= v_lim;
    v_pula := NULL;
    SELECT id INTO v_ct FROM nai_contato WHERE chave = r.chave;
    IF v_ct IS NULL THEN v_ct := nai_contato_do_cadastro(r.chave, NULL); END IF;
    v_ids := nai_contato_irmaos(v_ct);
    SELECT array_agg(chave) INTO v_chaves FROM nai_contato WHERE id = ANY (v_ids);

    IF nay_fora_da_regra_do_dia(r.chave) THEN
      v_pula := 'equipe ou teste';
    ELSIF EXISTS (SELECT 1 FROM nai_followup f WHERE f.chave = ANY (v_chaves) AND f.dia_recebeu = v_hoje - 1) THEN
      v_pula := 'a outra linha dele já recebeu';
    ELSIF EXISTS (SELECT 1 FROM mensagens m WHERE nai_chave(m.telefone) = ANY (v_chaves) AND m.direcao = 'recebida'
                   AND m.criada_em > r.primeiro AND nai_recusou(m.texto)) THEN
      v_pula := 'recusou';
    ELSIF EXISTS (SELECT 1 FROM nai_visita x WHERE x.corretor_id = ANY (v_ids) AND nai_visita_aberta(x.estado)) THEN
      v_pula := 'visita em andamento';
    ELSIF nai_tel_com_a_conversa(v_ct) THEN
      v_pula := 'o Tel está com a conversa';
    ELSIF EXISTS (SELECT 1 FROM mensagens m WHERE nai_chave(m.telefone) = ANY (v_chaves) AND m.direcao = 'recebida'
                   AND (m.criada_em AT TIME ZONE 'America/Manaus')::date = v_hoje) THEN
      v_pula := 'já conversou hoje';
    ELSIF EXISTS (SELECT 1 FROM nai_corretor_pergunta q WHERE q.chave = ANY (v_chaves) AND q.decisao = 'nao') THEN
      v_pula := 'o Tel disse que não é corretor';
    ELSIF btrim(nai_cfg('so_estes_numeros', '')) <> '' AND NOT nai_na_lista_curta(v_ct, r.chave) THEN
      v_pula := 'fora da lista curta';
    END IF;

    IF v_pula IS NOT NULL THEN
      INSERT INTO nai_followup (chave, dia_recebeu, contato_id, codigos, estado, motivo)
      VALUES (r.chave, v_hoje - 1, v_ct, r.codigos, 'pulado', v_pula) ON CONFLICT DO NOTHING;
      CONTINUE;
    END IF;

    SELECT nai_vocativo(coalesce(k.nome_completo, k.nome_whatsapp)) INTO v_nome FROM nai_contato k WHERE k.id = v_ct;
    INSERT INTO nai_saida (turno_id, contato_id, papel_destino, chave_destino, tipo, texto, ordem, motivo, enviar_apos)
    VALUES (NULL, v_ct, 'seguimento', '', 'texto',
            'Oi' || coalesce(' ' || v_nome, '') || ', seu cliente tem interesse?', 1, 'followup', now());
    INSERT INTO nai_saida (turno_id, contato_id, papel_destino, chave_destino, tipo, texto, ordem, motivo, enviar_apos)
    VALUES (NULL, v_ct, 'seguimento', '', 'texto',
            coalesce(v_nome || ', q', 'Q') || 'ualquer coisa temos muitas opções de imóveis para locação e venda, '
            || 'o que está procurando para seus clientes?', 2, 'followup', now() + interval '8 seconds');
    INSERT INTO nai_followup (chave, dia_recebeu, contato_id, codigos, estado)
    VALUES (r.chave, v_hoje - 1, v_ct, r.codigos, 'enviado') ON CONFLICT DO NOTHING;
    v_feitos := v_feitos + 1;
  END LOOP;
  RETURN v_feitos;
END;
$fn$;


CREATE OR REPLACE FUNCTION public.nai_liberar_saida(p_turno bigint)
 RETURNS TABLE(id bigint, rota text, telefone text, chave_esperada text, corpo jsonb, codigo integer, papel text, redirecionado boolean)
 LANGUAGE plpgsql
AS $function$
#variable_conflict use_column
DECLARE
  r          record;
  v_modo     text := nai_cfg('modo', 'desligado');
  v_pausada  boolean := nai_cfg('pausada', 'sim') <> 'nao';
  -- ESPELHO DO TREINO NUNCA SAI (92): a trava geral OU o destino ser o
  -- espelho. Com a Nay no ar, e o que permite testar sem calar ninguem.
  v_simulado boolean := nai_cfg('envio_simulado', 'nao') = 'sim'
                        OR nai_chave((SELECT c.telefone FROM nai_turno t
                                        JOIN nai_contato c ON c.id = t.contato_id
                                       WHERE t.id = p_turno))
                           = nai_chave(nai_cfg('treino_espelho', ''));
  v_testes   text[] := nai_chaves_teste();
  v_destino  text := nai_fone_envio(nai_cfg('telefone_teste_destino', ''));
  v_tel      text;
  v_texto    text;
  v_chave_c  text;
  v_bloq     text;
  v_redir    boolean;
  v_papel_t  text;
  v_etiqueta text;
  v_nome     text;
  -- PROPRIETARIO PELO TEL (Tel, 19/09) -- ver o bloco la embaixo.
  v_prop_tel boolean := nai_cfg('proprietario_pelo_tel', 'nao') = 'sim';
  v_fone_prop text;
  v_v        record;
  v_cmd      boolean;   -- e a resposta a um comando de quem pode comandar?
  v_simulado_linha boolean;   -- a trava do espelho, calculada por MENSAGEM (113b)
BEGIN
  FOR r IN
    SELECT s.* FROM nai_saida s
     WHERE s.estado = 'pendente'
       AND s.enviar_apos <= now()
       AND ((p_turno IS NOT NULL AND s.turno_id = p_turno)
         OR (p_turno IS NULL AND (s.turno_id IS NULL OR s.criado_em < now() - interval '3 minutes'
                                   -- com hora marcada (113): e o texto que espera as fotos
                                   OR s.enviar_apos > s.criado_em + interval '1 second')
             AND (nai_dentro_da_janela() OR s.papel_destino = 'tel')))
     ORDER BY s.id
     LIMIT 80
     FOR UPDATE SKIP LOCKED
  LOOP
    v_bloq := NULL; v_redir := false; v_texto := r.texto; v_etiqueta := NULL;
    SELECT k.chave, k.telefone, coalesce(k.nome_completo, k.nome_whatsapp)
      INTO v_chave_c, v_tel, v_nome FROM nai_contato k WHERE k.id = r.contato_id;

    -- RESPOSTA A COMANDO: volta para quem mandou, sempre. Nao e redirecionada
    -- no modo teste (senao a resposta do Tel cairia no chat do Pedro) e nao e
    -- barrada pela pausa (senao PARAR ATENDIMENTO ficaria sem confirmacao --
    -- medido em 15/09: saiu 'bloqueado' com motivo nai_pausada, e ele nao
    -- soube se tinha funcionado). Vale so para o texto que a propria funcao de
    -- comando escreveu, indo para um telefone de `comando_telefones`.
    -- O ESPELHO NUNCA SAI (92), agora conferido NESTA mensagem: pela
    -- agenda nao existe turno, e a trava calculada no topo dava falso.
    v_simulado_linha := v_simulado
      OR nai_chave(v_tel) = nai_chave(nai_cfg('treino_espelho', ''))
      OR nai_chave(v_chave_c) = nai_chave(nai_cfg('treino_espelho', ''))
      -- 141: o que NASCE de um turno ou de uma visita do espelho tambem e
      -- simulado -- o aviso ao Tel, o pedido a Rayssa, a mensagem ao dono e ao
      -- acompanhante. Sem isto, testar a visita pelo espelho com a Nay no ar
      -- mandaria mensagem de verdade para gente de verdade.
      OR EXISTS (SELECT 1 FROM nai_turno tt JOIN nai_contato cc ON cc.id = tt.contato_id
                  WHERE tt.id = r.turno_id AND cc.chave = nai_chave(nai_cfg('treino_espelho', '')))
      OR EXISTS (SELECT 1 FROM nai_visita vv JOIN nai_contato cc ON cc.id = vv.corretor_id
                  WHERE vv.id = r.visita_id AND cc.chave = nai_chave(nai_cfg('treino_espelho', '')));

    v_cmd := r.motivo = 'comando_tel' AND r.papel_destino = 'turno'
             AND nai_pode_comandar(v_chave_c);

    IF v_modo NOT IN ('teste', 'todos') THEN
      v_bloq := 'nai_desligada';
    ELSIF v_pausada AND NOT v_cmd THEN
      v_bloq := 'nai_pausada';
    ELSIF v_chave_c IS DISTINCT FROM r.chave_destino THEN
      v_bloq := 'contato_mudou';
    ELSIF r.papel_destino <> 'tel'
          -- 16/09: mesma leitura da porta e da abertura do turno.
          AND nai_tel_com_a_conversa(r.contato_id)
          -- 135: a ENTREGA pedida pela equipe tambem passa. Quem pediu para
          -- mandar o imovel ao cliente foi a propria equipe -- inclusive quando
          -- o Tel esta conversando com ele.
          AND NOT (r.papel_destino IN ('turno', 'entrega') AND (SELECT t2.papel FROM nai_turno t2 WHERE t2.id = r.turno_id) = 'tel') THEN
      -- O TEL ASSUMIU esse chat: a NAI nao manda mais nada para essa pessoa
      -- (so a resposta a um comando do proprio Tel passa).
      v_bloq := 'tel_assumiu';
    ELSIF r.tipo = 'imagem'
          AND NOT EXISTS (SELECT 1 FROM imovel_fotos f WHERE f.codigo = r.codigo AND f.url = r.imagem_url)
          -- A COLAGEM tambem e imagem legitima daquele imovel (Tel, 12/09): ela
          -- nao esta em `imovel_fotos` -- e montada por nos e mora em
          -- `imovel_colagem`. Sem esta linha, toda colagem sairia bloqueada
          -- como "foto_nao_confere", que e a trava contra mandar a foto de um
          -- imovel no card de outro.
          AND NOT EXISTS (SELECT 1 FROM imovel_colagem c WHERE c.codigo = r.codigo AND c.url = r.imagem_url) THEN
      v_bloq := 'foto_nao_confere';
    -- REPETIDA: o mesmo texto para a mesma pessoa em 10 minutos não sai de novo.
    -- EXCEÇÃO (Tel, 14/09): as frases do "depois das fotos" são passo do
    -- roteiro, não repetição do modelo. Ela mandou a sugestão de visita às
    -- 20:12 e as fotos às 20:17 -- e "Ou se tiver alguma dúvida ou quiser mais
    -- imóveis..." saiu BLOQUEADA como repetida, logo depois das fotos.
    -- ...e só conta o que saiu DEPOIS do marco de conversa zerada (14/09): o
    -- pré-voo mandou as frases da sugestão em modo simulado, a conversa foi
    -- zerada, e no teste seguinte a mesma sugestão saiu BARRADA como repetida.
    -- Conversa zerada é conversa nova, também para esta trava.
    -- ...e mensagem de VISITA só é repetida se for da MESMA visita (14/09): dois
    -- pedidos de visita seguidos ao mesmo proprietário, com o mesmo texto, são
    -- duas visitas -- o segundo saía barrado e o proprietário nunca sabia.
    -- ...e RESPOSTA A COMANDO nunca e repetida (Tel, 15/09): ele mandou
    -- "agenda de visitas" duas vezes, a agenda estava igual, e a segunda saiu
    -- BLOQUEADA como repetida -- que e exatamente o sintoma de "ela nao
    -- respondeu" que ele relatou. Comando pedido duas vezes e respondido duas
    -- vezes.
    ELSIF r.tipo = 'texto' AND NOT v_cmd AND coalesce(r.motivo, '') <> 'depois_das_fotos' AND EXISTS (
            SELECT 1 FROM nai_saida s2
             WHERE s2.contato_id = r.contato_id AND s2.estado IN ('enviado', 'simulado', 'enviando')
               AND s2.tipo = 'texto' AND s2.texto = r.texto
               AND s2.visita_id IS NOT DISTINCT FROM r.visita_id
               AND coalesce(s2.enviado_em, s2.criado_em) > greatest(now() - interval '10 minutes',
                     coalesce((SELECT k3.zerado_em FROM nai_contato k3 WHERE k3.id = r.contato_id), '-infinity'::timestamptz))) THEN
      v_bloq := 'repetida';
    -- foto que ELE pediu de novo sai de novo (Tel, 22/09)
    ELSIF r.tipo = 'imagem'
      AND NOT coalesce((SELECT nai_pede_foto(coalesce(tt.texto, '')) FROM nai_turno tt WHERE tt.id = r.turno_id), false)
      AND EXISTS (
            SELECT 1 FROM nai_saida s2
             WHERE s2.contato_id = r.contato_id AND s2.estado IN ('enviado', 'simulado', 'enviando')
               AND s2.tipo = 'imagem' AND s2.imagem_url = r.imagem_url
               AND coalesce(s2.enviado_em, s2.criado_em) > greatest(now() - interval '10 minutes',
                     coalesce((SELECT k3.zerado_em FROM nai_contato k3 WHERE k3.id = r.contato_id), '-infinity'::timestamptz))) THEN
      v_bloq := 'repetida';
    END IF;

    -- MODO TESTE: o que iria para proprietario, Fernando ou Tel vai para o
    -- numero de teste, com a etiqueta de para quem iria.
    IF v_bloq IS NULL AND v_modo = 'teste' AND NOT v_cmd THEN
      IF r.papel_destino IN ('proprietario', 'motoboy', 'tel') THEN
        v_redir := true;
        v_etiqueta := '🧪 TESTE · iria para o ' ||
          CASE r.papel_destino WHEN 'proprietario' THEN 'PROPRIETÁRIO' WHEN 'motoboy' THEN '' || nai_acompanhante_maiusculo() || ' (motoboy)' ELSE 'TEL' END ||
          coalesce(' ' || v_nome, '') ||
          coalesce(' · visita #' || r.visita_id, '') || E'\n' ||
          CASE r.papel_destino
            WHEN 'proprietario' THEN 'Para responder como proprietário: MARQUE esta mensagem, ou comece com P:'
            WHEN 'motoboy' THEN 'Para responder como ' || nai_acompanhante() || ': MARQUE esta mensagem, ou comece com M:'
            ELSE 'Para responder como Tel: comece com T:' END || E'\n\n';
        v_tel := v_destino;
      ELSIF r.papel_destino = 'turno' THEN
        SELECT t.papel INTO v_papel_t FROM nai_turno t WHERE t.id = r.turno_id;
        IF v_papel_t IN ('proprietario', 'motoboy', 'tel') THEN
          v_etiqueta := '🧪 (resposta ao ' ||
            CASE v_papel_t WHEN 'proprietario' THEN 'PROPRIETÁRIO' WHEN 'motoboy' THEN '' || nai_acompanhante_maiusculo() || '' ELSE 'TEL' END || E')\n';
        END IF;
        -- TODAS AS MENSAGENS NO CHAT DELE (Tel, 13/09: "quero que as mensagens
        -- vao todas para mim, corretores, proprietarios e tal nesse teste"). O
        -- que iria para outro numero -- um corretor simulado, por exemplo --
        -- chega no numero de teste com a etiqueta de para quem iria. Antes isso
        -- morria como 'teste_fora_da_lista' e ele nao via a mensagem.
        IF nai_chave(v_tel) IS DISTINCT FROM nai_chave(v_destino) THEN
          v_redir := true;
          v_etiqueta := coalesce(v_etiqueta, '') || '🧪 TESTE · iria para o ' ||
            CASE coalesce(v_papel_t, 'corretor')
              WHEN 'proprietario' THEN 'PROPRIETÁRIO'
              WHEN 'motoboy' THEN '' || nai_acompanhante_maiusculo() || ' (motoboy)'
              WHEN 'tel' THEN 'TEL'
              ELSE 'CORRETOR' END ||
            coalesce(' ' || v_nome, '') || ' ' || nai_fone_fmt(v_tel) || E'\n\n';
          v_tel := v_destino;
        END IF;
      END IF;
      -- PAREDE DO TESTE: nada sai para numero fora da lista de teste.
      IF NOT (nai_chave(v_tel) = ANY (v_testes)) THEN
        v_bloq := 'teste_fora_da_lista';
      END IF;
    END IF;

    -- ---------------------------------------------------------------
    -- PROPRIETARIO PELO TEL (Tel, 19/09): "so as mensagens para
    -- proprietarios estao temporariamente bloqueadas, entao elas vao para o
    -- Tel". O proprietario NAO recebe nada; o Tel recebe o nome e o numero
    -- de quem ele precisa ligar.
    --
    -- Isto NAO e o modo teste: vale em producao (`modo = todos`), e o desvio
    -- do teste continua mandando tudo para o numero de teste, como antes.
    --
    -- O aviso carrega o comando de volta (`VISITA <id> OK`). Sem ele a visita
    -- fica parada para sempre: a Nay pergunta, o Tel liga para o dono, e nao
    -- tem como dizer a ela que o dono confirmou.
    --
    -- `ult_msg_prop_em` continua sendo carimbado no `nai_confirmar_envio`,
    -- de proposito: e o relogio que espaca os lembretes. Sem o carimbo, o
    -- ciclo remarcaria o passo do proprietario na hora e encheria o Tel de
    -- mensagens iguais. E o mesmo que o modo teste ja faz ao redirecionar.
    -- ---------------------------------------------------------------
    IF v_bloq IS NULL AND v_modo = 'todos' AND v_prop_tel
       AND r.papel_destino = 'proprietario' THEN
      SELECT * INTO v_v FROM nai_visita WHERE id = r.visita_id;
      IF r.tipo <> 'texto' OR v_v.id IS NULL THEN
        -- Foto para proprietario nao existe (o gatilho barra na insercao). Se
        -- um dia existir, ela para aqui em vez de virar um desvio improvisado.
        v_bloq := 'prop_pelo_tel_sem_texto';
      ELSE
        v_fone_prop := v_tel;
        v_redir     := true;
        v_tel       := nai_fone_envio(nai_cfg('tel_telefone'));
        v_texto     := 'Visita agendada, pergunte ao proprietário '
          || coalesce(nullif(btrim(coalesce(v_nome, '')), ''),
                      nullif(btrim(coalesce(v_v.proprietario_nome, '')), ''),
                      'do imóvel ' || v_v.codigo)
          || ' de número ' || nai_fone_fmt(v_fone_prop)
          || ' se a visita ' || coalesce(nai_quando_humano(coalesce(v_v.quando, v_v.quando_sugerido)),
                                         'no horário combinado')
          || ' pode ser realizada.'
          || E'\n\nImóvel ' || v_v.codigo || ' · visita #' || v_v.id
          || E'\nMe responda: VISITA ' || v_v.id || ' OK (proprietário confirmou) · VISITA '
          || v_v.id || ' CANCELA · VISITA ' || v_v.id || ' REMARCA 16h'
          || E'\n\n— o que eu ia mandar para ele:\n' || r.texto;
      END IF;
    END IF;

    IF v_bloq IS NOT NULL THEN
      UPDATE nai_saida s SET estado = 'bloqueado', bloqueio = v_bloq, telefone_final = v_tel, enviado_em = now()
       WHERE s.id = r.id;
      CONTINUE;
    END IF;

    IF r.tipo = 'texto' AND v_etiqueta IS NOT NULL THEN
      v_texto := v_etiqueta || v_texto;
    END IF;

    IF v_simulado_linha THEN
      UPDATE nai_saida s SET estado = 'simulado', telefone_final = v_tel, redirecionado = v_redir,
                             enviado_em = now(), resposta = jsonb_build_object('texto_final', v_texto)
       WHERE s.id = r.id;
      IF r.visita_id IS NOT NULL AND r.papel_destino = 'proprietario' THEN
        UPDATE nai_visita SET ult_msg_prop_em = now() WHERE nai_visita.id = r.visita_id;
      ELSIF r.visita_id IS NOT NULL AND r.papel_destino = 'motoboy' THEN
        UPDATE nai_visita SET ult_msg_moto_em = now() WHERE nai_visita.id = r.visita_id;
      END IF;
      CONTINUE;
    END IF;

    UPDATE nai_saida s SET estado = 'enviando', telefone_final = v_tel, redirecionado = v_redir
     WHERE s.id = r.id;

    id := r.id;
    rota := CASE r.tipo WHEN 'imagem' THEN 'send-image' ELSE 'send-text' END;
    telefone := v_tel;
    chave_esperada := nai_chave(v_tel);
    corpo := CASE r.tipo
               WHEN 'imagem' THEN jsonb_build_object('phone', v_tel, 'image', r.imagem_url)
               ELSE jsonb_build_object('phone', v_tel, 'message', v_texto) END;
    codigo := r.codigo;
    papel := r.papel_destino;
    redirecionado := v_redir;
    RETURN NEXT;
  END LOOP;
END;
$function$;

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

CREATE OR REPLACE FUNCTION public.nai_deve_atender(p_telefone text, p_texto text, p_codigo_citado integer DEFAULT NULL::integer)
 RETURNS TABLE(atende boolean, motivo text)
 LANGUAGE plpgsql
AS $function$
DECLARE
  v_chave  text := nai_chave(p_telefone);
  v_desde  timestamptz;
  v_antigo boolean;
  v_lib    timestamptz;
  v_humano timestamptz;
  v_id     bigint;
  v_cod    boolean;
BEGIN
  IF lower(coalesce(nai_cfg('regra_publico', 'nao'), 'nao')) <> 'sim' THEN
    RETURN QUERY SELECT true, 'regra desligada'::text; RETURN;
  END IF;
  v_desde := nullif(btrim(nai_cfg('regra_publico_desde', '')), '')::timestamptz;
  IF v_desde IS NULL THEN
    RETURN QUERY SELECT true, 'sem carimbo: regra nao vale'::text; RETURN;
  END IF;

  SELECT c.id, c.liberado_em, c.humano_assumiu_em INTO v_id, v_lib, v_humano
    FROM nai_contato c WHERE c.chave = v_chave;

  -- MENSAGEM POR HUMANO PAUSA (Tel, 15/09), AGORA POR MEIA HORA (Tel, 16/09).
  -- Vale antes de tudo. Passado o gap, a conversa nao volta para ela de
  -- presente: volta a ser julgada pelas regras abaixo, como qualquer outra.
  -- Conversa antiga continua sendo do Tel, a nao ser que a pessoa peca fotos
  -- de um imovel ou peca imoveis -- que e o desenho dele desde 15/09.
  IF nai_tel_com_a_conversa(v_id) THEN
    RETURN QUERY SELECT false,
      CASE WHEN (SELECT c2.humano_motivo FROM nai_contato c2 WHERE c2.id = v_id)
                = 'o Tel escreveu pelo celular'
           THEN 'o Tel escreveu ha menos de ' || greatest(nai_cfg_int('gap_tel_min', 30), 0) || ' min'
           ELSE 'o Tel assumiu essa conversa' END;
    RETURN;
  END IF;

  -- A LISTA CURTA E QUEM ELA ATENDE -- E ATENDE SEMPRE (27/09/2026, 135).
  -- "responder as minhas mensagens e do tel" (25/09) e, no dia 27, "precisa
  -- enviar os imoveis que ele, eu ou a rayssa pedem". Ate aqui a lista so
  -- ABRIA a primeira parede: quem estava nela seguia sendo julgado como
  -- corretor la embaixo, e a Rayssa caia em "contato novo, assunto que nao e
  -- de corretor". E a lista olhava so a linha que chegou: o Pedro pelo @lid
  -- dava "fora da lista curta de teste". Agora olha as duas linhas da pessoa,
  -- e quem esta nela passa direto.
  IF nai_na_lista_curta(v_id, v_chave) THEN
    RETURN QUERY SELECT true, 'da lista curta: sempre atendida'::text; RETURN;
  END IF;
  -- A EQUIPE E SEMPRE ATENDIDA, COM OU SEM LISTA CURTA (137, 28/09/2026). O
  -- ensaio da religacao das 7h mostrou: sem a lista, Tel, Pedro @lid e Rayssa
  -- caiam em "conversa que ja existia: quem responde e o Tel" -- o porteiro
  -- julgava a equipe como corretor com conversa antiga. Equipe = o Tel e a
  -- tabela `equipe` (a mesma definicao da 130), pelas duas linhas da pessoa.
  IF v_id IS NOT NULL AND nai_e_da_equipe_contato(v_id) THEN
    RETURN QUERY SELECT true, 'da equipe: sempre atendida'::text; RETURN;
  END IF;

  -- A LISTA CURTA (Tel, 25/09/2026): "responder as minhas mensagens e do
  -- tel somente por enquanto". Vazia, a parede nem existe. Preenchida, ela
  -- vem antes da lista de corretor porque e mais restritiva -- e o Tel
  -- passa sempre, senao ele perderia o proprio comando de religar.
  IF btrim(nai_cfg('so_estes_numeros', '')) <> ''
     AND v_chave <> nai_chave(nai_cfg('tel_telefone'))
     AND NOT (v_chave = ANY (nai_chaves_de('so_estes_numeros')))
     -- O ESPELHO DO TREINO PASSA (26/09/2026). A lista curta existe para a
     -- Nay nao falar com ninguem no WhatsApp fora do Tel. O espelho do
     -- treino nao esta no WhatsApp -- ele roda aqui dentro, com
     -- envio_simulado=sim -- e a lista o derrubava junto, o que travou a
     -- rodada 12 inteira em "nao estabilizou". Quem esta em `numeros_teste`
     -- e lista nossa, escrita a mao: nao e publico.
     AND NOT (v_chave = ANY (nai_chaves_teste())) THEN
    RETURN QUERY SELECT false, 'fora da lista curta de teste'::text; RETURN;
  END IF;

  -- SO CORRETOR DOS GRUPOS (Tel, 18/09/2026): "voce so vai responder essas
  -- pessoas". Vem logo DEPOIS da pausa do Tel -- a pausa dele continua valendo
  -- antes de tudo -- e ANTES de "conversa ja liberada": a lista decide QUEM
  -- ela pode atender, as regras de baixo decidem QUANDO. So vale para quem
  -- seria corretor: `nai_lista_governa` isenta Tel, equipe, motoboy e dono de
  -- imovel com visita. Desligada enquanto `so_corretor_da_lista` <> 'sim'.
  IF lower(coalesce(nai_cfg('so_corretor_da_lista', 'nao'), 'nao')) = 'sim'
     AND nai_lista_governa(v_chave, v_id)
     AND NOT nai_pode_falar(v_chave, p_telefone) THEN
    IF EXISTS (SELECT 1 FROM nai_corretor_pergunta q
                WHERE q.chave = v_chave AND q.decisao = 'nao') THEN
      RETURN QUERY SELECT false, 'o Tel disse que nao e corretor'::text; RETURN;
    END IF;
    IF nai_pergunta_de_imovel(p_texto, p_telefone, p_codigo_citado) THEN
      -- A pergunta ao Tel sai do gatilho `nai_turno_pergunta_corretor`, que le
      -- ESTE texto no turno. Mudou a frase aqui, muda la tambem.
      IF EXISTS (SELECT 1 FROM nai_corretor_pergunta q WHERE q.chave = v_chave) THEN
        RETURN QUERY SELECT false, 'fora da lista: esperando o Tel dizer se e corretor'::text; RETURN;
      END IF;
      RETURN QUERY SELECT false, 'fora da lista: perguntou de imovel, perguntar ao Tel'::text; RETURN;
    END IF;
    RETURN QUERY SELECT false, 'fora da lista de corretores'::text; RETURN;
  END IF;

  IF v_lib IS NOT NULL THEN
    RETURN QUERY SELECT true, 'conversa ja liberada'::text; RETURN;
  END IF;

  -- CONVERSA QUE ELA JA ATENDEU e dela ate o Tel digitar. Sem isto a porta
  -- julgava cada mensagem sozinha, e "pode mandar" -- resposta de quem esta
  -- negociando -- virava "assunto que nao e de corretor".
  IF v_id IS NOT NULL AND EXISTS (
       SELECT 1 FROM nai_saida s
        WHERE s.contato_id = v_id
          AND s.papel_destino IN ('turno', 'corretor', 'seguimento')
          AND s.estado IN ('enviado', 'enviando', 'simulado')
          AND s.criado_em > v_desde) THEN
    RETURN QUERY SELECT true, 'conversa que ela ja estava atendendo'::text; RETURN;
  END IF;

  -- MARCOU UMA MENSAGEM (o card do grupo, o imovel que ela mandou): e imovel,
  -- seja o que for que ele tenha escrito junto. E o filtro que o Tel deu.
  IF p_codigo_citado IS NOT NULL THEN
    RETURN QUERY SELECT true, 'marcou uma mensagem de imovel'::text; RETURN;
  END IF;

  SELECT EXISTS (SELECT 1 FROM mensagens m
                  WHERE nai_chave(m.telefone) = v_chave AND m.criada_em < v_desde)
      OR EXISTS (SELECT 1 FROM nai_turno t JOIN nai_contato c ON c.id = t.contato_id
                  WHERE c.chave = v_chave AND t.criado_em < v_desde)
    INTO v_antigo;

  IF NOT v_antigo THEN
    IF nai_assunto_de_corretor(p_texto)
       OR (nai_pedido_de_perfil(p_texto)->>'e_pedido')::boolean
       -- 16/09: colar a ficha de um imovel nosso, mesmo sem a linha "Codigo:",
       -- e falar de imovel.
       OR coalesce(array_length(nai_imovel_pelo_condominio(p_texto, p_telefone), 1), 0) > 0 THEN
      RETURN QUERY SELECT true, 'contato novo falando de imovel'::text; RETURN;
    END IF;
    RETURN QUERY SELECT false, 'contato novo, assunto que nao e de corretor'::text; RETURN;
  END IF;

  v_cod := EXISTS (SELECT 1 FROM unnest(coalesce(nay_codigos_citados(coalesce(p_texto, '')), '{}'::text[])) x
                    WHERE x ~ '^[0-9]{3,5}$');

  -- MANDOU O IMOVEL PELO LINK DO CATALOGO (111, Tel 23/09). O link nao diz
  -- qual imovel e, mas diz que o assunto E imovel -- e e por isso que a porta
  -- abre. Quem descobre qual e o Tel, logo adiante.
  IF nai_e_link_de_produto(p_texto) THEN
    UPDATE nai_contato SET liberado_em = now(),
                           liberado_motivo = left('mandou link de catalogo: ' || coalesce(p_texto, ''), 200)
     WHERE chave = v_chave;
    RETURN QUERY SELECT true, 'mandou o imovel pelo link do catalogo'::text; RETURN;
  END IF;

  -- COLOU O CARD, OU ESCREVEU O CODIGO (101, Tel 23/09). E o caso mais
  -- claro de "falar de imovel nosso" que existe -- e era o unico que a porta
  -- recusava, porque a regra do nome logo abaixo comeca com `NOT v_cod`.
  -- O codigo tem que ser de imovel que existe: numero solto nao abre porta.
  IF v_cod AND EXISTS (
       SELECT 1 FROM imoveis i
        WHERE i.codigo::text = ANY (coalesce(nay_codigos_citados(coalesce(p_texto, '')), '{}'::text[]))) THEN
    UPDATE nai_contato SET liberado_em = now(),
                           liberado_motivo = left('colou o card / citou o codigo: ' || coalesce(p_texto, ''), 200)
     WHERE chave = v_chave;
    RETURN QUERY SELECT true, 'colou o card de um imovel nosso'::text; RETURN;
  END IF;

  -- CITOU UM IMOVEL NOSSO PELO NOME (Tel, 16/09). Vale o mesmo que pedir foto
  -- de um imovel: a pessoa disse de qual imovel fala, entao a conversa abre.
  IF NOT v_cod
     AND coalesce(array_length(nai_imovel_pelo_condominio(p_texto, p_telefone), 1), 0) > 0 THEN
    UPDATE nai_contato SET liberado_em = now(),
                           liberado_motivo = left('citou o imovel pelo nome: ' || coalesce(p_texto, ''), 200)
     WHERE chave = v_chave;
    RETURN QUERY SELECT true, 'citou um imovel nosso pelo nome'::text; RETURN;
  END IF;

  IF nai_pede_foto(p_texto) AND v_cod THEN
    UPDATE nai_contato SET liberado_em = now(),
                           liberado_motivo = left('pediu foto: ' || coalesce(p_texto, ''), 200)
     WHERE chave = v_chave;
    RETURN QUERY SELECT true, 'pediu foto de um imovel'::text; RETURN;
  END IF;

  IF (nai_pedido_de_perfil(p_texto)->>'e_pedido')::boolean THEN
    UPDATE nai_contato SET liberado_em = now(),
                           liberado_motivo = left('pediu imoveis: ' || coalesce(p_texto, ''), 200)
     WHERE chave = v_chave;
    RETURN QUERY SELECT true, 'pediu imoveis'::text; RETURN;
  END IF;

  IF nai_pede_foto(p_texto) THEN
    RETURN QUERY SELECT false, 'pediu foto mas nao da para saber o imovel'::text; RETURN;
  END IF;
  RETURN QUERY SELECT false, 'conversa que ja existia: quem responde e o Tel'::text;
END;
$function$;

CREATE OR REPLACE FUNCTION public.nai_conferir_resposta(p_turno bigint, p_texto text, p_codigos jsonb, p_escreveu text, p_fotos_site jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
AS $function$
DECLARE
  t        nai_turno;
  k        nai_contato;
  v_texto  text := btrim(coalesce(p_texto, ''));
  v_guarda text;
  v_alvo   int;
  v_cods   int[];
  v_sem    int[] := '{}';
  v_gate   boolean := false;
  v_sugerir boolean := false;
  v_base   text;
  v_novo   text;
  v_corretor boolean;
  v_calada boolean;
  c_ok     int;
  c_card   text;
  v_n      int;
  v_ident  boolean := false;
  v_cands  int[];
  v_fichas text;
BEGIN
  SELECT * INTO t FROM nai_turno WHERE id = p_turno;
  IF t.id IS NULL THEN RETURN jsonb_build_object('acao', 'parou', 'motivo', 'turno_inexistente'); END IF;
  SELECT * INTO k FROM nai_contato WHERE id = t.contato_id;
  v_corretor := t.papel = 'corretor';
  v_calada := v_texto = '' OR upper(v_texto) ~ '^\W*SIL[EÊ]NCIO\W*$';

  -- 00p ------------------------------------------ PARCERIA (Tel, 28/09/2026)
  -- "Quando o corretor perguntar se aceitamos parceria, ela dizer 'Sim,
  -- aceitamos parceria em todos os nossos imoveis o que precisar pode contar
  -- com a gente'". Vem antes da secretaria de proposito: seja quem for que
  -- respondeu, a frase sai igual. Mensagem so de parceria = so a frase; com
  -- outro assunto junto, a frase vai na frente da resposta dela.
  IF t.papel = 'corretor' AND nai_pergunta_parceria(coalesce(p_escreveu, ''))
     AND v_texto !~* 'aceitamos parceria' THEN
    v_texto := nai_cfg('resposta_parceria', 'Sim, aceitamos parceria em todos os nossos imóveis, o que precisar pode contar com a gente!')
               || CASE WHEN v_calada OR nai_so_parceria(coalesce(p_escreveu, '')) THEN ''
                       ELSE E'\n\n' || v_texto END;
    PERFORM nai_anotar(p_turno, 0, 'parceria', 'mudou', 'resposta fixa de parceria');
    IF v_calada OR nai_so_parceria(coalesce(p_escreveu, '')) THEN
      RETURN jsonb_build_object('acao', 'responder', 'texto', v_texto, 'guarda', 'parceria', 'codigo', NULL);
    END IF;
    v_calada := false;
  END IF;

  -- 00 ------------------------------------------- A SECRETARIA (99)
  -- Turno da secretaria nao passa pelas guardas de locacao: elas cobram card,
  -- código e consulta à base, que é o fluxo da outra. Aqui vale o silêncio
  -- quando não há o que dizer, e nada mais.
  IF t.atendente = 'secretaria' THEN
    IF v_calada THEN
      RETURN jsonb_build_object('acao', 'silencio', 'guarda', 'secretaria_calada');
    END IF;
    RETURN jsonb_build_object('acao', 'responder', 'texto', v_texto,
                              'guarda', 'secretaria', 'codigo', NULL);
  END IF;

  -- 01 -------------------------------------------------- DE QUAL IMÓVEL É
  -- O código do turno (card marcado, card da resposta, o que ele escreveu) e,
  -- faltando esse, o imóvel da CONVERSA. O turno guarda o que achou: é o fio
  -- para a mensagem seguinte ("me manda as fotos dele").
  SELECT CASE WHEN count(DISTINCT x) = 1 THEN min(x)::int END INTO v_alvo
    FROM jsonb_array_elements_text(coalesce(p_codigos, '[]'::jsonb)) x WHERE x ~ '^[0-9]{3,5}$' AND x::int > 0;
  IF v_alvo IS NULL THEN v_alvo := nai_imovel_da_conversa(t.contato_id, p_escreveu); END IF;
  IF v_alvo IS NOT NULL THEN
    UPDATE nai_turno SET codigo = v_alvo WHERE id = p_turno AND codigo IS DISTINCT FROM v_alvo;
  END IF;
  PERFORM nai_anotar(p_turno, 1, 'imovel_da_conversa',
                     CASE WHEN v_alvo IS NULL THEN 'passou' ELSE 'mudou' END,
                     coalesce('imóvel ' || v_alvo, 'nenhum imóvel identificado'));

  -- 02 ------------------------------------------- FOTOS LIDAS NO SITE (camada 2)
  v_n := nai_gravar_fotos_do_site(p_fotos_site);
  PERFORM nai_anotar(p_turno, 2, 'fotos_do_site', CASE WHEN v_n > 0 THEN 'mudou' ELSE 'passou' END,
                     CASE WHEN v_n > 0 THEN v_n || ' fotos gravadas do anúncio' END);

  -- 02a ------------------------- LINK DE CATÁLOGO NÃO DIZ QUAL IMÓVEL É (111)
  -- Sem código na conversa, qualquer imóvel que ela mandasse aqui seria
  -- chute. O Tel recebe o link e responde; ela diz que recebeu, e não cala.
  IF t.papel = 'corretor' AND v_alvo IS NULL
     AND nai_e_link_de_produto(coalesce(p_escreveu, '')) THEN
    v_base := nai_escalar_link_de_catalogo(p_turno, p_escreveu);
    PERFORM nai_anotar(p_turno, 2, 'link_de_catalogo', 'mudou',
                       'link de produto sem código: subiu ao Tel');
    RETURN jsonb_build_object('acao', 'responder', 'texto', v_base,
                              'guarda', 'link_de_catalogo', 'codigo', NULL);
  END IF;

  -- 02b ------------------------------------------ ELA NÃO FAZ CADASTRO (97)
  -- Oferta de imóvel dele é pergunta para o Tel. Tem que ser AQUI, antes de
  -- tudo: o card e as fotos só são enfileirados depois que esta função
  -- devolve 'responder'. O Tel e o Fernando ficam de fora pelo papel.
  IF t.papel IN ('corretor', 'proprietario')
     AND NOT nai_secretaria_ligada()
     AND nai_oferece_imovel(coalesce(p_escreveu, '')) THEN
    PERFORM nai_escalar_cadastro(p_turno, p_escreveu);
    PERFORM nai_anotar(p_turno, 2, 'oferta_de_imovel', 'parou',
                       'ofereceu imóvel: subiu ao Tel e parou o chat');
    RETURN jsonb_build_object('acao', 'parou', 'guarda', 'oferta_de_imovel_foi_ao_tel');
  END IF;

  -- 03 --------------------------------- PERGUNTA SEM RESPOSTA / PROMESSA DE RETORNO
  -- Não existe "vou ver e te aviso": ou responde com a base, ou o Tel responde.
  IF v_corretor AND NOT (coalesce(t.ferramentas, '{}') && ARRAY['escalar', 'visita']::text[])
     AND ((v_calada AND coalesce(p_escreveu, '') ~ '\?') OR v_texto ~* nai_re_promessa()) THEN
    v_base := nai_escalar_calado(p_turno, p_escreveu,
      CASE WHEN v_texto ~* nai_re_promessa() THEN 'prometeu retorno' ELSE 'pergunta sem resposta' END, v_alvo);
    IF v_base IS NULL THEN
      PERFORM nai_anotar(p_turno, 3, 'promessa_ou_sem_resposta', 'parou', 'subiu ao Tel e parou o chat');
      RETURN jsonb_build_object('acao', 'parou', 'guarda', 'sem_resposta_foi_ao_tel');
    END IF;
    v_texto := v_base; v_calada := false; v_guarda := 'respondido_pela_base';
    PERFORM nai_anotar(p_turno, 3, 'promessa_ou_sem_resposta', 'mudou', 'a ficha respondeu no lugar');
  ELSIF v_corretor AND 'escalar' = ANY (coalesce(t.ferramentas, '{}')) AND v_texto ~* nai_re_promessa() THEN
    PERFORM nai_anotar(p_turno, 3, 'promessa_ou_sem_resposta', 'cortou', 'já escalou neste turno: promessa cortada');
    RETURN jsonb_build_object('acao', 'silencio', 'guarda', 'promessa_cortada');
  ELSE
    PERFORM nai_anotar(p_turno, 3, 'promessa_ou_sem_resposta', 'passou', NULL);
  END IF;

  -- 04 ----------------------------------------------- RESPOSTA SEM CONSULTA
  -- Afirmou sobre imóvel sem ter chamado ferramenta nenhuma.
  IF v_corretor AND '_lidas' = ANY (coalesce(t.ferramentas, '{}'))
     AND coalesce(array_length(array_remove(t.ferramentas, '_lidas'), 1), 0) = 0
     AND NOT v_calada
     AND v_texto !~ '\?\s*\S{0,3}\s*$'
     AND (coalesce(p_escreveu, '') ~ '\?' OR coalesce(p_escreveu, '') ~ '\m\d{3,5}\M')
     AND (coalesce(p_escreveu, '') || ' ' || v_texto) ~* nai_re_assunto_imovel()
     AND v_guarda IS DISTINCT FROM 'respondido_pela_base' THEN
    v_base := nai_escalar_calado(p_turno, p_escreveu, 'respondeu sem consultar a base', v_alvo);
    IF v_base IS NULL THEN
      PERFORM nai_anotar(p_turno, 4, 'resposta_sem_consulta', 'parou', 'afirmou sem ferramenta: subiu ao Tel');
      RETURN jsonb_build_object('acao', 'parou', 'guarda', 'resposta_sem_consulta_foi_ao_tel');
    END IF;
    v_texto := v_base; v_guarda := 'respondido_pela_base';
    PERFORM nai_anotar(p_turno, 4, 'resposta_sem_consulta', 'mudou', 'trocada pela resposta da ficha');
  ELSE
    PERFORM nai_anotar(p_turno, 4, 'resposta_sem_consulta', 'passou', NULL);
  END IF;

  -- 05 ------------------------------------------- O FORMATO É DO TEL, NÃO DO MODELO
  IF v_corretor AND v_alvo IS NOT NULL AND coalesce(p_escreveu, '') ~ '\?'
     AND v_texto !~* 'c[óo]digo:'
     AND NOT (coalesce(t.ferramentas, '{}') && ARRAY['escalar', 'visita']::text[]) THEN
    v_base := nai_resposta_da_base(v_alvo, p_escreveu);
    IF v_base IS NOT NULL AND v_texto IS DISTINCT FROM v_base THEN
      v_texto := v_base; v_calada := false;
      v_guarda := coalesce(v_guarda || '+', '') || 'formato_da_base';
      PERFORM nai_anotar(p_turno, 5, 'formato_da_base', 'mudou', 'resposta da ficha, no formato dele');
    ELSE
      PERFORM nai_anotar(p_turno, 5, 'formato_da_base', 'passou', NULL);
    END IF;
  ELSE
    PERFORM nai_anotar(p_turno, 5, 'formato_da_base', 'passou', NULL);
  END IF;

  -- 06 ------------------------------------------------------------- SILÊNCIO
  IF v_texto = '' OR upper(v_texto) ~ '^\W*SIL[EÊ]NCIO\W*$' THEN
    PERFORM nai_anotar(p_turno, 6, 'silencio', 'parou', 'ela não responde nada, de propósito');
    RETURN jsonb_build_object('acao', 'silencio', 'guarda', v_guarda);
  END IF;
  PERFORM nai_anotar(p_turno, 6, 'silencio', 'passou', NULL);

  -- 07 ---------------------------------------------------- A VOZ DE CADA PAPEL
  IF t.papel IN ('proprietario', 'motoboy') THEN
    v_novo := nai_sem_emoji(v_texto);
    PERFORM nai_anotar(p_turno, 7, 'voz_sem_emoji', CASE WHEN v_novo <> v_texto THEN 'mudou' ELSE 'passou' END,
                       'proprietário e ' || nai_acompanhante() || ': voz da captação');
    v_texto := v_novo;
  ELSE
    PERFORM nai_anotar(p_turno, 7, 'voz_sem_emoji', 'passou', NULL);
  END IF;

  -- 08 ------------------------------------------ SUGERIR VISITA (uma vez por dia)
  IF v_corretor AND v_texto !~ '\?'
     AND (v_guarda LIKE '%respondido_pela_base%' OR v_guarda LIKE '%formato_da_base%' OR v_texto ~* '^\s*sobre isso:'
          OR coalesce(t.ferramentas, '{}') && ARRAY['o_que_sei_do_imovel', 'imovel_por_codigo',
                                                    'disponibilidade_no_condominio', 'listar_no_condominio',
                                                    'resumo_do_condominio']::text[])
     AND NOT (coalesce(t.ferramentas, '{}') && ARRAY['escalar', 'visita']::text[])
     AND v_texto !~* nai_re_sugere_visita()
     AND coalesce((k.visita_sugerida_em AT TIME ZONE 'America/Manaus')::date, date '1900-01-01')
         <> (now() AT TIME ZONE 'America/Manaus')::date
     AND NOT EXISTS (SELECT 1 FROM nai_visita x WHERE x.corretor_id = k.id AND nai_visita_aberta(x.estado)) THEN
    v_sugerir := true;
    PERFORM nai_anotar(p_turno, 8, 'sugerir_visita', 'mudou', 'sai em outra mensagem, depois da resposta');
  ELSE
    PERFORM nai_anotar(p_turno, 8, 'sugerir_visita', 'passou', NULL);
  END IF;

  -- 09 ------------------------------------------ SUGESTÃO REPETIDA NO MESMO DIA
  IF v_corretor AND v_texto ~* nai_re_sugere_visita()
     AND NOT coalesce(nay_pede_visita(coalesce(p_escreveu, '')), false)
     AND NOT EXISTS (SELECT 1 FROM nai_visita x WHERE x.corretor_id = k.id AND x.estado IN ('coletando', 'negociando')) THEN
    IF (k.visita_sugerida_em AT TIME ZONE 'America/Manaus')::date = (now() AT TIME ZONE 'America/Manaus')::date THEN
      v_texto := btrim(regexp_replace(v_texto, '(\m(e|se)\s+)?' || nai_re_sugere_visita() || '[^?!\n]*[?!]?', '', 'gi'));
      v_guarda := 'visita_repetida_cortada';
      PERFORM nai_anotar(p_turno, 9, 'sugestao_repetida', 'cortou', 'já sugeriu visita hoje');
      IF v_texto = '' THEN
        RETURN jsonb_build_object('acao', 'silencio', 'guarda', v_guarda);
      END IF;
    ELSE
      UPDATE nai_contato SET visita_sugerida_em = now() WHERE id = k.id;
      PERFORM nai_anotar(p_turno, 9, 'sugestao_repetida', 'passou', 'primeira sugestão do dia, registrada');
    END IF;
  ELSE
    PERFORM nai_anotar(p_turno, 9, 'sugestao_repetida', 'passou', NULL);
  END IF;

  -- 10 --------------------------------------------- NEGOU IMÓVEL QUE EXISTE
  IF v_corretor AND v_texto ~* nai_re_nega_imovel() THEN
    SELECT i.codigo INTO c_ok
      FROM unnest(coalesce(nay_codigos_citados(coalesce(p_escreveu, '')), '{}'::text[])) x
      JOIN imoveis i ON i.codigo::text = x
     WHERE x ~ '^[0-9]{3,5}$'
       AND nay_esta_no_mercado(i.disponivel, i.bloqueado, i.publicado_no_site)
     ORDER BY i.codigo LIMIT 1;
    IF c_ok IS NOT NULL THEN
      SELECT texto_pronto INTO c_card FROM nai_card_do_imovel(c_ok);
      IF coalesce(c_card, '') <> '' THEN
        v_texto := c_card;
        v_guarda := coalesce(v_guarda || '+', '') || 'negou_imovel_que_existe';
        PERFORM nai_anotar(p_turno, 10, 'negou_imovel_que_existe', 'mudou', 'negativa trocada pelo card do ' || c_ok);
      END IF;
    ELSE
      PERFORM nai_anotar(p_turno, 10, 'negou_imovel_que_existe', 'passou', 'negou, mas o código não é nosso ou não está no ar');
    END IF;
  ELSE
    PERFORM nai_anotar(p_turno, 10, 'negou_imovel_que_existe', 'passou', NULL);
  END IF;

  -- 11 -------------------------------------- FRASE DE VISITA SEM A FERRAMENTA
  IF v_corretor AND NOT ('visita' = ANY (coalesce(t.ferramentas, '{}')))
     AND v_texto ~* nai_re_frase_de_visita() THEN
    v_texto := nai_tirar_frase(v_texto, nai_re_frase_de_visita());
    v_guarda := coalesce(v_guarda || '+', '') || 'visita_sem_ferramenta';
    PERFORM nai_avisar_tel(p_turno, NULL,
      'Tel, o corretor ' || coalesce(k.nome_completo, k.nome_whatsapp, k.telefone) ||
      ' (' || nai_fone_fmt(k.telefone) || ') falou de visita e eu não consegui resolver aqui. Ele disse: "' ||
      left(coalesce(p_escreveu, ''), 300) ||
      E'". Não respondi nada e parei de responder esse chat: quem responde é você. Para eu voltar: DEVOLVER ' || nai_fone_fmt(k.telefone) || '.',
      'visita_sem_ferramenta');
    PERFORM nai_parar_chat(k.id, 'visita que eu nao consegui tratar');
    PERFORM nai_anotar(p_turno, 11, 'visita_sem_ferramenta', 'parou', 'falou de visita sem chamar a ferramenta');
    RETURN jsonb_build_object('acao', 'parou', 'guarda', v_guarda);
  END IF;
  PERFORM nai_anotar(p_turno, 11, 'visita_sem_ferramenta', 'passou', NULL);

  -- 12 ------------------------------------------------------ CITOU O TEL
  IF t.papel IN ('corretor', 'proprietario', 'motoboy') AND v_texto ~* '\mtel\M' THEN
    v_texto := nai_tirar_frase(v_texto, '\mtel\M');
    v_guarda := coalesce(v_guarda || '+', '') || 'citou_o_tel_cortado';
    PERFORM nai_anotar(p_turno, 12, 'citou_o_tel', 'cortou', 'quem sobe para o Tel não conta para ninguém');
    IF v_texto = '' THEN
      RETURN jsonb_build_object('acao', 'silencio', 'guarda', v_guarda);
    END IF;
  ELSE
    PERFORM nai_anotar(p_turno, 12, 'citou_o_tel', 'passou', NULL);
  END IF;

  -- 13 --------------------------------------------- UMA PERGUNTA POR MENSAGEM
  IF v_corretor THEN
    v_novo := nai_uma_pergunta_da_sequencia(v_texto);
    IF v_novo IS NOT NULL THEN
      v_texto := v_novo;
      v_guarda := coalesce(v_guarda || '+', '') || 'sequencia_uma_pergunta';
      PERFORM nai_anotar(p_turno, 13, 'uma_pergunta_por_mensagem', 'mudou', 'juntou duas perguntas: saiu só a primeira');
    ELSE
      PERFORM nai_anotar(p_turno, 13, 'uma_pergunta_por_mensagem', 'passou', NULL);
    END IF;
  ELSE
    PERFORM nai_anotar(p_turno, 13, 'uma_pergunta_por_mensagem', 'passou', NULL);
  END IF;

  -- 14 ------------------------------------------------------------- MARKDOWN
  v_novo := nai_limpar_markdown(v_texto);
  PERFORM nai_anotar(p_turno, 14, 'markdown', CASE WHEN v_novo <> v_texto THEN 'mudou' ELSE 'passou' END, NULL);
  v_texto := v_novo;

  -- 14v ------------------------------------------ VISITA QUE NINGUEM PEDIU (141)
  -- Walter, 28/09 09:28: ele perguntou se o Acquarelle estava disponivel e,
  -- num turno so com "Locacao", ela respondeu "A visita do 5712 seria hoje, as
  -- 11h30?" -- sem ferramenta, sem visita nenhuma no banco. Visita com dia ou
  -- hora so sai de ferramenta ou de visita que existe.
  IF v_corretor AND v_texto ~* '\mvisita'
     AND v_texto ~* '(\m\d{1,2}\s*h\M|\m\d{1,2}h\d{2}|\m\d{1,2}:\d{2}|\mhoje\M|\mamanh)'
     AND NOT coalesce(nay_pede_visita(coalesce(p_escreveu, '')), false)
     AND NOT ('visita' = ANY (coalesce(t.ferramentas, '{}')))
     AND NOT EXISTS (SELECT 1 FROM nai_visita x WHERE x.corretor_id = ANY (nai_contato_irmaos(t.contato_id))
                      AND nai_visita_aberta(x.estado)) THEN
    PERFORM nai_anotar(p_turno, 14, 'visita_inventada', 'parou', left(v_texto, 200));
    RETURN jsonb_build_object('acao', 'silencio', 'guarda', 'visita_inventada');
  END IF;

  -- 14i ------------------------------------------ A FICHA DE IDENTIFICACAO (141)
  -- Tel, 28/09: "ela errou na identificacao do imovel, ela perguntou o codigo
  -- para o corretor, a confirmacao deve ser um modelo tambem, manda nome do
  -- imovel, endereco e preco de aluguel ou preco de venda e o codigo no final
  -- #0000". Quando ela pergunta QUAL imovel -- citando codigo, ou pedindo o
  -- codigo a ele -- a pergunta vira a ficha de cada candidato. Sem foto: as
  -- fotos saem quando ele confirmar.
  IF v_corretor AND position('📍' IN v_texto) = 0 AND v_texto ~ '\?' THEN
    IF v_texto ~* ('(\me\s+(esse|este)\M|\mseria\s+(esse|este|o)\M|voc[eê]\s+(quer|fala|diz)[^?]{0,50}\d{3,5}'
                   || '|qual\s+(deles|desses|dos)\M|de\s+qual\s+(im[oó]vel|deles)|mais\s+informa[cç][oõ]es\s+do\s+im[oó]vel)') THEN
      SELECT coalesce(array_agg(DISTINCT x::int), '{}') INTO v_cands
        FROM unnest(coalesce(nay_codigos_citados(v_texto), '{}'::text[])) x
       WHERE x ~ '^[0-9]{3,5}$' AND EXISTS (SELECT 1 FROM imoveis i WHERE i.codigo = x::int);
    END IF;
    -- O QUE ELE CITOU PELO NOME ENTRA JUNTO (Magna, 28/09: "o Rio negro" -> ela
    -- escolheu o Barra do Rio Negro, de venda; era o Conquista Rio Negro de
    -- 1.900). Com os candidatos do nome, a ficha pergunta "qual deles?" em vez
    -- de afirmar o que o modelo chutou. So os que estao no mercado.
    IF v_ident IS NOT TRUE AND (coalesce(array_length(v_cands, 1), 0) > 0 OR v_texto ~* 'c[oó]digo') THEN
      SELECT coalesce(array_agg(DISTINCT c ORDER BY c), '{}') INTO v_cands
        FROM unnest(v_cands || coalesce(nai_imovel_pelo_condominio(coalesce(p_escreveu, ''), k.telefone), '{}'::int[])) c
       WHERE nai_imovel_disponivel(c) AND NOT EXISTS (SELECT 1 FROM imoveis i WHERE i.codigo = c AND coalesce(i.e_parceiro, false));
    END IF;
    IF coalesce(array_length(v_cands, 1), 0) BETWEEN 1 AND 5 THEN
      SELECT string_agg(nai_ficha_imovel(c), E'\n\n' ORDER BY c) INTO v_fichas FROM unnest(v_cands) c;
      v_texto := CASE WHEN array_length(v_cands, 1) = 1 THEN 'É este imóvel?' ELSE 'Qual deles?' END
                 || E'\n\n' || v_fichas;
      v_ident := true;
      PERFORM nai_anotar(p_turno, 14, 'ficha_de_identificacao', 'mudou', array_to_string(v_cands, ', '));
    END IF;
  END IF;

  -- 14c ------------------------------------------ ELE CONFIRMOU A VISITA (141)
  -- A camada de baixo do "sim": visita esperando a confirmacao dele, ele
  -- respondeu que sim, e o modelo nao chamou pedir_visita. O banco confirma.
  IF v_corretor AND nai_e_sim_curto(coalesce(p_escreveu, ''))
     AND NOT ('visita' = ANY (coalesce(t.ferramentas, '{}')))
     AND EXISTS (SELECT 1 FROM nai_visita x WHERE x.corretor_id = ANY (nai_contato_irmaos(t.contato_id))
                  AND x.estado = 'confirmando') THEN
    PERFORM nai_visita_corretor_confirmou(x.id, p_turno)
       FROM nai_visita x WHERE x.corretor_id = ANY (nai_contato_irmaos(t.contato_id)) AND x.estado = 'confirmando';
    PERFORM nai_anotar(p_turno, 14, 'visita_confirmada_pelo_corretor', 'mudou', 'o banco confirmou');
    RETURN jsonb_build_object('acao', 'responder', 'guarda', 'visita_confirmada_pelo_corretor', 'codigo', NULL,
                              'texto', 'Certo! Vou ver esse horário com o proprietário e já te retorno.');
  END IF;

  -- 15 ------------------------------------------- DE QUAIS IMÓVEIS SÃO AS FOTOS
  SELECT coalesce(array_agg(DISTINCT x::int), '{}') INTO v_cods
    FROM jsonb_array_elements_text(coalesce(p_codigos, '[]'::jsonb)) x
   WHERE x ~ '^[0-9]{3,5}$' AND x::int > 0;
  IF t.papel IN ('corretor', 'tel') THEN
    -- AS FOTOS VAO SEMPRE (Tel, 16/09): falou de imovel, recebe informacao e
    -- foto na mesma resposta. Antes era preciso pedir "foto" com todas as
    -- letras, e quem escrevia "me encaminha o 5717" recebia so o card.
    v_gate := coalesce(nai_deve_mandar_fotos(t.contato_id, k.telefone, coalesce(p_escreveu, '')), false);
  END IF;
  IF v_gate AND coalesce(array_length(v_cods, 1), 0) = 0 THEN
    v_cods := array_remove(ARRAY[coalesce(v_alvo, nai_imovel_da_conversa(t.contato_id, p_escreveu))], NULL);
  END IF;
  -- SEM IMOVEL NAO HA FOTO. Com o portao sempre aberto, ele continuava "true"
  -- mesmo quando nao se sabe de qual imovel se fala -- e os passos seguintes
  -- tratavam a resposta como se fotos fossem sair. Medido: seis testes de
  -- formato e de sugestao de visita cairam por isso.
  IF v_gate AND coalesce(array_length(v_cods, 1), 0) = 0 THEN
    v_gate := false;
  END IF;

  -- IMOVEL INDISPONIVEL NAO LEVA FOTO (138): a resposta de situacao lista os
  -- disponiveis do mesmo condominio e pergunta qual interessa. As fotos saem
  -- quando ele escolher -- as do indisponivel, nunca (parede no gatilho).
  IF v_gate AND v_texto ~ '^Hmmm, vi aqui que o' THEN
    v_gate := false;
  END IF;
  -- 141: a ficha de identificacao espera ele confirmar; pedido de visita nao
  -- leva card nem foto na hora ("primeiro confirma se sabe qual e o imovel").
  IF v_gate AND (v_ident OR coalesce(nay_pede_visita(coalesce(p_escreveu, '')), false)) THEN
    v_gate := false;
  END IF;

  -- NAO REPETE (Tel, 16/09): "o Tel ja tinha pedido manualmente para ela mandar
  -- as fotos do arezzo, mas ela foi la e mandou novamente". O imovel cujas
  -- fotos ja sairam para esta pessoa hoje sai da lista -- as informacoes
  -- continuam indo, so as fotos e que nao se repetem.
  -- ...A NAO SER QUE ELE PECA (Tel, 22/09: "manda de novo conforme
  -- solicitado"). A trava vale para foto que ele nao pediu.
  IF v_gate AND coalesce(array_length(v_cods, 1), 0) >= 1
     AND NOT nai_pede_foto(coalesce(p_escreveu, '')) THEN
    SELECT coalesce(array_agg(c), '{}') INTO v_cods
      FROM unnest(v_cods) c
     WHERE NOT nai_fotos_ja_mandadas(t.contato_id, c, 24);
    IF coalesce(array_length(v_cods, 1), 0) = 0 THEN
      v_gate := false;
    END IF;
  END IF;

  PERFORM nai_anotar(p_turno, 15, 'portao_de_fotos', CASE WHEN v_gate THEN 'mudou' ELSE 'passou' END,
                     CASE WHEN v_gate THEN 'ele pediu foto; imóveis: ' || coalesce(array_to_string(v_cods, ', '), 'nenhum')
                          ELSE 'ele não pediu foto' END);

  -- 16 ------------------------------- NEGOU FOTO QUE EXISTE / PROMETEU A QUE NÃO
  IF v_gate AND v_texto ~* nai_re_nega_foto() AND coalesce(array_length(v_cods, 1), 0) >= 1 THEN
    SELECT count(*) INTO v_n FROM imovel_fotos WHERE codigo = v_cods[1];
    IF v_n > 0 THEN
      v_texto := regexp_replace(v_texto, '[^.?!\n]*' || nai_re_nega_foto() || '[^.?!\n]*[.?!]?', 'segue as fotos', 'i');
      v_guarda := 'negacao_corrigida';
      PERFORM nai_anotar(p_turno, 16, 'negou_foto_que_existe', 'mudou', 'a foto existe: negativa trocada');
    END IF;
  END IF;
  IF v_gate THEN
    SELECT coalesce(array_agg(c), '{}') INTO v_sem FROM unnest(v_cods) c
     WHERE NOT EXISTS (SELECT 1 FROM imovel_fotos fx WHERE fx.codigo = c);
    IF coalesce(array_length(v_sem, 1), 0) >= 1 THEN
      -- 14/09: antes esta conferência TROCAVA a frase por "as fotos desse eu vou
      -- confirmar com o Tel e já te mando" -- promessa de retorno, que o fluxo
      -- v17 proíbe ("não existe vou ver e te aviso"). Agora a frase de foto
      -- (promessa ou negativa) sai fora e o Tel é avisado; o corretor não recebe
      -- promessa nenhuma.
      v_texto := nai_tirar_frase(v_texto, nai_re_promete_foto() || '|' || nai_re_nega_foto());
      PERFORM nai_avisar_tel(p_turno, NULL,
        'Tel, o corretor ' || coalesce(k.nome_whatsapp, k.telefone) || ' pediu fotos do ' ||
        array_to_string(v_sem, ', ') || ' e não achei foto nem no banco nem no anúncio do site. Pode me mandar?',
        'foto_inexistente');
      v_guarda := coalesce(v_guarda || '+', '') || 'promessa_sem_foto';
      PERFORM nai_anotar(p_turno, 17, 'foto_que_nao_existe', 'mudou', 'imóvel sem foto: o Tel foi avisado');
    ELSE
      PERFORM nai_anotar(p_turno, 17, 'foto_que_nao_existe', 'passou', NULL);
    END IF;
  ELSE
    PERFORM nai_anotar(p_turno, 17, 'foto_que_nao_existe', 'passou', NULL);
  END IF;

  RETURN jsonb_build_object(
    'acao', 'responder',
    'texto', v_texto,
    'guarda', v_guarda,
    'alvo', v_alvo,
    'cods', to_jsonb(v_cods),
    'gate', v_gate,
    'sugerir', v_sugerir);
END;
$function$;

CREATE OR REPLACE FUNCTION public.nai_pedir_visita(p_turno bigint, p_codigo text, p_quando text, p_qualificado text)
 RETURNS TABLE(texto_pronto text, instrucao_para_voce text)
 LANGUAGE plpgsql
AS $function$
DECLARE
  t        nai_turno;
  k        nai_contato;
  i        imoveis;
  v_cod    int := NULLIF(regexp_replace(coalesce(p_codigo, ''), '\D', '', 'g'), '')::int;
  v_q      timestamptz := nai_ler_quando(p_quando);
  v_conf   text;
  v_v      nai_visita;
  v_id     bigint;
  v_dono   record;
  v_moto   record;
  v_urg    boolean;
  d        record;
  v_min_h  int := nai_cfg_int('antecedencia_minima_horas', 2);
BEGIN
  PERFORM nai_usou_ferramenta(p_turno, 'visita');
  SELECT * INTO t FROM nai_turno WHERE id = p_turno;
  IF t.id IS NULL OR t.papel <> 'corretor' THEN
    RETURN QUERY SELECT NULL::text, 'pedir_visita e so para o corretor. nao chame de novo neste turno.'::text; RETURN;
  END IF;
  SELECT * INTO k FROM nai_contato WHERE id = t.contato_id;

  IF v_cod IS NULL THEN
    RETURN QUERY SELECT NULL::text, 'voce ainda nao sabe QUAL imovel. pergunte ao corretor (ou mostre a lista com imovel_do_disparo) antes de chamar pedir_visita.'::text; RETURN;
  END IF;

  -- O codigo NAO pode vir da cabeca do modelo: ele escreveu, ou foi o unico
  -- card que mandamos para ele, ou ja existe visita aberta desse imovel.
  v_conf := nay_codigo_confirmado(k.telefone, v_cod::text, 72);
  IF v_conf = 'nao' AND NOT EXISTS (SELECT 1 FROM nai_visita x WHERE x.corretor_id = k.id AND x.codigo = v_cod AND nai_visita_aberta(x.estado)) THEN
    RETURN QUERY SELECT NULL::text,
      ('o codigo ' || v_cod || ' nao foi dito por ele nesta conversa. NAO suponha: pergunte de qual imovel ele fala, confirmando o nome ou o codigo, e so depois chame pedir_visita.')::text;
    RETURN;
  END IF;

  SELECT * INTO i FROM imoveis WHERE codigo = v_cod;
  IF i.codigo IS NULL THEN
    RETURN QUERY SELECT ('Não achei nenhum imóvel com o código ' || v_cod || '. Confere pra mim?')::text, NULL::text; RETURN;
  END IF;
  IF coalesce(i.e_parceiro, false) THEN
    RETURN QUERY SELECT NULL::text, 'esse imovel e de PARCERIA, a visita nao e com a gente: chame escalar_ao_tel com o pedido de visita e diga o texto_pronto que vier.'::text; RETURN;
  END IF;
  IF NOT nay_esta_no_mercado(i.disponivel, i.bloqueado, i.publicado_no_site) THEN
    RETURN QUERY SELECT ('Esse imóvel saiu do mercado' || coalesce(', ' || nai_vocativo(coalesce(k.nome_completo, k.nome_whatsapp)), '') || '. Quer que eu veja outro parecido pro seu cliente?')::text, NULL::text; RETURN;
  END IF;
  -- VENDA SEGUE O MESMO FLUXO (Tel, 16/09): "confirmado, e para seguir o fluxo
  -- de agendar visita quando for venda tambem".
  --
  -- Aqui a visita de venda era desviada para o Tel. O resto desta funcao nunca
  -- dependeu de aluguel, e a mensagem que vai ao proprietario tambem nao fala
  -- em alugar -- ela pergunta do horario. Entao a visita de venda anda pelo
  -- mesmo caminho: proprietario, acompanhante, confirmacao.
  --
  -- Medido antes de abrir: dos imoveis no mercado e nossos, 258 sao de venda e
  -- 207 deles tem telefone do dono no cadastro. E cobertura melhor do que a da
  -- locacao (14 de 39), entao o fluxo tem com quem falar.
  --
  -- O IMOVEL DE PARCERIA continua subindo ao Tel, logo acima: aquele nao e
  -- nosso, e a visita nao e com a gente.

  IF v_q IS NULL THEN
    RETURN QUERY SELECT 'Claro! Me informa o dia e o horário que fica bom pro seu cliente, ok?'::text,
      'ele nao disse dia e hora (ou nao deu para entender). quando ele disser, chame pedir_visita de novo com o horario no formato AAAA-MM-DD HH:MM.'::text;
    RETURN;
  END IF;
  -- v_regra: ja passou
  IF v_q <= now() + interval '10 minutes' THEN
    RETURN QUERY SELECT 'Esse horário já passou. Qual outro horário fica bom pro seu cliente?'::text,
      'quando ele disser outro horario, chame pedir_visita de novo.'::text;
    RETURN;
  END IF;
  IF v_q > now() + interval '45 days' THEN
    RETURN QUERY SELECT NULL::text, 'o horario ficou para daqui a mais de 45 dias: confirme a data com ele antes de chamar de novo.'::text; RETURN;
  END IF;

  -- SEM pergunta de renda (Tel, 12/09): isso vinha da regra 2 da tabela
  -- `regras` (14/08, da Nay antiga) e NAO existe em card nenhum do fluxo do
  -- site. O fluxo e a lista completa do que ela faz com o corretor. O
  -- parametro p_qualificado continua sendo aceito (para nao quebrar chamada
  -- antiga), mas nao segura mais nada.

  -- Ja existe visita aberta deste imovel com este corretor?
  SELECT * INTO v_v FROM nai_visita x WHERE x.corretor_id = k.id AND x.codigo = v_cod AND nai_visita_aberta(x.estado);
  -- 141: A VISITA ESPERANDO A CONFIRMACAO DELE. Mesmo horario = ele confirmou;
  -- horario novo = troca e manda o modelo de confirmacao de novo.
  IF v_v.id IS NOT NULL AND v_v.estado = 'confirmando' THEN
    IF abs(extract(epoch FROM (v_v.quando - v_q))) < 60 THEN
      PERFORM nai_visita_corretor_confirmou(v_v.id, p_turno);
      RETURN QUERY SELECT 'Certo! Vou ver esse horário com o proprietário e já te retorno.'::text,
        'ele confirmou a visita. mande o texto_pronto exatamente e nada mais.'::text;
      RETURN;
    END IF;
    IF v_q < now() + make_interval(hours => v_min_h) THEN
      UPDATE nai_visita SET quando = v_q, estado = 'coletando', urgente = true, atualizado_em = now() WHERE id = v_v.id;
      v_id := v_v.id;
      -- segue para o caminho da urgente, la embaixo
    ELSE
      UPDATE nai_visita SET quando = v_q, atualizado_em = now() WHERE id = v_v.id;
      PERFORM nai_evento(v_v.id, 'horario_trocado_antes_de_confirmar', nai_hora_exata(v_q));
      RETURN QUERY SELECT nai_texto_confirmar_visita(v_v.id),
        ('mande o texto_pronto EXATAMENTE como veio. Quando ele confirmar (sim, isso, correto, pode), chame pedir_visita '
         || 'de novo com codigo ' || v_cod || ' e quando ' || to_char(v_q AT TIME ZONE 'America/Manaus', 'YYYY-MM-DD HH24:MI') || '.')::text;
      RETURN;
    END IF;
  END IF;
  IF v_v.id IS NOT NULL AND v_id IS NULL THEN
    RETURN QUERY SELECT NULL::text,
      ('ja existe visita em andamento desse imovel com ele (' || nai_status_humano(v_v) || ', ' ||
       coalesce(nai_quando_humano(v_v.quando), 'sem horario') || '). se ele quer OUTRO horario, chame mudar_horario_da_visita; se mandou nome/CPF, chame guardar_dados_da_visita; nao chame pedir_visita.')::text;
    RETURN;
  END IF;

  v_urg := v_q < now() + make_interval(hours => v_min_h);
  SELECT * INTO v_dono FROM nai_proprietario_do_imovel(v_cod);
  SELECT * INTO v_moto FROM nai_motoboy();

  IF v_id IS NULL THEN
    INSERT INTO nai_visita (codigo, corretor_id, quando, estado, aguardando, urgente, qualificado,
                            proprietario_cadastro, proprietario_nome, motoboy_id, proximo_lembrete_dados_em)
         VALUES (v_cod, k.id, v_q, CASE WHEN v_urg THEN 'coletando' ELSE 'confirmando' END, 'corretor', v_urg, NULL,
                 v_dono.cadastro_id, v_dono.nome, v_moto.contato_id, NULL)
    RETURNING id INTO v_id;
    PERFORM nai_evento(v_id, 'pedida', 'horario ' || nai_hora_exata(v_q));
  END IF;

  -- A CONFIRMACAO EM TEXTO (Tel, 28/09): o modelo dele, preenchido. So depois
  -- do "sim" do corretor a visita vai para a Rayssa -- e so com o SIM dela, e
  -- as informacoes completas, a Nay fala com o proprietario.
  IF NOT v_urg THEN
    RETURN QUERY SELECT nai_texto_confirmar_visita(v_id),
      ('mande o texto_pronto EXATAMENTE como veio, sem juntar nada. Quando ele confirmar (sim, isso, correto, pode), '
       || 'chame pedir_visita de novo com codigo ' || v_cod || ' e quando '
       || to_char(v_q AT TIME ZONE 'America/Manaus', 'YYYY-MM-DD HH24:MI')
       || '. Para varias visitas, uma chamada por imovel.')::text;
    RETURN;
  END IF;

  -- VISITA URGENTE (Tel, 12/09): menos de 3 horas nao passa pela IA. Sobe
  -- para o Tel e a Nay PARA -- e desde 13/09 para o chat inteiro do corretor.
  IF v_urg THEN
    UPDATE nai_visita SET estado = 'com_tel', aguardando = 'tel', urgente = true,
                          proximo_lembrete_dados_em = NULL, atualizado_em = now()
     WHERE id = v_id;
    PERFORM nai_evento(v_id, 'urgente_com_tel', nai_hora_exata(v_q));
    PERFORM nai_avisar_tel(p_turno, v_id,
      'Tel, VISITA URGENTE (menos de ' || v_min_h || 'h): ' || nai_ref_imovel(v_cod) || ', ' || nai_hora_exata(v_q) ||
      E'.\nCorretor: ' || coalesce(k.nome_completo, k.nome_whatsapp, '') || ' ' || nai_fone_fmt(k.telefone) ||
      E'\nEu parei aqui: não falei com o proprietário nem com o ' || nai_acompanhante() || ', e parei de responder esse corretor. A visita #' || v_id || ' é sua.' ||
      E'\nSe quiser que eu siga, responda VISITA ' || v_id || ' OK.', 'urgente');
    PERFORM nai_parar_chat(k.id, 'visita #' || v_id || ': urgente (menos de ' || v_min_h || 'h)');
    RETURN QUERY SELECT NULL::text,
      'visita URGENTE: foi para o Tel e voce PAROU neste chat. responda exatamente SILENCIO.'::text;
    RETURN;
  END IF;

  -- FLUXO v17 (Tel, 13/09): o horario vai DIRETO ao proprietario. Os dados do
  -- corretor e do visitante so sao pedidos depois da "Visita confirmada", e
  -- nesta hora o corretor nao recebe nada ("Nada, fica calada").
  PERFORM nai_pedir_ao_proprietario(v_id, p_turno);
  RETURN QUERY SELECT NULL::text,
    'o pedido foi ao proprietario (ou ao Tel). o corretor NAO recebe nada agora: responda exatamente SILENCIO. NAO peca dados e NAO diga que a visita esta confirmada.'::text;
END;
$function$;

CREATE OR REPLACE FUNCTION public.nai_pedir_ao_proprietario(p_visita bigint, p_turno bigint)
 RETURNS text
 LANGUAGE plpgsql
AS $function$
DECLARE
  v       nai_visita;
  c       nai_contato;
  dono    record;
  v_prop  bigint;
  v_voc   text;
  v_texto text;
BEGIN
  SELECT * INTO v FROM nai_visita WHERE id = p_visita FOR UPDATE;
  SELECT * INTO c FROM nai_contato WHERE id = v.corretor_id;
  SELECT * INTO dono FROM nai_proprietario_do_imovel(v.codigo);
  -- 141: o telefone que a Rayssa mandou (TELEFONE <n> <numero>) vale mais que o cadastro.
  IF v.prop_telefone_manual IS NOT NULL THEN
    dono.telefone := v.prop_telefone_manual;
    dono.motivo   := NULL;
    -- sem nome no cadastro, fica sem vocativo ("Bom dia!", nunca "Bom dia, proprietario!")
  END IF;
  IF dono.motivo IS NULL THEN
    v_prop := nai_contato_do_cadastro(dono.telefone, dono.nome);
  END IF;

  -- Sem telefone, cadastro dizendo "tratar com", dois donos -- ou o
  -- "proprietario" e o proprio corretor: o Tel resolve.
  IF v_prop IS NULL OR v_prop = v.corretor_id THEN
    UPDATE nai_visita SET estado = 'com_tel', aguardando = 'tel', atualizado_em = now() WHERE id = v.id;
    PERFORM nai_evento(v.id, 'proprietario_sem_contato', coalesce(dono.motivo, 'mesmo_contato'));
    PERFORM nai_avisar_tel(p_turno, v.id,
      'Tel, pedido de visita no ' || nai_ref_imovel(v.codigo) || ', ' || nai_hora_exata(v.quando) || '.' ||
      E'\nCorretor: ' || coalesce(c.nome_completo, c.nome_whatsapp, '') || ' (' || nai_fone_fmt(c.telefone) || ')' ||
      E'\nNão consigo falar com o proprietário (' ||
      CASE dono.motivo WHEN 'sem_telefone' THEN 'sem telefone no cadastro'
                       WHEN 'tratar_com_outra_pessoa' THEN 'o cadastro diz: ' || coalesce(dono.nome, '')
                       WHEN 'dois_donos' THEN 'o imóvel tem dois proprietários no cadastro'
                       WHEN 'sem_cadastro' THEN 'imóvel sem proprietário cadastrado'
                       ELSE 'o telefone do proprietário é o do próprio corretor' END || ').' ||
      E'\nParei de responder esse corretor até você responder.\nQuando resolver, me responda:\nVISITA ' || v.id || E' OK  (proprietário confirmou)\nVISITA ' || v.id ||
      E' HORARIO 16h  (ele pediu outro horário)\nVISITA ' || v.id || ' CANCELA',
      'sem_proprietario');
    PERFORM nai_parar_chat(v.corretor_id, 'visita #' || v.id || ': sem contato do proprietario');
    RETURN 'com_tel';
  END IF;

  v_voc := nai_vocativo(dono.nome);
  -- Card p_solicita, humanizado como o Tel pediu ("hoje a tarde", sem data numerica).
  -- A APRESENTACAO (Tel, 15/09), so na primeira vez com este proprietario: ele
  -- ja fala com a Imob Easy em outro numero, e sem isto a mensagem chega de um
  -- desconhecido pedindo para entrar no imovel dele.
  v_texto := nai_apresentacao_prop(v_prop) ||
             nai_saudacao() || coalesce(', ' || v_voc, '') || '! Tudo bem? Aqui é a Nay, da Imob Easy. ' ||
             'Temos um pedido de visita ' || nai_ref_imovel_prop(v.codigo) ||
             ' para ' || nai_quando_humano(v.quando) || '. Tem como receber a visita nesse horário?';

  UPDATE nai_visita SET proprietario_id = v_prop, proprietario_cadastro = dono.cadastro_id,
                        proprietario_nome = dono.nome, estado = 'aguardando_proprietario', aguardando = 'proprietario',
                        ult_msg_prop_em = now(), reenvios_prop = 0, atualizado_em = now()
   WHERE id = v.id;
  PERFORM nai_enfileirar_texto(p_turno, v.id, v_prop, 'proprietario', v_texto, 'p_solicita', 500);
  RETURN 'pedido';
END;
$function$;

CREATE OR REPLACE FUNCTION public.nai_confirmar_visita(p_visita bigint, p_turno bigint)
 RETURNS void
 LANGUAGE plpgsql
AS $function$
DECLARE v nai_visita; c nai_contato; m record; v_nome text; d record; v_pede text;
BEGIN
  SELECT * INTO v FROM nai_visita WHERE id = p_visita FOR UPDATE;
  SELECT * INTO c FROM nai_contato WHERE id = v.corretor_id;
  SELECT * INTO m FROM nai_motoboy();
  v_nome := nai_vocativo(coalesce(c.nome_completo, c.nome_whatsapp));
  UPDATE nai_visita SET estado = 'confirmada', aguardando = NULL, confirmada_em = now(), atualizado_em = now()
   WHERE id = v.id;
  PERFORM nai_evento(v.id, 'confirmada', NULL);
  PERFORM nai_enfileirar_texto(p_turno, v.id, v.corretor_id, 'corretor',
    'Visita confirmada' || coalesce(', ' || v_nome, '') || '! ' || initcap(left(nai_quando_humano(v.quando), 1)) ||
    substr(nai_quando_humano(v.quando), 2) || ', no ' || nai_ref_imovel(v.codigo) || '.' ||
    E'\nQuem vai acompanhar sua visita é o ' || nai_acompanhante() || '' || coalesce(', ' || nai_fone_fmt(m.telefone), '') || '.' ||
    CASE WHEN nai_linha_acesso_corretor(v.acesso) <> '' THEN E'\n' || nai_linha_acesso_corretor(v.acesso) ELSE '' END,
    'visita_confirmada', 400);
  -- Fluxo v17 (Tel, 13/09): SO AGORA os dados. Cards "Checa os dados do
  -- corretor" -> CORRETOR CONHECIDO / CORRETOR NOVO, sem o "vou confirmar aqui
  -- a visita" (ela ja esta confirmada) -- "tira o vou confirmar e pede claramente".
  -- TODOS OS DADOS AO TEL (Tel, 28/09): "enviar confirmacao com todos os ativos
  -- para o tel".
  PERFORM nai_avisar_tel(p_turno, v.id, nai_texto_visita_completa(v.id, 'Tel, visita CONFIRMADA'), 'visita_confirmada_tel');
  SELECT * INTO d FROM nai_dados_corretor(c.id);
  IF NOT coalesce(d.completo, false) THEN
    v_pede := 'Me passa o ' || nai_lista_pt(ARRAY_REMOVE(ARRAY[
      CASE WHEN d.nome_completo IS NULL THEN 'seu nome completo' END,
      CASE WHEN d.cpf IS NULL THEN 'o CPF' END,
      CASE WHEN d.creci IS NULL THEN 'o CRECI' END], NULL)) || '?';
  ELSIF v.visitante_nome IS NULL OR v.visitante_cpf IS NULL THEN
    v_pede := 'Me passa o nome completo e o CPF do visitante?';
  END IF;
  IF v_pede IS NOT NULL THEN
    PERFORM nai_enfileirar_texto(p_turno, v.id, v.corretor_id, 'corretor', v_pede, 'pedir_dados', 401);
    UPDATE nai_visita SET lembretes_dados = 0,
           proximo_lembrete_dados_em = now() + make_interval(mins => nai_cfg_int('dados_primeiro_lembrete_min', 3))
     WHERE id = v.id;
  END IF;
END;
$function$;

CREATE OR REPLACE FUNCTION public.nai_agenda_tick()
 RETURNS integer
 LANGUAGE plpgsql
AS $function$
DECLARE
  v        nai_visita;
  c        nai_contato;
  n        int := 0;
  v_nome   text;
  v_falta  text[];
  d        record;
  v_reenv  interval := make_interval(mins => nai_cfg_int('reenvio_proprietario_min', 30));
  v_rmoto  interval := make_interval(mins => nai_cfg_int('reenvio_motoboy_min', 30));
  v_max    int := nai_cfg_int('reenvios_proprietario_max', 3);
  v_tel_h  interval := make_interval(hours => nai_cfg_int('aviso_tel_horas_antes', 2));
  v_lemb   interval := make_interval(mins => nai_cfg_int('lembrete_corretor_min', 60));
  v_moto   interval := make_interval(mins => nai_cfg_int('aviso_motoboy_min', 30));
  v_pos    interval := make_interval(mins => nai_cfg_int('pos_visita_min', 60));
  v_ini    timestamptz;
BEGIN
  UPDATE nai_config SET valor = to_char(now() AT TIME ZONE 'America/Manaus', 'YYYY-MM-DD HH24:MI:SS'), atualizado_em = now()
   WHERE chave = '_agenda_rodou_em';
  IF NOT FOUND THEN
    INSERT INTO nai_config (chave, valor, descricao)
    VALUES ('_agenda_rodou_em', to_char(now() AT TIME ZONE 'America/Manaus', 'YYYY-MM-DD HH24:MI:SS'),
            'Carimbo: a ultima vez que a agenda da NAI rodou (so leitura).')
    ON CONFLICT (chave) DO NOTHING;
  END IF;
  IF nai_cfg('modo', 'desligado') NOT IN ('teste', 'todos') THEN RETURN 0; END IF;

  FOR v IN
    SELECT * FROM nai_visita
     WHERE estado NOT IN ('encerrada', 'cancelada', 'expirada')
     ORDER BY quando
     FOR UPDATE SKIP LOCKED
  LOOP
    SELECT * INTO c FROM nai_contato WHERE id = v.corretor_id;
    v_nome := nai_vocativo(coalesce(c.nome_completo, c.nome_whatsapp));

    -- 141: ELE NAO CONFIRMOU a visita em 12h (ou ela ficou em cima): vence.
    IF v.estado = 'confirmando' AND (v.criado_em < now() - interval '12 hours' OR v.quando < now() + interval '30 minutes') THEN
      UPDATE nai_visita SET estado = 'expirada', aguardando = NULL, encerrada_em = now(), atualizado_em = now() WHERE id = v.id;
      PERFORM nai_evento(v.id, 'expirou_sem_confirmar', NULL);
      n := n + 1;
      CONTINUE;
    END IF;
    -- 141: A RAYSSA NAO RESPONDEU. Perto da hora vira do Tel; antes disso, lembra ela.
    IF v.estado = 'aguardando_rayssa' THEN
      IF v.quando < now() + make_interval(hours => nai_cfg_int('antecedencia_minima_horas', 2)) THEN
        UPDATE nai_visita SET estado = 'com_tel', aguardando = 'tel', atualizado_em = now() WHERE id = v.id;
        PERFORM nai_evento(v.id, 'aprovacao_sem_resposta', NULL);
        PERFORM nai_avisar_tel(NULL, v.id, nai_texto_visita_completa(v.id, 'Tel, a ' || nai_cfg('aprovador_visita_nome', 'Rayssa')
          || ' não confirmou a tempo e a visita ficou em cima da hora -- ela é sua. Parei o chat do corretor')
          || E'\nQuando resolver: VISITA ' || v.id || ' OK / VISITA ' || v.id || ' CANCELA', 'aprovacao_sem_resposta');
        PERFORM nai_parar_chat(v.corretor_id, 'visita #' || v.id || ': sem aprovação a tempo');
        n := n + 1;
      ELSIF v.rayssa_msg_em < now() - make_interval(mins => nai_cfg_int('aprovacao_lembrete_min', 30))
            AND v.rayssa_lembretes < 2 AND nai_aprovador_contato() IS NOT NULL THEN
        PERFORM nai_enfileirar_texto(NULL, v.id, nai_aprovador_contato(), 'equipe',
          nai_cfg('aprovador_visita_nome', 'Rayssa') || ', a visita #' || v.id || ' ainda espera o seu SIM '
          || '(' || nai_ref_imovel(v.codigo) || ', ' || nai_hora_exata(v.quando) || '). Responda SIM ' || v.id
          || ' ou NÃO ' || v.id || '.', 'aprovar_visita_lembrete', 451);
        UPDATE nai_visita SET rayssa_msg_em = now(), rayssa_lembretes = rayssa_lembretes + 1 WHERE id = v.id;
        n := n + 1;
      END IF;
      CONTINUE;
    END IF;

    -- ---------------------------------------------- passou da hora sem fechar
    IF v.estado IN ('coletando', 'aguardando_proprietario', 'negociando', 'aguardando_acesso', 'aguardando_motoboy', 'com_tel')
       AND v.quando IS NOT NULL AND now() >= v.quando THEN
      UPDATE nai_visita SET estado = 'expirada', aguardando = NULL, senha = NULL, encerrada_em = now(), atualizado_em = now()
       WHERE id = v.id;
      PERFORM nai_evento(v.id, 'expirada', v.estado);
      -- Visita que estava COM O TEL (urgente, por exemplo) nao leva "nao
      -- consegui fechar" ao corretor: quem estava tratando era ele.
      IF v.estado <> 'com_tel' THEN
        PERFORM nai_enfileirar_texto(NULL, v.id, v.corretor_id, 'corretor',
          coalesce(v_nome || ', ', '') || 'não consegui fechar a visita de ' || nai_quando_humano(v.quando) || ' a tempo, desculpa. Quer tentar outro horário?',
          'expirada', 1);
      END IF;
      PERFORM nai_avisar_tel(NULL, v.id, 'Tel, a visita #' || v.id || ' (' || nai_ref_imovel(v.codigo) || ', ' ||
        nai_hora_exata(v.quando) || ') chegou no horário sem fechar (estava: ' || v.estado || '). Avisei o corretor.', 'expirada');
      n := n + 1;
      CONTINUE;
    END IF;

    -- ---------------------------------------------- faltam dados (coletando)
    -- fluxo v17: os dados so sao pedidos depois da confirmacao (card Revisao).
    IF v.estado = 'confirmada' AND v.proximo_lembrete_dados_em IS NOT NULL AND now() >= v.proximo_lembrete_dados_em THEN
      SELECT * INTO d FROM nai_dados_corretor(v.corretor_id);
      v_falta := ARRAY_REMOVE(ARRAY[
        CASE WHEN d.nome_completo IS NULL THEN 'seu nome completo' END,
        CASE WHEN d.cpf IS NULL THEN 'seu CPF' END,
        CASE WHEN d.creci IS NULL THEN 'seu CRECI' END,
        CASE WHEN v.visitante_nome IS NULL THEN 'o nome completo do visitante' END,
        CASE WHEN v.visitante_cpf IS NULL THEN 'o CPF do visitante' END], NULL);
      IF coalesce(array_length(v_falta, 1), 0) = 0 THEN
        UPDATE nai_visita SET proximo_lembrete_dados_em = NULL WHERE id = v.id;
      ELSIF v.lembretes_dados >= nai_cfg_int('dados_lembretes_max', 3) OR now() >= v.quando - interval '1 hour' THEN
        UPDATE nai_visita SET proximo_lembrete_dados_em = NULL, aviso_tel_dados_em = now() WHERE id = v.id;
        IF v.aviso_tel_dados_em IS NULL THEN
          PERFORM nai_avisar_tel(NULL, v.id, 'Tel, o corretor ' || coalesce(c.nome_completo, c.nome_whatsapp, '') || ' (' ||
            nai_fone_fmt(c.telefone) || ') pediu visita no ' || nai_ref_imovel(v.codigo) || ', ' || nai_hora_exata(v.quando) ||
            ', e não mandou: ' || array_to_string(v_falta, ', ') || '. Parei de cobrar. Visita #' || v.id || '.', 'dados_sem_resposta');
        END IF;
      ELSE
        PERFORM nai_enfileirar_texto(NULL, v.id, v.corretor_id, 'corretor',
          'Só falta ' || nai_lista_pt(v_falta) || ' pra eu fechar a visita', 'dados_falta', 1);
        UPDATE nai_visita SET lembretes_dados = lembretes_dados + 1,
                              proximo_lembrete_dados_em = now() + nai_intervalo_dados(v.quando)
         WHERE id = v.id;
      END IF;
      n := n + 1;
    END IF;

    -- ---------------------------------------------- proprietario sem responder
    IF v.aguardando = 'proprietario' AND v.proprietario_id IS NOT NULL AND v.ult_msg_prop_em IS NOT NULL
       AND (v.ult_resp_prop_em IS NULL OR v.ult_resp_prop_em < v.ult_msg_prop_em) THEN

      -- Hora marcada pelo Tel (VISITA <id> AVISA 10h).
      IF v.proximo_aviso_prop_em IS NOT NULL AND now() >= v.proximo_aviso_prop_em THEN
        PERFORM nai_enfileirar_texto(NULL, v.id, v.proprietario_id, 'proprietario',
          'Oi' || coalesce(', ' || nai_vocativo(v.proprietario_nome), '') || ', passando de novo sobre a visita de ' ||
          nai_quando_humano(v.quando) || '. Consegue me confirmar?', 'p_lembrete_tel', 1);
        UPDATE nai_visita SET proximo_aviso_prop_em = NULL, aviso_tel_em = NULL, ult_msg_prop_em = now(),
                              reenvios_prop = reenvios_prop + 1 WHERE id = v.id;
        n := n + 1;
        CONTINUE;
      END IF;

      IF now() >= v.ult_msg_prop_em + v_reenv THEN
        IF v.reenvios_prop < v_max AND v.proximo_aviso_prop_em IS NULL THEN
          PERFORM nai_enfileirar_texto(NULL, v.id, v.proprietario_id, 'proprietario',
            'Oi' || coalesce(', ' || nai_vocativo(v.proprietario_nome), '') || ', passando de novo sobre a visita de ' ||
            nai_quando_humano(v.quando) || '. Consegue me confirmar?', 'p_lembrete', 1);
          UPDATE nai_visita SET reenvios_prop = reenvios_prop + 1, ult_msg_prop_em = now() WHERE id = v.id;
          n := n + 1;
        END IF;
        -- Depois do primeiro reenvio sem resposta, o corretor sabe da demora.
        IF v.reenvios_prop >= 1 AND v.aviso_demora_em IS NULL THEN
          PERFORM nai_enfileirar_texto(NULL, v.id, v.corretor_id, 'corretor',
            coalesce(v_nome || ', ', '') || 'ainda estou aguardando o retorno do proprietário. Assim que ele responder eu te aviso, tá?',
            'p_avisa', 2);   -- card p_avisa: aqui quem esta devendo e o proprietario, nao o Tel
          UPDATE nai_visita SET aviso_demora_em = now() WHERE id = v.id;
          n := n + 1;
        END IF;
      END IF;

      -- Faltando 2h e ainda sem confirmacao: card "Acionar o Tel" e FIM (Tel,
      -- 13/09). A visita fica com ele e a Nay para o chat do corretor E o do
      -- proprietario ("chama o tel para ambos"). O VISITA N AVISA 10h dele
      -- devolve os dois chats e agenda o proximo aviso. Uma vez so por visita.
      IF now() >= v.quando - v_tel_h AND v.proximo_aviso_prop_em IS NULL
         AND NOT EXISTS (SELECT 1 FROM nai_visita_evento e WHERE e.visita_id = v.id AND e.tipo = 'tel_2h') THEN
        PERFORM nai_avisar_tel(NULL, v.id, 'Tel, a visita #' || v.id || ' no ' || nai_ref_imovel(v.codigo) || ' é ' ||
          nai_hora_exata(v.quando) || ' e o proprietário ainda não confirmou.' ||
          E'\nQue horas eu mando o próximo aviso ao proprietário? Responda VISITA ' || v.id || ' AVISA 10h — se ele não responder em ' ||
          nai_cfg_int('reenvio_proprietario_min', 30) || ' minutos, te aviso para ligar. Ou VISITA ' || v.id || ' OK se já confirmou.' ||
          E'\nParei com o corretor e com o proprietário até você responder.', 'p_tel_2h');
        UPDATE nai_visita SET aviso_tel_em = now(), estado = 'com_tel', aguardando = 'tel', atualizado_em = now() WHERE id = v.id;
        PERFORM nai_evento(v.id, 'tel_2h', NULL);
        PERFORM nai_parar_chat(v.corretor_id, 'visita #' || v.id || ': proprietario sem resposta 2h antes');
        PERFORM nai_parar_chat(v.proprietario_id, 'visita #' || v.id || ': proprietario sem resposta 2h antes');
        n := n + 1;
        CONTINUE;
      END IF;
    END IF;

    -- Depois do aviso marcado pelo Tel, sem resposta: "pode ligar".
    IF v.aguardando = 'proprietario' AND v.reenvios_prop > 0 AND v.aviso_tel_em IS NULL AND v.proximo_aviso_prop_em IS NULL
       AND v.ult_msg_prop_em IS NOT NULL AND now() >= v.ult_msg_prop_em + v_reenv
       AND (v.ult_resp_prop_em IS NULL OR v.ult_resp_prop_em < v.ult_msg_prop_em)
       AND EXISTS (SELECT 1 FROM nai_visita_evento e WHERE e.visita_id = v.id AND e.tipo = 'mensagem_proprietario' AND e.detalhe = 'p_lembrete_tel'
                    AND e.quando >= v.ult_msg_prop_em - interval '1 minute') THEN
      PERFORM nai_avisar_tel(NULL, v.id, 'Tel, mandei o aviso ao proprietário da visita #' || v.id || ' e ele não respondeu em ' ||
        nai_cfg_int('reenvio_proprietario_min', 30) || E' minutos. Pode ligar para ele?\nParei com o corretor e com o proprietário até você responder.', 'p_ligar');
      UPDATE nai_visita SET aviso_tel_em = now(), estado = 'com_tel', aguardando = 'tel', atualizado_em = now() WHERE id = v.id;
      PERFORM nai_parar_chat(v.corretor_id, 'visita #' || v.id || ': proprietario nao respondeu o aviso');
      PERFORM nai_parar_chat(v.proprietario_id, 'visita #' || v.id || ': proprietario nao respondeu o aviso');
      n := n + 1;
    END IF;

    -- ---------------------------------------------- Fernando sem responder
    IF v.estado = 'aguardando_motoboy' AND v.ult_msg_moto_em IS NOT NULL
       AND (v.ult_resp_moto_em IS NULL OR v.ult_resp_moto_em < v.ult_msg_moto_em)
       AND now() >= v.ult_msg_moto_em + v_rmoto THEN
      IF v.reenvios_moto < 1 THEN
        PERFORM nai_enfileirar_texto(NULL, v.id, v.motoboy_id, 'motoboy',
          '' || nai_acompanhante() || ', consegue me confirmar a visita do ' || nai_ref_imovel(v.codigo) || ', ' || nai_hora_exata(v.quando) || '?',
          'motoboy_lembrete', 1);
        UPDATE nai_visita SET reenvios_moto = reenvios_moto + 1, ult_msg_moto_em = now() WHERE id = v.id;
      ELSIF v.aviso_tel_moto_em IS NULL THEN
        PERFORM nai_avisar_tel(NULL, v.id, 'Tel, o ' || nai_acompanhante() || ' não confirmou a visita #' || v.id || ' (' || nai_ref_imovel(v.codigo) ||
          ', ' || nai_hora_exata(v.quando) || '). O proprietário já confirmou. Responda VISITA ' || v.id || ' ' || nai_acompanhante_maiusculo() || ' OK quando ele confirmar.',
          'motoboy_sem_resposta');
        UPDATE nai_visita SET aviso_tel_moto_em = now() WHERE id = v.id;
      END IF;
      n := n + 1;
    END IF;

    -- ---------------------------------------------- visita confirmada
    IF v.estado = 'confirmada' THEN
      v_ini := nai_inicio_periodo(v.quando);
      -- No comeco do periodo (se ficar a mais de 1h da visita).
      IF v.lembrete_periodo_em IS NULL AND now() >= v_ini AND v_ini <= v.quando - v_lemb
         AND v.confirmada_em < v_ini AND now() < v.quando - v_lemb THEN
        PERFORM nai_enfileirar_texto(NULL, v.id, v.corretor_id, 'corretor',
          coalesce(v_nome || ', ', '') || 'passando pra lembrar da visita ' || nai_quando_humano(v.quando) || ' no ' ||
          nai_ref_imovel(v.codigo) || '. O ' || nai_acompanhante() || ' te encontra lá', 'lembrete_periodo', 1);
        UPDATE nai_visita SET lembrete_periodo_em = now() WHERE id = v.id;
        n := n + 1;
      END IF;
      -- 1 hora antes (se a confirmacao nao foi ja dentro dessa hora).
      IF v.lembrete_1h_em IS NULL AND now() >= v.quando - v_lemb AND now() < v.quando AND v.confirmada_em < v.quando - v_lemb THEN
        PERFORM nai_enfileirar_texto(NULL, v.id, v.corretor_id, 'corretor',
          coalesce(v_nome || ', ', '') || 'daqui a 1 hora, às ' || to_char(v.quando AT TIME ZONE 'America/Manaus', 'HH24"h"MI') ||
          ', é a visita no ' || nai_ref_imovel(v.codigo) || '. O ' || nai_acompanhante() || ' te encontra lá. Qualquer imprevisto me avisa por aqui.', 'lembrete_1h', 1);
        UPDATE nai_visita SET lembrete_1h_em = now() WHERE id = v.id;
        n := n + 1;
      END IF;
      -- 30 min antes: senha (fechadura) ou conferir a chave, com o Fernando.
      IF v.aviso_motoboy_em IS NULL AND now() >= v.quando - v_moto AND now() < v.quando AND v.motoboy_id IS NOT NULL THEN
        PERFORM nai_enfileirar_texto(NULL, v.id, v.motoboy_id, 'motoboy',
          CASE v.acesso
            WHEN 'fechadura' THEN '' || nai_acompanhante() || ', a senha da fechadura do ' || nai_ref_imovel(v.codigo) || ' é ' || coalesce(v.senha, '(peça ao Tel)') ||
                                  '. A visita é às ' || to_char(v.quando AT TIME ZONE 'America/Manaus', 'HH24:MI') || '. Conseguiu anotar?'
            WHEN 'proprietario_acompanha' THEN '' || nai_acompanhante() || ', lembrete: visita no ' || nai_ref_imovel(v.codigo) || ' às ' ||
                                  to_char(v.quando AT TIME ZONE 'America/Manaus', 'HH24:MI') || '. O proprietário vai estar lá.'
            ELSE '' || nai_acompanhante() || ', só confirmando: você já está com a chave do ' || nai_ref_imovel(v.codigo) || ' pra visita das ' ||
                 to_char(v.quando AT TIME ZONE 'America/Manaus', 'HH24:MI') || '?' ||
                 CASE WHEN v.acesso = 'buscar_chave' THEN ' Depois não esquece de devolver ao proprietário.' ELSE '' END END,
          'aviso_motoboy', 1);
        UPDATE nai_visita SET aviso_motoboy_em = now() WHERE id = v.id;
        n := n + 1;
      END IF;
      -- Depois da visita: como foi? (e a senha sai do banco).
      IF v.pos_visita_em IS NULL AND now() >= v.quando + v_pos THEN
        PERFORM nai_enfileirar_texto(NULL, v.id, v.corretor_id, 'corretor',
          'E aí' || coalesce(', ' || v_nome, '') || ', como foi a visita no ' || nai_ref_imovel(v.codigo) || '? O cliente gostou?',
          'pos_visita', 1);
        IF v.acesso = 'buscar_chave' AND v.motoboy_id IS NOT NULL AND v.devolver_chave_em IS NULL THEN
          PERFORM nai_enfileirar_texto(NULL, v.id, v.motoboy_id, 'motoboy',
            '' || nai_acompanhante() || ', não esquece de devolver a chave do ' || nai_ref_imovel(v.codigo) || ' ao proprietário.', 'devolver_chave', 2);
          UPDATE nai_visita SET devolver_chave_em = now() WHERE id = v.id;
        END IF;
        UPDATE nai_visita SET pos_visita_em = now(), estado = 'realizada', senha = NULL, atualizado_em = now() WHERE id = v.id;
        PERFORM nai_evento(v.id, 'realizada', NULL);
        n := n + 1;
      END IF;
    END IF;

    -- Realizada ha mais de 2 dias sem retorno: encerra.
    IF v.estado = 'realizada' AND now() >= coalesce(v.pos_visita_em, v.quando) + interval '2 days' THEN
      UPDATE nai_visita SET estado = 'encerrada', encerrada_em = now(), senha = NULL WHERE id = v.id;
    END IF;
  END LOOP;
  -- 141: o follow-up do dia seguinte. Um erro aqui nunca para a agenda das visitas.
  BEGIN
    n := n + nai_followup_rodar();
  EXCEPTION WHEN OTHERS THEN
    RAISE WARNING 'nai_followup_rodar: %', SQLERRM;
  END;

  RETURN n;
END;
$function$;

CREATE OR REPLACE FUNCTION public.nai_abrir_turno(p_tel text, p_nome text, p_texto text, p_citado_id text, p_ids bigint[])
 RETURNS jsonb
 LANGUAGE plpgsql
AS $function$
DECLARE
  v_chave   text := nai_chave(p_tel);
  v_modo    text := nai_cfg('modo', 'desligado');
  v_teste   boolean;
  v_contato bigint;
  v_papel   text := 'corretor';
  v_visita  bigint;
  v_texto   text := coalesce(p_texto, '');
  v_m       text[];
  v_cit     record;
  v_n       int;
  v_turno   bigint;
  v_aprov   boolean;
  v_prim    boolean;
  v_pausado boolean;
  v_tel_lid text;
  v_porta   record;   -- a porta: atende essa mensagem?
BEGIN
  IF v_chave IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'motivo', 'sem_identificador');
  END IF;
  IF v_modo NOT IN ('teste', 'todos') THEN
    RETURN jsonb_build_object('ok', false, 'motivo', 'nai_desligada');
  END IF;
  v_teste := v_chave = ANY (nai_chaves_teste());

  -- O FILTRO DE PALAVRAS (106, Tel 23/09: "se ela estiver escrita mais ou
  -- menos certo, acima de 70% da palavra certa ela conserta a palavra antes
  -- ate de enviar para a Nay"). "bom pedro" vira Dom Pedro, "aquarelli" vira
  -- Acquarelle -- e isso vale para a PORTA tambem, que assim reconhece o
  -- imovel nosso mesmo quando o nome chega torto do audio.
  -- O comando do Tel nao passa por aqui: filtro de palavras nao pode ter
  -- poder de quebrar um DEVOLVER.
  IF NOT nai_pode_comandar(v_chave) THEN
    v_texto := nai_corrigir_nomes(v_texto);
  END IF;
  -- O COMANDO DELES PASSA MESMO EM MODO TESTE (Tel, 15/09: "tel mandou agenda
  -- de visitas e ela n respondeu"). O numero do Tel nao esta em
  -- `numeros_teste` -- so o do Pedro esta --, entao o turno nem abria e o
  -- comando morria calado. A excecao e so para o COMANDO: conversa normal
  -- desses numeros continua caindo na mesma porta de antes.
  IF v_modo = 'teste' AND NOT v_teste
     AND nai_pode_comandar(v_chave)
     AND (nai_e_comando_tel(v_texto) OR nai_e_comando_extra(v_texto)) THEN
    NULL;   -- deixa passar
  ELSIF v_modo = 'teste' AND NOT v_teste THEN
    -- Defesa em profundidade: o roteador nao devia ter mandado.
    RETURN jsonb_build_object('ok', false, 'motivo', 'fora_do_teste');
  END IF;

  v_contato := nai_contato_de(p_tel, p_nome);

  -- O TEL ASSUMIU este chat: a mensagem fica gravada (status 'Com o Tel') e
  -- a NAI nao responde. No teste, "T: ..." continua sendo o Tel mandando
  -- comando (e o DEVOLVER precisa passar).
  -- 16/09: a leitura da pausa passou a ser uma so, em `nai_tel_com_a_conversa`
  -- -- que sabe do gap. Antes eram tres copias de
  -- `humano_assumiu_em IS NOT NULL`, e com a janela entrando elas iam divergir.
  IF nai_tel_com_a_conversa(v_contato)
     AND NOT (v_teste AND v_texto ~* '^\s*(t|tel)\s*[:\-–]') THEN
    UPDATE mensagens SET status = 'Com o Tel' WHERE id = ANY (coalesce(p_ids, '{}')) AND status IN ('Recebido', 'Processando');
    RETURN jsonb_build_object('ok', false, 'motivo', 'tel_assumiu', 'contato_id', v_contato);
  END IF;

  IF v_teste THEN
    -- No teste, o mesmo numero faz todos os papeis. O papel vem da MARCACAO
    -- (ele respondeu marcando a mensagem que iria para o proprietario) ou
    -- do prefixo P: / M: / T:. Sem nada disso, e corretor.
    IF nullif(p_citado_id, '') IS NOT NULL THEN
      SELECT s.papel_destino, s.visita_id INTO v_cit
        FROM nai_saida s WHERE s.message_id = p_citado_id AND s.redirecionado LIMIT 1;
      IF v_cit.papel_destino IN ('proprietario', 'motoboy', 'tel') THEN
        v_papel := v_cit.papel_destino; v_visita := v_cit.visita_id;
      END IF;
    END IF;
    v_m := regexp_match(v_texto, ('^\s*(p|prop|propriet[aá]ri[oa]|m|moto|motoboy|fernando|'
                          -- as DUAS grafias do nome: quem digita "André:" e quem digita
                          -- "Andre:" tem que cair no mesmo lugar. O texto NAO passa por
                          -- unaccent -- ele e capturado aqui e vira a mensagem.
                          || lower(nai_acompanhante()) || '|' || lower(unaccent(nai_acompanhante()))
                          || '|t|tel)\s*[:\-–]\s*(.*)$'), 'is');
    IF v_m IS NOT NULL THEN
      v_texto := v_m[2];
      IF v_papel = 'corretor' THEN
        -- O NOME DO ACOMPANHANTE tambem manda para o motoboy (Tel, 16/09).
        -- Sem esta linha, "André: pode ser" caia como TEL: a decisao testava
        -- so as iniciais m e f (motoboy e Fernando), e "andre" nao comeca com
        -- nenhuma das duas. Medido antes de aplicar.
        v_papel := CASE WHEN lower(v_m[1]) ~ '^p' THEN 'proprietario'
                        WHEN lower(v_m[1]) ~ '^(m|f)' THEN 'motoboy'
                        WHEN lower(unaccent(v_m[1])) = lower(unaccent(nai_acompanhante()))
                          THEN 'motoboy'
                        ELSE 'tel' END;
      END IF;
    END IF;
    -- O NUMERO DO TEL no teste (13/09): comando da NAI (VISITAS, VISITA N, ACESSO,
    -- ASSUMIR, DEVOLVER) sem o prefixo T: tambem e o Tel. Conversa normal dele
    -- continua sendo corretor -- e assim que ele testa.
    -- 28/09: `nai_e_voz_do_tel` no lugar da igualdade com `tel_telefone`.
    -- O Tel pediu um SEGUNDO número "como se fosse ele", e a regra de quem
    -- é o Tel passou a morar numa função só -- repetida nos quatro pontos,
    -- divergiria e daria comando aceito num caminho e recusado no outro.
    IF v_papel = 'corretor' AND nai_e_voz_do_tel(v_chave) AND nai_e_comando_tel(v_texto) THEN
      v_papel := 'tel';
    END IF;
    -- AGENDA DE VISITAS (Tel, 15/09): "quero que o tel e eu quando digitar no
    -- pv dela Agenda de visitas". Vale para os telefones de
    -- `comando_telefones`, e SO para esse comando -- o resto da conversa deles
    -- continua caindo onde sempre caiu.
    IF v_papel = 'corretor' AND nai_e_comando_extra(v_texto) AND nai_pode_comandar(v_chave) THEN
      v_papel := 'tel';
    END IF;
    -- ENVIA <NUMERO> O <CODIGO> DA EQUIPE (27/09/2026, 135): o pedido de envio
    -- do Pedro e da Rayssa e comando, nao conversa. O do Tel continua indo para
    -- o publicador, pelo caminho de sempre -- por isso o Tel fica de fora aqui.
    IF v_papel = 'corretor' AND NOT nai_e_voz_do_tel(v_chave)
       AND nai_e_comando_envio(v_texto) AND nai_e_da_equipe_contato(v_contato) THEN
      v_papel := 'tel';
    END IF;
    -- 141: o SIM/NAO da Rayssa (ou "SIM 123" de quem e da equipe) e comando.
    IF v_papel = 'corretor' AND nai_resposta_aprovacao_valida(v_contato, v_texto) THEN
      v_papel := 'tel';
    END IF;
    IF v_papel IN ('proprietario', 'motoboy') AND v_visita IS NULL THEN
      -- A unica visita esperando esse papel. Mais de uma = pergunta.
      SELECT count(*), min(x.id) INTO v_n, v_visita FROM nai_visita x
       WHERE nai_visita_aberta(x.estado) AND x.aguardando = v_papel;
      IF v_n <> 1 THEN
        SELECT count(*), min(x.id) INTO v_n, v_visita FROM nai_visita x
         WHERE nai_visita_aberta(x.estado)
           AND (v_papel = 'proprietario' AND x.proprietario_id IS NOT NULL
             OR v_papel = 'motoboy' AND x.estado IN ('aguardando_motoboy', 'confirmada'));
        IF v_n <> 1 THEN v_visita := NULL; END IF;
      END IF;
    END IF;
  ELSE
    IF nai_e_voz_do_tel(v_chave)
       OR (nai_e_comando_extra(v_texto) AND nai_pode_comandar(v_chave))
       -- o pedido de envio da equipe (135)
       OR (nai_e_comando_envio(v_texto) AND nai_e_da_equipe_contato(v_contato))
       -- 141: a aprovacao da visita
       OR nai_resposta_aprovacao_valida(v_contato, v_texto) THEN
      v_papel := 'tel';
    ELSIF nai_e_motoboy(v_chave) THEN
      v_papel := 'motoboy';
    ELSIF EXISTS (SELECT 1 FROM nai_visita x WHERE x.proprietario_id = v_contato AND nai_visita_aberta(x.estado)) THEN
      v_papel := 'proprietario';
    END IF;
    IF v_papel IN ('proprietario', 'motoboy') THEN
      -- Qual visita: pela mensagem marcada; senao, a unica aberta dele.
      IF nullif(p_citado_id, '') IS NOT NULL THEN
        SELECT s.visita_id INTO v_visita FROM nai_saida s
         WHERE s.message_id = p_citado_id AND s.contato_id = v_contato AND s.visita_id IS NOT NULL LIMIT 1;
      END IF;
      IF v_visita IS NULL THEN
        SELECT count(*), min(x.id) INTO v_n, v_visita FROM nai_visita x
         WHERE nai_visita_aberta(x.estado)
           AND ((v_papel = 'proprietario' AND x.proprietario_id = v_contato)
             OR (v_papel = 'motoboy' AND x.motoboy_id = v_contato AND x.estado IN ('aguardando_motoboy', 'confirmada')));
        IF v_n <> 1 THEN v_visita := NULL; END IF;
      END IF;
    END IF;
  END IF;

  -- Corretor aprovado? Teste = sim. @lid: so pelo mapeamento ja gravado,
  -- e SO para aprovar -- a conversa continua sendo a do @lid.
  IF v_teste THEN
    v_aprov := true;
  ELSE
    IF v_chave ~ '^lid:' THEN
      SELECT telefone INTO v_tel_lid FROM identidade_lid WHERE lid = p_tel;
    END IF;
    v_aprov := EXISTS (SELECT 1 FROM corretores c
                        WHERE c.aprovado AND c.ativo
                          AND nai_chave(c.telefone) = coalesce(nai_chave(v_tel_lid), v_chave));
  END IF;
  v_prim := NOT EXISTS (SELECT 1 FROM mensagens m
                         WHERE m.telefone = p_tel AND m.direcao = 'recebida'
                           AND NOT (m.id = ANY (coalesce(p_ids, '{}'))));

  -- A PORTA (Tel, 15/09): quem ela atende quando a regra publica esta ligada.
  -- Com a regra desligada devolve atende=true e o roteador segue com o
  -- porteiro de sempre -- entao ligar este campo nao muda nada sozinho.
  -- O IMOVEL DA MENSAGEM MARCADA vai junto (Tel, 15/09): quem responde o card
  -- do grupo esta falando de imovel, escreva o que escrever -- ate "Boa
  -- noite!". `nay_imovel_da_citacao` ja resolve o card do grupo, o card que ela
  -- mandou e o envio do publicador.
  SELECT * INTO v_porta FROM nai_deve_atender(
    p_tel, v_texto,
    nullif(regexp_replace(coalesce(nay_imovel_da_citacao(p_citado_id), ''), '\D', '', 'g'), '')::int);
  -- A pausa geral da Nay (config.atendimento_pausado) vale para a NAI tambem --
  -- menos para o numero de teste, do mesmo jeito que a Nay antiga isenta o Tel.
  -- A PAUSA E SO A DELA (Tel, 15/09, na revisao depois de ativar).
  --
  -- Ate aqui a pausa da Nay ANTIGA (`config.atendimento_pausado`) tambem calava
  -- a NAI, menos para o numero de teste. Enquanto ela era so teste isso nunca
  -- aparecia -- o unico que falava com ela era o Pedro, e ele e "teste". Ao
  -- abrir para todos, as 14:12, TODO MUNDO caiu naquela pausa: 133 mensagens
  -- entraram e nenhuma foi respondida, e nao havia erro nenhum para ver.
  --
  -- A Nay antiga esta pausada desde agosto, de proposito e para sempre. Ela nao
  -- pode calar um atendimento que e outro produto, com a propria chave e o
  -- proprio botao no painel.
  v_pausado := nai_cfg('pausada', 'sim') <> 'nao';

  INSERT INTO nai_turno (contato_id, papel, visita_id, teste, texto, msg_ids, porta)
       VALUES (v_contato, v_papel, v_visita, v_teste, v_texto, p_ids, v_porta.motivo)
  RETURNING id INTO v_turno;

  -- Registra que o proprietario / Fernando respondeu (para as cobrancas).
  IF v_papel = 'proprietario' THEN
    UPDATE nai_visita SET ult_resp_prop_em = now(), atualizado_em = now()
     WHERE (id = v_visita) OR (v_visita IS NULL AND proprietario_id = v_contato AND nai_visita_aberta(estado));
  ELSIF v_papel = 'motoboy' AND v_visita IS NOT NULL THEN
    UPDATE nai_visita SET ult_resp_moto_em = now(), atualizado_em = now() WHERE id = v_visita;
  END IF;

  RETURN jsonb_build_object(
    'ok', true,
    'turno_id', v_turno,
    'contato_id', v_contato,
    'chave', v_chave,
    'telefone', (SELECT telefone FROM nai_contato WHERE id = v_contato),
    'papel', v_papel,
    'visita_id', v_visita,
    'teste', v_teste,
    'modo', v_modo,
    'texto', v_texto,
    'aprovado', v_aprov,
    -- ATENDE: NULL quando a regra publica esta desligada (o roteador decide
    -- como sempre decidiu); true/false quando ela manda. `porta` diz o motivo,
    -- e e ele que explica um silencio depois.
    'atende', CASE WHEN lower(coalesce(nai_cfg('regra_publico', 'nao'), 'nao')) = 'sim'
                   THEN v_porta.atende END,
    'porta', v_porta.motivo,
    -- SO CUMPRIMENTOU (Tel, 15/09): "ela tem que responder o cumprimento e
    -- aguardar nesse caso". Quem chega dizendo so "boa noite" ainda nao disse a
    -- que veio -- despejar o roteiro em cima dele e responder outra pergunta.
    'so_cumprimento', nai_so_cumprimentou(v_texto),
    'primeira_vez', v_prim,
    'pausado', v_pausado,
    -- "3500" depois de "qual a faixa de preco?" e VALOR, nao codigo (13/09).
    'esperando_valor', nai_esperando_valor(v_contato),
    'memoria', 'nai:' || v_papel || ':' || v_contato || coalesce(':v' || v_visita, ''),
    -- O PROMPT VEM DO BANCO (Tel, 15/09): editar no painel vale na mensagem
    -- seguinte, sem import nem reinicio. Vazio aqui = o fluxo usa o texto que
    -- ja esta dentro dele, entao nada quebra.
    'prompt', nai_prompt_de(CASE WHEN v_papel = 'tel' THEN 'corretor' ELSE v_papel END),
    -- COMANDO DA NAI: o roteador do fluxo lia uma COPIA da regex de
    -- `nai_e_comando_tel` dentro do JS, e as duas se afastariam na primeira
    -- mudanca. Agora quem responde e o banco, e o JS so le este campo.
    'comando_nai', (v_papel = 'tel' AND (nai_e_comando_tel(v_texto) OR nai_e_comando_extra(v_texto)
                    -- 135: o envio da equipe vai para `nai_comando_tel`; o do
                    -- Tel segue no publicador (comando_nai falso para ele)
                    OR (nai_e_comando_envio(v_texto)
                        AND NOT nai_e_voz_do_tel(v_chave))
                    -- 141: SIM/NAO da aprovacao da visita
                    OR nai_resposta_aprovacao_valida(v_contato, v_texto))),
    -- A BIBLIOTECA DE PALAVRAS (96, Tel 22/09) entra colada no contexto: so a
    -- explicacao da giria que ELE escreveu nesta mensagem, e nada quando nao
    -- ha giria nenhuma.
    -- 141: A ETAPA vem na frente do contexto (identificacao / recebeu o
    -- imovel / agendamento de visita) -- e o que a mantem no fio da conversa.
    'etapa', CASE WHEN v_papel = 'corretor' THEN nai_etapa_atualizar(v_contato) END,
    'contexto', CASE WHEN v_papel = 'corretor' THEN nai_etapa_para_o_modelo(v_contato) || E'\n' ELSE '' END
                || nai_contexto(v_papel, v_contato, v_visita, v_teste)
                || CASE WHEN v_papel IN ('corretor', 'tel')
                        THEN nai_giria_explica(v_texto) ELSE '' END,
    -- Como chamar a pessoa: Sr./Sra. + primeiro nome (Tel, 12/09 -- o mesmo
    -- tom da captacao). Quando o nome nao diz o genero, vem so o primeiro
    -- nome: melhor sem tratamento do que chamar uma corretora de "Sr.".
    'vocativo', CASE WHEN v_papel = 'proprietario'
                     THEN nai_vocativo((SELECT proprietario_nome FROM nai_visita WHERE id = v_visita))
                     WHEN v_papel = 'corretor'
                     THEN nai_vocativo(coalesce((SELECT nome_completo FROM nai_contato WHERE id = v_contato),
                                                nay_nome_de_pessoa((SELECT nome_whatsapp FROM nai_contato WHERE id = v_contato)))) END
  );
END;
$function$;

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

  -- 141: SIM <n> / NAO <n> / TELEFONE <n> <numero> -- a aprovacao da visita.
  IF nai_resposta_aprovacao_valida(t.contato_id, s) THEN
    v_msg := nai_aprovar_visita(p_turno, s);
    PERFORM nai_enfileirar_texto(p_turno, NULL, t.contato_id, 'turno', v_msg, 'comando_aprovacao', 1);
    RETURN QUERY SELECT v_msg; RETURN;
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
  -- 135: a frase e lida por `nai_ler_pedido_de_envio` -- telefone antes ou
  -- depois do verbo, um ou varios codigos -- e quem pode mandar e a equipe
  -- (a mesma definicao da 130), olhando as duas linhas da pessoa.
  IF nai_e_comando_envio(s)
     AND (t.papel = 'tel' OR nai_e_da_equipe_contato(t.contato_id))
  THEN
    v_msg := (SELECT nai_enviar_imoveis_para(p_turno, p.codigos, p.telefone)
                FROM nai_ler_pedido_de_envio(s) p);
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

-- 141c (28/09, "aplica todas as correções em produção mesmo e deixa ela
-- respondendo"): liga o follow-up e o contato DIRETO com o proprietário --
-- que agora só acontece depois do SIM da Rayssa, com as informações conferidas.
-- A marca 559200000001 era de um teste meu (27/09 16:14) e ganharia follow-up.
DELETE FROM imovel_enviado_no_dia WHERE chave = '559200000001';
UPDATE nai_config SET valor = 'sim', atualizado_em = now() WHERE chave = 'followup_ligado';
UPDATE nai_config SET valor = 'nao', atualizado_em = now() WHERE chave = 'proprietario_pelo_tel';
