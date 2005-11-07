unit XForm;

interface

uses
  XFormMan, baseVariation;

type
  TCalcMethod = procedure of object;

type
  TCPpoint = record
    x, y, c: double;
  end;
  PCPpoint = ^TCPpoint;

  TXYpoint = record
    x, y: double;
  end;
  PXYpoint = ^TXYpoint;

  TMatrix = array[0..2, 0..2] of double;

type
  TXForm = class
  private
    FNrFunctions: Integer;
    FFunctionList: array of TCalcMethod;
    FCalcFunctionList: array[0..64] of TCalcMethod;

    FTx, FTy: double;
    FPx, FPy: double;
    FAngle: double;
    FSinA: double;
    FCosA: double;
    FLength: double;
//    CalculateAngle, CalculateLength, CalculateSinCos: boolean;

    FRegVariations: array of TBaseVariation;

    procedure PrecalcAngle;
    procedure PrecalcSinCos;
    procedure PrecalcAll;
    procedure DoPostTransform;

    procedure Linear;              // var[0]
    procedure Sinusoidal;          // var[1]
    procedure Spherical;           // var[2]
    procedure Swirl;               // var[3]
    procedure Horseshoe;           // var[4]
    procedure Polar;               // var[5]
    procedure FoldedHandkerchief;  // var[6]
    procedure Heart;               // var[7]
    procedure Disc;                // var[8]
    procedure Spiral;              // var[9]
    procedure hyperbolic;          // var[10]
    procedure Square;              // var[11]
    procedure Ex;                  // var[12]
    procedure Julia;               // var[13]
    procedure Bent;                // var[14]
    procedure Waves;               // var[15]
    procedure Fisheye;             // var[16]
    procedure Popcorn;             // var[17]
    procedure Exponential;         // var[18]
    procedure Power;               // var[19]
    procedure Cosine;              // var[20]
    procedure Rings;               // var[21]
    procedure Fan;                 // var[22]

//    procedure Triblob;             // var[23]
//    procedure Daisy;               // var[24]
//    procedure Checkers;            // var[25]
//    procedure CRot;                // var[26]

    function Mul33(const M1, M2: TMatrix): TMatrix;
    function Identity: TMatrix;

    procedure BuildFunctionlist;
    procedure AddRegVariations;

  public
    vars: array of double; // normalized interp coefs between variations
    c: array[0..2, 0..1] of double;      // the coefs to the affine part of the function
    p: array[0..2, 0..1] of double;      // post-transform coefs!
    density: double;                     // prob is this function is chosen. 0 - 1
    color: double;                       // color coord for this function. 0 - 1
    color2: double;                      // Second color coord for this function. 0 - 1
    symmetry: double;
    c00, c01, c10, c11, c20, c21: double;
    p00, p01, p10, p11, p20, p21: double;

//    nx,ny,x,y: double;
//    script: TatPascalScripter;

    Orientationtype: integer;

    constructor Create;
    destructor Destroy; override;
    procedure Prepare;

    procedure Assign(Xform: TXForm);

    procedure PreviewPoint(var px, py: double);
    procedure NextPoint(var px, py, pc: double); overload;
    procedure NextPoint(var CPpoint: TCPpoint); overload;
//    procedure NextPoint(var px, py, pz, pc: double); overload;
    procedure NextPointXY(var px, py: double);
    procedure NextPoint2C(var px, py, pc1, pc2: double);

    procedure Rotate(const degrees: double);
    procedure Translate(const x, y: double);
    procedure Multiply(const a, b, c, d: double);
    procedure Scale(const s: double);

    procedure SetVariable(const name: string; var Value: double);
    procedure GetVariable(const name: string; var Value: double);

    function ToXMLString: string;
  end;

implementation

uses
  SysUtils, Math;

const
  EPS = 1E-10;

procedure SinCos(const Theta: double; var Sin, Cos: double); // I'm not sure, but maybe it'll help...
asm
    FLD     Theta
    FSINCOS
    FSTP    qword ptr [edx]    // Cos
    FSTP    qword ptr [eax]    // Sin
    FWAIT
end;

{ TXForm }

///////////////////////////////////////////////////////////////////////////////
constructor TXForm.Create;
var
  i: Integer;
begin
  density := 0;
  Color := 0;
  Symmetry := 0;

  c[0, 0] := 1;
  c[0, 1] := 0;
  c[1, 0] := 0;
  c[1, 1] := 1;
  c[2, 0] := 0;
  c[2, 1] := 0;

  p[0, 0] := 1;
  p[0, 1] := 0;
  p[1, 0] := 0;
  p[1, 1] := 1;
  p[2, 0] := 0;
  p[2, 1] := 0;

  AddRegVariations;
  BuildFunctionlist;

  SetLength(vars, NRLOCVAR + Length(FRegVariations));
  Vars[0] := 1;
  for i := 1 to High(vars) do
    Vars[i] := 0;
end;

///////////////////////////////////////////////////////////////////////////////
procedure TXForm.Prepare;
var
  i: integer;
  CalculateAngle, CalculateSinCos, CalculateLength: boolean;
begin
  c00 := c[0][0];
  c01 := c[0][1];
  c10 := c[1][0];
  c11 := c[1][1];
  c20 := c[2][0];
  c21 := c[2][1];

  FNrFunctions := 0;

  for i := 0 to High(FRegVariations) do begin
    FRegVariations[i].FPX := @FPX;
    FRegVariations[i].FPY := @FPY;
    FRegVariations[i].FTX := @FTX;
    FRegVariations[i].FTY := @FTY;

    FRegVariations[i].vvar := vars[i + NRLOCVAR];
    FRegVariations[i].prepare;
  end;

  CalculateAngle := (vars[5] <> 0.0) or (vars[6] <> 0.0) or (vars[7] <> 0.0) or (vars[8] <> 0.0) or
                    (vars[12] <> 0.0) or (vars[13] <> 0.0) or (vars[21] <> 0.0) or (vars[22] <> 0.0);
//  CalculateLength := False;
  CalculateSinCos := (vars[9] <> 0.0) or (vars[11] <> 0.0) or (vars[19] <> 0.0) or (vars[21] <> 0.0);

  if CalculateAngle or CalculateSinCos then
  begin
    if CalculateAngle and CalculateSinCos then
      FCalcFunctionList[FNrFunctions] := PrecalcAll
    else if CalculateAngle then
      FCalcFunctionList[FNrFunctions] := PrecalcAngle
    else //if CalculateSinCos then
      FCalcFunctionList[FNrFunctions] := PrecalcSinCos;
    Inc(FNrFunctions);
  end;

  for i := 0 to NrVar - 1 do begin
    if (vars[i] <> 0.0) then begin
      FCalcFunctionList[FNrFunctions] := FFunctionList[i];
      Inc(FNrFunctions);
    end;
  end;

  if (p[0,0]<>1) or (p[0,1]<>0) or(p[1,0]<>0) or (p[1,1]<>1) or (p[2,0]<>0) or (p[2,1]<>0) then
  begin
    p00 := p[0][0];
    p01 := p[0][1];
    p10 := p[1][0];
    p11 := p[1][1];
    p20 := p[2][0];
    p21 := p[2][1];

    FCalcFunctionList[FNrFunctions] := DoPostTransform;
    Inc(FNrFunctions);
  end;

