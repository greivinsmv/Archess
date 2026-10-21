; arChess graphical client. All UI, hit testing and legal hints are MASM/Win32.
INCLUDE arChess.inc
INCLUDE gui_win32.inc
Sync_ObtenerSnapshot PROTO
WndProc PROTO :DWORD,:DWORD,:DWORD,:DWORD
NetWorker PROTO :DWORD
PaintScene PROTO :DWORD
PaintButton PROTO :DWORD
DrawLabel PROTO :DWORD,:DWORD,:DWORD,:DWORD,:DWORD,:DWORD,:DWORD,:DWORD
FillBox PROTO :DWORD,:DWORD,:DWORD,:DWORD,:DWORD,:DWORD
StartJob PROTO :DWORD
ChooseSquare PROTO :DWORD
RefreshBoard PROTO
ComputeLegal PROTO
StartLocal PROTO
EXTERN _imp__SetTextColor@8:DWORD

.data
className BYTE 'arChessMasmWindowV3',0
titleText BYTE 'arChess | MASM + Firebase',0
fontName BYTE 'Segoe UI',0
pieceFontName BYTE 'Segoe UI Symbol',0
buttonClass BYTE 'BUTTON',0
brand BYTE 'arChess',0
tagline BYTE 'Tu proxima jugada empieza aqui.',0
boardLabel BYTE 'EL TABLERO',0
roomLabel BYTE 'SALA COMPARTIDA  /  prueba',0
roleWhite BYTE 'JUEGAS CON BLANCAS',0
roleBlack BYTE 'JUEGAS CON NEGRAS',0
roleLocal BYTE 'DOS JUGADORES EN ESTA PC',0
modeLabel BYTE 'Elige como quieres jugar',0
whiteLabel BYTE 'Crear / retomar con blancas',0
blackLabel BYTE 'Unirme con negras',0
localLabel BYTE 'Partida local',0
resignLabel BYTE 'Rendirme',0
txtDrawButton BYTE 'Ofrecer / aceptar tablas',0
flipLabel BYTE 'Girar tablero',0
newLabel BYTE 'Volver al inicio',0
selectHelp BYTE 'Selecciona una pieza tuya y toca una casilla marcada.',0
legend BYTE 'Punto: movimiento legal   /   Aro: captura',0
statusIdle BYTE 'Listo para jugar',0
statusConnect BYTE 'Conectando con la sala...',0
statusBusy BYTE 'Enviando jugada...',0
statusWaiting BYTE 'Esperando al rival',0
statusOwn BYTE 'Tu turno',0
statusWhite BYTE 'Turno de blancas',0
statusBlack BYTE 'Turno de negras',0
statusCheck BYTE 'Tu rey esta en jaque.',0
statusMate BYTE 'Jaque mate. Partida terminada.',0
statusStale BYTE 'Tablas por rey ahogado.',0
statusFinished BYTE 'Partida terminada',0
statusOffline BYTE 'Sin conexion. Reintentando...',0
statusInvalid BYTE 'Selecciona una pieza de tu color.',0
closeQuestion BYTE 'Salir termina tu participacion. Si estas conectado, te rendiras. Deseas salir?',0
resignQuestion BYTE 'Quieres rendirte en esta partida?',0
waitQuestion BYTE 'Hay una solicitud en curso. Espera a que termine antes de cerrar.',0
promoQuestion BYTE 'Elige la pieza de promocion en el panel derecho.',0
promoQ BYTE 'Dama',0
promoR BYTE 'Torre',0
promoB BYTE 'Alfil',0
promoN BYTE 'Caballo',0
statusText BYTE 256 DUP(0)
detailText BYTE 256 DUP(0)
workerText BYTE 256 DUP(0)
boardView BYTE 64 DUP('.')
legalSquares BYTE 64 DUP(0)
selected SDWORD -1
queuedSquare SDWORD -1
lastFrom SDWORD -1
lastTo SDWORD -1
moveFrom DWORD 0
moveTo DWORD 0
promotion BYTE 'Q'
promoPending DWORD 0
mode DWORD 0                 ; 0 menu, 1 local, 2 online
myColor DWORD 0
orientation DWORD 0
canMove DWORD 0
finished DWORD 0
busy DWORD 0
job DWORD 0
jobResult DWORD 0
closing DWORD 0
hasError DWORD 0
netVersion DWORD -1
netState DWORD 0
ackPending DWORD 0
instance DWORD 0
window DWORD 0
threadId DWORD 0
fontTitle DWORD 0
fontBody DWORD 0
fontSmall DWORD 0
fontPiece DWORD 0
fontStatus DWORD 0
wc WNDCLASSX <>
msg WINMSG <>
btnWhite DWORD 0
btnBlack DWORD 0
btnLocal DWORD 0
btnResign DWORD 0
btnDraw DWORD 0
btnFlip DWORD 0
btnNew DWORD 0
btnPromoQ DWORD 0
btnPromoR DWORD 0
btnPromoB DWORD 0
btnPromoN DWORD 0
pieceLetters BYTE 'KQRBNPkqrbnp',0
pieceGlyphs WORD 265Ah,265Bh,265Ch,265Dh,265Eh,265Fh,265Ah,265Bh,265Ch,265Dh,265Eh,265Fh

