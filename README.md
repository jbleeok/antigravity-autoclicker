# Antigravity Remote Auto Commit (J06)

AutoHotkey v2를 기반으로 작성된 **Antigravity IDE** 전용 리모컨(J06 링) 자동 클릭 스크립트입니다. 화면 캡처 이미지를 활용해 백그라운드에서도 버튼을 인식하고 클릭할 수 있습니다.

## 🚀 주요 기능

- **자동 버튼 인식 및 클릭 (ImageSearch)**: 화면을 스캔하여 미리 저장된 버튼 이미지(`Submit.png`, `Accept.png` 등)를 찾아 자동으로 클릭합니다.
- **백그라운드 검색 지원**: 활성화된 창과 무관하게 절대 모니터 좌표를 기반으로 검색하여, 창이 포커스를 잃어도 동작합니다. (가상 클릭 `ControlClick` 지원)
- **J06 링 리모컨 단축키 리매핑**:
  - `Volume_Mute` (우측 아래 버튼): 즉시 화면을 스캔하고 확인 버튼 클릭.
  - `Volume_Down` (좌측 아래 버튼): 기본 `Enter` 키 역할 수행.
- **GUI 컨트롤 패널**: 직관적인 UI(Catppuccin Mocha 테마 적용)로 Auto 기능을 쉽게 켜고 끌 수 있습니다.
- **Key Test 모드**: 리모컨이나 마우스의 키보드/마우스 입력 신호(VK, SC 코드)를 확인할 수 있는 테스트 창을 제공합니다.

## 📂 파일 구성

- `antigravity_j06.ahk`: 메인 실행 스크립트 (AutoHotkey v2 필요)
- `antigravity_j06.ini`: 환경설정 및 타겟 이미지 매칭 정보 (최초 실행 시 자동 생성)
- `img_targets/`: 클릭 대상이 될 버튼의 캡처 이미지(`*.png`, `*.bmp`)가 들어가는 폴더입니다.

## ⚙️ 설정 및 사용법

1. **[AutoHotkey v2](https://www.autohotkey.com/)** 가 설치되어 있어야 합니다.
2. `img_targets` 폴더 내에 인식하고자 하는 버튼의 캡처본(예: `Submit.png`)을 넣습니다. (가능한 버튼 안쪽의 내용만 작게 캡처하면 인식률이 높아집니다)
3. `antigravity_j06.ahk` 스크립트를 실행합니다.
4. 나타나는 **Auto Commit** GUI 창에서 `Auto` 체크박스를 켜면(🟢 ON), 1초마다 화면에 타겟 버튼이 있는지 스캔하고 클릭합니다.

> **참고:** 타겟 앱이 최신 WinUI 3 프레임워크인 경우, 가상 배경 클릭(`ControlClick`)을 무시할 수도 있습니다. 이 경우 소스를 수정하여 마우스 물리 클릭(`Click`)으로 우회할 수 있습니다.
