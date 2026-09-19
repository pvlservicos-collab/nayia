-- Ela responde UMA coisa quando o corretor pediu DUAS.
--
-- OS DOIS CASOS, os dois de 01/09 à noite, e os dois com o mesmo formato:
-- duas mensagens do corretor caem no mesmo turno (a janela de 25s junta),
-- e a Nay responde só a última.
--
--   * WALDYRENE, 22h02. O turno foi "os dois acquareles locacao é o de 02
--     e 03 quartos" + "me evia os de venda tambem". Ela mandou QUATRO
--     cards de VENDA e nenhum de locação. Medido na execução 3768: o
--     texto que chegou ao agente tinha as duas frases.
--
--   * ALICE, 21h00. "Cliente gostaria de agendar uma visita" + "Está
--     disponível?". Ela pediu o código, recebeu, mandou o card -- e não
--     falou uma palavra sobre a visita. O Tel teve que responder à mão.
--
-- POR QUE ISSO NÃO É "SÓ CAPRICHO DO MODELO": o turno chega como um
-- parágrafo só, e a última frase é a que fica mais perto da resposta. Sem
-- alguém apontar o que ficou pendente, o modelo fecha o turno satisfeito.
--
-- ESTES SÃO AVISOS, NÃO PAREDES, e é honesto dizer isso: não existe
-- ferramenta que force uma resposta a cobrir dois assuntos. O que dá para
-- fazer é a mesma coisa que funcionou no `pedeUnidade` -- transformar o
-- que estava implícito no texto em um campo que o turno carrega, para o
-- modelo não ter que perceber sozinho.
--
--   docker cp pedidos_do_turno.sql nay-postgres:/tmp/pt.sql
--   docker exec nay-postgres psql -U nay -d naydb -f /tmp/pt.sql

-- Ele está pedindo VISITA? A visita tem ferramenta própria
-- (`avaliar_visita`), e mandar o card não responde a pergunta.
CREATE OR REPLACE FUNCTION nay_pede_visita(p_texto text)
RETURNS boolean LANGUAGE sql IMMUTABLE AS $fn$
  SELECT coalesce(lower(unaccent(coalesce(p_texto,''))) ~
    '\m(visita|visitar|visitas|agendar|agendamento|marcar|conhecer o imovel|ver o imovel|ver o ap)\M',
    false);
$fn$;

-- Venda, locação, ou OS DOIS na mesma fala. O terceiro caso é o que
-- quebrou: "os de locação... me envia os de venda também".
CREATE OR REPLACE FUNCTION nay_negocio_pedido(p_texto text)
RETURNS text LANGUAGE plpgsql IMMUTABLE AS $fn$
DECLARE
  t text := lower(unaccent(coalesce(p_texto,'')));
  v boolean := t ~ '\m(venda|vender|vendas|comprar|compra|a venda)\M';
  l boolean := t ~ '\m(locacao|aluguel|alugar|aluga|alugado|locar)\M';
BEGIN
  IF v AND l THEN RETURN 'ambos'; END IF;
  IF v THEN RETURN 'venda'; END IF;
  IF l THEN RETURN 'locacao'; END IF;
  RETURN NULL;
END;
$fn$;
