// Двусторонний вариант «облака без основы» (ручка AssetMaterials `cloud_two_sided`): те же частицы, но cull_disabled — сквозь дыры передней грани видны задние грани объёма, объект читается целиком
// (владелец 08.10 на очках: «как будто рендерятся не все грани — очень заметно из-за прозрачности»). Цена — вдвое больше a2c-фрагментов у объекта; тело — cloud_dark.gdshaderinc.
shader_type spatial;
render_mode unshaded, cull_disabled, alpha_to_coverage_and_one, fog_disabled;

#include "cloud_dark.gdshaderinc"
