-- 334 -- O aviso de "imóvel saiu" só vai ao grupo Easy depois do SIM do Tel
--
-- Pedro, 09/10/2026: "tira essas notificações que a Nay fica mandando no grupo sobre imóveis indisponíveis,
-- tira tudo; deixa que o Tel responde e aprova cada um manualmente: no PV dele a Nay pergunta e só dispara no
-- grupo após o sim dele".
--
-- O que acontecia: `imoveis.disponivel` virou false por QUALQUER caminho (admin do site, captação, comando do
-- Tel) -> gatilho `imoveis_aviso_de_saida` -> fila `aviso_de_saida` -> cron de minuto em minuto
-- (`avisar_saidas.py`) -> card "🛑 ... alugado" no grupo IMÓVEIS PARA ANUNCIAR EASY. Em 10 dias foram 11
-- avisos, 9 deles de alguém mexendo na situação pelo admin, e nenhum passou por ele.
--
-- Como fica:
--   1. a saída continua entrando na fila (o gatilho não muda);
--   2. a agenda (`nai_agenda_tick`, a cada minuto) vê a saída nova e a Nay PERGUNTA ao Tel, no PV dele:
--      "Tel, saiu do ar: 3097 — ... (vendido). Aviso no grupo Easy? Responda SIM ou NÃO." Saídas do mesmo minuto
--      vão juntas, numa mensagem só. Das 22h às 7h ela espera amanhecer;
--   3. a resposta dele é comando: "sim" / "não" soltos valem para a ÚLTIMA pergunta; "SIM 3097", "NÃO 3097" e
--      "SIM TODOS" escolhem. Marcar a pergunta também vale (ele nunca marca: 0 de 68 mensagens em 10 dias);
--   4. o cron só enxerga o que tem SIM (`nay_saidas_a_avisar`). Sem resposta em 24 h a pergunta vence e o
--      grupo não é avisado. Imóvel que voltou a ficar disponível também não.
--
-- A chave `aviso_saida_pergunta` = 'nao' devolve o aviso automático de antes, sem migração.
--
-- Tabela NOVA (sem chave estrangeira, de propósito: FK tranca a `nai_saida` enquanto o ensaio está aberto).
BEGIN;
SET LOCAL lock_timeout = '3s';

CREATE TABLE IF NOT EXISTS public.aviso_de_saida_pergunta (
  id            bigserial   PRIMARY KEY,
  codigo        text        NOT NULL,
  motivo        text,
  marcado_em    timestamptz NOT NULL,              -- o mesmo de `aviso_de_saida`: amarra a pergunta a ESTA saída
  contato_id    bigint      NOT NULL,              -- quem foi perguntado (o Tel)
  saida_id      bigint,                            -- a mensagem da pergunta na `nai_saida`
  perguntado_em timestamptz NOT NULL DEFAULT now(),
  resposta      text CHECK (resposta IN ('sim', 'nao', 'vencida')),
  respondido_em timestamptz,
  turno_id      bigint,                            -- o turno em que ele respondeu
  UNIQUE (codigo, marcado_em)
);
CREATE INDEX IF NOT EXISTS aviso_de_saida_pergunta_aberta
    ON public.aviso_de_saida_pergunta (contato_id, perguntado_em) WHERE resposta IS NULL;
COMMENT ON TABLE public.aviso_de_saida_pergunta IS
  '334: a pergunta que a Nay faz ao Tel antes de avisar no grupo Easy que o imóvel saiu. Só resposta = sim libera o aviso.';
GRANT SELECT ON public.aviso_de_saida_pergunta TO nay_leitura;

INSERT INTO nai_config (chave, valor, descricao) VALUES
  ('aviso_saida_pergunta', 'sim',
   'Imóvel saiu do ar: sim = a Nay pergunta ao Tel no PV e só avisa no grupo Easy depois do SIM dele; nao = avisa sozinha, como era até 09/10.'),
  ('aviso_saida_validade_h', '24',
   'Quantas horas a pergunta do aviso de saída espera a resposta do Tel. Passou, vence e o grupo não é avisado.'),
  ('aviso_saida_hora_ini', '7', 'A pergunta do aviso de saída só é feita a partir desta hora (Manaus).'),
  ('aviso_saida_hora_fim', '22', 'A pergunta do aviso de saída não é feita desta hora em diante (Manaus).')
ON CONFLICT (chave) DO NOTHING;

