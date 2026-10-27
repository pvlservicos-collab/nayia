-- 503 (Pedro, 26/10/2026, 23h Manaus): "divide a lista, quero ver qual horário de Manaus é melhor, 07:30 ou 18:30".
--
-- O disparo dos donos pela API oficial (nay-captacao em Python) sai em DOIS horários e cada um tem a SUA metade da fila:
--   python_horarios = '07:30,18:30'  -> o 1º horário leva os leads de id par, o 2º os de id ímpar (id % n = posição - 1)
--   python_lote_por_horario = 125    -> no máximo 125 por horário (2 x 125 = os 250 do python_limite_dia)
--   python_horario_duracao_min = 120 -> o horário fica aberto 2 h a partir do início (125 x ~35 s = ~75 min)
-- Fora desses horários, ou com o lote do horário cumprido, o motivo é 'fora do horário' (a barrinha do CRM mostra
-- quando volta, sem publicar o CRM). Com horários ligados o limite do dia conta só o dia de Manaus: o de 24 h corridas
-- seguraria o lote das 07:30 até o das 18:30 da véspera sair da conta. Domingo continua sem disparo (python_sem_disparo_dow).
-- A janela da captação (captacao_no_horario: 08:00-19:00, pausa 12:00-13:30) não muda: a OLX e o n8n velho continuam nela.
-- Para voltar ao de antes: python_horarios = '' (vazio).
-- Para ver qual horário ganha: SELECT * FROM captacao_py_horarios_placar();
BEGIN;
SET LOCAL lock_timeout = '3s';

INSERT INTO captacao_config (chave, valor, nota) VALUES
  ('python_horarios', '07:30,18:30',
   '503: horários (Manaus) do disparo do Python; cada um leva a sua metade da fila (id par = 1º, ímpar = 2º). Vazio = a janela de sempre (captacao_no_horario).'),
  ('python_lote_por_horario', '125', '503: quantos disparos no máximo em cada horário de python_horarios.'),
  ('python_horario_duracao_min', '120', '503: quantos minutos cada horário de python_horarios fica aberto.'),
  ('python_horarios_desde', to_char(now() AT TIME ZONE 'America/Manaus', 'YYYY-MM-DD HH24:MI'),
   '503: início do teste de horários; captacao_py_horarios_placar() conta a partir daqui (Manaus).')
ON CONFLICT (chave) DO UPDATE SET valor = EXCLUDED.valor, nota = EXCLUDED.nota;

-- o horário de python_horarios em que p_ts cai (posição na lista, a hora escrita, o início, quantos horários há)
CREATE OR REPLACE FUNCTION public.captacao_py_horario(p_ts timestamp with time zone DEFAULT now())
 RETURNS TABLE(n integer, hora text, inicio timestamp with time zone, total integer)
 LANGUAGE sql
 STABLE
AS $function$
  WITH h AS (
    SELECT x.hora, x.n::int AS n, count(*) OVER ()::int AS total
      FROM unnest(string_to_array(regexp_replace(captacao_cfg('python_horarios', ''), '\s', '', 'g'), ',')) WITH ORDINALITY AS x(hora, n)
     WHERE x.hora ~ '^\d{1,2}:\d{2}$'
  )
  SELECT h.n, h.hora, (date_trunc('day', p_ts AT TIME ZONE 'America/Manaus') + h.hora::time) AT TIME ZONE 'America/Manaus', h.total
    FROM h
   WHERE p_ts >= (date_trunc('day', p_ts AT TIME ZONE 'America/Manaus') + h.hora::time) AT TIME ZONE 'America/Manaus'
     AND p_ts <  (date_trunc('day', p_ts AT TIME ZONE 'America/Manaus') + h.hora::time
                  + make_interval(mins => captacao_cfg('python_horario_duracao_min', '120')::int)) AT TIME ZONE 'America/Manaus'
   ORDER BY h.n
   LIMIT 1;
$function$;

