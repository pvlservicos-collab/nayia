-- 220 (30/09/2026): A RESPOSTA CORRIGIDA À MARIA SORAIA (…9959), pedida pelo Pedro:
-- "revise, corrija e avise ela". Ela mandou o filtro inteiro duas vezes e recebeu
-- perguntas (218 e 219 corrigiram a busca). Sai pela caixa da Nay, no turno dela
-- de 13:30, com os textos que a busca corrigida devolve.
BEGIN;
SELECT nai_enfileirar_texto(12755, NULL, 4939, 'turno',
  'Maria, conferi aqui com calma o que você pediu.' || E'\n\n'
  || 'No Adrianópolis e no Vieiralves eu não tenho apartamento mobiliado de 1 ou 2 quartos até R$ 4 mil agora, '
  || 'mas bem pertinho de lá, no Parque 10, eu tenho este, um pouco mais em conta:' || E'\n\n'
  || (SELECT texto_pronto FROM nai_card_do_imovel(5717)),
  'resposta', 1);
SELECT nai_enfileirar_texto(12755, NULL, 4939, 'turno',
  'E na Ponta Negra, 2 quartos até R$ 4 mil, eu tenho estas opções mais em conta:' || E'\n\n'
  || nai_bloco_oferta(5724, 'locacao') || E'\n\n' || nai_bloco_oferta(5727, 'locacao') || E'\n\n'
  || nai_bloco_oferta(5733, 'locacao') || E'\n\n'
  || 'Qual deles é de seu interesse? Assim, posso lhe enviar mais informações e detalhes.',
  'resposta', 2);
COMMIT;
