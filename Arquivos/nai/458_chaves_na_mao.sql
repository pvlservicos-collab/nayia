-- 458: CHAVES NA MÃO, os imóveis no XML do portal e os leads que ele manda (Pedro, 21/10/2026).
--
-- Pedro: "veja como fazemos para integrar nossos imóveis no chaves na mão também igual olx" e, com a mensagem do
-- portal (documentação de imóveis e de leads): "veja tudo aí e deixe preparado".
--
-- COMO O PORTAL FUNCIONA (https://chavesnamao.github.io/xml-documentation/ e /lead-documentation/, lidas em 21/10):
--   IMÓVEIS: não há API. O portal LÊ um XML numa URL nossa (<Document><imoveis><imovel>...), uma vez por dia.
--            O que sai do arquivo sai do portal. Todas as tags vão, mesmo vazias; tipo e áreas com o nome EXATO da
--            lista deles. A API do site (nay-site-api, chavesnamao_api.py) serve o arquivo; quem decide o que vai e
--            como vai é cnm_imoveis() aqui.
--   LEADS:   o portal faz POST de um JSON numa URL nossa, com Authorization: Basic base64(email:token) do cliente
--            (o e-mail da conta e o "Token Integração de leads" de Meus Dados) e User-Agent chavesnamao-leads-api.
--            O id do lead é a chave: repetido responde 200 e não duplica. cnm_lead_receber() confere e guarda.
--
-- QUAIS IMÓVEIS: a mesma regra da OLX (olx_anuncios_candidatos): Disponível, no nosso site, nosso (não parceiro),
-- não bloqueado, com valor. Um <imovel> por código: venda e locação juntas (transacao V + transacao2 L).
--
-- A SENHA DOS LEADS fica em privado.cnm_config (lead_email, lead_token), NÃO no git. Sem ela (antes do contrato),
-- o lead entra marcado autenticado = false se vier com o User-Agent do portal: é assim que o lead de teste deles
-- passa antes de termos o token. Com ela, só entra quem manda o e-mail e o token certos.
--
-- Desfazer: DROP FUNCTION cnm_imoveis(), cnm_imovel_montar(int), cnm_areas(text[], text), cnm_norm(text),
-- cnm_lead_receber(jsonb, text, text, text); DROP TABLE privado.cnm_lead, privado.cnm_config, privado.cnm_area_apelido,
-- privado.cnm_area.

BEGIN;

-- ---------------------------------------------------------------- as listas oficiais de áreas (nomes exatos)
CREATE OR REPLACE FUNCTION public.cnm_norm(p text)
 RETURNS text LANGUAGE sql IMMUTABLE
AS $f$ SELECT btrim(regexp_replace(lower(nay_sem_acento(coalesce(p, ''))), '[^a-z0-9]+', ' ', 'g')) $f$;

CREATE TABLE privado.cnm_area (
  lista text NOT NULL CHECK (lista IN ('comum', 'privativa')),
  nome  text NOT NULL,                       -- como o portal escreve (vai no XML)
  chave text NOT NULL,                       -- cnm_norm(nome), para casar com o nosso cadastro
  PRIMARY KEY (lista, nome));
CREATE INDEX cnm_area_chave ON privado.cnm_area (lista, chave);
COMMENT ON TABLE privado.cnm_area IS '458: as listas oficiais do Chaves na Mão (chavesnamao.com.br/imoveis/integracao/areas_comuns e /areas_privativas, lidas em 21/10/2026).';

-- o nosso jeito de escrever -> o nome deles (o que não casa direto pelo cnm_norm)
CREATE TABLE privado.cnm_area_apelido (
  lista text NOT NULL CHECK (lista IN ('comum', 'privativa')),
  chave text NOT NULL,                       -- cnm_norm do nosso texto
  nome  text NOT NULL,
  PRIMARY KEY (lista, chave, nome));

INSERT INTO privado.cnm_area (lista, nome, chave)
SELECT v.lista, v.nome, cnm_norm(v.nome) FROM (VALUES
  ('comum', 'Academia'),
  ('comum', 'Aceita pet'),
  ('comum', 'Acessibilidade'),
  ('comum', 'Acesso a praia'),
  ('comum', 'Acesso com asfalto'),
  ('comum', 'Acesso com senha'),
  ('comum', 'Acesso com tag'),
  ('comum', 'Acesso de pedestres'),
  ('comum', 'Acesso de serviço'),
  ('comum', 'Acesso exclusivo para pet'),
  ('comum', 'Acesso exclusivo para praia'),
  ('comum', 'Acesso independente'),
  ('comum', 'Acesso para PNE'),
  ('comum', 'Administração airbnb'),
  ('comum', 'Água coletiva'),
  ('comum', 'Água Encanada'),
  ('comum', 'Alarme'),
  ('comum', 'Ambiente climatizado'),
  ('comum', 'Ambientes equipados e decorados'),
  ('comum', 'Amortecedores de impacto nas garagens'),
  ('comum', 'Ante sala'),
  ('comum', 'Antena coletiva'),
  ('comum', 'Antipó'),
  ('comum', 'Aquecedor central de passagem'),
  ('comum', 'Aquecimento'),
  ('comum', 'Aquecimento à gás'),
  ('comum', 'Aquecimento central'),
  ('comum', 'Aquecimento elétrico e a gás'),
  ('comum', 'Ar condicionado'),
  ('comum', 'Área comum equipada e decorada'),
  ('comum', 'Área de descanso'),
  ('comum', 'Área de jogos externo'),
  ('comum', 'Área de lazer'),
  ('comum', 'Área de manobra'),
  ('comum', 'Área de recreação'),
  ('comum', 'Área de serviço'),
  ('comum', 'Área para fumantes'),
  ('comum', 'Área para pets'),
  ('comum', 'Área preservada'),
  ('comum', 'Área verde'),
  ('comum', 'Área verde de preservação'),
  ('comum', 'Armário(s) planejados'),
  ('comum', 'Ateliê'),
  ('comum', 'Auditório'),
  ('comum', 'Banheiro(s)'),
  ('comum', 'Banheiro(s) PNE'),
  ('comum', 'Bar'),
  ('comum', 'Beautycare'),
  ('comum', 'Bebedouro'),
  ('comum', 'Berçário'),
  ('comum', 'Bicicletário'),
  ('comum', 'Bicicletas compartilhadas'),
  ('comum', 'Bike share'),
  ('comum', 'Biometria'),
  ('comum', 'Blocos com acesso facial'),
  ('comum', 'Boat houses'),
  ('comum', 'Boliche'),
  ('comum', 'Bosque'),
  ('comum', 'Box de garagem'),
  ('comum', 'Brinquedoteca'),
  ('comum', 'Bwc coletivo'),
  ('comum', 'BWC empregada'),
  ('comum', 'Cachoeira(s)'),
  ('comum', 'Calçada'),
  ('comum', 'Calçada em paver'),
  ('comum', 'Câmeras de segurança'),
  ('comum', 'Campo c/ grama sintética'),
  ('comum', 'Campo de futebol'),
  ('comum', 'Campo de futebol suíço'),
  ('comum', 'Campo de golfe'),
  ('comum', 'Campo de volley com grama natural'),
  ('comum', 'Campo futebol areia'),
  ('comum', 'Cancha de bocha'),
  ('comum', 'Captação de água da chuva'),
  ('comum', 'Captação de energia solar'),
  ('comum', 'Car Space'),
  ('comum', 'Carregador para carro elétrico'),
  ('comum', 'Carteado'),
  ('comum', 'Casa da zeladoria'),
  ('comum', 'Casa de boneca'),
  ('comum', 'Casa de caseiro'),
  ('comum', 'Casa do tarzan'),
  ('comum', 'Catraca de identificação'),
  ('comum', 'Cerca de vidro'),
  ('comum', 'Cerca elétrica'),
  ('comum', 'Cercado'),
  ('comum', 'Chafariz'),
  ('comum', 'Children care'),
  ('comum', 'Churrasqueira coletiva'),
  ('comum', 'Chuveiro (saída de praia)'),
  ('comum', 'Ciclovia no condomínio'),
  ('comum', 'Cinema'),
  ('comum', 'Circuito de caminhada'),
  ('comum', 'Circuito funcional'),
  ('comum', 'Circuito Interno de TV'),
  ('comum', 'Cisterna'),
  ('comum', 'Clube Náutico com lazer de spa'),
  ('comum', 'Coleta seletiva de lixo'),
  ('comum', 'Concierge 24 horas'),
  ('comum', 'Condomínio fechado'),
  ('comum', 'Coworking'),
  ('comum', 'Cozinha ampla'),
  ('comum', 'Cozinha com armário(s)'),
  ('comum', 'Cozinha compartilhada'),
  ('comum', 'Deck'),
  ('comum', 'Dependência de empregados'),
  ('comum', 'Depósito'),
  ('comum', 'Despensa'),
  ('comum', 'Dry wash car'),
  ('comum', 'Ducha'),
  ('comum', 'Eclusa de veículos'),
  ('comum', 'Eclusa social'),
  ('comum', 'Edícula com churrasqueira'),
  ('comum', 'Elevador panorâmico'),
  ('comum', 'Elevador para Carro'),
  ('comum', 'Elevador(es)'),
  ('comum', 'Elevador(es) com biometria'),
  ('comum', 'Elevador(es) com sistema regenerativo de energia'),
  ('comum', 'Elevador(es) de acesso PNE'),
  ('comum', 'Elevador(es) de serviço'),
  ('comum', 'Entrada em nível'),
  ('comum', 'Entrada lateral'),
  ('comum', 'Entrada p/ visitantes'),
  ('comum', 'Entrada para banhistas'),
  ('comum', 'Entrada social e de serviço'),
  ('comum', 'Espaço ao ar livre'),
  ('comum', 'Espaço Business'),
  ('comum', 'Espaço café'),
  ('comum', 'Espaço chimarrão'),
  ('comum', 'Espaço Coffee'),
  ('comum', 'Espaço cultural'),
  ('comum', 'Espaço de convivência'),
  ('comum', 'Espaço de descanso'),
  ('comum', 'Espaço de leitura'),
  ('comum', 'Espaço delivery'),
  ('comum', 'Espaço família'),
  ('comum', 'Espaço fitness'),
  ('comum', 'Espaço Garden'),
  ('comum', 'Espaço gourmet'),
  ('comum', 'Espaço infantil'),
  ('comum', 'Espaço jovem'),
  ('comum', 'Espaço kids'),
  ('comum', 'Espaço mulher'),
  ('comum', 'Espaço Náutico'),
  ('comum', 'Espaço para adolescentes'),
  ('comum', 'Espaço para artes'),
  ('comum', 'Espaço play'),
  ('comum', 'Espaço pub'),
  ('comum', 'Espaço redário'),
  ('comum', 'Espaço terceira idade'),
  ('comum', 'Espaço verde'),
  ('comum', 'Espaço web'),
  ('comum', 'Espaço zen'),
  ('comum', 'Espelho d''água'),
  ('comum', 'Esquadrias PVC'),
  ('comum', 'Estacionamento com sistema valet'),
  ('comum', 'Estacionamento para veículos'),
  ('comum', 'Estacionamento rotativo'),
  ('comum', 'Estar com pergolado'),
  ('comum', 'Estrutura completa de clube'),
  ('comum', 'Estúdio de música'),
  ('comum', 'Estúdio de pilates'),
  ('comum', 'Estufa'),
  ('comum', 'Face norte'),
  ('comum', 'Fechadura digital'),
  ('comum', 'Fireplace'),
  ('comum', 'Fogão'),
  ('comum', 'Fogão a lenha'),
  ('comum', 'Fonte de água'),
  ('comum', 'Forno a lenha'),
  ('comum', 'Forno elétrico'),
  ('comum', 'Forro rebaixado'),
  ('comum', 'Fraldário'),
  ('comum', 'Galeria águas pluviais'),
  ('comum', 'Galeria de Arte'),
  ('comum', 'Game center'),
  ('comum', 'Garagem automatizada'),
  ('comum', 'Garagem coberta'),
  ('comum', 'Garagem com pintura epóxi'),
  ('comum', 'Garagem de barco'),
  ('comum', 'Gás canalizado'),
  ('comum', 'Gás central'),
  ('comum', 'Gazebo'),
  ('comum', 'Gerador de energia'),
  ('comum', 'Gibiteca'),
  ('comum', 'Gradeado'),
  ('comum', 'Guarita'),
  ('comum', 'Guarita blindada'),
  ('comum', 'Hall com pé direito duplo'),
  ('comum', 'Hall com pé direito triplo'),
  ('comum', 'Hall de entrada decorado'),
  ('comum', 'Heliponto'),
  ('comum', 'Hidromassagem'),
  ('comum', 'Horta'),
  ('comum', 'Iluminação inteligente'),
  ('comum', 'Infraestrutura ar condicionado'),
  ('comum', 'Interfone'),
  ('comum', 'Internet predial'),
  ('comum', 'Isolamento acústico'),
  ('comum', 'Isolamento termoacústico'),
  ('comum', 'Jardim'),
  ('comum', 'Lago'),
  ('comum', 'Lan house'),
  ('comum', 'Lareira'),
  ('comum', 'Lareira externa'),
  ('comum', 'Lava car'),
  ('comum', 'Lava Pés'),
  ('comum', 'Lavanderia compartilhada'),
  ('comum', 'Living'),
  ('comum', 'Lounge'),
  ('comum', 'Luzes de emergência'),
  ('comum', 'Manobrista'),
  ('comum', 'Manta asfáltica na laje'),
  ('comum', 'Máquinas de venda automática'),
  ('comum', 'Marina para barcos'),
  ('comum', 'Market four you'),
  ('comum', 'Mata nativa'),
  ('comum', 'Medidor individual'),
  ('comum', 'Medidores individuais de gás e água'),
  ('comum', 'Mercado de conveniências'),
  ('comum', 'Mina d''água'),
  ('comum', 'Mini lago'),
  ('comum', 'Mirante'),
  ('comum', 'Multiplay'),
  ('comum', 'Murado'),
  ('comum', 'Muros em vidro'),
  ('comum', 'Observatório'),
  ('comum', 'Office center'),
  ('comum', 'Oficina'),
  ('comum', 'Ofurô'),
  ('comum', 'Painel fotovoltaico'),
  ('comum', 'Paisagismo'),
  ('comum', 'Parque gramado'),
  ('comum', 'Passa-volume para delivery'),
  ('comum', 'Patinetes elétricos compartilhados'),
  ('comum', 'Pátio para manobra'),
  ('comum', 'Pé direito duplo'),
  ('comum', 'Pé direito elevado'),
  ('comum', 'Pergolado coberto'),
  ('comum', 'Permitido pets'),
  ('comum', 'Personal trainer do condomínio'),
  ('comum', 'Pier'),
  ('comum', 'Pilotis'),
  ('comum', 'Piscina'),
  ('comum', 'Piscina aquecida'),
  ('comum', 'Piscina borda infinita'),
  ('comum', 'Piscina coberta'),
  ('comum', 'Piscina com bar'),
  ('comum', 'Piscina com hidromassagem'),
  ('comum', 'Piscina infantil'),
  ('comum', 'Piso anti ruído'),
  ('comum', 'Piso de ardósia'),
  ('comum', 'Piso de granito'),
  ('comum', 'Piso de madeira'),
  ('comum', 'Piso de mármore'),
  ('comum', 'Piso elevado'),
  ('comum', 'Piso laminado'),
  ('comum', 'Piso porcelanato'),
  ('comum', 'Piso Travertino'),
  ('comum', 'Pista de corrida/caminhada'),
  ('comum', 'Pista de patinação'),
  ('comum', 'Pista de skate'),
  ('comum', 'Playground'),
  ('comum', 'Pocket park'),
  ('comum', 'Poço'),
  ('comum', 'Pomar'),
  ('comum', 'Pool lounge'),
  ('comum', 'Port cocherè'),
  ('comum', 'Porta blindada'),
  ('comum', 'Portão'),
  ('comum', 'Portão basculante'),
  ('comum', 'Portão com eclusa'),
  ('comum', 'Portão eletrônico'),
  ('comum', 'Portaria'),
  ('comum', 'Portaria 24h'),
  ('comum', 'Portaria com acesso facial'),
  ('comum', 'Portaria com biometria'),
  ('comum', 'Portaria das 07:00h as 20:00h'),
  ('comum', 'Portaria das 7 as 23hs'),
  ('comum', 'Portaria remota'),
  ('comum', 'Portaria virtual'),
  ('comum', 'Portas anti impacto'),
  ('comum', 'Portas automatizadas'),
  ('comum', 'Porteiro eletrônico'),
  ('comum', 'Praça boulevard'),
  ('comum', 'Praça de convívio'),
  ('comum', 'Prédio pastilhado'),
  ('comum', 'Prédio sem elevador'),
  ('comum', 'Projeto de automação'),
  ('comum', 'Pulmão de segurança'),
  ('comum', 'Quadra com grama'),
  ('comum', 'Quadra com grama sintética'),
  ('comum', 'Quadra de areia'),
  ('comum', 'Quadra de beach tênis'),
  ('comum', 'Quadra de esporte'),
  ('comum', 'Quadra de futebol'),
  ('comum', 'Quadra de futebol de salão'),
  ('comum', 'Quadra de padel'),
  ('comum', 'Quadra de peteca'),
  ('comum', 'Quadra de pickleball'),
  ('comum', 'Quadra de tênis'),
  ('comum', 'Quadra poliesportiva'),
  ('comum', 'Quadra recreativa'),
  ('comum', 'Quadra squash'),
  ('comum', 'Quiosque com churrasqueira'),
  ('comum', 'Quiosque gourmet'),
  ('comum', 'Quiosque(s)'),
  ('comum', 'Rede de energia subterrânea'),
  ('comum', 'Rede de tratamento de esgoto'),
  ('comum', 'Refeitório'),
  ('comum', 'Reserva'),
  ('comum', 'Restaurante privativo'),
  ('comum', 'Reuso de águas pluviais'),
  ('comum', 'Riacho'),
  ('comum', 'Ronda/Vigilância'),
  ('comum', 'Sala de atendimento'),
  ('comum', 'Sala de beleza'),
  ('comum', 'Sala de entregas'),
  ('comum', 'Sala de estética'),
  ('comum', 'Sala de estudos'),
  ('comum', 'Sala de Eventos'),
  ('comum', 'Sala de ferramentas'),
  ('comum', 'Sala de filmes'),
  ('comum', 'Sala de ginástica'),
  ('comum', 'Sala de massagem'),
  ('comum', 'Sala de pilates'),
  ('comum', 'Sala de poker'),
  ('comum', 'Sala de recepção'),
  ('comum', 'Sala de tênis de mesa'),
  ('comum', 'Sala de TV'),
  ('comum', 'Sala de vídeo'),
  ('comum', 'Sala multimídia'),
  ('comum', 'Sala para funcionários'),
  ('comum', 'Sala reuniões'),
  ('comum', 'Sala yoga'),
  ('comum', 'Sala(s) de convenções'),
  ('comum', 'Salão com churrasqueira'),
  ('comum', 'Salão de festas'),
  ('comum', 'Salão de festas com churrasqueira'),
  ('comum', 'Salão de jogos'),
  ('comum', 'Salão de jogos com churrasqueira'),
  ('comum', 'Salão multiuso'),
  ('comum', 'Sauna'),
  ('comum', 'Segurança 24h'),
  ('comum', 'Segurança monitorada'),
  ('comum', 'Segurança veicular'),
  ('comum', 'Sensor de perímetro'),
  ('comum', 'Sensor de presença na área comum'),
  ('comum', 'Sensor de presença na garagem'),
  ('comum', 'SERVIÇO HOTELEIRO'),
  ('comum', 'Serviços pay per use'),
  ('comum', 'Sistema de câmeras'),
  ('comum', 'Sistema de captação de água'),
  ('comum', 'Sistema de clausura'),
  ('comum', 'Sistema de irrigação no jardim'),
  ('comum', 'Sistema de luz solar'),
  ('comum', 'Sistema de monitoramento'),
  ('comum', 'Sistema de prevenção de incêndio'),
  ('comum', 'Solárium'),
  ('comum', 'Som ambiente nas áreas comuns'),
  ('comum', 'Spa'),
  ('comum', 'Sport lounge'),
  ('comum', 'Taberna'),
  ('comum', 'Tanque para peixe'),
  ('comum', 'Telhado verde'),
  ('comum', 'Terraço'),
  ('comum', 'Terraço com churrasqueira'),
  ('comum', 'Terraço com jacuzzi'),
  ('comum', 'Terraço garden'),
  ('comum', 'Teto em gesso'),
  ('comum', 'Teto rebaixado'),
  ('comum', 'Tomada para bicicleta elétrica'),
  ('comum', 'Trapiche'),
  ('comum', 'Trilha para caminhar'),
  ('comum', 'Vaga carga e descarga'),
  ('comum', 'Vaga de embarque'),
  ('comum', 'Vaga para Cadeirante'),
  ('comum', 'Vaga(s) de garagem'),
  ('comum', 'Vaga(s) para motos'),
  ('comum', 'Vaga(s) para visitantes'),
  ('comum', 'Vagas de garagem acessíveis'),
  ('comum', 'Varal Coletivo'),
  ('comum', 'Vestiário'),
  ('comum', 'Via de desaceleração'),
  ('comum', 'Vista para o mar'),
  ('comum', 'Wi-fi'),
  ('comum', 'Workspace'),
  ('comum', 'Xadrez gigante'),
  ('comum', 'Zelador')
) AS v(lista, nome);

INSERT INTO privado.cnm_area (lista, nome, chave)
SELECT v.lista, v.nome, cnm_norm(v.nome) FROM (VALUES
  ('privativa', '2° piso'),
  ('privativa', 'Acabamento em alto padrão'),
  ('privativa', 'Acabamento em mármore'),
  ('privativa', 'Academia'),
  ('privativa', 'Aceita Pet'),
  ('privativa', 'Acesso de serviço'),
  ('privativa', 'Acesso independente'),
  ('privativa', 'Acesso PNE'),
  ('privativa', 'Açude'),
  ('privativa', 'Adega'),
  ('privativa', 'Alarme'),
  ('privativa', 'Ambiente climatizado'),
  ('privativa', 'Ambiente(s) amplo(s)'),
  ('privativa', 'Ambientes integrados'),
  ('privativa', 'Ante sala'),
  ('privativa', 'Aquecedor'),
  ('privativa', 'Aquecedor à gás'),
  ('privativa', 'Aquecedor de passagem'),
  ('privativa', 'Aquecedor elétrico'),
  ('privativa', 'Aquecimento a gás'),
  ('privativa', 'Ar Condicionado'),
  ('privativa', 'Área de carga e descarga'),
  ('privativa', 'Área de circulação'),
  ('privativa', 'Área de descanso'),
  ('privativa', 'Área de estar coberta'),
  ('privativa', 'Área de fogueira'),
  ('privativa', 'Área de lazer'),
  ('privativa', 'Área de serviço'),
  ('privativa', 'Área de serviço ampla'),
  ('privativa', 'Área de serviço com armários'),
  ('privativa', 'Área de serviço com banheiro'),
  ('privativa', 'Área de serviço com depósito'),
  ('privativa', 'Área externa'),
  ('privativa', 'Área externa coberta'),
  ('privativa', 'Área técnica'),
  ('privativa', 'Armário(s) embutido(s)'),
  ('privativa', 'Armário(s) planejado(s)'),
  ('privativa', 'Árvores frutíferas'),
  ('privativa', 'Ático'),
  ('privativa', 'Ático com banheiro'),
  ('privativa', 'Ático com lareira'),
  ('privativa', 'Auditório'),
  ('privativa', 'Automatizada'),
  ('privativa', 'Baias de cavalo'),
  ('privativa', 'Bancada'),
  ('privativa', 'Banheira'),
  ('privativa', 'Banheiro amplo'),
  ('privativa', 'Banheiro auxiliar'),
  ('privativa', 'Banheiro boudoir'),
  ('privativa', 'Banheiro com box blindex'),
  ('privativa', 'Banheiro com chuveiro duplo'),
  ('privativa', 'Banheiro com cuba dupla'),
  ('privativa', 'Banheiro com ducha dupla'),
  ('privativa', 'Banheiro com hidromassagem'),
  ('privativa', 'Banheiro com sauna'),
  ('privativa', 'Banheiro funcionária(o)'),
  ('privativa', 'Banheiro Masculino e Feminino'),
  ('privativa', 'Banheiro PNE'),
  ('privativa', 'Banheiro social'),
  ('privativa', 'Banheiro(s) com armário(s)'),
  ('privativa', 'Bar molhado'),
  ('privativa', 'Biblioteca'),
  ('privativa', 'Bicicletário'),
  ('privativa', 'Biometria'),
  ('privativa', 'Blackout nas janelas'),
  ('privativa', 'Box de praia'),
  ('privativa', 'Box no banheiro'),
  ('privativa', 'Brinquedoteca'),
  ('privativa', 'Bwc Sr.'),
  ('privativa', 'Bwc Sr. e Sra.'),
  ('privativa', 'Bwc Sra.'),
  ('privativa', 'Cachoeira'),
  ('privativa', 'Câmara fria'),
  ('privativa', 'Câmeras de monitoramento'),
  ('privativa', 'Câmeras de segurança'),
  ('privativa', 'Campo de futebol'),
  ('privativa', 'Campo de gramado'),
  ('privativa', 'Canil'),
  ('privativa', 'Captação de água da chuva'),
  ('privativa', 'Carpete'),
  ('privativa', 'Carregador para carro elétrico'),
  ('privativa', 'Casa na árvore'),
  ('privativa', 'Casa nos fundos'),
  ('privativa', 'Casa para caseiro'),
  ('privativa', 'Casa para funcionários'),
  ('privativa', 'Casa para hóspede'),
  ('privativa', 'Casa sede'),
  ('privativa', 'Casa térrea'),
  ('privativa', 'Celeiro'),
  ('privativa', 'Chalé'),
  ('privativa', 'Churrasqueira'),
  ('privativa', 'Churrasqueira a carvão'),
  ('privativa', 'Churrasqueira Exclusiva'),
  ('privativa', 'Churrasqueira integrada na cozinha'),
  ('privativa', 'Chuveiro externo'),
  ('privativa', 'Circuito Interno TV'),
  ('privativa', 'Cisterna'),
  ('privativa', 'Clarabóia'),
  ('privativa', 'Closet'),
  ('privativa', 'Closet Sr.'),
  ('privativa', 'Closet Sr. e Closet Sra.'),
  ('privativa', 'Closet Sra.'),
  ('privativa', 'Cobertura com vidro retrátil'),
  ('privativa', 'Conceito aberto'),
  ('privativa', 'Contra-piso'),
  ('privativa', 'Copa'),
  ('privativa', 'Copa com armário(s)'),
  ('privativa', 'Corredor com armário'),
  ('privativa', 'Corredor lateral'),
  ('privativa', 'Corrimão aço inox'),
  ('privativa', 'Cortina(s)'),
  ('privativa', 'Cortinas automatizadas'),
  ('privativa', 'Cozinha'),
  ('privativa', 'Cozinha americana'),
  ('privativa', 'Cozinha ampla'),
  ('privativa', 'Cozinha com área de serviço integrada'),
  ('privativa', 'Cozinha com armário(s)'),
  ('privativa', 'Cozinha com Ilha'),
  ('privativa', 'Cozinha com passa prato'),
  ('privativa', 'Cozinha com refeitório'),
  ('privativa', 'Cozinha conceito aberto'),
  ('privativa', 'Cozinha conjugada'),
  ('privativa', 'Cozinha em porcelanato e bancada em granito'),
  ('privativa', 'Cozinha equipada'),
  ('privativa', 'Cozinha gourmet'),
  ('privativa', 'Cozinha independente'),
  ('privativa', 'Cozinha Industrial'),
  ('privativa', 'Cozinha planejada'),
  ('privativa', 'Cozinha revestida em cerâmica'),
  ('privativa', 'Cuba de mármore'),
  ('privativa', 'Cuba de vidro'),
  ('privativa', 'Curral'),
  ('privativa', 'Deck'),
  ('privativa', 'Decorado'),
  ('privativa', 'Demi suíte'),
  ('privativa', 'Dependência de empregada'),
  ('privativa', 'Dependência para funcionários'),
  ('privativa', 'Depósito'),
  ('privativa', 'Depósito privado na garagem'),
  ('privativa', 'Despensa'),
  ('privativa', 'Dormitório para hóspedes'),
  ('privativa', 'Ducha'),
  ('privativa', 'Ducha higiênica'),
  ('privativa', 'Edícula'),
  ('privativa', 'Edícula com churrasqueira'),
  ('privativa', 'Eletrodomésticos'),
  ('privativa', 'Elevador com digital'),
  ('privativa', 'Elevador delivery'),
  ('privativa', 'Elevador privativo'),
  ('privativa', 'Elevador(es)'),
  ('privativa', 'Entrada de serviço'),
  ('privativa', 'Entrada independente'),
  ('privativa', 'Entrada social'),
  ('privativa', 'Equipamento de aquecimento'),
  ('privativa', 'Escada em granito'),
  ('privativa', 'Escada em madeira'),
  ('privativa', 'Escada em mármore'),
  ('privativa', 'Escadaria'),
  ('privativa', 'Escritório'),
  ('privativa', 'Espaço de bar'),
  ('privativa', 'Espaço funcional'),
  ('privativa', 'Espaço gourmet'),
  ('privativa', 'Espelho d''água'),
  ('privativa', 'Esquadrias automatizadas'),
  ('privativa', 'Esquadrias de alumínio'),
  ('privativa', 'Esquadrias de madeira'),
  ('privativa', 'Esquadrilhas PVC'),
  ('privativa', 'Esquina'),
  ('privativa', 'Estação de gás'),
  ('privativa', 'Estacionamento'),
  ('privativa', 'Estrebaria'),
  ('privativa', 'Estúdio de musica'),
  ('privativa', 'Estufa'),
  ('privativa', 'Fechadura biométrica'),
  ('privativa', 'Fechadura digital'),
  ('privativa', 'Fogão a lenha'),
  ('privativa', 'Fogão cook top'),
  ('privativa', 'Fonte com lago'),
  ('privativa', 'Forno a lenha'),
  ('privativa', 'Forno elétrico'),
  ('privativa', 'Forro de madeira'),
  ('privativa', 'Forro em drywall'),
  ('privativa', 'Forro em gesso'),
  ('privativa', 'Forro em PVC'),
  ('privativa', 'Forro rebaixado'),
  ('privativa', 'forro térmico'),
  ('privativa', 'Galinheiro'),
  ('privativa', 'Garden'),
  ('privativa', 'Garden com churrasqueira'),
  ('privativa', 'Gerador'),
  ('privativa', 'Gradeado'),
  ('privativa', 'Gradil'),
  ('privativa', 'Guarita'),
  ('privativa', 'Guarita com segurança'),
  ('privativa', 'Hall com pé direito duplo'),
  ('privativa', 'Hall de entrada'),
  ('privativa', 'Hall de entrada decorado'),
  ('privativa', 'Heliporto'),
  ('privativa', 'Hidromassagem'),
  ('privativa', 'Hobby box'),
  ('privativa', 'Home theater'),
  ('privativa', 'Horta'),
  ('privativa', 'Iluminação automatizada'),
  ('privativa', 'Iluminação em LED'),
  ('privativa', 'Iluminação natural'),
  ('privativa', 'Infraestrutura de ar condicionado'),
  ('privativa', 'Infraestrutura para aquecedor'),
  ('privativa', 'Infraestrutura para aspiração central'),
  ('privativa', 'Infraestrutura para automação'),
  ('privativa', 'Infraestrutura para coifa'),
  ('privativa', 'Infraestrutura para desembaçador de espelho'),
  ('privativa', 'Infraestrutura para elevador'),
  ('privativa', 'Infraestrutura para persianas'),
  ('privativa', 'Infraestrutura para sauna'),
  ('privativa', 'Infraestrutura para som'),
  ('privativa', 'Infraestrutura para toalheiro elétrico'),
  ('privativa', 'Internet'),
  ('privativa', 'Interruptores Touch'),
  ('privativa', 'Isento condomínio'),
  ('privativa', 'Isolamento acústico'),
  ('privativa', 'Jacuzzi'),
  ('privativa', 'Janela automatizada'),
  ('privativa', 'Janela bay window'),
  ('privativa', 'Janela de PVC'),
  ('privativa', 'Janela em madeira'),
  ('privativa', 'Janelas amplas'),
  ('privativa', 'Janelas amplas com persiana de enrolar'),
  ('privativa', 'Janelas antirruído'),
  ('privativa', 'Janelas com persianas elétricas'),
  ('privativa', 'Janelas em alumínio'),
  ('privativa', 'Jardim'),
  ('privativa', 'Jardim de Inverno'),
  ('privativa', 'Jardim gramado'),
  ('privativa', 'Jardim suspenso'),
  ('privativa', 'Lago'),
  ('privativa', 'Lagoa para pesca'),
  ('privativa', 'Lareira'),
  ('privativa', 'Lavabo'),
  ('privativa', 'Lavabo com piso aquecido'),
  ('privativa', 'Lavanderia'),
  ('privativa', 'Lavanderia com água aquecida no tanque'),
  ('privativa', 'Lavanderia com armário(s) planejado(s)'),
  ('privativa', 'Living amplo'),
  ('privativa', 'Lounge'),
  ('privativa', 'Lounge com churrasqueira'),
  ('privativa', 'Lounge gourmet'),
  ('privativa', 'Lustre'),
  ('privativa', 'Manobrista'),
  ('privativa', 'Garagem'),
  ('privativa', 'Manta acústica na laje'),
  ('privativa', 'Medidor individual'),
  ('privativa', 'Meio de quadra'),
  ('privativa', 'Metais de alto padrão'),
  ('privativa', 'Mezanino'),
  ('privativa', 'Mezanino com escritório'),
  ('privativa', 'Mobiliado'),
  ('privativa', 'Monta carga'),
  ('privativa', 'Móveis assinados'),
  ('privativa', 'Móveis planejados'),
  ('privativa', 'Murado'),
  ('privativa', 'Muro de vidro'),
  ('privativa', 'Nicho esculpido no banheiro'),
  ('privativa', 'Ofurô'),
  ('privativa', 'Olho d''água'),
  ('privativa', 'Painel solar'),
  ('privativa', 'Paisagismo'),
  ('privativa', 'Papel de parede'),
  ('privativa', 'Parede reflexiva de vidro'),
  ('privativa', 'Paredes com isolamento'),
  ('privativa', 'Paredes duplas'),
  ('privativa', 'Pátio'),
  ('privativa', 'Pátio de serviço'),
  ('privativa', 'Pé direito alto'),
  ('privativa', 'Pé direito duplo'),
  ('privativa', 'Pé direito duplo na sala'),
  ('privativa', 'Pergolado'),
  ('privativa', 'Persiana(s)'),
  ('privativa', 'Persianas com blackout'),
  ('privativa', 'Persianas elétricas'),
  ('privativa', 'Pintura acrílica'),
  ('privativa', 'Piscina'),
  ('privativa', 'Piscina aquecida'),
  ('privativa', 'Piscina coberta'),
  ('privativa', 'piscina e sauna privativa'),
  ('privativa', 'Piscina infantil'),
  ('privativa', 'Piso aquecido'),
  ('privativa', 'Piso ardósia'),
  ('privativa', 'Piso de cerâmica'),
  ('privativa', 'Piso de concreto polido'),
  ('privativa', 'Piso de granito'),
  ('privativa', 'Piso de madeira'),
  ('privativa', 'Piso de madeira laminada'),
  ('privativa', 'Piso de mármore'),
  ('privativa', 'piso de tábua'),
  ('privativa', 'Piso elevado'),
  ('privativa', 'Piso em parquet'),
  ('privativa', 'Piso emborrachado'),
  ('privativa', 'Piso frio'),
  ('privativa', 'Piso laminado'),
  ('privativa', 'Piso porcelanato'),
  ('privativa', 'Piso taco de madeira'),
  ('privativa', 'Piso Travertino'),
  ('privativa', 'Piso vinílico'),
  ('privativa', 'Pista de cooper'),
  ('privativa', 'Pista de pouso'),
  ('privativa', 'Pista de skate'),
  ('privativa', 'Pizza grill'),
  ('privativa', 'Planta flexível'),
  ('privativa', 'Playground'),
  ('privativa', 'Poço'),
  ('privativa', 'Ponto de água quente'),
  ('privativa', 'Ponto de carregamento carro elétrico individual'),
  ('privativa', 'Ponto para triturador pia cozinha'),
  ('privativa', 'Ponto para TV no banheiro'),
  ('privativa', 'Porão'),
  ('privativa', 'Porcelanato acetinado'),
  ('privativa', 'Porta maciça'),
  ('privativa', 'Porta pivotante'),
  ('privativa', 'Portão'),
  ('privativa', 'Portão automático'),
  ('privativa', 'Portaria remota'),
  ('privativa', 'Portas antiruído'),
  ('privativa', 'Portas com borracha amortecedora'),
  ('privativa', 'Portas em laca'),
  ('privativa', 'Potencial construtivo'),
  ('privativa', 'Previsão para elevador'),
  ('privativa', 'Projeto de iluminação'),
  ('privativa', 'Quadra beach tennis'),
  ('privativa', 'Quadra de squash'),
  ('privativa', 'Quadra de tênis'),
  ('privativa', 'Quadra esportiva'),
  ('privativa', 'Quarto(s) amplo(s)'),
  ('privativa', 'Quarto(s) com ar condicionado'),
  ('privativa', 'Quarto(s) com armário(s)'),
  ('privativa', 'Quarto(s) com banheira'),
  ('privativa', 'Quarto(s) com closet'),
  ('privativa', 'Quarto(s) com piso laminado'),
  ('privativa', 'Quarto(s) com sacada'),
  ('privativa', 'Quarto(s) de solteiro'),
  ('privativa', 'Quarto(s) mobiliado'),
  ('privativa', 'Quintal'),
  ('privativa', 'Quintal com paisagismo'),
  ('privativa', 'Rebaixamento em gesso'),
  ('privativa', 'Recepção'),
  ('privativa', 'Reconhecimento facial'),
  ('privativa', 'Rede tela de proteção nas janelas'),
  ('privativa', 'Reflorestamento'),
  ('privativa', 'Reformado'),
  ('privativa', 'Reserva nativa'),
  ('privativa', 'Riacho'),
  ('privativa', 'Rodapé de madeira'),
  ('privativa', 'Rodapé em laca'),
  ('privativa', 'Rodapé em porcelanato'),
  ('privativa', 'Rodapés em poliestireno'),
  ('privativa', 'Sacada'),
  ('privativa', 'Sacada com churrasqueira'),
  ('privativa', 'Sacada com vista panorâmica'),
  ('privativa', 'Sacada envidraçada'),
  ('privativa', 'Sala ampla'),
  ('privativa', 'Sala ampla para 2 ambientes'),
  ('privativa', 'Sala ampla para 3 ambientes'),
  ('privativa', 'Sala ampla para 4 ambientes'),
  ('privativa', 'Sala ampla para 6 ambientes'),
  ('privativa', 'Sala c/ isolamento acústico'),
  ('privativa', 'Sala com armário(s)'),
  ('privativa', 'Sala com sacada'),
  ('privativa', 'Sala conjugada com cozinha'),
  ('privativa', 'Sala de cinema'),
  ('privativa', 'Sala de estar'),
  ('privativa', 'Sala de estar ampla'),
  ('privativa', 'Sala de estar com bar'),
  ('privativa', 'Sala de estar e jantar amplas'),
  ('privativa', 'Sala de estudo'),
  ('privativa', 'Sala de jantar'),
  ('privativa', 'Sala de jantar com churrasqueira'),
  ('privativa', 'Sala de jogos'),
  ('privativa', 'Sala de leitura'),
  ('privativa', 'Sala de massagem'),
  ('privativa', 'Sala de pilates'),
  ('privativa', 'Sala de pintura'),
  ('privativa', 'Sala de sinuca'),
  ('privativa', 'Sala de TV'),
  ('privativa', 'Sala de vinho'),
  ('privativa', 'Sala intima'),
  ('privativa', 'Sala mobiliada'),
  ('privativa', 'Sala(s) ampla'),
  ('privativa', 'Sala(s) de reunião'),
  ('privativa', 'Salão de festas privativo'),
  ('privativa', 'Sanca em gesso'),
  ('privativa', 'Sauna'),
  ('privativa', 'Sauna e hidromassagem'),
  ('privativa', 'Semi suítes'),
  ('privativa', 'Semimobiliado'),
  ('privativa', 'Serviço de quarto'),
  ('privativa', 'Sistema de aproveitamento de água'),
  ('privativa', 'Sistema de aquecimento'),
  ('privativa', 'Sistema de aquecimento solar'),
  ('privativa', 'Sistema de geração de energia fotovoltaica'),
  ('privativa', 'Sistema de irrigação'),
  ('privativa', 'Sistema de pressurização'),
  ('privativa', 'Sistema de prevenção de incêndio'),
  ('privativa', 'Sistema de segurança'),
  ('privativa', 'Sistema de som'),
  ('privativa', 'Sótão'),
  ('privativa', 'Spa'),
  ('privativa', 'Suíte com armário(s) planejado'),
  ('privativa', 'Suíte com closet'),
  ('privativa', 'Suíte com closet e banheira'),
  ('privativa', 'Suíte com closet e hidromassagem'),
  ('privativa', 'Suíte com lareira'),
  ('privativa', 'Suíte com sacada'),
  ('privativa', 'Suíte master'),
  ('privativa', 'Suíte master com closet'),
  ('privativa', 'Suíte master com hidromassagem'),
  ('privativa', 'Suíte(s)'),
  ('privativa', 'Tampo de granito'),
  ('privativa', 'Tanque de lavar roupa'),
  ('privativa', 'Tanque de louça'),
  ('privativa', 'Tanque de peixe'),
  ('privativa', 'Telha galvanizada'),
  ('privativa', 'Telhado shingle'),
  ('privativa', 'Telhas de policarbonato'),
  ('privativa', 'Telhas em cimento'),
  ('privativa', 'Terraço'),
  ('privativa', 'Terraço com churrasqueira'),
  ('privativa', 'Terraço com cobertura retrátil'),
  ('privativa', 'Terraço com hidromassagem'),
  ('privativa', 'Terraço com piscina'),
  ('privativa', 'Teto em gesso'),
  ('privativa', 'Teto em madeira'),
  ('privativa', 'Teto retrátil'),
  ('privativa', 'Teto retrátil automatizado'),
  ('privativa', 'Tirolesa'),
  ('privativa', 'Toalheiro elétrico'),
  ('privativa', 'Tomada para veículo elétrico'),
  ('privativa', 'Tomadas USB'),
  ('privativa', 'Transformador'),
  ('privativa', 'Triplex'),
  ('privativa', 'Turismo rural'),
  ('privativa', 'TV a cabo'),
  ('privativa', 'Vaga(s) de garagem'),
  ('privativa', 'Vaga(s) de garagem coberta'),
  ('privativa', 'Vaga(s) de garagem descoberta'),
  ('privativa', 'Vaga(s) de garagem rotativa'),
  ('privativa', 'Vaga(s) para visitantes'),
  ('privativa', 'Varanda'),
  ('privativa', 'Varanda com churrasqueira'),
  ('privativa', 'Varanda com jacuzzi'),
  ('privativa', 'Varanda com piscina'),
  ('privativa', 'Varanda gourmet'),
  ('privativa', 'Venezianas integradas as janelas'),
  ('privativa', 'Ventilação natural'),
  ('privativa', 'Ventilador de teto'),
  ('privativa', 'Vestiário'),
  ('privativa', 'Vestiário feminino'),
  ('privativa', 'Vestiário masculino'),
  ('privativa', 'Vidros de alta qualidade'),
  ('privativa', 'Vidros termo acústico'),
  ('privativa', 'Vista panorâmica'),
  ('privativa', 'Vista para o mar'),
  ('privativa', 'Vista permanente'),
  ('privativa', 'Viveiro'),
  ('privativa', 'Wi-fi')
) AS v(lista, nome);

INSERT INTO privado.cnm_area_apelido (lista, chave, nome)
SELECT a.lista, cnm_norm(a.de), a.para FROM (VALUES
  -- as características do imóvel (imoveis.caracteristicas, mobília)
  ('privativa', 'Semi-Mobiliado', 'Semimobiliado'),
  ('privativa', 'Climatizado', 'Ar Condicionado'),
  ('privativa', 'Armários na cozinha', 'Cozinha com armário(s)'),
  ('privativa', 'Armários no quarto', 'Quarto(s) com armário(s)'),
  ('privativa', 'Apartamento em conceito aberto', 'Conceito aberto'),
  ('privativa', 'Varanda integrada a cozinha', 'Varanda'),
  ('privativa', 'Varanda com cortina de vidro', 'Sacada envidraçada'),
  ('privativa', 'Área murada', 'Murado'),
  ('privativa', 'Quarto de serviço', 'Dependência de empregada'),
  ('privativa', 'Fechadura eletrônica', 'Fechadura digital'),
  ('privativa', 'Elevador', 'Elevador(es)'),
  ('privativa', 'Câmera de segurança', 'Câmeras de segurança'),
  ('privativa', 'Portão eletrônico', 'Portão automático'),
  -- o lazer, a segurança e as comodidades do condomínio (condominio_ficha)
  ('comum', 'Churrasqueira', 'Churrasqueira coletiva'),
  ('comum', 'Churrasqueiras', 'Churrasqueira coletiva'),
  ('comum', 'Quiosques integrados com churrasqueira', 'Quiosque com churrasqueira'),
  ('comum', 'Estacionamento para visitantes', 'Vaga(s) para visitantes'),
  ('comum', 'Guarita 24 Horas', 'Guarita'),
  ('comum', 'Guarita 24 Horas', 'Segurança 24h'),
  ('comum', 'Guarita de segurança', 'Guarita'),
  ('comum', 'Portaria 24 horas', 'Portaria 24h'),
  ('comum', 'Portaria com Segurança 24 Horas', 'Portaria 24h'),
  ('comum', 'Portaria com Segurança 24 Horas', 'Segurança 24h'),
  ('comum', 'Segurança 24 horas', 'Segurança 24h'),
  ('comum', 'Acesso para deficientes', 'Acesso para PNE'),
  ('comum', 'Gás Encanado', 'Gás canalizado'),
  ('comum', 'Água de Poço', 'Poço'),
  ('comum', 'Poço artesiano', 'Poço'),
  ('comum', 'Piscina adulto e infantil', 'Piscina'),
  ('comum', 'Piscina adulto e infantil', 'Piscina infantil'),
  ('comum', 'Piscina adulto e infantil com solarium', 'Piscina'),
  ('comum', 'Piscina adulto e infantil com solarium', 'Piscina infantil'),
  ('comum', 'Piscina adulto e infantil com solarium', 'Solárium'),
  ('comum', 'Piscina adulto', 'Piscina'),
  ('comum', 'Piscina para adulto', 'Piscina'),
  ('comum', 'Gerador 100%', 'Gerador de energia'),
  ('comum', 'Gerador', 'Gerador de energia'),
  ('comum', 'Fitness', 'Espaço fitness'),
  ('comum', 'Espaço fitness/academia equipada', 'Academia'),
  ('comum', 'Redário', 'Espaço redário'),
  ('comum', 'Redário sob árvores preservadas', 'Espaço redário'),
  ('comum', 'Quadra', 'Quadra de esporte'),
  ('comum', 'Pet Place', 'Área para pets'),
  ('comum', 'Espaço Pet dedicado', 'Área para pets'),
  ('comum', 'Praça', 'Praça de convívio'),
  ('comum', 'Pista de Caminhada', 'Pista de corrida/caminhada'),
  ('comum', 'Trilhas exclusivas para caminhada ecológica', 'Trilha para caminhar'),
  ('comum', 'Quadra de squash', 'Quadra squash'),
  ('comum', 'Elevador', 'Elevador(es)'),
  ('comum', 'Elevadores', 'Elevador(es)'),
  ('comum', 'Playground infantil', 'Playground'),
  ('comum', 'Salão de festas mobiliado', 'Salão de festas'),
  ('comum', 'Câmera de segurança', 'Câmeras de segurança'),
  ('comum', 'Central de lazer com Wi-Fi livre', 'Wi-fi')
) AS a(lista, de, para)
WHERE EXISTS (SELECT 1 FROM privado.cnm_area x WHERE x.lista = a.lista AND x.nome = a.para)
ON CONFLICT DO NOTHING;

-- os nomes do portal para uma lista de textos nossos, sem repetir, na ordem em que vieram
CREATE OR REPLACE FUNCTION public.cnm_areas(p_itens text[], p_lista text)
 RETURNS text[] LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public'
AS $f$
  WITH x AS (SELECT cnm_norm(t) AS k, n FROM unnest(coalesce(p_itens, '{}')) WITH ORDINALITY u(t, n)),
       m AS (SELECT a.nome, x.n FROM x JOIN privado.cnm_area a ON a.lista = p_lista AND a.chave = x.k
             UNION ALL
             SELECT p.nome, x.n FROM x JOIN privado.cnm_area_apelido p ON p.lista = p_lista AND p.chave = x.k)
  SELECT coalesce(array_agg(z.nome ORDER BY z.n, z.nome), '{}')
    FROM (SELECT nome, min(n) AS n FROM m GROUP BY nome) z
$f$;

-- ---------------------------------------------------------------- um imóvel como o portal pede
CREATE OR REPLACE FUNCTION public.cnm_imovel_montar(p_codigo integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  i        imoveis;
  cf       condominio_ficha;
  v_t      text;
  v_fin    text;                 -- RE ou CO
  v_tipo   text;                 -- o nome do tipo na lista do portal
  v_rot    text;                 -- o tipo como vai no título
  v_falta  text[] := '{}';
  v_venda  numeric;
  v_aluga  numeric;
  v_cep    text;
  v_fotos  jsonb;
  v_priv   text[];
  v_comum  text[];
  v_resto  text[];
  v_mob    text;
  v_cond   text;
  v_neg    text;
  v_tit    text;
  v_desc   text;
  v_pet    boolean;
  v_casa   boolean;
BEGIN
  SELECT * INTO i FROM imoveis WHERE codigo = p_codigo;
  IF i.codigo IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'falta', jsonb_build_array('o imóvel não está no cadastro'));
  END IF;
  v_venda := nullif(coalesce(i.valor_venda, 0), 0);
  v_aluga := nullif(coalesce(i.valor_aluguel, 0), 0);

  -- quem não vai (a mesma regra da OLX)
  IF i.status IS DISTINCT FROM 'Disponível' OR NOT coalesce(i.disponivel, false) THEN v_falta := v_falta || ('não está Disponível (' || coalesce(i.status, 'sem situação') || ')'); END IF;
  IF NOT coalesce(i.publicado_no_site, false) THEN v_falta := v_falta || 'fora do nosso site'::text; END IF;
  IF coalesce(i.e_parceiro, false) THEN v_falta := v_falta || 'imóvel de parceiro'::text; END IF;
  IF coalesce(i.bloqueado, false) THEN v_falta := v_falta || 'bloqueado'::text; END IF;
  IF v_venda IS NULL AND v_aluga IS NULL THEN v_falta := v_falta || 'sem valor de venda nem de aluguel'::text; END IF;

  -- o tipo: a lista do portal (residencial.html e comercial.html), com acento e espaço exatos
  v_t := lower(nay_sem_acento(coalesce(i.tipo, '')));
  v_casa := v_t ~ '^(casa|sobrado)';
  SELECT t.fin, t.tipo, t.rot INTO v_fin, v_tipo, v_rot FROM (VALUES
      (1, v_t ~ '^cobertura' OR (v_t ~ '^apartamento' AND coalesce(i.cobertura, false)), 'RE', 'Cobertura', 'Cobertura'),
      (2, v_t ~ '^apartamento', 'RE', 'Apartamento', 'Apartamento'),
      (3, v_t ~ '^flat', 'RE', 'Flat', 'Flat'),
      (4, v_t ~ '^(kitnet|kitinete|kit |studio|estudio|stúdio)', 'RE', 'Kitnet / Stúdio', 'Kitnet'),
      (5, v_t ~ '^loft', 'RE', 'Loft', 'Loft'),
      (6, v_casa AND v_t ~ 'condominio', 'RE', 'Casa / Sobrado em Condomínio', 'Casa em condomínio'),
      (7, v_casa, 'RE', 'Casa / Sobrado', 'Casa'),
      (8, v_t ~ '^(lote|terreno)' AND v_t ~ 'condominio', 'RE', 'Terreno em Condomínio', 'Terreno em condomínio'),
      (9, v_t ~ '^(lote|terreno|area)', 'RE', 'Terreno / Lote', 'Terreno'),
      (10, v_t ~ '^(sitio|chacara)', 'RE', 'Sítio / Chácara', 'Sítio'),
      (11, v_t ~ '^fazenda', 'CO', 'Fazenda', 'Fazenda'),
      (12, v_t ~ '^(sala|andar|conjunto)', 'CO', 'Conj. Comercial / Sala', 'Sala comercial'),
      (13, v_t ~ '^(loja|ponto)', 'CO', 'Loja / Comércio', 'Loja'),
      (14, v_t ~ '^(galpao|deposito|barracao)', 'CO', 'Barracão / Galpão', 'Galpão'),
      (15, v_t ~ '^(predio|edificio)', 'CO', 'Edifício', 'Prédio'),
      (16, v_t ~ '^consultorio', 'CO', 'Consultório', 'Consultório'),
      (17, v_t ~ '^garagem', 'CO', 'Garagem', 'Garagem')
    ) AS t(ordem, vale, fin, tipo, rot)
   WHERE t.vale ORDER BY t.ordem LIMIT 1;
  IF v_tipo IS NULL THEN
    v_falta := v_falta || ('tipo sem par no Chaves na Mão (' || coalesce(nullif(btrim(i.tipo), ''), 'sem tipo') || ')');
  END IF;
  IF nullif(btrim(coalesce(i.bairro, '')), '') IS NULL THEN v_falta := v_falta || 'sem bairro'::text; END IF;

  -- as fotos: a capa primeiro, sem a montagem dos grupos, sem repetir, JPG/PNG/WEBP públicas, até 30
  SELECT jsonb_agg(x.url ORDER BY x.n) INTO v_fotos
    FROM (SELECT y.url, min(y.n) AS n
            FROM (SELECT f.url, row_number() OVER (ORDER BY coalesce(f.e_capa, false) DESC, f.ordem NULLS LAST, f.id) AS n
                    FROM imovel_fotos f
                   WHERE f.codigo = p_codigo AND NOT coalesce(f.e_mosaico, false)
                     AND f.url ~* '^https://' AND split_part(f.url, '?', 1) ~* '\.(jpe?g|png|webp)$') y
           GROUP BY y.url ORDER BY 2 LIMIT 30) x;
  IF v_fotos IS NULL THEN v_falta := v_falta || 'sem foto (JPG, PNG ou WEBP)'::text; END IF;

  IF v_falta <> '{}' THEN
    RETURN jsonb_build_object('ok', false, 'falta', to_jsonb(v_falta));
  END IF;

  SELECT * INTO cf FROM condominio_ficha c WHERE c.condominio_id = i.condo_id;

  -- as áreas: a característica do imóvel é privativa; a que não casa lá e o que é do condomínio vão para comum
  v_priv := cnm_areas(i.caracteristicas, 'privativa');
  SELECT coalesce(array_agg(t ORDER BY n), '{}') INTO v_resto
    FROM unnest(coalesce(i.caracteristicas, '{}')) WITH ORDINALITY u(t, n)
   WHERE cardinality(cnm_areas(ARRAY[t], 'privativa')) = 0;
  v_comum := cnm_areas(v_resto || coalesce(cf.lazer, '{}') || coalesce(cf.seguranca, '{}') || coalesce(cf.comodidades, '{}'), 'comum');
  -- a mobília (campo próprio do cadastro)
  v_mob := lower(nay_sem_acento(coalesce(i.mobilia, '')));
  IF v_mob ~ '^mobiliado' AND NOT 'Mobiliado' = ANY (v_priv) THEN v_priv := v_priv || 'Mobiliado'::text; END IF;
  IF v_mob ~ 'modulad' AND NOT 'Armário(s) planejado(s)' = ANY (v_priv) THEN v_priv := v_priv || 'Armário(s) planejado(s)'::text; END IF;
  IF v_mob ~ '(\mar\M|climatizad)' AND NOT 'Ar Condicionado' = ANY (v_priv) THEN v_priv := v_priv || 'Ar Condicionado'::text; END IF;
  -- regra do portal: piscina não pode estar nas duas
  IF 'Piscina' = ANY (v_comum) THEN v_priv := array_remove(v_priv, 'Piscina'); END IF;
  v_pet := 'Aceita Pet' = ANY (v_priv) OR 'Aceita pet' = ANY (v_comum) OR 'Permitido pets' = ANY (v_comum);

  -- o CEP: o do imóvel; sem ele, o do condomínio (não é obrigatório no portal)
  v_cep := regexp_replace(coalesce(i.cep, ''), '\D', '', 'g');
  IF v_cep !~ '^\d{8}$' THEN v_cep := regexp_replace(coalesce(cf.cep, ''), '\D', '', 'g'); END IF;
  IF v_cep !~ '^\d{8}$' THEN v_cep := NULL; END IF;

  -- o título (até 100): "Apartamento com 3 quartos à venda no Kopenhagen, Ponta Negra"
  v_cond := nay_condominio_de_verdade(i.tipo, i.condominio_nome);
  v_neg := CASE WHEN v_venda IS NOT NULL AND v_aluga IS NOT NULL THEN ' à venda ou para alugar'
                WHEN v_venda IS NOT NULL THEN ' à venda' ELSE ' para alugar' END;
  v_tit := v_rot
    || CASE WHEN v_fin = 'RE' AND v_rot !~ '^(Terreno|Sítio)' AND coalesce(i.quartos, 0) > 0
            THEN ' com ' || i.quartos || CASE WHEN i.quartos = 1 THEN ' quarto' ELSE ' quartos' END ELSE '' END
    || v_neg
    || CASE WHEN v_cond IS NOT NULL THEN ' no ' || v_cond ELSE ' em ' || btrim(i.bairro) END;
  IF v_cond IS NOT NULL AND length(v_tit || ', ' || btrim(i.bairro)) <= 100 THEN v_tit := v_tit || ', ' || btrim(i.bairro); END IF;
  IF length(v_tit) > 100 THEN v_tit := btrim(regexp_replace(left(v_tit, 100), '\s+\S*$', '')); END IF;

  -- a descrição: a mesma do anúncio da OLX (o texto do cadastro e a ficha em linhas), até 3000
  v_desc := olx_corpo_do_anuncio(p_codigo, CASE WHEN v_venda IS NOT NULL THEN 'venda' ELSE 'locacao' END);
  IF length(v_desc) > 3000 THEN v_desc := btrim(regexp_replace(left(v_desc, 3000), '\s+\S*$', '')); END IF;

  RETURN jsonb_build_object('ok', true, 'falta', '[]'::jsonb, 'imovel', jsonb_build_object(
    'referencia', p_codigo::text,
    'codigo_cliente', p_codigo::text,
    'link_cliente', 'https://imobeasy.online/imovel/' || p_codigo,
    'titulo', v_tit,
    'transacao', CASE WHEN v_venda IS NOT NULL THEN 'V' ELSE 'L' END,
    'transacao2', CASE WHEN v_venda IS NOT NULL AND v_aluga IS NOT NULL THEN 'L' END,
    'finalidade', v_fin,
    'finalidade2', NULL,
    'destaque', 0,
    'tipo', v_tipo,
    'tipo2', NULL,
    'valor', coalesce(v_venda, v_aluga),
    'valor_locacao', CASE WHEN v_venda IS NOT NULL THEN v_aluga END,
    'valor_iptu', nullif(coalesce(i.iptu, 0), 0),
    'valor_condominio', nullif(coalesce(i.taxa_condominio, 0), 0),
    'area_total', nullif(coalesce(i.area_total, 0), 0),
    'area_util', nullif(coalesce(i.area_util, 0), 0),
    'conservacao', NULL,
    'quartos', CASE WHEN i.quartos >= 0 THEN i.quartos END,
    'suites', CASE WHEN i.suites >= 0 THEN i.suites END,
    'garagem', CASE WHEN i.vagas >= 0 THEN i.vagas END,
    'banheiro', CASE WHEN i.banheiros >= 0 THEN i.banheiros END,
    'aceita_pet', CASE WHEN v_pet THEN 1 ELSE 0 END,
    'estado', CASE WHEN upper(btrim(coalesce(i.estado, ''))) ~ '^[A-Z]{2}$' THEN upper(btrim(i.estado)) ELSE 'AM' END,
    'cidade', coalesce(nullif(btrim(coalesce(i.cidade, '')), ''), 'Manaus'),
    'bairro', btrim(i.bairro),
    'cep', v_cep,
    -- o endereço vai para o portal achar o lugar no mapa, mas não aparece no anúncio (esconder = 1)
    'endereco', left(nullif(btrim(coalesce(i.logradouro, '')), ''), 200),
    'numero', NULL,
    'complemento', NULL,
    'esconder_endereco_imovel', 1,
    'descritivo', v_desc,
    'fotos', v_fotos,
    'periodo_locacao', CASE WHEN v_aluga IS NOT NULL THEN 1 END,
    'area_comum', to_jsonb(v_comum),
    'area_privativa', to_jsonb(v_priv)));
END
$function$;

-- todos os que podem ir, com o motivo de quem não vai (o XML leva só os ok)
CREATE OR REPLACE FUNCTION public.cnm_imoveis()
 RETURNS TABLE(codigo integer, ok boolean, falta jsonb, imovel jsonb)
 LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public'
AS $f$
  SELECT i.codigo, (m->>'ok')::boolean, m->'falta', m->'imovel'
    FROM imoveis i CROSS JOIN LATERAL cnm_imovel_montar(i.codigo) m
   WHERE i.status = 'Disponível' AND coalesce(i.disponivel, false) AND coalesce(i.publicado_no_site, false)
     AND NOT coalesce(i.e_parceiro, false) AND NOT coalesce(i.bloqueado, false)
     AND (coalesce(i.valor_venda, 0) > 0 OR coalesce(i.valor_aluguel, 0) > 0)
   ORDER BY i.codigo
$f$;

-- ---------------------------------------------------------------- os leads
CREATE TABLE privado.cnm_config (
  chave text PRIMARY KEY,
  valor text,
  atualizado_em timestamptz NOT NULL DEFAULT now());
COMMENT ON TABLE privado.cnm_config IS '458: lead_email e lead_token = a conta da Imob Easy no Chaves na Mão (Meus Dados > Dados Adicionais > Token Integração de leads). Vazios = modo de teste (entra o lead com o User-Agent do portal, marcado autenticado = false).';
INSERT INTO privado.cnm_config (chave, valor) VALUES ('lead_email', NULL), ('lead_token', NULL);

CREATE TABLE privado.cnm_lead (
  lead_id          text PRIMARY KEY,             -- o "id" do portal: a mesma chave duas vezes não vira dois leads
  recebido_em      timestamptz NOT NULL DEFAULT now(),
  vezes            integer NOT NULL DEFAULT 1,   -- quantas vezes o portal mandou (reenvio)
  ultimo_em        timestamptz NOT NULL DEFAULT now(),
  autenticado      boolean NOT NULL,
  nome             text,
  telefone         text,                         -- só dígitos, como veio (com DDD)
  email            text,
  mensagem         text,
  tipo             text,                         -- proposeTypeName ("Formulário WhatsApp", "Contato Site", "Proposta")
  codigo           integer,                      -- ad.reference quando é um código nosso
  anuncio_id       text,
  anuncio_url      text,
  anuncio_titulo   text,
  negocio          text,                         -- ad.purpose: Venda, Locação, Venda/Locação
  valor            numeric,
  criado_no_portal timestamptz,
  payload          jsonb NOT NULL);
CREATE INDEX cnm_lead_recebido ON privado.cnm_lead (recebido_em DESC);
CREATE INDEX cnm_lead_telefone ON privado.cnm_lead (telefone);
COMMENT ON TABLE privado.cnm_lead IS '458: os leads que o Chaves na Mão manda por POST (nay-site-api /api/chavesnamao/leads).';

CREATE OR REPLACE FUNCTION public.cnm_lead_receber(p jsonb, p_email text, p_token text, p_agente text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_email text := nullif(btrim((SELECT valor FROM privado.cnm_config WHERE chave = 'lead_email')), '');
  v_token text := nullif(btrim((SELECT valor FROM privado.cnm_config WHERE chave = 'lead_token')), '');
  v_aut   boolean;
  v_id    text := nullif(btrim(p->>'id'), '');
  v_ref   text := btrim(coalesce(p#>>'{ad,reference}', ''));
  v_quando timestamptz;
  v_valor numeric;
  v_novo  boolean;
BEGIN
  IF v_email IS NOT NULL AND v_token IS NOT NULL THEN
    IF lower(btrim(coalesce(p_email, ''))) <> lower(v_email) OR coalesce(p_token, '') <> v_token THEN
      RETURN jsonb_build_object('status', 'negado');
    END IF;
    v_aut := true;
  ELSE
    -- sem a senha guardada (antes do contrato): só o que vem do portal, e marcado
    IF coalesce(p_agente, '') NOT ILIKE 'chavesnamao-leads-api%' THEN
      RETURN jsonb_build_object('status', 'negado');
    END IF;
    v_aut := false;
  END IF;
  IF v_id IS NULL OR jsonb_typeof(p) <> 'object' THEN
    RETURN jsonb_build_object('status', 'invalido', 'erro', 'falta o id do lead');
  END IF;

  BEGIN
    v_quando := (p->>'createdAt')::timestamp AT TIME ZONE 'America/Sao_Paulo';
  EXCEPTION WHEN others THEN v_quando := NULL;
  END;
  BEGIN
    v_valor := (p#>>'{ad,value}')::numeric;
  EXCEPTION WHEN others THEN v_valor := NULL;
  END;

  INSERT INTO privado.cnm_lead AS l (lead_id, autenticado, nome, telefone, email, mensagem, tipo, codigo, anuncio_id,
                                     anuncio_url, anuncio_titulo, negocio, valor, criado_no_portal, payload)
  VALUES (v_id, v_aut, nullif(btrim(p->>'name'), ''), nullif(regexp_replace(coalesce(p->>'phone', ''), '\D', '', 'g'), ''),
          nullif(btrim(p->>'email'), ''), nullif(btrim(p->>'message'), ''), nullif(btrim(p->>'proposeTypeName'), ''),
          CASE WHEN v_ref ~ '^\d{1,9}$' THEN v_ref::integer END, nullif(p#>>'{ad,id}', ''), nullif(p#>>'{ad,url}', ''),
          nullif(p#>>'{ad,title}', ''), nullif(p#>>'{ad,purpose}', ''), v_valor, v_quando, p)
  ON CONFLICT (lead_id) DO UPDATE SET vezes = l.vezes + 1, ultimo_em = now()
  RETURNING (xmax = 0) INTO v_novo;

  RETURN jsonb_build_object('status', CASE WHEN v_novo THEN 'novo' ELSE 'repetido' END, 'autenticado', v_aut, 'id', v_id);
END
$function$;

-- ---------------------------------------------------------------- quem pode
REVOKE ALL ON FUNCTION public.cnm_imoveis(), public.cnm_imovel_montar(integer), public.cnm_areas(text[], text),
  public.cnm_lead_receber(jsonb, text, text, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.cnm_imoveis(), public.cnm_imovel_montar(integer) TO nay_site_leitura, nay_site_escrita;
GRANT EXECUTE ON FUNCTION public.cnm_lead_receber(jsonb, text, text, text) TO nay_site_escrita;

COMMIT;
