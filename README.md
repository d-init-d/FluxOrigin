# FluxOrigin v3.0.0 — AI Book Translation & Transcreation Studio

<p align="center">
  <img src="https://img.shields.io/badge/Platform-macOS%20%7C%20Windows%20%7C%20Linux-043222?style=flat-square" alt="Platform">
  <img src="https://img.shields.io/badge/Flutter-3.x-02569B?style=flat-square&logo=flutter" alt="Flutter">
  <img src="https://img.shields.io/badge/Engine-D--Transcreate%20v1.1.0-13503D?style=flat-square" alt="D-Transcreate v1.1.0">
  <img src="https://img.shields.io/badge/AI-Local%20%2B%20BYOK%20Cloud-blue?style=flat-square" alt="Hybrid Local and BYOK Cloud">
  <img src="https://img.shields.io/badge/License-GPLv3-blue?style=flat-square" alt="License">
</p>

**FluxOrigin** là ứng dụng Desktop đa nền tảng (**macOS**, **Windows**, **Linux**) chuyên dụng cho dịch thuật & chuyển ngữ sách dài (`.epub`, `.pdf`, `.txt`, `.md`), kế thừa tư duy từ **n8n book translator** và tích hợp lõi **D-Transcreate v1.1.0** cùng giao diện **Literary Paper** đặc trưng.

Phiên bản **v3.0.0** mang đến bản dựng **macOS native** hoàn chỉnh, hỗ trợ **BYOK (Bring Your Own Key)** đa nhà cung cấp với **xoay vòng nhiều API key (multi-key rotation & `429`/`503` failover)** song song với **Local LLM (`Ollama` / `LM Studio`)**, cùng quy trình **Anchor-Locked Layout-Preserving EPUB** giữ nguyên CSS, ảnh bìa, bảng biểu, ghi chú (`<a>`, `<sup>`, `<img>`) và kiểm định chất lượng 5 cổng (**5-Pillar Deterministic QA**).

---

## 🌟 Điểm Mới Nổi Bật Trong v3.0.0

| Khía cạnh | Nâng cấp chính trong v3.0.0 |
|---|---|
| **macOS & Linux Native** | Hỗ trợ đầy đủ **macOS Universal (Apple Silicon & Intel)** với `.dmg` / `.zip`, thanh tiêu đề chuẩn macOS (`traffic-lights` safe padding), cuộn chuột mượt và bộ đóng gói CI/CD đa nền tảng. |
| **Lõi D-Transcreate v1.1.0** | Khai phá thực thể & thuật ngữ toàn sách (`WholeBookTermMiner`), lọc **Tier-1 Vietnamese Translation Memory** (`assets/d_transcreate/glossary_vi.csv`, 45 dòng) theo miền tri thức (không lem ngữ cảnh giữa Kỹ thuật / Pháp lý / Tiểu thuyết), áp dụng hồ sơ chuyển ngữ `vi-VN` chống khẩu khí dịch máy (`vi_vn_profile.md`). |
| **Anchor-Locked EPUB 2/3** | `EpubPipelineService` gắn neo `<!-- @bN -->` vào từng khối lá XHTML, trích link/footnote/ảnh nội tuyến thành placeholder, dịch song song và tái dựng nguyên vẹn file `.epub` gốc (bìa, CSS, OPF `dc:language`, ảnh, bảng). |
| **Đọc PDF & Markdown** | Hỗ trợ tải `.pdf` trực tiếp bằng bộ giải nén luồng `FlateDecode` viết thuần bằng Dart trong `FileParser` (tự động loại bỏ header/footer lặp lại và ghép từ ngắt dòng) cùng `.md` / `.markdown`. |
| **Hybrid Local + BYOK Cloud** | Chạy miễn phí ngoại tuyến qua **Ollama** / **LM Studio**, hoặc dùng **BYOK Cloud API** cho 7 preset (**Google Gemini**, **OpenAI**, **Anthropic Claude** native `/v1/messages`, **DeepSeek**, **OpenRouter**, **Groq**, **Custom OpenAI API**). |
| **Multi-Key Rotation & Masking** | Nhập nhiều API key (mỗi dòng hoặc ngăn cách bởi dấu phẩy) để xoay vòng luân phiên và tự động failover khi gặp HTTP `429` / `503`. Mọi API key đều được ẩn một phần khi ghi vào Dev Logs. |
| **Kiểm định QA 5 Cổng** | `QaVerifierService` chấm điểm chất lượng sau dịch theo 5 tiêu chí: Độ đầy đủ & tỉ lệ độ dài theo cặp ngôn ngữ, Rò rỉ chữ Hán/Hangul, Bảo toàn số liệu/năm/URL/phần trăm, Tuân thủ thuật ngữ, Lỗi dịch thô tiếng Việt & lặp ngữ điệu. |
| **Xuất Workspace Chuẩn Audit** | Xuất bộ hồ sơ D-Transcreate (`manifest.json`, `glossary.csv`, `style-sheet.md`, `chunk-manifest.json`, `qa-report.md`) và kèm sẵn gói `tools/d_transcreate/book_ops.py` cho quy trình CLI. |
| **Giao diện Literary Paper** | Giữ nguyên bố cục gốc (`TitleBar` + `250px Sidebar` + khu vực làm việc chính) cùng bảng màu giấy sách (`#043222` / `#FDFCF8` chế độ Sáng, `#000000` / `#111111` đơn sắc chế độ Tối) và font chữ `Merriweather` + `Inter`. |

