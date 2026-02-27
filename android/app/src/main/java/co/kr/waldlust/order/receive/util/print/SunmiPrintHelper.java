package co.kr.waldlust.order.receive.util.print;

import android.content.Context;
import android.os.RemoteException;
import android.util.Log;

import com.sunmi.peripheral.printer.ExceptionConst;
import com.sunmi.peripheral.printer.InnerLcdCallback;
import com.sunmi.peripheral.printer.InnerPrinterCallback;
import com.sunmi.peripheral.printer.InnerPrinterException;
import com.sunmi.peripheral.printer.InnerPrinterManager;
import com.sunmi.peripheral.printer.InnerResultCallback;
import com.sunmi.peripheral.printer.SunmiPrinterService;
import com.sunmi.peripheral.printer.WoyouConsts;


import java.text.DecimalFormat;
import java.text.NumberFormat;
import java.util.HashMap;

import org.json.JSONArray;
import org.json.JSONException;
import org.json.JSONObject;

import co.kr.waldlust.order.receive.MainActivity;


/**
 * <pre>
 *      This class is used to demonstrate various printing effects
 *      Developers need to repackage themselves, for details please refer to
 *      http://sunmi-ota.oss-cn-hangzhou.aliyuncs.com/DOC/resource/re_cn/Sunmiprinter%E5%BC%80%E5%8F%91%E8%80%85%E6%96%87%E6%A1%A31.1.191128.pdf
 *  </pre>
 *
 * @author kaltin
 * @since create at 2020-02-14
 */
public class SunmiPrintHelper {

    public static int NoSunmiPrinter = 0x00000000;
    public static int CheckSunmiPrinter = 0x00000001;
    public static int FoundSunmiPrinter = 0x00000002;
    public static int LostSunmiPrinter = 0x00000003;
    public static int receiptFontSize = 35;
    public static int receiptLineFontSize = 20;
    public static int receiptOptionFontSize = 30;
    public static int receiptInfoFontSize = 32;
    public static int receiptMenuFontSize = 40;
    public static int receiptTitleFontSize = 50;
    public static int receiptOrderNumFontSize = 37;
    /**
     *  sunmiPrinter means checking the printer connection status
     */
    public int sunmiPrinter = CheckSunmiPrinter;
    /**
     *  SunmiPrinterService for API
     */
    private SunmiPrinterService sunmiPrinterService;

    private static SunmiPrintHelper helper = new SunmiPrintHelper();
    private HashMap<String, Long> map = new HashMap<>();
    private Context context;
    private SunmiPrintHelper() {
    }

    public static SunmiPrintHelper getInstance() {
        return helper;
    }

    private InnerPrinterCallback innerPrinterCallback = new InnerPrinterCallback() {
        @Override
        protected void onConnected(SunmiPrinterService service) {
            sunmiPrinterService = service;
            checkSunmiPrinterService(service);
        }

        @Override
        protected void onDisconnected() {
            sunmiPrinterService = null;
            sunmiPrinter = LostSunmiPrinter;
        }
    };

    /**
     * init sunmi print service
     */
    public void initSunmiPrinterService(Context context){
        this.context = context;
        try {
            boolean ret =  InnerPrinterManager.getInstance().bindService(context,
                    innerPrinterCallback);
            if(!ret){
                sunmiPrinter = NoSunmiPrinter;
            }
        } catch (InnerPrinterException e) {
            e.printStackTrace();
        }
    }

    /**
     *  deInit sunmi print service
     */
    public void deInitSunmiPrinterService(Context context){
        try {
            if(sunmiPrinterService != null){
                InnerPrinterManager.getInstance().unBindService(context, innerPrinterCallback);
                sunmiPrinterService = null;
                sunmiPrinter = LostSunmiPrinter;
            }
        } catch (InnerPrinterException e) {
            e.printStackTrace();
        }
    }

    /**
     * Check the printer connection,
     * like some devices do not have a printer but need to be connected to the cash drawer through a print service
     */
    private void checkSunmiPrinterService(SunmiPrinterService service){
        boolean ret = false;
        try {
            ret = InnerPrinterManager.getInstance().hasPrinter(service);
        } catch (InnerPrinterException e) {
            e.printStackTrace();
        }
        sunmiPrinter = ret?FoundSunmiPrinter:NoSunmiPrinter;
    }

