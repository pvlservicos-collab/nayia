-- A Nay manda sozinha o imóvel que ficou de mandar.
--
-- O CASO: em 30/08 o Gustavo pediu três imóveis e não recebeu nenhum. Em
-- 31/08 o Ênio deu o perfil e também ficou sem. Nos dois, quem acabou
-- mandando fui EU, rodando comando no servidor -- e o Tel foi direto ao
-- ponto: "preciso que a Nay reconheça isso e envie ela mesma".
--
-- POR QUE ISSO NÃO É O LEMBRETE: o lembrete cobra RESPOSTA do corretor
-- ("a cliente decidiu?"). Aqui é o contrário -- somos nós que devemos
-- algo a ele. O que compartilham é o disparador: o cron de minuto em
-- minuto, o teto de uma mensagem por dia, e a pausa geral.
--
-- O QUE DECIDE, e é dado e não julgamento: `envios` diz o que saiu de
-- verdade; `mensagens` diz de que imóvel se falou. O que está numa e não
-- na outra é dívida. Pedir ao modelo que "lembre o que prometeu" foi o
-- que deixou o Gustavo dois dias esperando.
--
-- NUNCA MANDA SEM O CORRETOR TER PEDIDO: a dívida só nasce quando ele
-- pede -- "me manda", "quero ver", "tem fotos". Card que a Nay ofereceu e
-- ele ignorou não vira entrega; seria a Nay empurrando imóvel.
--
--   docker cp entrega_pendente.sql nay-postgres:/tmp/ep.sql
--   docker exec nay-postgres psql -U nay -d naydb -f /tmp/ep.sql

CREATE TABLE IF NOT EXISTS entrega_pendente (
  id           bigserial PRIMARY KEY,
  telefone     text NOT NULL,
  codigo       text NOT NULL,
  motivo       text,                     -- a frase dele que gerou a dívida
  estado       text NOT NULL DEFAULT 'devendo',
  criado_em    timestamptz NOT NULL DEFAULT now(),
  entregue_em  timestamptz,
  CONSTRAINT entrega_estado_ok CHECK (estado IN ('devendo','entregue','cancelada'))
);

CREATE UNIQUE INDEX IF NOT EXISTS entrega_uma_viva
  ON entrega_pendente (telefone, codigo) WHERE estado = 'devendo';

-- --------------------------------------------------------------------
-- Registra a dívida. Chamada pela ferramenta da Nay quando o corretor
-- pede um imóvel: se ela conseguir mandar na hora, marca como entregue no
-- mesmo movimento; se não, fica devendo e o cron resolve.
CREATE OR REPLACE FUNCTION nay_ficou_devendo(
  p_telefone text, p_codigo text, p_motivo text
) RETURNS text
LANGUAGE plpgsql AS $fn$
DECLARE
  v_tel text := regexp_replace(coalesce(p_telefone,''),'[^0-9]','','g');
  v_cod text := NULLIF(regexp_replace(coalesce(p_codigo,''),'[^0-9]','','g'),'');
BEGIN
  IF v_cod IS NULL OR v_tel = '' THEN
    RETURN 'sem codigo ou telefone, nao registrei nada.';
  END IF;

  -- O CODIGO TEM QUE TER VINDO DO CORRETOR. Sem isto, o modelo inventa um
  -- codigo (foi o que fez em 01/09, passando 5717 numa pergunta sobre o
  -- 4946), a divida nasce do imovel errado e o cron entrega o card errado
  -- sozinho, de madrugada, sem ninguem revisar. Ver codigo_confirmado.sql.
  IF nay_codigo_confirmado(p_telefone, v_cod) = 'nao' THEN
    RETURN 'esse corretor nao pediu o imovel ' || v_cod || ' e voce nao mandou '
        || 'esse card para ele. NAO registrei divida nenhuma: pergunte a ele de '
        || 'qual imovel esta falando antes de anotar.';
  END IF;

  -- Imovel que saiu do mercado nao vira divida.
  IF NOT EXISTS (SELECT 1 FROM imoveis i
                  WHERE i.codigo::text = v_cod AND coalesce(i.disponivel, true)) THEN
    RETURN 'o imovel ' || v_cod || ' nao esta disponivel, nao registrei divida.';
  END IF;

  -- IMOVEL DE PARCEIRO NAO VAI PELO CRON. `imovel_por_codigo` mostra so o
  -- nome do condominio e avisa que e de parceria -- sem bairro, sem valor,
  -- sem foto. O cron nao passa por ali: ele le o site AO VIVO e manda card
  -- cheio com todas as fotos, furando a reducao inteira. E sao 909 dos
  -- 1.208 disponiveis, 75% do catalogo. Achado na auditoria de 01/09.
  IF EXISTS (SELECT 1 FROM imoveis i
              WHERE i.codigo::text = v_cod AND coalesce(i.e_parceiro, false)) THEN
    RETURN 'o imovel ' || v_cod || ' e de parceria: nao registrei divida porque '
        || 'a entrega automatica mandaria o card completo. Responda agora na '
        || 'conversa com imovel_por_codigo, que mostra o que pode ser mostrado '
        || 'de imovel de parceiro.';
  END IF;

  -- Já mandou nas últimas 12h: não é dívida.
  IF EXISTS (SELECT 1 FROM envios e
              WHERE e.codigo = v_cod AND e.destino = 'corretor'
                AND right(regexp_replace(e.telefone,'[^0-9]','','g'),8) = right(v_tel,8)
                AND e.enviado_em > now() - interval '12 hours') THEN
    RETURN 'esse imovel ja foi para ele hoje, nao registrei.';
  END IF;

  INSERT INTO entrega_pendente (telefone, codigo, motivo)
  VALUES (v_tel, v_cod, left(coalesce(p_motivo,''), 200))
  ON CONFLICT (telefone, codigo) WHERE estado = 'devendo' DO NOTHING;

  RETURN 'anotei que devo o imovel ' || v_cod || ' a esse corretor.';
