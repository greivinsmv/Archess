# arChess

[English](README.md) | **Español**

Aplicación de ajedrez para Windows escrita en **Assembly x86 de 32 bits con MASM**. El cliente gráfico utiliza la API de Win32 y GDI para dibujar el tablero, representar las piezas con caracteres Unicode, recibir clics y marcar los movimientos legales. Un puente independiente en Python permite jugar entre dos computadoras mediante Firebase Realtime Database.

La representación del tablero, la validación local de movimientos y la interfaz gráfica están implementadas en Assembly. En las partidas en red, el puente de Python vuelve a comprobar las jugadas con `python-chess` antes de actualizar la partida mediante una transacción de Firebase.

## Funciones

- Dos jugadores en la misma computadora, sin conexión a la nube.
- Partidas en red con blancas o negras mediante una sala compartida en Firebase.
- Marcas de movimientos y capturas legales, rotación del tablero e indicadores de turno.
- Detección de jaque, jaque mate y rey ahogado.
- Enroque corto y largo, captura al paso y promoción a dama, torre, alfil o caballo.
- Controles para rendirse y acordar tablas. En red, el rival debe aceptar la oferta de tablas.
- Solicitudes de red en un trabajador separado del bucle de mensajes de la ventana.

La interfaz está en español. El motor local no incluye todas las reglas de tablas de competición, como la repetición y el material insuficiente. El modo en red utiliza `python-chess`, por lo que la resolución automática de tablas puede diferir de la partida local.

## Compilar en Windows

Instala:

- Visual Studio con **Desarrollo para el escritorio con C++**, un SDK de Windows y **MSVC v143 — herramientas de compilación de C++ x64/x86 de VS 2022**. El proyecto selecciona `v143`; una versión más reciente del IDE puede requerir instalar ese componente por separado.
- Los archivos de inclusión y la biblioteca **Irvine32**, instalados por separado.

Abre `TestMASM.sln`, selecciona **Debug | x86** y compila la solución. La ruta predeterminada de Irvine es `C:\Irvine`; si la instalaste en otra carpeta, configura la propiedad MSBuild `IrvineDir`.

Desde Developer PowerShell de Visual Studio:

```powershell
msbuild TestMASM.sln /m /p:Configuration=Debug /p:Platform=x86 /p:IrvineDir="C:\Irvine"
```

El ejecutable gráfico se genera en `Debug\arChess.exe`. Utiliza la configuración x86 incluso en un Windows de 64 bits. El código fuente no incluye Irvine32.

### Problemas de compilación

**MSB8020: no se pueden encontrar las herramientas de compilación para Visual Studio 2022** indica que falta el conjunto de herramientas `v143` seleccionado por el proyecto. En Visual Studio Installer, abre **Modificar → Componentes individuales** e instala **MSVC v143 — herramientas de compilación de C++ x64/x86 de VS 2022**. Puedes conservar tu instalación actual de Visual Studio.

Como alternativa, haz clic derecho en el **proyecto TestMASM → Propiedades**, selecciona **Todas las configuraciones | Win32** y elige un conjunto instalado en **Propiedades de configuración → General → Conjunto de herramientas de plataforma**. Esto modifica `TestMASM.vcxproj`; vuelve a compilar y comprueba el juego con ese conjunto. La compatibilidad con conjuntos más recientes no se ha verificado aquí.

Después de una compilación fallida, Visual Studio puede indicar que no encuentra `Debug\arChess.exe`. Revisa el primer error en **Ver → Salida → Compilación**: el ejecutable solo se genera cuando la compilación termina correctamente.

Si aparece un error por falta de `Irvine32.inc` o `Irvine32.lib`, comprueba que ambos estén instalados en `C:\Irvine` o indica su carpeta mediante `IrvineDir`, como en el comando anterior.

## Jugar en la misma computadora

Después de compilar, ejecuta:

```powershell
.\iniciar_juego.cmd
```

Selecciona **Partida local** para jugar entre dos personas en la misma computadora. Este modo no necesita Python ni credenciales de Firebase.

Haz clic en una pieza del jugador que tiene el turno y después en un destino marcado. Los puntos indican movimientos legales; los aros indican capturas. Cuando un peón llega a la última fila, elige la pieza de promoción en el panel lateral. **Girar tablero** cambia la vista sin modificar la posición.

## Preparar el modo en red

El puente en red es un prototipo académico para un entorno controlado. Utiliza el SDK de administración de Firebase: sus credenciales de cuenta de servicio pueden acceder a la base independientemente de las reglas de los clientes. Mantén esa credencial en computadoras de confianza; este diseño no es un backend público ni una credencial para distribuir entre jugadores.

Instala Python 3.12 o superior y crea un entorno local:

```powershell
py -3.12 -m venv .venv
.\.venv\Scripts\python.exe -m pip install -r requirements.txt
```

El repositorio no incluye una base de datos predeterminada ni credenciales compartidas. Utiliza tu propio proyecto Firebase y guarda su JSON de cuenta de servicio **fuera del repositorio**. Después configura la sesión actual de PowerShell:

