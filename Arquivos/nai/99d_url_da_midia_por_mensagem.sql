-- =====================================================================
-- NAI -- 99d: a url da midia fica gravada em cada mensagem
-- (Tel, 22/09/2026)
--
-- POR QUE: o ramo que le a imagem so enxerga UMA midia -- a do webhook que
-- ganhou a janela. Quando o corretor manda cinco fotos do imovel dele, as
-- outras quatro nao existem para o sistema. Para o cadastro da secretaria isso
-- e fatal: imovel com uma foto so.
--
-- Guardando a url em cada linha de `mensagens`, o turno inteiro tem as fotos:
-- `msg_ids` ja aponta para todas.
--
-- DE QUEBRA: a coluna `audio_url` existe desde o fluxo antigo e nunca foi
-- preenchida -- 1.106 audios, zero urls. Agora audio e imagem usam o mesmo
-- caminho.
-- =====================================================================

\set ON_ERROR_STOP on

BEGIN;

ALTER TABLE mensagens ADD COLUMN IF NOT EXISTS midia_url text;

-- TODAS as fotos do turno viram fotos da ficha aberta. Sem ficha aberta, nao
-- faz nada -- foto de conversa comum nao vira imovel.
CREATE OR REPLACE FUNCTION public.nai_sec_guardar_fotos_do_turno(p_turno bigint)
 RETURNS integer LANGUAGE plpgsql
AS $function$
DECLARE t nai_turno; v_id bigint; n int := 0;
BEGIN
  SELECT * INTO t FROM nai_turno WHERE id = p_turno;
  IF t.id IS NULL THEN RETURN 0; END IF;

  SELECT x.id INTO v_id FROM nai_imovel_novo x
   WHERE x.contato_id = t.contato_id AND x.situacao = 'colhendo'
   ORDER BY x.id DESC LIMIT 1;
  IF v_id IS NULL THEN RETURN 0; END IF;

  INSERT INTO nai_imovel_novo_foto (novo_id, url)
  SELECT v_id, m.midia_url
    FROM mensagens m
   WHERE m.id = ANY (coalesce(t.msg_ids, '{}'))
     AND m.midia_url ~ '^https?://'
     AND m.origem IN ('imagem', 'documento')
     -- a mesma foto nao entra duas vezes se o turno for reprocessado
     AND NOT EXISTS (SELECT 1 FROM nai_imovel_novo_foto f
                      WHERE f.novo_id = v_id AND f.url = m.midia_url);
  GET DIAGNOSTICS n = ROW_COUNT;
  IF n > 0 THEN
    PERFORM nai_anotar(p_turno, 6, 'fotos_do_cadastro', 'mudou', n || ' fotos na ficha ' || v_id);
  END IF;
  RETURN n;
END;
$function$;

COMMIT;

SELECT 'midia_url' AS coluna,
       (SELECT count(*) FROM information_schema.columns
         WHERE table_name = 'mensagens' AND column_name = 'midia_url') AS existe;
