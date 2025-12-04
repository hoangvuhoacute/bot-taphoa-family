import 'dart:io';
import 'package:teledart/teledart.dart';
import 'package:teledart/model.dart';
import 'package:teledart/telegram.dart';
import 'package:supabase/supabase.dart';
import 'package:intl/intl.dart';

// --- 1. ĐIỀN THÔNG TIN CỦA BẠN VÀO ĐÂY ---
const String botToken = '8398440437:AAHIbNqxvfkzZ7gXgIaXIZcc0Hu5EjgOF28';
const String supabaseUrl = 'https://jrufrflrvitljuurpdqa.supabase.co';
const String supabaseKey =
    'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImpydWZyZmxydml0bGp1dXJwZHFhIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NjQ4NDk4MTgsImV4cCI6MjA4MDQyNTgxOH0.5_BZ_GdeulTQzHR7J83OVRHLLAmA-ONJG1JxqBh0YuY';
// ------------------------------------------

void main() async {
  // --- Server giả để Render không tắt Bot ---
  try {
    final server = await HttpServer.bind(InternetAddress.anyIPv4,
        int.parse(Platform.environment['PORT'] ?? '8080'));
    server.listen((request) {
      request.response
        ..statusCode = 200
        ..write('Bot OK')
        ..close();
    });
    print('🌍 Dummy Server đang chạy tại port ${server.port}');
  } catch (e) {
    print('⚠️ Chạy local không cần server giả');
  }

  print('🤖 Đang khởi động Bot V6 (Fix lỗi)...');

  final supabase = SupabaseClient(supabaseUrl, supabaseKey);
  final username = (await Telegram(botToken).getMe()).username;
  var teledart = TeleDart(botToken, Event(username!));

  teledart.start();
  print('✅ Bot $username đang chạy!');

  // --- MENU CHÍNH ---
  final menuKeyboard = ReplyKeyboardMarkup(
    keyboard: [
      [
        KeyboardButton(text: '📦 Xem Kho'),
        KeyboardButton(text: '📉 Hết/Sắp Hết')
      ],
      [
        KeyboardButton(text: '📊 Doanh Thu'),
        KeyboardButton(text: '📥 Báo Cáo Nhập')
      ],
      [
        KeyboardButton(text: '➕ HD Nhập Hàng'),
        KeyboardButton(text: '✏️ HD Sửa Hàng')
      ],
      [
        KeyboardButton(text: '🔍 Tìm Kiếm'),
        KeyboardButton(text: '⏳ Check Hạn SD')
      ],
    ],
    resizeKeyboard: true,
  );

  teledart.onCommand('start').listen((message) {
    message.reply('Xin chào chủ tiệm! Chọn chức năng:',
        replyMarkup: menuKeyboard);
  });

  // ==========================================
  // 1. TÍNH NĂNG: BÁO CÁO NHẬP KHO
  // ==========================================
  teledart.onMessage(keyword: '📥 Báo Cáo Nhập').listen((message) {
    message.reply('📅 Xem chi phí nhập hàng:',
        replyMarkup: InlineKeyboardMarkup(inlineKeyboard: [
          [
            InlineKeyboardButton(
                text: 'Chi Hôm Nay', callbackData: 'import_today')
          ],
          [
            InlineKeyboardButton(
                text: 'Chi Tháng Này', callbackData: 'import_month')
          ],
        ]));
  });

  teledart.onCallbackQuery().listen((query) async {
    if (query.data!.startsWith('import_')) {
      DateTime now = DateTime.now();
      DateTime start, end;
      String title;

      if (query.data == 'import_today') {
        start = DateTime(now.year, now.month, now.day);
        end = DateTime(now.year, now.month, now.day, 23, 59, 59);
        title = "HÔM NAY";
      } else {
        start = DateTime(now.year, now.month, 1);
        end = DateTime(now.year, now.month + 1, 0, 23, 59, 59);
        title = "THÁNG ${now.month}";
      }

      try {
        teledart.answerCallbackQuery(query.id, text: 'Đang tính toán...');

        final allImports = await supabase
            .from('imports')
            .select('total_cost, created_date')
            .limit(200);

        double totalCost = 0;
        int countForm = 0;
        DateFormat fmt = DateFormat('dd/MM/yyyy');

        for (var item in allImports) {
          try {
            DateTime date = fmt.parse(item['created_date']);
            if (date.isAfter(start.subtract(Duration(seconds: 1))) &&
                date.isBefore(end.add(Duration(seconds: 1)))) {
              totalCost += (item['total_cost'] as num).toDouble();
              countForm++;
            }
          } catch (e) {}
        }

        final mf = NumberFormat("#,###", "vi_VN");
        teledart.sendMessage(query.message!.chat.id,
            "📉 **CHI PHÍ NHẬP HÀNG $title**\n--------------------------\n💸 Tổng chi: **${mf.format(totalCost)} đ**\n📝 Số phiếu nhập: $countForm phiếu",
            parseMode: 'Markdown');
      } catch (e) {
        teledart.sendMessage(query.message!.chat.id, "Lỗi tính toán: $e");
      }
    }
  });

  // ==========================================
  // 2. CÁC LỆNH SỬA (/suagia, /suahan)
  // ==========================================
  teledart.onCommand('suagia').listen((message) async {
    final args = message.text?.split(' ');
    if (args == null || args.length < 4) {
      await message.reply("❌ Sai cú pháp!\nVD: `/suagia 893123 15000 20000`",
          parseMode: 'Markdown');
      return;
    }
    try {
      String code = args[1];
      double importPrice = double.tryParse(args[2]) ?? 0;
      double sellPrice = double.tryParse(args[3]) ?? 0;

      final update = await supabase
          .from('products')
          .update({'import_price': importPrice, 'sell_price': sellPrice})
          .eq('barcode', code)
          .select();

      if (update.isEmpty) {
        await message.reply("❌ Không tìm thấy mã `$code`",
            parseMode: 'Markdown');
      } else {
        final mf = NumberFormat("#,###", "vi_VN");
        await message.reply(
            "✅ **Đã cập nhật giá:**\n📥 Nhập: ${mf.format(importPrice)} đ\n📤 Bán: ${mf.format(sellPrice)} đ",
            parseMode: 'Markdown');
      }
    } catch (e) {
      await message.reply("Lỗi: $e");
    }
  });

  teledart.onCommand('suahan').listen((message) async {
    final args = message.text?.split(' ');
    if (args == null || args.length < 3) {
      await message.reply("❌ Sai cú pháp!\nVD: `/suahan 893123 31/12/2025`",
          parseMode: 'Markdown');
      return;
    }
    try {
      String code = args[1];
      String expiry = args[2];
      final update = await supabase
          .from('products')
          .update({'expiry_date': expiry})
          .eq('barcode', code)
          .select();
      if (update.isEmpty) {
        await message.reply("❌ Không tìm thấy mã `$code`",
            parseMode: 'Markdown');
      } else {
        await message.reply("✅ **Đã cập nhật Hạn SD:** $expiry",
            parseMode: 'Markdown');
      }
    } catch (e) {
      await message.reply("Lỗi: $e");
    }
  });

  // ==========================================
  // 3. HƯỚNG DẪN
  // ==========================================
  teledart.onMessage(keyword: '✏️ HD Sửa Hàng').listen((message) {
    message.reply(
        '🛠 **HƯỚNG DẪN SỬA THÔNG TIN**\n(Chạm lệnh để copy)\n\n'
        '1️⃣ **Sửa Giá:** `/suagia [Mã] [GiáNhập] [GiáBán]`\nVD: `/suagia 893123 10000 15000`\n\n'
        '2️⃣ **Sửa Hạn:** `/suahan [Mã] [Ngày/Tháng/Năm]`\nVD: `/suahan 893123 31/12/2025`\n\n'
        '3️⃣ **Sửa Tên:** `/suaten [Mã] [Tên Mới]`\nVD: `/suaten 893123 Bánh Gạo`\n\n'
        '4️⃣ **Sửa Mã:** `/suama [Tên Cũ] [Mã Mới]`\nVD: `/suama Bánh_Quy 893999`\n\n'
        '5️⃣ **Sửa Tồn:** `/chinhkho [Mã] [Số Thực Tế]`\nVD: `/chinhkho 893123 50`',
        parseMode: 'Markdown');
  });

  teledart.onMessage(keyword: '➕ HD Nhập Hàng').listen((message) {
    message.reply(
        '📦 **HƯỚNG DẪN NHẬP HÀNG**\n\n'
        '1️⃣ **Nhập Thêm (Cộng dồn):**\n`/them [Mã] [Số lượng]`\nVD: `/them 893123 10`\n\n'
        '2️⃣ **Nhập Mới / Full:**\n`/nhap [Mã] [SL] [GiáGốc] [GiáBán] [Hạn] [Tên]`\nVD: `/nhap 893123 20 10000 12000 31/12/2025 Bánh`',
        parseMode: 'Markdown');
  });

  // ==========================================
  // 4. CÁC LỆNH KHÁC (Đã fix lỗi Return)
  // ==========================================

  // --- Báo Cáo Doanh Thu ---
  teledart.onMessage(keyword: '📊 Doanh Thu').listen((message) {
    message.reply('📅 Xem doanh thu:',
        replyMarkup: InlineKeyboardMarkup(inlineKeyboard: [
          [InlineKeyboardButton(text: 'Hôm nay', callbackData: 'stats_today')],
          [
            InlineKeyboardButton(text: 'Tháng này', callbackData: 'stats_month')
          ],
        ]));
  });

  teledart.onCallbackQuery().listen((query) async {
    if (query.data!.startsWith('stats_')) {
      DateTime now = DateTime.now();
      DateTime start, end;
      if (query.data == 'stats_today') {
        start = DateTime(now.year, now.month, now.day);
        end = DateTime(now.year, now.month, now.day, 23, 59, 59);
      } else {
        start = DateTime(now.year, now.month, 1);
        end = DateTime(now.year, now.month + 1, 0, 23, 59, 59);
      }
      try {
        teledart.answerCallbackQuery(query.id, text: 'Đang tính...');
        final res = await supabase
            .from('invoice_details')
            .select(
                'quantity, sell_price, capital_price, invoices!inner(created_date)')
            .gte('invoices.created_date', start.toIso8601String())
            .lte('invoices.created_date', end.toIso8601String());
        double rev = 0;
        double prof = 0;
        for (var i in res) {
          int q = i['quantity'] ?? 0;
          rev += (i['sell_price'] ?? 0) * q;
          prof += ((i['sell_price'] ?? 0) - (i['capital_price'] ?? 0)) * q;
        }
        final mf = NumberFormat("#,###", "vi_VN");
        teledart.sendMessage(query.message!.chat.id,
            "💰 **DOANH THU**\nDoanh thu: ${mf.format(rev)}đ\nLợi nhuận: ${mf.format(prof)}đ",
            parseMode: 'Markdown');
      } catch (e) {
        teledart.sendMessage(query.message!.chat.id, "Lỗi: $e");
      }
    }
  });

  // --- Hết/Sắp Hết ---
  teledart.onMessage(keyword: RegExp(r'(📉 Hết/Sắp Hết)')).listen((m) async {
    try {
      await m.reply('🕵️ Đang tìm...');
      final data = await supabase
          .from('products')
          .select('name, stock, barcode')
          .lte('stock', 5)
          .order('stock', ascending: true);
      if (data.isEmpty) {
        await m.reply('✅ Kho ổn định.');
        return;
      }
      List<String> low = [];
      for (var i in data)
        low.add((i['stock'] <= 0 ? "⚫" : "🔴") +
            " **${i['name']}** (SL: ${i['stock']})");
      await m.reply("⚠️ **CẦN NHẬP:**\n" + low.join('\n'),
          parseMode: 'Markdown');
    } catch (e) {
      m.reply("Lỗi: $e");
    }
  });

  // --- Xem Kho ---
  teledart.onMessage(keyword: RegExp(r'(📦 Xem Kho)')).listen((m) async {
    try {
      await m.reply('⏳ Đang tải...');
      final data = await supabase
          .from('products')
          .select('name, stock, sell_price, barcode')
          .order('stock', ascending: true);
      String res = "📦 **KHO:**\n";
      for (var i in data) {
        final p = NumberFormat("#,###").format(i['sell_price']);
        res +=
            "${i['stock'] == 0 ? '⚫' : (i['stock'] <= 5 ? '🔴' : '🟢')} **${i['name']}**\n   Mã: `${i['barcode'] ?? ''}` | SL: ${i['stock']} | Giá: ${p}\n\n";
        if (res.length > 3500) {
          await m.reply(res, parseMode: 'Markdown');
          res = "";
        }
      }
      if (res.isNotEmpty) await m.reply(res, parseMode: 'Markdown');
    } catch (e) {}
  });

  // --- /them (ĐÃ SỬA LỖI RETURN) ---
  teledart.onCommand('them').listen((m) async {
    final args = m.text?.split(' ');
    if (args == null || args.length < 3) {
      await m.reply("Sai cú pháp.");
      return;
    }
    int? qty = int.tryParse(args.last);
    String id = args.sublist(1, args.length - 1).join(' ');
    try {
      final s = await supabase
          .from('products')
          .select()
          .or('barcode.eq."$id",name.eq."$id"')
          .limit(1);
      if (s.isEmpty) {
        await m.reply("K tìm thấy.");
        return;
      }
      await supabase
          .from('products')
          .update({'stock': (s[0]['stock'] ?? 0) + qty}).eq('id', s[0]['id']);
      m.reply("✅ Đã thêm $qty cho **${s[0]['name']}**", parseMode: 'Markdown');
    } catch (e) {}
  });

  // --- /nhap (ĐÃ SỬA LỖI RETURN) ---
  teledart.onCommand('nhap').listen((m) async {
    final args = m.text?.split(' ');
    if (args == null || args.length < 7) {
      await m.reply("Thiếu thông tin.");
      return;
    }
    try {
      String bc = args[1];
      int q = int.parse(args[2]);
      double ip = double.parse(args[3]);
      double sp = double.parse(args[4]);
      String exp = args[5];
      String n = args.sublist(6).join(' ');

      final s = await supabase
          .from('products')
          .select()
          .eq('barcode', bc)
          .maybeSingle();
      int id;
      int oldS = 0;
      if (s == null) {
        final newP = await supabase
            .from('products')
            .insert({
              'barcode': bc,
              'name': n,
              'stock': 0,
              'category_id': 1,
              'import_price': ip,
              'sell_price': sp,
              'expiry_date': exp,
              'created_date': DateTime.now().toIso8601String()
            })
            .select()
            .single();
        id = newP['id'];
        m.reply("🆕 Món mới: **$n**", parseMode: 'Markdown');
      } else {
        id = s['id'];
        oldS = s['stock'] ?? 0;
      }

      final imp = await supabase
          .from('imports')
          .insert({
            'total_cost': ip * q,
            'created_date': DateFormat('dd/MM/yyyy').format(DateTime.now()),
            'supplier': 'Bot'
          })
          .select()
          .single();
      await supabase.from('import_details').insert({
        'import_id': imp['id'],
        'product_id': id,
        'product_name': n,
        'quantity': q,
        'import_price': ip,
        'expiry_date': exp
      });
      await supabase.from('products').update({
        'stock': oldS + q,
        'import_price': ip,
        'sell_price': sp,
        'expiry_date': exp
      }).eq('id', id);
      m.reply("✅ Nhập xong!\n📦 **$n**\n📈 Tồn: **${oldS + q}**",
          parseMode: 'Markdown');
    } catch (e) {
      m.reply("Lỗi: $e");
    }
  });

  // --- Các lệnh phụ ---
  teledart.onCommand('suaten').listen((m) async {
    final a = m.text?.split(' ');
    if (a == null || a.length < 3) return;
    try {
      await supabase
          .from('products')
          .update({'name': a.sublist(2).join(' ')}).eq('barcode', a[1]);
      m.reply("✅ Đã sửa tên.");
    } catch (e) {}
  });

  teledart.onCommand('suama').listen((m) async {
    final a = m.text?.split(' ');
    if (a == null || a.length < 3) return;
    try {
      final s = await supabase
          .from('products')
          .select('id')
          .or('barcode.eq."${a.sublist(1, a.length - 1).join(' ')}",name.eq."${a.sublist(1, a.length - 1).join(' ')}"')
          .limit(1);
      if (s.isNotEmpty) {
        await supabase
            .from('products')
            .update({'barcode': a.last}).eq('id', s[0]['id']);
        m.reply("✅ Đã sửa mã.");
      }
    } catch (e) {}
  });

  teledart.onCommand('chinhkho').listen((m) async {
    final a = m.text?.split(' ');
    if (a == null || a.length < 3) return;
    try {
      final s = await supabase
          .from('products')
          .select('id')
          .or('barcode.eq."${a.sublist(1, a.length - 1).join(' ')}",name.eq."${a.sublist(1, a.length - 1).join(' ')}"')
          .limit(1);
      if (s.isNotEmpty) {
        await supabase
            .from('products')
            .update({'stock': int.parse(a.last)}).eq('id', s[0]['id']);
        m.reply("✅ Đã chỉnh kho.");
      }
    } catch (e) {}
  });

  teledart
      .onMessage(keyword: '🔍 Tìm Kiếm')
      .listen((m) => m.reply('Gõ `/tim [tên]`'));
  teledart.onCommand('tim').listen((m) async {
    final k = m.text?.split(' ').sublist(1).join(' ');
    if (k == null || k.isEmpty) return;
    final d = await supabase.from('products').select().ilike('name', '%$k%');
    String r = "";
    for (var i in d) r += "- ${i['name']} | Tồn: ${i['stock']}\n";
    m.reply(r.isEmpty ? "K thấy" : r);
  });

  teledart.onMessage(keyword: RegExp(r'(⏳ Check Hạn SD)')).listen((m) async {
    try {
      m.reply('🕵️ Checking...');
      final d =
          await supabase.from('products').select('name,expiry_date,stock');
      List<String> e = [];
      DateFormat f = DateFormat('dd/MM/yyyy');
      DateTime n = DateTime.now();
      for (var i in d) {
        if (i['expiry_date'] == null) continue;
        try {
          DateTime t = f.parse(i['expiry_date']);
          if (t.isBefore(n))
            e.add("💀 ${i['name']} (Hết: ${i['expiry_date']})");
          else if (t.difference(n).inDays <= 30)
            e.add("⚠️ ${i['name']} (Còn ${t.difference(n).inDays} ngày)");
        } catch (x) {}
      }
      m.reply(e.isEmpty ? "✅ Hạn tốt" : "⚠️ **HẠN SD:**\n" + e.join('\n'),
          parseMode: 'Markdown');
    } catch (e) {}
  });
}
