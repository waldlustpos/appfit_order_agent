package com.bixolon.pdflib;

/**
 * BIXOLON Bixolon_pdf.aar 스텁 (PDF 직접 인쇄 모듈 — 본 앱 미사용).
 *
 * <p>BixolonLabelPrinter(V2.1.1) 생성자가 pdflib 클래스를 무조건 참조하고, 부재 시
 * catch(NoClassDefFoundError)로 삼키지만 printStackTrace() 를 호출해 연결마다
 * logcat 에 스택트레이스 소음이 찍힌다. 실제 aar(수 MB) 대신 최소 스텁으로 참조를
 * 충족시켜 소음을 제거한다. PDF 인쇄 API 를 쓰게 되면 이 스텁 패키지
 * (com.bixolon.pdflib.*)를 삭제하고 진짜 Bixolon_pdf.aar 를 넣을 것.
 *
 * <p>참조 멤버는 SDK jar bytecode 전수 조사로 확정 (BixolonLabelDriver 참고).
 */
public class License {
    private static final License INSTANCE = new License();

    public static License getInstance() {
        return INSTANCE;
    }

    public void setIsLicenseKey(boolean isLicenseKey) {
        // 스텁 — SDK 생성자가 호출하지만 PDF 미사용이라 무동작.
    }
}
