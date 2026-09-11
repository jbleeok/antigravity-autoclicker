#Requires AutoHotkey v2.0

; ============================================================
;  AudioRecorder.ahk — winmm.dll waveIn API 마이크 녹음 모듈
;  16kHz, Mono, 16-bit PCM → WAV 파일 저장
; ============================================================

GetAudioInputDevices() {
    devices := []
    count := DllCall("winmm\waveInGetNumDevs", "UInt")
    caps := Buffer(80, 0)

    Loop count {
        devId := A_Index - 1
        if (DllCall("winmm\waveInGetDevCapsW", "UInt", devId, "Ptr", caps, "UInt", caps.Size, "UInt") == 0) {
            devName := StrGet(caps.Ptr + 8, 32, "UTF-16")
            devices.Push({id: devId, name: devName})
        }
    }
    return devices
}

class WaveAudioRecorder {
    static MM_WIM_DATA  := 0x3C0
    static CALLBACK_WINDOW := 0x00010000

    __New(sampleRate := 16000, channels := 1, bitsPerSample := 16) {
        this.sampleRate := sampleRate
        this.channels := channels
        this.bitsPerSample := bitsPerSample
        this.hWaveIn := 0
        this.isRecording := false
        this.recordedChunks := []
        this.totalBytesRecorded := 0

        ; 0.5초 × 3개 순환 버퍼
        this.bufferSize := Integer(sampleRate * channels * (bitsPerSample // 8) * 0.5)
        this.bufferCount := 3
        this.buffers := []
        this.headers := []

        ; WAVEHDR 크기: x64=48, x86=32
        this.hdrSize := A_PtrSize == 8 ? 48 : 32

        ; 메시지 핸들러 바인딩
        this._boundOnWaveData := ObjBindMethod(this, "OnWaveData")
        OnMessage(WaveAudioRecorder.MM_WIM_DATA, this._boundOnWaveData)
    }

    __Delete() {
        if this.isRecording
            this.Stop()
        OnMessage(WaveAudioRecorder.MM_WIM_DATA, this._boundOnWaveData, 0)
    }

    Start(deviceId := -1) {
        if this.isRecording
            return false

        this.recordedChunks := []
        this.totalBytesRecorded := 0
        this.buffers := []
        this.headers := []

        ; WAVEFORMATEX 구조체 (18 bytes)
        wfx := Buffer(18, 0)
        byteRate := this.sampleRate * this.channels * (this.bitsPerSample // 8)
        blockAlign := this.channels * (this.bitsPerSample // 8)

        NumPut("UShort", 1, wfx, 0)                    ; WAVE_FORMAT_PCM
        NumPut("UShort", this.channels, wfx, 2)
        NumPut("UInt", this.sampleRate, wfx, 4)
        NumPut("UInt", byteRate, wfx, 8)
        NumPut("UShort", blockAlign, wfx, 12)
        NumPut("UShort", this.bitsPerSample, wfx, 14)
        NumPut("UShort", 0, wfx, 16)

        ; waveInOpen
        hWaveInBuf := Buffer(A_PtrSize, 0)
        res := DllCall("winmm\waveInOpen",
            "Ptr", hWaveInBuf,
            "UInt", deviceId,
            "Ptr", wfx,
            "Ptr", A_ScriptHwnd,
            "Ptr", 0,
            "UInt", WaveAudioRecorder.CALLBACK_WINDOW,
            "UInt")

        if (res != 0)
            throw Error("waveInOpen 실패 (에러 코드: " . res . ")")

        this.hWaveIn := NumGet(hWaveInBuf, 0, "Ptr")
        this.isRecording := true

        ; 순환 버퍼 준비
        Loop this.bufferCount {
            rawBuf := Buffer(this.bufferSize, 0)
            hdrBuf := Buffer(this.hdrSize, 0)

            NumPut("Ptr", rawBuf.Ptr, hdrBuf, 0)
            NumPut("UInt", this.bufferSize, hdrBuf, A_PtrSize == 8 ? 8 : 4)

            DllCall("winmm\waveInPrepareHeader", "Ptr", this.hWaveIn, "Ptr", hdrBuf, "UInt", this.hdrSize, "UInt")
            DllCall("winmm\waveInAddBuffer", "Ptr", this.hWaveIn, "Ptr", hdrBuf, "UInt", this.hdrSize, "UInt")

            this.buffers.Push(rawBuf)
            this.headers.Push(hdrBuf)
        }

        ; 녹음 시작
        DllCall("winmm\waveInStart", "Ptr", this.hWaveIn, "UInt")
        return true
    }

    OnWaveData(wParam, lParam, msg, hwnd) {
        if (!this.hWaveIn || wParam != this.hWaveIn)
            return

        ; dwBytesRecorded 오프셋: x64=12, x86=8
        bytesRecorded := NumGet(lParam, A_PtrSize == 8 ? 12 : 8, "UInt")
        pData := NumGet(lParam, 0, "Ptr")

        if (bytesRecorded > 0) {
            chunk := Buffer(bytesRecorded)
            DllCall("RtlMoveMemory", "Ptr", chunk.Ptr, "Ptr", pData, "UPtr", bytesRecorded)
            this.recordedChunks.Push(chunk)
            this.totalBytesRecorded += bytesRecorded
        }

        ; 녹음 중이면 버퍼 재큐
        if (this.isRecording) {
            DllCall("winmm\waveInAddBuffer", "Ptr", this.hWaveIn, "Ptr", lParam, "UInt", this.hdrSize, "UInt")
        }
    }

    Stop(saveWavPath := "") {
        if (!this.isRecording)
            return ""

        this.isRecording := false

        DllCall("winmm\waveInReset", "Ptr", this.hWaveIn, "UInt")
        DllCall("winmm\waveInStop", "Ptr", this.hWaveIn, "UInt")

        for hdr in this.headers {
            DllCall("winmm\waveInUnprepareHeader", "Ptr", this.hWaveIn, "Ptr", hdr, "UInt", this.hdrSize, "UInt")
        }

        DllCall("winmm\waveInClose", "Ptr", this.hWaveIn, "UInt")
        this.hWaveIn := 0

        if (saveWavPath != "") {
            this.SaveWavFile(saveWavPath)
            return saveWavPath
        }
        return ""
    }

    SaveWavFile(filePath) {
        file := FileOpen(filePath, "w")

        ; 44바이트 RIFF/WAV 헤더
        header := Buffer(44, 0)
        byteRate := this.sampleRate * this.channels * (this.bitsPerSample // 8)
        blockAlign := this.channels * (this.bitsPerSample // 8)
        riffChunkSize := 36 + this.totalBytesRecorded

        NumPut("UInt", 0x46464952, header, 0)           ; 'RIFF'
        NumPut("UInt", riffChunkSize, header, 4)
        NumPut("UInt", 0x45564157, header, 8)           ; 'WAVE'
        NumPut("UInt", 0x20746D66, header, 12)          ; 'fmt '
        NumPut("UInt", 16, header, 16)                   ; SubChunk1Size
        NumPut("UShort", 1, header, 20)                  ; PCM
        NumPut("UShort", this.channels, header, 22)
        NumPut("UInt", this.sampleRate, header, 24)
        NumPut("UInt", byteRate, header, 28)
        NumPut("UShort", blockAlign, header, 32)
        NumPut("UShort", this.bitsPerSample, header, 34)
        NumPut("UInt", 0x61746164, header, 36)          ; 'data'
        NumPut("UInt", this.totalBytesRecorded, header, 40)

        file.RawWrite(header)
        for chunk in this.recordedChunks {
            file.RawWrite(chunk)
        }
        file.Close()
    }
}
