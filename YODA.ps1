<#
    YODA.ps1
    Version 5.0

    A Windows Forms GUI for YODA - the watch-folder 7-Zip/ZIP
    split-archive extractor scripts bundled in Yoda_The_Unzipper-main.zip.

    Instead of editing command-line parameters and staring at a console
    window, this lets you configure the watcher, start/stop it, and watch
    a live, color-coded log with running stats - all from one window.

    Requirements: Windows PowerShell 5.1+ (or PowerShell 7+ on Windows),
    .NET WinForms, and 7-Zip installed.

    Run with:
        powershell.exe -ExecutionPolicy Bypass -File YODA.ps1
#>

$YodaGuiVersion = "5.0"

# WinForms requires a Single Threaded Apartment. Relaunch under -STA if needed.
if ([System.Threading.Thread]::CurrentThread.GetApartmentState() -ne 'STA') {
    $exePath = (Get-Process -Id $PID).Path
    Start-Process -FilePath $exePath -ArgumentList @(
        "-NoProfile", "-STA", "-ExecutionPolicy", "Bypass", "-File", "`"$PSCommandPath`""
    )
    exit
}

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# ------------------------------------------------------------------------
# Splash screen - shown for a few seconds on startup, before anything else
# loads.
# ------------------------------------------------------------------------

function Show-SplashScreen {
    param([int]$DurationSeconds = 5)

    $SplashArt = @'
      YO
       DAYO
       DAYODA
        YODAYOD
        AYODAYODA
         YODAYODAYO
          DAYODAYODAY                 ODAYODAYODAYODA
           YODAYODAYOD            AYODAYODAYODAYODAYODAY
            ODAYODAYODAY        ODAYODAYODAYODAYODAYODAYODA
             YODAYODAYODAY    ODAYODAYODAYODAYODAYODAYODAYODA
              YODAYODAYODAYO DAYODAYODAYODAYODAYODAYODAYODAYOD
               AYODAYODAYODAYODAYODAYODAYODAYODAYODAYODAYODAYOD
                 AYODAYODAYODAYODAYODAYODAYODAYODAYODAYODAYODAY
                   ODAYODAYODAYODAYODAYODAYODAYOD    AYODAYODAYO
                     DAYODAYODAYODAYODAYODAYODAYO    DAYODAYODAY
                       ODAYODAYODAYODAYODAYODAYODAYODAYODAYODAYOD
                         AYODAYODAYODAYODAYODAYODAYODAYODAYODAYODA
                           YODAYODAYODAYODAYODAYODAYODAYODAYODAYOD
                             AYODAYODAYODAYODAYODAYODAYODAYODAYOD
                               AYODAYODAYODAYODAYODAYODAYODA
                                YODAYODAYODAYODAYODAYODAYO
                                   DAYODAYODAYODAYODAYO
                                        DAYODAYODAY
                                           ODAYO
                                           DAYOD
                              AYODAYODAYODAYODAYODAYODAYODAYO
                            DAYODAYODAYODAYODAYODAYODAYODAYODA
                           YODAYODAYODAYODAYODAYODAYODAYODAYODAY
                         ODAYODAYODAYODAYODAYODAYODAYODAYODAYODAYO
                        DAYODAYODAYODAYODAYODAYODAYODAYODAYODAYODA
                         YODAYODAYODAYODAYODAYODAYODAYODAYODAYODAY
                         ODAYODAYODAYODAYODAYODAYODAYODAYODAYODAY
                          ODAYODAYODAYODAYODAYODAYODAYODAYODAYODA
                          YODAYODAYODAYODAYODAYODAYODAYODAYODAYOD
                        AYODAYODAYODAYODAYODAYODAYODAYODAYODAYODAY
                          ODAYODAYODAYODAYODAYODAYODAYODAYODAYOD
                                          AYODAYO
'@

    $splash = New-Object System.Windows.Forms.Form
    $splash.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::None
    $splash.StartPosition = "CenterScreen"
    $splash.Size = New-Object System.Drawing.Size(800, 820)
    $splash.BackColor = [System.Drawing.Color]::Black
    $splash.ShowInTaskbar = $false
    $splash.TopMost = $true

    $splash.Add_Paint({
        param($s, $e)
        $pen = New-Object System.Drawing.Pen([System.Drawing.Color]::Gold, 3)
        $e.Graphics.DrawRectangle($pen, 1, 1, $s.Width - 3, $s.Height - 3)
        $pen.Dispose()
    })

    $lblTitle = New-Object System.Windows.Forms.Label
    $lblTitle.Text = "YODA THE UNZIPPER"
    $lblTitle.Font = New-Object System.Drawing.Font("Segoe UI Black", 26, [System.Drawing.FontStyle]::Bold)
    $lblTitle.ForeColor = [System.Drawing.Color]::Gold
    $lblTitle.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter
    $lblTitle.Location = New-Object System.Drawing.Point(0, 15)
    $lblTitle.Size = New-Object System.Drawing.Size($splash.Width, 55)

    $lblArt = New-Object System.Windows.Forms.Label
    $lblArt.Text = $SplashArt
    $lblArt.Font = New-Object System.Drawing.Font("Consolas", 12)
    $lblArt.ForeColor = [System.Drawing.Color]::FromArgb(120, 220, 90)
    $lblArt.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter
    $lblArt.Location = New-Object System.Drawing.Point(0, 80)
    $lblArt.Size = New-Object System.Drawing.Size($splash.Width, 640)

    $lblSubtitle = New-Object System.Windows.Forms.Label
    $lblSubtitle.Text = "v$YodaGuiVersion - May the Force be with you... loading"
    $lblSubtitle.Font = New-Object System.Drawing.Font("Segoe UI", 12, [System.Drawing.FontStyle]::Italic)
    $lblSubtitle.ForeColor = [System.Drawing.Color]::Cyan
    $lblSubtitle.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter
    $lblSubtitle.Location = New-Object System.Drawing.Point(0, 750)
    $lblSubtitle.Size = New-Object System.Drawing.Size($splash.Width, 40)

    $splash.Controls.AddRange(@($lblTitle, $lblArt, $lblSubtitle))

    $splash.Show()
    $splash.Refresh()
    [System.Windows.Forms.Application]::DoEvents()

    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    while ($stopwatch.Elapsed.TotalSeconds -lt $DurationSeconds) {
        [System.Windows.Forms.Application]::DoEvents()
        Start-Sleep -Milliseconds 50
    }

    $splash.Close()
    $splash.Dispose()
}

Show-SplashScreen -DurationSeconds 5

# ------------------------------------------------------------------------
# Persisted configuration
# ------------------------------------------------------------------------

$ConfigFile = Join-Path -Path $PSScriptRoot -ChildPath "yoda_gui_config.json"

function Get-DefaultConfig {
    [PSCustomObject]@{
        BasePath                  = "C:\yoda"
        PreStagePath              = ""
        PreStageRecurseSubfolders = $true
        InboundPath               = "C:\yoda\inbound"
        ExtractedPath             = "C:\yoda\extracted"
        CompletedPath             = "C:\yoda\completed"
        SevenZipPath              = "C:\Program Files\7-Zip\7z.exe"
        CheckIntervalSeconds      = 30
        EmptyCyclesBeforeRestart  = 10
        StagerScanIntervalSeconds = 15
        EnableStarWarsTheme       = $true
        EnableYodaArt             = $true
        EnableYodaQuotes          = $true
        EnableThemeBeeps          = $true
        EnableGreenText           = $true
        HashExtractedFiles        = $true
        HashArchiveParts          = $true
        ShowSuccessBanner         = $true
    }
}

function Import-GuiConfig {
    if (Test-Path $ConfigFile) {
        try {
            return Get-Content -Path $ConfigFile -Raw | ConvertFrom-Json
        } catch {
            return Get-DefaultConfig
        }
    }
    return Get-DefaultConfig
}

function Export-GuiConfig {
    param($Config)
    try {
        $Config | ConvertTo-Json | Set-Content -Path $ConfigFile -Encoding UTF8
    } catch { }
}

$Config = Import-GuiConfig

# ------------------------------------------------------------------------
# Cross-runspace shared state (GUI thread <-> background engine thread)
# ------------------------------------------------------------------------

$Sync = [hashtable]::Synchronized(@{
    LogQueue      = [System.Collections.Concurrent.ConcurrentQueue[object]]::new()
    SuccessQueue  = [System.Collections.Concurrent.ConcurrentQueue[object]]::new()
    StopRequested = $false
    State         = "Idle"
    Cycle         = 0
    Completed     = 0
    Waiting       = 0
    Failed        = 0
    Errors        = 0
    Countdown     = ""
    StagerState   = "Idle"
    Staged        = 0
})

$script:EnginePS        = $null
$script:EngineRunspace  = $null
$script:EngineAsync     = $null

$script:StagerPS        = $null
$script:StagerRunspace  = $null
$script:StagerAsync     = $null

# ------------------------------------------------------------------------
# Background engine - adapted from Yoda_Unzipper.ps1
#
# Differences from the original console script:
#   - All console output (Write-Host / Clear-Host / ASCII art) is replaced
#     with a thread-safe log queue the GUI drains and renders.
#   - The "self-healing restart" no longer spawns a brand-new powershell.exe
#     process/window (that made no sense from a GUI). It instead resets the
#     in-memory tracking state in place and keeps running.
#   - The per-second countdown no longer floods the log; it just updates a
#     small "Next scan in mm:ss" status field the GUI polls.
#   - $Sync.StopRequested is checked at each wait point so the Stop button
#     is responsive even mid-wait.
# ------------------------------------------------------------------------

$EngineScriptBlock = {
    param(
        [string]$BasePath,
        [string]$InboundPath,
        [string]$ExtractedPath,
        [string]$CompletedPath,
        [string]$SevenZipPath,
        [int]$CheckIntervalSeconds,
        [int]$EmptyCyclesBeforeRestart,
        [bool]$EnableStarWarsTheme,
        [bool]$EnableYodaArt,
        [bool]$EnableYodaQuotes,
        [bool]$EnableThemeBeeps,
        [bool]$EnableGreenText,
        [bool]$HashExtractedFiles,
        [bool]$HashArchiveParts,
        $Sync
    )

    $LogFolder = Join-Path -Path $BasePath -ChildPath "logs"
    $MissingPartsFile = Join-Path -Path $LogFolder -ChildPath "missing_parts_log.txt"
    $FailedArchivesFile = Join-Path -Path $LogFolder -ChildPath "failed_archives_log.txt"
    $ErrorDetailsFile = Join-Path -Path $LogFolder -ChildPath "error_details_log.txt"
    $CompletedLogFile = Join-Path -Path $LogFolder -ChildPath "completed_log.txt"
    $ErrorCount = 0
    $ProcessedArchives = @{}
    $ConsecutiveEmptyCycles = 0
    $LastPartProgressAt = @{}
    $LastPartFingerprint = @{}
    $UnknownVolumeCountAlerted = @{}
    $FallbackTestedFingerprint = @{}
    # This measures minutes of NO NEW PARTS ARRIVING, not minutes-incomplete -
    # a large archive can legitimately take hours to fully arrive, so alerting
    # on elapsed time alone would false-alarm on every normal slow transfer.
    # Lack of *progress* for this long is the actual stuck signal.
    $StalledPartArrivalAlertMinutes = 60

    if (-not (Test-Path $LogFolder)) {
        New-Item -ItemType Directory -Path $LogFolder -Force | Out-Null
    }

    $LogFile = Join-Path -Path $LogFolder -ChildPath "extraction_log_$(Get-Date -Format 'yyyyMMdd_HHmmss').txt"

    $YodaQuotes = @{
        "Waiting" = "Patience, you must have. Archives, they are coming, yes."
    }

    $YodaArt = @'
      YO
       DAYO
       DAYODA
        YODAYOD
        AYODAYODA
         YODAYODAYO
          DAYODAYODAY                 ODAYODAYODAYODA
           YODAYODAYOD            AYODAYODAYODAYODAYODAY
            ODAYODAYODAY        ODAYODAYODAYODAYODAYODAYODA
             YODAYODAYODAY    ODAYODAYODAYODAYODAYODAYODAYODA
              YODAYODAYODAYO DAYODAYODAYODAYODAYODAYODAYODAYOD
               AYODAYODAYODAYODAYODAYODAYODAYODAYODAYODAYODAYOD
                 AYODAYODAYODAYODAYODAYODAYODAYODAYODAYODAYODAY
                   ODAYODAYODAYODAYODAYODAYODAYOD    AYODAYODAYO
                     DAYODAYODAYODAYODAYODAYODAYO    DAYODAYODAY
                       ODAYODAYODAYODAYODAYODAYODAYODAYODAYODAYOD
                         AYODAYODAYODAYODAYODAYODAYODAYODAYODAYODA
                           YODAYODAYODAYODAYODAYODAYODAYODAYODAYOD
                             AYODAYODAYODAYODAYODAYODAYODAYODAYOD
                               AYODAYODAYODAYODAYODAYODAYODA
                                YODAYODAYODAYODAYODAYODAYO
                                   DAYODAYODAYODAYODAYO
                                        DAYODAYODAY
                                           ODAYO
                                           DAYOD
                              AYODAYODAYODAYODAYODAYODAYODAYO
                            DAYODAYODAYODAYODAYODAYODAYODAYODA
                           YODAYODAYODAYODAYODAYODAYODAYODAYODAY
                         ODAYODAYODAYODAYODAYODAYODAYODAYODAYODAYO
                        DAYODAYODAYODAYODAYODAYODAYODAYODAYODAYODA
                         YODAYODAYODAYODAYODAYODAYODAYODAYODAYODAY
                         ODAYODAYODAYODAYODAYODAYODAYODAYODAYODAY
                          ODAYODAYODAYODAYODAYODAYODAYODAYODAYODA
                          YODAYODAYODAYODAYODAYODAYODAYODAYODAYOD
                        AYODAYODAYODAYODAYODAYODAYODAYODAYODAYODAY
                          ODAYODAYODAYODAYODAYODAYODAYODAYODAYOD
                                          AYODAYO
'@

    function Write-Log {
        param([string]$Message, [ValidateSet("Info", "Success", "Warning", "Error")][string]$Type = "Info")
        $Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        $LogEntry = "[$Timestamp] [$Type] $Message"
        try { Add-Content -Path $LogFile -Value $LogEntry -Encoding UTF8 -ErrorAction Stop } catch { }
        $Sync.LogQueue.Enqueue([PSCustomObject]@{ Type = $Type; Message = $LogEntry })
    }

    function Write-MissingPartsLog {
        param([string]$ArchiveName, [string]$Message)
        $Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        try { Add-Content -Path $MissingPartsFile -Value "[$Timestamp] $ArchiveName : $Message" -Encoding UTF8 -ErrorAction Stop } catch { }
    }

    function Write-FailedArchiveLog {
        param([string]$ArchiveName, [string]$Reason, [string]$Details)
        $Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        try {
            Add-Content -Path $FailedArchivesFile -Value "[$Timestamp] ARCHIVE: $ArchiveName | REASON: $Reason" -Encoding UTF8 -ErrorAction Stop
            if ($Details) { Add-Content -Path $FailedArchivesFile -Value "    DETAILS: $Details" -Encoding UTF8 -ErrorAction Stop }
            Add-Content -Path $FailedArchivesFile -Value "" -Encoding UTF8 -ErrorAction Stop
        } catch { }
    }

    # A dedicated, append-only record of every successful completion -
    # separate from the main log so "what has finished, ever" doesn't
    # require scrolling back through routine cycle noise, and survives
    # past whatever the main log's 3000-line on-screen trim keeps.
    function Write-CompletedLog {
        param([string]$ArchiveName, [string]$Location, [int]$FileCount, [int]$PartCount)
        $Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        try {
            Add-Content -Path $CompletedLogFile -Value "[$Timestamp] $ArchiveName | $PartCount part(s) | $FileCount file(s) | $Location" -Encoding UTF8 -ErrorAction Stop
        } catch { }
    }

    function Write-ErrorDetailsLog {
        param([string]$Component, [string]$ArchiveName, [string]$ErrorText, [string]$Details)
        $Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        try { Add-Content -Path $ErrorDetailsFile -Value "[$Timestamp] COMPONENT: $Component | ARCHIVE: $ArchiveName | ERROR: $ErrorText | DETAILS: $Details" -Encoding UTF8 -ErrorAction Stop } catch { }
    }

    function Test-FileStability {
        param([string]$FilePath)
        try {
            $null = Get-Item -Path $FilePath -ErrorAction Stop
            try {
                $Stream = [System.IO.File]::Open($FilePath, 'Open', 'Read', 'None')
                $Stream.Close()
                return $true
            } catch { return $false }
        } catch { return $false }
    }

    function Wait-FileStability {
        param([string]$FilePath, [int]$TimeoutSeconds = 120)
        $Elapsed = 0
        while ($Elapsed -lt $TimeoutSeconds) {
            if ($Sync.StopRequested) { return $false }
            if (Test-FileStability -FilePath $FilePath) { return $true }
            Start-Sleep -Seconds 2
            $Elapsed += 2
        }
        return $false
    }

    # Windows silently strips trailing dots and spaces from a path segment
    # when it's created through normal (non-\\?\-prefixed) APIs - so an
    # archive whose base name ends in "." (e.g. source files named
    # "TEST..001", "TEST..002", ...) gets extracted into a folder that
    # actually exists as "TEST" on disk, while every log line still shows
    # "TEST." - making it look like extraction silently failed when it
    # didn't. Apply this wherever a base name becomes a folder name.
    function ConvertTo-SafeFolderName {
        param([string]$Name)
        $Safe = $Name.TrimEnd('.', ' ')
        if ([string]::IsNullOrWhiteSpace($Safe)) { $Safe = "archive" }
        return $Safe
    }

    # Single source of truth for "which archive does this file belong to",
    # used everywhere a file needs to be matched back to its BaseName. Every
    # caller MUST compare with -eq against this, never with a -like "prefix*"
    # wildcard - a wildcard also matches a completely different archive whose
    # name simply starts with the same text (e.g. BaseName "Report" would
    # wildcard-match "ReportQ2.7z.001"), silently pulling unrelated files into
    # this archive's part count and, worse, into its RAW move.
    function Get-PartBaseName {
        param([string]$FileName)
        $BaseName = $FileName -replace '\.\d{3}$', ''
        $BaseName = $BaseName -replace '\.zip$', ''
        $BaseName = $BaseName -replace '\.7z$', ''
        return $BaseName
    }

    function Get-ArchiveGroups {
        param([string]$Path)
        try {
            $Files = @(Get-ChildItem -Path $Path -File -ErrorAction SilentlyContinue |
                       Where-Object { $_.Extension -match '\.(7z|zip)' -or $_.Name -match '\.\d{3}$' })
            if ($Files.Count -eq 0) { return @{} }
            $Groups = @{}
            foreach ($File in $Files) {
                $BaseName = Get-PartBaseName $File.Name
                if (-not $Groups.ContainsKey($BaseName)) { $Groups[$BaseName] = @() }
                $Groups[$BaseName] += $File
            }
            return $Groups
        } catch {
            Write-Log "Error scanning archives: $_" -Type "Error"
            Write-ErrorDetailsLog "Get-ArchiveGroups" "N/A" "Scan Error" $_
            return @{}
        }
    }

    function Get-ExpectedPartCount {
        param([string]$FilePath)
        try {
            if (-not (Wait-FileStability -FilePath $FilePath)) {
                Write-Log "First part file still being written: $(Split-Path $FilePath -Leaf)" -Type "Warning"
                return $null
            }
            $ListOutput = @(& $SevenZipPath l $FilePath 2>&1)
            foreach ($Line in $ListOutput) {
                if ($Line -match "Volumes\s*=\s*(\d+)") {
                    $VolumeCount = [int]$matches[1]
                    # This is the single most important number in the whole
                    # pipeline - everything downstream (are all parts present,
                    # does extraction proceed) hinges on 7-Zip's own claim
                    # here being correct. Log the raw lines it came from, not
                    # just the parsed number, so if 7-Zip is ever wrong about
                    # this on some archive/environment, there's direct
                    # evidence in the log instead of a bare figure to doubt.
                    $SizeLine = ($ListOutput | Where-Object { $_ -match '^(Physical Size|Total Physical Size)\s*=' }) -join ' | '
                    Write-Log "Archive has $VolumeCount volume(s) (source: $(Split-Path $FilePath -Leaf)) [$SizeLine]" -Type "Info"
                    return $VolumeCount
                }
            }
            return $null
        } catch {
            Write-Log "Error querying archive volumes: $_" -Type "Error"
            Write-ErrorDetailsLog "Get-ExpectedPartCount" (Split-Path $FilePath -Leaf) "Query Error" $_
            return $null
        }
    }

    # Collapses a list of missing part numbers into readable ranges, e.g.
    # 51,52,53,54,102 -> "051-054, 102" instead of a long comma list - matters
    # once archives run into the hundreds of parts.
    function Format-PartNumberRanges {
        param([int[]]$Numbers)
        if ($Numbers.Count -eq 0) { return "" }
        $Sorted = $Numbers | Sort-Object -Unique
        $Ranges = @()
        $RangeStart = $Sorted[0]
        $RangeEnd = $Sorted[0]
        for ($i = 1; $i -lt $Sorted.Count; $i++) {
            if ($Sorted[$i] -eq ($RangeEnd + 1)) {
                $RangeEnd = $Sorted[$i]
            } else {
                $Ranges += if ($RangeStart -eq $RangeEnd) { "{0:000}" -f $RangeStart } else { "{0:000}-{1:000}" -f $RangeStart, $RangeEnd }
                $RangeStart = $Sorted[$i]
                $RangeEnd = $Sorted[$i]
            }
        }
        $Ranges += if ($RangeStart -eq $RangeEnd) { "{0:000}" -f $RangeStart } else { "{0:000}-{1:000}" -f $RangeStart, $RangeEnd }
        return ($Ranges -join ", ")
    }

    function Verify-AllPartsPresentAndStable {
        param([string]$BaseName, [string]$SourcePath, [int]$ExpectedCount)
        $PartFiles = @(Get-ChildItem -Path $SourcePath -File -ErrorAction SilentlyContinue |
                       Where-Object { (Get-PartBaseName $_.Name) -eq $BaseName } | Sort-Object Name)
        $ActualCount = $PartFiles.Count
        Write-Log "Verifying parts for $BaseName : Expected=$ExpectedCount, Found=$ActualCount" -Type "Info"
        if ($ActualCount -lt $ExpectedCount) {
            $MissingCount = $ExpectedCount - $ActualCount
            $Message = "INCOMPLETE - Missing $MissingCount of $ExpectedCount parts. Found: $ActualCount parts"
            Write-Log $Message -Type "Warning"
            Write-MissingPartsLog $BaseName $Message

            # Identify missing part NUMBERS by inspecting the numeric suffix of each
            # file actually present, rather than reconstructing a filename from
            # BaseName - the middle extension (.7z, .zip, or none) varies and can't
            # be reliably guessed, so a reconstructed name almost never matches a
            # real "name.7z.NNN"-style file, which silently broke this before.
            $PresentNumbers = [System.Collections.Generic.HashSet[int]]::new()
            foreach ($Part in $PartFiles) {
                if ($Part.Name -match '\.(\d{3})$') {
                    [void]$PresentNumbers.Add([int]$matches[1])
                }
            }
            $MissingNumbers = @()
            for ($i = 1; $i -le $ExpectedCount; $i++) {
                if (-not $PresentNumbers.Contains($i)) { $MissingNumbers += $i }
            }
            if ($MissingNumbers.Count -gt 0) {
                $MissingSummary = Format-PartNumberRanges -Numbers $MissingNumbers
                Write-Log "Missing part number(s): $MissingSummary" -Type "Warning"
                Write-MissingPartsLog $BaseName "Missing part number(s): $MissingSummary"
            }
            return $false
        }

        Write-Log "All $ExpectedCount parts found. Verifying file stability..." -Type "Info"
        $UnstableFiles = @()
        foreach ($Part in $PartFiles) {
            if (-not (Wait-FileStability -FilePath $Part.FullName -TimeoutSeconds 30)) { $UnstableFiles += $Part.Name }
        }
        if ($UnstableFiles.Count -gt 0) {
            $Message = "Parts still being copied: $($UnstableFiles -join ', ')"
            Write-Log $Message -Type "Warning"
            Write-MissingPartsLog $BaseName $Message
            return $false
        }

        Write-Log "All $ExpectedCount parts present and stable for: $BaseName" -Type "Success"
        return $true
    }

    function Test-ArchiveIntegrity {
        param([string]$FilePath)
        $FileName = Split-Path $FilePath -Leaf
        Write-Log "Testing archive integrity: $FileName" -Type "Info"
        try {
            $TestOutput = @(& $SevenZipPath t $FilePath 2>&1)
            $OutputText = $TestOutput | Out-String
            # Never trust exit code alone for something this consequential -
            # cross-check against 7-Zip's own explicit textual verdict too.
            # "Everything is Ok" is the one line 7z only ever prints after a
            # fully successful test; any error banner (still checked even if
            # exit code somehow came back 0) means it isn't really a pass.
            $SaysOk = $OutputText -match 'Everything is Ok'
            $SaysError = $OutputText -match 'Unexpected end of archive|Data Error|CRC Failed|Headers Error|Can''t open as archive|ERRORS?:'
            if ($LASTEXITCODE -eq 0 -and $SaysOk -and -not $SaysError) {
                Write-Log "Archive integrity test PASSED: $FileName" -Type "Success"
                return $true
            } else {
                Write-Log "Archive integrity test FAILED: $FileName (exit=$LASTEXITCODE, saysOk=$SaysOk, saysError=$SaysError)" -Type "Error"
                $BaseName = $FileName -replace '\.\d{3}$', '' -replace '\.zip$', '' -replace '\.7z$', ''
                Write-FailedArchiveLog $BaseName "Integrity Test Failed" $OutputText
                $script:ErrorCount++
                return $false
            }
        } catch {
            Write-Log "Exception during integrity test: $_" -Type "Error"
            $BaseName = $FileName -replace '\.\d{3}$', '' -replace '\.zip$', '' -replace '\.7z$', ''
            Write-ErrorDetailsLog "Test-ArchiveIntegrity" $BaseName "Exception" $_
            $script:ErrorCount++
            return $false
        }
    }

    function Extract-Archive {
        param([string]$FirstPartPath, [string]$DestinationPath)
        try {
            $ArchiveName = Split-Path $FirstPartPath -Leaf
            $ArchiveName = $ArchiveName -replace '\.\d{3}$', '' -replace '\.zip$', '' -replace '\.7z$', ''
            $Timestamp = Get-Date -Format "yyyy-MM-dd_HH-mm-ss"
            $FolderName = "$(ConvertTo-SafeFolderName $ArchiveName)`_$Timestamp"
            $FinalDestination = Join-Path -Path $DestinationPath -ChildPath $FolderName

            if (-not (Test-Path $FinalDestination)) {
                New-Item -ItemType Directory -Path $FinalDestination -Force | Out-Null
                Write-Log "Created extraction directory: $FinalDestination" -Type "Info"
            }

            Write-Log "Extracting archive to: $FinalDestination" -Type "Info"
            $ExtractOutput = @(& $SevenZipPath x $FirstPartPath "-o$FinalDestination" 2>&1)
            $OutputText = $ExtractOutput | Out-String
            # Same double-check as Test-ArchiveIntegrity: exit code AND the
            # explicit "Everything is Ok" text, AND no error banner present.
            $SaysOk = $OutputText -match 'Everything is Ok'
            $SaysError = $OutputText -match 'Unexpected end of archive|Data Error|CRC Failed|Headers Error|Can''t open as archive|ERRORS?:'

            if ($LASTEXITCODE -eq 0 -and $SaysOk -and -not $SaysError) {
                Write-Log "Archive extraction completed successfully: $ArchiveName" -Type "Success"
                return $FinalDestination
            } else {
                Write-Log "Archive extraction FAILED: $ArchiveName (exit=$LASTEXITCODE, saysOk=$SaysOk, saysError=$SaysError)" -Type "Error"
                Write-FailedArchiveLog $ArchiveName "Extraction Failed" $OutputText
                # A failed extraction can still leave partial output behind on
                # disk (7z writes files as it goes) - never let a half-written
                # extraction pass as this archive's result on a later retry.
                if (Test-Path $FinalDestination) {
                    try { Remove-Item -Path $FinalDestination -Recurse -Force -ErrorAction Stop } catch { }
                }
                $script:ErrorCount++
                return $null
            }
        } catch {
            Write-Log "Exception during extraction: $_" -Type "Error"
            Write-ErrorDetailsLog "Extract-Archive" $ArchiveName "Exception" $_
            $script:ErrorCount++
            return $null
        }
    }

    function Move-ArchiveFiles {
        param([string]$BaseName, [string]$SourcePath, [string]$DestinationParent, [int]$ExpectedCount = 0)
        try {
            $RawFolder = Join-Path -Path $DestinationParent -ChildPath "RAW"
            if (-not (Test-Path $RawFolder)) {
                New-Item -ItemType Directory -Path $RawFolder -Force | Out-Null
                Write-Log "Created RAW folder: $RawFolder" -Type "Info"
            }

            $ArchiveFiles = @(Get-ChildItem -Path $SourcePath -File -ErrorAction SilentlyContinue |
                             Where-Object { (Get-PartBaseName $_.Name) -eq $BaseName })

            if ($ArchiveFiles.Count -eq 0) {
                Write-Log "No archive files found to move: $BaseName" -Type "Warning"
                return 0
            }

            if ($ExpectedCount -gt 0 -and $ArchiveFiles.Count -ne $ExpectedCount) {
                Write-Log "MISMATCH: about to move $($ArchiveFiles.Count) file(s) to RAW for '$BaseName' but the archive was verified with $ExpectedCount part(s) - moving anyway, but investigate this archive's output." -Type "Error"
                Write-ErrorDetailsLog "Move-ArchiveFiles" $BaseName "Part Count Mismatch" "Expected $ExpectedCount part(s), found $($ArchiveFiles.Count) file(s) matching this BaseName at move time."
                $script:ErrorCount++
            }

            Write-Log "Moving $($ArchiveFiles.Count) archive files to RAW folder..." -Type "Info"
            $MovedCount = 0
            foreach ($File in $ArchiveFiles) {
                try {
                    if (Wait-FileStability -FilePath $File.FullName) {
                        $DestPath = Join-Path -Path $RawFolder -ChildPath $File.Name
                        Move-Item -Path $File.FullName -Destination $DestPath -Force -ErrorAction Stop
                        Write-Log "Moved to RAW: $($File.Name)" -Type "Success"
                        $MovedCount++
                    } else {
                        Write-Log "File still in use, cannot move: $($File.Name)" -Type "Warning"
                    }
                } catch {
                    Write-Log "Failed to move $($File.Name): $_" -Type "Error"
                    Write-ErrorDetailsLog "Move-ArchiveFiles" $BaseName "Move Failed" $_
                    $script:ErrorCount++
                }
            }
            return $MovedCount
        } catch {
            Write-Log "Exception in Move-ArchiveFiles: $_" -Type "Error"
            Write-ErrorDetailsLog "Move-ArchiveFiles" $BaseName "Exception" $_
        }
    }

    # Relocates the actual unzipped output (not the RAW originals, which stay
    # under Extracted) into the Completed folder once extraction has fully
    # succeeded. A failure here is logged but never changes the archive's
    # "completed" status or triggers a re-extraction - the content is already
    # correctly extracted, it just didn't finish relocating.
    function Move-ExtractedToCompleted {
        param([string]$SourcePath, [string]$CompletedPath)
        try {
            if (-not (Test-Path $CompletedPath)) {
                New-Item -ItemType Directory -Path $CompletedPath -Force | Out-Null
                Write-Log "Created Completed folder: $CompletedPath" -Type "Info"
            }

            $FolderName = Split-Path $SourcePath -Leaf
            $Destination = Join-Path -Path $CompletedPath -ChildPath $FolderName

            if (Test-Path $Destination) {
                Write-Log "Cannot move to Completed - '$FolderName' already exists there: $Destination" -Type "Error"
                Write-ErrorDetailsLog "Move-ExtractedToCompleted" $FolderName "Destination Collision" "Extracted content left in place at $SourcePath"
                return $false
            }

            Move-Item -Path $SourcePath -Destination $Destination -ErrorAction Stop
            Write-Log "Moved extracted content to Completed: $Destination" -Type "Success"
            return $true
        } catch {
            Write-Log "Failed to move extracted content to Completed: $_" -Type "Error"
            Write-ErrorDetailsLog "Move-ExtractedToCompleted" (Split-Path $SourcePath -Leaf) "Move Failed" $_
            return $false
        }
    }

    # Writes one MD5 line per file under $RootPath into $OutputFile, in the
    # classic "hash *relativepath" format (the same layout md5sum produces),
    # so the result can be checked with a standard md5sum -c on either side.
    # Used both for the extracted output and for the RAW archive parts -
    # $Label just distinguishes which one shows up in the log.
    function Write-HashManifest {
        param([string]$RootPath, [string]$OutputFile, [string]$Label)
        try {
            $Files = @(Get-ChildItem -Path $RootPath -File -Recurse -ErrorAction SilentlyContinue |
                       Where-Object { $_.FullName -ne $OutputFile })
            if ($Files.Count -eq 0) {
                Write-Log "$Label hash manifest skipped - no files found under $RootPath" -Type "Warning"
                return
            }
            $Lines = foreach ($File in $Files) {
                try {
                    $Hash = (Get-FileHash -Path $File.FullName -Algorithm MD5 -ErrorAction Stop).Hash
                    $RelPath = $File.FullName.Substring($RootPath.Length).TrimStart('\', '/')
                    "$Hash *$RelPath"
                } catch {
                    "ERROR *$($File.Name) - $_"
                }
            }
            Set-Content -Path $OutputFile -Value $Lines -Encoding UTF8
            Write-Log "$Label MD5 hash manifest written: $OutputFile ($($Files.Count) file(s))" -Type "Success"
        } catch {
            Write-Log "Failed to write $Label hash manifest: $_" -Type "Error"
            Write-ErrorDetailsLog "Write-HashManifest" $Label "Exception" $_
        }
    }

    function Wait-NextCycle {
        param([int]$Seconds)
        if ($EnableYodaQuotes) { Write-Log $YodaQuotes['Waiting'] -Type "Info" }
        for ($i = $Seconds; $i -gt 0; $i--) {
            if ($Sync.StopRequested) { $Sync.Countdown = ""; return }
            $mins = [math]::Floor($i / 60)
            $secs = $i % 60
            $Sync.Countdown = "Next scan in {0}:{1}" -f $mins, $secs.ToString("00")
            Start-Sleep -Seconds 1
        }
        $Sync.Countdown = ""
    }

    if (-not (Test-Path $SevenZipPath)) {
        Write-Log "7-Zip not found at $SevenZipPath - stopping engine." -Type "Error"
        $Sync.State = "Stopped"
        return
    }

    Write-Log "=== YODA engine started ===" -Type "Info"

    if ($EnableStarWarsTheme -and $EnableThemeBeeps) {
        try {
            # An original, generic "power-up" tone - not any specific melody -
            # for the themed startup chime.
            $Notes = @(
                @{F = 330; D = 120}, @{F = 392; D = 120}, @{F = 494; D = 120}, @{F = 587; D = 260}
            )
            foreach ($Note in $Notes) { [Console]::Beep($Note.F, $Note.D) }
        } catch { }
    }

    if ($EnableYodaArt) {
        Write-Log $YodaArt -Type "Info"
    }

    Write-Log "May the Force be with you..." -Type "Info"
    Write-Log "Base: $BasePath | Inbound: $InboundPath | Extracted: $ExtractedPath | Completed: $CompletedPath" -Type "Info"
    Write-Log "Check interval: $CheckIntervalSeconds s | Self-heal after $EmptyCyclesBeforeRestart empty cycles" -Type "Info"

    foreach ($Dir in @($InboundPath, $ExtractedPath, $CompletedPath, $LogFolder)) {
        try {
            if (-not (Test-Path $Dir)) {
                New-Item -ItemType Directory -Path $Dir -Force | Out-Null
                Write-Log "Created directory: $Dir" -Type "Info"
            }
        } catch {
            Write-Log "Failed to create $Dir : $_" -Type "Error"
            Write-ErrorDetailsLog "Main" "N/A" "Directory Creation" $_
        }
    }

    $Sync.State = "Running"
    $CycleCount = 0

    while (-not $Sync.StopRequested) {
        try {
            $CycleCount++
            $Sync.Cycle = $CycleCount
            Write-Log "--- Scan Cycle #$CycleCount (Empty cycles: $ConsecutiveEmptyCycles/$EmptyCyclesBeforeRestart) ---" -Type "Info"

            $ArchiveGroups = Get-ArchiveGroups -Path $InboundPath

            if ($ArchiveGroups.Count -eq 0) {
                Write-Log "No archives found in inbound folder. Waiting for files..." -Type "Warning"
                $ConsecutiveEmptyCycles++

                if ($ConsecutiveEmptyCycles -ge $EmptyCyclesBeforeRestart) {
                    Write-Log "Self-healing reset triggered after $EmptyCyclesBeforeRestart empty cycles." -Type "Warning"
                    if ($EnableThemeBeeps) { try { [Console]::Beep(400, 300) } catch { } }
                    $ProcessedArchives = @{}
                    $ErrorCount = 0
                    $ConsecutiveEmptyCycles = 0
                    $LastPartProgressAt = @{}
                    $LastPartFingerprint = @{}
                    $UnknownVolumeCountAlerted = @{}
                    $FallbackTestedFingerprint = @{}
                }

                Wait-NextCycle $CheckIntervalSeconds
                continue
            }

            $ConsecutiveEmptyCycles = 0
            Write-Log "Found $($ArchiveGroups.Count) archive group(s)" -Type "Success"
            $ProcessedThisCycle = 0

            foreach ($BaseName in $ArchiveGroups.Keys) {
                if ($Sync.StopRequested) { break }
                try {
                    if ($ProcessedArchives.ContainsKey($BaseName) -and $ProcessedArchives[$BaseName] -eq "completed") {
                        Write-Log "Archive already processed: $BaseName (skipping)" -Type "Info"
                        continue
                    }
                    if ($ProcessedArchives.ContainsKey($BaseName) -and $ProcessedArchives[$BaseName] -eq "failed_integrity") {
                        Write-Log "Archive previously failed integrity: $BaseName (skipping)" -Type "Warning"
                        continue
                    }

                    $PartFiles = $ArchiveGroups[$BaseName]
                    $FirstPart = $PartFiles | Sort-Object Name | Select-Object -First 1

                    # .001 is the canonical entry point 7-Zip expects for a
                    # numbered split archive - and by design it's the part sent
                    # LAST, specifically so an incomplete set can never look
                    # ready. Don't run any volume-count or integrity check
                    # against some other part standing in as "first" while
                    # .001 is still missing - just wait, regardless of how
                    # many other parts have already arrived.
                    if ($FirstPart.Name -match '\.\d{3}$' -and -not ($PartFiles | Where-Object { $_.Name -match '\.001$' })) {
                        Write-Log "Waiting for .001 (arrives last) - $($PartFiles.Count) other part(s) already present: $BaseName" -Type "Warning"
                        if (-not $ProcessedArchives.ContainsKey($BaseName)) { $ProcessedArchives[$BaseName] = "waiting" }
                        continue
                    }

                    Write-Log "Processing: $BaseName ($($PartFiles.Count) parts found)" -Type "Info"

                    $ExpectedCount = Get-ExpectedPartCount -FilePath $FirstPart.FullName
                    if ($null -eq $ExpectedCount) {
                        if ($FirstPart.Name -match '\.\d{3}$') {
                            # This IS a numbered split part, but 7-Zip could not report a
                            # volume count from it alone. For 7-Zip's raw volume-split
                            # format, the end-of-archive header (which is where "Volumes="
                            # lives) is only reconstructable once every part is present -
                            # `7z l` on a partial set fails outright rather than reporting a
                            # partial answer. Treating that failure as "single-part" would
                            # test-and-permanently-fail an archive that is simply still
                            # arriving, so wait for more parts instead of guessing.
                            #
                            # A large archive can legitimately take hours to fully arrive,
                            # in any part order, so "still incomplete" is not itself a
                            # problem - it can wait indefinitely and is never auto-failed.
                            # What DOES matter is whether parts are still actually showing
                            # up. Track a fingerprint of exactly which part numbers are
                            # present; only escalate once that fingerprint has gone
                            # completely unchanged (no new/different parts at all) for a
                            # long stretch - a real stall, not just a slow transfer.
                            $PresentNumbers = [System.Collections.Generic.HashSet[int]]::new()
                            foreach ($Part in $PartFiles) {
                                if ($Part.Name -match '\.(\d{3})$') { [void]$PresentNumbers.Add([int]$matches[1]) }
                            }
                            $Fingerprint = ($PresentNumbers | Sort-Object) -join ','
                            $WasAlreadyStable = ($LastPartFingerprint.ContainsKey($BaseName) -and $LastPartFingerprint[$BaseName] -eq $Fingerprint)
                            if (-not $WasAlreadyStable) {
                                $LastPartFingerprint[$BaseName] = $Fingerprint
                                $LastPartProgressAt[$BaseName] = Get-Date
                                if ($UnknownVolumeCountAlerted.ContainsKey($BaseName)) { $UnknownVolumeCountAlerted.Remove($BaseName) }
                            }

                            # Fallback: 7-Zip's "Volumes = N" text is the normal way to learn
                            # the expected count, but that's a text-parse of 7z's own output
                            # and nothing guarantees its exact wording is stable across every
                            # 7-Zip build/locale/version. If the part set has stopped changing
                            # (same fingerprint as last cycle) and hasn't been probed yet at
                            # this exact fingerprint, try a real integrity test directly - if
                            # 7z can fully decompress and CRC-validate everything present
                            # right now, that alone proves this set is complete, independent
                            # of whether "Volumes=" was ever successfully parsed. Gated on
                            # "already stable" so an actively-arriving archive (fingerprint
                            # changing most cycles) never pays for a speculative test, and
                            # deduped per fingerprint so a genuinely stuck/corrupt archive
                            # isn't retested every cycle forever.
                            if ($WasAlreadyStable -and $FallbackTestedFingerprint["$BaseName|$Fingerprint"] -ne $true) {
                                $FallbackTestedFingerprint["$BaseName|$Fingerprint"] = $true
                                Write-Log "Volume count still not reported by 7-Zip's listing, but part set has stopped changing - attempting a direct integrity test as a fallback completeness check: $BaseName" -Type "Info"
                                if (Test-ArchiveIntegrity -FilePath $FirstPart.FullName) {
                                    Write-Log "Fallback integrity test PASSED against the $($PartFiles.Count) part(s) currently present - treating as complete: $BaseName" -Type "Success"
                                    $ExpectedCount = $PartFiles.Count
                                    $LastPartProgressAt.Remove($BaseName)
                                    $LastPartFingerprint.Remove($BaseName)
                                    $UnknownVolumeCountAlerted.Remove($BaseName)
                                }
                            }
                            if ($null -eq $ExpectedCount) {
                                $StalledMinutes = ((Get-Date) - $LastPartProgressAt[$BaseName]).TotalMinutes
                                if ($StalledMinutes -ge $StalledPartArrivalAlertMinutes -and -not $UnknownVolumeCountAlerted.ContainsKey($BaseName)) {
                                    $UnknownVolumeCountAlerted[$BaseName] = $true
                                    $StuckMsg = "STUCK: '$BaseName' has had NO new parts arrive for $([math]::Round($StalledMinutes, 1)) minute(s) and its total volume count still cannot be determined ($($PartFiles.Count) part(s) currently present in Inbound). If every part is genuinely present, the first volume (.001) may be corrupted; otherwise the transfer may have stopped. It will keep waiting indefinitely and will NOT be auto-failed - check manually if this persists."
                                    Write-Log $StuckMsg -Type "Error"
                                    Write-FailedArchiveLog $BaseName "Stuck - no new parts arriving" "No progress since $($LastPartProgressAt[$BaseName].ToString('yyyy-MM-dd HH:mm:ss')). $($PartFiles.Count) part(s) currently present in Inbound."
                                    if ($EnableThemeBeeps) { try { [Console]::Beep(300, 500) } catch { } }
                                }
                                # We don't know the true total yet, but we can still show gaps
                                # within the range of part numbers seen so far - e.g. parts
                                # 1-45 present but 012 and 030 missing - which is the useful,
                                # common case (a large archive trickling in over time), unlike
                                # Verify-AllPartsPresentAndStable's missing-part detection below,
                                # which by construction only runs once every single part is
                                # already present (see the comment above).
                                $GapMsg = ""
                                if ($PresentNumbers.Count -gt 0) {
                                    $HighestSeen = ($PresentNumbers | Measure-Object -Maximum).Maximum
                                    $GapsSoFar = @(1..($HighestSeen - 1) | Where-Object { -not $PresentNumbers.Contains($_) })
                                    if ($GapsSoFar.Count -gt 0) {
                                        $GapMsg = " - have parts up to $($HighestSeen.ToString('000')) with gap(s) at: $(Format-PartNumberRanges -Numbers $GapsSoFar)"
                                    } else {
                                        $GapMsg = " - have parts 001-$($HighestSeen.ToString('000')) with no gaps so far"
                                    }
                                }
                                Write-Log "Cannot determine total volume count yet (needs every part present)$GapMsg - waiting for more parts: $BaseName" -Type "Warning"
                                if (-not $ProcessedArchives.ContainsKey($BaseName)) { $ProcessedArchives[$BaseName] = "waiting" }
                                continue
                            }
                        }
                        if ($null -eq $ExpectedCount) {
                            $ExpectedCount = 1
                            Write-Log "Single-part archive detected: $BaseName" -Type "Info"
                        }
                    } else {
                        $LastPartProgressAt.Remove($BaseName)
                        $LastPartFingerprint.Remove($BaseName)
                        $UnknownVolumeCountAlerted.Remove($BaseName)
                    }

                    $AllPartsPresentAndStable = Verify-AllPartsPresentAndStable -BaseName $BaseName -SourcePath $InboundPath -ExpectedCount $ExpectedCount
                    if (-not $AllPartsPresentAndStable) {
                        Write-Log "Cannot process yet - waiting for missing or unstable parts" -Type "Warning"
                        if (-not $ProcessedArchives.ContainsKey($BaseName)) { $ProcessedArchives[$BaseName] = "waiting" }
                        continue
                    }

                    Write-Log "All parts verified. Starting integrity test..." -Type "Info"
                    $IntegrityOK = Test-ArchiveIntegrity -FilePath $FirstPart.FullName
                    if (-not $IntegrityOK) {
                        Write-Log "Archive failed integrity test: $BaseName - SKIPPING" -Type "Error"
                        $ProcessedArchives[$BaseName] = "failed_integrity"
                        continue
                    }

                    $ArchiveExtractPath = Join-Path -Path $ExtractedPath -ChildPath (ConvertTo-SafeFolderName $BaseName)
                    if (-not (Test-Path $ArchiveExtractPath)) { New-Item -ItemType Directory -Path $ArchiveExtractPath -Force | Out-Null }

                    Write-Log "Starting extraction process..." -Type "Info"
                    $ExtractionResult = Extract-Archive -FirstPartPath $FirstPart.FullName -DestinationPath $ArchiveExtractPath

                    if ($ExtractionResult) {
                        Write-Log "Extraction successful. Moving archive files to RAW folder..." -Type "Success"

                        $ExtractedFileCount = @(Get-ChildItem -Path $ExtractionResult -File -Recurse -ErrorAction SilentlyContinue).Count

                        if ($HashExtractedFiles) {
                            Write-HashManifest -RootPath $ExtractionResult -OutputFile (Join-Path $ExtractionResult "MD5_Hashes.txt") -Label "Extracted files"
                        }

                        $MovedPartCount = Move-ArchiveFiles -BaseName $BaseName -SourcePath $InboundPath -DestinationParent $ArchiveExtractPath -ExpectedCount $ExpectedCount

                        if ($HashArchiveParts) {
                            $RawFolder = Join-Path -Path $ArchiveExtractPath -ChildPath "RAW"
                            if (Test-Path $RawFolder) {
                                Write-HashManifest -RootPath $RawFolder -OutputFile (Join-Path $RawFolder "MD5_Hashes_Parts.txt") -Label "Archive parts"
                            }
                        }

                        $MovedToCompleted = Move-ExtractedToCompleted -SourcePath $ExtractionResult -CompletedPath $CompletedPath
                        $FinalLocation = if ($MovedToCompleted) { Join-Path -Path $CompletedPath -ChildPath (Split-Path $ExtractionResult -Leaf) } else { $ExtractionResult }

                        $ProcessedArchives[$BaseName] = "completed"
                        $ProcessedThisCycle++
                        if ($EnableThemeBeeps) {
                            # Original ascending chime - not any specific melody - for a
                            # successful-completion alert.
                            try { foreach ($f in 523, 659, 784, 1046) { [Console]::Beep($f, 130) } } catch { }
                        }
                        Write-CompletedLog -ArchiveName $BaseName -Location $FinalLocation -FileCount $ExtractedFileCount -PartCount $MovedPartCount
                        $Sync.SuccessQueue.Enqueue([PSCustomObject]@{
                            ArchiveName = $BaseName
                            Location    = $FinalLocation
                            FileCount   = $ExtractedFileCount
                            PartCount   = $MovedPartCount
                            Timestamp   = Get-Date
                        })
                        Write-Log "=== Successfully completed: $BaseName ===" -Type "Success"
                    } else {
                        $ProcessedArchives[$BaseName] = "extraction_failed"
                        Write-Log "Extraction failed for: $BaseName" -Type "Error"
                        if ($EnableThemeBeeps) { try { [Console]::Beep(300, 300) } catch { } }
                    }
                } catch {
                    Write-Log "Exception processing $BaseName : $_" -Type "Error"
                    Write-ErrorDetailsLog "Archive Processing" $BaseName "Unhandled Exception" $_
                    $ProcessedArchives[$BaseName] = "error"
                }
            }

            $WaitingCount = ($ProcessedArchives.Values | Where-Object { $_ -eq "waiting" }).Count
            $FailedCount = ($ProcessedArchives.Values | Where-Object { $_ -in "failed_integrity", "error", "extraction_failed" }).Count
            $CompletedCount = ($ProcessedArchives.Values | Where-Object { $_ -eq "completed" }).Count

            $Sync.Waiting = $WaitingCount
            $Sync.Failed = $FailedCount
            $Sync.Completed = $CompletedCount
            $Sync.Errors = $ErrorCount

            Write-Log "CYCLE SUMMARY - Processed This Cycle: $ProcessedThisCycle | Total Completed: $CompletedCount | Waiting: $WaitingCount | Failed: $FailedCount | Total Errors: $ErrorCount" -Type "Info"

            Wait-NextCycle $CheckIntervalSeconds
        } catch {
            Write-Log "CRITICAL EXCEPTION in main loop: $_" -Type "Error"
            Write-ErrorDetailsLog "Main Loop" "N/A" "Critical Exception" $_
            $ErrorCount++
            Start-Sleep -Seconds 5
        }
    }

    Write-Log "=== YODA engine stopped ===" -Type "Warning"
    $Sync.State = "Stopped"
}

