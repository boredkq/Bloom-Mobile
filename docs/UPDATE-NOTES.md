# Update notes

[Русская версия](UPDATE-NOTES.ru.md)

Bloom shows what changed in a version in the **What's new** sheet: once by itself after an update, and at any time in **Settings → Version**, next to **Update history**. The notes live in this repository, in [`update-notes/update-notes.json`](../update-notes/update-notes.json), and Bloom reads them from the `main` branch. They are not built into the app: a note can be added or fixed before or after its release.

## Two kinds of notes

The version number decides how its note looks.

- **A major version** ends in `.0` (`1.1.0`, `2.0.0`): a picture on top, then a short summary on a plate.
- **A patch** is everything else (`1.0.1`, `1.1.3`): "In this version" and a list of items.

## The file

One object; each key is a version without the `v`, newest first:

```json
{
  "1.1.0": {
    "date": "2026-12-01",
    "image": "1.1.0.png",
    "summary": {
      "ru": "Краткий итог версии одной-двумя фразами.",
      "en": "The version in a sentence or two."
    }
  },
  "1.0.1": {
    "date": "2026-11-20",
    "items": {
      "ru": ["Первое изменение", "Второе изменение"],
      "en": ["The first change", "The second change"]
    }
  },
  "1.0.0": {
    "date": "2026-11-11",
    "summary": {
      "ru": "Встречайте Bloom: SoundCloud, Яндекс Музыка, YouTube Music и ваши файлы в одном плеере.",
      "en": "Meet Bloom: SoundCloud, Yandex Music, YouTube Music and your own files in one player."
    }
  }
}
```

| Field | For | What goes in |
|---|---|---|
| `date` | any | The release day, `YYYY-MM-DD`. |
| `summary` | major | A sentence or two. |
| `image` | major, optional | A file name in `update-notes/assets/`, or a full `https://` link. |
| `items` | patch | A list of changes, one line each. |

### Two languages

Every text is either one string for both languages, or an object with `ru` and `en`. If one of them is missing, Bloom shows the other.

```json
"summary": "Same text in both languages"
"summary": { "ru": "По-русски", "en": "In English" }
```

`items` may also be a list of such texts. Keeping the two languages as two lists, as in the example above, is easier to read:

```json
"items": ["Fix: …", { "ru": "Исправлено: …", "en": "Fixed: …" }]
"items": { "ru": ["…", "…"], "en": ["…", "…"] }
```

## Picture

- Put it into `update-notes/assets/` (the folder comes with the first picture) and write its name into `image`.
- It takes the sheet's full width and keeps its proportions; corners are rounded by Bloom. **1200 × 675** (16:9) looks sharp on any screen.
- PNG, JPG or WebP.
- Without a picture a major version shows only its summary.

## Writing items

- One change per line, a short sentence without a full stop.
- Say what the listener sees, not how it was done: "The queue remembers its scroll", not "Fixed QueueBlock".
- Start with what's new, then what changed, then fixes.

## Releasing a version

1. The note, as its own commit:
   ```
   git add update-notes
   git commit -m "Update notes 1.0.1"
   git push
   ```
2. The version: only the `version:` line in `pubspec.yaml` (`1.0.1+1`; in a release the run counter replaces the number after `+`), the commit named by the number alone:
   ```
   git add pubspec.yaml
   git commit -m "1.0.1"
   git push
   ```
3. The tag publishes the release (GitHub Actions builds the `.apk` and `.ipa`):
   ```
   git tag v1.0.1
   git push origin v1.0.1
   ```

The note can come after the release too: Bloom reads it again on each start. Android's signing secrets are in the repository's settings: `ANDROID_KEYSTORE_BASE64`, `ANDROID_STORE_PASSWORD`, `ANDROID_KEY_ALIAS`, `ANDROID_KEY_PASSWORD`. Without them the APK gets the debug key and won't install over the last version.

## Checking a note before it's in main

A phone can't see your computer's files, so the note needs a link: push it to a separate branch, for example. Then run a build with that link:

```
flutter run --dart-define=UPDATE_NOTES=https://raw.githubusercontent.com/use-bloom/mobile/<branch>/update-notes/update-notes.json --dart-define=UPDATE_FORCE=true
```

`UPDATE_FORCE` opens this version's **What's new** at every launch. A picture named in `image` is still taken from `main`; until it's there, give its full `https://` link.
