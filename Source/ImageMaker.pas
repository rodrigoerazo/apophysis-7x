unit ImageMaker;

interface

uses
  Windows, Graphics, ControlPoint, RenderTypes, PngImage;

type TPalette = record
    logpal : TLogPalette;
    colors: array[0..255] of TPaletteEntry;
  end;

type
  TImageMaker = class
  private
    FOversample: Integer;
    FFilterSize: Integer;
    FFilter: array of array of double;

    FBitmap: TBitmap;
    FAlphaBitmap: TBitmap;
    AlphaPalette: TPalette;
    FTransparentImage: TBitmap;

    FCP: TControlPoint;

    FBucketHeight: integer;
    FBucketWidth: integer;

    FBuckets64: TBucket64Array;
    FBuckets48: TBucket48Array;
    FBuckets32: TBucket32Array;
    FBuckets32f: TBucket32fArray;

    FOnProgress: TOnProgress;

    FGetBucket: function(x, y: integer): TBucket64 of object;
    function GetBucket64(x, y: integer): TBucket64;
    function GetBucket48(x, y: integer): TBucket64;
    function GetBucket32(x, y: integer): TBucket64;
    function GetBucket32f(x, y: integer): TBucket64;
    function SafeGetBucket(x, y: integer): TBucket64;

    procedure CreateFilter;
    procedure NormalizeFilter;

  public
    constructor Create;
    destructor Destroy; override;

    function GetImage: TBitmap;
    function GetTransparentImage: TPNGObject;

    procedure SetCP(CP: TControlPoint);
    procedure Init;
    procedure SetBucketData(const Buckets: pointer; BucketWidth, BucketHeight: integer; bits: integer);

    function GetFilterSize: Integer;

    procedure CreateImage(YOffset: integer = 0);
    procedure SaveImage(FileName: String);

    procedure GetBucketStats(var Stats: TBucketStats);

    property OnProgress: TOnProgress
//      read FOnProgress
       write FOnProgress;
  end;

implementation

uses
  Math, SysUtils, JPEG, Global, Types;

{ TImageMaker }

type
  TRGB = packed Record
    blue: byte;
    green: byte;
    red: byte;
  end;

  PByteArray = ^TByteArray;
  TByteArray = array[0..0] of byte;
//  PLongintArray = ^TLongintArray;
//  TLongintArray = array[0..0] of Longint;
  PRGBArray = ^TRGBArray;
  TRGBArray = array[0..0] of TRGB;

///////////////////////////////////////////////////////////////////////////////
constructor TImageMaker.Create;
var
  i: integer;
begin
  AlphaPalette.logpal.palVersion := $300;
  AlphaPalette.logpal.palNumEntries := 256;
  for i := 0 to 255 do
    with AlphaPalette.logpal.palPalEntry[i] do begin
      peRed := i;
      peGreen := i;
      peBlue := i;
    end;
end;

///////////////////////////////////////////////////////////////////////////////
destructor TImageMaker.Destroy;
begin
  if assigned(FBitmap) then
    FBitmap.Free;

  if assigned(FAlphaBitmap) then
    FAlphaBitmap.Free;

  if assigned(FTransparentImage) then
    FTransparentImage.Free;

  inherited;
end;

///////////////////////////////////////////////////////////////////////////////
procedure TImageMaker.CreateFilter;
var
  i, j: integer;
  fw: integer;
  adjust: double;
  ii, jj: double;
begin
  FOversample := fcp.spatial_oversample;
  fw := Trunc(2.0 * FILTER_CUTOFF * FOversample * fcp.spatial_filter_radius);
  FFilterSize := fw + 1;

  // make sure it has same parity as oversample
  if odd(FFilterSize + FOversample) then
    inc(FFilterSize);

  if (fw > 0.0) then
  	adjust := (1.0 * FILTER_CUTOFF * FFilterSize) / fw
  else
  	adjust := 1.0;

  setLength(FFilter, FFilterSize, FFilterSize);
  for i := 0 to FFilterSize - 1 do begin
    for j := 0 to FFilterSize - 1 do begin
      ii := ((2.0 * i + 1.0)/ FFilterSize - 1.0) * adjust;
      jj := ((2.0 * j + 1.0)/ FFilterSize - 1.0) * adjust;

      FFilter[i, j] :=  exp(-2.0 * (ii * ii + jj * jj));
    end;
  end;

  Normalizefilter;