# ------------------------------------------------------------------------
# Pre-stage watcher (background thread)
#
# Watches a separate "pre-stage" drop folder (e.g. where some other process
# - a downloader, an FTP/SFTP drop, a torrent client - lands files) and
# relays qualifying files into the Inbound folder that the main engine
# above actually watches. A file qualifies only if:
#   - its name does not start with "." (hidden/partial marker files)
#   - its extension is not ".tmp" (the common "still writing" marker)
#   - it is a .7z/.zip file, or a numbered split-archive part (....001, etc.)
#   - it is stable (not currently open for writing by another process)
#
# Split-archive parts are relayed one at a time as each one stabilizes;
# the main engine already tolerates parts trickling in over time.
# ------------------------------------------------------------------------

$StagerScriptBlock = {
    param(
        [string]$PreStagePath,
        [string]$InboundPath,
        [int]$ScanIntervalSeconds,
        [bool]$RecurseSubfolders,
        $Sync
    )

    function Write-StagerLog {
        param([string]$Message, [ValidateSet("Info", "Success", "Warning", "Error")][string]$Type = "Info")
        $Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        $Sync.LogQueue.Enqueue([PSCustomObject]@{ Type = $Type; Message = "[$Timestamp] [PreStage] [$Type] $Message" })
    }

    function Test-StagerFileStability {
        param([string]$FilePath)
        try {
            $null = Get-Item -Path $FilePath -ErrorAction Stop
            try {
                $Stream = [System.IO.File]::Open($FilePath, 'Open', 'Read', 'None')
                $Stream.Close()
                return $true
            } catch { return $false }
        } catch { return $false }
    }

    # Before moving a file, confirm the write has actually finished: the file
    # must be unlocked and its size must not have changed for a full 10
    # seconds, not just at a single instant. This used to be a blocking
    # Start-Sleep loop run per file, one at a time - fine for one file, but
    # with a batch of many arriving together it meant 10 full seconds of the
    # whole thread doing nothing else, per file, back to back, before even
    # looking at the next one (a batch of 20 files could take 200+ seconds
    # just in these waits, on top of the scan interval). Instead, remember
    # each candidate's size and when it was first seen at that size, and
    # compare across scan cycles - checking every candidate on every cycle
    # costs nothing (no sleeping), and a file only actually needs to be
    # *seen* stable across roughly one scan interval, however many other
    # files are also waiting, rather than blocking 10 seconds per file.
    $StagerFileState = @{}

    function Test-StagerFileSettled {
        param([System.IO.FileInfo]$File, [int]$ConfirmSeconds = 10)

        if (-not (Test-StagerFileStability -FilePath $File.FullName)) {
            $StagerFileState.Remove($File.FullName)
            return $false
        }

        $CurrentSize = $File.Length
        if (-not $StagerFileState.ContainsKey($File.FullName) -or $StagerFileState[$File.FullName].Size -ne $CurrentSize) {
            $StagerFileState[$File.FullName] = [PSCustomObject]@{ Size = $CurrentSize; FirstSeenAt = Get-Date }
            return $false
        }

        $Elapsed = ((Get-Date) - $StagerFileState[$File.FullName].FirstSeenAt).TotalSeconds
        return ($Elapsed -ge $ConfirmSeconds)
    }

    function Test-QualifiesForStaging {
        param([System.IO.FileInfo]$File)
        if ($File.Name.StartsWith('.')) { return $false }
        if ($File.Extension -ieq '.tmp') { return $false }
        if ($File.Extension -imatch '^\.(7z|zip)$') { return $true }
        if ($File.Name -match '\.\d{3}$') { return $true }
        return $false
    }

    foreach ($Dir in @($PreStagePath, $InboundPath)) {
        try {
            if (-not (Test-Path $Dir)) {
                New-Item -ItemType Directory -Path $Dir -Force | Out-Null
                Write-StagerLog "Created directory: $Dir" -Type "Info"
            }
        } catch {
            Write-StagerLog "Failed to create $Dir : $_" -Type "Error"
        }
    }

    Write-StagerLog "Pre-stage watcher started. Watching: $PreStagePath -> $InboundPath" -Type "Info"
    $Sync.StagerState = "Running"

    while (-not $Sync.StopRequested) {
        try {
            # RecurseSubfolders (GUI checkbox): some upload/sync tools land files
            # in a subfolder per batch/session rather than directly in Pre-Stage.
            # Every candidate is flattened into Inbound by filename below
            # regardless of how deep it was nested, so this is safe - the source
            # subfolder is left in place (untouched, not deleted) once emptied,
            # in case whatever created it expects it to still exist.
            $Candidates = @(Get-ChildItem -Path $PreStagePath -File -Recurse:$RecurseSubfolders -ErrorAction SilentlyContinue |
                            Where-Object { Test-QualifiesForStaging $_ })

            foreach ($File in $Candidates) {
                if ($Sync.StopRequested) { break }
                try {
                    # Check the (cheap, instant) collision case before paying the
                    # (up to 10-second) settle-confirmation cost below - otherwise a
                    # permanently-colliding file would eat a full confirm-wait on
                    # every single scan cycle, delaying every other candidate queued
                    # behind it in the same pass.
                    $Destination = Join-Path -Path $InboundPath -ChildPath $File.Name
                    if (Test-Path $Destination) {
                        Write-StagerLog "Skipping $($File.Name) - a file with that name already exists in Inbound" -Type "Warning"
                        continue
                    }

                    if (-not (Test-StagerFileSettled -File $File -ConfirmSeconds 10)) {
                        Write-StagerLog "Write not yet confirmed complete, will recheck: $($File.Name)" -Type "Info"
                        continue
                    }

                    Move-Item -Path $File.FullName -Destination $Destination -ErrorAction Stop
                    $StagerFileState.Remove($File.FullName)
                    $Sync.Staged++
                    Write-StagerLog "Staged into inbound: $($File.Name)" -Type "Success"
                } catch {
                    Write-StagerLog "Failed to stage $($File.Name): $_" -Type "Error"
                }
            }

            # Forget tracking for anything no longer a candidate (moved,
            # deleted, or no longer qualifying) so this can't grow unbounded
            # across a long-running unattended session.
            $CandidatePaths = [System.Collections.Generic.HashSet[string]]::new([string[]]@($Candidates.FullName))
            foreach ($key in @($StagerFileState.Keys)) {
                if (-not $CandidatePaths.Contains($key)) { $StagerFileState.Remove($key) }
            }
        } catch {
            Write-StagerLog "Exception scanning pre-stage folder: $_" -Type "Error"
        }

        for ($i = 0; $i -lt $ScanIntervalSeconds; $i++) {
            if ($Sync.StopRequested) { break }
            Start-Sleep -Seconds 1
        }
    }

    Write-StagerLog "Pre-stage watcher stopped." -Type "Warning"
    $Sync.StagerState = "Stopped"
}

