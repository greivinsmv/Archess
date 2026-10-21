; ============================================================
; move_validator.asm  -  Validacion de reglas (arChess 4.0, Fase 2)
; ------------------------------------------------------------
; No conoce nada de red ni de UI: recibe una jugada candidata
; (origen, destino) y devuelve un codigo de validez.
;
; Incluye:
;   * Control de turnos (blancas empiezan)
;   * Movimiento legal de cada pieza (P N B R Q K), con
;     bloqueo de camino en torre / alfil / dama
;   * Captura de piezas enemigas (nunca las propias)
;   * Deteccion de jaque, jaque mate y rey ahogado
;   * Un movimiento que deja al propio rey en jaque es ilegal
;
; Fase 3 (reglas avanzadas obligatorias):
;   * Enroque corto y largo (derechos, casillas libres, sin jaque
;     ni casillas atacadas en el recorrido del rey)
;   * Captura al paso (solo en la jugada inmediata siguiente)
;   * Promocion de peon (la eleccion de pieza la pide main.asm a
;     ui_console.asm; aqui solo se aplica)
;   EjecutarMovimiento aplica cualquier jugada ya validada,
;   incluidas las especiales, y actualiza el estado de las reglas.
;
; Todavia no incluye tablas por repeticion ni material insuficiente.
;
; Toda lectura/escritura del tablero pasa por board.asm
; (ObtenerPieza / ColocarPieza / ObtenerIndice).
; Convencion: parametros por registros; cada rutina documenta
; sus entradas/salidas y preserva el resto.
; Indice = fila*8 + columna (a1 = 0, h8 = 63).
; ============================================================

INCLUDE arChess.inc

.data
turnoActual  DWORD TURNO_BLANCAS

; Direcciones: 0-3 ortogonales (torre), 4-7 diagonales (alfil).
; Las 8 juntas sirven para dama y rey.
tblDF  SBYTE  1, -1,  0,  0,  1,  1, -1, -1     ; delta de fila
tblDC  SBYTE  0,  0,  1, -1,  1, -1,  1, -1     ; delta de columna

; Saltos de caballo
tblCF  SBYTE  2,  2, -2, -2,  1,  1, -1, -1
tblCC  SBYTE  1, -1,  1, -1,  2, -2,  2, -2

atkFila  SDWORD 0                    ; casilla objetivo de CasillaAtacada
atkCol   SDWORD 0

; ---- Estado de las reglas avanzadas (Fase 3) ----
; Derechos de enroque (bits): 0 = blancas corto, 1 = blancas largo,
;                             2 = negras corto,  3 = negras largo
derechosEnroque DWORD 0Fh
casillaAlPaso   SDWORD SIN_JUGADA    ; casilla saltada por un peon que avanzo 2
nuevoAlPaso     SDWORD SIN_JUGADA    ; auxiliar de EjecutarMovimiento
tipoJugada      DWORD 0              ; auxiliar de EjecutarMovimiento
simCapSq        SDWORD SIN_JUGADA    ; auxiliar de DejaReyEnJaque (al paso)
simCapPz        BYTE   0

; Casillas cuyo movimiento/captura hace perder derechos de enroque:
;            a1 h1 e1 a8 h8 e8
tblDerSq BYTE  0,  7,  4, 56, 63, 60
tblDerMk BYTE  2,  1,  3,  8,  4, 12     ; bits a borrar en cada caso

.code

; ------------------------------------------------------------
; ColorDePieza
; In : AL = pieza (ASCII)
; Out: EAX = TURNO_BLANCAS (mayuscula), TURNO_NEGRAS (minuscula)
;      o COLOR_NINGUNO (casilla vacia). Preserva el resto.
; ------------------------------------------------------------
ColorDePieza PROC
    cmp   al, 'a'
    jae   cp_negra
    cmp   al, 'A'
    jb    cp_ninguna
    mov   eax, TURNO_BLANCAS
    ret
cp_negra:
    mov   eax, TURNO_NEGRAS
    ret
cp_ninguna:
    mov   eax, COLOR_NINGUNO
    ret
ColorDePieza ENDP

; ------------------------------------------------------------
; PiezaEnFC   (auxiliar interna)
; Lee la pieza en (fila, columna); tolera coordenadas fuera del tablero.
; In : DH = fila, DL = columna (bytes con signo, pueden ser -1 u 8)
; Out: CF = 1 si esta fuera del tablero
;      CF = 0 y AL = pieza si esta dentro. Preserva todo salvo EAX.
; ------------------------------------------------------------
PiezaEnFC PROC
    cmp   dh, 7
    ja    pf_fuera                     ; sin signo: -1 se ve como 255
    cmp   dl, 7
    ja    pf_fuera
    call  ObtenerIndice                ; EAX = indice
    call  ObtenerPieza                 ; AL = pieza
    clc
    ret
pf_fuera:
    stc
    ret
PiezaEnFC ENDP

