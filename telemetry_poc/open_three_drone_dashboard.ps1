param(
    [Parameter(Mandatory = $true)]
    [string]$Distro,
    [Parameter(Mandatory = $true)]
    [string]$ProjectRoot,
    [Parameter(Mandatory = $true)]
    [string]$StateRoot,
    [Parameter(Mandatory = $true)]
    [int]$LauncherPid,
    [Parameter(Mandatory = $true)]
    [string]$LauncherPidFile,
    [Parameter(Mandatory = $true)]
    [string]$PythonBin,
    [Parameter(Mandatory = $true)]
    [string]$MavproxyScript,
    [Parameter(Mandatory = $true)]
    [string]$MavproxyPaneScript,
    [Parameter(Mandatory = $true)]
    [ValidateSet('direct', 'mesh-fed')]
    [string]$GcsMode,
    [string]$WindowsHostIP = '',
    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'

function ConvertTo-BashQuoted {
    param([string]$Value)

    return "'" + $Value.Replace("'", "'\''") + "'"
}

function ConvertTo-WslPath {
    param([string]$Path)

    foreach ($prefix in @("\\wsl.localhost\$Distro\", "\\wsl$\$Distro\")) {
        if ($Path.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) {
            return '/' + $Path.Substring($prefix.Length).Replace('\', '/')
        }
    }

    return $Path
}

function New-WslCommand {
    param([string]$ShellCommand)

    return @(
        'wsl.exe',
        '-d', $Distro,
        '--cd', $ProjectRoot,
        '--exec', 'bash', '-lc', $ShellCommand
    )
}

$ProjectRoot = ConvertTo-WslPath $ProjectRoot
$StateRoot = ConvertTo-WslPath $StateRoot
$LauncherPidFile = ConvertTo-WslPath $LauncherPidFile
$PythonBin = ConvertTo-WslPath $PythonBin
$MavproxyScript = ConvertTo-WslPath $MavproxyScript
$MavproxyPaneScript = ConvertTo-WslPath $MavproxyPaneScript

$null = & wsl.exe -d $Distro --exec /bin/true
if ($LASTEXITCODE -ne 0) {
    throw "WSL distribution '$Distro' could not be started."
}

function New-MavproxyCommand {
    param(
        [int]$TcpPort,
        [int]$RouterPort
    )

    $commandArguments = @(
        (ConvertTo-BashQuoted $MavproxyPaneScript),
        (ConvertTo-BashQuoted "$LauncherPid"),
        (ConvertTo-BashQuoted $LauncherPidFile),
        (ConvertTo-BashQuoted $PythonBin),
        (ConvertTo-BashQuoted $MavproxyScript),
        (ConvertTo-BashQuoted "$TcpPort"),
        (ConvertTo-BashQuoted "$RouterPort"),
        (ConvertTo-BashQuoted $GcsMode),
        (ConvertTo-BashQuoted $WindowsHostIP)
    )

    return 'exec bash ' + ($commandArguments -join ' ')
}

function New-ReceiverLogCommand {
    param([int]$DroneNumber)

    $logPath = "$($StateRoot.TrimEnd('/'))/receiver-drone-$DroneNumber.log"
    return "exec tail --pid=$LauncherPid -F $(ConvertTo-BashQuoted $logPath)"
}

$wt = Get-Command 'wt.exe' -ErrorAction Stop
$wtArguments = @(
    '--window', 'new',
    '--maximized',
    'new-tab',
    '--title', 'Drone 1 - MAVProxy',
    '--suppressApplicationTitle'
) + (New-WslCommand (New-MavproxyCommand 5760 14610))

$wtArguments += @(
    ';', 'split-pane', '-V', '--size', '0.6667',
    '--title', 'Drone 2 - MAVProxy',
    '--suppressApplicationTitle'
) + (New-WslCommand (New-MavproxyCommand 5770 14611))

$wtArguments += @(
    ';', 'split-pane', '-V', '--size', '0.5',
    '--title', 'Drone 3 - MAVProxy',
    '--suppressApplicationTitle'
) + (New-WslCommand (New-MavproxyCommand 5780 14612))

$wtArguments += @(
    ';', 'split-pane', '-H', '--size', '0.5',
    '--title', 'Telemetry - Drone 3',
    '--suppressApplicationTitle'
) + (New-WslCommand (New-ReceiverLogCommand 3))

$wtArguments += @(
    ';', 'move-focus', 'up',
    ';', 'move-focus', 'left',
    ';', 'split-pane', '-H', '--size', '0.5',
    '--title', 'Telemetry - Drone 2',
    '--suppressApplicationTitle'
) + (New-WslCommand (New-ReceiverLogCommand 2))

$wtArguments += @(
    ';', 'move-focus', 'up',
    ';', 'move-focus', 'left',
    ';', 'split-pane', '-H', '--size', '0.5',
    '--title', 'Telemetry - Drone 1',
    '--suppressApplicationTitle'
) + (New-WslCommand (New-ReceiverLogCommand 1))

if ($DryRun) {
    $wtArguments | ForEach-Object { "[$_]" }
    exit 0
}

& $wt.Source @wtArguments
if ($LASTEXITCODE -ne 0) {
    throw "Windows Terminal exited with code $LASTEXITCODE."
}
