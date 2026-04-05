# Monorepo Template

Ein Template-Repository zur Initialisierung neuer Monorepos.

## Struktur

```
├── mono           # CLI Wrapper (leitet an .mono/bin/mono weiter)
├── apps/          # Alle Applikationen
├── libs/          # Gemeinsam genutzte Bibliotheken
└── .mono/         # Scripts zur Verwaltung des Monorepos
```

### `apps/`

Enthält alle eigenständigen Applikationen. Jede App lebt in einem eigenen Unterverzeichnis und kann unabhängig gebaut und deployed werden.

### `libs/`

Enthält wiederverwendbare Bibliotheken und Pakete, die von mehreren Apps geteilt werden.

### `.mono/`

Enthält Scripts und Konfigurationen zur Verwaltung des Monorepos (z. B. Build-Orchestrierung, Dependency-Management, CI/CD-Hilfsskripte).

```
.mono/
├── bin/
│   └── mono           # CLI Entry-Script
└── commands/
    └── <name>.sh      # Einzelne Commands
```

## CLI (`mono`)

Das Monorepo wird über das CLI-Tool `mono` verwaltet.

### Aufruf

```bash
./mono <command> [optionen]
```

### Verfügbare Befehle

| Command | Beschreibung |
|---------|-------------|
| `help`  | Zeigt alle verfügbaren Commands |
| `generate app <name>` | Erstellt eine neue App aus einem Template |
| `run <projekt>:<target>` | Führt ein Target aus der project.json aus |
| `changed` | Zeigt geänderte Apps/Libs seit dem letzten Deploy |
| `deploy-mark` | Setzt den Deploy-Tag auf den aktuellen Commit |
| `hello` | Beispiel-Command |

### `generate app`

Erstellt eine neue App im `apps/`-Verzeichnis aus einem Template.

```bash
./mono generate app <name> [--template <template>]
```

**Name-Format:**
- `app-name` → `apps/app-name/`
- `subfolder/app-name` → `apps/subfolder/app-name/`

**Verfügbare Templates:**

| Template | Beschreibung |
|----------|-------------|
| `empty`  | Leeres Verzeichnis |
| `minimal`| Nur README.md |
| `bun`   | Bun-Projekt mit TypeScript |

Wird kein `--template` angegeben, erfolgt eine interaktive Auswahl.

**Eigene Templates erstellen:** Neuen Ordner unter `.mono/templates/app/<name>/` anlegen. Dateien können die Platzhalter `{{APP_NAME}}` und `{{APP_PATH}}` verwenden. Eine `.template`-Datei (erste Zeile = Beschreibung) wird als Metadatei genutzt und nicht kopiert.

### `changed`

Erkennt welche Apps und Libs sich seit dem letzten Deploy geändert haben. Vergleicht dazu `HEAD` mit dem Git-Tag `deploy/latest`.

```bash
./mono changed                        # Alle Änderungen seit deploy/latest
./mono changed --apps                 # Nur geänderte Apps
./mono changed --libs                 # Nur geänderte Libs
./mono changed --json                 # JSON-Ausgabe für CI/CD
./mono changed --quiet                # Nur Pfade (eine pro Zeile)
./mono changed --ref main~5           # Vergleich mit beliebiger Git-Ref
```

Die Projekt-Erkennung basiert auf der `project.json` im Projektverzeichnis. Projekte ohne `project.json` werden mit einer Warnung angezeigt.

Die JSON-Ausgabe (`--json`) enthält die Deploy-Konfiguration aus der `project.json`:

```json
{
  "base": "a4007f0",
  "head": "c6ba265",
  "changed": [
    {
      "path": "apps/my-api",
      "name": "my-api",
      "type": "app",
      "deploy": { "strategy": "bun" }
    }
  ]
}
```

### `project.json`

Jedes Projekt (App/Lib) enthält eine `project.json`, die als Projekt-Marker, Target- und Deploy-Konfiguration dient:

```json
{
  "name": "my-app",
  "type": "app",
  "path": "apps/my-app",
  "targets": {
    "install": {
      "command": "bun install"
    },
    "dev": {
      "command": "bun run --watch src/index.ts",
      "dependsOn": ["install"]
    },
    "build": {
      "command": "bun build src/index.ts --outdir dist",
      "dependsOn": ["install"]
    },
    "start": {
      "command": "bun run src/index.ts",
      "dependsOn": ["build"]
    },
    "test": {
      "command": "bun test",
      "dependsOn": ["install"]
    }
  },
  "deploy": {
    "strategy": "bun",
    "entrypoint": "src/index.ts"
  },
  "dependencies": []
}
```

| Feld | Beschreibung |
|------|-------------|
| `name` | Projektname |
| `type` | `app` oder `lib` |
| `path` | Relativer Pfad im Monorepo |
| `targets` | Ausführbare Befehle (siehe `mono run`) |
| `targets.<name>.command` | Der CLI-Befehl, der ausgeführt wird |
| `targets.<name>.dependsOn` | Targets, die vorher ausgeführt werden müssen |
| `deploy.strategy` | Deploy-Strategie (`bun`, `docker`, `static`, `none`, ...) |
| `dependencies` | Lib-Abhängigkeiten (optional) |

### `run`

Führt Targets aus der `project.json` eines Projekts aus. Löst dabei automatisch die `dependsOn`-Kette auf.

```bash
./mono run my-app:dev                # Führt 'dev' aus (inkl. install)
./mono run my-app:build              # Führt 'build' aus (inkl. install)
./mono run my-app:start              # Führt 'start' aus (inkl. build → install)
./mono run my-app:start --skip-deps  # Nur start, ohne Dependencies
./mono run my-app:start --dry-run    # Zeigt Ausführungsplan ohne zu starten
./mono run my-app --list              # Alle Targets auflisten
./mono run my-app                     # Alle Targets auflisten (Kurzform)
```

Projekte können über ihren Namen oder Pfad referenziert werden:

```bash
./mono run my-app:dev                # Über project.json name
./mono run backend/my-api:dev        # Über Pfad unter apps/
```

### `deploy-mark`

Markiert den aktuellen Commit als letzten Deploy-Stand.

```bash
./mono deploy-mark                    # Setzt deploy/latest auf HEAD
./mono deploy-mark --push             # Setzt Tag und pusht zum Remote
./mono deploy-mark --tag deploy/prod  # Eigener Tag-Name
```

### Neuen Command erstellen

Erstelle eine neue Datei unter `.mono/commands/<name>.sh`:

```bash
#!/usr/bin/env bash
# description: Kurze Beschreibung des Commands

echo "Mein neuer Command"
```

Die erste Zeile mit `# description:` wird automatisch in `mono help` angezeigt.

Im Command stehen folgende Variablen zur Verfügung:

- `MONO_ROOT` – Absoluter Pfad zum Repository-Root
- `MONO_DIR` – Absoluter Pfad zu `.mono/`

## Verwendung

1. Repository als Template nutzen oder klonen:
   ```bash
   git clone https://github.com/codelabrx/monorepo.git <projekt-name>
   cd <projekt-name>
   ```

2. Remote auf das neue Repository setzen:
   ```bash
   git remote set-url origin <neue-repo-url>
   ```

3. CLI ausführbar machen:
   ```bash
   chmod +x mono
   ```

4. Apps und Libs nach Bedarf anlegen:
   ```bash
   mkdir -p apps/<app-name>
   mkdir -p libs/<lib-name>
   ```

