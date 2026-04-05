#!/usr/bin/env bash
# Shared Library: Task-Caching
# Wird von anderen Commands per `source "${MONO_DIR}/lib/cache.sh"` geladen.
#
# Funktionsweise:
#   1. Vor dem Ausführen: Hash aus Inputs berechnen (Dateien, Command, Deps)
#   2. Cache-Verzeichnis prüfen: existiert der Hash bereits?
#   3. Cache-Hit: Target überspringen, ggf. Outputs wiederherstellen
#   4. Cache-Miss: Target ausführen, bei Erfolg Outputs cachen
#
# Cache-Struktur:
#   .mono/cache/<project-path-hash>/<target>/<input-hash>/
#     ├── meta        # Metadaten (command, timestamp, etc.)
#     └── outputs/    # Gecachte Output-Dateien

MONO_CACHE_DIR="${MONO_DIR}/cache"

# ─── Hash eines Strings berechnen ──────────────────────────────────────────
cache::hash_string() {
  echo -n "$1" | shasum -a 256 | cut -d' ' -f1
}

# ─── Hash eines Verzeichnisses berechnen ───────────────────────────────────
# Hasht alle Dateien im Projektverzeichnis (ohne node_modules, dist, etc.)
cache::hash_dir() {
  local dir="$1"

  if [[ ! -d "${dir}" ]]; then
    echo "empty"
    return
  fi

  # Finde alle relevanten Dateien, sortiert, und hashe deren Inhalt
  find "${dir}" \
    -not -path '*/node_modules/*' \
    -not -path '*/.git/*' \
    -not -path '*/dist/*' \
    -not -path '*/out/*' \
    -not -path '*/.mono/*' \
    -not -path '*/coverage/*' \
    -not -path '*/.cache/*' \
    -not -path '*/bun.lock' \
    -not -name '*.tsbuildinfo' \
    -type f \
    2>/dev/null \
    | sort \
    | xargs shasum -a 256 2>/dev/null \
    | shasum -a 256 \
    | cut -d' ' -f1
}

# ─── Outputs-Muster aus target-Block lesen ─────────────────────────────────
# Liest "outputs": ["dist/**", "coverage/**"] aus dem Target-Block.
cache::get_target_outputs() {
  local project_file="$1"
  local target="$2"

  local block
  block="$(sed -n '/"'"${target}"'"[[:space:]]*:[[:space:]]*{/,/}/p' "${project_file}")"
  [[ -z "${block}" ]] && return 0

  local outputs_line
  outputs_line="$(echo "${block}" | grep '"outputs"' | head -1)"
  [[ -z "${outputs_line}" ]] && return 0

  echo "${outputs_line}" | sed 's/.*\[//; s/\].*//' | tr ',' '\n' | sed 's/[[:space:]]*"//g; /^$/d'
}

# ─── Prüfen ob Caching für ein Target deaktiviert ist ─────────────────────
# "cache": false im Target-Block → kein Caching
cache::is_cacheable() {
  local project_file="$1"
  local target="$2"

  local block
  block="$(sed -n '/"'"${target}"'"[[:space:]]*:[[:space:]]*{/,/}/p' "${project_file}")"
  [[ -z "${block}" ]] && return 1

  # Explizit deaktiviert?
  if echo "${block}" | grep -q '"cache"[[:space:]]*:[[:space:]]*false'; then
    return 1
  fi

  return 0
}

# ─── Input-Hash für ein Target berechnen ───────────────────────────────────
# Kombination aus:
#   - Dateien im Projektverzeichnis
#   - Der Command-String
#   - Hashes der project.json Dependencies (Cross-Project)
cache::compute_hash() {
  local project_dir="$1"
  local target="$2"
  local command="$3"

  local full_dir="${MONO_ROOT}/${project_dir}"
  local project_file="${full_dir}/project.json"

  # 1. Dateien-Hash
  local files_hash
  files_hash="$(cache::hash_dir "${full_dir}")"

  # 2. Command-Hash
  local cmd_hash
  cmd_hash="$(cache::hash_string "${command}")"

  # 3. Dependency-Hashes (Cross-Project project.json Dependencies)
  local deps_hash="none"
  if [[ -f "${project_file}" ]]; then
    local deps_combined=""
    local deps_line
    deps_line="$(grep '"dependencies"' "${project_file}" | head -1)"
    if [[ -n "${deps_line}" ]] && ! echo "${deps_line}" | grep -q '\[\s*\]'; then
      local dep_names
      dep_names="$(echo "${deps_line}" | sed 's/.*\[//; s/\].*//' | tr ',' '\n' | sed 's/[[:space:]]*"//g; /^$/d')"
      while IFS= read -r dep_name; do
        [[ -z "${dep_name}" ]] && continue
        local dep_dir
        dep_dir="$(graph::resolve_project "${dep_name}" 2>/dev/null)" || continue
        local dep_hash
        dep_hash="$(cache::hash_dir "${MONO_ROOT}/${dep_dir}")"
        deps_combined="${deps_combined}${dep_name}:${dep_hash};"
      done <<< "${dep_names}"
    fi
    if [[ -n "${deps_combined}" ]]; then
      deps_hash="$(cache::hash_string "${deps_combined}")"
    fi
  fi

  # Kombinierten Hash berechnen
  cache::hash_string "${files_hash}:${cmd_hash}:${deps_hash}:${target}"
}

