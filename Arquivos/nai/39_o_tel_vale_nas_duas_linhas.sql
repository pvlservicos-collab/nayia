-- =====================================================================
-- NAI -- 39: o carimbo do Tel vale nas DUAS linhas da pessoa (19/09/2026)
--
-- O BUG, como o Tel viu: "ela mandou imoveis para uma pessoa que o Tel estava
-- conversando ... e ainda tem a regra das 16hrs que eu pedi, ela nao te
-- obedece?"
--
-- Ela obedecia. O que falhou foi a LEITURA: a mesma pessoa tem DUAS linhas em
-- `nai_contato`.
--
--   * o Tel digita no celular -> o webhook entrega com `phone` = o @lid do
--     chat -> `nai_tel_assumiu` carimba a linha do LID;
--   * o corretor escreve      -> chega com o telefone real -> o turno abre na
--     linha do TELEFONE, que nao tem carimbo nenhum.
--
-- `nai_tel_com_a_conversa` lia UMA linha, pelo id, e via NULL. Medido em
-- 19/09: 50 pares LID+telefone, e em 38 deles o carimbo esta SO no lado do
-- LID. Nenhum ao contrario. Ou seja: em 38 conversas que o Tel assumiu, a Nay
-- nao tinha como saber.
--
-- Caso de origem: Solange Bernardino -- contato 4908 (`lid:98045530251303`)
-- carimbado 18/09 11:47 "o Tel escreveu pelo celular", e a conversa rodando no
-- contato 4906 (`559284093869`) com 15 turnos e nenhum carimbo.
--
-- O CONSERTO E NA LEITURA, nao na escrita: carimbar as duas linhas na hora
-- consertaria dali para a frente e deixaria as 38 de tras quebradas. Juntar na
-- leitura conserta as 38 tambem, e continua funcionando se um dia a pessoa
-- ganhar uma terceira linha.
-- =====================================================================

\set ON_ERROR_STOP on

BEGIN;

-- ---------------------------------------------------------------------
-- AS LINHAS DA MESMA PESSOA
--
-- Do id para o telefone (resolvendo o LID pelo `identidade_lid`, que a
-- sincronizacao dos grupos enche), e do telefone de volta para todos os LIDs
-- conhecidos dele. Mesma resolucao que `nai_pode_falar` ja faz -- ela nunca
-- teve esse bug justamente porque junta os dois lados.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION nai_contato_irmaos(p_contato bigint)
RETURNS bigint[] LANGUAGE sql STABLE AS $$
  WITH eu AS (
    SELECT id, chave FROM nai_contato WHERE id = p_contato
  ), fone AS (
    SELECT coalesce(
      (SELECT nai_chave(i.telefone)
         FROM identidade_lid i, eu
        WHERE eu.chave LIKE 'lid:%'
          AND i.lid = regexp_replace(eu.chave, '^lid:', '')
        LIMIT 1),
      (SELECT chave FROM eu)) AS chave
  )
  SELECT coalesce(array_agg(DISTINCT c.id), ARRAY[p_contato])
    FROM nai_contato c
   WHERE c.id = p_contato
      OR c.chave = (SELECT chave FROM fone)
      OR c.chave IN (SELECT 'lid:' || i.lid
                       FROM identidade_lid i, fone
                      WHERE nai_chave(i.telefone) = fone.chave);
$$;

COMMENT ON FUNCTION nai_contato_irmaos(bigint) IS
  'Os ids de nai_contato da MESMA pessoa: a linha do telefone e a(s) do @lid. Existe porque o Tel digitando chega por LID e o corretor chega por telefone.';

-- ---------------------------------------------------------------------
-- A LEITURA, agora nas duas linhas
--
-- O resto da regra nao muda: o gap so vale para a mensagem digitada por ele;
-- escalada segue com o Tel ate DEVOLVER; motivo que eu nao conheca continua
-- caindo no ELSE e ficando parado. Errar para o lado de ficar calada e
-- barato; errar para o outro e a Nay falando por cima do Tel -- que e
-- exatamente o que aconteceu.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION nai_tel_com_a_conversa(p_contato bigint)
RETURNS boolean LANGUAGE plpgsql STABLE AS $$
DECLARE
  v_em     timestamptz;
  v_motivo text;
  v_gap    int;
BEGIN
  IF p_contato IS NULL THEN RETURN false; END IF;

  -- A linha carimbada MAIS RECENTE entre as da mesma pessoa.
  SELECT c.humano_assumiu_em, c.humano_motivo
    INTO v_em, v_motivo
    FROM nai_contato c
   WHERE c.id = ANY (nai_contato_irmaos(p_contato))
     AND c.humano_assumiu_em IS NOT NULL
   ORDER BY c.humano_assumiu_em DESC
   LIMIT 1;

  IF v_em IS NULL THEN RETURN false; END IF;

  IF v_motivo = 'o Tel escreveu pelo celular' THEN
    v_gap := greatest(nai_cfg_int('gap_tel_min', 30), 0);
    RETURN v_em > now() - make_interval(mins => v_gap);
  END IF;

  RETURN true;
END;
$$;

COMMIT;

-- Prova: as conversas que a Nay passou a enxergar como "com o Tel".
SELECT count(*) AS pares_lid_e_fone,
       count(*) FILTER (WHERE l.humano_assumiu_em IS NOT NULL
                          AND p.humano_assumiu_em IS NULL) AS carimbo_so_no_lid
  FROM nai_contato l
  JOIN identidade_lid i ON i.lid = regexp_replace(l.chave, '^lid:', '')
  JOIN nai_contato p ON p.chave = nai_chave(i.telefone)
 WHERE l.chave LIKE 'lid:%';
