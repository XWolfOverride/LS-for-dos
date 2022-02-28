unit TUI;{Text User Interface}

{$G-}

{
 TUI, Text User Interface library for DOS
 
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

INTERFACE

{=== Util}
function  GetAttribute(fg,bg:byte):byte;
function  GetCharInfo(ch:char;attribute:byte):word;

{=== Screen}
type
 TScreenInfo=record
  width:byte;
  height:byte;
 end;
 TScreenMode=(smUnknown,smLow,smNormal,smHigh);
 TBoxMode=(bmNone,bmSingle,bmDouble,bmText);

var
 ScreenInfo:TScreenInfo;
 ScreenW: array[0..4000] of word absolute $b800:0000;

function  GetScreenLines:byte;
function  GetScreenMode:TScreenMode;
procedure SetScreenMode(mode:TScreenMode);
procedure UpdateScreenInfo;
procedure ShowCursor(b:boolean);
procedure SetCursorPosition(x,y:byte);
procedure GetCursorPosition(var x,y:byte);
procedure Blink(b:boolean);
procedure SaveScreen(var buffer);
procedure RestoreScreen(var buffer);

{=== Keyboard}
function  GetKey:char;

{=== Mouse}
procedure InitMouse;
procedure ShowMouse;
procedure HideMouse;
procedure SetMouseSpeed(horizontal,vertical:word);
procedure SetMouseRange(xmin,xmax,ymin,ymax:word);
procedure SetMouseCursor(hardware:boolean;andmask:word;xormask:word);
procedure GetMouse(var x,y:word;var bl,br,bm:boolean;var scrl:integer);


{=== Render}
procedure ClearScreen;
procedure FillScreen(CharInfo:word);
procedure Fill(x,y:byte;length,charinfo:word);
procedure DrawChar(x,y:byte;charinfo:word);
procedure DrawString(x,y:byte;s:string;attr:byte);
procedure DrawBox(x,y,width,height:byte;mode:TBoxMode;attr:byte;fill:boolean);

IMPLEMENTATION
uses XWMem;

var
 ScanCode:Byte;


{=========================================================Util}
{====== INTERNAL}
{====== PUBLISHED}

function GetAttribute(fg,bg:byte):byte;
begin
 GetAttribute:=(bg shl 4) or (fg and $0f);
end;

function GetCharInfo(ch:char;attribute:byte):word;
begin
 GetCharInfo:=byte(ch) or (attribute shl 8);
end;

{=========================================================Screen}
{====== INTERNAL}
{====== PUBLISHED}

function GetScreenLines:byte;
var
 lines:byte;
begin
 asm
  mov ax,1130h
  xor bh,bh
  xor dl,dl
  push si
  push di
  push bp
  push es
  int 10h
  pop es
  pop bp
  pop di
  pop si
  mov lines,dl
 end;
 if lines<=25 then
  lines:=25
 else if lines < 44 then
   lines:=43
  else
   lines:=50;
 GetScreenLines:=lines;
end;

function GetScreenMode:TScreenMode;
begin
 UpdateScreenInfo;
 case ScreenInfo.width of
  40:
   GetScreenMode:=smLow;
  80:
   if ScreenInfo.height=25 then
    GetScreenMode:=smNormal
   else
    GetScreenMode:=smHigh;
  else
   GetScreenMode:=smUnknown;
 end;
end;

procedure SetScreenMode(mode:TScreenMode);
begin
 case mode of
  smLow:asm
   mov ax,01h
   int 10h
  end;
  smNormal:asm
   mov ax,03h
   int 10h
  end;
  smHigh:asm
   mov ax,03h
   int 10h
   mov ax,1112h
   xor bl,bl
   push si
   push di
   push bp
   push es
   int 10h
   pop es
   pop bp
   pop di
   pop si
  end;
 end;
 UpdateScreenInfo;
end;

procedure UpdateScreenInfo;
var
 mode: ^byte;
begin
 mode:= Ptr($40, $49);
 case mode^ of
  $00,$01:begin
   ScreenInfo.width:=40;
   ScreenInfo.height:=25;
  end;
  $02,$03,$07:begin
   ScreenInfo.width:=80;
   ScreenInfo.height:=GetScreenLines;
  end;
  else begin
   ScreenInfo.width:=$ff;
   ScreenInfo.height:=$ff;
  end;
 end;
end;

procedure ShowCursor(b:boolean);
begin
 if b then
 asm
  mov ah,03h
  xor bx,bx
  int 10h
  or ch,0ffh-20h
  mov ax,0100h
  xor bx,bx
  int 10h
 end
 else
 asm
  mov ah,03h
  xor bx,bx
  int 10h
  or ch,20h
  mov ax,0100h
  xor bx,bx
  int 10h
 end
end;

procedure SetCursorPosition(x,y:byte);
begin
 asm
  mov ah,02h
  xor bh,bh
  mov dh,x
  mov dl,y
  int 10h
 end;
end;

procedure GetCursorPosition(var x,y:byte);
var
 xx,yy:byte;
begin
 asm
  mov ah,03h
  xor bh,bh
  int 10h
  mov xx,dl
  mov yy,dh
 end;
 x:=xx;
 y:=yy;
end;

procedure Blink(b:boolean);
begin
 if b then
  asm
   MOV   DX,003DAh   { CRTC Status register                     }
   IN    AL,DX       { Read CRTC Status. (This will reset)      }
                     { the Attribute controller flip-flop)      }
{ ; ===== Set blink bit =====                                   }
   MOV   DX,003C0h   { Attribute controller (Write port)        }
   MOV   AL,10h+20h  { Register 10h (Mode control)              }
                     { leave PAS field enabled.                 }
   OUT   DX,AL       { Activate register 10h                    }
   INC   DX          { DX=003C1h (Attribute READ port)          }
   IN    AL,DX       { Read Mode control register               }
   DEC   DX          { DX=003C0h (Attribute Write port)         }
   OR    AL,008h     { Set blink bit                            }
   OUT   DX,AL       { Rewrite Mode control register            }
  end else asm
   MOV   DX,003DAh   { CRTC Status register                     }
   IN    AL,DX       { Read CRTC Status. (This will reset       }
                     { the Attribute controller flip-flop)      }
{ ; ===== Set blink bit =====                                   }
   MOV   DX,003C0h   { Attribute controller (Write port)        }
   MOV   AL,10h+20h  { Register 10h (Mode control)              }
                     { leave PAS field enabled.                 }
   OUT   DX,AL       { Activate register 10h                    }
   INC   DX          { DX=003C1h (Attribute READ port)          }
   IN    AL,DX       { Read Mode control register               }
   DEC   DX          { DX=003C0h (Attribute Write port)         }
   AND   AL,NOT 008h { Clear blink bit                          }
   OUT   DX,AL       { Rewrite Mode control register            }
  end;
