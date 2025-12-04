import 'dart:io';
import 'package:teledart/teledart.dart';
import 'package:teledart/model.dart';
import 'package:teledart/telegram.dart';
import 'package:supabase/supabase.dart';
import 'package:intl/intl.dart';

// ==================================================
// 1. CẤU HÌNH (THÔNG TIN CỦA BẠN)
// ==================================================
const String botToken = '8398440437:AAHIbNqxvfkzZ7gXgIaXIZcc0Hu5EjgOF28';
const String supabaseUrl = 'https://jrufrflrvitljuurpdqa.supabase.co';
const String supabaseKey =
    'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImpydWZyZmxydml0bGp1dXJwZHFhIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NjQ4NDk4MTgsImV4cCI6MjA4MDQyNTgxOH0.5_BZ_GdeulTQzHR7J83OVRHLLAmA-ONJG1JxqBh0YuY';

// Thông tin Ngân hàng (Để tạo QR)
const String bankId = 'MB';
const String accountNo = '0829669310';
const String template = 'compact';
const String defaultContent = 'DanViet';

// ==================================================
// 2. CHƯƠNG TRÌNH CHÍNH
// ==================================================
void main() async {
  // --- A. Khởi động Server giả (Để Render không tắt Bot) ---
  try {
    final server = await HttpServer.bind(InternetAddress.anyIPv4,
        int.parse(Platform.environment['PORT'] ?? '8080'));
    server.listen((request) {
      request.response
        ..statusCode = 200
        ..write('Bot is running!')
        ..close();
    });
    print('🌍 Dummy Server đang chạy tại port ${server.port}');
  } catch (e) {
    print('⚠️ Chạy local (không cần server giả)');
  }

  print('🤖 Đang khởi động Bot TapHoa...');

  // --- B. Kết nối Database & Telegram ---
  final supabase = SupabaseClient(supabaseUrl, supabaseKey);
  final username = (await Telegram(botToken).getMe()).username;
  var teledart = TeleDart(botToken, Event(username!));

  teledart.start();
  print('✅ Bot $username đang chạy và sẵn sàng phục vụ!');

  // --- C. Tạo Menu Bàn Phím (10 Nút) ---
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

  // --- Lệnh /start ---
  teledart.onCommand('start').listen((message) {
    message.reply('Xin chào chủ tiệm! Chọn chức năng bên dưới:',
        replyMarkup: menuKeyboard);
  });

  // ==================================================
  // 3. TÍNH NĂNG: QR CODE THANH TOÁN
  // ==================================================
  Future<void> sendQrCode(dynamic message) async {
    // Tạo link QR VietQR (Không điền số tiền để khách tự nhập)
    String qrUrl =
        'https://img.vietqr.io/image/$bankId-$accountNo-$template.png?addInfo=$defaultContent';
    try {
      await teledart.sendPhoto(message.chat.id, qrUrl,
          caption: "🏧 **MÃ QR CỬA HÀNG**\n"
              "--------------------------\n"
              "🏦 Ngân hàng: **$bankId**\n"
              "💳 STK: **$accountNo**\n"
              "📝 Nội dung: `$defaultContent`\n\n"
              "👉 **Khách hàng vui lòng tự nhập số tiền.**",
          parseMode: 'Markdown');
    } catch (e) {
      await teledart.sendMessage(message.chat.id, "Lỗi tạo QR: $e");
    }
  }

  // Bắt sự kiện bấm nút hoặc gõ lệnh
  teledart.onMessage(keyword: '💳 Lấy Mã QR').listen((m) => sendQrCode(m));
  teledart.onCommand('qr').listen((m) => sendQrCode(m));

  // ==================================================
  // 4. TÍNH NĂNG: QUẢN LÝ KHO (Xem, Tìm, Check)
  // ==================================================

  // --- Xem Kho ---
  teledart.onMessage(keyword: RegExp(r'(📦 Xem Kho)')).listen((message) async {
    try {
      await message.reply('⏳ Đang tải kho...');
      final data = await supabase
          .from('products')
          .select('name, stock, sell_price, barcode')
          .order('stock', ascending: true);

      if (data.isEmpty) {
        await message.reply('Kho trống!');
        return;
      }

      String response = "📦 **DANH SÁCH KHO:**\n";
      for (var item in data) {
        final stock = item['stock'];
        final barcode = item['barcode'] ?? '---';
        String icon = (stock <= 0) ? "⚫" : (stock <= 5 ? "🔴" : "🟢");
        final price = NumberFormat("#,###", "vi_VN").format(item['sell_price']);

        // Hiển thị: Tên dòng trên, Mã và SL dòng dưới
        String line =
            "$icon **${item['name']}**\n   👉 Mã: `$barcode` | SL: **$stock** | Giá: ${price}đ\n\n";

        if ((response.length + line.length) > 4000) {
          await message.reply(response, parseMode: 'Markdown');
          response = "";
        }
        response += line;
      }
      if (response.isNotEmpty)
        await message.reply(response, parseMode: 'Markdown');
    } catch (e) {
      message.reply("Lỗi: $e");
    }
  });

  // --- Tìm Kiếm ---
  teledart.onMessage(keyword: '🔍 Tìm Kiếm').listen((m) => m.reply(
      '🔎 Gõ lệnh: `/tim [tên]`\nVí dụ: `/tim bánh`',
      parseMode: 'Markdown'));

  teledart.onCommand('tim').listen((message) async {
    final keyword = message.text?.split(' ').sublist(1).join(' ');
    if (keyword == null || keyword.isEmpty) return;

    final data =
        await supabase.from('products').select().ilike('name', '%$keyword%');
    if (data.isEmpty) {
      await message.reply("❌ Không tìm thấy.");
    } else {
      String res = "🔍 **KẾT QUẢ:**\n\n";
      for (var i in data) {
        final p = NumberFormat("#,###").format(i['sell_price']);
        res +=
            "- **${i['name']}**\n  Mã: `${i['barcode'] ?? ''}` | Tồn: **${i['stock']}** | Giá: $p\n\n";
      }
      await message.reply(res, parseMode: 'Markdown');
    }
  });

  // --- Check Hết/Sắp Hết ---
  teledart
      .onMessage(keyword: RegExp(r'(📉 Hết/Sắp Hết)'))
      .listen((message) async {
    try {
      await message.reply('🕵️ Đang kiểm tra...');
      final data = await supabase
          .from('products')
          .select('name, stock')
          .lte('stock', 5)
          .order('stock');

      if (data.isEmpty) {
        await message.reply('✅ Kho ổn định.');
        return;
      }

      String res = "⚠️ **CẦN NHẬP HÀNG:**\n";
      for (var i in data) {
        res +=
            "${i['stock'] <= 0 ? '⚫' : '🔴'} **${i['name']}** (Còn: ${i['stock']})\n";
      }
      await message.reply(res, parseMode: 'Markdown');
    } catch (e) {
      message.reply("Lỗi: $e");
    }
  });

  // --- Check Hạn Sử Dụng ---
  teledart
      .onMessage(keyword: RegExp(r'(⏳ Check Hạn SD)'))
      .listen((message) async {
    try {
      await message.reply('🕵️ Đang quét HSD...');
      final data = await supabase.from('products').select('name, expiry_date');
      List<String> expired = [];
      DateTime now = DateTime.now();
      DateFormat fmt = DateFormat('dd/MM/yyyy');

      for (var i in data) {
        if (i['expiry_date'] == null) continue;
        try {
          if (fmt.parse(i['expiry_date']).isBefore(now)) {
            expired.add("💀 **${i['name']}** (Hết: ${i['expiry_date']})");
          }
        } catch (e) {}
      }

      if (expired.isEmpty)
        await message.reply("✅ Không có hàng hết hạn.");
      else
        await message.reply("⚠️ **ĐÃ HẾT HẠN:**\n" + expired.join('\n'),
            parseMode: 'Markdown');
    } catch (e) {}
  });

  // ==================================================
  // 5. TÍNH NĂNG: BÁO CÁO (Doanh Thu & Nhập)
  // ==================================================
  teledart.onMessage(keyword: '📥 Báo Cáo Nhập').listen((m) {
    m.reply('📅 Chọn thời gian xem chi phí:',
        replyMarkup: InlineKeyboardMarkup(inlineKeyboard: [
          [InlineKeyboardButton(text: 'Hôm Nay', callbackData: 'import_today')],
          [
            InlineKeyboardButton(
                text: 'Tháng Này', callbackData: 'import_month')
          ],
        ]));
  });

  teledart.onMessage(keyword: '📊 Doanh Thu').listen((m) {
    m.reply('📅 Chọn thời gian xem doanh thu:',
        replyMarkup: InlineKeyboardMarkup(inlineKeyboard: [
          [InlineKeyboardButton(text: 'Hôm Nay', callbackData: 'stats_today')],
          [
            InlineKeyboardButton(text: 'Tháng Này', callbackData: 'stats_month')
          ],
        ]));
  });

  teledart.onCallbackQuery().listen((query) async {
    if (!query.data!.contains('_')) return;

    DateTime now = DateTime.now();
    DateTime start, end;
    String title =
        query.data!.endsWith('today') ? "HÔM NAY" : "THÁNG ${now.month}";

    if (query.data!.endsWith('today')) {
      start = DateTime(now.year, now.month, now.day);
      end = DateTime(now.year, now.month, now.day, 23, 59, 59);
    } else {
      start = DateTime(now.year, now.month, 1);
      end = DateTime(now.year, now.month + 1, 0, 23, 59, 59);
    }

    final mf = NumberFormat("#,###", "vi_VN");

    try {
      teledart.answerCallbackQuery(query.id, text: 'Đang tính...');

      if (query.data!.startsWith('import_')) {
        // Báo cáo nhập
        final imports = await supabase
            .from('imports')
            .select('total_cost, created_date')
            .limit(500);
        double total = 0;
        int count = 0;
        DateFormat fmt = DateFormat('dd/MM/yyyy');
        for (var item in imports) {
          try {
            DateTime d = fmt.parse(item['created_date']);
            if (d.isAfter(start.subtract(Duration(seconds: 1))) &&
                d.isBefore(end.add(Duration(seconds: 1)))) {
              total += (item['total_cost'] as num).toDouble();
              count++;
            }
          } catch (e) {}
        }
        teledart.sendMessage(query.message!.chat.id,
            "📉 **CHI PHÍ NHẬP $title**\n------------------\n💸 Tổng chi: **${mf.format(total)} đ**\n📝 Số phiếu: $count",
            parseMode: 'Markdown');
      } else {
        // Báo cáo bán (stats_)
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
        teledart.sendMessage(query.message!.chat.id,
            "💰 **DOANH THU $title**\n------------------\n💵 Thu: **${mf.format(rev)} đ**\n📈 Lãi: **${mf.format(prof)} đ**",
            parseMode: 'Markdown');
      }
    } catch (e) {
      teledart.sendMessage(query.message!.chat.id, "Lỗi: $e");
    }
  });

  // ==================================================
  // 6. CÁC LỆNH NHẬP & SỬA (Logic chi tiết)
  // ==================================================

  // --- /them [Mã] [SL] ---
  teledart.onCommand('them').listen((m) async {
    final args = m.text?.split(' ');
    if (args == null || args.length < 3) {
      await m.reply("❌ Sai cú pháp. Xem HD.");
      return;
    }

    int? qty = int.tryParse(args.last);
    String id = args.sublist(1, args.length - 1).join(' '); // Tên hoặc Mã

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

      int newStock = (s[0]['stock'] ?? 0) + qty!;
      await supabase
          .from('products')
          .update({'stock': newStock}).eq('id', s[0]['id']);
      await m.reply("✅ Đã thêm $qty. Tồn mới: **$newStock**",
          parseMode: 'Markdown');
    } catch (e) {
      m.reply("Lỗi: $e");
    }
  });

  // --- /nhap [Full] ---
  teledart.onCommand('nhap').listen((m) async {
    final args = m.text?.split(' ');
    if (args == null || args.length < 7) {
      await m.reply("❌ Thiếu thông tin. Xem HD.");
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
        await m.reply("🆕 Đã tạo món mới: **$n**", parseMode: 'Markdown');
      } else {
        id = s['id'];
        oldS = s['stock'] ?? 0;
      }

      // Lưu lịch sử nhập
      final imp = await supabase
          .from('imports')
          .insert({
            'total_cost': ip * q,
            'created_date': DateFormat('dd/MM/yyyy').format(DateTime.now()),
            'supplier': 'Bot Telegram'
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

      // Update kho
      await supabase.from('products').update({
        'stock': oldS + q,
        'import_price': ip,
        'sell_price': sp,
        'expiry_date': exp
      }).eq('id', id);
      await m.reply(
          "✅ Nhập kho thành công!\n📦 **$n**\n📈 Tồn: **${oldS + q}**",
          parseMode: 'Markdown');
    } catch (e) {
      m.reply("Lỗi: $e");
    }
  });

  // --- Các lệnh Sửa ---
  teledart.onCommand('suagia').listen((m) async {
    final a = m.text?.split(' ');
    if (a == null || a.length < 4) {
      await m.reply("❌ Sai cú pháp");
      return;
    }
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
    if (a == null || a.length < 3) {
      await m.reply("❌ Sai cú pháp");
      return;
    }
    try {
      await supabase
          .from('products')
          .update({'expiry_date': a[2]}).eq('barcode', a[1]);
      await m.reply("✅ Đã sửa hạn.");
    } catch (e) {}
  });

  teledart.onCommand('suaten').listen((m) async {
    final a = m.text?.split(' ');
    if (a == null || a.length < 3) return;
    try {
      await supabase
          .from('products')
          .update({'name': a.sublist(2).join(' ')}).eq('barcode', a[1]);
      await m.reply("✅ Đã sửa tên.");
    } catch (e) {}
  });

  teledart.onCommand('chinhkho').listen((m) async {
    final a = m.text?.split(' ');
    if (a == null || a.length < 3) return;
    try {
      final s = await supabase
          .from('products')
          .select()
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

  teledart.onCommand('suama').listen((m) async {
    final a = m.text?.split(' ');
    if (a == null || a.length < 3) return;
    try {
      final s = await supabase
          .from('products')
          .select()
          .or('barcode.eq."${a.sublist(1, a.length - 1).join(' ')}",name.eq."${a.sublist(1, a.length - 1).join(' ')}"')
          .limit(1);
      if (s.isNotEmpty) {
        await supabase
            .from('products')
            .update({'barcode': a.last}).eq('id', s[0]['id']);
        await m.reply("✅ Đã sửa mã.");
      }
    } catch (e) {}
  });

  // --- Hướng Dẫn ---
  teledart.onMessage(keyword: '✏️ HD Sửa Hàng').listen((m) => m.reply(
      '🛠 **SỬA:**\n`/suagia [Mã] [Gốc] [Bán]`\n`/suahan [Mã] [Hạn]`\n`/suaten [Mã] [Tên]`\n`/chinhkho [Mã] [SL]`\n`/suama [Tên] [Mã Mới]`',
      parseMode: 'Markdown'));
  teledart.onMessage(keyword: '➕ HD Nhập Hàng').listen((m) => m.reply(
      '📦 **NHẬP:**\n`/them [Mã] [SL]`\n`/nhap [Mã] [SL] [Gốc] [Bán] [Hạn] [Tên]`',
      parseMode: 'Markdown'));
  teledart.onMessage(keyword: '❓ Trợ Giúp').listen((m) => m.reply(
      '📖 Bấm các nút trên menu để xem chi tiết.',
      parseMode: 'Markdown'));
}
