# nay-captacao: a Nay de captação em Python

Pedro, 08/10/2026: "prepara a nay captação para rodar no número de api oficial, mas já sabendo a resposta do
modelo situacao_imovel_cadastrado_1 ... pode recriar a nay de captação em python sem perder nada ... e quero mais
uma pergunta no fluxo dela, se [ele] tem alguém que esteja vendendo um imóvel para indicar ... por enquanto roda só
no meu número".

## O que é

O serviço que decide e responde as conversas da captação de proprietários **pelo número oficial** (8456-0874), no
lugar do agente do fluxo do n8n (`Nay - captacao proprietarios`, VPS2). Roda no srv1894338, em
`/root/nay-captacao`, como o serviço systemd `nay-captacao`.

## O que veio do fluxo, peça por peça

| no n8n | aqui |
|---|---|
| Janela de 20s + Reservar mensagens | `banco.FILA`, `banco.RESERVAR` |
| Juntar mensagens | `turno.juntar` |
| AI Agent (texto do turno) | `turno.cabecalho` |
| AI Agent + GPT (captação) + Memoria | `modelo.responder` (API de Responses; a conversa vem de `captacao_mensagens`) |
| as 6 ferramentas (SQL) | `ferramentas.json`, tirado do fluxo por `scripts/extrair_ferramentas.py` |
| escalar_ao_tel (sub-fluxo) | `ferramentas.executar` + `banco.ESCALAR` |
| Preparar resposta | `resposta.baloes` |
| Pausa, Ainda é da IA? | `atender.atender` + `banco.AINDA_E_DA_IA` |
| Enviar resposta (oficial) | `envio.texto` (pelo CRM) |
| Registrar saida | `banco.REGISTRAR_SAIDA` |
| Registrar envio | `banco.REGISTRAR_DISPARO` |

O prompt é o MESMO, o vivo do banco (`nai_prompt_de('captacao')`), com um acréscimo que só vale aqui
(`modelo.ACRESCIMO`): o modelo da Meta que abriu a conversa, com os três botões, e a pergunta da indicação.

## O que é novo

- **O modelo que abre a conversa**: `situacao_imovel_cadastrado_1` (pt_BR), com os botões Disponível / Alugado /
  Vendido. `python -m captacao.disparo --lead N` manda e registra. O toque no botão chega como texto e é a resposta
  da situação.
- **A indicação**: antes de encerrar ela pergunta se a pessoa conhece alguém vendendo um imóvel. É parede:
  `encerrar_conversa` não encerra enquanto a pergunta não saiu (`captacao_indicacao_pendente`). O indicado fica em
  `privado.captacao_indicacao` (ferramenta `guardar_indicacao`).
- **O disparo da fila** (317): com `captacao_config.python_disparo = sim` o serviço manda o modelo a UM lead por
  vez, com intervalo sorteado entre `python_disparo_seg_min` e `python_disparo_seg_max` (45 a 75 s: um por minuto
  em média). O banco decide quem e quando: `captacao_py_fila_do_disparo` (nunca quem já recebeu algo, nunca a mesma
  pessoa por outro lead, nunca corretor ou parceiro, nunca quem está em `captacao_nao_disparar`) e
  `captacao_py_disparo_motivo` (desligado, fora do horário, três falhas seguidas, intervalo). Quem recebe o modelo
  entra em `captacao_motor` e passa a ser atendido aqui. Envio sem confirmação do CRM não é repetido: o lead vai
  para `captacao_nao_disparar` com o motivo.
- **Imóvel que já é nosso** (318): quem diz "disponível" e já tem o imóvel no cadastro só informa o valor; a ficha
  (quartos, vagas, fotos) é só para imóvel que ainda não temos.
- **Duas mensagens**: o que ela anotou e a pergunta saem separados (`resposta.em_duas_viagens`).
- **Até 4 conversas ao mesmo tempo**, nunca duas vezes a mesma pessoa. Na partida, o que ficou reservado e sem
  resposta nos últimos 10 minutos volta à fila.