    /**
     *  Some conditions can cause interface calls to fail
     *  For example: the version is too low、device does not support
     *  You can see {@link ExceptionConst}
     *  So you have to handle these exceptions
     */
    private void handleRemoteException(RemoteException e){
        //TODO process when get one exception
    }

    /**
     * send esc cmd
     */
    public void sendRawData(byte[] data) {
        if(sunmiPrinterService == null){
            //TODO Service disconnection processing
            return;
        }
        try {
            sunmiPrinterService.sendRAWData(data, null);
        } catch (RemoteException e) {
            handleRemoteException(e);
        }
    }

    /**
     *  Printer cuts paper and throws exception on machines without a cutter
     */
    public void cutpaper(){
        if(sunmiPrinterService == null){
            //TODO Service disconnection processing
            return;
        }
        try {
            sunmiPrinterService.cutPaper(null);
        } catch (RemoteException e) {
            handleRemoteException(e);
        }
    }

    /**
     *  Initialize the printer
     *  All style settings will be restored to default
     */
    public void initPrinter(){
        if(sunmiPrinterService == null){
            //TODO Service disconnection processing
            return;
        }
        try {
            sunmiPrinterService.printerInit(null);
        } catch (RemoteException e) {
            handleRemoteException(e);
        }
    }

    /**
     * Get printer serial number
     */
    public String getPrinterSerialNo(){
        if(sunmiPrinterService == null){
            //TODO Service disconnection processing
            return "";
        }
        try {
            return sunmiPrinterService.getPrinterSerialNo();
        } catch (RemoteException e) {
            handleRemoteException(e);
            return "";
        }
    }

    /**
     * Get device model
     */
    public String getDeviceModel(){
        if(sunmiPrinterService == null){
            //TODO Service disconnection processing
            return "";
        }
        try {
            return sunmiPrinterService.getPrinterModal();
        } catch (RemoteException e) {
            handleRemoteException(e);
            return "";
        }
    }

    /**
     * Get firmware version
     */
    public String getPrinterVersion(){
        if(sunmiPrinterService == null){
            //TODO Service disconnection processing
            return "";
        }
        try {
            return sunmiPrinterService.getPrinterVersion();
        } catch (RemoteException e) {
            handleRemoteException(e);
            return "";
        }
    }

    /**
     * Get paper specifications
     */
    public String getPrinterPaper(){
        if(sunmiPrinterService == null){
            //TODO Service disconnection processing
            return "";
        }
        try {
            return sunmiPrinterService.getPrinterPaper() == 1?"58mm":"80mm";
        } catch (RemoteException e) {
            handleRemoteException(e);
            return "";
        }
    }

    /**
     * Get paper specifications
     */
    public void getPrinterHead(InnerResultCallback callbcak){
        if(sunmiPrinterService == null){
            //TODO Service disconnection processing
            return;
        }
        try {
             sunmiPrinterService.getPrinterFactory(callbcak);
        } catch (RemoteException e) {
            handleRemoteException(e);
        }
    }

    /**
     * Get printing distance since boot
     * Get printing distance through interface callback since 1.0.8(printerlibrary)
     */
    public void getPrinterDistance(InnerResultCallback callback){
        if(sunmiPrinterService == null){
            //TODO Service disconnection processing
            return;
        }
        try {
            sunmiPrinterService.getPrintedLength(callback);
        } catch (RemoteException e) {
            handleRemoteException(e);
        }
    }

    /**
     * Set printer alignment
     */
    public void setAlign(int align){
        if(sunmiPrinterService == null){
            //TODO Service disconnection processing
            return;
        }
        try {
            sunmiPrinterService.setAlignment(align, null);
        } catch (RemoteException e) {
            handleRemoteException(e);
        }
    }

    /**
     *  Due to the distance between the paper hatch and the print head,
     *  the paper needs to be fed out automatically
     *  But if the Api does not support it, it will be replaced by printing three lines
     */
    public void feedPaper(){
        if(sunmiPrinterService == null){
            //TODO Service disconnection processing
            return;
        }

        try {
            sunmiPrinterService.autoOutPaper(null);
        } catch (RemoteException e) {
            print3Line();
        }
    }

