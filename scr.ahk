#Requires AutoHotkey v2.0
#SingleInstance Force

; 멀티 모니터 배율(DPI) 불일치로 인한 오작동 방지 설정
DllCall("SetThreadDpiAwarenessContext", "ptr", -3, "ptr")

; GUI 창을 닫아도 프로그램이 트레이에 상주하도록 설정
Persistent

; -----------------------------------------------------------------------------
; 모니터 전원 제어기 (Screen Controller)
; -----------------------------------------------------------------------------

global hHandCursor := DllCall("user32\LoadCursor", "ptr", 0, "ptr", 32649, "ptr")
global hBlankCursor := CreateBlankCursor()

CreateBlankCursor() {
    andMask := Buffer(4, 0xFF)
    xorMask := Buffer(4, 0x00)
    return DllCall("user32\CreateCursor", "ptr", 0, "int", 0, "int", 0, "int", 1, "int", 1, "ptr", andMask.Ptr, "ptr", xorMask.Ptr, "ptr")
}

global MainGui := ""
global monitorState := Map()     ; 모니터 상태 ("ON", "DDC_OFF", "BLACKOUT_OFF")
global blackoutGuis := Map()     ; 블랙아웃 GUI 객체들
global blackoutHwnds := Map()    ; 블랙아웃 HWND -> 모니터 인덱스 매핑
global ddcButtons := Map()       ; DDC/CI 버튼 컨트롤들
global blackButtons := Map()     ; 블랙아웃 버튼 컨트롤들
global statusLabels := Map()     ; 상태 텍스트 컨트롤들
global hMonitorMap := Map()      ; 장치 이름 -> HMONITOR 핸들 매핑

; -----------------------------------------------------------------------------
; 커스텀 플랫 버튼 클래스 (Sleek Dark Theme)
; -----------------------------------------------------------------------------
class CustomButton {
    static buttons := Map()
    
    __New(guiObj, options, text, callback, normalBg := "3B82F6", hoverBg := "60A5FA") {
        this.normalBg := normalBg
        this.hoverBg := hoverBg
        this.callback := callback
        this.enabled := true
        
        ; 텍스트 컨트롤을 사용하여 플랫하고 모던한 버튼 구현 (+0x200 = 수직 정렬)
        this.control := guiObj.AddText(options " Background" normalBg " Center +0x200 cFFFFFF", text)
        this.hwnd := this.control.Hwnd
        
        this.control.OnEvent("Click", (ctrl, info) => this.OnClick())
        CustomButton.buttons[this.hwnd] := this
    }
    
    OnClick() {
        if this.enabled
            this.callback.Call(this)
    }
    
    SetText(text) {
        this.control.Text := text
    }
    
    SetBg(color) {
        this.control.Opt("Background" color)
        this.control.Redraw()
    }
    
    SetEnabled(enabled) {
        this.enabled := enabled
        if enabled {
            this.control.Opt("+cFFFFFF")
            this.SetBg(this.normalBg)
        } else {
            this.control.Opt("+c888888")
            this.SetBg("475569") ; 비활성화 상태 배경 (Slate-600)
        }
        this.control.Redraw()
    }
}

; -----------------------------------------------------------------------------
; API Helper 함수들
; -----------------------------------------------------------------------------
GetHMonitorMap() {
    hMonitors := Map()
    EnumProc(hMonitor, hdcMonitor, lprcMonitor, dwData) {
        buf := Buffer(104, 0)
        NumPut("uint", 104, buf, 0)
        if DllCall("user32\GetMonitorInfoW", "ptr", hMonitor, "ptr", buf.Ptr) {
            deviceName := StrGet(buf.Ptr + 40, 32, "UTF-16")
            hMonitors[deviceName] := hMonitor
        }
        return true
    }
    cb := CallbackCreate(EnumProc, "F")
    DllCall("user32\EnumDisplayMonitors", "ptr", 0, "ptr", 0, "ptr", cb, "ptr", 0)
    CallbackFree(cb)
    return hMonitors
}

