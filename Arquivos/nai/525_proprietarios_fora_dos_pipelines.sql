-- 525: os proprietários fora de todos os pipelines do CRM (Pedro, 29/10/2026: "retirar os proprietários de todas as
-- pipelines e deixar um quadrado que quando eu marco eles aparecem na guia deles de proprietário, e não misturado com as
-- outras"). O CRM (PipelineBoard, os funis Parceria, Oficial e Captação e a tela Pipeline) pede os 8 últimos dígitos de
-- quem é proprietário e esconde esses cards; com a caixinha "Proprietários" marcada, mostra SÓ eles.
-- A lista é a mesma que a Nay respeita (nay_proprietario_bloqueio, 463: cadastro, admin antigo, captação, dono de visita).
BEGIN;

CREATE OR REPLACE FUNCTION public.crm_proprietarios_fone8()
 RETURNS SETOF text
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'privado'
AS $function$
  SELECT DISTINCT right(regexp_replace(b.chave, '\D', '', 'g'), 8)
    FROM nay_proprietario_bloqueio b
   WHERE length(regexp_replace(b.chave, '\D', '', 'g')) >= 8
     -- o dono que também está procurando imóvel com a Nay Leads é lead: fica no pipeline
     AND NOT EXISTS (SELECT 1 FROM privado.olx_lead_whatsapp l
                      WHERE right(regexp_replace(l.telefone, '\D', '', 'g'), 8) = right(regexp_replace(b.chave, '\D', '', 'g'), 8))
$function$;
COMMENT ON FUNCTION public.crm_proprietarios_fone8() IS
  '525: os 8 últimos dígitos dos proprietários (nay_proprietario_bloqueio), para o CRM tirar dos pipelines';
REVOKE ALL ON FUNCTION public.crm_proprietarios_fone8() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.crm_proprietarios_fone8() TO nay, nay_disparo;

COMMIT;