    public void print3Line(){
        if(sunmiPrinterService == null){
            //TODO Service disconnection processing
            return;
        }

        try {
            sunmiPrinterService.lineWrap(3, null);
        } catch (RemoteException e) {
            handleRemoteException(e);
        }
    }

    /**
     * print text
     * setPrinterStyle Api require V4.2.22 or later, So use esc cmd instead when not supported
     *  More settings reference documentation {@link WoyouConsts}
     */
    public void printText(String content, float size, boolean isBold, boolean isUnderLine) {
        if(sunmiPrinterService == null){
            //TODO Service disconnection processing
            return;
        }

        try {
            try {
                sunmiPrinterService.setPrinterStyle(WoyouConsts.ENABLE_BOLD, isBold?
                        WoyouConsts.ENABLE: WoyouConsts.DISABLE);
            } catch (RemoteException e) {
                if (isBold) {
                    sunmiPrinterService.sendRAWData(ESCUtil.boldOn(), null);
                } else {
                    sunmiPrinterService.sendRAWData(ESCUtil.boldOff(), null);
                }
            }
            try {
                sunmiPrinterService.setPrinterStyle(WoyouConsts.ENABLE_UNDERLINE, isUnderLine?
                        WoyouConsts.ENABLE: WoyouConsts.DISABLE);
            } catch (RemoteException e) {
                if (isUnderLine) {
                    sunmiPrinterService.sendRAWData(ESCUtil.underlineWithOneDotWidthOn(), null);
                } else {
                    sunmiPrinterService.sendRAWData(ESCUtil.underlineOff(), null);
                }
            }
            sunmiPrinterService.printTextWithFont(content, null, size, null);
        } catch (RemoteException e) {
            e.printStackTrace();
        }

    }

    /**
     * print Bar Code
     */
    public void printBarCode(String data, int symbology, int height, int width, int textposition) {
        if(sunmiPrinterService == null){
            //TODO Service disconnection processing
            return;
        }

        try {
            sunmiPrinterService.printBarCode(data, symbology, height, width, textposition, null);
        } catch (RemoteException e) {
            e.printStackTrace();
        }
    }

    /**
     * print Qr Code
     */
    public void printQr(String data, int modulesize, int errorlevel) {
        if(sunmiPrinterService == null){
            //TODO Service disconnection processing
            return;
        }

        try {
            sunmiPrinterService.printQRCode(data, modulesize, errorlevel, null);
        } catch (RemoteException e) {
            e.printStackTrace();
        }
    }

    /**
     *  Open cash box
     *  This method can be used on Sunmi devices with a cash drawer interface
     *  If there is no cash box (such as V1、P1) or the call fails, an exception will be thrown
     *
     *  Reference to https://docs.sunmi.com/general-function-modules/external-device-debug/cash-box-driver/}
     */
    public void openCashBox(){
        if(sunmiPrinterService == null){
            //TODO Service disconnection processing
            return;
        }

        try {
            sunmiPrinterService.openDrawer(null);
        } catch (RemoteException e) {
            handleRemoteException(e);
        }
    }

    /**
     * LCD screen control
     * @param flag 1 —— Initialization
     *             2 —— Light up screen
     *             3 —— Extinguish screen
     *             4 —— Clear screen contents
     */
    public void controlLcd(int flag){
        if(sunmiPrinterService == null){
            //TODO Service disconnection processing
            return;
        }

        try {
            sunmiPrinterService.sendLCDCommand(flag);
        } catch (RemoteException e) {
            handleRemoteException(e);
        }
    }

    /**
     * Display text SUNMI,font size is 16 and format is fill
     * sendLCDFillString(txt, size, fill, callback)
     * Since the screen pixel height is 40, the font should not exceed 40
     */
    public void sendTextToLcd(String text){
        if(sunmiPrinterService == null){
            //TODO Service disconnection processing
            return;
        }

        try {
            sunmiPrinterService.sendLCDFillString(text, 18, false, new InnerLcdCallback() {
                @Override
                public void onRunResult(boolean show) throws RemoteException {
                    //TODO handle result
                }
            });
        } catch (RemoteException e) {
            e.printStackTrace();
        }

    }

