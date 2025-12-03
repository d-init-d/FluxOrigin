# FluxOrigin - AI Book Translator

<p align="center">
  <img src="https://img.shields.io/badge/Platform-Windows-blue?style=flat-square" alt="Platform">
  <img src="https://img.shields.io/badge/Flutter-3.x-02569B?style=flat-square&logo=flutter" alt="Flutter">
  <img src="https://img.shields.io/badge/License-MIT-green?style=flat-square" alt="License">
</p>

**FluxOrigin** là một ứng dụng Desktop (Windows) mạnh mẽ hỗ trợ dịch sách, tài liệu tự động sử dụng sức mạnh của AI cục bộ (Local LLM).

Đây là phiên bản kế thừa và nâng cấp toàn diện từ dự án **n8n book translator**. FluxOrigin loại bỏ sự phụ thuộc vào các workflow phức tạp của n8n để mang lại một trải nghiệm "Cài đặt là chạy" (All-in-one) với giao diện người dùng trực quan, tốc độ xử lý nhanh hơn và khả năng tùy biến cao hơn.

---

## 🌟 Tính Năng Nổi Bật

So với phiên bản n8n cũ, FluxOrigin mang lại những cải tiến vượt bậc:

| Tính năng                     | Mô tả                                                                                  |
| ----------------------------- | -------------------------------------------------------------------------------------- |
| **Ứng dụng Native (Flutter)** | Không còn cần cài đặt Docker, Node.js hay n8n server. Chỉ cần một file `.exe` duy nhất |
| **Hỗ trợ đa AI Provider**     | Tích hợp **Ollama** và **LM Studio** - linh hoạt chọn nguồn AI phù hợp                 |
| **Quản lý Từ điển**           | Tải lên và quản lý thuật ngữ chuyên ngành, tên riêng để đảm bảo sự nhất quán           |
| **Xử lý văn bản thông minh**  | Tự động chia nhỏ (chunking) văn bản để tránh giới hạn token mà vẫn giữ ngữ cảnh        |
| **Live Translation Preview**  | Xem trực tiếp AI đang dịch đoạn nào và kết quả dịch real-time                          |
| **Dev Logs**                  | Tab dành cho developer xem chi tiết requests, responses và debug logs                  |
| **Lịch sử dịch thuật**        | Tự động lưu lại các bản dịch trước đó để xem lại bất cứ lúc nào                        |
| **Web Search (Experimental)** | Tích hợp tìm kiếm thông tin bổ sung để AI hiểu rõ ngữ cảnh hơn                         |

---

## 🚀 Yêu Cầu Hệ Thống

