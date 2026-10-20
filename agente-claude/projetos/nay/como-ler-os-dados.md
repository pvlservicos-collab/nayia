## Como ler as conversas da Nay (neste painel)

Neste painel você NÃO acessa servidor, banco nem código do nay-core: você analisa as conversas exportadas em
./dados/conversas. As partes do contexto que pedem descobrir a VPS, ler código, exportar ou corrigir (Etapa 1 itens 1
e 2, Etapa 2) são feitas pelo Claude Code do Pedro, fora daqui. O que dá para fazer aqui é o item 3 da Etapa 1 (a
leitura das conversas) e toda a análise: contar, achar exemplos, comparar dias, apontar os erros com o trecho.

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
