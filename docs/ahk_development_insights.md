# AutoHotkey v2 멀티 모니터 및 시스템 제어 스크립트 개발 인사이트

본 문서는 멀티 모니터 제어 및 NVIDIA Surround 윈도우 배치 스크립트(`scr.ahk`) 개발 과정에서 겪은 주요 이슈들과 이를 해결하기 위한 기술적 해결책, 디자인 패턴들을 정리한 개발 인사이트 문서입니다.

---

## 1. 멀티 모니터 DPI 배율(Scaling) 불일치 문제

### [이슈]
윈도우 환경에서 여러 모니터의 DPI 배율이 다를 경우(예: 주 모니터 150%, 보조 모니터 100%), AHK GUI 창 내부의 컨트롤 위치가 픽셀 단위로 왜곡되거나 해상도 인식 오류가 발생합니다.

### [해결책]
1. **DPI Awareness 컨텍스트 설정**:
   스크립트 최상단에서 `SetThreadDpiAwarenessContext` API를 사용하여 스크립트가 실행되는 스레드를 모니터별 배율(Per-Monitor v2) 인식 모드로 전환합니다.
   ```autohotkey
   DllCall("SetThreadDpiAwarenessContext", "ptr", -3, "ptr") ; -3 = DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2
   ```
2. **GUI DPI 스케일링 옵션 제거**:
   생성하는 모든 GUI 객체에 대해 자동 DPI 스케일링을 비활성화하여, 내부의 절대 픽셀 좌표가 일관되게 적용되도록 설정합니다.
   ```autohotkey
   MainGui.Opt("-DPIScale")
   ```

---

## 2. AHK v2 루프 바인딩 (클로저 캡처링) 이슈

### [이슈]
모니터 개수만큼 루프를 돌면서 GUI 버튼을 동적 생성하고 이벤트를 할당할 때, 콜백 함수 안에서 인덱스 변수(예: `A_Index` 또는 `index`)를 단순히 참조하면 모든 버튼이 **마지막 루프 인덱스**만을 가리키는 오류가 발생합니다. (AHK v2의 클로저가 변수를 참조로 캡처하기 때문)

### [해결책]
이벤트 콜백 함수를 할당할 때 `.Bind()` 메서드를 사용하여 당시의 변수 값(인덱스 상태)을 인자값으로 명시적으로 묶어두어야(Binding) 합니다.
```autohotkey
; 잘못된 방식 (모든 버튼이 루프의 마지막 index를 참조하게 됨)
btnBlack := CustomButton(MainGui, "...", "블랙아웃 끄기", (btn) => OnBlackClick(index))

; 올바른 방식 (.Bind를 통한 명시적 인자 바인딩)
btnBlack := CustomButton(MainGui, "...", "블랙아웃 끄기", OnBlackClick.Bind(index))
```

---

## 3. 윈도우 세션 잠금(Lock Screen) 대응 및 먹통 방지

### [이슈]
블랙아웃 GUI(투명 검은색 덮개 창)를 활성화한 상태에서 자리를 비워 윈도우가 잠금 화면 상태(`Win+L` 또는 화면 보호기/대기 모드)가 된 경우, 시스템은 기본 데스크톱('Default')에서 로그인 세션 데스크톱('Winlogon')으로 화면을 전환합니다.
이후 잠금을 해제하고 복귀하면 `AlwaysOnTop` 속성 때문에 검은 화면은 보이지만, 기존 창의 입력 포커스를 잃거나 이벤트 전달이 차단되어 **Esc 키나 마우스 클릭을 통한 블랙아웃 해제가 먹통이 되는 현상**이 발생합니다. (재부팅이나 강제 종료 필요)

### [해결책]
윈도우의 세션 상태 변경 메시지를 구독하여, 잠금 화면 진입 시점 혹은 잠금 해제 시점에 백그라운드에서 모든 블랙아웃 GUI 창을 자동으로 강제 파괴(해제)하도록 구현합니다.
1. **세션 변경 알림 등록**:
   ```autohotkey
   ; 0 = NOTIFY_FOR_THIS_SESSION (현재 세션 알림만 수신)
   DllCall("wtsapi32\WTSRegisterSessionNotification", "ptr", MainGui.Hwnd, "uint", 0)
   OnMessage(0x02B1, WM_WTSSESSION_CHANGE) ; 0x02B1 = WM_WTSSESSION_CHANGE
   ```
