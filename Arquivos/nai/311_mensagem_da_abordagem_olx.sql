-- 311 (08/10/2026): A MENSAGEM DA ABORDAGEM NA OLX É OUTRA.
-- Pedro: "o modelo da mensagem não é aquele que temos cliente, é esse aqui,
-- implemente o de abordagem olx". O texto dele, colado:
--
--   Oii, boa noite! Me chamo Nay Mendes, da Imob Easy.
--   Tenho uns clientes procurando imóveis na região do seu!
--   Posso apresentar pra eles?
--   Se gostarem, eu cuido de tudo: visita, documentação, contrato e assinatura.
--   Sem exclusividade, você continua vendendo aqui no OLX.
--   Me passa seu nome e seu WhatsApp que a gente conversa melhor.
--
-- SAI a frase do cliente ("uma família procurando um apartamento maior...") e SAI
-- o nome do bairro. FICAM só dois marcadores:
--   {saudacao}    bom dia / boa tarde / boa noite, pela hora de Manaus
--   {anunciando}  "vendendo" na venda; no aluguel "anunciando" (dono que aluga
--                 não está "vendendo")
--
-- Só o texto muda (tabela anuncio_abordagem_texto). A função que monta
-- (crm_anuncio_mensagem) é a mesma: marcador que não está no texto não faz nada.
-- As frases cliente_* ficam guardadas, fora de uso.
BEGIN;
SET LOCAL lock_timeout = '3s';

DO $do$
DECLARE
  v_n int;
BEGIN
  UPDATE anuncio_abordagem_texto
     SET texto = $t$Oii, {saudacao}! Me chamo Nay Mendes, da Imob Easy.

Tenho uns clientes procurando imóveis na região do seu!

Posso apresentar pra eles?

Se gostarem, eu cuido de tudo: visita, documentação, contrato e assinatura. Sem exclusividade, você continua {anunciando} aqui no OLX.

Me passa seu nome e seu WhatsApp que a gente conversa melhor.$t$,
         nota = 'O texto inteiro (Pedro, 08/10, 311). Marcadores: {saudacao} {anunciando}.',
         atualizado_em = now()
   WHERE chave = 'mensagem';
  GET DIAGNOSTICS v_n = ROW_COUNT;
  IF v_n <> 1 THEN RAISE EXCEPTION '311: esperava trocar 1 texto, troquei %', v_n; END IF;

  UPDATE anuncio_abordagem_texto
     SET nota = 'FORA DE USO desde a 311 (08/10): a mensagem não cita mais o cliente. ' || coalesce(nota, ''),
         atualizado_em = now()
   WHERE chave LIKE 'cliente\_%' AND coalesce(nota, '') NOT LIKE 'FORA DE USO%';
END
$do$;
COMMIT;