; ------------------------------------------------------------
; IniciarTurnos / CambiarTurno / ObtenerTurno   (control de turnos)
; ------------------------------------------------------------
; IniciarTurnos: nueva partida. Turno de las blancas, todos los
; derechos de enroque y sin captura al paso pendiente.
IniciarTurnos PROC
    mov   turnoActual, TURNO_BLANCAS
    mov   derechosEnroque, 0Fh
    mov   casillaAlPaso, SIN_JUGADA
    ret
IniciarTurnos ENDP

CambiarTurno PROC
    xor   turnoActual, 1               ; 0 <-> 1
    ret
CambiarTurno ENDP

; In: EAX = TURNO_BLANCAS o TURNO_NEGRAS
EstablecerTurno PROC
    mov   turnoActual, eax
    ret
EstablecerTurno ENDP

; Out: EAX = TURNO_BLANCAS o TURNO_NEGRAS
ObtenerTurno PROC
    mov   eax, turnoActual
    ret
ObtenerTurno ENDP

; ------------------------------------------------------------
; CasillaAtacada
; Dice si una casilla es atacada por alguna pieza de un color.
; In : EAX = casilla (0-63), BL = color atacante (TURNO_*)
; Out: EAX = 1 si esta atacada, 0 si no. Preserva el resto.
; ------------------------------------------------------------
CasillaAtacada PROC
    push  ebx
    push  ecx
    push  edx
    push  esi
    push  edi
    push  ebp

    movzx ebp, bl                      ; EBP = color atacante
    mov   edx, eax
    shr   edx, 3
    mov   atkFila, edx                 ; fila objetivo
    and   eax, 7
    mov   atkCol, eax                  ; columna objetivo

    ; ---- Peones ----
    ; Un peon blanco ataca hacia arriba: esta una fila ABAJO del objetivo.
    ; Un peon negro esta una fila ARRIBA.
    mov   edi, -1
    cmp   ebp, TURNO_BLANCAS
    je    ca_peon_ini
    mov   edi, 1
ca_peon_ini:
    mov   esi, -1                      ; columna -1, luego +1
ca_peon_loop:
    mov   eax, atkFila
    add   eax, edi
    mov   dh, al
    mov   eax, atkCol
    add   eax, esi
    mov   dl, al
    call  PiezaEnFC
    jc    ca_peon_sig
    mov   bl, 'P'
    cmp   ebp, TURNO_BLANCAS
    je    ca_peon_cmp
    mov   bl, 'p'
ca_peon_cmp:
    cmp   al, bl
    je    ca_si
ca_peon_sig:
    add   esi, 2
    cmp   esi, 1
    jle   ca_peon_loop

    ; ---- Caballos ----
    mov   bl, 'N'
    cmp   ebp, TURNO_BLANCAS
    je    ca_cab_ini
    mov   bl, 'n'
ca_cab_ini:
    xor   esi, esi
ca_cab_loop:
    mov   eax, atkFila
    movsx ecx, BYTE PTR tblCF[esi]
    add   eax, ecx
    mov   dh, al
    mov   eax, atkCol
    movsx ecx, BYTE PTR tblCC[esi]
    add   eax, ecx
    mov   dl, al
    call  PiezaEnFC
    jc    ca_cab_sig
    cmp   al, bl
    je    ca_si
ca_cab_sig:
    inc   esi
    cmp   esi, 8
    jb    ca_cab_loop

    ; ---- Rey (casillas adyacentes) ----
    mov   bl, 'K'
    cmp   ebp, TURNO_BLANCAS
    je    ca_rey_ini
    mov   bl, 'k'
ca_rey_ini:
    xor   esi, esi
ca_rey_loop:
    mov   eax, atkFila
    movsx ecx, BYTE PTR tblDF[esi]
    add   eax, ecx
    mov   dh, al
    mov   eax, atkCol
    movsx ecx, BYTE PTR tblDC[esi]
    add   eax, ecx
    mov   dl, al
    call  PiezaEnFC
    jc    ca_rey_sig
    cmp   al, bl
    je    ca_si
ca_rey_sig:
    inc   esi
    cmp   esi, 8
    jb    ca_rey_loop

    ; ---- Piezas deslizantes: torre, alfil, dama ----
    xor   esi, esi                     ; ESI = direccion (0-7)
ca_dir_loop:
    mov   eax, atkFila
    mov   dh, al
    mov   eax, atkCol
    mov   dl, al
ca_paso:
    mov   al, tblDF[esi]
    add   dh, al
    mov   al, tblDC[esi]
    add   dl, al
    call  PiezaEnFC
    jc    ca_dir_sig                   ; se salio del tablero
    cmp   al, CASILLA_VACIA
    je    ca_paso                      ; vacia: seguir avanzando
    mov   cl, al                       ; CL = primera pieza encontrada

    mov   bl, 'Q'                      ; una dama ataca en cualquier direccion
    cmp   ebp, TURNO_BLANCAS
    je    ca_dama_cmp
    mov   bl, 'q'
