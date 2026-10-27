-- 504 (Pedro, 27/10/2026): "está saindo um monte de informação interna na descrição dos imóveis, isso é informação
-- sigilosa, tem que ser revisado todos" / "revisa e tira essas informações de todos, e põe elas em um campo
-- observações internas que não entra no card".
--
-- DE ONDE VINHA: (1) em 26/10 o Claude gravou 152 fatos das conversas dos donos em imoveis.observacao -- o campo que
-- vai no card (nai_card_do_banco, o publicador, a Nay nova), no anúncio da OLX e na API pública do site -- com
-- comissão, preço líquido, margem e menor valor; (2) a memória da Nay (imovel_conhecimento), que as duas Nays leem
-- inteira antes de responder, tinha negociação gravada pela revisão dos donos (25/10) e pela fila do Tel; (3) o card
-- guardado em imovel_ficha.card já tinha esse OBS embutido; (4) cinco descrições de parceiro copiadas com o rodapé
-- do outro corretor (nome, CRECI, chave do anúncio).
--
-- PARA ONDE VAI: o campo interno que já existia -- privado.imovel_ficha.observacoes, o cartão "Uso interno ›
-- Observações" do Editar imóvel (fora do schema public; a Nay nova nem tem permissão de ler). Nada se perde: tudo
-- o que muda fica antes em privado.sigilo_504.
--
-- E DAQUI PARA A FRENTE: gatilhos em imoveis (observacao, descricao), imovel_ficha (card, descricao, observacoes) e
-- imovel_conhecimento separam sozinhos o que é negociação/comissão/registro interno e mandam para o Uso interno.
BEGIN;
SET LOCAL lock_timeout = '3s';
SET LOCAL statement_timeout = '20s';

-- ------------------------------------------------------------------ 0. a cópia de tudo o que muda
CREATE TABLE IF NOT EXISTS privado.sigilo_504 (
  origem text NOT NULL, codigo text NOT NULL, ref text, texto text, quem_contou text, em timestamptz NOT NULL DEFAULT now());
COMMENT ON TABLE privado.sigilo_504 IS
  '504 (27/10): cópia do que estava em imoveis.observacao/descricao, imovel_conhecimento e imovel_ficha.card antes da limpeza do sigilo.';
INSERT INTO privado.sigilo_504 (origem, codigo, texto)
  SELECT 'imoveis.observacao', codigo::text, observacao FROM imoveis WHERE coalesce(btrim(observacao), '') <> '';
INSERT INTO privado.sigilo_504 (origem, codigo, texto)
  SELECT 'imoveis.descricao', codigo::text, descricao FROM imoveis WHERE codigo IN (4376, 9049, 9050, 9066, 9074);
INSERT INTO privado.sigilo_504 (origem, codigo, ref, texto, quem_contou)
  SELECT 'imovel_conhecimento', codigo, id::text || ' | ' || assunto, texto, quem_contou FROM imovel_conhecimento;
INSERT INTO privado.sigilo_504 (origem, codigo, texto)
  SELECT 'imovel_ficha.card', codigo::text, card FROM imovel_ficha WHERE card ~ E'\nOBS: ';

-- ------------------------------------------------------------------ 1. o que é sigilo
-- Negociação e comissão: vale para todo texto (anúncio, observação, memória da Nay).
CREATE OR REPLACE FUNCTION public.nay_e_sigilo(p_texto text) RETURNS boolean
 LANGUAGE sql IMMUTABLE AS $f$
  SELECT coalesce(p_texto, '') ~* (
       'comiss[aã]o|comiss[oõ]es|honor[aá]rio|corretagem|taxa da imobili[aá]ria|\ml[ií]quid[oa]s?\M'
    || '|na m[aã]o d[aeo]|margem (de |para )?(negocia|desconto|manobra)|\mo menor valor|valor m[ií]nimo'
    || '|n[aã]o (baixa|faz desconto|aceita(m)? proposta)|negoci[aá]vel at[eé]|chega a (r\$ ?)?[0-9]|aceita descontar'
    || '|(n[aã]o (d[aá]|faz|tem)|sem) (contrato de )?exclusividade|n[aã]o autoriz|n[aã]o (publiqu|anunci|divulg)'
    || '|\mcreci\M|chave do an[uú]ncio|c[oó]digo do an[uú]ncio|consulte o corretor|\mimobili[aá]rias?\M'
    || '|corretora? \w+ (é|e) (o |a )?respons[aá]vel')
$f$;
COMMENT ON FUNCTION public.nay_e_sigilo(text) IS
  '504: o texto fala de negociação, comissão, valor líquido/mínimo, exclusividade ou é rodapé de anúncio de outro corretor. Não sai para cliente nem corretor.';

