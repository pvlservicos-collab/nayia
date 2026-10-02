-- 265 (02/10/2026): O PEDIDO DE VISITA DIZ O QUE VEM DEPOIS.
-- Pedro: "quero mudar a mensagem" -- a última linha do pedido de visita deixa de
-- ser só "confirme se os dados estão corretos" e passa a dizer para que serve a
-- confirmação: é ela que libera a Nay para procurar o proprietário.
--
-- Continua a linha da 255: o texto é PEDIDO, não visita marcada. Agora o corretor
-- lê também o passo seguinte, e entende por que ainda não está confirmado.
--
-- O texto que ele mandou foi "Por favor, confirme se os dados para que eu possa
-- entrar em contato com o proprietário" -- faltou o "estão corretos" no meio da
-- frase. Entrou com ele, que é o que a frase quer dizer.
BEGIN;
SET LOCAL lock_timeout = '3s';

CREATE OR REPLACE FUNCTION pg_temp.trocar(p_fn regprocedure, p_de text, p_para text, p_vezes int DEFAULT 1)
 RETURNS void LANGUAGE plpgsql AS $$
DECLARE d text := pg_get_functiondef(p_fn); n int := (length(d) - length(replace(d, p_de, ''))) / length(p_de);
BEGIN
  IF n <> p_vezes THEN RAISE EXCEPTION 'trocar em %: esperava % vez(es), achei % -- %', p_fn, p_vezes, n, left(p_de, 50); END IF;
  EXECUTE replace(d, p_de, p_para);
END $$;

SELECT pg_temp.trocar('nai_texto_confirmar_visita(bigint)'::regprocedure,
$de$      || 'Por favor, confirme se os dados estão corretos.'$de$,
$para$      || 'Por favor, confirme se os dados estão corretos para que eu possa entrar em contato com o proprietário.'$para$);
COMMIT;