ca_dama_cmp:
    cmp   cl, bl
    je    ca_si

    cmp   esi, 4
    jae   ca_diagonal
    mov   bl, 'R'                      ; direcciones 0-3: torre
    cmp   ebp, TURNO_BLANCAS
    je    ca_torre_cmp
    mov   bl, 'r'
ca_torre_cmp:
    cmp   cl, bl
    je    ca_si
    jmp   ca_dir_sig
ca_diagonal:
    mov   bl, 'B'                      ; direcciones 4-7: alfil
    cmp   ebp, TURNO_BLANCAS
    je    ca_alfil_cmp
    mov   bl, 'b'
ca_alfil_cmp:
    cmp   cl, bl
    je    ca_si
ca_dir_sig:
    inc   esi
    cmp   esi, 8
    jb    ca_dir_loop

    xor   eax, eax                     ; nadie la ataca
    jmp   ca_fin
ca_si:
    mov   eax, 1
ca_fin:
    pop   ebp
    pop   edi
    pop   esi
    pop   edx
    pop   ecx
    pop   ebx
    ret
CasillaAtacada ENDP

; ------------------------------------------------------------
; EstaEnJaque
; In : EAX = color (TURNO_BLANCAS o TURNO_NEGRAS)
; Out: EAX = 1 si el rey de ese color esta en jaque, 0 si no.
;      Preserva el resto.
; ------------------------------------------------------------
EstaEnJaque PROC
    push  ebx
    push  ecx
    push  edx

    mov   ebx, eax                     ; EBX = color del rey
    mov   dl, 'K'
    cmp   ebx, TURNO_BLANCAS
    je    ej_buscar
    mov   dl, 'k'
ej_buscar:
    xor   ecx, ecx                     ; ECX = casilla que se revisa
ej_loop:
    mov   eax, ecx
    call  ObtenerPieza
    cmp   al, dl
    je    ej_hallado
    inc   ecx
    cmp   ecx, TAM_TABLERO
    jb    ej_loop
    xor   eax, eax                     ; no hay rey: no hay jaque
    jmp   ej_fin
ej_hallado:
    mov   eax, ecx                     ; casilla del rey
    xor   bl, 1                        ; color atacante = el contrario
    call  CasillaAtacada
ej_fin:
    pop   edx
    pop   ecx
    pop   ebx
    ret
EstaEnJaque ENDP

; ------------------------------------------------------------
; CaminoLibre   (auxiliar interna)
; Comprueba que las casillas ENTRE origen y destino esten vacias.
; Solo para movimientos en linea recta o diagonal.
; In : ESI = origen, EDI = destino (distintos y alineados)
; Out: EAX = 1 si el camino esta libre, 0 si hay una pieza en medio.
;      Preserva el resto.
; ------------------------------------------------------------
CaminoLibre PROC
    push  ebx
    push  ecx
    push  edx

    mov   eax, esi
    shr   eax, 3
    mov   dh, al                       ; DH = fila actual
    mov   eax, esi
    and   eax, 7
    mov   dl, al                       ; DL = columna actual
    mov   eax, edi
    shr   eax, 3
    mov   ch, al                       ; CH = fila destino
    mov   eax, edi
    and   eax, 7
    mov   cl, al                       ; CL = columna destino

    xor   ebx, ebx                     ; BH = paso de fila, BL = paso de columna
    cmp   ch, dh
    je    cam_fila_fin
    ja    cam_fila_mas
    mov   bh, -1
    jmp   cam_fila_fin
cam_fila_mas:
    mov   bh, 1
cam_fila_fin:
    cmp   cl, dl
    je    cam_col_fin
    ja    cam_col_mas
    mov   bl, -1
    jmp   cam_col_fin
cam_col_mas:
    mov   bl, 1
cam_col_fin:

cam_paso:
    add   dh, bh
    add   dl, bl
    cmp   dh, ch
    jne   cam_revisar
    cmp   dl, cl
    je    cam_libre                    ; llegamos al destino sin bloqueos
cam_revisar:
    call  PiezaEnFC                    ; siempre dentro del tablero aqui
    cmp   al, CASILLA_VACIA
    je    cam_paso
    xor   eax, eax                     ; hay una pieza en medio
    jmp   cam_fin
cam_libre:
    mov   eax, 1
cam_fin:
    pop   edx
    pop   ecx
    pop   ebx
    ret
CaminoLibre ENDP

