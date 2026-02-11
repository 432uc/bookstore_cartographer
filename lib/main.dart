import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi_web/sqflite_ffi_web.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:bookstore_cartographer/l10n/app_localizations.dart';
import 'package:bookstore_cartographer/map_screen.dart';
import 'package:bookstore_cartographer/camera_screen.dart';
import 'package:camera/camera.dart';
import 'store_list_screen.dart';

Future<void> main() async {
  // main() 関数を非同期にし、カメラの初期化を待つ
  WidgetsFlutterBinding.ensureInitialized();

  // 利用可能なカメラのリストを取得
  final cameras = await availableCameras();

  if (kIsWeb) {
    databaseFactory = databaseFactoryFfiWeb;
  }
  runApp(AppMakerProject(cameras: cameras));
}

class AppMakerProject extends StatelessWidget {
  final List<CameraDescription> cameras;
  const AppMakerProject({super.key, required this.cameras});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Bookstore Cartographer',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
        useMaterial3: true,
      ),
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [
        Locale('en', ''),
        Locale('ja', ''),
      ],
      home: MainNavigationPage(cameras: cameras),
    );
  }
}

class MainNavigationPage extends StatefulWidget {
  final List<CameraDescription> cameras;
  const MainNavigationPage({super.key, required this.cameras});

  @override
  State<MainNavigationPage> createState() => _MainNavigationPageState();
}

class _MainNavigationPageState extends State<MainNavigationPage> {
  int _selectedIndex = 0;
  final GlobalKey<MapScreenState> _mapScreenKey = GlobalKey<MapScreenState>();

  late List<Widget> _pages;

  @override
  void initState() {
    super.initState();
    _pages = [
      StoreListScreen(),
      MapScreen(key: _mapScreenKey),
      const Center(child: Text('書籍リスト：出会った本')),
      const Center(child: Text('設定：スプレッドシート連携')),
    ];
  }

  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Bookstore Cartographer'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: _pages[_selectedIndex],
      bottomNavigationBar: BottomNavigationBar(
        type: BottomNavigationBarType.fixed,
        currentIndex: _selectedIndex,
        onTap: _onItemTapped,
        items: [
          BottomNavigationBarItem(icon: Icon(Icons.home), label: AppLocalizations.of(context)!.bookstoreName),
          BottomNavigationBarItem(icon: Icon(Icons.map), label: AppLocalizations.of(context)!.map),
          BottomNavigationBarItem(icon: Icon(Icons.book), label: '書籍'),
          BottomNavigationBarItem(icon: Icon(Icons.settings), label: '設定'),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () async {
          final result = await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => CameraScreen(cameras: widget.cameras),
            ),
          );
          if (result == true) {
            // 写真を撮って登録されたら、地図のピンを再読み込み
            _mapScreenKey.currentState?.loadBookstores();
            // ホーム画面（リスト）の更新が必要な場合は、そこも同様に
          }
        },
        child: const Icon(Icons.camera_alt),
      ),
    );
  }
}