# ------------------------------------------------------------------------
# GUI
# ------------------------------------------------------------------------

$Form = New-Object System.Windows.Forms.Form
$Form.Text = "YODA v$YodaGuiVersion"
$Form.Size = New-Object System.Drawing.Size(950, 962)
$Form.MinimumSize = New-Object System.Drawing.Size(860, 862)
$Form.StartPosition = "CenterScreen"
$Form.BackColor = [System.Drawing.Color]::FromArgb(30, 30, 30)
$Form.ForeColor = [System.Drawing.Color]::White
$Form.Font = New-Object System.Drawing.Font("Segoe UI", 9)

# Test-Path throws (rather than returning $false) when -Path is an empty
# string, which happens whenever an optional field (like Pre-Stage) or a
# cleared textbox is checked. Use this wrapper anywhere a GUI text field's
# value is passed to Test-Path.
function Test-PathSafe {
    param([string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path)) { return $false }
    return Test-Path $Path
}

function New-FormLabel {
    param([string]$Text, [int]$X, [int]$Y, [int]$Width = 110)
    $l = New-Object System.Windows.Forms.Label
    $l.Text = $Text
    $l.Location = New-Object System.Drawing.Point($X, $Y)
    $l.Size = New-Object System.Drawing.Size($Width, 20)
    $l.ForeColor = [System.Drawing.Color]::White
    return $l
}

