"""arChess: transactional Firebase games and a correlated, atomic MASM mailbox."""
from __future__ import annotations
import argparse
import copy
import json
import os
import re
import struct
import sys
import time
import uuid
from pathlib import Path

ROOT = Path(__file__).resolve().parent
import chess
import firebase_admin
from firebase_admin import credentials, db

DATABASE_URL = os.environ.get('ARCHESS_FIREBASE_URL')
CREDENTIALS_PATH = os.environ.get('ARCHESS_FIREBASE_CREDENTIALS')
DEFAULT_ROOM = os.environ.get('ARCHESS_ROOM', 'prueba')
MAGIC = 0x32484341
SNAPSHOT = struct.Struct('<8I64s33s127s')

def initialize():
    if firebase_admin._apps:
        return
    if not DATABASE_URL:
        raise ValueError('Configura ARCHESS_FIREBASE_URL para usar el modo online.')
    if not CREDENTIALS_PATH:
        raise ValueError('Configura ARCHESS_FIREBASE_CREDENTIALS con una credencial fuera del proyecto.')
    credential_file = Path(CREDENTIALS_PATH).expanduser().resolve()
    if credential_file == ROOT or ROOT in credential_file.parents:
        raise ValueError('La credencial de Firebase debe guardarse fuera de la carpeta del proyecto.')
    if not credential_file.is_file():
        raise ValueError('No se encontro el archivo configurado en ARCHESS_FIREBASE_CREDENTIALS.')
    try:
        certificate = credentials.Certificate(str(credential_file))
        firebase_admin.initialize_app(certificate, {'databaseURL': DATABASE_URL, 'httpTimeout': 12})
    except Exception:
        # SDK errors can contain credential details; keep those out of the console.
        raise RuntimeError('No se pudo iniciar Firebase. Revisa la configuracion y la credencial externa.') from None

def initial_board():
    return list('RNBQKBNR' + 'P'*8 + '.'*32 + 'p'*8 + 'rnbqkbnr')

def default_state(session=None):
    return dict(session=session or uuid.uuid4().hex, version=0, turn='white', board=initial_board(),
                fen=chess.STARTING_FEN, status='waiting', players={}, moves={}, updatedAt=time.time())

def room_ref(room):
    if not re.fullmatch(r'[A-Za-z0-9_-]{1,64}', room):
        raise ValueError('Nombre de sala invalido')
    return db.reference('/games/' + room)

def reply(code, state=None, error=None):
    result = {'ok': code.startswith('2'), 'code': code}
    if state is not None:
        result['state'] = copy.deepcopy(state)
    if error:
        result['error'] = error
    return result

