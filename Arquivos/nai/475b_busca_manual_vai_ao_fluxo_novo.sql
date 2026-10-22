-- 475b: a "Busca manual" da tela Buscar imóvel OLX (CRM) abre a busca do cliente do fluxo novo (475), já ATIVADA.
-- Pedro, 22/10/2026: "o que está funcionando hoje não é bom, que é a busca ... que abre no meu PC" e "aquele buscador
-- manual com várias opções da OLX esconde em um botão busca manual". O formulário continua o mesmo
-- (crm_olx_busca_parceiro_abrir cria o lead e a ordem antiga); a rota do CRM chama esta função logo depois: a ordem antiga
-- fica 'cancelado' (o caminho pelo Chrome do PC sai de cena: busca_parceiro = nao) e a busca do cliente nasce com o perfil
-- do formulário, em 'buscando' (grupos e OLX).

BEGIN;

CREATE OR REPLACE FUNCTION public.crm_busca_cliente_manual(p_ordem bigint, p_quem text DEFAULT NULL)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE o record; v_id bigint; v_f jsonb;
BEGIN
  SELECT * INTO o FROM privado.olx_busca_parceiro WHERE id = p_ordem;
  IF o.id IS NULL THEN RETURN jsonb_build_object('ok', false, 'erro', 'ordem não existe'); END IF;
  v_f := jsonb_strip_nulls(jsonb_build_object(
           'finalidade', o.filtros->'finalidade', 'tipo', o.filtros->'tipo', 'teto', o.filtros->'teto',
           'bairros', o.filtros->'bairros', 'qualquer_bairro', o.filtros->'qualquer_bairro', 'quartos', o.filtros->'quartos',
           'aceita_menos_quartos', o.filtros->'aceita_menos_quartos', 'mobilia', o.filtros->'mobilia',
           'financiamento', o.filtros->'financiamento'));
  UPDATE privado.olx_busca_parceiro SET estado = 'cancelado', atualizado_em = now() WHERE id = p_ordem AND estado = 'pendente';
  INSERT INTO privado.busca_cliente (lead, filtros, estado, ativada_em, motivo)
  VALUES (o.lead, v_f, 'buscando', now(), 'busca manual pela tela')
  ON CONFLICT (lead) DO UPDATE SET filtros = EXCLUDED.filtros, estado = 'buscando', ativada_em = now(),
                                  motivo = 'busca manual pela tela', atualizado_em = now()
  RETURNING id INTO v_id;
  INSERT INTO privado.busca_cliente_passo (busca, lugar, texto, dados)
  VALUES (v_id, 'equipe', 'Busca manual aberta' || coalesce(' por ' || nullif(btrim(p_quem), ''), '') || ' (tela do CRM): grupos e OLX', v_f);
  RETURN jsonb_build_object('ok', true, 'busca', v_id);
END $function$;

GRANT EXECUTE ON FUNCTION public.crm_busca_cliente_manual(bigint, text) TO nay_disparo;

-- o caminho antigo (Chrome do PC, olx/parceiro.py) não abre mais ordens sozinho
UPDATE privado.olx_config SET valor = 'nao' WHERE chave = 'busca_parceiro';

COMMIT;
