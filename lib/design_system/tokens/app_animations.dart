import 'package:flutter/material.dart';

class AppAnimations {
  static const Duration microDuration = Duration(milliseconds: 150);
  static const Duration fastDuration = Duration(milliseconds: 200);
  static const Duration normalDuration = Duration(milliseconds: 300);
  static const Duration slowDuration = Duration(milliseconds: 450);

  static const Curve defaultCurve = Curves.easeOutCubic;
  static const Curve entryCurve = Curves.easeOut;
  static const Curve exitCurve = Curves.easeIn;
  static const Curve springCurve = Curves.elasticOut;
}