-   **Hệ điều hành:** Windows 10/11 (64-bit)
-   **AI Backend:** [Ollama](https://ollama.com/) hoặc [LM Studio](https://lmstudio.ai/)
-   **RAM:** Khuyến nghị 8GB trở lên (để chạy mượt các model AI)

---

## 📦 Cài Đặt

### Cách 1: Sử dụng bộ cài đặt (Khuyên dùng)

Truy cập thư mục `releases` trong mã nguồn và chạy file cài đặt:

```
FluxOrigin_Installer_v1.0.1.exe
```

### Cách 2: Chạy từ mã nguồn (Dành cho Developer)

```bash
# 1. Clone repository
git clone https://github.com/tmih06/FluxOrigin.git
cd FluxOrigin

# 2. Cài đặt dependencies
flutter pub get

# 3. Chạy ứng dụng
flutter run -d windows
```

---

## 📖 Hướng Dẫn Sử Dụng

### Bước 1: Cấu hình AI

1. Mở ứng dụng FluxOrigin
2. Vào mục **Cài đặt (Settings)** ở thanh bên trái
3. Chọn **AI Provider**: Ollama hoặc LM Studio
4. Nhập URL của server:
    - Ollama: `http://localhost:11434` (mặc định)
    - LM Studio: `http://localhost:1234` (mặc định)
5. Nhấn **"Kiểm tra kết nối"** để đảm bảo server đang chạy
6. Chọn Model bạn muốn dùng từ danh sách

### 🧩 Gợi Ý Chọn Model AI

> **Lưu ý:** Các model dưới đây hoạt động tốt trên cả **Ollama** và **LM Studio**. Tải model từ Ollama bằng lệnh `ollama pull <tên>`, hoặc tải file GGUF từ HuggingFace cho LM Studio.

#### 📊 Bảng So Sánh Model Theo Cấu Hình

| Model | Ollama | VRAM | Chất lượng dịch | Tiếng Việt | Phù hợp |
|-------|--------|------|-----------------|------------|---------|
| **Qwen2.5-0.5B** | `qwen2.5:0.5b` | ~1GB | ⭐ | Kém | Máy yếu, test nhanh |
| **Qwen2.5-1.5B** | `qwen2.5:1.5b` | ~2GB | ⭐⭐ | Trung bình | Máy yếu |
| **Qwen2.5-3B** | `qwen2.5:3b` | ~3GB | ⭐⭐⭐ | Khá | Máy phổ thông |
| **Gemma3-4B** | `gemma3:4b` | ~4GB | ⭐⭐⭐ | Khá | Máy phổ thông |
| **Qwen2.5-7B** | `qwen2.5:7b` | ~5GB | ⭐⭐⭐⭐ | Tốt | Máy vừa (8GB VRAM) |
| **Qwen3-8B** | `qwen3:8b` | ~6GB | ⭐⭐⭐⭐⭐ | Rất tốt | Máy khá (8-12GB VRAM) |
| **Llama3.1-8B** | `llama3.1:8b` | ~6GB | ⭐⭐⭐⭐ | Tốt | Máy khá |
| **Gemma3-12B** | `gemma3:12b` | ~9GB | ⭐⭐⭐⭐⭐ | Rất tốt | Máy khá (12GB VRAM) |
| **Qwen3-14B** | `qwen3:14b` | ~10GB | ⭐⭐⭐⭐⭐ | Xuất sắc | Máy mạnh (16GB VRAM) |
| **Qwen2.5-14B** | `qwen2.5:14b` | ~10GB | ⭐⭐⭐⭐⭐ | Xuất sắc | Máy mạnh |
| **Gemma3-27B** | `gemma3:27b` | ~18GB | ⭐⭐⭐⭐⭐ | Xuất sắc | Máy cao cấp (24GB VRAM) |
| **Qwen3-30B-A3B** | `qwen3:30b-a3b` | ~20GB | ⭐⭐⭐⭐⭐ | Xuất sắc | Máy cao cấp (MoE) |
| **Llama3.3-70B** | `llama3.3:70b` | ~42GB | ⭐⭐⭐⭐⭐ | Xuất sắc | Máy workstation |

#### 🎯 Khuyến Nghị Theo Mục Đích

| Mục đích | Model đề xuất | Lý do |
|----------|---------------|-------|
| **Dịch tiểu thuyết Trung → Việt** | Qwen3-8B, Qwen3-14B | Qwen được train nhiều tiếng Trung, Hán Việt chuẩn |
| **Dịch sách kỹ thuật Anh → Việt** | Llama3.1-8B, Gemma3-12B | Hiểu thuật ngữ kỹ thuật tốt |
| **Máy yếu (4-6GB VRAM)** | Qwen2.5-3B, Gemma3-4B | Cân bằng chất lượng và tốc độ |
| **Chất lượng cao nhất** | Qwen3-14B, Gemma3-27B | Dịch mượt, ít lỗi ngữ pháp |

> 💡 **Mẹo:** Với LM Studio, hãy tải các phiên bản **Q4_K_M** hoặc **Q5_K_M** để cân bằng giữa chất lượng và VRAM.

### Bước 2: Chuẩn bị Từ điển (Tùy chọn)

1. Vào mục **Từ điển (Dictionary)**
2. Thêm các từ khóa hoặc upload file từ điển để AI tuân thủ theo cách dịch của bạn

> **Ví dụ:** `"FluxOrigin"` → `"FluxOrigin"` (giữ nguyên thay vì dịch nghĩa đen)

### Bước 3: Dịch thuật

1. Vào màn hình chính **Dịch thuật**
2. Tải lên file cần dịch (Hỗ trợ `.txt`, `.md`, `.epub`)
3. Chọn ngôn ngữ nguồn và ngôn ngữ đích
4. Nhấn **Bắt đầu dịch**
5. Theo dõi tiến trình trực tiếp:
    - Xem văn bản gốc đang được dịch
    - Xem kết quả dịch real-time
    - Theo dõi tiến độ (đoạn X/Y)

---

## 🏗️ Cấu Trúc Dự Án

```
lib/
├── ui/                    # Giao diện người dùng
│   ├── screens/           # Các màn hình chính
│   ├── widgets/           # Widget tái sử dụng
│   └── theme/             # Theme và Config Provider
├── services/              # Logic gọi API
│   ├── ai_service.dart    # Kết nối Ollama/LM Studio
│   ├── web_search_service.dart
│   └── dev_logger.dart    # Logging service
├── controllers/           # Quản lý trạng thái
├── utils/                 # Công cụ xử lý text/file
└── models/                # Định nghĩa dữ liệu
```

---

## 🤝 Đóng Góp

Dự án này được phát triển tiếp từ ý tưởng của **n8n book translator**.

Mọi đóng góp, báo lỗi (Issue) hoặc yêu cầu tính năng (Pull Request) đều được hoan nghênh!

---