GetPhysicalMonitorHandle(hMonitor) {
    count := 0
    if !DllCall("dxva2\GetNumberOfPhysicalMonitorsFromHMONITOR", "ptr", hMonitor, "uint*", &count)
        return 0
    if count == 0
        return 0
    
    structSize := A_PtrSize + 256
    buf := Buffer(structSize * count, 0)
    if !DllCall("dxva2\GetPhysicalMonitorsFromHMONITOR", "ptr", hMonitor, "uint", count, "ptr", buf.Ptr)
        return 0
    
    hPhysMon := NumGet(buf, 0, "ptr")
    return {handle: hPhysMon, buffer: buf, count: count}
}

SetMonitorPower(hMonitor, state) {
    try {
        monInfo := GetPhysicalMonitorHandle(hMonitor)
        if !monInfo
            return false
        
        success := DllCall("dxva2\SetVCPFeature", "ptr", monInfo.handle, "uchar", 0xD6, "uint", state)
        DllCall("dxva2\DestroyPhysicalMonitors", "uint", monInfo.count, "ptr", monInfo.buffer.Ptr)
        return success
    } catch {
        return false
    }
}

; -----------------------------------------------------------------------------
; 컨트롤러 로직 함수들
; -----------------------------------------------------------------------------
OnDccClick(index, btn) {
    state := monitorState[index]
    hMonitor := hMonitorMap[MonitorGetName(index)]
    
    if state == "ON" {
        if SetMonitorPower(hMonitor, 4) {
            monitorState[index] := "DDC_OFF"
            btn.SetText("DDC/CI 켜기")
            blackButtons[index].SetEnabled(false)
            statusLabels[index].Opt("cEF4444") ; Red-500
            statusLabels[index].Text := "● HW꺼짐"
            statusLabels[index].Redraw()
        } else {
            MsgBox("DDC/CI 명령 전송에 실패했습니다.`n`n모니터가 DDC/CI 기능을 지원하고, 모니터 자체 OSD 설정에서 활성화되어 있는지 확인해 주세요.`n지원되지 않는 경우 '블랙아웃(S/W)' 기능을 사용하시기 바랍니다.", "지원 미흡 또는 오류", "Iconi +AlwaysOnTop")
        }
    } else if state == "DDC_OFF" {
        SetMonitorPower(hMonitor, 1)
        monitorState[index] := "ON"
        btn.SetText("DDC/CI 끄기")
        blackButtons[index].SetEnabled(true)
        statusLabels[index].Opt("c10B981") ; Emerald-500
        statusLabels[index].Text := "● 켜짐"
        statusLabels[index].Redraw()
    }
}

OnBlackClick(index, btn) {
    state := monitorState[index]
    if state == "ON" {
        StartBlackout(index)
    } else if state == "BLACKOUT_OFF" {
        EndBlackout(index)
    }
}

StartBlackout(index) {
    if monitorState[index] != "ON"
        return
        
    MonitorGet(index, &left, &top, &right, &bottom)
    width := right - left
    height := bottom - top
    
    ; 전체화면 검은색 투명 테두리 없는 GUI 생성
    bgui := Gui("+AlwaysOnTop -Caption +ToolWindow")
    bgui.Opt("-DPIScale")
    bgui.BackColor := "000000"
    
    ; ESC 누르면 깨어남 (클릭은 WM_LBUTTONDOWN/WM_RBUTTONDOWN 메시지로 처리됨)
    bgui.OnEvent("Escape", (*) => EndBlackout(index))
    
    bgui.Show("x" left " y" top " w" width " h" height)
    
    blackoutGuis[index] := bgui
    blackoutHwnds[bgui.Hwnd] := index
    
    monitorState[index] := "BLACKOUT_OFF"
    blackButtons[index].SetText("블랙아웃 켜기")
    ddcButtons[index].SetEnabled(false)
    
    statusLabels[index].Opt("c8B5CF6") ; Purple-500
    statusLabels[index].Text := "● SW꺼짐"
    statusLabels[index].Redraw()
}

