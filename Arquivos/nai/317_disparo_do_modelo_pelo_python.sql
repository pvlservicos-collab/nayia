-- 317 (08/10/2026): O DISPARO DO MODELO OFICIAL, PELA NAY DE CAPTAÇÃO EM PYTHON.
-- Pedro: "prepare tudo para começarmos a disparar para os [contatos] da captação
-- que faltaram daqui a pouco, reveja duplicatas para nessa rodada não disparemos
-- para quem já recebeu, por mais que seja api oficial a ia não é ilimitada então
-- põe o modelo situacao_imovel_cadastrado_1 para sair em média 1 a 1 min".
--
-- O INTERRUPTOR É PRÓPRIO: `python_disparo` (nasce 'nao'). O disparo antigo, pela
-- Z-API e com o texto antigo, continua mandado por `captacao_pausada` -- que fica
-- 'sim'. Ligar um não liga o outro; os dois lendo a mesma fila ao mesmo tempo
-- mandariam duas aberturas para a mesma pessoa.
--
-- O RITMO: um modelo por vez, com intervalo sorteado entre `python_disparo_seg_min`
-- (45) e `python_disparo_seg_max` (75) segundos: 1 por minuto em média. Dentro da
-- janela de horário da captação (captacao_no_horario), como o disparo antigo.
--
-- QUEM ENTRA NA FILA (captacao_py_fila_do_disparo), e as travas contra duplicata:
--   * status novo ou erro, menos de 4 tentativas, sem opt-out, sem gente na conversa;
--   * é proprietário (captacao_fora_da_campanha vazia: sem corretor nem parceiro);
--   * NUNCA recebeu mensagem nossa neste cadastro (nenhuma 'enviada' que não falhou);
--   * o MESMO DONO não foi chamado por outro telefone (mesmo proprietario_id em outro
--     lead que já recebeu ou já respondeu);
--   * não está em `captacao_nao_disparar` (quem já conversa com a gente nas linhas
--     da captação no CRM, posto lá pela revisão de hoje);
--   * tem nome: o modelo começa com "Olá, {{1}}!".
--
-- QUEM RECEBE O MODELO PASSA A SER ATENDIDO PELO PYTHON: o lead entra em
-- `captacao_motor` na hora do disparo, e `captacao_e_do_python` passa a valer para
-- ele (315: a resposta dele entra como 'Recebido py'). É a Nay nova que conhece o
-- modelo com os botões e faz a pergunta da indicação.
--
-- DISJUNTOR: se os 3 últimos disparos falharam, para (fila parada e visível é
-- melhor que fila queimada). Um lead reservado que não virou envio volta em 30 min.
BEGIN;
SET LOCAL lock_timeout = '3s';

INSERT INTO captacao_config (chave, valor, nota) VALUES
 ('python_disparo', 'nao', '317: interruptor do DISPARO do modelo oficial pela Nay em Python. sim = sai um modelo por vez, no ritmo abaixo. Não tem nada a ver com captacao_pausada (o disparo antigo, pela Z-API).'),
 ('python_disparo_seg_min', '45', '317: menor intervalo entre dois modelos, em segundos.'),
 ('python_disparo_seg_max', '75', '317: maior intervalo entre dois modelos, em segundos. 45 e 75 dão 1 por minuto em média.')
ON CONFLICT (chave) DO NOTHING;

CREATE TABLE IF NOT EXISTS public.captacao_motor (
  lead_id bigint PRIMARY KEY,
  motor   text NOT NULL DEFAULT 'python',
  desde   timestamptz NOT NULL DEFAULT now()
);
COMMENT ON TABLE public.captacao_motor IS '317: leads da captação atendidos pela Nay em Python (entraram ao receber o modelo oficial). Apagar a linha devolve o lead ao fluxo do n8n.';

CREATE TABLE IF NOT EXISTS public.captacao_nao_disparar (
  telefone_chave text PRIMARY KEY,
  motivo         text NOT NULL,
  criado_em      timestamptz NOT NULL DEFAULT now()
);
COMMENT ON TABLE public.captacao_nao_disparar IS '317: telefones (chave) que o disparo do modelo pula, com o motivo. Ex.: já conversa com a gente em outra linha.';

-- 315 + 317: é do Python quem está na lista de teste OU quem recebeu o modelo por ele
CREATE OR REPLACE FUNCTION public.captacao_e_do_python(p_telefone text)
 RETURNS boolean
 LANGUAGE sql
 STABLE
AS $function$
  SELECT coalesce((
    SELECT btrim(c.valor) = 'todos'
        OR nay_fone_chave(p_telefone) IN (SELECT nay_fone_chave(btrim(x)) FROM regexp_split_to_table(c.valor, '[,;\s]+') x WHERE btrim(x) <> '')
      FROM captacao_config c WHERE c.chave = 'python_telefones'), false)
      OR EXISTS (SELECT 1 FROM captacao_motor mt JOIN captacao_leads l ON l.id = mt.lead_id
                  WHERE mt.motor = 'python' AND l.telefone_chave = nay_fone_chave(p_telefone));
