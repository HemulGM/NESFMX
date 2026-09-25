unit GBC.Joypad;

interface

uses
  System.SysUtils, GBC.InterruptManager;

{$SCOPEDENUMS ON}

type
  TGBCKey = (Up = 0, Down = 1, Left = 2, Right = 3, A = 4, B = 5, Select = 6, Start = 7);

type
  TGBCJoypad = class
  private
    class var
      FInstance: TGBCJoypad;
    class function GetInstance: TGBCJoypad; static;
  private
    FAPressed: Boolean;
    FBPressed: Boolean;
    FStartPressed: Boolean;
    FSelectPressed: Boolean;
    FUpPressed: Boolean;
    FDownPressed: Boolean;
    FLeftPressed: Boolean;
    FRightPressed: Boolean;
    FDPadSelected: Boolean;
  public
    KeyBindings: array[TGBCKey] of Integer;
    constructor Create; overload;
    function GetPressedKeys: Integer;
    procedure SetSelection(Value: Integer);
    procedure KeyDown(Key: Integer);
    procedure KeyUp(Key: Integer);
    class procedure ReleaseInstance;
    class property Instance: TGBCJoypad read GetInstance;
  end;

implementation

{ TGBCJoypad }

constructor TGBCJoypad.Create;
begin
  FAPressed := False;
  FBPressed := False;
  FStartPressed := False;
  FSelectPressed := False;
  FUpPressed := False;
  FDownPressed := False;
  FLeftPressed := False;
  FRightPressed := False;

  KeyBindings[TGBCKey.Up] := 87;
  KeyBindings[TGBCKey.Down] := 83;
  KeyBindings[TGBCKey.Left] := 65;
  KeyBindings[TGBCKey.Right] := 68;

  KeyBindings[TGBCKey.A] := 74;
  KeyBindings[TGBCKey.B] := 75;
  KeyBindings[TGBCKey.Select] := 90;
  KeyBindings[TGBCKey.Start] := 88;
end;

procedure TGBCJoypad.KeyDown(Key: Integer);
begin
  if Key = KeyBindings[TGBCKey.A] then
  begin
    if not FDPadSelected then
      TGBCInterruptManager.Instance.RaiseInterruptByIndex(0); //JoyPad_Input
    FAPressed := True;
  end
  else if Key = KeyBindings[TGBCKey.B] then
  begin
    if not FDPadSelected then
      TGBCInterruptManager.Instance.RaiseInterruptByIndex(0); //JoyPad_Input
    FBPressed := True;
  end
  else if Key = KeyBindings[TGBCKey.Start] then
  begin
    if not FDPadSelected then
      TGBCInterruptManager.Instance.RaiseInterruptByIndex(0); //JoyPad_Input
    FStartPressed := True;
  end
  else if Key = KeyBindings[TGBCKey.Select] then
  begin
    if not FDPadSelected then
      TGBCInterruptManager.Instance.RaiseInterruptByIndex(0); //JoyPad_Input
    FSelectPressed := True;
  end
  else if Key = KeyBindings[TGBCKey.Up] then
  begin
    if FDPadSelected then
      TGBCInterruptManager.Instance.RaiseInterruptByIndex(0); //JoyPad_Input
    FUpPressed := True;
  end
  else if Key = KeyBindings[TGBCKey.Down] then
  begin
    if FDPadSelected then
      TGBCInterruptManager.Instance.RaiseInterruptByIndex(0); //JoyPad_Input
    FDownPressed := True;
  end
  else if Key = KeyBindings[TGBCKey.Left] then
  begin
    if FDPadSelected then
      TGBCInterruptManager.Instance.RaiseInterruptByIndex(0); //JoyPad_Input
    FLeftPressed := True;
  end
  else if Key = KeyBindings[TGBCKey.Right] then
  begin
    if FDPadSelected then
      TGBCInterruptManager.Instance.RaiseInterruptByIndex(0); //JoyPad_Input
    FRightPressed := True;
  end;
end;

procedure TGBCJoypad.KeyUp(Key: Integer);
begin
  if Key = KeyBindings[TGBCKey.A] then
  begin
    FAPressed := False;
  end
  else if Key = KeyBindings[TGBCKey.B] then
  begin
    FBPressed := False;
  end
  else if Key = KeyBindings[TGBCKey.Start] then
  begin
    FStartPressed := False;
  end
  else if Key = KeyBindings[TGBCKey.Select] then
  begin
    FSelectPressed := False;
  end
  else if Key = KeyBindings[TGBCKey.Up] then
  begin
    FUpPressed := False;
  end
  else if Key = KeyBindings[TGBCKey.Down] then
  begin
    FDownPressed := False;
  end
  else if Key = KeyBindings[TGBCKey.Left] then
  begin
    FLeftPressed := False;
  end
  else if Key = KeyBindings[TGBCKey.Right] then
  begin
    FRightPressed := False;
  end;
end;

function TGBCJoypad.GetPressedKeys: Integer;
begin
  var Retval: Integer := $CF;
  if (FDPadSelected) then
  begin
    Retval := Retval or $20;
    if FDownPressed then       // Bit 3 - P13 Input Down  (0=Pressed)
      Retval := Retval and $F7
    else
      Retval := Retval and $FF;
    if FUpPressed then         // Bit 2 - P12 Input Up    (0=Pressed)
      Retval := Retval and $FB
    else
      Retval := Retval and $FF;

    if FLeftPressed then       // Bit 1 - P11 Input Left  (0=Pressed)
      Retval := Retval and $FD
    else
      Retval := Retval and $FF;
    if FRightPressed then      // Bit 0 - P10 Input Right (0=Pressed)
      Retval := Retval and $FE
    else
      Retval := Retval and $FF;
  end
  else
  begin
    Retval := Retval or $20;
    if FStartPressed then      //  Bit 3 - P13 Input Start    (0=Pressed)
      Retval := Retval and $F7
    else
      Retval := Retval and $FF;
    if FSelectPressed then     //Bit 2 - P12 Input Select   (0=Pressed)
      Retval := Retval and $FB
    else
      Retval := Retval and $FF;

    if FBPressed then          //Bit 1 - P11 Input Button B (0=Pressed)
      Retval := Retval and $FD
    else
      Retval := Retval and $FF;
    if FAPressed then          // Bit 0 - P10 Input Button A (0=Pressed)
      Retval := Retval and $FE
    else
      Retval := Retval and $FF;
  end;
  Result := Retval;
end;

class function TGBCJoypad.GetInstance: TGBCJoypad;
begin
  if FInstance = nil then
    FInstance := TGBCJoypad.Create;
  Result := FInstance;
end;

class procedure TGBCJoypad.ReleaseInstance;
begin
  FreeAndNil(FInstance);
end;

procedure TGBCJoypad.SetSelection(Value: Integer);
begin
  Value := Value and $30;
  if Value = $20 then
    FDPadSelected := True
  else if Value = $10 then
    FDPadSelected := False;
end;

end.