-- "3097 — Smart Tower (Ponta Negra), vendido": como o imóvel aparece na pergunta e na resposta
CREATE OR REPLACE FUNCTION public.nay_saida_rotulo(p_codigo text, p_motivo text)
 RETURNS text
 LANGUAGE sql
 STABLE
 SET search_path TO 'public'
AS $function$
  SELECT p_codigo
         || coalesce((SELECT ' — ' || coalesce(nai_condominio_ok(i.condominio_nome), coalesce(nullif(i.tipo, ''), 'imóvel'))
                             || coalesce(' (' || nullif(i.bairro, '') || ')', '')
                        FROM imoveis i WHERE i.codigo::text = p_codigo), '')
         || ', ' || left(coalesce(nullif(btrim(p_motivo), ''), 'alugado'), 40);
$function$;

-- A LEITURA: este texto, deste contato, é resposta a uma pergunta de aviso? Não é: nenhuma linha.
-- Quem responde é só quem foi perguntado (o Tel, nas duas linhas dele).
CREATE OR REPLACE FUNCTION public.nay_saida_resposta_ler(p_contato bigint, p_texto text, p_citado text DEFAULT NULL)
 RETURNS TABLE(resposta text, ids bigint[], sem_pergunta text[])
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'public'
AS $function$
DECLARE
  s        text;
  v_resp   text;
  v_cods   text[];
  v_todos  boolean;
  v_irmaos bigint[];
  v_ids    bigint[];
  v_sem    text[] := '{}';
  v_saida  bigint;
  v_val    interval := make_interval(hours => greatest(nai_cfg_int('aviso_saida_validade_h', 24), 1));
  -- a primeira palavra decide; o resto só pode ser enfeite da mesma resposta, "todos" ou código
  c_sim    CONSTANT text := 'sim|s|ss|pode|avisa|avise|avisar|manda|mande|mandar|dispara|dispare|disparar|confirmo|confirmado';
  c_sim_r  CONSTANT text := 'sim|pode|avisa|avise|avisar|manda|mande|mandar|dispara|dispare|disparar|ai|la|no|na|o|a|os|as|e|do|da|de|grupo|easy|todos|todas|tudo|dois|duas|[0-9]{3,5}';
  c_nao    CONSTANT text := 'nao|n|nn|negativo|deixa|nem';
  c_nao_r  CONSTANT text := 'nao|deixa|precisa|avisa|avise|avisar|manda|mande|mandar|dispara|dispare|disparar|quieto|pra|la|assim|no|na|o|a|os|as|e|do|da|de|grupo|easy|nenhum|nenhuma|todos|todas|tudo|dois|duas|[0-9]{3,5}';
