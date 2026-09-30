# Voice lines

Optional spoken lines per language. The game plays them a moment after the
matching sound effect when that language is selected in Settings.

```
assets/audio/voice/<language code>/<name>.wav
```

`<name>` is one of: `phutas`, `machyas`, `begi`, `treghi`, `win`, `lose`, `draw`.

Example for Urdu: record `machyas.wav`, `begi.wav`, ... into
`assets/audio/voice/ur/`, then add the folder to `flutter: assets:` in
`pubspec.yaml`:

```yaml
    - assets/audio/voice/ur/
```

and set the language's `ready` flag to `true` in
`lib/features/home/settings_sheet.dart`. No other code changes are needed.
