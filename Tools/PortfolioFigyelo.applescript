-- Portfólió Figyelő: a launchd ezt az appot indítja a Letöltések változásakor.
-- Miért app és nem sima script: a Letöltések mappát a macOS védi (TCC), és a
-- launchd-ből futó zsh NÉMÁN üres listát kap — mérve: 1 elem a valódi 267
-- helyett. Egy app viszont első futáskor engedélyt kér, és a rendszer
-- megjegyzi a választ.
on run
	do shell script "/Users/lacus/Portfolio/Tools/statement-watcher.sh"
end run
