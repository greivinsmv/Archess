"""Exercise the mailbox and game transactions without Firebase or credentials."""

import contextlib
import copy
import importlib.util
import io
import json
from pathlib import Path
import sys
import tempfile
import types
import unittest
from unittest.mock import Mock, patch

import chess


# Only Firebase is replaced. Legal moves still use the real python-chess library.
firebase = types.ModuleType('firebase_admin')
firebase._apps = {}
firebase.initialize_app = Mock()
firebase.credentials = types.SimpleNamespace(Certificate=Mock())
firebase.db = types.SimpleNamespace(reference=Mock())
spec = importlib.util.spec_from_file_location(
    'archess_backend_tests', Path(__file__).resolve().parents[1] / 'firebase_multiplayer.py'
)
backend = importlib.util.module_from_spec(spec)
with patch.dict(sys.modules, {'firebase_admin': firebase}):
    spec.loader.exec_module(backend)


class MemoryReference:
    def __init__(self, store, path):
        self.store = store
        self.path = path

    def get(self):
        return copy.deepcopy(self.store.get(self.path))

    def transaction(self, update):
        value = update(self.get())
        if value:
            self.store[self.path] = copy.deepcopy(value)
        else:
            self.store.pop(self.path, None)
        return copy.deepcopy(value)