(*
  if (vars[27] <> 0.0) then begin
    FFunctionList[FNrFunctions] := TestScript;
    Inc(FNrFunctions);

    Script := TatPascalScripter.Create(nil);
    Script.SourceCode.Text :=
       'function test(x, y; var nx, ny);' + #10#13 +
       'begin' +  #10#13 +
         'nx := x;' +  #10#13 +
         'ny := y;' +  #10#13 +
       'end;' + #10#13 +
       'function test2;' + #10#13 +
       'begin' +  #10#13 +
         'nx := x;' +  #10#13 +
         'ny := y;' +  #10#13 +
       'end;' + #10#13 +
       'nx := x;' +  #10#13 +
       'ny := y;' +  #10#13;
    Script.AddVariable('x',x);
    Script.AddVariable('y',y);
    Script.AddVariable('nx',nx);
    Script.AddVariable('ny',ny);
    Script.Compile;
  end;

  if (vars[NRLOCVAR -1] <> 0.0) then begin
    FFunctionList[FNrFunctions] := TestVar;
    Inc(FNrFunctions);
  end;
*)
end;

procedure TXForm.PrecalcAngle;
asm
    fld     qword ptr [eax + FTx]
    fld     qword ptr [eax + FTy]
    fpatan
    fstp    qword ptr [eax + FAngle]
    fwait
end;

procedure TXForm.PrecalcSinCos;
asm
    fld     qword ptr [eax + FTx]
    fld     qword ptr [eax + FTy]
    fld     st(1)
    fmul    st, st
    fld     st(1)
    fmul    st, st
    faddp
    fsqrt
    fdiv    st(1), st
    fdiv    st(2), st
    fstp    qword ptr [eax + FLength]
    fstp    qword ptr [eax + FCosA]
    fstp    qword ptr [eax + FSinA]
    fwait
end;

procedure TXForm.PrecalcAll;
asm
    fld     qword ptr [eax + FTx]
    fld     qword ptr [eax + FTy]
    fld     st(1)
    fld     st(1)
    fpatan
    fstp    qword ptr [eax + FAngle]
    fld     st(1)
    fmul    st, st
    fld     st(1)
    fmul    st, st
    faddp
    fsqrt
    fdiv    st(1), st
    fdiv    st(2), st
    fstp    qword ptr [eax + FLength]
    fstp    qword ptr [eax + FCosA]
    fstp    qword ptr [eax + FSinA]
    fwait
end;

procedure TXForm.DoPostTransform;
//  x := p00 * FPx + p10 * FPy + p20;
//  y := p01 * FPx + p11 * FPy + p21;
asm
    fld     qword ptr [eax + FPy]
    fld     qword ptr [eax + FPx]
    fld     st(1)
    fmul    qword ptr [eax + p10]
    fld     st(1)
    fmul    qword ptr [eax + p00]
    faddp
    fadd    qword ptr [eax + p20]
    fstp    qword ptr [eax + FPx] // + px]
    fmul    qword ptr [eax + p01]
    fld     qword ptr [eax + p11]
    fmulp   st(2), st
    faddp
    fadd    qword ptr [eax + p21]
    fstp    qword ptr [eax + FPy] // + py]
    fwait
end;

//--0--////////////////////////////////////////////////////////////////////////
procedure TXForm.Linear;
//begin
//  FPx := FPx + vars[0] * FTx;
//  FPy := FPy + vars[0] * FTy;
asm
    mov     edx, [eax + vars]
    fld     qword ptr [edx]
    fld     st
    fmul    qword ptr [eax + FTx]
    fadd    qword ptr [eax + FPx]
    fstp    qword ptr [eax + FPx]
    fmul    qword ptr [eax + FTy]
    fadd    qword ptr [eax + FPy]
    fstp    qword ptr [eax + FPy]
    fwait
end;

//--1--////////////////////////////////////////////////////////////////////////
procedure TXForm.Sinusoidal;
//begin
  //FPx := FPx + vars[1] * sin(FTx);
  //FPy := FPy + vars[1] * sin(FTy);
asm
    mov     edx, [eax + vars]
    fld     qword ptr [edx + 1*8]
    fld     qword ptr [eax + FTx]
    fsin
    fmul    st, st(1)
    fadd    qword ptr [eax + FPx]
    fstp    qword ptr [eax + FPx]
    fld     qword ptr [eax + FTy]
    fsin
    fmulp
    fadd    qword ptr [eax + FPy]
    fstp    qword ptr [eax + FPy]
    fwait
end;

//--2--////////////////////////////////////////////////////////////////////////
procedure TXForm.Spherical;
var
  r: double;
begin
  r := vars[2] / (sqr(FTx) + sqr(FTy) + 1E-6);
  FPx := FPx + FTx * r;
  FPy := FPy + FTy * r;
end;

//--3--////////////////////////////////////////////////////////////////////////
procedure TXForm.Swirl;
var
  sinr, cosr: double;
begin
{
  r2 := FTx * FTx + FTy * FTy;
  c1 := sin(r2);
  c2 := cos(r2);
  FPx := FPx + vars[3] * (c1 * FTx - c2 * FTy);
  FPy := FPy + vars[3] * (c2 * FTx + c1 * FTy);
}
//  SinCos(sqr(FTx) + sqr(FTy), rsin, rcos);
  asm
    fld     qword ptr [eax + FTx]
    fmul    st, st
    fld     qword ptr [eax + FTy]
    fmul    st, st
    faddp
    fsincos
    fstp    qword ptr [cosr]
    fstp    qword ptr [sinr]
    fwait
  end;
  FPx := FPx + vars[3] * (sinr * FTx - cosr * FTy);
  FPy := FPy + vars[3] * (cosr * FTx + sinr * FTy);
end;

//--4--////////////////////////////////////////////////////////////////////////
procedure TXForm.Horseshoe;
//var
//  a, c1, c2: double;
//begin
//  if (FTx < -EPS) or (FTx > EPS) or (FTy < -EPS) or (FTy > EPS) then
//    a := arctan2(FTx, FTy)
//  else
//    a := 0.0;
//  c1 := sin(FAngle);
//  c2 := cos(FAngle);

