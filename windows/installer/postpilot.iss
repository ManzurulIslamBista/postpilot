; Inno Setup Script for PostPilot
; Compiles a standalone Windows installer (.exe) for PostPilot

#define MyAppName "PostPilot"
#define MyAppPublisher "PostPilot"
#define MyAppExeName "postpilot.exe"
#ifndef MyAppVersion
#define MyAppVersion "1.0.0"
#endif

[Setup]
AppId={{8B190AE6-9937-4AE4-8D4C-97816FA7194A}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
DefaultDirName={autopf}\{#MyAppName}
ArchitecturesInstallIn64BitMode=x64compatible
DefaultGroupName={#MyAppName}
DisableProgramGroupPage=yes
OutputDir=..\..\dist-windows
OutputBaseFilename=PostPilot_Windows_Installer
SetupIconFile=..\runner\resources\app_icon.ico
Compression=lzma2/ultra64
SolidCompression=yes
WizardStyle=modern
UninstallDisplayIcon={app}\{#MyAppExeName}

; Tells Explorer the app's icon may have changed: Setup then refreshes the shell icon cache,
; so an update does not leave the previous icon on the taskbar, desktop or Start menu.
ChangesAssociations=yes

; Set privileges to lowest so the installer does not trigger the scary UAC Administrator elevation warning!
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=dialog

; Detailed file and version metadata for Microsoft Defender inspection
VersionInfoVersion={#MyAppVersion}
VersionInfoCompany={#MyAppPublisher}
VersionInfoDescription=PostPilot Desktop Application
VersionInfoProductName={#MyAppName}
VersionInfoProductVersion={#MyAppVersion}
VersionInfoCopyright=Copyright (C) 2026 {#MyAppPublisher}

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Files]
Source: "..\..\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"
Name: "{group}\{cm:UninstallProgram,{#MyAppName}}"; Filename: "{uninstallexe}"
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#MyAppExeName}"; Description: "{cm:LaunchProgram,{#StringChange(MyAppName, '&', '&&')}}"; Flags: nowait postinstall skipifsilent
