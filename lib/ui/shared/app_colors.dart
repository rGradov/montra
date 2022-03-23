import 'package:flutter/material.dart';

abstract class AppColor {
  /// violet
  static const MaterialColor violet =
  MaterialColor(_primary, <int, Color>{
    20:Color(0xFFEEE5FF),
    40:Color(0xFFD3BDFF),
    60:Color(0xFFB18AFF),
    80:Color(0xFF8F57FF),
    100:Color(0xFF7F3DFF),
  });
  /// Light
  static const MaterialColor baseLight = MaterialColor(_base, <int,Color>{
    20:Color(0xFF91919F),
    40:Color(0xFFF2F4F5),
    60:Color(0xFFF1F1FA),
    80:Color(0xFFFBFBFB),
    100:Color(0xFFFFFFFF),
  });
  /// dark
  static const MaterialColor baseDark = MaterialColor(_baseDark, <int,Color>{
    25:Color(0xFF7A7E80),
    50:Color(0xFF464A4D),
    75:Color(0xFF161719),
    100:Color(0xFF0D0E0F),
  });
  /// red
  static const MaterialColor baseRed = MaterialColor(_baseDark, <int,Color>{
    20:Color(0xFF7A7E80),
    40:Color(0xFF7A7E80),
    60:Color(0xFF464A4D),
    80:Color(0xFFFD5662),
    100:Color(0xFFFD3C4A),
  });
  static const int _base = 0xFF00000;
  static const int _baseDark =0xFF0D0E0F;
  static const int _primary = 0xFF05A5FF;
  static const Color green = Color(0xFF00A86B);

}