```powershell
$env:ARCHESS_FIREBASE_CREDENTIALS = "C:\Private\arChess\service-account.json"
$env:ARCHESS_FIREBASE_URL = "https://YOUR_PROJECT-default-rtdb.firebaseio.com"
$env:ARCHESS_ROOM = "prueba"

.\iniciar_juego.cmd -Online
```

Coloca la URL exacta de tu instancia. `ARCHESS_ROOM` es opcional y utiliza `prueba` de forma predeterminada; ambos jugadores deben usar el mismo proyecto y sala. El lanzador inicia el middleware local y abre el juego. Cada computadora debe tener una carpeta de proyecto independiente.

- El jugador de blancas selecciona **Crear / retomar con blancas**.
- El de negras selecciona **Unirme con negras**.
- Cada instalación conserva su propia identidad de cliente. No copies el estado de ejecución entre jugadores.
- **Ofrecer / aceptar tablas** envía una oferta o acepta la del rival. Mover una pieza rechaza la oferta anterior.
- Al terminar, ambos jugadores confirman el resultado antes de limpiar la sala.

Los fallos de conexión se muestran en la interfaz. Los diagnósticos del lanzador se guardan en `logs/`. Excluye de los commits las credenciales, el estado local y los registros. Si una clave privada queda expuesta, revócala en Google Cloud: borrar el archivo de Git no revoca la clave.

## Organización del código

| Archivo | Responsabilidad |
| --- | --- |
| `arChess.inc` | Constantes compartidas, declaraciones de procedimientos y convenciones de llamada por registros |
| `board.asm` | Tablero lineal de 64 bytes, índices, acceso a piezas e inicialización |
| `move_validator.asm` | Movimientos legales, seguridad del rey, jugadas especiales y estado de la partida local |
| `gui_main.asm` | Ventana Win32, dibujo GDI, selección, controles y trabajador de red |
| `gui_win32.inc` | Estructuras y declaraciones de funciones Win32 |
| `sync_manager.asm` | Solicitudes atómicas en archivos y respuestas binarias correlacionadas entre MASM y Python |
| `firebase_multiplayer.py` | Transacciones Firebase, validación en red, sesiones y sincronización |
| `iniciar_juego.ps1` | Arranque local/en red y ciclo de vida de los procesos que inicia el lanzador |
| `gui_tests.inc`, `gui_fixtures.inc` | Pruebas de selección de la interfaz y casos de destinos legales |
| `main.asm`, `ui_console.asm` | Interfaz anterior de consola, conservada como código fuente |

Las posiciones utilizan `índice = fila * 8 + columna`: `a1 = 0` y `h8 = 63`. Las letras ASCII mayúsculas representan piezas blancas; las minúsculas, negras; y `.` indica una casilla vacía.

El proyecto de Visual Studio compila el cliente gráfico de forma predeterminada. Para compilar la interfaz de consola:

```powershell
msbuild TestMASM.sln /m /p:Configuration=Debug /p:Platform=x86 /p:ChessInterface=Console
.\iniciar_consola.cmd
```

Se genera `Debug\arChess-console.exe`. Los movimientos de consola se escriben con coordenadas como `e2e4`. Las dos interfaces utilizan puntos de entrada y carpetas de archivos intermedios separados.

## Pruebas y comprobación

El puente de Python incluye pruebas sin conexión para las transacciones de partidas, las respuestas al cliente y la configuración. Desde la raíz del repositorio, después de instalar las dependencias:

```powershell
.\.venv\Scripts\python.exe -m unittest discover -s tests -v
```

Las 23 pruebas pasaron con la biblioteca `python-chess` real y las operaciones de Firebase simuladas. No leen una clave ni se conectan a una base de datos.

`gui_main.asm` incluye una compilación condicional `GUI_TEST` que ejecuta comprobaciones de selección y movimiento y 153 casos de destinos legales. Las pruebas llaman a los mismos procedimientos que utiliza el cliente gráfico y devuelven un código de salida en lugar de abrir el tablero.

Compílalas y ejecútalas desde Developer PowerShell de Visual Studio:

```powershell
msbuild TestMASM.sln /m /p:Configuration=Debug /p:Platform=x86 /p:RunGuiTests=true
$arChessTest = Start-Process -FilePath .\Debug\arChess-tests.exe -Wait -PassThru
$arChessTest.ExitCode
```

Añade `/p:IrvineDir="C:\Irvine"` si necesitas indicar la instalación de Irvine. La compilación normal conserva `arChess.exe`; la de pruebas genera `arChess-tests.exe`.

Una ejecución correcta devuelve `0`; un fallo de las pruebas de interfaz devuelve `1`, y los fallos de los casos devuelven `100 + número de caso`. Se necesita una compilación nativa de Windows para ejecutarlas. La compilación MASM, la interfaz gráfica y las partidas en red no se han verificado en este entorno Linux.