end;

///////////////////////////////////////////////////////////////////////////////
procedure TImageMaker.NormalizeFilter;
var
  i, j: integer;
  t: double;
begin
  t := 0;
  for i := 0 to FFilterSize - 1 do
    for j := 0 to FFilterSize - 1 do
      t := t + FFilter[i, j];

  for i := 0 to FFilterSize - 1 do
    for j := 0 to FFilterSize - 1 do
      FFilter[i, j] := FFilter[i, j] / t;
end;

///////////////////////////////////////////////////////////////////////////////
function TImageMaker.GetFilterSize: Integer;
begin
  Result := FFiltersize;
end;

///////////////////////////////////////////////////////////////////////////////
function TImageMaker.GetImage: TBitmap;
begin
//  if ShowTransparency then
//    Result := GetTransparentImage
//  else
    Result := FBitmap;
end;

///////////////////////////////////////////////////////////////////////////////
procedure TImageMaker.Init;
begin
  if not Assigned(FBitmap) then
    FBitmap := TBitmap.Create;

  FBitmap.PixelFormat := pf24bit;

  FBitmap.Width := Fcp.Width;
  FBitmap.Height := Fcp.Height;

  if not Assigned(FAlphaBitmap) then
    FAlphaBitmap := TBitmap.Create;

  FAlphaBitmap.PixelFormat := pf8bit;
  FAlphaBitmap.Width := Fcp.Width;
  FAlphaBitmap.Height := Fcp.Height;

  CreateFilter;
end;

///////////////////////////////////////////////////////////////////////////////
procedure TImageMaker.SetBucketData(const Buckets: pointer; BucketWidth, BucketHeight: integer; bits: integer);
begin
  FBuckets64 := TBucket64Array(Buckets);
  FBuckets48 := TBucket48Array(Buckets);
  FBuckets32f := TBucket32fArray(Buckets);
  FBuckets32 := TBucket32Array(Buckets);

  FBucketWidth := BucketWidth;
  FBucketHeight := BucketHeight;

  case bits of
    BITS_32:  FGetBucket := GetBucket32;
    BITS_32f: FGetBucket := GetBucket32f;
    BITS_48:  FGetBucket := GetBucket48;
    BITS_64:  FGetBucket := GetBucket64;
    else assert(false);
  end;
end;

///////////////////////////////////////////////////////////////////////////////
procedure TImageMaker.SetCP(CP: TControlPoint);
begin
  Fcp := CP;
end;

///////////////////////////////////////////////////////////////////////////////
procedure TImageMaker.CreateImage(YOffset: integer);
var
  gamma: double;
  i, j: integer;
  alpha: double;
  ri, gi, bi: Integer;
  ai, ia: integer;
  bgtot, zero_BG: TRGB;
  ls: double;
  ii, jj: integer;
  fp: array[0..3] of double;
  Row: PRGBArray;
  AlphaRow: PbyteArray;
  vib, notvib: Integer;
  bgi: array[0..2] of Integer;
//  bucketpos: Integer;
  filterValue: double;
//  filterpos: Integer;
  lsa: array[0..1024] of double;
  sample_density: extended;
  gutter_width: integer;
  k1, k2: double;
  area: double;
  frac, funcval: double;

  GetBucket: function(x, y: integer): TBucket64 of object;
  bucket: TBucket64;
  bx, by: integer;
  label zero_alpha;
begin
  if fcp.gamma = 0 then
    gamma := fcp.gamma
  else
    gamma := 1 / fcp.gamma;
  vib := round(fcp.vibrancy * 256.0);
  notvib := 256 - vib;

  if fcp.gamma_threshold <> 0 then
    funcval := power(fcp.gamma_threshold, gamma - 1); { / fcp.gamma_threshold; }

  bgi[0] := round(fcp.background[0]);
  bgi[1] := round(fcp.background[1]);
  bgi[2] := round(fcp.background[2]);
  bgtot.red := bgi[0];
  bgtot.green := bgi[1];
  bgtot.blue := bgi[2];
  zero_BG.red := 0;
  zero_BG.green := 0;
  zero_BG.blue := 0;

  gutter_width := FBucketwidth - FOversample * fcp.Width;
