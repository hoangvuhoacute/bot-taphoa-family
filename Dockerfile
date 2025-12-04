# Sử dụng môi trường Dart chính chủ
FROM dart:stable AS build

# Thiết lập thư mục làm việc
WORKDIR /app

# Copy file cấu hình và tải thư viện
COPY pubspec.* ./
RUN dart pub get

# Copy toàn bộ code vào
COPY . .

# Chạy Bot
CMD ["dart", "run", "bot.dart"]