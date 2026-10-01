#!/usr/bin/env python3
"""
auto_commit.py — автоматически коммитит КАЖДЫЙ изменённый/новый файл
отдельным коммитом, используя в качестве сообщения коммита номер версии
вида "X.Y", продолжая нумерацию с последнего такого коммита в истории.

Пример:
  Последний коммит в репозитории называется "1.36".
  У вас 5 изменённых/новых файлов (git status их видит).
  Запускаете скрипт — получаете 5 новых коммитов:
    1.37, 1.38, 1.39, 1.40, 1.41
  (каждый коммит содержит ровно один файл).

Использование:
  python3 auto_commit.py --dry-run              # посмотреть, что будет сделано, ничего не коммитить
  python3 auto_commit.py                        # закоммитить всё локально, без пуша
  python3 auto_commit.py --push                 # после КАЖДОГО коммита сразу делать git push
  python3 auto_commit.py --push --delay 5       # то же самое + пауза 5 секунд между коммитами
  python3 auto_commit.py --repo /path/to/repo
  python3 auto_commit.py --start 1.37           # задать номер вручную (если в истории
                                                 # ещё нет ни одного коммита вида X.Y)

По умолчанию скрипт ничего не пушит — только делает локальные коммиты.
С флагом --push после каждого отдельного коммита будет сразу выполняться
`git push`, как и просили: коммит 1.14 -> push -> (пауза) -> коммит 1.15 -> push -> ...

Если push на каком-то файле не получится (нет сети, нужен логин и т.п.),
скрипт остановится на этом месте — сам коммит уже сделан локально, ничего
не потеряется. Просто почините проблему (например, `git push` вручную) и
запустите скрипт заново — он продолжит с следующего незакоммиченного файла.
"""
import argparse
import re
import subprocess
import sys
import time

VERSION_RE = re.compile(r'^(\d+)\.(\d+)$')


def run(cmd, cwd=None):
    # git всегда пишет UTF-8, а на Windows text=True декодирует в cp1252
    # и падает на кириллице — поэтому кодировку задаём явно.
    result = subprocess.run(cmd, cwd=cwd, capture_output=True,
                            encoding='utf-8', errors='replace')
    if result.returncode != 0:
        raise RuntimeError(
            f"Команда не выполнилась: {' '.join(cmd)}\n{result.stderr.strip()}"
        )
    return result.stdout


def get_last_version(repo):
    """Идёт по логу коммитов (от новых к старым) и возвращает (major, minor)
    последнего коммита, чьё сообщение целиком выглядит как "X.Y".
    Если такого коммита нет — возвращает None."""
    log = run(['git', 'log', '--pretty=%s'], cwd=repo)
    for line in log.splitlines():
        m = VERSION_RE.match(line.strip())
        if m:
            return int(m.group(1)), int(m.group(2))
    return None


def get_changed_files(repo):
    """Возвращает список изменённых/новых/удалённых файлов из
    `git status --porcelain`, в том порядке, в котором их выдаёт git."""
    # -uall не сворачивает новые папки в одну строку — каждый файл внутри
    # новой директории тоже попадёт в список отдельно.
    # -z отдаёт пути как есть (без кавычек и \-экранирования кириллицы/пробелов),
    # записи разделены NUL.
    out = run(['git', 'status', '--porcelain', '-uall', '-z'], cwd=repo)
    entries = out.split('\0')
    files = []
    i = 0
    while i < len(entries):
        entry = entries[i]
        i += 1
        if not entry:
            continue
        status, path = entry[:2], entry[3:]
        # у переименований/копий следом идёт отдельная запись со старым
        # именем — пропускаем её, берём новое имя
        if 'R' in status or 'C' in status:
            i += 1
        files.append(path)
    return files


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--repo', default='.', help='Путь к git-репозиторию (по умолчанию текущая папка)')
    parser.add_argument('--start', help='Задать стартовую версию вручную, например 1.37, вместо автоопределения')
    parser.add_argument('--dry-run', action='store_true', help='Только показать, что будет сделано, не коммитить')
    parser.add_argument('--push', action='store_true', help='После каждого отдельного коммита сразу делать git push')
    parser.add_argument('--delay', type=float, default=0, help='Пауза в секундах между коммитами (по умолчанию 0)')
    args = parser.parse_args()

    repo = args.repo

    if args.start:
        m = VERSION_RE.match(args.start.strip())
        if not m:
            sys.exit(f"--start должен быть в формате X.Y, получено: {args.start}")
        major, minor = int(m.group(1)), int(m.group(2))
        # --start задаёт номер ПЕРВОГО нового коммита, поэтому уменьшаем на 1
        minor -= 1
    else:
        last = get_last_version(repo)
        if last is None:
            sys.exit(
                "Не найден ни один коммит вида \"X.Y\" в истории.\n"
                "Задайте стартовую версию вручную, например: --start 1.1"
            )
        major, minor = last

    files = get_changed_files(repo)
    if not files:
        print("Нет изменённых файлов для коммита (git status пуст).")
        return

    print(f"Найдено файлов: {len(files)}. Начинаю с версии {major}.{minor + 1}\n")

    made = []
    for i, path in enumerate(files):
        minor += 1
        version = f"{major}.{minor}"
        if args.dry_run:
            extra = " && git push" if args.push else ""
            print(f"[dry-run] git add -- {path!r} && git commit -m \"{version}\"{extra}")
            continue

        run(['git', 'add', '--', path], cwd=repo)
        run(['git', 'commit', '-m', version], cwd=repo)
        print(f"[{version}] {path}")

        if args.push:
            try:
                run(['git', 'push'], cwd=repo)
                print(f"    -> запушено ({version})")
            except RuntimeError as e:
                made.append((version, path))
                print(f"\nОШИБКА при push после коммита {version}:\n{e}")
                print(
                    f"Коммит {version} сделан локально, но не запушен.\n"
                    f"Сделано коммитов в этом запуске: {len(made)}.\n"
                    "Почините проблему (например, выполните `git push` вручную) "
                    "и запустите скрипт заново — он продолжит со следующего файла."
                )
                return

        made.append((version, path))

        # пауза перед следующим файлом (кроме самого последнего)
        if args.delay and i < len(files) - 1:
            time.sleep(args.delay)

    if not args.dry_run and made:
        print(f"\nГотово. Сделано коммитов: {len(made)}. Последняя версия: {made[-1][0]}")
        if not args.push:
            print("Пуш не выполнялся — сделайте `git push`, когда проверите.")


if __name__ == '__main__':
    main()
