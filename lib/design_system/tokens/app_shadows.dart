import 'package:flutter/material.dart';

class AppShadows {
  static const List<BoxShadow> none = [];

  static const List<BoxShadow> subtle = [
    BoxShadow(color: Color(0x14000000), blurRadius: 2, offset: Offset(0, 1)),
  ];

  static const List<BoxShadow> subtleDark = [
    BoxShadow(color: Color(0x08000000), blurRadius: 2, offset: Offset(0, 1)),
  ];

  static const List<BoxShadow> card = [
    BoxShadow(
      color: Color(0x1A000000),
      blurRadius: 8,
      spreadRadius: 1,
      offset: Offset(0, 2),
    ),
  ];

  static const List<BoxShadow> cardDark = [
    BoxShadow(
      color: Color(0x14000000),
      blurRadius: 8,
      spreadRadius: 1,
      offset: Offset(0, 2),
    ),
  ];

  static const List<BoxShadow> elevated = [
    BoxShadow(
      color: Color(0x26000000),
      blurRadius: 16,
      spreadRadius: 4,
      offset: Offset(0, 8),
    ),
  ];

  static const List<BoxShadow> elevatedDark = [
    BoxShadow(
      color: Color(0x1F000000),
      blurRadius: 16,
      spreadRadius: 4,
      offset: Offset(0, 8),
    ),
  ];

  static const List<BoxShadow> mapControl = [
    BoxShadow(color: Color(0x262563EB), blurRadius: 12, offset: Offset(0, 4)),
  ];

  static const List<BoxShadow> mapControlDark = [
    BoxShadow(color: Color(0x1F1B6FEB), blurRadius: 12, offset: Offset(0, 4)),
  ];
}
