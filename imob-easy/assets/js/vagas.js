/* ==========================================================================
   Imob Easy — Página de vagas (/vagas-manaus)
   Vídeo, currículo (clique ou arraste), validação e envio para a API.
   O envio vai para API_BASE/api/vagas/candidatura (config.js).
   ========================================================================== */
(function () {
  "use strict";

  var TETO = 5 * 1024 * 1024;
  var EXTENSOES = [".pdf", ".doc", ".docx"];

  /* ----------------------------------------------------------------- Vídeo */
  /* O link fica em data-video, no HTML. YouTube em qualquer formato de link,
     ou um .mp4. Vazio: fica o aviso de "em breve". */
  function idDoYoutube(url) {
    var m = String(url).match(/(?:youtu\.be\/|youtube(?:-nocookie)?\.com\/(?:watch\?(?:.*&)?v=|embed\/|shorts\/|live\/))([A-Za-z0-9_-]{11})/);
    return m ? m[1] : null;
  }

  var quadro = document.getElementById("vaga-video");
  var url = quadro ? (quadro.getAttribute("data-video") || "").trim() : "";
  if (quadro && url) {
    var yt = idDoYoutube(url);
    if (yt) {
      var f = document.createElement("iframe");
      f.src = "https://www.youtube-nocookie.com/embed/" + yt + "?rel=0";
      f.title = "Vídeo da vaga de SDR";
      f.loading = "lazy";
      f.allow = "accelerometer; encrypted-media; gyroscope; picture-in-picture; fullscreen";
      f.allowFullscreen = true;
      quadro.innerHTML = "";
      quadro.appendChild(f);
    } else if (/\.(mp4|webm)(\?|$)/i.test(url)) {
      var v = document.createElement("video");
      v.src = url;
      v.controls = true;
      v.preload = "metadata";
      v.playsInline = true;
      quadro.innerHTML = "";
      quadro.appendChild(v);
    }
  }

  /* ------------------------------------------------------------ Formulário */
  var form = document.getElementById("vg-form");
  if (!form) return;

  var arquivoRotulo = document.getElementById("vg-arquivo");
  var arquivoInput = document.getElementById("vg-curriculo");
  var arquivoTexto = document.getElementById("vg-arquivo-texto");
  var textoOriginal = arquivoTexto.innerHTML;
  var aviso = document.getElementById("vg-aviso");
  var botao = document.getElementById("vg-enviar");
  var porque = document.getElementById("vg-porque");
  var porqueN = document.getElementById("vg-porque-n");

  function esc(s) {
    return String(s).replace(/[&<>"']/g, function (c) {
      return { "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c];
    });
  }

  function tamanho(b) {
    return b >= 1048576 ? (b / 1048576).toFixed(1).replace(".", ",") + " MB" : Math.max(1, Math.round(b / 1024)) + " KB";
  }

  function arquivoValido(a) {
    if (!a) return false;
    var nome = a.name.toLowerCase();
    var ok = EXTENSOES.some(function (e) { return nome.slice(-e.length) === e; });
    return ok && a.size > 0 && a.size <= TETO;
  }

  function mostrarArquivo() {
    var a = arquivoInput.files && arquivoInput.files[0];
    arquivoRotulo.classList.remove("tem-arquivo");
    if (!a) { arquivoTexto.innerHTML = textoOriginal; return; }
    if (arquivoValido(a)) {
      arquivoRotulo.classList.add("tem-arquivo");
      arquivoTexto.innerHTML = "<strong>" + esc(a.name) + "</strong> · " + tamanho(a.size) +
        "<br><span class=\"vg-arquivo__regra\">Clique para trocar</span>";
      limparErro("curriculo");
    } else {
      arquivoTexto.innerHTML = textoOriginal;
      marcarErro("curriculo");
    }
  }

  arquivoInput.addEventListener("change", mostrarArquivo);

  ["dragenter", "dragover"].forEach(function (ev) {
    arquivoRotulo.addEventListener(ev, function (e) {
      e.preventDefault();
      arquivoRotulo.classList.add("arrastando");
    });
  });
  ["dragleave", "dragend", "drop"].forEach(function (ev) {
    arquivoRotulo.addEventListener(ev, function () { arquivoRotulo.classList.remove("arrastando"); });
  });
  arquivoRotulo.addEventListener("drop", function (e) {
    e.preventDefault();
    if (e.dataTransfer && e.dataTransfer.files && e.dataTransfer.files.length) {
      arquivoInput.files = e.dataTransfer.files;
      mostrarArquivo();
    }
  });

  porque.addEventListener("input", function () { porqueN.textContent = porque.value.length; });

  /* Máscara leve do WhatsApp: (92) 9 1234-5678 */
  var zap = document.getElementById("vg-whatsapp");
  zap.addEventListener("input", function () {
    var d = zap.value.replace(/\D/g, "");
    if (d.length > 11 && d.indexOf("55") === 0) d = d.slice(2);
    d = d.slice(0, 11);
    var s = d;
    if (d.length > 2) s = "(" + d.slice(0, 2) + ") " + d.slice(2);
    if (d.length > 3 && d.length === 11) s = "(" + d.slice(0, 2) + ") " + d.slice(2, 3) + " " + d.slice(3, 7) + "-" + d.slice(7);
    else if (d.length > 6) s = "(" + d.slice(0, 2) + ") " + d.slice(2, 6) + "-" + d.slice(6);
    zap.value = s;
  });

  /* ------------------------------------------------------------ Validação */
  function caixaDe(nome) {
    if (nome === "curriculo") return arquivoRotulo;
    if (nome === "consentimento") return form.querySelector(".vg-consentimento");
    var el = form.elements[nome];
    if (!el) return null;
    var alvo = el.length && !el.tagName ? el[0] : el;
    return alvo.closest(".vg-campo");
  }
  function marcarErro(nome) {
    var c = caixaDe(nome);
    if (c) c.classList.add("tem-erro");
    var msg = form.querySelector('[data-erro-de="' + nome + '"]');
    if (msg) msg.classList.add("visivel");
  }
  function limparErro(nome) {
    var c = caixaDe(nome);
    if (c) c.classList.remove("tem-erro");
    var msg = form.querySelector('[data-erro-de="' + nome + '"]');
    if (msg) msg.classList.remove("visivel");
  }

  form.addEventListener("input", function (e) { if (e.target.name) limparErro(e.target.name); });
  form.addEventListener("change", function (e) { if (e.target.name && e.target.name !== "curriculo") limparErro(e.target.name); });

  function validar() {
    var erros = [];
    var v = function (n) { return (form.elements[n].value || "").trim(); };
    if (v("nome").length < 3) erros.push("nome");
    var d = v("whatsapp").replace(/\D/g, "");
    if (d.indexOf("55") === 0 && d.length > 11) d = d.slice(2);
    if (d.length < 10 || d.length > 11) erros.push("whatsapp");
    if (!/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(v("email"))) erros.push("email");
    if (!v("experiencia_vendas")) erros.push("experiencia_vendas");
    if (!form.querySelector('input[name="experiencia_imobiliaria"]:checked')) erros.push("experiencia_imobiliaria");
    if (!form.querySelector('input[name="disponibilidade"]:checked')) erros.push("disponibilidade");
    if (!arquivoValido(arquivoInput.files && arquivoInput.files[0])) erros.push("curriculo");
    if (!form.elements.consentimento.checked) erros.push("consentimento");
    erros.forEach(marcarErro);
    return erros;
  }

  /* ---------------------------------------------------------------- Envio */
  form.addEventListener("submit", function (e) {
    e.preventDefault();
    aviso.hidden = true;
    var erros = validar();
    if (erros.length) {
      var primeiro = caixaDe(erros[0]);
      if (primeiro) {
        primeiro.scrollIntoView({ behavior: "smooth", block: "center" });
        var foco = primeiro.querySelector("input, select, textarea");
        if (foco) foco.focus({ preventScroll: true });
      }
      return;
    }

    botao.classList.add("enviando");
    botao.querySelector(".vg-enviar__texto").textContent = "Enviando…";

    fetch((window.API_BASE || "") + "/api/vagas/candidatura", { method: "POST", body: new FormData(form) })
      .then(function (r) {
        return r.json().catch(function () { return { ok: false }; }).then(function (j) { return { status: r.status, j: j }; });
      })
      .then(function (res) {
        if (res.j && res.j.ok) {
          var primeiroNome = (form.elements.nome.value || "").trim().split(/\s+/)[0];
          var titulo = document.getElementById("vg-sucesso-titulo");
          if (primeiroNome) titulo.textContent = "Candidatura recebida, " + primeiroNome + "!";
          form.hidden = true;
          var ok = document.getElementById("vg-sucesso");
          ok.hidden = false;
          ok.scrollIntoView({ behavior: "smooth", block: "center" });
          ok.focus({ preventScroll: true });
          return;
        }
        if (res.j && res.j.campo) marcarErro(res.j.campo);
        falhou((res.j && res.j.erro) || "Não conseguimos enviar agora. Tente de novo em instantes.");
      })
      .catch(function () {
        falhou("Sem conexão com o servidor. Confira sua internet e tente de novo.");
      });
  });

  function falhou(msg) {
    botao.classList.remove("enviando");
    botao.querySelector(".vg-enviar__texto").textContent = "Enviar candidatura";
    aviso.textContent = msg;
    aviso.hidden = false;
  }
})();
