#!/usr/bin/env bash
# description: Setzt den Deploy-Tag auf den aktuellen Commit

DEPLOY_TAG="${MONO_DEPLOY_TAG:-deploy/latest}"

deploy_mark::help() {
  echo ""
  echo -e "${BOLD}mono deploy-mark${NC} – Deploy-Stand markieren"
  echo ""
  echo -e "${BOLD}Verwendung:${NC}"
  echo "  mono deploy-mark [optionen]"
  echo ""
  echo -e "${BOLD}Optionen:${NC}"
  echo "  --tag <tag>         Eigenen Tag-Namen verwenden (Standard: ${DEPLOY_TAG})"
  echo "  --push              Tag automatisch zum Remote pushen"
  echo "  --help, -h          Diese Hilfe anzeigen"
  echo ""
  echo -e "${BOLD}Beispiele:${NC}"
  echo "  mono deploy-mark                    # Setzt deploy/latest auf HEAD"
  echo "  mono deploy-mark --push             # Setzt Tag und pusht zum Remote"
  echo "  mono deploy-mark --tag deploy/prod  # Eigener Tag-Name"
  echo ""
}

deploy_mark::run() {
  local tag="${DEPLOY_TAG}"
  local push=false

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --tag)
        tag="${2:-}"
        shift 2
        ;;
      --push)
        push=true
        shift
        ;;
      --help|-h)
        deploy_mark::help
        return 0
        ;;
      *)
        mono::error "Unbekannte Option: $1"
        deploy_mark::help
        return 1
        ;;
    esac
  done

  local head_sha
  head_sha="$(git -C "${MONO_ROOT}" rev-parse --short HEAD)"
  local head_full
  head_full="$(git -C "${MONO_ROOT}" rev-parse HEAD)"

  # Alten Tag entfernen falls vorhanden
  if git -C "${MONO_ROOT}" rev-parse --verify "${tag}" &>/dev/null; then
    local old_sha
    old_sha="$(git -C "${MONO_ROOT}" rev-parse --short "${tag}")"
    git -C "${MONO_ROOT}" tag -d "${tag}" &>/dev/null
    mono::log "Alter Tag ${BOLD}${tag}${NC} (${old_sha}) entfernt"
  fi

  # Neuen Tag setzen
  git -C "${MONO_ROOT}" tag "${tag}" HEAD
  mono::log "Tag ${BOLD}${tag}${NC} gesetzt auf ${BOLD}${head_sha}${NC}"

  # Optional pushen
  if [[ "${push}" == true ]]; then
    git -C "${MONO_ROOT}" push origin "${tag}" --force 2>/dev/null
    mono::log "Tag zum Remote gepusht"
  fi

  echo ""
}

# ─── Start ──────────────────────────────────────────────────────────────────
deploy_mark::run "$@"
