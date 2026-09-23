-- =====================================================================
-- NAI -- 91: ela fala menos "Sr." e "Sra." (Tel, 22/09/2026)
--
-- Ele: "poe para ela falar um pouco menos sra e sr".
--
-- O tratamento continua -- e o jeito dela, e o Tel pediu isso em 13/09 --,
-- mas em dose. A regra passa a dizer ONDE usar (no cumprimento e de vez em
-- quando) e os exemplos do prompt param de repetir em toda frase: era deles
-- que vinha o eco, porque o modelo copia o exemplo.
--
--   antes: "Bom dia, Sr. Carlos! Deixa eu ver aqui pro Sr."
--   agora: "Bom dia, Sr. Carlos! Deixa eu ver aqui."
--
--   antes: "Certo, Sr. Pedro! O que o Sr. quer saber desse imovel?"
--   agora: "Certo, Sr. Pedro! O que quer saber desse imovel?"
--
--   antes: "O aluguel do 5611 e R$ 2.600, Sr. Carlos."
--   agora: "O aluguel do 5611 e R$ 2.600."
--
-- As mensagens que o SISTEMA manda (confirmacao de visita, sugestao) seguem
-- com o tratamento uma vez cada: sao avulsas, nao conversa.
-- =====================================================================

\set ON_ERROR_STOP on

BEGIN;

DO $$
DECLARE
  v_texto text; v_novo text; v_versao int; n int := 0;
  trocas text[][] := ARRAY[
    ['"Bom dia, Sr. Carlos! Deixa eu ver aqui pro Sr."',
     '"Bom dia, Sr. Carlos! Deixa eu ver aqui."'],
    ['- Chame pelo tratamento que vem na informação de sistema ("Sr. Carlos", "Sra. Marcia"). Fale de si no feminino: "obrigada", "já te mando".',
     '- Chame pelo tratamento que vem na informação de sistema ("Sr. Carlos", "Sra. Marcia") no cumprimento e de vez em quando; no meio da conversa siga sem repetir a cada frase. Fale de si no feminino: "obrigada", "já te mando".'],
    ['"Certo, Sr. Pedro! O que o Sr. quer saber desse imóvel?"',
     '"Certo, Sr. Pedro! O que quer saber desse imóvel?"'],
    ['"Pode publicar sim, Sr. Carlos! O Sr. já está no nosso grupo, o Imóveis para Anunciar Easy?"',
     '"Pode publicar sim! O Sr. já está no nosso grupo, o Imóveis para Anunciar Easy?"'],
    ['"O aluguel do 5611 é R$ 2.600, Sr. Carlos."',
     '"O aluguel do 5611 é R$ 2.600."']
  ];
  i int;
BEGIN
  SELECT texto INTO v_texto FROM nai_prompt WHERE papel = 'corretor';
  v_novo := v_texto;
  FOR i IN 1 .. array_length(trocas, 1) LOOP
    IF position(trocas[i][1] IN v_novo) > 0 THEN
      v_novo := replace(v_novo, trocas[i][1], trocas[i][2]);
      n := n + 1;
    END IF;
  END LOOP;

  IF n = 0 THEN RAISE NOTICE 'nada a trocar (ja aplicado?)'; RETURN; END IF;

  SELECT coalesce(max(versao), 0) + 1 INTO v_versao FROM nai_prompt_historico WHERE papel = 'corretor';
  PERFORM nai_salvar_prompt('corretor', v_novo, v_versao, 'menos Sr./Sra. na conversa (Tel, 22/09)');
  RAISE NOTICE '% trocas | prompt: % -> % chars (versao %)', n, length(v_texto), length(v_novo), v_versao;
END $$;

COMMIT;

SELECT (length(texto) - length(replace(texto, 'Sr.', ''))) / 3 AS quantas_vezes_diz_sr,
       length(texto) AS chars
  FROM nai_prompt WHERE papel = 'corretor';
