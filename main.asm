; ============================================================
; main.asm  -  Bucle principal y control de estados
;              (arChess 4.0, Fase 2)
; ------------------------------------------------------------
; Es el unico modulo que invoca directamente a los demas.
; Maquina de estados (ver arChess.inc):
;   ESTADO_MENU, ESTADO_ESPERANDO_TURNO, ESTADO_MI_TURNO,
;   ESTADO_JAQUE, ESTADO_FIN_PARTIDA, ESTADO_ERROR_RED
;   (+ ESTADO_SALIR para terminar el programa)
;
; Fase 3: partida local con todas las reglas (enroque, captura al
; paso y promocion incluidas).
;   MENU, MI_TURNO, JAQUE y FIN_PARTIDA funcionan.
;   ESPERANDO_TURNO y ERROR_RED dependen de sync_manager.asm
;   (fase posterior): por ahora avisan y vuelven al menu.
;   ESTADO_JAQUE se comporta como MI_TURNO, pero avisa del jaque.
; ============================================================

INCLUDE arChess.inc

.data
estadoActual   DWORD ESTADO_MENU
syncActivo     DWORD 0

msgOpcionInv   BYTE "Opcion invalida. Elija 1, 2, 3 o 4.", 0
msgFormato     BYTE "Formato invalido. Use origen+destino (ej. e2e4), rendirse o tablas.", 0
msgTablas      BYTE "Ofrecer tablas requiere un oponente remoto (sync_manager.asm, fase posterior).", 0
msgFinPartida  BYTE "Partida terminada. Volviendo al menu.", 0
msgEsperando BYTE "Esperando al rival. R = rendirse, T = ofrecer/aceptar tablas.",0
msgOferta BYTE "Oferta enviada. El rival puede aceptar escribiendo tablas.",0
msgNoImpl      BYTE "Estado aun no implementado. Volviendo al menu.", 0
msgAdios       BYTE "Hasta luego.", 0

msgTurnoBlanc  BYTE "Turno de las BLANCAS (mayusculas).", 0
msgTurnoNegras BYTE "Turno de las NEGRAS (minusculas).", 0
msgJaque       BYTE "JAQUE!", 0

msgMateBlanc   BYTE "JAQUE MATE. Ganan las BLANCAS.", 0
msgMateNegras  BYTE "JAQUE MATE. Ganan las NEGRAS.", 0
msgAhogado     BYTE "Rey ahogado: la partida termina en tablas.", 0
msgRendBlanc   BYTE "Las BLANCAS se rinden. Ganan las NEGRAS.", 0
msgRendNegras  BYTE "Las NEGRAS se rinden. Ganan las BLANCAS.", 0

msgOrigenVac   BYTE "No hay pieza en la casilla de origen.", 0
msgNoTurno     BYTE "Esa pieza no es tuya: es el turno del otro jugador.", 0
msgDestPropio  BYTE "No puedes capturar tus propias piezas.", 0
msgDejaJaque   BYTE "Movimiento ilegal: dejaria a tu rey en jaque.", 0
msgIlegal      BYTE "Movimiento ilegal para esa pieza.", 0

msgEnroqueC    BYTE "Enroque corto.", 0
msgEnroqueL    BYTE "Enroque largo.", 0
msgAlPaso      BYTE "Captura al paso.", 0
msgPromocion   BYTE "Peon promovido.", 0

.code
main PROC
    call Sync_Inicializar

bucle_principal:
    mov   eax, estadoActual
    cmp   eax, ESTADO_MENU
    je    est_menu
    cmp   eax, ESTADO_MI_TURNO
    je    est_mi_turno
    cmp   eax, ESTADO_ESPERANDO_TURNO
    je    est_esperando
    cmp   eax, ESTADO_JAQUE
    je    est_mi_turno                 ; mismo manejo, pero avisa del jaque
    cmp   eax, ESTADO_FIN_PARTIDA
    je    est_fin
    cmp   eax, ESTADO_SALIR
    je    est_salir

    ; ESPERANDO_TURNO, ERROR_RED: pendientes
    mov   edx, OFFSET msgNoImpl
    call  UI_MostrarError
    mov   estadoActual, ESTADO_MENU
    jmp   bucle_principal

; ---------------- ESTADO_MENU ----------------
est_menu:
    call  UI_MostrarMenu               ; EAX = opcion
    cmp   eax, MENU_NUEVA
    je    elegir_nueva
    cmp   eax, MENU_MULTI_B
    je    elegir_multi_blancas
    cmp   eax, MENU_MULTI_N
    je    elegir_multi_negras
    cmp   eax, MENU_SALIR
    je    elegir_salir
    mov   edx, OFFSET msgOpcionInv
    call  UI_MostrarError
    jmp   bucle_principal
