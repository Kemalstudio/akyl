"""Генератор фирменного знака и иконок Android для Akyl.

Знак — сплошной треугольник со скруглёнными углами, рассечённый горизонтальным
вырезом. Верхняя часть читается как «А», нижняя — как строка речи под ней.
Одна форма, один цвет, никаких градиентов и теней: так знак остаётся
различимым и на 48 px в списке приложений, и на экране приветствия.
Тот же контур повторяет AkylMark на Dart
(app/lib/presentation/widgets/akyl_mark.dart) — PNG нужны только Android
для иконки запуска и заставки.

Запуск:
    python tools/make_icons.py

Требуется Pillow. Скрипт перезаписывает файлы в app/android/.../mipmap-* и
assets/brand/.
"""

from __future__ import annotations

import os
import sys

from PIL import Image, ImageDraw

# Консоль Windows по умолчанию не в UTF-8, а сообщения здесь по-русски.
if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")

# --- Геометрия знака (в системе координат 1024x1024) ------------------------

CANVAS = 1024

# Треугольник задаётся вершинами, углы скругляются обводкой того же цвета.
APEX = (512, 196)
BOTTOM_LEFT = (208, 824)
BOTTOM_RIGHT = (816, 824)
CORNER_RADIUS = 62

# Горизонтальный вырез: он и есть перекладина «А». Вырез не доходит до правого
# края — иначе знак распадается на две фигуры и начинает читаться как значок
# «извлечь» (⏏). Асимметрия оставляет знак цельным и узнаваемым.
GAP_TOP = 638
GAP_BOTTOM = 710
GAP_RIGHT = 700

# Рисуем в четыре раза крупнее и уменьшаем: даёт чистое сглаживание без
# дополнительных библиотек.
SUPERSAMPLE = 4

# --- Цвета ------------------------------------------------------------------

INK = (14, 16, 20, 255)          # почти чёрный: знак на светлом фоне
PAPER = (242, 244, 243, 255)     # почти белый: знак на тёмном фоне
ICON_BACKGROUND = (16, 18, 20, 255)

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ANDROID_RES = os.path.join(ROOT, "app", "android", "app", "src", "main", "res")
BRAND_DIR = os.path.join(ROOT, "assets", "brand")


def _mark_mask(work: int, unit: float, offset: float) -> Image.Image:
    """Маска знака: треугольник со скруглёнными углами минус вырез."""
    mask = Image.new("L", (work, work), 0)
    draw = ImageDraw.Draw(mask)

    def point(p: tuple[float, float]) -> tuple[float, float]:
        return (offset + p[0] * unit, offset + p[1] * unit)

    corners = [point(APEX), point(BOTTOM_RIGHT), point(BOTTOM_LEFT)]
    draw.polygon(corners, fill=255)

    # Скругление углов: обводка замкнутого контура толщиной в два радиуса
    # плюс круги в вершинах. Треугольник задан с запасом на эту обводку.
    radius = CORNER_RADIUS * unit
    draw.line(corners + [corners[0]], fill=255, width=max(1, round(radius * 2)),
              joint="curve")
    for x, y in corners:
        draw.ellipse([x - radius, y - radius, x + radius, y + radius], fill=255)

    # Вырез слева направо, но не до конца: правая грань остаётся сплошной.
    draw.rectangle(
        [
            0,
            offset + GAP_TOP * unit,
            offset + GAP_RIGHT * unit,
            offset + GAP_BOTTOM * unit,
        ],
        fill=0,
    )
    return mask


