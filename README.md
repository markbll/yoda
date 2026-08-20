# YODA

**GUI version: 4.9**

A self-healing watch-folder extractor for single or multi-part 7-Zip / ZIP
archives, with an optional Star Wars / Yoda theme. It watches an inbound
folder, waits for split archives (`.7z.001`, `.zip.001`, ...) to fully
arrive and stop changing, verifies their integrity, extracts them, and
files the originals away — unattended, forever.

The various CLI script revisions (`Unzipper5.ps1`, `YodaTheUnzipperv2.ps1`,
`YodaTheUnzipperV4`, `Yoda_The_Unzipperv6.ps1`, `Yod-TheUnzipper-FINAL.ps1`,
`Yoda_Unzipper.ps1`) and their original `README.md` are bundled in
[`Yoda_The_Unzipper-main.zip`](Yoda_The_Unzipper-main.zip).

## GUI

[`YODA.ps1`](YODA.ps1) is a Windows Forms front-end for the engine, built
from `Yoda_Unzipper.ps1` (the most complete revision, with the Star Wars
theme options). Instead of editing command-line parameters and watching a
console window, you get:

- Folder pickers for Base / Pre-Stage / Inbound / Extracted / Completed
  paths, plus a 7-Zip path field with a browse button.
- Numeric settings for the scan interval, the empty-cycle self-heal
  threshold, and the pre-stage scan interval.
- Checkboxes for the Star Wars intro jingle, Yoda ASCII art, Yoda quotes,
  and theme beeps.
- Start / Stop buttons that run the extractor engine (and, if configured,
  the pre-stage watcher) on background threads, so the window never freezes.
- A live, color-coded log (Info/Success/Warning/Error) and a status bar
  showing the current cycle, completed/waiting/failed counts, the
  pre-stage watcher's state and staged-file count, and a countdown to the
  next scan.
- "Open Pre-Stage / Inbound / Extracted / Completed / Logs" shortcuts, and
  settings are remembered between runs (`yoda_gui_config.json`, written
  next to the script).
- A borderless splash screen - large Yoda ASCII art and title - shown for
  5 seconds on startup before the main window loads.

### Pre-Stage folder (optional)

Some setups land files in one place first - a download client, an FTP/SFTP
drop, a torrent client - before they should be handed to Yoda's own Inbound
folder. Set a **Pre-Stage** path in the GUI and, whenever the engine is
running, a second background thread watches it and moves qualifying files
into Inbound automatically. Leave the field blank to disable this entirely
(the default).

A file is relayed only when all of the following hold:

- Its name does **not** start with `.` (filters out hidden/partial marker
  files).
- Its extension is **not** `.tmp` (the common "still being written" marker
  used by many downloaders/transfer tools).
- It's a `.zip`/`.7z` file, or a numbered split-archive part (`...001`,
  `...002`, etc.).
- It's confirmed settled: the file must be unlocked *and* its size must
  stay unchanged across a full 10-second confirmation window, not just
  at a single instant - a file that is momentarily unlocked mid-transfer
  won't be picked up prematurely. Files that don't pass are simply left in
  place and re-checked on a later scan.

Split-archive parts are relayed individually as each one stabilizes rather
than waiting for the whole set - Yoda's own Inbound watcher already handles
parts arriving over time. If a file with the same name already exists in
Inbound, the pre-stage copy is left alone and a warning is logged rather
than overwriting anything.

**Also look in subfolders of Pre-Stage** (checked by default): some upload
or sync tools land files in a subfolder per batch/session rather than
directly in Pre-Stage. When checked, those are found too and flattened
into Inbound by filename, regardless of nesting depth - the subfolder
itself is left in place, never deleted, in case whatever created it
expects to reuse it. Uncheck to only watch the Pre-Stage folder's top
level.

### Completed folder

Once an archive extracts successfully, its unzipped output is moved from
Extracted into the **Completed** folder - the final home for finished
work, separate from the working area extraction happens in. Only the
extracted content relocates; the original archive parts stay right where
they always have, under `Extracted\<name>\RAW`. If the move itself fails
for some reason (e.g. disk full), that's logged but the archive still
counts as completed - the content was extracted correctly, it just didn't
finish relocating, so it is never re-extracted.

### Requirements

- Windows PowerShell 5.1+ (or PowerShell 7+ on Windows) - WinForms only
  runs on Windows.
- 7-Zip installed (default expected path: `C:\Program Files\7-Zip\7z.exe`,
  overridable in the GUI).

### Run it

Double-click **`Start_YODA.bat`**, or run directly:

```powershell
powershell.exe -ExecutionPolicy Bypass -File YODA.ps1
```

### Behavior differences from the classic CLI scripts

The GUI reuses the same scan/verify/test/extract/move pipeline as
`Yoda_Unzipper.ps1`, with two deliberate adaptations for running inside a
GUI process rather than a console:

- **Self-healing no longer spawns a new console window.** The original
  scripts recover from prolonged idle/error conditions by relaunching a
  fresh `powershell.exe` process. From a GUI, that would pop up stray
  windows, so the engine instead resets its in-memory tracking state in
  place and keeps running under the same Start/Stop session.
- **The countdown doesn't flood the log.** The CLI scripts redraw the
  Yoda ASCII art and print a countdown line every second. The GUI shows
  that countdown in the status bar instead, and only logs the Yoda quote
  once per wait cycle, so the log view stays readable.

Stop is responsive even mid-wait: the engine checks for a stop request at
every wait point, not just between cycles.
