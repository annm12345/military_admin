import 'package:mailer/mailer.dart';
import 'package:mailer/smtp_server.dart';

Future<void> sendEmail({
  required String username,
  required String password,
  required String recipient,
  required String subject,
  required String body,
}) async {
  final smtpServer = gmail(username, password);

  // Create the email message
  final message = Message()
    ..from = Address(username, 'Your name')
    ..recipients.add(recipient)
    ..subject = subject
    ..text = body;

  try {
    final sendReport = await send(message, smtpServer);
    print('Message sent: ' + sendReport.toString());
  } on MailerException catch (e) {
    print('Message not sent.');
    for (var p in e.problems) {
      print('Problem: ${p.code}: ${p.msg}');
    }
  }
}