; ------------------------------------------------------------
; ValidarEnroque   (auxiliar interna)
; Comprueba si el rey en ESI puede hacer el enroque hacia EDI
; (destino a dos columnas: corto = +2, largo = -2).
; Condiciones: rey y torre sin haberse movido (derechos), torre en
; su esquina, casillas entre ellos vacias, y que el rey no este en
; jaque ni pase o termine en una casilla atacada.
; In : ESI = origen (rey), EDI = destino
; Out: EAX = 1 si el enroque es valido, 0 si no. Preserva el resto.
; ------------------------------------------------------------
ValidarEnroque PROC
    push  ebx
    push  ecx
    push  edx
    push  ebp

    mov   eax, esi
    call  ObtenerPieza
    call  ColorDePieza
    mov   ebp, eax                     ; EBP = color del rey
    mov   ecx, 0                       ; CL = bit base de los derechos
    mov   edx, 4                       ; casilla inicial del rey blanco (e1)
    cmp   ebp, TURNO_BLANCAS
    je    ve_ini
    mov   ecx, 2
    mov   edx, 60                      ; casilla inicial del rey negro (e8)
ve_ini:
    cmp   esi, edx
    jne   ve_no                        ; el rey no esta en su casilla inicial
    mov   ebx, ebp
    xor   ebx, 1                       ; BL = color enemigo (para CasillaAtacada)

    mov   eax, edi
    sub   eax, esi
    cmp   eax, 2
    je    ve_corto
    cmp   eax, -2
    je    ve_largo
    jmp   ve_no

; ---- Enroque corto: torre en esi+3; libres esi+1 y esi+2 ----
ve_corto:
    mov   edx, 1
    shl   edx, cl                      ; mascara del derecho de enroque corto
    test  derechosEnroque, edx
    jz    ve_no
    lea   eax, [esi+3]
    call  ObtenerPieza
    mov   dl, 'R'
    cmp   ebp, TURNO_BLANCAS
    je    ve_c_torre
    mov   dl, 'r'
ve_c_torre:
    cmp   al, dl                       ; torre propia en su esquina
    jne   ve_no
    lea   eax, [esi+1]
    call  ObtenerPieza
    cmp   al, CASILLA_VACIA
    jne   ve_no
    lea   eax, [esi+2]
    call  ObtenerPieza
    cmp   al, CASILLA_VACIA
    jne   ve_no
    xor   edx, edx                     ; rey: esi, esi+1, esi+2 no atacadas
ve_c_atq:
    lea   eax, [esi+edx]
    call  CasillaAtacada
    test  eax, eax
    jnz   ve_no
    inc   edx
    cmp   edx, 2
    jbe   ve_c_atq
    jmp   ve_si

; ---- Enroque largo: torre en esi-4; libres esi-1, esi-2 y esi-3 ----
ve_largo:
    mov   edx, 1
    inc   ecx                          ; el bit del enroque largo es el siguiente
    shl   edx, cl
    test  derechosEnroque, edx
    jz    ve_no
    lea   eax, [esi-4]
    call  ObtenerPieza
    mov   dl, 'R'
    cmp   ebp, TURNO_BLANCAS
    je    ve_l_torre
    mov   dl, 'r'
ve_l_torre:
    cmp   al, dl
    jne   ve_no
    lea   eax, [esi-1]
    call  ObtenerPieza
    cmp   al, CASILLA_VACIA
    jne   ve_no
    lea   eax, [esi-2]
    call  ObtenerPieza
    cmp   al, CASILLA_VACIA
    jne   ve_no
    lea   eax, [esi-3]
    call  ObtenerPieza
    cmp   al, CASILLA_VACIA
    jne   ve_no
    xor   edx, edx                     ; rey: esi, esi-1, esi-2 no atacadas
ve_l_atq:
    mov   eax, esi
    sub   eax, edx
    call  CasillaAtacada
    test  eax, eax
    jnz   ve_no
    inc   edx
    cmp   edx, 2
    jbe   ve_l_atq

ve_si:
    mov   eax, 1
    jmp   ve_fin
ve_no:
    xor   eax, eax
ve_fin:
    pop   ebp
    pop   edx
    pop   ecx
    pop   ebx
    ret
ValidarEnroque ENDP

; ------------------------------------------------------------
; MovimientoPseudoLegal
; Comprueba SOLO la geometria del movimiento de la pieza en el origen
; (incluye bloqueo de camino y reglas del peon). No mira turnos ni si
; el propio rey queda en jaque. Supone que el destino no tiene una
; pieza del mismo color.
; In : ESI = origen, EDI = destino
; Out: EAX = 1 si el movimiento es valido para esa pieza, 0 si no.
;      Preserva el resto.
; ------------------------------------------------------------
MovimientoPseudoLegal PROC
    push  ebx
    push  ecx
    push  edx
    push  ebp

    cmp   esi, edi
    je    pl_no

    mov   eax, esi
    call  ObtenerPieza                 ; AL = pieza
    mov   bl, al
    call  ColorDePieza                 ; EAX = color de la pieza
    mov   ebp, eax                     ; EBP = color

    mov   eax, edi
    shr   eax, 3
    mov   ecx, esi
    shr   ecx, 3
    sub   eax, ecx
    mov   ecx, eax                     ; ECX = df (fila destino - fila origen)
    mov   eax, edi
    and   eax, 7
    mov   edx, esi
    and   edx, 7
    sub   eax, edx
    mov   edx, eax                     ; EDX = dc (col destino - col origen)

    and   bl, 0DFh                     ; BL = tipo de pieza en mayuscula
    cmp   bl, 'N'
    je    pl_caballo
    cmp   bl, 'K'
    je    pl_rey
    cmp   bl, 'R'
    je    pl_torre
    cmp   bl, 'B'
    je    pl_alfil
    cmp   bl, 'Q'
    je    pl_dama
    cmp   bl, 'P'
    je    pl_peon
    jmp   pl_no

