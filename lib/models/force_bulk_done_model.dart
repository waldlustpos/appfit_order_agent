/// `PUT /v0/orders/force/bulk-done` 응답 모델.
///
/// 이 엔드포인트는 **부분 실패해도 200** 이다. HTTP 상태코드로는 성공/실패를 가릴 수
/// 없고, 건별 결과인 [ForceBulkDoneResponse.results] 를 봐야 한다. 단건 호출이라고
/// `updateSuccessCount` 로 판정하면 안 되는 이유이기도 하다 — 요청한 주문이 대상에서
/// 아예 빠졌는지(`results` 에 없음), 대상이었는데 실패했는지(`success:false`)를
/// 카운터는 구분하지 못한다.
///
/// 이름이 비슷한 `bulkOrdersDone`(`/v0/orders/bulk-done`) 은 **다른 DTO** 를 쓴다
/// (기간 단위, 건별 결과 없음). 그쪽 응답을 이 모델로 파싱하면 `results` 가 빈
/// 배열이 되어 모든 판정이 실패로 떨어진다.
library;

/// 강제 완료 요청 중 **주문 1건**의 처리 결과.
class ForceBulkDoneResult {
  final String orderNo;

  /// 강제 완료 성공 여부.
  ///
  /// **멱등이다** — 서버 스펙상 "이미 완료된 주문은 성공으로 응답한다". 중복 클릭이나
  /// 타임아웃 후 재시도가 안전하다는 뜻이므로, 호출부가 별도 중복 방지를 겹겹이
  /// 쌓을 필요는 없다(그래도 in-flight 락은 UI 피드백을 위해 유지한다).
  final bool success;

  /// 실패 시 서버 에러 코드. 성공 시 null.
  ///
  /// 관측된 값: `NOT_FOUND_ORDER`, `ACCESS_DENIED`, `INVALID_ORDER_STATUS`,
  /// `ORDER_STATUS_UPDATE_FAILED`. enum 으로 굳히지 않는다 — 서버가 값을 늘리면
  /// 파싱이 깨지는 쪽이 손해다.
  final String? errorCode;

  /// 실패 사유(사람이 읽는 문장). 성공 시 null.
  final String? message;

  const ForceBulkDoneResult({
    required this.orderNo,
    required this.success,
    this.errorCode,
    this.message,
  });

  factory ForceBulkDoneResult.fromJson(Map<String, dynamic> json) {
    return ForceBulkDoneResult(
      orderNo: json['orderNo']?.toString() ?? '',
      success: json['success'] == true,
      errorCode: json['errorCode']?.toString(),
      message: json['message']?.toString(),
    );
  }

  Map<String, dynamic> toJson() => {
        'orderNo': orderNo,
        'success': success,
        if (errorCode != null) 'errorCode': errorCode,
        if (message != null) 'message': message,
      };

  @override
  String toString() => 'ForceBulkDoneResult($orderNo, success: $success'
      '${errorCode != null ? ', $errorCode' : ''}'
      '${message != null ? ', $message' : ''})';
}

/// 강제 완료 일괄 처리 응답 전체.
class ForceBulkDoneResponse {
  /// 중복 제거 후 처리 대상 수. [results] 의 길이와 같다.
  final int targetOrderCount;
  final int updateSuccessCount;
  final int updateFailCount;

  /// 요청 순서를 보존한 건별 결과. 단, **인덱스로 찾지 말 것** — 중복 주문번호가
  /// 1건으로 합쳐지면 요청 배열과 길이가 어긋난다. [resultFor] 를 쓴다.
  final List<ForceBulkDoneResult> results;

  const ForceBulkDoneResponse({
    required this.targetOrderCount,
    required this.updateSuccessCount,
    required this.updateFailCount,
    required this.results,
  });

  factory ForceBulkDoneResponse.fromJson(Map<String, dynamic> json) {
    final rawResults = json['results'];
    return ForceBulkDoneResponse(
      targetOrderCount:
          int.tryParse(json['targetOrderCount']?.toString() ?? '') ?? 0,
      updateSuccessCount:
          int.tryParse(json['updateSuccessCount']?.toString() ?? '') ?? 0,
      updateFailCount:
          int.tryParse(json['updateFailCount']?.toString() ?? '') ?? 0,
      results: rawResults is List
          ? rawResults
              .whereType<Map<String, dynamic>>()
              .map(ForceBulkDoneResult.fromJson)
              .toList()
          : const <ForceBulkDoneResult>[],
    );
  }

  Map<String, dynamic> toJson() => {
        'targetOrderCount': targetOrderCount,
        'updateSuccessCount': updateSuccessCount,
        'updateFailCount': updateFailCount,
        'results': results.map((r) => r.toJson()).toList(),
      };

  /// [orderNo] 의 처리 결과. 대상에서 빠졌으면 null.
  ForceBulkDoneResult? resultFor(String orderNo) {
    for (final r in results) {
      if (r.orderNo == orderNo) return r;
    }
    return null;
  }

  /// [orderNo] 가 완료 처리됐는지. 대상에서 빠진 경우(null)는 **실패로 본다** —
  /// 요청했는데 결과가 없다는 건 서버가 그 주문을 건드리지 않았다는 뜻이다.
  bool isSuccessFor(String orderNo) => resultFor(orderNo)?.success == true;

  @override
  String toString() => 'ForceBulkDoneResponse(target: $targetOrderCount, '
      'success: $updateSuccessCount, fail: $updateFailCount, '
      'results: ${results.length})';
}