    public void drawLine(){

        try {
            int paper = sunmiPrinterService.getPrinterPaper();

            sunmiPrinterService.setFontSize(receiptLineFontSize, null);
            if(paper == 1){
                sunmiPrinterService.printText("--------------------------------------------------\n", null);
            }else{
                sunmiPrinterService.printText("---------------------------------------------------------\n", null);
            }
        } catch (RemoteException e) {
            e.printStackTrace();
        }
    }

    private void drawOptionLine(){

        try {
            int paper = sunmiPrinterService.getPrinterPaper();

            sunmiPrinterService.setFontSize(receiptLineFontSize, null);
            if(paper == 1){
                sunmiPrinterService.printText("━━━━━━━━━━━━━━━━━━━\n", null);
            }else{
                sunmiPrinterService.printText("━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n", null);
            }
        } catch (RemoteException e) {
            e.printStackTrace();
        }
    }



    /**
     * JSON 형식의 주문 데이터를 받아 주문서를 출력합니다. (메서드 설명 수정)
     * @param orderJson JSON 형식의 주문 데이터
     * @param isCancel 취소 주문서 여부
     */
    public void printOrderFromJson(String orderJson, boolean isCancel) { // 메서드 시그니처 재확인
        if(sunmiPrinterService == null){
            Log.e("SunmiPrintHelper", "프린터 서비스에 연결되지 않았습니다.");
            return;
        }

        try {
            JSONObject jsonOrder = new JSONObject(orderJson);
            
            // 영수증 인쇄 시작
            sunmiPrinterService.printerInit(null);
            sunmiPrinterService.setAlignment(1, null); // 가운데 정렬
            sunmiPrinterService.lineWrap(1, null);
            // 취소 주문서인 경우 제목 추가
            if (isCancel) {
                sunmiPrinterService.printTextWithFont("[취소주문서]\n", null, receiptTitleFontSize, null);
                sunmiPrinterService.lineWrap(1, null);
            }
            
            // 볼드체 설정
            try {
                sunmiPrinterService.setPrinterStyle(WoyouConsts.ENABLE_BOLD, WoyouConsts.ENABLE);
            } catch (RemoteException e) {
                sunmiPrinterService.sendRAWData(ESCUtil.boldOn(), null);
            }

            // 주문번호 출력 (ordrSimpleId 또는 displayOrderNum)
            String displayNum = jsonOrder.optString("displayOrderNum", jsonOrder.optString("ordrSimpleId", ""));
            sunmiPrinterService.printTextWithFont("주문번호: " + displayNum + "\n", null, receiptOrderNumFontSize, null);
            sunmiPrinterService.lineWrap(1, null);
            // 사용자 이름 출력 (userName)
            String userName = jsonOrder.optString("userName", "");
            Log.d("userName", "printOrderFromJson userName: " + userName);

            if (!userName.isEmpty() && !userName.equals("null")) {
                sunmiPrinterService.printTextWithFont(userName + "님\n", null, receiptOrderNumFontSize, null);
            }

            String kioskId = jsonOrder.optString("kioskId", "");
            if(!kioskId.isEmpty() && !kioskId.equals("null")){
                sunmiPrinterService.printTextWithFont("키오스크: " + kioskId + "\n", null, receiptOrderNumFontSize, null);
            }

            // 주문 일시 출력 (ordrDtm)
            String orderDate = jsonOrder.optString("ordrDtm", "");
            
            sunmiPrinterService.lineWrap(1, null);
            sunmiPrinterService.setAlignment(0, null); // 왼쪽 정렬
            
            // 볼드체 해제
            try {
                sunmiPrinterService.setPrinterStyle(WoyouConsts.ENABLE_BOLD, WoyouConsts.DISABLE);
            } catch (RemoteException e) {
                sunmiPrinterService.sendRAWData(ESCUtil.boldOff(), null);
            }

            // 매장명 출력 (매장명 고정값 사용)
            String storeName = jsonOrder.optString("storeName", "");
            sunmiPrinterService.printTextWithFont(storeName + "\n", null, receiptInfoFontSize, null);
            // 주문 일시 출력
            sunmiPrinterService.setFontSize(receiptInfoFontSize, null);
            sunmiPrinterService.printTextWithFont("[일시] : " + orderDate + "\n", null, receiptInfoFontSize, null);
            
            // 구분선 출력
            drawLine();
            
            // 메뉴 헤더 출력
            sunmiPrinterService.setFontSize(receiptFontSize, null);
            String[] columnHeaders = new String[]{"메뉴", "수량"};
            int[] columnWidths = new int[]{3, 1};
            int[] columnAligns = new int[]{0, 2}; // 0:왼쪽, 1:가운데, 2:오른쪽
            sunmiPrinterService.printColumnsString(columnHeaders, columnWidths, columnAligns, null);

            // 구분선 출력
            drawLine();

            // 메뉴 목록 출력 (ordrPrdList 배열)
            JSONArray menuList = jsonOrder.optJSONArray("ordrPrdList");
            if (menuList != null && menuList.length() > 0) {
                for (int i = 0; i < menuList.length(); i++) {
                    JSONObject menuItem = menuList.getJSONObject(i);
                    
                    // 메뉴 이름과 수량 출력
                    String menuName = menuItem.optString("prdNm", "");
                    int menuCount = menuItem.optInt("ordrCnt", 0);
                    String countString = isCancel ? "-" + menuCount : String.valueOf(menuCount); // 취소 시 - 추가
                    
                    String[] menuData = new String[]{menuName, countString};
                sunmiPrinterService.setFontSize(receiptMenuFontSize, null);
                    sunmiPrinterService.printColumnsString(menuData, columnWidths, columnAligns, null);
                sunmiPrinterService.printTextWithFont(" \n", null, 10, null);
                    
                    // 옵션 목록 출력 (optPrdList 배열)
                    JSONArray optionList = menuItem.optJSONArray("optPrdList");
                    if (optionList != null && optionList.length() > 0) {
                        for (int j = 0; j < optionList.length(); j++) {
                            JSONObject optionItem = optionList.getJSONObject(j);
                            
                            String optionName = optionItem.optString("optPrdNm", "");
                            int optionCount = optionItem.optInt("optPrdCnt", 0);
                            String optionCountString = isCancel ? "-" + optionCount : String.valueOf(optionCount); // 취소 시 - 추가

                    sunmiPrinterService.setFontSize(receiptOptionFontSize, null);
                            String prefix = (j == 0) ? "› " : "  ";
                            String[] optionData = new String[]{prefix + optionName, optionCountString};
                            sunmiPrinterService.printColumnsString(optionData, columnWidths, columnAligns, null);
                        }
                    }
                    
                    // 마지막 메뉴가 아니면 구분선 출력
                    if (i < menuList.length() - 1) {
                    drawOptionLine();
                }
                }
            }
            
            // 구분선 출력
            drawLine();

            // 메모 출력 (ordrMemo)
            String memo = jsonOrder.optString("ordrMemo", "");
            if (!memo.isEmpty()) {
            sunmiPrinterService.printText(" \n", null);
                sunmiPrinterService.setAlignment(1, null); // 가운데 정렬
                sunmiPrinterService.printTextWithFont(memo + "\n", null, receiptFontSize, null);
                sunmiPrinterService.setAlignment(0, null); // 왼쪽 정렬
                // 주문서에서는 메모 다음에 구분선 추가 안 함 (선택)
            }
            
            // 여백 및 마무리
            sunmiPrinterService.printText(" \n", null);
            sunmiPrinterService.printText(" \n", null);
            sunmiPrinterService.setAlignment(1, null); // 가운데 정렬

            // 볼드체 설정 (마무리 문구용, 선택적)
            try {
                sunmiPrinterService.setPrinterStyle(WoyouConsts.ENABLE_BOLD, WoyouConsts.ENABLE);
            } catch (RemoteException e) {
                sunmiPrinterService.sendRAWData(ESCUtil.boldOn(), null);
            }

            // 마무리 문구 등 추가 가능
            // sunmiPrinterService.printTextWithFont("주문해주셔서 감사합니다.\n", null, receiptFontSize, null);

            // 여백 및 용지 출력

            // 용지 자동 배출 또는 커팅
            try {
                sunmiPrinterService.autoOutPaper(null);
            } catch (Exception e) {
                Log.e("SunmiPrintHelper", "용지 배출 오류: " + e.getMessage());
                cutpaper();
            }

        } catch (JSONException e) {
            Log.e("SunmiPrintHelper", "JSON 파싱 오류: " + e.getMessage());
        } catch (RemoteException e) {
            Log.e("SunmiPrintHelper", "프린터 원격 오류: " + e.getMessage());
        } catch (Exception e) {
            Log.e("SunmiPrintHelper", "기타 오류: " + e.getMessage());
        }
    }

