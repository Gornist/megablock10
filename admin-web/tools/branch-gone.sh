#!/usr/bin/env bash
# Можно ли удалять ветку (только чтение). `git cherry` врёт, когда ветку влили пересборкой, поэтому сравниваем СОДЕРЖИМОЕ:
# для каждого файла, который ветка меняла относительно общей базы, blob в ветке и в origin/main.
#   admin-web/tools/branch-gone.sh <ветка>…
. "$(dirname "$0")/_lib.sh"
cd "$REPO" || exit 2
git fetch -q origin
[ $# = 0 ] && { echo "использование: branch-gone.sh <ветка>…"; exit 2; }
for b in "$@"; do
  ref=$b; git rev-parse -q --verify "$b" >/dev/null || ref="origin/$b"
  git rev-parse -q --verify "$ref" >/dev/null || { echo "$b: нет такой ветки"; continue; }
  base=$(git merge-base origin/main "$ref"); same=0; diff=0; list=""
  while read -r f; do
    [ -z "$f" ] && continue
    a=$(git rev-parse -q "$ref:$f" 2>/dev/null || echo gone); m=$(git rev-parse -q "origin/main:$f" 2>/dev/null || echo gone)
    if [ "$a" = "$m" ]; then same=$((same+1)); else diff=$((diff+1)); list="$list $f"; fi
  done < <(git diff --name-only "$base" "$ref")
  if [ $((same+diff)) = 0 ]; then echo "$b: своих изменений нет (ветка не ушла от main) → git branch -D $b"
  elif [ $diff = 0 ]; then echo "$b: В main ЦЕЛИКОМ ($same файлов совпадают) → git branch -D $b"
  else echo "$b: ЧАСТИЧНО/НЕТ — $diff из $((same+diff)) файлов отличаются от main:$(echo "$list" | cut -c1-200) — НЕ удалять без ревью"; fi
done
