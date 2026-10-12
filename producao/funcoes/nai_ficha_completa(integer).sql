CREATE OR REPLACE FUNCTION public.nai_ficha_completa(p_codigo integer)
 RETURNS text
 LANGUAGE plpgsql
 STABLE
AS $function$
DECLARE
  i imoveis;
  f imovel_ficha;
  v text[] := '{}';
  x text;
  fmt text := 'FM999G999G990';
BEGIN
  SELECT * INTO i FROM imoveis WHERE codigo = p_codigo;
  IF i.codigo IS NULL OR coalesce(i.e_parceiro, false) THEN RETURN NULL; END IF;
  SELECT * INTO f FROM imovel_ficha WHERE codigo = p_codigo AND encontrado;

  v := v || ('FICHA DO IMÓVEL ' || i.codigo || ' — ' || concat_ws(' · ', nullif(nai_condominio_ok(i.condominio_nome), ''),
             i.tipo, i.bairro));
  v := v || ('SITUAÇÃO: ' || CASE WHEN nay_esta_no_mercado(i.disponivel, i.bloqueado, i.publicado_no_site)
                                  THEN 'disponível' ELSE 'NÃO está disponível' END);
  v := v || ('VALORES: ' || concat_ws(' | ',
             CASE WHEN coalesce(i.valor_venda, 0) > 0 THEN 'venda R$ ' || replace(to_char(i.valor_venda, fmt), ',', '.') END,
             CASE WHEN coalesce(i.valor_aluguel, 0) > 0 THEN 'aluguel R$ ' || replace(to_char(i.valor_aluguel, fmt), ',', '.') END));
  v := v || ('PAGAMENTO: ' || concat_ws(' | ',
             'aceita financiamento: ' || coalesce(nai_ficha_valor(p_codigo, 'aceita financiamento'), 'NÃO INFORMADO'),
             'aceita permuta: ' || coalesce(nai_ficha_valor(p_codigo, 'aceita permuta'), 'NÃO INFORMADO')
               || coalesce(' (' || nai_ficha_valor(p_codigo, 'permuta') || ')', ''),
             CASE WHEN coalesce(nai_ficha_texto_livre(p_codigo), '') ~* 'fgts' THEN 'FGTS: o anúncio cita (ver descrição)'
                  ELSE 'FGTS: NÃO INFORMADO' END));
  v := v || ('TAXAS: ' || concat_ws(' | ',
             'condomínio: ' || coalesce(CASE WHEN coalesce(i.taxa_condominio, 0) > 0
                                             THEN 'R$ ' || replace(to_char(i.taxa_condominio, fmt), ',', '.') END,
                                        nai_ficha_valor(p_codigo, 'taxa de condominio'), 'não informado'),
             'IPTU: ' || coalesce(CASE WHEN coalesce(i.iptu, 0) > 0 THEN 'R$ ' || replace(to_char(i.iptu, fmt), ',', '.') END,
                                  nai_ficha_valor(p_codigo, 'iptu'), 'não informado'),
             'incluso no aluguel: ' || coalesce(nai_ficha_valor(p_codigo, 'incluso no aluguel'), 'não informado'),
             'garantia do aluguel: ' || coalesce(nai_ficha_valor(p_codigo, 'garantia de aluguel'), 'não informado')));
  v := v || ('O IMÓVEL: ' || concat_ws(' | ',
             CASE WHEN coalesce(i.area_util, 0) > 0 THEN trim(to_char(i.area_util, 'FM999990')) || ' m²' END,
             'área (anúncio): ' || nai_ficha_valor(p_codigo, 'area'),
             'área construída: ' || nai_ficha_valor(p_codigo, 'area construida'),
             'terreno: ' || nai_ficha_valor(p_codigo, 'tamanho do terreno'),
             CASE WHEN coalesce(i.quartos, 0) > 0 THEN i.quartos || ' quartos' || CASE WHEN coalesce(i.suites, 0) > 0 THEN ' (' || i.suites || CASE WHEN i.suites = 1 THEN ' suíte)' ELSE ' suítes)' END ELSE '' END END,
             CASE WHEN coalesce(i.banheiros, 0) > 0 THEN i.banheiros || ' banheiros' END,
             CASE WHEN coalesce(i.vagas, 0) > 0 OR coalesce(i.vagas_cobertas, 0) > 0
                  THEN 'vagas: ' || coalesce(i.vagas::text, '?') || coalesce(' (' || i.vagas_cobertas || ' cobertas)', '') END,
             'sol: ' || coalesce(nullif(i.sol, ''), nai_ficha_valor(p_codigo, 'sol')),
             CASE WHEN coalesce(i.andar, '') <> '' THEN 'andar ' || i.andar END,
             'lances de escada: ' || nai_ficha_valor(p_codigo, 'lances de escada'),
             'mobília: ' || nay_mobilia_rotulo(nay_mobilia_nivel(i.mobilia))));
  IF coalesce(array_length(f.caracteristicas_imovel, 1), 0) > 0 OR coalesce(array_length(i.caracteristicas, 1), 0) > 0 THEN
    v := v || ('CARACTERÍSTICAS DO IMÓVEL: ' || array_to_string(
               ARRAY(SELECT DISTINCT c FROM unnest(coalesce(f.caracteristicas_imovel, '{}') || coalesce(i.caracteristicas, '{}')) c), ', '));
  END IF;
  IF coalesce(array_length(f.caracteristicas_condominio, 1), 0) > 0 THEN
    v := v || ('CARACTERÍSTICAS DO CONDOMÍNIO: ' || array_to_string(f.caracteristicas_condominio, ', '));
  END IF;
  x := nai_ficha_texto_livre(p_codigo);
  IF x IS NOT NULL THEN v := v || ('DESCRIÇÃO E OBSERVAÇÕES DO ANÚNCIO: ' || left(x, 2500)); END IF;
  SELECT string_agg('- ' || k.assunto || ': ' || k.texto, E'\n' ORDER BY k.atualizado_em DESC) INTO x
    FROM imovel_conhecimento k WHERE k.codigo = p_codigo::text;
  IF x IS NOT NULL THEN v := v || (E'O QUE O TEL JÁ RESPONDEU SOBRE ESTE IMÓVEL:\n' || x); END IF;
  v := v || ('ATUALIZADA EM: ' || coalesce(to_char(f.lido_em AT TIME ZONE 'America/Manaus', 'DD/MM HH24:MI'), 'sem leitura do anúncio'));
  RETURN array_to_string(v, E'\n');
END;
$function$;
