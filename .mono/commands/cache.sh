#!/usr/bin/env bash
# description: Cache-Verwaltung (anzeigen, löschen, Statistik)

# Cache-Library laden
source "${MONO_DIR}/lib/cache.sh"

# ─── Help ───────────────────────────────────────────────────────────────────
cache_cmd::help() {
  echo ""
  echo -e "${BOLD}mono cache${NC} – Cache-Verwaltung"
  echo ""
  echo -e "${BOLD}Verwendung:${NC}"
  echo "  mono cache <subcommand>"
  echo ""
  echo -e "${BOLD}Subcommands:${NC}"
  echo "  stats       Cache-Statistik anzeigen"
  echo "  list        Alle Cache-Einträge auflisten"
  echo "  clear       Gesamten Cache löschen"
  echo "  --help, -h  Diese Hilfe anzeigen"
  echo ""
  echo -e "${BOLD}Beispiele:${NC}"
  echo "  mono cache stats     # Zeigt Anzahl und Größe"
  echo "  mono cache list      # Alle gecachten Targets"
  echo "  mono cache clear     # Cache komplett löschen"
  echo ""
  echo -e "${BOLD}Hinweis:${NC}"
  echo "  Caching kann pro Target deaktiviert werden:"
  echo '  "dev": { "command": "...", "cache": false }'
  echo ""
  echo "  Outputs können definiert werden für Output-Caching:"
  echo '  "build": { "command": "...", "outputs": ["dist/**"] }'
  echo ""
}

# ─── Stats ──────────────────────────────────────────────────────────────────
cache_cmd::stats() {
  echo ""
  echo -e "${BOLD}Cache-Statistik${NC}"
  echo ""

  local stats
  stats="$(cache::stats)"

  local entries size
  entries="$(echo "${stats}" | grep '^entries=' | cut -d= -f2)"
  size="$(echo "${stats}" | grep '^size=' | cut -d= -f2)"

  echo -e "  ${BOLD}Einträge:${NC}  ${entries}"
  echo -e "  ${BOLD}Größe:${NC}     ${size}"
  echo -e "  ${BOLD}Pfad:${NC}      ${MONO_CACHE_DIR}"
  echo ""
}

# ─── List ───────────────────────────────────────────────────────────────────
cache_cmd::list() {
  echo ""
  echo -e "${BOLD}Cache-Einträge${NC}"
  echo ""

  local entries
  entries="$(cache::list)"

  if [[ -z "${entries}" ]]; then
    echo "  (keine Einträge)"
  else
    while IFS= read -r entry; do
      echo -e "  ${CYAN}${entry}${NC}"
    done <<< "${entries}"
  fi

  echo ""
}

# ─── Clear ──────────────────────────────────────────────────────────────────
cache_cmd::clear() {
  local stats
  stats="$(cache::stats)"
  local entries
  entries="$(echo "${stats}" | grep '^entries=' | cut -d= -f2)"
  local size
  size="$(echo "${stats}" | grep '^size=' | cut -d= -f2)"

  cache::clear

  echo ""
  mono::log "Cache gelöscht (${entries} Einträge, ${size})"
  echo ""
}

# ─── Dispatch ──────────────────────────────────────────────────────────────
cache_cmd::run() {
  local subcommand="${1:-}"

  case "${subcommand}" in
    stats)        cache_cmd::stats ;;
    list)         cache_cmd::list ;;
    clear)        cache_cmd::clear ;;
    --help|-h|"") cache_cmd::help ;;
    *)
      mono::error "Unbekannter Subcommand: ${BOLD}${subcommand}${NC}"
      cache_cmd::help
      return 1
      ;;
  esac
}

# ─── Start ──────────────────────────────────────────────────────────────────
cache_cmd::run "$@"