// --Z-- he he he...
//                       FTx/FLength   FTy/FLength
//  FPx := FPx + vars[4] * (FSinA * FTx - FCosA * FTy);
//  FPy := FPy + vars[4] * (FCosA* FTx + FSinA * FTy);
var
  r: double;
begin
  r := vars[4] / sqrt(sqr(FTx) + sqr(FTy));
  FPx := FPx + (FTx - FTy) * (FTx + FTy) * r;
  FPy := FPy + (2*FTx*FTy) * r;
end;

//--5--////////////////////////////////////////////////////////////////////////
procedure TXForm.Polar;
{var
  ny: double;
  rPI: double;
begin
  rPI := 0.31830989;
  ny := sqrt(FTx * FTx + FTy * FTy) - 1.0;
  FPx := FPx + vars[5] * (FAngle*rPI);
  FPy := FPy + vars[5] * ny;
}
//begin
//  FPx := FPx + vars[5] * FAngle / PI;
//  FPy := FPy + vars[5] * (sqrt(sqr(FTx) + sqr(FTy)) - 1.0);
asm
    mov     edx, [eax + vars]
    fld     qword ptr [edx + 5*8]
    fld     qword ptr [eax + FAngle]
    fldpi
    fdivp   st(1), st
    fmul    st, st(1)
    fadd    qword ptr [eax + FPx]
    fstp    qword ptr [eax + FPx]
    fld     qword ptr [eax + FTx]
    fmul    st, st
    fld     qword ptr [eax + FTy]
    fmul    st, st
    faddp
    fsqrt
    fld1
    fsubp   st(1), st
    fmulp
    fadd    qword ptr [eax + FPy]
    fstp    qword ptr [eax + FPy]
    fwait
end;

//--6--////////////////////////////////////////////////////////////////////////
procedure TXForm.FoldedHandkerchief;
{
var
  r: double;
begin
  r := sqrt(sqr(FTx) + sqr(FTy));
  FPx := FPx + vars[6] * sin(FAngle + r) * r;
  FPy := FPy + vars[6] * cos(FAngle - r) * r;
}
asm
    mov     edx, [eax + vars]
    fld     qword ptr [edx + 6*8]
    fld     qword ptr [eax + FTx]
    fmul    st, st
    fld     qword ptr [eax + FTy]
    fmul    st, st
    faddp
    fsqrt
    fld     qword ptr [eax + FAngle]
    fld     st
    fadd    st, st(2)
    fsin
    fmul    st, st(2)
    fmul    st, st(3)
    fadd    qword ptr [eax + FPx]
    fstp    qword ptr [eax + FPx]
    fsub    st, st(1)
    fcos
    fmulp
    fmulp
    fadd    qword ptr [eax + FPy]
    fstp    qword ptr [eax + FPy]
    fwait
end;

//--7--////////////////////////////////////////////////////////////////////////
procedure TXForm.Heart;
var
  r, sinr, cosr: double;
begin
//  r := sqrt(sqr(FTx) + sqr(FTy));
//  Sincos(r*FAngle, sinr, cosr);
  asm
    fld     qword ptr [eax + FTx]
    fmul    st, st
    fld     qword ptr [eax + FTy]
    fmul    st, st
    faddp
    fsqrt
    fst     qword ptr [r]
    fmul    qword ptr [eax + FAngle]
    fsincos
    fstp    qword ptr [cosr]
    fstp    qword ptr [sinr]
    fwait
  end;
  r := r * vars[7];
  FPx := FPx + r * sinr;
  FPy := FPy - r * cosr;
end;

//--8--////////////////////////////////////////////////////////////////////////
procedure TXForm.Disc;
{
var
//  nx, ny: double;
  r, sinr, cosr: double;
begin
// --Z-- ????? - calculating PI^2 to get square root from it, hmm?
//  nx := FTx * PI;
//  ny := FTy * PI;
//  r := sqrt(nx * nx + ny * ny);

  SinCos(PI * sqrt(sqr(FTx) + sqr(FTy)), sinr, cosr);
  r := vars[8] * FAngle / PI;
  FPx := FPx + sinr * r;
  FPy := FPy + cosr * r;
}
asm
    mov     edx, [eax + vars]
    fld     qword ptr [edx + 8*8]
    fmul    qword ptr [eax + FAngle]
    fldpi
    fdivp   st(1), st
    fld     qword ptr [eax + FTx]
    fmul    st, st
    fld     qword ptr [eax + FTy]
    fmul    st, st
    faddp
    fsqrt
    fldpi
    fmulp
    fsincos
    fmul    st, st(2)
    fadd    qword ptr [eax + FPy]
    fstp    qword ptr [eax + FPy]
    fmulp
    fadd    qword ptr [eax + FPx]
    fstp    qword ptr [eax + FPx]
    fwait
end;

//--9--////////////////////////////////////////////////////////////////////////
procedure TXForm.Spiral;
var
  r, sinr, cosr: double;
begin
  r := Flength + 1E-6;
//  SinCos(r, sinr, cosr);
  asm
    fld     qword ptr [r]
    fsincos
    fstp    qword ptr [cosr]
    fstp    qword ptr [sinr]
    fwait
  end;
  r := vars[9] / r;
  FPx := FPx + (FCosA + sinr) * r;
  FPy := FPy + (FsinA - cosr) * r;
end;

//--10--///////////////////////////////////////////////////////////////////////
procedure TXForm.Hyperbolic;
{
var
  r: double;
begin
  r := Flength + 1E-6;
  FPx := FPx + vars[10] * FSinA / r;
  FPy := FPy + vars[10] * FCosA * r;
}

// --Z-- Yikes!!! SOMEONE SHOULD GO BACK TO SCHOOL!!!!!!!
// Scott Draves, you aren't so cool after all! :-))
// And did no one niticed it?!!
// After ALL THESE YEARS!!!

// Now watch and learn how to do this WITHOUT calculating sin and cos:
begin
  FPx := FPx + vars[10] * FTx / (sqr(FTx) + sqr(FTy) + 1E-6);
  FPy := FPy + vars[10] * FTy;
end;

//--11--///////////////////////////////////////////////////////////////////////
procedure TXForm.Square;
{
var
  sinr, cosr: double;
begin
  SinCos(FLength, sinr, cosr);
  FPx := FPx + vars[11] * FSinA * cosr;
  FPy := FPy + vars[11] * FCosA * sinr;
}
asm
    mov     edx, [eax + vars]
    fld     qword ptr [edx + 11*8]
    fld     qword ptr [eax + FLength]
    fsincos
    fmul    qword ptr [eax + FSinA]
    fmul    st, st(2)
    fadd    qword ptr [eax + FPx]
    fstp    qword ptr [eax + FPx]
    fmul    qword ptr [eax + FCosA]
    fmulp
    fadd    qword ptr [eax + FPy]
    fstp    qword ptr [eax + FPy]
    fwait
end;

