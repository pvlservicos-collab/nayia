CREATE OR REPLACE FUNCTION public.nai_pedido_do_turno(p_turno bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
AS $function$
DECLARE
  t nai_turno; k nai_contato; v_texto text; v_tipo text;
BEGIN
  SELECT * INTO t FROM nai_turno WHERE id = p_turno;
  IF t.id IS NULL THEN RETURN '{}'::jsonb; END IF;
  SELECT * INTO k FROM nai_contato WHERE id = t.contato_id;
  v_texto := coalesce(t.texto, '');

  -- UMA leitura so: `rotulo` e o mesmo `tipo` por extenso. Estava sendo
  -- calculado duas vezes, e essa leitura e a cara da funcao inteira.
  v_tipo := nai_tipo_da_conversa(t.contato_id, v_texto);

  RETURN jsonb_build_object(
    'turno',      p_turno,
    'texto',      v_texto,
    'tipo',       v_tipo,
    'rotulo',     nai_rotulo_do_tipo(v_tipo),
    'negocio',    nai_negocio_da_conversa(t.contato_id, v_texto),
    'teto',       nay_maior_valor(v_texto),
    'imoveis',    to_jsonb(nai_imoveis_pedidos(v_texto, coalesce(k.telefone, ''))),
    'cortesia',   nai_e_so_cortesia(v_texto),
    'oferta',     nai_oferece_imovel(v_texto),
    'link',       nai_e_link_de_produto(v_texto),
    'pede_lista', nai_pede_os_valores(v_texto),
    'sem_bairro', nai_sem_preferencia_de_bairro(v_texto) OR nai_e_a_cidade(v_texto),
    'de_imovel',  nai_e_assunto_de_locacao(v_texto)
  );
END;
$function$;
