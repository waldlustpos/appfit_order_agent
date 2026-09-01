package com.bixolon.pdflib;

/**
 * BIXOLON Bixolon_pdf.aar 스텁 (PDF 직접 인쇄 모듈 — 본 앱 미사용).
 *
 * <p><b>★ 삭제 금지 — G30(UPOS SDK)이 이 패키지를 참조한다.</b> 원래는 XD5-40d 의
 * Label SDK 소음 제거용으로 들어왔지만(그쪽은 부재 시 catch 후 printStackTrace 로
 * logcat 을 더럽히는 정도였다), 지금은 UPOS jar 의
 * {@code com.bxl.services.posprinter.POSPrinterService114} 와
 * {@code POSPrinterBaseService.validateDevice()} 가 참조한다 — bytecode 전수 조사로 확정.
 *
 * <p>그리고 {@code validateDevice()} 의 가드는 {@code catch (Exception)} 이라
 * <b>{@code NoClassDefFoundError}(Error)를 못 잡는다.</b> 즉 이 스텁이 사라지면
 * {@code BixolonPosDriver.ensureConnectedLocked} → {@code setDeviceEnabled(true)} 에서
 * G30 이 크래시한다. "XD5 잔재" 로 보고 지우지 말 것.
 *
 * <p>PDF 인쇄 API 를 쓰게 되면 이 스텁 패키지(com.bixolon.pdflib.*)를 삭제하고
 * 진짜 Bixolon_pdf.aar 를 넣을 것.
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