elegir_nueva:
    call  InicializarTablero
    call  IniciarTurnos                ; empiezan las blancas
    mov   syncActivo, 0
    mov   estadoActual, ESTADO_MI_TURNO
    jmp   bucle_principal
elegir_multi_blancas:
    call  InicializarTablero
    call  IniciarTurnos
    mov   syncActivo, 1
    mov   eax, TURNO_BLANCAS
    call  Sync_SeleccionarJugador
    call  Sync_NuevaPartida
    test eax,eax
    jz red_error
    call Sync_Unirse
    test eax,eax
    jz red_error
    mov edx,OFFSET msgEsperando
    call UI_MostrarMensaje
    mov   estadoActual, ESTADO_ESPERANDO_TURNO
    jmp   bucle_principal
elegir_multi_negras:
    call  InicializarTablero
    call  IniciarTurnos
    mov   syncActivo, 1
    mov   eax, TURNO_NEGRAS
    call  Sync_SeleccionarJugador
    call  Sync_Unirse
    test eax,eax
    jz red_error
    mov edx,OFFSET msgEsperando
    call UI_MostrarMensaje
    mov   estadoActual, ESTADO_ESPERANDO_TURNO
    jmp   bucle_principal
elegir_salir:
    mov   estadoActual, ESTADO_SALIR
    jmp   bucle_principal

; ------------ ESTADO_MI_TURNO / ESTADO_JAQUE ------------
est_esperando:
    call  Sync_ActualizarEstado
    cmp eax,-2
    je remoto_finalizado
    cmp eax,-1
    je red_error
    test  eax, eax
    jnz   esperando_mi_turno
    call ReadKey
    jz esperando_pausa
    or al,20h
    cmp al,'r'
    je turno_rendirse
    cmp al,'t'
    je turno_tablas
esperando_pausa:
    mov   eax, 500
    call  Delay
    jmp   bucle_principal
esperando_mi_turno:
    mov   estadoActual, ESTADO_MI_TURNO
    jmp   bucle_principal

est_mi_turno:
    cmp   syncActivo, 0
    je    est_mi_turno_local
    call  Sync_ActualizarEstado
    cmp eax,-2
    je remoto_finalizado
    cmp eax,-1
    je red_error
    test  eax, eax
    jz    est_esperando
est_mi_turno_local:
    call  DibujarTablero

    cmp   estadoActual, ESTADO_JAQUE
    jne   turno_aviso
    mov   edx, OFFSET msgJaque
    call  UI_MostrarMensaje

turno_aviso:
    call  ObtenerTurno                 ; EAX = de quien es el turno
    mov   edx, OFFSET msgTurnoBlanc
    cmp   eax, TURNO_BLANCAS
    je    turno_leer
    mov   edx, OFFSET msgTurnoNegras
turno_leer:
    call  UI_MostrarMensaje

    cmp syncActivo,0
    je leer_local
    call UI_LeerEntradaRemota
    cmp eax,4
    je remoto_finalizado
    cmp eax,5
    je red_error
    jmp leer_clasificar
leer_local:
    call  UI_LeerEntrada               ; EAX = tipo; ESI/EDI = origen/destino
leer_clasificar:
    cmp   eax, ENTRADA_JUGADA
    je    turno_jugada
    cmp   eax, ENTRADA_RENDIRSE
    je    turno_rendirse
    cmp   eax, ENTRADA_TABLAS
    je    turno_tablas
    mov   edx, OFFSET msgFormato       ; ENTRADA_INVALIDA
    call  UI_MostrarError
    jmp   bucle_principal

; ---- Jugada: validar, mover, cambiar turno y evaluar el nuevo estado ----
turno_jugada:
    cmp syncActivo,0
    jne turno_preparar_promo
    call  ValidarMovimiento            ; EAX = codigo (ESI/EDI intactos)
    test  eax, eax
    jnz   turno_rechazada

turno_preparar_promo:
    call  EsPromocion                  ; EAX = 1 si el peon llega a la ultima fila
    mov   bl, 'Q'                      ; por defecto, dama
    test  eax, eax
    jz    turno_ejecutar
    call  UI_LeerPromocion             ; AL = 'Q', 'R', 'B' o 'N'
    mov   bl, al
turno_ejecutar:
    cmp   syncActivo, 0
    je    turno_ejecutar_local
    push  esi
    push  edi
    call  Sync_PublicarMovimiento
    mov   ebp, eax
    pop   edi
    pop   esi
    test  ebp, ebp
    jz    turno_sync_rechazada
    call DibujarTablero
    mov edx,OFFSET msgEsperando
    call UI_MostrarMensaje
    mov estadoActual,ESTADO_ESPERANDO_TURNO
    jmp bucle_principal
