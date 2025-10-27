import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class ScanHistoryService {
  static Future<void> save({
    required String species,
    required String freshness,
    required String frontImagePath,
    String? backImagePath,
    String? modelName,
    Map<String, dynamic>? summary, // ✅ add summary map
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw Exception('Not signed in');

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
