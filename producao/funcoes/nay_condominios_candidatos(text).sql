CREATE OR REPLACE FUNCTION public.nay_condominios_candidatos(p_nome text)
 RETURNS TABLE(nome text, faixa integer)
 LANGUAGE sql
 STABLE
AS $function$
  WITH alvo AS (
    SELECT nay_normalizar_lugar(coalesce(p_nome,''), true) AS norm,
           nay_chave_condominio(coalesce(p_nome,''))       AS chave
  ), pedido AS (
    SELECT a.norm, a.chave,
           -- Metade das palavras, arredondando para cima. Ver a faixa 2.
           ceil(coalesce(array_length(string_to_array(a.chave,' '),1),1) / 2.0) AS minimo
      FROM alvo a
  ), cands AS (
    -- TODO o cadastro: reconhecer o nome não é a mesma decisão que poder
    -- enviar o imóvel. Quem filtra anúncio no ar é o chamador.
    SELECT DISTINCT i.condominio_nome AS nome,
           nay_chave_condominio(i.condominio_nome) AS chave
      FROM imoveis i
     WHERE coalesce(i.condominio_nome,'') <> ''
  ), com_faixa AS (
    SELECT c.nome,
           CASE
             -- 0. o nome inteiro, letra por letra. "Condomínio Laranjeiras" e
             --    "Residencial Laranjeiras" são DOIS condomínios cuja chave é
             --    a mesma palavra: sem esta faixa, escolher o nome que ela
             --    ofereceu devolvia a mesma pergunta -- laço fechado.
             WHEN nay_normalizar_lugar(c.nome, true) = p.norm THEN 0
             -- 1. o nome exato do cadastro, sem as palavras genéricas
             WHEN c.chave = p.chave THEN 1
             -- 2. ele escreveu o nome inteiro e mais alguma coisa. O piso de
             --    palavras não é enfeite: sem ele o "Parque Verde" (chave de
             --    UMA palavra) engolia "Vila Verde 1".
             WHEN string_to_array(c.chave,' ') <@ string_to_array(p.chave,' ')
              AND coalesce(array_length(string_to_array(c.chave,' '),1),0) >= p.minimo THEN 2
             -- 3. ele escreveu um pedaço: "Liverpool"
             WHEN string_to_array(p.chave,' ') <@ string_to_array(c.chave,' ') THEN 3
             -- 4. FAIXA FRACA: pedaço de palavra ou parecença. Daqui não sai
             --    afirmação nenhuma -- só "você quis dizer?".
             WHEN position(p.chave in c.chave) > 0
               OR position(c.chave in p.chave) > 0
               OR word_similarity(p.chave, c.chave) >= 0.6 THEN 4
           END AS faixa
      FROM cands c CROSS JOIN pedido p
     -- Chave vazia casa com TUDO por `position('' in x) > 0`. "Apartamento" e
     -- "Casa" existem como condominio_nome e a chave deles fica vazia.
     WHERE btrim(c.chave) <> '' AND btrim(p.chave) <> ''
  ), melhor AS (
    SELECT min(f.faixa) AS faixa FROM com_faixa f WHERE f.faixa IS NOT NULL
  )
  SELECT c.nome, c.faixa
    FROM com_faixa c, melhor m
   WHERE c.faixa IS NOT NULL AND c.faixa = m.faixa;
$function$;