def dispatch(command):
    op = command.get('op', 'get')
    ref = room_ref(str(command.get('room', DEFAULT_ROOM)))
    player = command.get('player', 'white')
    if player not in ('white', 'black'):
        raise ValueError('player debe ser white o black')
    client = str(command.get('client', 'manual'))
    session = command.get('session', '')
    request_id = str(command.get('id', 'manual'))
    new_session = uuid.uuid4().hex
    result = reply('500_ERROR')

    def transact(current):
        nonlocal result
        state = copy.deepcopy(current) if current else None
        if op == 'create':
            # Creating twice cannot erase a game another player is using.
            if state is not None:
                if state.get('players', {}).get('white', {}).get('client') == client:
                    result = reply('200_OK', state)
                else:
                    result = reply('409_SALA_OCUPADA', state)
                return current
            state = default_state(new_session)
            state['players'] = {'white': {'client': client}}
            result = reply('200_OK', state)
            return state
        if state is None:
            result = reply('200_CLEANED' if op == 'ack' else '404_SALA_NO_EXISTE')
            return {}
        if session and session != state.get('session'):
            result = reply('409_PARTIDA_ANTERIOR')
            return current
        if op == 'join':
            if state['status'] == 'finished':
                member = state.get('players', {}).get(player, {}).get('client') == client
                result = reply('200_OK' if member else '410_PARTIDA_TERMINADA', state)
                return current
            players = state.setdefault('players', {})
            if player in players and players[player].get('client') != client:
                result = reply('409_COLOR_OCUPADO', state)
                return current
            players[player] = {'client': client}
            state['status'] = 'ready' if len(players) == 2 else 'waiting'
            result = reply('200_OK', state)
            return state
        if op == 'get':
            result = reply('200_OK', state)
            return current
        if not session:
            result = reply('400_FALTA_SESSION')
            return current
        if state.get('players', {}).get(player, {}).get('client') != client:
            result = reply('403_JUGADOR', state)
            return current
        receipt = state.get('receipts', {}).get(player, {})
        if receipt.get('id') == request_id and receipt.get('op') == op:
            result = reply(receipt['code'], state)
            return current
        if op == 'ack':
            if state['status'] != 'finished':
                result = reply('409_NO_TERMINADA', state)
                return current
            state.setdefault('acks', {})[player] = True
            result = reply('200_CLEANED', state)
            if all(state['acks'].get(p) for p in state['players']):
                # Firebase rejects transaction(None); an empty object removes the node.
                return {}
            return state
        if state['status'] == 'finished':
            result = reply('410_PARTIDA_TERMINADA', state)
            return current
        if op in ('finish', 'resign'):
            state.update(status='finished', reason='rendicion', result='0-1' if player == 'white' else '1-0')
        elif op == 'draw':
            if state.get('drawOffer') and state['drawOffer'] != player:
                state.update(status='finished', reason='tablas acordadas', result='1/2-1/2')
            else:
                state['drawOffer'] = player
        elif op == 'move':
            if state['status'] != 'ready':
                result = reply('409_ESPERANDO_RIVAL', state)
                return current
            if int(command['version']) != state['version']:
                result = reply('409_CONFLICTO_VERSION', state)
                return current
            if state['turn'] != player:
                result = reply('409_TURNO', state)
                return current
            board = chess.Board(state.get('initialFen', chess.STARTING_FEN))
            for item in sorted(state.get('moves', {}).values(), key=lambda m: m['version']):
                board.push_uci(item['uci'])
            origin, destination = int(command['origin']), int(command['destination'])
            if not (0 <= origin < 64 and 0 <= destination < 64):
                result = reply('400_MOVIMIENTO', state)
                return current
            promotion = None
            piece = board.piece_at(origin)
            if piece and piece.piece_type == chess.PAWN and chess.square_rank(destination) in (0, 7):
                promotion = {'Q': chess.QUEEN, 'R': chess.ROOK, 'B': chess.BISHOP, 'N': chess.KNIGHT}.get(str(command.get('promotion', 'Q')).upper())
                if promotion is None:
                    result = reply('400_PROMOCION', state)
                    return current
            move = chess.Move(origin, destination, promotion=promotion)
            if move not in board.legal_moves:
                result = reply('400_MOVIMIENTO_ILEGAL', state)
                return current
            board.push(move)
            version = state['version'] + 1
            state['version'] = version
            state['fen'] = board.fen(en_passant='fen')
            state['turn'] = 'white' if board.turn else 'black'
            state['board'] = [board.piece_at(i).symbol() if board.piece_at(i) else '.' for i in range(64)]
            state.setdefault('moves', {})[f'v{version:06}'] = dict(uci=move.uci(), version=version, player=player)
            state.pop('drawOffer', None)
            outcome = board.outcome()
            if outcome:
                state.update(status='finished', result=outcome.result(), reason=outcome.termination.name.lower())
        else:
            result = reply('400_OPERACION')
            return current
        state['updatedAt'] = time.time()
        state.setdefault('receipts', {})[player] = dict(id=request_id, op=op, code='200_OK')
        result = reply('200_OK', state)
        return state

    if op == 'get':
        transact(ref.get())
    else:
        ref.transaction(transact)
    result['id'] = int(command.get('id', 0))
    return result

def snapshot(response):
    state = response.get('state', {})
    fen = chess.Board(state.get('fen', chess.STARTING_FEN))
    rights = sum(bit for bit, color, king in [(1, True, True), (2, True, False), (4, False, True), (8, False, False)]
                 if (fen.has_kingside_castling_rights(color) if king else fen.has_queenside_castling_rights(color)))
    status = {'waiting': 0, 'ready': 1, 'finished': 2}.get(state.get('status'), 3)
    message = response.get('error') or response['code']
    if status == 2:
        message = 'Partida terminada: ' + state.get('result', '') + ' ' + state.get('reason', '')
    elif state.get('drawOffer'):
        message = 'Oferta de tablas de ' + state['drawOffer'] + '. Escribe tablas para aceptar.'
    return SNAPSHOT.pack(MAGIC, int(response.get('id', 0)), int(response['ok']), status,
                         state.get('version', 0), int(state.get('turn') == 'black'), rights,
                         (fen.ep_square + 1) if fen.ep_square is not None else 0,
                         ''.join(state.get('board', initial_board())).encode('ascii'),
                         state.get('session', '').encode('ascii'), message.encode('ascii', errors='replace')[:126])

