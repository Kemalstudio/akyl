# Модели: что скачать и куда положить

Скачивание:

```powershell
powershell -ExecutionPolicy Bypass -File tools\fetch_models.ps1
```

Модели ложатся в `models/` — эта папка в `.gitignore`, в репозиторий они
не попадают.

## Набор v1.0

| Слой | Модель | Размер | Ссылка |
|---|---|---|---|
| VAD | `silero_vad.onnx` | ~2 МБ | [asr-models/silero_vad.onnx](https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/silero_vad.onnx) |
| STT | `sherpa-onnx-streaming-t-one-russian-2025-09-08` | 138 МБ (`model.onnx`) | [asr-models/…t-one-russian-2025-09-08.tar.bz2](https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/sherpa-onnx-streaming-t-one-russian-2025-09-08.tar.bz2) |
| TTS | `vits-piper-ru_RU-denis-medium` | ~63 МБ | [tts-models/vits-piper-ru_RU-denis-medium.tar.bz2](https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/vits-piper-ru_RU-denis-medium.tar.bz2) |

Что лежит внутри архива T-one (проверено по документации sherpa-onnx):

```
model.onnx    138M
tokens.txt    202B
0.wav          99K
README.md, LICENSE
```

Запуск через CLI sherpa-onnx — для проверки, что модель вообще работает:

```bash
./sherpa-onnx \
  --t-one-ctc-model=./sherpa-onnx-streaming-t-one-russian-2025-09-08/model.onnx \
  --tokens=./sherpa-onnx-streaming-t-one-russian-2025-09-08/tokens.txt \
  ./sherpa-onnx-streaming-t-one-russian-2025-09-08/0.wav
```

## Важное про T-one: 8 кГц

Модель обучена на телефонной речи и **ожидает 8000 Гц**. Микрофон Android
пишет 16 кГц, поэтому в конвейер между микрофоном и распознаванием нужна
передискретизация. Это не мелочь: без неё модель выдаёт мусор или пустоту.

Отсюда же следует, что «продиктовать длинное SMS» T-one будет делать хуже,
чем офлайн-модель на 16 кГц — на это и рассчитан кандидат GigaAM в v2
(ТЗ, раздел 4).

## Другие русские голоса Piper

Подтверждены `denis`, `dmitri`, `ruslan` (мужские). Женский голос
(в ТЗ указана `irina`) в найденной документации не подтверждён — перед тем
как закладывать его в v1.0, проверьте список на странице
[TTS-моделей sherpa-onnx](https://k2-fsa.github.io/sherpa/onnx/tts/all/).
Имя файла подставляется в `tools/fetch_models.ps1` в массив `$Models`.

## Лёгкий вариант для слабых телефонов

В ТЗ как запасной STT указан `vosk-model-small-streaming-ru`. Учтите: модели
Vosk — в формате Kaldi, и напрямую sherpa-onnx их не читает. Прежде чем
закладывать этот путь, нужно либо найти готовую сборку в релизах
`asr-models`, либо считать лёгким вариантом другую потоковую русскую модель
оттуда же. Пока этот пункт не проверен, в скрипте загрузки его нет.

## Размер APK

ТЗ ограничивает APK в 150 МБ, а T-one с Piper вместе дают около 200 МБ.
Выводов два, и выбрать нужно до этапа 2:

1. **Докачка при первом запуске.** APK маленький, модели тянутся один раз.
   Противоречит обещанию «работает сразу и без интернета», но только в первый
   запуск.
2. **Android App Bundle с asset packs.** Play доставляет модели отдельно,
   ограничение на APK обходится штатно.

Решение записывается в `docs/adr/` — сейчас оно не принято.

## Проверка даты

Данные сверены 28.09.2026 по документации sherpa-onnx. Перед стартом этапа 2
сверьте версии в релизах: имена архивов содержат дату и меняются.