EndBlackout(index) {
    if monitorState[index] != "BLACKOUT_OFF"
        return
        
    bgui := blackoutGuis[index]
    blackoutHwnds.Delete(bgui.Hwnd)
    blackoutGuis.Delete(index)
    bgui.Destroy()
    
    monitorState[index] := "ON"
    blackButtons[index].SetText("블랙아웃 끄기")
    ddcButtons[index].SetEnabled(true)
    
    statusLabels[index].Opt("c10B981") ; Emerald-500
    statusLabels[index].Text := "● 켜짐"
    statusLabels[index].Redraw()
}

ExitProgram() {
    global hBlankCursor, winStates, MainGui
    if MainGui {
        try {
            DllCall("wtsapi32\WTSUnRegisterSessionNotification", "ptr", MainGui.Hwnd)
        }
    }
    ; 꺼진 화면들 복구
    Loop MonitorGetCount() {
        if monitorState[A_Index] == "BLACKOUT_OFF" {
            EndBlackout(A_Index)
        } else if monitorState[A_Index] == "DDC_OFF" {
            hMonitor := hMonitorMap[MonitorGetName(A_Index)]
            SetMonitorPower(hMonitor, 1)
        }
    }
    ; 변경된 창 스타일 및 위치 복원
    for hwnd, orig in winStates {
        try {
            WinSetStyle(orig.style, "ahk_id " hwnd)
            WinMove(orig.x, orig.y, orig.w, orig.h, "ahk_id " hwnd)
        }
    }
    if hBlankCursor {
        DllCall("user32\DestroyIcon", "ptr", hBlankCursor)
    }
    ExitApp()
}

; -----------------------------------------------------------------------------
; Windows 메시지 이벤트 핸들러 (커서 및 화면변경 대응)
; -----------------------------------------------------------------------------
WM_MOUSEMOVE(wParam, lParam, msg, hwnd) {
    global hHandCursor
    MouseGetPos ,, &ctrlHwnd
    
    static lastHoveredHwnd := 0
    
    if ctrlHwnd != lastHoveredHwnd {
        if lastHoveredHwnd && CustomButton.buttons.Has(lastHoveredHwnd) {
            btn := CustomButton.buttons[lastHoveredHwnd]
            if btn.enabled {
                btn.SetBg(btn.normalBg)
            }
        }
        
        if ctrlHwnd && CustomButton.buttons.Has(ctrlHwnd) {
            btn := CustomButton.buttons[ctrlHwnd]
            if btn.enabled {
                btn.SetBg(btn.hoverBg)
                DllCall("user32\SetCursor", "ptr", hHandCursor)
            }
            lastHoveredHwnd := ctrlHwnd
        } else {
            lastHoveredHwnd := 0
        }
    } else if ctrlHwnd && CustomButton.buttons.Has(ctrlHwnd) {
        btn := CustomButton.buttons[ctrlHwnd]
        if btn.enabled {
            DllCall("user32\SetCursor", "ptr", hHandCursor)
        }
    }
}

WM_SETCURSOR(wParam, lParam, msg, hwnd) {
    global hBlankCursor, blackoutHwnds
    ; 블랙아웃 화면 위에 있으면 커서 숨기기
    if blackoutHwnds.Has(hwnd) {
        DllCall("user32\SetCursor", "ptr", hBlankCursor)
        return true
    }
    
    ; 커스텀 버튼 위에 있으면 포인터 커서로 변경
    MouseGetPos ,, &ctrlHwnd
    if ctrlHwnd && CustomButton.buttons.Has(ctrlHwnd) {
        btn := CustomButton.buttons[ctrlHwnd]
        if btn.enabled {
            DllCall("user32\SetCursor", "ptr", hHandCursor)
            return true
        }
    }
}

RebuildGui() {
    global MainGui, monitorState, blackoutGuis, ddcButtons, blackButtons, statusLabels, hMonitorMap
    try {
        DllCall("wtsapi32\WTSUnRegisterSessionNotification", "ptr", MainGui.Hwnd)
        MainGui.Destroy()
    }
    monitorState := Map()
    blackoutGuis := Map()
    ddcButtons := Map()
    blackButtons := Map()
    statusLabels := Map()
    hMonitorMap := GetHMonitorMap()
    CustomButton.buttons := Map()
    CreateMainGui()
}

