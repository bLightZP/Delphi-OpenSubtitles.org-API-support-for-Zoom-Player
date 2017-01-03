object ConfigForm: TConfigForm
  Left = 701
  Top = 352
  BorderStyle = bsDialog
  Caption = 'OpenSubtitles.org : configuration'
  ClientHeight = 238
  ClientWidth = 417
  Color = clBtnFace
  Font.Charset = DEFAULT_CHARSET
  Font.Color = clWindowText
  Font.Height = -11
  Font.Name = 'MS Sans Serif'
  Font.Style = []
  KeyPreview = True
  OldCreateOrder = False
  OnCreate = FormCreate
  OnKeyPress = FormKeyPress
  PixelsPerInch = 96
  TextHeight = 13
  object InfoLabel: TTntLabel
    Left = 12
    Top = 12
    Width = 393
    Height = 87
    AutoSize = False
    WordWrap = True
  end
  object LabelUsername: TTntLabel
    Left = 91
    Top = 117
    Width = 51
    Height = 13
    Caption = 'Username:'
  end
  object LabelPassword: TTntLabel
    Left = 91
    Top = 149
    Width = 49
    Height = 13
    Caption = 'Password:'
  end
  object OKButton: TButton
    Left = 329
    Top = 195
    Width = 75
    Height = 30
    Caption = 'OK'
    ModalResult = 1
    TabOrder = 0
  end
  object CancelButton: TButton
    Left = 12
    Top = 195
    Width = 75
    Height = 30
    Caption = 'Cancel'
    ModalResult = 2
    TabOrder = 1
  end
  object RegisterButton: TButton
    Left = 160
    Top = 195
    Width = 97
    Height = 30
    Caption = 'Register'
    TabOrder = 2
    OnClick = RegisterButtonClick
  end
  object UsernameEdit: TTntEdit
    Left = 160
    Top = 114
    Width = 152
    Height = 21
    TabOrder = 3
  end
  object PasswordEdit: TTntEdit
    Left = 160
    Top = 146
    Width = 152
    Height = 21
    TabOrder = 4
    OnChange = PasswordEditChange
  end
end
