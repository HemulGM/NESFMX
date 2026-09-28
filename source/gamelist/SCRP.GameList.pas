unit SCRP.GameList;

interface

uses
  System.SysUtils, System.Classes, System.Generics.Collections, Xml.XMLIntf,
  Xml.XMLDoc, Xml.Internal.OmniXML;

type
  TGameProvider = class
  private
    FSystem: string;
    FSoftware: string;
    FDatabase: string;
    FWeb: string;
  public
    procedure Clear;

    procedure LoadFromXML(const ANode: IXMLNode);
    function SaveToXML(const AParent: IXMLNode): IXMLNode;

    property System: string read FSystem write FSystem;
    property Software: string read FSoftware write FSoftware;
    property Database: string read FDatabase write FDatabase;
    property Web: string read FWeb write FWeb;
  end;

  TGame = class
  private
    FID: string;
    FSource: string;

    FPath: string;
    FName: string;
    FDesc: string;
    FRating: string;
    FReleaseDate: string;
    FDeveloper: string;
    FPublisher: string;
    FGenreID: string;
    FGenre: string;
    FPlayers: string;
    FHash: string;
    FMD5: string;
    FImage: string;
    FBox: string;
    FThumbnail: string;
    FVideo: string;
    FManual: string;
    FFavorite: Boolean;
    FHasFavorite: Boolean;
  public
    constructor Create;
    procedure Clear;

    procedure LoadFromXML(const ANode: IXMLNode);
    function SaveToXML(const AParent: IXMLNode): IXMLNode;

    property ID: string read FID write FID;
    property Source: string read FSource write FSource;

    property Path: string read FPath write FPath;
    property Name: string read FName write FName;
    property Desc: string read FDesc write FDesc;
    property Rating: string read FRating write FRating;
    property ReleaseDate: string read FReleaseDate write FReleaseDate;
    property Developer: string read FDeveloper write FDeveloper;
    property Publisher: string read FPublisher write FPublisher;
    property GenreID: string read FGenreID write FGenreID;
    property Genre: string read FGenre write FGenre;
    property Players: string read FPlayers write FPlayers;
    property Hash: string read FHash write FHash;
    property MD5: string read FMD5 write FMD5;
    property Image: string read FImage write FImage;
    property Box: string read FBox write FBox;
    property Thumbnail: string read FThumbnail write FThumbnail;
    property Video: string read FVideo write FVideo;
    property Manual: string read FManual write FManual;

    property Favorite: Boolean read FFavorite write FFavorite;
    property HasFavorite: Boolean read FHasFavorite write FHasFavorite;
  end;

  TGameList = class
  private
    FProvider: TGameProvider;
    FGames: TObjectList<TGame>;
  public
    constructor Create;
    destructor Destroy; override;

    procedure Clear;

    procedure LoadFromXML(const ANode: IXMLNode);
    function SaveToXML(const ADocument: IXMLDocument): IXMLNode;

    procedure LoadFromFile(const AFileName: string);
    procedure SaveToFile(const AFileName: string);

    property Provider: TGameProvider read FProvider;
    property Games: TObjectList<TGame> read FGames;
  end;

implementation

{ ---------------------------------------------------------------------------
  XML helpers
  --------------------------------------------------------------------------- }

function XMLChild(const AParent: IXMLNode; const AName: string): IXMLNode;
begin
  Result := AParent.ChildNodes[AName];
end;

function XMLReadString(const AParent: IXMLNode; const AName: string): string;
var
  Node: IXMLNode;
begin
  Node := XMLChild(AParent, AName);

  if Assigned(Node) then
    Result := Node.Text
  else
    Result := '';
end;

function XMLReadAttribute(const ANode: IXMLNode; const AName: string): string;
begin
  Result := ANode.GetAttribute(AName);
end;

function XMLReadBool(const AParent: IXMLNode; const AName: string; const ADefault: Boolean = False): Boolean;
var
  S: string;
  Node: IXMLNode;
begin
  Node := XMLChild(AParent, AName);

  if not Assigned(Node) then
    Exit(ADefault);

  S := LowerCase(Trim(Node.Text));

  if S = '' then
    Exit(ADefault);

  Result :=
    (S = 'true') or
    (S = '1') or
    (S = 'yes');
end;

