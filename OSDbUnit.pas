{$I PLUGIN_DEFINES.INC}
unit OSDbUnit;

interface

uses
  libxmlparser, SyncObjs;

const
  OSDbURLnormal : String = 'http://api.opensubtitles.org:80/xml-rpc';
  OSDbURLsecure : String = 'https://api.opensubtitles.org:443/xml-rpc';


type
  TSubPluginRecord =
  Record
    Status        : Integer;
    FileName      : PChar;
    PrefLanguages : PChar;
    SubData       : PChar;
  End;
  PSubPluginRecord = ^TSubPluginRecord;

  TOSDbLoginRecord =
  Record
    Token                 : String;
    Status                : Integer;
    IDUser                : Integer;
    UserNickName          : WideString;
    UserRank              : WideString;
    UploadCnt             : Integer;
    UserPreferedLanguages : String;
    DownloadCnt           : Integer;
    UserWebLanguage       : String;
  End;
  POSDbLoginRecord = ^TOSDbLoginRecord;

  {TOSDbSubEntryRecord =
  Record
    seISO639          : String; // Country ID
    seLanguageName    : String; // Language name
    seSubEncoding     : String; // Character encoding
    seZipDownloadLink : String; // Download URL of ZIP archive containing subtitle
  End;
  POSDbSubEntryRecord = ^TOSDbSubEntryRecord;}

  TStayAliveDataRecord =
  Record
    Status : Integer; // 406 = not logged in
  End;

  PStayAliveDataRecord = ^TStayAliveDataRecord;

  function  OSDb_Login(sUsername, sPassword, sLanguage, sUserAgent : String; var LoginData : POSDbLoginRecord; Secure : Boolean) : HResult;
  function  OSDb_LogOut(sToken, sUserAgent: String; Secure : Boolean) : HResult;
  function  OSDb_SearchSubtitles(sToken, sUserAgent, sMovieHash: string; iMovieByteSize: Int64; var SubSearchData : PSubPluginRecord; Secure : Boolean) : HResult;
  function  OSDb_StayAlive(sToken, sUserAgent: String; StayAliveData : PStayAliveDataRecord; Secure : Boolean) : HResult;
  function  GetXMLValue(XmlParser : TXMLParser) : String;
  procedure GetMemberValues(XmlParser : TXmlParser; var Name, Value : String);


var
  csStayAlive : TCriticalSection;


implementation


uses misc_utils_unit, sysutils, windows, classes;


procedure GetMemberValues(XmlParser : TXmlParser; var Name, Value : String);
begin
  Name  := '';
  Value := '';
  If XmlParser.Scan = True then
  Begin
    If CompareText(XmlParser.CurName,'name') = 0 then
    Begin
      If XmlParser.Scan = True then Name := XmlParser.CurContent;
      XmlParser.Scan; // end tag
    End;
    If XmlParser.Scan = True then
    Begin
      If CompareText(XmlParser.CurName,'value') = 0 then
      Begin
        XmlParser.Scan; // <string>
        If Lowercase(XmlParser.CurName) <> 'struct' then
        Begin
          If XmlParser.CurPartType <> ptEmptyTag then
          Begin
            If XmlParser.Scan = True then Value := XmlParser.CurContent;
            XmlParser.Scan; // end tag <string>
          End;
          XmlParser.Scan; // end tag <value>
        End;
      End;
    End;
  End;
end;


function GetXMLValue(XmlParser : TXMLParser) : String;
begin
  XmlParser.Scan; // </name>
  XmlParser.Scan; // <value>
  XmlParser.Scan; // <string>
  XmlParser.Scan; //  value
  Result := XmlParser.CurContent;
end;



function OSDb_Login(sUsername, sPassword, sLanguage, sUserAgent : String; var LoginData : POSDbLoginRecord; Secure : Boolean) : HResult;
const
  LOG_IN =
    '<?xml version="1.0"?>' +
    '<methodCall>'+
      '<methodName>LogIn</methodName>'+
      '<params>'+
        '<param>'+
          '<value><string>%0:s</string></value>'+
        '</param>'+
        '<param>'+
          '<value><string>%1:s</string></value>'+
        '</param>'+
        '<param>'+
          '<value><string>%2:s</string></value>'+
        '</param>'+
        '<param>'+
          '<value><string>%3:s</string></value>'+
        '</param>'+
      '</params>'+
    '</methodCall>';
