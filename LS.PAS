{
 Segunda versi¢n del programa LS para DOS (tras perder los fuentes originales)

 Copyright 2019-2021 XWolfOverride

 Licensed under the MIT License

 Permission is hereby granted, free of charge, to any person obtaining a copy of this software
 and associated documentation files (the "Software"), to deal in the Software without restriction,
 including without limitation the rights to use, copy, modify, merge, publish, distribute,
 sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is
 furnished to do so, subject to the following conditions:

 The above copyright notice and this permission notice shall be included in all copies or
 substantial portions of the Software.

 THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING
 BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
 NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM,
 DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
}

{
 TODO:
  Rutas y wildcards, procesar rutas y wildcards por parametro
  ANSI support, el modo de colores emitirlo por c¢digos ansi y
  eliminar la escritura directa a hardware, eso permitir  mayor compatibilidad
  con otros modos. y eliminar la dependencia a TUI.PAS
  columnas de 20 caracteres para tener 2 columans en vido 40 y 4 en 80
  evitar saltos de l¡nea manuales en el listado de archivos.
}

Program ls2;

uses TUI,DOS;

type
 TFileName=string[12];
 TFileType=(ftDirectory,ftExecutable,ftMedia,ftOther);
 PFileRecord=^TFileRecord;
 TFileRecord=record
  name:TFileName;
  size:Longint;
  kind:TFileType;
  next:PFileRecord;
 end;

const
 {colors}
 colorDir=$09;
 colorExe=$0A;
 colorMedia=$05;
 colorOther=$07;
 colorResume=$0F;

 extExe=' EXE COM BAT ';
 extMedia=' ROM ZIP RAR ARJ ACE LHZ ';

var
 root:PFileRecord;
 cursor:PFileRecord;
 smode:byte; {0:name;1:size}
 dir:string;
 simple:boolean;

{ **************************************************************
  * Routine   : RedirectedStd                                  *
  * Purpose   : Return Yes (True) if standard handle is being  *
  *           : redirected.                                    *
  * Note(s)   : Even though handle can take any handle value,  *
  *           : the function will be meaningful only for the   *
  *           : standard input, standard output, and standard  *
  *           : error.  It will, however, be True for any      *
  *           : handle that does NOT point to the console.     *
  *           : (Besides, this is what it actually checks for.)*
  *           : Make sure handle belongs to an open file or    *
  *           : you will get wrong answer (check IOResult).    *
  ************************************************************** }
function RedirectedStd(handle: Word): Boolean; assembler;
const
  DEVICE       = $0080;
  FASTCONSOLE  = $0010;
  CONSOUT      = $0002;
  CONSIN       = $0001;
asm
  mov     InOutRes,0
  mov     ax,$4400       { IOCTL svc, get device information }
  mov     bx,handle
  int     $21            { result in DX }
  mov     ax,1           { assume function is True }
  jc      @Error         { got error with code in AX }
  test    dx,DEVICE
  jz      @Out
  test    dx,FASTCONSOLE
  jz      @Out
  test    dx,CONSOUT
  jz      @Out
  test    dx,CONSIN
  jz      @Out
  xor     ax,ax          { function is False }
  jmp     @Out
@Error:
  mov     InOutRes,ax
@Out:
end; { RedirectedStd }


function ToString(i:integer):string;
var buf:string;
begin
 str(i,buf);
 ToString:=buf;
end;

{Return true if N is prior to nto based on sort mode}
function PriorTo(n,nTo:PFileRecord):boolean;
begin
 case smode of
  0:PriorTo:=n^.name<nto^.name;
  1:PriorTo:=n^.size<nto^.size;
 end;
end;

{Add a record to the record list}
procedure AddRecord(name:TFileName;kind:TFileType;size:longint);
var
 i,p:integer;
 brk:boolean;
 n:PFileRecord;
begin
 new(n);
 n^.name:=name;
 n^.kind:=kind;
 n^.size:=size;
 i:=0;
 if root=nil then begin
  {First node on table, link directly}
  root:=n;
  cursor:=n;
  n^.next:=nil;
 end else begin
  {Search position by order}
  if PriorTo(n,root) then begin
   n^.next:=root;
   root:=n;
  end else begin
   if PriorTo(n,cursor) then
    cursor:=root;
   while (cursor^.next<>nil) and (not PriorTo(n,cursor^.next)) do
    cursor:=cursor^.next;
   n^.next:=cursor^.next;
   cursor^.next:=n;
  end;
 end;
end;

procedure CleanRecords;
var
 x,d:PFileRecord;
begin
 x:=root;
 while x<>nil do begin
  d:=x;
  x:=x^.next;
  release(d);
 end;
 root:=nil;
