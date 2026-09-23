-- =====================================================================
-- NAI -- 109: quem tem dono parceiro E parceiro (Tel, 23/09/2026)
--
-- Ele: "tem imoveis que o proprietario esta um corretor (PARCEIRO) mas nao e
-- correto isso, os imoveis de parceiros devem estar separados, nao podem ser
-- enviados pela nay... ex o imovel 4797" e "o filtro de proprietarios na nossa
-- lista imovel esta errado, aparece imoveis de parceiros tb".
--
-- O QUE MEDI: 964 imoveis tem o dono escrito com a marca no proprio nome --
-- "ALEX BRAGA (PARCEIRO)", "David Felipe (PARCEIRO)" -- e mesmo assim estao
-- com `e_parceiro = false`. O 4797 e um deles (esta em revisao, fora do
-- catalogo).
--
-- O QUE IMPORTA DE VERDADE: desses 964, UM esta no catalogo e ao alcance da
-- Nay -- o 3050, Ilhas Gregas Condominio, Ponta Negra, dono "David Felipe
-- (PARCEIRO)". E esse mesmo 3050 foi disparado pelo publicador em 22/09 as
-- 22:05 para um corretor, como se fosse nosso. A parede da Nay
-- (`parceria-nunca-sai`) nao pegou porque ela olha `e_parceiro`, e a marca
-- estava errada.
--
-- A CORRECAO E NA MARCA, nao numa parede nova: quem tem dono parceiro passa a
-- ter `e_parceiro = true`, e com isso some da Nay, some do publicador e some
-- do filtro "so imovel de proprietario (nosso)" -- tudo de uma vez, porque os
-- tres ja olham essa coluna.
-- =====================================================================

\set ON_ERROR_STOP on

BEGIN;

-- Como se reconhece um dono que nao e dono. A marca esta no nome porque foi
-- assim que o pessoal cadastrou no site antigo: "FULANO (PARCEIRO)".
CREATE OR REPLACE FUNCTION public.nai_dono_e_parceiro(p_nome text)
 RETURNS boolean LANGUAGE sql IMMUTABLE
AS $function$
  SELECT coalesce(p_nome, '') ~* '(\(|\[|-|/|\s)(parceiro|parceira|corretor|corretora|imobiliaria|imobiliária|assessoria|creci)'
      OR coalesce(p_nome, '') ~* '^(parceiro|corretor|imobiliaria|imobiliária)\M';
$function$;

-- A marca certa nos imoveis do catalogo.
UPDATE imoveis i
   SET e_parceiro = true
  FROM vw_imoveis_todos v
 WHERE v.codigo = i.codigo
   AND NOT coalesce(i.e_parceiro, false)
   AND nai_dono_e_parceiro(v.proprietario_nome);

COMMIT;

SELECT 'imoveis no catalogo com dono parceiro' AS o,
       count(*)::text AS quantos,
       count(*) FILTER (WHERE e_parceiro)::text AS ja_marcados
  FROM imoveis i
 WHERE EXISTS (SELECT 1 FROM vw_imoveis_todos v
                WHERE v.codigo = i.codigo AND nai_dono_e_parceiro(v.proprietario_nome));

SELECT 'o 3050 agora' AS o, codigo, e_parceiro, publicado_no_site, disponivel
  FROM imoveis WHERE codigo = 3050;
