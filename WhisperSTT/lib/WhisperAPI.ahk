#Requires AutoHotkey v2.0

; ============================================================
;  WhisperAPI.ahk — WhisperLive REST API 통신 모듈
;  WinHttp COM으로 multipart/form-data POST 전송
; ============================================================

TranscribeAudio(endpoint, wavFilePath, model := "medium", language := "") {
    boundary := "----WhisperSTTBoundary" . A_TickCount . Random(100000, 999999)
    CRLF := "`r`n"

    ; WAV 파일 읽기
    fileBytes := FileRead(wavFilePath, "RAW")
    if (!fileBytes || fileBytes.Size == 0)
        throw Error("WAV 파일을 읽을 수 없습니다: " . wavFilePath)

    ; multipart body 구성
    headerText := "--" . boundary . CRLF
    headerText .= 'Content-Disposition: form-data; name="response_format"' . CRLF . CRLF
    headerText .= "text" . CRLF

    if (model != "") {
        headerText .= "--" . boundary . CRLF
        headerText .= 'Content-Disposition: form-data; name="model"' . CRLF . CRLF
        headerText .= model . CRLF
    }

    if (language != "") {
        headerText .= "--" . boundary . CRLF
        headerText .= 'Content-Disposition: form-data; name="language"' . CRLF . CRLF
        headerText .= language . CRLF
    }

    headerText .= "--" . boundary . CRLF
    headerText .= 'Content-Disposition: form-data; name="file"; filename="audio.wav"' . CRLF
    headerText .= "Content-Type: audio/wav" . CRLF . CRLF

    footerText := CRLF . "--" . boundary . "--" . CRLF

    ; UTF-8 인코딩
    headLen := StrPut(headerText, "UTF-8") - 1
    headBuf := Buffer(headLen)
    StrPut(headerText, headBuf, "UTF-8")

    footLen := StrPut(footerText, "UTF-8") - 1
    footBuf := Buffer(footLen)
    StrPut(footerText, footBuf, "UTF-8")

    totalSize := headLen + fileBytes.Size + footLen

    ; COM SafeArray 생성 (VT_UI1 = 0x11)
    safeArray := ComObjArray(0x11, totalSize)

    ; SafeArray 잠금 → 바이너리 데이터 복사
    pData := 0
    DllCall("oleaut32\SafeArrayAccessData", "Ptr", ComObjValue(safeArray), "Ptr*", &pData)

    DllCall("RtlMoveMemory", "Ptr", pData, "Ptr", headBuf.Ptr, "UPtr", headLen)
    offset := headLen

    DllCall("RtlMoveMemory", "Ptr", pData + offset, "Ptr", fileBytes.Ptr, "UPtr", fileBytes.Size)
    offset += fileBytes.Size

    DllCall("RtlMoveMemory", "Ptr", pData + offset, "Ptr", footBuf.Ptr, "UPtr", footLen)

    DllCall("oleaut32\SafeArrayUnaccessData", "Ptr", ComObjValue(safeArray))

    ; HTTP POST 전송
    http := ComObject("WinHttp.WinHttpRequest.5.1")
    http.Open("POST", endpoint, false)
    http.SetTimeouts(5000, 5000, 30000, 60000)
    http.SetRequestHeader("Content-Type", "multipart/form-data; boundary=" . boundary)

    try {
        http.Send(safeArray)
    } catch Error as err {
        throw Error("네트워크 요청 실패: " . err.Message)
    }

    if (http.Status != 200) {
        throw Error("서버 오류 (HTTP " . http.Status . "): " . http.ResponseText)
    }

    ; response_format=text이므로 순수 텍스트 반환
    result := http.ResponseText
    ; 앞뒤 공백/줄바꿈 제거
    result := Trim(result, " `t`r`n")
    return result
}
