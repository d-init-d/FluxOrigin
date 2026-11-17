# Changelog

Tất cả các thay đổi quan trọng của **FluxOrigin** được ghi lại tại đây.

---

## [3.0.0] - 2026-11-18

### Added
- **Hỗ trợ đầy đủ macOS & Linux Desktop Runners:**
  - Bổ sung runner `macos/` (`com.dinitd.fluxorigin`, entitlements hỗ trợ file cục bộ ngoài sandbox và outbound HTTP cho Local/Cloud AI, icon `.icns`/`AppIcon` đủ kích cỡ từ `16px` tới `1024px`, `MainMenu.xib` và `MainFlutterWindow.swift`).
  - Bổ sung runner `linux/` (`flux_origin`) và workflow đóng gói `.tar.gz`.
- **Hệ thống BYOK (Bring Your Own Key) Hybrid Local + Cloud AI:**
  - Tích hợp 7 preset Cloud API trong `AIService`: **Google Gemini**, **OpenAI**, **Anthropic Claude** (giao thức native `/v1/messages` với `x-api-key` & `anthropic-version`), **DeepSeek**, **OpenRouter**, **Groq**, và **Custom OpenAI API**.
  - Lưu trữ độc lập danh sách key theo từng preset trong `ConfigProvider` (`SharedPreferences`), hỗ trợ **Multi-Key Rotation** và **Failover tự động** khi gặp HTTP `429` hoặc `503`.
  - Che một phần khóa API (`maskSecret`) trước khi ghi vào `DevLogger`.
- **Tích hợp lõi D-Transcreate v1.1.0 thuần Dart + CLI kèm theo:**
  - `EpubPipelineService`: Đọc EPUB 2/3 bằng **Anchor-Locked (`<!-- @bN -->`)**, giữ nguyên link/footnote/ảnh nội tuyến bằng placeholder an toàn, cập nhật `dc:language` OPF, chia đoạn dài khi tái dựng XHTML và bảo toàn CSS, bảng, bìa và cấu trúc OCF (`mimetype` không nén đứng đầu). Hỗ trợ tạo `.epub` sạch từ văn bản/Markdown (`buildCleanEpubFromText`).
  - `WholeBookTermMiner`: Khai phá nhân danh, tổ chức, thuật ngữ viết hoa, cụm từ viết tắt và từ Hán-Nhật lặp lại trên toàn bộ cuốn sách để xuất CSV/Glossary.
  - `DTranscreateService`: Nạp **Tier-1 Vietnamese Translation Memory** (`assets/d_transcreate/glossary_vi.csv`, 45 mục) với bộ lọc tách biệt miền tri thức (`fiction`, `technical`, `legal`, `general`), nạp hồ sơ chuyển ngữ `vi-VN` (`assets/d_transcreate/vi_vn_profile.md`), cắt gọn từ điển theo từng chunk (`sliceGlossaryForChunk`, tối đa 60 thuật ngữ khớp) và xuất trọn bộ **D-Transcreate Workspace** (`manifest.json`, `glossary.csv`, `style-sheet.md`, `chunk-manifest.json`, `qa-report.md`).
  - `QaVerifierService`: Hệ thống **5-Pillar Deterministic QA** kiểm tra tỉ lệ độ dài theo cặp ngôn ngữ, rò rỉ ký tự CJK/Hangul, sai lệch số liệu/năm/URL/phần trăm, tuân thủ từ điển và lỗi dịch thô tiếng Việt; chấm điểm `/100` và hiển thị tóm tắt trực tiếp trên giao diện.
  - Nhúng bộ công cụ Python `tools/d_transcreate/book_ops.py` (`D-Transcreate v1.1.0`).
- **Hỗ trợ định dạng PDF & Markdown trong `FileParser`:**
  - Bổ sung bộ trích xuất text PDF thuần Dart giải nén luồng `FlateDecode`, tự động loại bỏ dòng header/footer lặp lại và nối từ bị ngắt gạch nối.
- **CI/CD đa nền tảng (`.github/workflows/ci.yml` & `.github/workflows/release.yml`):**
  - Tự động kiểm định `flutter analyze`, chạy full `flutter test`, build & đóng gói cho **macOS** (`.dmg` + `.zip`), **Windows** (Inno Setup `.exe` + Portable `.zip`), và **Linux** (`.tar.gz`) kèm `SHA256SUMS.txt`.

### Changed
- **Tinh chỉnh UI giữ nguyên bố cục gốc (`ui_design.html`):**
  - Bảo toàn kiến trúc `TitleBar` (`38px` trên macOS / `32px` trên Windows/Linux) + `250px Sidebar` + `IndexedStack` cùng bảng màu `#043222` / `#FDFCF8` (Light Mode) và `#000000` / `#111111` (Dark Mode), typography `Merriweather` + `Inter`.
  - Mở rộng `SettingsScreen`, `DictionaryScreen`, `TranslateScreen`, `BatchTranslateScreen`, `HistoryScreen` và `DevLogsScreen` với các điều khiển BYOK, Auto-Mine Terms, EPUB layout-preserve toggle, QA badge/sheet, và xuất Workspace.
  - Sửa bug xử lý khoảng trắng dấu câu trong `_cleanResponse` của `AIService` (`replaceAllMapped` thay cho chuỗi `$1` literal).
  - Bổ sung dấu kết thúc câu CJK (`。`, `！`, `？`, `；`) và look-forward thích ứng trong `TextProcessor.smartSplit`.
- **Dọn sạch mã nguồn & cập nhật installer:**
  - Gỡ bỏ các file nhị phân Windows Release từng bị commit nhầm vào git; cập nhật `.gitignore` và `installers/Flux_Origin.iss` lên đường dẫn tương đối cho `v3.0.0`.
  - Sửa một biến cục bộ không dùng trong `test/bugfixes/progress_throttle_test.dart` để đạt 0 warning khi analyze.

---

## [2.1.0] - Historical
- Hỗ trợ dịch hàng loạt (**Batch Translation**, `#5`) và tôn trọng file từ điển người dùng tải lên (`#6`).

## [2.0.2] - Historical
- Sửa 5 lỗi nghiêm trọng liên quan đến throttling lưu tiến trình dịch nguyên tử (atomic save), DevLogger ring buffer và từ điển người dùng.
