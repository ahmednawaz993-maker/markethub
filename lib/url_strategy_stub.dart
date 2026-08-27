// URL strategy: the non-web half of a conditional import.
//
// Mobile has no URL bar. Android hands deep links straight to Flutter via the
// flutter_deeplinking_enabled meta-data in AndroidManifest.xml, so there is
// nothing to configure here — but the symbol has to exist, because main.dart
// calls it unconditionally.
//
// This file must NOT import package:flutter_web_plugins: that package only
// exists on the web, and importing it here would break the Android build.
void configureUrlStrategy() {}
