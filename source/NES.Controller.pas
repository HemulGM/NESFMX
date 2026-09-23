unit NES.Controller;

interface

uses
  NES.State, NES.Types;

{$SCOPEDENUMS ON}

type
  TNesButton = (A, B, Select, Start, Up, Down, Left, Right);

  TNesButtons = set of TNesButton;

  TController = class
  private
    FState: UInt8;
    FShift: UInt8;
    FStrobe: Boolean;
    FPowerPadEnabled: Boolean;
    FPowerPadState: UInt16;
    FPowerPadLowShift: UInt8;
    FPowerPadHighShift: UInt8;
    procedure Latch;
  public
    procedure SerializeState(State: TNesStateArchive);
    procedure SetButton(Button: TNesButton; Pressed: Boolean);
    procedure SetPowerPadButton(Button: Integer; Pressed: Boolean);
    procedure Write(Value: UInt8);
    function Read: UInt8;
    property PowerPadEnabled: Boolean read FPowerPadEnabled write FPowerPadEnabled;
  end;

implementation

procedure TController.SerializeState(State: TNesStateArchive);
begin
  State.Field(FState, SizeOf(FState));
  State.Field(FShift, SizeOf(FShift));
  State.Field(FStrobe, SizeOf(FStrobe));
  State.Field(FPowerPadEnabled, SizeOf(FPowerPadEnabled));
  State.Field(FPowerPadState, SizeOf(FPowerPadState));
  State.Field(FPowerPadLowShift, SizeOf(FPowerPadLowShift));
  State.Field(FPowerPadHighShift, SizeOf(FPowerPadHighShift));
end;

procedure TController.Latch;
const
  LOW_BUTTONS: array[0..7] of Integer = (2, 1, 5, 9, 6, 10, 11, 7);
  HIGH_BUTTONS: array[0..3] of Integer = (4, 3, 12, 8);
begin
  FShift := FState;
  FPowerPadLowShift := 0;
  FPowerPadHighShift := $F0;
  for var i := 0 to High(LOW_BUTTONS) do
    if (FPowerPadState and (UInt16(1) shl (LOW_BUTTONS[i] - 1))) <> 0 then
      FPowerPadLowShift := FPowerPadLowShift or (UInt8(1) shl i);
  for var i := 0 to High(HIGH_BUTTONS) do
    if (FPowerPadState and (UInt16(1) shl (HIGH_BUTTONS[i] - 1))) <> 0 then
      FPowerPadHighShift := FPowerPadHighShift or (UInt8(1) shl i);
end;

procedure TController.SetButton(Button: TNesButton; Pressed: Boolean);
const
  MASKS: array[TNesButton] of UInt8 = ($01, $02, $04, $08, $10, $20, $40, $80);
begin
  if Pressed then
    FState := FState or MASKS[Button]
  else
    FState := FState and not MASKS[Button];

  if FStrobe then
    Latch;
end;

procedure TController.SetPowerPadButton(Button: Integer; Pressed: Boolean);
begin
  if (Button < 1) or (Button > 12) then
    Exit;
  var Mask := UInt16(1) shl (Button - 1);
  if Pressed then
    FPowerPadState := FPowerPadState or Mask
  else
    FPowerPadState := FPowerPadState and not Mask;
  if FStrobe then
    Latch;
end;

procedure TController.Write(Value: UInt8);
begin
  var NewStrobe: Boolean := (Value and 1) <> 0;
  if FStrobe and not NewStrobe then
    Latch;
  FStrobe := NewStrobe;
  if FStrobe then
    Latch;
end;

function TController.Read: UInt8;
begin
  if FStrobe then
    Latch;
  Result := FShift and 1;
  FShift := (FShift shr 1) or $80;
  if FPowerPadEnabled then
  begin
    Result := Result or ((FPowerPadLowShift and 1) shl 3)
      or ((FPowerPadHighShift and 1) shl 4);
    FPowerPadLowShift := (FPowerPadLowShift shr 1) or $80;
    FPowerPadHighShift := (FPowerPadHighShift shr 1) or $80;
  end;
end;

end.

