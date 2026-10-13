# Navegador do Agente OLX (admin > Agentes). Pedro, 13/10/2026.
#
# A OLX bloqueia navegador de servidor (Cloudflare: "you have been blocked"), entao o navegador do agente e um
# Chrome NORMAL neste computador, com perfil separado (nao mexe no seu Chrome de todo dia).
# Pedro, na mesma noite: "abriu e eu fechei, quero mexer nisso la pela aquela tela la". Por isso ele roda ESCONDIDO:
# nenhuma janela aparece aqui; tudo se ve e se faz pela tela do admin (inclusive o login da OLX).
#
#   navegador-olx.bat            liga (escondido): abre o Chrome do agente e o tunel ssh para a VPS2
#   navegador-olx.bat mostrar    traz a janela do Chrome do agente para a tela (se precisar mexer nela aqui)
#   navegador-olx.bat esconder   esconde de novo
#   navegador-olx.bat desligar   fecha o Chrome do agente (o tunel cai sozinho). Tambem da para desligar pela tela.
#
# O tunel publica a porta do Chrome so em 127.0.0.1:9303 da VPS2, que e onde o agente e a ponte do painel o procuram.
# Nada fica aberto para a internet.
param([string]$Modo = 'ligar')
$ErrorActionPreference = 'Continue'
$porta = 9377          # a porta do Chrome aqui (so 127.0.0.1)
$portaVps = 9303       # a porta na VPS2 (so 127.0.0.1 de la)
$vps = 'nay-srv1877774'
$perfil = Join-Path $env:LOCALAPPDATA 'NavegadorAgenteOLX'
$registro = Join-Path $perfil 'navegador-olx.log'

Add-Type -Namespace Nay -Name Janela -MemberDefinition @'
[DllImport("user32.dll")] public static extern bool ShowWindowAsync(IntPtr hWnd, int nCmdShow);
[DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr hWnd);
[DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint pid);
public delegate bool Visita(IntPtr hWnd, IntPtr l);
[DllImport("user32.dll")] public static extern bool EnumWindows(Visita f, IntPtr l);
[DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern int GetClassName(IntPtr hWnd, System.Text.StringBuilder s, int n);
'@

function Chrome-No-Ar {
  # ligacao direta na porta: o Invoke-WebRequest levava segundos a cada tentativa
  $c = New-Object System.Net.Sockets.TcpClient
  try {
    $pedido = $c.BeginConnect('127.0.0.1', $porta, $null, $null)
    $ok = $pedido.AsyncWaitHandle.WaitOne(700) -and $c.Connected
    return [bool]$ok
  } catch { return $false } finally { $c.Close() }
}
function Pid-Do-Chrome {
  $c = Get-NetTCPConnection -LocalPort $porta -State Listen -ErrorAction SilentlyContinue | Select-Object -First 1
  if ($c) { return [uint32]$c.OwningProcess }
  return [uint32]0
}
# as janelas de navegador (classe Chrome_WidgetWin_1) do Chrome do agente; $mostrar: 0 esconde, 9 traz de volta
function Janelas-Do-Agente([int]$mostrar) {
  $dono = Pid-Do-Chrome
  if ($dono -eq 0) { return }
  $achadas = New-Object System.Collections.ArrayList
  $visita = [Nay.Janela+Visita] {
    param($h, $l)
    $p = [uint32]0
    [void][Nay.Janela]::GetWindowThreadProcessId($h, [ref]$p)
    if ($p -eq $dono) {
      $nome = New-Object System.Text.StringBuilder 64
      [void][Nay.Janela]::GetClassName($h, $nome, 64)
      if ($nome.ToString() -eq 'Chrome_WidgetWin_1') { [void]$achadas.Add($h) }
    }
    return $true
  }
  [void][Nay.Janela]::EnumWindows($visita, [IntPtr]::Zero)
  foreach ($h in $achadas) {
    $visivel = [Nay.Janela]::IsWindowVisible($h)
    if ($mostrar -eq 0 -and $visivel) { [void][Nay.Janela]::ShowWindowAsync($h, 0) }
    if ($mostrar -ne 0 -and -not $visivel) { [void][Nay.Janela]::ShowWindowAsync($h, $mostrar) }
  }
}
function Anota($texto) {
  try { Add-Content -Path $registro -Value "$(Get-Date -Format 'dd/MM HH:mm:ss') $texto" -Encoding utf8 } catch {}
}

if ($Modo -eq 'mostrar') { Janelas-Do-Agente 9; exit 0 }
if ($Modo -eq 'esconder') { Janelas-Do-Agente 0; exit 0 }
if ($Modo -eq 'desligar') {
  $dono = Pid-Do-Chrome
  if ($dono -ne 0) { $p = Get-Process -Id $dono -ErrorAction SilentlyContinue; if ($p -and $p.ProcessName -eq 'chrome') { Stop-Process -Id $dono -Force -Confirm:$false } }
  exit 0
}

# --- ligar (um so de cada vez)
$unico = New-Object System.Threading.Mutex($false, 'NavegadorAgenteOLX')
if (-not $unico.WaitOne(0)) { exit 0 }
New-Item -ItemType Directory -Force $perfil | Out-Null
$chrome = @("$env:ProgramFiles\Google\Chrome\Application\chrome.exe",
            "${env:ProgramFiles(x86)}\Google\Chrome\Application\chrome.exe",
            "$env:LOCALAPPDATA\Google\Chrome\Application\chrome.exe") | Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $chrome) { Anota 'nao achei o Google Chrome instalado'; exit 1 }
