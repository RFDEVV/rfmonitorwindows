#define AppName "RFMonitor"
#define AppVersion "1.1.0"
#define AppExecutable "rfmonitor.exe"

[Setup]
AppId={{CF9D12AB-15DD-4B11-8FDB-8B5BEA0E7CB2}
AppName={#AppName}
AppVersion={#AppVersion}
AppPublisher=RFMonitor
DefaultDirName={localappdata}\Programs\RFMonitor
DefaultGroupName={#AppName}
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
ArchitecturesAllowed=x64
ArchitecturesInstallIn64BitMode=x64
OutputDir=..\build
OutputBaseFilename=RFMonitor-Setup-x64
SetupIconFile=..\windows\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\{#AppExecutable}
Compression=lzma2/ultra64
SolidCompression=yes
WizardStyle=modern

[Tasks]
Name: "desktopicon"; Description: "Buat shortcut di Desktop"; GroupDescription: "Shortcut tambahan:"

[Files]
Source: "..\build\installer\payload\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autoprograms}\{#AppName}"; Filename: "{app}\{#AppExecutable}"
Name: "{autodesktop}\{#AppName}"; Filename: "{app}\{#AppExecutable}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#AppExecutable}"; Description: "Jalankan RFMonitor"; Flags: postinstall nowait skipifsilent
