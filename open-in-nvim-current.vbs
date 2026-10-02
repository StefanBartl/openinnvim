' open-in-nvim-current.vbs
' Hidden bridge: Explorer -> PowerShell (no window). The script is looked up next to this file,
' so the folder can be anywhere (installed copy or the repository itself).
' Save as ANSI or UTF-8 without BOM.

Dim sh, fso, here, args, i, a, cmd
Set sh = CreateObject("WScript.Shell")
Set fso = CreateObject("Scripting.FileSystemObject")
here = fso.GetParentFolderName(WScript.ScriptFullName)

args = ""
For i = 0 To WScript.Arguments.Count - 1
  a = WScript.Arguments(i)
  If InStr(a, " ") > 0 Or InStr(a, """") > 0 Then
    a = Replace(a, """", "\""")
    ' A trailing backslash would escape the closing quote.
    If Right(a, 1) = "\" Then a = a & "\"
    a = """" & a & """"
  End If
  args = args & " " & a
Next

cmd = sh.ExpandEnvironmentStrings("%SystemRoot%") & "\System32\WindowsPowerShell\v1.0\powershell.exe -NoProfile -ExecutionPolicy Bypass -File """ & here & "\open-in-nvim-current.ps1""" & args
sh.Run cmd, 0, False
