param(
  [switch]$Enable,
  [switch]$Disable,
  [switch]$Once,
  [switch]$Fix,
  [int]$IntervalMinutes = 30,
  [int]$MaxRunsPerWindow = 4,
  [int]$MaxMinutesPerRun = 35,
  [decimal]$MaxBudgetUsdPerRun = 0,
  [string]$StartTime = "14:00",
  [string]$EndTime = "08:00",
  [string]$Model = "sonnet"
)

$ErrorActionPreference = "Stop"

$Root = Split-Path -Parent $PSScriptRoot
$StateDir = Join-Path $Root "audit_reports"
$StatePath = Join-Path $StateDir "claude_night_worker_state.json"
$LogPath = Join-Path $StateDir "claude_night_worker.log"

New-Item -ItemType Directory -Force -Path $StateDir | Out-Null

function Write-Log {
  param([string]$Message)
  $line = "$(Get-Date -Format o) $Message"
  $line | Tee-Object -FilePath $LogPath -Append
}

function New-State {
  [ordered]@{
    enabled = $false
    cooldown_until = $null
    window_date = $null
    runs_this_window = 0
    last_run_started = $null
    last_run_finished = $null
    last_exit_code = $null
    last_status = "never_run"
    last_report = $null
  }
}

function Read-State {
  if (Test-Path $StatePath) {
    return Get-Content $StatePath -Raw | ConvertFrom-Json
  }
  return [pscustomobject](New-State)
}

function Save-State {
  param($State)
  $State | ConvertTo-Json -Depth 8 | Set-Content -Path $StatePath -Encoding utf8
}

function Convert-ToMinutes {
  param([string]$Clock)
  $parts = $Clock.Split(":")
  return ([int]$parts[0] * 60) + [int]$parts[1]
}

function Test-InWindow {
  param([datetime]$Now)
  $nowMinutes = ($Now.Hour * 60) + $Now.Minute
  $startMinutes = Convert-ToMinutes $StartTime
  $endMinutes = Convert-ToMinutes $EndTime

  if ($startMinutes -lt $endMinutes) {
    return ($nowMinutes -ge $startMinutes -and $nowMinutes -lt $endMinutes)
  }

  return ($nowMinutes -ge $startMinutes -or $nowMinutes -lt $endMinutes)
}

function Get-WindowDate {
  param([datetime]$Now)
  $endMinutes = Convert-ToMinutes $EndTime
  $nowMinutes = ($Now.Hour * 60) + $Now.Minute

  if ($nowMinutes -lt $endMinutes) {
    return $Now.AddDays(-1).ToString("yyyy-MM-dd")
  }

  return $Now.ToString("yyyy-MM-dd")
}

function Get-NextWindowStart {
  param([datetime]$Now)
  $parts = $StartTime.Split(":")
  $candidate = Get-Date -Year $Now.Year -Month $Now.Month -Day $Now.Day -Hour ([int]$parts[0]) -Minute ([int]$parts[1]) -Second 0

  if ($candidate -le $Now) {
    $candidate = $candidate.AddDays(1)
  }

  return $candidate
}

function Test-UsageDepleted {
  param([string]$Text)
  $patterns = @(
    "usage limit",
    "rate limit",
    "too many requests",
    "quota",
    "exceeded",
    "try again",
    "limit reached",
    "overloaded"
  )

  foreach ($pattern in $patterns) {
    if ($Text -match $pattern) {
      return $true
    }
  }

  return $false
}

function Get-UsageSummary {
  param([string]$Text)

  $usageLines = @()
  foreach ($line in ($Text -split "`r?`n")) {
    if ($line -match '"usage"' -or $line -match '"cost"' -or $line -match '"total_cost"' -or $line -match '"usage_limit"') {
      $usageLines += $line
    }
  }

  if ($usageLines.Count -eq 0) {
    return "No structured usage fields observed in Claude output."
  }

  return ($usageLines | Select-Object -Last 20) -join "`n"
}

