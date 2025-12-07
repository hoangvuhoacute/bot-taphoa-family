import 'dart:io';
import 'dart:convert';
import 'package:teledart/teledart.dart';
import 'package:teledart/model.dart';
import 'package:teledart/telegram.dart';
import 'package:supabase/supabase.dart';
import 'package:intl/intl.dart';

// --- 1. CẤU HÌNH BOT & DATABASE ---
const String botToken = '8398440437:AAHIbNqxvfkzZ7gXgIaXIZcc0Hu5EjgOF28';
const String supabaseUrl = 'https://jrufrflrvitljuurpdqa.supabase.co';
const String supabaseKey =
    'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImpydWZyZmxydml0bGp1dXJwZHFhIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NjQ4NDk4MTgsImV4cCI6MjA4MDQyNTgxOH0.5_BZ_GdeulTQzHR7J83OVRHLLAmA-ONJG1JxqBh0YuY';

// --- 2. CẤU HÌNH NGÂN HÀNG ---
const String bankId = 'MB';
const String accountNo = '0829669310';
const String template = 'compact';
const String defaultContent = 'DanViet';

// --- 3. CẤU HÌNH NHẬN THÔNG BÁO ---
// Điền ID của bạn vào đây (Lấy bằng lệnh /myid)
int adminChatId = 0;

// --- HÀM KIỂM TRA MÃ VẠCH (QUAN TRỌNG) ---
bool isValidBarcode(String? code) {
  if (code == null || code.trim().isEmpty) return false; // Không được rỗng
  // Kiểm tra xem có phải toàn số không (Dùng Regex)
  return RegExp(r'^[0-9]+$').hasMatch(code);
}

