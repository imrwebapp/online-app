import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AzkarScreen extends StatelessWidget {
  AzkarScreen({super.key});
  final List<Map<String, String>> azkars = [
    {
      'title': 'والدین کے لیے دعا',
      'arabic': 'رَّبِّ ارْحَمْهُمَا كَمَا رَبَّيَانِي صَغِيرًا',
      'translation': 'اے میرے رب! ان پر رحم فرما جیسے انہوں نے بچپن میں مجھ پر رحم کیا۔'
    },
    {
      'title': 'رزق اور برکت کے لیے دعا',
      'arabic': 'اللّهُمَّ اكْفِنِي بِحَلالِكَ عَنْ حَرامِكَ، وَأَغْنِنِي بِفَضْلِكَ عَمَّنْ سِوَاكَ',
      'translation': 'اے اللہ! اپنے حلال سے مجھے کافی کر دے اپنے حرام سے، اور اپنے فضل سے مجھے دوسروں سے بے نیاز کر دے۔'
    },
    {
      'title': 'غم اور پریشانی سے نجات کی دعا',
      'arabic': 'اللهم إني أعوذ بك من الهم والحزن، والعجز والكسل، والبخل والجبن، وضلع الدين وغلبة الرجال',
      'translation': 'اے اللہ! میں تجھ سے پناہ مانگتا ہوں غم اور پریشانی سے، کمزوری اور سستی سے، بخل اور بزدلی سے، قرض کے بوجھ اور لوگوں کے غلبے سے۔'
    },
    {
      'title': 'روزِ قیامت کی ثابت قدمی کی دعا',
      'arabic': 'اللهم ثبتنا يوم القيامة عند السؤال',
      'translation': 'اے اللہ! روزِ قیامت سوال کے وقت ہمیں ثابت قدم رکھ۔'
    },
    {
      'title': 'گناہوں کی معافی کی دعا',
      'arabic': 'اللهم اغفر لي ولوالدي وللمؤمنين يوم يقوم الحساب',
      'translation': 'اے اللہ! مجھے، میرے والدین کو، اور تمام مؤمنوں کو روزِ حساب بخش دے۔'
    },
    {
      'title': 'سونے سے پہلے کی دعا',
      'arabic': 'بِاسْمِكَ اللَّهُمَّ أَحْيَا وَبِاسْمِكَ أَمُوتُ',
      'translation': 'اے اللہ! تیرے نام پر میں جیتا ہوں اور تیرے نام پر مرتا ہوں۔'
    },
    {
      'title': 'جاگنے کی دعا',
      'arabic': 'الْحَمْدُ لِلَّهِ الَّذِي أَحْيَانَا بَعْدَ مَا أَمَاتَنَا وَإِلَيْهِ النُّشُورُ',
      'translation': 'تمام تعریفیں اللہ کے لیے ہیں جس نے ہمیں مرنے کے بعد زندہ کیا، اور اسی کی طرف ہمیں لوٹنا ہے۔'
    },
    {
      'title': 'کھانے سے پہلے کی دعا',
      'arabic': 'بِسْمِ اللَّهِ',
      'translation': 'اللہ کے نام سے (کھانا شروع کرتا ہوں)۔'
    },
    {
      'title': 'کھانے کے بعد کی دعا',
      'arabic': 'الْحَمْدُ لِلَّهِ الَّذِي أَطْعَمَنَا وَسَقَانَا وَجَعَلَنَا مُسْلِمِينَ',
      'translation': 'تمام تعریفیں اللہ کے لیے ہیں جس نے ہمیں کھلایا، پلایا اور ہمیں مسلمان بنایا۔'
    },
    {
      'title': 'گھر سے نکلنے کی دعا',
      'arabic': 'بِسْمِ اللَّهِ تَوَكَّلْتُ عَلَى اللَّهِ وَلَا حَوْلَ وَلَا قُوَّةَ إِلَّا بِاللَّهِ',
      'translation': 'اللہ کے نام سے، میں نے اللہ پر بھروسہ کیا، اور اللہ کے سوا کوئی طاقت یا قوت نہیں۔'
    },
    {
      'title': 'گھر میں داخل ہونے کی دعا',
      'arabic': 'اللَّهُمَّ إِنِّي أَسْأَلُكَ خَيْرَ الْمَوْلَجِ وَخَيْرَ الْمَخْرَجِ',
      'translation': 'اے اللہ! میں تجھ سے داخل ہونے کی بھلائی اور نکلنے کی بھلائی مانگتا ہوں۔'
    },
    {
      'title': 'سفر کی دعا',
      'arabic': 'سُبْحَانَ الَّذِي سَخَّرَ لَنَا هَذَا وَمَا كُنَّا لَهُ مُقْرِنِينَ وَإِنَّا إِلَىٰ رَبِّنَا لَمُنقَلِبُونَ',
      'translation': 'پاک ہے وہ ذات جس نے ہمارے لیے اس سواری کو تابع بنایا، حالانکہ ہم اس پر قابو نہیں پا سکتے تھے، اور ہم اپنے رب ہی کی طرف لوٹنے والے ہیں۔'
    },
    {
      'title': 'علم میں اضافہ کی دعا',
      'arabic': 'رَبِّ زِدْنِي عِلْمًا',
      'translation': 'اے میرے رب! میرے علم میں اضافہ فرما۔'
    },
    {
      'title': 'صبر کی دعا',
      'arabic': 'رَبَّنَا أَفْرِغْ عَلَيْنَا صَبْرًا وَتَوَفَّنَا مُسْلِمِينَ',
      'translation': 'اے ہمارے رب! ہم پر صبر نازل فرما اور ہمیں مسلمان حالت میں موت دے۔'
    },
    {
      'title': 'ہدایت کی دعا',
      'arabic': 'اللَّهُمَّ اهْدِنِي وَسَدِّدْنِي',
      'translation': 'اے اللہ! مجھے ہدایت دے اور مجھے درست راستے پر قائم رکھ۔'
    },
    {
      'title': 'شر سے حفاظت کی دعا',
      'arabic': 'أَعُوذُ بِكَلِمَاتِ اللَّهِ التَّامَّاتِ مِنْ شَرِّ مَا خَلَقَ',
      'translation': 'میں اللہ کے کامل کلمات کے ذریعے ہر مخلوق کے شر سے پناہ مانگتا ہوں۔'
    },
    {
      'title': 'کامیابی کی دعا',
      'arabic': 'اللَّهُمَّ إِنِّي أَسْأَلُكَ النَّجَاحَ فِي كُلِّ أَمْرٍ',
      'translation': 'اے اللہ! میں تجھ سے ہر کام میں کامیابی مانگتا ہوں۔'
    },
    {
      'title': 'بیماری میں شفا کی دعا',
      'arabic': 'اللَّهُمَّ اشْفِنِي شِفَاءً لَا يُغَادِرُ سَقَمًا',
      'translation': 'اے اللہ! مجھے ایسی شفا عطا فرما جو کسی بیماری کو باقی نہ رکھے۔'
    },
    {
      'title': 'رحم و مغفرت کی دعا',
      'arabic': 'رَبَّنَا ظَلَمْنَا أَنْفُسَنَا وَإِنْ لَمْ تَغْفِرْ لَنَا وَتَرْحَمْنَا لَنَكُونَنَّ مِنَ الْخَاسِرِينَ',
      'translation': 'اے ہمارے رب! ہم نے اپنی جانوں پر ظلم کیا، اگر تو ہمیں نہ بخشے اور ہم پر رحم نہ کرے تو ہم ضرور نقصان اٹھانے والوں میں سے ہوں گے۔'
    },
    {
      'title': 'رات کی حفاظت کی دعا',
      'arabic': 'اللَّهُمَّ بِاسْمِكَ أَحْيَا وَبِاسْمِكَ أَمُوتُ',
      'translation': 'اے اللہ! تیرے نام سے میں جیتا ہوں اور تیرے نام سے مرتا ہوں۔'
    },
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('اذکار و دعائیں'),
        
        centerTitle: true,
        elevation: 0,
        iconTheme: const IconThemeData(
    color: Colors.white,),
        
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color.fromARGB(255, 14, 76, 61), Color.fromARGB(255, 14, 76, 61)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFFF0FFF4), Color(0xFFE8F5E9)],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: azkars.length,
          itemBuilder: (context, index) {
            final dua = azkars[index];
            return _buildDuaCard(context, dua, index);
          },
        ),
      ),
    );
  }

  Widget _buildDuaCard(BuildContext context, Map<String, String> dua, int index) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: 600 + (index * 100)),
      curve: Curves.easeOutCubic,
      builder: (context, value, child) {
        return Opacity(
          opacity: value,
          child: Transform.translate(
            offset: Offset(0, (1 - value) * 30),
            child: child,
          ),
        );
      },
      child: Card(
        elevation: 5,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        margin: const EdgeInsets.symmetric(vertical: 10),
        child: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFFB2DFDB), Color(0xFF80CBC4)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.all(Radius.circular(16)),
          ),
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                dua['title']!,
                textAlign: TextAlign.right,
                style: GoogleFonts.notoSans(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.teal[900],
                ),
              ),
              const SizedBox(height: 10),
              Text(
                dua['arabic']!,
                textAlign: TextAlign.right,
                style: GoogleFonts.amiri(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: Colors.teal[800],
                  height: 1.6,
                ),
              ),
              const SizedBox(height: 8),
              Divider(color: Colors.teal.shade100),
              const SizedBox(height: 6),
              Text(
                dua['translation']!,
                textAlign: TextAlign.right,
                style: GoogleFonts.notoSans(
                  fontSize: 15,
                  color: Colors.teal[900],
                  height: 1.6,
                ),
              ),
            ],
          ),
        ),
     ),
);
}
}
