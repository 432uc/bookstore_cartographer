import 'package:flutter/material.dart';

void main() {
  runApp(const AppMakerProject());
}

class AppMakerProject extends StatelessWidget {
  const AppMakerProject({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Bookstore Cartographer',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
        useMaterial3: true,
      ),
      home: const MainNavigationPage(),
    );
  }
}

class MainNavigationPage extends StatefulWidget {
  const MainNavigationPage({super.key});

  @override
  State<MainNavigationPage> createState() => _MainNavigationPageState();
}

class _MainNavigationPageState extends State<MainNavigationPage> {
  int _selectedIndex = 0;

  // 画面リスト：0番目を「BookstoreHomePage」に差し替え
  final List<Widget> _pages = [
    const BookstoreHomePage(), // ホーム（本屋リスト）
    const Center(child: Text('計測：PDRマッピング（核心機能）')), 
    const Center(child: Text('書籍リスト：出会った本')), 
    const Center(child: Text('設定：スプレッドシート連携')), 
  ];

  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('App Maker - 本屋アプリ'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: _pages[_selectedIndex],
      bottomNavigationBar: BottomNavigationBar(
        type: BottomNavigationBarType.fixed,
        currentIndex: _selectedIndex,
        onTap: _onItemTapped,
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.home), label: 'ホーム'),
          BottomNavigationBarItem(icon: Icon(Icons.map), label: '計測'),
          BottomNavigationBarItem(icon: Icon(Icons.book), label: '書籍'),
          BottomNavigationBarItem(icon: Icon(Icons.settings), label: '設定'),
        ],
      ),
    );
  }
}

// --- ここからが新しく追加する「入力フォーム付き」のホーム画面 ---

class BookstoreHomePage extends StatefulWidget {
  const BookstoreHomePage({super.key});

  @override
  State<BookstoreHomePage> createState() => _BookstoreHomePageState();
}

class _BookstoreHomePageState extends State<BookstoreHomePage> {
  bool _hasToilet = false;
  bool _hasCafe = false;

  void _showRegistrationDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            title: const Text('新しい本屋を登録'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const TextField(decoration: InputDecoration(labelText: '店名')),
                CheckboxListTile(
                  title: const Text('トイレ'),
                  value: _hasToilet,
                  // トイレのチェックボックス部分
                  onChanged: (bool? value) {
                    // 1. ダイアログ内の見た目を即座に変える
                    setDialogState(() => _hasToilet = value!); 
                    // 2. クラス全体の変数（保存される値）を書き換える
                    setState(() => _hasToilet = value!); 
                  },                ),
                CheckboxListTile(
                  title: const Text('カフェ'),
                  value: _hasCafe,
                  onChanged: (bool? value) {
                    setDialogState(() => _hasCafe = value!);
                    setState(() => _hasCafe = value!);
                  },
                ),
              ],
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context), child: const Text('キャンセル')),
              ElevatedButton(onPressed: () => Navigator.pop(context), child: const Text('保存')),
            ],
          );
        }
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: const Center(child: Text('＋ボタンから登録してください')),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showRegistrationDialog(context),
        child: const Icon(Icons.add),
      ),
    );
  }
}