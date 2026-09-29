-- =====================================================================
-- 130 — EQUIPE NÃO TEM JANELA (27/09/2026)
--
-- Tel: "para os numeros da equipe não deve existir janela".
--
-- A JANELA é a regra do `nai_tel_com_a_conversa`: quando alguém escreve à mão
-- numa conversa, a Nay cala 30 minutos (ou para sempre, se o motivo não for
-- "o Tel escreveu pelo celular"). Ela existe para uma coisa só: a Nay não falar
-- por cima do Tel quando ele assume a conversa de um CORRETOR.
--
-- Na conversa da própria equipe não tem terceiro para proteger -- e a regra
-- só atrapalhava. Hoje, medido:
--
--   * o Tel ficou DOIS DIAS sem resposta no número dele (carimbo de 25/09,
--     motivo "midia: 2 arquivos", que não expira);
--   * o Pedro mandou quatro mensagens às 16:25 e 16:29 e nenhuma abriu turno:
--     a linha @lid dele foi carimbada às 16:28 com "o Tel escreveu pelo
--     celular";
--   * a Rayssa tinha o mesmo carimbo desde 26/09.
--
-- O CUIDADO QUE FALTOU NA PRIMEIRA VEZ: cada pessoa tem DUAS linhas em
-- `nai_contato` (o telefone e o @lid). Hoje de manhã eu limpei só a linha do
-- telefone do Pedro, e a do @lid continuou calando ela -- porque
-- `nai_tel_com_a_conversa` olha o carimbo MAIS RECENTE entre as irmãs. Por
-- isso a isenção aqui olha todas as irmãs, e não uma linha só.
--
-- QUEM É EQUIPE: o `tel_telefone`, quem está na lista curta
-- (`so_estes_numeros`) e quem está ativo em `equipe`.
-- =====================================================================
\set ON_ERROR_STOP on

BEGIN;

-- ---------------------------------------------------------------------
-- Este contato é da equipe? Olha TODAS as linhas da pessoa.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION nai_e_da_equipe_contato(p_contato bigint)
RETURNS boolean
LANGUAGE sql
STABLE
AS $fn$
  SELECT EXISTS (
    SELECT 1
      FROM nai_contato c
     WHERE c.id = ANY (nai_contato_irmaos(p_contato))
       AND (
             c.chave = nai_chave(nai_cfg('tel_telefone'))
          OR c.chave = ANY (nai_chaves_de('so_estes_numeros'))
          OR EXISTS (SELECT 1 FROM nay_e_da_equipe(c.telefone))
       )
  );
$fn$;

-- ---------------------------------------------------------------------
-- A janela, com a isenção da equipe na frente de tudo.
-- O resto é a versão viva, sem mudança.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.nai_tel_com_a_conversa(p_contato bigint)
 RETURNS boolean
 LANGUAGE plpgsql
 STABLE
AS $function$
DECLARE
  v_em     timestamptz;
  v_motivo text;
  v_gap    int;
BEGIN
  IF p_contato IS NULL THEN RETURN false; END IF;

  -- EQUIPE NÃO TEM JANELA (Tel, 27/09/2026). Ver o cabeçalho da 130.
  IF nai_e_da_equipe_contato(p_contato) THEN RETURN false; END IF;

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
$function$;

-- E os carimbos que estão calando a equipe agora, em TODAS as linhas.
UPDATE nai_contato c
   SET humano_assumiu_em = NULL, humano_motivo = NULL
 WHERE c.humano_assumiu_em IS NOT NULL
   AND nai_e_da_equipe_contato(c.id);

COMMIT;

\echo '=== o porteiro para a equipe (tem de ser tudo true) ==='
SELECT 'Tel' AS quem, atende, motivo FROM nai_deve_atender('559294717316', 'envia 92 9450-0381 o 3050')
UNION ALL SELECT 'Pedro', atende, motivo FROM nai_deve_atender('559691712835', 'Colocar no meio selo Parceiro easy')
UNION ALL SELECT 'Pedro (@lid)', atende, motivo FROM nai_deve_atender('lid:173340601933982', 'Colocar no meio selo Parceiro easy')
UNION ALL SELECT 'Rayssa', atende, motivo FROM nai_deve_atender('559691511557', 'me manda o 1125');

\echo '=== e a janela CONTINUA valendo para corretor (prova: um corretor qualquer) ==='
SELECT count(*) AS corretores_isentos_por_engano
  FROM nai_contato c
 WHERE nai_e_da_equipe_contato(c.id)
   AND c.chave NOT IN (SELECT unnest(nai_chaves_de('so_estes_numeros')))
   AND c.chave <> nai_chave(nai_cfg('tel_telefone'))
   AND c.chave NOT LIKE 'lid:%'
   AND NOT EXISTS (SELECT 1 FROM nay_e_da_equipe(c.telefone));
