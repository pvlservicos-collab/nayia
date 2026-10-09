-- 324 -- A última pergunta da captação: os 6% de honorários estão no valor?
--
-- Pedro, 09/10/2026: "põe mais uma pergunta no final, sempre -- Pedro coloca para perguntar sobre os honorários de
-- corretagem, se está incluso no valor de 350k os 6% ... personalizando o valor por cliente" e "o valor do imóvel na
-- pergunta, mas o 6% é fixo".
--
-- É a última pergunta da conversa, depois da indicação (315/320), e só quando há VALOR DE VENDA para pôr na frase:
--   1. o que ele pediu na própria campanha (captacao_leads.valor_venda_pedido, "R$ 350 mil", "570.000"...);
--   2. senão, o valor de venda do imóvel dele no cadastro (imoveis.valor_venda).
-- Sem valor de venda (imóvel só de locação) a pergunta não existe: `captacao_honorarios_frase` devolve NULL.
--
-- Como a indicação: a frase vem do banco, com o nome e o tratamento dele; `captacao_honorarios_pendente` diz se ainda
-- falta perguntar (olha as mensagens enviadas desde o último disparo); `captacao_honorarios_guardar` anota a resposta
-- em privado.captacao_honorarios. A parede fica no serviço em Python (encerrar_conversa não encerra sem a pergunta).
BEGIN;
SET LOCAL lock_timeout = '3s';

CREATE TABLE IF NOT EXISTS privado.captacao_honorarios (
  id         bigserial PRIMARY KEY,
  lead_id    bigint,
  telefone   text NOT NULL,
  valor      text,
  resposta   text NOT NULL,
  criado_em  timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS captacao_honorarios_lead ON privado.captacao_honorarios (lead_id, criado_em DESC);
COMMENT ON TABLE privado.captacao_honorarios IS
  '324: o que o proprietário respondeu sobre os 6% de honorários de corretagem no valor de venda (a última pergunta da captação)';

-- o valor de venda para a frase, já escrito ("R$ 350.000"), ou NULL quando não há venda
CREATE OR REPLACE FUNCTION public.captacao_honorarios_valor(p_telefone text)
 RETURNS text
 LANGUAGE sql
 STABLE
AS $function$
  WITH l AS (
    SELECT c.codigo, nullif(btrim(coalesce(c.valor_venda_pedido, '')), '') AS pedido
      FROM captacao_leads c WHERE c.telefone_chave = nay_fone_chave(p_telefone) LIMIT 1
  ), num AS (
    -- o número que ele escreveu: "R$ 350 mil" -> 350000; "570.000" -> 570000; "1.350.000,00" -> 1350000; "2,5" -> 2500000 (milhões)
    SELECT l.pedido,
           (regexp_match(l.pedido, '(\d[\d\.]*(?:,\d+)?)'))[1] AS bruto,
           l.pedido ~* '\mmil\M' AS em_mil,
           l.pedido ~* 'milh' AS em_milhao
      FROM l
  ), v AS (
    SELECT CASE
             WHEN num.bruto IS NULL THEN NULL
             WHEN num.em_milhao THEN replace(replace(num.bruto, '.', ''), ',', '.')::numeric * 1000000
             WHEN num.em_mil THEN replace(replace(num.bruto, '.', ''), ',', '.')::numeric * 1000
             -- "2,5" sem unidade: só pode ser milhão; "350" sem unidade: mil
             WHEN num.bruto ~ '^\d{1,2}(,\d+)?$' THEN replace(num.bruto, ',', '.')::numeric * 1000000
             WHEN num.bruto ~ '^\d{3}$' THEN num.bruto::numeric * 1000
             ELSE replace(split_part(num.bruto, ',', 1), '.', '')::numeric
           END AS pedido_num
      FROM num
  )
  SELECT 'R$ ' || replace(to_char(x.valor, 'FM999,999,999'), ',', '.')
    FROM (
      SELECT coalesce((SELECT v.pedido_num FROM v WHERE v.pedido_num >= 10000),
                      (SELECT i.valor_venda FROM l JOIN imoveis i ON i.codigo::text = l.codigo
                        WHERE coalesce(i.valor_venda, 0) > 0 LIMIT 1)) AS valor
    ) x
   WHERE x.valor IS NOT NULL;
$function$;

-- a pergunta, com o nome dele e o valor; NULL quando não há valor de venda
CREATE OR REPLACE FUNCTION public.captacao_honorarios_frase(p_telefone text)
 RETURNS text
 LANGUAGE sql
 STABLE
AS $function$
  WITH l AS (
    SELECT c.tratamento, nay_primeiro_nome(c.nome) AS n
      FROM captacao_leads c WHERE c.telefone_chave = nay_fone_chave(p_telefone) LIMIT 1
  ), d AS (
    SELECT l.tratamento,
           CASE WHEN l.n = upper(l.n) OR l.n = lower(l.n) THEN initcap(l.n) ELSE l.n END AS nome,
           captacao_honorarios_valor(p_telefone) AS valor
      FROM l
  )
  SELECT CASE WHEN d.tratamento IN ('Sr.', 'Sra.') THEN d.tratamento || coalesce(' ' || d.nome, '') || ', só'
              WHEN d.nome IS NOT NULL THEN d.nome || ', só'
              ELSE 'Só' END
         || ' para eu anotar certinho: no valor de ' || d.valor
         || ' já estão inclusos os 6% de honorários de corretagem, ou '
         || CASE d.tratamento WHEN 'Sra.' THEN 'a Sra.' WHEN 'Sr.' THEN 'o Sr.' ELSE 'você' END
         || ' quer esse valor líquido?'
    FROM d
   WHERE d.valor IS NOT NULL;
$function$;

-- ainda falta perguntar? A frase, ou NULL (já perguntou desde o último disparo, ou não se aplica)
CREATE OR REPLACE FUNCTION public.captacao_honorarios_pendente(p_telefone text)
 RETURNS text
 LANGUAGE sql
 STABLE
AS $function$
  SELECT CASE WHEN EXISTS (
           SELECT 1 FROM captacao_mensagens m
            WHERE nay_fone_chave(m.telefone) = nay_fone_chave(p_telefone) AND m.direcao = 'enviada'
              AND m.texto ~* 'honor[aá]rio|corretagem' AND m.texto ~ '\?'
              AND m.id > coalesce((SELECT max(d.id) FROM captacao_mensagens d
                                    WHERE nay_fone_chave(d.telefone) = nay_fone_chave(p_telefone)
                                      AND d.direcao = 'enviada' AND d.origem = 'disparo'), 0))
         THEN NULL
         ELSE captacao_honorarios_frase(p_telefone) END;
$function$;

-- a resposta dele, nas palavras dele
CREATE OR REPLACE FUNCTION public.captacao_honorarios_guardar(p_telefone text, p_resposta text)
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_resposta text := left(nullif(btrim(coalesce(p_resposta, '')), ''), 300);
BEGIN
  IF v_resposta IS NULL THEN
    RETURN 'Nao gravei: passe o que ele respondeu sobre os honorarios (incluso, por fora, ou o que ele disse).';
  END IF;
  INSERT INTO privado.captacao_honorarios (lead_id, telefone, valor, resposta)
  SELECT l.id, p_telefone, captacao_honorarios_valor(p_telefone), v_resposta
    FROM (SELECT 1) x LEFT JOIN captacao_leads l ON l.telefone_chave = nay_fone_chave(p_telefone);
  RETURN 'Anotado. Agradeca em uma linha e encerre a conversa (encerrar_conversa, motivo concluido).';
END
$function$;

COMMIT;
