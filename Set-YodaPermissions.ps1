<#
    Set-YodaPermissions.ps1

    One-time setup helper for a freshly-downloaded YODA package. Files
    downloaded from the internet (including everything inside a zip you
    extract) are tagged by Windows as coming from another computer, and
    PowerShell's default execution policy on most machines refuses to run
    an unsigned .ps1 at all - both of these block YODA.ps1 (and this
    script itself) from running until cleared, with no obviously-related
    error message pointing at either cause.

    This does two things, both scoped to the current user only (no
    administrator rights required, and nothing outside this user profile
    is changed):
      1. Removes the "downloaded from the internet" block (the Zone.Identifier
         alternate data stream) from every file in this folder, so Windows
         stops treating them as untrusted just for having been downloaded.
      2. Sets the PowerShell execution policy for the current user to
         RemoteSigned, if it is currently more restrictive than that -
         local scripts you already have on disk (like YODA.ps1, once
         unblocked above) are then allowed to run, while a script freshly
         downloaded from the internet and never unblocked still would not
         be - this is the standard, minimum-privilege setting for exactly
         this situation, not a blanket "allow everything."

    Run it once after unzipping the package, before the first
    Start_YODA.bat / YODA.ps1 launch. Safe to run again any time - both
    steps are no-ops if already applied.
#>

$ScriptDir = $PSScriptRoot
Write-Host "=== YODA Permissions Setup ===" -ForegroundColor Cyan
Write-Host "Folder: $ScriptDir`n"

Write-Host "Step 1: Unblocking files downloaded from the internet..."
$Files = Get-ChildItem -Path $ScriptDir -Recurse -File -ErrorAction SilentlyContinue
$UnblockedCount = 0
foreach ($File in $Files) {
    try {
        $Zone = Get-Item -Path $File.FullName -Stream Zone.Identifier -ErrorAction Stop
        Unblock-File -Path $File.FullName -ErrorAction Stop
        $UnblockedCount++
        Write-Host "  Unblocked: $($File.Name)" -ForegroundColor Green
    } catch {
        # No Zone.Identifier stream present - file was never blocked, nothing to do.
    }
}
if ($UnblockedCount -eq 0) {
    Write-Host "  Nothing to unblock - these files were not flagged as downloaded." -ForegroundColor DarkGray
} else {
    Write-Host "  Unblocked $UnblockedCount file(s)." -ForegroundColor Green
}

Write-Host "`nStep 2: Checking PowerShell execution policy (current user)..."
$CurrentPolicy = Get-ExecutionPolicy -Scope CurrentUser
$SufficientPolicies = @('RemoteSigned', 'Unrestricted', 'Bypass')

if ($CurrentPolicy -in $SufficientPolicies) {
    Write-Host "  Already set to '$CurrentPolicy' - no change needed." -ForegroundColor Green
} else {
    try {
        Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy RemoteSigned -Force -ErrorAction Stop
        Write-Host "  Changed from '$CurrentPolicy' to 'RemoteSigned' for the current user." -ForegroundColor Green
    } catch {
        Write-Host "  Could not change execution policy: $_" -ForegroundColor Red
        Write-Host "  YODA.ps1 will still run via Start_YODA.bat (it passes its own -ExecutionPolicy Bypass" -ForegroundColor Yellow
        Write-Host "  for that single launch), but running YODA.ps1 directly may still be blocked." -ForegroundColor Yellow
    }
}

Write-Host "`n=== Done. You can now run Start_YODA.bat or YODA.ps1 directly. ===" -ForegroundColor Cyan