end;

procedure SaveScreen(var buffer);
begin
 CopyW(ScreenW,buffer,ScreenInfo.width*ScreenInfo.height);
end;

procedure RestoreScreen(var buffer);
begin
 CopyW(buffer,ScreenW,ScreenInfo.width*ScreenInfo.height);
end;

{=========================================================Keyboard}
{====== INTERNAL}
{====== PUBLISHED}

function GetKey:char;
var
 b:byte;
begin
 if ScanCode <> 0 then begin
  GetKey:=char(ScanCode);
  ScanCode:=0;
  exit;
 end;
 asm
  xor ax,ax
  int 16h
  mov b,al
 end;
 if b=0 then asm
  mov ScanCode,ah
 end;
 GetKey:=char(b);
end;

{=========================================================Mouse}
{====== INTERNAL}
{====== PUBLISHED}

procedure InitMouse;
begin
 asm
  xor ax,ax
  int 33h   {Init mouse driver}
 end;
 ShowMouse;
 SetMouseSpeed(8,16);
 setMouseRange(0,640,0,200);
end;

procedure ShowMouse; assembler;
asm
 mov ax,1
 int 33h
end;

procedure HideMouse; assembler;
asm
 mov ax,2
 int 33h
end;

procedure SetMouseSpeed(horizontal,vertical:word); assembler;
asm
 mov ax,0fh
 mov cx,horizontal
 mov dx,vertical
 int 33h