//  gutter_width := 2 * ((25 - Foversample) div 2);
  if(FFilterSize <= gutter_width div 2) then // filter too big when 'post-processing' ?
    GetBucket := FGetBucket
  else
    GetBucket := SafeGetBucket;

  FBitmap.PixelFormat := pf24bit;

  sample_density := fcp.actual_density * sqr( power(2, fcp.zoom) );
  if sample_density = 0 then sample_density := 0.001;
  k1 := (fcp.Contrast * BRIGHT_ADJUST * fcp.brightness * 268 * PREFILTER_WHITE) / 256.0;
  area := FBitmap.Width * FBitmap.Height / (fcp.ppux * fcp.ppuy);
  k2 := (FOversample * FOversample) / (fcp.Contrast * area * fcp.White_level * sample_density);

  lsa[0] := 0;
  for i := 1 to 1024 do begin
    lsa[i] := (k1 * log10(1 + fcp.White_level * i * k2)) / (fcp.White_level * i);
  end;

  ls := 0;
  ai := 0;
  //bucketpos := 0;
  by := 0;
  for i := 0 to fcp.Height - 1 do begin
    bx := 0;

    if (i and $3f = 0) and assigned(FOnProgress) then FOnProgress(i / fcp.Height);

    AlphaRow := PByteArray(FAlphaBitmap.scanline[YOffset + i]);
    Row := PRGBArray(FBitmap.scanline[YOffset + i]);
    for j := 0 to fcp.Width - 1 do begin
      if FFilterSize > 1 then begin
        fp[0] := 0;
        fp[1] := 0;
        fp[2] := 0;
        fp[3] := 0;

        for ii := 0 to FFilterSize - 1 do begin
          for jj := 0 to FFilterSize - 1 do begin
            filterValue := FFilter[ii, jj];

            bucket := GetBucket(bx + jj, by + ii);
            if bucket.count < 1024 then
              ls := lsa[bucket.Count]
            else
              ls := (k1 * log10(1 + fcp.White_level * bucket.count * k2)) / (fcp.White_level * bucket.count);

            fp[0] := fp[0] + filterValue * ls * bucket.Red;
            fp[1] := fp[1] + filterValue * ls * bucket.Green;
            fp[2] := fp[2] + filterValue * ls * bucket.Blue;
            fp[3] := fp[3] + filterValue * ls * bucket.Count;
          end;
        end;

        fp[0] := fp[0] / PREFILTER_WHITE;
        fp[1] := fp[1] / PREFILTER_WHITE;
        fp[2] := fp[2] / PREFILTER_WHITE;
        fp[3] := fcp.white_level * fp[3] / PREFILTER_WHITE;
      end else begin
        bucket := GetBucket(bx, by);
        if bucket.count < 1024 then
          ls := lsa[bucket.count] / PREFILTER_WHITE
        else
          ls := (k1 * log10(1 + fcp.White_level * bucket.count * k2)) / (fcp.White_level * bucket.count) / PREFILTER_WHITE;

        fp[0] := ls * bucket.Red;
        fp[1] := ls * bucket.Green;
        fp[2] := ls * bucket.Blue;
        fp[3] := ls * bucket.Count * fcp.white_level;
      end;

      Inc(bx, FOversample);

      if fcp.Transparency then begin // -------------------------- Transparency
        // gamma linearization
        if (fp[3] > 0.0) then begin
          if fp[3] <= fcp.gamma_threshold then begin
            frac := fp[3] / fcp.gamma_threshold;
            alpha := (1 - frac) * fp[3] * funcval + frac * power(fp[3], gamma);
          end
          else
            alpha := power(fp[3], gamma);

          ls := vib * alpha / fp[3];
          ai := round(alpha * 256);
          if (ai <= 0) then goto zero_alpha // ignore all if alpha = 0
          else if (ai > 255) then ai := 255;
          //ia := 255 - ai;
        end
        else begin