; ---- Caballo: (1,2) o (2,1) -> |df*dc| = 2 ----
pl_caballo:
    mov   eax, ecx
    imul  eax, edx
    cmp   eax, 2
    je    pl_si
    cmp   eax, -2
    je    pl_si
    jmp   pl_no

; ---- Rey: una casilla en cualquier direccion, o enroque ----
pl_rey:
    test  ecx, ecx                     ; df == 0 y |dc| == 2 -> enroque
    jnz   pl_rey_normal
    cmp   edx, 2
    je    pl_enroque
    cmp   edx, -2
    je    pl_enroque
pl_rey_normal:
    mov   eax, ecx
    add   eax, 1
    cmp   eax, 2
    ja    pl_no                        ; |df| > 1
    mov   eax, edx
    add   eax, 1
    cmp   eax, 2
    ja    pl_no                        ; |dc| > 1
    jmp   pl_si
pl_enroque:
    call  ValidarEnroque
    jmp   pl_fin

; ---- Torre: recta ----
pl_torre:
    test  ecx, ecx
    jz    pl_recta
    test  edx, edx
    jz    pl_recta
    jmp   pl_no

; ---- Dama: recta o diagonal ----
pl_dama:
    test  ecx, ecx
    jz    pl_recta
    test  edx, edx
    jz    pl_recta
    jmp   pl_diagonal

; ---- Alfil: diagonal ----
pl_alfil:
pl_diagonal:
    mov   eax, ecx
    test  eax, eax
    jns   pl_diag_1
    neg   eax
pl_diag_1:
    mov   ebx, edx
    test  ebx, ebx
    jns   pl_diag_2
    neg   ebx
pl_diag_2:
    cmp   eax, ebx                     ; |df| == |dc| ?
    jne   pl_no
    call  CaminoLibre
    jmp   pl_fin

pl_recta:
    call  CaminoLibre
    jmp   pl_fin

; ---- Peon ----
pl_peon:
    mov   ebx, 1                       ; EBX = direccion de avance (blanco +1)
    cmp   ebp, TURNO_BLANCAS
    je    pl_peon_dir
    mov   ebx, -1                      ; negro -1
pl_peon_dir:
    cmp   ecx, ebx                     ; avanza una fila?
    jne   pl_peon_doble
    test  edx, edx
    jnz   pl_peon_captura

    mov   eax, edi                     ; avance recto: destino vacio
    call  ObtenerPieza
    cmp   al, CASILLA_VACIA
    jne   pl_no
    jmp   pl_si

pl_peon_captura:
    mov   eax, edx
    add   eax, 1
    cmp   eax, 2
    ja    pl_no                        ; debe ser exactamente una columna al lado
    mov   eax, edi
    call  ObtenerPieza
    cmp   al, CASILLA_VACIA
    je    pl_peon_paso                 ; destino vacio: solo vale al paso
    call  ColorDePieza                 ; color de lo que hay en el destino
    mov   ebx, ebp
    xor   ebx, 1                       ; color contrario
    cmp   eax, ebx
    jne   pl_no                        ; debe haber una pieza enemiga
    jmp   pl_si
pl_peon_paso:
    cmp   edi, casillaAlPaso           ; captura al paso: solo en la casilla
    je    pl_si                        ; que el peon rival acaba de saltar
    jmp   pl_no

pl_peon_doble:
    mov   eax, ebx
    add   eax, eax                     ; 2 * direccion
    cmp   ecx, eax
    jne   pl_no
    test  edx, edx
    jnz   pl_no                        ; el doble avance es recto
    mov   eax, esi
    shr   eax, 3                       ; fila de origen
    mov   ebx, 1                       ; fila inicial blanca
    cmp   ebp, TURNO_BLANCAS
    je    pl_peon_ini
    mov   ebx, 6                       ; fila inicial negra
pl_peon_ini:
    cmp   eax, ebx
    jne   pl_no
    call  CaminoLibre                  ; la casilla intermedia debe estar vacia
    test  eax, eax
    jz    pl_no
    mov   eax, edi                     ; y el destino tambien
    call  ObtenerPieza
    cmp   al, CASILLA_VACIA
    jne   pl_no
    jmp   pl_si

pl_si:
    mov   eax, 1
    jmp   pl_fin
