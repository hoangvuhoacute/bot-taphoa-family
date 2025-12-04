import 'dart:io';
import 'package:teledart/teledart.dart';
import 'package:teledart/model.dart';
import 'package:teledart/telegram.dart';
import 'package:supabase/supabase.dart';
import 'package:intl/intl.dart';

const String botToken = '8398440437:AAHIbNqxvfkzZ7gXgIaXIZcc0Hu5EjgOF28';

const String supabaseUrl =
    'https://jrufrflrvitljuurpdqa.supabase.co'; // Ví dụ: https://xyz.supabase.co

const String supabaseKey =
    'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImpydWZyZmxydml0bGp1dXJwZHFhIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NjQ4NDk4MTgsImV4cCI6MjA4MDQyNTgxOH0.5_BZ_GdeulTQzHR7J83OVRHLLAmA-ONJG1JxqBh0YuY'; // Key dài loằng ngoằng

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
  // ----------------------------------------

  print('🤖 Đang khởi động Bot...');

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
        KeyboardButton(text: '➕ HD Nhập Hàng'),
        KeyboardButton(text: '✏️ HD Sửa Hàng')
      ],
      [
        KeyboardButton(text: '📊 Báo Cáo'),
        KeyboardButton(text: '⏳ Check Hạn SD')
      ],
      [KeyboardButton(text: '🔍 Tìm Kiếm'), KeyboardButton(text: '❓ Trợ Giúp')],
    ],
    resizeKeyboard: true,
  );

  teledart.onCommand('start').listen((message) {
    message.reply('Xin chào chủ tiệm! Chọn chức năng bên dưới:',
        replyMarkup: menuKeyboard);
  });

  // ==========================================
  // 1. TÍNH NĂNG: CHECK HẾT HÀNG / SẮP HẾT
  // ==========================================
  teledart
      .onMessage(
          keyword:
              RegExp(r'(📉 Hết/Sắp Hết)|(\/checkhet)', caseSensitive: false))
      .listen((message) async {
    try {
      await message.reply('🕵️ Đang tìm hàng cần nhập...');

      final data = await supabase
          .from('products')
          .select('name, stock, barcode')
          .lte('stock', 5)
          .order('stock', ascending: true);

      if (data.isEmpty) {
        await message.reply('✅ Kho hàng ổn định! Không có món nào sắp hết.');
        return;
      }

      List<String> outOfStock = [];
      List<String> lowStock = [];

      for (var item in data) {
        int stock = item['stock'];
        String name = item['name'];
        String code = item['barcode'] ?? '---';

        if (stock <= 0) {
          outOfStock.add("⚫ **$name** (Mã: `$code`)");
        } else {
          lowStock.add("🔴 **$name** (Còn: **$stock** - Mã: `$code`)");
        }
      }

      String response = "";
      if (outOfStock.isNotEmpty) {
        response += "🚨 **HẾT HÀNG (${outOfStock.length} món):**\n" +
            outOfStock.join('\n') +
            "\n\n";
      }
      if (lowStock.isNotEmpty) {
        response +=
            "⚠️ **SẮP HẾT (${lowStock.length} món):**\n" + lowStock.join('\n');
      }

      await message.reply(response, parseMode: 'Markdown');
    } catch (e) {
      await message.reply("Lỗi: $e");
    }
  });

  // ==========================================
  // 2. TÍNH NĂNG: HƯỚNG DẪN NHẬP HÀNG
  // ==========================================
  teledart.onMessage(keyword: '➕ HD Nhập Hàng').listen((message) {
    message.reply(
        '📦 **HƯỚNG DẪN NHẬP HÀNG**\n'
        '(Chạm vào lệnh để copy)\n\n'
        '1️⃣ **Nhập Thêm (Cộng dồn):**\n'
        '`/them [Mã] [Số lượng]`\n'
        'VD: `/them 893123 10`\n\n'
        '2️⃣ **Tạo Mới / Nhập Full:**\n'
        '`/nhap [Mã] [SL] [GiáGốc] [GiáBán] [Hạn] [Tên]`\n'
        'VD: `/nhap 893123 20 10000 12000 31/12/2025 Bánh Quy`',
        parseMode: 'Markdown');
  });

  // ==========================================
  // 3. TÍNH NĂNG: HƯỚNG DẪN SỬA HÀNG
  // ==========================================
  teledart.onMessage(keyword: '✏️ HD Sửa Hàng').listen((message) {
    message.reply(
        '🛠 **HƯỚNG DẪN SỬA THÔNG TIN**\n'
        '(Chạm vào lệnh để copy)\n\n'
        '✏️ **Sửa Tên:**\n'
        '`/suaten [Mã] [Tên Mới]`\n'
        'VD: `/suaten 893123 Bánh Gạo Cay`\n\n'
        '🔢 **Sửa Tồn Kho (Set cứng):**\n'
        '`/chinhkho [Mã] [Số Thực Tế]`\n'
        'VD: `/chinhkho 893123 5`\n\n'
        '🏷 **Sửa Mã Vạch:**\n'
        '`/suama [Tên hoặc Mã Cũ] [Mã Mới]`\n'
        'VD: `/suama Bánh_Quy 893999`',
        parseMode: 'Markdown');
  });

  // ==========================================
  // 4. CÁC LỆNH XỬ LÝ LOGIC (Nhập, Sửa...)
  // ==========================================

  // --- Lệnh /them ---
  teledart.onCommand('them').listen((message) async {
    final args = message.text?.split(' ');
    if (args == null || args.length < 3) {
      await message.reply("❌ Sai cú pháp. Xem lại nút [➕ HD Nhập Hàng]");
      return;
    }

    int? qty = int.tryParse(args.last);
    if (qty == null) {
      await message.reply("Số lượng phải là số.");
      return;
    }
    String id = args.sublist(1, args.length - 1).join(' ');

    try {
      final search = await supabase
          .from('products')
          .select()
          .or('barcode.eq."$id",name.eq."$id"')
          .limit(1);
      if (search.isEmpty) {
        await message.reply("❌ Không tìm thấy: $id");
        return;
      }

      final p = search[0];
      int newStock = (p['stock'] ?? 0) + qty;
      await supabase
          .from('products')
          .update({'stock': newStock}).eq('id', p['id']);
      await message.reply(
          "✅ Đã nhập thêm $qty cho **${p['name']}**. Tồn mới: **$newStock**",
          parseMode: 'Markdown');
    } catch (e) {
      await message.reply("Lỗi: $e");
    }
  });

  // --- Lệnh /nhap ---
  teledart.onCommand('nhap').listen((message) async {
    final args = message.text?.split(' ');
    if (args == null || args.length < 7) {
      await message.reply("❌ Thiếu thông tin. Xem lại nút [➕ HD Nhập Hàng]");
      return;
    }

    try {
      String barcode = args[1];
      int qty = int.tryParse(args[2]) ?? 0;
      double importPrice = double.tryParse(args[3]) ?? 0;
      double sellPrice = double.tryParse(args[4]) ?? 0;
      String expiry = args[5];
      String name = args.sublist(6).join(' ');

      final search = await supabase
          .from('products')
          .select()
          .eq('barcode', barcode)
          .maybeSingle();
      int pid;
      int oldStock = 0;

      if (search == null) {
        final newP = await supabase
            .from('products')
            .insert({
              'barcode': barcode,
              'name': name,
              'stock': 0,
              'category_id': 1,
              'import_price': importPrice,
              'sell_price': sellPrice,
              'expiry_date': expiry,
              'created_date': DateTime.now().toIso8601String()
            })
            .select()
            .single();
        pid = newP['id'];
        await message.reply("🆕 Đã tạo món mới: **$name**",
            parseMode: 'Markdown');
      } else {
        pid = search['id'];
        oldStock = search['stock'] ?? 0;
      }

      final imp = await supabase
          .from('imports')
          .insert({
            'total_cost': importPrice * qty,
            'created_date': DateFormat('dd/MM/yyyy').format(DateTime.now()),
            'supplier': 'Bot Telegram'
          })
          .select()
          .single();

      await supabase.from('import_details').insert({
        'import_id': imp['id'],
        'product_id': pid,
        'product_name': name,
        'quantity': qty,
        'import_price': importPrice,
        'expiry_date': expiry
      });

      int newStock = oldStock + qty;
      await supabase.from('products').update({
        'stock': newStock,
        'import_price': importPrice,
        'sell_price': sellPrice,
        'expiry_date': expiry
      }).eq('id', pid);

      await message.reply(
          "✅ Nhập kho thành công!\n📦 **$name**\n📈 Tồn: **$newStock**",
          parseMode: 'Markdown');
    } catch (e) {
      await message.reply("Lỗi: $e");
    }
  });

  // --- Lệnh /suaten ---
  teledart.onCommand('suaten').listen((message) async {
    final args = message.text?.split(' ');
    if (args == null || args.length < 3) {
      await message.reply("❌ Sai cú pháp.");
      return;
    }
    try {
      String code = args[1];
      String newName = args.sublist(2).join(' ');
      await supabase
          .from('products')
          .update({'name': newName}).eq('barcode', code);
      await message.reply("✏️ Đã đổi tên thành: **$newName**",
          parseMode: 'Markdown');
    } catch (e) {
      await message.reply("Lỗi: $e");
    }
  });

  // --- Lệnh /chinhkho ---
  teledart.onCommand('chinhkho').listen((message) async {
    final args = message.text?.split(' ');
    if (args == null || args.length < 3) {
      await message.reply("❌ Sai cú pháp.");
      return;
    }
    try {
      int? stock = int.tryParse(args.last);
      if (stock == null) return;
      String id = args.sublist(1, args.length - 1).join(' ');

      final search = await supabase
          .from('products')
          .select()
          .or('barcode.eq."$id",name.eq."$id"')
          .limit(1);
      if (search.isEmpty) {
        await message.reply("Không tìm thấy.");
        return;
      }

      await supabase
          .from('products')
          .update({'stock': stock}).eq('id', search[0]['id']);
      await message.reply(
          "✏️ Đã sửa tồn kho **${search[0]['name']}** thành: **$stock**",
          parseMode: 'Markdown');
    } catch (e) {
      await message.reply("Lỗi: $e");
    }
  });

  // --- Lệnh /suama ---
  teledart.onCommand('suama').listen((message) async {
    final args = message.text?.split(' ');
    if (args == null || args.length < 3) {
      await message.reply("❌ Sai cú pháp.");
      return;
    }
    try {
      String newCode = args.last;
      String id = args.sublist(1, args.length - 1).join(' ');
      final search = await supabase
          .from('products')
          .select()
          .or('barcode.eq."$id",name.eq."$id"')
          .limit(1);
      if (search.isEmpty) {
        await message.reply("Không tìm thấy.");
        return;
      }

      await supabase
          .from('products')
          .update({'barcode': newCode}).eq('id', search[0]['id']);
      await message.reply("✏️ Đã cập nhật mã mới: `$newCode`",
          parseMode: 'Markdown');
    } catch (e) {
      await message.reply("Lỗi: $e");
    }
  });

  // --- Xem Kho ---
  teledart
      .onMessage(keyword: RegExp(r'(📦 Xem Kho)|(\/kho)', caseSensitive: false))
      .listen((message) async {
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
        String icon = (stock == 0) ? "⚫" : (stock <= 5 ? "🔴" : "🟢");
        final price = NumberFormat("#,###", "vi_VN").format(item['sell_price']);
        String line =
            "$icon **${item['name']}**\n   └ Mã: `$barcode` | SL: **$stock** | Giá: ${price}đ\n\n";

        if ((response.length + line.length) > 4000) {
          await message.reply(response, parseMode: 'Markdown');
          response = "";
        }
        response += line;
      }
      if (response.isNotEmpty)
        await message.reply(response, parseMode: 'Markdown');
    } catch (e) {
      await message.reply("Lỗi: $e");
    }
  });

  // --- Tìm Kiếm ---
  teledart
      .onMessage(keyword: '🔍 Tìm Kiếm')
      .listen((m) => m.reply('Gõ: `/tim [tên]`'));
  teledart.onCommand('tim').listen((message) async {
    final k = message.text?.split(' ').sublist(1).join(' ');
    if (k == null || k.isEmpty) return;
    final data = await supabase.from('products').select().ilike('name', '%$k%');
    String res = data.isEmpty ? "Không thấy." : "🔍 **KẾT QUẢ:**\n";
    for (var i in data) res += "- ${i['name']} | Tồn: ${i['stock']}\n";
    await message.reply(res, parseMode: 'Markdown');
  });

  // --- Báo Cáo ---
  teledart
      .onMessage(keyword: RegExp(r'(📊 Báo Cáo)', caseSensitive: false))
      .listen((message) {
    message.reply('📅 Chọn báo cáo:',
        replyMarkup: InlineKeyboardMarkup(inlineKeyboard: [
          [InlineKeyboardButton(text: 'Hôm nay', callbackData: 'stats_today')],
          [
            InlineKeyboardButton(text: 'Tháng này', callbackData: 'stats_month')
          ],
        ]));
  });

  teledart.onCallbackQuery().listen((query) async {
    if (!query.data!.startsWith('stats_')) return;
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
          "📊 **KẾT QUẢ:**\n💰 Doanh thu: ${mf.format(rev)}đ\n📈 Lợi nhuận: ${mf.format(prof)}đ",
          parseMode: 'Markdown');
    } catch (e) {
      teledart.sendMessage(query.message!.chat.id, "Lỗi: $e");
    }
  });

  // --- Check Hạn ---
  teledart
      .onMessage(keyword: RegExp(r'(⏳ Check Hạn SD)', caseSensitive: false))
      .listen((message) async {
    try {
      await message.reply('🕵️ Đang quét...');
      final data =
          await supabase.from('products').select('name, expiry_date, stock');
      List<String> exp = [];
      List<String> near = [];
      DateTime now = DateTime.now();
      DateFormat fmt = DateFormat('dd/MM/yyyy');
      for (var i in data) {
        if (i['expiry_date'] == null) continue;
        try {
          DateTime d = fmt.parse(i['expiry_date']);
          if (d.isBefore(now))
            exp.add("💀 ${i['name']} (Hết: ${i['expiry_date']})");
          else if (d.difference(now).inDays <= 30)
            near.add("⚠️ ${i['name']} (Còn ${d.difference(now).inDays} ngày)");
        } catch (e) {}
      }
      String resp = "";
      if (exp.isNotEmpty)
        resp += "❌ **ĐÃ HẾT HẠN:**\n" + exp.join('\n') + "\n\n";
      if (near.isNotEmpty) resp += "🟠 **SẮP HẾT HẠN:**\n" + near.join('\n');
      if (resp.isEmpty) resp = "✅ Hạn sử dụng tốt.";
      await message.reply(resp, parseMode: 'Markdown');
    } catch (e) {
      await message.reply("Lỗi: $e");
    }
  });

  teledart.onMessage(keyword: '❓ Trợ Giúp').listen((message) {
    message.reply(
        '📖 Bấm vào các nút trên Menu để xem hướng dẫn chi tiết từng phần.',
        parseMode: 'Markdown');
  });
}