-- Registro interno: além do sigilo, o jeito de anotação da equipe ("o proprietário disse", "CONFERIR", "(Nome, 12/10)").
-- Só para a observação do imóvel e o card -- na memória da Nay esse é o jeito normal de gravar.
CREATE OR REPLACE FUNCTION public.nay_e_registro_interno(p_texto text) RETURNS boolean
 LANGUAGE sql IMMUTABLE AS $f$
  SELECT nay_e_sigilo(p_texto) OR coalesce(p_texto, '') ~* (
       'propriet[aá]ri[oa]s? (\([^)]*\) )?(disse|confirmou|respondeu|quer|pediu|pede|falou|informou|n[aã]o autorizou)'
    || '|\mconferir\M|\mimportante\M|aten[cç][aã]o|interesse principal|[0-9]{1,2}/[0-9]{1,2}\)')
$f$;

-- Separa linha a linha (e, na linha marcada, frase a frase): o que fica público e o que vai para o Uso interno.
CREATE OR REPLACE FUNCTION public.nay_separar_sigilo(p_texto text, p_registro boolean, OUT publico text, OUT interno text)
 LANGUAGE plpgsql IMMUTABLE AS $f$
DECLARE
  linha text; frase text; pub text[] := '{}'; int_ text[] := '{}'; resto text[]; marcado boolean;
BEGIN
  IF p_texto IS NULL THEN RETURN; END IF;
  FOREACH linha IN ARRAY regexp_split_to_array(p_texto, E'\n') LOOP
    marcado := CASE WHEN p_registro THEN nay_e_registro_interno(linha) ELSE nay_e_sigilo(linha) END;
    IF marcado THEN
      resto := '{}';
      FOREACH frase IN ARRAY regexp_split_to_array(linha, '(?<=[.!?;])\s+|\s+/\s+') LOOP
        marcado := CASE WHEN p_registro THEN nay_e_registro_interno(frase) ELSE nay_e_sigilo(frase) END;
        IF marcado THEN
          int_ := int_ || btrim(regexp_replace(frase, '^\s*OBS:\s*', ''));
        ELSE
          resto := resto || frase;
        END IF;
      END LOOP;
      linha := btrim(array_to_string(resto, ' '));
      IF linha <> '' AND linha !~* '^OBS:\s*$' THEN pub := pub || linha; END IF;
    ELSE
      pub := pub || linha;
    END IF;
  END LOOP;
  publico := nullif(btrim(array_to_string(pub, E'\n')), '');
  interno := nullif(btrim(array_to_string(int_, ' ')), '');
END $f$;

-- Soma no Uso interno do imóvel, sem repetir o que já está lá (a ficha do anúncio é relida a cada 3 h).
CREATE OR REPLACE FUNCTION privado.uso_interno_somar(p_codigo integer, p_texto text) RETURNS void
 LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public', 'privado' AS $f$
BEGIN
  IF p_codigo IS NULL OR coalesce(btrim(p_texto), '') = '' THEN RETURN; END IF;
  INSERT INTO privado.imovel_ficha AS f (codigo, observacoes, atualizado_em)
  VALUES (p_codigo, btrim(p_texto), now())
  ON CONFLICT (codigo) DO UPDATE
     SET observacoes = CASE WHEN coalesce(btrim(f.observacoes), '') = '' THEN EXCLUDED.observacoes
                            WHEN position(EXCLUDED.observacoes IN f.observacoes) > 0 THEN f.observacoes
                            ELSE f.observacoes || E'\n' || EXCLUDED.observacoes END,
         atualizado_em = CASE WHEN position(EXCLUDED.observacoes IN coalesce(f.observacoes, '')) > 0
                              THEN f.atualizado_em ELSE now() END;
END $f$;

