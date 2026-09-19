-- A mensagem marcada volta a apontar para o imóvel certo.
--
-- O CASO (01/09, 09h51): o Victor marcou o card do Rio Amazonas
-- Residencial que saiu no grupo e escreveu "Me manda esse". A Nay
-- respondeu "de qual imóvel você fala? me manda o código".
--
-- Perguntar já é melhor que chutar -- em 31/08 ela respondia do imóvel
-- errado. Mas dava para acertar, e faltava uma peça só.
--
-- O QUE JÁ FUNCIONAVA: desde 01/09 a Z-API entrega `referenceMessageId`
-- e o fluxo grava em `mensagens.citado_id`. A mensagem 2993 tem
-- `3EB044B725B8C809EE1FD0` -- o ID da mensagem que ele marcou.
--
-- O QUE FALTAVA: ninguém guardava o ID das mensagens que a GENTE manda.
-- Com o ID do card na ponta e o ID guardado em `envios`, a citação vira
-- o código, sem heurística nenhuma -- é igualdade, não semelhança.
--
--   docker cp citacao_resolve.sql nay-postgres:/tmp/cr.sql
--   docker exec nay-postgres psql -U nay -d naydb -f /tmp/cr.sql

ALTER TABLE envios ADD COLUMN IF NOT EXISTS message_id text;

-- O ID vem da Z-API e é único por mensagem; o índice serve para a busca
-- da citação, que roda a cada mensagem marcada.
CREATE INDEX IF NOT EXISTS envios_message_id ON envios (message_id)
  WHERE message_id IS NOT NULL;

-- --------------------------------------------------------------------
-- De qual imóvel é a mensagem que ele marcou?
--
-- Devolve NULL quando não sabe -- e não saber tem que continuar levando
-- à pergunta, nunca ao chute. É o mesmo princípio de tudo aqui: o dado
-- prova, ou ela pergunta.
CREATE OR REPLACE FUNCTION nay_imovel_da_citacao(p_message_id text)
RETURNS text
LANGUAGE sql STABLE AS $fn$
  SELECT e.codigo
    FROM envios e
   WHERE e.message_id = NULLIF(btrim(coalesce(p_message_id,'')), '')
   ORDER BY e.enviado_em DESC
   LIMIT 1;
$fn$;

-- --------------------------------------------------------------------
-- O que ela deve saber quando o corretor marca uma mensagem.
--
-- Junta as duas metades: se a citação resolve, ela SABE o imóvel e não
-- pergunta nada; se não resolve, cai na lista do `nay_qual_imovel`, que
-- nunca escolhe por ele.
CREATE OR REPLACE FUNCTION nay_imovel_marcado(
  p_telefone text, p_message_id text
) RETURNS TABLE(texto_pronto text, codigo text, instrucao_para_voce text)
LANGUAGE plpgsql STABLE AS $fn$
DECLARE
  v_cod  text := nay_imovel_da_citacao(p_message_id);
  v_nome text;
BEGIN
  IF v_cod IS NOT NULL THEN
    SELECT coalesce(NULLIF(i.condominio_nome,''), i.tipo, 'o imóvel')
      INTO v_nome FROM imoveis i WHERE i.codigo::text = v_cod;

    RETURN QUERY SELECT
      ''::text, v_cod,
      ('ele marcou a mensagem do imovel ' || v_cod || ' (' || coalesce(v_nome,'?')
       || '). E DESSE que ele fala -- isto nao e palpite, e a mensagem que ele '
       || 'apontou. Siga a conversa com esse codigo, sem perguntar qual e.')::text;
    RETURN;
  END IF;

  -- Não resolveu: cai na lista da conversa. NUNCA chuta.
  RETURN QUERY
  SELECT q.texto_pronto, NULL::text,
         q.instrucao_para_voce || ' (Ele marcou uma mensagem que voce nao '
         || 'consegue identificar -- pode ser card de outro corretor, de outro '
         || 'grupo, ou anterior ao registro. Por isso pergunte.)'
    FROM nay_qual_imovel(p_telefone) q;
END;
$fn$;
