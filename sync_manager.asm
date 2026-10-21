; arChess protocol v2: one atomic request, one correlated response.
INCLUDE arChess.inc
MoveFileExA PROTO, oldPath:PTR BYTE, newPath:PTR BYTE, flags:DWORD
GetModuleFileNameA PROTO, module:DWORD, fileName:PTR BYTE, capacity:DWORD
SetCurrentDirectoryA PROTO, directory:PTR BYTE
GetFileAttributesA PROTO, fileName:PTR BYTE
GetCurrentProcessId PROTO

.data
requestPath BYTE "sync_request.txt",0
tempPath BYTE "sync_request.pending",0
statePath BYTE "sync_state.bin",0
backendPath BYTE "firebase_multiplayer.py",0
modulePath BYTE 1024 DUP(0)
playerWhite BYTE "white",0
playerBlack BYTE "black",0
syncPlayer DWORD OFFSET playerWhite
syncColor DWORD 0
syncId DWORD 0
syncVersion DWORD 0
syncDrawNotice DWORD 0
syncSession BYTE 33 DUP(0)
syncOrigin DWORD 0
syncDestination DWORD 0
syncPromotion BYTE 'Q',0
syncOperation DWORD 0
syncBuffer BYTE 512 DUP(0)
syncSnapshot BYTE 256 DUP(0)
syncDecimals BYTE 12 DUP(0)
opCreate BYTE "create",0
opJoin BYTE "join",0
opGet BYTE "get",0
opMove BYTE "move",0
opFinish BYTE "resign",0
opAck BYTE "ack",0
opDraw BYTE "draw",0
jsonStart BYTE '{"room":"prueba","op":"',0
jsonPlayer BYTE '","player":"',0
jsonSession BYTE '","session":"',0
jsonId BYTE '","id":',0
jsonVersion BYTE ',"version":',0
jsonOrigin BYTE ',"origin":',0
jsonDestination BYTE ',"destination":',0
jsonPromotion BYTE ',"promotion":"',0
jsonEnd BYTE '"}',0
msgTimeout BYTE "Sin respuesta del middleware (20 s). Revisa su ventana y vuelve a conectar.",0
msgWrite BYTE "No se pudo publicar la solicitud. Cierra la otra copia del juego en esta carpeta.",0

.code
Sync_Inicializar PROC
    pushad
    invoke GetModuleFileNameA, 0, ADDR modulePath, SIZEOF modulePath
    test eax,eax
    jz si_done
    cmp eax,SIZEOF modulePath
    jae si_done
    lea esi,modulePath[eax]
si_find:
    dec esi
    cmp esi,OFFSET modulePath
    jbe si_done
    cmp BYTE PTR [esi],92
    jne si_find
    mov BYTE PTR [esi],0
    invoke SetCurrentDirectoryA, ADDR modulePath
    invoke GetFileAttributesA, ADDR backendPath
    cmp eax,-1
    jne si_done
si_parent:
    dec esi
    cmp esi,OFFSET modulePath
    jbe si_done
    cmp BYTE PTR [esi],92
    jne si_parent
    mov BYTE PTR [esi],0
    invoke SetCurrentDirectoryA, ADDR modulePath
si_done:
    popad
    ret
Sync_Inicializar ENDP

Sync_AppendText PROC
    lodsb
    test al,al
    jz sat_done
    stosb
    jmp Sync_AppendText
sat_done:
    ret
Sync_AppendText ENDP

Sync_AppendUInt PROC USES ebx ecx edx esi
    mov ebx,10
    lea esi,syncDecimals[11]
    mov BYTE PTR [esi],0
sau_loop:
    xor edx,edx
    div ebx
    add dl,'0'
    dec esi
    mov [esi],dl
    test eax,eax
    jnz sau_loop
    call Sync_AppendText
    ret
Sync_AppendUInt ENDP

Sync_SeleccionarJugador PROC
    mov syncColor,eax
    mov syncPlayer,OFFSET playerWhite
    cmp eax,TURNO_BLANCAS
    je ssj_done
    mov syncPlayer,OFFSET playerBlack
ssj_done:
    mov BYTE PTR syncSession,0
    mov syncVersion,0
    mov syncDrawNotice,0
    call GetTickCount
    mov syncId,eax
    invoke GetCurrentProcessId
    shl eax,16
    xor syncId,eax
    ret
Sync_SeleccionarJugador ENDP

; EDX = operation string. Returns 1 for success, 0 for error.
; Preserves all registers except EAX. Never consumes an unrelated response.
Sync_Request PROC
    pushad
    cld
    mov syncOperation,edx
    inc syncId
    mov edi,OFFSET syncBuffer
    mov esi,OFFSET jsonStart
    call Sync_AppendText
    mov esi,syncOperation
    call Sync_AppendText
    mov esi,OFFSET jsonPlayer
    call Sync_AppendText
    mov esi,syncPlayer
    call Sync_AppendText
    mov esi,OFFSET jsonSession
    call Sync_AppendText
    mov esi,OFFSET syncSession
    call Sync_AppendText
    mov esi,OFFSET jsonId
    call Sync_AppendText
    mov eax,syncId
    call Sync_AppendUInt
    mov esi,OFFSET jsonVersion
    call Sync_AppendText
    mov eax,syncVersion
    call Sync_AppendUInt
    mov esi,OFFSET jsonOrigin
    call Sync_AppendText
    mov eax,syncOrigin
    call Sync_AppendUInt
    mov esi,OFFSET jsonDestination
    call Sync_AppendText
    mov eax,syncDestination
    call Sync_AppendUInt
    mov esi,OFFSET jsonPromotion
    call Sync_AppendText
    mov esi,OFFSET syncPromotion
    call Sync_AppendText
    mov esi,OFFSET jsonEnd
    call Sync_AppendText
    mov ecx,edi
    sub ecx,OFFSET syncBuffer
    push ecx
    mov edx,OFFSET tempPath
    call CreateOutputFile
    pop ecx
    cmp eax,INVALID_HANDLE_VALUE
    je sr_write_error
    mov ebx,eax
    mov edx,OFFSET syncBuffer
    push ecx
    call WriteToFile
    pop ecx
    jc sr_close_bad
    cmp eax,ecx
    jne sr_close_bad
    mov eax,ebx
    call CloseFile
    mov ebp,40