zero_alpha:
          Row[j] := zero_BG;
          AlphaRow[j] := 0;
          continue;
        end;

        if (notvib > 0) then begin
          ri := Round(ls * fp[0] + notvib * power(fp[0], gamma));
          gi := Round(ls * fp[1] + notvib * power(fp[1], gamma));
          bi := Round(ls * fp[2] + notvib * power(fp[2], gamma));
        end
        else begin
          ri := Round(ls * fp[0]);
          gi := Round(ls * fp[1]);
          bi := Round(ls * fp[2]);
        end;

        // ignoring BG color in transparent renders...

        ri := (ri * 255) div ai; // ai > 0 !
        if (ri < 0) then ri := 0
        else if (ri > 255) then ri := 255;

        gi := (gi * 255) div ai;
        if (gi < 0) then gi := 0
        else if (gi > 255) then gi := 255;

        bi := (bi * 255) div ai;
        if (bi < 0) then bi := 0
        else if (bi > 255) then bi := 255;

        Row[j].red := ri;
        Row[j].green := gi;
        Row[j].blue := bi;
        AlphaRow[j] := ai;
      end
      else begin // ------------------------------------------- No transparency
        if (fp[3] > 0.0) then begin
          // gamma linearization
          if fp[3] <= fcp.gamma_threshold then begin
            frac := fp[3] / fcp.gamma_threshold;
            alpha := (1 - frac) * fp[3] * funcval + frac * power(fp[3], gamma);
          end
          else
            alpha := power(fp[3], gamma);

          ls := vib * alpha / fp[3];
          ai := round(alpha * 256);
          if (ai < 0) then ai := 0
          else if (ai > 255) then ai := 255;
          ia := 255 - ai;
        end
        else begin
          // no intensity so simply set the BG;
          Row[j] := bgtot;
          continue;
        end;

        if (notvib > 0) then begin
          ri := Round(ls * fp[0] + notvib * power(fp[0], gamma));
          gi := Round(ls * fp[1] + notvib * power(fp[1], gamma));
          bi := Round(ls * fp[2] + notvib * power(fp[2], gamma));
        end
        else begin
          ri := Round(ls * fp[0]);
          gi := Round(ls * fp[1]);
          bi := Round(ls * fp[2]);
        end;

        ri := ri + (ia * bgi[0]) shr 8;
        if (ri < 0) then ri := 0
        else if (ri > 255) then ri := 255;

        gi := gi + (ia * bgi[1]) shr 8;
        if (gi < 0) then gi := 0
        else if (gi > 255) then gi := 255;

        bi := bi + (ia * bgi[2]) shr 8;
        if (bi < 0) then bi := 0
        else if (bi > 255) then bi := 255;

        Row[j].red := ri;
        Row[j].green := gi;
        Row[j].blue := bi;
        AlphaRow[j] := ai;//?
      end
    end;

    //Inc(bucketpos, gutter_width);
    //Inc(bucketpos, (FOversample - 1) * FBucketWidth);
    Inc(by, FOversample);
  end;

  FBitmap.PixelFormat := pf24bit;

  if assigned(FOnProgress) then FOnProgress(1);
end;

///////////////////////////////////////////////////////////////////////////////
procedure TImageMaker.SaveImage(FileName: String);
var
  i,row: integer;
  PngObject: TPngObject;
  rowbm, rowpng: PByteArray;
  JPEGImage: TJPEGImage;
  PNGerror: boolean;
  label BMPhack;
begin
  if UpperCase(ExtractFileExt(FileName)) = '.PNG' then begin
    pngError := false;

    PngObject := TPngObject.Create;
    try
      PngObject.Assign(FBitmap);
      if fcp.Transparency then // PNGTransparency <> 0
      begin
        PngObject.CreateAlpha;
        for i:= 0 to FAlphaBitmap.Height - 1 do begin
          rowbm := PByteArray(FAlphaBitmap.scanline[i]);
          rowpng := PByteArray(PngObject.AlphaScanline[i]);
          for row := 0 to FAlphaBitmap.Width -1 do begin
            rowpng[row] := rowbm[row];
          end;
        end;
      end;
      //else Exception.CreateFmt('Unexpected value of PNGTransparency [%d]', [PNGTransparency]);

      PngObject.SaveToFile(FileName);
    except
      pngError := true;
    end;
    PngObject.Free;

    if pngError then begin
      FileName := ChangeFileExt(FileName, '.bmp');
      goto BMPHack;
    end;

  end else if UpperCase(ExtractFileExt(FileName)) = '.JPG' then begin
    JPEGImage := TJPEGImage.Create;
    JPEGImage.Assign(FBitmap);
    JPEGImage.CompressionQuality := JPEGQuality;
    JPEGImage.SaveToFile(FileName);
    JPEGImage.Free;