-- ------------------------------------------------------------------ 2. a observação do card: o original vai inteiro
--    para o Uso interno; fica só a parte pública (sem nome de dono, data, negociação ou aviso da equipe)
CREATE TEMP TABLE obs_nova (codigo int PRIMARY KEY, texto text) ON COMMIT DROP;
INSERT INTO obs_nova VALUES
 (205, $t$Casa toda climatizada.$t$),
 (216, $t$Na venda ficam o ar-condicionado, a banheira e os armários; não ficam sofá, geladeira, mesa, cama e fogão. A água está incluída na taxa de condomínio.$t$),
 (331, $t$Fica só com os armários e o ar-condicionado.$t$),
 (887, $t$O aluguel de R$ 8.000 já inclui condomínio e IPTU.$t$),
 (1189, $t$Dependência de serviço, 4 splits, tela de proteção, cortinas nos quartos e varanda.$t$),
 (1246, $t$Os embutidos da copa ficam no imóvel.$t$),
 (1595, $t$Não é mobiliado: ficam poucas peças de mobília. Está desocupado.$t$),
 (1606, $t$Livre para visita somente a partir do final de fevereiro/2027.$t$),
 (1750, $t$Não é condomínio (sem taxa). 2 áreas de serviço, 2 salas de estar, 1 sala de jantar, lavanderia e terraço; 7 x 20 m (140 m²). Serve também para comércio, clínica ou consultório.$t$),
 (1778, $t$Só tem armários na cozinha e está sem ar-condicionado.$t$),
 (1953, $t$Taxa de condomínio de R$ 3.000, com água e gás incluídos; pode haver reajuste em breve (assembleias em andamento).$t$),
 (2014, $t$Locação com depósito caução (não aceita fiador) e análise de perfil do cliente.$t$),
 (2084, $t$Livre para visita somente a partir da 2ª semana de novembro/2026.$t$),
 (2201, $t$Livre para visita somente a partir do final de dezembro/2026.$t$),
 (2202, $t$Não aceita permuta (nem por imóvel, nem por carro).$t$),
 (2315, $t$Só para venda; não aceita troca.$t$),
 (2411, $t$Está só com modulados e ar-condicionado.$t$),
 (2462, $t$Terreno maior que os demais do condomínio (é a última casa): 11,3 x 14 x 25 m. Condomínio incluso no aluguel.$t$),
 (2609, $t$Livre para visita somente a partir do final de janeiro/2027.$t$),
 (2943, $t$Móveis projetados (sem móveis soltos).$t$),
 (2944, $t$Não aceita pet.$t$),
 (2952, $t$Livre para visita somente a partir de 02/12/2026. Ficam cortinas em todo o apartamento, fechadura eletrônica na porta principal, 3 ar-condicionados e móveis planejados na cozinha. Garantia: 2 cauções, parceláveis em até 3 vezes.$t$),
 (3078, $t$Livre para visita somente a partir do início de novembro/2026.$t$),
 (3347, $t$Livre para visita somente a partir de janeiro/2027.$t$),
 (3516, $t$Piso em porcelanato, forro de gesso e banheiro de uma suíte reformado.$t$),
 (3605, $t$Livre para visita somente a partir de janeiro/fevereiro de 2027.$t$),
 (3647, $t$Andar alto com vista para o rio: 1 suíte e 2 quartos com banheiro americano, sala de jantar com home theater, lavabo, varanda e depósito na garagem. O aluguel de R$ 8.000 já inclui condomínio e IPTU.$t$),
 (3735, $t$Livre para visita somente a partir do final de dezembro/2026.$t$),
 (3751, $t$Não aceita animal de estimação de nenhum porte.$t$),
 (3755, $t$Não aceita animal de estimação de nenhum porte.$t$),
 (4099, $t$Livre para visita somente a partir do final de dezembro/2026.$t$),
 (4159, $t$O condomínio (R$ 600) já está embutido no aluguel de R$ 4.000.$t$),
 (4300, $t$Livre para visita somente a partir de dezembro/2026.$t$),
 (4305, $t$Livre para visita somente a partir do final de fevereiro/2027.$t$),
 (4331, $t$Livre para visita somente a partir de dezembro/2026.$t$),
 (4538, $t$12º andar, vista para o Rio Negro e a ponte. Totalmente mobiliado, gerador 100% no apartamento.$t$),
 (4776, $t$4 suítes master, todas com closet, e garagem ampla.$t$),
 (4823, $t$O aluguel já inclui condomínio e IPTU.$t$),
 (4902, $t$4 suítes master, todas com closet, e garagem ampla.$t$),
 (5045, $t$Tem documentação que permite financiamento bancário na venda.$t$),
 (5141, $t$São dois lotes, jardim amplo, 4 salas, lavabo, cozinha com geladeira, lava-louças, cooktop, forno e exaustor (ficam no imóvel) e área de serviço. Desocupada.$t$),
 (5165, $t$Livre para visita somente a partir do final de janeiro/2027.$t$),
 (5241, $t$Casa duplex: sala com 3 ambientes, lavabo, cozinha, lavanderia, banheiro social e garagem para 4 carros.$t$),
 (5609, $t$O aluguel de R$ 5.800 já inclui o condomínio.$t$),
 (5629, $t$Garantia: depósito caução (não aceita fiador).$t$),
 (5647, $t$Tem habite-se e aceita financiamento.$t$),
 (5668, $t$Casa duplex: no 1º pavimento, sala integrada, cozinha, lavabo e quintal (coberto e descoberto, com churrasqueira); no 2º, 2 quartos, varanda e banheiro. Portas e janelas em blindex, bancada em granito com cooktop, infraestrutura para ar-condicionado em todos os cômodos. Aceita financiamento; entrega prevista de 30 a 40 dias após o habite-se (previsto para o fim de janeiro).$t$),
 (5683, $t$Livre para visita somente a partir de 01/11/2026.$t$),
 (5699, $t$Aceita pet. O condomínio não tem porteiro.$t$),
 (5706, $t$Só para venda.$t$),
 (5712, $t$A água é rateada entre os moradores. O condomínio é pago à parte pelo inquilino.$t$),
 (5721, $t$A casa precisa de reparos; a locadora faz os reparos depois de alugar.$t$),
 (5726, $t$2 lances de escada até o apartamento (o térreo conta como 1º andar).$t$),
 (5727, $t$Aceita pet de pequeno porte. IPTU à parte, em torno de R$ 95 a R$ 100 por mês.$t$),
 (5728, $t$IPTU, gás e taxa de condomínio já inclusos no aluguel.$t$),
 (5731, $t$Caução de 6 meses de aluguel; o IPTU é por conta do inquilino.$t$),
 (5739, $t$Prédio de 8 andares; é o último andar. Vaga de garagem descoberta.$t$),
 (5743, $t$Semi-mobiliado: tem modulados e ar-condicionado, não são móveis planejados. O aluguel de R$ 2.500 já inclui o condomínio, mas não a energia; reajuste anual.$t$),
 (5757, $t$Garantia: depósito caução (não aceita fiador).$t$),
 (5764, $t$Casa duplex: no 1º pavimento, sala integrada, cozinha, lavabo e quintal (coberto e descoberto, com churrasqueira); no 2º, 2 quartos, varanda e banheiro. Portas e janelas em blindex, bancada em granito com cooktop, infraestrutura para ar-condicionado em todos os cômodos. Aceita financiamento; entrega prevista de 30 a 40 dias após o habite-se (previsto para o fim de janeiro).$t$),
 (9003, $t$4 apartamentos por andar. As 2 vagas de garagem são soltas, no subsolo. Aluga mobiliado.$t$),
 (9021, $t$Varanda com tela de proteção. 2 elevadores por torre. Pet place e salão de festas. Água, energia e taxa de condomínio por conta do inquilino, além do aluguel.$t$),
 (9036, $t$Sala entregue acabada, com piso e forro, sem divisórias; 2 shafts onde dá para fazer copa, cozinha ou banheiro; banheiro no corredor. Cada sala tem direito a 2 vagas rotativas. Quem alugar adapta a sala. O condomínio do prédio (anexo ao Soberane) começa em dezembro ou janeiro, mas já dá para entrar para fazer obras. Condomínio incluso no valor; IPTU à parte.$t$),
 (9037, $t$IPTU por conta do inquilino.$t$),
 (9040, $t$Lote de 12 x 25 m, quitado (sem dívidas ou ônus).$t$),
 (9044, $t$Apartamento sem acabamento (ideal para o cliente fazer o projeto), elevador social e de serviço, 2 vagas soltas no subsolo, gerador 100%.$t$),
 (9048, $t$Falta só a cama, mas a locadora pode colocar.$t$),
 (9055, $t$Condomínio pequeno (cerca de 8 casas), sem área de lazer; lavanderia externa, quintal lateral e 1 lavabo além dos banheiros.$t$);

