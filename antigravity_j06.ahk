#Requires AutoHotkey v2.0
#SingleInstance Force
#Include <FindText>

; ==============================================================================
; 전역 변수 및 설정
; ==============================================================================
SetTitleMatchMode "RegEx" ; 정규식을 사용하여 프로세스 이름의 일부만으로도 매칭 가능하게 설정

global IniFile := A_ScriptDir "\antigravity_j06.ini"
global autoEnabled := 0
global guiX := ""
global guiY := ""
global scanIntervalMs := 2000

global autoClickTargets := []
global findTextTargets := []   ; FindText 검색 문자열 목록 (INI [FindTextTargets]에서 로딩)

; ==============================================================================
; INI 파일 처리
; ==============================================================================
LoadSettings() {
    global autoEnabled, guiX, guiY, scanIntervalMs, autoClickTargets, findTextTargets

    if !FileExist(IniFile) {
        ; 기본 설정 파일 생성
        IniWrite 0, IniFile, "General", "AutoEnabled"
        IniWrite "", IniFile, "General", "GuiX"
        IniWrite "", IniFile, "General", "GuiY"
        IniWrite 2000, IniFile, "General", "ScanIntervalMs"

        IniWrite "Submit", IniFile, "AutoClickTargets", "Button1"
        IniWrite "Accept", IniFile, "AutoClickTargets", "Button2"
        IniWrite "Proceed", IniFile, "AutoClickTargets", "Button3"
        IniWrite "Run", IniFile, "AutoClickTargets", "Button4"
        IniWrite "Approve", IniFile, "AutoClickTargets", "Button5"
    }

    autoEnabled := IniRead(IniFile, "General", "AutoEnabled", 0)
    guiX := IniRead(IniFile, "General", "GuiX", "")
    guiY := IniRead(IniFile, "General", "GuiY", "")
    scanIntervalMs := IniRead(IniFile, "General", "ScanIntervalMs", 2000)

    autoClickTargets := []
    Loop 10 {
        val := IniRead(IniFile, "AutoClickTargets", "Button" A_Index, "")
        if (val != "")
            autoClickTargets.Push(val)
    }
    if (autoClickTargets.Length == 0) {
        autoClickTargets := ["Submit", "Accept", "Proceed", "Run", "Approve"]
    }

    ; FindText 텍스트 문자열 목록 로딩
    findTextTargets := []
    Loop 20 {
        val := IniRead(IniFile, "FindTextTargets", "Target" A_Index, "")
        if (val != "") {
            ; 사용자가 INI에 큰따옴표를 넣었을 경우 제거
            val := Trim(val, "`"")
            findTextTargets.Push(val)
        }
    }
}

SaveSettings() {
    global autoEnabled, guiX, guiY
    IniWrite autoEnabled, IniFile, "General", "AutoEnabled"
    if (guiX != "" && guiY != "") {
        IniWrite guiX, IniFile, "General", "GuiX"
        IniWrite guiY, IniFile, "General", "GuiY"
    }
}

; ==============================================================================
; 메인 GUI (Auto Commit)
; ==============================================================================
global MainGui := Gui("+AlwaysOnTop +ToolWindow -DPIScale", "Auto Commit")
MainGui.BackColor := "1e1e2e" ; Catppuccin Mocha 배경색

; 글꼴 설정
MainGui.SetFont("cCDD6F4 s10", "Segoe UI")

; Auto 체크박스
global ChkAuto := MainGui.Add("CheckBox", "x15 y15 w80 h25 Checked" autoEnabled, "Auto")
ChkAuto.OnEvent("Click", OnAutoToggle)

; 상태 LED
global TxtStatus := MainGui.Add("Text", "x+10 y15 w60 h25 +0x200", "")

; (디버깅용) Key Test 및 KeyHistory 버튼 제거 요청됨
; global BtnTest := MainGui.Add("Button", "x15 y45 w90 h30 Background313244", "🔑 Key Test")
; BtnTest.OnEvent("Click", ShowKeyTest)

; global BtnHistory := MainGui.Add("Button", "x+5 y45 w70 h30 Background313244", "📜 히스토리")
; BtnHistory.OnEvent("Click", (*) => KeyHistory())

; 이벤트 처리
MainGui.OnEvent("Close", (*) => MainGui.Hide())

UpdateStatusLED() {
    if autoEnabled {
        TxtStatus.Value := "🟢 ON"
        TxtStatus.SetFont("ca6e3a1") ; 녹색
        SetTimer(AutoScan, scanIntervalMs)
    } else {
        TxtStatus.Value := "⚫ OFF"
        TxtStatus.SetFont("c585b70") ; 회색
        SetTimer(AutoScan, 0)
    }
}

OnAutoToggle(ctrl, *) {
    global autoEnabled
    autoEnabled := ctrl.Value
    if (autoEnabled) {
        ; Auto 켤 때 INI를 다시 읽어서 수정사항을 즉시 반영
        LoadSettings()
        autoEnabled := 1 ; LoadSettings가 값을 덮어쓸 수 있으므로 다시 설정
    }
    SaveSettings()
    UpdateStatusLED()
}

; 위치 저장용 타이머 (창 이동 시 저장)
OnMessage(0x0232, WM_EXITSIZEMOVE)
WM_EXITSIZEMOVE(wParam, lParam, msg, hwnd) {
    if (hwnd == MainGui.Hwnd) {
        WinGetPos(&gx, &gy,,, MainGui.Hwnd)
        global guiX := gx
        global guiY := gy
        SaveSettings()
    }
}

; ==============================================================================
; J06 링 키 리매핑 (Antigravity 활성 시 동작)
; ==============================================================================
#HotIf WinActive("ahk_exe i)Antigravity")

; VOLUME_MUTE (우측 아래 버튼) 누르면 화면 내의 확인 버튼(Submit, Accept 등)을 찾아 즉시 클릭
Volume_Mute:: {
    AutoScan()
}

; VOLUME_DOWN (좌측 아래 버튼) 누르면 기본 엔터 키 역할 수행
Volume_Down::Send("{Enter}")

#HotIf

; ==============================================================================
; FindText 기반 자동 스캔 & 클릭
; ==============================================================================
AutoScan() {
    global findTextTargets

    hwnds := WinGetList("ahk_exe i)Antigravity")
    if (hwnds.Length == 0)
        return

    ; FindText 타겟이 없으면 사용자에게 안내 후 종료
    if (findTextTargets.Length = 0) {
        ToolTip("⚠️ FindText 타겟 미등록`nLib\FindText.ahk를 실행해 버튼을 캡처하세요.", 10, 50, 2)
        SetTimer(() => ToolTip(,,, 2), -3000)
        return
    }

    for hwnd in hwnds {
        ; 최소화된 창은 화면 스캔이 불가능하므로 건너뜀
        if (WinGetMinMax(hwnd) == -1)
            continue

        ; 창의 Client Area 절대 좌표 획득
        try {
            WinGetClientPos(&cx, &cy, &cw, &ch, hwnd)
            if (cw <= 0 || ch <= 0)
                continue
        } catch {
            continue
        }

        ; 검색 범위: 창의 Client Area 전체 (Screen 절대 좌표)
        x1 := cx, y1 := cy, x2 := cx + cw, y2 := cy + ch

        for ftStr in findTextTargets {
            ; FindText 호출: FindText(&X, &Y, x1, y1, x2, y2, err1, err0, Text)
            ok := FindText(&fx, &fy, x1, y1, x2, y2, 0, 0, ftStr)

            if (ok) {
                ; fx, fy는 이미 매칭된 이미지의 정중앙 좌표(Screen 기준)입니다.
                ; ControlClick을 위해 Client 상대 좌표로 변환합니다.
                ClickX := fx - cx
                ClickY := fy - cy

                ; 대상 창의 Client 좌표를 클릭 (NA: 마우스 포커스 뺏지 않음)
                ControlClick("x" ClickX " y" ClickY, hwnd,,,, "NA")

                ToolTip("✔️ 찾음 & 클릭: (" ClickX ", " ClickY ")", 10, 50, 2)
                SetTimer(() => ToolTip(,,, 2), -2000)
                
                ; 이 창에서 버튼을 찾았으므로 더 이상 찾지 않고 다음 창으로 넘어감
                break 
            }
        }
    }
}

; ==============================================================================
; Key Test 기능
; ==============================================================================
global ih := ""
global keyDisplay := ""

ShowKeyTest(*) {
    global keyDisplay
    if WinExist("Key Test") {
        WinActivate("Key Test")
        return
    }

    testGui := Gui("+AlwaysOnTop +ToolWindow -DPIScale", "Key Test")
    testGui.BackColor := "1e1e2e"
    testGui.SetFont("cCDD6F4 s11", "Segoe UI")
    
    testGui.Add("Text", "w250", "J06 버튼을 눌러보세요:`n(마우스/휠 입력도 감지합니다)")
    keyDisplay := testGui.Add("Text", "w250 h50 Border +0x200 center", "대기 중...")
    
    global ih := InputHook("L0 T0")
    ih.KeyOpt("{All}", "N")
    ih.OnKeyDown := (ihObj, vk, sc) => UpdateKeyDisplay(vk, sc, keyDisplay)
    ih.Start()
    
    testGui.OnEvent("Close", (*) => ih.Stop())
    testGui.Show("w280 h140")
}

UpdateKeyDisplay(vk, sc, textCtrl) {
    keyName := GetKeyName(Format("vk{:x}sc{:x}", vk, sc))
    textCtrl.Value := Format("Name: {}`nVK: {:#x}  SC: {:#x}", keyName, vk, sc)
}

UpdateKeyDisplayMouse(hotkeyName) {
    global keyDisplay
    if (keyDisplay && WinExist("Key Test")) {
        ; Remove ~* from the hotkey name
        cleanName := RegExReplace(hotkeyName, "^~\*")
        vk := GetKeyVK(cleanName)
        sc := GetKeySC(cleanName)
        keyDisplay.Value := Format("Name: {}`nVK: {:#x}  SC: {:#x}", cleanName, vk, sc)
    }
}

#HotIf WinActive("Key Test")
~*LButton::
~*RButton::
~*MButton::
~*XButton1::
~*XButton2::
~*WheelUp::
~*WheelDown::
~*WheelLeft::
~*WheelRight::
~*Browser_Back::
~*Browser_Forward::
{
    UpdateKeyDisplayMouse(A_ThisHotkey)
}
#HotIf

; ==============================================================================
; 트레이 메뉴 설정
; ==============================================================================
SetupTray() {
    A_IconTip := "J06 Remote Auto Commit"
    TraySetIcon("shell32.dll", 295) ; 임시 아이콘
    
    Tray := A_TrayMenu
    Tray.Delete()
    
    Tray.Add("Show/Hide GUI", ToggleGui)
    Tray.Add()
    Tray.Add("Exit", (*) => ExitApp())
    
    Tray.Default := "Show/Hide GUI"
}

ToggleGui(*) {
    if WinExist(MainGui.Hwnd) {
        if WinActive(MainGui.Hwnd)
            MainGui.Hide()
        else
            MainGui.Show()
    } else {
        if (guiX != "" && guiY != "")
            MainGui.Show("x" guiX " y" guiY)
        else
            MainGui.Show()
    }
}

; ==============================================================================
; 초기화 및 실행
; ==============================================================================
LoadSettings()
SetupTray()

UpdateStatusLED()

if (guiX != "" && guiY != "")
    MainGui.Show("x" guiX " y" guiY)
else
    MainGui.Show("w180 h55")

