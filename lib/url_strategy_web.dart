// URL strategy: the web half of a conditional import.
//
// THE BUG THIS FIXES. Flutter web defaults to the HASH url strategy, where the
// route is read from the fragment (`/#/ad/123`) and the browser PATH is ignored
// entirely. Firebase Hosting rewrites `**` to index.html, so
// https://pakbazar24.com/ad/123 loaded the app and left the address bar
// looking correct — but Flutter saw an empty route and showed the home screen.
//
// Every ad link and every Ludo invite the app itself generates is a path URL.
// So every shared link landed on the login screen instead of the thing that was
// shared, and Google had one indexable URL for the whole marketplace. The
// routing code was right the entire time; it was never being handed the path.
//
// usePathUrlStrategy() makes Flutter read the real path, which is also what the
// Android deep links already send.

import 'package:flutter_web_plugins/url_strategy.dart';

void configureUrlStrategy() => usePathUrlStrategy();