//--12--///////////////////////////////////////////////////////////////////////
procedure TXForm.Ex;
{var
  r: double;
  n0, n1, m0, m1: double;
begin
  r := sqrt(sqr(FTx) + sqr(FTy));
  n0 := sin(FAngle + r);
  n1 := cos(FAngle - r);
  m0 := sqr(n0) * n0;
  m1 := sqr(n1) * n1;
  r := r * vars[12];
  FPx := FPx + r * (m0 + m1);
  FPy := FPy + r * (m0 - m1);
}
asm
    fld     qword ptr [eax + FTx]
    fmul    st, st
    fld     qword ptr [eax + FTy]
    fmul    st, st
    faddp
    fsqrt
    fld     qword ptr [eax + FAngle]
    fld     st
    fadd    st, st(2)
    fsin
    fld     st
    fld     st
    fmulp
    fmulp
    fxch    st(1)
    fsub    st, st(2)
    fcos
    fld     st
    fld     st
    fmulp
    fmulp
    mov     edx, [eax + vars]
    fld     qword ptr [edx + 12*8]
    fmulp   st(3), st
    fld     st
    fadd    st, st(2)
    fmul    st, st(3)

    fadd    qword ptr [eax + FPx]
    fstp    qword ptr [eax + FPx]
    fsubp   st(1), st
    fmulp
    fadd    qword ptr [eax + FPy]
    fstp    qword ptr [eax + FPy]
    fwait
end;

//--13--///////////////////////////////////////////////////////////////////////
procedure TXForm.Julia;
{
var
  a, r: double;
  sinr, cosr: double;
begin
  if random > 0.5 then
    a := FAngle/2 + PI
  else
    a := FAngle/2;
  SinCos(a, sinr, cosr);
  r := vars[13] * sqrt(sqrt(sqr(FTx) + sqr(FTy)));
  FPx := FPx + r * cosr;
  FPy := FPy + r * sinr;
}
asm
    fld     qword ptr [ebx + FAngle] // assert: self is in ebx
    fld1
    fld1
    faddp
    fdivp   st(1), st
    xor     eax, eax        // hmm...
    add     eax, $02        // hmmm....
    call    System.@RandInt // hmmmm.....
    test    al, al
    jnz     @skip
    fldpi
    faddp
@skip:
    fsincos
    fld     qword ptr [ebx + FTx]
    fmul    st, st
    fld     qword ptr [ebx + FTy]
    fmul    st, st
    faddp
    fsqrt
    fsqrt
    mov     edx, [ebx + vars]
    fmul    qword ptr [edx + 13*8]
    fmul    st(2), st
    fmulp   st(1), st
    fadd    qword ptr [ebx + FPx]
    fstp    qword ptr [ebx + FPx]
    fadd    qword ptr [ebx + FPy]
    fstp    qword ptr [ebx + FPy]
    fwait
end;

//--14--///////////////////////////////////////////////////////////////////////
procedure TXForm.Bent;
{
var
  nx, ny: double;
begin
  nx := FTx;
  ny := FTy;
  if (nx < 0) and (nx > -1E100) then
     nx := nx * 2;
  if ny < 0 then
    ny := ny / 2;
  FPx := FPx + vars[14] * nx;
  FPy := FPy + vars[14] * ny;
}
// --Z-- This variation is kinda weird...
begin
  if FTx < 0 then
    FPx := FPx + vars[14] * (FTx*2)
  else
    FPx := FPx + vars[14] * FTx;
  if FTy < 0 then
    FPy := FPy + vars[14] * (FTy/2)
  else
    FPy := FPy + vars[14] * FTy;
end;

//--15--///////////////////////////////////////////////////////////////////////
procedure TXForm.Waves;
{
var
  dx,dy,nx,ny: double;
begin
  dx := c20;
  dy := c21;
  nx := FTx + c10 * sin(FTy / ((dx * dx) + EPS));
  ny := FTy + c11 * sin(FTx / ((dy * dy) + EPS));
  FPx := FPx + vars[15] * nx;
  FPy := FPy + vars[15] * ny;
}
begin
  FPx := FPx + vars[15] * (FTx + c10 * sin(FTy / (sqr(c20) + EPS)));
  FPy := FPy + vars[15] * (FTy + c11 * sin(FTx / (sqr(c21) + EPS)));
end;

//--16--///////////////////////////////////////////////////////////////////////
procedure TXForm.Fisheye;
(*
var
  r: double;
begin
{
//  r := sqrt(FTx * FTx + FTy * FTy);
//  a := arctan2(FTx, FTy);
//  r := 2 * r / (r + 1);
  r := 2 * Flength / (Flength + 1);
  FPx := FPx + vars[16] * r * FCosA;
  FPy := FPy + vars[16] * r * FSinA;
}
// --Z-- and again, sin & cos are NOT necessary here:
  r := 2 * vars[16] / (sqrt(sqr(FTx) + sqr(FTy)) + 1);
// by the way, now we can clearly see that the original author messed X and Y:
  FPx := FPx +  r * FTy;
  FPy := FPy +  r * FTx;
*)
asm
    mov     edx, [eax + vars]
    fld     qword ptr [edx + 16*8]
    fadd    st, st
    fld     qword ptr [eax + FTx]
    fld     qword ptr [eax + FTy]
    fld     st(1)
    fmul    st, st
    fld     st(1)
    fmul    st, st
    faddp
    fsqrt
    fld1
    faddp
    fdivp   st(3), st
    fmul    st, st(2)
    fadd    qword ptr [ebx + FPx]
    fstp    qword ptr [ebx + FPx]
    fmulp
    fadd    qword ptr [ebx + FPy]
    fstp    qword ptr [ebx + FPy]
    fwait
end;

//--17--///////////////////////////////////////////////////////////////////////
procedure TXForm.Popcorn;
(*
var
  dx, dy: double;
//  nx, ny: double;
begin
  dx := tan(3 * FTy);
  if (dx <> dx) then
    dx := 0.0;                  // < probably won't work in Delphi
  dy := tan(3 * FTx);            // NAN will raise an exception...
  if (dy <> dy) then
    dy := 0.0;                  // remove for speed?
//  nx := FTx + c20 * sin(dx);
//  ny := FTy + c21 * sin(dy);
//  FPx := FPx + vars[17] * nx;
//  FPy := FPy + vars[17] * ny;
  FPx := FPx + vars[17] * (FTx + c20 * sin(dx));
  FPy := FPy + vars[17] * (FTy + c21 * sin(dy));
*)
asm
    mov     edx, [eax + vars]
    fld     qword ptr [edx + 17*8]
    fld     qword ptr [eax + FTy]
    fld     qword ptr [eax + FTx]
    fld     st(1)
    fld     st
    fld     st
    faddp
    faddp
    fptan
    fstp    st
    fsin
    fmul    qword ptr [eax + c20]
    fadd    st, st(1)
    fmul    st, st(3)
    fadd    qword ptr [ebx + FPx]
    fstp    qword ptr [ebx + FPx]
    fld     st
    fld     st
    faddp
    faddp
    fptan
    fstp    st
    fsin
    fmul    qword ptr [eax + c21]
    faddp
    fmulp
    fadd    qword ptr [ebx + FPy]
    fstp    qword ptr [ebx + FPy]
    fwait