def draw_mark(size: int, color: tuple[int, int, int, int], scale: float = 1.0) -> Image.Image:
    """Знак на прозрачном фоне.

    scale — доля канвы, которую занимает знак. Для иконки Android содержимое
    должно уместиться в центральные 66% (безопасная зона adaptive icon).
    """
    work = size * SUPERSAMPLE
    unit = work / CANVAS * scale
    offset = (work - CANVAS * unit) / 2

    mask = _mark_mask(work, unit, offset)
    image = Image.new("RGBA", (work, work), color[:3] + (0,))
    image.putalpha(mask.point(lambda v: v * color[3] // 255))
    return image.resize((size, size), Image.LANCZOS)


def squircle_mask(size: int, radius_ratio: float = 0.22) -> Image.Image:
    """Маска скруглённого квадрата — для старых пусковых иконок без adaptive."""
    work = size * SUPERSAMPLE
    mask = Image.new("L", (work, work), 0)
    ImageDraw.Draw(mask).rounded_rectangle(
        [0, 0, work - 1, work - 1],
        radius=int(work * radius_ratio),
        fill=255,
    )
    return mask.resize((size, size), Image.LANCZOS)


def circle_mask(size: int) -> Image.Image:
    work = size * SUPERSAMPLE
    mask = Image.new("L", (work, work), 0)
    ImageDraw.Draw(mask).ellipse([0, 0, work - 1, work - 1], fill=255)
    return mask.resize((size, size), Image.LANCZOS)


def legacy_icon(size: int, mask: Image.Image) -> Image.Image:
    """Иконка целиком: тёмная плашка со светлым знаком."""
    base = Image.new("RGBA", (size, size), ICON_BACKGROUND)
    base.alpha_composite(draw_mark(size, PAPER, scale=0.60))
    result = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    result.paste(base, (0, 0), mask)
    return result


def write(image: Image.Image, *path_parts: str) -> None:
    path = os.path.join(*path_parts)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    image.save(path, "PNG")
    print("  ", os.path.relpath(path, ROOT))


def main() -> None:
    # Плотности Android: множитель к 48dp для пусковой иконки и к 108dp
    # для слоёв adaptive icon.
    densities = {
        "mdpi": 1.0,
        "hdpi": 1.5,
        "xhdpi": 2.0,
        "xxhdpi": 3.0,
        "xxxhdpi": 4.0,
    }

    print("Иконки Android:")
    for name, factor in densities.items():
        folder = os.path.join(ANDROID_RES, f"mipmap-{name}")
        legacy_size = round(48 * factor)
        adaptive_size = round(108 * factor)

        write(legacy_icon(legacy_size, squircle_mask(legacy_size)),
              folder, "ic_launcher.png")
        write(legacy_icon(legacy_size, circle_mask(legacy_size)),
              folder, "ic_launcher_round.png")

        # Слои adaptive icon: система сама обрежет их по своей маске, поэтому
        # знак занимает только безопасную зону.
        foreground = Image.new("RGBA", (adaptive_size, adaptive_size), (0, 0, 0, 0))
        foreground.alpha_composite(draw_mark(adaptive_size, PAPER, scale=0.42))
        write(foreground, folder, "ic_launcher_foreground.png")

        # Слой для тематических иконок Android 13+: только форма, цвет задаёт система.
        monochrome = Image.new("RGBA", (adaptive_size, adaptive_size), (0, 0, 0, 0))
        monochrome.alpha_composite(
            draw_mark(adaptive_size, (255, 255, 255, 255), scale=0.42)
        )
        write(monochrome, folder, "ic_launcher_monochrome.png")

    print("Знак для заставки и магазина:")
    write(draw_mark(1024, PAPER, scale=0.62), BRAND_DIR, "akyl_mark_on_dark.png")
    write(draw_mark(1024, INK, scale=0.62), BRAND_DIR, "akyl_mark_on_light.png")

    # Заставка: Flutter показывает её как drawable, поэтому нужен один слой
    # со знаком без фона — фон задаётся в launch_background.xml.
    for name, factor in densities.items():
        size = round(96 * factor)
        write(draw_mark(size, PAPER, scale=0.72),
              ANDROID_RES, f"drawable-{name}", "splash_mark.png")

    store = Image.new("RGBA", (512, 512), ICON_BACKGROUND)
    store.alpha_composite(draw_mark(512, PAPER, scale=0.60))
    write(store, BRAND_DIR, "play_store_512.png")


if __name__ == "__main__":
    main()
