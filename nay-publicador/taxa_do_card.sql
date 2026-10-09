-- A TAXA DE CONDOMÍNIO NO CARD, E SÓ QUANDO ELA É RECENTE (Tel, 03/10/2026).
--
-- O PEDIDO, com o card dele do 9013 por exemplo: "acrescentando também a taxa
-- de condomínio quando tem, lembrando que você coloca a taxa de condomínio
-- somente dos imóveis tem 45 dias em diante a taxa atualizada no site".
--
-- POR QUE A JANELA EXISTE: taxa de condomínio é reajustada em assembleia. O
-- corretor repassa o número ao cliente e a conta aparece na visita -- citar uma
-- taxa de dois anos atrás custa mais que não citar nenhuma. Então a taxa é a
-- única linha do card com data de validade.
--
-- E AQUI ESTAVA O BURACO: nenhuma coluna de `imoveis` sabia QUANDO a taxa foi
-- escrita. Medido em 03/10, nos 149 imóveis no mercado com taxa:
--   * `sincronizado_em` não serve -- 141 dos 149 foram "tocados nos últimos 45
--     dias" só porque a varredura roda todo dia. A janela não cortaria nada;
--   * `criado_em` não serve -- 124 são do import `planilha_site_antigo_20260926`
--     e trazem 26/09 como data de criação. A data é a do IMPORT, não a da taxa,
--     e são justamente essas as taxas velhas que ele quer de fora.
--
-- Por isso a coluna nova. Sem ela a regra dele não tem como ser obedecida: só
-- dava para fingir obediência usando um carimbo que mede outra coisa.
ALTER TABLE imoveis ADD COLUMN IF NOT EXISTS taxa_condominio_em timestamptz;

COMMENT ON COLUMN imoveis.taxa_condominio_em IS
  'Quando o VALOR de taxa_condominio foi escrito pela última vez. Carimbado '
  'pelo trigger imoveis_carimbar_taxa, nunca à mão. NULL = não se sabe, e o '
  'card não mostra a taxa (regra do Tel, 03/10).';

-- O CARIMBO É TRIGGER, NÃO É RESPONSABILIDADE DE QUEM ESCREVE.
--
-- Medido em 03/10: escrevem em `imoveis.taxa_condominio` a varredura
-- (`sincronizar_catalogo.py`), o `preencher_do_anuncio.py`, a API do site novo
-- (`nay-site-api`), a `nai_imovel_novo_subir` da secretaria, o CRM (o 9013 é o
-- primeiro `origem = 'crm'`, de hoje) e qualquer UPDATE na mão. São seis
-- caminhos, e o sétimo aparece no mês que vem -- este projeto ganhou DOIS
-- catálogos e um CRM em cinco dias.
--
-- Pedir a cada um que carimbe é criar a sétima cópia de uma regra (o padrão 4.3
-- do HISTORICO) e garantir que o próximo writer esqueça -- e esquecer aqui não
-- dá erro: a taxa simplesmente para de sair no card, calada. O trigger não tem
-- como ser esquecido.
CREATE OR REPLACE FUNCTION public.imoveis_carimbar_taxa()
RETURNS trigger
LANGUAGE plpgsql
AS $function$
BEGIN
  -- `IS DISTINCT FROM` e não `<>`: com NULL de um lado o `<>` devolve NULL, a
  -- condição não é verdadeira e a primeira taxa de um imóvel -- que é
  -- exatamente NULL -> valor -- nunca seria carimbada. É a mesma armadilha de
  -- NULL que já derrubou portão neste projeto.
  IF TG_OP = 'INSERT' THEN
    IF NEW.taxa_condominio IS NOT NULL THEN
      NEW.taxa_condominio_em := now();
    END IF;
  ELSIF NEW.taxa_condominio IS DISTINCT FROM OLD.taxa_condominio THEN
    -- Taxa APAGADA perde o carimbo: sem valor não há linha no card, e deixar
    -- data velha pendurada num campo vazio só enganaria a próxima leitura.
    NEW.taxa_condominio_em := CASE WHEN NEW.taxa_condominio IS NULL
                                   THEN NULL ELSE now() END;
  END IF;
  RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS imoveis_carimbar_taxa ON imoveis;
