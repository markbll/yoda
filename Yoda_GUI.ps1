<#
    Yoda_GUI.ps1

    A Windows Forms front-end for "Yoda The Unzipper" - the watch-folder
    7-Zip/ZIP split-archive extractor scripts bundled in
    Yoda_The_Unzipper-main.zip.

    Instead of editing command-line parameters and staring at a console
    window, this lets you configure the watcher, start/stop it, and watch
    a live, color-coded log with running stats - all from one window.

    Requirements: Windows PowerShell 5.1+ (or PowerShell 7+ on Windows),
    .NET WinForms, and 7-Zip installed.

    Run with:
        powershell.exe -ExecutionPolicy Bypass -File Yoda_GUI.ps1
#>

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

    $SplashArt = @"
        ___.-'`~^~'^-._
       /                \_
      |  (\___/)  Yoda  |
      |  (= ^.^ =)      |
       \_  c\~//~ ) /^--_/
         ^~._//^~_/^
              ||
              ||
              |\
              | \_
              |   |
             /|   |\
            / |   | \
           /  |   |  \
          /   |   |   \
"@

    $splash = New-Object System.Windows.Forms.Form
    $splash.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::None
    $splash.StartPosition = "CenterScreen"
    $splash.Size = New-Object System.Drawing.Size(720, 600)
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
    $lblTitle.Font = New-Object System.Drawing.Font("Segoe UI Black", 30, [System.Drawing.FontStyle]::Bold)
    $lblTitle.ForeColor = [System.Drawing.Color]::Gold
    $lblTitle.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter
    $lblTitle.Location = New-Object System.Drawing.Point(0, 40)
    $lblTitle.Size = New-Object System.Drawing.Size($splash.Width, 60)

    $lblArt = New-Object System.Windows.Forms.Label
    $lblArt.Text = $SplashArt
    $lblArt.Font = New-Object System.Drawing.Font("Consolas", 18)
    $lblArt.ForeColor = [System.Drawing.Color]::Yellow
    $lblArt.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter
    $lblArt.Location = New-Object System.Drawing.Point(0, 120)
    $lblArt.Size = New-Object System.Drawing.Size($splash.Width, 380)

    $lblSubtitle = New-Object System.Windows.Forms.Label
    $lblSubtitle.Text = "May the Force be with you... loading"
    $lblSubtitle.Font = New-Object System.Drawing.Font("Segoe UI", 12, [System.Drawing.FontStyle]::Italic)
    $lblSubtitle.ForeColor = [System.Drawing.Color]::Cyan
    $lblSubtitle.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter
    $lblSubtitle.Location = New-Object System.Drawing.Point(0, 520)
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
        BasePath                  = "C:\unzipper"
        PreStagePath              = ""
        InboundPath               = "C:\unzipper\inbound"
        ExtractedPath             = "C:\unzipper\extracted"
        SevenZipPath              = "C:\Program Files\7-Zip\7z.exe"
        CheckIntervalSeconds      = 30
        EmptyCyclesBeforeRestart  = 10
        StagerScanIntervalSeconds = 15
        EnableStarWarsTheme       = $true
        EnableYodaArt             = $true
        EnableYodaQuotes          = $true
        EnableThemeBeeps          = $true
        EnableGreenText           = $true
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
        [string]$SevenZipPath,
        [int]$CheckIntervalSeconds,
        [int]$EmptyCyclesBeforeRestart,
        [bool]$EnableStarWarsTheme,
        [bool]$EnableYodaArt,
        [bool]$EnableYodaQuotes,
        [bool]$EnableThemeBeeps,
        [bool]$EnableGreenText,
        $Sync
    )

    $LogFolder = Join-Path -Path $BasePath -ChildPath "logs"
    $MissingPartsFile = Join-Path -Path $LogFolder -ChildPath "missing_parts_log.txt"
    $FailedArchivesFile = Join-Path -Path $LogFolder -ChildPath "failed_archives_log.txt"
    $ErrorDetailsFile = Join-Path -Path $LogFolder -ChildPath "error_details_log.txt"
    $ErrorCount = 0
    $ProcessedArchives = @{}
    $ConsecutiveEmptyCycles = 0

    if (-not (Test-Path $LogFolder)) {
        New-Item -ItemType Directory -Path $LogFolder -Force | Out-Null
    }

    $LogFile = Join-Path -Path $LogFolder -ChildPath "extraction_log_$(Get-Date -Format 'yyyyMMdd_HHmmss').txt"

    $YodaQuotes = @{
        "Waiting" = "Patience, you must have. Archives, they are coming, yes."
    }

    $YodaArt = @"
        ___.-'`~^~'^-._
       /                \_
      |  (\___/)  Yoda  |
      |  (= ^.^ =)      |
       \_  c\~//~ ) /^--_/
         ^~._//^~_/^
              ||
              ||
              |\
              | \_
              |   |
             /|   |\
            / |   | \
           /  |   |  \
          /   |   |   \