//    with TLinearBitmap.Create do
//    try
//      Assign(Renderer.GetImage);
//      JPEGLoader.Default.Quality := JPEGQuality;
//      SaveToFile(RenderForm.FileName);
//    finally
//      Free;
//    end;
  end else begin // bitmap
BMPHack:
    FBitmap.SaveToFile(FileName);
    if fcp.Transparency then begin
      FAlphaBitmap.Palette := CreatePalette(AlphaPalette.logpal);
      FileName := ChangeFileExt(FileName, '_alpha.bmp');
      FAlphaBitmap.SaveToFile(FileName);
    end;
  end;
end;

///////////////////////////////////////////////////////////////////////////////
function TImageMaker.GetTransparentImage: TPngObject;
var
  x, y: integer;
  i, row: integer;
  rowbm, rowpng: PByteArray;
begin
  Result := TPngObject.Create;
  Result.Assign(FBitmap);

  if fcp.Transparency then begin
    Result.CreateAlpha;
    for i:= 0 to FAlphaBitmap.Height - 1 do begin
      rowbm := PByteArray(FAlphaBitmap.scanline[i]);
      rowpng := PByteArray(Result.AlphaScanline[i]);
      for row := 0 to FAlphaBitmap.Width - 1 do begin
        rowpng[row] := rowbm[row];
      end;
    end;
  end;
end;

///////////////////////////////////////////////////////////////////////////////

function TImageMaker.GetBucket64(x, y: integer): TBucket64;
begin
  Result := FBuckets64[y][x];
end;

function TImageMaker.GetBucket32(x, y: integer): TBucket64;
begin
  with FBuckets32[y][x] do begin
    Result.Red   := Red;
    Result.Green := Green;
    Result.Blue  := Blue;
    Result.Count := Count;
  end;
end;

function TImageMaker.GetBucket32f(x, y: integer): TBucket64;
begin
  with FBuckets32f[y][x] do begin
    Result.Red   := round(Red);
    Result.Green := round(Green);
    Result.Blue  := round(Blue);
    Result.Count := round(Count);
  end;
end;

function TImageMaker.GetBucket48(x, y: integer): TBucket64;
begin
  with FBuckets48[y][x] do begin
    Result.Red   := int64(rl) or ( int64(rh) shl 32 );
    Result.Green := int64(gl) or ( int64(gh) shl 32 );
    Result.Blue  := int64(bl) or ( int64(bh) shl 32 );
    Result.Count := int64(cl) or ( int64(ch) shl 32 );
  end;
end;

function TImageMaker.SafeGetBucket(x, y: integer): TBucket64;
begin
  if x < 0 then x := 0
  else if x >= FBucketWidth then x := FBucketWidth-1;
  if y < 0 then y := 0
  else if y >= FBucketHeight then y := FBucketHeight-1;
  Result := FGetBucket(x, y);
end;

///////////////////////////////////////////////////////////////////////////////

procedure TImageMaker.GetBucketStats(var Stats: TBucketStats);
var
  bucketpos: integer;
  x, y: integer;
  b: TBucket64;
begin
  with Stats do begin
    MaxR := 0;
    MaxG := 0;
    MaxB := 0;
    MaxA := 0;
    TotalA := 0;

    for y := 0 to FBucketHeight - 1 do
      for x := 0 to FBucketWidth - 1 do begin
        b := FGetBucket(x, y);
        MaxR := max(MaxR, b.Red);
        MaxG := max(MaxG, b.Green);
        MaxB := max(MaxB, b.Blue);
        MaxA := max(MaxA, b.Count);
        Inc(TotalA, b.Count);
      end;
  end;
end;

end.