-- as que já eram públicas e ficam como estão (texto da equipe ou descrição limpa)
CREATE TEMP TABLE obs_fica (codigo int PRIMARY KEY) ON COMMIT DROP;
INSERT INTO obs_fica VALUES (1288), (5714), (5718), (5744), (5746), (5748), (5762), (9008), (9022), (9026), (9045),
                            (9057), (9058), (9067), (9068);

CREATE TEMP TABLE obs_muda ON COMMIT DROP AS
  SELECT i.codigo, i.observacao AS antes, n.texto AS depois
    FROM imoveis i LEFT JOIN obs_nova n USING (codigo)
   WHERE coalesce(btrim(i.observacao), '') <> '' AND NOT EXISTS (SELECT 1 FROM obs_fica f WHERE f.codigo = i.codigo);

SELECT privado.uso_interno_somar(codigo, 'Tirado da observação do card em 27/10 (504): ' || antes) FROM obs_muda;
UPDATE imoveis i SET observacao = m.depois FROM obs_muda m WHERE m.codigo = i.codigo;

-- o card guardado da ficha do anúncio que trazia a observação antiga: troca o bloco OBS pelo público (ou tira)
UPDATE imovel_ficha f
   SET card = regexp_replace(f.card, E'\nOBS: .*?(\nC[óo]digo:)',
                             coalesce(E'\nOBS: ' || regexp_replace(m.depois, '\s*\n+\s*', ' / ', 'g'), '') || E'\\1')
  FROM obs_muda m
 WHERE f.codigo = m.codigo AND f.card ~ E'\nOBS: '
   AND position(left(regexp_replace(btrim(m.antes), '\s+', ' ', 'g'), 25) IN regexp_replace(f.card, '\s+', ' ', 'g')) > 0;

-- ------------------------------------------------------------------ 3. as cinco descrições de parceiro copiadas
SELECT privado.uso_interno_somar(4376,
  $t$Tirado da descrição em 27/10 (504): Corretor José é responsável pelo imóvel do proprietário Alberto. Para agendar uma visita, entrar em contato com José com 1 dia de antecedência, para que o proprietário autorize a visita.$t$);
