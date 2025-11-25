import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class ScanHistoryService {
  // Ensure we always have a user (anonymous if needed)
  static Future<User> _ensureUser() async {
    final auth = FirebaseAuth.instance;
    User? user = auth.currentUser;

    if (user != null) return user;

    // If not signed in, sign in anonymously
    final cred = await auth.signInAnonymously();
    return cred.user!;
  }

  static Future<void> save({
    required String species,
    required String freshness,
    required String frontImagePath,
    String? backImagePath,
    String? modelName,
    Map<String, dynamic>? summary, // summary map from pipeline
  }) async {
    final user = await _ensureUser(); // ✅ guarantees a user

    // Extract top confidence (if present)
    double? confidence;
    if (summary != null && summary['confidence'] is num) {
      confidence = (summary['confidence'] as num).toDouble();
    }

    final Map<String, dynamic> data = {
      'uid': user.uid,
      'species': species,
      'freshness': freshness,
      'frontImagePath': frontImagePath,
      'backImagePath': backImagePath ?? frontImagePath,
      'modelName': modelName ?? '',
      'timestamp': FieldValue.serverTimestamp(),
      if (summary != null) 'summary': summary,
      if (confidence != null) 'confidence': confidence,
    };

    await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('scanHistory')
        .add(data);
  }
}
