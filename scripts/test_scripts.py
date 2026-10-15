import unittest
from pathlib import Path
from app_build import BuildVariant
from sync_source import source_files

class TestToolchainScripts(unittest.TestCase):
    def test_build_variant(self):
        variant = BuildVariant(all_sources=False)
        self.assertEqual(variant.slug, 'THLRedLook')
        self.assertEqual(variant.name, '糖葫芦Haw')
        self.assertEqual(variant.arguments, [])

    def test_source_isolation_hongguo_only(self):
        root = Path(__file__).resolve().parents[1]
        sources = source_files(root)
        # 验证仅收录 hongguo.js
        source_js_files = [
            p.as_posix() for p in sources
            if p.parts[:2] == ('assets', 'sources')
        ]
        self.assertEqual(source_js_files, ['assets/sources/hongguo.js'])

if __name__ == '__main__':
    unittest.main()