UPDATE imoveis SET descricao = btrim(regexp_replace(descricao, '\s*Corretor José é responsável.*$', '')) WHERE codigo = 4376;
SELECT privado.uso_interno_somar(9066, $t$Tirado da descrição em 27/10 (504): anúncio de Heber Gomes, CRECI 6669/PF (código 188413).$t$);
SELECT privado.uso_interno_somar(9074, $t$Tirado da descrição em 27/10 (504): anúncio de Alessandra Borghe, CRECI 4212 (código 241praias).$t$);
UPDATE imoveis SET descricao = btrim(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(
         descricao,
         '^\s*C[óo]digo do an[uú]ncio:[^\n]*\n*', ''),
         '\n[^\n]*Chave do an[uú]ncio:[^\n]*', '', 'g'),
         '\n[^\n]*Consulte o corretor respons[aá]vel\.?[^\n]*', '', 'g'),
         '\n[^\n]*Aprovamos seu financiamento banc[aá]rio sem custo[^\n]*', '', 'g'),
         '\n\s*(Heber Gomes|CRECI 6669/PF)\s*(?=\n|$)', '', 'g'),
         '\n\s*Agende sua visita\s*\n\s*Alessandra Borghe\s*\n\s*Creci:\s*4212\s*\n+\s*Im[óo]vel atualizado em\s*', E'\n', 'g'))
 WHERE codigo IN (9049, 9050, 9066, 9074);

-- ------------------------------------------------------------------ 4. a memória da Nay (imovel_conhecimento)
-- 4a. saem inteiras: negociação, comissão, menor valor, exclusividade, autorização, aviso interno
CREATE TEMP TABLE k_sai (id bigint PRIMARY KEY) ON COMMIT DROP;
INSERT INTO k_sai VALUES (437), (451), (457), (458), (462), (463), (472), (478), (488), (510), (514), (415), (519), (523),
  (531), (537), (549), (407), (562), (579), (465), (466), (467), (468), (603), (561), (425), (547), (542), (418), (410);

