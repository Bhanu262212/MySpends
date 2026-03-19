import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter_sms_inbox/flutter_sms_inbox.dart';
import 'package:fl_chart/fl_chart.dart';

void main() {
  runApp(const SpendTrackApp());
}

class SpendTrackApp extends StatelessWidget {
  const SpendTrackApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SpendTrack',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: const SpendTrackHomePage(title: 'SpendTrack Insights'),
    );
  }
}

class Transaction {
  final String sender;
  final double amount;
  final String type; // 'credit' or 'debit'
  final DateTime date;

  Transaction({required this.sender, required this.amount, required this.type, required this.date});
}

class SpendTrackHomePage extends StatefulWidget {
  const SpendTrackHomePage({super.key, required this.title});

  final String title;

  @override
  State<SpendTrackHomePage> createState() => _SpendTrackHomePageState();
}

class _SpendTrackHomePageState extends State<SpendTrackHomePage> {
  final SmsQuery _query = SmsQuery();
  List<Transaction> _transactions = [];
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _fetchSmsMessages();
  }

  Future<void> _fetchSmsMessages() async {
    setState(() {
      _isLoading = true;
    });

    var permission = await Permission.sms.status;
    if (permission.isGranted) {
      final messages = await _query.querySms(
        kinds: [SmsQueryKind.inbox],
        count: 500, // Look at the last 500 messages
      );
      _parseMessages(messages);
    } else {
      await Permission.sms.request();
      permission = await Permission.sms.status;
      if (permission.isGranted) {
        final messages = await _query.querySms(
          kinds: [SmsQueryKind.inbox],
          count: 500,
        );
        _parseMessages(messages);
      } else {
         setState(() {
          _isLoading = false;
        });
      }
    }
  }

  void _parseMessages(List<SmsMessage> messages) {
    List<Transaction> parsedTransactions = [];

    // Very basic regex to find amounts like Rs. 500, INR 500.00, Rs.50, INR 50.
    final RegExp amountRegex = RegExp(r'(?:Rs\.?|INR)\s*(\d+(?:\.\d+)?)', caseSensitive: false);

    // Keywords for debit and credit
    final RegExp debitRegex = RegExp(r'\b(debited|spent|paid|deducted)\b', caseSensitive: false);
    final RegExp creditRegex = RegExp(r'\b(credited|received|added|deposited)\b', caseSensitive: false);

    for (var message in messages) {
      if (message.body != null) {
        final body = message.body!;

        final amountMatch = amountRegex.firstMatch(body);
        if (amountMatch != null) {
          final amountStr = amountMatch.group(1);
          if (amountStr != null) {
            final amount = double.tryParse(amountStr);
            if (amount != null) {
               String? type;
               if (debitRegex.hasMatch(body)) {
                 type = 'debit';
               } else if (creditRegex.hasMatch(body)) {
                 type = 'credit';
               }

               if (type != null) {
                 parsedTransactions.add(Transaction(
                   sender: message.sender ?? 'Unknown',
                   amount: amount,
                   type: type,
                   date: message.date ?? DateTime.now(),
                 ));
               }
            }
          }
        }
      }
    }

    setState(() {
      _transactions = parsedTransactions;
      _isLoading = false;
    });
  }

  List<Transaction> get _debits => _transactions.where((t) => t.type == 'debit').toList();

  Map<String, double> get _debitsBySender {
    Map<String, double> debitsMap = {};
    for (var t in _debits) {
      debitsMap[t.sender] = (debitsMap[t.sender] ?? 0) + t.amount;
    }
    return debitsMap;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: Text(widget.title),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _fetchSmsMessages,
          )
        ],
      ),
      body: _isLoading
        ? const Center(child: CircularProgressIndicator())
        : (_transactions.isEmpty
            ? const Center(child: Text('No transaction insights found.'))
            : Column(
                children: [
                  const Padding(
                    padding: EdgeInsets.all(16.0),
                    child: Text(
                      'Debit Breakdown by Sender',
                      style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                    ),
                  ),
                  SizedBox(
                    height: 250,
                    child: _debitsBySender.isEmpty
                      ? const Center(child: Text('No debit transactions found for chart.'))
                      : PieChart(
                          PieChartData(
                            sectionsSpace: 0,
                            centerSpaceRadius: 40,
                            sections: _getPieChartSections(),
                          ),
                        ),
                  ),
                  const Padding(
                    padding: EdgeInsets.all(16.0),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'Recent Debits',
                        style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                  Expanded(
                    child: ListView.builder(
                      itemCount: _debits.length,
                      itemBuilder: (context, index) {
                        final transaction = _debits[index];
                        return ListTile(
                          leading: const CircleAvatar(
                            backgroundColor: Colors.redAccent,
                            child: Icon(Icons.remove, color: Colors.white),
                          ),
                          title: Text(transaction.sender),
                          subtitle: Text('${transaction.date.day}/${transaction.date.month}/${transaction.date.year}'),
                          trailing: Text(
                            'Rs. ${transaction.amount.toStringAsFixed(2)}',
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                          ),
                        );
                      },
                    ),
                  )
                ],
              )),
    );
  }

  List<PieChartSectionData> _getPieChartSections() {
    final colors = [
      Colors.blue, Colors.red, Colors.green, Colors.orange,
      Colors.purple, Colors.teal, Colors.pink, Colors.yellow
    ];

    int colorIndex = 0;
    return _debitsBySender.entries.map((entry) {
      final color = colors[colorIndex % colors.length];
      colorIndex++;

      return PieChartSectionData(
        color: color,
        value: entry.value,
        title: '${entry.key}\n(Rs. ${entry.value.toStringAsFixed(0)})',
        radius: 60,
        titleStyle: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.white),
      );
    }).toList();
  }
}