var
  sURL      : String;
  sResult   : String;
  XmlParser : TXmlParser;
  ErrCode   : Boolean;
  mName     : String;
  mValue    : String;


begin
  {$IFDEF LOCALTRACE}DebugMsgFT(logPath,'*** OSDb_Login begin');{$ENDIF}
  Result := E_FAIL;
  If Secure = True then sURL := OSDbURLsecure else sURL := OSDbURLnormal;
  sResult := XML_RPC(sURL,sUserAgent,Format(LOG_IN,[sUsername,sPassword,sLanguage,sUserAgent]),Secure);
  {sResult := '<?xml version="1.0" encoding="utf-8"?>'+
             '<methodResponse>'+
               '<params>'+
                 '<param>'+
                   '<value>'+
                     '<struct>'+
                       '<member>'+
                         '<name>token</name>'+
                         '<value><string>xxxxx-xxxxxxxxxxxxxxxxxxxxx</string></value>'+
                       '</member>'+
                       '<member>'+
                         '<name>status</name>'+
                         '<value><string>200 OK</string></value>'+
                       '</member>'+
                       '<member>'+
                         '<name>data</name>'+
                         '<value>'+
                           '<struct>'+
                             '<member>'+
                               '<name>IDUser</name>'+
                               '<value><string>1234567</string></value>'+
                             '</member>'+
                             '<member>'+
                               '<name>UserNickName</name>'+
                               '<value><string>Inmatrix</string></value>'+
                             '</member>'+
                             '<member>'+
                               '<name>UserRank</name>'+
                               '<value><string>app developer</string></value>'+
                             '</member>'+
                             '<member>'+
                               '<name>UploadCnt</name>'+
                               '<value><string>1234</string></value>'+
                             '</member>'+
                             '<member>'+
                               '<name>UserPreferedLanguages</name>'+
                               '<value><string/></value>'+
                             '</member>'+
                             '<member>'+
                               '<name>DownloadCnt</name>'+
                               '<value><string>4321</string></value>'+
                             '</member>'+
                             '<member>'+
                               '<name>UserWebLanguage</name>'+
                               '<value><string>en</string></value>'+
                             '</member>'+
                           '</struct>'+
                         '</value>'+
                       '</member>'+
                       '<member>'+
                         '<name>seconds</name>'+
                         '<value><double>0.026</double></value>'+
                       '</member>'+
                     '</struct>'+
                   '</value>'+
                 '</param>'+
               '</params>'+
             '</methodResponse>';}

  If sResult <> '' then
  Begin
    // Parse results
    XmlParser := TXmlParser.Create;
    XmlParser.Normalize := True;
    XmlParser.LoadFromBuffer(PChar(sResult));

    If XmlParser.Scan = True then
    Begin
      If XmlParser.CurPartType = ptXmlProlog then
      Begin
        // XML format validated
        If XmlParser.Scan = True then
        Begin
          If CompareText(XmlParser.CurName,'methodResponse') = 0 then
          Begin
            Repeat
              ErrCode := XmlParser.Scan;
              If (CompareText(XmlParser.CurName,'member') = 0) and (XmlParser.CurPartType in [ptStartTag]) then
              Begin
                GetMemberValues(XmlParser,mName,mValue);
                mName := Lowercase(mName);
                If mName = 'token' then
                Begin
                  LoginData^.Token := mValue;
                End
                  else
                If mName = 'status' then
                Begin
                  LoginData^.Status := StrToIntDef(Copy(mValue,1,3),E_FAIL);
                  If LoginData^.Status = 200 then Result := S_OK;
                End
                  else
                If mName = 'iduser' then
                Begin
                  LoginData^.IDUser := StrToIntDef(mValue,0);
                End
                  else
                If mName = 'usernickname' then
                Begin
                  LoginData^.UserNickName := UTF8Decode(mValue);
                End
                  else
                If mName = 'userrank' then
                Begin
                  LoginData^.UserRank := UTF8Decode(mValue);
                End
                  else
                If mName = 'uploadcnt' then
                Begin
                  LoginData^.UploadCnt := StrToIntDef(mValue,0);
                End
                  else
                If mName = 'downloadcnt' then
                Begin
                  LoginData^.DownloadCnt := StrToIntDef(mValue,0);
                End
                  else
                If mName = 'userpreferedlanguages' then
                Begin
                  LoginData^.UserPreferedLanguages := mValue;
                End
                  else
                If mName = 'userweblanguage' then
                Begin
                  LoginData^.UserWebLanguage := mValue;
                End;
              End;
            Until (ErrCode = False) or ((XmlParser.CurName = 'methodResponse') and (XmlParser.CurPartType = ptEndTag));
          End;
        End;
      End;

      {Case XmlParser.CurPartType of
        ptXmlProlog : ;
        ptStartTag,
        ptEmptyTag  :
        ptEndTag    : Break;
      End;}
    End;

    {$IFDEF LOCALTRACE}
    DebugMsgFT(logPath,'Token                 : '+LoginData^.Token);
    DebugMsgFT(logPath,'Status                : '+IntToStr(LoginData^.Status));
    DebugMsgFT(logPath,'IDUser                : '+IntToStr(LoginData^.IDUser));
    DebugMsgFT(logPath,'UserNickName          : '+LoginData^.UserNickName);
    DebugMsgFT(logPath,'UserRank              : '+LoginData^.UserRank);
    DebugMsgFT(logPath,'UploadCnt             : '+IntToStr(LoginData^.UploadCnt));
    DebugMsgFT(logPath,'DownloadCnt           : '+IntToStr(LoginData^.DownloadCnt));
    DebugMsgFT(logPath,'UserPreferedLanguages : '+LoginData^.UserPreferedLanguages);
    DebugMsgFT(logPath,'UserWebLanguage       : '+LoginData^.UserWebLanguage);
    {$ENDIF}
    XmlParser.Free;
  End
  {$IFDEF LOCALTRACE}Else DebugMsgFT(logPath,'Zero length reply'){$ENDIF};



  {$IFDEF LOCALTRACE}DebugMsgFT(logPath,'*** OSDb_Login end'+CRLF{+sResult});{$ENDIF}
