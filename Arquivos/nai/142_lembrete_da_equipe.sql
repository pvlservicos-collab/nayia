-- =====================================================================
-- 142 — A NAY COMO LEMBRETE DA EQUIPE (28/09/2026)
--
-- Pedido: "a rayssa vai usar a nay como um lembrete, então ela pediu aqui
-- para avisar ela em tal horário, a nay vai salvar um cron temporário para
-- ela avisando por mensagem, implementa esse serviço de lembrete".
--
-- COMO FUNCIONA
--   Rayssa (ou Pedro, ou Tel) escreve para a Nay:
--     "Nay, me lembra às 15h de ligar pro dono do 3050"
--     "me avisa amanhã 9h: reunião com o Tel"
--     "lembrete daqui 30 minutos buscar a chave"
--   Ela grava em `nai_lembrete` e responde "Combinado! Te lembro hoje às
--   15h00: ligar pro dono do 3050". Na hora, o ciclo de minuto em minuto
--   (`nai_agenda_tick`) manda "⏰ Lembrete: ligar pro dono do 3050".
--   "meus lembretes" lista; "cancela lembrete 12" cancela.
--
--   O "cron temporário" é a linha na tabela: o ciclo já roda todo minuto, e
--   um cron de verdade por lembrete seria um processo a mais para vigiar.
--
-- SÓ A EQUIPE usa (`nai_e_da_equipe_contato`): o pedido vira turno de
-- comando, como o envio da 135 e o SIM da 141. O lembrete sai mesmo fora da
-- janela das 06-22h e com a Nay pausada -- é recado da equipe para a equipe.
-- =====================================================================
\set ON_ERROR_STOP on

BEGIN;
SET LOCAL lock_timeout = '5s';

CREATE TABLE IF NOT EXISTS nai_lembrete (
  id         bigserial PRIMARY KEY,
  contato_id bigint NOT NULL REFERENCES nai_contato(id),
  quando     timestamptz NOT NULL,
  texto      text NOT NULL,
  estado     text NOT NULL DEFAULT 'agendado' CHECK (estado IN ('agendado', 'enviado', 'cancelado')),
  turno_id   bigint,
  pedido     text,
  criado_em  timestamptz NOT NULL DEFAULT now(),
  enviado_em timestamptz
);
CREATE INDEX IF NOT EXISTS nai_lembrete_agendado ON nai_lembrete (quando) WHERE estado = 'agendado';

-- ---------------------------------------------------------------------
-- É pedido de lembrete? (ou "meus lembretes" / "cancela lembrete N")
-- "me avisa" e "me lembra" -- "avisa o corretor" NÃO é lembrete.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION nai_e_pedido_lembrete(p text)
RETURNS boolean
LANGUAGE sql
IMMUTABLE
AS $fn$
  SELECT lower(unaccent(btrim(coalesce(p, '')))) ~
         ('^(@?nay[\s,:;.!-]*)?((me|nos)\s+(lembr\w*|avis\w*)\M|lembr\w*-me\M|(agenda\s+(um\s+)?|cria\s+(um\s+)?)?lembrete\M'
          || '|meus\s+lembretes\M|cancel\w*\s+(o\s+)?lembrete\M)');
$fn$;

-- ---------------------------------------------------------------------
-- Lê QUANDO e O QUÊ de um pedido em português.
--   "às 15h", "15:30", "3 da tarde", "meio dia", "amanhã 9h", "hoje 18h",
--   "sexta 10h", "dia 30 às 14h", "daqui 30 minutos", "em 2 horas".
-- Hora sem dia: hoje, ou amanhã se já passou. Dia sem hora: 09h00.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION nai_ler_lembrete(p text, p_agora timestamptz DEFAULT now())
RETURNS TABLE (quando timestamptz, oque text)
LANGUAGE plpgsql
STABLE
AS $fn$
DECLARE
  s      text := lower(unaccent(coalesce(p, '')));
  agora  timestamp := p_agora AT TIME ZONE 'America/Manaus';
  m      text[];
  v_dia  date;
  v_h    int;
  v_min  int := 0;
  v_n    int;
  v_q    timestamp;
  v_txt  text := coalesce(p, '');
  v_dow  int;
  v_alvo int;
