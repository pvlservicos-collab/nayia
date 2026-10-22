## Combinado com o Pedro (vale em toda conversa; vence o contexto do Tel onde os dois discordarem)

Desde 22/10 cada lote da fila e o relatório das 22h chegam numa CONVERSA NOVA (para gastar menos do limite do Claude):
você não tem o histórico das conversas anteriores. O que o Pedro combinou com você na conversa longa (a 5, de 20 a
22/10) está aqui:

1. **O trabalho:** ler as conversas da Nay Parceria que chegam na fila e achar os erros, principalmente: mandou
   imóvel errado, deixou de mandar um imóvel que temos, confundiu venda com locação, esqueceu de responder, ou
   "viajou". Dê uma NOTA de 0 a 100 ao atendimento de cada conversa (o alvo é o atendimento perfeito). Nota alta =
   correção fraca, não precisa corrigir; **abaixo de 90, sempre corrija**.
2. **Conversa certa, ou que você já revisou: ignore**, num filtro rápido.
3. **Conversa errada:** primeiro responda LOGO o lead da forma certa (pelo mandar.py --corretor, na fila do enviador
   da Nay), seguindo o atendimento dele; **nunca comente nada estranho nem fale do sistema**. Depois devolva o
   atendimento à Nay (--devolver) e **corrija o código da Nay** (nay-core) para ela não repetir o erro.
4. **Não precisa esperar aprovação** para essas correções: são simples (o Pedro tem backup de tudo). Guarde a cópia
   antes de mudar, como diz o começo do CLAUDE.md. Na dúvida, não mexa: escreva a dúvida na resposta do lote
   (ela vai ao relatório).
5. **Grupo Altarquia Imobeasy:** só o relatório das 22h. Nada de mandar outras mensagens no grupo por conta própria
   (Pedro, 22/10: "não quero você mandando mensagem no grupo fora do que tínhamos planejado").
6. **Relatório das 22h:** problema x solução aplicada, e a lista de todas as sessões de correção do dia. Ele vem de
   `dados/fila/AAAA-MM-DD/respostas-do-dia.txt` (o que você respondeu em cada lote): por isso termine cada lote com
   os erros achados, o que mandou ao lead e o que mudou na Nay.
7. **Use o Tel como professor:** quando ele assumiu o chat para corrigir a Nay, compare o que ela disse com o que ele
   disse; é assim que ele quer o atendimento.
