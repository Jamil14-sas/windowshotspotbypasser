param(
    [switch]$ChangeLimit,
    [switch]$RestoreIPv4,
    [switch]$RestoreIPv6
)

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$ErrorActionPreference = "Stop"
$script:AppName = "NetHop Manager"
$script:AppIconPath = Join-Path $PSScriptRoot "assets\globe.ico"
$script:DefaultHopLimit = 128
$script:LimitChange = 65

function Test-IsAdmin {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Invoke-Netsh {
    param([Parameter(Mandatory)][string[]]$Arguments)

    $output = & netsh @Arguments 2>&1
    return ($output | Out-String).Trim()
}

function Restore-IPv4Default {
    Invoke-Netsh -Arguments @("int", "ipv4", "set", "global", "defaultcurhoplimit=$script:DefaultHopLimit")
}

function Restore-IPv6Default {
    Invoke-Netsh -Arguments @("int", "ipv6", "set", "global", "defaultcurhoplimit=$script:DefaultHopLimit")
}

function Start-ElevatedAction {
    param([Parameter(Mandatory)][string]$Action)

    $scriptPath = $PSCommandPath
    $args = "-NoProfile -ExecutionPolicy Bypass -File `"$scriptPath`" -$Action"
    Start-Process -FilePath "powershell.exe" -ArgumentList $args -Verb RunAs -Wait
}

function Change-Limit {
    Invoke-Netsh -Arguments @("int", "ipv4", "set", "global", "defaultcurhoplimit=$script:LimitChange")
	Invoke-Netsh -Arguments @("int", "ipv6", "set", "global", "defaultcurhoplimit=$script:LimitChange")
}

function Get-CommandText {
    param([Parameter(Mandatory)][scriptblock]$ScriptBlock)

    try {
        $result = & $ScriptBlock
        return ($result | Out-String).Trim()
    }
    catch {
        return "ERROR: $($_.Exception.Message)"
    }
}

function Get-StatusText {
    $ipv4Global = Get-CommandText { netsh int ipv4 show global }
    $ipv6Global = Get-CommandText { netsh int ipv6 show global }
    $interfaces = Get-CommandText {
        Get-NetIPInterface |
            Sort-Object InterfaceAlias, AddressFamily |
            Select-Object InterfaceAlias, AddressFamily, InterfaceMetric, NlMtu, Dhcp, ConnectionState |
            Format-Table -AutoSize
    }
    $ipv6Bindings = Get-CommandText {
        Get-NetAdapterBinding -ComponentID ms_tcpip6 |
            Sort-Object Name |
            Select-Object Name, DisplayName, Enabled |
            Format-Table -AutoSize
    }

    return @"
$script:AppName
Generated: $(Get-Date -Format "yyyy-MM-dd HH:mm:ss zzz")
Running as administrator: $(Test-IsAdmin)

IPv4 Global Settings
$ipv4Global

IPv6 Global Settings
$ipv6Global

IP Interfaces
$interfaces

IPv6 Adapter Bindings
$ipv6Bindings
"@
}

function Save-DiagnosticsReport {
    param([Parameter(Mandatory)][string]$Text)

    $reportsDir = Join-Path $PSScriptRoot "reports"
    New-Item -ItemType Directory -Force -Path $reportsDir | Out-Null

    $fileName = "network-diagnostics-{0}.txt" -f (Get-Date -Format "yyyyMMdd-HHmmss")
    $path = Join-Path $reportsDir $fileName
    Set-Content -Path $path -Value $Text -Encoding UTF8
    return $path
}

if ($ChangeLimit -or $RestoreIPv4 -or $RestoreIPv6) {
    if (-not (Test-IsAdmin)) {
        Write-Error "This action requires an elevated PowerShell session."
        exit 1
    }

    if ($ChangeLimit) {
        Change-Limit | Write-Output
    }

    if ($RestoreIPv4) {
        Restore-IPv4Default | Write-Output
    }

    if ($RestoreIPv6) {
        Restore-IPv6Default | Write-Output
    }

    exit 0
}

$form = New-Object Windows.Forms.Form
$form.Text = $script:AppName
if (Test-Path -LiteralPath $script:AppIconPath) {
    $form.Icon = New-Object Drawing.Icon($script:AppIconPath)
}
$form.Size = New-Object Drawing.Size(920, 680)
$form.MinimumSize = New-Object Drawing.Size(760, 520)
$form.StartPosition = "CenterScreen"
$form.Font = New-Object Drawing.Font("Segoe UI", 10)

$header = New-Object Windows.Forms.Label
$header.Text = $script:AppName
$header.Font = New-Object Drawing.Font("Segoe UI", 16, [Drawing.FontStyle]::Bold)
$header.Location = New-Object Drawing.Point(16, 14)
$header.Size = New-Object Drawing.Size(620, 32)
$form.Controls.Add($header)

$adminLabel = New-Object Windows.Forms.Label
$adminLabel.Location = New-Object Drawing.Point(18, 52)
$adminLabel.Size = New-Object Drawing.Size(850, 26)
$adminLabel.Text = "Admin status: " + $(if (Test-IsAdmin) { "elevated" } else { "not elevated; restore actions will request UAC approval" })
$form.Controls.Add($adminLabel)

$buttonPanel = New-Object Windows.Forms.FlowLayoutPanel
$buttonPanel.Location = New-Object Drawing.Point(16, 86)
$buttonPanel.Size = New-Object Drawing.Size(870, 46)
$buttonPanel.Anchor = "Top,Left,Right"
$buttonPanel.FlowDirection = "LeftToRight"
$buttonPanel.WrapContents = $false
$form.Controls.Add($buttonPanel)

$outputBox = New-Object Windows.Forms.TextBox
$outputBox.Multiline = $true
$outputBox.ScrollBars = "Both"
$outputBox.WordWrap = $false
$outputBox.ReadOnly = $true
$outputBox.Font = New-Object Drawing.Font("Consolas", 9)
$outputBox.Location = New-Object Drawing.Point(16, 142)
$outputBox.Size = New-Object Drawing.Size(870, 480)
$outputBox.Anchor = "Top,Bottom,Left,Right"
$form.Controls.Add($outputBox)

function New-AppButton {
    param(
        [Parameter(Mandatory)][string]$Text,
        [Parameter(Mandatory)][scriptblock]$OnClick
    )

    $button = New-Object Windows.Forms.Button
    $button.Text = $Text
    $button.AutoSize = $true
    $button.Height = 34
    $button.Margin = New-Object Windows.Forms.Padding(0, 0, 10, 0)
    $button.Add_Click($OnClick)
    $buttonPanel.Controls.Add($button)
}

New-AppButton -Text "Refresh Status" -OnClick {
    $outputBox.Text = "Refreshing network status..."
    $outputBox.Text = Get-StatusText
}

New-AppButton -Text "Change Limit" -OnClick {
    try {
        if (Test-IsAdmin) {
            ChangeLimit | Out-Null
        }
        else {
            Start-ElevatedAction -Action "ChangeLimit"
        }

        [Windows.Forms.MessageBox]::Show("IPv4 and IPv6 default hop limits changed $script:LimitChange.", $script:AppName, "OK", "Information") | Out-Null
        $outputBox.Text = Get-StatusText
    }
    catch {
        [Windows.Forms.MessageBox]::Show($_.Exception.Message, $script:AppName, "OK", "Error") | Out-Null
    }
}

New-AppButton -Text "Restore IPv4 Default" -OnClick {
    try {
        if (Test-IsAdmin) {
            Restore-IPv4Default | Out-Null
        }
        else {
            Start-ElevatedAction -Action "RestoreIPv4"
        }

        [Windows.Forms.MessageBox]::Show("IPv4 default hop limit restored to $script:DefaultHopLimit.", $script:AppName, "OK", "Information") | Out-Null
        $outputBox.Text = Get-StatusText
    }
    catch {
        [Windows.Forms.MessageBox]::Show($_.Exception.Message, $script:AppName, "OK", "Error") | Out-Null
    }
}

New-AppButton -Text "Restore IPv6 Default" -OnClick {
    try {
        if (Test-IsAdmin) {
            Restore-IPv6Default | Out-Null
        }
        else {
            Start-ElevatedAction -Action "RestoreIPv6"
        }

        [Windows.Forms.MessageBox]::Show("IPv6 default hop limit restored to $script:DefaultHopLimit.", $script:AppName, "OK", "Information") | Out-Null
        $outputBox.Text = Get-StatusText
    }
    catch {
        [Windows.Forms.MessageBox]::Show($_.Exception.Message, $script:AppName, "OK", "Error") | Out-Null
    }
}

New-AppButton -Text "Save Report" -OnClick {
    try {
        $text = Get-StatusText
        $path = Save-DiagnosticsReport -Text $text
        $outputBox.Text = $text
        [Windows.Forms.MessageBox]::Show("Report saved to:`r`n$path", $script:AppName, "OK", "Information") | Out-Null
    }
    catch {
        [Windows.Forms.MessageBox]::Show($_.Exception.Message, $script:AppName, "OK", "Error") | Out-Null
    }
}

New-AppButton -Text "Open Reports Folder" -OnClick {
    $reportsDir = Join-Path $PSScriptRoot "reports"
    New-Item -ItemType Directory -Force -Path $reportsDir | Out-Null
    Start-Process explorer.exe $reportsDir
}

$form.Add_Shown({
    $outputBox.Text = Get-StatusText
})

[void]$form.ShowDialog()
