-- =====================================================================
-- 132 — A TRAVA DO IMÓVEL É DE 24 HORAS, NÃO DO DIA (27/09/2026)
--
-- Resposta à pergunta da 131 (se o corretor pedir o mesmo imóvel de novo):
-- "MANTEM MAS NO PRAZO DE 24 HRS, ELE PODE PEDIR DE NOVO APOS 24 HRS".
--
-- Então a regra continua sem exceção, e o que muda é a régua: não é mais "o
-- dia de Manaus" (que liberava às 00:00 um imóvel mandado às 23:50), é
-- "24 horas desde o último envio" para aquela pessoa.
--
-- Os nomes (`imovel_enviado_no_dia`, `nay_reservar_imovel_do_dia`) ficam: o
-- publicador e o entregar_pendentes chamam por eles, e trocar nome agora é
-- mexer em três lugares para ganhar só a palavra. A coluna `dia` continua
-- existindo e continua certa -- dois envios liberados ficam a 24h um do outro,
-- então nunca caem no mesmo dia e a chave primária nunca bate.
--
-- A FRASE DE RECUSA diz quando foi ("hoje às 16h31" ou "ontem às 16h31") e,
-- para o Tel, quando libera.
-- =====================================================================
\set ON_ERROR_STOP on

BEGIN;

-- "ontem às 16h31" / "hoje às 16h31" / "amanhã às 16h31", no fuso de Manaus.
CREATE OR REPLACE FUNCTION nay_quando_foi(p_em timestamptz)
RETURNS text
LANGUAGE sql
STABLE
AS $fn$
  SELECT CASE (p_em AT TIME ZONE 'America/Manaus')::date
              - (now() AT TIME ZONE 'America/Manaus')::date
              WHEN 0  THEN 'hoje'
              WHEN -1 THEN 'ontem'
              WHEN 1  THEN 'amanhã'
              ELSE 'em ' || to_char(p_em AT TIME ZONE 'America/Manaus', 'DD/MM') END
         || ' às ' || to_char(p_em AT TIME ZONE 'America/Manaus', 'HH24"h"MI');
$fn$;

CREATE OR REPLACE FUNCTION nay_reservar_imovel_do_dia(p_chave text, p_codigo integer,
                                                      p_origem text,
                                                      p_turno bigint DEFAULT NULL)
RETURNS timestamptz
LANGUAGE plpgsql
AS $fn$
DECLARE
  v_dia    date := (now() AT TIME ZONE 'America/Manaus')::date;
  v_chaves text[];
  r        imovel_enviado_no_dia;
BEGIN
  IF p_codigo IS NULL OR nay_fora_da_regra_do_dia(p_chave) THEN
    RETURN NULL;
  END IF;

  -- Dois pedidos iguais chegando juntos: o segundo espera o primeiro gravar.
  PERFORM pg_advisory_xact_lock(hashtext('imovel_24h:' || p_codigo));

  -- Todas as linhas da pessoa (telefone e @lid).
  SELECT coalesce(array_agg(DISTINCT c.chave), '{}') INTO v_chaves
    FROM nai_contato k
    JOIN nai_contato c ON c.id = ANY (nai_contato_irmaos(k.id))
   WHERE k.chave = p_chave;
  v_chaves := array_append(v_chaves, p_chave);

  -- O ÚLTIMO envio nas últimas 24 horas.
  SELECT * INTO r
    FROM imovel_enviado_no_dia e
   WHERE e.chave = ANY (v_chaves) AND e.codigo = p_codigo
     AND e.primeiro_em > now() - interval '24 hours'
   ORDER BY e.primeiro_em DESC
   LIMIT 1;

  IF r.chave IS NULL THEN
    INSERT INTO imovel_enviado_no_dia (chave, codigo, dia, origem, turno_id)
    VALUES (p_chave, p_codigo, v_dia, p_origem, p_turno)
    ON CONFLICT (chave, codigo, dia) DO UPDATE
       SET primeiro_em = now(), origem = EXCLUDED.origem, turno_id = EXCLUDED.turno_id;
    RETURN NULL;
  END IF;

  -- A mesma resposta continuando (card e fotos são linhas separadas).
  IF p_turno IS NOT NULL AND r.turno_id = p_turno THEN
    RETURN NULL;
  END IF;

  RETURN r.primeiro_em;
END;
$fn$;

-- As duas frases que a 131 escreveu com "hoje" fixo.
DO $do$
DECLARE
  v_def text;
BEGIN
  v_def := pg_get_functiondef('nai_saida_validar'::regproc);
  IF position('''O '' || v_cod || '' eu já mandei hoje às ''' IN v_def) = 0 THEN
    RAISE EXCEPTION 'nai_saida_validar mudou: a frase da 131 nao esta la';
  END IF;
  v_def := replace(v_def,
    $a$NEW.texto := 'O ' || v_cod || ' eu já mandei hoje às '
                     || to_char(v_ja AT TIME ZONE 'America/Manaus', 'HH24"h"MI')
                     || ', está aqui em cima na conversa.';$a$,
    $b$NEW.texto := 'O ' || v_cod || ' eu já mandei ' || nay_quando_foi(v_ja)
                     || ', está aqui em cima na conversa.';$b$);
  v_def := replace(v_def,
    $a$NEW.bloqueio := 'imovel ja enviado hoje para este corretor ('
                          || to_char(v_ja AT TIME ZONE 'America/Manaus', 'HH24:MI') || ')';$a$,
    $b$NEW.bloqueio := 'imovel ja enviado a este corretor nas ultimas 24h ('
                          || nay_quando_foi(v_ja) || ')';$b$);
  IF position('nay_quando_foi(v_ja)' IN v_def) = 0 THEN
    RAISE EXCEPTION 'nai_saida_validar: a troca da frase nao pegou';
  END IF;
  EXECUTE v_def;

  v_def := pg_get_functiondef('nai_enviar_imovel_para'::regproc);
  v_def := replace(v_def,
    $a$RETURN 'O ' || p_codigo || ' já foi hoje para ' || nai_fone_fmt(v_digitos)
           || ', às ' || to_char(v_ja AT TIME ZONE 'America/Manaus', 'HH24"h"MI')
           || '. Não mandei de novo: um imóvel por corretor por dia.';$a$,
    $b$RETURN 'O ' || p_codigo || ' já foi para ' || nai_fone_fmt(v_digitos)
           || ' ' || nay_quando_foi(v_ja) || '. Não mandei de novo: o mesmo imóvel'
           || ' só volta para o mesmo corretor depois de 24 horas ('
           || nay_quando_foi(v_ja + interval '24 hours') || ').';$b$);
  IF position('nay_quando_foi(v_ja)' IN v_def) = 0 THEN
    RAISE EXCEPTION 'nai_enviar_imovel_para: a troca da frase nao pegou';
  END IF;
  EXECUTE v_def;
END;
$do$;

COMMIT;