BEGIN
  -- relativo: "daqui 30 minutos", "em 2 horas", "daqui a uma hora", "daqui meia hora"
  m := regexp_match(s, '\m(daqui|em|dentro\s+de)\s+(a\s+)?(\d{1,3}|uma|um|meia)\s*(min\w*|h\M|hs\M|hora\w*)');
  IF m IS NOT NULL THEN
    v_n := CASE WHEN m[3] IN ('uma', 'um') THEN 1 WHEN m[3] = 'meia' THEN 0 ELSE m[3]::int END;
    IF m[4] ~ '^min' THEN
      v_q := agora + make_interval(mins => v_n);
    ELSIF m[3] = 'meia' THEN
      v_q := agora + interval '30 minutes';
    ELSE
      v_q := agora + make_interval(hours => v_n);
    END IF;
  ELSE
    -- o dia
    IF s ~ '\mdepois\s+de\s+amanha\M' THEN
      v_dia := agora::date + 2;
    ELSIF s ~ '\mamanha\M' THEN
      v_dia := agora::date + 1;
    ELSIF s ~ '\mhoje\M' THEN
      v_dia := agora::date;
    ELSE
      m := regexp_match(s, '\mdia\s+(\d{1,2})(\s*/\s*(\d{1,2}))?');
      IF m IS NOT NULL THEN
        BEGIN
          v_dia := make_date(extract(year FROM agora)::int,
                             coalesce(m[3]::int, extract(month FROM agora)::int), m[1]::int);
          IF v_dia < agora::date THEN
            v_dia := CASE WHEN m[3] IS NULL THEN (v_dia + interval '1 month')::date ELSE (v_dia + interval '1 year')::date END;
          END IF;
        EXCEPTION WHEN OTHERS THEN v_dia := NULL;
        END;
      ELSE
        m := regexp_match(s, '\m(segunda|terca|quarta|quinta|sexta|sabado|domingo)\M');
        IF m IS NOT NULL THEN
          v_alvo := array_position(ARRAY['segunda', 'terca', 'quarta', 'quinta', 'sexta', 'sabado', 'domingo'], m[1]);
          v_dow := extract(isodow FROM agora)::int;
          v_dia := agora::date + ((v_alvo - v_dow + 7) % 7);
        END IF;
      END IF;
    END IF;

    -- a hora
    IF s ~ '\mmeio[\s-]dia\M' THEN
      v_h := 12; v_min := 0;
    ELSE
      m := regexp_match(s, '\m(\d{1,2})\s*(h|:|hs|horas?)\s*(\d{2})?(\s*(da|de)\s+(manha|tarde|noite))?');
      IF m IS NULL THEN
        m := regexp_match(s, '\m(as|a)\s+(\d{1,2})(\s*(da|de)\s+(manha|tarde|noite))?\M');
        IF m IS NOT NULL THEN
          m := ARRAY[m[2], 'h', NULL, m[3], m[4], m[5]];
        END IF;
      END IF;
      IF m IS NOT NULL THEN
        v_h := m[1]::int;
        v_min := coalesce(m[3]::int, 0);
        IF m[6] IN ('tarde', 'noite') AND v_h < 12 THEN v_h := v_h + 12; END IF;
      END IF;
    END IF;

    IF v_h IS NULL AND v_dia IS NULL THEN
      RETURN;   -- nao deu para saber quando
    END IF;
    IF v_h IS NULL OR v_h > 23 OR v_min > 59 THEN
      IF v_h IS NOT NULL THEN RETURN; END IF;
      v_h := 9; v_min := 0;   -- dia sem hora: 09h00
    END IF;
    v_q := coalesce(v_dia, agora::date) + make_time(v_h, v_min, 0);
    IF v_dia IS NULL AND v_q <= agora THEN
      v_q := v_q + interval '1 day';
    ELSIF v_dia IS NOT NULL AND v_dia = agora::date AND v_q <= agora AND s ~ '\m(segunda|terca|quarta|quinta|sexta|sabado|domingo)\M' THEN
      v_q := v_q + interval '7 days';
    END IF;
  END IF;

  -- o que lembrar: o pedido sem o comando, sem o quando e sem os conectivos
  v_txt := regexp_replace(v_txt, '^\s*@?nay[\s,:;.!-]*', '', 'i');
  v_txt := regexp_replace(v_txt, '^\s*((me|nos)\s+(lembr\w*|avis\w*)|lembr\w*-me|(agenda\s+(um\s+)?|cria\s+(um\s+)?)?lembrete)[\s,:;.!-]*', '', 'i');
  v_txt := regexp_replace(v_txt, '\m(daqui|em|dentro\s+de)\s+(a\s+)?(\d{1,3}|uma|um|meia)\s*(min\w*|h\M|hs\M|hora\w*)', ' ', 'gi');
  v_txt := regexp_replace(v_txt, '\m(depois\s+de\s+amanh[ãa]|amanh[ãa]|hoje)\M', ' ', 'gi');
  v_txt := regexp_replace(v_txt, '\m((na|no|nesta|neste|pr[óo]xim[ao])\s+)?(segunda|ter[çc]a|quarta|quinta|sexta|s[áa]bado|domingo)(-feira)?\M', ' ', 'gi');
  v_txt := regexp_replace(v_txt, '\mdia\s+\d{1,2}(\s*/\s*\d{1,2})?', ' ', 'gi');
  v_txt := regexp_replace(v_txt, '\m(à|a|às|as)?\s*\d{1,2}\s*(h|:|hs|horas?)\s*(\d{2})?(\s*(da|de)\s+(manh[ãa]|tarde|noite))?', ' ', 'gi');
  v_txt := regexp_replace(v_txt, '\m(à|a|às|as)\s+\d{1,2}(\s*(da|de)\s+(manh[ãa]|tarde|noite))?\M', ' ', 'gi');
  v_txt := regexp_replace(v_txt, '\m(ao\s+|a\s+|à\s+)?meio[\s-]dia\M', ' ', 'gi');
  v_txt := regexp_replace(v_txt, '\s{2,}', ' ', 'g');
  v_txt := btrim(v_txt, E' \t\n,:;.-');
  v_txt := regexp_replace(v_txt, '^(de|que|para|pra|pro|sobre|do|da)\s+', '', 'i');
  v_txt := btrim(v_txt, E' \t\n,:;.-');

  quando := v_q AT TIME ZONE 'America/Manaus';
  oque := nullif(v_txt, '');
  RETURN NEXT;
