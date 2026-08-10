# Antigravity Remote Auto Commit (J06)

AutoHotkey v2를 기반으로 작성된 **Antigravity IDE** 전용 리모컨(J06 링) 자동 클릭 스크립트입니다.  
**FindText** 라이브러리를 활용해 이미지 파일 없이 텍스트 문자열 기반으로 버튼을 인식하고, 백그라운드에서도 안정적으로 클릭합니다.

## 🚀 주요 기능

- **자동 버튼 인식 및 클릭 (FindText)**: 화면을 스캔하여 `antigravity_j06.ini`에 등록된 FindText 문자열과 일치하는 버튼 영역을 찾아 자동으로 클릭합니다. 이미지 파일이 필요 없으며 기존 `ImageSearch`보다 인식률이 훨씬 높습니다.
- **백그라운드 검색 지원**: 활성화된 창과 무관하게 절대 모니터 좌표를 기반으로 검색하여, 창이 포커스를 잃어도 동작합니다. (가상 클릭 `ControlClick` 지원)
- **J06 링 리모컨 단축키 리매핑**:
  - `Volume_Mute` (우측 아래 버튼): 즉시 화면을 스캔하고 확인 버튼 클릭.
  - `Volume_Down` (좌측 아래 버튼): 기본 `Enter` 키 역할 수행.
- **GUI 컨트롤 패널**: 직관적인 UI(Catppuccin Mocha 테마 적용)로 Auto 기능을 쉽게 켜고 끌 수 있습니다.
- **Key Test 모드**: 리모컨이나 마우스의 키보드/마우스 입력 신호(VK, SC 코드)를 확인할 수 있는 테스트 창을 제공합니다.

## 📂 파일 구성

- `antigravity_j06.ahk`: 메인 실행 스크립트 (AutoHotkey v2 필요)
- `antigravity_j06.ini`: 환경설정 및 FindText 버튼 인식 문자열 (`[FindTextTargets]` 섹션)
- `Lib/FindText.ahk`: FeiYue의 FindText v10.2 라이브러리 (AHK v2용). 직접 실행하면 캡처 GUI가 실행됩니다.

## ⚙️ 설정 및 사용법

1. **[AutoHotkey v2](https://www.autohotkey.com/)** 가 설치되어 있어야 합니다.
2. `Lib/FindText.ahk`를 더블클릭하여 **FindText 캡처 GUI**를 실행합니다.
3. 캡처 GUI에서 인식할 버튼 영역을 드래그하여 선택하면, 텍스트 문자열 코드가 생성됩니다.
4. 생성된 코드 중 `|<이름>*숫자$...` 형태의 문자열을 복사합니다.
5. `antigravity_j06.ini`의 `[FindTextTargets]` 섹션에 붙여넣습니다:
   ```ini
   [FindTextTargets]
   Target1=|<Submit>*100$45.xxxxx...
   Target2=|<Accept>*100$32.xxxxx...
   ```
6. `antigravity_j06.ahk` 스크립트를 실행(또는 재시작)합니다.
7. **Auto Commit** GUI 창에서 `Auto` 체크박스를 켜면(🟢 ON), 1초마다 화면에 타겟 버튼이 있는지 스캔하고 클릭합니다.

> **참고:** 타겟 앱이 최신 WinUI 3 프레임워크인 경우, 가상 배경 클릭(`ControlClick`)을 무시할 수도 있습니다. 이 경우 소스를 수정하여 마우스 물리 클릭(`Click`)으로 우회할 수 있습니다.

> **FindText 캡처 팁:** 버튼 텍스트나 아이콘처럼 배경색과 대비가 뚜렷한 픽셀이 있는 영역을 작게 캡처할수록 인식률이 높아집니다. 너무 넓게 캡처하면 오히려 오탐이 발생할 수 있습니다.