end;


function OSDb_LogOut(sToken, sUserAgent: String; Secure : Boolean) : HResult;
const
  LOG_OUT =
    '<?xml version="1.0"?>'+
    '<methodCall>'+
      '<methodName>LogOut</methodName>'+
      '<params>'+
      '<param>'+
        '<value><string>%0:s</string></value>'+
        '</param>'+
      '</params>'+
    '</methodCall>';
var
  sURL      : String;
  sResult   : String;
begin
  Result := S_OK;
  If Secure = True then sURL := OSDbURLsecure else sURL := OSDbURLnormal;
  sResult := XML_RPC(sURL,sUserAgent,Format(LOG_OUT,[sToken]),Secure);
  {$IFDEF LOCALTRACE}DebugMsgFT(logPath,'*** OSDb_LogOut:'+CRLF+CRLF{+sResult});{$ENDIF}
end;


function OSDb_SearchSubtitles(sToken, sUserAgent, sMovieHash: string; iMovieByteSize: Int64; var SubSearchData : PSubPluginRecord; Secure : Boolean) : HResult;
const
  SEARCH_SUBTITLES = '<?xml version="1.0"?>'+
                     '<methodCall>'+
                     '<methodName>SearchSubtitles</methodName>'+
                     '<params>'+
                       '<param>'+
                         '<value><string>%0:s</string></value>'+
                       '</param>'+
                       '<param>'+
                         '<value>'+
                           '<array>'+
                             '<data>'+
                               '<value>'+
                                 '<struct>'+
                                   '<member>'+
                                     '<name>sublanguageid</name>'+
                                     '<value><string>%1:s</string></value>'+
                                   '</member>'+
                                   '<member>'+
                                     '<name>moviehash</name>'+
                                     '<value><string>%2:s</string></value>'+
                                   '</member>'+
                                   '<member>'+
                                     '<name>moviebytesize</name>'+
                                     '<value><double>%3:s</double></value>'+
                                   '</member>'+
                                 '</struct>'+
                               '</value>'+
                             '</data>'+
                           '</array>'+
                         '</value>'+
                       '</param>'+
                     '</params>'+
                     '</methodCall>';

