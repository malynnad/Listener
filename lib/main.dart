import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';

import 'app.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // 必须在创建 Player 之前初始化，否则原生 mpv 句柄为空。
  MediaKit.ensureInitialized();
  runApp(const ListenerApp());
}
