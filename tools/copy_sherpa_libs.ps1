# Копирует нативные библиотеки sherpa-onnx (arm64) из кэша pub в локальный
# пакет app/packages/sherpa_onnx_android_arm64. Запускать после
# `flutter pub get`, до сборки APK:
#
#     powershell -ExecutionPolicy Bypass -File tools\copy_sherpa_libs.ps1
#
# Зачем локальный пакет — см. комментарий у dependency_overrides в app/pubspec.yaml.

$ErrorActionPreference = "Stop"
$Version = "1.13.8"
$Source = Join-Path $env:LOCALAPPDATA "Pub\Cache\hosted\pub.dev\sherpa_onnx_android_arm64-$Version\android\src\main\jniLibs\arm64-v8a"
$Target = Join-Path $PSScriptRoot "..\app\packages\sherpa_onnx_android_arm64\android\src\main\jniLibs\arm64-v8a"

if (-not (Test-Path $Source)) {
    # Пакет в кэш кладёт pub даже при override — достаточно одного pub get
    # с исходным pubspec или `dart pub cache add`.
    & dart pub cache add sherpa_onnx_android_arm64 --version $Version
}

New-Item -ItemType Directory -Force $Target | Out-Null
Copy-Item (Join-Path $Source "*.so") $Target -Force
Get-ChildItem $Target | Format-Table Name, Length
