-- =====================================================================
-- 143 — A CONFIRMAÇÃO DA VISITA VAI PARA O NÚMERO DA IMOB EASY (28/09/2026)
--
-- Pedido: "muda a confirmação da rayssa, para confirmar no número da
-- imobeasy que no whatsapp é o +55 92 8595-6408, pode confirmar nesse a
-- visita com proprietários".
--
-- O número da Imob Easy já é "voz do Tel" (`comando_telefones`, pela outra
-- sessão de 28/09), mas NÃO contava como equipe: o pedido de confirmação
-- (papel 'equipe') seria recusado pelo gatilho da caixa de saída e o SIM
-- dele não valeria. Agora quem pode dar comando conta como equipe também.
-- =====================================================================
\set ON_ERROR_STOP on
BEGIN;
SET LOCAL lock_timeout = '5s';

CREATE OR REPLACE FUNCTION public.nai_e_da_equipe_contato(p_contato bigint)
 RETURNS boolean
 LANGUAGE sql
 STABLE
AS $function$
  SELECT EXISTS (
    SELECT 1
      FROM nai_contato c
     WHERE c.id = ANY (nai_contato_irmaos(p_contato))
       AND (
             c.chave = nai_chave(nai_cfg('tel_telefone'))
          OR c.chave = ANY (nai_chaves_de('so_estes_numeros'))
          OR EXISTS (SELECT 1 FROM nay_e_da_equipe(c.telefone))
          -- 143: quem pode dar comando (a "voz do Tel": o número da Imob Easy)
          OR nai_pode_comandar(c.chave)
       )
  );
$function$;

UPDATE nai_config SET valor = '5592985956408', atualizado_em = now() WHERE chave = 'aprovador_visita_telefone';

COMMIT;
