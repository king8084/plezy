import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/services/settings_service.dart';
import 'package:plezy/utils/subtitle_tag_policy.dart';

void main() {
  test('plain-text tracks strip inline sizes; styled tracks keep the viewer policy', () {
    // <font size="71"> on every SRT line made subtitles fill a quarter of the screen.
    expect(subAssOverrideForTrack('subrip', SubAssOverride.no), 'strip');
    expect(subAssOverrideForTrack('SRT', SubAssOverride.yes), 'strip');
    expect(subAssOverrideForTrack('webvtt', SubAssOverride.no), 'strip');
    expect(subAssOverrideForTrack('ass', SubAssOverride.no), 'no');
    expect(subAssOverrideForTrack('ssa', SubAssOverride.scale), 'scale');
    expect(subAssOverrideForTrack('hdmv_pgs_subtitle', SubAssOverride.no), 'no');
    expect(subAssOverrideForTrack(null, SubAssOverride.yes), 'yes');
  });
}