"@

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

    function Get-ArchiveGroups {
        param([string]$Path)
        try {
            $Files = @(Get-ChildItem -Path $Path -File -ErrorAction SilentlyContinue |
                       Where-Object { $_.Extension -match '\.(7z|zip)' -or $_.Name -match '\.(001|002|003|004|005|006|007|008|009)$' })
            if ($Files.Count -eq 0) { return @{} }
            $Groups = @{}
            foreach ($File in $Files) {
                $BaseName = $File.Name -replace '\.\d{3}$', ''
                $BaseName = $BaseName -replace '\.zip$', ''
                $BaseName = $BaseName -replace '\.7z$', ''
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
                    Write-Log "Archive has $VolumeCount volume(s)" -Type "Info"
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

    function Verify-AllPartsPresentAndStable {
        param([string]$BaseName, [string]$SourcePath, [int]$ExpectedCount)
        $PartFiles = @(Get-ChildItem -Path $SourcePath -File -ErrorAction SilentlyContinue |
                       Where-Object { $_.Name -like "$BaseName*" } | Sort-Object Name)
        $ActualCount = $PartFiles.Count
        Write-Log "Verifying parts for $BaseName : Expected=$ExpectedCount, Found=$ActualCount" -Type "Info"
        if ($ActualCount -lt $ExpectedCount) {
            $MissingCount = $ExpectedCount - $ActualCount
            $Message = "INCOMPLETE - Missing $MissingCount of $ExpectedCount parts. Found: $ActualCount parts"
            Write-Log $Message -Type "Warning"
            Write-MissingPartsLog $BaseName $Message

            $MissingFiles = @()
            for ($i = 1; $i -le $ExpectedCount; $i++) {
                $PartNum = $i.ToString("000")
                $PartName = "$BaseName.$PartNum"
                if (-not ($PartFiles | Where-Object { $_.Name -eq $PartName })) { $MissingFiles += $PartName }
            }
            if ($MissingFiles.Count -gt 0) {
                Write-Log "Missing files: $($MissingFiles -join ', ')" -Type "Warning"
                Write-MissingPartsLog $BaseName "Missing: $($MissingFiles -join ', ')"
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
            if ($LASTEXITCODE -eq 0) {
                Write-Log "Archive integrity test PASSED: $FileName" -Type "Success"
                return $true
            } else {
                Write-Log "Archive integrity test FAILED: $FileName" -Type "Error"
                $BaseName = $FileName -replace '\.\d{3}$', '' -replace '\.zip$', '' -replace '\.7z$', ''
                Write-FailedArchiveLog $BaseName "Integrity Test Failed" ($TestOutput | Out-String)
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
            $FolderName = "$ArchiveName`_$Timestamp"
            $FinalDestination = Join-Path -Path $DestinationPath -ChildPath $FolderName

            if (-not (Test-Path $FinalDestination)) {
                New-Item -ItemType Directory -Path $FinalDestination -Force | Out-Null
                Write-Log "Created extraction directory: $FinalDestination" -Type "Info"
            }

            Write-Log "Extracting archive to: $FinalDestination" -Type "Info"
            $ExtractOutput = @(& $SevenZipPath x $FirstPartPath "-o$FinalDestination" 2>&1)

            if ($LASTEXITCODE -eq 0) {
                Write-Log "Archive extraction completed successfully: $ArchiveName" -Type "Success"
                return $FinalDestination
            } else {
                Write-Log "Archive extraction FAILED: $ArchiveName" -Type "Error"
                Write-FailedArchiveLog $ArchiveName "Extraction Failed" ($ExtractOutput | Out-String)
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
        param([string]$BaseName, [string]$SourcePath, [string]$DestinationParent)
        try {
            $RawFolder = Join-Path -Path $DestinationParent -ChildPath "RAW"
            if (-not (Test-Path $RawFolder)) {
                New-Item -ItemType Directory -Path $RawFolder -Force | Out-Null
                Write-Log "Created RAW folder: $RawFolder" -Type "Info"
            }

            $ArchiveFiles = @(Get-ChildItem -Path $SourcePath -File -ErrorAction SilentlyContinue |
                             Where-Object { $_.Name -like "$BaseName*" })

            if ($ArchiveFiles.Count -eq 0) {
                Write-Log "No archive files found to move: $BaseName" -Type "Warning"
                return
            }

            Write-Log "Moving $($ArchiveFiles.Count) archive files to RAW folder..." -Type "Info"
            foreach ($File in $ArchiveFiles) {
                try {
                    if (Wait-FileStability -FilePath $File.FullName) {
                        $DestPath = Join-Path -Path $RawFolder -ChildPath $File.Name
                        Move-Item -Path $File.FullName -Destination $DestPath -Force -ErrorAction Stop
                        Write-Log "Moved to RAW: $($File.Name)" -Type "Success"
                    } else {
                        Write-Log "File still in use, cannot move: $($File.Name)" -Type "Warning"
                    }
                } catch {
                    Write-Log "Failed to move $($File.Name): $_" -Type "Error"
                    Write-ErrorDetailsLog "Move-ArchiveFiles" $BaseName "Move Failed" $_
                    $script:ErrorCount++
                }
            }
        } catch {
            Write-Log "Exception in Move-ArchiveFiles: $_" -Type "Error"
            Write-ErrorDetailsLog "Move-ArchiveFiles" $BaseName "Exception" $_
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

    Write-Log "=== Yoda The Unzipper engine started ===" -Type "Info"

    if ($EnableStarWarsTheme -and $EnableThemeBeeps) {
        try {
            $Notes = @(
                @{F = 440; D = 500}, @{F = 440; D = 500}, @{F = 440; D = 500}, @{F = 349; D = 350},
                @{F = 523; D = 150}, @{F = 440; D = 500}, @{F = 349; D = 350}, @{F = 523; D = 150}
            )
            foreach ($Note in $Notes) { [Console]::Beep($Note.F, $Note.D) }
        } catch { }
    }

    if ($EnableYodaArt) {
        Write-Log $YodaArt -Type "Info"
    }

    Write-Log "May the Force be with you..." -Type "Info"
    Write-Log "Base: $BasePath | Inbound: $InboundPath | Extracted: $ExtractedPath" -Type "Info"
    Write-Log "Check interval: $CheckIntervalSeconds s | Self-heal after $EmptyCyclesBeforeRestart empty cycles" -Type "Info"

    foreach ($Dir in @($InboundPath, $ExtractedPath, $LogFolder)) {
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

                    Write-Log "Processing: $BaseName ($($PartFiles.Count) parts found)" -Type "Info"

                    $ExpectedCount = Get-ExpectedPartCount -FilePath $FirstPart.FullName
                    if ($null -eq $ExpectedCount) {
                        $ExpectedCount = 1
                        Write-Log "Single-part archive detected: $BaseName" -Type "Info"
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

                    $ArchiveExtractPath = Join-Path -Path $ExtractedPath -ChildPath $BaseName
                    if (-not (Test-Path $ArchiveExtractPath)) { New-Item -ItemType Directory -Path $ArchiveExtractPath -Force | Out-Null }

                    Write-Log "Starting extraction process..." -Type "Info"
                    $ExtractionResult = Extract-Archive -FirstPartPath $FirstPart.FullName -DestinationPath $ArchiveExtractPath

                    if ($ExtractionResult) {
                        Write-Log "Extraction successful. Moving archive files to RAW folder..." -Type "Success"
                        Move-ArchiveFiles -BaseName $BaseName -SourcePath $InboundPath -DestinationParent $ArchiveExtractPath
                        $ProcessedArchives[$BaseName] = "completed"
                        $ProcessedThisCycle++
                        if ($EnableThemeBeeps) { try { [Console]::Beep(600, 200); [Console]::Beep(600, 200) } catch { } }
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

    Write-Log "=== Yoda The Unzipper engine stopped ===" -Type "Warning"
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

    function Get-StagerFileSize {
        param([string]$FilePath)
        try { return (Get-Item -Path $FilePath -ErrorAction Stop).Length } catch { return -1 }
    }

    # Before moving a file, confirm the write has actually finished: the file
    # must be unlocked and its size must not change across a full
    # confirmation window (fixed at 10 seconds), not just at a single instant.
    function Wait-StagerFileSettled {
        param([string]$FilePath, [int]$ConfirmSeconds = 10)

        if (-not (Test-StagerFileStability -FilePath $FilePath)) { return $false }
        $sizeBefore = Get-StagerFileSize -FilePath $FilePath

        for ($i = 0; $i -lt $ConfirmSeconds; $i++) {
            if ($Sync.StopRequested) { return $false }
            Start-Sleep -Seconds 1
        }

        if (-not (Test-Path $FilePath)) { return $false }
        if (-not (Test-StagerFileStability -FilePath $FilePath)) { return $false }
        $sizeAfter = Get-StagerFileSize -FilePath $FilePath

        return ($sizeAfter -ge 0 -and $sizeAfter -eq $sizeBefore)
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
            $Candidates = @(Get-ChildItem -Path $PreStagePath -File -ErrorAction SilentlyContinue |
                            Where-Object { Test-QualifiesForStaging $_ })

            foreach ($File in $Candidates) {
                if ($Sync.StopRequested) { break }
                try {
                    if (-not (Wait-StagerFileSettled -FilePath $File.FullName -ConfirmSeconds 10)) {
                        Write-StagerLog "Write not yet confirmed complete, will recheck: $($File.Name)" -Type "Info"
                        continue
                    }

                    $Destination = Join-Path -Path $InboundPath -ChildPath $File.Name
                    if (Test-Path $Destination) {
                        Write-StagerLog "Skipping $($File.Name) - a file with that name already exists in Inbound" -Type "Warning"
                        continue
                    }

                    Move-Item -Path $File.FullName -Destination $Destination -ErrorAction Stop
                    $Sync.Staged++
                    Write-StagerLog "Staged into inbound: $($File.Name)" -Type "Success"
                } catch {
                    Write-StagerLog "Failed to stage $($File.Name): $_" -Type "Error"
                }
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
$Form.Text = "Yoda The Unzipper"
$Form.Size = New-Object System.Drawing.Size(950, 800)
$Form.MinimumSize = New-Object System.Drawing.Size(860, 700)
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
$grpPaths.Size = New-Object System.Drawing.Size(900, 165)
$grpPaths.ForeColor = [System.Drawing.Color]::White

$lblBase = New-FormLabel "Base path:" 15 28 90
$txtBase = New-FormTextBox 110 25 580 $Config.BasePath
$btnBrowseBase = New-FormButton "Browse..." 700 24 90

$lblPreStage = New-FormLabel "Pre-stage:" 15 60 90
$txtPreStage = New-FormTextBox 110 57 580 $Config.PreStagePath
$btnBrowsePreStage = New-FormButton "Browse..." 700 56 90

$lblInbound = New-FormLabel "Inbound:" 15 92 90
$txtInbound = New-FormTextBox 110 89 580 $Config.InboundPath
$btnBrowseInbound = New-FormButton "Browse..." 700 88 90

$lblExtracted = New-FormLabel "Extracted:" 15 124 90
$txtExtracted = New-FormTextBox 110 121 580 $Config.ExtractedPath
$btnBrowseExtracted = New-FormButton "Browse..." 700 120 90

$toolTip = New-Object System.Windows.Forms.ToolTip
$toolTip.SetToolTip($txtPreStage, "Optional. Files dropped here by another process (downloader, FTP, etc.) are moved into Inbound once they are fully written. Leave blank to disable.")
$toolTip.SetToolTip($lblPreStage, "Optional. Files dropped here by another process (downloader, FTP, etc.) are moved into Inbound once they are fully written. Leave blank to disable.")

$grpPaths.Controls.AddRange(@(
    $lblBase, $txtBase, $btnBrowseBase,
    $lblPreStage, $txtPreStage, $btnBrowsePreStage,
    $lblInbound, $txtInbound, $btnBrowseInbound,
    $lblExtracted, $txtExtracted, $btnBrowseExtracted
))

# --- Engine settings group ---
$grpEngine = New-Object System.Windows.Forms.GroupBox
$grpEngine.Text = "Engine Settings"
$grpEngine.Location = New-Object System.Drawing.Point(15, 190)
$grpEngine.Size = New-Object System.Drawing.Size(900, 140)
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

$grpEngine.Controls.AddRange(@(
    $lbl7z, $txt7z, $btnBrowse7z,
    $lblInterval, $numInterval, $lblEmptyCycles, $numEmptyCycles, $lblStagerInterval, $numStagerInterval,
    $chkTheme, $chkArt, $chkQuotes, $chkBeeps, $chkGreenText
))

# --- Action buttons ---
$btnStart = New-FormButton "Start" 15 340 110 32
$btnStart.BackColor = [System.Drawing.Color]::FromArgb(40, 90, 40)
$btnStart.ForeColor = [System.Drawing.Color]::White

$btnStop = New-FormButton "Stop" 135 340 110 32
$btnStop.BackColor = [System.Drawing.Color]::FromArgb(90, 40, 40)
$btnStop.ForeColor = [System.Drawing.Color]::White
$btnStop.Enabled = $false

$btnOpenPreStage = New-FormButton "Open Pre-Stage" 265 342 130 28
$btnOpenInbound = New-FormButton "Open Inbound" 405 342 120 28
$btnOpenExtracted = New-FormButton "Open Extracted" 535 342 120 28
$btnOpenLogs = New-FormButton "Open Logs" 665 342 100 28
$btnClearLog = New-FormButton "Clear Log" 775 342 120 28

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

# --- Log view ---
$rtbLog = New-Object System.Windows.Forms.RichTextBox
$rtbLog.Location = New-Object System.Drawing.Point(15, 380)
$rtbLog.Size = New-Object System.Drawing.Size(900, 300)
$rtbLog.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Bottom -bor [System.Windows.Forms.AnchorStyles]::Left -bor [System.Windows.Forms.AnchorStyles]::Right
$rtbLog.ReadOnly = $true
$rtbLog.BackColor = [System.Drawing.Color]::Black
$rtbLog.ForeColor = [System.Drawing.Color]::Cyan
$rtbLog.Font = New-Object System.Drawing.Font("Consolas", 9)
$rtbLog.WordWrap = $true

$Form.Controls.AddRange(@(
    $grpPaths, $grpEngine,
    $btnStart, $btnStop, $btnOpenPreStage, $btnOpenInbound, $btnOpenExtracted, $btnOpenLogs, $btnClearLog,
    $rtbLog, $statusStrip
))

# ------------------------------------------------------------------------
# Behavior
# ------------------------------------------------------------------------

function Save-CurrentConfig {
    $cfg = [PSCustomObject]@{
        BasePath                  = $txtBase.Text
        PreStagePath              = $txtPreStage.Text
        InboundPath               = $txtInbound.Text
        ExtractedPath             = $txtExtracted.Text
        SevenZipPath              = $txt7z.Text
        CheckIntervalSeconds      = [int]$numInterval.Value
        EmptyCyclesBeforeRestart  = [int]$numEmptyCycles.Value
        StagerScanIntervalSeconds = [int]$numStagerInterval.Value
        EnableStarWarsTheme       = $chkTheme.Checked
        EnableYodaArt             = $chkArt.Checked
        EnableYodaQuotes          = $chkQuotes.Checked
        EnableThemeBeeps          = $chkBeeps.Checked
        EnableGreenText           = $chkGreenText.Checked
    }
    Export-GuiConfig -Config $cfg
}

function Set-InputsEnabled {
    param([bool]$Enabled)
    foreach ($ctrl in @($txtBase, $txtPreStage, $txtInbound, $txtExtracted, $txt7z, $numInterval, $numEmptyCycles, $numStagerInterval,
                        $chkTheme, $chkArt, $chkQuotes, $chkBeeps, $chkGreenText,
                        $btnBrowseBase, $btnBrowsePreStage, $btnBrowseInbound, $btnBrowseExtracted, $btnBrowse7z)) {
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

$btnBrowse7z.Add_Click({
    $dlg = New-Object System.Windows.Forms.OpenFileDialog
    $dlg.Filter = "7z.exe|7z.exe|Executable files (*.exe)|*.exe|All files (*.*)|*.*"
    if (Test-PathSafe $txt7z.Text) { $dlg.InitialDirectory = Split-Path $txt7z.Text -Parent }
    if ($dlg.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) { $txt7z.Text = $dlg.FileName }
})

$btnOpenPreStage.Add_Click({
    if ([string]::IsNullOrWhiteSpace($txtPreStage.Text)) {
        [System.Windows.Forms.MessageBox]::Show("No pre-stage folder is configured.", "Yoda The Unzipper") | Out-Null
    } elseif (Test-PathSafe $txtPreStage.Text) {
        Start-Process explorer.exe $txtPreStage.Text
    } else {
        [System.Windows.Forms.MessageBox]::Show("Pre-stage folder does not exist yet.", "Yoda The Unzipper") | Out-Null
    }
})

$btnOpenInbound.Add_Click({
    if (Test-PathSafe $txtInbound.Text) { Start-Process explorer.exe $txtInbound.Text }
    else { [System.Windows.Forms.MessageBox]::Show("Inbound folder does not exist yet.", "Yoda The Unzipper") | Out-Null }
})

$btnOpenExtracted.Add_Click({
    if (Test-PathSafe $txtExtracted.Text) { Start-Process explorer.exe $txtExtracted.Text }
    else { [System.Windows.Forms.MessageBox]::Show("Extracted folder does not exist yet.", "Yoda The Unzipper") | Out-Null }
})

$btnOpenLogs.Add_Click({
    if ([string]::IsNullOrWhiteSpace($txtBase.Text)) {
        [System.Windows.Forms.MessageBox]::Show("Set a Base path first.", "Yoda The Unzipper") | Out-Null
        return
    }
    $logsPath = Join-Path -Path $txtBase.Text -ChildPath "logs"
    if (Test-PathSafe $logsPath) { Start-Process explorer.exe $logsPath }
    else { [System.Windows.Forms.MessageBox]::Show("Logs folder does not exist yet.", "Yoda The Unzipper") | Out-Null }
})

$btnClearLog.Add_Click({ $rtbLog.Clear() })

$btnStart.Add_Click({
    if ($null -ne $script:EnginePS) { return }

    $basePath = $txtBase.Text.Trim()
    $preStagePath = $txtPreStage.Text.Trim()
    $inboundPath = $txtInbound.Text.Trim()
    $extractedPath = $txtExtracted.Text.Trim()
    $sevenZip = $txt7z.Text.Trim()

    if ([string]::IsNullOrWhiteSpace($basePath) -or [string]::IsNullOrWhiteSpace($inboundPath) -or
        [string]::IsNullOrWhiteSpace($extractedPath) -or [string]::IsNullOrWhiteSpace($sevenZip)) {
        [System.Windows.Forms.MessageBox]::Show("Please fill in Base, Inbound, Extracted and 7-Zip paths.", "Yoda The Unzipper") | Out-Null
        return
    }
    if (-not (Test-PathSafe $sevenZip)) {
        [System.Windows.Forms.MessageBox]::Show("7-Zip executable not found at:`n$sevenZip", "Yoda The Unzipper") | Out-Null
        return
    }
    if (-not [string]::IsNullOrWhiteSpace($preStagePath) -and
        ($preStagePath.TrimEnd('\', '/') -ieq $inboundPath.TrimEnd('\', '/'))) {
        [System.Windows.Forms.MessageBox]::Show("Pre-stage and Inbound must be different folders.", "Yoda The Unzipper") | Out-Null
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
        SevenZipPath              = $sevenZip
        CheckIntervalSeconds      = [int]$numInterval.Value
        EmptyCyclesBeforeRestart  = [int]$numEmptyCycles.Value
        EnableStarWarsTheme       = $chkTheme.Checked
        EnableYodaArt             = $chkArt.Checked
        EnableYodaQuotes          = $chkQuotes.Checked
        EnableThemeBeeps          = $chkBeeps.Checked
        EnableGreenText           = $chkGreenText.Checked
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
    Save-CurrentConfig
})

[void]$Form.ShowDialog()
