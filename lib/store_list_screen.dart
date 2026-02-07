import 'package:flutter/material.dart';
import 'package:bookstore_cartographer/l10n/app_localizations.dart';
import 'database_helper.dart';
import 'models/bookstore.dart';

class StoreListScreen extends StatefulWidget {
  @override
  _StoreListScreenState createState() => _StoreListScreenState();
}

class _StoreListScreenState extends State<StoreListScreen> {
  bool _hasToilet = false;
  bool _hasCafe = false;
  late Future<List<Bookstore>> _storesFuture;

  @override
  void initState() {
    super.initState();
    _refreshList();
  }

  void _refreshList() {
    setState(() {
      _storesFuture = DatabaseHelper.instance.queryAllStores();
    });
  }

  void _showRegistrationDialog(BuildContext context) {
    _hasToilet = false;
    _hasCafe = false;
    String inputName = '';

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            title: Text(AppLocalizations.of(context)!.bookstoreName),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  decoration: InputDecoration(labelText: AppLocalizations.of(context)!.bookstoreName),
                  onChanged: (value) => inputName = value,
                ),
                CheckboxListTile(
                  title: Text(AppLocalizations.of(context)!.hasToilet),
                  value: _hasToilet,
                  onChanged: (bool? value) {
                    setDialogState(() => _hasToilet = value!);
                  },
                ),
                CheckboxListTile(
                  title: Text(AppLocalizations.of(context)!.hasCafe),
                  value: _hasCafe,
                  onChanged: (bool? value) {
                    setDialogState(() => _hasCafe = value!);
                  },
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () async {
                  if (inputName.isEmpty) return;
                  final newBookstore = Bookstore(
                    name: inputName,
                    station: '',
                    registers: 0,
                    hasToilet: _hasToilet,
                    hasCafe: _hasCafe,
                  );
                  await DatabaseHelper.instance.insertStore(newBookstore);
                  if (!context.mounted) return;
                  Navigator.pop(context);
                  _refreshList();
                },
                child: Text('Save'),
              ),
            ],
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(AppLocalizations.of(context)!.bookstoreName)),
      body: FutureBuilder<List<Bookstore>>(
        future: _storesFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          }
          if (!snapshot.hasData || snapshot.data!.isEmpty) {
            return const Center(child: Text('No bookstores registered.'));
          }

          final stores = snapshot.data!;

          return ListView.builder(
            itemCount: stores.length,
            itemBuilder: (context, index) {
              final store = stores[index];
              return ListTile(
                leading: Icon(Icons.book),
                title: Text(store.name),
                subtitle: Text(store.station),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (store.hasToilet) Icon(Icons.wc, size: 20, color: Colors.blue),
                    if (store.hasCafe) Icon(Icons.coffee, size: 20, color: Colors.brown),
                  ],
                ),
                onTap: () async {
                  await Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => BookstoreDetailPage(bookstore: store),
                    ),
                  );
                  _refreshList();
                },
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showRegistrationDialog(context),
        child: const Icon(Icons.add),
      ),
    );
  }
}

class BookstoreDetailPage extends StatefulWidget {
  final Bookstore bookstore;

  const BookstoreDetailPage({super.key, required this.bookstore});

  @override
  _BookstoreDetailPageState createState() => _BookstoreDetailPageState();
}

class _BookstoreDetailPageState extends State<BookstoreDetailPage> {
  late TextEditingController _nameController;
  late TextEditingController _stationController;
  late TextEditingController _registersController;
  late bool _hasToilet;
  late bool _hasCafe;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.bookstore.name);
    _stationController = TextEditingController(text: widget.bookstore.station);
    _registersController = TextEditingController(text: widget.bookstore.registers.toString());
    _hasToilet = widget.bookstore.hasToilet;
    _hasCafe = widget.bookstore.hasCafe;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.bookstore.name),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            TextField(
              controller: _nameController,
              decoration: InputDecoration(labelText: AppLocalizations.of(context)!.bookstoreName),
            ),
            TextField(
              controller: _stationController,
              decoration: InputDecoration(labelText: AppLocalizations.of(context)!.station),
            ),
            TextField(
              controller: _registersController,
              decoration: InputDecoration(labelText: AppLocalizations.of(context)!.registers),
              keyboardType: TextInputType.number,
            ),
            CheckboxListTile(
              title: Text(AppLocalizations.of(context)!.hasToilet),
              value: _hasToilet,
              onChanged: (value) {
                setState(() {
                  _hasToilet = value!;
                });
              },
            ),
            CheckboxListTile(
              title: Text(AppLocalizations.of(context)!.hasCafe),
              value: _hasCafe,
              onChanged: (value) {
                setState(() {
                  _hasCafe = value!;
                });
              },
            ),
            ElevatedButton(
              onPressed: () async {
                final updatedBookstore = Bookstore(
                  id: widget.bookstore.id,
                  name: _nameController.text,
                  station: _stationController.text,
                  registers: int.parse(_registersController.text),
                  hasToilet: _hasToilet,
                  hasCafe: _hasCafe,
                );
                await DatabaseHelper.instance.updateStore(updatedBookstore);
                Navigator.pop(context);
              },
              child: Text('Update'),
            ),
          ],
        ),
      ),
    );
  }
}
