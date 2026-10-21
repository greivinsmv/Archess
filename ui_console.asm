; ============================================================
; ui_console.asm  -  Captura de entrada y formato de salida
;                    (arChess 4.0, Hito 1 / Fase 1)
; ------------------------------------------------------------
; * UI_MostrarMenu    : menu principal, devuelve la opcion elegida
; * UI_LeerEntrada    : lee una jugada ("e2e4") o un comando
;                       ("rendirse", "tablas") y valida el FORMATO
;                       antes de pasarlo a move_validator.asm
; * UI_ParseSquare    : "e2" -> indice 0-63 (via ObtenerIndice)
; * UI_LeerPromocion  : pregunta la pieza de promocion del peon
; * UI_MostrarMensaje : mensaje de estado
; * UI_MostrarError   : mensaje de error
; El pintado del tablero es de board.asm (DibujarTablero).
; ============================================================

INCLUDE arChess.inc

INPUT_MAX = 31                         ; maximo de caracteres a leer

.data
titulo        BYTE "=== arChess 4.0 ===", 0
opcNueva      BYTE "1. Nueva partida (local)", 0
opcMultiB     BYTE "2. Multijugador (blancas)", 0
opcMultiN     BYTE "3. Multijugador (negras)", 0
opcSalir      BYTE "4. Salir", 0
promptMenu    BYTE "Opcion: ", 0
promptJugada  BYTE "Jugada (ej. e2e4) | rendirse | tablas: ", 0
promptPromo   BYTE "Promocion - elige D=dama, T=torre, A=alfil, C=caballo (Enter = dama): ", 0

cmdRendirse   BYTE "RENDIRSE", 0       ; se compara sin distinguir mayusculas
cmdTablas     BYTE "TABLAS", 0

prefMensaje   BYTE ">> ", 0
prefError     BYTE "[Error] ", 0

inputBuf      BYTE INPUT_MAX + 1 DUP(0)   ; +1 para el terminador nulo
remoteLength DWORD 0
remotePoll DWORD 0

.code

; ------------------------------------------------------------
; UI_CmdEquals   (auxiliar interna)
; Compara dos cadenas terminadas en nulo sin distinguir mayusculas
; en la primera (la segunda debe estar en MAYUSCULAS).
; In : ESI = texto del usuario, EDI = comando en mayusculas
; Out: ZF = 1 si son iguales, ZF = 0 si no. Preserva todo.
; ------------------------------------------------------------
UI_CmdEquals PROC
    push  eax
    push  esi
    push  edi
ce_loop:
    mov   al, [esi]
    cmp   al, 'a'
    jb    ce_cmp
    cmp   al, 'z'
    ja    ce_cmp
    sub   al, 20h                      ; a mayuscula
ce_cmp:
    cmp   al, [edi]
    jne   ce_fin                       ; distintos -> ZF = 0
    test  al, al
    jz    ce_fin                       ; ambos terminaron -> ZF = 1
    inc   esi
    inc   edi
    jmp   ce_loop
ce_fin:
    pop   edi                          ; POP no altera los flags
    pop   esi
    pop   eax
    ret
UI_CmdEquals ENDP

; ------------------------------------------------------------
; UI_MostrarMensaje / UI_MostrarError
; In : EDX = puntero a cadena terminada en nulo
; Out: nada. Preserva todos los registros.
; ------------------------------------------------------------
UI_MostrarMensaje PROC
    push  edx
    mov   edx, OFFSET prefMensaje
    call  WriteString
    pop   edx
    call  WriteString
    call  Crlf
    ret
UI_MostrarMensaje ENDP

UI_MostrarError PROC
    push  edx
    mov   edx, OFFSET prefError
    call  WriteString
    pop   edx
    call  WriteString
    call  Crlf
    ret
UI_MostrarError ENDP