pl_no:
    xor   eax, eax
pl_fin:
    pop   ebp
    pop   edx
    pop   ecx
    pop   ebx
    ret
MovimientoPseudoLegal ENDP

; ------------------------------------------------------------
; DejaReyEnJaque
; Simula el movimiento origen -> destino y comprueba si el rey del
; que mueve quedaria atacado. Deshace la simulacion antes de volver
; (el tablero queda exactamente como estaba).
; In : ESI = origen, EDI = destino
; Out: EAX = 1 si su propio rey quedaria en jaque, 0 si no.
;      Preserva el resto.
; ------------------------------------------------------------
DejaReyEnJaque PROC
    push  ebx
    push  ecx
    push  edx

    mov   eax, esi
    call  ObtenerPieza
    mov   ch, al                       ; CH = pieza que se mueve
    call  ColorDePieza
    mov   edx, eax                     ; EDX = su color
    mov   eax, edi
    call  ObtenerPieza
    mov   cl, al                       ; CL = contenido original del destino

    mov   eax, edi                     ; destino <- pieza
    mov   bl, ch
    call  ColocarPieza
    mov   eax, esi                     ; origen <- vacio
    mov   bl, CASILLA_VACIA
    call  ColocarPieza

    ; Captura al paso: tambien desaparece el peon capturado, que esta en
    ; la fila del origen y la columna del destino.
    mov   simCapSq, SIN_JUGADA
    mov   al, ch
    and   al, 0DFh
    cmp   al, 'P'
    jne   dj_sin_paso                  ; no es un peon
    cmp   cl, CASILLA_VACIA
    jne   dj_sin_paso                  ; el destino no esta vacio
    cmp   edi, casillaAlPaso
    jne   dj_sin_paso                  ; no es la casilla al paso
    mov   eax, esi
    xor   eax, edi
    test  al, 7
    jz    dj_sin_paso                  ; misma columna: no es una captura
    mov   eax, esi
    and   eax, 0FFFFFFF8h              ; fila del origen
    mov   ebx, edi
    and   ebx, 7                       ; columna del destino
    add   eax, ebx
    mov   simCapSq, eax
    call  ObtenerPieza
    mov   simCapPz, al                 ; recordar el peon capturado
    mov   eax, simCapSq
    mov   bl, CASILLA_VACIA
    call  ColocarPieza
dj_sin_paso:

    mov   eax, edx
    call  EstaEnJaque                  ; EAX = 1 si ese rey esta atacado
    push  eax                          ; guardar el resultado

    cmp   simCapSq, SIN_JUGADA         ; deshacer la captura al paso
    je    dj_restaurar
    mov   eax, simCapSq
    mov   bl, simCapPz
    call  ColocarPieza
dj_restaurar:

    mov   eax, edi                     ; deshacer: destino <- lo que habia
    mov   bl, cl
    call  ColocarPieza
    mov   eax, esi                     ; origen <- pieza original
    mov   bl, ch
    call  ColocarPieza

    pop   eax
    pop   edx
    pop   ecx
    pop   ebx
    ret
DejaReyEnJaque ENDP

; ------------------------------------------------------------
; TieneMovimientoLegal
; Busca si un color tiene AL MENOS un movimiento legal.
; In : EAX = color (TURNO_*)
; Out: EAX = 1 si tiene alguno, 0 si no. Preserva el resto.
; ------------------------------------------------------------
TieneMovimientoLegal PROC
    push  ebx
    push  ecx
    push  edx
    push  esi
    push  edi
    push  ebp

    mov   ebp, eax                     ; EBP = color
    xor   esi, esi                     ; ESI = origen
tm_origen:
    mov   eax, esi
    call  ObtenerPieza
    call  ColorDePieza
    cmp   eax, ebp
    jne   tm_sig_origen                ; no es pieza de ese color

    xor   edi, edi                     ; EDI = destino
tm_destino:
    cmp   edi, esi
    je    tm_sig_destino
    mov   eax, edi
    call  ObtenerPieza
    call  ColorDePieza
    cmp   eax, ebp
    je    tm_sig_destino               ; casilla con pieza propia
    call  MovimientoPseudoLegal
    test  eax, eax
    jz    tm_sig_destino
    call  DejaReyEnJaque
    test  eax, eax
    jnz   tm_sig_destino
    mov   eax, 1                       ; encontrado un movimiento legal
    jmp   tm_fin
tm_sig_destino:
    inc   edi
    cmp   edi, TAM_TABLERO
    jb    tm_destino

tm_sig_origen:
    inc   esi
    cmp   esi, TAM_TABLERO
    jb    tm_origen

    xor   eax, eax                     ; ninguno
tm_fin:
    pop   ebp
    pop   edi
    pop   esi
    pop   edx
    pop   ecx
    pop   ebx
    ret
TieneMovimientoLegal ENDP

