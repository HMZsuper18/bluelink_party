import 'dart:ui';

class VirtualDeviceProfile {
  const VirtualDeviceProfile({
    required this.key,
    required this.label,
    required this.width,
    required this.height,
    this.note = '',
  });

  final String key;
  final String label;
  final int width;
  final int height;
  final String note;

  double get aspect => width / height;

  Size get size => Size(width.toDouble(), height.toDouble());

  static const VirtualDeviceProfile phonePortrait = VirtualDeviceProfile(
    key: 'phone-p',
    label: 'Phone Portrait',
    width: 360,
    height: 640,
    note: '9:16 narrow; controls fall back below play area',
  );

  static const VirtualDeviceProfile phoneLandscape = VirtualDeviceProfile(
    key: 'phone-l',
    label: 'Phone Landscape',
    width: 640,
    height: 360,
    note: '16:9 compact landscape',
  );

  static const VirtualDeviceProfile tabletPortrait = VirtualDeviceProfile(
    key: 'tablet-p',
    label: 'Tablet Portrait',
    width: 768,
    height: 1024,
    note: '3:4 portrait',
  );

  static const VirtualDeviceProfile tabletLandscape = VirtualDeviceProfile(
    key: 'tablet-l',
    label: 'Tablet Landscape',
    width: 1280,
    height: 800,
    note: '16:10 landscape',
  );

  static const VirtualDeviceProfile desktopHd = VirtualDeviceProfile(
    key: 'desktop',
    label: 'Desktop HD',
    width: 1920,
    height: 1080,
    note: '16:9 reference desktop',
  );

  static const VirtualDeviceProfile ultraWide = VirtualDeviceProfile(
    key: 'ultrawide',
    label: 'Ultra-Wide',
    width: 2560,
    height: 1080,
    note: '21:9 wide control strips',
  );

  static const List<VirtualDeviceProfile> defaults = [
    phoneLandscape,
    tabletLandscape,
    desktopHd,
    ultraWide,
  ];

  static VirtualDeviceProfile fromKey(String key) {
    const all = [
      phonePortrait,
      phoneLandscape,
      tabletPortrait,
      tabletLandscape,
      desktopHd,
      ultraWide,
    ];
    return all.firstWhere((p) => p.key == key, orElse: () => desktopHd);
  }
}