; -----------------------------------------------------------------------------
; GUI 생성 및 구성
; -----------------------------------------------------------------------------
CreateMainGui() {
    global MainGui, monitorState, ddcButtons, blackButtons, statusLabels, hMonitorMap
    
    MainGui := Gui("+AlwaysOnTop -MaximizeBox", "모니터 제어기")
    MainGui.Opt("-DPIScale")
    MainGui.BackColor := "0F172A" ; Slate-900
    
    ; 창의 외부 마진 설정 (좌우 15px, 상하 15px)
    MainGui.MarginX := 15
    MainGui.MarginY := 15
    
    monitorCount := MonitorGetCount()
    primaryIndex := MonitorGetPrimary()
    
    ; 물리적인 좌우 배치 순서대로 모니터 인덱스 정렬 (왼쪽 -> 오른쪽)
    monitorIndices := []
    Loop monitorCount {
        monitorIndices.Push(A_Index)
    }
    Loop monitorIndices.Length {
        i := A_Index
        Loop monitorIndices.Length - i {
            j := A_Index
            MonitorGet(monitorIndices[j], &left1)
            MonitorGet(monitorIndices[j+1], &left2)
            if (left1 > left2) {
                temp := monitorIndices[j]
                monitorIndices[j] := monitorIndices[j+1]
                monitorIndices[j+1] := temp
            }
        }
    }
    
    ; 모니터 수에 따른 가로 크기 정의
    if (monitorCount >= 2) {
        cardW := 175
        cardH := 140
        gap := 20
        guiW := 15 + (cardW * monitorCount) + (gap * (monitorCount - 1)) + 15
        surroundW := guiW - 30
        btnW := 150
        btnH := 28
    } else {
        cardW := 350
        cardH := 115
        gap := 0
        guiW := 380
        surroundW := 350
        btnW := 150
        btnH := 28
    }
    
    Loop monitorIndices.Length {
        index := monitorIndices[A_Index]
        name := MonitorGetName(index)
        
        MonitorGet(index, &left, &top, &right, &bottom)
        width := right - left
        height := bottom - top
        
        isPrimary := (index == primaryIndex) ? " (기본)" : ""
        monitorState[index] := "ON"
        
        ; 카드 레이아웃 배경 생성
        if (monitorCount >= 2) {
            cardX := 15 + (A_Index - 1) * (cardW + gap)
            cardOpt := "x" cardX " y15 Section"
        } else {
            cardOpt := "x15 y15 Section"
        }
        
        MainGui.AddText("w" cardW " h" cardH " Background1E293B " cardOpt, "")
        
        ; 타이틀 및 상태 표시 (카드 너비에 따른 배치 조정)
        if (monitorCount >= 2) {
            MainGui.SetFont("s9 bold cF8FAFC", "Segoe UI")
            isPrimaryShort := (index == primaryIndex) ? "*" : ""
            MainGui.AddText("xs+12 ys+15 w85 Background1E293B", "모니터 " index isPrimaryShort)
            
            MainGui.SetFont("s9 c10B981", "Segoe UI")
            statusLabels[index] := MainGui.AddText("xs+97 ys+15 w68 Background1E293B Right", "● 켜짐")
        } else {
            MainGui.SetFont("s10 bold cF8FAFC", "Segoe UI")
            MainGui.AddText("xs+15 ys+15 w200 Background1E293B", "모니터 " index isPrimary)
            
            MainGui.SetFont("s10 bold c10B981", "Segoe UI")
            statusLabels[index] := MainGui.AddText("xs+225 ys+15 w110 Background1E293B Right", "● 켜짐")
        }
        
        ; 세부 정보 (디바이스 명 간략화)
        MainGui.SetFont("s8 c94A3B8", "Segoe UI")
        if (monitorCount >= 2) {
            dispShort := RegExReplace(name, "i)^\\\\.\\\\DISPLAY", "D")
            MainGui.AddText("xs+12 ys+37 w150 Background1E293B", width "x" height " | " dispShort)
        } else {
            MainGui.AddText("xs+15 ys+37 w320 Background1E293B", width "x" height " | " name)
        }
        
        MainGui.SetFont("s9 bold cFFFFFF", "Segoe UI")
        
        if (monitorCount >= 2) {
            ; 듀얼 모니터: 세로 배치
            ; 블랙아웃 버튼 (초록색, 상단 배치)
            btnBlack := CustomButton(MainGui, "xs+12 ys+65 w" btnW " h" btnH, "블랙아웃 끄기", OnBlackClick.Bind(index), "10B981", "34D399")
            blackButtons[index] := btnBlack
            
            ; DDC/CI 버튼 (파란색, 하단 배치)
            btnDDC := CustomButton(MainGui, "xs+12 ys+98 w" btnW " h" btnH, "DDC/CI 끄기", OnDccClick.Bind(index), "3B82F6", "60A5FA")
            ddcButtons[index] := btnDDC
        } else {
            ; 싱글 모니터: 가로 배치 (y+65에 나란히 배치)
            btnBlack := CustomButton(MainGui, "xs+15 ys+65 w" btnW " h" btnH, "블랙아웃 끄기", OnBlackClick.Bind(index), "10B981", "34D399")
            blackButtons[index] := btnBlack
            
            btnDDC := CustomButton(MainGui, "xs+185 ys+65 w" btnW " h" btnH, "DDC/CI 끄기", OnDccClick.Bind(index), "3B82F6", "60A5FA")
            ddcButtons[index] := btnDDC
        }
    }
    
    ; NVIDIA Surround 창 제어 카드 추가 (가로 너비 surroundW)
    MainGui.AddText("w" surroundW " h115 Background1E293B xm y+15 Section", "")
    MainGui.SetFont("s10 bold cF8FAFC", "Segoe UI")
    MainGui.AddText("xs+15 ys+15 w300 Background1E293B", "창 크기/위치 제어 (NVIDIA Surround)")
    
    MainGui.SetFont("s9 bold cFFFFFF", "Segoe UI")
    
    if (monitorCount >= 2) {
        ; 2개 이상 모니터일 때 버튼들을 상하 카드에 열을 맞춰 정렬
        ; 1열 시작: xs+12 (절대 X: 27), 2열 시작: xs+207 (절대 X: 222)
        CustomButton(MainGui, "xs+12 ys+42 w" btnW " h" btnH, "← 왼쪽 화면", OnSurroundLeft, "3B82F6", "60A5FA")
        CustomButton(MainGui, "xs+207 ys+42 w" btnW " h" btnH, "오른쪽 화면 →", OnSurroundRight, "3B82F6", "60A5FA")
        CustomButton(MainGui, "xs+12 ys+75 w" btnW " h" btnH, "↔ 전체 화면 (합성)", OnSurroundFull, "10B981", "34D399")
        CustomButton(MainGui, "xs+207 ys+75 w" btnW " h" btnH, "↩ 원래 크기로 복원", OnSurroundRestore, "64748B", "94A3B8")
    } else {
        ; 싱글 모니터일 때 버튼 배치
        ; 1열 시작: xs+15 (절대 X: 30), 2열 시작: xs+185 (절대 X: 200)
        CustomButton(MainGui, "xs+15 ys+42 w" btnW " h" btnH, "← 왼쪽 화면", OnSurroundLeft, "3B82F6", "60A5FA")
        CustomButton(MainGui, "xs+185 ys+42 w" btnW " h" btnH, "오른쪽 화면 →", OnSurroundRight, "3B82F6", "60A5FA")
        CustomButton(MainGui, "xs+15 ys+75 w" btnW " h" btnH, "↔ 전체 화면 (합성)", OnSurroundFull, "10B981", "34D399")
        CustomButton(MainGui, "xs+185 ys+75 w" btnW " h" btnH, "↩ 원래 크기로 복원", OnSurroundRestore, "64748B", "94A3B8")
    }
    
    ; GUI 표시
    MainGui.Show("x10 y10 w" guiW)
    MainGui.OnEvent("Close", (*) => MainGui.Hide())
    
    ; 세션 변경(잠금/잠금해제) 알림 등록 (0 = NOTIFY_FOR_THIS_SESSION)
    try {
        DllCall("wtsapi32\WTSRegisterSessionNotification", "ptr", MainGui.Hwnd, "uint", 0)
    }
}

