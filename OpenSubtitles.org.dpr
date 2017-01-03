{$I PLUGIN_DEFINES.INC}

     {********************************************************************
      | This Source Code is subject to the terms of the                  |
      | Mozilla Public License, v. 2.0. If a copy of the MPL was not     |
      | distributed with this file, You can obtain one at                |
      | https://mozilla.org/MPL/2.0/.                                    |
      |                                                                  |
      | Software distributed under the License is distributed on an      |
      | "AS IS" basis, WITHOUT WARRANTY OF ANY KIND, either express or   |
      | implied. See the License for the specific language governing     |
      | rights and limitations under the License.                        |
      ********************************************************************}


      { This sample code uses the Indy v10 open source library:
        http://www.indyproject.org

        And the TNT Delphi Unicode Controls (compatiable with the last free version)
        to handle a few unicode tasks.

        And MD5 code from Peter Sawatzki:
        http://www.sawatzki.de

        And XML parsing form Stefan Heymann:
        http://www.destructor.de/xmlparser/index.htm

        And adapted code snippets from Yanniel Alvarez :
        http://www.yanniel.info/2012/01/open-subtitles-api-in-delphi.html

        And adapted OSDb hashing code from :
        http://trac.opensubtitles.org/projects/opensubtitles/wiki/HashSourceCodes#Delphi

        And optionally, the FastMM/FastCode/FastMove libraries:
        http://sourceforge.net/projects/fastmm/

        Hopefully, I haven't forggoten anyone.

        Most of the remaining code by Yaron Gur, Zoom Player's lead developer:
        http://inmatrix.com.
        }

// to do :
// [x]  1. XML parsing basics
// [x]  2. Code keep-alive thread
// [x]  3. Code calling functions
// [x]  4. Configure screen with user login/pass input
// [x]  5. md5 encode the pass
// [x]  6. parse login
// [x]  7. parse search
// [x]  8. parse keepalive pings
// [x]  9. look into gzip communication
// [ ] 10. handle '407 Download limit reached', do not use persistent connections (HTTP keep-alive) and don't download more than 200 subtitles per 24 hour per IP/User. If user wants more, he can ?Become OpenSubtitles VIP member - thats one of the many reasons, why your app should allow user to login.
// [p] 11. properly handle HTTP status codes, sometimes you might get 5xx


library OpenSubtitles.org;

uses
  FastMM4,
  FastMove,
  FastCode,
  Windows,
  SysUtils,
  Classes,
  Forms,
  Controls,
  DateUtils,
  SyncObjs,
  Dialogs,
  StrUtils,
  TNTClasses,
  TNTSysUtils,
  SuperObject,
  WinInet,
  misc_utils_unit,
  md5,
  OSDbUnit in 'OSDbUnit.pas',
  configformunit in 'configformunit.pas';

{$R *.res}


Type
  TStayAliveThread = Class(TThread)
    procedure Execute; override;
  public
    StayAliveData : PStayAliveDataRecord;
    doTerminate   : Boolean;
    threadStatus  : Integer;
  end;

Const
  {$I APIKEY.INC}

  // Settings Registry Path and Key
  PluginRegKey               : String = 'Software\VirtuaMedia\ZoomPlayer\SubtitlePlugins\OpenSubtitles.org';
  RegKey_Username            : String = 'user';
  RegKey_PasswordMD5         : String = 'passMD5';


var
  LoggedIn        : Boolean    = False;
  cUser           : String     = ''; // 'Inmatrix';
  cPass           : String     = ''; //'Op3nSu6titl3s_2016';
  cPassMD5        : String     = '';
  cLanguage       : String     = 'en';
  cToken          : String     = '';
  cSecure         : Boolean    = False;
  cLoginData      : POSDbLoginRecord;
  StayAliveThread : TStayAliveThread = nil;



procedure DestroyStayAliveThread;
var
  iTimeout : Integer;
begin
  If StayAliveThread <> nil then
  Begin
    {$IFDEF LOCALTRACE}DebugMsgFT(logPath,'Destroy StayAlive thread (before)');{$ENDIF}
    StayAliveThread.doTerminate := True;
    iTimeout := 0;
    While (StayAliveThread.ThreadStatus <> 255) and (iTimeout < 1000) do
    Begin
      Sleep(25);
      Inc(iTimeout,25);
    End;
    FreeAndnil(StayAliveThread);
    {$IFDEF LOCALTRACE}DebugMsgFT(logPath,'Destroy StayAlive thread (after)');{$ENDIF}
  End
  {$IFDEF LOCALTRACE}Else DebugMsgFT(logPath,'Destroy StayAlive thread, thread did not exist'){$ENDIF};
end;


