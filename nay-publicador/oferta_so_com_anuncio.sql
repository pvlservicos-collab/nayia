-- "Está no mercado?" -- a pergunta em UM lugar só.
--
-- O CASO (Tel, 09/09): *"Brisas Lirio já tirei do site e ainda está
-- aparecendo"*. Ele tirou os sete apartamentos do Brisas do Lírio (5110 a
-- 5116) do site, a varredura VIU que sumiram e marcou
-- `publicado_no_site = false` -- e eles continuaram saindo na lista de
-- apartamentos para locação.
--
-- A varredura estava certa. Quem estava errado era a OFERTA: das 17 funções
-- da Nay que leem `imoveis`, **nenhuma** olhava `publicado_no_site`. Medido
-- no mesmo dia: **35 imóveis** fora do site continuavam sendo oferecidos
-- (22 de locação, 10 de venda, 3 com os dois valores).
--
-- POR QUE ISSO É PIOR QUE PARECE: o corretor recebe o código, procura no site
-- e não acha. E se ele levar cliente, é imóvel que o Tel já tirou de
-- circulação. A regra 2 do projeto -- "sumir do site NÃO vira indisponível" --
-- continua valendo e não muda nada aqui: ela governa o que a VARREDURA
-- escreve, para não apagar cadastro. O que muda é o que a Nay OFERECE.
--
-- POR QUE UMA FUNÇÃO, e não a condição repetida: hoje o
-- `disponivel AND NOT bloqueado` aparece em cinco lugares dentro de três
-- funções, e o próprio `buscar_por_perfil` traz o comentário de que "duas
-- consultas iguais lado a lado divergem na primeira edição". Acrescentar um
-- quarto termo em cinco cópias é criar a divergência de novo. Com a função,
-- mudar o significado de "está no mercado" é mudar UM corpo.
--
-- `e_parceiro` fica DE FORA de propósito: não é sobre o imóvel estar ativo, é
-- sobre de quem ele é -- e o `nay_disponibilidade_no_condominio` precisa
-- contar os de parceria à parte, para poder dizer "no X o que eu tenho é
-- imóvel de parceria" em vez de "não tenho nada".
--
-- FALHA FECHADA: `publicado_no_site` nulo NÃO é ofertável. Medido em 09/09
-- não existe nenhum nulo (853 verdadeiros, 371 falsos, 0 nulos), mas a
-- proteção não pode depender da sorte do cadastro.
--
--   docker cp oferta_so_com_anuncio.sql nay-postgres:/tmp/o.sql
--   docker exec nay-postgres psql -U nay -d naydb -f /tmp/o.sql

CREATE OR REPLACE FUNCTION nay_esta_no_mercado(p_disponivel boolean,
                                               p_bloqueado  boolean,
                                               p_no_site    boolean)
RETURNS boolean
LANGUAGE sql IMMUTABLE AS $fn$
  SELECT coalesce(p_disponivel, true)
     AND NOT coalesce(p_bloqueado, false)
     AND coalesce(p_no_site, false)
$fn$;
