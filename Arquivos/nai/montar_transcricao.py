# -*- coding: utf-8 -*-
"""Transcricao melhor: modelo novo da OpenAI + o vocabulario da nossa casa.

    python3 montar_transcricao.py w.json w_novo.json

Tel, 23/09/2026: "n da para usar um modelo de transcricao de audio da open ia
gastando token?" -- e, sobre a chave: "a chave da open ai e a mesma do modelo
de cerebro". Entao a credencial e a MESMA que ja esta no fluxo.

O CASO: a Geina mandou um audio pedindo casa e a transcricao saiu
"Inaicio, Tens pra Area, Julio de Carvalho, Canticos Livres, Alvorada, Bom
Pedro, ne? Essas mediacoes de casa para aluguel". Tudo que errou foi NOME
PROPRIO -- "Bom Pedro" e o bairro DOM PEDRO, "mediacoes" e "imediacoes".

DUAS MUDANCAS:
  1. `whisper-1` (o padrao do no da OpenAI no n8n) passa a `gpt-4o-transcribe`.
  2. Vai junto um `prompt` com os NOSSOS bairros e condominios. O campo existe
     exatamente para isso: ensinar o vocabulario antes de ouvir. Sem ele,
     nenhum modelo adivinha "Tarumã-Açu" ou "Acquarelle".

A lista sai do proprio catalogo (bairros com imovel no mercado), entao
acompanha o que temos sem ninguem precisar manter nada a mao.
"""
import io, json, sys

BAIRROS = ("Adrianópolis, Aleixo, Alvorada, Cachoeirinha, Centro, Chapada, Cidade de Deus, "
           "Cidade Nova, Colônia Santo Antônio, Colônia Terra Nova, Compensa, Coroado, Da Paz, "
           "Dom Pedro, Flores, Japiim, Lago Azul, Lírio do Vale, Nossa Senhora das Graças, "
           "Nova Cidade, Nova Esperança, Novo Aleixo, Parque 10 de Novembro, "
           "Parque das Laranjeiras, Petrópolis, Planalto, Ponta Negra, Praça 14 de Janeiro, "
           "Raiz, Santa Etelvina, Santo Agostinho, Santo Antônio, São Francisco, São Geraldo, "
           "São Jorge, São José Operário, Tarumã, Tarumã-Açu, Zumbi dos Palmares")

CONDOMINIOS = ("Acquarelle, Alphaville, Ilhas Gregas, Gran Vista, Morada dos Pássaros, "
               "Ponta Negra I e II, Itapuranga, Reserva do Parque, Smart Downtown, "
               "Vitta Club House, Passaredo, Forest Hill, Quinta das Marinas, "
               "Mundi Resort, Evidence Ponta Negra, Living Comfort, Park Golf")

VOCABULARIO = ("Conversa entre corretores de imóveis em Manaus, Amazonas. "
               "Bairros: " + BAIRROS + ". "
               "Condomínios: " + CONDOMINIOS + ". "
               "Fala-se de aluguel, locação, venda, quartos, suíte, vaga, "
               "mobiliado, semimobiliado, condomínio, visita e código do imóvel.")


def main():
    entrada, saida = sys.argv[1], sys.argv[2]
    d = json.load(io.open(entrada, encoding="utf-8"))
    w = d[0] if isinstance(d, list) else d

    antigo = None
    for n in w["nodes"]:
        if n["name"] == "Transcrever":
            antigo = n
            break
    if antigo is None:
        raise SystemExit("nao achei o no Transcrever")

    # O NOME E A SAIDA CONTINUAM OS MESMOS: o "Juntar mensagens" le
    # `$('Transcrever').all()[0].json.text`, e a API devolve {text: "..."}.
    novo = {
        "parameters": {
            "method": "POST",
            "url": "https://api.openai.com/v1/audio/transcriptions",
            "authentication": "predefinedCredentialType",
            "nodeCredentialType": "openAiApi",
            "sendBody": True,
            "contentType": "multipart-form-data",
            "bodyParameters": {"parameters": [
                {"parameterType": "formBinaryData", "name": "file", "inputDataFieldName": "data"},
                {"name": "model", "value": "gpt-4o-transcribe"},
                {"name": "language", "value": "pt"},
                {"name": "prompt", "value": VOCABULARIO},
            ]},
            "options": {"timeout": 45000},
        },
        "name": "Transcrever",
        "type": "n8n-nodes-base.httpRequest",
        "typeVersion": 4.2,
        "id": antigo["id"],
        "position": antigo.get("position", [0, 0]),
        "credentials": antigo.get("credentials", {}),
        "onError": "continueRegularOutput",
    }
    w["nodes"] = [novo if n["name"] == "Transcrever" else n for n in w["nodes"]]

    limpo = {k: w[k] for k in ("id", "name", "nodes", "connections", "settings",
                               "staticData", "pinData", "active") if k in w}
    io.open(saida, "w", encoding="utf-8", newline="\n").write(
        json.dumps(limpo, ensure_ascii=False, indent=1))
    print("transcricao trocada | vocabulario: %d caracteres" % len(VOCABULARIO))


if __name__ == "__main__":
    main()
