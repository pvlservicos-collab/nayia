CREATE OR REPLACE FUNCTION public.nai_etapa_para_o_modelo(p_contato bigint)
 RETURNS text
 LANGUAGE plpgsql
 STABLE
AS $function$
DECLARE
  r     record;
  v_txt text;
  v_conf text;
BEGIN
  -- a etapa que o `nai_etapa_atualizar` acabou de gravar neste mesmo turno;
  -- so recalcula se ainda nao existe linha
  SELECT e.etapa, e.motivo INTO r FROM nai_etapa_contato e WHERE e.contato_id = p_contato;
  IF r.etapa IS NULL THEN
    SELECT * INTO r FROM nai_etapa_calcular(p_contato);
  END IF;
  v_txt := '(informação de sistema) ETAPA DESTA CONVERSA: ' ||
    CASE r.etapa
      WHEN 'identificacao' THEN
        'IDENTIFICAÇÃO (' || r.motivo || '; ' ||
        coalesce('ele procura ' || CASE nai_negocio_do_pedido(p_contato, '') WHEN 'locacao' THEN 'LOCAÇÃO'
                                                                             WHEN 'venda' THEN 'VENDA' ELSE NULL END,
                 'ainda não se sabe se é locação ou venda: pergunte antes de mandar imóvel') || '). Descubra o que o cliente dele quer: pediu foto, informação ou '
        || 'o imóvel -> card; perguntou se está disponível -> o_que_sei_do_imovel; falou de um imóvel pelo nome e você '
        || 'não tem certeza de qual é -> confirme com a ficha (a ferramenta devolve); pediu opções ou não disse -> '
        || 'buscar_por_perfil (valor, depois bairros). Fale de visita só se ele pedir.'
      WHEN 'recebeu_imovel' THEN
        'RECEBEU O IMÓVEL (' || r.motivo || '). Responda as dúvidas desse imóvel; se ele quiser visitar, vá '
        || 'para a visita; se quiser outras opções, faça o filtro.'
      ELSE
        'AGENDAMENTO DE VISITA (' || r.motivo || '). Cuide só da visita: sem card e sem fotos agora.'
    END;
  SELECT string_agg('o ' || x.codigo || ' em ' || to_char(x.quando AT TIME ZONE 'America/Manaus', 'DD/MM "às" HH24"h"MI')
                    || ' (para confirmar: pedir_visita com codigo ' || x.codigo || ' e quando '
                    || to_char(x.quando AT TIME ZONE 'America/Manaus', 'YYYY-MM-DD HH24:MI') || ')', '; ')
    INTO v_conf
    FROM nai_visita x WHERE x.corretor_id = ANY (nai_contato_irmaos(p_contato)) AND x.estado = 'confirmando';
  IF v_conf IS NOT NULL THEN
    v_txt := v_txt || ' VISITA ESPERANDO A CONFIRMAÇÃO DELE: ' || v_conf
             || '. Se ele confirmar (sim, isso, correto), chame pedir_visita com esses dados.';
  END IF;
  RETURN v_txt;
END;
$function$
;