class GameTransactionsTest(unittest.TestCase):
    def setUp(self):
        self.store = {}
        self.sequence = 0
        replacement = types.SimpleNamespace(reference=lambda path: MemoryReference(self.store, path))
        self.database = patch.object(backend, 'db', replacement)
        self.database.start()
        self.addCleanup(self.database.stop)

    def send(self, op, player='white', client='white-client', session=None, request_id=None, **fields):
        self.sequence += 1
        command = {
            'room': 'unit-room', 'op': op, 'player': player, 'client': client,
            'id': self.sequence if request_id is None else request_id,
        }
        if session is not None:
            command['session'] = session
        command.update(fields)
        return backend.dispatch(command)

    def start_game(self):
        created = self.send('create')
        self.session = created['state']['session']
        return self.send('join', 'black', 'black-client', self.session)

    def move(self, origin, destination, player='white', version=0, **fields):
        return self.send(
            'move', player, player + '-client', self.session,
            origin=origin, destination=destination, version=version, **fields
        )

    def test_create_and_join(self):
        result = self.start_game()
        self.assertEqual(result['code'], '200_OK')
        self.assertEqual(result['state']['status'], 'ready')
        self.assertEqual(set(result['state']['players']), {'white', 'black'})
        self.assertEqual(len(result['state']['board']), 64)

    def test_creating_again_does_not_reset_a_room(self):
        self.start_game()
        moved = self.move(12, 28)
        own_retry = self.send('create')
        other = self.send('create', client='another-client')
        self.assertEqual(own_retry['state']['session'], self.session)
        self.assertEqual(own_retry['state']['version'], moved['state']['version'])
        self.assertEqual(other['code'], '409_SALA_OCUPADA')

    def test_join_rejects_an_occupied_color(self):
        self.start_game()
        result = self.send('join', 'black', 'another-client', self.session)
        self.assertEqual(result['code'], '409_COLOR_OCUPADO')

    def test_missing_room_returns_not_found(self):
        result = self.send('get')
        self.assertEqual(result['code'], '404_SALA_NO_EXISTE')
        self.assertEqual(self.store, {})

    def test_room_name_cannot_escape_games_path(self):
        for room in ['../other', 'room/name', '', 'x' * 65]:
            with self.subTest(room=room), self.assertRaises(ValueError):
                backend.dispatch({'op': 'get', 'room': room})

    def test_move_requires_an_opponent(self):
        created = self.send('create')
        self.session = created['state']['session']
        result = self.move(12, 28)
        self.assertEqual(result['code'], '409_ESPERANDO_RIVAL')

    def test_legal_move_updates_board_and_version(self):
        self.start_game()
        result = self.move(12, 28)
        self.assertEqual(result['code'], '200_OK')
        self.assertEqual(result['state']['board'][12], '.')
        self.assertEqual(result['state']['board'][28], 'P')
        self.assertEqual(result['state']['version'], 1)
        self.assertEqual(result['state']['turn'], 'black')
        self.assertEqual(result['state']['moves']['v000001']['uci'], 'e2e4')

    def test_illegal_move_and_out_of_range_do_not_change_state(self):
        self.start_game()
        before = copy.deepcopy(self.store)
        self.assertEqual(self.move(12, 36)['code'], '400_MOVIMIENTO_ILEGAL')
        self.assertEqual(self.move(-1, 28)['code'], '400_MOVIMIENTO')
        self.assertEqual(self.store, before)

    def test_rejects_wrong_turn_and_stale_version(self):
        self.start_game()
        self.assertEqual(self.move(52, 36, 'black')['code'], '409_TURNO')
        self.move(12, 28)
        self.assertEqual(self.move(52, 36, 'black', version=0)['code'], '409_CONFLICTO_VERSION')

    def test_rejects_missing_or_old_session(self):
        self.start_game()
        missing = self.send('move', origin=12, destination=28, version=0)
        old = self.send('move', session='old-session', origin=12, destination=28, version=0)
        self.assertEqual(missing['code'], '400_FALTA_SESSION')
        self.assertEqual(old['code'], '409_PARTIDA_ANTERIOR')

    def test_rejects_another_client_using_a_players_color(self):
        self.start_game()
        result = self.send(
            'move', client='another-client', session=self.session,
            origin=12, destination=28, version=0,
        )
        self.assertEqual(result['code'], '403_JUGADOR')

    def test_repeated_request_does_not_apply_a_move_twice(self):
        self.start_game()
        first = self.move(12, 28, request_id=700)
        retry = self.move(12, 28, request_id=700)
        self.assertEqual(retry['code'], '200_OK')
        self.assertEqual(retry['state']['version'], 1)
        self.assertEqual(retry['state']['moves'], first['state']['moves'])

    def test_promotions_are_validated(self):
        self.start_game()
        board = chess.Board('7k/P7/8/8/8/8/8/7K w - - 0 1')
        state = self.store['/games/unit-room']
        state.update(
            initialFen=board.fen(), fen=board.fen(),
            board=[board.piece_at(i).symbol() if board.piece_at(i) else '.' for i in range(64)],
        )
        self.assertEqual(self.move(48, 56, promotion='K')['code'], '400_PROMOCION')
        promoted = self.move(48, 56, promotion='N')
        self.assertEqual(promoted['code'], '200_OK')
        self.assertEqual(promoted['state']['board'][56], 'N')
        self.assertEqual(promoted['state']['moves']['v000001']['uci'], 'a7a8n')

    def test_checkmate_finishes_the_game(self):
        self.start_game()
        for version, (player, origin, destination) in enumerate([
            ('white', 13, 21), ('black', 52, 36), ('white', 14, 30), ('black', 59, 31),
        ]):
            result = self.move(origin, destination, player, version)
            self.assertEqual(result['code'], '200_OK')
        self.assertEqual(result['state']['status'], 'finished')
        self.assertEqual(result['state']['result'], '0-1')
        self.assertEqual(result['state']['reason'], 'checkmate')

    def test_draw_requires_both_players_and_a_move_clears_an_offer(self):
        self.start_game()
        offered = self.send('draw', session=self.session)
        self.assertEqual(offered['state']['status'], 'ready')
        self.assertEqual(offered['state']['drawOffer'], 'white')
        moved = self.move(12, 28)
        self.assertNotIn('drawOffer', moved['state'])
        self.send('draw', 'black', 'black-client', self.session)
        accepted = self.send('draw', session=self.session)
        self.assertEqual(accepted['state']['status'], 'finished')
        self.assertEqual(accepted['state']['result'], '1/2-1/2')

    def test_resignation_and_acknowledgements_clean_the_room(self):
        self.start_game()
        unfinished = self.send('ack', session=self.session)
        self.assertEqual(unfinished['code'], '409_NO_TERMINADA')
        resigned = self.send('resign', session=self.session)
        self.assertEqual(resigned['state']['result'], '0-1')
        self.assertEqual(self.move(12, 28)['code'], '410_PARTIDA_TERMINADA')
        first_ack = self.send('ack', session=self.session)
        self.assertEqual(first_ack['code'], '200_CLEANED')
        self.assertIn('/games/unit-room', self.store)
        self.send('ack', 'black', 'black-client', self.session)
        self.assertNotIn('/games/unit-room', self.store)

    def test_snapshot_layout_matches_the_assembly_mailbox(self):
        self.start_game()
        moved = self.move(12, 28, request_id=900)
        binary = backend.snapshot(moved)
        values = backend.SNAPSHOT.unpack(binary)
        self.assertEqual(len(binary), 256)
        self.assertEqual(values[:8], (backend.MAGIC, 900, 1, 1, 1, 1, 15, 21))
        self.assertEqual(len(values[8]), 64)
        self.assertEqual(values[8][28:29], b'P')
        self.assertEqual(values[9].rstrip(b'\0').decode(), self.session)
        self.assertEqual(values[10].rstrip(b'\0'), b'200_OK')

    def test_response_files_can_be_read_after_publication(self):
        result = self.start_game()
        with tempfile.TemporaryDirectory() as directory:
            ipc = Path(directory)
            backend.write_response(result, ipc)
            self.assertEqual(json.loads((ipc / 'sync_response.txt').read_text()), result)
            self.assertEqual((ipc / 'sync_state.bin').read_bytes(), backend.snapshot(result))
            self.assertTrue((ipc / 'sync_state.txt').read_text().startswith('200_OK\n'))
            self.assertFalse(list(ipc.glob('*.tmp')))


