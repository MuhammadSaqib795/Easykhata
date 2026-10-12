import 'package:flutter/material.dart';
import 'package:fluttertoast/fluttertoast.dart';

enum ToastTone { success, error, info }

class Toastmessage {
  void showmessage(String message, {ToastTone tone = ToastTone.info}) {
    final Color backgroundColor;

    switch (tone) {
      case ToastTone.success:
        backgroundColor = const Color(0xFF166534);
        break;
      case ToastTone.error:
        backgroundColor = const Color(0xFFB91C1C);
        break;
      case ToastTone.info:
        backgroundColor = const Color(0xFF1F2937);
        break;
    }

    Fluttertoast.showToast(
      msg: message,
      toastLength: Toast.LENGTH_SHORT,
      gravity: ToastGravity.BOTTOM,
      timeInSecForIosWeb: 1,
      backgroundColor: backgroundColor,
      textColor: Colors.white,
      fontSize: 16.0,
    );
  }
}