procedure CreateStayAliveThread;
begin
  If StayAliveThread = nil then
  Begin
    {$IFDEF LOCALTRACE}DebugMsgFT(logPath,'Create StayAlive thread (before)');{$ENDIF}
    StayAliveThread                 := TStayAliveThread.Create(True);
    StayAliveThread.doTerminate     := False;
    StayAliveThread.threadStatus    := 0;
    StayAliveThread.FreeOnTerminate := False;
    New(StayAliveThread.StayAliveData);
    StayAliveThread.Resume;
    {$IFDEF LOCALTRACE}DebugMsgFT(logPath,'Create StayAlive thread (after)');{$ENDIF}
  End
  {$IFDEF LOCALTRACE}Else DebugMsgFT(logPath,'Create StayAlive thread, thread already exists'){$ENDIF};
end;


procedure TStayAliveThread.Execute;
const
  PingDelay     : Integer = 15*60*1000; // 15min in
var
  PingTS        : Int64;
  CurrentTS     : Int64;
  perfTimerFreq : Int64;
  Tick64        : Int64;
  I             : Integer;
begin
  {$IFDEF LOCALTRACE}DebugMsgFT(logPath,'StayAlive thread execute (before)');{$ENDIF}
  QueryPerformanceFrequency(perfTimerFreq);
  QueryPerformanceCounter(Tick64);
  CurrentTS := (Tick64*1000) div perfTimerFreq;
  PingTS    := CurrentTS+PingDelay;
  New(StayAliveData);

  ThreadStatus := 1;
  While doTerminate = False do
  Begin
    QueryPerformanceCounter(Tick64);
    CurrentTS := (Tick64*1000) div perfTimerFreq;
    For I := 0 to 9 do If doTerminate = False then Sleep(100);

    // Ping to stay alive (logged in)
    If CurrentTS >= PingTS then
    Begin
      {$IFDEF LOCALTRACE}DebugMsgFT(logPath,'StayAlive ping (before)');{$ENDIF}
      PingTS := CurrentTS+PingDelay;
      csStayAlive.Enter;
      Try
        StayAliveData^.Status := E_FAIL;
      Finally
        csStayAlive.Leave;
      End;
      OSDb_StayAlive(cToken,cUserAgent,StayAliveData,cSecure);

      If (StayAliveData^.Status = E_FAIL) or (StayAliveData^.Status = 406) then
      Begin
        {$IFDEF LOCALTRACE}DebugMsgFT(logPath,'StayAlive: not logged in!');{$ENDIF}
        If LoggedIn = True then
        Begin
          csStayAlive.Enter;
          Try
            LoggedIn := False;
            Dispose(cLoginData);
          Finally
            csStayAlive.Leave;
          End;
        End;
      End;
      {$IFDEF LOCALTRACE}DebugMsgFT(logPath,'StayAlive ping (after)');{$ENDIF}
    End;
  End;
  {$IFDEF LOCALTRACE}DebugMsgFT(logPath,'StayAlive thread execute (after)');{$ENDIF}
  Dispose(StayAliveData);
  ThreadStatus := 255; // signal thread is terminated
end;


// Called by Zoom Player to free any resources allocated in the DLL prior to unloading the DLL.
// Keep this function light, it slows down Zoom Player's closing time.
Procedure FreePlugin; stdcall;
begin
  {$IFDEF LOCALTRACE}DebugMsgFT(logPath,'Free Plugin (before)');{$ENDIF}
  DestroyStayAliveThread;
  If LoggedIn = True then
  Begin
    OSDb_Logout(cUser,cUserAgent,cSecure);
    Dispose(cLoginData);
  End;
  {$IFDEF LOCALTRACE}DebugMsgFT(logPath,'Free Plugin (after)');{$ENDIF}
end;


// Called by Zoom Player to init any resources.
// Keep this function light, it slows down Zoom Player's launch time.
function InitPlugin : Bool; stdcall;
begin
  {$IFDEF LOCALTRACE}DebugMsgFT(logPath,'Init Plugin (before)');{$ENDIF}
  Result := True;

  // Read username/password MD5 checksum from registry
  cUser    := GetRegString(HKEY_CURRENT_USER,PluginRegKey,RegKey_Username);
  cPassMD5 := GetRegString(HKEY_CURRENT_USER,PluginRegKey,RegKey_PasswordMD5);
  {$IFDEF LOCALTRACE}DebugMsgFT(logPath,'Init Plugin (after)');{$ENDIF}
end;


// Called by Zoom Player to verify if a configuration dialog is available.
// Return True if a dialog exits and False if no configuration dialog exists.
function CanConfigure : Bool; stdcall;
begin
  {$IFDEF LOCALTRACE}DebugMsgFT(logPath,'CanConfigure (before)');{$ENDIF}
  Result := True;
  {$IFDEF LOCALTRACE}DebugMsgFT(logPath,'CanConfigure (after)');{$ENDIF}
end;


// Called by Zoom Player to show the plugin's configuration dialog.
Procedure Configure(CenterOnWindow : HWND); stdcall;
var
  CenterOnRect : TRect;
  tmpInt: Integer;
