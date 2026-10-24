-- 485 -- Disparo da lista 4 com o outro_imovel_sair_07, 250 por dia, nunca no domingo
--
-- Pedro, 24/10/2026: "outro_imovel_sair_07: pode disparar essa para o resto da base, mas vai com calma, só podemos 250
-- hoje, o resto só segunda". O portão do disparo do Python (captacao_py_disparo_motivo) não tinha limite por dia nem
-- parada de domingo; ganha as duas:
--   python_limite_dia      quantos disparos por dia (dia de Manaus) E em 24 h seguidas (o limite da Meta, TIER_250, conta
--                          as 24 h): passou, 'limite do dia'. Vazio = sem limite (como era).
--   python_sem_disparo_dow dias da semana (isodow, 7 = domingo) em que o disparo não sai.
-- E: os 635+ da lista 4 passam para o modelo outro_imovel_sair_07 (o texto do outro_imovel_04 com "Excluir meu contato",
-- Utilidade, aprovado), o intervalo vai de 18-22 s para 30-40 s ("com calma": o número está com qualidade vermelha) e
-- python_disparo = sim. Desligar tudo na hora: UPDATE captacao_config SET valor = 'nao' WHERE chave = 'python_disparo'.
BEGIN;
SET LOCAL lock_timeout = '3s';

INSERT INTO captacao_config (chave, valor, nota) VALUES
  ('python_limite_dia', '250', '485: disparos do Python por dia (Manaus) e em 24 h seguidas; o limite da Meta (TIER_250).'),
  ('python_sem_disparo_dow', '7', '485: dias da semana (isodow, 7 = domingo) sem disparo do Python.')
ON CONFLICT (chave) DO UPDATE SET valor = EXCLUDED.valor, nota = EXCLUDED.nota;

CREATE OR REPLACE FUNCTION public.captacao_py_disparo_motivo()
 RETURNS text
 LANGUAGE sql
 STABLE
AS $function$
  SELECT CASE
    WHEN coalesce((SELECT valor FROM captacao_config WHERE chave = 'python_disparo'), 'nao') <> 'sim' THEN 'desligado'
    WHEN NOT captacao_no_horario(now()) THEN 'fora do horário'
    WHEN extract(isodow FROM now() AT TIME ZONE 'America/Manaus')::int::text = ANY (string_to_array(
           regexp_replace(coalesce((SELECT valor FROM captacao_config WHERE chave = 'python_sem_disparo_dow'), ''), '\s', '', 'g'), ','))
      THEN 'dia sem disparo (485)'
    WHEN coalesce(nullif(btrim((SELECT valor FROM captacao_config WHERE chave = 'python_limite_dia')), ''), '0')::int > 0
         AND GREATEST(
               (SELECT count(*) FROM captacao_mensagens m WHERE m.direcao = 'enviada' AND m.origem = 'disparo' AND m.status <> 'Falhou'
                   AND m.criada_em >= date_trunc('day', now() AT TIME ZONE 'America/Manaus') AT TIME ZONE 'America/Manaus'),
               (SELECT count(*) FROM captacao_mensagens m WHERE m.direcao = 'enviada' AND m.origem = 'disparo' AND m.status <> 'Falhou'
                   AND m.criada_em > now() - interval '24 hours'))
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

UPDATE captacao_leads SET modelo_abertura = 'outro_imovel_sair_07', atualizado_em = now()
 WHERE status = 'novo' AND quem_importou LIKE 'Pedro (lista 4%' AND modelo_abertura = 'outro_imovel_04';

UPDATE captacao_config SET valor = '30' WHERE chave = 'python_disparo_seg_min';
UPDATE captacao_config SET valor = '40' WHERE chave = 'python_disparo_seg_max';
UPDATE captacao_config SET valor = 'sim' WHERE chave = 'python_disparo';

SELECT captacao_py_disparo_motivo() AS motivo_agora,
       (SELECT count(*) FROM captacao_leads WHERE status = 'novo' AND modelo_abertura = 'outro_imovel_sair_07') AS leads_no_sair_07,
       (SELECT count(*) FROM captacao_py_fila_do_disparo() i JOIN captacao_leads l ON l.id = i WHERE l.modelo_abertura = 'outro_imovel_sair_07') AS na_fila;
COMMIT;