end;

//--18--///////////////////////////////////////////////////////////////////////
procedure TXForm.Exponential;
{
var
  d: double;
  sinr, cosr: double;
begin
  SinCos(PI * FTy, sinr, cosr);
  d := vars[18] * exp(FTx - 1); // --Z-- (e^x)/e = e^(x-1)
  FPx := FPx +  cosr * d;
  FPy := FPy +  sinr * d;
}
asm
    fld     qword ptr [eax + FTx]
    fld1
    fsubp   st(1), st
// --Z-- here goes exp(x) code from System.pas
    FLDL2E
    FMUL
    FLD     ST(0)
    FRNDINT
    FSUB    ST(1), ST
    FXCH    ST(1)
    F2XM1
    FLD1
    FADD
    FSCALE
    FSTP    ST(1)
// -----
    mov     edx, [eax + vars]
    fmul    qword ptr [edx + 18*8]
    fld     qword ptr [eax + FTy]
    fldpi
    fmulp
    fsincos
    fmul    st, st(2)
    fadd    qword ptr [ebx + FPx]
    fstp    qword ptr [ebx + FPx]
    fmulp
    fadd    qword ptr [ebx + FPy]
    fstp    qword ptr [ebx + FPy]
    fwait
end;

//--19--///////////////////////////////////////////////////////////////////////
procedure TXForm.Power;
var
  r: double;
//  nx, ny: double;
begin
//  r := sqrt(FTx * FTx + FTy * FTy);
//  sa := sin(FAngle);
  r := vars[19] * Math.Power(FLength, FSinA);
//  nx := r * FCosA;
//  ny := r * FSinA;
  FPx := FPx + r * FCosA;
  FPy := FPy + r * FSinA;
end;

//--20--///////////////////////////////////////////////////////////////////////
procedure TXForm.Cosine;
var
  vsin2, vcos2: double;
  e1, e2: double;
begin
//  SinCos(FTx * PI, sinr, cosr);
//  FPx := FPx + vars[20] * cosr * cosh(FTy);
//  FPy := FPy - vars[20] * sinr * sinh(FTy);
{
  SinCos(FTx * PI, sinr, cosr);
  if FTy = 0 then
  begin
    // sinh(0) = 0, cosh(0) = 1
    FPx := FPx + vars[20] * cosr;
  end
  else begin
    // --Z-- sinh() and cosh() both calculate exp(y) and exp(-y)
    e1 := exp(FTy);
    e2 := exp(-FTy);
    FPx := FPx + vars[20] * cosr * (e1 + e2)/2;
    FPy := FPy - vars[20] * sinr * (e1 - e2)/2;
  end;
}
  asm
    mov     edx, [eax + vars]
    fld     qword ptr [edx + 20*8]
    fld1
    fld1
    faddp
    fdivp   st(1), st
    fld     qword ptr [eax + FTx]
    fldpi
    fmulp
    fsincos
    fmul    st, st(2)
    fstp    qword ptr [vcos2]
    fmulp
    fstp    qword ptr [vsin2]
    fwait
  end;
  if FTy = 0 then
  begin
    // sinh(0) = 0, cosh(0) = 1
    FPx := FPx + 2 * vcos2;
  end
  else begin
    // --Z-- sinh() and cosh() both calculate exp(y) and exp(-y)
    e1 := exp(FTy);
    e2 := exp(-FTy);
    FPx := FPx + vcos2 * (e1 + e2);
    FPy := FPy - vsin2 * (e1 - e2);
  end;
end;

//--21--///////////////////////////////////////////////////////////////////////
procedure TXForm.Rings;
var
  r: double;
  dx: double;
begin
  dx := sqr(c20) + EPS;
//  r := FLength;
//  r := r + dx - System.Int((r + dx)/(2 * dx)) * 2 * dx - dx + r * (1-dx);
// --Z--   ^^^^               heheeeee :-)               ^^^^

//  FPx := FPx + vars[21] * r * FCosA;
//  FPy := FPy + vars[21] * r * FSinA;
  r := vars[21] * (
         2 * FLength - dx * (System.Int((FLength/dx + 1)/2) * 2 + FLength)
       );
  FPx := FPx + r * FCosA;
  FPy := FPy + r * FSinA;
end;

//--22--///////////////////////////////////////////////////////////////////////
procedure TXForm.Fan;
var
//  r, a : double;
//  sinr, cosr: double;
  dx, dy, dx2: double;
begin
  dy := c21;
  dx := PI * (sqr(c20) + EPS);
  dx2 := dx/2;

  if (FAngle+dy - System.Int((FAngle + dy)/dx) * dx) > dx2 then
    //a := FAngle - dx2
    asm
      fld   qword ptr [ebx + FAngle]
      fsub  qword ptr [dx2]
    end
  else
    //a := FAngle + dx2;
    asm
      fld   qword ptr [ebx + FAngle]
      fadd  qword ptr [dx2]
    end;
//  SinCos(a, sinr, cosr);
//  r := vars[22] * sqrt(sqr(FTx) + sqr(FTy));
//  FPx := FPx + r * cosr;
//  FPy := FPy + r * sinr;
  asm
    fsincos
    fld       qword ptr [ebx + FTx]
    fmul      st, st
    fld       qword ptr [ebx + FTy]
    fmul      st, st
    faddp
    fsqrt
    mov       edx, [ebx + vars]
    fmul      qword ptr [edx + 22*8]
    fmul      st(2), st
    fmulp
    fadd    qword ptr [ebx + FPx]
    fstp    qword ptr [ebx + FPx]
    fadd    qword ptr [ebx + FPy]
    fstp    qword ptr [ebx + FPy]
    fwait
  end;
end;

