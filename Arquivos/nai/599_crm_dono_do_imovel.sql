-- 599 (Pedro, 04/11/2026: "quero poder pesquisar lá na aba Proprietários o código do imóvel 1778 ou #1778 e aparecer o
-- número do proprietário"): o dono do imóvel pelo código, para a lupa do CRM. Lê o mesmo que a Nay lê
-- (nai_proprietario_do_imovel) e o resumo do imóvel. O papel do CRM (nay_disparo) só executa funções crm_.
BEGIN;

CREATE OR REPLACE FUNCTION public.crm_dono_do_imovel(p_codigo integer)
 RETURNS TABLE(codigo integer, imovel text, status text, e_parceiro boolean, nome text, telefone text, motivo text)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  SELECT i.codigo,
         nullif(btrim(concat_ws(' · ', nullif(btrim(i.tipo), ''), coalesce(nullif(btrim(i.condominio_nome), ''), nullif(btrim(i.bairro), '')))), ''),
         i.status, coalesce(i.e_parceiro, false), d.nome, d.telefone, d.motivo
    FROM imoveis i
    LEFT JOIN LATERAL (SELECT * FROM nai_proprietario_do_imovel(i.codigo) LIMIT 1) d ON true
   WHERE i.codigo = p_codigo;
$function$;

REVOKE ALL ON FUNCTION public.crm_dono_do_imovel(integer) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.crm_dono_do_imovel(integer) TO nay_disparo, nay;

COMMIT;
