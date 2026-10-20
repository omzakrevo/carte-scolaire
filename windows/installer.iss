; Installateur Windows de Carte Scolaire (Inno Setup 6).
; Compilé par GitHub Actions : ISCC /DAppVersion=1.0.0 windows\installer.iss

#ifndef AppVersion
  #define AppVersion "1.0.0"
#endif

[Setup]
AppId={{6F1D2B7A-3C4E-4F8A-9B21-CA27E5C0A5B1}
AppName=Carte Scolaire
AppVersion={#AppVersion}
AppPublisher=OMZAKREVO INFORMATIQUE
AppPublisherURL=https://omzakrevo.github.io/carte-scolaire/
DefaultDirName={autopf}\Carte Scolaire
DefaultGroupName=Carte Scolaire
UninstallDisplayIcon={app}\carte_scolaire.exe
SetupIconFile=runner\resources\app_icon.ico
OutputDir=..
OutputBaseFilename=carte-scolaire-windows-installation
Compression=lzma2
SolidCompression=yes
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
PrivilegesRequiredOverridesAllowed=dialog
WizardStyle=modern

[Languages]
Name: "french"; MessagesFile: "compiler:Languages\French.isl"

[Tasks]
Name: "desktopicon"; Description: "Créer une icône sur le Bureau"; GroupDescription: "Raccourcis :"
Name: "firewall"; Description: "Autoriser la caméra du téléphone (pare-feu, réseau privé)"; GroupDescription: "Réseau :"

[Files]
Source: "..\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\Carte Scolaire"; Filename: "{app}\carte_scolaire.exe"
Name: "{group}\Désinstaller Carte Scolaire"; Filename: "{uninstallexe}"
Name: "{autodesktop}\Carte Scolaire"; Filename: "{app}\carte_scolaire.exe"; Tasks: desktopicon

[Run]
Filename: "{sys}\netsh.exe"; Parameters: "advfirewall firewall add rule name=""Carte Scolaire"" dir=in action=allow program=""{app}\carte_scolaire.exe"" profile=private"; Flags: runhidden; Tasks: firewall; Check: IsAdminInstallMode
Filename: "{app}\carte_scolaire.exe"; Description: "Lancer Carte Scolaire"; Flags: nowait postinstall skipifsilent

[UninstallRun]
Filename: "{sys}\netsh.exe"; Parameters: "advfirewall firewall delete rule name=""Carte Scolaire"""; Flags: runhidden; RunOnceId: "fw"
