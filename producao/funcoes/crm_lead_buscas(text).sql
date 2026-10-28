CREATE OR REPLACE FUNCTION public.crm_lead_buscas(p_telefone text)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  WITH f AS (SELECT right(regexp_replace(coalesce(p_telefone, ''), '\D', '', 'g'), 8) AS f8)
  SELECT coalesce(jsonb_agg(jsonb_build_object(
           'id', b.id, 'titulo', b.titulo, 'disse', b.disse, 'situacao', b.situacao, 'motivo', b.motivo,
           'analisada_em', b.analisada_em,
           'imoveis', coalesce((
             SELECT jsonb_agg(jsonb_build_object(
                      'codigo', x.codigo, 'nota', x.nota, 'detalhe', x.detalhe,
                      'condominio', i.condominio_nome, 'bairro', i.bairro, 'tipo', i.tipo, 'quartos', i.quartos,
                      'venda', i.valor_venda, 'aluguel', i.valor_aluguel,
                      'enviado', EXISTS (SELECT 1 FROM privado.olx_cliente_enviada e
                                          WHERE e.lead = b.lead_id AND e.codigo = x.codigo))
                    ORDER BY x.posicao)
               FROM privado.lead_busca_imovel x
               JOIN imoveis i ON i.codigo = x.codigo
              WHERE x.busca_id = b.id AND i.status = 'Disponível' AND coalesce(i.disponivel, true)), '[]'::jsonb))
         ORDER BY b.ordem, b.id), '[]'::jsonb)
    FROM privado.lead_busca b, f
   WHERE f.f8 <> '' AND right(regexp_replace(b.telefone, '\D', '', 'g'), 8) = f.f8
$function$;
