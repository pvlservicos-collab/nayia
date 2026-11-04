CREATE OR REPLACE FUNCTION public.crm_campanha_listar(p_lista text DEFAULT NULL::text, p_estado text DEFAULT NULL::text, p_limite integer DEFAULT 500)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'privado'
AS $function$
  SELECT jsonb_build_object(
    'resumo', (SELECT coalesce(jsonb_agg(jsonb_build_object('lista', lista, 'estado', estado, 'n', n) ORDER BY lista, estado), '[]')
                 FROM (SELECT lista, estado, count(*) AS n FROM campanha_contato
                        WHERE dia >= (now() AT TIME ZONE 'America/Manaus')::date - 14 GROUP BY 1, 2) t),
    'itens', (SELECT coalesce(jsonb_agg(to_jsonb(t) ORDER BY t.lista, t.prioridade DESC, t.id), '[]') FROM (
                SELECT c.id, c.lista, c.dia, c.nome, c.vocativo, c.telefone, c.linha, c.modelo, c.codigos, c.imoveis,
                       c.prioridade, c.falou_conosco_60d, c.mensagem, c.mensagem_seguinte, c.estado, c.liberada_em,
                       c.liberada_por, c.adiada_motivo, c.outro_atende, c.enviada_em, c.resposta_em, c.resposta_texto,
                       c.classe, c.novo_valor, c.classe_codigos, c.resumo, c.seguinte_em, c.respondeu_quem, c.erro
                  FROM campanha_contato c
                 WHERE (p_lista IS NULL OR c.lista = p_lista) AND (p_estado IS NULL OR c.estado = p_estado)
                   AND c.dia >= (now() AT TIME ZONE 'America/Manaus')::date - 14
                 ORDER BY c.lista, c.prioridade DESC, c.id LIMIT greatest(coalesce(p_limite, 500), 1)) t))
$function$;