; -----------------------------------------------------------------------------
; 트레이 메뉴 설정 및 구동
; -----------------------------------------------------------------------------
A_IconTip := "모니터 제어기"
try {
    TraySetIcon("shell32.dll", 16)
}
A_TrayMenu.Delete()
A_TrayMenu.Add("열기", (*) => ShowGui())
A_TrayMenu.Add("종료", (*) => ExitProgram())
A_TrayMenu.Default := "열기"

ShowGui() {
    MainGui.Show()
    MainGui.Restore()
}

; 이벤트 및 메시지 연결
OnMessage(0x0200, WM_MOUSEMOVE)
OnMessage(0x0020, WM_SETCURSOR)
OnMessage(0x007E, WM_DISPLAYCHANGE)
OnMessage(0x0201, WM_LBUTTONDOWN) ; 마우스 좌클릭 감지
OnMessage(0x0204, WM_LBUTTONDOWN) ; 마우스 우클릭 감지
OnMessage(0x02B1, WM_WTSSESSION_CHANGE) ; 세션 변경 감지 (잠금/해제)

WM_DISPLAYCHANGE(wParam, lParam, msg, hwnd) {
    SetTimer(RebuildGui, -1000)
}

WM_LBUTTONDOWN(wParam, lParam, msg, hwnd) {
    global blackoutHwnds
    ; 클릭한 창이 블랙아웃 화면인지 확인
    if blackoutHwnds.Has(hwnd) {
        index := blackoutHwnds[hwnd]
        EndBlackout(index)
    }
}

