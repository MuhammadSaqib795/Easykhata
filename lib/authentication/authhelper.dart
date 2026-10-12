// import 'package:firebase_auth/firebase_auth.dart';
// import 'package:flutter/material.dart';

// class AuthService {
//   static final FirebaseAuth _auth = FirebaseAuth.instance;

//   static Future<UserCredential?> authenticate({
//     required String email,
//     required String password,
//     required bool isLogin,
//   }) async {
//     try {
//       if (isLogin) {
//         return await _auth.signInWithEmailAndPassword(
//           email: email.trim(),
//           password: password.trim(),
//         );
//       } else {
//         return await _auth.createUserWithEmailAndPassword(
//           email: email.trim(),
//           password: password.trim(),
//         );
//       }
//     } on FirebaseAuthException catch (e) {
//       // Return null so the UI knows it failed, but catch the error here
//       debugPrint("Auth Error: ${e.message}");
//       rethrow; // Pass the error to the UI to show a Toast
//     }
//   }
// }