2. **세션 변경 이벤트 처리**:
   ```autohotkey
   WM_WTSSESSION_CHANGE(wParam, lParam, msg, hwnd) {
       global monitorState
       ; wParam: 0x7 = WTS_SESSION_LOCK (잠금), 0x8 = WTS_SESSION_UNLOCK (잠금 해제)
       if (wParam == 0x7 || wParam == 0x8) {
           Loop MonitorGetCount() {
               if monitorState.Has(A_Index) && monitorState[A_Index] == "BLACKOUT_OFF" {
                   EndBlackout(A_Index) ; 강제로 블랙아웃 상태 해제
               }
           }
       }
   }
   ```
3. **가비지 컬렉션 (해제)**:
   GUI가 다시 그려지거나(`RebuildGui`) 종료될 때(`ExitApp`) 등록한 알림을 명시적으로 해제해 줍니다.
   ```autohotkey
   DllCall("wtsapi32\WTSUnRegisterSessionNotification", "ptr", MainGui.Hwnd)
   ```

---

## 4. 다중 칼럼 그리드 레이아웃 설계 기법

### [이슈]
AHK GUI 설계 시 상대 좌표(`x+15`, `y+10`)는 코드 가독성을 해치고, 컨트롤의 선언 순서가 바뀔 때 전체 레이아웃이 붕괴하는 문제가 있습니다. 특히 상단의 모니터 카드 영역과 하단의 NVIDIA Surround 제어 카드 영역의 버튼 열을 세로로 완벽히 정렬해야 할 때 위치가 어긋나기 쉽습니다.

### [해결책]
**기준 단면 좌표(`xs`, `ys`) 오프셋 기법**을 기반으로 절대적인 칼럼 좌표 설계를 사용하는 것이 가장 안전합니다.
1. **각 카드의 영역 분할**:
   ```autohotkey
   ; 2개 이상일 때: 카드 1은 x15 y15, 카드 2는 x210 ys (15 + 175 + 20)
   cardX := (A_Index == 1) ? 15 : 210
   cardOpt := "x" cardX " y15 Section"
   ```
2. **칼럼 좌표 정밀 매핑**:
   - 1열 시작: `xs+12` (카드 1 및 아래 카드의 1열 버튼 시작점 통일) -> 절대 X: `27px`
   - 2열 시작: `xs+207` (카드 2 및 아래 카드의 2열 버튼 시작점 통일) -> 절대 X: `222px`
   - 버튼 너비: `150px`로 대칭 정렬
   - 이 방식으로 상단 개별 카드와 하단 Surround 조절 버튼이 단 1픽셀의 오차도 없이 일치하는 깔끔한 수직 그리드가 연출됩니다.

---

## 5. DDC/CI (H/W) vs 블랙아웃 (S/W) 모니터 전원 제어

물리적인 하드웨어 대기모드 진입 방식과 소프트웨어 오버레이 방식을 상황에 따라 조합하여 제어의 신뢰도를 극대화했습니다.

1. **DDC/CI를 통한 물리적 제어 (VCP 0xD6)**:
   `dxva2\GetPhysicalMonitorsFromHMONITOR`를 이용해 물리 모니터 핸들을 획득하고, VCP 코드 `0xD6`를 전송하여 모니터를 실제 대기모드(Sleep) 상태로 전환합니다.
   - `SetVCPFeature(hPhysMon, 0xD6, 4)`: 모니터 물리적 꺼짐 (Power Off/Sleep)
   - `SetVCPFeature(hPhysMon, 0xD6, 1)`: 모니터 물리적 켜짐 (Power On)
   - **장점**: 실제 백라이트가 꺼지며 전력이 차단됩니다.
   - **단점**: 모니터 펌웨어나 포트(DP/HDMI), 그래픽 카드 드라이버 호환성에 따라 동작하지 않을 수 있습니다.
2. **블랙아웃(S/W) 오버레이 제어**:
   대상 모니터의 전체 해상도 영역을 덮는 테두리 없는 검은색 GUI 창을 띄워 백라이트를 가리는 방식입니다.
   - **특징**: `AlwaysOnTop` 옵션을 주어 활성화하고, 마우스 클릭이나 `Escape` 이벤트를 감지하여 클릭 시 자동으로 창을 파괴하고 깨어나게 설계했습니다.
   - **사용성 개선**: 검은 화면 위로 흰색 마우스 커서가 둥둥 떠다니는 시각적 이질감을 없애기 위해, 마우스 이동/감지 이벤트 핸들러(`WM_SETCURSOR`)를 통해 투명 빈 커서(`CreateBlankCursor`)를 생성해 할당함으로써 마우스를 숨겼습니다.
