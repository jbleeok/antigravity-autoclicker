#Requires AutoHotkey v2.0

; ============================================================
;  AppGui.ahk — 메인 GUI + 설정 다이얼로그 + 시스템 트레이
; ============================================================

class AppGui {
    static IniPath := A_ScriptDir . "\WhisperSTT.ini"
    static recorder := ""
    static devices := []
    static mainGui := ""
    static micDropdown := ""
    static btnRecord := ""
    static editResult := ""
    static isProcessing := false

    static Create() {
        try TraySetIcon("C:\Windows\System32\mmres.dll", 14) ; 마이크 아이콘
        this.recorder := WaveAudioRecorder(16000, 1, 16)
        this.devices := GetAudioInputDevices()

        ; ── 메인 GUI ──
        this.mainGui := Gui("+AlwaysOnTop -MaximizeBox +Resize -MinimizeBox", "🎙️ WhisperSTT")
        this.mainGui.SetFont("s9", "Segoe UI")
        this.mainGui.BackColor := "202020"
        this.mainGui.MarginX := 10
        this.mainGui.MarginY := 8

        ; 다크 모드 타이틀바 (Win10 1809+)
        if (VerCompare(A_OSVersion, "10.0.17763") >= 0) {
            attr := (VerCompare(A_OSVersion, "10.0.18985") >= 0) ? 20 : 19
            DllCall("dwmapi\DwmSetWindowAttribute", "Ptr", this.mainGui.Hwnd,
                    "Int", attr, "Int*", 1, "Int", 4)
        }

        ; 마이크 선택 라벨
        this.mainGui.SetFont("s8 cA0A0A0")
        this.mainGui.Add("Text", "x10 y8 w230", "INPUT DEVICE")

        ; 설정 버튼
        this.mainGui.SetFont("s10 cD0D0D0")
        btnSettings := this.mainGui.Add("Button", "x270 y4 w30 h24", "⚙")
        btnSettings.OnEvent("Click", (*) => this.ShowSettings())

        ; 마이크 드롭다운
        micNames := ["시스템 기본 장치"]
        for d in this.devices
            micNames.Push(d.name)

        savedMicIndex := Integer(IniRead(this.IniPath, "Audio", "DeviceIndex", "1"))
        if (savedMicIndex > micNames.Length || savedMicIndex < 1)
            savedMicIndex := 1

        this.mainGui.SetFont("s9 cE0E0E0")
        this.micDropdown := this.mainGui.Add("DropDownList", "x10 y28 w290 Choose" . savedMicIndex, micNames)
        this.micDropdown.OnEvent("Change", (*) => IniWrite(this.micDropdown.Value, this.IniPath, "Audio", "DeviceIndex"))

        ; 녹음 버튼 (상태 표시)
        this.mainGui.SetFont("s10 cE0E0E0 Bold")
        this.btnRecord := this.mainGui.Add("Button", "x10 y60 w290 h30", "🎤  F9를 꾹 눌러 말하세요")
        this.btnRecord.Enabled := false  ; 표시용 (실제 녹음은 F9 핫키로)

        ; 결과 라벨
        this.mainGui.SetFont("s8 cA0A0A0 Norm")
        this.mainGui.Add("Text", "x10 y96 w290", "LAST TRANSCRIPTION")

        ; 결과 텍스트
        this.mainGui.SetFont("s9 cE0E0E0 Norm")
        this.editResult := this.mainGui.Add("Edit", "x10 y114 w290 r2 ReadOnly -E0x200 Background2A2A2A",
            "준비 완료. F9를 꾹 누르고 말하세요.")

        ; 이벤트
        this.mainGui.OnEvent("Close", (*) => this.OnClose())
        this.mainGui.OnEvent("Size", (*) => this.OnResize())

        ; 트레이 메뉴 설정
        this.SetupTray()

        ; 저장된 위치 복원
        savedX := IniRead(this.IniPath, "Window", "X", "")
        savedY := IniRead(this.IniPath, "Window", "Y", "")
        if (savedX != "" && savedY != "")
            this.mainGui.Show("x" . savedX . " y" . savedY . " w310 h165")
        else
            this.mainGui.Show("w310 h165")
    }

    static SetupTray() {
        A_IconTip := "WhisperSTT — F9로 음성 입력"
        tray := A_TrayMenu
        tray.Delete()
        tray.Add("WhisperSTT 열기", (*) => this.mainGui.Show())
        tray.Add("설정", (*) => this.ShowSettings())
        tray.Add()
        tray.Add("종료", (*) => this.ExitApp())
        tray.Default := "WhisperSTT 열기"
        tray.ClickCount := 1
    }

    static GetSelectedDeviceId() {
        selIndex := this.micDropdown.Value
        if (selIndex <= 1)
            return -1  ; WAVE_MAPPER (기본 장치)
        return this.devices[selIndex - 1].id
    }

