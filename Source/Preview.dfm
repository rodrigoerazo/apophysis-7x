object PreviewForm: TPreviewForm
  Left = 336
  Top = 228
  Width = 212
  Height = 181
  BorderIcons = [biSystemMenu, biMinimize]
  BorderStyle = bsSizeToolWin
  Caption = 'Preview'
  Color = clBtnFace
  Font.Charset = DEFAULT_CHARSET
  Font.Color = clWindowText
  Font.Height = -11
  Font.Name = 'MS Sans Serif'
  Font.Style = []
  OldCreateOrder = False
  Position = poDefaultPosOnly
  OnClose = FormClose
  OnCreate = FormCreate
  OnDestroy = FormDestroy
  OnKeyPress = FormKeyPress
  PixelsPerInch = 96
  TextHeight = 13
  object BackPanel: TPanel
    Left = 0
    Top = 0
    Width = 204
    Height = 154
    Align = alClient
    BevelInner = bvLowered
    BevelOuter = bvLowered
    Color = clBlack
    TabOrder = 0
    object Image: TImage
      Left = 2
      Top = 2
      Width = 200
      Height = 150
      Align = alClient
      AutoSize = True
      Stretch = True
    end
  end
end