; ------------------------------------------------------------
; ValidarMovimiento
; Valida una jugada del jugador al que le toca.
; In : ESI = origen (0-63), EDI = destino (0-63)
; Out: EAX = MOV_OK, MOV_ILEGAL_PIEZA, MOV_ORIGEN_VACIO,
;            MOV_NO_ES_TU_TURNO, MOV_DESTINO_PROPIO o MOV_DEJA_EN_JAQUE
;      Preserva todo lo demas (no modifica el tablero).
; ------------------------------------------------------------
ValidarMovimiento PROC
    push  ebx
    push  ecx
    push  edx

    cmp   esi, edi
    je    vm_ilegal

    mov   eax, esi
    call  ObtenerPieza
    cmp   al, CASILLA_VACIA
    je    vm_vacio
    call  ColorDePieza
    cmp   eax, turnoActual
    jne   vm_turno                     ; pieza del otro jugador

    mov   eax, edi
    call  ObtenerPieza
    call  ColorDePieza
    cmp   eax, turnoActual
    je    vm_propia                    ; captura de pieza propia

    call  MovimientoPseudoLegal
    test  eax, eax
    jz    vm_ilegal

    call  DejaReyEnJaque
    test  eax, eax
    jnz   vm_jaque

    mov   eax, MOV_OK
    jmp   vm_fin
vm_ilegal:
    mov   eax, MOV_ILEGAL_PIEZA
    jmp   vm_fin
vm_vacio:
    mov   eax, MOV_ORIGEN_VACIO
    jmp   vm_fin
vm_turno:
    mov   eax, MOV_NO_ES_TU_TURNO
    jmp   vm_fin
vm_propia:
    mov   eax, MOV_DESTINO_PROPIO
    jmp   vm_fin
vm_jaque:
    mov   eax, MOV_DEJA_EN_JAQUE
vm_fin:
    pop   edx
    pop   ecx
    pop   ebx
    ret
ValidarMovimiento ENDP

; ------------------------------------------------------------
; EstadoPartida
; Estado del jugador al que le toca mover.
; In : EAX = color que debe mover (TURNO_*)
; Out: EAX = PARTIDA_NORMAL, PARTIDA_JAQUE, PARTIDA_MATE o
;            PARTIDA_AHOGADO (sin jugadas legales y sin jaque).
;      Preserva el resto.
; ------------------------------------------------------------
EstadoPartida PROC
    push  ebx
    push  ecx

    mov   ebx, eax                     ; EBX = color
    call  EstaEnJaque
    mov   ecx, eax                     ; ECX = 1 si esta en jaque
    mov   eax, ebx
    call  TieneMovimientoLegal
    test  eax, eax
    jnz   ep_hay_jugadas

    test  ecx, ecx                     ; sin jugadas legales
    jz    ep_ahogado
    mov   eax, PARTIDA_MATE
    jmp   ep_fin
ep_ahogado:
    mov   eax, PARTIDA_AHOGADO
    jmp   ep_fin

ep_hay_jugadas:
    mov   eax, PARTIDA_NORMAL
    test  ecx, ecx
    jz    ep_fin
    mov   eax, PARTIDA_JAQUE
ep_fin:
    pop   ecx
    pop   ebx
    ret
EstadoPartida ENDP

; ------------------------------------------------------------
; EsPromocion
; Dice si una jugada mueve un peon a la ultima fila.
; In : ESI = origen, EDI = destino
; Out: EAX = 1 si es una promocion, 0 si no. Preserva el resto.
; ------------------------------------------------------------
EsPromocion PROC
    mov   eax, esi
    call  ObtenerPieza
    cmp   al, 'P'
    je    pr_blanca
    cmp   al, 'p'
    je    pr_negra
    jmp   pr_no
pr_blanca:
    mov   eax, edi
    shr   eax, 3                       ; fila del destino
    cmp   eax, 7                       ; fila 8
    jne   pr_no
    mov   eax, 1
    ret
pr_negra:
    mov   eax, edi
    shr   eax, 3
    test  eax, eax                     ; fila 1
    jnz   pr_no
    mov   eax, 1
    ret
pr_no:
    xor   eax, eax
    ret
EsPromocion ENDP