(*

//--23--///////////////////////////////////////////////////////////////////////
procedure TXForm.Triblob;
var
  r : double;
  Angle: double;
  sinr, cosr: double;
begin
  r := sqrt(sqr(FTx) + sqr(FTy));
  if (FTx < -EPS) or (FTx > EPS) or (FTy < -EPS) or (FTy > EPS) then
     Angle := arctan2(FTx, FTy)
  else
    Angle := 0.0;

  r := r * (0.6 + 0.4 * sin(3 * Angle));
  SinCos(Angle, sinr, cosr);

  FPx := FPx + vars[23] * r * cosr;
  FPy := FPy + vars[23] * r * sinr;
end;

//--24--///////////////////////////////////////////////////////////////////////
procedure TXForm.Daisy;
var
  r : double;
  Angle: double;
  sinr, cosr: double;
begin
  r := sqrt(sqr(FTx) + sqr(FTy));
  if (FTx < -EPS) or (FTx > EPS) or (FTy < -EPS) or (FTy > EPS) then
     Angle := arctan2(FTx, FTy)
  else
    Angle := 0.0;

//  r := r * (0.6 + 0.4 * sin(3 * Angle));
  r := r * ( 1 - Sqr(sin(5 * Angle)));
  SinCos(Angle, sinr, cosr);

  FPx := FPx + vars[24] * r * cosr;
  FPy := FPy + vars[24] * r * sinr;
end;

//--25--///////////////////////////////////////////////////////////////////////
procedure TXForm.Checkers;
var
  dx: double;
begin
  if odd(Round(FTX * 5) + Round(FTY * 5)) then
    dx := 0.2
  else
    dx := 0;

  FPx := FPx + vars[25] * FTx + dx;
  FPy := FPy + vars[25] * FTy;
end;

//--26--///////////////////////////////////////////////////////////////////////
procedure TXForm.CRot;
var
  r : double;
  Angle: double;
  sinr, cosr: double;
begin
  r := sqrt(sqr(FTx) + sqr(FTy));
  if (FTx < -EPS) or (FTx > EPS) or (FTy < -EPS) or (FTy > EPS) then
     Angle := arctan2(FTx, FTy)
  else
    Angle := 0.0;

  if r < 3 then
    Angle := Angle + (3 - r) * sin(3 * r);
  SinCos(Angle, sinr, cosr);

//   r:=  R - 0.04 * sin(6.2 * R - 1) - 0.008 * R;

  FPx := FPx + vars[26] * r * cosr;
  FPy := FPy + vars[26] * r * sinr;
end;

*)

//***************************************************************************//

procedure TXForm.PreviewPoint(var px, py: double);
var
  i: Integer;
begin
  FTx := c00 * px + c10 * py + c20;
  FTy := c01 * px + c11 * py + c21;

  Fpx := 0;
  Fpy := 0;

  for i := 0 to FNrFunctions - 1 do
    FCalcFunctionList[i];

  px := FPx;
  py := FPy;
end;

procedure TXForm.NextPoint(var px, py, pc: double);
var
  i: Integer;
begin
  // first compute the color coord
  if symmetry = 0 then
    pc := (pc + color) / 2
  else
    pc := (pc + color) * 0.5 * (1 - symmetry) + symmetry * pc;

  FTx := c00 * px + c10 * py + c20;
  FTy := c01 * px + c11 * py + c21;
(*
  if CalculateAngle then begin
    if (FTx < -EPS) or (FTx > EPS) or (FTy < -EPS) or (FTy > EPS) then
       FAngle := arctan2(FTx, FTy)
    else
       FAngle := 0.0;
  end;

  if CalculateSinCos then begin
    Flength := sqrt(sqr(FTx) + sqr(FTy));
    if FLength = 0 then begin
      FSinA := 0;
      FCosA := 0;
    end else begin
      FSinA := FTx/FLength;
      FCosA := FTy/FLength;
    end;
  end;

//  if CalculateLength then begin
//    FLength := sqrt(FTx * FTx + FTy * FTy);
//  end;
*)
  Fpx := 0;
  Fpy := 0;

  for i := 0 to FNrFunctions - 1 do
    FCalcFunctionList[i];

  px := FPx;
  py := FPy;
//  px := p[0,0] * FPx + p[1,0] * FPy + p[2,0];
//  py := p[0,1] * FPx + p[1,1] * FPy + p[2,1];
end;

///////////////////////////////////////////////////////////////////////////////
procedure TXForm.NextPoint(var CPpoint: TCPpoint);
var
  i: Integer;
begin
  // first compute the color coord
  if symmetry = 0 then
    CPpoint.c := (CPpoint.c + color) / 2
  else
    CPpoint.c := (CPpoint.c + color) * 0.5 * (1 - symmetry) + symmetry * CPpoint.c;

  FTx := c00 * CPpoint.x + c10 * CPpoint.y + c20;
  FTy := c01 * CPpoint.x + c11 * CPpoint.y + c21;

(*
  if CalculateAngle then begin
    if (FTx < -EPS) or (FTx > EPS) or (FTy < -EPS) or (FTy > EPS) then
       FAngle := arctan2(FTx, FTy)
    else
       FAngle := 0.0;
  end;

  if CalculateSinCos then begin
    Flength := sqrt(sqr(FTx) + sqr(FTy));
    if FLength = 0 then begin
      FSinA := 0;
      FCosA := 1;
    end else begin
      FSinA := FTx/FLength;
      FCosA := FTy/FLength;
    end;
  end;

//  if CalculateLength then begin
//    FLength := sqrt(FTx * FTx + FTy * FTy);
//  end;
*)

  Fpx := 0;
  Fpy := 0;

  for i:= 0 to FNrFunctions-1 do
    FFunctionList[i];

  CPpoint.x := FPx;
  CPpoint.y := FPy;
//  CPpoint.x := p[0,0] * FPx + p[1,0] * FPy + p[2,0];
//  CPpoint.y := p[0,1] * FPx + p[1,1] * FPy + p[2,1];
end;


{
///////////////////////////////////////////////////////////////////////////////
procedure TXForm.NextPoint(var px, py, pz, pc: double);
var
  i: Integer;
  tpx, tpy: double;
begin
  // first compute the color coord
  pc := (pc + color) * 0.5 * (1 - symmetry) + symmetry * pc;

  case Orientationtype of
  1:
     begin
       tpx := px;
       tpy := pz;
     end;
  2:
     begin
       tpx := py;
       tpy := pz;
     end;
  else
    tpx := px;
    tpy := py;
  end;

  FTx := c00 * tpx + c10 * tpy + c20;
  FTy := c01 * tpx + c11 * tpy + c21;

(*
  if CalculateAngle then begin
    if (FTx < -EPS) or (FTx > EPS) or (FTy < -EPS) or (FTy > EPS) then
       FAngle := arctan2(FTx, FTy)
    else
       FAngle := 0.0;
  end;

  if CalculateSinCos then begin
    Flength := sqrt(sqr(FTx) + sqr(FTy));
    if FLength = 0 then begin
      FSinA := 0;
      FCosA := 1;
    end else begin
      FSinA := FTx/FLength;
      FCosA := FTy/FLength;
    end;
  end;

//  if CalculateLength then begin
//    FLength := sqrt(FTx * FTx + FTy * FTy);
//  end;
*)

  Fpx := 0;
  Fpy := 0;

  for i:= 0 to FNrFunctions-1 do
    FFunctionList[i];

  case Orientationtype of
  1:
     begin
       px := FPx;
       pz := FPy;
     end;
  2:
     begin
       py := FPx;
       pz := FPy;
     end;
  else
    px := FPx;
    py := FPy;
  end;
end;
}