function New-FormTextBox {
    param([int]$X, [int]$Y, [int]$Width, [string]$Text = "")
    $t = New-Object System.Windows.Forms.TextBox
    $t.Location = New-Object System.Drawing.Point($X, $Y)
    $t.Size = New-Object System.Drawing.Size($Width, 22)
    $t.Text = $Text
    return $t
}

function New-FormButton {
    param([string]$Text, [int]$X, [int]$Y, [int]$Width = 90, [int]$Height = 24)
    $b = New-Object System.Windows.Forms.Button
    $b.Text = $Text
    $b.Location = New-Object System.Drawing.Point($X, $Y)
    $b.Size = New-Object System.Drawing.Size($Width, $Height)
    return $b
}

# --- Folders group ---
$grpPaths = New-Object System.Windows.Forms.GroupBox
$grpPaths.Text = "Folders"
$grpPaths.Location = New-Object System.Drawing.Point(15, 15)
$grpPaths.Size = New-Object System.Drawing.Size(900, 229)
$grpPaths.ForeColor = [System.Drawing.Color]::White

$lblBase = New-FormLabel "Base path:" 15 28 90
$txtBase = New-FormTextBox 110 25 580 $Config.BasePath
$btnBrowseBase = New-FormButton "Browse..." 700 24 90

