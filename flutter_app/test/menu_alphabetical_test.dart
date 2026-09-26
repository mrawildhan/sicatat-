import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sicatat_flutter/core/widgets/menu_choice_card.dart';

void main() {
  testWidgets('menu kartu selalu berurutan abjad', (tester) async {
    MenuChoiceCard card(String title, {String? sortTitle}) => MenuChoiceCard(
      icon: Icons.circle,
      title: title,
      sortTitle: sortTitle,
      subtitle: '',
      onTap: () {},
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: MenuChoiceList(
              cards: <MenuChoiceCard>[
                card('Tren suhu'),
                card('Memeriksa…', sortTitle: 'Sinkronisasi'),
                card('belum lengkap'),
                card('Lembar saya'),
              ],
            ),
          ),
        ),
      ),
    );
    final List<double> tops = <String>[
      'belum lengkap',
      'Lembar saya',
      'Memeriksa…',
      'Tren suhu',
    ].map((String t) => tester.getTopLeft(find.text(t)).dy).toList();
    expect(tops, List<double>.of(tops)..sort());
  });
}
