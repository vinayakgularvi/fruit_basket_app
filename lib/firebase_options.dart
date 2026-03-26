// Fill these values from Firebase Console → Project settings → Your apps.
// Or run: dart pub global activate flutterfire_cli && flutterfire configure
//
// NEVER put service account JSON (safety-tag-storageAccountKey.json) in the app.
// That file is for servers only; use this client config for Flutter.
//
// ignore_for_file: lines_longer_than_80_chars

import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

/// Firestore database ID (Firebase Console → Firestore → pick your database).
/// The built-in **default** database is always named `(default)` — not your project ID.
/// Override only if you create an additional named database:
/// `--dart-define=FIRESTORE_DATABASE_ID=my-other-db`
const String kFirestoreDatabaseId = String.fromEnvironment(
  'FIRESTORE_DATABASE_ID',
  defaultValue: '(default)',
);

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      return web;
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.macOS:
        return macos;
      case TargetPlatform.windows:
      case TargetPlatform.linux:
        return web;
      default:
        throw UnsupportedError(
          'Add FirebaseOptions for this platform or run flutterfire configure.',
        );
    }
  }

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyCzvsxBoe7-BCvrwuH-3tj2JyVFwl5tCj4',
    appId: '1:848758944392:web:c4b9d675574a75eecfe53d',
    messagingSenderId: '848758944392',
    projectId: 'fruit-basket-ab8fd',
    authDomain: 'fruit-basket-ab8fd.firebaseapp.com',
    storageBucket: 'fruit-basket-ab8fd.firebasestorage.app',
    measurementId: 'G-97K7GL83QV',
  );

  /// macOS — add a macOS app in Firebase Console and run flutterfire configure,
  /// or paste the same project's macOS apiKey/appId here (still placeholder).
  static const FirebaseOptions macos = FirebaseOptions(
    apiKey: 'REPLACE_ME',
    appId: 'REPLACE_ME',
    messagingSenderId: '299521818533',
    projectId: 'fruit-basket-d3ffa',
    storageBucket: 'fruit-basket-d3ffa.appspot.com',
    iosBundleId: 'com.example.fruitBasketApp',
  );
}

/// True while firebase_options still has placeholders (skips broken Firebase.init).
bool get firebaseOptionsArePlaceholder {
  return DefaultFirebaseOptions.web.apiKey == 'REPLACE_ME' ||
      DefaultFirebaseOptions.web.appId == 'REPLACE_ME';
}