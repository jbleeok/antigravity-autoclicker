#Requires AutoHotkey v2.0
#SingleInstance Force

; ==============================================================================
; 전역 변수 및 설정
; ==============================================================================
SetTitleMatchMode "RegEx" ; 정규식을 사용하여 프로세스 이름의 일부만으로도 매칭 가능하게 설정

global IniFile := A_ScriptDir "\antigravity_j06.ini"
global autoEnabled := 0
global guiX := ""
global guiY := ""
global scanIntervalMs := 1000

global autoClickTargets := []

; ==============================================================================
; INI 파일 처리
; ==============================================================================
LoadSettings() {
    global autoEnabled, guiX, guiY, scanIntervalMs, autoClickTargets

    if !FileExist(IniFile) {
        ; 기본 설정 파일 생성
        IniWrite 0, IniFile, "General", "AutoEnabled"
        IniWrite "", IniFile, "General", "GuiX"
        IniWrite "", IniFile, "General", "GuiY"
        IniWrite 1000, IniFile, "General", "ScanIntervalMs"

        IniWrite "Submit", IniFile, "AutoClickTargets", "Button1"
        IniWrite "Accept", IniFile, "AutoClickTargets", "Button2"
        IniWrite "Proceed", IniFile, "AutoClickTargets", "Button3"
        IniWrite "Run", IniFile, "AutoClickTargets", "Button4"
        IniWrite "Approve", IniFile, "AutoClickTargets", "Button5"
    }

    autoEnabled := IniRead(IniFile, "General", "AutoEnabled", 0)
    guiX := IniRead(IniFile, "General", "GuiX", "")
    guiY := IniRead(IniFile, "General", "GuiY", "")
    scanIntervalMs := IniRead(IniFile, "General", "ScanIntervalMs", 1000)

    autoClickTargets := []
    Loop 10 {
        val := IniRead(IniFile, "AutoClickTargets", "Button" A_Index, "")
        if (val != "")
            autoClickTargets.Push(val)
    }
    if (autoClickTargets.Length == 0) {
        autoClickTargets := ["Submit", "Accept", "Proceed", "Run", "Approve"]
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
; ImageSearch 기반 자동 스캔 & 클릭
; ==============================================================================
AutoScan() {
    if !WinExist("ahk_exe i)Antigravity")
        return

    ; 좌표계를 화면 전체(Screen) 기준으로 통일 (창이 비활성 상태여도 검색 가능하도록)
    CoordMode "Pixel", "Screen"
    
    ; 창의 내부 크기(Client Area)와 화면상의 절대 좌표(cx, cy) 획득
    try {
        WinGetClientPos(&cx, &cy, &cw, &ch, "ahk_exe i)Antigravity")
        if (cw <= 0 || ch <= 0)
            return
    } catch {
        return
    }
    
    targetFolder := A_ScriptDir "\img_targets"
    if !DirExist(targetFolder) {
        DirCreate(targetFolder)
        return
    }

    Loop Files, targetFolder "\*.*" {
        ext := RegExReplace(A_LoopFileName, "^.*\.")
        if !(ext = "png" || ext = "bmp")
            continue

        ToolTip("검색 시도 중: " A_LoopFileName " (창 크기: " cw "x" ch ")", 10, 10)
        SetTimer(() => ToolTip(,,, 1), -1000)

        ; 오차 범위를 80으로 높여 투명도/그림자/안티앨리어싱 차이 허용
        try {
            found := ImageSearch(&FoundX, &FoundY, cx, cy, cx + cw, cy + ch, "*80 " A_LoopFilePath)
        } catch {
            return
        }

        if (found) {
            
            ; 캡처한 이미지의 실제 가로/세로 길이를 알아내어 '정중앙'을 클릭하도록 개선
            imgW := 30
            imgH := 30
            try {
                tempGui := Gui()
                pic := tempGui.Add("Picture",, A_LoopFilePath)
                pic.GetPos(,, &imgW, &imgH)
                tempGui.Destroy()
            }
            
            ; FoundX, FoundY는 Screen 기준 좌표이므로, ControlClick을 위해 Client 상대 좌표로 변환
            ClickX := FoundX - cx + (imgW // 2)
            ClickY := FoundY - cy + (imgH // 2)
            
            ; 대상 창의 Client 좌표를 클릭 (NA: 마우스 포커스 뺏지 않음)
            ControlClick("x" ClickX " y" ClickY, "ahk_exe i)Antigravity",,,, "NA")
            
            ; 매칭 성공 여부를 화면에 띄워줌
            ToolTip("✔️ 찾음 & 클릭 시도: " A_LoopFileName, 10, 50, 2)
            SetTimer(() => ToolTip(,,, 2), -2000)
            
            break
        }
    }
    
    if (!found) {
        ToolTip("❌ 이미지를 찾지 못했습니다.", 10, 50, 2)
        SetTimer(() => ToolTip(,,, 2), -2000)
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

