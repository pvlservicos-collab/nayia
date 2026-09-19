-- =====================================================================
-- NAI -- 36d: proprietario NUNCA entra na regra dos corretores (18/09/2026)
--
-- Medido antes de ligar a regra: das 105 pessoas que escreveram para a NAI
-- em 7 dias, 51 estavam fora dos grupos -- e lendo o que elas escreveram
-- ("o imovel ja foi vendido", "Bloco 13 apto 203, sao dois lances de
-- escada", "quarto andar torre 2", "valor mensal do IPTU"), a maioria e DONO
-- DE IMOVEL combinando visita, nao corretor de fora.
--
-- Chegam como papel 'corretor' porque o `nai_abrir_turno` so da papel de
-- proprietario a quem tem visita ABERTA naquele instante. A excecao da 36
-- herdou essa mesma cegueira. Aqui ela passa a olhar o que o sistema SABE:
-- cadastro de proprietarios, a lista da captacao, e visita em qualquer
-- estado. Com isso, 22 dos 51 saem da regra.
-- =====================================================================
\set ON_ERROR_STOP on
BEGIN;

CREATE OR REPLACE FUNCTION nai_lista_governa(p_chave text, p_contato bigint)
RETURNS boolean LANGUAGE sql STABLE AS $$
  SELECT NOT (
       p_chave = nai_chave(nai_cfg('tel_telefone'))
    OR nai_pode_comandar(p_chave)
    OR nai_e_motoboy(p_chave)
    OR EXISTS (SELECT 1 FROM equipe e WHERE nai_chave(e.telefone) = p_chave)
    -- DONO DE IMOVEL, por qualquer caminho que o sistema conheca (36d):
    OR EXISTS (SELECT 1 FROM proprietarios p WHERE nai_chave(p.telefone) = p_chave)
    OR EXISTS (SELECT 1 FROM captacao_leads l WHERE l.telefone_chave = p_chave)
    OR (p_contato IS NOT NULL AND EXISTS (
          SELECT 1 FROM nai_visita x WHERE x.proprietario_id = p_contato))
    -- quem ela ja tratou como proprietario, motoboy ou Tel nao e corretor
    OR (p_contato IS NOT NULL AND EXISTS (
          SELECT 1 FROM nai_saida s
           WHERE s.contato_id = p_contato
             AND s.papel_destino IN ('proprietario', 'motoboy', 'tel')))
  );
$$;

COMMIT;