-- o disparo do Python pode sair em p_ts? Sem python_horarios é a janela de sempre (captacao_no_horario).
CREATE OR REPLACE FUNCTION public.captacao_py_no_horario(p_ts timestamp with time zone DEFAULT now())
 RETURNS boolean
 LANGUAGE sql
 STABLE
AS $function$
  SELECT CASE WHEN captacao_cfg('python_horarios', '') = '' THEN captacao_no_horario(p_ts)
              ELSE EXISTS (
                SELECT 1 FROM captacao_py_horario(p_ts) h
                 WHERE NOT extract(isodow FROM p_ts AT TIME ZONE 'America/Manaus')::int::text = ANY (string_to_array(
                             regexp_replace(captacao_cfg('python_sem_disparo_dow', ''), '\s', '', 'g'), ','))
                   AND (SELECT count(*) FROM captacao_mensagens m
                         WHERE m.direcao = 'enviada' AND m.origem = 'disparo' AND m.status <> 'Falhou'
                           AND m.criada_em >= h.inicio AND m.criada_em <= p_ts)
                       < captacao_cfg('python_lote_por_horario', '125')::int)
         END;
$function$;

CREATE OR REPLACE FUNCTION public.captacao_py_disparo_motivo()
 RETURNS text
 LANGUAGE sql
 STABLE
AS $function$
  SELECT CASE
    WHEN coalesce((SELECT valor FROM captacao_config WHERE chave = 'python_disparo'), 'nao') <> 'sim' THEN 'desligado'
    -- 503: com python_horarios, só nos horários e até o lote de cada um
    WHEN NOT captacao_py_no_horario(now()) THEN 'fora do horário'
    WHEN extract(isodow FROM now() AT TIME ZONE 'America/Manaus')::int::text = ANY (string_to_array(
           regexp_replace(coalesce((SELECT valor FROM captacao_config WHERE chave = 'python_sem_disparo_dow'), ''), '\s', '', 'g'), ','))
      THEN 'dia sem disparo (485)'
    WHEN coalesce(nullif(btrim((SELECT valor FROM captacao_config WHERE chave = 'python_limite_dia')), ''), '0')::int > 0
         AND GREATEST(
               (SELECT count(*) FROM captacao_mensagens m WHERE m.direcao = 'enviada' AND m.origem = 'disparo' AND m.status <> 'Falhou'
                   AND m.criada_em >= date_trunc('day', now() AT TIME ZONE 'America/Manaus') AT TIME ZONE 'America/Manaus'),
               -- 503: com python_horarios, as 24 h corridas seguravam o lote das 07:30 (o das 18:30 da véspera ainda contava)
               CASE WHEN captacao_cfg('python_horarios', '') <> '' THEN 0 ELSE
               (SELECT count(*) FROM captacao_mensagens m WHERE m.direcao = 'enviada' AND m.origem = 'disparo' AND m.status <> 'Falhou'
                   AND m.criada_em > now() - interval '24 hours') END)
             >= (SELECT btrim(valor)::int FROM captacao_config WHERE chave = 'python_limite_dia')
      THEN 'limite do dia (485)'
    WHEN (SELECT count(*) FILTER (WHERE u.status = 'Falhou') FROM (
            SELECT m.status FROM captacao_mensagens m WHERE m.direcao = 'enviada' AND m.origem = 'disparo'
             ORDER BY m.id DESC LIMIT 3) u) >= 3 THEN 'os 3 últimos disparos falharam'
    WHEN EXISTS (SELECT 1 FROM captacao_leads r WHERE r.status = 'reservado') THEN 'há um lead reservado'
    WHEN EXISTS (SELECT 1 FROM captacao_mensagens m WHERE m.direcao = 'enviada' AND m.origem = 'disparo' AND m.status <> 'Falhou'
                    AND m.criada_em > now() - make_interval(secs => 0.6 * coalesce(
                          (SELECT nullif(btrim(valor), '')::numeric FROM captacao_config WHERE chave = 'python_disparo_seg_min'), 45)))
      THEN 'ainda no intervalo do último disparo'
  END;
$function$;

