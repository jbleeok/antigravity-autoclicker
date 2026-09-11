# 🎙️ WhisperSTT (Push-to-Talk 입코딩 툴)

AutoHotkey v2와 로컬 Docker Whisper 서버를 활용한 **Push-to-Talk 방식의 음성 인식(STT) 도구**입니다.
`F9` 키를 누르고 말한 뒤 손을 떼면, 음성을 텍스트로 변환하여 활성화된 창에 자동으로 붙여넣어 줍니다. 주로 AI 에디터(Antigravity, Cursor 등)에서의 **입코딩(Voice Coding)**을 위해 사용됩니다.

---

## ⚙️ 시스템 요구사항 (Prerequisites)

이 스크립트를 완벽하게 구동하기 위해 아래 3가지가 미리 준비되어야 합니다.

1. **[AutoHotkey v2](https://www.autohotkey.com/)**
   - 스크립트 실행을 위해 반드시 v2 버전이 필요합니다.
2. **NVIDIA 그래픽카드 및 최신 드라이버**
   - 로컬에서 AI 모델을 빠르게 돌리기 위해 GPU가 필요합니다.
   - **중요:** WhisperLive 컨테이너는 CUDA 13.0을 기반으로 하므로, **NVIDIA 그래픽 드라이버 버전이 580.xx 이상(최신)**이어야 정상적으로 GPU 가속이 작동합니다. 드라이버가 너무 구형일 경우 강제로 CPU 모드로 작동하여 타임아웃이 발생할 수 있습니다.
3. **Docker Desktop (WSL2 기반)**
   - Whisper 서버를 백그라운드에서 띄워두기 위해 Docker가 필요합니다.

---

## 🚀 설치 및 실행 방법

### 1. Whisper 서버 (Docker) 기동
터미널(또는 명령 프롬프트)을 열고 아래 명령어를 통해 Whisper REST API 서버를 백그라운드에 띄웁니다.

```bash
docker run -d --name whisperlive --gpus all -p 8000:8000 -p 9090:9090 ghcr.io/collabora/whisperlive-gpu:latest
```
* 서버가 켜진 상태로 대기하며, 이후 컴퓨터를 껐다 켜더라도 Docker Desktop이 실행되면 자동으로 백그라운드에서 돌아가게 됩니다 (`--restart unless-stopped` 옵션 추가 권장).*

### 2. WhisperSTT 앱 실행
1. 폴더 내의 `WhisperSTT.ahk` 파일을 더블 클릭하여 실행합니다.
2. 작업 표시줄 우측 하단 트레이 아이콘에 **마이크 모양(🎤) 아이콘**이 생기며 앱이 실행됩니다.

### 3. 마이크 설정 (중요)
1. 앱 화면의 **`INPUT DEVICE`** 드롭다운 메뉴를 클릭합니다.
2. 현재 사용 중인 **실제 마이크** (예: `Microphone (USB Audio Device)`)를 선택합니다.
   - *주의:* Voicemeeter를 사용하시는 경우, B1/B2 채널로 라우팅을 켜둔 상태에서 `VoiceMeeter Output`을 선택하셔야 합니다. (잘 모르시겠다면 진짜 마이크 이름을 직접 고르시는 게 가장 안전합니다.)

---

## 🎤 사용 방법

1. 텍스트를 입력할 창(채팅창, 에디터 등)을 클릭해 커서를 둡니다.
2. 키보드의 **`F9`** 키를 **꾹 누른 상태**로 말을 합니다.
3. 말이 끝나면 **`F9`** 키에서 손을 뗍니다.
4. 약 1~2초 뒤 인식된 텍스트가 자동으로 **붙여넣기(Ctrl+V)** 됩니다.

---

## 🛠️ 설정 (Settings)
메인 GUI 우측 상단의 톱니바퀴(⚙) 버튼을 누르면 설정 창이 열립니다.

- **모델 (Model):** 기본값은 `medium` 입니다. (속도와 정확도의 밸런스가 가장 좋습니다.) 만약 GPU VRAM이 부족하거나 더 빠른 속도를 원하시면 `small`로, 더 완벽한 정확도를 원하시면 `large-v3`로 변경하세요.
- **언어 (Language):** 기본값은 자동 감지(빈칸)입니다. 한국어 전용으로만 쓰실 분들은 `ko`라고 입력하시면 인식 정확도와 속도가 조금 더 올라갑니다.
- **자동 붙여넣기:** 변환 완료 후 자동으로 `Ctrl+V`를 쳐주는 기능입니다.
- **자동 시작:** 윈도우가 켜질 때 이 프로그램도 같이 켜지게 합니다.

---

## 🚨 자주 묻는 질문 (Troubleshooting)

**Q. 말도 안 했는데 계속 "Thank you" 나 "Thanks for watching" 이라고 뜹니다.**
> Whisper AI 모델의 대표적인 고질병입니다. 마이크 입력이 '완벽한 무음'이거나 아무 소리도 서버로 전달되지 않았을 때 발생하는 환각(Hallucination) 증상입니다.
> **해결책:** 
> 1. 윈도우 설정 > 개인정보 > 마이크에서 앱 접근 권한이 켜져 있는지 확인하세요.
> 2. `INPUT DEVICE` 목록에서 마이크가 제대로 선택되어 있는지 다시 확인하세요.

**Q. 서버 오류 (HTTP 500) 또는 libcublas.so.12 에러가 납니다.**
> Docker 컨테이너 내의 PyTorch(CUDA 13)와 faster-whisper(CUDA 12) 라이브러리 간의 버전 충돌 문제입니다. 최신 그래픽 드라이버 업데이트 후, 컨테이너 내부에 `nvidia-cublas-cu12` 패키지를 설치해야 합니다.

**Q. 로그에 "Loading REST model on CPU" 라고 뜨면서 엄청 느립니다.**
> PC의 NVIDIA 드라이버 버전이 너무 낮아서 컨테이너가 GPU를 인식하지 못한 경우입니다. NVIDIA 공식 홈페이지나 GeForce Experience에서 최신 그래픽 드라이버로 업데이트하신 후, 컴퓨터(또는 WSL)를 재부팅하세요.