END;
$fn$;

-- "hoje às 15h00" / "amanhã (terça, 29/09) às 09h00" / "quinta, 02/10 às 10h00"
CREATE OR REPLACE FUNCTION nai_quando_lembrete(p_ts timestamptz)
RETURNS text
LANGUAGE sql
STABLE
AS $fn$
  SELECT CASE (p_ts AT TIME ZONE 'America/Manaus')::date - (now() AT TIME ZONE 'America/Manaus')::date
           WHEN 0 THEN 'hoje'
           WHEN 1 THEN 'amanhã (' || nai_dia_da_semana(p_ts) || ', ' || to_char(p_ts AT TIME ZONE 'America/Manaus', 'DD/MM') || ')'
           ELSE nai_dia_da_semana(p_ts) || ', ' || to_char(p_ts AT TIME ZONE 'America/Manaus', 'DD/MM') END
         || ' às ' || to_char(p_ts AT TIME ZONE 'America/Manaus', 'HH24"h"MI');
$fn$;

-- ---------------------------------------------------------------------
-- O comando: grava, lista ou cancela. Devolve a resposta para quem pediu.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION nai_comando_lembrete(p_turno bigint, p_texto text)
RETURNS text
LANGUAGE plpgsql
AS $fn$
DECLARE
  t      nai_turno;
  s      text := lower(unaccent(btrim(coalesce(p_texto, ''))));
  m      text[];
  r      record;
  v_id   bigint;
  v_lista text;
BEGIN
  SELECT * INTO t FROM nai_turno WHERE id = p_turno;
  IF t.id IS NULL OR NOT nai_e_da_equipe_contato(t.contato_id) THEN
    RETURN 'O lembrete é só da equipe.';
  END IF;

  -- cancelar
  m := regexp_match(s, 'cancel\w*\s+(o\s+)?lembrete\s*#?\s*(\d+)');
  IF m IS NOT NULL THEN
    UPDATE nai_lembrete SET estado = 'cancelado'
     WHERE id = m[2]::bigint AND estado = 'agendado' AND contato_id = ANY (nai_contato_irmaos(t.contato_id))
    RETURNING id INTO v_id;
    IF v_id IS NULL THEN RETURN 'Não achei o lembrete ' || m[2] || ' agendado para você.'; END IF;
    RETURN 'Cancelei o lembrete ' || v_id || '.';
  END IF;

  -- listar
  IF s ~ '\mmeus\s+lembretes\M' OR s ~ '^(@?nay[\s,:;.!-]*)?lembretes\s*[?.!]*$' THEN
    SELECT string_agg('#' || l.id || ' — ' || nai_quando_lembrete(l.quando) || ': ' || l.texto, E'\n' ORDER BY l.quando)
      INTO v_lista FROM nai_lembrete l
     WHERE l.estado = 'agendado' AND l.contato_id = ANY (nai_contato_irmaos(t.contato_id));
    RETURN coalesce(E'Seus lembretes:\n' || v_lista, 'Você não tem lembrete agendado.');
  END IF;

  -- gravar
  SELECT * INTO r FROM nai_ler_lembrete(p_texto);
  IF r.quando IS NULL THEN
    RETURN 'Me diz quando, assim: "me lembra às 15h de ligar pro proprietário", "amanhã 9h", ou "daqui 30 minutos".';
  END IF;
  IF r.quando <= now() + interval '30 seconds' THEN
    RETURN 'Esse horário já passou. Me diz outro, por favor.';
  END IF;
  IF r.oque IS NULL THEN
    RETURN 'Te lembro do quê? Me manda de novo com o assunto, assim: "me lembra às 15h de ligar pro proprietário".';
  END IF;
  INSERT INTO nai_lembrete (contato_id, quando, texto, turno_id, pedido)
  VALUES (t.contato_id, r.quando, r.oque, p_turno, p_texto)
  RETURNING id INTO v_id;
  RETURN 'Combinado! Te lembro ' || nai_quando_lembrete(r.quando) || ': ' || r.oque || '.'
         || E'\n(lembrete ' || v_id || ' -- para cancelar: cancela lembrete ' || v_id || ')';
