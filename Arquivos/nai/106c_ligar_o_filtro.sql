-- =====================================================================
-- NAI -- 106c: o filtro de palavras entra no caminho (Tel, 23/09/2026)
--
-- Ele: "ela conserta a palavra antes ate de enviar para a Nay".
--
-- `nai_abrir_turno` e o unico lugar por onde TODO texto passa antes de
-- qualquer coisa acontecer -- antes da porta decidir se atende, antes de o
-- turno ser gravado e antes de o modelo ler. Entao o filtro entra aqui, e de
-- uma vez so vale para os tres.
--
-- O COMANDO DO TEL FICA DE FORA. "DEVOLVER 9296..." e "RESPOSTA 81 ..." nao
-- sao nome de condominio, e um filtro de palavras nunca pode poder quebrar um
-- comando dele. Por isso a trava por `nai_pode_comandar`.
-- =====================================================================

\set ON_ERROR_STOP on

BEGIN;

DO $mig$
DECLARE v_def text; v_alvo text;
BEGIN
  v_def := pg_get_functiondef('nai_abrir_turno'::regproc);
  IF position('nai_corrigir_nomes' IN v_def) > 0 THEN
    RAISE NOTICE 'o filtro ja esta ligado'; RETURN;
  END IF;

  v_alvo := '  v_teste := v_chave = ANY (nai_chaves_teste());';
  IF position(v_alvo IN v_def) = 0 THEN
    RAISE EXCEPTION 'nao achei o ponto de entrada no abrir_turno';
  END IF;

  EXECUTE replace(v_def, v_alvo, v_alvo || E'\n\n'
    || '  -- O FILTRO DE PALAVRAS (106, Tel 23/09: "se ela estiver escrita mais ou' || E'\n'
    || '  -- menos certo, acima de 70% da palavra certa ela conserta a palavra antes' || E'\n'
    || '  -- ate de enviar para a Nay"). "bom pedro" vira Dom Pedro, "aquarelli" vira' || E'\n'
    || '  -- Acquarelle -- e isso vale para a PORTA tambem, que assim reconhece o' || E'\n'
    || '  -- imovel nosso mesmo quando o nome chega torto do audio.' || E'\n'
    || '  -- O comando do Tel nao passa por aqui: filtro de palavras nao pode ter' || E'\n'
    || '  -- poder de quebrar um DEVOLVER.' || E'\n'
    || '  IF NOT nai_pode_comandar(v_chave) THEN' || E'\n'
    || '    v_texto := nai_corrigir_nomes(v_texto);' || E'\n'
    || '  END IF;');
  RAISE NOTICE 'filtro de palavras ligado no abrir_turno';
END $mig$;

COMMIT;

SELECT 'o filtro esta no caminho?' AS o,
       CASE WHEN pg_get_functiondef('nai_abrir_turno'::regproc) ~ 'nai_corrigir_nomes'
            THEN 'sim' ELSE 'NAO' END AS resposta;