sr_publish:
    invoke MoveFileExA, ADDR tempPath, ADDR requestPath, 1
    test eax,eax
    jnz sr_wait_start
    mov eax,50
    call Delay
    dec ebp
    jnz sr_publish
    jmp sr_write_error
sr_close_bad:
    mov eax,ebx
    call CloseFile
sr_write_error:
    mov edx,OFFSET msgWrite
    call UI_MostrarError
    jmp sr_fail
sr_wait_start:
    call GetTickCount
    mov ebp,eax
sr_wait:
    mov edx,OFFSET statePath
    call OpenInputFile
    cmp eax,INVALID_HANDLE_VALUE
    je sr_pause
    mov ebx,eax
    mov edx,OFFSET syncSnapshot
    mov ecx,SIZEOF syncSnapshot
    call ReadFromFile
    jc sr_read_bad
    mov esi,eax
    mov eax,ebx
    call CloseFile
    cmp esi,SIZEOF syncSnapshot
    jne sr_pause
    cmp DWORD PTR syncSnapshot,32484341h
    jne sr_pause
    mov eax,syncId
    cmp DWORD PTR syncSnapshot[4],eax
    jne sr_pause
    cmp DWORD PTR syncSnapshot[8],1
    jne sr_remote_error
    call Sync_Apply
    mov DWORD PTR [esp+28],1
    popad
    ret
sr_read_bad:
    mov eax,ebx
    call CloseFile
sr_pause:
    call GetTickCount
    sub eax,ebp
    cmp eax,20000
    jae sr_timeout
    mov eax,50
    call Delay
    jmp sr_wait
sr_timeout:
    mov edx,OFFSET msgTimeout
    call UI_MostrarError
    jmp sr_fail
sr_remote_error:
    mov BYTE PTR syncSnapshot[255],0
    mov edx,OFFSET syncSnapshot+129
    call UI_MostrarError
sr_fail:
    mov DWORD PTR [esp+28],0
    popad
    ret
Sync_Request ENDP

Sync_Apply PROC
    cmp DWORD PTR syncSnapshot[12],3
    je sa_done
    cld
    mov esi,OFFSET syncSnapshot+96
    mov edi,OFFSET syncSession
    mov ecx,33
    rep movsb
    mov BYTE PTR syncSession[32],0
    mov eax,DWORD PTR syncSnapshot[16]
    mov syncVersion,eax
    mov esi,OFFSET syncSnapshot+32
    xor ecx,ecx
sa_board:
    mov bl,[esi+ecx]
    mov eax,ecx
    call ColocarPieza
    inc ecx
    cmp ecx,64
    jb sa_board
    mov eax,DWORD PTR syncSnapshot[20]
    call EstablecerTurno
    mov eax,DWORD PTR syncSnapshot[24]
    mov edx,DWORD PTR syncSnapshot[28]
    dec edx
    call EstablecerReglasRemotas
sa_done:
    ret
Sync_Apply ENDP

Sync_NuevaPartida PROC
    mov edx,OFFSET opCreate
    jmp Sync_Request
Sync_NuevaPartida ENDP
Sync_Unirse PROC
    mov edx,OFFSET opJoin
    jmp Sync_Request
Sync_Unirse ENDP
Sync_Finalizar PROC
    mov edx,OFFSET opFinish
    jmp Sync_Request
Sync_Finalizar ENDP
Sync_ConfirmarFin PROC
    mov edx,OFFSET opAck
    jmp Sync_Request
Sync_ConfirmarFin ENDP
Sync_Tablas PROC
    mov edx,OFFSET opDraw
    jmp Sync_Request
Sync_Tablas ENDP
Sync_PublicarMovimiento PROC
    mov syncOrigin,esi
    mov syncDestination,edi
    mov syncPromotion,bl
    mov edx,OFFSET opMove
    jmp Sync_Request
Sync_PublicarMovimiento ENDP

; -2 finished, -1 network/protocol error, 0 waiting, 1 own turn.
Sync_ActualizarEstado PROC
    mov edx,OFFSET opGet
    call Sync_Request
    test eax,eax
    jz sas_error
    cmp DWORD PTR syncSnapshot[12],2
    je sas_finished
    cmp BYTE PTR syncSnapshot[129],'O'
    jne sas_no_offer
    cmp syncDrawNotice,1
    je sas_status
    mov syncDrawNotice,1
    mov edx,OFFSET syncSnapshot+129
    call Crlf
    call UI_MostrarMensaje
    jmp sas_status
sas_no_offer:
    mov syncDrawNotice,0
sas_status:
    cmp DWORD PTR syncSnapshot[12],1
    jne sas_wait
    mov eax,syncColor
    cmp DWORD PTR syncSnapshot[20],eax
    sete al
    movzx eax,al
    ret
sas_wait:
    xor eax,eax
    ret
sas_error:
    mov eax,-1
    ret
sas_finished:
    mov edx,OFFSET syncSnapshot+129
    call UI_MostrarMensaje
    mov eax,-2
    ret
Sync_ActualizarEstado ENDP
Sync_ObtenerSnapshot PROC
    mov eax,OFFSET syncSnapshot
    ret
Sync_ObtenerSnapshot ENDP
END