    /**
     * JSON 형식의 주문 데이터를 받아 영수증을 출력합니다.
     * @param orderJson JSON 형식의 주문 데이터
     * @param isCancel 취소 영수증 여부
     */
    public void printReceiptFromJson(String orderJson, boolean isCancel) {
        if(sunmiPrinterService == null){
            Log.e("SunmiPrintHelper", "프린터 서비스에 연결되지 않았습니다.");
            return;
        }
        
        try {
            JSONObject jsonOrder = new JSONObject(orderJson);
            
            // 영수증 인쇄 시작
            sunmiPrinterService.printerInit(null);
            sunmiPrinterService.setAlignment(1, null); // 가운데 정렬
            sunmiPrinterService.lineWrap(1, null);
            // 취소 영수증인 경우 제목 추가
            if (isCancel) {
                sunmiPrinterService.printTextWithFont("[취소영수증]\n", null, receiptTitleFontSize, null);
                sunmiPrinterService.lineWrap(1, null);
            }
            
            // 볼드체 설정
            try {
                sunmiPrinterService.setPrinterStyle(WoyouConsts.ENABLE_BOLD, WoyouConsts.ENABLE);
            } catch (RemoteException e) {
                sunmiPrinterService.sendRAWData(ESCUtil.boldOn(), null);
            }
            // 주문번호 출력
            String displayNum = jsonOrder.optString("displayOrderNum", jsonOrder.optString("ordrSimpleId", ""));
            sunmiPrinterService.printTextWithFont("주문번호 : " + displayNum + "\n", null, receiptOrderNumFontSize, null);
            sunmiPrinterService.printTextWithFont("〓〓〓〓〓〓〓〓〓〓〓〓〓〓〓〓〓〓〓〓〓〓〓〓〓〓〓〓〓〓〓〓〓〓〓〓〓〓〓〓〓〓〓〓\n", null, 13, null);
            sunmiPrinterService.lineWrap(1, null);
            
            // 왼쪽 정렬 및 줄 간격 설정
            sunmiPrinterService.setAlignment(0, null);
            try {
                sunmiPrinterService.setPrinterStyle(WoyouConsts.SET_LINE_SPACING, 0);
            } catch (RemoteException e) {
                sunmiPrinterService.sendRAWData(new byte[]{0x1B, 0x33, 0x00}, null);
            }
            
            // 볼드체 해제
            try {
                sunmiPrinterService.setPrinterStyle(WoyouConsts.ENABLE_BOLD, WoyouConsts.DISABLE);
            } catch (RemoteException e) {
                sunmiPrinterService.sendRAWData(ESCUtil.boldOff(), null);
            }

            // 매장명 출력
            String storeName = jsonOrder.optString("storeName", "");
            sunmiPrinterService.setFontSize(receiptFontSize, null);
            sunmiPrinterService.printTextWithFont(storeName + "\n", null, receiptFontSize, null);

            // 주문 일시 출력
            String orderDate = jsonOrder.optString("ordrDtm", "");
            sunmiPrinterService.printTextWithFont("[일시]   : " + orderDate + "\n", null, receiptInfoFontSize, null);
            sunmiPrinterService.lineWrap(1, null);
            
            // 구분선 출력
            drawLine();

            // 메뉴 헤더 출력
                    sunmiPrinterService.setFontSize(receiptFontSize, null);
            String[] columnHeaders = new String[]{"메뉴", "수량", "금액"};
            int[] columnWidths = new int[]{5, 1, 2};
            int[] columnAligns = new int[]{0, 2, 2};
            sunmiPrinterService.printColumnsString(columnHeaders, columnWidths, columnAligns, null);
            
            // 구분선 출력
                        drawLine();
            // 메뉴 목록 출력
            JSONArray menuList = jsonOrder.optJSONArray("ordrPrdList");
            if (menuList != null && menuList.length() > 0) {
                for (int i = 0; i < menuList.length(); i++) {
                    JSONObject menuItem = menuList.getJSONObject(i);
                    
                    // 메뉴 이름, 수량, 금액 출력
                    String menuName = menuItem.optString("prdNm", "");
                    int menuCount = menuItem.optInt("ordrCnt", 0);
                    double menuPrice = menuItem.optDouble("prdPrc", 0.0);
                    String countString = isCancel ? "-" + menuCount : String.valueOf(menuCount); // 취소 시 - 추가
                    String amountString = isCancel ? "-" + getPriceFormatter((int) (menuPrice * menuCount))  : getPriceFormatter((int) (menuPrice * menuCount)); // 취소 시 - 추가 및 정수 변환
                    
                    String[] menuData = new String[]{
                        menuName,
                        countString, // 수정된 수량 문자열
                        amountString // 수정된 금액 문자열
                    };

            sunmiPrinterService.setFontSize(receiptMenuFontSize, null);
                    sunmiPrinterService.printColumnsString(menuData, columnWidths, columnAligns, null);
            sunmiPrinterService.printTextWithFont(" \n", null, 10, null);
                    
                    // 옵션 목록 출력
                    JSONArray optionList = menuItem.optJSONArray("optPrdList");
                    if (optionList != null && optionList.length() > 0) {
                        for (int j = 0; j < optionList.length(); j++) {
                            JSONObject optionItem = optionList.getJSONObject(j);
                            
                            String optionName = optionItem.optString("optPrdNm", "");
                            int optionCount = optionItem.optInt("optPrdCnt", 0);
                            double optionPrice = optionItem.optDouble("optPrdPrc", 0.0);
                            String optionCountString = isCancel ? "-" + optionCount : String.valueOf(optionCount); // 취소 시 - 추가
                            String optionAmountString = isCancel ? "-" + getPriceFormatter((int)(optionPrice * optionCount)) : getPriceFormatter((int)(optionPrice * optionCount)); // 취소 시 - 추가 및 정수 변환
                            
                            sunmiPrinterService.setFontSize(receiptOptionFontSize, null);
                            String prefix = (j == 0) ? "› " : "  ";
                            String[] optionData = new String[]{
                                prefix + optionName,
                                optionCountString, // 수정된 수량 문자열
                                optionAmountString // 수정된 금액 문자열
                            };
                            sunmiPrinterService.printColumnsString(optionData, columnWidths, columnAligns, null);
                        }
                    }
                    
                    // 구분선 출력
                    if (i < menuList.length() - 1) {
                        drawOptionLine();
                    }
                }
            }
            
            // 구분선 출력
            drawLine();

            // 세금 정보 출력 (취소 시에도 그대로 표시)
                        sunmiPrinterService.setFontSize(receiptOptionFontSize, null);
            String exceptTaxPriceStr = jsonOrder.optString("exceptTaxPrice", "0");
            String taxPriceStr = jsonOrder.optString("taxPrice", "0");
            
            String[] taxData = new String[]{"과세금액", exceptTaxPriceStr};
            int[] taxWidths = new int[]{1, 1};
            int[] taxAligns = new int[]{2, 2};
            sunmiPrinterService.printColumnsString(taxData, taxWidths, taxAligns, null);
            
            taxData[0] = "부가세";
            taxData[1] = taxPriceStr;
            sunmiPrinterService.printColumnsString(taxData, taxWidths, taxAligns, null);
            
            // 구분선 출력
                        drawLine();
            
            // 결제 정보 출력 (취소 시에도 그대로 표시)
            sunmiPrinterService.setFontSize(receiptMenuFontSize, null);
            String[] priceData = new String[]{"메뉴", "수량"}; // 헤더는 실제 사용 안함
            int[] priceWidths = new int[]{1, 1};
            int[] priceAligns = new int[]{0, 2};
            
            // 주문금액
            priceData[0] = "주문금액 : ";
            priceData[1] = jsonOrder.optString("ordrPrc", "0");
            sunmiPrinterService.printColumnsString(priceData, priceWidths, priceAligns, null);
            
            // 할인금액
            String discPrcStr = jsonOrder.optString("discPrc", "0");
            priceData[0] = "할인금액 : ";
            priceData[1] = discPrcStr.equals("0") ? "0" : "-" + discPrcStr;
            sunmiPrinterService.printColumnsString(priceData, priceWidths, priceAligns, null);
            
            // 결제금액
            priceData[0] = "결제금액 : ";
            priceData[1] = jsonOrder.optString("payPrc", "0");
            sunmiPrinterService.printColumnsString(priceData, priceWidths, priceAligns, null);
            
            // 구분선 출력
            drawLine();


            // 메모 출력
            String memo = jsonOrder.optString("ordrMemo", "");
            if (!memo.isEmpty()) {
            sunmiPrinterService.setAlignment(1, null);
                sunmiPrinterService.printTextWithFont(memo + "\n", null, receiptFontSize, null);
            sunmiPrinterService.setAlignment(0, null);
            drawLine();
            }
            
            // 여백 및 마무리
            sunmiPrinterService.printText(" \n", null);
            sunmiPrinterService.printText(" \n", null);

            // 매장명 출력
            sunmiPrinterService.setAlignment(1, null);
            try {
                sunmiPrinterService.setPrinterStyle(WoyouConsts.ENABLE_BOLD, WoyouConsts.ENABLE);
            } catch (RemoteException e) {
                sunmiPrinterService.sendRAWData(ESCUtil.boldOn(), null);
            }

            /*sunmiPrinterService.printTextWithFont(storeName + "\n", null, receiptTitleFontSize, null);
            sunmiPrinterService.printText(" \n", null);
            sunmiPrinterService.printText(" \n", null);
            sunmiPrinterService.printText(" \n", null);*/



            if(MainActivity.bitmapLogoForPrint != null)sunmiPrinterService.printBitmap(MainActivity.bitmapLogoForPrint, null);
            sunmiPrinterService.printText(" \n", null);
            sunmiPrinterService.printText(" \n", null);
            sunmiPrinterService.printText(" \n", null);

            // 용지 자동 배출 또는 커팅
            try {
                sunmiPrinterService.autoOutPaper(null);
            } catch (Exception e) {
                Log.e("SunmiPrintHelper", "용지 배출 오류: " + e.getMessage());
                cutpaper();
            }

        } catch (JSONException e) {
            Log.e("SunmiPrintHelper", "JSON 파싱 오류: " + e.getMessage());
        } catch (RemoteException e) {
            Log.e("SunmiPrintHelper", "프린터 원격 오류: " + e.getMessage());
        } catch (Exception e) {
            Log.e("SunmiPrintHelper", "기타 오류: " + e.getMessage());
        }
    }