CREATE TRIGGER imoveis_carimbar_taxa
  BEFORE INSERT OR UPDATE OF taxa_condominio ON imoveis
  FOR EACH ROW EXECUTE FUNCTION public.imoveis_carimbar_taxa();

-- A JANELA MORA NO BANCO, muda com um UPDATE e sem deploy -- como
-- `pendencia_horas_para_cobrar` e `lista_repete_minutos` já fazem. Ele disse 45
-- e 45 fica; se amanhã for 30, é uma linha.
INSERT INTO config (chave, valor) VALUES ('card_taxa_dias', '45')
  ON CONFLICT (chave) DO NOTHING;

-- UMA CÓPIA DA REGRA, e é esta função.
--
-- O card do publicador (`montar_mensagem.py`, Python) e o card do banco
-- (`nai_card_do_banco`, SQL) são DOIS montadores do mesmo card, e o projeto já
-- pagou por regra duplicada entre eles. Então a decisão "mostra a taxa?" e o
-- FORMATO dela vivem aqui, e os dois lados só imprimem o texto que sai daqui.
--
-- Devolve NULL -- não string vazia -- quando não deve sair: NULL é o que os dois
-- lados já sabem descartar sem imprimir linha em branco.
CREATE OR REPLACE FUNCTION public.nay_linha_da_taxa(p_taxa numeric,
                                                    p_taxa_em timestamptz)
RETURNS text
LANGUAGE sql
STABLE
AS $function$
  SELECT CASE
    -- FALHA FECHADA, e é a regra do projeto inteiro: taxa sem carimbo não sai.
    -- Hoje isso são as 124 taxas do import da planilha -- as mais velhas do
    -- catálogo, e as que ele mandou de fora. Elas voltam a sair sozinhas quando
    -- alguém reescrever o valor (o trigger carimba) ou quando a leitura do
    -- anúncio corrigir a taxa pelo site.
    WHEN coalesce(p_taxa, 0) <= 0 THEN NULL
    WHEN p_taxa_em IS NULL THEN NULL
    WHEN p_taxa_em < now() - make_interval(days => (
           SELECT coalesce(nullif(valor, '')::int, 45)
             FROM config WHERE chave = 'card_taxa_dias')) THEN NULL
    -- O FORMATO É O DELE, do card do 9013: "• taxa de condomínio 1092,10".
    -- Sem "R$" e sem ponto de milhar -- foi como ele escreveu, e a maior taxa
    -- do catálogo é 3.898,50, então o ponto de milhar quase nunca apareceria.
    -- Os centavos saem sempre: taxa é cobrança com centavos, e "592" ao lado de
    -- "1092,10" no mesmo grupo pareceria dado de qualidade diferente.
    ELSE '• taxa de condomínio '
         || replace(trim(to_char(p_taxa, 'FM999990.00')), '.', ',')
  END;
$function$;

-- BACKFILL, e só onde a data é honesta.
--
-- O catálogo novo (`olx` e `crm`) nasce no banco: a taxa foi digitada por quem
-- captou, no ato, e `criado_em` É a data dela. São 8 imóveis em 03/10, e é de
-- onde vem o 9013 do exemplo dele -- sem este backfill o card do próprio imóvel
-- que ele mandou sairia sem a linha que ele pediu.
--
-- O resto fica NULL de propósito. Chutar data para as 124 da planilha seria
-- afirmar frescor que ninguém mediu, e a afirmação errada é mais cara que a
-- ausência dela -- a lição do "o site não publica a taxa" que guiou este
-- projeto por semanas estando errada.
UPDATE imoveis SET taxa_condominio_em = criado_em
 WHERE taxa_condominio_em IS NULL
   AND coalesce(taxa_condominio, 0) > 0
   AND origem IN ('olx', 'crm');
