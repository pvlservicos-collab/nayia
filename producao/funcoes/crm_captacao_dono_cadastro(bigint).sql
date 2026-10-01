CREATE OR REPLACE FUNCTION public.crm_captacao_dono_cadastro(p_captacao_id bigint)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  SELECT jsonb_build_object(
    'captacaoId', l.id,
    'nome', nullif(btrim(l.nome), ''),
    'tratamento', nullif(btrim(l.tratamento), ''),
    'temProprietario', l.proprietario_id IS NOT NULL,
    'proprietario', (SELECT p.nome FROM proprietarios p WHERE p.id = l.proprietario_id),
    'codigo', nullif(btrim(l.codigo), ''),
    'condominio', nullif(btrim(l.condominio), ''),
    'bairro', nullif(btrim(l.bairro), ''),
    'tipo', nullif(btrim(l.tipo_imovel), ''),
    'imovelDesc', nullif(btrim(l.imovel_desc), ''),
    'situacao', l.situacao,
    'situacaoPor', l.situacao_por,
    'contratoAte', l.contrato_ate,
    'querVender', coalesce(l.quer_vender, false),
    'temOutroImovel', coalesce(l.tem_outro_imovel, false),
    'valorLocacao', l.valor_locacao_pedido,
    'valorVenda', l.valor_venda_pedido,
    'etapa', l.etapa,
    'status', l.status,
    'respondeuEm', l.respondeu_em,
    'ultimoEnvioEm', l.ultimo_envio_em,
    'fechadoEm', l.fechado_em,
    'optOut', coalesce(l.opt_out, false),
    'comOTel', l.humano_assumiu_em IS NOT NULL,
    'comOTelMotivo', l.humano_motivo,
    'perguntaPendente', l.pergunta_pendente,
    'canal', l.canal,
    'etapaManual', (SELECT e.etapa FROM captacao_etapa_manual e
                     WHERE right(e.telefone, 8) = right(regexp_replace(l.telefone, '\D', '', 'g'), 8) LIMIT 1))
    FROM captacao_leads l
   WHERE l.id = p_captacao_id
$function$;