var
  sURL                : String;
  sResult             : String;
  mName               : String;
  mValue              : String;
  sList               : TStringList;
  XmlParser           : TXmlParser;
  ErrCode             : Boolean;
  sISO639             : String; // Country ID
  sLanguageName       : String; // Language name
  sSubEncoding        : String; // Character encoding
  sZipDownloadLink    : String; // Download URL of ZIP archive containing subtitle
  sSubData            : String;
  sMovieReleaseName   : String;
  sSubFileName        : String;
  sSubFormat          : String;
  sSubRating          : String;
  sSubHearingImpaired : String;
  S                   : String;
begin
  {$IFDEF LOCALTRACE}DebugMsgFT(logPath,'*** OSDb_SearchSubtitles begin');{$ENDIF}
  Result              := E_FAIL;
  sMovieReleaseName   := '';
  sLanguageName       := '';
  sISO639             := '';
  sSubFileName        := '';
  sSubFormat          := '';
  sSubEncoding        := '';
  sSubRating          := '';
  sSubHearingImpaired := '';
  sZipDownloadLink    := '';
  If Secure = True then sURL := OSDbURLsecure else sURL := OSDbURLnormal;
  sResult := XML_RPC(sURL,sUserAgent,Format(SEARCH_SUBTITLES, [sToken, SubSearchData.PrefLanguages, sMovieHash, IntToStr(iMovieByteSize)]),Secure);

  {sList := TStringList.Create;
  sList.LoadFromFile('c:\log\subsearch.xml');
  sResult := sList.Text;
  sList.Free;}

  If sResult <> '' then
  Begin
    XmlParser := TXmlParser.Create;
    XmlParser.Normalize := True;
    XmlParser.LoadFromBuffer(PChar(sResult));

    If XmlParser.Scan = True then
    Begin
      If XmlParser.CurPartType = ptXmlProlog then
      Begin
        Repeat
          Repeat
            ErrCode := XmlParser.Scan
          Until (CompareText(XmlParser.CurName,'name') = 0) or ((CompareText(XmlParser.CurName,'struct') = 0) and (XmlParser.CurPartType = ptEndTag)) or (ErrCode = False);

          If (CompareText(XmlParser.CurName,'name') = 0) and (ErrCode = True) then
          Begin
            XmlParser.Scan;
            mName := Lowercase(XmlParser.CurContent);
            If mName = 'status' then
            Begin
              mValue := GetXMLValue(XmlParser);
              SubSearchData^.Status := StrToIntDef(Copy(mValue,1,3),E_FAIL);
              {$IFDEF LOCALTRACE}DebugMsgFT(logPath,'Status          : '+Copy(mValue,1,3));{$ENDIF}
            End
              else
            If mName = 'iso639' then
            Begin
              sISO639 := GetXMLValue(XmlParser);
            End
              else
            If mName = 'languagename' then
            Begin
              sLanguageName := GetXMLValue(XmlParser);
            End
              else
            If mName = 'subencoding' then
            Begin
              sSubEncoding := GetXMLValue(XmlParser);
            End
              else
            If mName = 'zipdownloadlink' then
            Begin
              sZipDownloadLink := GetXMLValue(XmlParser);
            End
              else
            If mName = 'moviereleasename' then
            Begin
              sMovieReleaseName := GetXMLValue(XmlParser);
            End
              else
            If mName = 'subfilename' then
            Begin
              sSubFileName := GetXMLValue(XmlParser);
            End
              else
            If mName = 'subformat' then
            Begin
              sSubFormat := GetXMLValue(XmlParser);
            End
              else
            If mName = 'subrating' then
            Begin
              sSubRating := GetXMLValue(XmlParser);
            End
              else
            If mName = 'subhearingimpaired' then
            Begin
              sSubHearingImpaired := GetXMLValue(XmlParser);
            End
          End
            else
          Begin
            If (sISO639 <> '') and (sZipDownloadLink <> '') then
            Begin
              S := '"MovieReleaseName='  +sMovieReleaseName+'",'+
                   '"LanguageName='      +sLanguageName+'",'+
                   '"ISO639='            +sISO639+'",'+
                   '"SubFileName='       +sSubFileName+'",'+
                   '"SubFormat='         +sSubFormat+'",'+
                   '"SubEncoding='       +sSubEncoding+'",'+
                   '"SubRating='         +sSubRating+'",'+
                   '"SubHearingImpaired='+sSubHearingImpaired+'",'+
                   '"ZipDownloadLink='   +sZipDownloadLink+'"';

              If sSubData = '' then sSubData := S else sSubData := sSubData+'|'+S;
              {$IFDEF LOCALTRACE}
              DebugMsgFT(logPath,'MovieReleaseName   : '+sMovieReleaseName);
              DebugMsgFT(logPath,'LanguageName       : '+sLanguageName);
              DebugMsgFT(logPath,'ISO639             : '+sISO639);
              DebugMsgFT(logPath,'SubFileName        : '+sSubFileName);
              DebugMsgFT(logPath,'SubFormat          : '+sSubFormat);
              DebugMsgFT(logPath,'SubEncoding        : '+sSubEncoding);
              DebugMsgFT(logPath,'SubRating          : '+sSubRating);
              DebugMsgFT(logPath,'SubHearingImpaired : '+sSubHearingImpaired);
              DebugMsgFT(logPath,'ZipDownloadLink    : '+sZipDownloadLink+CRLF);
              {$ENDIF}
              sMovieReleaseName   := '';
              sLanguageName       := '';
              sISO639             := '';
              sSubFileName        := '';
              sSubFormat          := '';
              sSubEncoding        := '';
              sSubRating          := '';
              sSubHearingImpaired := '';
              sZipDownloadLink    := '';
            End;
          End;
        Until ErrCode = False;
      End;
    End;

    If sSubData <> '' then
    Begin
      {sList := TStringList.Create;
      sList.Text := sResult;
      sList.SaveToFile('d:\test.txt');}
      Result                 := S_OK;
      SubSearchData^.SubData := PChar(sSubData);
    End;

    XmlParser.Free;
  End
  {$IFDEF LOCALTRACE}Else DebugMsgFT(logPath,'Zero length reply'){$ENDIF};


  {$IFDEF LOCALTRACE}DebugMsgFT(logPath,'*** OSDb_SearchSubtitles end'{+sResult});{$ENDIF}
