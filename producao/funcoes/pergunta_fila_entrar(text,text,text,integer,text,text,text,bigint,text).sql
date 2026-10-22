CREATE OR REPLACE FUNCTION public.pergunta_fila_entrar(p_linha text, p_chave text, p_cliente text, p_codigo integer, p_imovel text, p_pergunta text, p_origem text, p_origem_id bigint, p_detalhe text DEFAULT NULL::text)
 RETURNS bigint
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_d  text := regexp_replace(coalesce(p_chave, ''), '\D', '', 'g');
  v_p  text := btrim(coalesce(p_pergunta, ''));
  v_id bigint;
BEGIN
  IF v_p = '' OR length(v_d) < 10 THEN RETURN NULL; END IF;
  -- a mesma pergunta da mesma pessoa sobre o mesmo imóvel, ainda aberta, é a mesma
  SELECT id INTO v_id FROM pergunta_fila
   WHERE estado IN ('fila', 'perguntada', 'agente') AND right(chave, 8) = right(v_d, 8) AND coalesce(codigo, 0) = coalesce(p_codigo, 0)
     AND lower(unaccent(regexp_replace(pergunta, '\s+', ' ', 'g'))) = lower(unaccent(regexp_replace(v_p, '\s+', ' ', 'g')))
   LIMIT 1;
  IF v_id IS NOT NULL THEN RETURN v_id; END IF;
  -- a fila estava vazia: começa a rodada (a numeração volta a 1)
  IF NOT EXISTS (SELECT 1 FROM pergunta_fila WHERE estado IN ('fila', 'perguntada')) THEN
    UPDATE nai_config SET valor = now()::text, atualizado_em = now() WHERE chave = '_pergunta_fila_rodada';
  END IF;
  -- 475: a dúvida da Nay do WhatsApp da OLX (linha captação) vai primeiro ao agente de correção, não ao PV do Tel
  INSERT INTO pergunta_fila (linha, chave, cliente, codigo, imovel, pergunta, origem, origem_id, ordem, detalhe, estado)
  VALUES (p_linha, v_d,
          coalesce(nullif(btrim(p_cliente), ''),
                   (SELECT CASE WHEN btrim(k.nome_completo) ~ '[[:alpha:]]{2}' THEN btrim(k.nome_completo)
                                WHEN btrim(k.nome_whatsapp) ~ '[[:alpha:]]{2}' THEN btrim(k.nome_whatsapp) END
                      FROM nai_contato k WHERE k.chave = nai_chave(v_d) LIMIT 1)),
          p_codigo,
          coalesce(nullif(btrim(p_imovel), ''),
                   (SELECT CASE WHEN coalesce(btrim(i.condominio_nome), '') = ''
                                  OR lower(unaccent(btrim(i.condominio_nome)))
                                     ~ '^(apartamento|predio|casa|cobertura|kitnet|terreno|condominio|residencial|sala|loja|galpao)([/ ].*)?$'
                                THEN nullif(concat_ws(' no ', nullif(btrim(i.tipo), ''), nullif(btrim(i.bairro), '')), '')
                                ELSE btrim(i.condominio_nome) END
                      FROM imoveis i WHERE i.codigo = p_codigo)),
          left(v_p, 1000), p_origem, p_origem_id,
          (SELECT coalesce(max(ordem), 0) + 1 FROM pergunta_fila),
          nullif(btrim(replace(coalesce(p_detalhe, ''), '_', ' ')), ''),
          CASE WHEN p_linha = 'captacao' AND coalesce(nai_cfg('duvida_olx_vai_ao_agente', 'nao'), 'nao') = 'sim'
               THEN 'agente' ELSE 'fila' END)
  ON CONFLICT (origem, origem_id) WHERE origem_id IS NOT NULL DO NOTHING
  RETURNING id INTO v_id;
  RETURN v_id;
END
$function$;