void main() async {
  // --- Server giả (Keep Alive) ---
  try {
    final server = await HttpServer.bind(InternetAddress.anyIPv4,
        int.parse(Platform.environment['PORT'] ?? '8080'));
    print('🌍 Server đang chạy tại port ${server.port}');

    server.listen((request) async {
      // 1. Webhook SePay
      if (request.method == 'POST' && request.uri.path == '/sepay_webhook') {
        try {
          final content = await utf8.decoder.bind(request).join();
          final data = jsonDecode(content);

          String amountIn = data['transferAmount'].toString();
          String description = data['content'];
          String date = data['transactionDate'];
          final mf = NumberFormat("#,###", "vi_VN");
          String money = mf.format(int.tryParse(amountIn) ?? 0);

          if (adminChatId != 0) {
            await teledart.sendMessage(adminChatId,
                "🔔 **TING TING! TIỀN VỀ!**\n---------------------------\n💰 Số tiền: **$money đ**\n📝 Nội dung: `$description`\n⏰ Thời gian: $date\n---------------------------\n✅ Giao dịch thành công!",
                parseMode: 'Markdown');
          }
          request.response
            ..statusCode = 200
            ..write('OK')
            ..close();
        } catch (e) {
          request.response
            ..statusCode = 500
            ..write('Error')
            ..close();
        }
      }
      // 2. Keep Alive
      else {
        request.response
          ..statusCode = 200
          ..write('Bot OK')
          ..close();
      }
    });
  } catch (e) {
    print('⚠️ Chạy local: $e');
  }

  print('🤖 Đang khởi động Bot V13 (Check Barcode)...');

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
        KeyboardButton(text: '💳 Lấy Mã QR')
      ],
      [
        KeyboardButton(text: '🔍 Tìm Kiếm'),
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
        KeyboardButton(text: '⏳ Check Hạn SD'),
        KeyboardButton(text: '❓ Trợ Giúp')
      ],
    ],
    resizeKeyboard: true,
  );

  teledart.onCommand('start').listen((message) {
    message.reply('Xin chào chủ tiệm! Chọn chức năng:',
        replyMarkup: menuKeyboard);
  });

  teledart.onCommand('myid').listen((message) {
    adminChatId = message.chat.id;
    message.reply(
        "✅ Đã lưu ID: `${message.chat.id}`. Bot sẽ báo tin tiền về cho bạn.",
        parseMode: 'Markdown');
  });

  // ==========================================
  // 1. TÍNH NĂNG QR CODE
  // ==========================================
  Future<void> sendQrCode(dynamic message) async {
    String qrUrl =
        'https://img.vietqr.io/image/$bankId-$accountNo-$template.png?addInfo=$defaultContent';
    try {
      await teledart.sendPhoto(message.chat.id, qrUrl,
          caption:
              "🏧 **MÃ QR CỬA HÀNG**\n--------------------------\n🏦 Ngân hàng: **$bankId**\n💳 STK: **$accountNo**\n📝 Nội dung: `$defaultContent`\n👉 Khách tự nhập số tiền.",
          parseMode: 'Markdown');
    } catch (e) {
      message.reply("Lỗi: $e");
    }
  }

  teledart.onMessage(keyword: '💳 Lấy Mã QR').listen((m) => sendQrCode(m));
  teledart.onCommand('qr').listen((m) => sendQrCode(m));

  // ==========================================
  // 2. CÁC LỆNH NHẬP & SỬA (ĐÃ THÊM CHECK BARCODE)
  // ==========================================

  // --- /nhap (Full) ---
  teledart.onCommand('nhap').listen((m) async {
    final args = m.text?.split(' ');
    if (args == null || args.length < 7) {
      await m.reply("❌ Thiếu thông tin. Xem HD.");
      return;
    }

    // 1. Kiểm tra mã vạch
    String bc = args[1];
    if (!isValidBarcode(bc)) {
      await m.reply(
          "❌ Mã vạch `$bc` không hợp lệ!\n(Phải là số và không được để trống)",
          parseMode: 'Markdown');
      return;
    }

    try {
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
        await m.reply("🆕 Món mới: **$n**", parseMode: 'Markdown');
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
      await m.reply("✅ Nhập xong!\n📦 **$n**\n📈 Tồn: **${oldS + q}**",
          parseMode: 'Markdown');
    } catch (e) {
      m.reply("Lỗi: $e");
    }
  });

  // --- /them (Cộng dồn) ---
  teledart.onCommand('them').listen((m) async {
    final args = m.text?.split(' ');
    if (args == null || args.length < 3) {
      await m.reply("Sai cú pháp.");
      return;
    }

    // Nếu tham số nhập vào là mã số thì check
    String id = args.sublist(1, args.length - 1).join(' ');
    // Ở đây ta không check strict vì người dùng có thể nhập Tên thay vì Mã

    int? qty = int.tryParse(args.last);
    try {
      final s = await supabase
          .from('products')
          .select()
          .or('barcode.eq."$id",name.eq."$id"')
          .limit(1);
      if (s.isEmpty) {
        await m.reply("❌ Không tìm thấy: $id");
        return;
      }
      await supabase
          .from('products')
          .update({'stock': (s[0]['stock'] ?? 0) + qty!}).eq('id', s[0]['id']);
      await m.reply("✅ Đã thêm $qty. Tồn mới: ${(s[0]['stock'] ?? 0) + qty}");
    } catch (e) {}
  });

  // --- /suama (Sửa Mã Vạch) ---
  teledart.onCommand('suama').listen((m) async {
    final a = m.text?.split(' ');
    if (a == null || a.length < 3) return;

    // Kiểm tra mã mới
    String newCode = a.last;
    if (!isValidBarcode(newCode)) {
      await m.reply("❌ Mã mới `$newCode` không hợp lệ (Phải là số)!",
          parseMode: 'Markdown');
      return;
    }

    try {
      final s = await supabase
          .from('products')
          .select('id')
          .or('barcode.eq."${a.sublist(1, a.length - 1).join(' ')}",name.eq."${a.sublist(1, a.length - 1).join(' ')}"')
          .limit(1);
      if (s.isNotEmpty) {
        // Kiểm tra mã mới đã tồn tại chưa
        final check =
            await supabase.from('products').select().eq('barcode', newCode);
        if (check.isNotEmpty) {
          await m.reply("❌ Mã `$newCode` đã được dùng cho món khác!",
              parseMode: 'Markdown');
          return;
        }

        await supabase
            .from('products')
            .update({'barcode': newCode}).eq('id', s[0]['id']);
        await m.reply("✅ Đã sửa mã thành công: `$newCode`",
            parseMode: 'Markdown');
      } else {
        await m.reply("❌ Không tìm thấy món hàng cũ.");
      }
    } catch (e) {}
  });

  // --- Các lệnh khác (Giữ nguyên) ---
  teledart.onCommand('suagia').listen((m) async {
    final a = m.text?.split(' ');
    if (a != null && a.length >= 4)
      try {
        await supabase.from('products').update({
          'import_price': double.parse(a[2]),
          'sell_price': double.parse(a[3])
        }).eq('barcode', a[1]);
        await m.reply("✅ Đã sửa giá.");
      } catch (e) {}
  });
  teledart.onCommand('suahan').listen((m) async {
    final a = m.text?.split(' ');
    if (a != null && a.length >= 3)
      try {
        await supabase
            .from('products')
            .update({'expiry_date': a[2]}).eq('barcode', a[1]);
        await m.reply("✅ Đã sửa hạn.");
      } catch (e) {}
  });
  teledart.onCommand('suaten').listen((m) async {
    final a = m.text?.split(' ');
    if (a != null && a.length >= 3)
      try {
        await supabase
            .from('products')
            .update({'name': a.sublist(2).join(' ')}).eq('barcode', a[1]);
        await m.reply("✅ Đã sửa tên.");
      } catch (e) {}
  });
  teledart.onCommand('chinhkho').listen((m) async {
    final a = m.text?.split(' ');
    if (a != null && a.length >= 3)
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
          await m.reply("✅ Đã chỉnh kho.");
        }
      } catch (e) {}
  });

  // --- Hướng Dẫn & Tìm Kiếm ---
  teledart.onMessage(keyword: '✏️ HD Sửa Hàng').listen((m) => m.reply(
      '🛠 **HƯỚNG DẪN:**\n`/suagia [Mã] [Gốc] [Bán]`\n`/suahan [Mã] [Hạn]`\n`/suaten [Mã] [Tên]`\n`/chinhkho [Mã] [SL]`\n`/suama [Tên] [Mã Mới]`',
      parseMode: 'Markdown'));
  teledart.onMessage(keyword: '➕ HD Nhập Hàng').listen((m) => m.reply(
      '📦 **HƯỚNG DẪN:**\n`/them [Mã] [SL]`\n`/nhap [Mã] [SL] [Gốc] [Bán] [Hạn] [Tên]`',
      parseMode: 'Markdown'));
  teledart.onMessage(keyword: '❓ Trợ Giúp').listen((m) => m.reply(
      '📖 Bấm các nút trên menu để xem chi tiết.',
      parseMode: 'Markdown'));
  teledart.onMessage(keyword: '🔍 Tìm Kiếm').listen((m) => m.reply(
      '🔎 Gõ lệnh: `/tim [tên]`\nVí dụ: `/tim bánh`',
      parseMode: 'Markdown'));

  teledart.onCommand('tim').listen((message) async {
    final k = message.text?.split(' ').sublist(1).join(' ');
    if (k == null || k.isEmpty) return;
    final d = await supabase.from('products').select().ilike('name', '%$k%');
    if (d.isEmpty)
      await message.reply("❌ Không tìm thấy.");
    else {
      String r = "🔍 **KẾT QUẢ:**\n\n";
      for (var i in d)
        r +=
            "- **${i['name']}**\n  Mã: `${i['barcode'] ?? ''}` | Tồn: **${i['stock']}**\n\n";
      await message.reply(r, parseMode: 'Markdown');
    }
  });

  // --- Xem Kho & Check ---
  teledart.onMessage(keyword: RegExp(r'(📦 Xem Kho)')).listen((m) async {
    try {
      await m.reply('⏳ Đang tải...');
      final d = await supabase.from('products').select().order('stock');
      String r = "📦 **KHO:**\n";
      for (var i in d) {
        final p = NumberFormat("#,###").format(i['sell_price']);
        r +=
            "${i['stock'] <= 5 ? (i['stock'] == 0 ? '⚫' : '🔴') : '🟢'} **${i['name']}**\n   👉 Mã: `${i['barcode'] ?? ''}` | SL: **${i['stock']}** | Giá: $p\n\n";
        if (r.length > 3500) {
          await m.reply(r, parseMode: 'Markdown');
          r = "";
        }
      }
      if (r.isNotEmpty) await m.reply(r, parseMode: 'Markdown');
    } catch (e) {}
  });
  teledart.onMessage(keyword: RegExp(r'(📉 Hết/Sắp Hết)')).listen((m) async {
    try {
      await m.reply('🕵️ Checking...');
      final d = await supabase.from('products').select().lte('stock', 5);
      if (d.isEmpty)
        await m.reply("✅ Kho ổn.");
      else {
        String r = "⚠️ **SẮP HẾT:**\n";
        for (var i in d) r += "- ${i['name']}: ${i['stock']}\n";
        await m.reply(r, parseMode: 'Markdown');
      }
    } catch (e) {}
  });
  teledart.onMessage(keyword: RegExp(r'(⏳ Check Hạn SD)')).listen((m) async {
    try {
      await m.reply('🕵️ Checking...');
      final d = await supabase.from('products').select();
      List<String> e = [];
      DateTime n = DateTime.now();
      for (var i in d) {
        if (i['expiry_date'] == null) continue;
        try {
          if (DateFormat('dd/MM/yyyy').parse(i['expiry_date']).isBefore(n))
            e.add("💀 ${i['name']}");
        } catch (x) {}
      }
      await m.reply(
          e.isEmpty ? "✅ Hạn tốt" : "⚠️ **HẾT HẠN:**\n" + e.join('\n'),
          parseMode: 'Markdown');
    } catch (e) {}
  });

  // --- Báo Cáo ---
  teledart.onMessage(keyword: '📥 Báo Cáo Nhập').listen((m) => m.reply(
      '📅 Chọn thời gian:',
      replyMarkup: InlineKeyboardMarkup(inlineKeyboard: [
        [InlineKeyboardButton(text: 'Hôm Nay', callbackData: 'import_today')],
        [InlineKeyboardButton(text: 'Tháng Này', callbackData: 'import_month')]
      ])));
  teledart
      .onMessage(keyword: '📊 Doanh Thu')
      .listen((m) => m.reply('📅 Chọn thời gian:',
          replyMarkup: InlineKeyboardMarkup(inlineKeyboard: [
            [
              InlineKeyboardButton(text: 'Hôm Nay', callbackData: 'stats_today')
            ],
            [
              InlineKeyboardButton(
                  text: 'Tháng Này', callbackData: 'stats_month')
            ]
          ])));

  teledart.onCallbackQuery().listen((q) async {
    if (!q.data!.contains('_')) return;
    DateTime n = DateTime.now(), s, e;
    if (q.data!.endsWith('today')) {
      s = DateTime(n.year, n.month, n.day);
      e = DateTime(n.year, n.month, n.day, 23, 59, 59);
    } else {
      s = DateTime(n.year, n.month, 1);
      e = DateTime(n.year, n.month + 1, 0, 23, 59, 59);
    }
    try {
      teledart.answerCallbackQuery(q.id, text: 'Đang tính...');
      if (q.data!.startsWith('import')) {
        final all = await supabase.from('imports').select().limit(500);
        double t = 0;
        int c = 0;
        DateFormat f = DateFormat('dd/MM/yyyy');
        for (var i in all) {
          try {
            if (f
                .parse(i['created_date'])
                .isAfter(s.subtract(Duration(seconds: 1)))) {
              t += (i['total_cost'] as num).toDouble();
              c++;
            }
          } catch (e) {}
        }
        teledart.sendMessage(q.message!.chat.id,
            "📉 **CHI NHẬP:** ${NumberFormat("#,###").format(t)}đ ($c phiếu)",
            parseMode: 'Markdown');
      } else {
        final r = await supabase
            .from('invoice_details')
            .select(
                'quantity,sell_price,capital_price,invoices!inner(created_date)')
            .gte('invoices.created_date', s.toIso8601String())
            .lte('invoices.created_date', e.toIso8601String());
        double rev = 0, pro = 0;
        for (var i in r) {
          int q = i['quantity'];
          rev += (i['sell_price'] ?? 0) * q;
          pro += ((i['sell_price'] ?? 0) - (i['capital_price'] ?? 0)) * q;
        }
        teledart.sendMessage(q.message!.chat.id,
            "💰 **DOANH THU:** ${NumberFormat("#,###").format(rev)}đ\nLãi: ${NumberFormat("#,###").format(pro)}đ",
            parseMode: 'Markdown');
      }
    } catch (e) {}
  });
}