class ConfigurationTest(unittest.TestCase):
    def setUp(self):
        self.apps = patch.object(backend.firebase_admin, '_apps', {})
        self.apps.start()
        self.addCleanup(self.apps.stop)

    def test_missing_connection_settings_fail_without_initializing_sdk(self):
        with (
            patch.object(backend, 'DATABASE_URL', None),
            patch.object(backend.firebase_admin, 'initialize_app') as start,
        ):
            with self.assertRaisesRegex(ValueError, 'ARCHESS_FIREBASE_URL'):
                backend.initialize()
            start.assert_not_called()
        with (
            patch.object(backend, 'DATABASE_URL', 'https://example.firebaseio.com'),
            patch.object(backend, 'CREDENTIALS_PATH', None),
        ):
            with self.assertRaisesRegex(ValueError, 'ARCHESS_FIREBASE_CREDENTIALS'):
                backend.initialize()

    def test_credential_inside_the_project_is_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            credential = root / 'credentials.json'
            credential.write_text('{}')
            with (
                patch.object(backend, 'ROOT', root),
                patch.object(backend, 'DATABASE_URL', 'https://example.firebaseio.com'),
                patch.object(backend, 'CREDENTIALS_PATH', str(credential)),
            ):
                with self.assertRaisesRegex(ValueError, 'fuera'):
                    backend.initialize()

    def test_external_credential_path_is_used_only_when_initializing(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            project = root / 'project'
            project.mkdir()
            credential = root / 'credentials.json'
            credential.write_text('{}')
            with (
                patch.object(backend, 'ROOT', project),
                patch.object(backend, 'DATABASE_URL', 'https://example.firebaseio.com'),
                patch.object(backend, 'CREDENTIALS_PATH', str(credential)),
                patch.object(backend.credentials, 'Certificate', return_value='test-certificate') as certificate,
                patch.object(backend.firebase_admin, 'initialize_app') as start,
            ):
                backend.initialize()
                certificate.assert_called_once_with(str(credential.resolve()))
                start.assert_called_once_with('test-certificate', {'databaseURL': 'https://example.firebaseio.com', 'httpTimeout': 12})

    def test_credential_errors_do_not_print_sdk_details(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            credential = root / 'credentials.json'
            credential.write_text('{}')
            with (
                patch.object(backend, 'ROOT', root / 'project'),
                patch.object(backend, 'DATABASE_URL', 'https://example.firebaseio.com'),
                patch.object(backend, 'CREDENTIALS_PATH', str(credential)),
                patch.object(backend.credentials, 'Certificate', side_effect=ValueError('sensitive-credential-value')),
            ):
                with self.assertRaises(RuntimeError) as caught:
                    backend.initialize()
                self.assertNotIn('sensitive-credential-value', str(caught.exception))

    def test_help_exits_before_loading_credentials(self):
        with (
            patch.object(sys, 'argv', ['firebase_multiplayer.py', '--help']),
            patch.object(backend, 'initialize') as start,
            contextlib.redirect_stdout(io.StringIO()),
        ):
            with self.assertRaises(SystemExit) as caught:
                backend.main()
            self.assertEqual(caught.exception.code, 0)
            start.assert_not_called()


class WatcherStartupTest(unittest.TestCase):
    def capture_ready(self, launcher_id=None):
        captured = {}
        locking = Mock()
        windows_lock = types.SimpleNamespace(LK_NBLCK=1, locking=locking)
        with tempfile.TemporaryDirectory() as directory:
            ipc = Path(directory)
            ready_path = ipc / 'middleware_ready.json'
            ready_path.write_text(json.dumps({'pid': -1, 'protocol': 2, 'launcher_id': 'old-startup'}))

            def stop_after_ready(_interval):
                captured.update(json.loads(ready_path.read_text()))
                raise KeyboardInterrupt

            with (
                patch.dict(sys.modules, {'msvcrt': windows_lock}),
                patch.object(backend.time, 'sleep', side_effect=stop_after_ready),
                patch.object(backend, 'dispatch') as dispatch,
                contextlib.redirect_stdout(io.StringIO()),
            ):
                with self.assertRaises(KeyboardInterrupt):
                    if launcher_id is None:
                        backend.watch(ipc)
                    else:
                        backend.watch(ipc, launcher_id=launcher_id)
                dispatch.assert_not_called()

            self.assertFalse(ready_path.exists())
            self.assertTrue((ipc / 'sync_client.id').read_text().strip())
        locking.assert_called_once()
        return captured

    def test_ready_file_identifies_the_current_launcher_startup(self):
        ready = self.capture_ready('current-launcher-id')
        self.assertEqual(ready['launcher_id'], 'current-launcher-id')
        self.assertEqual(ready['pid'], backend.os.getpid())
        self.assertEqual(ready['protocol'], 2)

    def test_manual_watcher_remains_compatible_without_launcher_id(self):
        ready = self.capture_ready()
        self.assertEqual(ready, {'pid': backend.os.getpid(), 'protocol': 2})

    def test_cli_passes_launcher_id_and_poll_options_without_credentials(self):
        with tempfile.TemporaryDirectory() as directory:
            arguments = [
                'firebase_multiplayer.py', '--watch', '--ipc-dir', directory,
                '--poll-seconds', '0.25', '--launcher-id', 'cli-launcher-id',
            ]
            with (
                patch.object(sys, 'argv', arguments),
                patch.object(backend, 'initialize') as initialize,
                patch.object(backend, 'watch') as watch,
            ):
                self.assertEqual(backend.main(), 0)
            initialize.assert_called_once_with()
            watch.assert_called_once_with(Path(directory).resolve(), 0.25, launcher_id='cli-launcher-id')

    def test_cli_still_supports_manual_watch_without_launcher_id(self):
        with (
            patch.object(sys, 'argv', ['firebase_multiplayer.py', '--watch']),
            patch.object(backend, 'initialize'),
            patch.object(backend, 'watch') as watch,
        ):
            self.assertEqual(backend.main(), 0)
        watch.assert_called_once_with(backend.ROOT.resolve(), 0.1, launcher_id=None)


if __name__ == '__main__':
    unittest.main()
