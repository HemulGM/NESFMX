unit GB.Joypad;

interface

uses
  System.SysUtils, GB.InterruptManager;

{$SCOPEDENUMS ON}

type
  TGBKey = (Up = 0, Down = 1, Left = 2, Right = 3, A = 4, B = 5, Select = 6, Start = 7);

type
  TGBJoypad = class
  private
    class var
      FInstance: TGBJoypad;
    class function GetInstance: TGBJoypad; static;
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
    KeyBindings: array[TGBKey] of Integer;
    constructor Create; overload;
    function GetPressedKeys: Integer;
    procedure SetSelection(Value: Integer);
    procedure KeyDown(Key: Integer);
    procedure KeyUp(Key: Integer);
    class procedure ReleaseInstance;
    class property Instance: TGBJoypad read GetInstance;
  end;

implementation

{ TGBJoypad }

constructor TGBJoypad.Create;
begin
  FAPressed := False;
  FBPressed := False;
  FStartPressed := False;
  FSelectPressed := False;
  FUpPressed := False;
  FDownPressed := False;
  FLeftPressed := False;
  FRightPressed := False;

  KeyBindings[TGBKey.Up] := 87;
  KeyBindings[TGBKey.Down] := 83;
  KeyBindings[TGBKey.Left] := 65;
  KeyBindings[TGBKey.Right] := 68;

  KeyBindings[TGBKey.A] := 74;
  KeyBindings[TGBKey.B] := 75;
  KeyBindings[TGBKey.Select] := 90;
  KeyBindings[TGBKey.Start] := 88;
end;

procedure TGBJoypad.KeyDown(Key: Integer);
begin
  if Key = KeyBindings[TGBKey.A] then
  begin
    if not FDPadSelected then
      TGBInterruptManager.Instance.RaiseInterruptByIndex(0); //JoyPad_Input
    FAPressed := True;
  end
  else if Key = KeyBindings[TGBKey.B] then
  begin
    if not FDPadSelected then
      TGBInterruptManager.Instance.RaiseInterruptByIndex(0); //JoyPad_Input
    FBPressed := True;
  end
  else if Key = KeyBindings[TGBKey.Start] then
  begin
    if not FDPadSelected then
      TGBInterruptManager.Instance.RaiseInterruptByIndex(0); //JoyPad_Input
    FStartPressed := True;
  end
  else if Key = KeyBindings[TGBKey.Select] then
  begin
    if not FDPadSelected then
      TGBInterruptManager.Instance.RaiseInterruptByIndex(0); //JoyPad_Input
    FSelectPressed := True;
  end
  else if Key = KeyBindings[TGBKey.Up] then
  begin
    if FDPadSelected then
      TGBInterruptManager.Instance.RaiseInterruptByIndex(0); //JoyPad_Input
    FUpPressed := True;
  end
  else if Key = KeyBindings[TGBKey.Down] then
  begin
    if FDPadSelected then
      TGBInterruptManager.Instance.RaiseInterruptByIndex(0); //JoyPad_Input
    FDownPressed := True;
  end
  else if Key = KeyBindings[TGBKey.Left] then
  begin
    if FDPadSelected then
      TGBInterruptManager.Instance.RaiseInterruptByIndex(0); //JoyPad_Input
    FLeftPressed := True;
  end
  else if Key = KeyBindings[TGBKey.Right] then
  begin
    if FDPadSelected then
      TGBInterruptManager.Instance.RaiseInterruptByIndex(0); //JoyPad_Input
    FRightPressed := True;
  end;
end;

procedure TGBJoypad.KeyUp(Key: Integer);
begin
  if Key = KeyBindings[TGBKey.A] then
  begin
    FAPressed := False;
  end
  else if Key = KeyBindings[TGBKey.B] then
  begin
    FBPressed := False;
  end
  else if Key = KeyBindings[TGBKey.Start] then
  begin
    FStartPressed := False;
  end
  else if Key = KeyBindings[TGBKey.Select] then
  begin
    FSelectPressed := False;
  end
  else if Key = KeyBindings[TGBKey.Up] then
  begin
    FUpPressed := False;
  end
  else if Key = KeyBindings[TGBKey.Down] then
  begin
    FDownPressed := False;
  end
  else if Key = KeyBindings[TGBKey.Left] then
  begin
    FLeftPressed := False;
  end
  else if Key = KeyBindings[TGBKey.Right] then
  begin
    FRightPressed := False;
  end;
end;

function TGBJoypad.GetPressedKeys: Integer;
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

class function TGBJoypad.GetInstance: TGBJoypad;
begin
  if FInstance = nil then
    FInstance := TGBJoypad.Create;
  Result := FInstance;
end;

class procedure TGBJoypad.ReleaseInstance;
begin
  FreeAndNil(FInstance);
end;

procedure TGBJoypad.SetSelection(Value: Integer);
begin
  Value := Value and $30;
  if Value = $20 then
    FDPadSelected := True
  else if Value = $10 then
    FDPadSelected := False;
end;

end.