BEGIN
  IF p_contato IS NULL OR lower(coalesce(nai_cfg('aviso_saida_pergunta', 'sim'), 'sim')) <> 'sim' THEN RETURN; END IF;

  s := regexp_replace(lower(unaccent(coalesce(p_texto, ''))), '^\s*@?nay\M[\s,:;.!-]*', '');
  s := btrim(regexp_replace(s, '[^a-z0-9]+', ' ', 'g'));
  IF s = '' OR length(s) > 60 THEN RETURN; END IF;
  IF s ~ ('^(' || c_sim || ')( (' || c_sim_r || '))*$') THEN
    v_resp := 'sim';
  ELSIF s ~ ('^(' || c_nao || ')( (' || c_nao_r || '))*$') THEN
    v_resp := 'nao';
  ELSE
    RETURN;
  END IF;

  v_irmaos := coalesce(nai_contato_irmaos(p_contato), ARRAY[p_contato]);
  v_cods   := ARRAY(SELECT DISTINCT (m.x)[1] FROM regexp_matches(s, '\m([0-9]{3,5})\M', 'g') AS m(x));
  v_todos  := s ~ '\m(todos|todas|tudo|dois|duas|nenhum|nenhuma)\M';

  IF cardinality(v_cods) > 0 THEN
    -- "SIM 3097": pelo código, a pergunta desta saída (vale mudar de ideia depois do NÃO, até 7 dias).
    -- Um número só, que também é visita esperando aprovação: é da visita (141), não daqui.
    IF cardinality(v_cods) = 1 AND EXISTS (SELECT 1 FROM nai_visita x
                                            WHERE x.id = v_cods[1]::bigint AND x.estado = 'aguardando_rayssa') THEN
      RETURN;
    END IF;
    SELECT array_agg(x.id ORDER BY x.id) INTO v_ids
      FROM (SELECT DISTINCT ON (q.codigo) q.id
              FROM aviso_de_saida_pergunta q
              JOIN aviso_de_saida a ON a.codigo = q.codigo AND a.marcado_em = q.marcado_em
             WHERE q.contato_id = ANY (v_irmaos) AND q.codigo = ANY (v_cods)
               AND a.avisado_em IS NULL AND q.perguntado_em > now() - interval '7 days'
             ORDER BY q.codigo, q.id DESC) x;
    IF v_ids IS NULL THEN RETURN; END IF;
    v_sem := ARRAY(SELECT c FROM unnest(v_cods) c
                    WHERE NOT EXISTS (SELECT 1 FROM aviso_de_saida_pergunta q WHERE q.id = ANY (v_ids) AND q.codigo = c)
                    ORDER BY c);
  ELSIF nullif(btrim(coalesce(p_citado, '')), '') IS NOT NULL THEN
    -- marcou uma mensagem: só vale se for a pergunta. Marcou outra coisa, a resposta é para outra coisa.
    SELECT o.id INTO v_saida FROM nai_saida o
     WHERE o.message_id = btrim(p_citado) AND o.motivo = 'aviso_saida_pergunta' LIMIT 1;
    IF v_saida IS NULL THEN RETURN; END IF;
    SELECT array_agg(q.id ORDER BY q.id) INTO v_ids
      FROM aviso_de_saida_pergunta q
      JOIN aviso_de_saida a ON a.codigo = q.codigo AND a.marcado_em = q.marcado_em
     WHERE q.saida_id = v_saida AND q.contato_id = ANY (v_irmaos) AND a.avisado_em IS NULL;
  ELSE
    -- sem código e sem marcar: as perguntas ainda abertas. "todos" pega todas; solto, só a ÚLTIMA mensagem.
    SELECT array_agg(y.id ORDER BY y.id) INTO v_ids
      FROM (SELECT q.id, dense_rank() OVER (ORDER BY q.perguntado_em DESC, coalesce(q.saida_id, 0) DESC) AS ordem
              FROM aviso_de_saida_pergunta q
              JOIN aviso_de_saida a ON a.codigo = q.codigo AND a.marcado_em = q.marcado_em
             WHERE q.contato_id = ANY (v_irmaos) AND q.resposta IS NULL
               AND a.avisado_em IS NULL AND q.perguntado_em > now() - v_val) y
     WHERE v_todos OR y.ordem = 1;
  END IF;

  IF v_ids IS NULL THEN RETURN; END IF;
  RETURN QUERY SELECT v_resp, v_ids, v_sem;
END
$function$;

-- A mesma leitura, em sim/não, para o cabeçalho do turno. Nunca derruba a entrada da mensagem.
CREATE OR REPLACE FUNCTION public.nay_saida_resposta_valida(p_contato bigint, p_texto text, p_citado text DEFAULT NULL)
 RETURNS boolean
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'public'
AS $function$
BEGIN
  RETURN EXISTS (SELECT 1 FROM nay_saida_resposta_ler(p_contato, p_texto, p_citado));
EXCEPTION WHEN others THEN
  RETURN false;
END
$function$;

-- A RESPOSTA: grava o sim/não nas perguntas e devolve o que a Nay diz ao Tel. NULL = não era resposta de aviso.
CREATE OR REPLACE FUNCTION public.nay_saida_responder(p_turno bigint, p_contato bigint, p_texto text, p_citado text DEFAULT NULL)
 RETURNS text
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
DECLARE
  r        record;
  p        record;
  v_ok     text[] := '{}';
  v_voltou text[] := '{}';
  v_restam text[];
  v_msg    text := '';
  v_val    interval := make_interval(hours => greatest(nai_cfg_int('aviso_saida_validade_h', 24), 1));