begin
  {$IFDEF LOCALTRACE}DebugMsgFT(logPath,'Configure (before)');{$ENDIF}
  If GetWindowRect(CenterOnWindow,CenterOnRect) = False then
    GetWindowRect(0,CenterOnRect); // Can't find window, center on screen

  ConfigForm := TConfigForm.Create(nil);
  ConfigForm.SetBounds(CenterOnRect.Left+(((CenterOnRect.Right -CenterOnRect.Left)-ConfigForm.Width)  div 2),
                       CenterOnRect.Top +(((CenterOnRect.Bottom-CenterOnRect.Top )-ConfigForm.Height) div 2),ConfigForm.Width,ConfigForm.Height);

  ConfigForm.UsernameEdit.Text := UTF8Decode(cUser);
  ConfigForm.PasswordEdit.Text := cPassMD5;
  If ConfigForm.ShowModal = mrOK then
  Begin
    cUser    := ConfigForm.UsernameEdit.Text;
    cPass    := ConfigForm.PasswordEdit.Text;

    If ConfigForm.PasswordEdit.Tag = 0 then
      cPassMD5 := StringMD5Digest(cPass) else
      cPassMD5 := cPass;
    cPass    := '';

    // Save to registry
    SetRegString(HKEY_CURRENT_USER,PluginRegKey,RegKey_Username,cUser);
    SetRegString(HKEY_CURRENT_USER,PluginRegKey,RegKey_PasswordMD5,cPassMD5);
  End;
  ConfigForm.Free;
  {$IFDEF LOCALTRACE}DebugMsgFT(logPath,'Configure (after)');{$ENDIF}
end;


Function GetSubtitleEntries(CenterOnWindow : HWND; SubData : PSubPluginRecord) : Integer; stdcall;
var
  sFileName : WideString;
  iFileHash : Int64;
  iFileSize : Int64;
  sFileHash : String;


begin
  {$IFDEF LOCALTRACE}DebugMsgFT(logPath,'GetSubtitleEntries (before)');{$ENDIF}
  Result       := E_FAIL;

  If LoggedIn = False then
  Begin
    {$IFDEF LOCALTRACE}DebugMsgFT(logPath,'Try to Login'+CRLF);{$ENDIF}
    New(cLoginData);
    cLoginData^.IDUser                := -1;
    cLoginData^.UserNickName          := '';
    cLoginData^.UserRank              := '';
    cLoginData^.UploadCnt             := -1;
    cLoginData^.DownloadCnt           := -1;
    cLoginData^.UserPreferedLanguages := '';
    cLoginData^.UserWebLanguage       := '';

    //cPassMD5 := StringMD5Digest(cPass); // Only send MD5 hash of the password

    // Login
    If OSDb_Login(cUser,cPassMD5,cLanguage,cUserAgent,cLoginData,cSecure) = S_OK then
    Begin
      csStayAlive.Enter;
      Try
        cToken   := cLoginData^.Token;
        LoggedIn := True;
      Finally
        csStayAlive.Leave;
      End;
      {$IFDEF LOCALTRACE}DebugMsgFT(logPath,'Login successful'+CRLF);{$ENDIF}

      CreateStayAliveThread;
    End
      else
    Begin
      {$IFDEF LOCALTRACE}DebugMsgFT(logPath,'Login failed!'+CRLF);{$ENDIF}
    End;
  End;

  If LoggedIn = True then
  Begin
    sFileName := UTF8Decode(SubData^.FileName);

    If WideFileExists(sFileName) = True then
    Begin
      {$IFDEF LOCALTRACE}DebugMsgFT(logPath,'Source File : '+sFileName);{$ENDIF}
      // Generate OSDb file hash
      iFileHash := CalcGabestHash(sFileName);
      If iFileHash <> 0 then
      Begin
        sFileHash := IntToHex(iFileHash,16);
        {$IFDEF LOCALTRACE}DebugMsgFT(logPath,'File Hash : '+sFileHash);{$ENDIF}
        iFileSize := GetFileSize64(sFileName);
        {$IFDEF LOCALTRACE}DebugMsgFT(logPath,'File Size : '+IntToStr(iFileSize)+CRLF+CRLF);{$ENDIF}

        // Query OSDb for subtitle match based on hash
        SubData^.Status := E_FAIL;
        If OSDb_SearchSubtitles(cToken,cUserAgent,sFileHash,iFileSize,SubData,cSecure) = S_OK then
        Begin
          Result := S_OK;
        End;
      End;
    End;
  End;

  {$IFDEF LOCALTRACE}DebugMsgFT(logPath,'GetSubtitleEntries, Result : '+IntToHex(Result,8)+' (after)');{$ENDIF}
end;




exports
   InitPlugin,
   FreePlugin,
   CanConfigure,
   Configure,
   GetSubtitleEntries;

begin
end.