-- 4b. ficam só com a parte pública
CREATE TEMP TABLE k_nova (id bigint PRIMARY KEY, texto text) ON COMMIT DROP;
INSERT INTO k_nova VALUES
 (444, $t$A proprietária disse em 31/08 que o apartamento está alugado.$t$),
 (448, $t$A proprietária disse em 15/09 que o apartamento está alugado e que a inquilina deve sair (previsão de uns 3 meses, sem data certa).$t$),
 (454, $t$O proprietário disse em 21/10 que o apartamento do Mondrian está locado e que vai verificar até quando vai o contrato.$t$),
 (470, $t$O aluguel de R$ 8.000 já inclui condomínio e IPTU. O apartamento é todo mobiliado, com 3 suítes e copa.$t$),
 (489, $t$O proprietário confirmou em 16/10 que a sala do Tropical Center segue à venda.$t$),
 (497, $t$O proprietário disse em 15/10 que o lote sai por R$ 550.000 à vista.$t$),
 (498, $t$O proprietário disse em 09/10 que a casa sai por R$ 1.200.000 na venda e R$ 7.000 no aluguel. Em 16/10 disse que a casa está locada, mas segue disponível para venda.$t$),
 (502, $t$O apartamento não deve ser considerado mobiliado: ficam poucas peças de mobília. Está desocupado.$t$),
 (516, $t$Garantia: caução de 2 meses, fora do valor do aluguel. Antes de aprovar, o proprietário pede perfil, Serasa e comprovante de renda do cliente.$t$),
 (515, $t$O preço de venda é R$ 980.000.$t$),
 (518, $t$O proprietário disse que a cobertura está disponível para venda por R$ 2.200.000 e que também pode ser locação com opção de compra em 1 ano.$t$),
 (525, $t$A chave fica com a administração do proprietário, que atende de segunda a sexta (não aos sábados); é preciso mandar antes os dados de quem vai visitar para liberar a entrada. A locação é com depósito caução (não fiador) e passa por análise de perfil do cliente.$t$),
 (526, $t$A proprietária confirmou em 12/10 que a casa segue disponível, só para venda (não para locação).$t$),
 (469, $t$A proprietária disse em 07/10 que o apartamento do Easy está locado, portanto não está disponível.$t$),
 (528, $t$A proprietária confirmou em 12/10 que a casa está disponível.$t$),
 (529, $t$O proprietário confirmou em 12/10 que o imóvel está disponível.$t$),
 (534, $t$O apartamento do Coral Gables fica no 7º andar.$t$),
 (533, $t$Para a visita, é preciso mandar antes os nomes e documentos de quem vai, para a liberação na portaria. Não há energia ligada no apartamento: visita só de dia.$t$),
 (536, $t$A taxa de condomínio é de cerca de R$ 450 (informada pela proprietária em 30/09).$t$),
 (543, $t$O aluguel é R$ 6.800, com condomínio incluso.$t$),
 (545, $t$A visita é liberada pela portaria do Residencial Tapajós, com autorização do proprietário. À noite não é possível visitar.$t$),
 (550, $t$Venda por R$ 700.000. Em 19/10 a proprietária passou o aluguel: R$ 4.000 mais R$ 1.500 de condomínio (o IPTU ainda falta confirmar).$t$),
 (558, $t$O apartamento é no 18º andar, com móveis projetados (sem móveis soltos). Aluguel de R$ 3.500; a proprietária avalia o perfil financeiro do cliente antes de fechar.$t$),
 (557, $t$Aluguel de R$ 3.800 com condomínio incluso. Venda por R$ 470 mil, com toda a documentação. A chave fica com a proprietária: a visita se combina com antecedência.$t$),
 (555, $t$Apartamento no 12º andar. Aluguel de R$ 5.000 com condomínio e IPTU incluídos. Está locado até 02/12/2026; visitas só depois dessa data.$t$),
 (563, $t$Para a visita, é preciso mandar antes o nome do corretor e o veículo, para a liberação. A portaria do condomínio está em reforma: avisar na portaria ao chegar. O apartamento foi reformado.$t$),
 (566, $t$O proprietário confirmou em 13/10 que o apartamento segue disponível.$t$),
 (568, $t$O proprietário resolveu vender a casa do Villa Verde 1: 4 quartos sendo 3 suítes, 190 m² construídos, 2 vagas, piso em porcelanato, forro de gesso, modulada e climatizada, banheiro de uma suíte reformado. Pede R$ 850.000. Pode marcar visita para cliente (o proprietário volta de viagem em 27/10).$t$),
 (496, $t$A casa do Vivenda das Samambaias sai por R$ 370.000. O proprietário disse que não fez benfeitorias na casa.$t$),
 (572, $t$A casa foi alugada em 08/10, com contrato de 15/10/2026 a 15/10/2027.$t$),
 (475, $t$A proprietária descreveu em 08/09 o apartamento do Solar da Praia: andar alto com vista para o rio, 1 suíte e 2 quartos com banheiro americano, sala de jantar com home theater, lavabo, cozinha, varanda, depósito na garagem e 2 vagas.$t$),
 (576, $t$Aluguel total de R$ 8.000, com condomínio e IPTU incluídos.$t$),
 (473, $t$A proprietária confirmou em 21/10 que vende por R$ 1.200.000, mobiliado. Aluguel de R$ 8.000.$t$),
 (584, $t$O proprietário confirmou que o apartamento é no 7º andar (a ficha tinha 5º).$t$),
 (585, $t$Aluguel de R$ 3.500 com condomínio incluso. Gerador 100% no apartamento. Totalmente mobiliado. 12º andar, vista para o Rio Negro e a ponte. 2 quartos sendo 1 suíte, sala, varanda, banheiro social, cozinha e área de serviço.$t$),
 (586, $t$A proprietária disse que o imóvel não está mais disponível (vendido ou reservado).$t$),
 (593, $t$Tem documentos que permitem financiamento bancário na venda. Condomínio de R$ 1.700 (com desconto se pago até o dia 5).$t$),
 (453, $t$Esta casa do Le Village Blanc está à venda por R$ 2.500.000.$t$),
 (598, $t$Casa duplex de 220 m²: 3 suítes, sala com 3 ambientes, lavabo, cozinha, lavanderia, banheiro social e garagem para 4 carros. Venda R$ 1.290.000.$t$),
 (600, $t$O proprietário disse que o apartamento tem 96 m², mobiliado (a ficha tem 113 m² de área útil; pode ser a área privativa).$t$),
 (604, $t$Os contratos deste imóvel são com depósito caução, não com fiador.$t$),
 (605, $t$Os contratos deste imóvel são com depósito caução, não com fiador.$t$),
 (606, $t$Os contratos deste imóvel são com depósito caução, não com fiador.$t$),
 (607, $t$O proprietário disse que a casa tem habite-se e pode ser financiada.$t$),
 (612, $t$Casa duplex: no 1º pavimento, sala integrada, cozinha, lavabo e quintal (coberto e descoberto, com churrasqueira); no 2º, 2 quartos, varanda e banheiro. Portas e janelas em blindex, bancada em granito com cooktop, infraestrutura para ar-condicionado em todos os cômodos. Aceita financiamento; entrega prevista de 30 a 40 dias após o habite-se (previsto para o fim de janeiro).$t$),
 (613, $t$Casa duplex: no 1º pavimento, sala integrada, cozinha, lavabo e quintal (coberto e descoberto, com churrasqueira); no 2º, 2 quartos, varanda e banheiro. Portas e janelas em blindex, bancada em granito com cooktop, infraestrutura para ar-condicionado em todos os cômodos. Aceita financiamento; entrega prevista de 30 a 40 dias após o habite-se (previsto para o fim de janeiro).$t$),
 (657, $t$O condomínio não tem porteiro. A visita e as dúvidas do dia a dia se combinam com o inquilino, que mora no imóvel.$t$),
 (546, $t$Este imóvel é somente para venda, não para locação. IPTU de cerca de R$ 1.260.$t$),
 (637, $t$Casa documentada no Villa Suíça, com 1 suíte e piscina; R$ 720.000.$t$),
 (634, $t$4 apartamentos por andar. As 2 vagas de garagem são soltas, no subsolo. A proprietária aluga mobiliado.$t$),
 (640, $t$Condomínio Estilo Golf, bairro Colônia Japonesa: 2 quartos, 2 banheiros, sala, cozinha e varanda com tela de proteção. 2 elevadores por torre. Piscina adulto e infantil, pet place e salão de festas.$t$),
 (641, $t$Água, energia e a taxa de condomínio (cerca de R$ 280, com gás incluído) são por conta do inquilino, pagos além do aluguel.$t$),
 (643, $t$O imóvel está desocupado. Fica no Condomínio Reserva das Flores (Av. Frederico Baird), um condomínio tranquilo.$t$),
 (507, $t$O proprietário disse em 07/10 que a casa duplex do Ponta Negra Village (ao lado do Shopping Ponta Negra) está disponível por R$ 1.590.000, com 4 suítes e dependência. A visita precisa ser agendada com antecedência. IPTU R$ 1.500 (por ano, como está no cadastro).$t$),
 (541, $t$A proprietária está com a chave da sala e vai pôr fechadura eletrônica para facilitar as visitas.$t$),
 (539, $t$Sala de 100 m², R$ 23.000 com condomínio incluso; IPTU à parte (valor ainda não informado).$t$),
 (592, $t$Lote de 12 x 25 m, quitado (sem dívidas ou ônus).$t$),
 (426, $t$A casa está passando por reparos e melhorias (serviços a partir da semana de 26/10): confirmar antes de marcar visita.$t$),
 (548, $t$Apartamento cru (sem acabamento, ideal para o cliente fazer o projeto), 4 quartos sendo 3 suítes, 135 m², andar alto (acima do 14º) com vista para a Ponte do Rio Negro, poente, 4 banheiros e 1 lavabo, varanda ampla, dá para ampliar sala e cozinha, elevador social e de serviço, 2 vagas soltas no subsolo, gerador 100%. Condomínio de R$ 1.265 com água e gás; IPTU de cerca de R$ 1.500. Aceita financiamento.$t$),
 (650, $t$Weekend Club, 12º andar. Totalmente mobiliado, gerador 100% no apartamento, vista para o Rio Negro e a ponte.$t$),
 (524, $t$A construtora (proprietária) disse em 15/10 que a taxa de condomínio é R$ 3.000, com água e gás incluídos, e que há assembleias em andamento: pode haver reajuste em breve.$t$),
 (596, $t$A casa está desocupada (confirmado pela proprietária).$t$),
 (630, $t$Aceita pet de pequeno porte (a proprietária condicionou ao porte do animal).$t$);