---

## 📦 Tải Xuống & Cài Đặt

Tải bản dựng mới nhất tại trang **[GitHub Releases](https://github.com/d-init-d/FluxOrigin/releases/latest)**:

### macOS (Apple Silicon M1–M4 & Intel)
1. Tải **`FluxOrigin-v3.0.0-macos-universal.dmg`** (hoặc `.zip`).
2. Mở file `.dmg` và kéo **FluxOrigin.app** vào thư mục **Applications**.
3. **Lưu ý lần đầu mở app chưa ký Apple Developer Certificate (Gatekeeper):**
   Nếu macOS báo không xác minh được nhà phát triển, chạy một lệnh sau trong Terminal rồi mở lại ứng dụng:
   ```bash
   xattr -cr /Applications/FluxOrigin.app
   ```

### Windows 10/11 (64-bit)
- **Microsoft Store (`.msix`):** Gói **`FluxOrigin-v3.0.0-windows-x64-store.msix`** (`Identity: d-init-d.FluxOrigin`, `Version: 3.0.0.0`, `store: true`) sẵn sàng upload trực tiếp lên Partner Center.
- **Bộ cài đặt (Khuyên dùng):** Tải **`FluxOrigin-v3.0.0-windows-x64-setup.exe`** và làm theo trình hướng dẫn.
- **Bản Portable:** Tải **`FluxOrigin-v3.0.0-windows-x64-portable.zip`**, giải nén và chạy `flux_origin.exe`.

### Linux (x64)
- Tải **`FluxOrigin-v3.0.0-linux-x64.tar.gz`**, giải nén và chạy `./flux_origin` (yêu cầu GTK3 runtime).

---

## ⚙️ Cấu Hình AI: Local LLM & BYOK Cloud

Vào mục **Cài đặt (Settings)** ở thanh điều hướng bên trái để chọn chế độ:

### 1. Local LLM (Miễn phí, Riêng tư 100%)
- **Ollama:** URL mặc định `http://localhost:11434`
- **LM Studio:** URL mặc định `http://localhost:1234`
- Nhấn **Kiểm tra kết nối** để nạp danh sách model đang có trên máy.

### 2. Cloud BYOK (Bring Your Own Key)
Hỗ trợ 7 preset cấu hình sẵn:
- **Google Gemini** (`https://generativelanguage.googleapis.com/v1beta/openai`) — VD: `gemini-2.5-flash`, `gemini-2.5-pro`
- **OpenAI** (`https://api.openai.com/v1`) — VD: `gpt-4.1-mini`, `gpt-4.1`
- **Anthropic Claude** (`https://api.anthropic.com` — gọi trực tiếp `/v1/messages`) — VD: `claude-sonnet-4-20250514`, `claude-3-5-haiku-latest`
- **DeepSeek** (`https://api.deepseek.com/v1`) — VD: `deepseek-chat`, `deepseek-reasoner`
- **OpenRouter** (`https://openrouter.ai/api/v1`)
- **Groq** (`https://api.groq.com/openai/v1`)
- **Custom OpenAI API** (mọi endpoint tương thích `/chat/completions`)

> **Mẹo Multi-Key Rotation:** Dán nhiều API key (mỗi key trên một dòng) trong ô **API Key(s)**. FluxOrigin sẽ tự động luân phiên sử dụng và đổi key dự phòng nếu một key chạm ngưỡng tốc độ (`429` / `503`).

---

## 🧩 Gợi Ý Chọn Model Local (Ollama / LM Studio)

| Mục đích | Model đề xuất | VRAM gợi ý | Ghi chú |
|---|---|---|---|
| **Tiểu thuyết Trung → Việt** | `qwen3:8b`, `qwen3:14b` | 8–16 GB | Hiểu ngữ cảnh Hán-Việt và khẩu khí tốt |
| **Sách kỹ thuật Anh → Việt** | `llama3.1:8b`, `gemma3:12b` | 8–12 GB | Thuật ngữ và cú pháp kỹ thuật chuẩn |
| **Máy phổ thông** | `qwen2.5:3b`, `gemma3:4b` | 4–6 GB | Tốc độ nhanh, nhẹ RAM/VRAM |
| **Chất lượng cao / Cloud** | `gemini-2.5-flash`, `claude-sonnet-4-20250514`, `gpt-4.1` | BYOK | Cửa sổ ngữ cảnh lớn, văn phong mượt |

---

## 📖 Quy Trình Dịch Sách Khuyên Dùng

1. **Từ điển (Tùy chọn thông minh):** Mở **Từ điển**, dùng **Auto-Mine Terms** trên file nguồn để trích xuất nhân danh/địa danh/thuật ngữ lặp lại hoặc nạp thêm từ Tier-1 Vietnamese Memory. File từ điển bạn tải lên bằng tay luôn được tôn trọng nguyên trạng.
2. **Dịch đơn hoặc Dịch hàng loạt:** Kéo thả `.epub`, `.pdf`, `.txt`, `.md` vào màn hình **Dịch thuật** hoặc **Dịch hàng loạt**. Chọn ngôn ngữ nguồn/đích và **Phong cách / Thể loại** (`Tiên hiệp / Kiếm hiệp`, `Kỹ thuật / CNTT`, `Pháp lý / Chính sách`, `Tùy chỉnh...`).
3. **Theo dõi Real-time & QA:** Xem văn bản gốc song song bản dịch, điểm **QA Score (/100)** tự động sau khi hoàn tất, và mở **Nhật ký Dev Logs** nếu cần theo dõi request/key failover.
4. **Xuất thành phẩm:** Lưu kết quả dạng `.epub` giữ nguyên định dạng gốc (với nguồn `.epub`), `.epub` dựng mới gọn đẹp (từ `.txt`/`.md`/`.pdf`), `.md`, `.txt`, hoặc **Export D-Transcreate Workspace** để lưu giữ toàn bộ từ điển, style sheet và báo cáo QA.

---

## 🛠️ Build Từ Mã Nguồn (Developer)

```bash
# 1. Clone repository
git clone https://github.com/d-init-d/FluxOrigin.git
cd FluxOrigin

# 2. Cài đặt dependencies
flutter pub get

# 3. Kiểm tra tĩnh & chạy toàn bộ test suite (106 unit & preservation tests)
flutter analyze --no-fatal-infos --no-fatal-warnings
flutter test

# 4. Chạy trên nền tảng desktop tương ứng
flutter run -d macos     # macOS
flutter run -d windows   # Windows
flutter run -d linux     # Linux
```

---

## 🏗️ Cấu Trúc Dự Án

```text
FluxOrigin/
├── lib/
│   ├── controllers/         # TranslationController, BatchTranslationController (Single/Batch, Pause/Resume, QA)
│   ├── models/              # TranslationProgress (hỗ trợ styleGuide, epubMetadata, qaSummary)
│   ├── services/
│   │   ├── ai_service.dart            # Ollama, LM Studio, 7 BYOK Cloud presets, Key Rotation, Slicing
│   │   ├── d_transcreate_service.dart # Tier-1 Memory, Domain Filter, vi-VN Profile, Workspace Export
│   │   ├── epub_pipeline_service.dart # Anchor-Locked <!-- @bN --> EPUB 2/3 Scan & Rebuild
│   │   ├── qa_verifier_service.dart   # 5-Pillar Deterministic QA Gate & Report
│   │   ├── web_search_service.dart    # DuckDuckGo / Wikipedia / Ollama Web Search context helper
│   │   └── dev_logger.dart            # Structured ring-buffer diagnostic logger
│   ├── ui/                  # Literary Paper UI (Theme, TitleBar, 250px Sidebar, 6 Screens)
│   └── utils/               # FileParser (.epub/.pdf/.txt/.md), WholeBookTermMiner, TextProcessor
├── assets/d_transcreate/    # Bundled Tier-1 glossary_vi.csv & vi_vn_profile.md
├── tools/d_transcreate/     # Embedded D-Transcreate v1.1.0 Python toolkit (book_ops.py)
├── installers/              # Windows Inno Setup script (Flux_Origin.iss)
├── macos/ windows/ linux/   # Native desktop platform runners
└── test/                    # Unit tests, D-Transcreate upgrade suite & bugfix preservation tests
```

---

## 🤝 Đóng Góp & Ghi Nhận

Dự án được phát triển tiếp từ ý tưởng của **n8n book translator** và nâng cấp toàn diện cùng kiến trúc dịch sách của **D-Transcreate v1.1.0**.

Mọi đóng góp, báo lỗi (Issue) hoặc Pull Request đều được hoan nghênh!

Developed with ❤️ by **d-init-d**

---

## ⚖️ Giấy Phép & Bản Quyền (License & Branding)

Dự án này được phân phối dưới giấy phép **GPLv3** (xem [LICENSE](LICENSE)).

> **Lưu ý về Thương hiệu:**
> Tên ứng dụng **"FluxOrigin"** và Logo là tài sản riêng. Bạn có thể fork và sửa mã nguồn theo giấy phép GPLv3, nhưng vui lòng **đổi tên và logo khác** nếu bạn phát hành bản sửa đổi ra công chúng.

---

## Contributors

[![Contributors](https://contrib.rocks/image?repo=d-init-d/FluxOrigin)](https://github.com/d-init-d/FluxOrigin/graphs/contributors)