CREATE OR REPLACE FUNCTION public.captacao_py_reservar_disparo()
 RETURNS TABLE(lead_id bigint, telefone text, nome text, tratamento text)
 LANGUAGE plpgsql
AS $function$
#variable_conflict use_column
DECLARE
  v_id bigint;
  v_h record;
BEGIN
  INSERT INTO captacao_config (chave, valor, nota)
  VALUES ('_py_disparo_em', to_char(now() AT TIME ZONE 'America/Manaus', 'YYYY-MM-DD HH24:MI:SS'),
          'Última vez que o disparo do Python olhou a fila. Parou de avançar = serviço parado.')
  ON CONFLICT (chave) DO UPDATE SET valor = EXCLUDED.valor;
  -- o reservado que não virou envio volta para a fila em 30 minutos
  UPDATE captacao_leads l
     SET status = CASE WHEN l.ultimo_envio_em IS NULL THEN 'novo' ELSE 'enviado' END, atualizado_em = now()
   WHERE l.status = 'reservado' AND l.atualizado_em < now() - interval '30 minutes';
  IF captacao_py_disparo_motivo() IS NOT NULL THEN RETURN; END IF;

  -- 503: cada horário de python_horarios leva a sua metade da fila (1º horário = id par, 2º = ímpar)
  SELECT * INTO v_h FROM captacao_py_horario(now());
  SELECT f.id INTO v_id FROM captacao_py_fila_do_disparo() AS f(id)
   WHERE v_h.n IS NULL OR f.id % v_h.total = v_h.n - 1
   LIMIT 1;
  IF v_id IS NULL THEN RETURN; END IF;
  PERFORM 1 FROM captacao_leads l WHERE l.id = v_id FOR UPDATE SKIP LOCKED;
  -- a parede da 308 mora neste UPDATE: corretor ou parceiro é marcado e a reserva não acontece.
  -- 323: o 'enviado' da retomada pelo oficial também pode ser reservado.
  UPDATE captacao_leads l SET status = 'reservado', atualizado_em = now()
   WHERE l.id = v_id
     AND (l.status IN ('novo', 'erro')
          OR (l.status = 'enviado' AND EXISTS (SELECT 1 FROM captacao_retomada_oficial r WHERE r.lead_id = l.id)));
  IF NOT EXISTS (SELECT 1 FROM captacao_leads l WHERE l.id = v_id AND l.status = 'reservado') THEN RETURN; END IF;
  -- daqui para a frente este lead é atendido pela Nay em Python
  INSERT INTO captacao_motor (lead_id) VALUES (v_id) ON CONFLICT (lead_id) DO NOTHING;
  RETURN QUERY SELECT l.id, l.telefone, l.nome, l.tratamento FROM captacao_leads l WHERE l.id = v_id;
END
$function$;

-- 503: qual horário responde melhor. Conta os disparos desde python_horarios_desde, pelo horário em que saíram;
-- respondeu = escreveu em até 24 h depois do modelo; pediu para sair = opt_out (o botão "Excluir meu contato").
CREATE OR REPLACE FUNCTION public.captacao_py_horarios_placar()
 RETURNS TABLE(horario text, enviados bigint, responderam bigint, pct_resposta numeric, pediram_sair bigint,
               minutos_ate_responder_mediana numeric)
 LANGUAGE sql
 STABLE
AS $function$
  WITH d AS (
    SELECT m.lead_id, m.criada_em, (SELECT h.hora FROM captacao_py_horario(m.criada_em) h) AS hora,
           (SELECT min(r.criada_em) FROM captacao_mensagens r
             WHERE r.lead_id = m.lead_id AND r.direcao = 'recebida'
               AND r.criada_em > m.criada_em AND r.criada_em < m.criada_em + interval '24 hours') AS resposta_em
      FROM captacao_mensagens m
     WHERE m.direcao = 'enviada' AND m.origem = 'disparo' AND m.status <> 'Falhou'
       AND m.criada_em >= (captacao_cfg('python_horarios_desde', '2026-10-26 23:00')::timestamp AT TIME ZONE 'America/Manaus')
  )
  SELECT coalesce(d.hora, 'fora dos horários'), count(*), count(d.resposta_em),
         round(100.0 * count(d.resposta_em) / nullif(count(*), 0), 1),
         count(*) FILTER (WHERE l.opt_out),
         round((percentile_cont(0.5) WITHIN GROUP (ORDER BY extract(epoch FROM d.resposta_em - d.criada_em) / 60))::numeric, 0)
    FROM d LEFT JOIN captacao_leads l ON l.id = d.lead_id
   GROUP BY d.hora
   ORDER BY d.hora;
