#ifndef Payload
  #error Payload is required
#endif
#ifndef Arch
  #error Arch is required
#endif
#ifndef Output
  #error Output is required
#endif
[Setup]
AppId=SaySpan.Windows.Preview.{#Arch}
AppName={#Brand} (Preview)
AppVersion=0.2.1
AppVerName={#Brand} Windows Preview 0.2.1
AppPublisher=SaySpan contributors
AppPublisherURL=https://github.com/Ethan-Infcos/SaySpan
DefaultDirName={autopf}\SaySpan Preview
DefaultGroupName=SaySpan Preview
DisableProgramGroupPage=yes
PrivilegesRequired=admin
#if Arch == "ARM64"
ArchitecturesAllowed=arm64
ArchitecturesInstallIn64BitMode=arm64
MinVersion=10.0.22000
#else
ArchitecturesAllowed=x64os
ArchitecturesInstallIn64BitMode=x64os
MinVersion=10.0.19045
#endif
DisableDirPage=yes
LicenseFile={#Payload}\LICENSE
InfoAfterFile={#Payload}\README.txt
OutputDir={#Output}
OutputBaseFilename=SaySpan-0.2.1-preview-windows-{#Arch}-setup
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
CloseApplications=no
RestartApplications=no
UninstallDisplayName={#Brand} (Preview)
UninstallDisplayIcon={app}\SaySpanTip.dll
[Files]
Source: "{#Payload}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs restartreplace uninsrestartdelete
[Icons]
Name: "{group}\{#Brand} Settings"; Filename: "{app}\companion\SaySpan.exe"; Parameters: "--settings"
Name: "{commonstartup}\{#Brand}"; Filename: "{app}\companion\SaySpan.exe"; Parameters: "--background"
Name: "{group}\SaySpan — Read me"; Filename: "{app}\README.txt"
[Run]
Filename: "{app}\companion\SaySpan.exe"; Parameters: "--settings"; Description: "Open {#Brand} Settings"; Flags: nowait postinstall skipifsilent runasoriginaluser
[Code]
procedure CurStepChanged(CurStep: TSetupStep);
var Code: Integer;
begin
  if CurStep = ssPostInstall then
  begin
    if not Exec(ExpandConstant('{app}\SaySpanRegister.exe'), '--register', '', SW_HIDE, ewWaitUntilTerminated, Code) then
      RaiseException('Could not start SaySpan input registration.');
    if Code <> 0 then
      RaiseException('SaySpan input registration failed. Please uninstall the preview and report the error.');
  end;
end;
function InitializeUninstall(): Boolean;
var Code: Integer;
begin
  Result := Exec(ExpandConstant('{app}\SaySpanRegister.exe'), '--unregister', '', SW_HIDE, ewWaitUntilTerminated, Code);
  Result := Result and (Code = 0);
  if not Result then
    MsgBox('SaySpan could not unregister. Close applications using SaySpan and try again.', mbError, MB_OK);
end;
