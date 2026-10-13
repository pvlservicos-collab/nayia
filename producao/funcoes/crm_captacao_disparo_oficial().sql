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
                WHEN l.quem_importou LIKE 'Pedro (lista 6:%' THEN 'lista6'
                WHEN l.quem_importou LIKE 'Pedro (lista 8:%' THEN 'lista8'
                ELSE 'anterior' END AS lista
      FROM captacao_leads l
  ), fila AS (
    SELECT d.lista FROM captacao_py_fila_do_disparo() f(id) JOIN da_lista d ON d.id = f.id
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
  ), m AS (SELECT captacao_py_disparo_motivo() AS motivo
  ), nomes AS (SELECT * FROM (VALUES
      (1, 'lista6', 'Donos com imóvel disponível', 'Lista 6: donos com imóvel disponível no cadastro (entraram em 12/10)'),
      (2, 'lista8', 'Donos da planilha antiga', 'Lista 8: donos da planilha antiga que nunca viraram imóvel (entraram em 12/10)'),
      (3, 'anterior', 'Campanha anterior', 'Proprietários das listas de antes de 12/10 que nunca receberam nada nosso'),
      (4, 'retomada', 'Não responderam no outro número',
          'Receberam a abertura pela Z-API, nunca responderam, e recebem o modelo oficial uma vez (323)')
    ) AS v(ordem, chave, rotulo, titulo))
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
    'listas', (SELECT jsonb_agg(jsonb_build_object(
                        'chave', n.chave, 'rotulo', n.rotulo, 'titulo', n.titulo,
                        'enviados', (SELECT count(*) FROM saiu s WHERE s.lista = n.chave),
                        'faltam', (SELECT count(*) FROM fila f WHERE f.lista = n.chave)) ORDER BY n.ordem)
                 FROM nomes n));
$function$;