end;

{Scan directory}
procedure ReadDirectory;
var
 t:searchrec;
 p:byte;
 ext:string[5];
 dir:string;
begin
 CleanRecords;
 FindFirst('*.*',anyFile,T);
 while doserror=0 do begin
  if (t.name<>'.') then begin
   p:=pos('.',t.name);
   ext:=' '+copy(t.name,p+1,3)+' ';
   if (t.attr and directory)<>0 then
    AddRecord(t.name,ftDirectory,-1)
   else if pos(ext,extExe)>0 then
    AddRecord(t.name,ftExecutable,t.size)
   else if pos(ext,extMedia)>0 then
    AddRecord(t.name,ftMedia,t.size)
   else
    AddRecord(t.name,ftOther,t.size);
  end;
  FindNext(t);
 end;
end;

function FBytes(s:longint):string;
var
 n,u:string;
begin
 u:='b ';
 if s>1024 then begin s:=s div 1024;u:='Kb';end;
 if s>1024 then begin s:=s div 1024;u:='Mb';end;
 if s>1024 then begin s:=s div 1024;u:='Gb';end;
 str(s,n);
 FBytes:=n+u;
end;

procedure LSinit;
var
 ScreenMode:TScreenMode;
 i:integer;
 p:string;
 doHelp:boolean;
begin
 simple:=RedirectedSTD(TextRec(output).handle);
 GetDir(0,Dir);
 smode:=0; {1 si se especifica -s sino 0}
 doHelp:=false;

 {Process parameters}
 for i:=1 to paramcount do begin
  p:=paramstr(i);
  if (length(p)>1) and (p[1]='-') then begin
   {p:=copy(p,1,length(p)-1);}
   case p[2] of
    's':
     smode:=1;
    '1':
     simple:=true;
    'h':
     doHelp:=true;
   else
    doHelp:=true;
   end;
  end else
   dir:=p;
 end;

 if doHelp then begin
  Writeln('Unix directory listing style for DOS v2.0 by XWolfOverride (2020)');
  Writeln;
  Writeln('use: ls [path] [-s][-1][-help]');
  Writeln;
  Writeln(' path  Valid directory path or wildcard');
  Writeln(' -s    Sort by size (by default sort by name)');
  Writeln(' -1    Basic mode (default if output redirected or video mode unknown)');
  Writeln(' -help This help text');
  Halt;
 end;

 {Init}
 if not simple then begin
  ScreenMode:=GetScreenMode;
  if ScreenMode=smUnknown then
   simple:=true
  else
   UpdateScreenInfo;
 end;

 root:=nil;
 cursor:=nil;

end;

procedure LSprint;
var x,y,c,l:byte;
    sz:string;
    stotal:longint;
    cf,cd:integer;
begin
 cursor:=root;
 if not simple then begin
  GetCursorPosition(x,y);
  cd:=0;
  cf:=0;
  stotal:=0;
 end;
 while cursor<>nil do begin
  l:=length(cursor^.name);
  if Simple then begin
   {Modo simple}
   for l:=l to 12 do write(' ');
   write(cursor^.name);
   if cursor^.kind=ftDirectory then
    write('\')
   else
    write(' ',fbytes(cursor^.size));
   writeln;
  end else begin
   {Modo directo}
   case cursor^.kind of
    ftDirectory:
     c:=colorDir;
    ftExecutable:
     c:=colorExe;
    ftMedia:
     c:=colorMedia;
    ftOther:
     c:=colorOther;
   end;
   inc(x,12-l);
   DrawString(x,y,cursor^.name,c);
   inc(x,l);
   if cursor^.kind=ftDirectory then begin
    DrawString(x,y,'\',7);
    if cursor^.name<>'..' then
     inc(cd);
   end else begin
    sz:=fbytes(cursor^.size);
    DrawString(x+6-length(sz),y,sz,c);
    inc(cf);
    inc(stotal,cursor^.size);
   end;
   inc(x,7);
   if x=76 then begin
    writeln;
    GetCursorPosition(x,y);
   end;
  end;
  cursor:=cursor^.next;
 end;
 if not simple then begin
  if x>0 then
   writeln;
  GetCursorPosition(x,y);
  sz:='';
  if cf>0 then
   sz:=sz+fbytes(stotal)+' in '+ToString(cf)+' files, ';
  if cd>0 then
   sz:=sz+ToString(cd)+' sub-folders, ';
  if (cf=0) and (cd=0) then
   sz:=sz+'Empty folder, ';
  sz:=sz+fbytes(diskFree(0))+' free';
  DrawString(80-length(sz),y,sz,colorResume);
 end;
end;

begin
 LSinit;
 ReadDirectory;
 LSprint;
end.
