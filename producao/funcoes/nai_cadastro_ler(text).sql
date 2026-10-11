CREATE OR REPLACE FUNCTION public.nai_cadastro_ler(p_texto text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
AS $function$
DECLARE
  s text := lower(unaccent(coalesce(p_texto, '')));
  r jsonb := '{}'::jsonb;
  m text[];
BEGIN
  -- TAMANHO: "60m2", "60 m²", "60 metros"
  m := regexp_match(s, '(\d{2,4})\s*(m2|m²|mts?|metros)\M');
  IF m IS NOT NULL THEN r := r || jsonb_build_object('area', (m[1])::numeric); END IF;

  -- COMODOS: "2 quartos", "3 dormitorios"
  m := regexp_match(s, '(\d{1,2})\s*(quartos?|dormit\w*|qtos?)\M');
  IF m IS NOT NULL THEN r := r || jsonb_build_object('quartos', (m[1])::int); END IF;

  -- SUITES: "sendo 1 suite", "2 suites". "sendo uma suite" tambem.
  m := regexp_match(s, '(\d{1,2})\s*su[ií]tes?\M');
  IF m IS NOT NULL THEN
    r := r || jsonb_build_object('suites', (m[1])::int);
  ELSIF s ~ '\m(uma|1)\s+su[ií]te' THEN
    r := r || jsonb_build_object('suites', 1);
  END IF;

  -- BANHEIROS
  m := regexp_match(s, '(\d{1,2})\s*banheiros?\M');
  IF m IS NOT NULL THEN r := r || jsonb_build_object('banheiros', (m[1])::int); END IF;

  -- VAGAS
  m := regexp_match(s, '(\d{1,2})\s*vagas?\M');
  IF m IS NOT NULL THEN
    r := r || jsonb_build_object('vagas', (m[1])::int);
  ELSIF s ~ '\m(sem vaga|nao tem vaga)\M' THEN
    r := r || jsonb_build_object('vagas', 0);
  END IF;

  -- MOBILIA: a ordem importa, "semi" antes de "mobiliado"
  IF    s ~ '\m(semi\s*-?\s*mobili|modulad)'            THEN r := r || '{"mobilia":"com modulados e ar"}';
  ELSIF s ~ '\m(sem mobili|vazio|desmobili|nao mobili)' THEN r := r || '{"mobilia":"sem nada"}';
  ELSIF s ~ '\mmobiliad'                                THEN r := r || '{"mobilia":"mobiliado"}';
  ELSIF s ~ '\m(so|somente) (climatizad|ar)'            THEN r := r || '{"mobilia":"só climatizado"}';
  END IF;

  -- PRECO e FINALIDADE, das funcoes que ja existem e ja foram medidas
  IF nay_maior_valor(p_texto) IS NOT NULL THEN
    r := r || jsonb_build_object('valor', nay_maior_valor(p_texto));
  END IF;
  IF nay_negocio_pedido(p_texto) IS NOT NULL THEN
    r := r || jsonb_build_object('finalidade', nay_negocio_pedido(p_texto));
  END IF;

  -- TIPO: so o canonico, nunca a frase inteira. Foi assim que a ficha 4
  -- subiu com tipo = "apartamentos, casas e imoveis em predios".
  IF nai_tipo_canonico(p_texto) IS NOT NULL THEN
    r := r || jsonb_build_object('tipo', nai_tipo_canonico(p_texto));
  END IF;

  RETURN r;
END;
$function$;
