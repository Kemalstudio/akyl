# Скачивает офлайн-модели для Akyl (ТЗ, раздел 4).
#
# Модели не хранятся в репозитории: вместе они весят больше 200 МБ. Скрипт
# кладёт их в models/ (папка в .gitignore), откуда сборка Android забирает их
# в assets — либо приложение докачивает их при первом запуске, если APK
# не должен превышать 150 МБ.
#
# Запуск:
#     powershell -ExecutionPolicy Bypass -File tools\fetch_models.ps1
#     powershell -ExecutionPolicy Bypass -File tools\fetch_models.ps1 -Light
#
# -Light  — только VAD и TTS, без T-one (138 МБ): для быстрой проверки сборки.

param(
    [switch]$Light,
    [string]$Destination = "models"
)

$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"  # иначе Invoke-WebRequest тормозит

$AsrRelease = "https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models"
$TtsRelease = "https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models"

# Имя, URL, примерный размер, для чего нужна.
$Models = @(
    @{
        Name    = "silero_vad.onnx"
        Url     = "$AsrRelease/silero_vad.onnx"
        Size    = "~2 МБ"
        Purpose = "Определение конца фразы, бюджет 300 мс"
        Light   = $true
    },
    @{
        Name    = "sherpa-onnx-streaming-t-one-russian-2025-09-08.tar.bz2"
        Url     = "$AsrRelease/sherpa-onnx-streaming-t-one-russian-2025-09-08.tar.bz2"
        Size    = "~138 МБ"
        Purpose = "Распознавание речи, основная модель (WER 5.83%)"
        Light   = $false
    },
    @{
        Name    = "vits-piper-ru_RU-denis-medium.tar.bz2"
        Url     = "$TtsRelease/vits-piper-ru_RU-denis-medium.tar.bz2"
        Size    = "~63 МБ"
        Purpose = "Голосовой ответ, мужской голос"
        Light   = $true
    }
)

function Expand-Archive-Tar {
    param([string]$Path, [string]$WorkDir)

    if (-not $Path.EndsWith(".tar.bz2")) { return }

    $folder = [System.IO.Path]::GetFileName($Path) -replace "\.tar\.bz2$", ""
    if (Test-Path (Join-Path $WorkDir $folder)) {
        Write-Host "    уже распаковано: $folder"
        return
    }

    Write-Host "    распаковка..."
    # tar есть в Windows 10 1803+ и умеет bz2.
    & tar -xf $Path -C $WorkDir
    if ($LASTEXITCODE -ne 0) {
        Write-Warning "    tar вернул $LASTEXITCODE — распакуйте архив вручную"
    }
}

$root = Split-Path -Parent $PSScriptRoot
$target = Join-Path $root $Destination
New-Item -ItemType Directory -Force -Path $target | Out-Null

Write-Host "Каталог моделей: $target"
Write-Host ""

foreach ($model in $Models) {
    if ($Light -and -not $model.Light) {
        Write-Host "[пропуск] $($model.Name) — режим -Light"
        continue
    }

    $path = Join-Path $target $model.Name
    Write-Host "[$($model.Size)] $($model.Name)"
    Write-Host "    $($model.Purpose)"

    if (Test-Path $path) {
        Write-Host "    уже скачано"
    } else {
        Write-Host "    загрузка..."
        try {
            Invoke-WebRequest -Uri $model.Url -OutFile $path -UseBasicParsing
        } catch {
            Write-Warning "    не удалось скачать: $($_.Exception.Message)"
            Write-Warning "    ссылка: $($model.Url)"
            continue
        }
    }

    Expand-Archive-Tar -Path $path -WorkDir $target
    Write-Host ""
}

Write-Host "Готово. Что дальше — docs/models.md"
