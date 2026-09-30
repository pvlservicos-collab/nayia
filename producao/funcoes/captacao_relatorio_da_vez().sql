CREATE OR REPLACE FUNCTION public.captacao_relatorio_da_vez()
 RETURNS TABLE(phone text, message text, "delayMessage" integer)
 LANGUAGE plpgsql
AS $function$
DECLARE
  v_agora  timestamp := now() AT TIME ZONE 'America/Manaus';
  v_dia    date := v_agora::date;
  v_fds    boolean := extract(isodow FROM v_agora) >= 6;
  v_fim    time;
  v_teto   int := coalesce(captacao_teto_hoje(), 0);
  v_disp   int;
  v_ultimo timestamp;
  v_hora   boolean;
  r        record;
BEGIN
  IF coalesce((SELECT valor FROM captacao_config WHERE chave = '_relatorio_dia'), '') = v_dia::text THEN
    RETURN;   -- já saiu hoje
  END IF;
  v_fim := coalesce(nullif((SELECT valor FROM captacao_config WHERE chave = CASE WHEN v_fds THEN 'janela_fim_fds' ELSE 'janela_fim' END), ''),
                    (SELECT valor FROM captacao_config WHERE chave = 'janela_fim'), '18:00')::time;
  SELECT count(*) FILTER (WHERE status IS DISTINCT FROM 'Falhou'), max(criada_em AT TIME ZONE 'America/Manaus')
    INTO v_disp, v_ultimo
    FROM captacao_mensagens
   WHERE direcao = 'enviada' AND origem = 'disparo' AND (criada_em AT TIME ZONE 'America/Manaus')::date = v_dia;

  v_hora := (v_teto > 0 AND v_disp >= v_teto AND v_agora >= v_ultimo + interval '1 hour')   -- o último disparo do dia + 1 h
         OR (v_agora::time >= v_fim AND (v_disp > 0 OR NOT v_fds));                         -- a cota não fechou: o fim da janela
  IF NOT v_hora THEN RETURN; END IF;

  SELECT * INTO r FROM crm_captacao_relatorio();
  IF r.telefone IS NULL THEN RETURN; END IF;
  INSERT INTO captacao_config (chave, valor, nota)
  VALUES ('_relatorio_dia', v_dia::text, 'Carimbo: o dia do último relatório da captação (185). Apague para mandar de novo hoje.')
  ON CONFLICT (chave) DO UPDATE SET valor = EXCLUDED.valor;
  RETURN QUERY SELECT r.telefone, r.mensagem, 4;
END;
$function$;