END;
$fn$;

-- --------------------------------------------------------------------
-- O que o cron precisa entregar agora. Respeita a pausa geral e o teto de
-- um contato por dia -- as mesmas paredes do lembrete, pelas mesmas razões.
CREATE OR REPLACE FUNCTION nay_entregas_devidas()
RETURNS TABLE(telefone text, ids bigint[], codigos text, abertura text)
LANGUAGE sql STABLE AS $fn$
  WITH ok AS (
    SELECT NOT COALESCE((SELECT valor = 'sim' FROM config
                          WHERE chave = 'atendimento_pausado'), true) AS pode
  ), devidas AS (
    SELECT p.*, coalesce(split_part(btrim(c.nome),' ',1), '') AS primeiro_nome
      FROM entrega_pendente p
      JOIN imoveis i ON i.codigo::text = p.codigo
      LEFT JOIN corretores c ON right(regexp_replace(c.telefone,'[^0-9]','','g'),8)
                              = right(regexp_replace(p.telefone,'[^0-9]','','g'),8)
     WHERE p.estado = 'devendo'
       AND (SELECT pode FROM ok)
       AND coalesce(i.disponivel, true)   -- imóvel que saiu não se manda
       AND nay_pode_falar(p.telefone)     -- teto de 1 por dia
       -- Só depois de 3 minutos: se ela conseguir mandar na própria
       -- conversa, o cron não atropela.
       AND p.criado_em < now() - interval '3 minutes'
       -- E NÃO DEPOIS DE 24 HORAS. Dívida sem prazo faz um pedido de
       -- terça chegar no sábado, sem contexto nenhum -- o corretor já
       -- resolveu com o cliente e recebe um card do nada. Achado na
       -- auditoria de 01/09. Passado o prazo, ela não manda; se ele
       -- perguntar de novo, nasce dívida nova.
       AND p.criado_em > now() - interval '24 hours'
  )
  SELECT d.telefone,
         array_agg(d.id ORDER BY d.criado_em),
         string_agg(d.codigo, ',' ORDER BY d.criado_em),
         CASE WHEN min(d.primeiro_nome) <> '' THEN min(d.primeiro_nome) || ', segue '
              ELSE 'segue ' END
         || CASE WHEN count(*) > 1 THEN 'as opções' ELSE 'o imóvel' END
         || ' que fiquei de te enviar 👇'
    FROM devidas d
   GROUP BY d.telefone;
$fn$;

-- Reserva atômica: o cron roda de minuto em minuto e `postar_agora` já
-- provou neste projeto que sem isto o mesmo item sai duas vezes.
CREATE OR REPLACE FUNCTION nay_reservar_entregas(p_ids bigint[])
RETURNS int
LANGUAGE plpgsql AS $fn$
DECLARE n int;
BEGIN
  UPDATE entrega_pendente SET estado = 'entregue', entregue_em = now()
   WHERE id = ANY(p_ids) AND estado = 'devendo';
  GET DIAGNOSTICS n = ROW_COUNT;
  RETURN n;
END;
$fn$;

CREATE OR REPLACE FUNCTION nay_devolver_entregas(p_ids bigint[])
RETURNS int
LANGUAGE plpgsql AS $fn$
DECLARE n int;
BEGIN
  UPDATE entrega_pendente SET estado = 'devendo', entregue_em = NULL
   WHERE id = ANY(p_ids) AND estado = 'entregue';
  GET DIAGNOSTICS n = ROW_COUNT;
  RETURN n;
END;
$fn$;
