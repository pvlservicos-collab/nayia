-- =====================================================================
-- NAI -- 111b: a cortesia dela nao pode morrer na porta (23/09/2026)
--
-- MEDIDO no espelho, logo depois de aplicar a 111:
--     nai_saida 32306  link_de_catalogo  simulado   (o aviso ao Tel saiu)
--     nai_saida 32307  resposta          BLOQUEADO  tel_assumiu
--                      "Recebi, Sr. Treino! Ja te respondo por aqui."
--
-- Ou seja: eu mandava parar o chat DENTRO da mesma chamada, e o portao --
-- que confere na hora de soltar -- barrava a propria linha de cortesia. O
-- corretor ficaria sem nada, que e exatamente o que eu queria evitar.
--
-- A secretaria (99) ja resolvia isso do jeito certo: ela avisa o Tel e NAO
-- para o chat. Aqui fica igual. Se o corretor mandar outro link, a parede
-- toca de novo -- e o Tel continua com o DEVOLVER e o PARAR na mao quando
-- quiser assumir.
-- =====================================================================

\set ON_ERROR_STOP on

BEGIN;

CREATE OR REPLACE FUNCTION public.nai_escalar_link_de_catalogo(p_turno bigint, p_escreveu text)
 RETURNS text LANGUAGE plpgsql
AS $function$
DECLARE t nai_turno; k nai_contato; v_nome text;
BEGIN
  SELECT * INTO t FROM nai_turno WHERE id = p_turno;
  SELECT * INTO k FROM nai_contato WHERE id = t.contato_id;
  IF k.id IS NULL THEN RETURN NULL; END IF;
  v_nome := coalesce(k.nome_completo, k.nome_whatsapp, k.telefone);

  PERFORM nai_avisar_tel(p_turno, NULL,
    'Tel, ' || v_nome || ' (' || nai_fone_fmt(k.telefone) || ') perguntou de um imóvel mandando o '
    || 'link do catálogo do WhatsApp:' || E'\n' || left(coalesce(p_escreveu, ''), 400) || E'\n'
    || 'O link não diz qual imóvel é — só você abrindo dá para ver.'
    || E'\nFalei só que recebi e que já respondo; a conversa segue comigo. '
    || 'Se quiser assumir: PARAR ' || nai_fone_fmt(k.telefone) || '.',
    'link_de_catalogo');

  PERFORM nai_usou_ferramenta(p_turno, 'escalar');

  RETURN ('Recebi' || coalesce(', ' || nai_vocativo(coalesce(k.nome_completo, k.nome_whatsapp)), '')
          || '! Já te respondo por aqui.')::text;
END;
$function$;

COMMIT;
