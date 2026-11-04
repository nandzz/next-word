# NextWord

NextWord is a macOS menu bar app. It suggests the next word while you type in any app, for example Slack, WhatsApp or Mail.

Hold **⇧ ?** in a text field. A panel opens near the cursor and shows 5, 10 or 20 words that fit the text. Select a word, and NextWord types it for you.

## Features

- Suggestions for the word after the cursor. If the cursor is in the middle of a word, NextWord completes that word.
- Three engines:
  - **On-device**: Apple Foundation Models. The text stays on your Mac. A request takes approximately 1 second.
  - **Claude**: the Claude Code CLI (Haiku, Sonnet, Opus, Fable or a custom model). A request takes approximately 4–6 seconds.
  - **Codex**: the OpenAI Codex CLI.
- **Meaning view**: push **→** to see the meaning of the selected word in the language of your text. Push **→** again to see the translation and meaning in your language.
- **Rewrite**: push **⌘E** in the panel to get 3 versions of your text: clearer, shorter and reworded. Select one, and NextWord replaces the text. If text is selected, NextWord rewrites only the selection. If not, it rewrites the full text field. Push **⌘Z** in the app to undo.
- Settings for the number of words, the engine, the tone, the language, the long-press duration and the meaning view.

## Requirements

- macOS 14 or later. The on-device engine needs macOS 26, a Mac with Apple silicon and Apple Intelligence turned on.
- For the Claude engine: the [Claude Code CLI](https://docs.anthropic.com/en/docs/claude-code), logged in. You do not need an API key.
- For the Codex engine: the Codex CLI (`npm i -g @openai/codex`), logged in with `codex login`.

## Keys in the panel

| Key | Action |
|---|---|
| ↑ ↓ or Tab | Select the previous or next word |
| ⏎ or 1–9, 0 | Type the selected word, or word 1–10 |
| → | Show the meaning. Push again to show it in your language |
| ← | Go back |
| ⌘E | Show rewrites of the text. Push again to go back |
| ⌘R | Get new suggestions or rewrites |
| Esc | Close the panel |

In the rewrite view, ↑ ↓ select a rewrite, and ⏎ or 1–3 replace the text with it.

## Permissions

NextWord needs **Accessibility** access. Give it in **System Settings → Privacy & Security → Accessibility**. NextWord uses this access to:

- detect the long press of the "?" key,
- read the text near the cursor,
- type the word that you select,
- replace the text with the rewrite that you select.

If NextWord cannot read a text field, it can copy the current line: it selects to the start of the line, copies the text, and then restores your clipboard. NextWord does not do this in password fields, terminals, code editors or Finder.

To replace text with a rewrite, NextWord pastes it: it puts the rewrite on the clipboard, selects the text if necessary, pushes ⌘V, and then restores your clipboard. In Mail, Outlook, terminals and code editors, NextWord rewrites only selected text. It does not rewrite password fields or texts longer than 2,000 characters.

## Privacy

- With the on-device engine, the text stays on your Mac.
- With Claude or Codex, NextWord gives the text near the cursor (approximately 1,500 characters) to that CLI. The CLI sends it to Anthropic or OpenAI with your account.
- When you push ⌘E, NextWord also gives the full text that it rewrites (at most 2,000 characters) to that CLI.
- "Fall back to Claude" is off by default. If you turn it on, NextWord uses Claude when the selected engine is not available. The panel then shows "fallback".
- NextWord does not keep your text. Release builds write no log files.

## Build

```bash
./Scripts/build-app.sh --install --run
```

This builds the app, signs it with your Apple Development certificate, copies it to `~/Applications` and starts it.

To make a build that you can give to other people:

```bash
NOTARY_PROFILE=<notarytool-profile> ./Scripts/build-app.sh --dist
```

This builds a universal binary, signs it with your Developer ID Application certificate and a secure timestamp, notarizes it, and makes `build/NextWord.zip`. To make the keychain profile, use `xcrun notarytool store-credentials`.

## Tests

```bash
xcrun swift test
```

## Project layout

| Folder | Contents |
|---|---|
| `Sources/NextWord/App` | App entry point and coordinator |
| `Sources/NextWord/Core` | Models, settings, panel logic |
| `Sources/NextWord/Input` | Key detection, text reading, text insertion |
| `Sources/NextWord/Claude`, `Codex`, `OnDevice`, `Engines` | The engines |
| `Sources/NextWord/UI` | Panel, menu bar popover, settings window |
| `Tests/NextWordTests` | Unit tests |

## License

NextWord uses the MIT License. See [LICENSE](LICENSE).
