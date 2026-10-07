class_name Label3DSharp
extends RefCounted
## Чёткий текст Label3D в очках: «лесенка» букв — это растр глифов, который при взгляде на метр-два и размере в мире шириной в ладонь
## занимает считанные пиксели. Лечим без смены вида: растр глифов крупнее (font_size ×SCALE), размер в мире тот же (pixel_size ÷SCALE),
## обводка пропорционально, фильтр — с мипами и анизотропией (текст под углом не мылится и не дрожит).
## Зовётся после того, как у метки заданы font_size, pixel_size и outline_size, — один раз на метку.
## MSDF (чёткие края при любом увеличении) у Label3D берётся из шрифта: нужен FontFile с multichannel_signed_distance_field = true
## в его .import (Label3D сейчас рисует шрифтом темы по умолчанию — свой шрифт ему не назначен, поэтому здесь не включаем).

## Во сколько раз крупнее растр глифов.
const SCALE := 2.0
## Предел растра: на больших кеш глифов раздувается (метка «!» у Стража 96 → 192 всё ещё в пределе).
const MAX_FONT_SIZE := 256
## Наименьшая обводка у метки с обводкой, px растра: тоньше — края ломаются.
const MIN_OUTLINE := 2


## Во сколько раз реально увеличен растр для метки данного размера (SCALE, но не выше MAX_FONT_SIZE) — чистая часть, без сцены.
static func factor(font_size: int) -> float:
	if font_size <= 0:
		return 1.0
	return clampf(float(MAX_FONT_SIZE) / float(font_size), 1.0, SCALE)


static func apply(l: Label3D) -> void:
	var f := factor(l.font_size)
	var old := l.font_size
	l.font_size = roundi(old * f)
	l.pixel_size = l.pixel_size * old / l.font_size   # размер глифа в мире (font_size × pixel_size) не меняется
	if l.outline_size > 0:
		l.outline_size = maxi(MIN_OUTLINE, roundi(l.outline_size * f))
	l.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