WM_WTSSESSION_CHANGE(wParam, lParam, msg, hwnd) {
    global monitorState
    ; wParam: 0x7 = WTS_SESSION_LOCK (잠금), 0x8 = WTS_SESSION_UNLOCK (잠금 해제)
    if (wParam == 0x7 || wParam == 0x8) {
        Loop MonitorGetCount() {
            if monitorState.Has(A_Index) && monitorState[A_Index] == "BLACKOUT_OFF" {
                EndBlackout(A_Index)
            }
        }
    }
}

; -----------------------------------------------------------------------------
; NVIDIA Surround 창 제어 로직
; -----------------------------------------------------------------------------
global winStates := Map()

GetPreviousActiveWindow() {
    hwnd := DllCall("user32\GetWindow", "ptr", MainGui.Hwnd, "uint", 2, "ptr")
    Loop {
        if !hwnd
            break
        if WinExist("ahk_id " hwnd) {
            try {
                style := WinGetStyle("ahk_id " hwnd)
                exStyle := WinGetExStyle("ahk_id " hwnd)
                title := WinGetTitle("ahk_id " hwnd)
                class := WinGetClass("ahk_id " hwnd)
                
                if (style & 0x10000000) && !(exStyle & 0x80) && title != "" && class != "Shell_TrayWnd" && class != "Progman" {
                    return hwnd
                }
            } catch {
                ; 창이 검사 중에 닫히거나 사라진 경우 예외 처리
            }
        }
        hwnd := DllCall("user32\GetWindow", "ptr", hwnd, "uint", 2, "ptr")
    }
    return 0
}

GetSortedMonitors() {
    count := MonitorGetCount()
    monitors := []
    Loop count {
        MonitorGet(A_Index, &left, &top, &right, &bottom)
        monitors.Push({index: A_Index, left: left, top: top, right: right, bottom: bottom, w: right - left, h: bottom - top})
    }
    
    Loop count {
        i := A_Index
        Loop count - i {
            j := A_Index
            if (monitors[j].left > monitors[j+1].left) {
                temp := monitors[j]
                monitors[j] := monitors[j+1]
                monitors[j+1] := temp
            }
        }
    }
    return monitors
}

