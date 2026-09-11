#Requires AutoHotkey v2.0
#SingleInstance Force

; ============================================================
;  WhisperSTT.ahk — Push-to-Talk 음성 인식 (메인 스크립트)
;
;  F9를 꾹 누르면 녹음 → 손 떼면 WhisperLive 서버로 전송
;  → STT 결과를 클립보드에 복사 + 자동 붙여넣기
; ============================================================

#Include lib\AudioRecorder.ahk
#Include lib\WhisperAPI.ahk
#Include lib\AppGui.ahk

; 앱 초기화
AppGui.Create()

; ── F9 Push-to-Talk 핫키 ──
*F9:: {
    static isKeyHeld := false

    ; OS 키 리피트 방지
    if isKeyHeld
        return
    ; 처리 중이면 무시
    if AppGui.isProcessing
        return

    isKeyHeld := true

    ; 1. 선택된 마이크 장치 ID
    devId := AppGui.GetSelectedDeviceId()

    ; 2. 녹음 시작
    AppGui.SetState("recording")
    try {
        AppGui.recorder.Start(devId)
    } catch Error as err {
        AppGui.SetTranscription("마이크 오류: " . err.Message)
        AppGui.SetState("error")
        isKeyHeld := false
        return
    }

    ; 3. F9를 떼기를 기다림 (이 동안 메시지 펌프는 계속 돌아 오디오 콜백 수신)
    KeyWait("F9")

    ; 4. 녹음 중지 + WAV 저장
    wavFile := A_Temp . "\whisper_stt_temp.wav"
    try {
        AppGui.recorder.Stop(wavFile)
    } catch Error as err {
        AppGui.SetTranscription("녹음 중지 오류: " . err.Message)
        AppGui.SetState("error")
        isKeyHeld := false
        return
    }

    isKeyHeld := false

    ; 5. 너무 짧은 녹음 무시 (0.3초 미만 = 9600 bytes 미만)
    try {
        fileObj := FileOpen(wavFile, "r")
        fSize := fileObj.Length
        fileObj.Close()
        if (fSize < 9644) {  ; WAV 헤더 44 + 최소 PCM 데이터
            AppGui.SetTranscription("녹음이 너무 짧습니다. 좀 더 길게 눌러주세요.")
            AppGui.SetState("ready")
            try FileDelete(wavFile)
            return
        }
    }

    ; 6. API 호출 (별도 타이머 스레드로 GUI 블록 방지)
    AppGui.SetState("processing")
    SetTimer(ProcessTranscription.Bind(wavFile), -1)
}

ProcessTranscription(wavFile) {
    endpoint := IniRead(AppGui.IniPath, "API", "Endpoint",
        "http://localhost:8000/v1/audio/transcriptions")
    model := IniRead(AppGui.IniPath, "API", "Model", "medium")
    lang := IniRead(AppGui.IniPath, "API", "Language", "")
    autoPaste := Integer(IniRead(AppGui.IniPath, "API", "AutoPaste", "1"))

    try {
        text := TranscribeAudio(endpoint, wavFile, model, lang)

        if (text == "") {
            AppGui.SetTranscription("(인식된 텍스트 없음)")
            AppGui.SetState("ready")
        } else {
            AppGui.SetTranscription(text)

            ; 클립보드에 복사
            A_Clipboard := text

            ; 자동 붙여넣기
            if (autoPaste) {
                Sleep(50)
                Send("^v")
            }

            AppGui.SetState("done")
        }
    } catch Error as err {
        AppGui.SetTranscription("오류: " . err.Message)
        AppGui.SetState("error")
    } finally {
        try FileDelete(wavFile)
    }
}
