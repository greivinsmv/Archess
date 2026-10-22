# arChess

**English** | [Español](README.es.md)

A Windows chess application written in **32-bit x86 assembly with MASM**. The graphical client uses the Win32 API and GDI for the board, Unicode chess pieces, mouse input and legal-move hints. A separate Python bridge supports two-player games through Firebase Realtime Database.

The board representation, local move validation and graphical interface are implemented in assembly. Online moves are also checked by the Python bridge using `python-chess` before a Firebase transaction updates the game.

## Features

- Two players on the same computer, without a cloud connection.
- Online play as White or Black through a shared Firebase room.
- Legal-move and capture markers, board rotation and turn indicators.
- Check, checkmate and stalemate detection.
- Kingside and queenside castling, en passant and promotion to a queen, rook, bishop or knight.
- Resignation and draw controls. In online games, a draw offer requires the opponent's acceptance.
- Background network requests so synchronization does not run on the window's message loop.

The interface is in Spanish. The local engine does not implement every tournament draw rule, including repetition and insufficient material. Online adjudication uses `python-chess`, so its automatic draw handling can differ from local play.

## Build on Windows

Install:

- Visual Studio with **Desktop development with C++**, a Windows SDK and **MSVC v143 — VS 2022 C++ x64/x86 build tools**. The project selects `v143`; a newer IDE may need this component installed separately.
- The **Irvine32** include files and library, installed separately.

Open `TestMASM.sln`, select **Debug | x86** and build the solution. The default Irvine directory is `C:\Irvine`; set the `IrvineDir` MSBuild property if your installation is elsewhere.

From a Visual Studio Developer PowerShell:

```powershell
msbuild TestMASM.sln /m /p:Configuration=Debug /p:Platform=x86 /p:IrvineDir="C:\Irvine"
```

The graphical executable is `Debug\arChess.exe`. Use the x86 configuration, including on a 64-bit Windows computer. Irvine32 is not bundled with the source.

### Build troubleshooting

**MSB8020: the build tools for Visual Studio 2022 cannot be found** means that the selected `v143` toolset is missing. In Visual Studio Installer, choose **Modify → Individual components** and install **MSVC v143 — VS 2022 C++ x64/x86 build tools**. You can keep your current Visual Studio installation.

Alternatively, right-click the **TestMASM project → Properties**, select **All Configurations | Win32**, and choose an installed toolset under **Configuration Properties → General → Platform Toolset**. This changes `TestMASM.vcxproj`; rebuild and check the game with that toolset. Compatibility with newer toolsets has not been verified here.

After a failed build, Visual Studio may report that it cannot find `Debug\arChess.exe`. Check **View → Output → Build** for the first compilation error: the executable is only created after a successful build.

If the build reports that `Irvine32.inc` or `Irvine32.lib` is missing, check that both files are installed in `C:\Irvine` or set `IrvineDir` to their directory using the command above.

## Play locally

After building, run:

```powershell
.\iniciar_juego.cmd
```

Select **Partida local** for two players on the same computer. Local play does not require Python or Firebase credentials.

Click a piece belonging to the current player, then a marked destination. Dots indicate legal moves; rings indicate captures. Select the promotion piece in the side panel when a pawn reaches the last rank. **Girar tablero** changes the view without changing the position.

## Set up online play

The online bridge is an academic prototype for a controlled environment. It uses the Firebase Admin SDK, whose service-account credentials can access the database independently of client security rules. Keep this credential on trusted machines; this setup is not a public backend or a credential that should be distributed to players.

Install Python 3.12 or later and create a local environment:

```powershell
py -3.12 -m venv .venv
.\.venv\Scripts\python.exe -m pip install -r requirements.txt
```

The repository has no default database or shared credentials. Use your own Firebase project and store its service-account JSON **outside the repository**, then configure the current PowerShell session:

