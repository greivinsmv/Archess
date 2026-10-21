; ============================================================
; board.asm  -  Representacion y pintado ASCII del tablero
;               (arChess 4.0, Hito 1 / Fase 1)
; ------------------------------------------------------------
; ADR #1: vector lineal de 64 casillas, indice = fila*8 + columna.
; Rutinas expuestas:
;   ObtenerIndice, ObtenerPieza, ColocarPieza, MoverPieza,
;   InicializarTablero, DibujarTablero
; El arreglo 'board' es privado de este modulo.
; ============================================================

INCLUDE arChess.inc

.data
board        BYTE TAM_TABLERO DUP(CASILLA_VACIA)   ; tablero actual

; Posicion inicial, de la fila 1 a la fila 8
posInicial   BYTE "RNBQKBNR"                       ; fila 1 (blancas)
             BYTE "PPPPPPPP"                       ; fila 2
             BYTE 32 DUP(CASILLA_VACIA)            ; filas 3 a 6
             BYTE "pppppppp"                       ; fila 7
             BYTE "rnbqkbnr"                       ; fila 8 (negras)

ultimoOrigen  SDWORD SIN_JUGADA                    ; ultima jugada (resaltado)
ultimoDestino SDWORD SIN_JUGADA

etiquetaCols  BYTE "  a b c d e f g h", 0

.code

; ------------------------------------------------------------
; ObtenerIndice   (rutina centralizada de indexacion, ADR #1)
; In : DH = fila (0-7), DL = columna (0-7)
; Out: EAX = fila*8 + columna (0-63). Preserva el resto.
; ------------------------------------------------------------
ObtenerIndice PROC
    movzx eax, dh
    shl   eax, 3                       ; fila * 8
    add   al, dl                       ; + columna (max 63, sin acarreo)
    ret
ObtenerIndice ENDP

; ------------------------------------------------------------
; ObtenerPieza
; In : EAX = indice (0-63)
; Out: EAX = pieza (ASCII en AL, resto de EAX en 0)
; ------------------------------------------------------------
ObtenerPieza PROC
    movzx eax, BYTE PTR board[eax]
    ret
ObtenerPieza ENDP

; ------------------------------------------------------------
; ColocarPieza
; In : EAX = indice (0-63), BL = pieza (ASCII)
; Out: nada. Preserva todos los registros.
; ------------------------------------------------------------
ColocarPieza PROC
    mov   BYTE PTR board[eax], bl
    ret
ColocarPieza ENDP

; ------------------------------------------------------------
; MoverPieza
; Mueve la pieza de ESI a EDI SIN validar reglas (eso es de
; move_validator.asm). Deja vacio el origen, sobrescribe el destino
; (captura) y guarda la jugada para resaltarla al dibujar.
; In : ESI = indice origen (0-63), EDI = indice destino (0-63)
; Out: nada. Preserva todos los registros.
; ------------------------------------------------------------
MoverPieza PROC
    push  eax
    cmp   esi, edi
    je    mp_fin                       ; origen == destino: no hacer nada
    movzx eax, BYTE PTR board[esi]     ; AL = pieza que se mueve
    mov   BYTE PTR board[esi], CASILLA_VACIA
    mov   BYTE PTR board[edi], al
    mov   ultimoOrigen, esi
    mov   ultimoDestino, edi
mp_fin:
    pop   eax
    ret
MoverPieza ENDP

; ------------------------------------------------------------
; InicializarTablero
; Copia la posicion inicial al tablero y borra el resaltado.
; In : nada
; Out: nada. Preserva todos los registros.
; ------------------------------------------------------------
InicializarTablero PROC
    pushad
    cld
    mov   esi, OFFSET posInicial
    mov   edi, OFFSET board
    mov   ecx, TAM_TABLERO
    rep   movsb
    mov   ultimoOrigen, SIN_JUGADA
    mov   ultimoDestino, SIN_JUGADA
    popad
    ret
InicializarTablero ENDP

; ------------------------------------------------------------
; DibujarTablero
; Pinta el tablero en consola (fila 8 arriba) con coordenadas
; a-h / 1-8 y resalta origen y destino de la ultima jugada
; (texto negro sobre fondo amarillo).
;     8 r n b q k b n r
;     ...
;     1 R N B Q K B N R
;       a b c d e f g h
; In : nada
; Out: nada. Preserva todos los registros.
; ------------------------------------------------------------
DibujarTablero PROC
    pushad
    call  Crlf
    mov   esi, 7                       ; ESI = fila actual (7 = fila 8)

db_fila:
    mov   eax, esi
    inc   eax                          ; numero de fila (1-8)
    call  WriteDec
    mov   al, ' '
    call  WriteChar

    xor   ebx, ebx                     ; EBX = columna (0-7)
db_col:
    mov   eax, esi
    mov   dh, al                       ; DH = fila
    mov   dl, bl                       ; DL = columna
    call  ObtenerIndice                ; EAX = indice
    mov   ecx, eax                     ; ECX = indice (para el resaltado)
    call  ObtenerPieza                 ; AL = pieza
    mov   edi, eax                     ; EDI = pieza

    mov   eax, lightGray + (black * 16)        ; color normal
    cmp   ecx, ultimoOrigen
    je    db_resaltar
    cmp   ecx, ultimoDestino
    jne   db_pintar
db_resaltar:
    mov   eax, black + (yellow * 16)           ; casilla de la ultima jugada
db_pintar:
    call  SetTextColor
    mov   eax, edi
    call  WriteChar                    ; dibuja la pieza

    mov   eax, lightGray + (black * 16)        ; restaurar color normal
    call  SetTextColor
    mov   al, ' '
    call  WriteChar

    inc   ebx
    cmp   ebx, 8
    jb    db_col

    call  Crlf
    dec   esi
    jns   db_fila                      ; repetir mientras ESI >= 0

    mov   edx, OFFSET etiquetaCols
    call  WriteString
    call  Crlf
    call  Crlf
    popad
    ret
DibujarTablero ENDP

END
