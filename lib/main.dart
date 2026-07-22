import 'package:flutter/material.dart';

import 'app.dart';
import 'services/database/database.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AppDatabase.instance.init();
  runApp(const StarHopeApp());
}