```powershell
$env:ARCHESS_FIREBASE_CREDENTIALS = "C:\Private\arChess\service-account.json"
$env:ARCHESS_FIREBASE_URL = "https://YOUR_PROJECT-default-rtdb.firebaseio.com"
$env:ARCHESS_ROOM = "prueba"

.\iniciar_juego.cmd -Online
```

Use your instance's exact database URL. `ARCHESS_ROOM` is optional and defaults to `prueba`; both players must use the same project and room. The launcher starts the local middleware and opens the game. Run it on each computer with a separate project directory.

- White selects **Crear / retomar con blancas**.
- Black selects **Unirme con negras**.
- Each installation keeps its own client identity. Do not copy runtime state between players.
- **Ofrecer / aceptar tablas** offers a draw or accepts the opponent's offer. Making a move declines the previous offer.
- When a game finishes, both players acknowledge the result before the room is cleared.

Connection failures are shown in the interface. Launcher diagnostics are saved under `logs/`. Keep credentials, local game state and logs out of commits. If a private key is exposed, revoke it in Google Cloud; deleting the file from Git does not revoke the key.

## Code layout

| File | Responsibility |
| --- | --- |
| `arChess.inc` | Shared constants, procedure declarations and register-based calling conventions |
| `board.asm` | Linear 64-byte board, indexing, piece access and board initialization |
| `move_validator.asm` | Legal moves, king safety, special moves and local game status |
| `gui_main.asm` | Win32 window, GDI drawing, selection, controls and network worker |
| `gui_win32.inc` | Win32 structures and function declarations |
| `sync_manager.asm` | Atomic file requests and correlated binary responses between MASM and Python |
| `firebase_multiplayer.py` | Firebase transactions, online validation, sessions and game synchronization |
| `iniciar_juego.ps1` | Local/online startup and lifecycle of launcher-owned processes |
| `gui_tests.inc`, `gui_fixtures.inc` | GUI selection tests and legal-destination fixtures |
| `main.asm`, `ui_console.asm` | Earlier console interface, retained as source |

Board positions use `index = rank * 8 + file`: `a1 = 0` and `h8 = 63`. Uppercase ASCII letters represent White pieces, lowercase letters represent Black, and `.` represents an empty square.

The Visual Studio project builds the graphical client by default. To build the console interface instead:

```powershell
msbuild TestMASM.sln /m /p:Configuration=Debug /p:Platform=x86 /p:ChessInterface=Console
.\iniciar_consola.cmd
```

This produces `Debug\arChess-console.exe`. Console moves use coordinate notation such as `e2e4`. The two interfaces have separate entry points and intermediate build directories.

## Tests and verification

The Python bridge has offline tests for game transactions, mailbox responses and configuration. From the repository root, after installing the dependencies:

```powershell
.\.venv\Scripts\python.exe -m unittest discover -s tests -v
```

The 27 tests passed with the real `python-chess` library and simulated Firebase operations. They do not read a key or contact a database.

The launcher's readiness checks can also be tested with a simulated process, without opening the game or connecting to Firebase:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\test_launcher.ps1
```

`gui_main.asm` includes a `GUI_TEST` conditional build that runs selection/movement checks and 153 legal-destination fixtures. These tests call the same procedures used by the graphical client and return a process exit code instead of opening the board.

Build and run them from a Visual Studio Developer PowerShell:

```powershell
msbuild TestMASM.sln /m /p:Configuration=Debug /p:Platform=x86 /p:RunGuiTests=true
$arChessTest = Start-Process -FilePath .\Debug\arChess-tests.exe -Wait -PassThru
$arChessTest.ExitCode
```

Add `/p:IrvineDir="C:\Irvine"` if you need to select your Irvine installation. The normal build still produces `arChess.exe`; the test build produces `arChess-tests.exe`.

A successful run returns `0`; a GUI self-test failure returns `1`, and fixture failures return `100 + fixture number`. A native Windows build is needed to execute them. The MASM build, graphical interface and online matches have not been verified in this Linux environment.