.code
main PROC
IFDEF GUI_TEST
    call GuiSelfTest
    test eax,eax
    jnz gui_tests_exit
    call GuiFixtureTest
gui_tests_exit:
    invoke ExitProcess,eax
ENDIF
    call Sync_Inicializar
    invoke GetModuleHandleA,0
    mov instance,eax
    mov wc.hInstance,eax
    mov wc.style,3
    mov wc.lpfnWndProc,OFFSET WndProc
    mov wc.lpszClassName,OFFSET className
    invoke LoadCursorA,0,32512
    mov wc.hCursor,eax
    invoke RegisterClassA,ADDR wc
    invoke CreateFontA,36,0,0,0,700,0,0,0,1,0,0,5,0,ADDR fontName
    mov fontTitle,eax
    invoke CreateFontA,19,0,0,0,400,0,0,0,1,0,0,5,0,ADDR fontName
    mov fontBody,eax
    invoke CreateFontA,14,0,0,0,500,0,0,0,1,0,0,5,0,ADDR fontName
    mov fontSmall,eax
    invoke CreateFontA,27,0,0,0,600,0,0,0,1,0,0,5,0,ADDR fontName
    mov fontStatus,eax
    invoke CreateFontA,54,0,0,0,400,0,0,0,1,0,0,5,0,ADDR pieceFontName
    mov fontPiece,eax
    call InicializarTablero
    call IniciarTurnos
    call RefreshBoard
    invoke lstrcpynA,ADDR statusText,ADDR statusIdle,256
    invoke CreateWindowExA,0,ADDR className,ADDR titleText,02CA0000h,100,40,1016,750,0,0,instance,0
    mov window,eax
    invoke ShowWindow,window,5
    invoke UpdateWindow,window
main_messages:
    invoke GetMessageA,ADDR msg,0,0,0
    cmp eax,0
    jle main_done
    invoke TranslateMessage,ADDR msg
    invoke DispatchMessageA,ADDR msg
    jmp main_messages
main_done:
    invoke DeleteObject,fontTitle
    invoke DeleteObject,fontBody
    invoke DeleteObject,fontSmall
    invoke DeleteObject,fontStatus
    invoke DeleteObject,fontPiece
    invoke ExitProcess,0
main ENDP

CreateButton PROC textPtr:DWORD,ident:DWORD,posY:DWORD
    invoke CreateWindowExA,0,ADDR buttonClass,textPtr,5000000Bh,602,posY,344,42,window,ident,instance,0
    ret
CreateButton ENDP

WndProc PROC USES ebx esi edi hwnd:DWORD,message:DWORD,wparam:DWORD,lparam:DWORD
    LOCAL ps:PAINTX
    LOCAL dc:DWORD
    mov eax,message
    cmp eax,1
    je wm_create
    cmp eax,0Fh
    je wm_paint
    cmp eax,14h
    je wm_erase
    cmp eax,2Bh
    je wm_drawitem
    cmp eax,111h
    je wm_command
    cmp eax,201h
    je wm_click
    cmp eax,113h
    je wm_timer
    cmp eax,8001h
    je wm_network
    cmp eax,10h
    je wm_close
    cmp eax,2
    je wm_destroy
    invoke DefWindowProcA,hwnd,message,wparam,lparam
    ret
