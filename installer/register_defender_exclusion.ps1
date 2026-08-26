# ----------------------------------------------------------------------
# AppFit Order Agent -- Windows Defender exclusion registration helper.
#
# Brand-agnostic on purpose: every path arrives as an argument, so the common
# and mammoth installers share this one script with different arguments.
#
# Invoked by the Inno Setup installer through ShellExec with the "runas"
# verb. The installer itself is a per-user install (PrivilegesRequired=
# lowest) and therefore holds no admin rights, but Add-MpPreference does
# require them, so the registration is pushed into this elevated child.
#
# IMPORTANT: the paths are passed in as arguments ON PURPOSE. Do NOT
# re-resolve them from $env:LOCALAPPDATA inside this script. When the UAC
# prompt is satisfied with a DIFFERENT administrator account, that variable
# points at the administrator's profile and the exclusion would land on the
# wrong user while the operator account stays uncovered.
#
# Never exits non-zero: a missing exclusion must not fail the install. The
# outcome is recorded in the log file instead.
#
# Log keys are shared with kokonut_order_agent_v2 (same operational docs).
# Keep them stable:
#   addError        why Add-MpPreference was refused, if it was
#   winDefend       Defender service state. Error 0x800106ba plus every
#                   other field blank means the service is not running at
#                   all, so no Defender cmdlet can work.
#   av              every AV product registered with Security Center. If a
#                   third-party product owns scanning, this whole script is
#                   a no-op and the exclusion has to be set in that product.
#   runningMode     Passive / EDR Block means the same thing.
#   tamperProtected Tamper Protection can block exclusion changes.
#   exclusions      the effective list after the attempt.
# ----------------------------------------------------------------------

param(
    [Parameter(Mandatory = $true)][string] $AppDir,
    [Parameter(Mandatory = $true)][string] $StagingDir,
    [Parameter(Mandatory = $true)][string] $LogPath
)

# Two paths are covered:
#   $AppDir      the installed exe. The 2026-08 Bearfoos.A!ml incident
#                quarantined exactly this file.
#   $StagingDir  OTA working folder: downloaded zip, the extracted new exe,
#                the updater bat/vbs and its log. See UpdateConfig
#                .stagingDir() in lib/config/update_config.dart.
# Registering only the install folder would stop "the installed exe gets
# quarantined later" but not "the update gets blocked halfway".
Add-MpPreference -ExclusionPath $AppDir, $StagingDir `
    -ErrorAction SilentlyContinue -ErrorVariable addErr

$status  = Get-MpComputerStatus -ErrorAction SilentlyContinue
$service = Get-Service WinDefend -ErrorAction SilentlyContinue
$av      = (Get-CimInstance -Namespace root\SecurityCenter2 `
                -ClassName AntiVirusProduct -ErrorAction SilentlyContinue).displayName
$effective = (Get-MpPreference -ErrorAction SilentlyContinue).ExclusionPath

$lines = @(
    'time='            + (Get-Date -Format s),
    'user='            + $env:USERNAME,
    'appDir='          + $AppDir,
    'stagingDir='      + $StagingDir,
    'addError='        + ($addErr -join ' | '),
    'winDefend='       + $service.Status,
    'av='              + ($av -join ' ; '),
    'runningMode='     + $status.AMRunningMode,
    'tamperProtected=' + $status.IsTamperProtected,
    'exclusions='      + ($effective -join ' ; ')
)

try {
    $lines | Out-File -FilePath $LogPath -Encoding utf8 -ErrorAction Stop
} catch {
    # The log is a diagnostic aid, not a requirement. Swallow and leave.
}

exit 0
