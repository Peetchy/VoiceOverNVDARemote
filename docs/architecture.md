# VO NVDA Remote MVP

## ขอบเขต MVP

- macOS utility app สำหรับเชื่อมต่อผ่าน raw TCP over TLS ไปยัง `nvdaremote` relay
- ใช้ NVDA Remote protocol v2 โดยตรงในโหมด `control another machine`
- ไม่รองรับการเปิดเครื่อง mac ให้ถูกควบคุมจากภายนอก
- รองรับ presence, keyboard forwarding, clipboard sync และ map ข้อความ speech เป็น VoiceOver announcement

## Architecture

- `RemoteProtocol`: shared protocol/data model และ serializer
- `WindowsCompanionContract`: contract ที่ฝั่ง Windows add-on ต้อง implement เพื่อ map จาก NVDA event ภายในออกมาเป็น protocol กลาง
- `MacRemoteCore`: transport abstraction, state machine, clipboard/announcement bridge
- `VONVDARemote`: SwiftUI app shell

## Module แยกฝั่ง mac / windows

- ฝั่ง mac ใช้ `MacRemoteCore` + `VONVDARemote`
- ฝั่ง windows ใช้ `WindowsCompanionContract` เป็น interface boundary สำหรับ add-on ในอนาคต

## Protocol Model

- `protocol_version`
- `join`
- `channel_joined`
- `client_joined`
- `client_left`
- `key`
- `speak`
- `cancel`
- `pause_speech`
- `tone`
- `wave`
- `set_clipboard_text`
- `ping`
- `error`

## Event Flow

1. mac app เปิด TLS socket ไปยัง relay
2. เมื่อ socket connected จะส่ง `protocol_version`
3. app ส่ง `join` พร้อม channel key และ `connection_type=master`
4. relay/companion ตอบ `channel_joined`
5. ถ้าฝั่ง Windows ส่ง `speak` จะถูกสกัดเฉพาะ text แล้ว post ผ่าน `NSAccessibility` ให้ VoiceOver อ่าน
6. ถ้าฝั่ง mac อยู่ใน controlling mode จะส่ง `key`

## Data Structure

- `RemoteEnvelope` เป็น root message
- payload แยก typed struct ต่อ message ตาม NVDA Remote
- `RemoteSessionSnapshot` เป็น state สำหรับ UI

## Acceptance Criteria

- โปรเจกต์ build ได้ด้วย `swift build`
- protocol serializer/deserializer ผ่าน unit tests
- state machine เปลี่ยน phase ได้ถูกต้องตาม connect/join/announcement/disconnect flow
- clipboard sync อัปเดต local pasteboard abstraction ได้

## Risk และ Roadmap

- keyboard mapping ยังเป็น virtual key payload ระดับพื้นฐาน
- speech command ของ NVDA ที่ไม่ใช่ text ยังไม่ถูก map เป็น announcement เชิง semantics
- phase ถัดไปควรเพิ่ม braille rendering จริง, key capture แบบ global, และ certificate fingerprint trust management
