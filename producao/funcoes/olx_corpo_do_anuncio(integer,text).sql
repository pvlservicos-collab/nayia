CREATE OR REPLACE FUNCTION public.olx_corpo_do_anuncio(p_codigo integer, p_negocio text)
 RETURNS text
 LANGUAGE plpgsql
 STABLE
AS $function$
DECLARE
  i      imoveis;
  l      text[] := '{}';   -- as linhas, na ordem do modelo
  v_cond text;
  v_area numeric;
  v_mob  text;
  v_vaga int;
  v_fone text;
BEGIN
  SELECT * INTO i FROM imoveis WHERE codigo = p_codigo;
  IF i.codigo IS NULL THEN RETURN NULL; END IF;

  -- 📍 o condomínio, só quando o campo guarda um NOME e não o rótulo do tipo
  -- ("Casa", "Loja/Ponto", "Condomínio não identificado") -- quem separa isso
  -- é nay_condominio_de_verdade, a mesma que a linha da lista usa
  v_cond := nay_condominio_de_verdade(i.tipo, i.condominio_nome);
  IF v_cond IS NOT NULL THEN l := l || ('📍 ' || v_cond); END IF;

  IF nullif(btrim(coalesce(i.bairro, '')), '') IS NOT NULL THEN
    l := l || ('Bairro: ' || btrim(i.bairro));
  END IF;

  -- a metragem: útil para quem mora, total para terreno (igual ao resto do anúncio)
  v_area := CASE WHEN lower(nay_sem_acento(coalesce(i.tipo,''))) ~ '^(lote|terreno|sitio|chacara|fazenda)'
                 THEN coalesce(nullif(i.area_total, 0), nullif(i.area_util, 0))
                 ELSE coalesce(nullif(i.area_util, 0), nullif(i.area_total, 0)) END;
  IF coalesce(v_area, 0) >= 1 THEN l := l || (round(v_area)::bigint || 'm2'); END IF;

  IF coalesce(i.quartos, 0) > 0 THEN
    l := l || (i.quartos || CASE WHEN i.quartos = 1 THEN ' quarto' ELSE ' quartos' END
               || CASE WHEN coalesce(i.suites, 0) > 0
                       THEN ' sendo ' || i.suites || CASE WHEN i.suites = 1 THEN ' suíte' ELSE ' suítes' END
                       ELSE '' END);
  END IF;

  IF coalesce(i.banheiros, 0) > 0 THEN
    l := l || (i.banheiros || CASE WHEN i.banheiros = 1 THEN ' banheiro' ELSE ' banheiros' END);
  END IF;

  -- "1 vaga coberta" quando se sabe que é coberta; senão, só "1 vaga"
  v_vaga := greatest(coalesce(i.vagas, 0), coalesce(i.vagas_cobertas, 0));
  IF v_vaga > 0 THEN
    l := l || (v_vaga || CASE WHEN v_vaga = 1 THEN ' vaga' ELSE ' vagas' END
               || CASE WHEN coalesce(i.vagas_cobertas, 0) >= v_vaga
                       THEN CASE WHEN v_vaga = 1 THEN ' coberta' ELSE ' cobertas' END ELSE '' END);
  END IF;

  IF nullif(btrim(coalesce(i.sol, '')), '') IS NOT NULL THEN
    l := l || lower(btrim(i.sol));
  END IF;

  -- as 4 categorias (nay_mobilia_rotulo é o dono da redação; ver o cabeçalho)
  v_mob := nay_mobilia_rotulo(nay_mobilia_nivel(i.mobilia));
  IF v_mob IS NOT NULL THEN l := l || v_mob; END IF;

  IF coalesce(i.taxa_condominio, 0) > 0 THEN
    l := l || ('taxa de condomínio ' || olx_reais(i.taxa_condominio, true));
  END IF;

  l := l || (CASE WHEN p_negocio = 'venda' THEN 'Venda: R$ ' || olx_reais(i.valor_venda)
                  ELSE 'Aluguel: R$ ' || olx_reais(i.valor_aluguel) END);
  l := l || ('Código: ' || p_codigo);

  -- O OBS: a observação do imóvel, quando tem. É o campo que ele pediu na aba
  -- Características ("imóvel aceita pet", "falta só TV", "vista para o rio").
  -- Quebra de linha vira " / ": o anúncio é uma linha por assunto.
  IF nullif(btrim(coalesce(i.observacao, '')), '') IS NOT NULL THEN
    l := l || ('OBS: ' || btrim(regexp_replace(btrim(i.observacao), '\s*\n+\s*', ' / ', 'g')));
  END IF;

  v_fone := olx_fone_bonito(olx_cfg('telefone'));
  RETURN left(array_to_string(l, E'\n'), 5600)
         || coalesce(E'\n\nInformações e contatos: ' || v_fone || ' Wpp', '');
END;
$function$;
