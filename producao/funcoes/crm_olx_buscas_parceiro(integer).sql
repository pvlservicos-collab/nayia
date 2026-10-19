CREATE OR REPLACE FUNCTION public.crm_olx_buscas_parceiro(p_dias integer DEFAULT 7)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'privado', 'pg_temp'
AS $function$
  SELECT coalesce(jsonb_agg(jsonb_build_object(
           'id', b.id, 'estado', b.estado, 'teste', b.teste, 'criado_em', b.criado_em, 'atualizado_em', b.atualizado_em,
           'cliente', coalesce(l.nome, ''), 'cliente_tel', l.telefone, 'origem', l.origem, 'filtros', b.filtros, 'nota', b.nota,
           'titulo', b.escolhido->>'titulo', 'link', b.escolhido->>'url', 'preco', b.escolhido->>'preco_texto',
           'anunciante', b.contato_nome, 'contato', b.contato_tel, 'linha', b.linha, 'resposta', b.resposta_texto,
           'codigo', b.codigo, 'status_do_imovel', (SELECT i.status FROM imoveis i WHERE i.codigo = b.codigo),
           'candidatos', jsonb_array_length(b.candidatos), 'erro', b.erro) ORDER BY b.id DESC), '[]'::jsonb)
    FROM privado.olx_busca_parceiro b JOIN privado.olx_lead_whatsapp l ON l.id = b.lead
   WHERE b.criado_em > now() - make_interval(days => greatest(1, least(coalesce(p_dias, 7), 90)))
$function$;
