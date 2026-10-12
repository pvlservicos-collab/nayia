CREATE OR REPLACE FUNCTION public.condominio_aplicar_google(p_id integer DEFAULT NULL::integer)
 RETURNS TABLE(fichas integer, campos integer)
 LANGUAGE plpgsql
AS $function$
DECLARE
  TEXTOS text[] := ARRAY['logradouro', 'numero', 'cidade', 'estado', 'cep',
                         'torres', 'andares', 'aptos_por_andar', 'unidades',
                         'construtora', 'ano_construcao'];
  f       record;
  k       text;
  s       text;
  n       int := 0;
  nf      int := 0;
  mexeu   boolean;
  v_atual text[];
  v_junta text[];
BEGIN
  FOR f IN SELECT * FROM condominio_ficha
            WHERE ia_sugestao IS NOT NULL AND (p_id IS NULL OR condominio_id = p_id)
            ORDER BY id
  LOOP
    mexeu := false;

    FOREACH k IN ARRAY TEXTOS LOOP
      CONTINUE WHEN coalesce(btrim(to_jsonb(f) ->> k), '') <> '';      -- já tem: não toca
      s := left(btrim(coalesce(f.ia_sugestao ->> k, '')), 200);
      CONTINUE WHEN s = '';
      EXECUTE format('UPDATE condominio_ficha SET %I = $1 WHERE id = $2', k) USING s, f.id;
      n := n + 1; mexeu := true;
    END LOOP;

    -- elevador: a sugestão é booleana, a coluna é a frase que a tela mostra
    IF coalesce(btrim(f.elevador), '') = '' AND jsonb_typeof(f.ia_sugestao->'elevador') = 'boolean' THEN
      UPDATE condominio_ficha
         SET elevador = CASE WHEN (f.ia_sugestao->>'elevador')::boolean
                             THEN 'Sim, possui elevador' ELSE 'Não possui elevador' END
       WHERE id = f.id;
      n := n + 1; mexeu := true;
    END IF;

    -- as listas SOMAM: o que o Tel marcou fica, e o que a pesquisa trouxe
    -- entra depois dele. `DISTINCT ON` sobre a união já resolve o repetido
    -- (ordem menor ganha, e o que ele marcou tem ordem menor de propósito).
    FOREACH k IN ARRAY ARRAY['lazer', 'seguranca', 'comodidades'] LOOP
      CONTINUE WHEN coalesce(jsonb_typeof(f.ia_sugestao->k), '') <> 'array';
      v_atual := CASE k WHEN 'lazer' THEN f.lazer WHEN 'seguranca' THEN f.seguranca ELSE f.comodidades END;
      -- coalesce obrigatório: as três colunas são NOT NULL, e `array_agg` de
      -- conjunto vazio devolve NULL (sugestão com "comodidades": [] vazia)
      SELECT coalesce(array_agg(b.x ORDER BY b.ord), '{}') INTO v_junta
        FROM (SELECT DISTINCT ON (condominio_google_chave(a.x)) a.x, a.ord
                FROM (SELECT left(btrim(u.y), 80) AS x, u.n AS ord
                        FROM unnest(coalesce(v_atual, '{}')) WITH ORDINALITY u(y, n)
                      UNION ALL
                      SELECT left(btrim(e.x), 80), 1000 + e.n
                        FROM jsonb_array_elements_text(f.ia_sugestao->k) WITH ORDINALITY e(x, n)) a
               WHERE condominio_google_chave(a.x) IS NOT NULL
               ORDER BY condominio_google_chave(a.x), a.ord) b;
      IF v_junta IS DISTINCT FROM v_atual THEN
        EXECUTE format('UPDATE condominio_ficha SET %I = $1 WHERE id = $2', k) USING v_junta, f.id;
        n := n + 1; mexeu := true;
      END IF;
    END LOOP;

    IF mexeu THEN nf := nf + 1; END IF;
  END LOOP;

  /* O ENDEREÇO NUM TEXTO SÓ -- sem isto a pesquisa não chega na Nay.
     `nai_cadastro_importar` lê `cf.endereco`, a coluna composta, não
     `logradouro`. Eu escrevi as partes direto (EXECUTE), passando por fora
     do `site_condominio_salvar`, que é quem normalmente recompõe o texto --
     resultado: 427 fichas ficaram com rua nova e endereço vazio, e para a
     Nay nada tinha mudado. A expressão abaixo é a mesma de lá, de propósito.

     SÓ onde está VAZIO: as 24 que já tinham endereço escrito continuam como
     estão. Mesma regra do resto desta função. */
  UPDATE condominio_ficha x
     SET endereco = x.logradouro
                    || coalesce(', nº ' || nullif(x.numero, ''), '')
                    || coalesce(', Bairro ' || nullif(coalesce(x.bairro, c.bairro), ''), '')
                    || coalesce(', ' || nullif(x.cidade, ''), '')
                    || coalesce(' - ' || nullif(x.estado, ''), '')
    FROM condominios c
   WHERE c.id = x.condominio_id
     AND coalesce(btrim(x.logradouro), '') <> ''
     AND coalesce(btrim(x.endereco), '') = ''
     AND (p_id IS NULL OR x.condominio_id = p_id);

  RETURN QUERY SELECT nf, n;
END;
$function$;
