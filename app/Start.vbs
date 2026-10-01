Set shell = CreateObject("WScript.Shell")
Set fso = CreateObject("Scripting.FileSystemObject")
folder = fso.GetParentFolderName(WScript.ScriptFullName)
shell.Run "powershell.exe -NoProfile -ExecutionPolicy Bypass -STA -WindowStyle Hidden -File """ & folder & "\Launch.ps1""", 0, False
