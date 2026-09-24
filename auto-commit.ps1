$project  = Split-Path -Parent $MyInvocation.MyCommand.Path
$logFile  = Join-Path $project 'auto-commit.log'

$git = (Get-Command git -ErrorAction SilentlyContinue).Source
if (-not $git) { $git = 'C:\Program Files\Git\cmd\git.exe' }

Set-Location $project

function Write-DemoLog([string]$msg) {
    Add-Content -Path $logFile -Value ("[{0}] {1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $msg)
}

Write-DemoLog 'watcher started'

$dirtySince  = $null
$pollSec     = 60
$quietSec    = 6

while ($true) {
    try {
        $status = @(& $git status --porcelain 2>$null) | Where-Object { $_ -notmatch 'auto-commit\.(log|ps1|cmd)' -and $_ -notmatch 'warning|Replace' }
        $hasChanges = $status.Count -gt 0

        if ($hasChanges) {
            $now = Get-Date
            if ($null -eq $dirtySince) { $dirtySince = $now }
            if (($now - $dirtySince).TotalSeconds -ge $quietSec) {
                & $git add -A 2>$null | Out-Null
                & $git -c user.name="opencode-demo-bot" -c user.email="opencode-demo-bot@users.noreply.github.com" commit -m ("auto-commit {0}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')) 2>$null | Out-Null
                $pushOut = & $git push 2>&1
                Write-DemoLog ("committed and pushed: " + (($pushOut -join ' ').Trim()))
                $dirtySince = $null
            }
        } else {
            $dirtySince = $null
        }
    } catch {
        Write-DemoLog ("error: " + $_.Exception.Message)
    }
    Start-Sleep -Seconds $pollSec
}