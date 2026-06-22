; Inno Setup — ویزارد کلاسیک «Coinceeper» (شبیه استایل نصب‌کنندهٔ استاندارد Inno)
;
; قبل از Compile:  flutter build windows --release
; سپس:  Inno Setup Compiler → این فایل → Build → Compile
; یا:    .\scripts\inno\Compile-CoinCeeperInstaller.ps1
;
; نسخه را با pubspec.yaml هماهنگ نگه دارید (خط version:).
; برای دکمهٔ واقعی PayPal، DonateURL را به لینک PayPal.me خودتان عوض کنید.


#define MyAppName      "Coinceeper"
#define MyAppPublisher "Coinceeper"
#define MyAppExeName   "CoinCeeper.exe"
#define MyAppVersion   "1.0.38"

; مخزن رسمی پروژه (تا زمان تعریف لینک‌های اختصاصی حمایت / اشتراک)
#define DonateURL    "https://github.com/netcoincapital/flutter"
#define SubscribeURL "https://github.com/netcoincapital/flutter/releases"

#define ReleaseRoot "..\\..\\build\\windows\\x64\\runner\\Release"

[Setup]
AppId={{E81FAACB-4F91-4BDC-A21F-AABBCCDDEECC}}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppVerName={#MyAppName} {#MyAppVersion}
AppPublisher={#MyAppPublisher}
VersionInfoVersion={#MyAppVersion}
DefaultDirName={autopf}\{#MyAppName}
DefaultGroupName={#MyAppName}

LicenseFile=LICENSE_Coinceeper.txt
DisableWelcomePage=no
DisableProgramGroupPage=no

; چک‌باکس «Don't create a Start Menu folder» مثل ویزارد کلاسیک
AllowNoIcons=yes

UninstallDisplayIcon={app}\{#MyAppExeName}

PrivilegesRequired=admin
PrivilegesRequiredOverridesAllowed=dialog

OutputDir=..\..\build\windows\installer_inno
OutputBaseFilename=Coinceeper_Setup_{#MyAppVersion}
Compression=lzma2/ultra64
SolidCompression=yes
WizardStyle=modern
SetupIconFile=..\..\windows\runner\resources\app_icon.ico
WizardSmallImageFile=..\..\assets\images\logo.png

ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
MinVersion=10.0.17763

AllowRootDirectory=no

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Files]
Source: "{#ReleaseRoot}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#MyAppExeName}"; Description: "{cm:LaunchProgram,{#StringChange(MyAppName, '&', '&&')}}"; Flags: nowait postinstall skipifsilent

[Code]
var
  DonateButton: TNewButton;
  SubscribeButton: TNewButton;

procedure DonateClick(Sender: TObject);
var
  ErrCode: Integer;
begin
  ShellExecAsOriginalUser('open', '{#DonateURL}', '', '', SW_SHOWNORMAL, ewNoWait, ErrCode);
end;

procedure SubscribeClick(Sender: TObject);
var
  ErrCode: Integer;
begin
  ShellExecAsOriginalUser('open', '{#SubscribeURL}', '', '', SW_SHOWNORMAL, ewNoWait, ErrCode);
end;

procedure LayoutWizardButtons;
begin
  DonateButton.Top := WizardForm.NextButton.Top;
  DonateButton.Left := ScaleX(8);
  DonateButton.Height := WizardForm.NextButton.Height;

  SubscribeButton.Top := WizardForm.NextButton.Top;
  SubscribeButton.Left := DonateButton.Left + DonateButton.Width + ScaleX(8);
  SubscribeButton.Height := WizardForm.NextButton.Height;
end;

procedure InitializeWizard;
begin
  DonateButton := TNewButton.Create(WizardForm);
  DonateButton.Parent := WizardForm;
  DonateButton.Caption := 'PayPal DONATE';
  DonateButton.Width := ScaleX(130);
  DonateButton.OnClick := @DonateClick;

  SubscribeButton := TNewButton.Create(WizardForm);
  SubscribeButton.Parent := WizardForm;
  SubscribeButton.Caption := 'SUBSCRIBE';
  SubscribeButton.Width := ScaleX(110);
  SubscribeButton.OnClick := @SubscribeClick;

  LayoutWizardButtons;
end;

procedure CurPageChanged(CurPageID: Integer);
begin
  LayoutWizardButtons;
end;
