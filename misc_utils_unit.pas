{$I PLUGIN_DEFINES.INC}

unit misc_utils_unit;


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

      { This sample code uses the TNT Delphi Unicode Controls (compatiable
        with the last free version) to handle a few unicode tasks. }

interface

uses
  Windows, Classes, TNTClasses, SuperObject;


Const
{$IFDEF LOCALTRACE}
  logPath : String = 'c:\log\.OpenSubtitles.org_plugin.txt';
{$ENDIF}
  CRLF    : String = #13#10;

function  TickCount64 : Int64;

procedure DebugMsgF(FileName : WideString; Txt : WideString);
procedure DebugMsgFT(FileName : WideString; Txt : WideString);

function  DownloadFileToStringList(URL : String; fStream : TStringList; var Status : String; var ErrorCode: Integer; TimeOut : DWord) : Boolean; overload;
function  DownloadFileToStream(URL : String; fStream : TMemoryStream; var Status : String; var ErrorCode: Integer; TimeOut : DWord) : Boolean; overload;
//function  DownloadFileToStream(URL : String; fStream : TMemoryStream) : Boolean; overload;
function  DownloadImageToFile(URL : String; ImageFilePath, ImageFileName : WideString; var Status : String; var ErrorCode: Integer; TimeOut : DWord) : Boolean; overload;
//function  DownloadImageToFile(URL : String; ImageFilePath, ImageFileName : WideString) : Boolean; overload;
procedure DownloadImageToFileThreaded(URL : String; ImageFilePath, ImageFileName : WideString; var Status : String; var ErrorCode: Integer; TimeOut : DWord; var SuccessCode, DownloadEnded : Boolean);

function  URLEncodeUTF8(stInput : widestring) : string;

function  SetRegDWord(BaseKey : HKey; SubKey : String; KeyEntry : String; KeyValue : Integer) : Boolean;
function  GetRegDWord(BaseKey : HKey; SubKey : String; KeyEntry : String) : Integer;
function  SetRegString(BaseKey : HKey; SubKey : String; KeyEntry : String; KeyValue : String) : Boolean;
function  GetRegString(BaseKey : HKey; SubKey : String; KeyEntry : String) : String;

function  AddBackSlash(S : WideString) : WideString; Overload;
function  ConvertCharsToSpaces(S : WideString) : WideString;

function  DecodeTextTags(S : WideString; RemoveSuffix : Boolean) : WideString;
function  EncodeTextTags(S : WideString; AddSuffix : Boolean) : WideString;

procedure FileExtIntoStringList(fPath,fExt : WideString; fList : TTNTStrings; Recursive : Boolean);

function  CalcGabestHash(const Stream: TStream): Int64; overload;
function  CalcGabestHash(const FileName: WideString): Int64; overload;
function  XML_RPC(sURL,sUserAgent, sRPCRequest: string; Secured : Boolean): string;

function  GetFileSize64(FileName : Widestring) : Int64;


implementation

uses
  SysUtils, SyncObjs, TNTSysUtils, wininet, IdHTTP, IdCompressorZLib;


const
  URLIdentifier     : String = 'Mozilla/4.0 (compatible; MSIE 6.0; Windows NT 5.1)';

type
  TDownloadThread = Class(TThread)
    procedure execute; override;
  public
    DownloadEnded  : PBoolean;
    SuccessCode    : PBoolean;
    URL            : String;
    ImageFilePath  : WideString;
    ImageFileName  : WideString;
    Status         : PString;
    ErrorCode      : PInteger;
    TimeOut        : DWord;
  end;

var
  TickCountLast    : DWORD = 0;
  TickCountBase    : Int64 = 0;
  DebugStartTime   : Int64 = -1;
  qTimer64Freq     : Int64;
  csDebug          : TCriticalSection;


function TickCount64 : Int64;
begin
  Result := GetTickCount;
  If Result < TickCountLast then TickCountBase := TickCountBase+$100000000;
  TickCountLast := Result;
  Result := Result+TickCountBase;
end;


procedure DebugMsgFT(FileName : WideString; Txt : WideString);
var
  S,S1 : String;
  i64  : Int64;