    // 테스트용 빈 메서드 (MainActivity에서 호출되는 파라미터 없는 메서드)
    public void printConfirmOrder() {
        Log.d("SunmiPrintHelper", "테스트 영수증 출력");
        
        if(sunmiPrinterService == null){
            Log.e("SunmiPrintHelper", "프린터 서비스에 연결되지 않았습니다.");
            return;
        }

        try {
            // 간단한 테스트 영수증 출력
            sunmiPrinterService.printerInit(null);
            sunmiPrinterService.setAlignment(1, null);
            sunmiPrinterService.printTextWithFont("테스트 영수증\n", null, receiptTitleFontSize, null);
                sunmiPrinterService.printText(" \n", null);
            sunmiPrinterService.printTextWithFont("영수증 테스트입니다\n", null, receiptFontSize, null);
                sunmiPrinterService.printText(" \n", null);
            sunmiPrinterService.printText(" \n", null);
            sunmiPrinterService.printText(" \n", null);

            try {
                sunmiPrinterService.autoOutPaper(null);
            } catch (Exception e) {
                Log.e("SunmiPrintHelper", "용지 배출 오류: " + e.getMessage());
                cutpaper();
            }
        } catch (RemoteException e) {
            Log.e("SunmiPrintHelper", "프린터 원격 오류: " + e.getMessage());
        }
    }


    public static String getPriceFormatter(int price)
    {
        NumberFormat formatter = new DecimalFormat("#,###");
        String formattedNumber = formatter.format(price);
        return formattedNumber;
    }
}