function New-ClaudePrompt {
  param([bool]$CanFix)

  $mode = if ($CanFix) { "You may make a small code change on a new branch if the issue is clear and testable." } else { "Do not edit files. Produce an audit report only." }

  return @"
You are running as Xene's bounded overnight maintenance worker.

Goal:
- Spend this run on exactly one useful improvement area.
- Prefer security, auth, proxy safety, dependency health, failing tests, or missing tests.
- Keep the work small enough to review.

Rules:
- $mode
- Do not merge, push, deploy, delete data, rotate secrets, or modify production configuration.
- If editing is allowed, create a branch named codex/claude-night-worker-YYYYMMDD-HHMM before editing.
- Start by checking git status and do not overwrite unrelated user changes.
- Run the most relevant verification command before stopping.
- Write a short report to audit_reports/claude_run_YYYYMMDD_HHMM.md with findings, changes, tests, risks, and next recommended action.
- If blocked by missing credentials or usage limits, write that plainly and stop.

Suggested first targets:
- packages/xene_backend/routes/auth/soundcloud/*
- packages/xene_backend/routes/proxy/image.dart
- packages/xene_backend/routes/soundcloud/stream/[id].dart
- packages/xene_backend/routes/bug_report.dart
- packages/xene_backend/routes/admin/poll.dart
- packages/xene_backend/lib/src/utils/auth_utils.dart
- packages/xene_backend/lib/src/utils/rate_limiter.dart
- packages/xene_backend/lib/src/services/token_store.dart
- packages/xene_app/lib/src/providers/dio_provider.dart
- packages/xene_dashboard/app/auth/*
- packages/xene_dashboard/proxy.ts
"@
}

function Invoke-ClaudeRun {
  param([bool]$CanFix)

  $timestamp = Get-Date -Format "yyyy-MM-dd_HH-mm-ss"
  $outPath = Join-Path $StateDir "claude_worker_output_$timestamp.txt"
  $debugPath = Join-Path $StateDir "claude_worker_debug_$timestamp.log"
  $prompt = New-ClaudePrompt -CanFix $CanFix

  $permissionMode = if ($CanFix) { "default" } else { "plan" }
  $allowedTools = if ($CanFix) {
    "Read,Grep,Glob,Bash,Edit,Write"
  } else {
    "Read,Grep,Glob,Bash"
  }

  Write-Log "Starting Claude run. fix=$CanFix output=$outPath debug=$debugPath maxBudgetUsd=$MaxBudgetUsdPerRun"

  $job = Start-Job -ScriptBlock {
    param($Root, $Model, $PermissionMode, $AllowedTools, $Prompt, $DebugPath, $MaxBudgetUsdPerRun)
    Set-Location $Root
    $args = @(
      "-p",
      "--model", $Model,
      "--permission-mode", $PermissionMode,
      "--allowedTools", $AllowedTools,
      "--output-format", "stream-json",
      "--include-partial-messages",
      "--debug-file", $DebugPath
    )

    if ($MaxBudgetUsdPerRun -gt 0) {
      $args += @("--max-budget-usd", $MaxBudgetUsdPerRun.ToString([System.Globalization.CultureInfo]::InvariantCulture))
    }

    $args += $Prompt
    claude @args
    <#
    Equivalent shape:
    claude -p `
      --model $Model `
      --permission-mode $PermissionMode `
      --allowedTools $AllowedTools `
      --output-format stream-json `
      --include-partial-messages `
      --debug-file $DebugPath `
      $Prompt
    #>
  } -ArgumentList $Root, $Model, $permissionMode, $allowedTools, $prompt, $debugPath, $MaxBudgetUsdPerRun

  $completed = Wait-Job $job -Timeout ($MaxMinutesPerRun * 60)
  if ($null -eq $completed) {
    Stop-Job $job
    Receive-Job $job 2>&1 | Set-Content -Path $outPath -Encoding utf8
    Remove-Job $job -Force
    return [pscustomobject]@{
      exit_code = 124
      status = "timed_out"
      output_path = $outPath
      usage_depleted = $false
    }
  }

  $output = Receive-Job $job 2>&1 | Out-String
  Remove-Job $job -Force
  $output | Set-Content -Path $outPath -Encoding utf8

  $usageDepleted = Test-UsageDepleted $output.ToLowerInvariant()
  $status = if ($usageDepleted) { "usage_depleted" } else { "completed" }
  $usageSummary = Get-UsageSummary $output

  return [pscustomobject]@{
    exit_code = 0
    status = $status
    output_path = $outPath
    debug_path = $debugPath
    usage_summary = $usageSummary
    usage_depleted = $usageDepleted
  }
}

$state = Read-State

if ($Enable) {
  $state.enabled = $true
  Save-State $state
  Write-Log "Worker enabled."
}

if ($Disable) {
  $state.enabled = $false
  Save-State $state
  Write-Log "Worker disabled."
  exit 0
}

do {
  $state = Read-State
  $now = Get-Date

  if (-not $state.enabled) {
    Write-Log "Worker is disabled. Use -Enable to turn it on."
    if ($Once) { break }
    Start-Sleep -Seconds ($IntervalMinutes * 60)
    continue
  }

  if (-not (Test-InWindow $now)) {
    $next = Get-NextWindowStart $now
    Write-Log "Outside active window. Next start: $($next.ToString("o"))"
    if ($Once) { break }
    Start-Sleep -Seconds ([Math]::Min($IntervalMinutes * 60, 3600))
    continue
  }

  $windowDate = Get-WindowDate $now
  if ($state.window_date -ne $windowDate) {
    $state.window_date = $windowDate
    $state.runs_this_window = 0
    $state.cooldown_until = $null
    Save-State $state
    Write-Log "New active window: $windowDate"
  }

  if ($state.cooldown_until) {
    $cooldownUntil = [datetime]$state.cooldown_until
    if ($cooldownUntil -gt $now) {
      Write-Log "Cooling down until $($cooldownUntil.ToString("o"))"
      if ($Once) { break }
      Start-Sleep -Seconds ($IntervalMinutes * 60)
      continue
    }
    $state.cooldown_until = $null
  }

  if ($state.runs_this_window -ge $MaxRunsPerWindow) {
    Write-Log "Run cap reached for window: $($state.runs_this_window)/$MaxRunsPerWindow"
    if ($Once) { break }
    Start-Sleep -Seconds ($IntervalMinutes * 60)
    continue
  }

  $state.last_run_started = $now.ToString("o")
  $state.runs_this_window = [int]$state.runs_this_window + 1
  Save-State $state

  $result = Invoke-ClaudeRun -CanFix ([bool]$Fix)

  $state = Read-State
  $state.last_run_finished = (Get-Date).ToString("o")
  $state.last_exit_code = $result.exit_code
  $state.last_status = $result.status
  $state.last_report = $result.output_path
  $state.last_debug = $result.debug_path
  $state.last_usage_summary = $result.usage_summary

  if ($result.usage_depleted) {
    $state.cooldown_until = (Get-NextWindowStart (Get-Date)).ToString("o")
    Write-Log "Claude appears usage/rate limited. Cooling down until next window."
  } elseif ($result.status -eq "timed_out") {
    $state.cooldown_until = (Get-Date).AddMinutes($IntervalMinutes).ToString("o")
    Write-Log "Claude run timed out. Cooling down for $IntervalMinutes minutes."
  } else {
    Write-Log "Claude run finished: $($result.status)"
  }

  Save-State $state

  if ($Once) { break }
  Start-Sleep -Seconds ($IntervalMinutes * 60)
} while ($true)