SELECT privado.uso_interno_somar(NULLIF(regexp_replace(k.codigo, '\D', '', 'g'), '')::int,
         'Tirado da memória da Nay em 27/10 (504) — ' || k.assunto || ': ' || k.texto
         || coalesce(' (' || k.quem_contou || ')', ''))
  FROM imovel_conhecimento k
 WHERE k.id IN (SELECT id FROM k_sai) OR k.id IN (SELECT id FROM k_nova)
 ORDER BY k.codigo, k.id;
DELETE FROM imovel_conhecimento WHERE id IN (SELECT id FROM k_sai);
UPDATE imovel_conhecimento k SET texto = n.texto, atualizado_em = now() FROM k_nova n WHERE n.id = k.id;

-- 4c. o resto fica, sem o nome do dono entre parênteses: "O proprietário (Ricardo) disse" -> "O proprietário disse"
UPDATE imovel_conhecimento
   SET texto = regexp_replace(texto, '((propriet|procurador)[a-zà-ú]*)\s*\([^)]*\)', '\1', 'gi')
 WHERE texto ~* '(propriet|procurador)[a-zà-ú]*\s*\(';

-- ------------------------------------------------------------------ 5. a API pública do site não leva mais a observação
-- (a página nunca mostrou o `obs`, mas ele ia no JSON aberto)
DO $do$
DECLARE d text;
BEGIN
  d := pg_get_functiondef('public.site_imovel_publico(integer)'::regprocedure);
  IF position($s$    'obs', t.observacao,$s$ IN d) = 0 THEN RAISE EXCEPTION 'site_imovel_publico mudou: não achei a linha do obs'; END IF;
  EXECUTE replace(d, $s$    'obs', t.observacao,$s$ || E'\n', '');
END $do$;

