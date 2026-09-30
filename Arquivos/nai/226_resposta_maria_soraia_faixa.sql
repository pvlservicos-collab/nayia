BEGIN;
SELECT nai_enfileirar_texto(12780, NULL, 4939, 'turno',
  'Maria, desculpa a demora, conferi aqui direitinho.' || E'\n\n'
  || 'Até R$ 4 mil (eu procuro entre R$ 3.200 e R$ 4.400), apartamento mobiliado de 2 quartos na Ponta Negra eu não tenho agora, nem nos bairros ao redor.',
  'resposta', 1);
SELECT nai_enfileirar_texto(12780, NULL, 4939, 'turno',
  'Nessa faixa o que eu tenho é de 3 quartos, semi-mobiliado, em outra região:' || E'\n\n'
  || nai_bloco_oferta(5725, 'locacao') || E'\n\n' || nai_bloco_oferta(2944, 'locacao') || E'\n\n'
  || 'Se algum servir para o cliente, ou se ele aceitar outro bairro, me fala que eu já te mando o card.',
  'resposta', 2);
COMMIT;
SELECT id, estado, left(texto, 90) FROM nai_saida WHERE turno_id = 12780 AND motivo = 'resposta' AND criado_em > now() - interval '1 minute';