begin
  If FileName <> '' then
  Begin
    QueryPerformanceCounter(i64);
    S := FloatToStrF(((i64-DebugStartTime)*1000) / qTimer64Freq,ffFixed,15,3);
    While Length(S) < 12 do S := ' '+S;
    S1 := DateToStr(Date)+' '+TimeToStr(Time);
    DebugMsgF(FileName,S1+' ['+S+'] : '+Txt);
  End;
end;


procedure DebugMsgF(FileName : WideString; Txt : WideString);
var
  fStream  : TTNTFileStream;
  S        : String;
begin
  If FileName <> '' then
  Begin
    csDebug.Enter;
    Try
      If WideFileExists(FileName) = True then
      Begin
        Try
          fStream := TTNTFileStream.Create(FileName,fmOpenWrite);
        Except
          fStream := nil;
        End;
      End
        else
      Begin
        Try
           fStream := TTNTFileStream.Create(FileName,fmCreate);
        Except
          fStream := nil;
        End;
      End;
      If fStream <> nil then
      Begin
        S := UTF8Encode(Txt)+CRLF;
        fStream.Seek(0,soFromEnd);
        fStream.Write(S[1],Length(S));
        fStream.Free;
       End;
    Finally
      csDebug.Leave;
    End;
  End;
end;


function  DownloadFileToStringList(URL : String; fStream : TStringList; var Status : String; var ErrorCode: Integer; TimeOut : DWord) : Boolean;
var
  MemStream : TMemoryStream;
begin
  Result := False;
  If fStream <> nil then
  Begin
    MemStream := TMemoryStream.Create;
    Result := DownloadFileToStream(URL,MemStream,Status,ErrorCode,TimeOut);
    MemStream.Position := 0;
    fStream.LoadFromStream(MemStream);
    MemStream.Free;
  End;
end;


