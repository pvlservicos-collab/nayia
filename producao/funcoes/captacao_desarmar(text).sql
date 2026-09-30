CREATE OR REPLACE FUNCTION public.captacao_desarmar(p_motivo text)
 RETURNS void
 LANGUAGE sql
AS $function$
  INSERT INTO captacao_config (chave, valor, nota) VALUES
    ('captacao_pausada', 'sim', NULL),
    ('_disjuntor', p_motivo, 'Por que a campanha pausou sozinha. Religar apaga.'),
    ('_disjuntor_em', to_char(now() AT TIME ZONE 'America/Manaus', 'YYYY-MM-DD HH24:MI'), 'Quando o disjuntor pausou.'),
    ('rampa_desde', '', NULL)
  ON CONFLICT (chave) DO UPDATE SET valor = EXCLUDED.valor;
$function$;
