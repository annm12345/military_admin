import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:mailer/mailer.dart';
import 'package:mailer/smtp_server/gmail.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_html/flutter_html.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late Future<List<User>> futureUsers;
  String randomCode = RandomStringGenerator.generate(length: 16);

  @override
  void initState() {
    super.initState();
    futureUsers = fetchUsers();
  }

  Future<List<User>> fetchUsers() async {
    final response = await http
        .get(Uri.parse('http://militarycommand.atwebpages.com/all_users.php'));

    if (response.statusCode == 200) {
      List jsonResponse = json.decode(response.body);
      return jsonResponse.map((user) => User.fromJson(user)).toList();
    } else {
      throw Exception('Failed to load users');
    }
  }

  Future<void> approveUser(String email, String password) async {
    
    final response = await http.post(
      Uri.parse('http://militarycommand.atwebpages.com/approve_user.php'),
      body: {'email': email, 'password': randomCode},
    );

    // if (response.statusCode == 200) {
    //   final responseBody = json.decode(response.body);
    //   if (responseBody['message'] == 'Email Sent!') {
    //     showDialog(
    //       context: context,
    //       builder: (BuildContext context) {
    //         return AlertDialog(
    //           title: Text('Success'),
    //           content: Text('User approved and email sent successfully.'),
    //           actions: [
    //             TextButton(
    //               child: Text('OK'),
    //               onPressed: () {
    //                 Navigator.of(context).pop();
    //               },
    //             ),
    //           ],
    //         );
    //       },
    //     );

    //     setState(() {
    //       futureUsers = fetchUsers();
    //     });
    //   } else {
    //     print('Error: ${responseBody['error']}');
    //   }
    // } else {
    //   throw Exception('Failed to approve user');
    // }
  }

  void sendMail({
    required String recipientEmail,
  }) async {
    String username = 'aungnyinyimin32439@gmail.com'; // Update with your email
    String password = 'gdbcegflheqtzjjd'; // Update with your email password

    final smtpServer = gmail(username, password);

    final message = Message()
      ..from = Address(username, 'Military Command App')
      ..recipients.add(recipientEmail)
      ..subject = 'Confirmation Code'
      ..html = '''
      Welcome from Military Command App user!<br>
      Please do not show the confirmation code to anyone for your security.<br>
      Your Confirmation Code is: <b>$randomCode</b>
    ''';

    try {
      await send(message, smtpServer);
      showSnackbar('Email sent successfully');
    } catch (e) {
      if (kDebugMode) {
        print(e.toString());
      }
      showSnackbar('Failed to send email');
    }
  }

  void showSnackbar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: const TextStyle(fontSize: 16),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('User List'),
      ),
      body: Center(
        child: FutureBuilder<List<User>>(
          future: futureUsers,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return CircularProgressIndicator();
            } else if (snapshot.hasError) {
              return Text('${snapshot.error}');
            } else if (snapshot.hasData) {
              List<User> users = snapshot.data!;
              return ListView.builder(
                itemCount: users.length,
                itemBuilder: (context, index) {
                  return Card(
                    margin: EdgeInsets.all(10),
                    child: Padding(
                      padding: EdgeInsets.all(10),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('BC: ${users[index].bc}',
                              style: TextStyle(fontWeight: FontWeight.bold)),
                          SizedBox(height: 5),
                          Text('Rank: ${users[index].rank}'),
                          SizedBox(height: 5),
                          Text('Name: ${users[index].name}'),
                          SizedBox(height: 5),
                          Text('Mobile: ${users[index].mobile}'),
                          SizedBox(height: 5),
                          Text('Unit: ${users[index].unit}'),
                          SizedBox(height: 5),
                          Text('Command: ${users[index].command}'),
                          SizedBox(height: 5),
                          Text('Email: ${users[index].email}'),
                          SizedBox(height: 5),
                          users[index].approve.isEmpty
                              ? ElevatedButton(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor:
                                        Color.fromARGB(255, 40, 3, 201),
                                  ),
                                  onPressed: () {
                                    approveUser(
                                        users[index].email, users[index].code);
                                    sendMail(
                                        recipientEmail: users[index].email);
                                    setState(() {
                                      users[index].approve = "Approved";
                                    });
                                  },
                                  child: Text(
                                    'Approve',
                                    style: TextStyle(color: Colors.white),
                                  ),
                                )
                              : Text('Approved'),
                        ],
                      ),
                    ),
                  );
                },
              );
            } else {
              return Text('No users found');
            }
          },
        ),
      ),
    );
  }
}

class RandomStringGenerator {
  static const String _letters =
      'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ';
  static const String _numbers = '0123456789';
  static const String _specialChars = '!@#\$%^&*()_+[]{}|;:,.<>?';
  static const String _allChars = _letters + _numbers + _specialChars;

  static String generate({int length = 12}) {
    final Random random = Random();
    final StringBuffer buffer = StringBuffer();

    for (int i = 0; i < length; i++) {
      int index = random.nextInt(_allChars.length);
      buffer.write(_allChars[index]);
    }

    return buffer.toString();
  }
}

class User {
  final String bc;
  final String rank;
  final String name;
  final String mobile;
  final String unit;
  final String command;
  final String email;
  String approve;
  String code;

  User({
    required this.bc,
    required this.rank,
    required this.name,
    required this.mobile,
    required this.unit,
    required this.command,
    required this.email,
    required this.approve,
    required this.code,
  });

  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      bc: json['bc'] as String,
      rank: json['rank'] as String,
      name: json['name'] as String,
      mobile: json['mobile'] as String,
      unit: json['unit'] as String,
      command: json['command'] as String,
      email: json['email'] as String,
      approve: json['approve'] as String,
      code: json['confirm_code'] as String,
    );
  }
}
