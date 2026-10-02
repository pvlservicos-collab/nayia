-- no-op desde 01/09. Este no gravava em `envios` o codigo do PRIMEIRO
-- card com o message_id do ULTIMO (medido na execucao 3768: codigo 1125
-- com o ID do 5643). Quem grava agora e o `Registrar saida`, dentro do
-- laco, onde o codigo e o ID sao da mesma mensagem.
SELECT $1::int AS codigo_ignorado, $2::text AS telefone, $3::text AS id_ignorado;