function XMLAddElement(const AParent: IXMLNode; const AName: string; const AValue: string): IXMLNode;
begin
  Result := AParent.OwnerDocument.CreateElement(AName, '');
  Result.Text := AValue;
  //AParent.AppendChild(Result);
end;

function XMLAddAttribute(const ANode: IXMLNode; const AName: string; const AValue: string): IXMLNode;
begin
  ANode.SetAttribute(AName, AValue);
  Result := ANode;
end;

function XMLBoolToString(const AValue: Boolean): string;
begin
  if AValue then
    Result := 'true'
  else
    Result := 'false';
end;

{ ---------------------------------------------------------------------------
  TGameProvider
  --------------------------------------------------------------------------- }

procedure TGameProvider.Clear;
begin
  FSystem := '';
  FSoftware := '';
  FDatabase := '';
  FWeb := '';
end;

procedure TGameProvider.LoadFromXML(const ANode: IXMLNode);
begin
  Clear;

  if not Assigned(ANode) then
    Exit;

  FSystem := XMLReadString(ANode, 'System');
  FSoftware := XMLReadString(ANode, 'software');
  FDatabase := XMLReadString(ANode, 'database');
  FWeb := XMLReadString(ANode, 'web');
end;

function TGameProvider.SaveToXML(const AParent: IXMLNode): IXMLNode;
begin
  Result := AParent.OwnerDocument.CreateElement('provider', '');
  //AParent.AppendChild(Result);

  XMLAddElement(Result, 'System', FSystem);
  XMLAddElement(Result, 'software', FSoftware);
  XMLAddElement(Result, 'database', FDatabase);
  XMLAddElement(Result, 'web', FWeb);
end;

{ ---------------------------------------------------------------------------
  TGame
  --------------------------------------------------------------------------- }

constructor TGame.Create;
begin
  inherited Create;
  Clear;
end;

procedure TGame.Clear;
begin
  FID := '';
  FSource := '';

  FPath := '';
  FName := '';
  FDesc := '';
  FRating := '';
  FReleaseDate := '';
  FDeveloper := '';
  FPublisher := '';
  FGenreID := '';
  FGenre := '';
  FPlayers := '';
  FHash := '';
  FMD5 := '';
  FImage := '';
  FBox := '';
  FThumbnail := '';
  FVideo := '';
  FManual := '';

  FFavorite := False;
  FHasFavorite := False;
end;

procedure TGame.LoadFromXML(const ANode: IXMLNode);
begin
  Clear;

  if not Assigned(ANode) then
    Exit;

  { Attributes }
  FID := XMLReadAttribute(ANode, 'id');
  FSource := XMLReadAttribute(ANode, 'source');

  { Fields }
  FPath := XMLReadString(ANode, 'path');
  FName := XMLReadString(ANode, 'name');
  FDesc := XMLReadString(ANode, 'desc');
  FRating := XMLReadString(ANode, 'rating');
  FReleaseDate := XMLReadString(ANode, 'releasedate');
  FDeveloper := XMLReadString(ANode, 'developer');
  FPublisher := XMLReadString(ANode, 'publisher');
  FGenreID := XMLReadString(ANode, 'genreid');
  FGenre := XMLReadString(ANode, 'genre');
  FPlayers := XMLReadString(ANode, 'players');
  FHash := XMLReadString(ANode, 'hash');
  FMD5 := XMLReadString(ANode, 'md5');
  FImage := XMLReadString(ANode, 'image');
  FBox := XMLReadString(ANode, 'box');
  FThumbnail := XMLReadString(ANode, 'thumbnail');
  FVideo := XMLReadString(ANode, 'video');
  FManual := XMLReadString(ANode, 'manual');

  { favorite is optional }
  if Assigned(XMLChild(ANode, 'favorite')) then
  begin
    FHasFavorite := True;
    FFavorite := XMLReadBool(ANode, 'favorite');
  end;
end;