end;

procedure SetMouseRange(xmin,xmax,ymin,ymax:word); assembler;
asm
 mov ax,07h
 mov cx,xmin
 mov dx,xmax
 int 33h
 mov ax,08h
 mov cx,ymin
 mov dx,ymax
 int 33h
end;

procedure SetMouseCursor(hardware:boolean;andmask:word;xormask:word);
var b:word;
begin
 if hardware then
  b:=1 else b:=0;
 asm
  mov ax,000ah
  mov bx,b
  mov cx,andmask
  mov dx,xormask
  int 33h
 end;
end;

procedure GetMouse(var x,y:word;var bl,br,bm:boolean;var scrl:integer);
var c,d,b:word;
begin
 asm
  mov ax,03h
  int 33h
  mov b,bx
  mov c,cx
  mov d,dx
 end;
 x:=c shr 1;
 y:=d;
 bl:=(b and 1)=1;
 br:=(b and 2)=2;
 bm:=(b and 4)=4;
end;


{=========================================================Render}
{====== INTERNAL}
{====== PUBLISHED}

procedure ClearScreen;
begin
 FillScreen($0700);
end;

procedure FillScreen(charinfo:word);
begin
 FillW(ScreenW,ScreenInfo.width*ScreenInfo.height,charinfo);
end;

procedure Fill(x,y:byte;length,charinfo:word);
begin
 FillW(ScreenW[(y*ScreenInfo.width)+x],length,charinfo);
end;

procedure DrawChar(x,y:byte;charinfo:word);
begin
 ScreenW[(y*ScreenInfo.width)+x]:=charinfo;
end;

procedure DrawString(x,y:byte;s:string;attr:byte);
var
 pos,charinfo:word;
 i:byte;
 ch:^char;
begin
  if length(s)=0 then
    exit;
 pos:=(y*ScreenInfo.width)+x;
 charinfo:=attr shl 8;
 ch:=@charinfo;
 for i:=0 to length(s)-1 do begin
  ch^:=s[i+1];
  ScreenW[pos]:=charinfo;
  inc(pos);
 end;
end;

procedure DrawBox(x,y,width,height:byte;mode:TBoxMode;attr:byte;fill:boolean);
var
 boxinfo:string[6];
 charinfo:word;
 ch:^char;
 i:integer;
begin
 if (width=0) or (height=0) then
  exit;
 charinfo:=attr shl 8;
 ch:=@charinfo;
 dec(width);
 dec(height,2);
 case mode of
  bmNone:   boxinfo:=#0#0#0#0#0#0;
  bmSingle: boxinfo:=#218#191#217#192#179#196;
  bmDouble: boxinfo:='/\/\|-';
  bmText:   boxinfo:='/\/\|-';
 end;
 ch^:=boxinfo[1];
 DrawChar(x,y,charinfo);
 ch^:=boxinfo[6];
 Tui.Fill(x+1,y,width-1,charinfo);
 ch^:=boxinfo[2];
 DrawChar(x+width,y,charinfo);
 for i:=0 to height-1 do begin
  inc(y);
  ch^:=boxinfo[5];
  DrawChar(x,y,charinfo);
  DrawChar(x+width,y,charinfo);
  if fill then begin
   ch^:=#0;
   Tui.Fill(x+1,y,width-1,charinfo);
  end
 end;
 inc(y);
 ch^:=boxinfo[4];
 DrawChar(x,y,charinfo);
 ch^:=boxinfo[6];
 Tui.Fill(x+1,y,width-1,charinfo);
 ch^:=boxinfo[3];
 DrawChar(x+width,y,charinfo);

end;

begin
end.