# Antigravity J06 Auto Commit Controller (v2.0)

## 1. 개요 (Overview)
`antigravity_j06.ahk` 스크립트는 **J06 블루투스 링 리모컨**을 활용하여 Antigravity IDE 환경에서 코딩 작업 중 발생하는 승인(Submit, Accept 등) 절차를 원격으로, 혹은 완전히 자동으로 처리하기 위해 개발된 AutoHotkey v2 스크립트입니다.

## 2. 주요 기능 (Features)
- **수동 원격 제어 (J06 리모컨 매핑)**
  - `Volume_Down` (좌측 하단 버튼) ➔ `Enter` 키로 동작 (채팅 전송 등에 활용)
  - `Volume_Mute` (우측 하단 버튼) ➔ 현재 화면에서 Submit, Accept 등의 승인 버튼을 찾아 즉시 클릭
- **자동 승인 모드 (Auto Mode)**
  - 미니멀한 GUI에서 `Auto` 체크박스를 활성화하면 1초(1000ms) 간격으로 타겟 이미지를 지속적으로 스캔
  - 권한 요청이나 코드 승인 팝업이 뜨는 즉시 사용자의 개입 없이 백그라운드 클릭으로 자동 승인
- **설정 자동 저장**
  - GUI 창의 마지막 위치 및 Auto 체크박스 상태가 `antigravity_j06.ini`에 저장되어 재실행 시 그대로 복원됨

## 3. 디렉토리 구조 및 작동 원리
- **`antigravity_j06.ahk`**: 메인 로직 스크립트
- **`antigravity_j06.ini`**: 환경설정 파일 (자동 생성)
- **`img_targets/`**: 
  - 스크립트와 같은 경로에 생성되는 폴더. 
  - 사용자가 클릭을 원하는 버튼을 캡처한 이미지(`.png`, `.bmp`)들을 넣어두면 스크립트가 파일명과 무관하게 폴더 내의 모든 이미지를 순회하며 매칭합니다.

## 4. 디버깅 및 기술 전환 히스토리 (Lessons Learned)

### 4.1 J06 리모컨의 입력 신호 특성 분석
- **초기 문제**: 전/후/좌/우 버튼이 키보드 훅(InputHook)에 잡히지 않음.
- **원인 파악 (KeyHistory 분석)**: 해당 리모컨이 '비디오/틱톡 모드'로 작동 중이었으며, 키보드 방향키가 아닌 **마우스 좌클릭(LButton) + 드래그**로 스와이프 제스처를 보내고 있었음.
- **해결 방안**: 방향키 제어를 포기하고, 확실한 Media Key 신호를 보내는 하단 두 버튼(`Volume_Down`, `Volume_Mute`)만을 만능키로 활용하는 실용적 노선으로 변경.

### 4.2 UIA (UI Automation) ➔ ImageSearch 방식 전환
- **초기 접근 (UIA-v2)**: 화면 해상도나 테마에 구애받지 않도록 마이크로소프트의 UIA를 사용해 DOM 트리에서 'Submit'이라는 `Name`을 가진 요소를 직접 찾아 `Invoke()` 하려 함.
- **한계점 직면**: Antigravity IDE(Electron/VS Code 기반) 내부 웹 렌더러 특성상, 권한 허용 팝업 안의 버튼이 표준 Button 컨트롤로 노출되지 않거나 DOM 깊숙이 숨어있어 UIA로 정확한 타겟팅 및 클릭이 불가능했음.
- **해결 방안 (ImageSearch)**: 사용자가 직접 `img_targets` 폴더에 타겟 이미지를 넣고, 스크립트가 이를 찾아 클릭하는 전통적이고 직관적인 **ImageSearch** 방식으로 아키텍처 전면 교체.

### 4.3 윈도우 타이틀 충돌 및 좌표계 혼선(Coordinate Bug) 수정
- **타이틀 충돌**: GUI 창 이름을 `"Antigravity Commit"`으로 변경하자, 타겟 창을 검색하는 `WinExist("Antigravity")` 로직이 IDE 대신 자기 자신의 GUI를 타겟팅하는 버그 발생. ➔ 타겟 검색 문자열을 `"Antigravity IDE"`로 명시하여 해결.
- **좌표계 혼선**: ImageSearch는 Screen(화면 전체) 좌표계를 쓰고, ControlClick은 Client(창 내부) 좌표계를 쓰면서, 엉뚱한 위치(3번 옵션 텍스트박스 테두리 등)를 클릭하는 현상 발생.
- **좌표계 통일**: 
  ```autohotkey
  CoordMode "Pixel", "Client"
  WinGetClientPos(,, &cw, &ch, "Antigravity IDE")
  ```
  좌표계를 대상 창의 내부(Client) 기준으로 완벽히 통일하고, 이미지 매칭 오차 허용치를 `*50`으로 조율하여 한 치의 오차 없는 정확한 백그라운드 클릭을 구현함.
