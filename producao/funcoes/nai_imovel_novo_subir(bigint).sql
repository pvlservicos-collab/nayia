CREATE OR REPLACE FUNCTION public.nai_imovel_novo_subir(p_id bigint)
 RETURNS integer
 LANGUAGE plpgsql
AS $function$
DECLARE n nai_imovel_novo; v_cod int; v_desc text;
BEGIN
  SELECT * INTO n FROM nai_imovel_novo WHERE id = p_id;
  IF n.id IS NULL OR n.situacao = 'subido' THEN RETURN n.codigo; END IF;

  v_desc := coalesce(n.descricao, '');
  v_desc := regexp_replace(v_desc, '\(?\d{2}\)?\s*9?\d{4}[-. ]?\d{4}', '', 'g');
  v_desc := regexp_replace(v_desc, '[[:alnum:]._%+-]+@[[:alnum:].-]+\.[a-z]{2,}', '', 'g');
  v_desc := regexp_replace(v_desc, '(?i)\m(whats(app)?|contato|falar com|corretor[a]?)\M[^.\n]*', '', 'g');
  v_desc := btrim(regexp_replace(v_desc, '[ \t]+', ' ', 'g'));

  SELECT coalesce(max(codigo), 0) + 1 INTO v_cod FROM imoveis;

  INSERT INTO imoveis (codigo, tipo, condominio_nome, bairro, quartos, suites, vagas,
                       area_total, valor_venda, valor_aluguel, taxa_condominio, mobilia,
                       descricao, origem, disponivel, bloqueado, publicado_no_site,
                       e_parceiro, travado, precisa_confirmacao, administrado)
       VALUES (v_cod, coalesce(n.tipo, 'Apartamento'), n.condominio, n.bairro, n.quartos,
               n.suites, n.vagas, n.area,
               CASE WHEN n.finalidade = 'venda'   THEN n.valor END,
               CASE WHEN n.finalidade = 'locacao' THEN n.valor END,
               n.taxa_condominio, n.mobilia, nullif(v_desc, ''), 'secretaria',
               true, false, true, false, false, false, false);

  INSERT INTO imovel_fotos (codigo, url, ordem, e_capa)
       SELECT v_cod, f.url, row_number() OVER (ORDER BY f.id), row_number() OVER (ORDER BY f.id) = 1
         FROM nai_imovel_novo_foto f WHERE f.novo_id = n.id;

  UPDATE nai_imovel_novo SET situacao = 'subido', codigo = v_cod, subido_em = now() WHERE id = n.id;
  RETURN v_cod;
END;
$function$;
