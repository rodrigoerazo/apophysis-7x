unit GradientHlpr;

interface

uses
  windows, Graphics, Cmap;

const
  PixelCountMax = 32768;

type
  pRGBTripleArray = ^TRGBTripleArray;
  TRGBTripleArray = array[0..PixelCountMax - 1] of TRGBTriple;

type
  TGradientHelper = class
  private
    procedure RGBBlend(a, b: integer; var Palette: TColorMap);
  public
    function GetGradientBitmap(Index: integer; const hue_rotation: double): TBitmap;
    function RandomGradient: TColorMap;
  end;

var
  GradientHelper: TGradientHelper;

implementation

uses
  Global;

{ TGradientHelper }

function TGradientHelper.GetGradientBitmap(Index: integer; const hue_rotation: double): TBitmap;
var
  BitMap: TBitMap;
  i, j: integer;
  Row: pRGBTripleArray;
  pal: TColorMap;
begin
  GetCMap(index, hue_rotation, pal);

  BitMap := TBitMap.create;
  Bitmap.PixelFormat := pf24bit;
  BitMap.Width := 256;
  BitMap.Height := 2;

  for j := 0 to Bitmap.Height - 1 do begin
    Row := Bitmap.Scanline[j];
    for i := 0 to Bitmap.Width - 1 do begin
      Row[i].rgbtRed := Pal[i][0];
      Row[i].rgbtGreen := Pal[i][1];
      Row[i].rgbtBlue := Pal[i][2];
    end
  end;

  Result := BitMap;
end;

///////////////////////////////////////////////////////////////////////////////
function TGradientHelper.RandomGradient: TColorMap;
var
  a, b, n, nodes: integer;
  rgb: array[0..2] of double;
  hsv: array[0..2] of double;
  pal: TColorMap;
begin
  inc(MainSeed);
  RandSeed := Mainseed;
  nodes := random((MaxNodes - 1) - (MinNodes - 2)) + (MinNodes - 1);
  n := 256 div nodes;
  b := 0;
  hsv[0] := (random(MaxHue - (MinHue - 1)) + MinHue) / 100;
  hsv[1] := (random(MaxSat - (MinSat - 1)) + MinSat) / 100;
  hsv[2] := (random(MaxLum - (MinLum - 1)) + MinLum) / 100;
  hsv2rgb(hsv, rgb);
  Pal[0][0] := Round(rgb[0] * 255);
  Pal[0][1] := Round(rgb[1] * 255);
  Pal[0][2] := Round(rgb[2] * 255);
  repeat
    a := b;
    b := b + n;
    hsv[0] := (random(MaxHue - (MinHue - 1)) + MinHue) / 100;
    hsv[1] := (random(MaxSat - (MinSat - 1)) + MinSat) / 100;
    hsv[2] := (random(MaxLum - (MinLum - 1)) + MinLum) / 100;
    hsv2rgb(hsv, rgb);
    if b > 255 then b := 255;
    Pal[b][0] := Round(rgb[0] * 255);
    Pal[b][1] := Round(rgb[1] * 255);
    Pal[b][2] := Round(rgb[2] * 255);
    RGBBlend(a, b, pal);
  until b = 255;
  Result := Pal;
end;

///////////////////////////////////////////////////////////////////////////////
procedure TGradientHelper.RGBBlend(a, b: integer; var Palette: TColorMap);
{ Linear blend between to indices of a palette }
var
  c, v: real;
  vrange, range: real;
  i: integer;
begin
  if a = b then
  begin
    Exit;
  end;
  range := b - a;
  vrange := Palette[b mod 256][0] - Palette[a mod 256][0];
  c := Palette[a mod 256][0];
  v := vrange / range;
  for i := (a + 1) to (b - 1) do
  begin
    c := c + v;
    Palette[i mod 256][0] := Round(c);
  end;
  vrange := Palette[b mod 256][1] - Palette[a mod 256][1];
  c := Palette[a mod 256][1];
  v := vrange / range;
  for i := a + 1 to b - 1 do
  begin
    c := c + v;
    Palette[i mod 256][1] := Round(c);
  end;
  vrange := Palette[b mod 256][2] - Palette[a mod 256][2];
  c := Palette[a mod 256][2];
  v := vrange / range;
  for i := a + 1 to b - 1 do
  begin
    c := c + v;
    Palette[i mod 256][2] := Round(c);
  end;
end;

///////////////////////////////////////////////////////////////////////////////
initialization
  GradientHelper := TGradientHelper.create;
finalization
  GradientHelper.Free;
end.
