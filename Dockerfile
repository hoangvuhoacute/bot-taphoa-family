# 1. Sử dụng môi trường Dart chính chủ
FROM dart:stable AS build

# 2. Thiết lập thư mục làm việc
WORKDIR /app

# 3. Chỉ copy file khai báo thư viện trước (để tận dụng cache)
COPY pubspec.yaml ./

# 4. Tải các thư viện về Server
RUN dart pub get

# 5. Bây giờ mới copy toàn bộ code nguồn vào
COPY . .

# 6. Tải lại thư viện offline một lần nữa để chắc chắn (bước fix lỗi đường dẫn)
RUN dart pub get --offline

# 7. Lệnh chạy Bot
CMD ["dart", "run", "bot.dart"]