(*
function DownloadFileToStringList(URL : String; fStream : TStringList) : Boolean;
var
  Status    : String;
  ErrorCode : DWord;
begin
  Result := DownloadFileToStringList(URL,fStream,Status,ErrorCode,0);
end;
(**)


function DownloadFileToStream(URL : String; fStream : TMemoryStream; var Status : String; var ErrorCode: Integer; TimeOut : DWord) : Boolean;
type
  DLBufType = Array[0..1024] of Char;
const
  MaxRetryAttempts = 5;
  RetryInterval = 1; //seconds
var
  NetHandle  : HINTERNET;
  URLHandle  : HINTERNET;
  DLBuf      : ^DLBufType;
  BytesRead  : DWord;
  infoBuffer : Array [0..512] of char;
  bufLen     : DWORD;
  Tmp        : DWord;
  iAttemptsLeft : Integer;
  AttemptAgain  : Boolean;
  RetryAfter: String;
begin
  Result := False;
  Status := '';
  ErrorCode := 0;
  If fStream <> nil then
  Begin
    NetHandle := InternetOpen(PChar(URLIdentifier),INTERNET_OPEN_TYPE_PRECONFIG, nil, nil, 0);
    If Assigned(NetHandle) then
    Begin
      If TimeOut > 0 then
      Begin
        InternetSetOption(NetHandle,INTERNET_OPTION_CONNECT_TIMEOUT,@TimeOut,Sizeof(TimeOut));
        InternetSetOption(NetHandle,INTERNET_OPTION_SEND_TIMEOUT   ,@TimeOut,Sizeof(TimeOut));
        InternetSetOption(NetHandle,INTERNET_OPTION_RECEIVE_TIMEOUT,@TimeOut,Sizeof(TimeOut));
      End;

      iAttemptsLeft := MaxRetryAttempts;
      repeat
        AttemptAgain := False;

        UrlHandle := InternetOpenUrl(NetHandle,PChar(URL),nil,0,INTERNET_FLAG_RELOAD,0);
        If Assigned(UrlHandle) then
        Begin
          tmp    := 0;
          bufLen := Length(infoBuffer);

          If HttpQueryInfo(UrlHandle,HTTP_QUERY_STATUS_CODE,@infoBuffer[0],bufLen,tmp) = True then
          Begin
            Status := infoBuffer;

            RetryAfter := '';
            If Status = '429' then
            Begin
              //To get all headers use the following code
              //  HttpQueryInfo(UrlHandle,HTTP_QUERY_RAW_HEADERS_CRLF,@Headers[0],bufLen,tmp);
              //for guidance and hints on buffer sizes and in/out params see:
              //  https://msdn.microsoft.com/en-us/library/windows/desktop/aa385373%28v=vs.85%29.aspx

              //Retry-After
              //X-RateLimit-Limit: 40
              //X-RateLimit-Remaining: 39
              //X-RateLimit-Reset: 1453056622
              bufLen := Length(infoBuffer);
              infoBuffer := 'Retry-After';
              if HttpQueryInfo(UrlHandle,HTTP_QUERY_CUSTOM,@infoBuffer[0],bufLen,tmp) then
                RetryAfter := infoBuffer
              else RetryAfter := '';
            End;

            New(DLBuf);
            fStream.Clear;
            Repeat
              ZeroMemory(DLBuf,Sizeof(DLBufType));
              If InternetReadFile(UrlHandle,DLBuf,SizeOf(DLBufType),BytesRead) = True then
                If BytesRead > 0 then fStream.Write(DLBuf^,BytesRead);
            Until (BytesRead = 0);
            Dispose(DLBuf);

            If Status = '200' then Result := True
            else If Status = '429' then // 429 - Too Many Requests
            Begin
              AttemptAgain := True;
              Dec(iAttemptsLeft);
              Sleep(1000 * StrToIntDef(RetryAfter, RetryInterval));
            End
          End;
          InternetCloseHandle(UrlHandle);
        End
          else ErrorCode := GetLastError;
      until
        not (AttemptAgain and (iAttemptsLeft > 0));
      InternetCloseHandle(NetHandle);
    End;
  End;
end;


(*
function DownloadFileToStream(URL : String; fStream : TMemoryStream) : Boolean;
var
  Status    : String;
  ErrorCode : DWord;
begin
  Result := DownloadFileToStream(URL,fStream,Status,ErrorCode,0);
end;
(**)

procedure TDownloadThread.execute;
begin
  SuccessCode^   := DownloadImageToFile(URL,ImageFilePath,ImageFileName,Status^,ErrorCode^,TimeOut);
  DownloadEnded^ := True;
end;


procedure DownloadImageToFileThreaded(URL : String; ImageFilePath, ImageFileName : WideString; var Status : String; var ErrorCode: Integer; TimeOut : DWord; var SuccessCode, DownloadEnded : Boolean);
var
  DownloadThread : TDownloadthread;
begin
  DownloadThread                    := TDownloadThread.Create(True);
  DownloadThread.Priority           := tpIdle;
  DownloadThread.FreeOnTerminate    := True;
  DownloadThread.URL                := URL;
  DownloadThread.ImageFilePath      := ImageFilePath;
  DownloadThread.ImageFileName      := ImageFileName;
  DownloadThread.Status             := @Status;
  DownloadThread.ErrorCode          := @ErrorCode;
  DownloadThread.TimeOut            := TimeOut;
  DownloadThread.SuccessCode        := @SuccessCode;
  DownloadThread.SuccessCode^       := False;
  DownloadThread.DownloadEnded      := @DownloadEnded;
  DownloadThread.DownloadEnded^     := False;

  DownloadThread.Resume;
end;


function  DownloadImageToFile(URL : String; ImageFilePath, ImageFileName : WideString; var Status : String; var ErrorCode: Integer; TimeOut : DWord) : Boolean;
var
  iStream : TMemoryStream;
  fStream : TTNTFileStream;
begin
  Result := False;
  // Download image to memory stream
  iStream := TMemoryStream.Create;
  iStream.Clear;
  If DownloadFileToStream(URL,iStream,Status,ErrorCode,TimeOut) = True then
  Begin
    If iStream.Size > 0 then
    Begin
      // Create the destination folder if it doesn't exist
      If WideDirectoryExists(ImageFilePath) = False then WideForceDirectories(ImageFilePath);

      // Save the source image to disk
      Try
        fStream := TTNTFileStream.Create(ImageFilePath+ImageFileName,fmCreate);
      Except
        fStream := nil
      End;
      If fStream <> nil then
      Begin
        iStream.Position := 0;
        Try
          fStream.CopyFrom(iStream,iStream.Size);
          Result := True;
        Finally
          fStream.Free;
        End;
      End;
    End;
  End;
  iStream.Free;
end;


(*
function DownloadImageToFile(URL : String; ImageFilePath, ImageFileName : WideString) : Boolean;
var
  Status    : String;
  ErrorCode : DWord;
begin
  Result := DownloadImageToFile(URL,ImageFilePath,ImageFileName,Status,ErrorCode,0);
end;
(**)


function URLEncodeUTF8(stInput : widestring) : string;
const
  Hex : array[0..255] of string = (
    '%00', '%01', '%02', '%03', '%04', '%05', '%06', '%07',
    '%08', '%09', '%0a', '%0b', '%0c', '%0d', '%0e', '%0f',
    '%10', '%11', '%12', '%13', '%14', '%15', '%16', '%17',
    '%18', '%19', '%1a', '%1b', '%1c', '%1d', '%1e', '%1f',
    '%20', '%21', '%22', '%23', '%24', '%25', '%26', '%27',
    '%28', '%29', '%2a', '%2b', '%2c', '%2d', '%2e', '%2f',
    '%30', '%31', '%32', '%33', '%34', '%35', '%36', '%37',
    '%38', '%39', '%3a', '%3b', '%3c', '%3d', '%3e', '%3f',
    '%40', '%41', '%42', '%43', '%44', '%45', '%46', '%47',
    '%48', '%49', '%4a', '%4b', '%4c', '%4d', '%4e', '%4f',
    '%50', '%51', '%52', '%53', '%54', '%55', '%56', '%57',
    '%58', '%59', '%5a', '%5b', '%5c', '%5d', '%5e', '%5f',
    '%60', '%61', '%62', '%63', '%64', '%65', '%66', '%67',
    '%68', '%69', '%6a', '%6b', '%6c', '%6d', '%6e', '%6f',
    '%70', '%71', '%72', '%73', '%74', '%75', '%76', '%77',
    '%78', '%79', '%7a', '%7b', '%7c', '%7d', '%7e', '%7f',
    '%80', '%81', '%82', '%83', '%84', '%85', '%86', '%87',
    '%88', '%89', '%8a', '%8b', '%8c', '%8d', '%8e', '%8f',
    '%90', '%91', '%92', '%93', '%94', '%95', '%96', '%97',
    '%98', '%99', '%9a', '%9b', '%9c', '%9d', '%9e', '%9f',
    '%a0', '%a1', '%a2', '%a3', '%a4', '%a5', '%a6', '%a7',
    '%a8', '%a9', '%aa', '%ab', '%ac', '%ad', '%ae', '%af',
    '%b0', '%b1', '%b2', '%b3', '%b4', '%b5', '%b6', '%b7',
    '%b8', '%b9', '%ba', '%bb', '%bc', '%bd', '%be', '%bf',
    '%c0', '%c1', '%c2', '%c3', '%c4', '%c5', '%c6', '%c7',
    '%c8', '%c9', '%ca', '%cb', '%cc', '%cd', '%ce', '%cf',
    '%d0', '%d1', '%d2', '%d3', '%d4', '%d5', '%d6', '%d7',
    '%d8', '%d9', '%da', '%db', '%dc', '%dd', '%de', '%df',
    '%e0', '%e1', '%e2', '%e3', '%e4', '%e5', '%e6', '%e7',
    '%e8', '%e9', '%ea', '%eb', '%ec', '%ed', '%ee', '%ef',
    '%f0', '%f1', '%f2', '%f3', '%f4', '%f5', '%f6', '%f7',
    '%f8', '%f9', '%fa', '%fb', '%fc', '%fd', '%fe', '%ff');
var
  iLen,iIndex : integer;
  stEncoded   : string;
  ch          : widechar;
begin
  iLen := Length(stInput);
  stEncoded := '';
  for iIndex := 1 to iLen do
  begin
    ch := stInput[iIndex];
    If (ch >= 'A') and (ch <= 'Z') then stEncoded := stEncoded + ch
      else
    If (ch >= 'a') and (ch <= 'z') then stEncoded := stEncoded + ch
      else
    If (ch >= '0') and (ch <= '9') then stEncoded := stEncoded + ch
      else
    If (ch = ' ') then stEncoded := stEncoded + '%20'//'+'
      else
    If ((ch = '-') or (ch = '_') or (ch = '.') or (ch = '!') or (ch = '*') or (ch = '~') or (ch = '\')  or (ch = '(') or (ch = ')')) then stEncoded := stEncoded + ch
      else
    If (Ord(ch) <= $07F) then stEncoded := stEncoded + hex[Ord(ch)]
      else
    If (Ord(ch) <= $7FF) then
    begin
      stEncoded := stEncoded + hex[$c0 or (Ord(ch) shr 6)];
      stEncoded := stEncoded + hex[$80 or (Ord(ch) and $3F)];
    end
      else
    begin
      stEncoded := stEncoded + hex[$e0 or (Ord(ch) shr 12)];
      stEncoded := stEncoded + hex[$80 or ((Ord(ch) shr 6) and ($3F))];
      stEncoded := stEncoded + hex[$80 or ((Ord(ch)) and ($3F))];
    end;
  end;
  result := (stEncoded);
end;


function SetRegDWord(BaseKey : HKey; SubKey : String; KeyEntry : String; KeyValue : Integer) : Boolean;
var
  RegHandle : HKey;
  I         : Integer;
begin
  Result := False;
  If RegCreateKeyEx(BaseKey,PChar(SubKey),0,nil,REG_OPTION_NON_VOLATILE,KEY_ALL_ACCESS,nil,RegHandle,@I) = ERROR_SUCCESS then
  Begin
    If RegSetValueEx(RegHandle,PChar(KeyEntry),0,REG_DWORD,@KeyValue,4) = ERROR_SUCCESS then Result := True;
    RegCloseKey(RegHandle);
  End;
end;


function GetRegDWord(BaseKey : HKey; SubKey : String; KeyEntry : String) : Integer;
var
  RegHandle : HKey;
  RegType   : LPDWord;
  BufSize   : LPDWord;
  KeyValue  : Integer;
begin
  Result := -1;
  If RegOpenKeyEx(BaseKey,PChar(SubKey),0,KEY_READ,RegHandle) = ERROR_SUCCESS then
  Begin
    New(RegType);
    New(BufSize);
    RegType^ := Reg_DWORD;
    BufSize^ := 4;
    If RegQueryValueEx(RegHandle,PChar(KeyEntry),nil,RegType,@KeyValue,BufSize) = ERROR_SUCCESS then
    Begin
      Result := KeyValue;
    End;
    Dispose(BufSize);
    Dispose(RegType);
    RegCloseKey(RegHandle);
  End;
end;


function  GetRegString(BaseKey : HKey; SubKey : String; KeyEntry : String) : String;
var
  RegHandle : HKey;
  RegType   : LPDWord;
  BufSize   : LPDWord;
  KeyValue  : String;
begin
  Result := '';
  If RegOpenKeyEx(BaseKey,PChar(SubKey),0,KEY_READ,RegHandle) = ERROR_SUCCESS then
  Begin
    New(RegType);
    New(BufSize);
    RegType^ := Reg_SZ;
    BufSize^ := 1024;
    SetLength(KeyValue,1024);
    If RegQueryValueEx(RegHandle,PChar(KeyEntry),nil,RegType,@KeyValue[1],BufSize) = ERROR_SUCCESS then
    Begin
      If BufSize^ > 0 then SetLength(KeyValue,BufSize^-1) else KeyValue := '';
      Result := KeyValue;
    End;
    Dispose(BufSize);
    Dispose(RegType);
    RegCloseKey(RegHandle);
  End;
end;


function SetRegString(BaseKey : HKey; SubKey : String; KeyEntry : String; KeyValue : String) : Boolean;
var
  RegHandle : HKey;
  S         : String;
  I         : Integer;
begin
  Result := False;
  If RegCreateKeyEx(BaseKey,PChar(SubKey),0,nil,REG_OPTION_NON_VOLATILE,KEY_ALL_ACCESS,nil,RegHandle,@I) = ERROR_SUCCESS then
  Begin
    S := KeyValue;
    Result := RegSetValueEx(RegHandle,@KeyEntry[1],0,REG_SZ,@S[1],Length(S)) = ERROR_SUCCESS;
    RegCloseKey(RegHandle);
  End;
end;




function AddBackSlash(S : WideString) : WideString; Overload;
var I : Integer;
begin
  I := Length(S);
  If I > 0 then If (S[I] <> '\') and (S[I] <> '/') then S := S+'\';
  Result := S;
end;


function ConvertCharsToSpaces(S : WideString) : WideString;
begin
  Result := TNT_WideStringReplace(TNT_WideStringReplace(TNT_WideStringReplace(S,'-', ' ', [rfReplaceAll]), '.', ' ', [rfReplaceAll]), '_', ' ', [rfReplaceAll]);
end;


procedure FileExtIntoStringList(fPath,fExt : WideString; fList : TTNTStrings; Recursive : Boolean);
var
  sRec : TSearchRecW;
begin
  If WideFindFirst(fPath+'*.*',faAnyFile,sRec) = 0 then
  Begin
    Repeat
      If (Recursive = True) and (sRec.Attr and faDirectory = faDirectory) and (sRec.Name <> '.') and (sRec.Name <> '..') then
      Begin
        FileExtIntoStringList(AddBackSlash(fPath+sRec.Name),fExt,fList,Recursive);
      End
        else
      If (sRec.Attr and faVolumeID = 0) and (sRec.Attr and faDirectory = 0) then
      Begin
        If WideCompareText(WideExtractFileExt(sRec.Name),fExt) = 0 then
          fList.Add(fPath+sRec.Name);
      End;
    Until WideFindNext(sRec) <> 0;
    WideFindClose(sRec);
  End;
end;


function DecodeTextTags(S : WideString; RemoveSuffix : Boolean) : WideString;
var
  S1 : WideString;
begin
  If RemoveSuffix = True then S1 := ';' else S1 := '';
  S := TNT_WideStringReplace(S,'&apos' +S1,'''',[rfReplaceAll]);
  S := TNT_WideStringReplace(S,'&comma'+S1,',' ,[rfReplaceAll]);
  S := TNT_WideStringReplace(S,'&quot' +S1,'"' ,[rfReplaceAll]);
  S := TNT_WideStringReplace(S,'&lt'   +S1,'<' ,[rfReplaceAll]);
  S := TNT_WideStringReplace(S,'&gt'   +S1,'>' ,[rfReplaceAll]);
  S := TNT_WideStringReplace(S,'&amp'  +S1,'&' ,[rfReplaceAll]);
  S := TNT_WideStringReplace(S,'&pipe' +S1,'|' ,[rfReplaceAll]);
  Result := S;
end;


function EncodeTextTags(S : WideString; AddSuffix : Boolean) : WideString;
var
  S1 : WideString;
begin
  If AddSuffix = True then S1 := ';' else S1 := '';
  S := TNT_WideStringReplace(S,'&' ,'&amp'  +S1,[rfReplaceAll]);
  S := TNT_WideStringReplace(S,'''','&apos' +S1,[rfReplaceAll]);
  S := TNT_WideStringReplace(S,',' ,'&comma'+S1,[rfReplaceAll]);
  S := TNT_WideStringReplace(S,'"' ,'&quot' +S1,[rfReplaceAll]);
  S := TNT_WideStringReplace(S,'<' ,'&lt'   +S1,[rfReplaceAll]);
  S := TNT_WideStringReplace(S,'>' ,'&gt'   +S1,[rfReplaceAll]);
  S := TNT_WideStringReplace(S,'|' ,'&pipe' +S1,[rfReplaceAll]);

  Result := S;
end;


function CalcGabestHash(const Stream: TStream): Int64; overload;
const HashPartSize = 1 shl 16; // 64 KiB

  procedure UpdateHashFromStream(const Stream: TStream; var Hash: Int64);
  var buffer: Array[0..HashPartSize div SizeOf(Int64) - 1] of Int64;
      i     : integer;
  begin
    Stream.ReadBuffer(buffer[0], SizeOf(buffer));
    for i := Low(buffer) to High(buffer) do
      Inc(Hash, buffer[i]);
  end;

begin
  result := Stream.Size;

  if result < HashPartSize then
  begin
    // stream too small return invalid hash
    result := 0;
    exit;
  end;

  // first 64 KiB
  Stream.Position:= 0;
  UpdateHashFromStream(Stream, result);

  // last 64 KiB
  Stream.Seek(-HashPartSize, soEnd);
  UpdateHashFromStream(Stream, result);

  // use "IntToHex(result, 16);" to get a string and "StrToInt64('$' + hash);" to get your Int64 back
end;


function CalcGabestHash(const FileName: WideString): Int64; overload;
var stream: TStream;
begin
  Result := 0;
  Stream := TTNTFileStream.Create(FileName, fmOpenRead or fmShareDenyWrite);
  Try
    Result := CalcGabestHash(stream);
  Finally
    Stream.Free;
  End;
end;



function XML_RPC(sURL,sUserAgent, sRPCRequest: string; Secured : Boolean): string;
var
  lHTTP           : TIdHTTP;
  Source,
  ResponseContent : TStringStream;
  GZip            : TIdCompressorZLib;

begin
  // Missing code to support SSL connections (https), possible use http://stackoverflow.com/questions/1823542/how-to-send-a-http-post-request-in-delphi-using-wininet-api
  lHTTP := TIdHTTP.Create(nil);
  GZip  := TIdCompressorZLib.Create;

  lHTTP.Request.ContentType    := 'text/xml';
  lHTTP.Request.Accept         := '*/*';
  lHTTP.Request.AcceptEncoding := 'gzip';
  lHTTP.Request.Connection     := 'Keep-Alive';
  lHTTP.Request.Method         := Id_HTTPMethodPost;
  lHTTP.Request.UserAgent      := sUserAgent;
  lHTTP.Compressor             := GZip;
  Source := TStringStream.Create(sRPCRequest);
  ResponseContent:= TStringStream.Create('');
  try
    try
      lHTTP.Post(sURL, Source, ResponseContent);
      Result := ResponseContent.DataString;
    except
      Result := '';
    end;
  finally
    GZip.Free;
    lHTTP.Free;
    Source.Free;
    ResponseContent.Free;
  end;
end;


function GetFileSize64(FileName : Widestring) : Int64;
var
  sRec : TSearchRecW;
  nLen : Integer;
  FFileHandle: THandle;
  i64  : Int64;
  fData : WIN32_FILE_ATTRIBUTE_DATA;
begin
  Result := -1;
  nLen := Length(FileName);
  If (nLen > 0) then
  Begin
    If Char(FileName[nLen]) in ['\','/'] then FileName := Copy(FileName,1,nLen-1);

    If Win32PlatformIsUnicode = False then
    Begin
      If GetFileAttributesExA(PChar(String(FileName)),GetFileExInfoStandard,@fData) = True then
        If fData.dwFileAttributes and FILE_ATTRIBUTE_DIRECTORY = 0 then
      Begin
        Int64Rec(Result).Lo := fData.nFileSizeLow;
        Int64Rec(Result).Hi := fData.nFileSizeHigh;
      End;
    End
      else
    Begin
      If GetFileAttributesExW(PWideChar(FileName),GetFileExInfoStandard,@fData) = True then
        If fData.dwFileAttributes and FILE_ATTRIBUTE_DIRECTORY = 0 then
      Begin
        Int64Rec(Result).Lo := fData.nFileSizeLow;
        Int64Rec(Result).Hi := fData.nFileSizeHigh;
      End;
    End;
  End;
end;


initialization
  QueryPerformanceFrequency(qTimer64Freq);
  QueryPerformanceCounter(DebugStartTime);
  csDebug := TCriticalSection.Create;

finalization
  csDebug.Free;

end.