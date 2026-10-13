-- 357 -- Captação: a ficha do imóvel NOVO não presume aluguel quando o dono não disse se vai alugar ou vender
--
-- Pedro, 12/10/2026: "a Nay está tendo vários erros lá na captação API oficial, principalmente confundindo venda e
-- locação, ajusta". A parte do imóvel da campanha (o que está no cadastro para venda) saiu no serviço em 12/10
-- (nay-captacao/captacao/venda.py). Esta é a da FICHA, que mora no banco. Conversa do final 8870 (09 e 10/10):
--     Nay: "O Sr. quer alugar ou vender esse imóvel?"        Ele: "Ainda não decidimos"
--     ...  Nay: "E qual valor o Sr. quer pedir no aluguel?"  "...O aluguel já inclui algum deles?"
-- `v_aluga` é verdadeiro sempre que o negócio NÃO diz "venda", inclusive quando ele não disse nada. Agora, sem o
-- negócio dito, a pergunta do valor é neutra e a das taxas não fala em aluguel. Quem disse aluguel, venda ou os dois
-- continua ouvindo as frases de sempre; o imóvel da campanha (tipo `atualizar`) não muda.
BEGIN;
SET LOCAL lock_timeout = '3s';

CREATE FUNCTION pg_temp.remendar(p_fn regprocedure, p_de text, p_para text) RETURNS void LANGUAGE plpgsql AS $$
DECLARE v text := pg_get_functiondef(p_fn); n int;
BEGIN
  n := (length(v) - length(replace(v, p_de, ''))) / length(p_de);
  IF n <> 1 THEN RAISE EXCEPTION 'remendo em %: o trecho aparece % vez(es), esperava 1: %', p_fn, n, left(p_de, 60); END IF;
  EXECUTE replace(v, p_de, p_para);
END $$;

SELECT pg_temp.remendar('captacao_ficha(text,text,jsonb,boolean)',
$de$                              WHEN v_aluga THEN 'E qual valor ' || v_pron || ' quer pedir no aluguel?'$de$,
$para$                              -- 357: ele não disse se aluga ou vende ("ainda não decidimos"): não presume aluguel
                              WHEN coalesce(d->>'negocio', '') !~* 'vend|alug|loca|amb'
                              THEN 'E qual valor ' || v_pron || ' pensa em pedir, no aluguel ou na venda?'
                              WHEN v_aluga THEN 'E qual valor ' || v_pron || ' quer pedir no aluguel?'$para$);

SELECT pg_temp.remendar('captacao_ficha(text,text,jsonb,boolean)',
$de$WHEN v_cond AND v_aluga THEN 'E o condomínio e o IPTU, estão em quanto? O aluguel já inclui algum deles?'$de$,
$para$WHEN v_cond AND v_aluga AND (v_tipo = 'atualizar' OR coalesce(d->>'negocio', '') ~* 'alug|loca|amb')
                                   THEN 'E o condomínio e o IPTU, estão em quanto? O aluguel já inclui algum deles?'$para$);

SELECT pg_temp.remendar('captacao_ficha(text,text,jsonb,boolean)',
$de$WHEN v_aluga THEN 'E o IPTU, sabe me dizer o valor? O aluguel já inclui alguma coisa, como água ou IPTU?'$de$,
$para$WHEN v_aluga AND (v_tipo = 'atualizar' OR coalesce(d->>'negocio', '') ~* 'alug|loca|amb')
                                   THEN 'E o IPTU, sabe me dizer o valor? O aluguel já inclui alguma coisa, como água ou IPTU?'$para$);

COMMIT;
