# NetHop Manager

A small Windows PowerShell GUI for safe network diagnostics and default restoration.

## Features

- Change the hop limit to '65' (meant for bypass HOTSPOT)
- Shows IPv4 and IPv6 global network settings.
- Shows IP interface information.
- Shows whether IPv6 is enabled on network adapters.
- Restores IPv4 default hop limit to the Windows default value of `128`.
- Restores IPv6 default hop limit to the Windows default value of `128`.
- Saves a timestamped diagnostics report under `reports/`.

The tool intentionally does not include controls for carrier policy evasion or hotspot-limit bypassing.

## Run

Double-click:

```bat
Run-NetworkSettingsTool.bat
```

Or run from PowerShell:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\NetworkSettingsTool.ps1
```

Read-only checks can run without administrator rights. Restore actions request UAC elevation when needed.
