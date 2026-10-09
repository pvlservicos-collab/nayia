-- 323 -- A retomada pelo número oficial: quem recebeu a abertura pela Z-API e nunca respondeu entra na fila do
--        disparo do Python (o modelo da Meta), uma vez.
--
-- Pedro, 09/10/2026: "continua o disparo para os [contatos] que faltaram da captação na API oficial e os que não
-- responderam na captação pelo outro número".
--
-- A regra "captação nunca duas vezes" (291) continua: o status não volta para 'novo'. Quem entra de novo entra por
-- uma tabela própria, `captacao_retomada_oficial`, como a 291 mandou ("retomada com OUTRO texto: tabela própria").
-- O modelo oficial é a mesma pergunta ("seu imóvel ainda está disponível?"), por outro número, para quem ficou calado.
--
-- 1. `captacao_retomada_oficial(lead_id, motivo)`: quem pode receber o modelo apesar de já ter recebido pela Z-API.
-- 2. `captacao_py_fila_do_disparo()`: além de 'novo'/'erro', entra o lead 'enviado' que está na retomada E nunca
--    respondeu (nem respondeu_em, nem mensagem recebida) E ainda não recebeu o modelo oficial (não está em
--    captacao_motor). As outras paredes valem igual: opt_out, humano_assumiu_em, corretor/parceiro (308), telefone
--    e nome, dono já chamado por outro imóvel, captacao_nao_disparar. Os novos saem primeiro; a retomada depois.
-- 3. `captacao_py_reservar_disparo()`: a reserva aceita o 'enviado' da retomada. Depois do envio o lead fica
--    'enviado' de novo (REGISTRAR_DISPARO do serviço) e já está em captacao_motor, então não volta à fila.
-- 4. Entram na retomada os que hoje estão nessa situação (status 'enviado', calados), com o motivo gravado.
--
-- O interruptor (`python_disparo`) NÃO é ligado aqui: é ligado à parte, com a ordem dele.
BEGIN;
SET LOCAL lock_timeout = '3s';

CREATE TABLE IF NOT EXISTS public.captacao_retomada_oficial (
  lead_id    bigint PRIMARY KEY REFERENCES captacao_leads(id) ON DELETE CASCADE,
  motivo     text NOT NULL,
  criado_em  timestamptz NOT NULL DEFAULT now()
);
COMMENT ON TABLE public.captacao_retomada_oficial IS
  '323: leads que já receberam a abertura pela Z-API e nunca responderam; o disparo do Python (modelo oficial) pode chamá-los UMA vez. Apagar a linha tira da fila.';
GRANT SELECT ON public.captacao_retomada_oficial TO nay_leitura;

CREATE OR REPLACE FUNCTION public.captacao_py_fila_do_disparo()
 RETURNS SETOF bigint
 LANGUAGE sql
 STABLE
AS $function$
  SELECT l.id
    FROM captacao_leads l
   WHERE l.tentativas < 4 AND NOT l.opt_out AND l.humano_assumiu_em IS NULL
     AND coalesce(btrim(l.telefone), '') <> '' AND coalesce(btrim(l.nome), '') <> ''
     AND captacao_fora_da_campanha(l.id) IS NULL
     AND (
          -- quem nunca recebeu nada nosso por este número
          (l.status IN ('novo', 'erro')
           AND NOT EXISTS (SELECT 1 FROM captacao_mensagens m
                            WHERE nay_fone_chave(m.telefone) = l.telefone_chave AND m.direcao = 'enviada' AND m.status <> 'Falhou'))
          -- 323: a retomada pelo oficial -- recebeu pela Z-API, nunca respondeu, ainda sem o modelo oficial
          OR (l.status = 'enviado'
              AND EXISTS (SELECT 1 FROM captacao_retomada_oficial r WHERE r.lead_id = l.id)
              AND l.respondeu_em IS NULL
              AND NOT EXISTS (SELECT 1 FROM captacao_mensagens m
                               WHERE nay_fone_chave(m.telefone) = l.telefone_chave AND m.direcao = 'recebida')
              AND NOT EXISTS (SELECT 1 FROM captacao_motor mt WHERE mt.lead_id = l.id))
         )
     AND NOT EXISTS (SELECT 1 FROM captacao_leads o
                      WHERE o.id <> l.id AND o.proprietario_id IS NOT NULL AND o.proprietario_id = l.proprietario_id
                        AND (o.ultimo_envio_em IS NOT NULL OR o.respondeu_em IS NOT NULL))
     AND NOT EXISTS (SELECT 1 FROM captacao_nao_disparar n WHERE n.telefone_chave = l.telefone_chave)
   ORDER BY (l.status = 'enviado'), l.id;
$function$;

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

  SELECT f.id INTO v_id FROM captacao_py_fila_do_disparo() AS f(id) LIMIT 1;
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

-- 4. quem entra na retomada hoje: recebeu pela Z-API (status 'enviado') e nunca respondeu
INSERT INTO public.captacao_retomada_oficial (lead_id, motivo)
SELECT l.id, 'não respondeu a abertura pela Z-API (último envio ' || coalesce(to_char(l.ultimo_envio_em AT TIME ZONE 'America/Manaus', 'DD/MM'), '?') || '); retomada pelo oficial, Pedro 09/10/2026'
  FROM captacao_leads l
 WHERE l.status = 'enviado' AND l.respondeu_em IS NULL AND NOT l.opt_out AND l.humano_assumiu_em IS NULL
   AND captacao_fora_da_campanha(l.id) IS NULL
   AND NOT EXISTS (SELECT 1 FROM captacao_mensagens m WHERE nay_fone_chave(m.telefone) = l.telefone_chave AND m.direcao = 'recebida')
   AND NOT EXISTS (SELECT 1 FROM captacao_motor mt WHERE mt.lead_id = l.id)
ON CONFLICT (lead_id) DO NOTHING;

COMMIT;