$lblPreStage = New-FormLabel "Pre-stage:" 15 60 90
$txtPreStage = New-FormTextBox 110 57 580 $Config.PreStagePath
$btnBrowsePreStage = New-FormButton "Browse..." 700 56 90

$chkPreStageRecurse = New-Object System.Windows.Forms.CheckBox
$chkPreStageRecurse.Text = "Also look in subfolders of Pre-Stage"
$chkPreStageRecurse.Location = New-Object System.Drawing.Point(110, 88)
$chkPreStageRecurse.Size = New-Object System.Drawing.Size(300, 22)
$chkPreStageRecurse.Checked = [bool]$Config.PreStageRecurseSubfolders
$chkPreStageRecurse.ForeColor = [System.Drawing.Color]::White

$lblInbound = New-FormLabel "Inbound:" 15 124 90
$txtInbound = New-FormTextBox 110 121 580 $Config.InboundPath
$btnBrowseInbound = New-FormButton "Browse..." 700 120 90

$lblExtracted = New-FormLabel "Extracted:" 15 156 90
$txtExtracted = New-FormTextBox 110 153 580 $Config.ExtractedPath
$btnBrowseExtracted = New-FormButton "Browse..." 700 152 90

$lblCompleted = New-FormLabel "Completed:" 15 188 90
$txtCompleted = New-FormTextBox 110 185 580 $Config.CompletedPath
$btnBrowseCompleted = New-FormButton "Browse..." 700 184 90

