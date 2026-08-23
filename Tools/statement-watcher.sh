#!/bin/zsh
# Kivonat-figyelő a Letöltések mappán.
#
# A launchd hívja, amikor a ~/Downloads változik. A felismerhető nevű
# kivonat-fájlokat ÁTMOZGATJA az iCloud „Portfólió" mappába — onnan az
# iPhone-app beolvassa, és a „Feldolgozva" almappába archiválja. A fájl
# tehát nem vész el, csak átköltözik: Letöltések → Portfólió → Feldolgozva.
#
# Napló: ~/Library/Logs/portfolio-statement-watcher.log
set -u

DOWNLOADS="$HOME/Downloads"
TARGET="$HOME/Library/Mobile Documents/iCloud~hu~halasz~portfolio/Documents"
LOG="$HOME/Library/Logs/portfolio-statement-watcher.log"

mkdir -p "$TARGET"

# Ugyanazok a minták, mint az appban (Inbox.looksLikeStatement).
PATTERNS=(
  'Bankszámlakivonat_*.PDF'
  'Bankszámlakivonat_*.pdf'
  'Hitelkártya számlakivonat_*.pdf'
  'Hitelkártya számlakivonat_*.PDF'
  'savings-statement_*.csv'
  'account-statement_*.csv'
  'AccountStatement-LY-*.csv'
)

moved=0
for pattern in "${PATTERNS[@]}"; do
  # A (N) nullglob: ha nincs találat, a ciklus egyszerűen kimarad.
  for file in "$DOWNLOADS"/${~pattern}(N); do
    name="${file:t}"
    # Ha a cél már létezik (pl. ugyanazt kétszer töltötted le), sorszámozunk.
    target="$TARGET/$name"
    counter=2
    while [[ -e "$target" ]]; do
      target="$TARGET/${name:r}-$counter.${name:e}"
      (( counter++ ))
    done
    if mv "$file" "$target" 2>>"$LOG"; then
      echo "$(date '+%Y-%m-%d %H:%M:%S') áthelyezve: $name" >> "$LOG"
      (( moved++ ))
    fi
  done
done

exit 0
