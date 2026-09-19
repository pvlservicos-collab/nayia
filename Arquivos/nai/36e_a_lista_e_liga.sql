-- =====================================================================
-- NAI -- 36e: A LISTA, e a Nay de Locacao so fala com ela (Tel, 19/09/2026)
--
-- Nas palavras dele: "cria entao essa lista porque e nela que vamos liberar
-- para a nay locacao, que e a nay parceria, conversar, mandar os imoveis e
-- tudo mais."
--
-- O QUE EU ACHEI ANTES DE ESCREVER ISTO: nao existe "lista do site" separada
-- da "lista dos grupos". As 1.453 linhas de `corretores` tem `origem` com
-- nome de grupo de WhatsApp ("FECHANDO PARCERIAS 1.0", "IMOVEIS PARA
-- ANUNCIAR EASY"...) -- so 5 foram postas a mao. O numero que o site mostra
-- como "Corretores parceiros" e a leitura dos grupos, na mesma tabela.
-- Entao juntar as duas e este arquivo, nao uma importacao.
--
-- SOBRA: 10 aprovados sem `pode_falar` -- gente da exportacao de 13-14/09 que
-- nao apareceu mais na leitura de 18/09 (sairam dos grupos). Entram, porque
-- foram aprovados. O Tel tira quem quiser com NAO CORRETOR <telefone>.
-- O decimo e o proprio Tel, e ele NAO entra: a sincronizacao o exclui de
-- proposito, e `nai_lista_governa` ja o isenta da regra inteira.
-- =====================================================================

\set ON_ERROR_STOP on

BEGIN;

-- ---------------------------------------------------------------------
-- 1. QUEM NAO ESTA MAIS NUM GRUPO PRECISA DE FONTE PROPRIA
--
-- A sincronizacao de segunda derruba `pode_falar` de quem tem fonte='grupo'
-- e nao apareceu na leitura. Sem esta troca, os 9 voltariam a ser calados na
-- proxima segunda e ninguem veria.
-- ---------------------------------------------------------------------
UPDATE corretores
   SET fonte = 'site'
 WHERE aprovado AND ativo AND no_grupo_em IS NULL
   AND nai_chave(telefone) IS DISTINCT FROM nai_chave(nai_cfg('tel_telefone'));

-- ---------------------------------------------------------------------
-- 2. A LISTA -- todo corretor aprovado e ativo pode falar
--
-- Menos quem o Tel calou a mao com NAO CORRETOR: a decisao dele vale mais
-- que a lista, e um UPDATE em massa nao pode religar quem ele desligou.
-- ---------------------------------------------------------------------
UPDATE corretores c
   SET pode_falar = true
 WHERE c.aprovado AND c.ativo AND NOT c.pode_falar
   AND nai_chave(c.telefone) IS DISTINCT FROM nai_chave(nai_cfg('tel_telefone'))
   AND NOT EXISTS (SELECT 1 FROM nai_corretor_pergunta q
                    WHERE q.chave = nai_chave(c.telefone) AND q.decisao = 'nao');

-- ---------------------------------------------------------------------
-- 3. NINGUEM DA LISTA PODE CAIR NA SEGUNDA SEM QUERER
-- ---------------------------------------------------------------------
DO $$
DECLARE v_risco int;
BEGIN
  SELECT count(*) INTO v_risco
    FROM corretores
   WHERE pode_falar AND fonte = 'grupo' AND no_grupo_em IS NULL;
  IF v_risco > 0 THEN
    RAISE EXCEPTION 'ABORTADO: % corretores perderiam a permissao na sincronizacao de segunda', v_risco;
  END IF;
END $$;

-- ---------------------------------------------------------------------
-- 4. LIGA
-- ---------------------------------------------------------------------
INSERT INTO nai_config (chave, valor, descricao, atualizado_em)
VALUES ('so_corretor_da_lista', 'sim',
        'sim = a NAI so atende corretor da lista (corretores.pode_falar). Fora da lista, se perguntar de imovel, ela pergunta ao Tel.',
        now())
ON CONFLICT (chave) DO UPDATE SET valor = 'sim', descricao = EXCLUDED.descricao, atualizado_em = now();

COMMIT;

SELECT count(*) FILTER (WHERE pode_falar AND ativo)               AS podem_falar,
       count(*) FILTER (WHERE aprovado AND ativo AND NOT pode_falar) AS aprovados_de_fora,
       count(*) FILTER (WHERE NOT aprovado)                       AS aguardando
  FROM corretores;