BEGIN
  SELECT * INTO r FROM nay_saida_resposta_ler(p_contato, p_texto, p_citado);
  IF NOT FOUND THEN RETURN NULL; END IF;

  FOR p IN
    SELECT q.id, q.codigo, coalesce(a.motivo, q.motivo) AS motivo,
           coalesce((SELECT i.disponivel FROM imoveis i WHERE i.codigo::text = q.codigo), true) AS disponivel
      FROM aviso_de_saida_pergunta q
      JOIN aviso_de_saida a ON a.codigo = q.codigo AND a.marcado_em = q.marcado_em
     WHERE q.id = ANY (r.ids)
     ORDER BY q.id
       FOR UPDATE OF q
  LOOP
    IF p.disponivel THEN
      -- voltou a ficar disponível antes da resposta: não há o que avisar
      UPDATE aviso_de_saida_pergunta SET resposta = 'vencida', respondido_em = now(), turno_id = p_turno WHERE id = p.id;
      v_voltou := array_append(v_voltou, p.codigo);
    ELSE
      UPDATE aviso_de_saida_pergunta SET resposta = r.resposta, respondido_em = now(), turno_id = p_turno WHERE id = p.id;
      v_ok := array_append(v_ok, nay_saida_rotulo(p.codigo, p.motivo));
    END IF;
  END LOOP;

  IF cardinality(v_ok) > 0 THEN
    v_msg := CASE WHEN r.resposta = 'sim' THEN 'Combinado, aviso no grupo Easy: ' ELSE 'Combinado, não aviso no grupo: ' END
             || array_to_string(v_ok, '; ') || '.';
  END IF;
  IF cardinality(v_voltou) > 0 THEN
    v_msg := v_msg || E'\n' || 'Voltou a ficar disponível, então não tem aviso: ' || array_to_string(v_voltou, ', ') || '.';
  END IF;
  IF cardinality(r.sem_pergunta) > 0 THEN
    v_msg := v_msg || E'\n' || 'Não tenho pergunta de aviso em aberto para: ' || array_to_string(r.sem_pergunta, ', ') || '.';
  END IF;

  SELECT array_agg(q.codigo ORDER BY q.id) INTO v_restam
    FROM aviso_de_saida_pergunta q
    JOIN aviso_de_saida a ON a.codigo = q.codigo AND a.marcado_em = q.marcado_em
   WHERE q.contato_id = ANY (coalesce(nai_contato_irmaos(p_contato), ARRAY[p_contato]))
     AND q.resposta IS NULL AND a.avisado_em IS NULL AND q.perguntado_em > now() - v_val;
  IF v_restam IS NOT NULL THEN
    v_msg := v_msg || E'\n' || 'Ainda sem resposta: ' || array_to_string(v_restam, ', ')
             || '. Responda SIM ' || v_restam[1] || ', NÃO ' || v_restam[1] || ' ou SIM TODOS.';
  END IF;
  RETURN btrim(v_msg, E' \n');
END
$function$;

-- A PERGUNTA: a cada passada da agenda, o que saiu do ar e ainda não foi perguntado vai ao PV do Tel.
-- Nunca levanta erro: uma falha aqui não pode parar a agenda das visitas (30/09: 10 horas parada por um erro assim).
CREATE OR REPLACE FUNCTION public.nay_saidas_perguntar()
 RETURNS integer
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
DECLARE
  v_tel   bigint;
  v_hora  int;
  v_val   interval := make_interval(hours => greatest(nai_cfg_int('aviso_saida_validade_h', 24), 1));
  v_ids   bigint[];
  v_itens text[];
  v_texto text;
  v_saida bigint;
BEGIN
  IF lower(coalesce(nai_cfg('aviso_saida_pergunta', 'sim'), 'sim')) <> 'sim' THEN RETURN 0; END IF;

  -- o que não vale mais sai de aberto: prazo vencido, imóvel que voltou, saída que já é outra
  UPDATE aviso_de_saida_pergunta q
     SET resposta = 'vencida', respondido_em = now()
   WHERE q.resposta IS NULL
     AND (q.perguntado_em < now() - v_val
          OR NOT EXISTS (SELECT 1 FROM aviso_de_saida a JOIN imoveis i ON i.codigo::text = a.codigo
                          WHERE a.codigo = q.codigo AND a.marcado_em = q.marcado_em
                            AND a.avisado_em IS NULL AND NOT coalesce(i.disponivel, true)));

  -- parada, ou de noite: a pergunta espera (a saída continua na fila)
  IF nai_cfg('pausada', 'sim') <> 'nao' THEN RETURN 0; END IF;
  v_hora := extract(hour FROM now() AT TIME ZONE 'America/Manaus')::int;
  IF v_hora < nai_cfg_int('aviso_saida_hora_ini', 7) OR v_hora >= nai_cfg_int('aviso_saida_hora_fim', 22) THEN
    RETURN 0;
  END IF;
  v_tel := nai_contato_do_cadastro(nai_cfg('tel_telefone'), 'Tel');
  IF v_tel IS NULL THEN RETURN 0; END IF;

  WITH novas AS (
    INSERT INTO aviso_de_saida_pergunta (codigo, motivo, marcado_em, contato_id)
    SELECT a.codigo, a.motivo, a.marcado_em, v_tel
      FROM aviso_de_saida a
      JOIN imoveis i ON i.codigo::text = a.codigo
     WHERE a.avisado_em IS NULL
       AND a.marcado_em > now() - v_val
       AND NOT coalesce(i.disponivel, true)
     ORDER BY a.marcado_em
    ON CONFLICT (codigo, marcado_em) DO NOTHING
    RETURNING id, codigo, motivo)
  SELECT array_agg(n.id ORDER BY n.id), array_agg(nay_saida_rotulo(n.codigo, n.motivo) ORDER BY n.id)
    INTO v_ids, v_itens
    FROM novas n;
  IF v_ids IS NULL THEN RETURN 0; END IF;

  IF cardinality(v_ids) = 1 THEN
    v_texto := 'Tel, saiu do ar: ' || v_itens[1] || '.' || E'\n'
            || 'Aviso no grupo Easy? Responda SIM ou NÃO.';
  ELSE
    v_texto := 'Tel, saíram do ar:' || E'\n• ' || array_to_string(v_itens, E'\n• ') || E'\n'
            || 'Aviso no grupo Easy? SIM avisa todos, NÃO nenhum. Para escolher: SIM e os códigos.';
  END IF;
  v_saida := nai_avisar_tel(NULL, NULL, v_texto, 'aviso_saida_pergunta');
  UPDATE aviso_de_saida_pergunta SET saida_id = v_saida WHERE id = ANY (v_ids);
  RETURN cardinality(v_ids);
