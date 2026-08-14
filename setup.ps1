# ============================================================
# setup.ps1  –  Configuração completa do Flexão 3000
# Rode como Administrador: clique direito > Executar como admin
# ============================================================

$ErrorActionPreference = "Stop"
$FlutterDir = "C:\flutter"
$ProjectDir = "C:\Projeto Flexão\Outro-Claude\Flexao3000"

Write-Host "`n=== Flexão 3000 - Setup ===" -ForegroundColor Green

# ── 1. Baixar e instalar Flutter SDK ───────────────────────
if (-not (Test-Path "$FlutterDir\bin\flutter.bat")) {
    Write-Host "`n[1/5] Baixando Flutter SDK (~700 MB)..." -ForegroundColor Cyan

    # Pega a URL do release estável mais recente
    $releasesUrl = "https://storage.googleapis.com/flutter_infra_release/releases/releases_windows.json"
    Write-Host "  Consultando versão mais recente..."
    $releases = Invoke-RestMethod -Uri $releasesUrl
    $latestHash = $releases.current_release.stable
    $latestRelease = $releases.releases | Where-Object { $_.hash -eq $latestHash } | Select-Object -First 1
    $downloadUrl = "https://storage.googleapis.com/$($latestRelease.archive)"
    $zipPath = "C:\flutter_sdk.zip"

    Write-Host "  Versão: $($latestRelease.version)"
    Write-Host "  Baixando de $downloadUrl ..."
    Invoke-WebRequest -Uri $downloadUrl -OutFile $zipPath -UseBasicParsing

    Write-Host "  Extraindo para C:\..."
    Expand-Archive -Path $zipPath -DestinationPath "C:\" -Force
    Remove-Item $zipPath
    Write-Host "  Flutter SDK instalado em $FlutterDir" -ForegroundColor Green
} else {
    Write-Host "`n[1/5] Flutter SDK já encontrado em $FlutterDir" -ForegroundColor Green
}

# Adiciona Flutter ao PATH da sessão atual
$env:PATH = "$FlutterDir\bin;$env:PATH"

# ── 2. Aceitar licenças Android ────────────────────────────
Write-Host "`n[2/5] Aceitando licenças do Android SDK..." -ForegroundColor Cyan
try {
    echo "y`ny`ny`ny`ny`ny`n" | & "$FlutterDir\bin\flutter.bat" doctor --android-licenses 2>&1 | Out-Null
} catch {
    Write-Host "  Aviso: não foi possível aceitar licenças automaticamente." -ForegroundColor Yellow
    Write-Host "  Execute manualmente: flutter doctor --android-licenses" -ForegroundColor Yellow
}

# ── 3. Criar estrutura do projeto Flutter ──────────────────
Write-Host "`n[3/5] Criando estrutura do projeto Flutter..." -ForegroundColor Cyan
Push-Location $ProjectDir

# Salva nosso main.dart antes do flutter create sobrescrever
$ourMain = Get-Content "lib\main.dart" -Raw -ErrorAction SilentlyContinue

& "$FlutterDir\bin\flutter.bat" create `
    --project-name flexao_3000 `
    --org com.ativore.flexao `
    --platforms android `
    . 2>&1 | Where-Object { $_ -notmatch "^  •|^\s*$" }

# Restaura nosso main.dart
if ($ourMain) {
    Set-Content -Path "lib\main.dart" -Value $ourMain -NoNewline
    Write-Host "  main.dart restaurado com sucesso." -ForegroundColor Green
} else {
    Write-Host "  AVISO: lib\main.dart não foi encontrado antes do create." -ForegroundColor Yellow
}

# ── 4. Instalar dependências ────────────────────────────────
Write-Host "`n[4/5] Instalando dependências (flutter pub get)..." -ForegroundColor Cyan
& "$FlutterDir\bin\flutter.bat" pub get

# ── 5. Build APK release ────────────────────────────────────
Write-Host "`n[5/5] Gerando APK release..." -ForegroundColor Cyan
& "$FlutterDir\bin\flutter.bat" build apk --release

$apkPath = "$ProjectDir\build\app\outputs\flutter-apk\app-release.apk"
if (Test-Path $apkPath) {
    Write-Host "`n✅ APK gerado com sucesso!" -ForegroundColor Green
    Write-Host "   Caminho: $apkPath" -ForegroundColor White
    Write-Host ""
    Write-Host "📲 Para instalar nos celulares dos amigos:" -ForegroundColor Cyan
    Write-Host "   1. Envie o arquivo APK (WhatsApp, Google Drive, etc.)"
    Write-Host "   2. No celular: Configurações > Instalar apps desconhecidos > Permitir"
    Write-Host "   3. Abra o APK e instale"
    Write-Host ""
    Write-Host "🌐 Banco de dados:" -ForegroundColor Cyan
    Write-Host "   Supabase: https://supabase.com/dashboard/project/fvsynfsljatdbevbgmsk"
    Write-Host ""

    # Abre a pasta do APK no Explorer
    explorer.exe (Split-Path $apkPath)
} else {
    Write-Host "`n⚠️  APK não foi gerado. Verifique os erros acima." -ForegroundColor Yellow
    Write-Host "   Tente rodar: flutter doctor" -ForegroundColor Yellow
}

Pop-Location
Write-Host "`n=== Concluído ===" -ForegroundColor Green
