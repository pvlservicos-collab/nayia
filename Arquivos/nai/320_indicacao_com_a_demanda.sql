-- 320 -- A pergunta da indicação com a demanda do fim de ano, e "alugar ou vender" conforme o imóvel dele
--
-- Pedro, 08/10/2026: "a requisição de pergunta ... poderia ser assim: Sra. (nome) estamos com uma demanda alta de
-- clientes querendo imóveis para locação nesse final de ano, a Sra. teria alguém para indicar que queira alugar ou
-- vender?" e "pode colocar vendendo ou alugando para indicar na mensagem que criou, a depender do tipo do imóvel do
-- cara".
--
-- A frase passa a ser montada pelo banco, com o tratamento e o primeiro nome do proprietário:
--   imóvel de LOCAÇÃO (o comum):  "... clientes querendo imóveis para locação ... que queira alugar ou vender?"
--   imóvel de VENDA (o cadastro só tem valor de venda, ou ele disse que quer vender):
--                                 "... clientes querendo comprar imóveis ... que queira vender ou alugar?"
-- `captacao_indicacao_pendente` devolve essa mesma frase (antes devolvia um texto fixo), e o serviço em Python a
-- entrega ao modelo no começo do turno, para a pergunta sair com estas palavras.
BEGIN;

CREATE OR REPLACE FUNCTION public.captacao_indicacao_frase(p_telefone text)
 RETURNS text
 LANGUAGE sql
 STABLE
AS $function$
  WITH l AS (
    SELECT c.tratamento, nay_primeiro_nome(c.nome) AS n, c.codigo, coalesce(c.quer_vender, false) AS quer_vender
      FROM captacao_leads c WHERE c.telefone_chave = nay_fone_chave(p_telefone) LIMIT 1
  ), d AS (
    SELECT l.tratamento,
           -- nome todo em maiúscula ou minúscula vira "Maria"; o que já veio certo fica como está
           CASE WHEN l.n = upper(l.n) OR l.n = lower(l.n) THEN initcap(l.n) ELSE l.n END AS nome,
           (l.quer_vender OR EXISTS (SELECT 1 FROM imoveis i WHERE i.codigo::text = l.codigo
                                        AND coalesce(i.valor_venda, 0) > 0 AND coalesce(i.valor_aluguel, 0) = 0)) AS de_venda
      FROM l
  )
  SELECT coalesce((
    SELECT CASE WHEN d.tratamento IN ('Sr.', 'Sra.') THEN d.tratamento || coalesce(' ' || d.nome, '') || ', estamos'
                WHEN d.nome IS NOT NULL THEN d.nome || ', estamos'
                ELSE 'Estamos' END
           || ' com uma demanda alta de clientes querendo '
           || CASE WHEN d.de_venda THEN 'comprar imóveis' ELSE 'imóveis para locação' END
           || ' nesse final de ano, '
           || CASE d.tratamento WHEN 'Sra.' THEN 'a Sra.' WHEN 'Sr.' THEN 'o Sr.' ELSE 'você' END
           || ' teria alguém para indicar que queira '
           || CASE WHEN d.de_venda THEN 'vender ou alugar?' ELSE 'alugar ou vender?' END
      FROM d),
    'Estamos com uma demanda alta de clientes querendo imóveis para locação nesse final de ano, você teria alguém '
    || 'para indicar que queira alugar ou vender?');
$function$;

DO $mig$
DECLARE
  v_def   text := pg_get_functiondef('public.captacao_indicacao_pendente(text)'::regprocedure);
  v_velho text := $v$ELSE 'Para finalizar: conhece alguém que esteja vendendo um imóvel e que possa nos indicar?' END;$v$;
  v_novo  text := $n$ELSE captacao_indicacao_frase(p_telefone) END;   -- 320: a frase do Pedro, com o nome e o tipo do imóvel$n$;
BEGIN
  IF (length(v_def) - length(replace(v_def, v_velho, ''))) / length(v_velho) <> 1 THEN
    RAISE EXCEPTION '320: o trecho de captacao_indicacao_pendente mudou no banco; leia a função viva antes';
  END IF;
  EXECUTE replace(v_def, v_velho, v_novo);
END
$mig$;

COMMIT;