///////////////////////////////////////////////////////////////////////////////
procedure TXForm.NextPoint2C(var px, py, pc1, pc2: double);
var
  i: Integer;
begin
  // first compute the color coord
  pc1 := (pc1 + color) * 0.5 * (1 - symmetry) + symmetry * pc1;
  pc2 := (pc2 + color) * 0.5 * (1 - symmetry) + symmetry * pc2;

  FTx := c00 * px + c10 * py + c20;
  FTy := c01 * px + c11 * py + c21;

(*
  if CalculateAngle then begin
    if (FTx < -EPS) or (FTx > EPS) or (FTy < -EPS) or (FTy > EPS) then
       FAngle := arctan2(FTx, FTy)
    else
       FAngle := 0.0;
  end;

  if CalculateSinCos then begin
    Flength := sqrt(sqr(FTx) + sqr(FTy));
    if FLength = 0 then begin
      FSinA := 0;
      FCosA := 1;
    end else begin
      FSinA := FTx/FLength;
      FCosA := FTy/FLength;
    end;
  end;

//  if CalculateLength then begin
//    FLength := sqrt(FTx * FTx + FTy * FTy);
//  end;
*)

  Fpx := 0;
  Fpy := 0;

  for i:= 0 to FNrFunctions-1 do
    FFunctionList[i];

  px := FPx;
  py := FPy;
//  px := p[0,0] * FPx + p[1,0] * FPy + p[2,0];
//  py := p[0,1] * FPx + p[1,1] * FPy + p[2,1];
end;

///////////////////////////////////////////////////////////////////////////////
procedure TXForm.NextPointXY(var px, py: double);
var
  i: integer;
begin
  FTx := c00 * px + c10 * py + c20;
  FTy := c01 * px + c11 * py + c21;

(*
  if CalculateAngle then begin
    if (FTx < -EPS) or (FTx > EPS) or (FTy < -EPS) or (FTy > EPS) then
       FAngle := arctan2(FTx, FTy)
    else
       FAngle := 0.0;
  end;

  if CalculateSinCos then begin
    Flength := sqrt(sqr(FTx) + sqr(FTy));
    if FLength = 0 then begin
      FSinA := 0;
      FCosA := 0;
    end else begin
      FSinA := FTx/FLength;
      FCosA := FTy/FLength;
    end;
  end;
*)

  Fpx := 0;
  Fpy := 0;

  for i:= 0 to FNrFunctions-1 do
    FFunctionList[i];

  px := FPx;
  py := FPy;
//  px := p[0,0] * FPx + p[1,0] * FPy + p[2,0];
//  py := p[0,1] * FPx + p[1,1] * FPy + p[2,1];
end;

///////////////////////////////////////////////////////////////////////////////
function TXForm.Mul33(const M1, M2: TMatrix): TMatrix;
begin
  result[0, 0] := M1[0][0] * M2[0][0] + M1[0][1] * M2[1][0] + M1[0][2] * M2[2][0];
  result[0, 1] := M1[0][0] * M2[0][1] + M1[0][1] * M2[1][1] + M1[0][2] * M2[2][1];
  result[0, 2] := M1[0][0] * M2[0][2] + M1[0][1] * M2[1][2] + M1[0][2] * M2[2][2];
  result[1, 0] := M1[1][0] * M2[0][0] + M1[1][1] * M2[1][0] + M1[1][2] * M2[2][0];
  result[1, 1] := M1[1][0] * M2[0][1] + M1[1][1] * M2[1][1] + M1[1][2] * M2[2][1];
  result[1, 2] := M1[1][0] * M2[0][2] + M1[1][1] * M2[1][2] + M1[1][2] * M2[2][2];
  result[2, 0] := M1[2][0] * M2[0][0] + M1[2][1] * M2[1][0] + M1[2][2] * M2[2][0];
  result[2, 0] := M1[2][0] * M2[0][1] + M1[2][1] * M2[1][1] + M1[2][2] * M2[2][1];
  result[2, 0] := M1[2][0] * M2[0][2] + M1[2][1] * M2[1][2] + M1[2][2] * M2[2][2];
end;

///////////////////////////////////////////////////////////////////////////////
function TXForm.Identity: TMatrix;
var
  i, j: integer;
begin
  for i := 0 to 2 do
    for j := 0 to 2 do
      Result[i, j] := 0;
  Result[0][0] := 1;
  Result[1][1] := 1;
  Result[2][2] := 1;
end;

///////////////////////////////////////////////////////////////////////////////
procedure TXForm.Rotate(const degrees: double);
var
  r: double;
  Matrix, M1: TMatrix;
begin
  r := degrees * pi / 180;
  M1 := Identity;
  M1[0, 0] := cos(r);
  M1[0, 1] := -sin(r);
  M1[1, 0] := sin(r);
  M1[1, 1] := cos(r);
  Matrix := Identity;

  Matrix[0][0] := c[0, 0];
  Matrix[0][1] := c[0, 1];
  Matrix[1][0] := c[1, 0];
  Matrix[1][1] := c[1, 1];
  Matrix[0][2] := c[2, 0];
  Matrix[1][2] := c[2, 1];
  Matrix := Mul33(Matrix, M1);
  c[0, 0] := Matrix[0][0];
  c[0, 1] := Matrix[0][1];
  c[1, 0] := Matrix[1][0];
  c[1, 1] := Matrix[1][1];
  c[2, 0] := Matrix[0][2];
  c[2, 1] := Matrix[1][2];
end;

///////////////////////////////////////////////////////////////////////////////
procedure TXForm.Translate(const x, y: double);
var
  Matrix, M1: TMatrix;
begin
  M1 := Identity;
  M1[0, 2] := x;
  M1[1, 2] := y;
  Matrix := Identity;

  Matrix[0][0] := c[0, 0];
  Matrix[0][1] := c[0, 1];
  Matrix[1][0] := c[1, 0];
  Matrix[1][1] := c[1, 1];
  Matrix[0][2] := c[2, 0];
  Matrix[1][2] := c[2, 1];
  Matrix := Mul33(Matrix, M1);
  c[0, 0] := Matrix[0][0];
  c[0, 1] := Matrix[0][1];
  c[1, 0] := Matrix[1][0];
  c[1, 1] := Matrix[1][1];
  c[2, 0] := Matrix[0][2];
  c[2, 1] := Matrix[1][2];
end;

///////////////////////////////////////////////////////////////////////////////
procedure TXForm.Multiply(const a, b, c, d: double);
var
  Matrix, M1: TMatrix;
