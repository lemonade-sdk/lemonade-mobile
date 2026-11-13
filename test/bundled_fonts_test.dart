// The app's fonts are bundled, so google_fonts never fetches them from
// fonts.gstatic.com (main.dart turns runtime fetching off). google_fonts
// looks up a bundled variant by "<Family>-<Variant>.ttf" in the asset
// manifest; every variant the app requests must be there.

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Inter Tight: the text theme (Material weights 400 and 500) and the
  // headings; IBM Plex Mono: nexusMono() with the weights its callers use.
  const required = [
    'InterTight-Regular',
    'InterTight-Medium',
    'InterTight-SemiBold',
    'InterTight-Bold',
    'IBMPlexMono-Regular',
    'IBMPlexMono-Medium',
    'IBMPlexMono-SemiBold',
    'IBMPlexMono-Bold',
  ];

  test('every font variant the app uses is bundled', () async {
    final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
    final assets = manifest.listAssets().toSet();
    for (final name in required) {
      final path = 'assets/google_fonts/$name.ttf';
      expect(assets, contains(path));
      final data = await rootBundle.load(path);
      // A TrueType font starts with the 0x00010000 sfnt version.
      expect(data.lengthInBytes, greaterThan(10000), reason: path);
      expect(data.getUint32(0), 0x00010000, reason: path);
    }
  });

  test('the font licenses ship with the fonts', () async {
    for (final family in ['InterTight', 'IBMPlexMono']) {
      final text = await rootBundle.loadString('assets/google_fonts/OFL-$family.txt');
      expect(text, contains('SIL Open Font License'));
    }
  });
}
