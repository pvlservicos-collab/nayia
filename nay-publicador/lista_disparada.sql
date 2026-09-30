-- A lista disparada nos grupos: registro e trava de repetição.
--
-- O PEDIDO (Tel, 09/09): *"quando eu pedir para a Nay disparar lista de
-- locação de apartamentos ela vai e dispara nos grupos do parceiro"*, e
-- *"Nay dispara lista no imóveis para anunciar easy — ela dispara apenas
-- no neste grupo o qual a gente envia todas as fotos"*.
--
-- POR QUE UMA TRAVA: o CLAUDE.md já registra que `postar_agora` **não tem
-- proteção contra repetição**, e que reenviar posta duas vezes em 14 grupos
-- sem desfazer. Um disparo de lista é o mesmo risco com um comando mais
-- curto de digitar. A trava é de JANELA, não definitiva: passados
-- `config.lista_repete_minutos` (padrão 30), o mesmo comando volta a valer,
-- porque disparar a mesma lista de manhã e à tarde é uso legítimo.
--
-- E A TRAVA TEM ESCAPE: "de novo", "novamente", "mesmo assim" passam por
-- cima dela. Trava sem escape vira parede, e parede que o dono não consegue
-- abrir acaba desligada.
--
-- POR QUE A RESERVA É ATÔMICA (`pg_advisory_xact_lock`): a lição do
-- `postar_easy`, escrita no publicador em 25/08 -- SELECT (checa) → envia →
-- INSERT (grava) deixa uma janela de segundos entre checar e gravar, e duas
-- chamadas nesse intervalo passam as duas. Aqui o lock serializa as duas
-- chamadas na MESMA chave (categoria+negócio+destino): a segunda espera a
-- primeira commitar e então enxerga a linha.
--
--   docker cp lista_disparada.sql nay-postgres:/tmp/l.sql
--   docker exec nay-postgres psql -U nay -d naydb -f /tmp/l.sql

CREATE TABLE IF NOT EXISTS lista_disparada (
  id          serial PRIMARY KEY,
  categoria   text NOT NULL,
  negocio     text NOT NULL,
  destino     text NOT NULL,          -- 'parceiros' | 'easy'
  quantos     int,                    -- imóveis na lista
  grupos      text[],                 -- os que REALMENTE receberam
  enviado_em  timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS lista_disparada_recente
  ON lista_disparada (categoria, negocio, destino, enviado_em DESC);

INSERT INTO config (chave, valor)
SELECT 'lista_repete_minutos', '30'
 WHERE NOT EXISTS (SELECT 1 FROM config WHERE chave = 'lista_repete_minutos');


-- Reserva o disparo, ou diz quando o mesmo já saiu.
--
-- Devolve `id` preenchido = pode mandar. `id` nulo com `ja_foi_em`
-- preenchido = já saiu agora há pouco, não mande.
--
-- Quem chama tem que COMMITAR na hora: o lock é da transação, e segurá-lo
-- durante o envio (dezenas de segundos) travaria a fila inteira -- o mesmo
-- motivo pelo qual o `postar_easy` commita a reserva antes de enviar.
CREATE OR REPLACE FUNCTION nay_reservar_disparo_de_lista(
    p_categoria text,
    p_negocio   text,
    p_destino   text,
    p_forcar    boolean DEFAULT false)
RETURNS TABLE(id int, ja_foi_em timestamptz)
LANGUAGE plpgsql AS $fn$
DECLARE
  v_min    int;
  v_ultimo timestamptz;
  v_id     int;
BEGIN
  PERFORM pg_advisory_xact_lock(
    hashtext('lista_disparada:' || coalesce(p_categoria,'') || ':' ||
             coalesce(p_negocio,'') || ':' || coalesce(p_destino,'')));

  SELECT nullif(c.valor,'')::int INTO v_min
    FROM config c WHERE c.chave = 'lista_repete_minutos';
  v_min := coalesce(v_min, 30);

  IF NOT coalesce(p_forcar, false) THEN
    SELECT max(d.enviado_em) INTO v_ultimo
      FROM lista_disparada d
     WHERE d.categoria = p_categoria
       AND d.negocio   = p_negocio
       AND d.destino   = p_destino
       AND d.enviado_em > now() - make_interval(mins => v_min);
    IF v_ultimo IS NOT NULL THEN
      RETURN QUERY SELECT NULL::int, v_ultimo;
      RETURN;
    END IF;
  END IF;

  INSERT INTO lista_disparada (categoria, negocio, destino)
       VALUES (p_categoria, p_negocio, p_destino)
    RETURNING lista_disparada.id INTO v_id;

  RETURN QUERY SELECT v_id, NULL::timestamptz;
END;
$fn$;