def atomic_write(path, data):
    temporary = path.with_name(path.name + '.tmp')
    temporary.write_bytes(data)
    deadline = time.monotonic() + 5
    while True:
        try:
            temporary.replace(path)
            return
        except PermissionError:
            if time.monotonic() >= deadline:
                raise
            time.sleep(.025)

def write_response(response, ipc):
    atomic_write(ipc / 'sync_response.txt', json.dumps(response, ensure_ascii=True).encode())
    atomic_write(ipc / 'sync_state.txt', (response['code'] + '\n' + json.dumps(response.get('state', {}))).encode())
    # The binary snapshot is the commit marker, published last.
    atomic_write(ipc / 'sync_state.bin', snapshot(response))

def watch(ipc, interval=.1, launcher_id=None):
    import msvcrt
    ipc.mkdir(parents=True, exist_ok=True)
    lock = (ipc / 'middleware.lock').open('a+b')
    lock.seek(0)
    if lock.read(1) == b'':
        lock.write(b'0'); lock.flush()
    lock.seek(0)
    try:
        msvcrt.locking(lock.fileno(), msvcrt.LK_NBLCK, 1)
    except OSError:
        raise RuntimeError('Ya hay un middleware activo en esta carpeta')
    identity = ipc / 'sync_client.id'
    if not identity.exists():
        identity.write_text(uuid.uuid4().hex)
    client = identity.read_text().strip()
    # A restarted watcher must not replay a request from a previous executable.
    for name in ('sync_request.txt', 'sync_state.bin', 'sync_response.txt', 'sync_state.txt'):
        try:
            (ipc / name).unlink(missing_ok=True)
        except PermissionError:
            raise RuntimeError('Cierra el juego antes de reiniciar el middleware')
    ready = {'pid': os.getpid(), 'protocol': 2}
    # A Windows venv can run the interpreter in a child of the process we launched.
    if launcher_id is not None:
        ready['launcher_id'] = launcher_id
    atomic_write(ipc / 'middleware_ready.json', json.dumps(ready).encode())
    print(f'Middleware v2 activo. Esperando solicitudes en {ipc}', flush=True)
    last_raw = None
    last_response = None
    last_visible_state = None
    try:
        while True:
            try:
                raw = (ipc / 'sync_request.txt').read_bytes()
            except (FileNotFoundError, PermissionError):
                time.sleep(interval); continue
            if raw and raw != last_raw:
                command = {}
                try:
                    command = json.loads(raw.decode('utf-8-sig'))
                    if not isinstance(command, dict):
                        command = {}
                        raise ValueError('La solicitud debe ser un objeto JSON')
                    if not isinstance(command.get('id'), int):
                        raise ValueError('Cliente antiguo: usa el ejecutable actualizado (protocolo v2)')
                    command['client'] = client
                    command['room'] = os.environ.get('ARCHESS_ROOM', command.get('room', DEFAULT_ROOM))
                    response = dispatch(command)
                except Exception as exc:
                    response = dict(ok=False, code='500_ERROR', error=str(exc), id=command.get('id', 0))
                # Cache after dispatch, before publish: a local sharing violation must not replay a move.
                last_raw, last_response = raw, response
                state = response.get('state', {})
                visible = (response['code'], state.get('version'), state.get('status'), state.get('drawOffer'))
                if command.get('op') != 'get' or visible != last_visible_state:
                    print(f">> {command.get('op', '?')} sala={command.get('room', DEFAULT_ROOM)} id={response['id']} -> {response['code']}", flush=True)
                last_visible_state = visible
            if last_response is not None:
                try:
                    write_response(last_response, ipc)
                    last_response = None
                except PermissionError:
                    pass
            time.sleep(interval)
    finally:
        (ipc / 'middleware_ready.json').unlink(missing_ok=True)
        lock.close()

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--watch', action='store_true')
    parser.add_argument('--request')
    parser.add_argument('--ipc-dir', type=Path, default=ROOT)
    parser.add_argument('--poll-seconds', type=float, default=.1)
    parser.add_argument('--launcher-id', help='Identifies this watcher startup to its launcher')
    args = parser.parse_args()
    try:
        initialize()
        if args.watch:
            watch(args.ipc_dir.resolve(), args.poll_seconds, launcher_id=args.launcher_id)
        else:
            print(json.dumps(dispatch(json.loads(args.request))))
        return 0
    except KeyboardInterrupt:
        return 0
    except Exception as exc:
        print('ERROR:', str(exc), flush=True)
        return 1

if __name__ == '__main__':
    sys.exit(main())