SetWindowBorderlessPosition(hwnd, position) {
    global winStates
    if !hwnd
        return
        
    if !winStates.Has(hwnd) {
        try {
            style := WinGetStyle("ahk_id " hwnd)
            WinGetPos(&x, &y, &w, &h, "ahk_id " hwnd)
            winStates[hwnd] := {state: "NORMAL", x: x, y: y, w: w, h: h, style: style}
        } catch {
            return
        }
    }
    
    orig := winStates[hwnd]
    
    if position == "NORMAL" {
        try {
            WinSetStyle(orig.style, "ahk_id " hwnd)
            WinMove(orig.x, orig.y, orig.w, orig.h, "ahk_id " hwnd)
            winStates.Delete(hwnd)
        }
        return
    }
    
    monitors := GetSortedMonitors()
    count := monitors.Length
    
    targetX := 0
    targetY := 0
    targetW := 0
    targetH := 0
    
    if position == "FULL" {
        minX := 999999, minY := 999999, maxX := -999999, maxY := -999999
        for m in monitors {
            if m.left < minX
                minX := m.left
            if m.top < minY
                minY := m.top
            if m.right > maxX
                maxX := m.right
            if m.bottom > maxY
                maxY := m.bottom
        }
        targetX := minX
        targetY := minY
        targetW := maxX - minX
        targetH := maxY - minY
    } else {
        if count >= 2 {
            if position == "LEFT" {
                targetX := monitors[1].left
                targetY := monitors[1].top
                targetW := monitors[1].w
                targetH := monitors[1].h
            } else if position == "RIGHT" {
                targetX := monitors[count].left
                targetY := monitors[count].top
                targetW := monitors[count].w
                targetH := monitors[count].h
            }
        } else {
            m := monitors[1]
            targetY := m.top
            targetH := m.h
            if position == "LEFT" {
                targetX := m.left
                targetW := m.w / 2
            } else if position == "RIGHT" {
                targetX := m.left + (m.w / 2)
                targetW := m.w / 2
            }
        }
    }
    
    try {
        WinSetStyle("-0xC40000", "ahk_id " hwnd)
        WinMove(targetX, targetY, targetW, targetH, "ahk_id " hwnd)
        WinRedraw("ahk_id " hwnd)
        orig.state := position
    }
}

OnSurroundLeft(btn) {
    hwnd := GetPreviousActiveWindow()
    if hwnd
        SetWindowBorderlessPosition(hwnd, "LEFT")
}

OnSurroundRight(btn) {
    hwnd := GetPreviousActiveWindow()
    if hwnd
        SetWindowBorderlessPosition(hwnd, "RIGHT")
}

OnSurroundFull(btn) {
    hwnd := GetPreviousActiveWindow()
    if hwnd
        SetWindowBorderlessPosition(hwnd, "FULL")
}

OnSurroundRestore(btn) {
    hwnd := GetPreviousActiveWindow()
    if hwnd
        SetWindowBorderlessPosition(hwnd, "NORMAL")
}

; -----------------------------------------------------------------------------
; 글로벌 단축키 (Active Window 제어)
; -----------------------------------------------------------------------------
^!Left:: {
    hwnd := WinExist("A")
    if hwnd && hwnd != MainGui.Hwnd
        SetWindowBorderlessPosition(hwnd, "LEFT")
}

^!Right:: {
    hwnd := WinExist("A")
    if hwnd && hwnd != MainGui.Hwnd
        SetWindowBorderlessPosition(hwnd, "RIGHT")
}

^!Up:: {
    hwnd := WinExist("A")
    if hwnd && hwnd != MainGui.Hwnd
        SetWindowBorderlessPosition(hwnd, "FULL")
}

^!Down:: {
    hwnd := WinExist("A")
    if hwnd && hwnd != MainGui.Hwnd
        SetWindowBorderlessPosition(hwnd, "NORMAL")
}

; 메인 구동
hMonitorMap := GetHMonitorMap()
CreateMainGui()