wm_create:
    mov eax,hwnd
    mov window,eax
    invoke CreateButton,ADDR whiteLabel,101,248
    mov btnWhite,eax
    invoke CreateButton,ADDR blackLabel,102,298
    mov btnBlack,eax
    invoke CreateButton,ADDR localLabel,103,348
    mov btnLocal,eax
    invoke CreateButton,ADDR resignLabel,104,448
    mov btnResign,eax
    invoke CreateButton,ADDR txtDrawButton,105,498
    mov btnDraw,eax
    invoke CreateButton,ADDR flipLabel,106,548
    mov btnFlip,eax
    invoke CreateButton,ADDR newLabel,107,598
    mov btnNew,eax
    invoke CreateButton,ADDR promoQ,111,248
    mov btnPromoQ,eax
    invoke CreateButton,ADDR promoR,112,298
    mov btnPromoR,eax
    invoke CreateButton,ADDR promoB,113,348
    mov btnPromoB,eax
    invoke CreateButton,ADDR promoN,114,398
    mov btnPromoN,eax
    call UpdateButtons
    invoke SetTimer,hwnd,1,750,0
    xor eax,eax
    ret
wm_paint:
    invoke BeginPaint,hwnd,ADDR ps
    mov dc,eax
    invoke PaintScene,dc
    invoke EndPaint,hwnd,ADDR ps
    xor eax,eax
    ret
wm_erase:
    mov eax,1
    ret
wm_drawitem:
    invoke PaintButton,lparam
    mov eax,1
    ret
wm_click:
    cmp promoPending,0
    jne wm_zero
    cmp canMove,1
    jne wm_zero
    mov eax,lparam
    movzx ecx,ax
    shr eax,16
    sub ecx,32
    sub eax,116
    cmp ecx,512
    jae wm_zero
    cmp eax,512
    jae wm_zero
    shr ecx,6
    shr eax,6
    cmp orientation,0
    jne click_black
    mov edx,7
    sub edx,eax
    shl edx,3
    add edx,ecx
    jmp click_index
click_black:
    shl eax,3
    mov edx,7
    sub edx,ecx
    add edx,eax
click_index:
    cmp busy,0
    je click_now
    cmp job,3
    jne wm_zero
    mov queuedSquare,edx
    jmp wm_zero
click_now:
    invoke ChooseSquare,edx
    jmp wm_invalidate
wm_timer:
    cmp mode,2
    jne wm_zero
    cmp busy,0
    jne wm_zero
    cmp ackPending,1
    je timer_ack
    cmp finished,0
    jne wm_zero
    cmp promoPending,0
    jne wm_zero
    invoke StartJob,3
    jmp wm_zero
timer_ack:
    invoke StartJob,7
    jmp wm_zero
wm_network:
    mov busy,0
    cmp job,7
    je network_ack
    cmp jobResult,-1
    je network_error
    mov hasError,0
    call Sync_ObtenerSnapshot
    mov esi,eax
    mov eax,[esi+16]
    cmp eax,netVersion
    je network_same
    mov netVersion,eax
    mov selected,-1
network_same:
    call RefreshBoard
    mov eax,[esi+12]
    mov netState,eax
    cmp eax,2
    je network_finished
    cmp jobResult,1
    jne network_waiting
    mov canMove,1
    invoke lstrcpynA,ADDR statusText,ADDR statusOwn,256
    jmp network_detail
network_waiting:
    mov canMove,0
    invoke lstrcpynA,ADDR statusText,ADDR statusWaiting,256
network_detail:
    mov BYTE PTR detailText,0
    cmp BYTE PTR [esi+129],'O'
    jne network_buttons
    lea eax,[esi+129]
    invoke lstrcpynA,ADDR detailText,eax,256
network_buttons:
    cmp selected,-1
    je network_ready
    call ComputeLegal
network_ready:
    cmp queuedSquare,-1
    je network_ready_buttons
    mov eax,queuedSquare
    mov queuedSquare,-1
    cmp canMove,1
    jne network_ready_buttons
    cmp busy,0
    jne network_ready_buttons
    invoke ChooseSquare,eax
network_ready_buttons:
    call UpdateButtons
    jmp wm_invalidate
network_error:
    cmp closing,1
    jne network_error_normal
    mov closing,0
    invoke MessageBoxA,hwnd,ADDR workerText,ADDR brand,30h
network_error_normal:
    mov canMove,0
    mov hasError,1
    invoke lstrcpynA,ADDR detailText,ADDR workerText,256
    invoke lstrcpynA,ADDR statusText,ADDR statusOffline,256
    cmp job,1
    je network_connect_failed
    cmp job,2
    jne network_ready
