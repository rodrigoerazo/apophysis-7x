{
     Flame screensaver Copyright (C) 2002 Ronald Hordijk
     Apophysis Copyright (C) 2001-2004 Mark Townsend

     This program is free software; you can redistribute it and/or modify
     it under the terms of the GNU General Public License as published by
     the Free Software Foundation; either version 2 of the License, or
     (at your option) any later version.

     This program is distributed in the hope that it will be useful,
     but WITHOUT ANY WARRANTY; without even the implied warranty of
     MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
     GNU General Public License for more details.

     You should have received a copy of the GNU General Public License
     along with this program; if not, write to the Free Software
     Foundation, Inc., 675 Mass Ave, Cambridge, MA 02139, USA.
}
unit RenderThread;

interface

uses
  Classes, windows, Messages, Graphics,
   controlPoint, Render, Render32, Render64, RenderMM;

const
  WM_THREAD_COMPLETE = WM_APP + 5437;
  WM_THREAD_TERMINATE = WM_APP + 5438;

type
  TRenderThread = class(TThread)
  private
    FRenderer: TBaseRenderer;

    FOnProgress: TOnProgress;
    FCP: TControlPoint;
    Fcompatibility: Integer;
    FMaxMem: int64;

    procedure Render;
    function GetNrSlices: integer;
    function GetSlice: integer;
    procedure Setcompatibility(const Value: Integer);
    procedure SetMaxMem(const Value: int64);
  public
    TargetHandle: HWND;

    constructor Create;
    destructor Destroy; override;

    procedure SetCP(CP: TControlPoint);
    function GetImage: TBitmap;
    procedure Execute; override;

    procedure Terminate;

    property OnProgress: TOnProgress
      read FOnProgress
      write FOnProgress;

    property Slice: integer
        read GetSlice;
    property NrSlices: integer
        read GetNrSlices;
    property MaxMem: int64
        read FMaxMem
       write SetMaxMem;
    property compatibility: Integer
        read Fcompatibility
       write Setcompatibility;
  end;

implementation

uses
  Math, Sysutils;

{ TRenderThread }

///////////////////////////////////////////////////////////////////////////////
destructor TRenderThread.Destroy;
begin
  if assigned(FRenderer) then
    FRenderer.Free;

  inherited;
end;

///////////////////////////////////////////////////////////////////////////////
function TRenderThread.GetImage: TBitmap;
begin
  Result := nil;
  if assigned(FRenderer) then
    Result := FRenderer.GetImage;
end;

///////////////////////////////////////////////////////////////////////////////
procedure TRenderThread.SetCP(CP: TControlPoint);
begin
  FCP := CP;
end;

///////////////////////////////////////////////////////////////////////////////
constructor TRenderThread.Create;
begin
  MaxMem := 0;
  FreeOnTerminate := False;
  inherited Create(True);               // Create Suspended;
end;

///////////////////////////////////////////////////////////////////////////////
procedure TRenderThread.Render;
begin
  if assigned(FRenderer) then
    FRenderer.Free;

  if MaxMem = 0 then begin
    FRenderer := TRenderer64.Create;
  end else begin
    FRenderer := TRendererMM64.Create;
    FRenderer.MaxMem := MaxMem
  end;

  FRenderer.SetCP(FCP);
  FRenderer.compatibility := compatibility;
  FRenderer.OnProgress := FOnProgress;
  Frenderer.Render;
end;

///////////////////////////////////////////////////////////////////////////////
procedure TRenderThread.Execute;
begin
  Render;

  if Terminated then
    PostMessage(TargetHandle, WM_THREAD_TERMINATE, 0, 0)
  else
    PostMessage(TargetHandle, WM_THREAD_COMPLETE, 0, 0);
end;

///////////////////////////////////////////////////////////////////////////////
procedure TRenderThread.Terminate;
begin
  inherited Terminate;

  if assigned(FRenderer) then
    FRenderer.Stop;
end;

///////////////////////////////////////////////////////////////////////////////
function TRenderThread.GetNrSlices: integer;
begin
  if assigned(FRenderer) then
    Result := FRenderer.Nrslices
  else
    Result := 1;
end;

///////////////////////////////////////////////////////////////////////////////
function TRenderThread.GetSlice: integer;
begin
  if assigned(FRenderer) then
    Result := FRenderer.Slice
  else
    Result := 1;
end;

///////////////////////////////////////////////////////////////////////////////
procedure TRenderThread.Setcompatibility(const Value: Integer);
begin
  Fcompatibility := Value;
end;

///////////////////////////////////////////////////////////////////////////////
procedure TRenderThread.SetMaxMem(const Value: int64);
begin
  FMaxMem := Value;
end;

///////////////////////////////////////////////////////////////////////////////
end.
