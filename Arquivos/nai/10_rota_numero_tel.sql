-- =====================================================================
-- NAI -- 10: o numero do Tel dentro do teste (13/09/2026)
--
-- Pedido: "liga para o numero do Tel tambem" (92 9471-7316), mantendo os
-- comandos do publicador. O roteador do "Nay- recebe mensagem" manda TUDO de
-- um numero em teste para a NAI -- e os comandos do publicador ("Alugou...",
-- "envia esse imovel para a Geina...", "posta...", "Vagas", "RESPOSTA N")
-- so existem no caminho antigo. Medido: 13 desses em 7 dias, o ultimo hoje as
-- 07:33. Sem esta funcao eles parariam enquanto o numero estivesse no teste.
--
-- A regra e ESTREITA de proposito: "me manda as fotos do 5718", "manda as
-- fotos pra mim" e "tira uma duvida" sao conversa de corretor e vao para a NAI.
-- =====================================================================

CREATE OR REPLACE FUNCTION nai_e_comando_publicador(p text)
RETURNS boolean LANGUAGE sql IMMUTABLE AS $$
  SELECT x ~* '^\s*(@?nay\M[\s,:;.!?-]*)?(vendeu|alugou)\M'
      OR x ~* '^\s*(@?nay\M[\s,:;.!?-]*)?(posta|postar|publica|publicar|dispara|disparar)\M'
      OR x ~* '^\s*(@?nay\M[\s,:;.!?-]*)?(tira|remove)\s+(o\s+|os\s+)?\d{3,5}'
      OR x ~* '^\s*(@?nay\M[\s,:;.!?-]*)?vagas\s*[.!?]*\s*$'
      OR x ~* '^\s*(@?nay\M[\s,:;.!?-]*)?(resposta|descartar)\s+#?\d+'
      -- envio para alguem: exige o destino depois de para/pra/pro (a mesma
      -- preposicao obrigatoria do publicador) e nao vale "pra mim"
      OR (x ~* '^\s*(@?nay\M[\s,:;.!?-]*)?(envi|m[a]?nd|repass|encaminh|mostr|solt)(a|ar|e|ei|ou|o)?\M.*\m(para|pra|pro|p/)\s*\S'
          AND x !~* '\m(para|pra|pro)\s+(mim|eu)\M')
  FROM (SELECT coalesce(p, '') AS x) t;
$$;

-- Versao com o TEXTO, usada pelo roteador. A de 2 argumentos continua igual
-- (sobrecarga de proposito: quem ainda chama a antiga nao quebra).
CREATE OR REPLACE FUNCTION nai_quem_atende(p_phone text, p_grupo boolean, p_texto text)
RETURNS text LANGUAGE plpgsql STABLE AS $$
DECLARE v_chave text := nai_chave(p_phone);
BEGIN
  IF v_chave IS NOT NULL AND v_chave = nai_chave(nai_cfg('tel_telefone'))
     AND NOT coalesce(p_grupo, true) AND nai_e_comando_publicador(p_texto) THEN
    RETURN 'nay';
  END IF;
  RETURN nai_quem_atende(p_phone, p_grupo);
EXCEPTION WHEN others THEN
  RETURN 'nay';
END;
$$;