network_connect_failed:
    mov mode,0
    jmp network_ready
network_finished:
    mov finished,1
    mov canMove,0
    mov selected,-1
    lea eax,[esi+129]
    invoke lstrcpynA,ADDR detailText,eax,256
    invoke lstrcpynA,ADDR statusText,ADDR statusFinished,256
    mov ackPending,1
    invoke StartJob,7
    jmp network_ready
network_ack:
    cmp jobResult,1
    jne network_ready
    mov ackPending,0
    cmp closing,0
    je network_ready
    invoke DestroyWindow,hwnd
    jmp wm_zero
wm_command:
    movzx eax,WORD PTR wparam
    cmp eax,106
    je command_flip
    cmp busy,0
    jne wm_zero
    cmp eax,101
    je command_white
    cmp eax,102
    je command_black
    cmp eax,103
    je command_local
    cmp eax,104
    je command_resign
    cmp eax,105
    je command_draw
    cmp eax,107
    je command_home
    cmp eax,111
    jb wm_zero
    cmp eax,114
    ja wm_zero
    cmp promoPending,1
    jne wm_zero
    mov promotion,'Q'
    cmp eax,111
    je command_promote
    mov promotion,'R'
    cmp eax,112
    je command_promote
    mov promotion,'B'
    cmp eax,113
    je command_promote
    mov promotion,'N'
command_promote:
    mov promoPending,0
    call MakeMove
    call UpdateButtons
    jmp wm_invalidate
command_white:
    mov myColor,0
    mov orientation,0
    mov eax,1
    jmp command_connect
command_black:
    mov myColor,1
    mov orientation,1
    mov eax,2
command_connect:
    push eax
    mov mode,2
    mov finished,0
    mov ackPending,0
    mov selected,-1
    mov netVersion,-1
    invoke lstrcpynA,ADDR statusText,ADDR statusConnect,256
    mov BYTE PTR detailText,0
    pop eax
    invoke StartJob,eax
    call UpdateButtons
    jmp wm_invalidate
command_local:
    call StartLocal
    jmp wm_invalidate
command_flip:
    xor orientation,1
    jmp wm_invalidate
command_resign:
    invoke MessageBoxA,hwnd,ADDR resignQuestion,ADDR brand,24h
    cmp eax,6
    jne wm_zero
    cmp mode,2
    jne resign_local
    invoke StartJob,5
    jmp wm_invalidate
resign_local:
    mov finished,1
    mov canMove,0
    invoke lstrcpynA,ADDR statusText,ADDR statusFinished,256
    call UpdateButtons
    jmp wm_invalidate
command_draw:
    cmp mode,2
    jne resign_local
    invoke StartJob,6
    jmp wm_invalidate
command_home:
    cmp ackPending,1
    je wm_zero
    mov mode,0
    mov finished,0
    mov selected,-1
    mov canMove,0
    mov BYTE PTR detailText,0
    invoke lstrcpynA,ADDR statusText,ADDR statusIdle,256
    call UpdateButtons
    jmp wm_invalidate
wm_close:
    cmp busy,0
    jne close_busy
    cmp mode,2
    jne close_now
    cmp finished,1
    jne close_ask
    cmp ackPending,0
    je close_now
    mov closing,1
    invoke StartJob,7
    jmp wm_zero
close_ask:
    invoke MessageBoxA,hwnd,ADDR closeQuestion,ADDR brand,24h
    cmp eax,6
    jne wm_zero
    mov closing,1
    invoke StartJob,5
    jmp wm_zero
close_busy:
    invoke MessageBoxA,hwnd,ADDR waitQuestion,ADDR brand,40h
    jmp wm_zero
close_now:
    invoke DestroyWindow,hwnd
    jmp wm_zero
wm_destroy:
    invoke KillTimer,hwnd,1
    invoke PostQuitMessage,0
    jmp wm_zero
wm_invalidate:
    invoke InvalidateRect,hwnd,0,0
wm_zero:
    xor eax,eax
    ret
WndProc ENDP

UpdateButtons PROC USES ebx
    mov ebx,0
    cmp mode,0
    jne ub_menu
    mov ebx,5
ub_menu:
    invoke ShowWindow,btnWhite,ebx
    invoke ShowWindow,btnBlack,ebx
    invoke ShowWindow,btnLocal,ebx
    mov ebx,0
    cmp mode,0
    je ub_actions
    cmp finished,0
    jne ub_actions
    cmp promoPending,0
    jne ub_actions
    mov ebx,5