; ------------------------------------------------------------
; UI_MostrarMenu
; Muestra el menu principal y lee la opcion.
; In : nada
; Out: EAX = MENU_NUEVA, MENU_SALIR o MENU_INVALIDA
;      Preserva EBX, ECX, EDX.
; ------------------------------------------------------------
UI_MostrarMenu PROC
    push  edx
    push  ecx

    call  Crlf
    mov   edx, OFFSET titulo
    call  WriteString
    call  Crlf
    mov   edx, OFFSET opcNueva
    call  WriteString
    call  Crlf
    mov   edx, OFFSET opcMultiB
    call  WriteString
    call  Crlf
    mov   edx, OFFSET opcMultiN
    call  WriteString
    call  Crlf
    mov   edx, OFFSET opcSalir
    call  WriteString
    call  Crlf
    mov   edx, OFFSET promptMenu
    call  WriteString

    mov   edx, OFFSET inputBuf
    mov   ecx, INPUT_MAX
    call  ReadString                   ; EAX = caracteres leidos

    cmp   eax, 1
    jne   mm_invalida
    mov   al, inputBuf
    cmp   al, '1'
    je    mm_nueva
    cmp   al, '2'
    je    mm_multi_b
    cmp   al, '3'
    je    mm_multi_n
    cmp   al, '4'
    je    mm_salir
mm_invalida:
    mov   eax, MENU_INVALIDA
    jmp   mm_fin
mm_nueva:
    mov   eax, MENU_NUEVA
    jmp   mm_fin
mm_multi_b:
    mov   eax, MENU_MULTI_B
    jmp   mm_fin
mm_multi_n:
    mov   eax, MENU_MULTI_N
    jmp   mm_fin
mm_salir:
    mov   eax, MENU_SALIR
mm_fin:
    pop   ecx
    pop   edx
    ret
UI_MostrarMenu ENDP