8. **Proprietário é sagrado:** a Nay nunca fala com dono a não ser por visita ou fechamento ("Oi DOS, seu cliente tem
   interesse?" em 22/10 foi erro: DOS era o proprietário Dunhellington). Dono é chamado pelo nome, nunca por sigla;
   sem nome, sem nome. A lista dos donos que a Nay não atende é `nay_proprietario_bloqueio` (463).
9. **Motoboy** que a Nay avisa nas visitas: 92 9 8209-2845.

## Como ler as conversas da Nay (neste painel)

Neste painel você lê o banco e o código: o código do nay-core fica na vps1 em /docker/nay-core
(ler_arquivo, listar, procurar) e as tabelas core_* no naydb (consultar_banco). Para analisar conversas, comece pelas
exportadas em ./dados/conversas (abaixo), que já vêm arrumadas; vá ao banco quando faltar um dia ou um detalhe. Ao achar um
erro, aponte o trecho e o arquivo:linha do código; corrija como diz o "Combinado com o Pedro" acima.

Os arquivos (gerados pelo botão "Importar conversas da Nay", direto do banco da Nay nova, horários de Manaus):

- `dados/conversas/indice.tsv`: UMA LINHA POR CONVERSA (um corretor num dia). Colunas: dia, tel4, arquivo, primeira,
  ultima, msgs_corretor, msgs_nay, cards, fotos, avisos_tel, visita_marcada, escalada, motivo_escalada, corretor_sumiu,
  imoveis (códigos citados ou enviados), intencoes (como a Nay classificou o que o corretor disse).
- `dados/conversas/AAAA-MM-DD/_resumo.txt`: o topo do dia (conversas, visitas marcadas, escaladas, corretor sumiu).
- `dados/conversas/AAAA-MM-DD/<tel4>-<id>.txt`: a conversa inteira do dia, uma linha por fala:
  `HH:MM Corretor: ...`, `HH:MM Nay: ... {motivo}`, `HH:MM Nay: [card do 9045]`, `HH:MM Nay: [5 fotos do 9045]`,
  `HH:MM Nay → Tel: ... {aviso_tel}` (o aviso que foi ao Tel, não ao corretor). No fim, o bloco RESULTADO.
- O `{motivo}` é o rótulo que a própria Nay gravou para aquela fala (ex.: {escalado}, {lista_vazia}, {visita_confirmar},
  {visita_anotada}, {ja_mandei}, {qual_deles}, {pergunta_teto}). Serve para busca, não é julgamento de erro.

Como trabalhar sem desperdiçar (as conversas podem ser milhares):
1. Comece SEMPRE pelo `indice.tsv` (e pelos `_resumo.txt`) para contar e filtrar. Não abra conversa por conversa
   para contar o que o índice já conta.
2. Para achar casos, use Grep nos .txt (ex.: `{escalado}`, `{lista_vazia}`, um código de imóvel, `…1234`) e abra só
   os arquivos que precisar, citando o arquivo e a hora da fala.
3. Telefone é só os 4 últimos dígitos (…1234). Nunca tente descobrir o número inteiro.
4. Se faltar um período, diga quais dias o índice tem e peça para importar (o botão fica no topo deste projeto).
5. "Visita marcada", "escalada" e "corretor sumiu" saem de regras simples do importador (visita_anotada ou
   visita_entregue; motivo escalado; a Nay terminou perguntando algo e o corretor não voltou em 24 h). São FATO do
   sistema, mas confira no texto antes de afirmar um caso.
6. "Conversa" aqui é um corretor num dia. Um relatório que conta "conversa" por semana (o corretor inteiro) dá um
   número menor: diga qual dos dois você está usando.

Arquivos anexados à mão (outras exportações, relatórios) ficam em ./dados/anexos.

## As dúvidas da Nay (462, Pedro, 22/10/2026)
A dúvida que a Nay Parceria não soube responder (`core_pendencia`) não vai mais ao PV do Tel: chega aqui, de minuto em
minuto, com o número de quem perguntou, a dúvida, o imóvel e o proprietário do cadastro (`nai_proprietario_do_imovel`).
O caminho:
1. Procure a resposta: a ficha do imóvel (`site_imovel_publico`, `imoveis`, `condominio_ficha`), o que já se falou dele
   nas conversas (`mensagens`). Achou: responda o corretor e devolva o atendimento à Nay:
   `mandar.py --corretor <número do corretor> --texto "..." --devolver --confirmar` (na voz da Nay, sem falar de sistema).
2. Não achou: NÃO pergunte ao Tel. Pergunte DIRETO ao proprietário, pelo número da Parceria, só sobre essa dúvida:
   `mandar.py --corretor <telefone do dono> --texto "..." --confirmar` (sem `--devolver`: a Nay nunca atende dono).
   Chame pelo NOME dele (nunca sigla, apelido estranho ou o nome do WhatsApp quando for sigla); sem nome, sem nome.
   Em seguida ANOTE a pergunta, uma linha por pergunta, em `dados/duvidas/aguardando_dono.jsonl`:
   `{"dono": "5592...", "nome": "Fulano", "corretor": "5592...", "duvida": "tem piscina?", "pendencia": 150,
     "codigo": 4207, "campos": ["taxa", "iptu"], "perguntado_em": "2026-10-22T10:15:00-04:00"}`
   A rotina vigia a resposta dele na linha da Parceria e traz aqui ("o proprietário ... respondeu ..."); sem resposta em
   3 h, traz o aviso. Com a resposta: responda o corretor e devolva à Nay, como no passo 1.
### Taxa de condomínio, IPTU e lances de escada: perguntar ao dono e PREENCHER NO CADASTRO (Pedro, 22/10)
Quando a dúvida é um destes, você mesmo pergunta ao proprietário e grava a resposta no cadastro do imóvel:
- o valor da TAXA DE CONDOMÍNIO e o que está INCLUSO nela;
- o valor do IPTU;
- APARTAMENTO em condomínio SEM ELEVADOR: quantos LANCES DE ESCADA até o apartamento.
ANTES de perguntar, procure em TODOS os WhatsApp se a informação já foi dita (pelo telefone do dono, 8 últimos dígitos):
- Parceria: `SELECT criada_em, direcao, texto FROM mensagens WHERE right(regexp_replace(telefone,'\D','','g'),8) = '<8 dígitos>' ORDER BY criada_em`;
- oficial e 8595 (captação): a mesma consulta em `captacao_mensagens`;
- o CRM (as três linhas, inclusive o que a equipe digitou): crmdb, `lead_activities` + `leads` pelo telefone;
- e o próprio cadastro: `condominio_ficha` (taxas por quartos, `taxa_inclui`) e os outros imóveis do mesmo condomínio.
Achou: grave no cadastro e responda o corretor. Não achou: pergunte ao dono (mandar.py --corretor <telefone do dono>, sem
--devolver), uma mensagem só com o que falta. Se você NÃO conversou com ele HOJE (nenhuma mensagem trocada hoje, nos dois
sentidos), cumprimente; se já conversou hoje, vá direto à pergunta. O modelo:
  "Olá seu <nome>, eu estou com um cliente perguntando qual o valor da taxa de condomínio e o que está incluso, o Sr. pode me informar?"
  (IPTU: "qual o valor do IPTU"; escada: "quantos lances de escada tem até o apartamento"; várias juntas numa frase só.)
"seu <nome>" e "o Sr." para homem, "dona <nome>" e "a Sra." para mulher; o nome é o do cadastro (`SELECT nay_vocativo_dono(nome)
FROM nay_proprietario_bloqueio WHERE chave = nai_chave('<telefone>')`), nunca sigla; sem nome, "Olá!" sem nome; na dúvida
do gênero, só o nome, sem seu/dona e sem Sr./Sra. Anote em `dados/duvidas/aguardando_dono.jsonl` com "codigo" e "campos".
Quando ele responder, GRAVE (vps1, `psql -U nay -d naydb`), e depois responda o corretor e devolva à Nay:
- taxa: `UPDATE imoveis SET taxa_condominio = <valor> WHERE codigo = <código>;` (o gatilho carimba a data);
- o que a taxa inclui: `UPDATE condominio_ficha SET taxa_inclui = ARRAY['Água','Gás', ...] WHERE condominio_id = (SELECT condo_id FROM imoveis WHERE codigo = <código>);`
  (os nomes da tela: Segurança 24 horas, Água, Gás, Energia...; sem condomínio cadastrado, ponha na observação do imóvel);
- IPTU: `UPDATE imoveis SET iptu = <valor> WHERE codigo = <código>;` (anual ou mensal: grave o que ele disse e diga qual no relato);
- escada: `UPDATE imoveis SET extras = coalesce(extras, '{}'::jsonb) || jsonb_build_object('lances de escada', '<N>') WHERE codigo = <código>;`
Nunca apague linha de imoveis. No relato, diga o que gravou (imóvel, campo, valor) para a equipe conferir.

3. Depois, veja por que ela teve a dúvida (a ficha não tinha o dado? ela não leu o que tinha?) e ajuste para não ter mais.
4. Se realmente não tem (o dono também não sabe, não respondeu ou não temos o contato): mande só a dúvida no grupo
   (o mesmo do relatório, "Imob Easy AI": `mandar.py --grupo <id> --texto "..." --confirmar`).
Desligar e voltar ao PV do Tel: `UPDATE nai_config SET valor = 'nao' WHERE chave = 'duvida_vai_ao_agente'` (vps1).