END;
$fn$;

-- ---------------------------------------------------------------------
-- Dispara os lembretes da hora. Chamado pelo ciclo de minuto em minuto.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION nai_lembretes_disparar()
RETURNS integer
LANGUAGE plpgsql
AS $fn$
DECLARE
  l nai_lembrete;
  n int := 0;
BEGIN
  FOR l IN SELECT * FROM nai_lembrete WHERE estado = 'agendado' AND quando <= now() ORDER BY quando FOR UPDATE SKIP LOCKED LOOP
    PERFORM nai_enfileirar_texto(NULL, NULL, l.contato_id, 'equipe', '⏰ Lembrete: ' || l.texto, 'lembrete', 1);
    UPDATE nai_lembrete SET estado = 'enviado', enviado_em = now() WHERE id = l.id;
    n := n + 1;
  END LOOP;
  RETURN n;
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
             -- 142: recado da equipe (lembrete, aprovacao de visita) sai a qualquer hora
             AND (nai_dentro_da_janela() OR s.papel_destino IN ('tel', 'equipe'))))
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

    v_cmd := (r.motivo = 'comando_tel' AND r.papel_destino = 'turno'
              AND nai_pode_comandar(v_chave_c))
             -- 142: o lembrete que a equipe pediu passa ate com a Nay pausada
             OR (r.motivo = 'lembrete' AND r.papel_destino = 'equipe');

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
    IF v_papel = 'corretor' AND (nai_resposta_aprovacao_valida(v_contato, v_texto)
                                 -- 142: o lembrete da equipe
                                 OR (nai_e_pedido_lembrete(v_texto) AND nai_e_da_equipe_contato(v_contato))) THEN
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
       OR nai_resposta_aprovacao_valida(v_contato, v_texto)
       -- 142: o lembrete da equipe
       OR (nai_e_pedido_lembrete(v_texto) AND nai_e_da_equipe_contato(v_contato)) THEN
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

  -- 141b: a etapa e atualizada ANTES de montar o cabecalho. Dentro do
  -- jsonb_build_object a ordem de avaliacao nao e garantida, e o contexto
  -- saiu com a etapa velha ("recebeu o imovel") no turno do "sim" da visita.
  IF v_papel = 'corretor' THEN
    PERFORM nai_etapa_atualizar(v_contato);
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
                    OR nai_resposta_aprovacao_valida(v_contato, v_texto)
                    -- 142: o lembrete da equipe
                    OR (nai_e_pedido_lembrete(v_texto) AND nai_e_da_equipe_contato(v_contato)))),
    -- A BIBLIOTECA DE PALAVRAS (96, Tel 22/09) entra colada no contexto: so a
    -- explicacao da giria que ELE escreveu nesta mensagem, e nada quando nao
    -- ha giria nenhuma.
    -- 141: A ETAPA vem na frente do contexto (identificacao / recebeu o
    -- imovel / agendamento de visita) -- e o que a mantem no fio da conversa.
    'etapa', CASE WHEN v_papel = 'corretor' THEN (SELECT e.etapa FROM nai_etapa_contato e WHERE e.contato_id = v_contato) END,
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

  -- 142: o lembrete da equipe ("me lembra as 15h de ...", "meus lembretes",
  -- "cancela lembrete 12").
  IF nai_e_pedido_lembrete(s) AND nai_e_da_equipe_contato(t.contato_id) THEN
    v_msg := nai_comando_lembrete(p_turno, s);
    PERFORM nai_enfileirar_texto(p_turno, NULL, t.contato_id, 'turno', v_msg, 'comando_lembrete', 1);
    RETURN QUERY SELECT v_msg; RETURN;
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
  -- 142: os lembretes da equipe que venceram. Erro aqui nunca para a agenda.
  BEGIN
    n := n + nai_lembretes_disparar();
  EXCEPTION WHEN OTHERS THEN
    RAISE WARNING 'nai_lembretes_disparar: %', SQLERRM;
  END;

  -- 141: o follow-up do dia seguinte. Um erro aqui nunca para a agenda das visitas.
  BEGIN
    n := n + nai_followup_rodar();
  EXCEPTION WHEN OTHERS THEN
    RAISE WARNING 'nai_followup_rodar: %', SQLERRM;
  END;

  RETURN n;
END;
$function$;

COMMIT;
