# 07. Roadmap, Đội ngũ, Rủi ro, Câu hỏi mở

## 1. Lộ trình theo phase

```mermaid
gantt
  dateFormat  YYYY-MM-DD
  axisFormat  %m/%y
  section Phase 0 - Discovery
  Stakeholder, legal, quyết định kiến trúc :p0, 2026-11-01, 4w
  section Phase 1 - MVP
  Nền tảng: IdP, CI/CD, IaC, design system :p1a, after p0, 3w
  Auth + KYC + profile HCP                 :p1b, after p1a, 3w
  Catalog + player + progress              :p1c, after p1a, 5w
  Assessment + certificate                 :p1d, after p1c, 3w
  Admin CMS + duyệt nội dung + báo cáo     :p1e, after p1b, 5w
  UAT, pentest, pilot                      :p1f, after p1d, 3w
  section Phase 2
  Webinar + điểm danh + Q&A                :p2a, after p1f, 6w
  Community / group + CME ledger           :p2b, after p1f, 8w
  Sponsor dashboard + SSO thuocsi + thanh toán :p2c, after p2a, 6w
  section Phase 3
  Library search + AI tutor                :p3a, after p2b, 8w
  Gamification + mobile app                :p3b, after p2c, 10w
```

*(Mốc thời gian chỉ để minh họa, phụ thuộc quy mô team và phạm vi chốt ở Phase 0.)*

### Phase 0: Discovery (3–4 tuần)
**Đầu ra:** PRD v1, tracking plan, mô hình dữ liệu v1, ADR (Architecture Decision Records) cho các quyết định lớn, ước tính chi phí hạ tầng, kết luận legal, kế hoạch nội dung cho 10–20 khóa đầu tiên.
- Phỏng vấn 10–15 người dùng: dược sĩ nhà thuốc, bác sĩ, trình dược viên, đối tác dược.
- **Legal review:** đào tạo liên tục (ai cấp CME/CPE, hồ sơ cần lưu), thông tin thuốc cho HCP, bảo vệ dữ liệu cá nhân và vị trí lưu dữ liệu, thưởng hoặc khuyến mại gắn với đào tạo.
- Chọn 1–2 **cơ sở đào tạo liên tục** làm đối tác cấp CME/CPE cho pilot.
- PoC kỹ thuật: video provider (độ trễ và chi phí từ VN), SSO với IdP Buymed, RLS + policy engine trên stack đã chọn.

### Phase 1: MVP (khoảng 12–16 tuần)
**Phạm vi:** đăng ký/đăng nhập (OTP, SSO nếu sẵn), xác thực HCP, catalog và trang khóa học (SEO), player video có progress chống tua, quiz và bài thi cuối, chứng chỉ PDF + QR verify, CMS cho org (khóa học, bài học, ngân hàng câu hỏi, luồng duyệt), báo cáo cơ bản, thông báo email/ZNS.
**Không làm:** community, live, thanh toán, AI, mobile app.
**Tiêu chí pilot:** khoảng 1.000 dược sĩ nhà thuốc, 3–5 khóa, completion rate, thời gian duyệt KYC, NPS.

### Phase 2: Tăng trưởng
Webinar và điểm danh CME, Q&A theo bài học, group/cộng đồng, sổ CME, dashboard nhà tài trợ, SSO và giao khóa từ hệ thống Buymed, voucher, thanh toán nếu có khóa trả phí, import SCORM.

### Phase 3: Khác biệt hóa
Library search hợp nhất, AI tutor (RAG có trích dẫn), gamification (điểm, huy hiệu, bảng xếp hạng, đổi thưởng), mobile app, API mở cho đối tác.

## 2. Đội ngũ đề xuất

| Vai trò | Phase 0 | Phase 1 | Ghi chú |
|---|---|---|---|
| Product Owner / PM | 1 | 1 | Chủ trì PRD và ưu tiên |
| Business Analyst (am hiểu y dược) | 1 | 1 | Quy trình CME, KYC, MLR |
| UX/UI Designer | 1 | 1 | Mobile-first, design system |
| Tech Lead / Architect | 1 | 1 | ADR, review, bảo mật |
| Frontend (Next.js) | – | 2 | |
| Backend | – | 2–3 | |
| DevOps / SRE | 0.5 | 0.5–1 | IaC, CI/CD, observability |
| QA (manual + automation) | – | 1 | Bao gồm test phân quyền |
| **Vận hành (không phải dev)** | | | KYC officer, content ops, reviewer y khoa (MLR), CSKH |