; ------------------------------------------------------------
; EjecutarMovimiento
; Aplica al tablero una jugada YA VALIDADA (ValidarMovimiento = MOV_OK),
; incluidas las especiales, y actualiza el estado de las reglas:
;   * enroque: ademas del rey, mueve la torre
;   * captura al paso: retira el peon capturado
;   * promocion: reemplaza el peon por la pieza elegida
;   * registra si un peon avanzo dos casillas (posible captura al paso)
;   * borra los derechos de enroque cuando se mueve o captura un rey
;     o una torre en su casilla inicial
; No cambia el turno (eso lo hace CambiarTurno).
; In : ESI = origen, EDI = destino,
;      BL  = pieza de promocion en MAYUSCULA ('Q','R','B','N');
;            se ignora si la jugada no es una promocion
; Out: EAX = TIPO_NORMAL, TIPO_ENROQUE_CORTO, TIPO_ENROQUE_LARGO,
;            TIPO_AL_PASO o TIPO_PROMOCION. Preserva el resto.
; ------------------------------------------------------------
EjecutarMovimiento PROC
    pushad
    movzx ebp, bl                      ; EBP = pieza elegida para promocion

    mov   tipoJugada, TIPO_NORMAL
    mov   nuevoAlPaso, SIN_JUGADA      ; por defecto no hay captura al paso

    mov   eax, esi
    call  ObtenerPieza
    mov   bl, al                       ; BL = pieza que se mueve
    call  ColorDePieza
    mov   edx, eax                     ; EDX = su color
    mov   eax, edi
    call  ObtenerPieza
    mov   bh, al                       ; BH = contenido del destino

    mov   al, bl
    and   al, 0DFh                     ; tipo en mayuscula
    cmp   al, 'P'
    je    xm_peon
    cmp   al, 'K'
    je    xm_rey
    jmp   xm_mover

; ---- Peon: avance doble o captura al paso ----
xm_peon:
    mov   eax, edi
    sub   eax, esi                     ; +-16 = avance de dos filas
    cmp   eax, 16
    je    xm_doble
    cmp   eax, -16
    je    xm_doble
    cmp   bh, CASILLA_VACIA
    jne   xm_mover                     ; captura normal
    mov   eax, esi
    xor   eax, edi
    test  al, 7
    jz    xm_mover                     ; avance recto de una casilla
    mov   eax, esi                     ; captura al paso: quitar el peon rival
    and   eax, 0FFFFFFF8h              ; fila del origen
    mov   ecx, edi
    and   ecx, 7                       ; columna del destino
    add   eax, ecx
    push  ebx
    mov   bl, CASILLA_VACIA
    call  ColocarPieza
    pop   ebx
    mov   tipoJugada, TIPO_AL_PASO
    jmp   xm_mover
xm_doble:
    lea   eax, [esi+edi]
    shr   eax, 1                       ; casilla intermedia
    mov   nuevoAlPaso, eax
    jmp   xm_mover

; ---- Rey: enroque si avanza dos columnas ----
xm_rey:
    mov   eax, edi
    sub   eax, esi
    cmp   eax, 2
    je    xm_enroque_corto
    cmp   eax, -2
    je    xm_enroque_largo
    jmp   xm_mover
xm_enroque_corto:                      ; torre: esi+3 -> esi+1
    push  esi
    push  edi
    lea   edi, [esi+1]
    add   esi, 3
    call  MoverPieza
    pop   edi
    pop   esi
    mov   tipoJugada, TIPO_ENROQUE_CORTO
    jmp   xm_mover
xm_enroque_largo:                      ; torre: esi-4 -> esi-1
    push  esi
    push  edi
    lea   edi, [esi-1]
    sub   esi, 4
    call  MoverPieza
    pop   edi
    pop   esi
    mov   tipoJugada, TIPO_ENROQUE_LARGO

; ---- Mover la pieza principal (rey, peon o cualquier otra) ----
xm_mover:
    call  MoverPieza                   ; ESI -> EDI

    mov   al, bl
    and   al, 0DFh
    cmp   al, 'P'
    jne   xm_derechos
    mov   eax, edi
    shr   eax, 3                       ; fila del destino
    cmp   eax, 7
    je    xm_promo
    test  eax, eax
    jnz   xm_derechos                  ; ni fila 8 ni fila 1
xm_promo:
    mov   ecx, ebp                     ; pieza elegida (mayuscula)
    cmp   edx, TURNO_BLANCAS
    je    xm_promo_col
    or    cl, 20h                      ; las negras van en minuscula
xm_promo_col:
    mov   eax, edi
    mov   bl, cl
    call  ColocarPieza                 ; reemplaza el peon
    mov   tipoJugada, TIPO_PROMOCION

; ---- Derechos de enroque: perder los que afecta esta jugada ----
xm_derechos:
    xor   ecx, ecx
xm_der_loop:
    movzx eax, BYTE PTR tblDerSq[ecx]
    cmp   eax, esi
    je    xm_der_borrar
    cmp   eax, edi
    jne   xm_der_sig
xm_der_borrar:
    movzx eax, BYTE PTR tblDerMk[ecx]
    not   eax
    and   derechosEnroque, eax
xm_der_sig:
    inc   ecx
    cmp   ecx, 6
    jb    xm_der_loop

    mov   eax, nuevoAlPaso             ; guardar la casilla al paso para el
    mov   casillaAlPaso, eax           ; turno siguiente
    popad
    mov   eax, tipoJugada
    ret
EjecutarMovimiento ENDP

EstablecerReglasRemotas PROC
    mov derechosEnroque,eax
    mov casillaAlPaso,edx
    ret
EstablecerReglasRemotas ENDP
END
