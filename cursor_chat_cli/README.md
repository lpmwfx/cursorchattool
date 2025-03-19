# Cursor Udviklingsværktøjer

Dette repository indeholder en samling af værktøjer til at arbejde med Cursor AI IDE, herunder både kommandolinjeværktøjer og grafiske brugergrænseflader.

## Projektstruktur

- **cursor_chat_cli/**: Kommandolinjeværktøj til at browse og udtrække chat historikker fra Cursor SQLite-databaser
- **tools_ui/**: Grafisk brugergrænseflade der giver adgang til kommandolinjeværktøjerne og tilføjer ekstra funktionalitet

## Cursor Chat Værktøj

For mere information om CLI-værktøjet, se [cursor_chat_cli/README.md](cursor_chat_cli/README.md).

### Brug som VSCode Task

Værktøjet kan bruges direkte fra VSCode som en task. En task-konfigurationsfil er inkluderet i `vscode_task_example.json`.

For at bruge dette værktøj som en task i VSCode:

1. Kopier indholdet af `vscode_task_example.json` til `.vscode/tasks.json` i dit projekt
2. Kør task via Command Palette (Ctrl+Shift+P) > "Tasks: Run Task" > "Udtræk Cursor Chat med Request ID"
3. Indtast request ID (f.eks. `1e4ddc91eebcec20571cd738f31756a9_5154`)
4. Værktøjet vil generere en JSON-fil i projektets rodmappe

### Kommandolinje Parametre

```
Cursor Chat Browser & Extractor

Brug: cursor_chat_tool [options]

-h, --help                 Vis hjælp
-l, --list                 List alle chat historikker
-e, --extract=<chatId>     Udtræk en specifik chat (id eller alle)
-f, --format=<format>      Output format (text, markdown, html, json)
-o, --output=<dir>         Output mappe
-c, --config=<file>        Sti til konfigurationsfil
-r, --request-id=<id>      Udtræk chat med specifik request ID og gem JSON i nuværende mappe
```

### Eksempel på brug

Udtræk chat med et specifikt request ID og gem som JSON i nuværende mappe:

```bash
dart bin/cursor_chat_tool.dart --request-id 1e4ddc91eebcec20571cd738f31756a9_5154
```

## UI Værktøjer

UI værktøjerne er under udvikling og vil indeholde:
- Chat browser med søgemuligheder
- Filtreringsfunktioner for chats
- Integreret editor for at arbejde med udtrukne chats
- Flere udviklingsværktøjer tilføjes løbende

## Installation

Se installationsvejledningerne i de respektive mapper for hvert værktøj.

## Udviklet af

Dette projektet er udviklet af Lars med hjælp fra Claude 3.7 AI. 