ub_actions:
    invoke ShowWindow,btnResign,ebx
    invoke ShowWindow,btnDraw,ebx
    mov ebx,0
    cmp finished,1
    jne ub_home
    mov ebx,5
ub_home:
    cmp ackPending,1
    jne ub_home_show
    mov ebx,0
ub_home_show:
    invoke ShowWindow,btnNew,ebx
    mov ebx,0
    cmp promoPending,1
    jne ub_promo
    mov ebx,5
ub_promo:
    invoke ShowWindow,btnPromoQ,ebx
    invoke ShowWindow,btnPromoR,ebx
    invoke ShowWindow,btnPromoB,ebx
    invoke ShowWindow,btnPromoN,ebx
    ret
UpdateButtons ENDP

RefreshBoard PROC USES eax ecx
    xor ecx,ecx
rb_loop:
    mov eax,ecx
    call ObtenerPieza
    mov boardView[ecx],al
    inc ecx
    cmp ecx,64
    jb rb_loop
    ret
RefreshBoard ENDP

ComputeLegal PROC USES eax ecx esi edi
    mov esi,selected
    xor edi,edi
cl_loop:
    mov legalSquares[edi],0
    cmp esi,-1
    je cl_next
    call ValidarMovimiento
    cmp eax,MOV_OK
    jne cl_next
    mov legalSquares[edi],1
cl_next:
    inc edi
    cmp edi,64
    jb cl_loop
    ret
ComputeLegal ENDP

ChooseSquare PROC USES eax ebx esi edi square:DWORD
    mov edi,square
    mov esi,selected
    cmp esi,-1
    je cs_select
    cmp legalSquares[edi],1
    jne cs_select
    mov moveFrom,esi
    mov moveTo,edi
    mov promotion,'Q'
    call EsPromocion
    test eax,eax
    jz cs_move
    mov promoPending,1
    invoke lstrcpynA,ADDR detailText,ADDR promoQuestion,256
    call UpdateButtons
    ret
cs_move:
    call MakeMove
    ret
cs_select:
    mov eax,edi
    call ObtenerPieza
    call ColorDePieza
    mov ebx,eax
    call ObtenerTurno
    cmp eax,ebx
    jne cs_clear
    cmp selected,edi
    je cs_clear
    mov selected,edi
    call ComputeLegal
    ret
cs_clear:
    mov selected,-1
    call ComputeLegal
    ret
ChooseSquare ENDP

MakeMove PROC
    mov eax,moveFrom
    mov lastFrom,eax
    mov eax,moveTo
    mov lastTo,eax
    mov selected,-1
    cmp mode,2
    je mm_online
    mov esi,moveFrom
    mov edi,moveTo
    mov bl,promotion
    call EjecutarMovimiento
    call CambiarTurno
    call RefreshBoard
    call LocalStatus
    ret
mm_online:
    invoke lstrcpynA,ADDR statusText,ADDR statusBusy,256
    invoke StartJob,4
    ret
MakeMove ENDP

StartLocal PROC
    mov mode,1
    mov finished,0
    mov selected,-1
    mov lastFrom,-1
    mov lastTo,-1
    mov orientation,0
    mov promoPending,0
    mov canMove,1
    mov BYTE PTR detailText,0
    call InicializarTablero
    call IniciarTurnos
    call RefreshBoard
    call LocalStatus
    call UpdateButtons
    ret
StartLocal ENDP

LocalStatus PROC
    call ObtenerTurno
    mov edx,OFFSET statusWhite
    cmp eax,0
    je ls_turn
    mov edx,OFFSET statusBlack
ls_turn:
    invoke lstrcpynA,ADDR statusText,edx,256
    mov BYTE PTR detailText,0
    call ObtenerTurno
    call EstadoPartida
    cmp eax,PARTIDA_JAQUE
    je ls_check
    cmp eax,PARTIDA_MATE
    je ls_mate
    cmp eax,PARTIDA_AHOGADO
    je ls_stale
    ret
ls_check:
    invoke lstrcpynA,ADDR detailText,ADDR statusCheck,256
    ret
ls_mate:
    mov edx,OFFSET statusMate
    jmp ls_end
ls_stale:
    mov edx,OFFSET statusStale
