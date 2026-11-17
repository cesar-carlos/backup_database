import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / 'scripts'))
import sync_appcast_from_releases as appcast


class AppcastNewlinesTest(unittest.TestCase):
    def test_release_notes_are_normalized_without_changing_asset_metadata(self):
        asset = appcast.ReleaseAsset('installer.exe', 'https://example.com/installer.exe', 123, 'a' * 64)
        release = appcast.PublishedRelease('3.6.13', '2026-11-17T00:00:00Z', 'first\r\nsecond\rthird\nfourth', asset)
        policy = appcast.AppcastPolicy(frozenset(), None, {}, {})
        tree = appcast.render_appcast('owner/repo', [release], policy)
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'appcast.xml'
            appcast.write_appcast(path, tree)
            self.assertNotIn(b'\r', path.read_bytes())
        item = tree.find('channel/item')
        self.assertEqual(item.findtext('description'), 'first\nsecond\nthird\nfourth')
        self.assertEqual(item.find('enclosure').get('sha256'), asset.sha256)
        self.assertEqual(item.find('enclosure').get('length'), '123')


if __name__ == '__main__':
    unittest.main()
