import importlib.util
import json
from pathlib import Path
import tempfile
import unittest
import zipfile

spec = importlib.util.spec_from_file_location('import_world', Path(__file__).parents[1] / 'scripts/import-world.py')
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class ArchiveSafety(unittest.TestCase):
    def run_archive(self, entries):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            archive = root / 'world.zip'
            with zipfile.ZipFile(archive, 'w') as output:
                for name, data in entries:
                    output.writestr(name, data)
            stage = root / 'stage'
            stage.mkdir()
            module.extract_world(archive, stage)
            return sorted(str(p.relative_to(stage)) for p in stage.rglob('*') if p.is_file())

    def valid(self):
        return [('universe/worlds/default/config.json', json.dumps({'Seed': 1})),
                ('universe/worlds/default/chunks/0.0.region.bin', b'fixture')]

    def test_only_world_is_imported(self):
        files = self.run_archive(self.valid() + [('config.json', '{"Password":"private"}'), ('mods/plugin.jar', b'no')])
        self.assertEqual(len(files), 2)
        self.assertTrue(all(name.startswith('universe/') for name in files))

    def test_traversal_rejected(self):
        for path in ['../escape', '/tmp/escape', 'universe/../../escape', 'universe\\escape', 'C:/escape']:
            with self.subTest(path=path), self.assertRaises(ValueError):
                self.run_archive(self.valid() + [(path, b'no')])

    def test_symlink_rejected(self):
        info = zipfile.ZipInfo('universe/link')
        info.create_system = 3
        info.external_attr = 0o120777 << 16
        with self.assertRaises(ValueError):
            self.run_archive(self.valid() + [(info, '/etc/passwd')])

    def test_empty_world_rejected(self):
        with self.assertRaises((ValueError, FileNotFoundError)):
            self.run_archive([('universe/worlds/default/config.json', '{}')])


if __name__ == '__main__':
    unittest.main()
