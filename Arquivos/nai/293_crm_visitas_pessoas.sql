-- 293 (05/10/2026, Pedro): "na agenda ... que apareça 2 pequenos cards com a foto e o número de quem está
-- naquela visita, ou seja, o corretor e o proprietário, posso ir para as conversas deles por ali ao clicar".
--
-- crm_visitas (166) traz só o NOME do proprietário. Esta devolve, por visita, o telefone do corretor e do
-- proprietário e as chaves de cada um (telefone e @lid, pelas irmãs), para o CRM achar as duas conversas.
-- O proprietário: o contato gravado na visita; sem ele, o telefone digitado à mão (prop_telefone_manual);
-- sem os dois, o dono do cadastro do imóvel (nai_proprietario_do_imovel, o caminho da Nay).
-- Só leitura. O CRM lê o banco da Nay pelo papel nay_disparo, que só enxerga funções: SECURITY DEFINER.
BEGIN;

CREATE OR REPLACE FUNCTION public.crm_visitas_pessoas(p_ids bigint[])
 RETURNS TABLE(id bigint, corretor_telefone text, proprietario_telefone text, proprietario_chaves text[])
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  SELECT x.id, x.corretor_telefone, x.dono,
         CASE WHEN x.dono_id IS NOT NULL THEN
                ARRAY(SELECT DISTINCT k.chave FROM nai_contato k WHERE k.id = ANY (nai_contato_irmaos(x.dono_id)) OR k.id = x.dono_id)
              WHEN x.dono IS NOT NULL THEN ARRAY[nai_chave(x.dono)]
              ELSE '{}'::text[] END
    FROM (
      SELECT v.id, c.telefone AS corretor_telefone, p.id AS dono_id,
             -- o contato gravado na visita; o número digitado à mão; o dono do cadastro do imóvel
             coalesce(nullif(btrim(p.telefone), ''), nullif(btrim(v.prop_telefone_manual), ''),
                      (SELECT d.telefone FROM nai_proprietario_do_imovel(v.codigo) d
                        WHERE d.motivo IS NULL AND nullif(btrim(d.telefone), '') IS NOT NULL LIMIT 1)) AS dono
        FROM nai_visita v
        LEFT JOIN nai_contato c ON c.id = v.corretor_id
        LEFT JOIN nai_contato p ON p.id = v.proprietario_id
       WHERE v.id = ANY (coalesce(p_ids, '{}'::bigint[]))
    ) x
   LIMIT 2000
$function$;

REVOKE ALL ON FUNCTION public.crm_visitas_pessoas(bigint[]) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.crm_visitas_pessoas(bigint[]) TO nay_disparo;

COMMIT;
