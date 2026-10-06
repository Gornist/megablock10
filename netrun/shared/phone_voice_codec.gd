class_name PhoneVoiceCodec
extends RefCounted
## Бинарный кадр голоса по WebSocket связи очков с телефоном (docs/netrun-phone-link.md, «Голос»):
## [1 байт тип][4 байта seq uint32 LE][PCM int16 LE моно]. Тип 1 — микрофон очков → телефон, тип 2 — звук собеседника телефон → очки.
## Чистая функция над байтами: ни узлов, ни сокета (сокет — RemotePhoneLink).

const TYPE_MIC := 1
const TYPE_PEER := 2
const HEADER_BYTES := 5
## Полезная часть (PCM) — чётное число байт, не больше этого.
const MAX_PAYLOAD := 4096
const SEQ_MODULO := 4294967296   # 2^32


## Собрать кадр. Пустой PCM, нечётная длина, длина больше MAX_PAYLOAD или неизвестный тип — пустой массив (нечего слать).
static func encode(type: int, seq: int, pcm: PackedByteArray) -> PackedByteArray:
	if not _known_type(type) or not _payload_ok(pcm.size()):
		return PackedByteArray()
	var out := PackedByteArray()
	out.resize(HEADER_BYTES)
	out[0] = type
	out.encode_u32(1, posmod(seq, SEQ_MODULO))
	out.append_array(pcm)
	return out


## Разобрать кадр: {ok, type, seq, pcm}. ok=false — короче 6 байт, нечётная или слишком длинная полезная часть, неизвестный тип.
static func decode(bytes: PackedByteArray) -> Dictionary:
	var bad := {"ok": false, "type": 0, "seq": 0, "pcm": PackedByteArray()}
	if bytes.size() <= HEADER_BYTES:
		return bad
	var type := int(bytes[0])
	if not _known_type(type) or not _payload_ok(bytes.size() - HEADER_BYTES):
		return bad
	return {"ok": true, "type": type, "seq": int(bytes.decode_u32(1)), "pcm": bytes.slice(HEADER_BYTES)}


## Отсчётов в куске длиной `ms` миллисекунд при частоте `rate` (44100, 20 мс → 882).
static func samples_per_chunk(rate: int, ms: int = 20) -> int:
	return maxi(rate, 0) * maxi(ms, 0) / 1000


static func _known_type(type: int) -> bool:
	return type == TYPE_MIC or type == TYPE_PEER


static func _payload_ok(size: int) -> bool:
	return size > 0 and size % 2 == 0 and size <= MAX_PAYLOAD
