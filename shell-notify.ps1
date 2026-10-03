# shell-notify.ps1
# Dot-sourced by install.ps1, uninstall.ps1 and register-nvim-default-app.ps1.
# Windows PowerShell 5.1 compatible.

function Send-AssocChanged {
  <#
    .SYNOPSIS
      Tell Explorer that file associations / shell verbs changed (SHCNE_ASSOCCHANGED).
    .DESCRIPTION
      Explorer keeps the old commands in memory until it is told; without this a click right after the
      (un)install still runs the previous command. Failing is harmless, so it only warns.
      Does nothing for a throw-away registry key (the tests): nothing real changed, and the broadcast
      makes every Explorer window refresh its icons.
  #>
  param([switch]$Skip)
  if ($Skip) { return }
  try {
    Add-Type -Namespace OpenInNvimSetup -Name Shell -MemberDefinition '[System.Runtime.InteropServices.DllImport("shell32.dll")] public static extern void SHChangeNotify(int wEventId, uint uFlags, System.IntPtr dwItem1, System.IntPtr dwItem2);'
    [OpenInNvimSetup.Shell]::SHChangeNotify(0x08000000, 0x1000, [IntPtr]::Zero, [IntPtr]::Zero)   # SHCNE_ASSOCCHANGED, SHCNF_FLUSH
  } catch { Write-Warning "Could not notify Explorer; restart it if the menu still runs the old command." }
}