$function$;

-- a barrinha do CRM: "volta em" pelo horário do Python (503), não pela janela da captação
CREATE OR REPLACE FUNCTION public.crm_captacao_disparo_oficial()
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
 SET jit TO 'off'
AS $function$
  WITH da_lista AS (       -- de qual lista é cada lead
    SELECT l.id,
           CASE WHEN EXISTS (SELECT 1 FROM captacao_retomada_oficial r WHERE r.lead_id = l.id) THEN 'retomada'
                WHEN l.quem_importou LIKE 'Pedro (lista 5:%' THEN 'lista5'   -- 449
                WHEN l.quem_importou LIKE 'Pedro (lista 4:%' THEN 'lista4'   -- 456
                WHEN l.quem_importou LIKE 'Pedro (lista 3:%' THEN 'lista3'   -- 456
                WHEN l.quem_importou LIKE 'Pedro (lista 6:%' THEN 'lista6'
                WHEN l.quem_importou LIKE 'Pedro (lista 8:%' THEN 'lista8'
                ELSE 'anterior' END AS lista
      FROM captacao_leads l
  ), fila AS MATERIALIZED (
    SELECT d.lista, f.id FROM captacao_py_fila_do_disparo() f(id) JOIN da_lista d ON d.id = f.id
  ), esperando AS (        -- 449: na fila, mas o modelo próprio dele ainda não foi aprovado pela Meta
    SELECT d.lista, l.modelo_abertura
      FROM captacao_leads l JOIN da_lista d ON d.id = l.id
     WHERE l.modelo_abertura IS NOT NULL AND l.status = 'novo' AND l.ultimo_envio_em IS NULL
       AND NOT l.opt_out AND l.humano_assumiu_em IS NULL
       AND NOT l.modelo_abertura = ANY (regexp_split_to_array(
             coalesce((SELECT c.valor FROM captacao_config c WHERE c.chave = 'python_modelos_aprovados'), ''), '\s*,\s*'))
  ), saiu AS (
    -- quem já recebeu o modelo oficial do disparo (o lead entra em captacao_motor ao receber)
    SELECT d.lista
      FROM captacao_motor mt JOIN da_lista d ON d.id = mt.lead_id
     WHERE EXISTS (SELECT 1 FROM captacao_mensagens m
                    WHERE m.lead_id = mt.lead_id AND m.direcao = 'enviada' AND m.origem = 'disparo' AND m.status <> 'Falhou')
  ), hoje AS (
    SELECT count(*) FILTER (WHERE m.status <> 'Falhou') AS ok, count(*) FILTER (WHERE m.status = 'Falhou') AS falhou,
           max(m.criada_em) AS ultimo
      FROM captacao_mensagens m JOIN captacao_motor mt ON mt.lead_id = m.lead_id
     WHERE m.direcao = 'enviada' AND m.origem = 'disparo'
       AND (m.criada_em AT TIME ZONE 'America/Manaus')::date = (now() AT TIME ZONE 'America/Manaus')::date
  ), ritmo AS (
    SELECT coalesce((SELECT nullif(btrim(valor), '')::numeric FROM captacao_config WHERE chave = 'python_disparo_seg_min'), 45) AS menor,
           coalesce((SELECT nullif(btrim(valor), '')::numeric FROM captacao_config WHERE chave = 'python_disparo_seg_max'), 75) AS maior
  ), m AS (
    -- 449: sem ninguém pronto na fila e com gente esperando a aprovação do modelo, o motivo é a Meta
    SELECT coalesce(captacao_py_disparo_motivo(),
                    CASE WHEN NOT EXISTS (SELECT 1 FROM fila) AND EXISTS (SELECT 1 FROM esperando)
                         THEN 'esperando a Meta aprovar o modelo ' || (SELECT string_agg(DISTINCT e.modelo_abertura, ', ') FROM esperando e) END) AS motivo
  ), nomes AS (SELECT * FROM (VALUES
      (-1, 'lista4', 'Donos que só têm imóvel vendido', 'Lista 4: donos que só têm imóvel vendido, modelo outro_imovel_04 (imóvel para vender), entraram em 21/10'),
      (-2, 'lista3', 'Donos com imóvel removido ou arquivado', 'Lista 3: donos com imóvel removido ou arquivado, modelo outro_imovel_04 (imóvel para vender), entraram em 21/10'),
      (-3, 'lista5', 'Donos com imóvel alugado', 'Lista 5: donos com imóvel alugado por nós, modelo outro_imovel_04 ("possui outro imóvel disponível?"), entraram em 20/10'),
      (1, 'lista6', 'Donos com imóvel disponível', 'Lista 6: donos com imóvel disponível no cadastro (entraram em 12/10)'),
      (2, 'lista8', 'Donos da planilha antiga', 'Lista 8: donos da planilha antiga que nunca viraram imóvel (entraram em 12/10)'),
      (3, 'anterior', 'Campanha anterior', 'Proprietários das listas de antes de 12/10 que nunca receberam nada nosso'),
      (4, 'retomada', 'Não responderam no outro número',
          'Receberam a abertura pela Z-API, nunca responderam, e recebem o modelo oficial uma vez (323)')
    ) AS v(ordem, chave, rotulo, titulo))
  SELECT jsonb_build_object(
    'ligado', coalesce((SELECT valor FROM captacao_config WHERE chave = 'python_disparo'), 'nao') = 'sim',
    'motivo', (SELECT motivo FROM m),
    -- fora do horário: o próximo minuto em que o disparo pode sair (almoço, noite, fim de semana; 503: os horários do Python)
    -- com python_horarios só os inícios dos horários são candidatos (minuto a minuto levava 5 s)
    'volta_em', CASE WHEN (SELECT motivo FROM m) <> 'fora do horário' THEN NULL
                     WHEN captacao_cfg('python_horarios', '') = '' THEN
                  (SELECT min(t) FROM generate_series(date_trunc('minute', now()) + interval '1 minute',
                                                      now() + interval '3 days', interval '1 minute') t
                    WHERE captacao_no_horario(t))
                     ELSE
                  (SELECT min(t) FROM (
                     SELECT (date_trunc('day', now() AT TIME ZONE 'America/Manaus') + make_interval(days => d) + h.hora::time)
                              AT TIME ZONE 'America/Manaus' AS t
                       FROM generate_series(0, 3) d,
                            unnest(string_to_array(regexp_replace(captacao_cfg('python_horarios', ''), '\s', '', 'g'), ',')) h(hora)
                      WHERE h.hora ~ '^\d{1,2}:\d{2}$') c
                    WHERE c.t > now() AND captacao_py_no_horario(c.t)) END,
    'hoje', (SELECT ok FROM hoje), 'falharam_hoje', (SELECT falhou FROM hoje), 'ultimo_em', (SELECT ultimo FROM hoje),
    'seg_medio', (SELECT (menor + maior) / 2 FROM ritmo),
    'listas', (SELECT jsonb_agg(jsonb_build_object(
                        'chave', n.chave, 'rotulo', n.rotulo, 'titulo', n.titulo,
                        'enviados', (SELECT count(*) FROM saiu s WHERE s.lista = n.chave),
                        'faltam', (SELECT count(*) FROM fila f WHERE f.lista = n.chave)
                                  + (SELECT count(*) FROM esperando e WHERE e.lista = n.chave),
                        'esperando', (SELECT count(*) FROM esperando e WHERE e.lista = n.chave)) ORDER BY n.ordem)
                 FROM nomes n));
$function$;

COMMIT;