begin
  M1 := Identity;
  M1[0, 0] := a;
  M1[0, 1] := b;
  M1[1, 0] := c;
  M1[1, 1] := d;
  Matrix := Identity;
  Matrix[0][0] := Self.c[0, 0];
  Matrix[0][1] := Self.c[0, 1];
  Matrix[1][0] := Self.c[1, 0];
  Matrix[1][1] := Self.c[1, 1];
  Matrix[0][2] := Self.c[2, 0];
  Matrix[1][2] := Self.c[2, 1];
  Matrix := Mul33(Matrix, M1);
  Self.c[0, 0] := Matrix[0][0];
  Self.c[0, 1] := Matrix[0][1];
  Self.c[1, 0] := Matrix[1][0];
  Self.c[1, 1] := Matrix[1][1];
  Self.c[2, 0] := Matrix[0][2];
  Self.c[2, 1] := Matrix[1][2];
end;

///////////////////////////////////////////////////////////////////////////////
procedure TXForm.Scale(const s: double);
var
  Matrix, M1: TMatrix;
begin
  M1 := Identity;
  M1[0, 0] := s;
  M1[1, 1] := s;
  Matrix := Identity;
  Matrix[0][0] := c[0, 0];
  Matrix[0][1] := c[0, 1];
  Matrix[1][0] := c[1, 0];
  Matrix[1][1] := c[1, 1];
  Matrix[0][2] := c[2, 0];
  Matrix[1][2] := c[2, 1];
  Matrix := Mul33(Matrix, M1);
  c[0, 0] := Matrix[0][0];
  c[0, 1] := Matrix[0][1];
  c[1, 0] := Matrix[1][0];
  c[1, 1] := Matrix[1][1];
  c[2, 0] := Matrix[0][2];
  c[2, 1] := Matrix[1][2];
end;

///////////////////////////////////////////////////////////////////////////////
destructor TXForm.Destroy;
var
  i: integer;
begin
//  if assigned(Script) then
//    Script.Free;

  for i := 0 to High(FRegVariations) do
    FRegVariations[i].Free;

  inherited;
end;

///////////////////////////////////////////////////////////////////////////////
procedure TXForm.BuildFunctionlist;
var
  i: integer;
begin
  SetLength(FFunctionList, NrVar + Length(FRegVariations));

  //fixed
  FFunctionList[0] := Linear;
  FFunctionList[1] := Sinusoidal;
  FFunctionList[2] := Spherical;
  FFunctionList[3] := Swirl;
  FFunctionList[4] := Horseshoe;
  FFunctionList[5] := Polar;
  FFunctionList[6] := FoldedHandkerchief;
  FFunctionList[7] := Heart;
  FFunctionList[8] := Disc;
  FFunctionList[9] := Spiral;
  FFunctionList[10] := Hyperbolic;
  FFunctionList[11] := Square;
  FFunctionList[12] := Ex;
  FFunctionList[13] := Julia;
  FFunctionList[14] := Bent;
  FFunctionList[15] := Waves;
  FFunctionList[16] := Fisheye;
  FFunctionList[17] := Popcorn;
  FFunctionList[18] := Exponential;
  FFunctionList[19] := Power;
  FFunctionList[20] := Cosine;
  FFunctionList[21] := Rings;
  FFunctionList[22] := Fan;

//  FFunctionList[23] := Triblob;
//  FFunctionList[24] := Daisy;
//  FFunctionList[25] := Checkers;
//  FFunctionList[26] := CRot;

  //registered
  for i := 0 to High(FRegVariations) do
    FFunctionList[23 + i] := FRegVariations[i].CalcFunction;
end;

///////////////////////////////////////////////////////////////////////////////
procedure TXForm.AddRegVariations;
var
  i: integer;
begin
  SetLength(FRegVariations, GetNrRegisteredVariations);
  for i := 0 to GetNrRegisteredVariations - 1 do begin
    FRegVariations[i] := GetRegisteredVariation(i).GetInstance;
  end;
end;

///////////////////////////////////////////////////////////////////////////////
procedure TXForm.Assign(XForm: TXForm);
var
  i,j: integer;
  Name: string;
  Value: double;
begin
  if Not assigned(XForm) then
    Exit;

  for i := 0 to High(vars) do
    vars[i] := XForm.vars[i];

  c := Xform.c;
  p := Xform.p;
  density := XForm.density;
  color := XForm.color;
  color2 := XForm.color2;
  symmetry := XForm.symmetry;
  Orientationtype := XForm.Orientationtype;

  for i := 0 to High(FRegVariations)  do begin
    for j:= 0 to FRegVariations[i].GetNrVariables -1 do begin
      Name := FRegVariations[i].GetVariableNameAt(j);
      XForm.FRegVariations[i].GetVariable(Name,Value);
      FRegVariations[i].SetVariable(Name,Value);
    end;
  end;
end;

///////////////////////////////////////////////////////////////////////////////
function TXForm.ToXMLString: string;
var
  i, j: integer;
  Name: string;
  Value: double;
begin
  result := Format('   <xform weight="%g" color="%g" symmetry="%g" ', [density, color, symmetry]);
  for i := 0 to nrvar - 1 do begin
    if vars[i] <> 0 then
      Result := Result + varnames(i) + format('="%g" ', [vars[i]]);
  end;
  Result := Result + Format('coefs="%g %g %g %g %g %g" ', [c[0,0], c[0,1], c[1,0], c[1,1], c[2,0], c[2,1]]);
  if (p[0,0]<>1) or (p[0,1]<>0) or(p[1,0]<>0) or (p[1,1]<>1) or (p[2,0]<>0) or (p[2,1]<>0) then
    Result := Result + Format('post="%g %g %g %g %g %g" ', [p[0,0], p[0,1], p[1,0], p[1,1], p[2,0], p[2,1]]);

  for i := 0 to High(FRegVariations)  do begin
    if vars[i+NRLOCVAR] <> 0 then
      for j:= 0 to FRegVariations[i].GetNrVariables -1 do begin
        Name := FRegVariations[i].GetVariableNameAt(j);
        FRegVariations[i].GetVariable(Name,Value);
        Result := Result + Format('%s="%g" ', [name, value]);
      end;
  end;

  Result := Result + '/>';
end;

///////////////////////////////////////////////////////////////////////////////
procedure TXForm.SetVariable(const name: string; var Value: double);
var
  i: integer;
begin
  for i := 0 to High(FRegVariations) do
    if FRegVariations[i].SetVariable(name, value) then
      break;
end;

///////////////////////////////////////////////////////////////////////////////
procedure TXForm.GetVariable(const name: string; var Value: double);
var
  i: integer;
begin
  for i := 0 to High(FRegVariations) do
    if FRegVariations[i].GetVariable(name, value) then
      break;
end;

///////////////////////////////////////////////////////////////////////////////
end.
