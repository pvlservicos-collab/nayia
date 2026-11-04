-- 587 (Pedro, 03/11/2026, CRM v2): duas peças para as abas Proprietários e Visita.
--
-- 1. crm_imoveis_nomes(codigos): o nome de cada imóvel para a faixa da aba Proprietários ("nem tem o nome dos condomínios
--    deles"). A Parceria só sabe o código (imoveis_do_dono); aqui vem o condomínio, ou tipo e bairro quando não há.
-- 2. crm_visita_leads_cancelar(visita, quem): "Status da visita › Cancelada" numa visita da Nay Leads (privado.olx_visita).
--    A da Parceria já tinha crm_visita_excluir. Faz o que o nay-olx faz ao cancelar (visita.py): a visita vira 'cancelada'
--    e a consulta que esperava resposta também; nada é mandado a ninguém.
BEGIN;

CREATE OR REPLACE FUNCTION public.crm_imoveis_nomes(p_codigos integer[])
 RETURNS TABLE(codigo integer, nome text)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  SELECT i.codigo,
         coalesce(nullif(btrim(CASE WHEN i.condominio_nome ~* 'n[aã]o identificad' OR i.condominio_nome ~ '^[—–-]+$' THEN ''
                                    ELSE i.condominio_nome END), ''),
                  nullif(btrim(concat_ws(' ', i.tipo, i.bairro)), ''))
    FROM imoveis i
   WHERE i.codigo = ANY (coalesce(p_codigos, '{}'))
   LIMIT 500;
$function$;

CREATE OR REPLACE FUNCTION public.crm_visita_leads_cancelar(p_visita bigint, p_quem text)
 RETURNS TABLE(ok boolean, mensagem text)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'privado'
 SET lock_timeout TO '3s'
AS $function$
DECLARE
  v privado.olx_visita;
BEGIN
  SELECT * INTO v FROM privado.olx_visita WHERE id = p_visita FOR UPDATE;
  IF v.id IS NULL THEN
    RETURN QUERY SELECT false, 'Não achei essa visita da Nay Leads.'; RETURN;
  END IF;
  IF v.estado IN ('cancelada', 'expirada') THEN
    RETURN QUERY SELECT true, 'Essa visita já não estava valendo.'; RETURN;
  END IF;
  IF v.estado = 'realizada' THEN
    RETURN QUERY SELECT false, 'Essa visita já foi marcada como realizada' || coalesce(' por ' || v.realizada_por, '') || '.'; RETURN;
  END IF;
  UPDATE privado.olx_visita SET estado = 'cancelada', atualizado_em = now() WHERE id = v.id;
  UPDATE privado.olx_visita_consulta SET estado = 'cancelada' WHERE visita = v.id AND estado = 'esperando';
  RETURN QUERY SELECT true, 'Visita cancelada' || coalesce(' por ' || nullif(btrim(p_quem), ''), '') || '. Ninguém foi avisado.';
END $function$;

REVOKE ALL ON FUNCTION public.crm_imoveis_nomes(integer[]) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.crm_visita_leads_cancelar(bigint, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.crm_imoveis_nomes(integer[]) TO nay_disparo, nay;
GRANT EXECUTE ON FUNCTION public.crm_visita_leads_cancelar(bigint, text) TO nay_disparo, nay;

COMMIT;