    static SetState(state) {
        switch state {
            case "ready":
                this.btnRecord.Text := "🎤  F9를 꾹 눌러 말하세요"
                this.isProcessing := false
            case "recording":
                this.btnRecord.Text := "🔴  녹음 중... (F9에서 손을 떼세요)"
            case "processing":
                this.btnRecord.Text := "⏳  텍스트 변환 중..."
                this.isProcessing := true
            case "done":
                this.btnRecord.Text := "✅  완료! 클립보드에 복사됨"
                SetTimer(() => this.SetState("ready"), -2000)
            case "error":
                this.btnRecord.Text := "❌  오류 발생"
                SetTimer(() => this.SetState("ready"), -3000)
        }
    }

    static SetTranscription(text) {
        this.editResult.Value := text
    }

    static ShowSettings() {
        sg := Gui("+Owner" . this.mainGui.Hwnd . " +ToolWindow", "⚙ WhisperSTT 설정")
        sg.SetFont("s9", "Segoe UI")
        sg.BackColor := "252525"
        sg.MarginX := 15
        sg.MarginY := 10

        ; 서버 주소
        sg.SetFont("s8 cA0A0A0")
        sg.Add("Text", "x15 y10 w310", "WHISPER 서버 주소")
        sg.SetFont("s9 cE0E0E0")
        edEndpoint := sg.Add("Edit", "x15 y28 w310",
            IniRead(this.IniPath, "API", "Endpoint", "http://localhost:8000/v1/audio/transcriptions"))

        ; 모델 / 언어
        sg.SetFont("s8 cA0A0A0")
        sg.Add("Text", "x15 y60 w145", "모델")
        sg.Add("Text", "x180 y60 w145", "언어 (빈칸=자동감지)")

        sg.SetFont("s9 cE0E0E0")
        modelChoices := ["tiny", "base", "small", "medium", "large-v3"]
        savedModel := IniRead(this.IniPath, "API", "Model", "medium")
        modelIdx := 1
        for i, m in modelChoices {
            if (m == savedModel)
                modelIdx := i
        }
        ddModel := sg.Add("DropDownList", "x15 y78 w145 Choose" . modelIdx, modelChoices)

        edLang := sg.Add("Edit", "x180 y78 w145",
            IniRead(this.IniPath, "API", "Language", ""))

        ; 체크박스들
        sg.SetFont("s9 cD0D0D0")
        chkPaste := sg.Add("Checkbox", "x15 y115 w310", "변환 후 자동 붙여넣기 (Ctrl+V)")
        chkPaste.Value := Integer(IniRead(this.IniPath, "API", "AutoPaste", "1"))

        chkAuto := sg.Add("Checkbox", "x15 y140 w310", "Windows 로그인 시 자동 시작")
        chkAuto.Value := this.IsAutoStartEnabled()

        ; 버튼
        btnSave := sg.Add("Button", "x140 y175 w85 h28 Default", "저장")
        btnCancel := sg.Add("Button", "x240 y175 w85 h28", "취소")

        btnSave.OnEvent("Click", (*) => this._SaveSettings(sg, edEndpoint, ddModel, modelChoices, edLang, chkPaste, chkAuto))
        btnCancel.OnEvent("Click", (*) => sg.Destroy())

        sg.Show("w340 h215")
    }

    static _SaveSettings(sg, edEndpoint, ddModel, modelChoices, edLang, chkPaste, chkAuto) {
        IniWrite(edEndpoint.Value, this.IniPath, "API", "Endpoint")
        IniWrite(modelChoices[ddModel.Value], this.IniPath, "API", "Model")
        IniWrite(edLang.Value, this.IniPath, "API", "Language")
        IniWrite(chkPaste.Value, this.IniPath, "API", "AutoPaste")
        this.SetAutoStart(chkAuto.Value)
        sg.Destroy()
    }

    static OnResize() {
        ; 리사이즈 무시 (고정 크기)
    }

    static OnClose() {
        this.SaveWindowPos()
        this.mainGui.Hide()
        TrayTip("WhisperSTT가 트레이에서 실행 중입니다.`nF9로 음성 입력이 가능합니다.", "WhisperSTT", 1)
    }

    static SaveWindowPos() {
        try {
            this.mainGui.GetPos(&x, &y)
            if (x > -10000 && y > -10000) {
                IniWrite(x, this.IniPath, "Window", "X")
                IniWrite(y, this.IniPath, "Window", "Y")
            }
        }
    }

    static ExitApp() {
        this.SaveWindowPos()
        ExitApp()
    }

    ; ── 자동 시작 (레지스트리) ──
    static SetAutoStart(enable) {
        regKey := "HKCU\Software\Microsoft\Windows\CurrentVersion\Run"
        appName := "WhisperSTT"
        if enable {
            cmd := A_IsCompiled
                ? ('"' . A_ScriptFullPath . '"')
                : ('"' . A_AhkPath . '" "' . A_ScriptFullPath . '"')
            RegWrite(cmd, "REG_SZ", regKey, appName)
        } else {
            try RegDelete(regKey, appName)
        }
    }

    static IsAutoStartEnabled() {
        try {
            val := RegRead("HKCU\Software\Microsoft\Windows\CurrentVersion\Run", "WhisperSTT")
            return (val != "")
        } catch {
            return false
        }
    }
}
