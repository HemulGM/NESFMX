unit NES.Controller;

interface

uses
  NES.Types;

type
  TNesButton = (nbA, nbB, nbSelect, nbStart, nbUp, nbDown, nbLeft, nbRight);

  TController = class
  private
    FState: UInt8;
    FShift: UInt8;
    FStrobe: Boolean;
  public
    procedure SetButton(Button: TNesButton; Pressed: Boolean);
    procedure Write(Value: UInt8);
    function Read: UInt8;
  end;

implementation

procedure TController.SetButton(Button: TNesButton; Pressed: Boolean);
const
  MASKS: array[TNesButton] of UInt8 = ($01, $02, $04, $08, $10, $20, $40, $80);
begin
  if Pressed then
    FState := FState or MASKS[Button]
  else
    FState := FState and not MASKS[Button];

  if FStrobe then
    FShift := FState;
end;

procedure TController.Write(Value: UInt8);
begin
  var NewStrobe: Boolean := (Value and 1) <> 0;
  if FStrobe and not NewStrobe then
    FShift := FState;
  FStrobe := NewStrobe;
  if FStrobe then
    FShift := FState;
end;

function TController.Read: UInt8;
begin
  if FStrobe then
    Exit(FState and 1);
  Result := FShift and 1;
  FShift := (FShift shr 1) or $80;
end;

end.
