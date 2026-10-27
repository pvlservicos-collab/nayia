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