$ssh = 'C:\Program Files\Git\usr\bin\ssh.exe'
if (-not (Test-Path $ssh)) { $ssh = (Get-Command ssh -ErrorAction SilentlyContinue).Source }
if (-not $ssh) { Anota 'nao achei o ssh'; exit 1 }

if (-not (Chrome-No-Ar)) {
  # as tres opcoes de "background" deixam a pagina desenhando com a janela escondida: e o que o agente e a tela do admin veem
  Start-Process -FilePath $chrome -WindowStyle Minimized -ArgumentList @("--remote-debugging-port=$porta", "--user-data-dir=`"$perfil`"",
    '--no-first-run', '--no-default-browser-check', '--disable-backgrounding-occluded-windows',
    '--disable-renderer-backgrounding', '--disable-background-timer-throttling', '--window-size=1366,900',
    'https://conta.olx.com.br/acesso')
  foreach ($i in 1..40) { if (Chrome-No-Ar) { break }; Start-Sleep -Milliseconds 500 }
}
if (-not (Chrome-No-Ar)) { Anota 'o Chrome do agente nao abriu'; exit 1 }
Anota "ligado (Chrome do agente, pid $(Pid-Do-Chrome))"

$tunel = $null
while ($true) {
  if (-not (Chrome-No-Ar)) { Start-Sleep -Seconds 2; if (-not (Chrome-No-Ar)) { Anota 'o Chrome do agente foi fechado; encerrando'; break } }
  Janelas-Do-Agente 0      # janela nova (popup de login, por exemplo) tambem fica escondida: ela aparece como aba na tela do admin
  if ($null -eq $tunel -or $tunel.HasExited) {
    if ($null -ne $tunel) { Anota 'a ligacao com a VPS caiu; ligando de novo'; Start-Sleep -Seconds 4 }
    $tunel = Start-Process -FilePath $ssh -WindowStyle Hidden -PassThru -ArgumentList @('-N', '-o', 'ExitOnForwardFailure=yes',
      '-o', 'ServerAliveInterval=30', '-o', 'ServerAliveCountMax=3', '-o', 'BatchMode=yes', '-o', 'ConnectTimeout=20',
      '-R', "127.0.0.1:${portaVps}:127.0.0.1:${porta}", $vps)
  }
  Start-Sleep -Seconds 3
}
if ($null -ne $tunel -and -not $tunel.HasExited) { Stop-Process -Id $tunel.Id -Force -Confirm:$false }
$unico.ReleaseMutex()