ls_end:
    invoke lstrcpynA,ADDR detailText,edx,256
    invoke lstrcpynA,ADDR statusText,ADDR statusFinished,256
    mov finished,1
    mov canMove,0
    call UpdateButtons
    ret
LocalStatus ENDP

StartJob PROC action:DWORD
    cmp busy,0
    jne sj_done
    mov busy,1
    mov eax,action
    mov job,eax
    mov BYTE PTR workerText,0
    invoke CreateThread,0,0,ADDR NetWorker,0,0,ADDR threadId
    test eax,eax
    jz sj_failed
    invoke CloseHandle,eax
sj_done:
    ret
sj_failed:
    mov busy,0
    ret
StartJob ENDP

NetWorker PROC USES ebx esi edi param:DWORD
    mov eax,job
    cmp eax,1
    je nw_white
    cmp eax,2
    je nw_black
    cmp eax,3
    je nw_poll
    cmp eax,4
    je nw_move
    cmp eax,5
    je nw_resign
    cmp eax,6
    je nw_draw
    cmp eax,7
    je nw_ack
nw_white:
    call InicializarTablero
    call IniciarTurnos
    mov eax,myColor
    call Sync_SeleccionarJugador
    call Sync_NuevaPartida
    test eax,eax
    jz nw_error
    jmp nw_join
nw_black:
    call InicializarTablero
    call IniciarTurnos
    mov eax,myColor
    call Sync_SeleccionarJugador
nw_join:
    call Sync_Unirse
    test eax,eax
    jz nw_error
    jmp nw_poll
nw_move:
    mov esi,moveFrom
    mov edi,moveTo
    mov bl,promotion
    call Sync_PublicarMovimiento
    test eax,eax
    jz nw_error
    jmp nw_poll
nw_resign:
    call Sync_Finalizar
    test eax,eax
    jz nw_error
    jmp nw_poll
nw_draw:
    call Sync_Tablas
    test eax,eax
    jz nw_error
    jmp nw_poll
nw_ack:
    call Sync_ConfirmarFin
    jmp nw_done
nw_poll:
    call Sync_ActualizarEstado
    jmp nw_done
nw_error:
    mov eax,-1
nw_done:
    mov jobResult,eax
    invoke PostMessageA,window,8001h,0,0
    xor eax,eax
    ret
NetWorker ENDP

; Sync diagnostics are shown in the window, never in a hidden console.
UI_MostrarError PROC
    pushad
    invoke lstrcpynA,ADDR workerText,edx,256
    popad
    ret
UI_MostrarError ENDP
UI_MostrarMensaje PROC
    pushad
    invoke lstrcpynA,ADDR workerText,edx,256
    popad
    ret
UI_MostrarMensaje ENDP

FillBox PROC dc:DWORD,x:DWORD,y:DWORD,w:DWORD,h:DWORD,color:DWORD
    LOCAL rect:RECTX
    LOCAL brush:DWORD
    mov eax,x
    mov rect.left,eax
    add eax,w
    mov rect.right,eax
    mov eax,y
    mov rect.top,eax
    add eax,h
    mov rect.bottom,eax
    invoke CreateSolidBrush,color
    mov brush,eax
    invoke FillRect,dc,ADDR rect,brush
    invoke DeleteObject,brush
    ret
FillBox ENDP

DrawLabel PROC dc:DWORD,textPtr:DWORD,x:DWORD,y:DWORD,w:DWORD,h:DWORD,font:DWORD,color:DWORD
    LOCAL rect:RECTX
    LOCAL oldFont:DWORD
    mov eax,x
    mov rect.left,eax
    add eax,w
    mov rect.right,eax
    mov eax,y
    mov rect.top,eax
    add eax,h
    mov rect.bottom,eax
    invoke SelectObject,dc,font
    mov oldFont,eax
    invoke GdiSetTextColor,dc,color
    invoke SetBkMode,dc,1
    invoke DrawTextA,dc,textPtr,-1,ADDR rect,10h
    invoke SelectObject,dc,oldFont
    ret
DrawLabel ENDP

PaintButton PROC USES esi edi ebx item:DWORD
    LOCAL rect:RECTX
    LOCAL caption[96]:BYTE
    mov esi,item
    mov edi,[esi+24]
    mov eax,[esi+28]
    mov rect.left,eax
    mov eax,[esi+32]
    mov rect.top,eax
    mov eax,[esi+36]
    mov rect.right,eax
    mov eax,[esi+40]
    mov rect.bottom,eax
    mov ebx,003C352Eh
    cmp DWORD PTR [esi+4],101
    jne pb_pressed
    mov ebx,008CBC9Bh
