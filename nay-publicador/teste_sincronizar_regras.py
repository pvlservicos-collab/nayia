"""
Testa a parte pura do sincronizar_regras.py: montar o bloco e aplicá-lo
ao prompt. Não toca banco, docker nem n8n -- roda em qualquer máquina.

O que importa provar aqui é a IDEMPOTÊNCIA. Este script vai ser rodado
várias vezes contra um prompt de produção de 274 linhas; se rodar duas
vezes gerar dois blocos, ou comer um pedaço do prompt, o estrago aparece
no atendimento a corretor e não num teste.

Uso:
    .venv/bin/python teste_sincronizar_regras.py
"""
from sincronizar_regras import ANCORA, FIM, INICIO, aplicar, montar_bloco

falhas = 0

PROMPT_BASE = """Você é a Nay Mendes, assistente da Imob Easy.

=== REGRA ZERO: NUNCA AFIRME SEM TER CONSULTADO ===
Você só afirma um fato depois de uma ferramenta ter te devolvido.

=== COMO VOCÊ ESCREVE ===
Português do Brasil, sempre.

=== QUEM VOCÊ É ===
Assistente da Imob Easy."""

REGRAS = [
    ("endereco", "Voce pode passar o endereco do CONDOMINIO, nunca a unidade."),
    ("locacao", "Em TODA locacao confirme renda de 3x antes de mobilizar."),
]


def checar(rotulo, condicao, detalhe=""):
    global falhas
    ok = bool(condicao)
    falhas += 0 if ok else 1
    print(f"  {'OK  ' if ok else 'FALHOU'} {rotulo}")
    if not ok and detalhe:
        print(f"         {detalhe}")


print("--- bloco: formato e conteúdo ---")
bloco = montar_bloco(REGRAS)
checar("abre com o marcador de início", bloco.startswith(INICIO))
checar("fecha com o marcador de fim", bloco.rstrip().endswith(FIM))
checar("traz as duas regras", all(t in bloco for _, t in REGRAS))
checar("marca o contexto de cada uma", "[endereco]" in bloco and "[locacao]" in bloco)
checar("diz que a regra ganha do resto do prompt", "a regra ganha" in bloco)
print()

print("--- inserção: bloco ainda não existe ---")
uma_vez = aplicar(PROMPT_BASE, bloco)
checar("o prompt original continua inteiro",
       all(p in uma_vez for p in ("REGRA ZERO", "COMO VOCÊ ESCREVE", "QUEM VOCÊ É")))
checar("o bloco entrou", INICIO in uma_vez and FIM in uma_vez)
checar("entrou ANTES da âncora, não depois",
       uma_vez.index(INICIO) < uma_vez.index(ANCORA),
       f"inicio={uma_vez.index(INICIO)} ancora={uma_vez.index(ANCORA)}")
checar("entrou DEPOIS da REGRA ZERO (política antes de estilo)",
       uma_vez.index("REGRA ZERO") < uma_vez.index(INICIO))
print()

print("--- idempotência: rodar de novo com as MESMAS regras ---")
duas_vezes = aplicar(uma_vez, bloco)
checar("o resultado é idêntico", duas_vezes == uma_vez,
       f"tamanhos: {len(uma_vez)} vs {len(duas_vezes)}")
checar("não duplicou o bloco", duas_vezes.count(INICIO) == 1,
       f"encontrei {duas_vezes.count(INICIO)} marcadores de início")
print()

print("--- atualização: regra nova entra, antiga sai ---")
regras_novas = [("visita", "Nao existe acompanhante reserva do Fernando.")]
atualizado = aplicar(uma_vez, montar_bloco(regras_novas))
checar("a regra nova aparece", "acompanhante reserva" in atualizado)
checar("a regra antiga sumiu", "renda de 3x" not in atualizado)
checar("continua com um bloco só", atualizado.count(INICIO) == 1)
checar("o prompt original continua inteiro",
       all(p in atualizado for p in ("REGRA ZERO", "COMO VOCÊ ESCREVE", "QUEM VOCÊ É")))
print()

print("--- recusas: melhor parar do que adivinhar ---")
try:
    aplicar(PROMPT_BASE.replace(ANCORA, "=== OUTRA COISA ==="), bloco)
    checar("âncora ausente levanta erro", False, "não levantou")
except RuntimeError as exc:
    checar("âncora ausente levanta erro", "esperava exatamente 1" in str(exc))

try:
    aplicar(PROMPT_BASE + "\n" + ANCORA, bloco)
    checar("âncora duplicada levanta erro", False, "não levantou")
except RuntimeError as exc:
    checar("âncora duplicada levanta erro", "esperava exatamente 1" in str(exc))

try:
    # alguém editou o prompt à mão e comeu o marcador de fim
    quebrado = uma_vez.replace(FIM, "")
    aplicar(quebrado, bloco)
    checar("marcador de fim sumido levanta erro", False, "não levantou")
except RuntimeError as exc:
    checar("marcador de fim sumido levanta erro", "editado à mão" in str(exc))
print()

print("--- normalização vinda do banco ---")
bloco_multilinha = montar_bloco([("x", "linha um\nlinha dois   com   espaços")])
checar("regra multilinha vira uma linha só",
       "linha um linha dois com espaços" in bloco_multilinha)
print()

print("TODOS OS TESTES PASSARAM" if falhas == 0 else f"{falhas} FALHARAM")
raise SystemExit(1 if falhas else 0)
