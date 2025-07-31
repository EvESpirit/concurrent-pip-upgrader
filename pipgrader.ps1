<#
.SYNOPSIS
    A concurrent Python environment upgrader/synchronizer that doesen't break things.
#>

$pipCommand = "pip"
$maxRepairAttempts = 5


Clear-Host
Write-Host "Concurrent pip Package Upgrader/Synchronizer" -ForegroundColor Magenta

Write-Host "`n[Step 1] Assessing environment state..." -ForegroundColor Cyan

$packagesToUpgrade = (& $pipCommand list --outdated --disable-pip-version-check) | Select-Object -Skip 2
Write-Host "Found $($packagesToUpgrade.Count) outdated package(s)."

Write-Host "Verifying environment health..."
$initialPipCheck = & $pipCommand check 2>&1
if ($?) {
    $environmentIsBroken = $false
    Write-Host "Environment is healthy."
} else {
    $environmentIsBroken = $true
    Write-Warning "Dependency conflicts exist."
}

if (($packagesToUpgrade.Count -eq 0) -and (-not $environmentIsBroken)) {
    Write-Host "`nAll packages are up-to-date and the environment is healthy. Exiting..." -ForegroundColor Green
    if ($Host.Name -eq "ConsoleHost") { Read-Host -Prompt "Press Enter to exit" }
    exit 0
}


if ($packagesToUpgrade.Count -gt 0) {
    Write-Host "`nUpgrading packages..." -ForegroundColor Yellow
    $confirmation = Read-Host -Prompt "Proceed? We have $($packagesToUpgrade.Count) to upgrade. (y/n)"
    if ($confirmation -eq 'y') {
        Write-Host "Starting..."
        $jobs = @()
        foreach ($packageLine in $packagesToUpgrade) {
            $packageName = ($packageLine -split '\s+')[0]
            if ([string]::IsNullOrWhiteSpace($packageName)) { continue }
            $jobs += Start-Job -ScriptBlock {
                param($pipCmd, $pkgName)
                & $pipCmd install --upgrade --no-deps $pkgName 2>&1 | Out-Null
            } -ArgumentList $pipCommand, $packageName
        }
        Write-Host "`nWaiting for all upgrade jobs to complete..." -ForegroundColor Yellow
        Wait-Job -Job $jobs | Out-Null
        $jobs | ForEach-Object { Remove-Job -Job $_ }
        Write-Host "Phase 1 complete. The environment will now be checked and repaired if necessary." -ForegroundColor Green
        $environmentIsBroken = $true # Assumption
    } else {
        Write-Host "Skipping..." -ForegroundColor Yellow
    }
}


if (-not $environmentIsBroken) {
    Write-Host "`nEnvironment is healthy. Skipping repairs..." -ForegroundColor Green
    if ($Host.Name -eq "ConsoleHost") { Read-Host -Prompt "Press Enter to exit" }
    exit 0
}

Write-Host "`n[Step 2] Fixing dependencies..." -ForegroundColor Yellow

for ($i = 1; $i -le $maxRepairAttempts; $i++) {
    Write-Host "`n[Repair Attempt $i of $maxRepairAttempts]" -ForegroundColor Cyan
    
    $currentPipCheckOutput = & $pipCommand check 2>&1
    if ($?) {
        Write-Host "SUCCESS: Environment is now healthy." -ForegroundColor Green
        break
    }

    Write-Warning "Conflicts found. Parsing packages to fix..."
    $packagesToFix = @{}
    $regex = "^(?<packageName>\S+)\s+[\d\.]+\s+has requirement"
    
    foreach ($line in $currentPipCheckOutput) {
        if ($line -match $regex) {
            $packageName = $matches.packageName
            Write-Host "  -> Broken package: $packageName. It will be reinstalled/upgraded."
            $packagesToFix[$packageName] = $true
        }
    }

    if ($packagesToFix.Count -eq 0) {
        Write-Host "No actionable dependency conflicts found in the output. The remaining error may be a different issue." -ForegroundColor Yellow
        Write-Host "Remaining 'pip check' output:" -ForegroundColor Yellow
        $currentPipCheckOutput
        break
    }

    Write-Host "`nRechecking $($packagesToFix.Keys.Count) package(s)..." -ForegroundColor Yellow
    
    try {
        $argumentList = @("install", "--upgrade")
        $argumentList += $packagesToFix.Keys
        & $pipCommand $argumentList
        
        if (-not $?) {
            throw "The 'pip install' command failed with a non-zero exit code."
        }
    } catch {
        Write-Error "A critical error occurred during the repair install. Your pip environment is likely broken. The script will now exit."
        exit 1
    }

    if ($i -eq $maxRepairattempts) {
        Write-Error "Maximum repair attempts reached. Please run 'pip check' manually."
        exit 1
    }
}

Write-Host "`nProcess Finished!" -ForegroundColor Magenta
if ($Host.Name -eq "ConsoleHost") { Read-Host -Prompt "Press Enter to exit" }
