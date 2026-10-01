-- 240 (30/09/2026): O IMÓVEL QUE ELE DESCREVE OU MARCA MANDA NO "IMÓVEL DA CONVERSA".
-- Pedro, caso da Raquel: "a mensagem que coloquei em círculo é do Parque dos Ingleses
-- cód. 9004 ... ela pensou que era o Sausalito que foi enviado como opção para a
-- corretora, chegou a notificação falando que não sabia a taxa do Sausalito e
-- transferiu para mim."
--
-- O que aconteceu (20h50): "Qual o valor do condomínio do apartamento da Chapada" ->
-- a Nay pegou o último imóvel da conversa (5699, Sausalito: uma CASA no PARQUE 10),
-- não achou a taxa e escalou ao Tel -- e a base SABE a do 9004 (R$ 520). Um minuto
-- depois ela marcou o card do 9004 ("Esse"); a marcação foi lida, mas o chat já
-- estava pausado pela escalada e a mensagem não virou atendimento.
--
--   1. nai_imovel_da_conversa: se a frase diz o TIPO e o BAIRRO ("apartamento da
--      Chapada"), só serve imóvel que bate. Um só bate: é ele. Nenhum da conversa
--      bate: vale o único do catálogo com essa descrição; havendo mais de um, NULL
--      (ela pergunta qual) -- nunca mais o "último da conversa" de outro tipo e bairro.
--   2. nai_imovel_pela_descricao enxergava só LOCAÇÃO (e tirava o que já foi enviado
--      a ele): o 9004, de venda, não aparecia. Agora vê locação e venda.
--   3. nai_abrir_turno: chat pausado por "dúvida fora da base" + ele marca ou cita
--      OUTRO imóvel = a dúvida era de outro imóvel: a pausa cai, a Nay atende, e o Tel
--      é avisado de que pode desconsiderar.
BEGIN;
SET LOCAL lock_timeout = '3s';

CREATE OR REPLACE FUNCTION pg_temp.trocar(p_fn regprocedure, p_de text, p_para text, p_vezes int DEFAULT 1)
 RETURNS void LANGUAGE plpgsql AS $$
DECLARE d text := pg_get_functiondef(p_fn); n int := (length(d) - length(replace(d, p_de, ''))) / length(p_de);
BEGIN
  IF n <> p_vezes THEN RAISE EXCEPTION 'trocar em %: esperava % vez(es), achei % -- %', p_fn, p_vezes, n, left(p_de, 50); END IF;
  EXECUTE replace(d, p_de, p_para);
END $$;

-- 2 ------------------------------------------- a descrição vê venda também
SELECT pg_temp.trocar('nai_imovel_pela_descricao(text,text)',
$a$    SELECT i.codigo AS c, i.valor_aluguel AS v FROM imoveis i
     WHERE nay_normalizar_lugar(i.bairro, true) = nay_normalizar_lugar(v_bairro, true)
       AND i.tipo ILIKE v_tipo
       AND nai_oferta_serve(i, coalesce(p_telefone, ''), NULL, NULL, false, false)
     ORDER BY i.valor_aluguel LIMIT 9) z;$a$,
$b$    -- 240: locação E venda, e inclusive o que já foi enviado a ele (é justamente
    -- do que ele recebeu que ele costuma perguntar)
    SELECT i.codigo AS c, coalesce(nullif(i.valor_aluguel, 0), i.valor_venda) AS v FROM imoveis i
     WHERE nay_normalizar_lugar(i.bairro, true) = nay_normalizar_lugar(v_bairro, true)
       AND i.tipo ILIKE v_tipo
       AND nay_esta_no_mercado(i.disponivel, i.bloqueado, i.publicado_no_site)
       AND NOT coalesce(i.e_parceiro, false)
       AND (coalesce(i.valor_aluguel, 0) > 0 OR coalesce(i.valor_venda, 0) > 0)
     ORDER BY 2 LIMIT 9) z;$b$);

