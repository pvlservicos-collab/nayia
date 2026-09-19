-- =====================================================================
-- NAI -- 43: as fotos vão SEMPRE junto com as informações (Tel, 16/09/2026)
--
-- Ele, tres vezes na mesma lista: "quando pedir me encaminha, ela tem que
-- mandar logo as fotos"; "a qualquer menção dos imóveis manda sempre
-- informações e as fotos"; e, no fim, "de novo ele pediu um imóvel e ela mandou
-- só as informações e não as fotos -- ela deve mandar sempre as fotos junto das
-- informações".
--
-- COMO ERA: `nay_deve_mandar_fotos` exigia que o corretor pedisse FOTO com
-- todas as letras, ou dissesse "sim" a uma oferta recente dela. Quem escrevia
-- "me encaminha o 5717" recebia o card e mais nada -- e tinha que pedir de
-- novo. A regra nasceu em 29/08 para o problema oposto (ela mandava foto sem
-- ninguem pedir); hoje o Tel quer o contrario, e e ele quem manda.
--
-- COMO FICA: falou de um imovel, saem as informacoes E as fotos.
--
-- DUAS EXCECOES, e as duas vieram da mesma lista dele:
--   1. quem DIZ que ja tem ("as fotos eu ja tenho", "nao precisa") nao recebe
--      de novo -- a recusa explicita continua valendo;
--   2. as fotos daquele imovel nao se repetem na mesma conversa em 24h. Ele:
--      "o Tel ja tinha pedido manualmente para ela mandar as fotos do arezzo,
--      mas ela foi la e mandou novamente; e importante ela ler o contexto da
--      conversa antes".
-- =====================================================================

-- Ela ja mandou as fotos DESTE imovel para ESTA pessoa, faz pouco?
CREATE OR REPLACE FUNCTION nai_fotos_ja_mandadas(p_contato bigint, p_codigo int, p_horas int DEFAULT 24)
RETURNS boolean LANGUAGE sql STABLE AS $$
  SELECT EXISTS (
    SELECT 1 FROM nai_saida s
     WHERE s.contato_id = p_contato
       AND s.codigo = p_codigo
       AND s.tipo = 'imagem'
       AND s.estado IN ('enviado', 'enviando', 'simulado')
       AND s.criado_em > now() - make_interval(hours => p_horas));
$$;

COMMENT ON FUNCTION nai_fotos_ja_mandadas(bigint, int, int) IS
  'As fotos desse imovel ja sairam para essa pessoa nas ultimas horas? Evita o reenvio. Tel, 16/09.';

-- O portão de fotos da NAI. Separado do da Nay antiga de proposito: as duas
-- tem donos diferentes e regras que agora divergem.
CREATE OR REPLACE FUNCTION nai_deve_mandar_fotos(p_contato bigint, p_telefone text, p_escreveu text)
RETURNS boolean LANGUAGE plpgsql STABLE AS $$
DECLARE v_txt text := lower(unaccent(btrim(coalesce(p_escreveu, ''))));
BEGIN
  -- ELE DISSE QUE JA TEM. A negacao precisa estar COLADA a palavra de foto, na
  -- mesma oracao: "ja tenho o endereco, agora me manda as fotos" e pedido, nao
  -- recusa. E o pedido explicito vence a negacao -- foi o caso do Andre, em
  -- 01/09: "ja recebi o card mas nao recebi as fotos, manda por favor".
  IF (v_txt ~ ('(ja\s+(tenho|recebi|vi|peguei)|nao\s+precisa|voce\s+ja\s+'
               || '(me\s+)?(mandou|enviou))[^.,;!?]{0,30}\m(foto|fotos|imagem|imagens|fachada|material)\M')
      OR v_txt ~ ('\m(foto|fotos|imagem|imagens|fachada|material)\M[^.,;!?]{0,30}'
                  || '(ja\s+(tenho|recebi|vi|peguei)|nao\s+precisa)'))
     AND v_txt !~ '\m(manda|mande|envia|envie|me\s+passa|por\s+favor)\M' THEN
    RETURN false;
  END IF;

  -- Fora isso: SEMPRE (Tel, 16/09). Quem chega perto de um imovel recebe as
  -- informacoes e as fotos na mesma resposta.
  RETURN true;
END;
$$;

COMMENT ON FUNCTION nai_deve_mandar_fotos(bigint, text, text) IS
  'As fotos vao junto das informacoes SEMPRE, menos para quem disse que ja tem. Tel, 16/09.';