pb_pressed:
    test DWORD PTR [esi+16],1
    jz pb_fill
    mov ebx,00608065h
pb_fill:
    invoke CreateSolidBrush,ebx
    push eax
    invoke FillRect,edi,ADDR rect,eax
    pop eax
    invoke DeleteObject,eax
    invoke GetWindowTextA,DWORD PTR [esi+20],ADDR caption,96
    invoke SelectObject,edi,fontBody
    push eax
    mov eax,00E4EEF3h
    cmp DWORD PTR [esi+4],101
    jne pb_text
    mov eax,00221B10h
pb_text:
    invoke GdiSetTextColor,edi,eax
    invoke SetBkMode,edi,1
    invoke DrawTextA,edi,ADDR caption,-1,ADDR rect,25h
    pop eax
    invoke SelectObject,edi,eax
    ret
PaintButton ENDP

PaintScene PROC USES ebx esi edi dc:DWORD
    LOCAL back:DWORD
    LOCAL bitmap:DWORD
    LOCAL oldBitmap:DWORD
    LOCAL x:DWORD
    LOCAL y:DWORD
    LOCAL index:DWORD
    LOCAL rect:RECTX
    LOCAL glyph:WORD
    LOCAL coordText[2]:BYTE
    LOCAL brush:DWORD
    LOCAL pen:DWORD
    LOCAL oldPen:DWORD
    LOCAL oldBrush:DWORD
    invoke CreateCompatibleDC,dc
    mov back,eax
    invoke CreateCompatibleBitmap,dc,1000,712
    mov bitmap,eax
    invoke SelectObject,back,bitmap
    mov oldBitmap,eax
    invoke FillBox,back,0,0,1000,712,00221B10h
    invoke FillBox,back,576,112,398,558,00322A1Bh
    invoke DrawLabel,back,ADDR brand,32,22,300,48,fontTitle,00E4EEF3h
    invoke DrawLabel,back,ADDR tagline,34,68,460,28,fontBody,00AFA99Ch
    invoke DrawLabel,back,ADDR roomLabel,604,40,345,30,fontSmall,009BBC8Ch
    cmp mode,0
    je ps_role_done
    mov eax,OFFSET roleLocal
    cmp mode,1
    je ps_role
    mov eax,OFFSET roleWhite
    cmp myColor,0
    je ps_role
    mov eax,OFFSET roleBlack
ps_role:
    invoke DrawLabel,back,eax,604,68,345,25,fontSmall,00AFA99Ch
ps_role_done:
    invoke DrawLabel,back,ADDR boardLabel,32,94,250,22,fontSmall,00AFA99Ch
    invoke DrawLabel,back,ADDR statusText,602,135,340,72,fontStatus,00E4EEF3h
    invoke DrawLabel,back,ADDR detailText,602,210,342,108,fontSmall,00AECBB5h
    cmp mode,0
    jne ps_help
    invoke DrawLabel,back,ADDR modeLabel,602,206,340,32,fontBody,00AFA99Ch
ps_help:
    invoke DrawLabel,back,ADDR selectHelp,602,365,330,64,fontBody,00AFA99Ch
    invoke DrawLabel,back,ADDR legend,32,662,520,28,fontSmall,00AFA99Ch
    xor esi,esi
ps_square:
    mov eax,esi
    and eax,7
    shl eax,6
    add eax,32
    mov x,eax
    mov eax,esi
    shr eax,3
    shl eax,6
    add eax,116
    mov y,eax
    mov eax,esi
    cmp orientation,0
    jne ps_black
    xor eax,56
    jmp ps_index
ps_black:
    xor eax,7
ps_index:
    mov index,eax
    mov ebx,00D7E4E9h
    mov eax,esi
    shr eax,3
    xor eax,esi
    test eax,1
    jz ps_color
    mov ebx,00849378h
ps_color:
    mov eax,index
    cmp eax,lastFrom
    je ps_last
    cmp eax,lastTo
    jne ps_selected
ps_last:
    mov ebx,0099B6B1h
ps_selected:
    cmp eax,selected
    jne ps_fill
    mov ebx,006BB6E0h
ps_fill:
    invoke FillBox,back,x,y,64,64,ebx
    mov eax,index
    movzx ebx,boardView[eax]
    cmp bl,'.'
    je ps_hint
    xor edi,edi
