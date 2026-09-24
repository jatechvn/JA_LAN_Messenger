; Inno Setup Script cho JA LAN Messenger
; Tự động hóa đóng gói bộ cài đặt độc lập (.exe) cho Windows 64-bit

#define MyAppName "JA LAN Messenger"
#define MyAppVersion "1.3.1"
#define MyAppPublisher "JA Tech"
#define MyAppURL "https://github.com/jatechvn/JA_LAN_Messenger"
#define MyAppExeName "ja_lan_messenger.exe"

[Setup]
; AppId định danh duy nhất ứng dụng
AppId={{C2818A9E-3D07-4C0A-9B3E-BEEBEEP6475}}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppVerName={#MyAppName} v{#MyAppVersion}
AppPublisher={#MyAppPublisher}
AppPublisherURL={#MyAppURL}
AppSupportURL={#MyAppURL}
AppUpdatesURL={#MyAppURL}
DefaultDirName={localappdata}\Programs\JA_LAN_Messenger_Setup
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
DisableProgramGroupPage=yes
OutputDir=..\..\dist
OutputBaseFilename=JA_LAN_Messenger_v{#MyAppVersion}_Setup
SetupIconFile=..\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\{#MyAppExeName}
Compression=lzma2/ultra64
SolidCompression=yes
WizardStyle=modern
PrivilegesRequired=lowest
CloseApplications=yes
RestartApplications=no

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: checkedonce

[Files]
; Inno owns its uninstaller; never distribute the batch installer in this app.
Source: "..\..\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Excludes: "install.bat,uninstall.bat,uninstall.ps1,user_preferences.json,update_config.json,known_devices.json,network_preferences.json,config.json,config.ini,*.log,*.key,*.pem,*.pfx,*.p12,logs\*,conversations\*,backups\*"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autoprograms}\{#MyAppName}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"
Name: "{autoprograms}\{#MyAppName}\Gỡ cài đặt {#MyAppName}"; Filename: "{uninstallexe}"
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#MyAppExeName}"; Description: "{cm:LaunchProgram,{#StringChange(MyAppName, '&', '&&')}}"; Flags: nowait postinstall skipifsilent
