-- Grava o ID da mensagem (e alimenta mensagem_saida/envios, para a citacao).
SELECT nai_confirmar_envio($1::bigint, $2::jsonb) AS r;
