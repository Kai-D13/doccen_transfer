# LMS E-learning cho nhân viên y tế: Research & Định hướng kiến trúc

> Giai đoạn: **Discovery / Research (bước sơ khai)**. Tài liệu này dùng để thống nhất hướng đi trước khi chốt phạm vi, ngân sách và đội ngũ.
> Đối tượng tham chiếu: [doccen.vn](https://doccen.vn/), nền tảng học trực tuyến và CME/CPE cho nhân viên y tế Việt Nam.

## Bộ tài liệu

| # | Tài liệu | Nội dung chính |
|---|---|---|
| 01 | [Phân tích Doccen](docs/01-doccen-analysis.md) | Doccen làm gì, mô hình kinh doanh, tính năng, bài học rút ra |
| 02 | [Phạm vi sản phẩm & Business logic](docs/02-product-scope-business-logic.md) | Module, user journey, state machine, quy tắc nghiệp vụ (CME, quiz, chứng chỉ, KYC) |
| 03 | [Kiến trúc & Hạ tầng](docs/03-architecture-infrastructure.md) | Kiến trúc tổng thể, chọn stack FE/BE, video, live, search, AI, hạ tầng cloud, NFR |
| 04 | [Database & RLS](docs/04-database-rls.md) | Mô hình dữ liệu, ERD, Row Level Security trên PostgreSQL, ví dụ policy |
| 05 | [RBAC & Phân quyền](docs/05-rbac-authorization.md) | Vai trò, ma trận quyền, RBAC + ABAC + ReBAC, enforcement nhiều lớp |
| 06 | [Tích hợp](docs/06-integrations.md) | SSO, thuocsi.vn/Buymed, thanh toán, Zalo/SMS, video, CRM, data warehouse |
| 07 | [Roadmap, Đội ngũ, Rủi ro](docs/07-roadmap-team-risks.md) | Lộ trình theo phase, team, rủi ro, câu hỏi cần stakeholder quyết định |

## Tóm tắt điều hành (TL;DR)

1. **Doccen không chỉ là một LMS.** Đây là sự kết hợp của 4 thứ: (a) **mạng cộng đồng chuyên môn** (profile, group, feed), (b) **LMS** (khóa học video, quiz, chứng chỉ), (c) **kênh phân phối CME/CPE** cùng cơ sở đào tạo được công nhận và hội nghề nghiệp, (d) **kênh đào tạo có tài trợ** cho doanh nghiệp dược và phân phối (ví dụ trang `doccen.vn/buymed` cho dược sĩ và khách hàng thuocsi.vn). Họ có thêm **Doccen Library** (tìm kiếm tập trung) và **DoccenAI** (chatbot hỏi đáp tài liệu, quiz).
2. **Nên build custom, nhưng mua các phần "hàng hóa".** Phần lõi khác biệt (KYC nhân viên y tế, sổ CME, tài trợ, tích hợp hệ sinh thái Buymed/thuocsi) nên tự build. Video hosting/transcoding, live webinar, gửi OTP/email, thanh toán và LLM nên dùng dịch vụ có sẵn.
3. **Kiến trúc đề xuất:** **Modular monolith** (một codebase, chia module rõ ràng) + **PostgreSQL làm nguồn dữ liệu chuẩn và bật RLS làm lớp bảo vệ thứ hai** + worker bất đồng bộ + video pipeline managed + CDN. Frontend dùng **Next.js** (SSR/ISR cho SEO trang khóa học và bài viết), admin/CMS tách app riêng trong cùng monorepo. Chỉ tách microservice khi có số liệu chứng minh cần.
4. **Phân quyền 3 lớp:** RBAC theo phạm vi (platform / organization / group) + ABAC (nghề nghiệp, trạng thái xác thực HCP, khu vực) + kiểm tra quan hệ (enrollment, thành viên group). Enforcement ở API (policy layer) **và** ở DB (RLS). Báo cáo cho nhà tài trợ chỉ đi qua view tổng hợp, không cho truy cập dữ liệu dòng.
5. **Rủi ro pháp lý quan trọng hơn rủi ro kỹ thuật:** quy định đào tạo liên tục của Bộ Y tế (ai được cấp chứng chỉ CME/CPE), quy định thông tin thuốc cho người hành nghề (nội dung thuốc kê đơn phải giới hạn cho HCP đã xác thực), và quy định bảo vệ dữ liệu cá nhân (Nghị định 13/2023 và Luật Bảo vệ dữ liệu cá nhân mới). Cần legal review ngay từ Phase 0.
6. **Lộ trình gợi ý:** Phase 0 Discovery khoảng 3–4 tuần → Phase 1 MVP khoảng 12–16 tuần (auth + KYC, khóa học video, quiz, chứng chỉ, CMS, báo cáo cơ bản) → Phase 2 (webinar live, cộng đồng/group, Q&A với diễn giả, sổ CME, dashboard nhà tài trợ) → Phase 3 (Library search, AI tutor, gamification, mobile app).

## Giới hạn của đợt research này

- Môi trường cloud chạy research **bị network policy chặn truy cập trực tiếp `doccen.vn`** (cả trình duyệt Chromium lẫn fetch). Phần phân tích Doccen được tổng hợp từ nội dung đã được công cụ tìm kiếm index (trang con doccen.vn, blog doccencorp.com/doccen.edu.vn, báo chí, LinkedIn, Threads). Chưa đi được từng màn hình UI khi đã đăng nhập.
- Để deep-dive UI/UX (crawl từng trang, chụp màn hình, phân tích flow), cần thêm `doccen.vn` (và nếu muốn, `doccencorp.com`, `doccen.edu.vn`) vào **Allowed domains** trong cấu hình network của cloud environment, rồi chạy lại phần crawl.
- Các con số (user, tài liệu) lấy từ trang công khai tại thời điểm index, có thể đã cũ.