ps_find:
    cmp pieceLetters[edi],bl
    je ps_glyph
    inc edi
    cmp edi,12
    jb ps_find
    jmp ps_hint
ps_glyph:
    mov ax,pieceGlyphs[edi*2]
    mov glyph,ax
    mov eax,x
    mov rect.left,eax
    add eax,64
    mov rect.right,eax
    mov eax,y
    sub eax,1
    mov rect.top,eax
    add eax,64
    mov rect.bottom,eax
    invoke SelectObject,back,fontPiece
    invoke SetBkMode,back,1
    mov eax,00221B10h
    cmp edi,6
    jb ps_shadow
    mov eax,00D7E4E9h
ps_shadow:
    invoke GdiSetTextColor,back,eax
    sub rect.left,2
    invoke DrawTextW,back,ADDR glyph,1,ADDR rect,25h
    add rect.left,4
    invoke DrawTextW,back,ADDR glyph,1,ADDR rect,25h
    sub rect.left,2
    sub rect.top,2
    invoke DrawTextW,back,ADDR glyph,1,ADDR rect,25h
    add rect.top,4
    invoke DrawTextW,back,ADDR glyph,1,ADDR rect,25h
    sub rect.top,2
    mov eax,00E8F5FFh
    cmp edi,6
    jb ps_piece
    mov eax,002B2315h
ps_piece:
    invoke GdiSetTextColor,back,eax
    invoke DrawTextW,back,ADDR glyph,1,ADDR rect,25h
ps_hint:
    cmp selected,-1
    je ps_coords
    mov eax,index
    cmp legalSquares[eax],1
    jne ps_coords
    cmp boardView[eax],'.'
    jne ps_capture
    invoke CreateSolidBrush,00485835h
    mov brush,eax
    invoke SelectObject,back,eax
    mov oldBrush,eax
    invoke GetStockObject,8
    invoke SelectObject,back,eax
    mov oldPen,eax
    mov eax,x
    add eax,25
    mov ecx,y
    add ecx,25
    mov edx,eax
    add edx,14
    mov ebx,ecx
    add ebx,14
    invoke Ellipse,back,eax,ecx,edx,ebx
    invoke SelectObject,back,oldBrush
    invoke SelectObject,back,oldPen
    invoke DeleteObject,brush
    jmp ps_coords
ps_capture:
    invoke CreatePen,0,4,00335989h
    mov pen,eax
    invoke SelectObject,back,eax
    mov oldPen,eax
    invoke GetStockObject,5
    invoke SelectObject,back,eax
    mov oldBrush,eax
    mov eax,x
    add eax,4
    mov ecx,y
    add ecx,4
    mov edx,eax
    add edx,56
    mov ebx,ecx
    add ebx,56
    invoke Ellipse,back,eax,ecx,edx,ebx
    invoke SelectObject,back,oldPen
    invoke SelectObject,back,oldBrush
    invoke DeleteObject,pen
ps_coords:
    inc esi
    cmp esi,64
    jb ps_square
    xor esi,esi
ps_letters:
    mov eax,esi
    cmp orientation,0
    je ps_letter
    mov eax,7
    sub eax,esi
ps_letter:
    add al,'a'
    mov coordText[0],al
    mov coordText[1],0
    mov eax,esi
    shl eax,6
    add eax,58
    invoke DrawLabel,back,ADDR coordText,eax,635,24,24,fontSmall,00AFA99Ch
    mov eax,8
    sub eax,esi
    cmp orientation,0
    je ps_number
    mov eax,esi
    inc eax
ps_number:
    add al,'0'
    mov coordText[0],al
    mov eax,esi
    shl eax,6
    add eax,137
    invoke DrawLabel,back,ADDR coordText,12,eax,18,22,fontSmall,00AFA99Ch
    inc esi
    cmp esi,8
    jb ps_letters
    invoke BitBlt,dc,0,0,1000,712,back,0,0,00CC0020h
    invoke SelectObject,back,oldBitmap
    invoke DeleteObject,bitmap
    invoke DeleteDC,back
    ret
PaintScene ENDP
GdiSetTextColor PROC dc:DWORD,color:DWORD
    push color
    push dc
    call DWORD PTR [_imp__SetTextColor@8]
    ret
GdiSetTextColor ENDP
IFDEF GUI_TEST
INCLUDE gui_tests.inc
ENDIF
END main