-- ------------------------------------------------------------------ 6. a trava: o que chegar de novo já entra separado
CREATE OR REPLACE FUNCTION public.imoveis_sigilo_fora() RETURNS trigger
 LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public', 'privado' AS $f$
DECLARE s record;
BEGIN
  IF NEW.observacao IS DISTINCT FROM (CASE WHEN TG_OP = 'UPDATE' THEN OLD.observacao END)
     AND nay_e_registro_interno(NEW.observacao) THEN
    SELECT * INTO s FROM nay_separar_sigilo(NEW.observacao, true);
    PERFORM privado.uso_interno_somar(NEW.codigo, 'Tirado da observação do card (504): ' || s.interno);
    NEW.observacao := s.publico;
  END IF;
  IF NEW.descricao IS DISTINCT FROM (CASE WHEN TG_OP = 'UPDATE' THEN OLD.descricao END)
     AND nay_e_sigilo(NEW.descricao) THEN
    SELECT * INTO s FROM nay_separar_sigilo(NEW.descricao, false);
    PERFORM privado.uso_interno_somar(NEW.codigo, 'Tirado da descrição (504): ' || s.interno);
    NEW.descricao := s.publico;
  END IF;
  RETURN NEW;
END $f$;
DROP TRIGGER IF EXISTS imoveis_sigilo_fora ON imoveis;
CREATE TRIGGER imoveis_sigilo_fora BEFORE INSERT OR UPDATE OF observacao, descricao ON imoveis
  FOR EACH ROW EXECUTE FUNCTION imoveis_sigilo_fora();

-- a ficha do anúncio (relida do site antigo a cada 3 h): o card e o texto que a Nay lê saem limpos
CREATE OR REPLACE FUNCTION public.imovel_ficha_sigilo_fora() RETURNS trigger
 LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public', 'privado' AS $f$
DECLARE s record;
BEGIN
  IF nay_e_registro_interno(NEW.card) THEN NEW.card := (nay_separar_sigilo(NEW.card, true)).publico; END IF;
  IF nay_e_sigilo(NEW.descricao) THEN NEW.descricao := (nay_separar_sigilo(NEW.descricao, false)).publico; END IF;
  IF nay_e_sigilo(NEW.observacoes) THEN
    SELECT * INTO s FROM nay_separar_sigilo(NEW.observacoes, false);
    PERFORM privado.uso_interno_somar(NEW.codigo, 'Tirado das observações do anúncio do site antigo (504): ' || s.interno);
    NEW.observacoes := s.publico;
  END IF;
  RETURN NEW;
END $f$;
DROP TRIGGER IF EXISTS imovel_ficha_sigilo_fora ON imovel_ficha;
CREATE TRIGGER imovel_ficha_sigilo_fora BEFORE INSERT OR UPDATE ON imovel_ficha
  FOR EACH ROW EXECUTE FUNCTION imovel_ficha_sigilo_fora();

-- a memória da Nay: negociação nem entra (vai para o Uso interno); o nome do dono entre parênteses cai
CREATE OR REPLACE FUNCTION public.imovel_conhecimento_sigilo_fora() RETURNS trigger
 LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public', 'privado' AS $f$
BEGIN
  IF nay_e_sigilo(coalesce(NEW.assunto, '') || ' ' || coalesce(NEW.texto, '')) THEN
    PERFORM privado.uso_interno_somar(NULLIF(regexp_replace(NEW.codigo, '\D', '', 'g'), '')::int,
              'Da memória da Nay (504) — ' || NEW.assunto || ': ' || NEW.texto || coalesce(' (' || NEW.quem_contou || ')', ''));
    RETURN NULL;
  END IF;
  NEW.texto := regexp_replace(NEW.texto, '((propriet|procurador)[a-zà-ú]*)\s*\([^)]*\)', '\1', 'gi');
  RETURN NEW;
END $f$;
DROP TRIGGER IF EXISTS imovel_conhecimento_sigilo_fora ON imovel_conhecimento;
CREATE TRIGGER imovel_conhecimento_sigilo_fora BEFORE INSERT OR UPDATE ON imovel_conhecimento
  FOR EACH ROW EXECUTE FUNCTION imovel_conhecimento_sigilo_fora();

-- e passa a trava, uma vez, no que já está na ficha do anúncio (ex.: 5694, "incluso os honorários de corretagem")
UPDATE imovel_ficha SET card = card
 WHERE nay_e_registro_interno(card) OR nay_e_sigilo(descricao) OR nay_e_sigilo(observacoes);

COMMENT ON COLUMN imoveis.observacao IS
  '344/504: o que vale o cliente saber (vista, o que fica, o que o aluguel inclui); vai no card. Negociação, comissão, valor líquido, nome do dono e aviso da equipe vão para Uso interno (privado.imovel_ficha.observacoes) -- o gatilho imoveis_sigilo_fora separa sozinho.';

COMMIT;