end;


function OSDb_StayAlive(sToken, sUserAgent: String; StayAliveData : PStayAliveDataRecord; Secure : Boolean) : HResult;
const
  KEEP_ALIVE =
    '<?xml version="1.0"?>'+
    '<methodCall>'+
      '<methodName>NoOperation</methodName>'+
      '<params>'+
      '<param>'+
        '<value><string>%0:s</string></value>'+
        '</param>'+
      '</params>'+
    '</methodCall>';
var
  sURL    : String;
  sResult : String;
  XmlParser : TXmlParser;
  ErrCode   : Boolean;
  mName     : String;
  mValue    : String;
begin
  Result := E_FAIL;
  If Secure = True then sURL := OSDbURLsecure else sURL := OSDbURLnormal;
  sResult := XML_RPC(sURL,sUserAgent,Format(KEEP_ALIVE,[sToken]),Secure);

  If sResult <> '' then
  Begin
    XmlParser := TXmlParser.Create;
    XmlParser.Normalize := True;
    XmlParser.LoadFromBuffer(PChar(sResult));

    If XmlParser.Scan = True then
    Begin
      If XmlParser.CurPartType = ptXmlProlog then
      Begin
        Repeat
          Repeat
            ErrCode := XmlParser.Scan;
          Until (CompareText(XmlParser.CurName,'name') = 0) or ((CompareText(XmlParser.CurName,'struct') = 0) and (XmlParser.CurPartType = ptEndTag)) or (ErrCode = False);

          If (CompareText(XmlParser.CurName,'name') = 0) and (ErrCode = True) then
          Begin
            XmlParser.Scan;
            mName := Lowercase(XmlParser.CurContent);
            If mName = 'status' then
            Begin
              mValue := GetXMLValue(XmlParser);
              csStayAlive.Enter;
              Try
                StayAliveData^.Status := StrToIntDef(Copy(mValue,1,3),E_FAIL);
              Finally
                csStayAlive.Leave;
              End;
              {$IFDEF LOCALTRACE}DebugMsgFT(logPath,'Status          : '+Copy(mValue,1,3));{$ENDIF}
            End
              else;
          End;
        Until ErrCode = False;
      End;
    End;
  End;

  {$IFDEF LOCALTRACE}DebugMsgFT(logPath,'*** OSDb_StayAlive:'+CRLF+CRLF{+sResult});{$ENDIF}
end;


initialization
  csStayAlive := TCriticalSection.Create;

finalization
  csStayAlive.Free;

end.






