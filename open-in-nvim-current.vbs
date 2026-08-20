' open-in-nvim-current.vbs
' Hidden bridge: Explorer -> PowerShell (no window).

Dim sh, args, i, a, cmd
Set sh = CreateObject("WScript.Shell")
args = ""
For i = 0 To WScript.Arguments.Count - 1
  a = WScript.Arguments(i)
  If InStr(a, " ") > 0 Then a = """" & a & """"
  args = args & " " & a
Next

cmd = "C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe -NoProfile -ExecutionPolicy Bypass -File ""C:\tools\OpenInNvim\open-in-nvim-current.ps1""" & args
sh.Run cmd, 0, False
