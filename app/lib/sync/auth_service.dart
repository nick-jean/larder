import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

/// Firebase Auth when configured (google-services.json / GoogleService-Info.plist present);
/// otherwise the app runs in local-only guest mode.
class AuthService extends ChangeNotifier {
  bool _available = false;
  User? _user;

  bool get available => _available;
  bool get signedIn => _user != null;
  String? get uid => _user?.uid;
  String? get email => _user?.email;

  Future<void> init() async {
    try {
      await Firebase.initializeApp();
      _available = true;
      _user = FirebaseAuth.instance.currentUser;
      FirebaseAuth.instance.authStateChanges().listen((u) {
        _user = u;
        notifyListeners();
      });
    } catch (e) {
      debugPrint('Firebase not configured, guest mode only: $e');
      _available = false;
    }
  }

  Future<String?> idToken() async => _user?.getIdToken();

  Future<void> signInWithEmail(String email, String password, {bool create = false}) async {
    final auth = FirebaseAuth.instance;
    if (create) {
      await auth.createUserWithEmailAndPassword(email: email, password: password);
    } else {
      await auth.signInWithEmailAndPassword(email: email, password: password);
    }
  }

  Future<void> signOut() => FirebaseAuth.instance.signOut();
}
