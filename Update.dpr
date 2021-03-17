program Update;

{$APPTYPE CONSOLE}

{$R *.res}

uses
  System.SysUtils, System.Classes, IdComponent, IdHTTP, Vcl.Dialogs, System.JSON,
  IdMultipartFormData, Registry, Winapi.Windows, ShellApi, TlHelp32;

type
  TFilePaths = record
    link : string;
    path : string;
  end;

const
  regKey = 'Software\StashPic\';

var
  list : array of TFilePaths;
  baseDir : string;
  stream: TMemoryStream;
  http: TIdHTTP;
  downloadErrors : boolean = false;

function processCount(exeFileName: string): integer;
var
  ContinueLoop: BOOL;
  FSnapshotHandle: THandle;
  FProcessEntry32: TProcessEntry32;
begin
  FSnapshotHandle := CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS, 0);
  FProcessEntry32.dwSize := SizeOf(FProcessEntry32);
  ContinueLoop := Process32First(FSnapshotHandle, FProcessEntry32);
  Result := 0;
  while Integer(ContinueLoop) <> 0 do
  begin
    if ((UpperCase(ExtractFileName(FProcessEntry32.szExeFile)) =
      UpperCase(ExeFileName)) or (UpperCase(FProcessEntry32.szExeFile) =
      UpperCase(ExeFileName))) then inc(Result);
    ContinueLoop := Process32Next(FSnapshotHandle, FProcessEntry32);
  end;
  CloseHandle(FSnapshotHandle);
end;


procedure getInetFilesList();
var
  JSONValue: TJSONValue;
  JsonNestedObject: TJSONObject;
  response: string;
  formData: TIdMultiPartFormDataStream;
  idHTTP : TIdHTTP;
  reg : TRegistry;
  updateToken : string;
begin
  IdHTTP := TIdHTTP.Create;
  formData := TIdMultiPartFormDataStream.Create;

  reg := TRegistry.Create(KEY_READ);
  reg.OpenKey(regKey, False);
  updateToken := reg.ReadString('updateToken');
  reg.CloseKey();
  reg.Free;

  formData.AddFormField('updateToken', updateToken);
  response := IdHTTP.Post('http://stashmap.net/stashpic/update', formData);
  JSONValue := TJSONObject.ParseJSONValue(response).AsType<TJSONObject>;
  JsonNestedObject := JSONValue.FindValue('files').AsType<TJSONObject>;
  with JsonNestedObject.GetEnumerator do
    while MoveNext do
    begin
      SetLength(list, length(list)+1);
      list[length(list)-1].link := (Current.JSONValue as TJSONObject).Values['fileLink'].Value;
      list[length(list)-1].path := (Current.JSONValue as TJSONObject).Values['filePlace'].Value;
    end;
  IdHTTP.Destroy;
  formData.Destroy;
end;


function GetInetFileSize(const FileUrl: string): integer;
var
  IdHTTP: TIdHTTP;
begin
  result := -1;
  IdHTTP := TIdHTTP.Create(nil);
  try
    IdHTTP.Head(FileUrl);
    if IdHTTP.ResponseCode = 200 then
      result := IdHTTP.Response.ContentLength;
  except
    IdHTTP.Free;
  end;
end;

begin
  try
    if processCount('StashPic.exe') > 0 then
    begin
      Writeln('StashPic completion pending...');
      while processCount('StashPic.exe') > 0 do sleep(3000);
    end;

    Writeln('The update starts... ');
    baseDir := ExtractFileDir(ParamStr(0));
    getInetFilesList();
    while length(list) > 0 do
    begin
      http := TIdHTTP.Create(nil);
      stream := TMemoryStream.Create;
      if GetInetFileSize(list[length(list)-1].link) > 0 then
        try
          http.get(list[length(list)-1].link, stream);
          if not DirectoryExists(ExtractFileDir(baseDir + '\' + list[length(list)-1].path)) then
            forcedirectories(ExtractFileDir(baseDir + '\' + list[length(list)-1].path));
          stream.SaveToFile(baseDir + '\' + list[length(list)-1].path);
          SetLength(list, length(list)-1);
        except
          FreeAndNil(http);
          FreeAndNil(stream);
        end
      else
        downloadErrors := true;
    end;
    if downloadErrors then
    begin
      Writeln('Error while downloading file(s)! Run Update.exe again in a couple of minutes. If errors persist, please contact support ');
      Readln;
    end;

    ShellExecute(0, 'open', Pchar( baseDir + '\StashPic.exe'), nil, nil, SW_SHOWNORMAL) ;

  except
    on E: Exception do
    begin
      Writeln(E.ClassName, ': ', E.Message);
      Readln;
    end;


  end;
end.
