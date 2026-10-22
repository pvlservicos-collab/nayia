## Como ler as conversas da Nay (neste painel)

Neste painel você lê o banco e o código: o código do nay-core fica na vps1 em /docker/nay-core
(ler_arquivo, listar, procurar) e as tabelas core_* no naydb (consultar_banco). Para analisar conversas, comece pelas
exportadas em ./dados/conversas (abaixo), que já vêm arrumadas; vá ao banco quando faltar um dia ou um detalhe. Ao achar um
erro, aponte o trecho e o arquivo:linha do código; só corrija (Etapa 2) quando a mensagem pedir o conserto.

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
     "perguntado_em": "2026-10-22T10:15:00-04:00"}`
   A rotina vigia a resposta dele na linha da Parceria e traz aqui ("o proprietário ... respondeu ..."); sem resposta em
   3 h, traz o aviso. Com a resposta: responda o corretor e devolva à Nay, como no passo 1.
3. Depois, veja por que ela teve a dúvida (a ficha não tinha o dado? ela não leu o que tinha?) e ajuste para não ter mais.
4. Se realmente não tem (o dono também não sabe, não respondeu ou não temos o contato): mande só a dúvida no grupo
   (o mesmo do relatório, "Imob Easy AI": `mandar.py --grupo <id> --texto "..." --confirmar`).
Desligar e voltar ao PV do Tel: `UPDATE nai_config SET valor = 'nao' WHERE chave = 'duvida_vai_ao_agente'` (vps1).
