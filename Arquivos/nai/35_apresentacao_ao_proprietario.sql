-- =====================================================================
-- NAI -- 35: a Nay se apresenta ao proprietário (Tel, 15/09/2026)
--
-- Ele: "como ja estamos falando com proprietarios em outros numeros, quando
-- essa nay locacao for falar, seria bom ela colocar antes uma apresentacao
-- 'Olá! Este é o número que usamos somente para agendamentos de visitas ...' e
-- ai segue a mensagem normal para proprietario".
--
-- O problema real: o proprietario ja conversa com a Imob Easy em OUTRO numero.
-- Quando a Nay de locacao escreve, chega de um numero desconhecido pedindo para
-- entrar no imovel dele -- e sem explicacao isso parece golpe.
--
-- SO NA PRIMEIRA VEZ com cada proprietario. Da segunda visita em diante ele ja
-- sabe de onde vem o numero, e repetir a apresentacao a cada visita viraria
-- ruido. "Primeira vez" e medida: nunca saiu mensagem de proprietario para
-- aquele contato.
--
-- O TEXTO mora em `nai_config`, entao mudar a frase e um UPDATE ou uma edicao
-- no painel -- sem deploy, sem mexer em funcao.
-- =====================================================================

INSERT INTO nai_config (chave, valor, descricao) VALUES
  ('apresentacao_proprietario',
   'Olá! Este é o número que usamos somente para agendamentos de visitas.',
   'Frase que vai ANTES da primeira mensagem a cada proprietario. Vazio = nao manda nada.')
ON CONFLICT (chave) DO NOTHING;

-- A apresentacao, ou vazio quando ela nao cabe.
CREATE OR REPLACE FUNCTION nai_apresentacao_prop(p_contato bigint)
RETURNS text LANGUAGE sql STABLE AS $$
  SELECT CASE
    WHEN nullif(btrim(coalesce(nai_cfg('apresentacao_proprietario', ''), '')), '') IS NULL
      THEN ''
    -- ja falamos com ele antes por aqui: nao se apresenta de novo
    WHEN EXISTS (SELECT 1 FROM nai_saida s
                  WHERE s.contato_id = p_contato
                    AND s.papel_destino = 'proprietario'
                    AND s.estado IN ('enviado', 'enviando', 'simulado'))
      THEN ''
    ELSE btrim(nai_cfg('apresentacao_proprietario', '')) || E'\n\n'
  END;
$$;

COMMENT ON FUNCTION nai_apresentacao_prop(bigint) IS
  'A frase de apresentacao, so na PRIMEIRA mensagem a cada proprietario. Tel, 15/09.';
