unit NES.Types;

interface

uses
  System.SysUtils;

type
  TByteArray = array of UInt8;

  TPalette32 = array[0..63] of UInt32;

  TFrameBuffer = array[0..255, 0..239] of UInt32;

  ENesException = class(Exception);

implementation

end.