$toolTip = New-Object System.Windows.Forms.ToolTip
$toolTip.SetToolTip($txtPreStage, "Optional. Files dropped here by another process (downloader, FTP, etc.) are moved into Inbound once they are fully written. Leave blank to disable.")
$toolTip.SetToolTip($lblPreStage, "Optional. Files dropped here by another process (downloader, FTP, etc.) are moved into Inbound once they are fully written. Leave blank to disable.")
$toolTip.SetToolTip($chkPreStageRecurse, "When checked, files in subfolders of Pre-Stage (e.g. a per-batch folder some upload tools create) are found too and flattened into Inbound. The subfolder itself is left in place, never deleted.")
$toolTip.SetToolTip($txtCompleted, "Once an archive extracts successfully, its unzipped output is moved here. The original archive parts stay under Extracted\<name>\RAW - only the extracted content relocates.")
$toolTip.SetToolTip($lblCompleted, "Once an archive extracts successfully, its unzipped output is moved here. The original archive parts stay under Extracted\<name>\RAW - only the extracted content relocates.")

$grpPaths.Controls.AddRange(@(
    $lblBase, $txtBase, $btnBrowseBase,
    $lblPreStage, $txtPreStage, $btnBrowsePreStage,
    $chkPreStageRecurse,
    $lblInbound, $txtInbound, $btnBrowseInbound,
    $lblExtracted, $txtExtracted, $btnBrowseExtracted,
    $lblCompleted, $txtCompleted, $btnBrowseCompleted
))

# --- Engine settings group ---
$grpEngine = New-Object System.Windows.Forms.GroupBox
$grpEngine.Text = "Engine Settings"
$grpEngine.Location = New-Object System.Drawing.Point(15, 254)
$grpEngine.Size = New-Object System.Drawing.Size(900, 168)
$grpEngine.ForeColor = [System.Drawing.Color]::White

$lbl7z = New-FormLabel "7-Zip exe:" 15 28 90
$txt7z = New-FormTextBox 110 25 580 $Config.SevenZipPath
$btnBrowse7z = New-FormButton "Browse..." 700 24 90

$lblInterval = New-FormLabel "Check interval (s):" 15 64 130
$numInterval = New-Object System.Windows.Forms.NumericUpDown
$numInterval.Location = New-Object System.Drawing.Point(150, 62)
$numInterval.Size = New-Object System.Drawing.Size(70, 22)
$numInterval.Minimum = 5
$numInterval.Maximum = 3600
$numInterval.Value = [Math]::Min([Math]::Max([int]$Config.CheckIntervalSeconds, 5), 3600)

$lblEmptyCycles = New-FormLabel "Self-heal after empty cycles:" 260 64 190
$numEmptyCycles = New-Object System.Windows.Forms.NumericUpDown
$numEmptyCycles.Location = New-Object System.Drawing.Point(460, 62)
$numEmptyCycles.Size = New-Object System.Drawing.Size(70, 22)
$numEmptyCycles.Minimum = 1
$numEmptyCycles.Maximum = 1000
$numEmptyCycles.Value = [Math]::Min([Math]::Max([int]$Config.EmptyCyclesBeforeRestart, 1), 1000)

$lblStagerInterval = New-FormLabel "Pre-stage scan (s):" 560 64 160
$numStagerInterval = New-Object System.Windows.Forms.NumericUpDown
$numStagerInterval.Location = New-Object System.Drawing.Point(725, 62)
$numStagerInterval.Size = New-Object System.Drawing.Size(65, 22)
$numStagerInterval.Minimum = 5
$numStagerInterval.Maximum = 3600
$numStagerInterval.Value = [Math]::Min([Math]::Max([int]$Config.StagerScanIntervalSeconds, 5), 3600)

$chkTheme = New-Object System.Windows.Forms.CheckBox
$chkTheme.Text = "Star Wars intro"
$chkTheme.Location = New-Object System.Drawing.Point(15, 100)
$chkTheme.Size = New-Object System.Drawing.Size(140, 22)
$chkTheme.Checked = [bool]$Config.EnableStarWarsTheme
$chkTheme.ForeColor = [System.Drawing.Color]::White

$chkArt = New-Object System.Windows.Forms.CheckBox
$chkArt.Text = "Yoda art"
$chkArt.Location = New-Object System.Drawing.Point(165, 100)
$chkArt.Size = New-Object System.Drawing.Size(100, 22)
$chkArt.Checked = [bool]$Config.EnableYodaArt
$chkArt.ForeColor = [System.Drawing.Color]::White

$chkQuotes = New-Object System.Windows.Forms.CheckBox
$chkQuotes.Text = "Yoda quotes"
$chkQuotes.Location = New-Object System.Drawing.Point(275, 100)
$chkQuotes.Size = New-Object System.Drawing.Size(120, 22)
$chkQuotes.Checked = [bool]$Config.EnableYodaQuotes
$chkQuotes.ForeColor = [System.Drawing.Color]::White

$chkBeeps = New-Object System.Windows.Forms.CheckBox
$chkBeeps.Text = "Theme beeps"
$chkBeeps.Location = New-Object System.Drawing.Point(405, 100)
$chkBeeps.Size = New-Object System.Drawing.Size(120, 22)
$chkBeeps.Checked = [bool]$Config.EnableThemeBeeps
$chkBeeps.ForeColor = [System.Drawing.Color]::White

$chkGreenText = New-Object System.Windows.Forms.CheckBox
$chkGreenText.Text = "Green console text (classic CLI only)"
$chkGreenText.Location = New-Object System.Drawing.Point(535, 100)
$chkGreenText.Size = New-Object System.Drawing.Size(260, 22)
$chkGreenText.Checked = [bool]$Config.EnableGreenText
$chkGreenText.ForeColor = [System.Drawing.Color]::White

$chkHashFiles = New-Object System.Windows.Forms.CheckBox
$chkHashFiles.Text = "MD5 hash extracted files"
$chkHashFiles.Location = New-Object System.Drawing.Point(15, 128)
$chkHashFiles.Size = New-Object System.Drawing.Size(200, 22)
$chkHashFiles.Checked = [bool]$Config.HashExtractedFiles
$chkHashFiles.ForeColor = [System.Drawing.Color]::White

$chkHashParts = New-Object System.Windows.Forms.CheckBox
$chkHashParts.Text = "MD5 hash archive parts"
$chkHashParts.Location = New-Object System.Drawing.Point(225, 128)
$chkHashParts.Size = New-Object System.Drawing.Size(200, 22)
$chkHashParts.Checked = [bool]$Config.HashArchiveParts
$chkHashParts.ForeColor = [System.Drawing.Color]::White

$chkSuccessBanner = New-Object System.Windows.Forms.CheckBox
$chkSuccessBanner.Text = "Show success banner popup"
$chkSuccessBanner.Location = New-Object System.Drawing.Point(435, 128)
$chkSuccessBanner.Size = New-Object System.Drawing.Size(220, 22)
$chkSuccessBanner.Checked = [bool]$Config.ShowSuccessBanner
$chkSuccessBanner.ForeColor = [System.Drawing.Color]::White

$toolTip.SetToolTip($chkHashFiles, "After each successful extraction, writes MD5_Hashes.txt into the extracted output folder - one MD5 line per file, in standard md5sum format.")
$toolTip.SetToolTip($chkHashParts, "After each successful extraction, writes MD5_Hashes_Parts.txt into the RAW folder - one MD5 line per original archive part, in standard md5sum format.")
$toolTip.SetToolTip($chkSuccessBanner, "Shows a green on-screen banner naming the archive, its destination, and how many files were extracted, for a few seconds, whenever an archive completes successfully. Never blocks the engine - it's informational only.")

$grpEngine.Controls.AddRange(@(
    $lbl7z, $txt7z, $btnBrowse7z,
    $lblInterval, $numInterval, $lblEmptyCycles, $numEmptyCycles, $lblStagerInterval, $numStagerInterval,
    $chkTheme, $chkArt, $chkQuotes, $chkBeeps, $chkGreenText,
    $chkHashFiles, $chkHashParts, $chkSuccessBanner
))

# --- Action buttons ---
$btnStart = New-FormButton "Start" 15 432 110 32
$btnStart.BackColor = [System.Drawing.Color]::FromArgb(40, 90, 40)
$btnStart.ForeColor = [System.Drawing.Color]::White

$btnStop = New-FormButton "Stop" 135 432 110 32
$btnStop.BackColor = [System.Drawing.Color]::FromArgb(90, 40, 40)
$btnStop.ForeColor = [System.Drawing.Color]::White
$btnStop.Enabled = $false

$btnOpenPreStage = New-FormButton "Open Pre-Stage" 15 472 120 28
$btnOpenInbound = New-FormButton "Open Inbound" 145 472 110 28
$btnOpenExtracted = New-FormButton "Open Extracted" 265 472 110 28
$btnOpenCompleted = New-FormButton "Open Completed" 385 472 120 28
$btnOpenLogs = New-FormButton "Open Logs" 515 472 90 28
$btnClearLog = New-FormButton "Clear Log" 615 472 100 28