EXCEPTION WHEN others THEN
  RAISE WARNING 'nay_saidas_perguntar: %', SQLERRM;
  RETURN 0;
END
$function$;

-- A FILA DO GRUPO: com a chave ligada, só o que tem o SIM do Tel (e o prazo de 6 h conta do SIM).
DO $mig$
DECLARE v_def text := pg_get_functiondef('public.nay_saidas_a_avisar(integer)'::regprocedure);
BEGIN
  IF position('aviso_de_saida_pergunta' IN v_def) > 0 THEN
    RAISE EXCEPTION '334: já aplicada';
  END IF;
  IF position('AND a.marcado_em > now() - make_interval(hours => p_horas)' IN v_def) = 0 THEN
    RAISE EXCEPTION '334: nay_saidas_a_avisar mudou no banco; leia a função viva antes';
  END IF;
END
$mig$;

CREATE OR REPLACE FUNCTION public.nay_saidas_a_avisar(p_horas integer DEFAULT 6)
 RETURNS TABLE(codigo text, motivo text)
 LANGUAGE sql
 STABLE
AS $function$
  SELECT a.codigo, coalesce(a.motivo, 'alugado')
    FROM aviso_de_saida a
    JOIN imoveis i ON i.codigo::text = a.codigo
   WHERE a.avisado_em IS NULL
     AND NOT coalesce(i.disponivel, true)   -- voltou atrás: não avisa
     -- 334: com a pergunta ligada, só sai o que o Tel respondeu SIM (o prazo conta do SIM dele);
     -- desligada, vale a regra de antes (o prazo conta da saída), menos para o que ele já respondeu NÃO
     AND CASE WHEN lower(coalesce(nai_cfg('aviso_saida_pergunta', 'sim'), 'sim')) = 'sim'
              THEN EXISTS (SELECT 1 FROM aviso_de_saida_pergunta q
                            WHERE q.codigo = a.codigo AND q.marcado_em = a.marcado_em
                              AND q.resposta = 'sim'
                              AND q.respondido_em > now() - make_interval(hours => p_horas))
              ELSE a.marcado_em > now() - make_interval(hours => p_horas)
                   AND NOT EXISTS (SELECT 1 FROM aviso_de_saida_pergunta q
                                    WHERE q.codigo = a.codigo AND q.marcado_em = a.marcado_em AND q.resposta = 'nao') END
   ORDER BY a.marcado_em;
$function$;

-- O CABEÇALHO DO TURNO: a resposta do Tel é comando (papel 'tel' mesmo chegando pela linha @lid, e comando_nai)
DO $mig$
DECLARE
  v_def text := pg_get_functiondef('public.nai_abrir_turno(text,text,text,text,bigint[])'::regprocedure);
  v_a1  text := $v$-- 141: a aprovacao da visita$v$;
  v_n1  text := $n$-- 334: o SIM/NAO do Tel à pergunta "aviso no grupo que o imóvel saiu?"
       OR nay_saida_resposta_valida(v_contato, v_texto, p_citado_id)
       -- 141: a aprovacao da visita$n$;
  v_a2  text := $v$-- 141: SIM/NAO da aprovacao da visita$v$;
  v_n2  text := $n$-- 334: SIM/NAO do Tel à pergunta do aviso de saída
                    OR nay_saida_resposta_valida(v_contato, v_texto, p_citado_id)
                    -- 141: SIM/NAO da aprovacao da visita$n$;
