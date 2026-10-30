-- Pedro, 30/10/2026: "você subiu todos os imóveis mas não marcou lá na tela Envio Chaves na Mão pra eu acompanhar, e vê
-- se não tem imóveis que já estão indisponíveis lá na lista". A escolha publicada (a URL envio.xml e a tela) passa a ser
-- todos os que entram no portal (cnm_imoveis ok = 227), menos os 2 que a conversa diz que saíram:
--   5609 Reserva das Flores: "Não está disponível: está alugada (ocupada)" (memória do imóvel, 28/10)
--   5668 Villa Suiça: o construtor disse em 29/10 que as casas prontas estão todas vendidas
-- Os 6 destaques de antes ficam. Pelo mesmo caminho do botão Publicar da tela (cnm_envio_publicar, 538).
BEGIN;
SELECT jsonb_array_length(r->'ids') AS no_ar, jsonb_array_length(r->'destaques') AS destaques, r->>'atualizado_em' AS em
  FROM (SELECT cnm_envio_publicar(
          (SELECT array_agg(codigo ORDER BY codigo) FROM cnm_imoveis() WHERE ok AND codigo NOT IN (5609, 5668)),
          (SELECT destaques FROM privado.cnm_envio_selecao WHERE id = 1),
          'Claude (Pedro, 30/10: todos os do portal menos 5609 e 5668)') AS r) x;
COMMIT;