# --- Status strip ---
$statusStrip = New-Object System.Windows.Forms.StatusStrip
$lblState = New-Object System.Windows.Forms.ToolStripStatusLabel
$lblState.Text = "State: Idle"
$lblCycle = New-Object System.Windows.Forms.ToolStripStatusLabel
$lblCycle.Text = "Cycle: 0"
$lblCompleted = New-Object System.Windows.Forms.ToolStripStatusLabel
$lblCompleted.Text = "Completed: 0"
$lblWaiting = New-Object System.Windows.Forms.ToolStripStatusLabel
$lblWaiting.Text = "Waiting: 0"
$lblFailed = New-Object System.Windows.Forms.ToolStripStatusLabel
$lblFailed.Text = "Failed: 0"
$lblErrors = New-Object System.Windows.Forms.ToolStripStatusLabel
$lblErrors.Text = "Errors: 0"
$lblStagerState = New-Object System.Windows.Forms.ToolStripStatusLabel
$lblStagerState.Text = "Stager: Idle"
$lblStaged = New-Object System.Windows.Forms.ToolStripStatusLabel
$lblStaged.Text = "Staged: 0"
$lblCountdown = New-Object System.Windows.Forms.ToolStripStatusLabel
$lblCountdown.Text = ""
$lblCountdown.Spring = $true
$lblCountdown.TextAlign = [System.Drawing.ContentAlignment]::MiddleRight
$statusStrip.Items.AddRange(@($lblState, $lblCycle, $lblCompleted, $lblWaiting, $lblFailed, $lblErrors, $lblStagerState, $lblStaged, $lblCountdown))

# --- Log view - a tab for the full activity log, and a second tab that only
# ever gets a line added on a successful completion, so "what's finished"
# never requires scrolling back through routine cycle noise. ---
$tabLog = New-Object System.Windows.Forms.TabControl
$tabLog.Location = New-Object System.Drawing.Point(15, 510)
$tabLog.Size = New-Object System.Drawing.Size(900, 300)
$tabLog.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Bottom -bor [System.Windows.Forms.AnchorStyles]::Left -bor [System.Windows.Forms.AnchorStyles]::Right

$tabPageActivity = New-Object System.Windows.Forms.TabPage
$tabPageActivity.Text = "Activity Log"

$tabPageCompleted = New-Object System.Windows.Forms.TabPage
$tabPageCompleted.Text = "Completed Archives"

$rtbLog = New-Object System.Windows.Forms.RichTextBox
$rtbLog.Dock = [System.Windows.Forms.DockStyle]::Fill
$rtbLog.ReadOnly = $true
$rtbLog.BackColor = [System.Drawing.Color]::Black
$rtbLog.ForeColor = [System.Drawing.Color]::Cyan
$rtbLog.Font = New-Object System.Drawing.Font("Consolas", 9)
$rtbLog.WordWrap = $true

$rtbCompleted = New-Object System.Windows.Forms.RichTextBox
$rtbCompleted.Dock = [System.Windows.Forms.DockStyle]::Fill
$rtbCompleted.ReadOnly = $true
$rtbCompleted.BackColor = [System.Drawing.Color]::Black
$rtbCompleted.ForeColor = [System.Drawing.Color]::LightGreen
$rtbCompleted.Font = New-Object System.Drawing.Font("Consolas", 9)
$rtbCompleted.WordWrap = $true

$tabPageActivity.Controls.Add($rtbLog)
$tabPageCompleted.Controls.Add($rtbCompleted)
$tabLog.TabPages.AddRange(@($tabPageActivity, $tabPageCompleted))

$Form.Controls.AddRange(@(
    $grpPaths, $grpEngine,
    $btnStart, $btnStop, $btnOpenPreStage, $btnOpenInbound, $btnOpenExtracted, $btnOpenCompleted, $btnOpenLogs, $btnClearLog,
    $tabLog, $statusStrip
))

# ------------------------------------------------------------------------
# Behavior
# ------------------------------------------------------------------------

function Save-CurrentConfig {
    $cfg = [PSCustomObject]@{
        BasePath                  = $txtBase.Text
        PreStagePath              = $txtPreStage.Text
        PreStageRecurseSubfolders = $chkPreStageRecurse.Checked
        InboundPath               = $txtInbound.Text
        ExtractedPath             = $txtExtracted.Text
        CompletedPath             = $txtCompleted.Text
        SevenZipPath              = $txt7z.Text
        CheckIntervalSeconds      = [int]$numInterval.Value
        EmptyCyclesBeforeRestart  = [int]$numEmptyCycles.Value
        StagerScanIntervalSeconds = [int]$numStagerInterval.Value
        EnableStarWarsTheme       = $chkTheme.Checked
        EnableYodaArt             = $chkArt.Checked
        EnableYodaQuotes          = $chkQuotes.Checked
        EnableThemeBeeps          = $chkBeeps.Checked
        EnableGreenText           = $chkGreenText.Checked
        HashExtractedFiles        = $chkHashFiles.Checked
        HashArchiveParts          = $chkHashParts.Checked
        ShowSuccessBanner         = $chkSuccessBanner.Checked
    }
    Export-GuiConfig -Config $cfg
}

function Set-InputsEnabled {
    param([bool]$Enabled)
    foreach ($ctrl in @($txtBase, $txtPreStage, $txtInbound, $txtExtracted, $txtCompleted, $txt7z, $numInterval, $numEmptyCycles, $numStagerInterval,
                        $chkTheme, $chkArt, $chkQuotes, $chkBeeps, $chkGreenText, $chkPreStageRecurse,
                        $chkHashFiles, $chkHashParts, $chkSuccessBanner,
                        $btnBrowseBase, $btnBrowsePreStage, $btnBrowseInbound, $btnBrowseExtracted, $btnBrowseCompleted, $btnBrowse7z)) {
        $ctrl.Enabled = $Enabled
    }
}

function Add-LogEntry {
    param($Entry)
    $color = switch ($Entry.Type) {
        "Success" { [System.Drawing.Color]::LightGreen }
        "Warning" { [System.Drawing.Color]::Gold }
        "Error"   { [System.Drawing.Color]::OrangeRed }
        default   { [System.Drawing.Color]::Cyan }
    }
    $rtbLog.SelectionStart = $rtbLog.TextLength
    $rtbLog.SelectionLength = 0
    $rtbLog.SelectionColor = $color
    $rtbLog.AppendText("$($Entry.Message)`r`n")
    $rtbLog.ScrollToCaret()

    if ($rtbLog.Lines.Count -gt 3000) {
        $keep = $rtbLog.Lines[-2000..-1] -join "`r`n"
        $rtbLog.Text = $keep + "`r`n"
        $rtbLog.SelectionStart = $rtbLog.TextLength
        $rtbLog.ScrollToCaret()
    }
}

# Tracks how many success banners are currently on screen, so a burst of
# completions (several archives finishing in the same cycle) stacks them
# instead of piling up on top of each other.
# Open banners, oldest first - lets a new one evict the oldest once the cap
# is hit, and lets Stop-Engine (or the form closing) sweep all of them.
$script:OpenBanners = [System.Collections.Generic.List[object]]::new()
$script:MaxOpenBanners = 8

# A non-modal notification for a completed extraction. Never uses
# ShowDialog()/MessageBox - this must not block the unattended engine
# waiting for someone to click OK. It stays on screen until closed (the X
# button, or Stop/exit) rather than timing out, since the whole point is to
# still be visible whenever someone next looks at the screen - but the
# count of simultaneously-open banners is capped so a long unattended run
# processing many archives can never accumulate windows without bound; once
# the cap is hit, the oldest banner is closed to make room for the newest.
function Show-SuccessBanner {
    param($Event)

    while ($script:OpenBanners.Count -ge $script:MaxOpenBanners) {
        $oldest = $script:OpenBanners[0]
        $script:OpenBanners.RemoveAt(0)
        try { $oldest.Close(); $oldest.Dispose() } catch { }
    }

    $banner = New-Object System.Windows.Forms.Form
    $banner.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::None
    $banner.StartPosition = "Manual"
    $banner.Size = New-Object System.Drawing.Size(420, 130)
    $banner.BackColor = [System.Drawing.Color]::FromArgb(28, 130, 58)
    $banner.ShowInTaskbar = $false
    $banner.TopMost = $true

    $workArea = [System.Windows.Forms.Screen]::PrimaryScreen.WorkingArea
    $x = $workArea.Right - $banner.Width - 20
    $y = $workArea.Bottom - $banner.Height - 20 - ($script:OpenBanners.Count * ($banner.Height + 12))
    $banner.Location = New-Object System.Drawing.Point($x, $y)

    $banner.Add_Paint({
        param($s, $e)
        $pen = New-Object System.Drawing.Pen([System.Drawing.Color]::White, 2)
        $e.Graphics.DrawRectangle($pen, 1, 1, $s.Width - 3, $s.Height - 3)
        $pen.Dispose()
    })

    $lblTitle = New-Object System.Windows.Forms.Label
    $lblTitle.Text = [char]0x2713 + " Extraction Successful"
    $lblTitle.Font = New-Object System.Drawing.Font("Segoe UI", 13, [System.Drawing.FontStyle]::Bold)
    $lblTitle.ForeColor = [System.Drawing.Color]::White
    $lblTitle.Location = New-Object System.Drawing.Point(14, 10)
    $lblTitle.Size = New-Object System.Drawing.Size(368, 28)

    $btnClose = New-Object System.Windows.Forms.Label
    $btnClose.Text = [char]0x2715
    $btnClose.Font = New-Object System.Drawing.Font("Segoe UI", 11, [System.Drawing.FontStyle]::Bold)
    $btnClose.ForeColor = [System.Drawing.Color]::White
    $btnClose.Location = New-Object System.Drawing.Point(388, 8)
    $btnClose.Size = New-Object System.Drawing.Size(24, 24)
    $btnClose.Cursor = [System.Windows.Forms.Cursors]::Hand
    $btnClose.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter
    $btnClose.Add_Click({ $banner.Close() }.GetNewClosure())

    $lblDetails = New-Object System.Windows.Forms.Label
    $PartInfo = if ($Event.PartCount) { " ($($Event.PartCount) part(s))" } else { "" }
    $lblDetails.Text = "$($Event.ArchiveName)$PartInfo`r`n$($Event.FileCount) file(s) extracted to:`r`n$($Event.Location)"
    $lblDetails.Font = New-Object System.Drawing.Font("Segoe UI", 9)
    $lblDetails.ForeColor = [System.Drawing.Color]::White
    $lblDetails.Location = New-Object System.Drawing.Point(14, 42)
    $lblDetails.Size = New-Object System.Drawing.Size(392, 78)
    $lblDetails.AutoEllipsis = $true

    $banner.Controls.AddRange(@($lblTitle, $btnClose, $lblDetails))

    $banner.Add_FormClosed({
        [void]$script:OpenBanners.Remove($banner)
    }.GetNewClosure())

    $script:OpenBanners.Add($banner)
    $banner.Show()
}

function Stop-Engine {
    param([int]$WaitSeconds = 5)
    if ($null -eq $script:EnginePS -and $null -eq $script:StagerPS) { return }
    $Sync.StopRequested = $true
    $deadline = (Get-Date).AddSeconds($WaitSeconds)
    while ((($null -ne $script:EnginePS -and $Sync.State -ne "Stopped") -or
            ($null -ne $script:StagerPS -and $Sync.StagerState -ne "Stopped")) -and
           (Get-Date) -lt $deadline) {
        Start-Sleep -Milliseconds 100
    }
    if ($null -ne $script:EnginePS) {
        try { [void]$script:EnginePS.Stop() } catch { }
        try { $script:EnginePS.Dispose() } catch { }
        try { $script:EngineRunspace.Close() } catch { }
        try { $script:EngineRunspace.Dispose() } catch { }
        $script:EnginePS = $null
        $script:EngineRunspace = $null
        $script:EngineAsync = $null
    }
    if ($null -ne $script:StagerPS) {
        try { [void]$script:StagerPS.Stop() } catch { }
        try { $script:StagerPS.Dispose() } catch { }
        try { $script:StagerRunspace.Close() } catch { }
        try { $script:StagerRunspace.Dispose() } catch { }
        $script:StagerPS = $null
        $script:StagerRunspace = $null
        $script:StagerAsync = $null
    }
}

