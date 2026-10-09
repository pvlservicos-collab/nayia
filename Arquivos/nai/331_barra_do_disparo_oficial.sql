-- 331 -- A barrinha do disparo pela API oficial: qual lista está saindo e quanto falta
--
-- Pedro, 09/10/2026, na aba Oficial do CRM: "em cima desses filtros quero uma barrinha para eu saber qual lista está
-- sendo disparada e quanto falta para acabar".
--
-- O disparo do Python (serviço nay-captacao, chave `python_disparo`) tira um lead por vez de
-- captacao_py_fila_do_disparo(), que tem duas listas, nesta ordem:
--   1. NUNCA CHAMADOS: status novo/erro, nunca receberam nada nosso;
--   2. RETOMADA (323): receberam a abertura pela Z-API e nunca responderam; recebem o modelo oficial uma vez.
-- Esta função conta, para cada lista, quantos já receberam o modelo oficial e quantos ainda estão na fila, e diz se o
-- disparo está saindo agora (e, se não, por quê e quando volta). Só lê.
BEGIN;
SET LOCAL lock_timeout = '3s';

CREATE OR REPLACE FUNCTION public.crm_captacao_disparo_oficial()
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
 SET jit TO 'off'
AS $function$
  WITH fila AS (
    SELECT (l.status = 'enviado') AS retomada
      FROM captacao_py_fila_do_disparo() f(id) JOIN captacao_leads l ON l.id = f.id
  ), saiu AS (
    -- quem já recebeu o modelo oficial do disparo (o lead entra em captacao_motor ao receber)
    SELECT EXISTS (SELECT 1 FROM captacao_retomada_oficial r WHERE r.lead_id = mt.lead_id) AS retomada
      FROM captacao_motor mt
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
  ), m AS (SELECT captacao_py_disparo_motivo() AS motivo)
  SELECT jsonb_build_object(
    'ligado', coalesce((SELECT valor FROM captacao_config WHERE chave = 'python_disparo'), 'nao') = 'sim',
    'motivo', (SELECT motivo FROM m),
    -- fora do horário: o próximo minuto em que o disparo pode sair (almoço, noite, fim de semana)
    'volta_em', CASE WHEN (SELECT motivo FROM m) = 'fora do horário' THEN
                  (SELECT min(t) FROM generate_series(date_trunc('minute', now()) + interval '1 minute',
                                                      now() + interval '3 days', interval '1 minute') t
                    WHERE captacao_no_horario(t)) END,
    'hoje', (SELECT ok FROM hoje), 'falharam_hoje', (SELECT falhou FROM hoje), 'ultimo_em', (SELECT ultimo FROM hoje),
    'seg_medio', (SELECT (menor + maior) / 2 FROM ritmo),
    'listas', jsonb_build_array(
      jsonb_build_object('chave', 'nunca_chamados', 'rotulo', 'Nunca chamados',
                         'titulo', 'Proprietários que nunca receberam nada nosso',
                         'enviados', (SELECT count(*) FROM saiu WHERE NOT retomada),
                         'faltam', (SELECT count(*) FROM fila WHERE NOT retomada)),
      jsonb_build_object('chave', 'retomada', 'rotulo', 'Não responderam no outro número',
                         'titulo', 'Receberam a abertura pela Z-API, nunca responderam, e recebem o modelo oficial uma vez (323)',
                         'enviados', (SELECT count(*) FROM saiu WHERE retomada),
                         'faltam', (SELECT count(*) FROM fila WHERE retomada))));
$function$;
COMMENT ON FUNCTION public.crm_captacao_disparo_oficial() IS
  '331: a barrinha do disparo pela API oficial no CRM: cada lista da fila (nunca chamados, retomada), quantos já saíram, quantos faltam, e se está saindo agora.';
GRANT EXECUTE ON FUNCTION public.crm_captacao_disparo_oficial() TO nay_disparo;

COMMIT;
