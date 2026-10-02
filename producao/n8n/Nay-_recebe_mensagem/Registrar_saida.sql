-- Uma linha por mensagem que sai, com o ID dela.
-- Os dois INSERT sao CTE que MODIFICA dado, entao os dois rodam sempre --
-- CTE de SELECT que ninguem referencia o Postgres nem executa (foi assim
-- que o `nay_sincronizar_nome` ficou meses sem rodar).
WITH s AS (
  INSERT INTO mensagem_saida (message_id, telefone, texto)
  SELECT $1::text, $2::text, $3::text
   WHERE NULLIF(btrim(coalesce($1::text,'')),'') IS NOT NULL
  ON CONFLICT (message_id) DO NOTHING
  RETURNING 1
), e AS (
  -- O codigo sai do TEXTO DESTA mensagem, nao de outro no: e isso que
  -- garante que o codigo e o ID sejam do mesmo card.
  INSERT INTO envios (codigo, telefone, destino, valor_enviado, message_id)
  SELECT i.codigo, $2::text, 'corretor',
         COALESCE(i.valor_venda, i.valor_aluguel, 0), $1::text
    FROM imoveis i
   WHERE NULLIF(btrim(coalesce($1::text,'')),'') IS NOT NULL
     AND i.codigo::text = (regexp_match(coalesce($3::text,''), 'C[oó]digo:\s*(\d{3,5})'))[1]
  RETURNING 1
)
SELECT (SELECT count(*) FROM s) AS saida, (SELECT count(*) FROM e) AS envio;
