{$I SCRAPER_DEFINES.INC}

unit configformunit;

interface

uses
  Windows, Messages, SysUtils, Variants, Classes, Graphics, Controls, Forms,
  Dialogs, StdCtrls, TntStdCtrls;

type
  TConfigForm = class(TForm)
    OKButton: TButton;
    CancelButton: TButton;
    InfoLabel: TTntLabel;
    RegisterButton: TButton;
    LabelUsername: TTntLabel;
    LabelPassword: TTntLabel;
    UsernameEdit: TTntEdit;
    PasswordEdit: TTntEdit;
    procedure FormKeyPress(Sender: TObject; var Key: Char);
    procedure FormCreate(Sender: TObject);
    procedure RegisterButtonClick(Sender: TObject);
    procedure PasswordEditChange(Sender: TObject);
  private
    { Private declarations }
  public
    { Public declarations }
  end;

var
  ConfigForm: TConfigForm = nil;

implementation

{$R *.dfm}

uses shellapi;


procedure TConfigForm.FormKeyPress(Sender: TObject; var Key: Char);
begin
  If Key = #27 then
  Begin
    Key := #0;
    Close;
  End;
end;


procedure TConfigForm.FormCreate(Sender: TObject);
begin
  InfoLabel.Caption :=
    'OpenSubtitles.org allows for limited anonymous subtitle downloads. However, if you connecting through a proxy or router that uses the same outward facing IP address, '+
    'other people on the same network may reduce your quota further.'#10#10+
    'To download up to 200 subtitles per day, click the register button and sign up for a free user account.';

  PasswordEdit.PasswordChar := '*';   
end;


procedure TConfigForm.RegisterButtonClick(Sender: TObject);
begin
  ShellExecute(Handle,'open','http://www.opensubtitles.org/en/newuser',nil,nil,SW_SHOWNORMAL);
end;

procedure TConfigForm.PasswordEditChange(Sender: TObject);
begin
  PasswordEdit.Tag := 1;
end;

end.
