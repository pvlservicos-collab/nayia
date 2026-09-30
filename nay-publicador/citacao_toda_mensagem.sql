-- A citação passa a resolver por QUALQUER mensagem que a gente mandou,
-- não só pelos cards que viraram linha em `envios`.
--
-- O QUE EU TINHA DITO QUE ESTAVA RESOLVIDO, E NÃO ESTAVA. Em 01/09 eu
-- escrevi que "a citação resolve por igualdade de message_id". O sinal da
-- Z-API chega mesmo -- conferido, `citado_id` vem preenchido nas duas
-- conversas abaixo. O que faltava era o outro lado: o ID que ela cita não
-- estava guardado em lugar nenhum.
--
-- OS DOIS CASOS REAIS, de 01/09 à noite:
--
--   * WALDYRENE, 21h46. Respondeu ao card do Smart Tower Itapuranga (5712)
--     postado no grupo "IMÓVEIS PARA ANUNCIAR EASY" e escreveu "ainda
--     disponivel". `citado_id = 3EB0353248E053CFFFCAF2`, e esse ID não
--     existe em `envios`: o caminho `postar_easy` do publicador era o
--     ÚNICO que postava e não registrava. (Consertado no publicador, na
--     mesma leva.)
--
--   * ALICE, 21h57 e 21h58. Marcou duas mensagens da própria Nay e a Nay
--     respondeu "não consigo identificar qual imóvel foi citado" -- duas
--     vezes seguidas. Os IDs também não estavam em `envios`, e por um
--     motivo diferente: `Registrar envio` só grava quando a resposta dela
--     tem `Código: NNNN`. A mensagem que a Alice marcou era a LISTA
--     ("• 2943 — 2 quartos — 3.500 / • 5611 — 3 quartos — 4.600"), que não
--     tem esse rótulo. Card ela registrava; conversa, não.
--
-- A CORREÇÃO É DE COBERTURA, não de algoritmo: guardar o texto de TODA
-- mensagem que sai, com o ID dela. Aí a citação resolve pelo texto, seja
-- qual for o formato de hoje ou de amanhã -- e não volta a quebrar quando
-- o formato do card mudar.
--
-- E CONTINUA VALENDO A REGRA DO TEL: quando não dá para saber, PERGUNTA.
-- Se a mensagem citada tem dois códigos dentro, isso não vira palpite --
-- vira a lista dos dois, para ele escolher.
--
--   docker cp citacao_toda_mensagem.sql nay-postgres:/tmp/ct.sql
--   docker exec nay-postgres psql -U nay -d naydb -f /tmp/ct.sql

CREATE TABLE IF NOT EXISTS mensagem_saida (
  message_id  text PRIMARY KEY,
  telefone    text,
  texto       text,
  enviado_em  timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS mensagem_saida_tel
  ON mensagem_saida (telefone, enviado_em DESC);

-- --------------------------------------------------------------------
-- Os códigos que uma mensagem NOSSA menciona.
--
-- Usa `nay_codigos_citados`, que já tira os valores antes de procurar
-- código -- senão "locação: 3.500" viraria o imóvel 3500, e a faixa de
-- códigos deste catálogo (45 a 5712) é a mesma de um valor de aluguel.
CREATE OR REPLACE FUNCTION nay_codigos_da_saida(p_message_id text)
RETURNS text[] LANGUAGE sql STABLE AS $fn$
  SELECT nay_codigos_citados(coalesce(s.texto,''))
    FROM mensagem_saida s
   WHERE s.message_id = NULLIF(btrim(coalesce(p_message_id,'')), '')
   LIMIT 1;
$fn$;

-- --------------------------------------------------------------------
-- De qual imóvel é a mensagem que ele marcou.
--
-- Ordem: primeiro `envios`, que é o registro explícito de "mandei o
-- imóvel X para fulano" e não depende de interpretar texto. Só quando não
-- há linha lá é que o texto entra -- e mesmo assim só quando o texto
-- aponta para UM imóvel. Dois códigos na mensagem citada devolve NULL, e
-- NULL leva a perguntar com a lista, nunca a escolher um.
CREATE OR REPLACE FUNCTION nay_imovel_da_citacao(p_message_id text)
RETURNS text LANGUAGE plpgsql STABLE AS $fn$
DECLARE
  v_id   text := NULLIF(btrim(coalesce(p_message_id,'')), '');
  v_cod  text;
  v_cods text[];
BEGIN
  IF v_id IS NULL THEN RETURN NULL; END IF;

  SELECT e.codigo INTO v_cod
    FROM envios e
   WHERE e.message_id = v_id
   ORDER BY e.enviado_em DESC
   LIMIT 1;
  IF v_cod IS NOT NULL THEN RETURN v_cod; END IF;

  v_cods := nay_codigos_da_saida(v_id);
  IF coalesce(array_length(v_cods,1),0) = 1 THEN
    -- Só existe se for imóvel de verdade: número solto num texto nosso
    -- pode ser qualquer coisa.
    SELECT i.codigo::text INTO v_cod FROM imoveis i WHERE i.codigo::text = v_cods[1];
    RETURN v_cod;
  END IF;

  RETURN NULL;
END;
$fn$;

-- --------------------------------------------------------------------
-- Quando a mensagem citada fala de MAIS DE UM imóvel, a pergunta pode
-- ser específica em vez de genérica. "de qual imóvel você fala?" depois
-- de ele ter apontado para a mensagem é a pergunta que mais irritou o
-- Tel: a informação estava ali.
CREATE OR REPLACE FUNCTION nay_opcoes_da_citacao(p_message_id text)
RETURNS text LANGUAGE plpgsql STABLE AS $fn$
DECLARE
  v_cods text[] := nay_codigos_da_saida(p_message_id);
  v_lista text;
BEGIN
  IF coalesce(array_length(v_cods,1),0) < 2 THEN RETURN NULL; END IF;

  SELECT string_agg('• ' || i.codigo || ' — '
                    || coalesce(NULLIF(i.condominio_nome,''), NULLIF(i.tipo,''), 'imóvel')
                    || coalesce(' — ' || i.quartos || ' quartos', ''),
                    chr(10) ORDER BY i.codigo)
    INTO v_lista
    FROM imoveis i
   WHERE i.codigo::text = ANY (v_cods);

  RETURN v_lista;
END;
$fn$;
