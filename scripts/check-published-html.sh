#!/usr/bin/env bash
# check-published-html.sh — проверка клиентских HTML перед публикацией.
#
# Использование:
#   bash scripts/check-published-html.sh docs/
#   bash scripts/check-published-html.sh docs/mdo-a7k29q/index.html
#
# Проверяет каждую страницу на:
#   - noindex
#   - мобильный viewport
#   - отсутствие file://
#   - отсутствие локальных путей (C:\, /Users/, /home/)
#   - отсутствие внешних скриптов
#   - отсутствие реальных form action
#   - отсутствие password inputs
#   - отсутствие незамененных {{...}}
#   - наличие демонстрационного предупреждения
#
# Коды возврата: 0 — все чисто, 1 — есть проблемы.

set -uo pipefail

cd "$(dirname "$0")/.." || exit 1

TARGET="${1:-docs/}"

if [ ! -e "$TARGET" ]; then
  echo "Путь не найден: $TARGET"
  exit 1
fi

# Главная docs/index.html — служебная заглушка, не клиентское демо.
# Она проверяется в validate-project.sh и здесь пропускается.
SKIP_INDEX="docs/index.html"

TOTAL=0
BADFILES=0

check_file() {
  local f="$1"
  local problems=0

  echo
  echo "--- $f"

  # noindex
  if grep -qi 'name=["'"'"']robots["'"'"'][^>]*noindex' "$f"; then
    echo "  [ok]   noindex"
  else
    echo "  [FAIL] нет noindex"; problems=$((problems + 1))
  fi

  # viewport
  if grep -qi 'name=["'"'"']viewport["'"'"'][^>]*width=device-width' "$f"; then
    echo "  [ok]   мобильный viewport"
  else
    echo "  [FAIL] нет мобильного viewport"; problems=$((problems + 1))
  fi

  # file://
  if grep -qi 'file://' "$f"; then
    echo "  [FAIL] найден file://"; problems=$((problems + 1))
  else
    echo "  [ok]   file:// нет"
  fi

  # локальные пути
  if grep -qiE '[A-Z]:\\\\|[A-Z]:/Users/|/Users/[a-zA-Z]|/home/[a-zA-Z]' "$f"; then
    echo "  [FAIL] найден локальный путь (C:\\, /Users/, /home/)"; problems=$((problems + 1))
  else
    echo "  [ok]   локальных путей нет"
  fi

  # внешние скрипты
  if grep -qiE '<script[^>]+src=["'"'"']?(https?:)?//' "$f"; then
    echo "  [FAIL] внешний <script src>"; problems=$((problems + 1))
  else
    echo "  [ok]   внешних скриптов нет"
  fi

  # внешние стили / шрифты
  if grep -qiE '<link[^>]+href=["'"'"']?(https?:)?//' "$f"; then
    echo "  [FAIL] внешний <link href> (стили/шрифты с CDN)"; problems=$((problems + 1))
  else
    echo "  [ok]   внешних стилей нет"
  fi

  # реальная отправка формы
  if grep -qiE '<form[^>]+action=["'"'"']?[^"'"'"'#>][^"'"'"'>]*' "$f"; then
    echo "  [FAIL] <form action> с реальной отправкой"; problems=$((problems + 1))
  else
    echo "  [ok]   form action нет"
  fi

  # сетевые вызовы
  if grep -qiE '\bfetch\s*\(|XMLHttpRequest|sendBeacon|\bWebSocket\s*\(' "$f"; then
    echo "  [FAIL] найден сетевой вызов (fetch/XHR/sendBeacon/WebSocket)"; problems=$((problems + 1))
  else
    echo "  [ok]   сетевых вызовов нет"
  fi

  # password input
  if grep -qiE '<input[^>]+type=["'"'"']?password' "$f"; then
    echo "  [FAIL] найден password input"; problems=$((problems + 1))
  else
    echo "  [ok]   password inputs нет"
  fi

  # незамененные плейсхолдеры
  # Показываем и именованные {{NAME}}, и любые прочие вхождения "{{",
  # иначе список выходит пустым и проблему невозможно найти.
  if grep -q '{{' "$f"; then
    echo "  [FAIL] незамененные плейсхолдеры:"
    named="$(grep -o '{{[A-Za-z0-9_]*}}' "$f" | sort -u)"
    if [ -n "$named" ]; then
      echo "$named" | sed 's/^/           /'
    fi
    echo "$(grep -n '{{' "$f" | head -5 | cut -c1-90)" | sed 's/^/           строка /'
    problems=$((problems + 1))
  else
    echo "  [ok]   плейсхолдеров нет"
  fi

  # демонстрационное предупреждение
  if grep -qi 'демонстрацион' "$f"; then
    echo "  [ok]   демонстрационное предупреждение"
  else
    echo "  [FAIL] нет предупреждения о демонстрационном характере"; problems=$((problems + 1))
  fi

  if [ "$problems" -gt 0 ]; then
    BADFILES=$((BADFILES + 1))
    echo "  => проблем: $problems"
  else
    echo "  => чисто"
  fi
}

echo "== check-published-html =="
echo "цель: $TARGET"

if [ -f "$TARGET" ]; then
  TOTAL=1
  check_file "$TARGET"
else
  while IFS= read -r f; do
    [ -z "$f" ] && continue
    if [ "$f" = "$SKIP_INDEX" ] || [ "$f" = "./$SKIP_INDEX" ]; then
      echo
      echo "--- $f (служебная главная, пропущена)"
      continue
    fi
    TOTAL=$((TOTAL + 1))
    check_file "$f"
  done < <(find "$TARGET" -type f -name '*.html' | sed 's|^\./||' | sort)
fi

echo
echo "== итог =="
echo "  проверено файлов: $TOTAL"
echo "  с проблемами:     $BADFILES"
echo

if [ "$TOTAL" -eq 0 ]; then
  echo "РЕЗУЛЬТАТ: клиентских HTML не найдено (это нормально до создания демо)."
  exit 0
fi

if [ "$BADFILES" -gt 0 ]; then
  echo "РЕЗУЛЬТАТ: публиковать НЕЛЬЗЯ. Исправьте проблемы выше."
  exit 1
fi

echo "РЕЗУЛЬТАТ: все страницы прошли проверку."
exit 0