$function$;

-- A fila do disparo do modelo, na ordem. É a mesma lista para contar e para reservar.
CREATE OR REPLACE FUNCTION public.captacao_py_fila_do_disparo()
 RETURNS SETOF bigint
 LANGUAGE sql
 STABLE
AS $function$
  SELECT l.id
    FROM captacao_leads l
   WHERE l.status IN ('novo', 'erro') AND l.tentativas < 4 AND NOT l.opt_out AND l.humano_assumiu_em IS NULL
     AND coalesce(btrim(l.telefone), '') <> '' AND coalesce(btrim(l.nome), '') <> ''
     AND captacao_fora_da_campanha(l.id) IS NULL
     AND NOT EXISTS (SELECT 1 FROM captacao_mensagens m
                      WHERE nay_fone_chave(m.telefone) = l.telefone_chave AND m.direcao = 'enviada' AND m.status <> 'Falhou')
     AND NOT EXISTS (SELECT 1 FROM captacao_leads o
                      WHERE o.id <> l.id AND o.proprietario_id IS NOT NULL AND o.proprietario_id = l.proprietario_id
                        AND (o.ultimo_envio_em IS NOT NULL OR o.respondeu_em IS NOT NULL))
     AND NOT EXISTS (SELECT 1 FROM captacao_nao_disparar n WHERE n.telefone_chave = l.telefone_chave)
   ORDER BY l.id;
$function$;

-- Por que o disparo não sai agora (NULL = pode sair).
CREATE OR REPLACE FUNCTION public.captacao_py_disparo_motivo()
 RETURNS text
 LANGUAGE sql
 STABLE
AS $function$
  SELECT CASE
    WHEN coalesce((SELECT valor FROM captacao_config WHERE chave = 'python_disparo'), 'nao') <> 'sim' THEN 'desligado'
    WHEN NOT captacao_no_horario(now()) THEN 'fora do horário'
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

-- Reserva UM lead para receber o modelo agora. Nada devolvido = nada a fazer neste momento.
CREATE OR REPLACE FUNCTION public.captacao_py_reservar_disparo()
 RETURNS TABLE(lead_id bigint, telefone text, nome text, tratamento text)
 LANGUAGE plpgsql
AS $function$
#variable_conflict use_column
DECLARE
  v_id bigint;
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

  SELECT l.id INTO v_id FROM captacao_leads l
   WHERE l.id IN (SELECT captacao_py_fila_do_disparo())
   ORDER BY l.id LIMIT 1 FOR UPDATE SKIP LOCKED;
  IF v_id IS NULL THEN RETURN; END IF;
  -- a parede da 308 mora neste UPDATE: corretor ou parceiro é marcado e a reserva não acontece
  UPDATE captacao_leads l SET status = 'reservado', atualizado_em = now() WHERE l.id = v_id AND l.status IN ('novo', 'erro');
  IF NOT EXISTS (SELECT 1 FROM captacao_leads l WHERE l.id = v_id AND l.status = 'reservado') THEN RETURN; END IF;
  -- daqui para a frente este lead é atendido pela Nay em Python
  INSERT INTO captacao_motor (lead_id) VALUES (v_id) ON CONFLICT (lead_id) DO NOTHING;
  RETURN QUERY SELECT l.id, l.telefone, l.nome, l.tratamento FROM captacao_leads l WHERE l.id = v_id;
END
$function$;

-- O placar do disparo, para o registro e para quem perguntar "como está".
CREATE OR REPLACE FUNCTION public.captacao_py_disparo_placar()
 RETURNS TABLE(motivo_de_nao_sair text, na_fila bigint, modelos_hoje bigint, falharam_hoje bigint, ultimo_em timestamptz, atendidos_pelo_python bigint)
 LANGUAGE sql
 STABLE
AS $function$
  SELECT captacao_py_disparo_motivo(),
         (SELECT count(*) FROM captacao_py_fila_do_disparo()),
         (SELECT count(*) FROM captacao_mensagens m JOIN captacao_motor mt ON mt.lead_id = m.lead_id
           WHERE m.direcao = 'enviada' AND m.origem = 'disparo' AND m.status <> 'Falhou'
             AND (m.criada_em AT TIME ZONE 'America/Manaus')::date = (now() AT TIME ZONE 'America/Manaus')::date),
         (SELECT count(*) FROM captacao_mensagens m JOIN captacao_motor mt ON mt.lead_id = m.lead_id
           WHERE m.direcao = 'enviada' AND m.origem = 'disparo' AND m.status = 'Falhou'
             AND (m.criada_em AT TIME ZONE 'America/Manaus')::date = (now() AT TIME ZONE 'America/Manaus')::date),
         (SELECT max(m.criada_em) FROM captacao_mensagens m JOIN captacao_motor mt ON mt.lead_id = m.lead_id
           WHERE m.direcao = 'enviada' AND m.origem = 'disparo'),
         (SELECT count(*) FROM captacao_motor);
$function$;
COMMIT;