## 3. Rủi ro chính

| Rủi ro | Mức | Giảm thiểu |
|---|---|---|
| Hiểu sai quy định CME/CPE, chứng chỉ không được công nhận | Cao | Legal review ở Phase 0. Hợp tác cơ sở đào tạo đủ điều kiện. Nền tảng không tự "cấp CME" |
| Lộ dữ liệu cá nhân hoặc giấy tờ hành nghề | Cao | RLS + policy, mã hóa, audit, least privilege, pentest, DPIA |
| Nội dung thuốc kê đơn hiển thị cho người không phải HCP | Cao | Gating `verified_hcp` ở cả API và RLS. MLR workflow. Nhãn tài trợ |
| Gian lận hoàn thành (tua, nhờ người học hộ) | Trung bình | Heartbeat phía server, chống tua, attention check, phát hiện bất thường |
| Chi phí video vượt dự toán | Trung bình | PoC chi phí, chọn bitrate ladder hợp lý, giới hạn tải về, theo dõi chi phí hằng tuần |
| Cold-start nội dung (ít khóa thì ít người dùng) | Cao | Bắt đầu với tệp nhà thuốc Buymed và chuyển nội dung sẵn có (hội thảo cũ). Hợp tác hội và trường |
| Phụ thuộc Doccen trong giai đoạn chuyển đổi | Trung bình | Kế hoạch di trú nội dung và học viên (nếu hợp đồng cho phép xuất dữ liệu). Chạy song song |
| Over-engineering (microservice quá sớm) | Trung bình | Modular monolith. Chỉ tách khi có số liệu |
| Webinar peak làm sập hệ thống | Trung bình | Live chạy trên provider. Platform chỉ xử lý đăng ký, Q&A. Load test trước sự kiện lớn |

## 4. Câu hỏi cần stakeholder trả lời (quyết định hướng đi)

1. **Định vị:** LMS **nội bộ cho hệ sinh thái Buymed** (nhà thuốc, khách thuocsi, nhân viên) hay **nền tảng mở đa đối tác** giống Doccen (các hãng dược mở kênh riêng)? Câu trả lời quyết định mức đầu tư multi-tenant, sponsor dashboard và billing.
2. **Đối tượng ưu tiên:** dược sĩ nhà thuốc trước, hay cả bác sĩ và điều dưỡng ngay từ đầu?
3. **CME/CPE:** có cần cấp CME/CPE ngay ở MVP không? Đối tác cơ sở đào tạo là ai?
4. **Mô hình doanh thu:** miễn phí cho người học + tài trợ, bán khóa, thuê bao, hay bán license cho tổ chức?
5. **Quan hệ với Doccen:** thay thế hoàn toàn, chạy song song, hay chỉ cho nhóm nội dung mới? Có quyền xuất dữ liệu học viên/khóa học hiện có không?
6. **Hạ tầng:** Buymed đang dùng cloud nào? Có yêu cầu dữ liệu phải ở VN không? Có IdP và data platform dùng chung không?
7. **Stack ưu tiên của team:** TypeScript, Go hay Java? Nên chọn theo năng lực team hiện có.
8. **Mobile app native** có bắt buộc ở năm đầu không, hay mobile web/PWA là đủ?
9. **Ngân sách và mốc thời gian** cho MVP và pilot?
10. **Vận hành:** ai làm KYC, duyệt nội dung y khoa, CSKH? Cần SLA duyệt KYC bao lâu?

## 5. Bước tiếp theo đề xuất
1. Họp kickoff để trả lời mục 4 (ít nhất câu 1, 3, 5, 6).
2. Mở quyền truy cập `doccen.vn` cho môi trường research để làm **UI/UX teardown** chi tiết (screenshot từng flow: đăng ký, xác thực, học, thi, chứng chỉ, group, webinar).
3. Viết PRD MVP và ADR: (a) stack BE, (b) video provider, (c) IdP, (d) cloud và vị trí dữ liệu, (e) policy engine.
4. PoC 2 tuần: Next.js + API + Postgres RLS (dựa trên `sql/`) + video provider + chứng chỉ PDF.
