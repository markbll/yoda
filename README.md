# Yoda The Unzipper

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

[`Yoda_GUI.ps1`](Yoda_GUI.ps1) is a Windows Forms front-end for the engine,
built from `Yoda_Unzipper.ps1` (the most complete revision, with the
Star Wars theme options). Instead of editing command-line parameters and
watching a console window, you get:

- Folder pickers for Base / Inbound / Extracted paths, plus a 7-Zip path
  field with a browse button.
- Numeric settings for the scan interval and the empty-cycle self-heal
  threshold.
- Checkboxes for the Star Wars intro jingle, Yoda ASCII art, Yoda quotes,
  and theme beeps.
- Start / Stop buttons that run the extractor engine on a background
  thread, so the window never freezes.
- A live, color-coded log (Info/Success/Warning/Error) and a status bar
  showing the current cycle, completed/waiting/failed counts, and a
  countdown to the next scan.
- "Open Inbound / Extracted / Logs" shortcuts, and settings are
  remembered between runs (`yoda_gui_config.json`, written next to the
  script).

### Requirements

- Windows PowerShell 5.1+ (or PowerShell 7+ on Windows) - WinForms only
  runs on Windows.
- 7-Zip installed (default expected path: `C:\Program Files\7-Zip\7z.exe`,
  overridable in the GUI).

### Run it

Double-click **`Start_Yoda_GUI.bat`**, or run directly:

```powershell
powershell.exe -ExecutionPolicy Bypass -File Yoda_GUI.ps1
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