BEGIN
  IF position('nay_saida_resposta_valida' IN v_def) > 0 THEN
    RAISE EXCEPTION '334: nai_abrir_turno já remendada';
  END IF;
  IF (length(v_def) - length(replace(v_def, v_a1, ''))) / length(v_a1) <> 1
     OR (length(v_def) - length(replace(v_def, v_a2, ''))) / length(v_a2) <> 1 THEN
    RAISE EXCEPTION '334: os trechos de nai_abrir_turno mudaram no banco; leia a função viva antes';
  END IF;
  EXECUTE replace(replace(v_def, v_a1, v_n1), v_a2, v_n2);
END
$mig$;

-- O COMANDO: o ramo da resposta vem antes da aprovação da visita (só responde quando há pergunta de aviso)
DO $mig$
DECLARE
  v_def   text := pg_get_functiondef('public.nai_comando_tel(bigint,text)'::regprocedure);
  v_velho text := $v$  -- 141: SIM <n> / NAO <n> / TELEFONE <n> <numero> -- a aprovacao da visita.$v$;
  v_novo  text := $n$  -- 334: SIM / NAO do Tel à pergunta "aviso no grupo Easy que o imóvel saiu?". Só devolve
  -- texto quando a mensagem é mesmo resposta de uma pergunta de aviso em aberto (e de quem foi perguntado).
  v_msg := nay_saida_responder(p_turno, t.contato_id, s,
             (SELECT x.citado_id FROM mensagens x
               WHERE x.id = ANY (coalesce(t.msg_ids, '{}')) AND nullif(btrim(x.citado_id), '') IS NOT NULL
               ORDER BY x.id DESC LIMIT 1));
  IF v_msg IS NOT NULL THEN
    PERFORM nai_enfileirar_texto(p_turno, NULL, t.contato_id, 'turno', v_msg, 'comando_aviso_saida', 1);
    RETURN QUERY SELECT v_msg; RETURN;
  END IF;

  -- 141: SIM <n> / NAO <n> / TELEFONE <n> <numero> -- a aprovacao da visita.$n$;
BEGIN
  IF position('nay_saida_responder' IN v_def) > 0 THEN
    RAISE EXCEPTION '334: nai_comando_tel já remendada';
  END IF;
  IF (length(v_def) - length(replace(v_def, v_velho, ''))) / length(v_velho) <> 1 THEN
    RAISE EXCEPTION '334: o trecho de nai_comando_tel mudou no banco; leia a função viva antes';
  END IF;
  EXECUTE replace(v_def, v_velho, v_novo);
END
$mig$;

-- A AGENDA: pergunta a cada passada, logo depois de fechar as visitas de dia passado (333)
DO $mig$
DECLARE
  v_def   text := pg_get_functiondef('public.nai_agenda_tick()'::regprocedure);
  v_velho text := $v$  n := n + nai_visitas_fechar_dia_passado();$v$;
  v_novo  text := $n$  n := n + nai_visitas_fechar_dia_passado();

  -- 334: imóvel que saiu do ar -> a Nay pergunta ao Tel se avisa no grupo Easy (o grupo só recebe depois do SIM)
  n := n + nay_saidas_perguntar();$n$;
BEGIN
  IF position('nay_saidas_perguntar' IN v_def) > 0 THEN
    RAISE EXCEPTION '334: nai_agenda_tick já remendada';
  END IF;
  IF (length(v_def) - length(replace(v_def, v_velho, ''))) / length(v_velho) <> 1 THEN
    RAISE EXCEPTION '334: o trecho de nai_agenda_tick mudou no banco; leia a função viva antes';
  END IF;
  EXECUTE replace(v_def, v_velho, v_novo);
END
$mig$;

-- O que já estava na fila e ainda não foi ao grupo passa a esperar a pergunta (nada sai sem o SIM)
SELECT count(*) AS saidas_que_agora_esperam_a_pergunta
  FROM aviso_de_saida a JOIN imoveis i ON i.codigo::text = a.codigo
 WHERE a.avisado_em IS NULL AND NOT coalesce(i.disponivel, true)
   AND a.marcado_em > now() - interval '24 hours';

COMMIT;