; ------------------------------------------------------------
; UI_ParseSquare
; Convierte dos caracteres ("e2", tambien "E2") a indice de casilla.
; Calcula fila y columna y llama a ObtenerIndice (ADR #1).
; In : EDX = puntero a 2 caracteres [columna][fila]
; Out: EAX = indice 0-63 (valido solo si CF = 0)
;      CF = 0 valido, CF = 1 invalido
;      Preserva EBX, ECX, EDX.
; ------------------------------------------------------------
UI_ParseSquare PROC
    push  ebx
    push  edx

    movzx eax, BYTE PTR [edx]          ; caracter de columna
    or    al, 20h                      ; a minuscula
    sub   al, 'a'
    cmp   al, 7
    ja    ps_mal                       ; sin signo: cubre < 'a' y > 'h'

    movzx ebx, BYTE PTR [edx+1]        ; caracter de fila
    sub   bl, '1'
    cmp   bl, 7
    ja    ps_mal

    mov   dh, bl                       ; DH = fila
    mov   dl, al                       ; DL = columna
    call  ObtenerIndice                ; EAX = fila*8 + columna
    pop   edx
    pop   ebx
    clc
    ret

ps_mal:
    pop   edx
    pop   ebx
    stc
    ret
UI_ParseSquare ENDP

; ------------------------------------------------------------
; UI_LeerEntrada
; Lee una linea del teclado y la clasifica.
; In : nada
; Out: EAX = ENTRADA_JUGADA   -> ESI = origen, EDI = destino (0-63)
;      EAX = ENTRADA_RENDIRSE
;      EAX = ENTRADA_TABLAS
;      EAX = ENTRADA_INVALIDA (formato incorrecto)
;      Preserva EBX, ECX, EDX. ESI/EDI solo son utiles con
;      ENTRADA_JUGADA (en otros casos pueden quedar modificados).
; ------------------------------------------------------------
UI_LeerEntrada PROC
    push  edx
    push  ecx

    mov   edx, OFFSET promptJugada
    call  WriteString

    mov   edx, OFFSET inputBuf
    mov   ecx, INPUT_MAX
    call  ReadString                   ; EAX = caracteres leidos

    call UI_ClasificarEntrada
    pop ecx
    pop edx
    ret
UI_LeerEntrada ENDP

; Keep receiving terminal events while the player is typing.
UI_LeerEntradaRemota PROC USES ebx ecx edx ebp
    mov edx,OFFSET promptJugada
    call WriteString
    mov remoteLength,0
    call GetTickCount
    mov remotePoll,eax
ler_loop:
    call ReadKey
    jz ler_poll
    cmp al,13
    je ler_enter
    cmp al,8
    je ler_back
    cmp al,32
    jb ler_poll
    cmp al,126
    ja ler_poll
    mov ecx,remoteLength
    cmp ecx,INPUT_MAX
    jae ler_poll
    mov inputBuf[ecx],al
    inc remoteLength
    call WriteChar
    jmp ler_poll
ler_back:
    cmp remoteLength,0
    je ler_poll
    dec remoteLength
    mov al,8
    call WriteChar
    mov al,' '
    call WriteChar
    mov al,8
    call WriteChar
ler_poll:
    call GetTickCount
    sub eax,remotePoll
    cmp eax,1000
    jb ler_delay
    call Sync_ActualizarEstado
    cmp eax,-2
    je ler_finished
    cmp eax,-1
    je ler_error
    call GetTickCount
    mov remotePoll,eax
ler_delay:
    mov eax,25
    call Delay
    jmp ler_loop
ler_enter:
    call Crlf
    mov eax,remoteLength
    mov inputBuf[eax],0
    call UI_ClasificarEntrada
    ret
ler_finished:
    mov eax,4
    ret
ler_error:
    mov eax,5
    ret
UI_LeerEntradaRemota ENDP

UI_ClasificarEntrada PROC

    cmp   eax, 4
    je    le_jugada                    ; 4 caracteres: formato "e2e4"

    mov   esi, OFFSET inputBuf         ; si no, puede ser un comando
    mov   edi, OFFSET cmdRendirse
    call  UI_CmdEquals
    je    le_rendirse
    mov   edi, OFFSET cmdTablas
    call  UI_CmdEquals
    je    le_tablas
    jmp   le_invalida

le_jugada:
    mov   edx, OFFSET inputBuf         ; casilla de origen
    call  UI_ParseSquare
    jc    le_invalida
    mov   esi, eax
    mov   edx, OFFSET inputBuf + 2     ; casilla de destino
    call  UI_ParseSquare
    jc    le_invalida
    mov   edi, eax
    mov   eax, ENTRADA_JUGADA
    jmp   le_fin

le_rendirse:
    mov   eax, ENTRADA_RENDIRSE
    jmp   le_fin

le_tablas:
    mov   eax, ENTRADA_TABLAS
    jmp   le_fin

le_invalida:
    mov   eax, ENTRADA_INVALIDA

le_fin:
    ret
UI_ClasificarEntrada ENDP

; ------------------------------------------------------------
; UI_LeerPromocion
; Pregunta a que pieza se promueve el peon. Repite hasta recibir una
; respuesta valida. Acepta D/T/A/C (espanol) o Q/R/B/N (ingles),
; en mayuscula o minuscula. Enter solo = dama.
; In : nada
; Out: AL = 'Q', 'R', 'B' o 'N' (mayuscula; EAX con el resto en 0)
;      Preserva todo salvo EAX.
; ------------------------------------------------------------
UI_LeerPromocion PROC
    push  edx
    push  ecx

lp_pedir:
    mov   edx, OFFSET promptPromo
    call  WriteString
    mov   edx, OFFSET inputBuf
    mov   ecx, INPUT_MAX
    call  ReadString                   ; EAX = caracteres leidos

    test  eax, eax
    jz    lp_dama                      ; Enter solo: dama
    cmp   eax, 1
    jne   lp_pedir                     ; mas de un caracter: preguntar de nuevo

    mov   al, inputBuf
    and   al, 0DFh                     ; a mayuscula
    cmp   al, 'D'
    je    lp_dama
    cmp   al, 'Q'
    je    lp_dama
    cmp   al, 'T'
    je    lp_torre
    cmp   al, 'R'
    je    lp_torre
    cmp   al, 'A'
    je    lp_alfil
    cmp   al, 'B'
    je    lp_alfil
    cmp   al, 'C'
    je    lp_caballo
    cmp   al, 'N'
    je    lp_caballo
    jmp   lp_pedir

lp_dama:
    mov   eax, 'Q'
    jmp   lp_fin
lp_torre:
    mov   eax, 'R'
    jmp   lp_fin
lp_alfil:
    mov   eax, 'B'
    jmp   lp_fin
lp_caballo:
    mov   eax, 'N'
lp_fin:
    pop   ecx
    pop   edx
    ret
UI_LeerPromocion ENDP

END