-- 1 ------------------------------------------- o que ele descreve manda
SELECT pg_temp.trocar('nai_imovel_da_conversa(bigint,text)',
$a$  IF coalesce(array_length(v_cods, 1), 0) = 0 THEN RETURN NULL; END IF;

  -- 3. ele chamou pelo NOME$a$,
$b$  -- 240: ELE DESCREVEU O IMÓVEL (tipo + bairro: "o apartamento da Chapada"). Só
  -- serve o que bate; sem isto valia o último imóvel da conversa, de outro tipo e
  -- outro bairro (Raquel, 30/09: a casa do Parque 10 no lugar do 9004).
  IF nai_tipo_pedido(p_texto) IS NOT NULL THEN
    DECLARE
      v_desc  jsonb := nai_imovel_pela_descricao(p_texto, k.telefone);
      v_bate  int[];
    BEGIN
      IF v_desc ? 'bairro' THEN
        v_bate := ARRAY(SELECT i.codigo FROM imoveis i
                         WHERE i.codigo = ANY (v_cods) AND i.tipo ILIKE nai_tipo_pedido(p_texto)
                           AND nay_normalizar_lugar(i.bairro, true) = nay_normalizar_lugar(v_desc->>'bairro', true));
        IF coalesce(array_length(v_bate, 1), 0) = 1 THEN
          RETURN v_bate[1];
        ELSIF coalesce(array_length(v_bate, 1), 0) >= 2 THEN
          v_cods := v_bate;
        ELSIF coalesce((v_desc->>'quantos')::int, 0) = 1 THEN
          RETURN (v_desc->'codigos'->>0)::int;     -- o único do catálogo com essa descrição
        ELSE
          RETURN NULL;                             -- descreveu outro imóvel: ela pergunta qual
        END IF;
      END IF;
    END;
  END IF;

  IF coalesce(array_length(v_cods, 1), 0) = 0 THEN RETURN NULL; END IF;

  -- 3. ele chamou pelo NOME$b$);

-- 3 ------------------------------------------- a marcação de outro imóvel solta a escalada
SELECT pg_temp.trocar('nai_abrir_turno(text,text,text,text,bigint[])',
$a$  IF nai_tel_com_a_conversa(v_contato)
     AND NOT (v_teste AND v_texto ~* '^\s*(t|tel)\s*[:\-–]') THEN$a$,
$b$  -- 240: A DÚVIDA ERA DE OUTRO IMÓVEL. Chat pausado por "dúvida fora da base" e ele
  -- MARCA ou CITA um imóvel diferente do que foi escalado: a pausa cai e a Nay
  -- atende (a base pode saber a resposta do imóvel certo). O Tel é avisado.
  DECLARE
    v_irmaos bigint[] := coalesce(nai_contato_irmaos(v_contato), ARRAY[v_contato]);
    v_cit    int;
    v_esc    int;
  BEGIN
    IF EXISTS (SELECT 1 FROM nai_contato c WHERE c.id = ANY (v_irmaos) AND c.humano_motivo ~ '^duvida fora da base') THEN
      v_cit := coalesce(
        nullif(regexp_replace(coalesce(nay_imovel_da_citacao(p_citado_id), ''), '\D', '', 'g'), '')::int,
        (SELECT x::int FROM unnest(coalesce(nay_codigos_citados(v_texto), '{}'::text[])) x
          WHERE x ~ '^[0-9]{3,5}$' AND EXISTS (SELECT 1 FROM imoveis i WHERE i.codigo = x::int) LIMIT 1));
      SELECT t.codigo INTO v_esc FROM nai_turno t
       WHERE t.contato_id = ANY (v_irmaos) AND 'escalar' = ANY (coalesce(t.ferramentas, '{}'))
       ORDER BY t.id DESC LIMIT 1;
      IF v_cit IS NOT NULL AND v_cit IS DISTINCT FROM v_esc THEN
        UPDATE nai_contato SET humano_assumiu_em = NULL, humano_motivo = NULL WHERE id = ANY (v_irmaos);
        BEGIN
          PERFORM nai_avisar_tel(NULL, NULL,
            'Tel, pode desconsiderar a dúvida de ' || coalesce(nullif(btrim(p_nome), ''), 'um corretor')
            || coalesce(' sobre o ' || nai_ref_imovel(v_esc), '') || ': ela falava de outro imóvel ('
            || coalesce(nai_ref_imovel(v_cit), 'código ' || v_cit) || '), marcou o card e eu voltei a atender.',
            'duvida_era_de_outro_imovel');
        EXCEPTION WHEN others THEN NULL;   -- o aviso nunca derruba o atendimento
        END;
      END IF;
    END IF;
  END;

  IF nai_tel_com_a_conversa(v_contato)
     AND NOT (v_teste AND v_texto ~* '^\s*(t|tel)\s*[:\-–]') THEN$b$);
COMMIT;
