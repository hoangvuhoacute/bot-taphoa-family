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
  final server = await HttpServer.bind(InternetAddress.anyIPv4,
      int.parse(Platform.environment['PORT'] ?? '8080'));
  server.listen((request) {
    request.response
      ..statusCode = 200
      ..write('Bot is running OK!')
      ..close();
  });
  print('🌍 Dummy Server đang chạy tại port ${server.port}');

  print('🤖 Đang khởi động Bot ');

  final supabase = SupabaseClient(supabaseUrl, supabaseKey);
  final username = (await Telegram(botToken).getMe()).username;
  var teledart = TeleDart(botToken, Event(username!));

  teledart.start();
  print('✅ Bot $username đang chạy!');

  // --- MENU CHÍNH ---
  final menuKeyboard = ReplyKeyboardMarkup(
    keyboard: [
      [KeyboardButton(text: '📦 Xem Kho'), KeyboardButton(text: '🔍 Tìm Kiếm')],
      [
        KeyboardButton(text: '📊 Báo Cáo'),
        KeyboardButton(text: '⏳ Check Hạn SD')
      ],
      [KeyboardButton(text: '❓ Hướng dẫn')],
    ],
    resizeKeyboard: true,
  );

  teledart.onCommand('start').listen((message) {
    message.reply('Xin chào! Chọn chức năng:', replyMarkup: menuKeyboard);
  });

  // ==================================================
  // 🚀 LỆNH NHẬP HÀNG MỚI (Full tính năng)
  // Cú pháp: /nhap [Mã] [SL] [GiáNhập] [GiáBán] [HạnSD] [Tên]
  // ==================================================
  teledart.onCommand('nhap').listen((message) async {
    final args = message.text?.split(' ');

    // Kiểm tra đủ thông tin chưa (ít nhất 6 tham số + lệnh = 7 phần)
    if (args == null || args.length < 7) {
      await message.reply(
          "❌ **Sai cú pháp!**\n\n"
          "Gõ theo thứ tự:\n"
          "`/nhap [Mã] [SL] [GiáNhập] [GiáBán] [HạnSD] [Tên]`\n\n"
          "Ví dụ:\n"
          "`/nhap 893123 10 15000 20000 31/12/2025 Bánh Quy Bơ`",
          parseMode: 'Markdown');
      return;
    }

    try {
      // 1. Phân tích dữ liệu từ tin nhắn
      String barcode = args[1];
      int qty = int.tryParse(args[2]) ?? 0;
      double importPrice = double.tryParse(args[3]) ?? 0;
      double sellPrice = double.tryParse(args[4]) ?? 0;
      String expiryDate = args[5]; // Giữ nguyên dạng chuỗi dd/MM/yyyy
      String name = args.sublist(6).join(' '); // Ghép phần tên lại

      if (qty <= 0) {
        await message.reply("❌ Số lượng phải lớn hơn 0");
        return;
      }

      await message.reply("⏳ Đang xử lý nhập hàng...");

      // 2. Tìm xem sản phẩm đã có chưa
      final search = await supabase
          .from('products')
          .select()
          .eq('barcode', barcode)
          .maybeSingle();

      int productId;
      int currentStock = 0;

      if (search == null) {
        // --- CHƯA CÓ -> TẠO MỚI ---
        final newProduct = await supabase
            .from('products')
            .insert({
              'barcode': barcode,
              'name': name,
              'category_id': 1, // Mặc định danh mục 1
              'import_price': importPrice,
              'sell_price': sellPrice,
              'stock': 0, // Sẽ cộng sau
              'expiry_date': expiryDate,
              'created_date': DateTime.now().toIso8601String(),
            })
            .select()
            .single();

        productId = newProduct['id'];
        await message.reply("🆕 Đã tạo sản phẩm mới: **$name**",
            parseMode: 'Markdown');
      } else {
        // --- ĐÃ CÓ -> LẤY ID ---
        productId = search['id'];
        currentStock = search['stock'] ?? 0;
        // Nếu người dùng nhập tên khác, có thể update tên luôn (tuỳ chọn)
        // Ở đây ta ưu tiên cập nhật giá và hạn sử dụng
      }

      // 3. Tạo Phiếu Nhập (Để lưu lịch sử)
      final importRecord = await supabase
          .from('imports')
          .insert({
            'total_cost': importPrice * qty,
            'created_date': DateFormat('dd/MM/yyyy').format(DateTime.now()),
            'supplier': 'Nhập qua Bot Telegram',
            'invoice_image_url': null // Không cần ảnh
          })
          .select()
          .single();

      // 4. Tạo Chi Tiết Nhập
      await supabase.from('import_details').insert({
        'import_id': importRecord['id'],
        'product_id': productId,
        'product_name': name,
        'quantity': qty,
        'import_price': importPrice,
        'expiry_date': expiryDate,
        'manufacturing_date': '' // Bỏ trống
      });

      // 5. Cập nhật Tồn Kho & Giá Mới vào bảng Products
      int newStock = currentStock + qty;
      await supabase.from('products').update({
        'stock': newStock,
        'import_price': importPrice, // Cập nhật giá nhập mới nhất
        'sell_price': sellPrice, // Cập nhật giá bán mới nhất
        'expiry_date': expiryDate // Cập nhật hạn sử dụng mới nhất
      }).eq('id', productId);

      // 6. Thông báo thành công
      final money = NumberFormat("#,###", "vi_VN");
      await message.reply(
          "✅ **NHẬP KHO THÀNH CÔNG!**\n"
          "📦 **$name**\n"
          "--------------------\n"
          "➕ Nhập thêm: **$qty**\n"
          "📈 Tồn kho mới: **$newStock**\n"
          "💰 Giá bán mới: ${money.format(sellPrice)} đ\n"
          "📅 Hạn SD: $expiryDate",
          parseMode: 'Markdown');
    } catch (e) {
      await message.reply("❌ Lỗi: $e");
    }
  });

  // ==========================================
  // CÁC TÍNH NĂNG KHÁC (Giữ nguyên)
  // ==========================================

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
            "$icon **${item['name']}**\n   └ Mã: `$barcode` | SL: **$stock** | Giá: ${price}\n\n";
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
      DateTime now = DateTime.now();
      DateFormat fmt = DateFormat('dd/MM/yyyy');
      for (var i in data) {
        if (i['expiry_date'] == null) continue;
        try {
          DateTime d = fmt.parse(i['expiry_date']);
          if (d.isBefore(now))
            exp.add("💀 ${i['name']} (Hết: ${i['expiry_date']})");
          else if (d.difference(now).inDays <= 30)
            exp.add("⚠️ ${i['name']} (Còn ${d.difference(now).inDays} ngày)");
        } catch (e) {}
      }
      if (exp.isEmpty)
        await message.reply("✅ Không có hàng hết hạn.");
      else
        await message.reply("⚠️ **CẢNH BÁO HẠN SD:**\n\n${exp.join('\n')}",
            parseMode: 'Markdown');
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

  teledart.onMessage(keyword: '❓ Hướng dẫn').listen((message) {
    message.reply(
        '📖 **CÁCH NHẬP HÀNG:**\n'
        '`/nhap [Mã] [SL] [GiáNhập] [GiáBán] [Hạn] [Tên]`\n\n'
        'Ví dụ:\n`/nhap 893123 10 15000 20000 31/12/2025 Bánh Quy`',
        parseMode: 'Markdown');
  });
}