- **A pergunta da indicação** (320) é montada pelo banco (`captacao_indicacao_frase`): "Sra. Maria, estamos com uma
  demanda alta de clientes querendo imóveis para locação nesse final de ano, a Sra. teria alguém para indicar que
  queira alugar ou vender?" -- e "comprar imóveis ... vender ou alugar" quando o imóvel dele é de venda.
- **Cartão de contato**: o CRM entrega o cartão que a pessoa compartilha como texto ("👤 Contato: NOME — TELEFONE");
  ela usa o nome e o telefone e não pede de novo. A indicação com telefone é **encaminhada na hora** para
  `captacao_config.telefone_relatorio` pelo número oficial (fora da janela de 24 h de quem recebe, vira aviso ao Tel).
- **A resposta vai para o cadastro do imóvel** (321, `captacao/cadastro.py`): de 5 em 5 minutos o serviço chama
  `captacao_aplicar_pendentes()` -- situação (vendido/alugado/disponível), valor do aluguel e fim do contrato
  (`contratos_locacao.vencimento`), só depois de 15 minutos de silêncio na conversa -- e traz para o imóvel a foto que
  o dono mandou na conversa (`captacao_fotos_a_puxar()` + a rota de foto da API do site). O que entrou e o que ficou
  para gente decidir está em `captacao_aplicado` (colunas `mudou` e `conferir`). Vale para toda a captação, não só
  para quem é atendido aqui.

## O que AINDA é do fluxo do n8n

- A **entrada**: o webhook do número oficial, a transcrição do áudio, a foto guardada na ficha e o "Gravar na
  fila". A mensagem entra por lá; o gatilho da migração 315 marca como `Recebido py` as dos telefones da lista, e
  só essas chegam aqui.
- O lembrete (desligado: `max_followup = 0`), o vigia do número e o relatório do dia.
- Toda conversa de quem **não está na lista** nem recebeu o modelo por aqui.

## Quem é atendido aqui

`captacao_config.python_telefones`: telefones separados por vírgula (`todos` = todos). Hoje, só o número do Pedro.
Tirar um número da lista devolve o número ao fluxo antigo na mensagem seguinte. E todo lead de `captacao_motor`
(quem recebeu o modelo pelo disparo daqui).

## Ligar e acompanhar o disparo

```
UPDATE captacao_config SET valor = 'sim' WHERE chave = 'python_disparo';   -- liga   ('nao' desliga na hora)
SELECT * FROM captacao_py_disparo_placar();                                -- por que não sai, fila, enviados
journalctl -u nay-captacao -f | grep disparo
```

Só sai dentro do horário de `captacao_no_horario()`: dias úteis 08:00-18:00 com pausa 12:00-13:30, fim de semana
09:00-16:00 (Manaus). Fora dele o serviço espera sozinho e retoma.

## Rodar

```
systemctl status nay-captacao            journalctl -u nay-captacao -n 50
cd /root/nay-captacao && set -a && . ./.env && set +a
.venv/bin/python -m captacao.ensaio disponivel     # conversa inteira com o lead de teste; nada sai, nada fica
.venv/bin/python -m captacao.disparo --lead 835 --zerar   # manda o modelo de verdade ao lead de teste
python -m unittest discover -s tests               # as partes puras (roda em qualquer máquina)
```

`.env` (fora do git): `DATABASE_URL`, `OPENAI_API_KEY`, `CAPTACAO_OFICIAL_SEGREDO`, `CAPTACAO_FOTO_SEGREDO` (a senha
de máquina da rota de foto do site; sem ela as fotos da conversa não são trazidas); opcionais `CAPTACAO_AVISAR_TEL`
(`nao` cala o aviso de escalada e de foto ao Tel; o telefone de teste nunca avisa), `SITE_API_URL` e `CAPTACAO_MODELO`.

O que a captação mudou no cadastro, e o que espera gente:

```
SELECT aplicado_em, codigo, mudou, conferir FROM captacao_aplicado WHERE mudou <> '{}' OR conferir <> '{}' ORDER BY id DESC;
```

## Parar

Só o disparo: `python_disparo = nao`. Tudo: `systemctl stop nay-captacao` (quem já recebeu o modelo fica sem
resposta até o serviço voltar; para devolver alguém ao fluxo antigo, apague a linha dele de `captacao_motor`).
