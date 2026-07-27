package com.bixolon.pdflib;

import android.content.Context;
import android.graphics.Bitmap;
import android.os.ParcelFileDescriptor;

import com.bixolon.pdflib.util.Size;

/**
 * BIXOLON Bixolon_pdf.aar 스텁 — 사유는 {@link License} javadoc 참고.
 * 생성자만 SDK 초기화 시 실행되고, 나머지는 PDF 인쇄 API(미사용) 경로에서만 호출된다.
 */
public class PdfCore {
    public PdfCore(Context context, License license) {
        // 스텁 — SDK 생성자가 인스턴스만 만든다.
    }

    public void setDpi(int dpi) {
        throw new UnsupportedOperationException("pdflib stub - PDF printing not supported");
    }

    public PdfDocument newDocument(ParcelFileDescriptor fd, String password) {
        throw new UnsupportedOperationException("pdflib stub - PDF printing not supported");
    }

    public int getPageCount(PdfDocument document) {
        throw new UnsupportedOperationException("pdflib stub - PDF printing not supported");
    }

    public int getPageHeight(PdfDocument document, int pageIndex) {
        throw new UnsupportedOperationException("pdflib stub - PDF printing not supported");
    }

    public Size getPageSize(PdfDocument document, int pageIndex) {
        throw new UnsupportedOperationException("pdflib stub - PDF printing not supported");
    }

    public long openPage(PdfDocument document, int pageIndex) {
        throw new UnsupportedOperationException("pdflib stub - PDF printing not supported");
    }

    public void renderPageBitmap(PdfDocument document, Bitmap bitmap, int pageIndex,
                                 int startX, int startY, int drawSizeX, int drawSizeY) {
        throw new UnsupportedOperationException("pdflib stub - PDF printing not supported");
    }
}
