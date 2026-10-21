; ============================================================
; arChess.inc  -  Cabecera compartida (arChess 4.0, Hito 1 / Fase 1)
; ------------------------------------------------------------
; ADR #1: el tablero es un VECTOR LINEAL de 64 bytes.
;   indice = fila*8 + columna
;       fila    : 0 = fila 1 (blancas) ... 7 = fila 8 (negras)
;       columna : 0 = 'a' ... 7 = 'h'
;   => a1 = 0, h1 = 7, a8 = 56, h8 = 63
;
;   Todo acceso al tablero pasa por la rutina centralizada
;   ObtenerIndice (fila, columna). El arreglo 'board' es privado
;   de board.asm: el resto de modulos usa ObtenerPieza,
;   ColocarPieza y MoverPieza.
;
; Cada casilla guarda un caracter ASCII:
;   blancas = mayuscula (P N B R Q K)   negras = minuscula (p n b r q k)
;   vacia   = '.'
;
; Convencion de llamada entre modulos: por REGISTROS (como Irvine32).
; Cada rutina documenta sus entradas/salidas y preserva el resto.
; ============================================================

INCLUDE Irvine32.inc

TAM_TABLERO    = 64
CASILLA_VACIA  = '.'
SIN_JUGADA     = -1                    ; "no hay ultima jugada" (resaltado)

; ---- Estados de main.asm (maquina de estados del Hito 1) ----
ESTADO_MENU             = 0
ESTADO_ESPERANDO_TURNO  = 1
ESTADO_MI_TURNO         = 2
ESTADO_JAQUE            = 3
ESTADO_FIN_PARTIDA      = 4
ESTADO_ERROR_RED        = 5
ESTADO_SALIR            = 6            ; extra: termina el programa

; ---- Opciones del menu (UI_MostrarMenu) ----
MENU_INVALIDA  = 0
MENU_NUEVA     = 1
MENU_MULTI_B   = 2
MENU_MULTI_N   = 3
MENU_SALIR     = 4

; ---- Tipos de entrada (UI_LeerEntrada) ----
ENTRADA_INVALIDA = 0
ENTRADA_JUGADA   = 1
ENTRADA_RENDIRSE = 2
ENTRADA_TABLAS   = 3

; ---- Fase 2: turnos / colores ----
TURNO_BLANCAS  = 0
TURNO_NEGRAS   = 1
COLOR_NINGUNO  = 2                     ; casilla vacia

; ---- Codigos de ValidarMovimiento (en EAX) ----
MOV_OK               = 0
MOV_ILEGAL_PIEZA     = 1               ; la pieza no se mueve asi / camino bloqueado
MOV_ORIGEN_VACIO     = 2
MOV_NO_ES_TU_TURNO   = 3
MOV_DESTINO_PROPIO   = 4               ; intenta capturar una pieza propia
MOV_DEJA_EN_JAQUE    = 5               ; dejaria a su propio rey en jaque

; ---- Tipos de jugada (resultado de EjecutarMovimiento) ----
TIPO_NORMAL          = 0
TIPO_ENROQUE_CORTO   = 1
TIPO_ENROQUE_LARGO   = 2
TIPO_AL_PASO         = 3
TIPO_PROMOCION       = 4

; ---- Estado de la partida (EstadoPartida) ----
PARTIDA_NORMAL   = 0
PARTIDA_JAQUE    = 1
PARTIDA_MATE     = 2
PARTIDA_AHOGADO  = 3

; ---- board.asm ----
ObtenerIndice       PROTO
ObtenerPieza        PROTO
ColocarPieza        PROTO
MoverPieza          PROTO
InicializarTablero  PROTO
DibujarTablero      PROTO

; ---- sync_manager.asm ----
Sync_NuevaPartida   PROTO
Sync_Finalizar      PROTO
Sync_SeleccionarJugador PROTO
Sync_Unirse          PROTO
Sync_ActualizarEstado PROTO
Sync_PublicarMovimiento PROTO
EstablecerTurno      PROTO

; ---- ui_console.asm ----
UI_MostrarMenu      PROTO
UI_LeerEntrada      PROTO
UI_ParseSquare      PROTO
UI_MostrarMensaje   PROTO
UI_MostrarError     PROTO
UI_LeerPromocion    PROTO

; ---- move_validator.asm ----
ValidarEnroque          PROTO
EsPromocion             PROTO
EjecutarMovimiento      PROTO
IniciarTurnos           PROTO
CambiarTurno            PROTO
ObtenerTurno            PROTO
ColorDePieza            PROTO
ValidarMovimiento       PROTO
EstaEnJaque             PROTO
EstadoPartida           PROTO
CasillaAtacada          PROTO
MovimientoPseudoLegal   PROTO
DejaReyEnJaque          PROTO
TieneMovimientoLegal    PROTO

Sync_Inicializar PROTO
Sync_ConfirmarFin PROTO
Sync_Tablas PROTO
EstablecerReglasRemotas PROTO
UI_LeerEntradaRemota PROTO