turno_ejecutar_local:
    call  EjecutarMovimiento           ; aplica la jugada; EAX = tipo de jugada
    cmp   eax, TIPO_NORMAL
    je    turno_cambio
    mov   edx, OFFSET msgEnroqueC
    cmp   eax, TIPO_ENROQUE_CORTO
    je    turno_tipo_msg
    mov   edx, OFFSET msgEnroqueL
    cmp   eax, TIPO_ENROQUE_LARGO
    je    turno_tipo_msg
    mov   edx, OFFSET msgAlPaso
    cmp   eax, TIPO_AL_PASO
    je    turno_tipo_msg
    mov   edx, OFFSET msgPromocion     ; TIPO_PROMOCION
turno_tipo_msg:
    call  UI_MostrarMensaje

turno_cambio:
    call  CambiarTurno
    call  ObtenerTurno                 ; EAX = color al que le toca ahora
    call  EstadoPartida                ; EAX = estado de ese jugador
    cmp   eax, PARTIDA_MATE
    je    turno_mate
    cmp   eax, PARTIDA_AHOGADO
    je    turno_ahogado
    cmp   eax, PARTIDA_JAQUE
    je    turno_jaque
    mov   estadoActual, ESTADO_MI_TURNO
    jmp   bucle_principal

turno_sync_rechazada:
    mov   estadoActual, ESTADO_ESPERANDO_TURNO
    jmp   bucle_principal

turno_jaque:
    mov   estadoActual, ESTADO_JAQUE
    jmp   bucle_principal

turno_mate:
    call  DibujarTablero
    call  ObtenerTurno                 ; le toca al que recibio el mate
    mov   edx, OFFSET msgMateNegras    ; si le toca a las blancas, ganan negras
    cmp   eax, TURNO_BLANCAS
    je    turno_mate_msg
    mov   edx, OFFSET msgMateBlanc
turno_mate_msg:
    call  UI_MostrarMensaje
    mov   estadoActual, ESTADO_FIN_PARTIDA
    jmp   bucle_principal

turno_ahogado:
    call  DibujarTablero
    mov   edx, OFFSET msgAhogado
    call  UI_MostrarMensaje
    mov   estadoActual, ESTADO_FIN_PARTIDA
    jmp   bucle_principal

; ---- Jugada rechazada: explicar por que ----
turno_rechazada:
    mov   edx, OFFSET msgOrigenVac
    cmp   eax, MOV_ORIGEN_VACIO
    je    turno_error
    mov   edx, OFFSET msgNoTurno
    cmp   eax, MOV_NO_ES_TU_TURNO
    je    turno_error
    mov   edx, OFFSET msgDestPropio
    cmp   eax, MOV_DESTINO_PROPIO
    je    turno_error
    mov   edx, OFFSET msgDejaJaque
    cmp   eax, MOV_DEJA_EN_JAQUE
    je    turno_error
    mov   edx, OFFSET msgIlegal        ; MOV_ILEGAL_PIEZA
turno_error:
    call  UI_MostrarError
    jmp   bucle_principal

; ---- Comandos ----
turno_rendirse:
    cmp syncActivo,0
    je rendirse_local
    call Sync_Finalizar
    test eax,eax
    jz red_error
    jmp est_esperando
rendirse_local:
    call  ObtenerTurno
    mov   edx, OFFSET msgRendBlanc
    cmp   eax, TURNO_BLANCAS
    je    turno_rend_msg
    mov   edx, OFFSET msgRendNegras
turno_rend_msg:
    call  UI_MostrarMensaje
    mov   estadoActual, ESTADO_FIN_PARTIDA
    jmp   bucle_principal

turno_tablas:
    cmp syncActivo,0
    je tablas_local
    call Sync_Tablas
    test eax,eax
    jz red_error
    mov edx,OFFSET msgOferta
    call UI_MostrarMensaje
    jmp est_esperando
tablas_local:
    mov   edx, OFFSET msgTablas
    call  UI_MostrarMensaje
    jmp   bucle_principal

; ---------------- ESTADO_FIN_PARTIDA ----------------
est_fin:
    ; Local games never touch Firebase.
    mov   edx, OFFSET msgFinPartida
    call  UI_MostrarMensaje
    mov   estadoActual, ESTADO_MENU
    jmp   bucle_principal

remoto_finalizado:
    call DibujarTablero
    call Sync_ConfirmarFin
    mov syncActivo,0
    mov estadoActual,ESTADO_MENU
    jmp bucle_principal
red_error:
    mov syncActivo,0
    mov estadoActual,ESTADO_MENU
    jmp bucle_principal

; ---------------- ESTADO_SALIR ----------------
est_salir:
    mov   edx, OFFSET msgAdios
    call  UI_MostrarMensaje
    exit
main ENDP

END main
