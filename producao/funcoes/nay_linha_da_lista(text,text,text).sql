CREATE OR REPLACE FUNCTION public.nay_linha_da_lista(p_codigo text, p_categoria text, p_negocio text DEFAULT 'locacao'::text)
 RETURNS text
 LANGUAGE plpgsql
 STABLE
AS $function$
DECLARE
  i record;
  partes text[] := '{}';
  quartos text;
  mob text;
  valor numeric;
  cauda text;
BEGIN
  SELECT * INTO i FROM imoveis WHERE codigo::text = p_codigo;
  IF i IS NULL THEN RETURN NULL; END IF;

  -- 1. o nome: o condomínio, ou tipo + bairro para o de rua -- e o CÓDIGO
  --    colado nele, que é onde o Tel pôs no exemplo de 28/09.
  partes := array_append(partes,
    coalesce(nay_condominio_de_verdade(i.tipo, i.condominio_nome),
             btrim(coalesce(i.tipo,'imóvel') || ' ' || coalesce(i.bairro,'')))
    || ' cod ' || i.codigo::text);

  -- 2. SALA mostra a metragem; o resto mostra quartos. Decisão do Tel.
  IF p_categoria = 'sala' THEN
    IF coalesce(i.area_util,0) > 0 THEN
      partes := array_append(partes, to_char(i.area_util,'FM999990') || 'm2');
    END IF;
  ELSE
    IF coalesce(i.quartos,0) > 0 THEN
      quartos := i.quartos || CASE WHEN i.quartos = 1 THEN ' quarto' ELSE ' quartos' END;
      IF coalesce(i.suites,0) > 0 THEN
        -- "3 suítes" quando TODOS os quartos são suíte -- é como ele escreve
        -- ("Morada dos pássarros / 3 suítes").
        IF i.suites >= i.quartos THEN
          quartos := i.suites || CASE WHEN i.suites = 1 THEN ' suíte' ELSE ' suítes' END;
        ELSE
          quartos := quartos || ' sendo ' || i.suites
                     || CASE WHEN i.suites = 1 THEN ' suíte' ELSE ' suítes' END;
        END IF;
      END IF;
      partes := array_append(partes, quartos);
    END IF;
  END IF;

  -- 3. mobília, quando se sabe.
  -- 12/10: a redação vem de nay_mobilia_rotulo, o mesmo lugar do card.
  -- Os padrões antigos ('semi%', 'ar[- ]condicionado') não casavam com NENHUM
  -- dos quatro valores novos, e 738 imóveis mandavam a linha sem a mobília.
  mob := nay_mobilia_rotulo(nay_mobilia_nivel(i.mobilia));
  IF mob IS NOT NULL THEN partes := array_append(partes, mob); END IF;

  -- 4. o valor, e o que acontece com a taxa.
  valor := CASE WHEN p_negocio = 'venda' THEN i.valor_venda ELSE i.valor_aluguel END;
  partes := array_append(partes, nay_valor_curto(valor));

  IF p_negocio <> 'venda' THEN
    IF coalesce(i.extras->>'incluso no aluguel','') ILIKE '%condom%' THEN
      cauda := '(incluso a tx)';
    ELSIF coalesce(i.taxa_condominio,0) > 0 THEN
      cauda := '+ tx de ' || replace(replace(replace(
                 to_char(i.taxa_condominio,'FM999,999,990.00'), '.', '@'),
                 ',', '.'), '@', ',');
    END IF;
  END IF;

  RETURN array_to_string(partes, ' / ')
         || coalesce(CASE WHEN cauda LIKE '(%' THEN ' ' || cauda
                          ELSE ' / ' || cauda END, '');
END;
$function$;
