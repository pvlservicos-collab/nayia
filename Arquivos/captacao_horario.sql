-- =====================================================================
-- Horario da CAPTACAO (pedido do Tel em 10/09/2026):
--   segunda a sexta: 8h as 22h
--   sabado e domingo: 8h as 18h
--   pausa todo dia: 12h as 13h30
--
-- Uma funcao so, lida pelos dois SQLs de reserva (lead novo e followup) e
-- pelo "Portao de seguranca" do n8n -- antes a regra estava escrita em tres
-- lugares (8h-18h, sem fim de semana, sem 12h) e mudar exigia mexer nos tres.
-- Os horarios moram em captacao_config: mudam com um UPDATE, sem publicar.
-- Nada e apagado: janela_inicio/janela_fim continuam as mesmas chaves.
-- =====================================================================

INSERT INTO captacao_config (chave, valor, nota) VALUES
  ('janela_inicio_fds', '08:00', 'Sabado e domingo: comeca a mandar a partir desta hora (Manaus).'),
  ('janela_fim_fds',    '18:00', 'Sabado e domingo: para de mandar nesta hora (Manaus).'),
  ('pausa_inicio',      '12:00', 'Pausa de todo dia (almoco): nao manda a partir desta hora...'),
  ('pausa_fim',         '13:30', '...ate esta hora.')
ON CONFLICT (chave) DO NOTHING;

UPDATE captacao_config SET valor = '22:00' WHERE chave = 'janela_fim';
UPDATE captacao_config SET nota = 'Segunda a sexta: comeca a mandar a partir desta hora (Manaus).' WHERE chave = 'janela_inicio';
UPDATE captacao_config SET nota = 'Segunda a sexta: para de mandar nesta hora (Manaus).' WHERE chave = 'janela_fim';

CREATE OR REPLACE FUNCTION captacao_cfg(p_chave text, p_padrao text)
RETURNS text LANGUAGE sql STABLE AS $$
  SELECT coalesce((SELECT NULLIF(btrim(valor), '') FROM captacao_config WHERE chave = p_chave), p_padrao);
$$;

-- true = pode mandar agora. Comparacao em texto HH:MM (sempre com 2 digitos).
CREATE OR REPLACE FUNCTION captacao_no_horario(p_ts timestamptz DEFAULT now())
RETURNS boolean LANGUAGE sql STABLE AS $$
  SELECT CASE WHEN dow <= 5
              THEN hm >= captacao_cfg('janela_inicio', '08:00') AND hm < captacao_cfg('janela_fim', '22:00')
              ELSE hm >= captacao_cfg('janela_inicio_fds', '08:00') AND hm < captacao_cfg('janela_fim_fds', '18:00')
         END
     AND NOT (hm >= captacao_cfg('pausa_inicio', '12:00') AND hm < captacao_cfg('pausa_fim', '13:30'))
  FROM (SELECT extract(isodow FROM p_ts AT TIME ZONE 'America/Manaus')::int AS dow,
               to_char(p_ts AT TIME ZONE 'America/Manaus', 'HH24:MI') AS hm) t;
$$;