$btnBrowseBase.Add_Click({
    $dlg = New-Object System.Windows.Forms.FolderBrowserDialog
    if (Test-PathSafe $txtBase.Text) { $dlg.SelectedPath = $txtBase.Text }
    if ($dlg.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) { $txtBase.Text = $dlg.SelectedPath }
})

$btnBrowsePreStage.Add_Click({
    $dlg = New-Object System.Windows.Forms.FolderBrowserDialog
    if (Test-PathSafe $txtPreStage.Text) { $dlg.SelectedPath = $txtPreStage.Text }
    if ($dlg.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) { $txtPreStage.Text = $dlg.SelectedPath }
})

$btnBrowseInbound.Add_Click({
    $dlg = New-Object System.Windows.Forms.FolderBrowserDialog
    if (Test-PathSafe $txtInbound.Text) { $dlg.SelectedPath = $txtInbound.Text }
    if ($dlg.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) { $txtInbound.Text = $dlg.SelectedPath }
})

$btnBrowseExtracted.Add_Click({
    $dlg = New-Object System.Windows.Forms.FolderBrowserDialog
    if (Test-PathSafe $txtExtracted.Text) { $dlg.SelectedPath = $txtExtracted.Text }
    if ($dlg.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) { $txtExtracted.Text = $dlg.SelectedPath }
})

$btnBrowseCompleted.Add_Click({
    $dlg = New-Object System.Windows.Forms.FolderBrowserDialog
    if (Test-PathSafe $txtCompleted.Text) { $dlg.SelectedPath = $txtCompleted.Text }
    if ($dlg.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) { $txtCompleted.Text = $dlg.SelectedPath }
})

$btnBrowse7z.Add_Click({
    $dlg = New-Object System.Windows.Forms.OpenFileDialog
    $dlg.Filter = "7z.exe|7z.exe|Executable files (*.exe)|*.exe|All files (*.*)|*.*"
    if (Test-PathSafe $txt7z.Text) { $dlg.InitialDirectory = Split-Path $txt7z.Text -Parent }
    if ($dlg.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) { $txt7z.Text = $dlg.FileName }
})

$btnOpenPreStage.Add_Click({
    if ([string]::IsNullOrWhiteSpace($txtPreStage.Text)) {
        [System.Windows.Forms.MessageBox]::Show("No pre-stage folder is configured.", "YODA") | Out-Null
    } elseif (Test-PathSafe $txtPreStage.Text) {
        Start-Process explorer.exe $txtPreStage.Text
    } else {
        [System.Windows.Forms.MessageBox]::Show("Pre-stage folder does not exist yet.", "YODA") | Out-Null
    }
})

$btnOpenInbound.Add_Click({
    if (Test-PathSafe $txtInbound.Text) { Start-Process explorer.exe $txtInbound.Text }
    else { [System.Windows.Forms.MessageBox]::Show("Inbound folder does not exist yet.", "YODA") | Out-Null }
})

$btnOpenExtracted.Add_Click({
    if (Test-PathSafe $txtExtracted.Text) { Start-Process explorer.exe $txtExtracted.Text }
    else { [System.Windows.Forms.MessageBox]::Show("Extracted folder does not exist yet.", "YODA") | Out-Null }
})

$btnOpenCompleted.Add_Click({
    if (Test-PathSafe $txtCompleted.Text) { Start-Process explorer.exe $txtCompleted.Text }
    else { [System.Windows.Forms.MessageBox]::Show("Completed folder does not exist yet.", "YODA") | Out-Null }
})

$btnOpenLogs.Add_Click({
    if ([string]::IsNullOrWhiteSpace($txtBase.Text)) {
        [System.Windows.Forms.MessageBox]::Show("Set a Base path first.", "YODA") | Out-Null
        return
    }
    $logsPath = Join-Path -Path $txtBase.Text -ChildPath "logs"
    if (Test-PathSafe $logsPath) { Start-Process explorer.exe $logsPath }
    else { [System.Windows.Forms.MessageBox]::Show("Logs folder does not exist yet.", "YODA") | Out-Null }
})

$btnClearLog.Add_Click({
    if ($tabLog.SelectedTab -eq $tabPageCompleted) { $rtbCompleted.Clear() } else { $rtbLog.Clear() }
})

$btnStart.Add_Click({
    if ($null -ne $script:EnginePS) { return }

    $basePath = $txtBase.Text.Trim()
    $preStagePath = $txtPreStage.Text.Trim()
    $inboundPath = $txtInbound.Text.Trim()
    $extractedPath = $txtExtracted.Text.Trim()
    $completedPath = $txtCompleted.Text.Trim()
    $sevenZip = $txt7z.Text.Trim()

    if ([string]::IsNullOrWhiteSpace($basePath) -or [string]::IsNullOrWhiteSpace($inboundPath) -or
        [string]::IsNullOrWhiteSpace($extractedPath) -or [string]::IsNullOrWhiteSpace($completedPath) -or
        [string]::IsNullOrWhiteSpace($sevenZip)) {
        [System.Windows.Forms.MessageBox]::Show("Please fill in Base, Inbound, Extracted, Completed and 7-Zip paths.", "YODA") | Out-Null
        return
    }
    if (-not (Test-PathSafe $sevenZip)) {
        [System.Windows.Forms.MessageBox]::Show("7-Zip executable not found at:`n$sevenZip", "YODA") | Out-Null
        return
    }
    if (-not [string]::IsNullOrWhiteSpace($preStagePath) -and
        ($preStagePath.TrimEnd('\', '/') -ieq $inboundPath.TrimEnd('\', '/'))) {
        [System.Windows.Forms.MessageBox]::Show("Pre-stage and Inbound must be different folders.", "YODA") | Out-Null
        return
    }

    $Sync.StopRequested = $false
    $Sync.State = "Starting"
    $Sync.Cycle = 0
    $Sync.Completed = 0
    $Sync.Waiting = 0
    $Sync.Failed = 0
    $Sync.Errors = 0
    $Sync.Countdown = ""
    $Sync.StagerState = "Idle"
    $Sync.Staged = 0
    $dummy = $null
    while ($Sync.LogQueue.TryDequeue([ref]$dummy)) { }

    $script:EngineRunspace = [runspacefactory]::CreateRunspace()
    $script:EngineRunspace.Open()
    $script:EnginePS = [powershell]::Create()
    $script:EnginePS.Runspace = $script:EngineRunspace
    [void]$script:EnginePS.AddScript($EngineScriptBlock.ToString()).AddParameters(@{
        BasePath                 = $basePath
        InboundPath               = $inboundPath
        ExtractedPath             = $extractedPath
        CompletedPath             = $completedPath
        SevenZipPath              = $sevenZip
        CheckIntervalSeconds      = [int]$numInterval.Value
        EmptyCyclesBeforeRestart  = [int]$numEmptyCycles.Value
        EnableStarWarsTheme       = $chkTheme.Checked
        EnableYodaArt             = $chkArt.Checked
        EnableYodaQuotes          = $chkQuotes.Checked
        EnableThemeBeeps          = $chkBeeps.Checked
        EnableGreenText           = $chkGreenText.Checked
        HashExtractedFiles        = $chkHashFiles.Checked
        HashArchiveParts          = $chkHashParts.Checked
        Sync                      = $Sync
    })
    $script:EngineAsync = $script:EnginePS.BeginInvoke()

    if (-not [string]::IsNullOrWhiteSpace($preStagePath)) {
        $script:StagerRunspace = [runspacefactory]::CreateRunspace()
        $script:StagerRunspace.Open()
        $script:StagerPS = [powershell]::Create()
        $script:StagerPS.Runspace = $script:StagerRunspace
        [void]$script:StagerPS.AddScript($StagerScriptBlock.ToString()).AddParameters(@{
            PreStagePath        = $preStagePath
            InboundPath         = $inboundPath
            ScanIntervalSeconds = [int]$numStagerInterval.Value
            RecurseSubfolders   = $chkPreStageRecurse.Checked
            Sync                = $Sync
        })
        $script:StagerAsync = $script:StagerPS.BeginInvoke()
    }

    $btnStart.Enabled = $false
    $btnStop.Enabled = $true
    Set-InputsEnabled -Enabled $false
    Save-CurrentConfig
})

$btnStop.Add_Click({
    if ($null -eq $script:EnginePS -and $null -eq $script:StagerPS) { return }
    $Sync.StopRequested = $true
    $Sync.State = "Stopping"
    if ($null -ne $script:StagerPS) { $Sync.StagerState = "Stopping" }
    $btnStop.Enabled = $false
})

$tmrPoll = New-Object System.Windows.Forms.Timer
$tmrPoll.Interval = 250
$tmrPoll.Add_Tick({
    $dummy = $null
    $drained = 0
    while ($Sync.LogQueue.TryDequeue([ref]$dummy)) {
        Add-LogEntry -Entry $dummy
        $drained++
        if ($drained -ge 200) { break }
    }

    $successEvent = $null
    while ($Sync.SuccessQueue.TryDequeue([ref]$successEvent)) {
        if ($chkSuccessBanner.Checked) { Show-SuccessBanner -Event $successEvent }

        $PartInfo = if ($successEvent.PartCount) { " ($($successEvent.PartCount) part(s))" } else { "" }
        $line = "[$($successEvent.Timestamp.ToString('yyyy-MM-dd HH:mm:ss'))] $($successEvent.ArchiveName)$PartInfo - $($successEvent.FileCount) file(s) - $($successEvent.Location)"
        $rtbCompleted.AppendText("$line`r`n")
        $rtbCompleted.SelectionStart = $rtbCompleted.TextLength
        $rtbCompleted.ScrollToCaret()
        if ($rtbCompleted.Lines.Count -gt 3000) {
            $keep = $rtbCompleted.Lines[-2000..-1] -join "`r`n"
            $rtbCompleted.Text = $keep + "`r`n"
            $rtbCompleted.SelectionStart = $rtbCompleted.TextLength
            $rtbCompleted.ScrollToCaret()
        }
    }

    $lblState.Text = "State: $($Sync.State)"
    $lblCycle.Text = "Cycle: $($Sync.Cycle)"
    $lblCompleted.Text = "Completed: $($Sync.Completed)"
    $lblWaiting.Text = "Waiting: $($Sync.Waiting)"
    $lblFailed.Text = "Failed: $($Sync.Failed)"
    $lblErrors.Text = "Errors: $($Sync.Errors)"
    $lblStagerState.Text = "Stager: $($Sync.StagerState)"
    $lblStaged.Text = "Staged: $($Sync.Staged)"
    $lblCountdown.Text = $Sync.Countdown

    if ($Sync.State -eq "Stopped" -and $null -ne $script:EnginePS) {
        try { [void]$script:EnginePS.EndInvoke($script:EngineAsync) } catch { }
        try { $script:EnginePS.Dispose() } catch { }
        try { $script:EngineRunspace.Close() } catch { }
        try { $script:EngineRunspace.Dispose() } catch { }
        $script:EnginePS = $null
        $script:EngineRunspace = $null
        $script:EngineAsync = $null
    }

    if ($Sync.StagerState -eq "Stopped" -and $null -ne $script:StagerPS) {
        try { [void]$script:StagerPS.EndInvoke($script:StagerAsync) } catch { }
        try { $script:StagerPS.Dispose() } catch { }
        try { $script:StagerRunspace.Close() } catch { }
        try { $script:StagerRunspace.Dispose() } catch { }
        $script:StagerPS = $null
        $script:StagerRunspace = $null
        $script:StagerAsync = $null
    }

    if ($null -eq $script:EnginePS -and $null -eq $script:StagerPS -and -not $btnStart.Enabled) {
        $btnStart.Enabled = $true
        $btnStop.Enabled = $false
        Set-InputsEnabled -Enabled $true
    }
})
$tmrPoll.Start()

$Form.Add_FormClosing({
    $tmrPoll.Stop()
    if ($null -ne $script:EnginePS -or $null -ne $script:StagerPS) {
        Stop-Engine -WaitSeconds 5
    }
    foreach ($b in @($script:OpenBanners)) { try { $b.Close(); $b.Dispose() } catch { } }
    $script:OpenBanners.Clear()
    Save-CurrentConfig
})

[void]$Form.ShowDialog()