# ─── Cache-Pfad für ein Target ─────────────────────────────────────────────
cache::cache_path() {
  local project_dir="$1"
  local target="$2"
  local hash="$3"

  # Projekt-Pfad hashen für kürzere Verzeichnisnamen
  local path_hash
  path_hash="$(cache::hash_string "${project_dir}" | cut -c1-12)"

  echo "${MONO_CACHE_DIR}/${path_hash}/${target}/${hash}"
}

# ─── Cache-Hit prüfen ─────────────────────────────────────────────────────
cache::check() {
  local project_dir="$1"
  local target="$2"
  local hash="$3"

  local cache_dir
  cache_dir="$(cache::cache_path "${project_dir}" "${target}" "${hash}")"

  [[ -f "${cache_dir}/meta" ]]
}

# ─── Outputs aus dem Cache wiederherstellen ────────────────────────────────
cache::restore_outputs() {
  local project_dir="$1"
  local target="$2"
  local hash="$3"

  local cache_dir
  cache_dir="$(cache::cache_path "${project_dir}" "${target}" "${hash}")"
  local outputs_dir="${cache_dir}/outputs"
  local full_dir="${MONO_ROOT}/${project_dir}"

  if [[ -d "${outputs_dir}" ]] && [[ -n "$(ls -A "${outputs_dir}" 2>/dev/null)" ]]; then
    cp -R "${outputs_dir}"/. "${full_dir}/"
    return 0
  fi

  return 1
}

# ─── Outputs in den Cache speichern ───────────────────────────────────────
cache::save() {
  local project_dir="$1"
  local target="$2"
  local hash="$3"
  local command="$4"

  local project_file="${MONO_ROOT}/${project_dir}/project.json"
  local full_dir="${MONO_ROOT}/${project_dir}"

  local cache_dir
  cache_dir="$(cache::cache_path "${project_dir}" "${target}" "${hash}")"

  # Cache-Verzeichnis erstellen
  mkdir -p "${cache_dir}"

  # Metadaten speichern
  cat > "${cache_dir}/meta" << EOF
project=${project_dir}
target=${target}
hash=${hash}
command=${command}
timestamp=$(date +%s)
date=$(date '+%Y-%m-%d %H:%M:%S')
EOF

  # Outputs cachen (falls definiert)
  local outputs
  outputs="$(cache::get_target_outputs "${project_file}" "${target}")"

  if [[ -n "${outputs}" ]]; then
    local outputs_dir="${cache_dir}/outputs"
    mkdir -p "${outputs_dir}"

    while IFS= read -r pattern; do
      [[ -z "${pattern}" ]] && continue

      # Pattern ohne trailing /** für das Basisverzeichnis
      local base_pattern="${pattern%%/**}"

      if [[ -e "${full_dir}/${base_pattern}" ]]; then
        # Verzeichnisstruktur im Cache nachbilden
        local parent
        parent="$(dirname "${base_pattern}")"
        if [[ "${parent}" != "." ]]; then
          mkdir -p "${outputs_dir}/${parent}"
        fi
        cp -R "${full_dir}/${base_pattern}" "${outputs_dir}/${base_pattern}" 2>/dev/null || true
      fi
    done <<< "${outputs}"
  fi
}

# ─── Alten Cache für ein Target aufräumen ──────────────────────────────────
# Behält nur den neuesten Hash, löscht ältere.
cache::cleanup_target() {
  local project_dir="$1"
  local target="$2"
  local keep_hash="$3"

  local path_hash
  path_hash="$(cache::hash_string "${project_dir}" | cut -c1-12)"
  local target_dir="${MONO_CACHE_DIR}/${path_hash}/${target}"

  [[ -d "${target_dir}" ]] || return 0

  for entry in "${target_dir}"/*/; do
    [[ -d "${entry}" ]] || continue
    local entry_hash
    entry_hash="$(basename "${entry}")"
    if [[ "${entry_hash}" != "${keep_hash}" ]]; then
      rm -rf "${entry}"
    fi
  done
}

# ─── Cache-Statistik ──────────────────────────────────────────────────────
cache::stats() {
  if [[ ! -d "${MONO_CACHE_DIR}" ]]; then
    echo "entries=0"
    echo "size=0"
    return
  fi

  local entries
  entries="$(find "${MONO_CACHE_DIR}" -name "meta" 2>/dev/null | wc -l | tr -d ' ')"

  local size
  size="$(du -sh "${MONO_CACHE_DIR}" 2>/dev/null | cut -f1 | tr -d ' ')"
  [[ -z "${size}" ]] && size="0B"

  echo "entries=${entries}"
  echo "size=${size}"
}

# ─── Gesamten Cache löschen ───────────────────────────────────────────────
cache::clear() {
  if [[ -d "${MONO_CACHE_DIR}" ]]; then
    rm -rf "${MONO_CACHE_DIR}"
    mkdir -p "${MONO_CACHE_DIR}"
  fi
}

# ─── Cache-Einträge auflisten ─────────────────────────────────────────────
cache::list() {
  if [[ ! -d "${MONO_CACHE_DIR}" ]]; then
    return
  fi

  find "${MONO_CACHE_DIR}" -name "meta" 2>/dev/null | while read -r meta_file; do
    local project target hash timestamp date
    project="$(grep '^project=' "${meta_file}" | cut -d= -f2-)"
    target="$(grep '^target=' "${meta_file}" | cut -d= -f2-)"
    hash="$(grep '^hash=' "${meta_file}" | cut -d= -f2- | cut -c1-12)"
    date="$(grep '^date=' "${meta_file}" | cut -d= -f2-)"

    echo "${project}:${target} (${hash}) – ${date}"
  done | sort
}