function TGame.SaveToXML(const AParent: IXMLNode): IXMLNode;
begin
  Result := AParent.OwnerDocument.CreateElement('game', '');
  //AParent.AppendChild(Result);

  { Attributes }
  if FID <> '' then
    XMLAddAttribute(Result, 'id', FID);

  if FSource <> '' then
    XMLAddAttribute(Result, 'source', FSource);

  { Fields }
  if FPath <> '' then
    XMLAddElement(Result, 'path', FPath);

  if FName <> '' then
    XMLAddElement(Result, 'name', FName);

  if FDesc <> '' then
    XMLAddElement(Result, 'desc', FDesc);

  if FRating <> '' then
    XMLAddElement(Result, 'rating', FRating);

  if FReleaseDate <> '' then
    XMLAddElement(Result, 'releasedate', FReleaseDate);

  if FDeveloper <> '' then
    XMLAddElement(Result, 'developer', FDeveloper);

  if FPublisher <> '' then
    XMLAddElement(Result, 'publisher', FPublisher);

  if FGenreID <> '' then
    XMLAddElement(Result, 'genreid', FGenreID);

  if FGenre <> '' then
    XMLAddElement(Result, 'genre', FGenre);

  if FPlayers <> '' then
    XMLAddElement(Result, 'players', FPlayers);

  if FHash <> '' then
    XMLAddElement(Result, 'hash', FHash);

  if FMD5 <> '' then
    XMLAddElement(Result, 'md5', FMD5);

  if FImage <> '' then
    XMLAddElement(Result, 'image', FImage);

  if FBox <> '' then
    XMLAddElement(Result, 'box', FBox);

  if FThumbnail <> '' then
    XMLAddElement(Result, 'thumbnail', FThumbnail);

  if FVideo <> '' then
    XMLAddElement(Result, 'video', FVideo);

  if FManual <> '' then
    XMLAddElement(Result, 'manual', FManual);

  if FHasFavorite then
    XMLAddElement(Result, 'favorite', XMLBoolToString(FFavorite));
end;

{ ---------------------------------------------------------------------------
  TGameList
  --------------------------------------------------------------------------- }

constructor TGameList.Create;
begin
  inherited Create;

  FProvider := TGameProvider.Create;
  FGames := TObjectList<TGame>.Create(True);
end;

destructor TGameList.Destroy;
begin
  FGames.Free;
  FProvider.Free;

  inherited;
end;

procedure TGameList.Clear;
begin
  FProvider.Clear;
  FGames.Clear;
end;

procedure TGameList.LoadFromXML(const ANode: IXMLNode);
var
  Node: IXMLNode;
  Game: TGame;
begin
  Clear;

  if not Assigned(ANode) then
    Exit;

  { provider }
  Node := XMLChild(ANode, 'provider');

  if Assigned(Node) then
    FProvider.LoadFromXML(Node);

  { games }
  Node := ANode.ChildNodes['game'];

  while Assigned(Node) do
  begin
    Game := TGame.Create;

    try
      Game.LoadFromXML(Node);
      FGames.Add(Game);
    except
      Game.Free;
      raise;
    end;

    Node := Node.NextSibling;

    while Assigned(Node) and (Node.NodeType <> ntElement) do
      Node := Node.NextSibling;

    if Assigned(Node) and
      (Node.NodeName <> 'game') then
      Break;
  end;
end;

function TGameList.SaveToXML(const ADocument: IXMLDocument): IXMLNode;
var
  Root: IXMLNode;
  Game: TGame;
begin
  if not Assigned(ADocument) then
    raise EArgumentNilException.Create('ADocument');

  Root := ADocument.CreateElement('gameList', '');
  //ADocument.AppendChild(Root);

  FProvider.SaveToXML(Root);

  for Game in FGames do
    Game.SaveToXML(Root);

  Result := Root;
end;

procedure TGameList.LoadFromFile(const AFileName: string);
var
  XML: IXMLDocument;
  Root: IXMLNode;
begin
  XML := TXMLDocument.Create(nil);
  XML.LoadFromFile(AFileName);
  if not XML.Active then
    raise Exception.CreateFmt('Unable to load XML file: %s', [AFileName]);

  Root := XML.DocumentElement;

  if not Assigned(Root) then
    raise Exception.Create('XML document has no root element');

  if Root.NodeName <> 'gameList' then
    raise Exception.CreateFmt('Invalid root element "%s", expected "gameList"', [Root.NodeName]);

  LoadFromXML(Root);
end;

procedure TGameList.SaveToFile(const AFileName: string);
var
  XML: IXMLDocument;
begin
  XML := TXMLDocument.Create(nil);
  XML.Encoding := 'UTF-8';
  //XML.Standalone := True;

  SaveToXML(XML);

  try
    XML.SaveToFile(AFileName)
  except
    raise Exception.CreateFmt('Unable to save XML file: %s', [AFileName]);
  end;
end;

end.

