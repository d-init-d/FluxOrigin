# **FluxOrigin \- AI Book Translator**

**FluxOrigin** là một ứng dụng Desktop (Windows) mạnh mẽ hỗ trợ dịch sách, tài liệu tự động sử dụng sức mạnh của AI cục bộ (Local LLM).

Đây là phiên bản kế thừa và nâng cấp toàn diện từ dự án **n8n book translator**. FluxOrigin loại bỏ sự phụ thuộc vào các workflow phức tạp của n8n để mang lại một trải nghiệm "Cài đặt là chạy" (All-in-one) với giao diện người dùng trực quan, tốc độ xử lý nhanh hơn và khả năng tùy biến cao hơn.

## **🌟 Tính Năng Nổi Bật**

So với phiên bản n8n cũ, FluxOrigin mang lại những cải tiến vượt bậc:

* **Ứng dụng Native (Flutter):** Không còn cần cài đặt Docker, Node.js hay n8n server. Chỉ cần một file cài đặt .exe duy nhất.  
* **Tích hợp Ollama sâu:** Kết nối trực tiếp với Ollama (localhost) để sử dụng các model AI mới nhất hoàn toàn miễn phí và offline.  
* **Quản lý Từ điển (Dictionary/Glossary):** Cho phép tải lên và quản lý các thuật ngữ chuyên ngành, tên riêng để đảm bảo sự nhất quán trong bản dịch (tính năng mà n8n rất khó xử lý).  
* **Xử lý văn bản thông minh:** Tự động chia nhỏ (chunking) văn bản thông minh để tránh giới hạn token của AI mà vẫn giữ được ngữ cảnh.  
* **Lịch sử dịch thuật:** Tự động lưu lại các bản dịch trước đó để xem lại bất cứ lúc nào.  
* **Hỗ trợ tìm kiếm Web (Web Search):** (Experimental) Tích hợp khả năng tìm kiếm thông tin bổ sung để AI hiểu rõ ngữ cảnh hơn khi dịch.

## **🚀 Yêu Cầu Hệ Thống**

1. **Hệ điều hành:** Windows 10/11 (64-bit).  
2. **Ollama:** Bạn cần cài đặt và chạy [Ollama](https://ollama.com/) trên máy tính.  
3. **RAM:** Khuyến nghị 8GB trở lên (để chạy mượt các model AI).

## **📦 Cài Đặt**

### **Cách 1: Sử dụng bộ cài đặt (Khuyên dùng)**

Truy cập thư mục releases trong mã nguồn và chạy file cài đặt:  
FluxOrigin\_Installer\_v1.0.1.exe

### **Cách 2: Chạy từ mã nguồn (Dành cho Developer)**

Nếu bạn muốn chỉnh sửa code:

1. Cài đặt [Flutter SDK](https://flutter.dev/docs/get-started/install).  
2. Clone repository này.  
3. Mở terminal tại thư mục gốc dự án.  
4. Chạy lệnh:  
   flutter pub get  
   flutter run \-d windows

## **📖 Hướng Dẫn Sử Dụng**

### **Bước 1: Cấu hình AI**

1. Mở ứng dụng FluxOrigin.  
2. Vào mục **Cài đặt (Settings)** ở thanh bên trái.  
3. Nhập URL của Ollama (mặc định là http://localhost:11434).  
4. Nhấn "Kiểm tra kết nối" để đảm bảo Ollama đang chạy.  
5. Chọn Model bạn muốn dùng.

#### **🧩 Gợi Ý Chọn Model AI**

Dưới đây là danh sách các model được tối ưu sẵn trong ứng dụng. Hãy chọn model phù hợp với cấu hình phần cứng (RAM/VRAM) của bạn:

| Model | Lệnh Ollama | Yêu cầu VRAM | Tốc độ | Chất lượng | Tiếng Việt | Phù hợp cho |
| :---- | :---- | :---- | :---- | :---- | :---- | :---- |
| **Qwen2.5-0.5B** | qwen2.5:0.5b | 1GB | 20 tokens/s | ⭐ | Kém | Máy rất yếu |
| **Qwen2.5-1B** | qwen2.5:1b | 2GB | 30 tokens/s | ⭐⭐ | Bình thường | Máy yếu |
| **Qwen2.5-3B** | qwen2.5:3b | 4GB | 40 tokens/s | ⭐⭐⭐ | Tốt | Máy vừa |
| **Qwen2.5-7B** | qwen2.5:7b | 6GB | 60 tokens/s | ⭐⭐⭐⭐ | Tốt | Máy vừa-khá |
| **Llama3.1-8B** | llama2:8b | 8GB | 80 tokens/s | ⭐⭐⭐⭐ | Rất Tốt | Máy khá |
| **Qwen3-8B** | qwen3:8b | 8GB | 90 tokens/s | ⭐⭐⭐⭐⭐ | Rất Tốt | Máy khá |
| **Qwen3-14B** | qwen3:14b | 16GB | 120 tokens/s | ⭐⭐⭐⭐⭐ | Xuất Sắc | Máy mạnh |
| **Qwen3-30B-A3B** | qwen3:30b | 16GB | 150 tokens/s | ⭐⭐⭐⭐⭐ | Xuất Sắc | Máy mạnh |

### **Bước 2: Chuẩn bị Từ điển (Tùy chọn)**

1. Vào mục **Từ điển (Dictionary)**.  
2. Thêm các từ khóa hoặc upload file từ điển để AI tuân thủ theo cách dịch của bạn (Ví dụ: "FluxOrigin" \-\> "FluxOrigin" thay vì dịch nghĩa đen).

### **Bước 3: Dịch thuật**

1. Vào màn hình chính **Dịch thuật**.  
2. Tải lên file cần dịch (Hỗ trợ .txt, .md, ...).  
3. Chọn ngôn ngữ đích (Target Language).  
4. Nhấn **Bắt đầu dịch**.  
5. Theo dõi tiến trình và nhận kết quả ngay trên màn hình.

## **🏗️ Cấu Trúc Dự Án**

Dự án được viết bằng **Flutter (Dart)** với cấu trúc Clean Architecture cơ bản:


* lib/ui/: Chứa giao diện người dùng (Screens, Widgets).  
* lib/services/: Xử lý logic gọi API (AiService, WebSearchService).  
* lib/controllers/: Quản lý trạng thái ứng dụng (TranslationController).  
* lib/utils/: Các công cụ hỗ trợ xử lý text và file.  
* lib/models/: Định nghĩa dữ liệu (TranslationProgress, v.v.).

## **🤝 Đóng Góp**

Dự án này được phát triển tiếp từ ý tưởng của **n8n book translator**. Mọi đóng góp, báo lỗi (Issue) hoặc yêu cầu tính năng (Pull Request) đều được hoan nghênh.

Developed with ❤️ by **d-init-d**